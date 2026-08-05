local ItemIconRegistry = {}

local iconsByKey = {}

local function register(key, data)
    if type(key) ~= "string" or key == "" or type(data) ~= "table" then
        return
    end
    iconsByKey[key] = data
end

-- Health potion: use a direct asset key so UIs render a simple image instead
local healthPotionIcon = {
    Key = "HealthPotion",
    AssetKey = "HealthPotion",
}

local speedPotionIcon = {
    Key = "SpeedPotion",
    Kind = "PotionBottle",
    IconColor = { 92, 229, 132 },
    GlassColor = { 220, 255, 232 },
    LiquidColor = { 52, 206, 104 },
    StrokeColor = { 28, 112, 67 },
    CapColor = { 42, 112, 73 },
    Motif = "speed",
}

local strengthPotionIcon = {
    Key = "StrengthPotion",
    Kind = "PotionBottle",
    IconColor = { 255, 140, 0 },
    GlassColor = { 255, 240, 220 },
    LiquidColor = { 230, 110, 20 },
    StrokeColor = { 150, 70, 20 },
    CapColor = { 140, 65, 20 },
    Motif = "strength",
}

-- Elixir bottles: same procedurally-drawn style as Battle potions, but with
-- `Shape = "elixir"` so the body renders as a rounded bulb (fantasy flask)
-- instead of the squarish Battle-potion bottle.
local doubleCoinsIcon = {
    Key = "DoubleCoins",
    Kind = "PotionBottle",
    Shape = "elixir",
    IconColor = { 255, 200, 40 },
    GlassColor = { 255, 244, 200 },
    LiquidColor = { 255, 196, 48 },
    StrokeColor = { 120, 80, 24 },
    CapColor = { 132, 88, 32 },
    Motif = "coins_elixir",
}

local doubleXPIcon = {
    Key = "DoubleXP",
    Kind = "PotionBottle",
    Shape = "elixir",
    IconColor = { 180, 120, 255 },
    GlassColor = { 232, 220, 255 },
    LiquidColor = { 168, 110, 240 },
    StrokeColor = { 70, 40, 130 },
    CapColor = { 82, 52, 138 },
    Motif = "xp_elixir",
}

local doubleMasteryIcon = {
    Key = "DoubleMastery",
    Kind = "PotionBottle",
    Shape = "elixir",
    IconColor = { 180, 120, 255 },
    GlassColor = { 232, 220, 255 },
    LiquidColor = { 168, 110, 240 },
    StrokeColor = { 70, 40, 130 },
    CapColor = { 82, 52, 138 },
    Motif = "mastery_elixir",
}

local doubleXPIconBlue = {
    Key = "DoubleXPBlue",
    Kind = "PotionBottle",
    Shape = "elixir",
    IconColor = { 80, 165, 255 },
    GlassColor = { 220, 240, 255 },
    LiquidColor = { 60, 140, 255 },
    StrokeColor = { 30, 70, 120 },
    CapColor = { 40, 85, 140 },
    Motif = "xp_elixir",
}

register("HealthPotion", healthPotionIcon)
register("health_potion", healthPotionIcon)
register("SpeedPotion", speedPotionIcon)
register("speed_potion", speedPotionIcon)
register("StrengthPotion", strengthPotionIcon)
register("strength_potion", strengthPotionIcon)
register("DoubleCoins", doubleCoinsIcon)
register("coins_2x", doubleCoinsIcon)
register("DoubleXP", doubleXPIcon)
register("mastery_2x", doubleMasteryIcon)
register("xp_2x", doubleXPIconBlue)
local powerElixirIcon = {
    Key = "PowerElixir",
    AssetKey = "PowerElixir",
}
local vitalityElixirIcon = {
    Key = "VitalityElixir",
    AssetKey = "VitalityElixir",
}

register("PowerElixir", powerElixirIcon)
register("power_elixir", powerElixirIcon)
register("VitalityElixir", vitalityElixirIcon)
register("vitality_elixir", vitalityElixirIcon)

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = nestedValue
    end
    return copy
end

function ItemIconRegistry.Get(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end

    local data = iconsByKey[key]
    if type(data) ~= "table" then
        return nil
    end

    local copy = {}
    for dataKey, value in pairs(data) do
        copy[dataKey] = copyValue(value)
    end
    return copy
end

return ItemIconRegistry
