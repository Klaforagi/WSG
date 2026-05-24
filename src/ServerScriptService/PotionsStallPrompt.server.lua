-- PotionsStallPrompt.server.lua
-- The Potions stall now uses the same client-side zone-detection pattern as
-- the Skins/Cosmetics and Forge (Upgrade) stalls (see PotionsStall.client.lua
-- and UpgradeStall.client.lua). The "Press E" ProximityPrompt is no longer
-- desired here. This server script just ensures any ProximityPrompt parented
-- under a Potions stall is disabled so other clients can never see one,
-- including those placed in the .rbxl via Studio or left over from prior
-- versions of this file.

local Workspace = game:GetService("Workspace")

local STALL_NAMES = {
    PotionsStall = true,
    PotionStall = true,
    ["Potion Stall"] = true,
    ["Potions Stall"] = true,
    PotionShop = true,
    PotionsShop = true,
    ["Potion Shop"] = true,
    ["Potions Shop"] = true,
    PotionStand = true,
    PotionsStand = true,
    ["Potion Stand"] = true,
    ["Potions Stand"] = true,
    PotionVendor = true,
    PotionsVendor = true,
    PotionBooth = true,
    PotionsBooth = true,
    ["Potion Booth"] = true,
    ["Potions Booth"] = true,
    Potion = true,
    Potions = true,
}

local STALL_NAME_KEYWORDS = {
    "stall",
    "shop",
    "stand",
    "vendor",
    "booth",
}

local function isStallName(name)
    if STALL_NAMES[name] == true then
        return true
    end

    local lowerName = string.lower(tostring(name or ""))
    if string.find(lowerName, "potion", 1, true) == nil then
        return false
    end

    for _, keyword in ipairs(STALL_NAME_KEYWORDS) do
        if string.find(lowerName, keyword, 1, true) ~= nil then
            return true
        end
    end

    return false
end

local function isStallModel(instance)
    return instance and (instance:IsA("Model") or instance:IsA("Folder")) and isStallName(instance.Name)
end

local function containsPotionText(instance)
    local name = string.lower(tostring(instance and instance.Name or ""))
    if string.find(name, "potion", 1, true) ~= nil then
        return true
    end

    if instance and instance:IsA("ProximityPrompt") then
        local actionText = string.lower(tostring(instance.ActionText or ""))
        local objectText = string.lower(tostring(instance.ObjectText or ""))
        return string.find(actionText, "potion", 1, true) ~= nil
            or string.find(objectText, "potion", 1, true) ~= nil
    end

    return false
end

local function hasPotionStallAncestor(instance)
    local current = instance
    while current and current ~= Workspace do
        if isStallName(current.Name) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function disablePromptsUnder(stallModel)
    for _, descendant in ipairs(stallModel:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            descendant.Enabled = false
        end
    end

    stallModel.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") then
            descendant.Enabled = false
        end
    end)
end

local handled = setmetatable({}, { __mode = "k" })

local function handleStall(stallModel)
    if not isStallModel(stallModel) then return end
    if handled[stallModel] then return end
    handled[stallModel] = true
    disablePromptsUnder(stallModel)
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
    if isStallModel(descendant) then
        handleStall(descendant)
    end
end

Workspace.DescendantAdded:Connect(function(instance)
    if isStallModel(instance) then
        task.defer(handleStall, instance)
        return
    end

    if instance:IsA("ProximityPrompt") and (containsPotionText(instance) or hasPotionStallAncestor(instance)) then
        instance.Enabled = false
    end
end)
