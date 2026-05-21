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

return PotionConfig