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
    local suffix = tostring(tool.Name):match("^Tool(.+)") or tostring(tool.Name):match("^(.+)$")
    if not suffix then return false end
    if MeleeCfgModule and MeleeCfgModule.presets then
        return MeleeCfgModule.presets[suffix:lower()] ~= nil
    end
    return false
end

local function getCfg(tool)
    local cfg = {}
    local suffix = tostring(tool.Name):match("^Tool(.+)") or tostring(tool.Name):match("^(.+)$")
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
    label.TextColor3 = isHeadshot and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(255, 215, 80)
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
-- Play configured animation locally (returns true on success)
-- Supports swing_anim_ids (ordered array) — cycles 1→2→3→1… per tool.
--------------------------------------------------------------------------------
local currentSwingTrack = nil -- script-level: previous swing track reference
local swingCycleIndex = {}    -- [toolName] → next index into swing_anim_ids

local function playLocalCfgAnimation(cfg, toolName)
    -- Resolve which animation id to use this swing
    local animId = nil
    if cfg and cfg.swing_anim_ids and type(cfg.swing_anim_ids) == "table" and #cfg.swing_anim_ids > 0 then
        -- build a filtered list of non-empty ids
        local validIds = {}
        for _, id in ipairs(cfg.swing_anim_ids) do
            if id and tostring(id) ~= "" then table.insert(validIds, tostring(id)) end
        end
        if #validIds > 0 then
            local key = toolName or "_default"
            local idx = swingCycleIndex[key] or 1
            animId = validIds[((idx - 1) % #validIds) + 1]
            swingCycleIndex[key] = idx + 1
        end
    end
    -- fall back to single swing_anim_id
    if (not animId or animId == "") and cfg and cfg.swing_anim_id and cfg.swing_anim_id ~= "" then
        animId = tostring(cfg.swing_anim_id)
    end
    if not animId or animId == "" then return false end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    print("[MeleeAnim] RigType =", tostring(hum.RigType))

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end

    -- Stop any previous swing track to avoid overlap/conflicts
    if currentSwingTrack then
        pcall(function() currentSwingTrack:Stop(0) end)
        currentSwingTrack = nil
    end

    if not animId:match("^rbxassetid://") then
        if tonumber(animId) then animId = "rbxassetid://" .. animId end
    end
    print("[MeleeAnim] Loading animId =", animId)

    local a = Instance.new("Animation")
    a.AnimationId = animId
    local ok, track = pcall(function() return animator:LoadAnimation(a) end)
    if not ok or not track then
        print("[MeleeAnim] LoadAnimation FAILED")
        return false
    end

    -- Use Action4 (highest action priority) so idle/walk/tool anims cannot override
    track.Priority = Enum.AnimationPriority.Action4

    -- scale speed to match cooldown if provided
    local cd = cfg.cd or 0.6
    local okL, length = pcall(function() return track.Length end)
    if okL and type(length) == "number" and length > 0 and cd and cd > 0 then
        local speed = length / cd
        if speed < 0.25 then speed = 0.25 end
        if speed > 4 then speed = 4 end
        pcall(function() track:AdjustSpeed(speed) end)
    end

    local okPlay = pcall(function() track:Play(0) end)
    if not okPlay then
        print("[MeleeAnim] track:Play() FAILED")
        return false
    end

    currentSwingTrack = track
    print("[MeleeAnim] track:Play() called for", animId)

    -- wait one frame then verify playback status
    task.spawn(function()
        RunService.Heartbeat:Wait()
        local playing = false
        pcall(function() playing = track.IsPlaying end)
        print("[MeleeAnim] After 1 frame: IsPlaying =", tostring(playing))

        -- check length after a short delay (some tracks report 0 initially)
        task.wait(0.1)
        local delayedLength = 0
        pcall(function() delayedLength = track.Length end)
        print("[MeleeAnim] Track.Length (delayed) =", delayedLength)

        if playing and delayedLength > 0 then
            -- Animation is playing but may be invisible if authored for wrong rig
            local rigType = tostring(hum.RigType)
            if rigType == "Enum.HumanoidRigType.R6" then
                warn("[MeleeAnim] Character is R6 — if you see no visual, the animation may have been authored for R15.")
            elseif rigType == "Enum.HumanoidRigType.R15" then
                warn("[MeleeAnim] Character is R15 — if you see no visual, the animation may have been authored for R6.")
            end
        end
    end)

    -- schedule stop/cleanup
    task.delay((cd or 0.6) * 1.2 + 0.05, function()
        if track then pcall(function() track:Stop() end) end
        if currentSwingTrack == track then currentSwingTrack = nil end
        if a and a.Parent == nil then pcall(function() a:Destroy() end) end
    end)
    return true
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

    -- (moved playLocalCfgAnimation to top-level)

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
    -- use slightly less than 90° to avoid ambiguous 180° interpolation that can flip the arm
    local SWING_ANGLE = 85
    -- phase 1: raise arm up (negative rotation to lift)
    local raiseGoal = originalC1 * CFrame.Angles(math.rad(-SWING_ANGLE), 0, 0)
    -- phase 2: slash down (rotate to +SWING_ANGLE relative to default)
    local slashGoal = originalC1 * CFrame.Angles(math.rad(SWING_ANGLE), 0, 0)

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
                local startTime = tick()
                local boxSize = cfg.hitboxSize or Vector3.new(4,3,7)
                local offset = cfg.hitboxOffset or Vector3.new(0, 1, boxSize.Z * 0.5)

                -- create a single client-side debug part and update it every frame
                local part = workspace:FindFirstChild("_MeleeHitboxDebug")
                if not part or not part:IsA("BasePart") then
                    part = Instance.new("Part")
                    part.Name = "_MeleeHitboxDebug"
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = 0.6
                    part.Size = boxSize
                    part.Color = color
                    part.Material = Enum.Material.Neon
                    part.Parent = workspace
                end

                local conn
                conn = RunService.Heartbeat:Connect(function()
                    if not part or not part.Parent then
                        if conn then conn:Disconnect() end
                        return
                    end
                    if tick() - startTime > ha then
                        if conn then conn:Disconnect() end
                        if part and part.Parent then part:Destroy() end
                        return
                    end
                    local char = player.Character
                    if not char then return end
                    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                    if not hrp then return end
                    local rightV = hrp.CFrame.RightVector
                    local upV = hrp.CFrame.UpVector
                    local lookV = hrp.CFrame.LookVector
                    local pos = hrp.Position + rightV * offset.X + upV * offset.Y + lookV * offset.Z
                    local boxCFrame = CFrame.new(pos, pos + lookV)
                    if part.Size ~= boxSize then part.Size = boxSize end
                    if part.Color ~= color then part.Color = color end
                    part.CFrame = boxCFrame
                end)
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

        -- play local configured animation for immediate feedback, fallback to procedural
        local playedAnim = nil
        pcall(function() playedAnim = playLocalCfgAnimation(cfg, tool.Name) end)
        if not playedAnim then
            playSwingVisual(tool)
        end

        -- trigger hotbar cooldown overlay (slot 1 = Melee)
        if _G.HotbarCooldown then
            _G.HotbarCooldown.start(1, cooldown)
        end

        -- small delay to avoid immediate reentry; actual cooldown enforced by lastSwing
        task.delay(0.05, function() swingLock = false end)
    end

    local function startHolding()
        -- single-click behavior: trigger one swing per button down
        doSwing()
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
