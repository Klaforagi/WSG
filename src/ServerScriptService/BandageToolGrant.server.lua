--------------------------------------------------------------------------------
-- BandageToolGrant.server.lua
-- Grants a fallback Bandage tool to every player so slot 3 can equip an
-- actual tool instead of immediately firing the heal action.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")

local BANDAGE_TOOL_NAME = "Bandage"

local function createBandageToolTemplate()
    local tool = Instance.new("Tool")
    tool.Name = BANDAGE_TOOL_NAME
    tool.CanBeDropped = false
    tool.RequiresHandle = true
    tool:SetAttribute("HotbarCategory", "Utility")
    tool:SetAttribute("UtilityType", "bandage")
    tool:SetAttribute("BandageTool", true)

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1, 0.45, 1.35)
    handle.Color = Color3.fromRGB(240, 236, 226)
    handle.Material = Enum.Material.SmoothPlastic
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    handle.Parent = tool

    local wrap = Instance.new("Part")
    wrap.Name = "Wrap"
    wrap.Size = Vector3.new(1.05, 0.14, 0.42)
    wrap.Color = Color3.fromRGB(160, 255, 84)
    wrap.Material = Enum.Material.SmoothPlastic
    wrap.CanCollide = false
    wrap.CanTouch = false
    wrap.CanQuery = false
    wrap.Massless = true
    wrap.Parent = tool

    local wrapWeld = Instance.new("WeldConstraint")
    wrapWeld.Part0 = handle
    wrapWeld.Part1 = wrap
    wrapWeld.Parent = wrap
    wrap.CFrame = handle.CFrame

    local strip = Instance.new("Part")
    strip.Name = "Strip"
    strip.Size = Vector3.new(0.16, 0.52, 0.42)
    strip.Color = Color3.fromRGB(255, 255, 255)
    strip.Material = Enum.Material.SmoothPlastic
    strip.CanCollide = false
    strip.CanTouch = false
    strip.CanQuery = false
    strip.Massless = true
    strip.Parent = tool

    local stripWeld = Instance.new("WeldConstraint")
    stripWeld.Part0 = handle
    stripWeld.Part1 = strip
    stripWeld.Parent = strip
    strip.CFrame = handle.CFrame

    local plusGui = Instance.new("BillboardGui")
    plusGui.Name = "PlusIcon"
    plusGui.Size = UDim2.fromOffset(48, 48)
    plusGui.StudsOffset = Vector3.new(0, 0.7, 0)
    plusGui.AlwaysOnTop = true
    plusGui.Parent = handle

    local plus = Instance.new("TextLabel")
    plus.BackgroundTransparency = 1
    plus.Size = UDim2.fromScale(1, 1)
    plus.Text = "+"
    plus.TextScaled = true
    plus.Font = Enum.Font.GothamBlack
    plus.TextColor3 = Color3.fromRGB(160, 255, 84)
    plus.TextStrokeColor3 = Color3.fromRGB(40, 80, 20)
    plus.TextStrokeTransparency = 0.25
    plus.Parent = plusGui

    tool.GripPos = Vector3.new(0, -0.1, -0.55)
    tool.GripForward = Vector3.new(0, 0, -1)
    tool.GripRight = Vector3.new(1, 0, 0)
    tool.GripUp = Vector3.new(0, 1, 0)

    return tool
end

local bandageToolTemplate = createBandageToolTemplate()

local function grantBandageTool(player)
    if not player or not player.Parent then
        return
    end

    local starterGear = player:WaitForChild("StarterGear", 5)
    local backpack = player:WaitForChild("Backpack", 5)
    local character = player.Character

    local starterHas = starterGear and starterGear:FindFirstChild(BANDAGE_TOOL_NAME)
    local backpackHas = backpack and backpack:FindFirstChild(BANDAGE_TOOL_NAME)
    local characterHas = character and character:FindFirstChild(BANDAGE_TOOL_NAME)

    if starterGear and not starterHas then
        local starterClone = bandageToolTemplate:Clone()
        starterClone.Parent = starterGear
    end

    if backpack and not backpackHas and not characterHas then
        local backpackClone = bandageToolTemplate:Clone()
        backpackClone.Parent = backpack
    end
end

local function hookPlayer(player)
    if not player then
        return
    end

    player.CharacterAdded:Connect(function()
        task.spawn(grantBandageTool, player)
    end)

    task.defer(function()
        grantBandageTool(player)
    end)
end

Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(player)
    -- The tool is cloned per-player and cleaned up automatically with the player.
end)

for _, player in ipairs(Players:GetPlayers()) do
    hookPlayer(player)
end
