local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionProductIds = require(ReplicatedStorage:WaitForChild("PotionProductIds"))

local PotionConfig = {}

PotionConfig.FirstPotionHotbarSlot = 4
PotionConfig.MaxEquippedPotions = 3
PotionConfig.SharedHotbarSlot = 4

local orderedPotions = {
    {
        Id = "health_potion",
        DisplayName = "Health Potion",
        Category = "Battle",
        Description = "",
        DetailText = "Restores 40 HP instantly",
        PriceCoins = 50,
        PriceRobux = 29,
        PurchaseQuantity = 3,
        StockPerRefresh = 5,
        RobuxProductId = PotionProductIds.HealthPotionRobuxProductId,
        Purchasable = true,
        IconKey = "HealthPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 245, 86, 86 },
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
        Description = "",
        DetailText = "+30% Movement Speed for 8s",
        PriceCoins = 50,
        PriceRobux = 29,
        PurchaseQuantity = 3,
        StockPerRefresh = 4,
        RobuxProductId = PotionProductIds.SpeedPotionRobuxProductId,
        Purchasable = true,
        IconKey = "SpeedPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 92, 229, 132 },
        HotbarLabel = "Speed",
        EffectType = "MovementSpeed",
        AdditiveBonus = 6,
        DurationSeconds = 8,
        CooldownSeconds = 60,
        ModifierId = "speed_potion",
        ShowInPotionsStall = true,
        SortOrder = -999,
    },
    {
        Id = "strength_potion",
        DisplayName = "Strength Potion",
        Category = "Battle",
        Description = "",
        DetailText = "+6 Melee Damage, +3 Ranged Damage for 10s",
        PriceCoins = 50,
        PriceRobux = 29,
        PurchaseQuantity = 3,
        StockPerRefresh = 4,
        RobuxProductId = PotionProductIds.StrengthPotionRobuxProductId,
        Purchasable = true,
        IconKey = "StrengthPotion",
        IconGlyph = "",
        BadgeText = "",
        IconColor = { 255, 140, 0 },
        HotbarLabel = "Strength",
        EffectType = "OutgoingDamageFlat",
        FlatDamageAdd = 6,
        RangedFlatDamageAdd = 3,
        SizeAdd = 2,
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

function PotionConfig.GetPurchaseQuantity(potionDefOrId)
    local potionDef = potionDefOrId
    if type(potionDefOrId) == "string" then
        potionDef = PotionConfig.GetById(potionDefOrId)
    end
    local qty = math.floor(tonumber(potionDef and potionDef.PurchaseQuantity) or 1)
    if qty < 1 then
        qty = 1
    end
    return qty
end

function PotionConfig.GetMaxEquippedPotions()
    return math.max(1, math.floor(tonumber(PotionConfig.MaxEquippedPotions) or 3))
end

function PotionConfig.GetFirstPotionHotbarSlot()
    return math.max(1, math.floor(tonumber(PotionConfig.FirstPotionHotbarSlot) or 4))
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