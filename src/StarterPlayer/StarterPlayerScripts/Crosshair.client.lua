local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local BASE_GAP = 6
local MAX_RECOIL_SPREAD = 14
local LINE_THICKNESS = 3
local LINE_LENGTH = 10
local GAP_RETURN_TIME = 0.18 -- seconds
local DEFAULT_RECOIL_AMOUNT = 8

-- State
local currentGap = BASE_GAP
local returnTween = nil
local tweenInfo = TweenInfo.new(GAP_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CrosshairUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui
screenGui.Enabled = false

local function makeLine(name, size, anchor, pos)
    local f = Instance.new("Frame")
    f.Name = name
    f.Size = size
    f.AnchorPoint = anchor
    f.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
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

-- Public functions
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

-- Expose functions
_G.expandCrosshair = expandCrosshair
_G.resetCrosshair = resetCrosshair

-- Auto-hook: expand on server fire ack
local fireAck = ReplicatedStorage:FindFirstChild("ToolGunFireAck")
if fireAck and fireAck:IsA("RemoteEvent") then
    fireAck.OnClientEvent:Connect(function(gunOrigin, aimPos, toolName)
        expandCrosshair(DEFAULT_RECOIL_AMOUNT)
    end)
end

-- initial layout
updatePositions(BASE_GAP)

-- Show/hide crosshair based on equipped toolguns
local TOOLCFG_MODULE
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    TOOLCFG_MODULE = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
end

local function isToolGunLocal(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsToolGun") then return true end
    local name = tostring(tool.Name)
    local suffix = name:match("^Tool(.+)")
    if suffix then
        local key = suffix:lower()
        if TOOLCFG_MODULE and TOOLCFG_MODULE.presets and TOOLCFG_MODULE.presets[key] then
            return true
        end
    end
    return false
end

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

local function watchTool(tool)
    if not isToolGunLocal(tool) then return end
    if toolConns[tool] then return end
    local conns = {}
    table.insert(conns, tool.Equipped:Connect(onEquippedTool))
    table.insert(conns, tool.Unequipped:Connect(onUnequippedTool))
    -- if already parented to character, consider it equipped
    if tool.Parent and tool.Parent:IsDescendantOf(player.Character or workspace) and tool.Parent == player.Character then
        onEquippedTool()
    end
    toolConns[tool] = conns
end

local function unwatchTool(tool)
    local conns = toolConns[tool]
    if conns then
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        toolConns[tool] = nil
    end
    -- if it was equipped, ensure count corrected (Unequipped should have fired normally)
end

local function scanContainer(container)
    if not container then return end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            watchTool(child)
        end
    end
    container.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            watchTool(child)
        end
    end)
end

-- initial scan
scanContainer(player.Backpack)
if player.Character then
    scanContainer(player.Character)
end
player.CharacterAdded:Connect(function(char)
    -- reset state
    for tool, _ in pairs(toolConns) do
        unwatchTool(tool)
    end
    equippedCount = 0
    screenGui.Enabled = false
    scanContainer(char)
end)
