local PotionConfig = {}

PotionConfig.SharedHotbarSlot = 4

local orderedPotions = {
    {
        Id = "health_potion",
        DisplayName = "Health Potion",
        Description = "Equip it to slot 4 to drink it for an instant heal.",
        DetailText = "Restores 40 HP instantly",
        IconGlyph = "HP",
        BadgeText = "HP",
        IconColor = { 103, 186, 255 },
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
        Description = "Equip it to slot 4 to gain +6 movement speed for 5 seconds.",
        DetailText = "+6 Move Speed for 5s",
        IconGlyph = "SPD",
        BadgeText = "SPD",
        IconColor = { 136, 255, 190 },
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