-- EtherealSwordHandleColorizer.server.lua
-- Tints Ethereal Sword / Ethereal Bow parts from their enchant, using the
-- shared EtherealPartColors in WeaponEnchantConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TARGET_KEYWORD = "ethereal" -- case-insensitive match for tool name

local WeaponEnchantConfig
pcall(function()
    local module = ReplicatedStorage:FindFirstChild("WeaponEnchantConfig")
    if module and module:IsA("ModuleScript") then
        WeaponEnchantConfig = require(module)
    end
end)

local AssetCodes
pcall(function()
    local module = ReplicatedStorage:FindFirstChild("AssetCodes")
    if module and module:IsA("ModuleScript") then
        AssetCodes = require(module)
    end
end)

local FALLBACK_ENCHANT_TO_COLOR = {
    Lifesteal = Color3.fromRGB(255, 0, 4),   -- red
    Fiery     = Color3.fromRGB(255, 111, 0), -- orange
    Shock     = Color3.fromRGB(255, 213, 0), -- yellow
    Toxic     = Color3.fromRGB(98, 255, 0),  -- green
    Icy       = Color3.fromRGB(0, 166, 255), -- blue
    Void      = Color3.fromRGB(162, 0, 255), -- purple
}

local function getEnchantColor(enchantName)
    if WeaponEnchantConfig and type(WeaponEnchantConfig.GetEtherealPartColor) == "function" then
        local color = WeaponEnchantConfig.GetEtherealPartColor(enchantName)
        if color then
            return color
        end
    end
    return FALLBACK_ENCHANT_TO_COLOR[enchantName]
end

local function isTargetTool(tool)
    if not tool or not tool.Name then return false end
    local n = tostring(tool.Name):lower()
    return n == "ethereal sword" or n == "ethereal bow" or string.find(n, TARGET_KEYWORD, 1, true) ~= nil
end

local originalPartColors = setmetatable({}, { __mode = "k" })

local function setPartColor(part, color3)
    if not part or not part:IsA("BasePart") then return end
    pcall(function()
        -- Set Color3 directly to preserve exact color values (avoids BrickColor palette snapping)
        part.Color = color3
    end)
end

local function rememberOriginalColor(tool, part)
    if not tool or not part then return end
    local stored = originalPartColors[tool]
    if not stored then
        stored = {}
        originalPartColors[tool] = stored
    end
    if stored[part] == nil then
        stored[part] = part.Color
    end
end

local function restoreOriginalColors(tool)
    local stored = originalPartColors[tool]
    if not stored then return end
    for part, color in pairs(stored) do
        if part and part.Parent then
            setPartColor(part, color)
        end
    end
end

local function collectTintParts(tool)
    local parts = {}
    local handle = tool and tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        table.insert(parts, handle)
    end

    -- Ethereal Bow can be several welded meshes; tint those too.
    local toolName = tool and string.lower(tostring(tool.Name or ""))
    if toolName and string.find(toolName, "ethereal bow", 1, true) and tool.GetDescendants then
        for _, descendant in ipairs(tool:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name ~= "EnchantBlock" and descendant ~= handle then
                table.insert(parts, descendant)
            end
        end
    end

    return parts
end

local function applyEtherealIcon(tool, enchantName)
    if not tool or not AssetCodes or type(AssetCodes.GetWeaponIcon) ~= "function" then
        return
    end
    local icon = AssetCodes.GetWeaponIcon(tool.Name, enchantName)
    if type(icon) ~= "string" or icon == "" then
        return
    end
    pcall(function()
        tool.TextureId = icon
        tool:SetAttribute("Icon", icon)
    end)
end

local function applyHandleColorForEnchant(tool)
    if not tool then return end
    if not isTargetTool(tool) then return end
    local hasEnchant = tool:GetAttribute("HasEnchant")
    local enchantName = tool:GetAttribute("EnchantName")
    if not hasEnchant or not enchantName or enchantName == "" then
        restoreOriginalColors(tool)
        return
    end

    local color3 = getEnchantColor(enchantName)
    if not color3 then
        restoreOriginalColors(tool)
        return
    end

    for _, part in ipairs(collectTintParts(tool)) do
        rememberOriginalColor(tool, part)
        setPartColor(part, color3)
    end

    applyEtherealIcon(tool, enchantName)
end

local function onToolEquipped(tool)
    -- Only act on Ethereal-style tools
    if not isTargetTool(tool) then return end
    applyHandleColorForEnchant(tool)
end

local function attachToTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if not isTargetTool(tool) then return end
    if tool:GetAttribute("_HandleColorizerAttached") then return end
    tool:SetAttribute("_HandleColorizerAttached", true)

    -- Connect Equipped (server-side) so color changes are authoritative and visible to all
    tool.Equipped:Connect(function()
        onToolEquipped(tool)
    end)

    -- Listen for attribute changes so color updates immediately when enchants change
    if tool.GetAttributeChangedSignal then
        tool:GetAttributeChangedSignal("HasEnchant"):Connect(function()
            applyHandleColorForEnchant(tool)
        end)
        tool:GetAttributeChangedSignal("EnchantName"):Connect(function()
            applyHandleColorForEnchant(tool)
        end)
        tool:GetAttributeChangedSignal("EnchantColorHex"):Connect(function()
            applyHandleColorForEnchant(tool)
        end)
    end

    -- Tint immediately so backpack / StarterGear copies match the enchant too.
    applyHandleColorForEnchant(tool)
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
