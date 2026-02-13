--------------------------------------------------------------------------------
-- ToolMelee.client.lua  –  client-side melee weapon handler
-- Mirrors the ToolGun.client.lua pattern: auto-detects any Tool whose name
-- starts with "Tool" and whose suffix matches a ToolMeleeSettings preset
-- (e.g. ToolBat, ToolSword).  On click it fires a RemoteEvent so the server
-- can validate and apply damage.
--------------------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local Debris             = game:GetService("Debris")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local camera    = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- read melee settings module
local MeleeCfgModule
if ReplicatedStorage:FindFirstChild("ToolMeleeSettings") then
    MeleeCfgModule = require(ReplicatedStorage:WaitForChild("ToolMeleeSettings"))
end

-- remote for swings (server creates this)
local swingEvent = ReplicatedStorage:WaitForChild("MeleeSwing")

-- remote for hit feedback (server → client: damage, isHeadshot, hitPart, hitPos)
local meleeHitEvent = ReplicatedStorage:WaitForChild("MeleeHit")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function isMeleeTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsMelee") then return true end
    local suffix = tostring(tool.Name):match("^Tool(.+)")
    if not suffix then return false end
    if MeleeCfgModule and MeleeCfgModule.presets then
        return MeleeCfgModule.presets[suffix:lower()] ~= nil
    end
    return false
end

local function getCfg(tool)
    local cfg = {}
    local suffix = tostring(tool.Name):match("^Tool(.+)")
    local key = suffix and suffix:lower()
    if key and MeleeCfgModule and MeleeCfgModule.presets and MeleeCfgModule.presets[key] then
        for k, v in pairs(MeleeCfgModule.presets[key]) do cfg[k] = v end
    end
    -- per-tool attribute overrides
        for _, a in ipairs({"damage","cd","knockback","hitboxSize","hitboxOffset","hitboxDelay","hitboxActive","showHitbox"}) do
        local val = tool:GetAttribute(a)
        if val ~= nil then cfg[a] = val end
    end
    return cfg
end

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------
local function playMeleeSound(soundKey)
    if not soundKey or soundKey == "" then return end
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local meleeFolder = soundsFolder:FindFirstChild("ToolMelee")
    if not meleeFolder then return end
    local template = meleeFolder:FindFirstChild(soundKey)
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = camera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

--------------------------------------------------------------------------------
-- Hit feedback GUI (floating damage number – same style as ranged)
--------------------------------------------------------------------------------
local function showDamagePopup(damage, isHeadshot, hitPart, hitPos)
    local parentPart, anchor
    if hitPart and typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
        parentPart = hitPart
    elseif hitPos and typeof(hitPos) == "Vector3" then
        anchor = Instance.new("Part")
        anchor.Name = "_MeleeAnchor"
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CFrame = CFrame.new(hitPos)
        anchor.Parent = workspace
        parentPart = anchor
    end
    if not parentPart then return end

    local gui = Instance.new("BillboardGui")
    gui.Name = "MeleeDmgPopup"
    gui.Size = UDim2.new(0, 100, 0, 40)
    gui.Adornee = parentPart
    gui.AlwaysOnTop = true
    gui.StudsOffset = Vector3.new(0, 2, 0)
    gui.Parent = parentPart

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(math.floor(damage))
    label.Font = Enum.Font.GothamBold
    label.TextSize = 24
    label.TextColor3 = isHeadshot and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.5
    label.Parent = gui

    local tween = TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
        StudsOffset = gui.StudsOffset + Vector3.new(0, 1.2, 0),
    })
    tween:Play()
    for i = 0, 1, 0.06 do
        label.TextTransparency = i
        task.wait(0.06)
    end
    tween:Cancel()
    gui:Destroy()
    if anchor and anchor.Parent then anchor:Destroy() end
end

--------------------------------------------------------------------------------
-- Debug: show hitbox disk locally for tuning (client-only part)
--------------------------------------------------------------------------------
local function showDebugHitbox(originCFrame, boxSize, offset, duration, color)
    if not originCFrame or not boxSize then return end
    duration = duration or 0.2
    color = color or Color3.fromRGB(255, 50, 50)

    local offset = offset or Vector3.new(0, 0, 0)
    local pos = originCFrame.Position
        + originCFrame.RightVector * offset.X
        + originCFrame.UpVector * offset.Y
        + originCFrame.LookVector * offset.Z
    local boxCFrame = CFrame.new(pos, pos + originCFrame.LookVector)
    local part = Instance.new("Part")
    part.Name = "_MeleeHitboxDebug"
    part.Anchored = true
    part.CanCollide = false
    part.Size = boxSize
    part.Transparency = 0.6
    part.Color = color
    part.Material = Enum.Material.Neon
    part.CFrame = boxCFrame
    part.Parent = workspace
    Debris:AddItem(part, duration)
end

--------------------------------------------------------------------------------
-- Swing animation — procedural CFrame tween on the right arm + tool
-- Works for both R6 (Right Arm) and R15 (RightHand / RightUpperArm).
-- If the tool contains an Animation named "Swing*" it uses that instead.
--------------------------------------------------------------------------------
-- Swing timing: raise → slash down → return to rest
local raiseTweenInfo  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local slashTweenInfo  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local returnTweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local function playSwingVisual(tool)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 1) try a custom Animation inside the tool first
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, a in ipairs(tool:GetDescendants()) do
            if a:IsA("Animation") and a.Name:lower():find("swing") then
                pcall(function()
                    local track = animator:LoadAnimation(a)
                    track.Priority = Enum.AnimationPriority.Action
                    track:Play()
                end)
                return
            end
        end
    end

    -- 2) procedural swing: raise arm up 90°, slash down 180°, return to rest
    -- R6: "Right Shoulder" Motor6D in Torso
    -- R15: "RightShoulder" Motor6D in RightUpperArm
    local motor = nil
    local torso = char:FindFirstChild("Torso")
    if torso then
        motor = torso:FindFirstChild("Right Shoulder")
    end
    if not motor then
        local rua = char:FindFirstChild("RightUpperArm")
        if rua then motor = rua:FindFirstChild("RightShoulder") end
    end
    if not motor or not motor:IsA("Motor6D") then return end

    local originalC1 = motor.C1
    -- phase 1: raise arm up 90° (negative rotation to lift)
    local raiseGoal = originalC1 * CFrame.Angles(math.rad(-90), 0, 0)
    -- phase 2: slash down 180° from raised position (rotate to +90° relative to default)
    local slashGoal = originalC1 * CFrame.Angles(math.rad(90), 0, 0)

    local raiseTween = TweenService:Create(motor, raiseTweenInfo, { C1 = raiseGoal })
    raiseTween:Play()
    raiseTween.Completed:Once(function()
        local slashTween = TweenService:Create(motor, slashTweenInfo, { C1 = slashGoal })
        slashTween:Play()
        slashTween.Completed:Once(function()
            local returnTween = TweenService:Create(motor, returnTweenInfo, { C1 = originalC1 })
            returnTween:Play()
        end)
    end)
end

--------------------------------------------------------------------------------
-- Per-tool setup
--------------------------------------------------------------------------------
local function attachMelee(tool)
    if not tool or not tool:IsA("Tool") then return end
    if not isMeleeTool(tool) then return end
    if tool:GetAttribute("_meleeConnected") then return end
    tool:SetAttribute("_meleeConnected", true)

    local cfg = getCfg(tool)
    local cooldown = cfg.cd or 0.6
    local lastSwing = 0
    local swingLock = false

    local mouse = player:GetMouse()
    local mouseConns = {}
    local holding = false

    local function doSwing()
        -- prevent reentry
        if swingLock then return end
        local now = tick()
        if now - lastSwing < cooldown then return end
        swingLock = true
        lastSwing = now

        -- (audio/animation now played server-side for authoritative playback)
        -- debug: optionally show hitbox visual after hitboxDelay
        local showGlobal = false
        local globalVal = ReplicatedStorage:FindFirstChild("ToolMeleeShowHitbox")
        if globalVal and globalVal:IsA("BoolValue") then showGlobal = globalVal.Value end
        local wantDebug = (cfg.showHitbox == true) or showGlobal
        if wantDebug then
            local hd = cfg.hitboxDelay or 0.1
            local ha = cfg.hitboxActive or 0.2
            local color = cfg.hitboxColor or Color3.fromRGB(255, 50, 50)
            spawn(function()
                task.wait(hd)
                local char = player.Character
                local originCFrame = nil
                if char and char.PrimaryPart then originCFrame = char.PrimaryPart.CFrame end
                if not originCFrame and char then
                    originCFrame = (char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.CFrame) or CFrame.new()
                end
                if originCFrame then
                        local boxSize = cfg.hitboxSize or Vector3.new(4,3,7)
                        local offset = cfg.hitboxOffset or Vector3.new(0, 1, boxSize.Z * 0.5)
                        showDebugHitbox(originCFrame, boxSize, offset, ha + 0.04, color)
                end
            end)
        end

        -- tell the server we swung
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                swingEvent:FireServer(tool.Name, hrp.CFrame.LookVector)
            end
        end

        -- small delay to avoid immediate reentry; actual cooldown enforced by lastSwing
        task.delay(0.05, function() swingLock = false end)
    end

    local function startHolding()
        if holding then return end
        holding = true
        -- attempt immediate swing
        doSwing()
        spawn(function()
            while holding and tool and tool.Parent do
                local now = tick()
                local nextAllowed = lastSwing + cooldown
                local waitTime = math.max(0.001, nextAllowed - now)
                task.wait(waitTime)
                if not holding then break end
                doSwing()
            end
        end)
    end

    local function stopHolding()
        holding = false
    end

    tool.Equipped:Connect(function()
        table.insert(mouseConns, mouse.Button1Down:Connect(startHolding))
        table.insert(mouseConns, mouse.Button1Up:Connect(stopHolding))
    end)

    tool.Unequipped:Connect(function()
        stopHolding()
        for _, c in ipairs(mouseConns) do c:Disconnect() end
        mouseConns = {}
    end)
end

--------------------------------------------------------------------------------
-- Hit feedback from server
--------------------------------------------------------------------------------
meleeHitEvent.OnClientEvent:Connect(function(damage, isHeadshot, hitPart, hitPos)
    playMeleeSound("hit") -- generic fallback; server can send tool-specific later
    spawn(function()
        showDamagePopup(damage, isHeadshot, hitPart, hitPos)
    end)
end)

--------------------------------------------------------------------------------
-- Scan & watch for melee tools (same pattern as ToolGun.client)
--------------------------------------------------------------------------------
local function scanAndAttach()
    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do attachMelee(child) end
    end
    if player.Character then
        for _, child in ipairs(player.Character:GetChildren()) do attachMelee(child) end
    end
end

scanAndAttach()

player.Backpack.ChildAdded:Connect(function(child) attachMelee(child) end)
player.CharacterAdded:Connect(function(char)
    scanAndAttach()
    char.ChildAdded:Connect(function(child) attachMelee(child) end)
end)

print("[ToolMelee.client] running for", player and player.Name)
