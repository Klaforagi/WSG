local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionProductIds = require(ReplicatedStorage:WaitForChild("PotionProductIds"))

local PotionConfig = {}

PotionConfig.SharedHotbarSlot = 4

local orderedPotions = {
    {
        Id = "health_potion",
        DisplayName = "Health Potion",
        Category = "Battle",
        Description = "Equip it to slot 4 to drink it for an instant heal.",
        DetailText = "Restores 40 HP instantly",
        PriceCoins = 25,
        PriceRobux = 5,
        RobuxProductId = PotionProductIds.HealthPotionRobuxProductId,
        Purchasable = true,
        IconKey = "HealthPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 245, 86, 86 },
        HotbarSlot = 4,
        HotbarLabel = "Health",
        EffectType = "Heal",
        HealAmount = 40,
        CooldownSeconds = 20,
        ShowInPotionsStall = true,
        SortOrder = -1000,
    },
    {
        Id = "speed_potion",
        DisplayName = "Speed Potion",
        Category = "Battle",
        Description = "Equip it to slot 4 to gain +6 movement speed for 5 seconds.",
        DetailText = "+6 Move Speed for 5s",
        PriceCoins = 30,
        PriceRobux = 7,
        RobuxProductId = PotionProductIds.SpeedPotionRobuxProductId,
        Purchasable = true,
        IconKey = "SpeedPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 92, 229, 132 },
        HotbarSlot = 4,
        HotbarLabel = "Speed",
        EffectType = "MovementSpeed",
        AdditiveBonus = 6,
        DurationSeconds = 5,
        CooldownSeconds = 60,
        ModifierId = "speed_potion",
        ShowInPotionsStall = true,
        SortOrder = -999,
    },
    {
        Id = "strength_potion",
        DisplayName = "Strength Potion",
        Category = "Battle",
        Description = "Increase all damage dealt by 20% for 10 seconds.",
        DetailText = "+20% Damage for 10s",
        PriceCoins = 45,
        PriceRobux = 9,
        RobuxProductId = PotionProductIds.StrengthPotionRobuxProductId,
        Purchasable = true,
        IconKey = "StrengthPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 255, 140, 0 },
        HotbarSlot = 4,
        HotbarLabel = "Strength",
        EffectType = "OutgoingDamageMultiplier",
        DamageMultiplier = 1.2,
        DurationSeconds = 10,
        CooldownSeconds = 60,
        ModifierId = "strength_potion",
        ShowInPotionsStall = true,
        SortOrder = -998,
    },
}

local potionsById = {}
for _, potionDef in ipairs(orderedPotions) do
    potionsById[potionDef.Id] = potionDef
end

PotionConfig.Potions = orderedPotions

function PotionConfig.GetById(potionId)
    return potionsById[potionId]
end

function PotionConfig.GetOrderedPotions()
    local copy = {}
    for _, potionDef in ipairs(orderedPotions) do
        table.insert(copy, potionDef)
    end
    return copy
end

function PotionConfig.GetRobuxProductId(potionDefOrId)
    local potionDef = potionDefOrId
    if type(potionDefOrId) == "string" then
        potionDef = PotionConfig.GetById(potionDefOrId)
    end
    if type(potionDef) ~= "table" then
        return 0
    end
    return math.max(0, math.floor(tonumber(potionDef.RobuxProductId) or 0))
end

function PotionConfig.IsRobuxPurchasable(potionDefOrId)
    return PotionConfig.GetRobuxProductId(potionDefOrId) > 0
end

function PotionConfig.ShouldShowInPotionsStall(potionDefOrId)
    local potionDef = potionDefOrId
    if type(potionDefOrId) == "string" then
        potionDef = PotionConfig.GetById(potionDefOrId)
    end
    if type(potionDef) ~= "table" then
        return false
    end
    if potionDef.Hidden == true or potionDef.Visible == false or potionDef.RemovedFromShop == true then
        return false
    end
    return potionDef.ShowInPotionsStall == true
end

function PotionConfig.GetStallPotions()
    local copy = {}
    for _, potionDef in ipairs(orderedPotions) do
        if PotionConfig.ShouldShowInPotionsStall(potionDef) then
            table.insert(copy, potionDef)
        end
    end
    return copy
end

return PotionConfig