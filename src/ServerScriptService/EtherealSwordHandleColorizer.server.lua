-- EtherealSwordHandleColorizer.server.lua
-- Sets the Handle BrickColor for Ethereal Sword based on its enchant when equipped.

local Players = game:GetService("Players")

local TARGET_KEYWORD = "ethereal" -- case-insensitive match for tool name

local ENCHANT_TO_BRICKCOLOR = {
    Lifesteal = BrickColor.new(Color3.fromRGB(255, 0, 4)),   -- red
    Fiery     = BrickColor.new(Color3.fromRGB(255, 111, 0)), -- orange
    Shock     = BrickColor.new(Color3.fromRGB(255, 213, 0)), -- yellow
    Toxic     = BrickColor.new(Color3.fromRGB(98, 255, 0)),   -- green
    Icy       = BrickColor.new(Color3.fromRGB(0, 166, 255)), -- blue
    Void      = BrickColor.new(Color3.fromRGB(162, 0, 255)), -- purple
}

local function isTargetTool(tool)
    if not tool or not tool.Name then return false end
    local n = tostring(tool.Name):lower()
    return string.find(n, TARGET_KEYWORD, 1, true) ~= nil
end

local function applyHandleColorForEnchant(tool)
    if not tool then return end
    local hasEnchant = tool:GetAttribute("HasEnchant")
    local enchantName = tool:GetAttribute("EnchantName")
    if not hasEnchant or not enchantName or enchantName == "" then
        return
    end

    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        local bc = ENCHANT_TO_BRICKCOLOR[enchantName]
        if bc then
            pcall(function()
                handle.BrickColor = bc
            end)
        end
    end
end

local function onToolEquipped(tool)
    -- Only act on Ethereal-style tools
    if not isTargetTool(tool) then return end
    applyHandleColorForEnchant(tool)
end

local function attachToTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if tool:GetAttribute("_HandleColorizerAttached") then return end
    tool:SetAttribute("_HandleColorizerAttached", true)

    -- Connect Equipped (server-side) so color changes are authoritative and visible to all
    tool.Equipped:Connect(function()
        onToolEquipped(tool)
    end)

    -- Also react if enchant attributes are already present when the tool appears in a character
    if tool.Parent and tool.Parent:IsA("Model") and tool.Parent:FindFirstChildOfClass("Humanoid") then
        -- tool is already in a character
        onToolEquipped(tool)
    end
end

local function monitorPlayer(player)
    -- Watch Backpack for tools added
    local backpack = player:WaitForChild("Backpack")
    backpack.ChildAdded:Connect(function(child)
        attachToTool(child)
    end)

    -- Watch Character tools
    player.CharacterAdded:Connect(function(char)
        char.ChildAdded:Connect(function(child)
            attachToTool(child)
        end)
        -- Attach existing tools in character
        for _, c in ipairs(char:GetChildren()) do
            attachToTool(c)
        end
    end)

    -- Attach existing tools in backpack
    for _, t in ipairs(backpack:GetChildren()) do
        attachToTool(t)
    end
    -- Attach currently equipped tool if character exists
    if player.Character then
        for _, c in ipairs(player.Character:GetChildren()) do
            attachToTool(c)
        end
    end
end

-- Initial hookup for existing players
for _, p in ipairs(Players:GetPlayers()) do
    monitorPlayer(p)
end

Players.PlayerAdded:Connect(function(player)
    monitorPlayer(player)
end)

-- Also monitor tools that may be created elsewhere (e.g. ServerStorage grants)
game.DescendantAdded:Connect(function(desc)
    if desc and desc:IsA("Tool") then
        attachToTool(desc)
    end
end)

return nil
