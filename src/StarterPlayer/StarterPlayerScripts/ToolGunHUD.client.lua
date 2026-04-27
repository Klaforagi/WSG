local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local fireEvent = ReplicatedStorage:WaitForChild("ToolGunFire")
local fireAck = ReplicatedStorage:WaitForChild("ToolGunFireAck")
local fireHit = ReplicatedStorage:FindFirstChild("ToolGunHit")

-- Config (from original crosshair)
local BASE_GAP = 6
local MAX_RECOIL_SPREAD = 14
local LINE_THICKNESS = 3
local LINE_LENGTH = 10
local GAP_RETURN_TIME = 0.18
local DEFAULT_RECOIL_AMOUNT = 8

-- Tracer / color utils (from original toolgun client)
local TEAM_TRACER_COLORS = {
    Blue = Color3.fromRGB(65, 105, 225),
    Red  = Color3.fromRGB(255, 75, 75),
}
local DEFAULT_TRACER_COLOR = Color3.fromRGB(255, 200, 100)
local function getTracerColor()
    if player and player.Team then
        return TEAM_TRACER_COLORS[player.Team.Name] or DEFAULT_TRACER_COLOR
    end
    return DEFAULT_TRACER_COLOR
end

local Debris = game:GetService("Debris")

-- Load tool config module early so playFireSound can use preset shoot_sound
local TOOLCFG_MODULE
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    TOOLCFG_MODULE = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
end

-- Size-scaling helpers (mirrors server logic in ToolGunSetup)
local function getClientSizePercent(tool)
    if not tool then return 100 end
    local sp = tool:GetAttribute("SizePercent")
        or tool:GetAttribute("WeaponSizePercent")
        or tool:GetAttribute("ScalePercent")
        or tool:GetAttribute("WeaponScale")
    if type(sp) == "number" and sp > 0 then return sp end
    return 100
end
local function getClientSizeSpeedMult(sp)
    if sp <= 100 then return math.clamp(sp / 100, 0.5, 1.0) end
    return math.clamp(1.0 + (sp - 100) / 200, 1.0, 2.0)
end
local function getClientScaledCooldown(baseCd, sizePercent)
    return baseCd * getClientSizeSpeedMult(sizePercent)
end

local function playFireSound(toolName)
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end

    local template = nil

    -- 1) Try preset shoot_sound from Toolgunsettings
    if TOOLCFG_MODULE and TOOLCFG_MODULE.getPreset and toolName then
        local suffix = tostring(toolName):match("^Tool(.+)") or tostring(toolName)
        local preset = TOOLCFG_MODULE.getPreset(suffix:lower())
        if preset and preset.shoot_sound then
            -- try exact name first, then case-insensitive scan
            template = toolgunFolder:FindFirstChild(preset.shoot_sound)
            if not template then
                local target = preset.shoot_sound:lower()
                for _, child in ipairs(toolgunFolder:GetChildren()) do
                    if child:IsA("Sound") and child.Name:lower() == target then
                        template = child
                        break
                    end
                end
            end
        end
    end

    -- 2) Fallback: name-based heuristics
    if not template and toolName then
        local lower = tostring(toolName):lower()
        if lower:find("sniper") then
            template = toolgunFolder:FindFirstChild("Sniper_shoot") or toolgunFolder:FindFirstChild("Sniper_Shoot")
        elseif lower:find("pistol") then
            template = toolgunFolder:FindFirstChild("Pistol_shoot") or toolgunFolder:FindFirstChild("Pistol_Shoot")
        elseif lower:find("shortbow") or lower:find("bow") then
            -- prefer Shortbow detection but fall back to legacy 'Bow' asset names
            template = toolgunFolder:FindFirstChild("Shortbow_shoot") or toolgunFolder:FindFirstChild("Shortbow_Shoot")
            if not template then
                template = toolgunFolder:FindFirstChild("Bow_shoot") or toolgunFolder:FindFirstChild("Bow_Shoot")
            end
        end
    end

    -- 3) Last resort
    if not template then
        template = toolgunFolder:FindFirstChild("Gun_shoot")
    end

    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

local function playHitSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end
    local template = toolgunFolder:FindFirstChild("Gun_hitmarker")
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

-- Build HUD ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ToolGunHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui
screenGui.Enabled = false

local function makeLine(name, size, anchor, pos)
    local f = Instance.new("Frame")
    f.Name = name
    f.Size = size
    f.AnchorPoint = anchor
    f.BackgroundColor3 = getTracerColor()
    f.BorderSizePixel = 0
    f.Position = pos
    f.Parent = screenGui
    return f
end

local centerUD = UDim2.new(0.5, 0, 0.5, 0)
local up = makeLine("Cross_Up",
    UDim2.new(0, LINE_THICKNESS, 0, LINE_LENGTH),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))
)
local down = makeLine("Cross_Down",
    UDim2.new(0, LINE_THICKNESS, 0, LINE_LENGTH),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, 0, 0, (BASE_GAP + LINE_LENGTH/2))
)
local left = makeLine("Cross_Left",
    UDim2.new(0, LINE_LENGTH, 0, LINE_THICKNESS),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)
)
local right = makeLine("Cross_Right",
    UDim2.new(0, LINE_LENGTH, 0, LINE_THICKNESS),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, (BASE_GAP + LINE_LENGTH/2), 0, 0)
)

local function updatePositions(gap)
    up.Position    = centerUD + UDim2.new(0, 0, 0, -(gap + LINE_LENGTH/2))
    down.Position  = centerUD + UDim2.new(0, 0, 0,  (gap + LINE_LENGTH/2))
    left.Position  = centerUD + UDim2.new(0, -(gap + LINE_LENGTH/2), 0, 0)
    right.Position = centerUD + UDim2.new(0,  (gap + LINE_LENGTH/2), 0, 0)
end

-- Hitmarker (center X)
local hitLabel = Instance.new("TextLabel")
hitLabel.Name = "HitMarker"
hitLabel.Size = UDim2.new(0, 12, 0, 12)
hitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hitLabel.BackgroundTransparency = 1
hitLabel.Text = "X"
hitLabel.Font = Enum.Font.GothamBold
hitLabel.TextScaled = false
hitLabel.TextSize = 14
hitLabel.TextColor3 = Color3.fromRGB(0,0,0)
hitLabel.TextTransparency = 0
hitLabel.TextStrokeTransparency = 0.5
hitLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hitLabel.Visible = false
hitLabel.Position = centerUD
hitLabel.Parent = screenGui

-- Crosshair animation state
local currentGap = BASE_GAP
local returnTween = nil
local tweenInfo = TweenInfo.new(GAP_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function resetCrosshair()
    if returnTween then
        pcall(function() returnTween:Cancel() end)
        returnTween = nil
    end
    local goal = {}
    goal[up]    = {Position = centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))}
    goal[down]  = {Position = centerUD + UDim2.new(0, 0, 0,  (BASE_GAP + LINE_LENGTH/2))}
    goal[left]  = {Position = centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)}
    goal[right] = {Position = centerUD + UDim2.new(0,  (BASE_GAP + LINE_LENGTH/2), 0, 0)}

    local tweens = {}
    for part, props in pairs(goal) do
        local t = TweenService:Create(part, tweenInfo, props)
        t:Play()
        table.insert(tweens, t)
    end
    currentGap = BASE_GAP
    returnTween = tweens[1]
    returnTween.Completed:Connect(function()
        returnTween = nil
    end)
end

local function expandCrosshair(amount)
    local add = amount or DEFAULT_RECOIL_AMOUNT
    local newGap = math.min((currentGap or BASE_GAP) + add, MAX_RECOIL_SPREAD)
    currentGap = newGap

    if returnTween then
        pcall(function() returnTween:Cancel() end)
        returnTween = nil
    end

    updatePositions(currentGap)

    local goal = {}
    goal[up]    = {Position = centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))}
    goal[down]  = {Position = centerUD + UDim2.new(0, 0, 0,  (BASE_GAP + LINE_LENGTH/2))}
    goal[left]  = {Position = centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)}
    goal[right] = {Position = centerUD + UDim2.new(0,  (BASE_GAP + LINE_LENGTH/2), 0, 0)}

    local tweens = {}
    for part, props in pairs(goal) do
        local t = TweenService:Create(part, tweenInfo, props)
        t:Play()
        table.insert(tweens, t)
    end
    returnTween = tweens[1]
    returnTween.Completed:Connect(function()
        currentGap = BASE_GAP
        returnTween = nil
    end)
end

-- Hold-to-fire state (server-paced via ACK; no client-side timer drift)
local COOLDOWN = 0.5
local isHoldingFire = false
local shotInFlight = false
local nextAllowedFireAt = 0
local fireToken = 0
local currentFiringTool = nil
local toolCooldowns = {} -- toolName → base cd (set by attachTool, used in ACK handler)

local function tryFire(tool)
    if not isHoldingFire then return end
    if shotInFlight then return end
    if os.clock() < nextAllowedFireAt then return end
    if not tool or not tool.Parent then return end
    local char = player.Character
    if not char or not char:FindFirstChild(tool.Name) then return end
    if _G.IsBandaging then return end

    shotInFlight = true
    local origin
    if tool:FindFirstChild("Handle") and tool.Handle:IsA("BasePart") then
        origin = tool.Handle.Position
    else
        origin = camera.CFrame.Position
    end
    local mouse = player:GetMouse()
    local mx, my
    if mouse and mouse.X and mouse.Y then
        mx = mouse.X ; my = mouse.Y
    else
        local mpos = game:GetService("UserInputService"):GetMouseLocation()
        mx = mpos.X ; my = mpos.Y
    end
    local ray = camera:ScreenPointToRay(mx, my)
    fireEvent:FireServer(ray.Origin, ray.Direction.Unit, origin, tool.Name)
    -- Failsafe: if no ACK within 0.35s, clear the in-flight flag so the gun does not get stuck
    local myToken = fireToken
    task.delay(0.35, function()
        if fireToken == myToken and shotInFlight then
            shotInFlight = false
        end
    end)
end

fireAck.OnClientEvent:Connect(function(gunOrigin, targetPos, toolName)
    expandCrosshair(DEFAULT_RECOIL_AMOUNT)
    playFireSound(toolName)

    -- Resolve the equipped tool to compute size-scaled cooldown
    local equippedTool = nil
    local char = player.Character
    if char and toolName then equippedTool = char:FindFirstChild(toolName) end
    local baseCd = toolCooldowns[toolName] or COOLDOWN
    local sizePercent = getClientSizePercent(equippedTool)
    local scaledCd = getClientScaledCooldown(baseCd, sizePercent)

    -- Hotbar cooldown overlay with the correct size-scaled duration
    if _G.HotbarCooldown then
        _G.HotbarCooldown.start(2, scaledCd)
    end

    -- Unblock the next shot and schedule tryFire if player is still holding
    shotInFlight = false
    nextAllowedFireAt = os.clock() + scaledCd

    if isHoldingFire then
        local myToken = fireToken
        task.delay(scaledCd, function()
            if fireToken == myToken and isHoldingFire then
                tryFire(currentFiringTool)
            end
        end)
    end
end)

-- Hit event handling: reuse logic from ToolGun.client.lua
if fireHit and fireHit:IsA("RemoteEvent") then
    fireHit.OnClientEvent:Connect(function(damage, isHeadshot, hitPart, hitPos)
        playHitSound()
        local color = isHeadshot and Color3.fromRGB(243, 255, 16) or Color3.fromRGB(243, 255, 16)
        if screenGui.Enabled then
            hitLabel.TextColor3 = color
            local hitSize = isHeadshot and 28 or 16
            hitLabel.TextSize = hitSize
            hitLabel.TextStrokeTransparency = 0
            hitLabel.Visible = true
            task.delay(0.25, function()
                hitLabel.Visible = false
                hitLabel.TextSize = 14
                hitLabel.TextStrokeTransparency = 0.5
            end)
        else
            -- temporary center hit indicator if HUD not shown
            local tempGui = Instance.new("ScreenGui")
            tempGui.IgnoreGuiInset = true
            tempGui.ResetOnSpawn = false
            tempGui.Parent = playerGui
            local temp = Instance.new("TextLabel")
            temp.Size = UDim2.new(0,12,0,12)
            temp.Position = centerUD
            temp.AnchorPoint = Vector2.new(0.5,0.5)
            temp.BackgroundTransparency = 1
            temp.Text = "X"
            temp.Font = Enum.Font.GothamBold
            local tempSize = isHeadshot and 28 or 16
            temp.TextSize = tempSize
            temp.TextColor3 = color
            temp.TextTransparency = 0
            temp.TextStrokeTransparency = 0
            temp.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            temp.Parent = tempGui
            task.delay(0.25, function()
                tempGui:Destroy()
            end)
        end

        -- floating damage number at hit location/part (unchanged)
        spawn(function()
            local TweenService = game:GetService("TweenService")
            local parentPart = nil
            local createdAnchor = nil
            if hitPart and typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
                parentPart = hitPart
            elseif hitPos and typeof(hitPos) == "Vector3" then
                createdAnchor = Instance.new("Part")
                createdAnchor.Name = "_DamageAnchor"
                createdAnchor.Size = Vector3.new(0.2,0.2,0.2)
                createdAnchor.Transparency = 1
                createdAnchor.Anchored = true
                createdAnchor.CanCollide = false
                createdAnchor.CFrame = CFrame.new(hitPos)
                createdAnchor.Parent = workspace
                parentPart = createdAnchor
            end
            if not parentPart then return end

            local gui = Instance.new("BillboardGui")
            gui.Name = "DamagePopup"
            gui.Size = UDim2.new(0,100,0,40)
            gui.Adornee = parentPart
            gui.AlwaysOnTop = true
            gui.StudsOffset = Vector3.new(0, 2, 0)
            gui.Parent = parentPart

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1,0,1,0)
            label.BackgroundTransparency = 1
            label.Text = tostring(math.floor(damage))
            label.Font = Enum.Font.GothamBold
            label.TextSize = 24
            label.TextColor3 = isHeadshot and Color3.fromRGB(255,75,75) or Color3.fromRGB(255,255,255)
            label.TextStrokeTransparency = 0.5
            label.Parent = gui

            local goal = {StudsOffset = gui.StudsOffset + Vector3.new(0,1.2,0)}
            local tween = TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), goal)
            tween:Play()
            for i = 0, 1, 0.06 do
                label.TextTransparency = i
                task.wait(0.06)
            end
            tween:Cancel()
            gui:Destroy()
            if createdAnchor and createdAnchor.Parent then createdAnchor:Destroy() end
        end)
    end)
end

-- Tool detection logic (merge of both scripts)
-- (TOOLCFG_MODULE already required above)

local function isToolGun(tool)
    if not tool then return false end
    if tool:GetAttribute("IsToolGun") then return true end
    local name = tostring(tool.Name)
    if name == "ToolPistol" or name == "ToolSniper" then return true end
    local suffix = name:match("^Tool(.+)") or name:match("^(.+)$")
    if suffix then
        local key = suffix:lower()
        if TOOLCFG_MODULE and TOOLCFG_MODULE.presets and TOOLCFG_MODULE.presets[key] then
            return true
        end
    end
    return false
end

-- Show/hide HUD based on equipped ToolGun
local equippedCount = 0
local toolConns = {}

local function onEquippedTool()
    equippedCount = equippedCount + 1
    screenGui.Enabled = true
end
local function onUnequippedTool()
    equippedCount = math.max(0, equippedCount - 1)
    if equippedCount == 0 then
        screenGui.Enabled = false
    end
end

-- Firing logic copied from original ToolGun.client.lua
local attachedTools = {} -- Lua table registry to prevent duplicate connections on clones

local function getToolCfgForTool(tool)
    local cfg = {}
    local toolType = tool:GetAttribute("ToolType")
    if not toolType then
        local name = tostring(tool.Name)
        local suffix = name:match("^Tool(.+)") or name:match("^(.+)$")
        if suffix then toolType = suffix:lower() end
    end
    if TOOLCFG_MODULE and TOOLCFG_MODULE.getPreset and toolType then
        local preset = TOOLCFG_MODULE.getPreset(toolType)
        if preset then
            for k, v in pairs(preset) do cfg[k] = v end
        end
    end
    local attrs = {"cd","bulletspeed","damage","range","projectile_lifetime","projectile_size","bulletdrop","showTracer"}
    for _, a in ipairs(attrs) do
        local val = tool:GetAttribute(a)
        if val ~= nil then cfg[a] = val end
    end
    return cfg
end

local function attachTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if not isToolGun(tool) then return end
    if attachedTools[tool] then return end
    attachedTools[tool] = true

    local toolCfg = getToolCfgForTool(tool)
    local toolCooldown = (toolCfg and toolCfg.cd) or COOLDOWN
    toolCooldowns[tool.Name] = toolCooldown   -- base cd stored for ACK handler size-scaling

    local mouse = player:GetMouse()
    local function startFiring()
        if _G.IsBandaging then return end
        isHoldingFire = true
        currentFiringTool = tool
        tryFire(tool)
    end

    local function stopFiring()
        isHoldingFire = false
        fireToken = fireToken + 1
        shotInFlight = false
    end

    local mouseConns = {}
    local function clearMouseConns()
        for _, c in ipairs(mouseConns) do c:Disconnect() end
        mouseConns = {}
    end

    tool.Equipped:Connect(function()
        clearMouseConns() -- prevent duplicates if Equipped fires twice
        table.insert(mouseConns, mouse.Button1Down:Connect(startFiring))
        table.insert(mouseConns, mouse.Button1Up:Connect(stopFiring))
        onEquippedTool()
    end)

    tool.Unequipped:Connect(function()
        clearMouseConns()
        stopFiring()
        onUnequippedTool()
    end)

end

local scannedContainers = {} -- prevent duplicate ChildAdded on same container
local function scanContainer(container)
    if not container then return end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            attachTool(child)
        end
    end
    if not scannedContainers[container] then
        scannedContainers[container] = true
        container.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                attachTool(child)
            end
        end)
    end
end

-- initial scan & connections
scanContainer(player.Backpack)
if player.Character then scanContainer(player.Character) end
player.CharacterAdded:Connect(function(char)
    scanContainer(char)
end)

-- also scan StarterPack for tools (they get copied to Backpack)
for _, child in ipairs(StarterPack:GetChildren()) do
    if child:IsA("Tool") and isToolGun(child) then
        -- no-op; attach happens when copied to Backpack
    end
end

-- initial crosshair layout
updatePositions(BASE_GAP)

return nil
