local ItemIconRegistry = {}

local iconsByKey = {}

local function register(key, data)
    if type(key) ~= "string" or key == "" or type(data) ~= "table" then
        return
    end
    iconsByKey[key] = data
end

local healthPotionIcon = {
    Key = "HealthPotion",
    Kind = "PotionBottle",
    IconColor = { 245, 86, 86 },
    GlassColor = { 255, 225, 225 },
    LiquidColor = { 222, 63, 67 },
    StrokeColor = { 118, 38, 44 },
    CapColor = { 104, 48, 58 },
    Motif = "health",
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
    IconColor = { 235, 72, 55 },
    GlassColor = { 255, 226, 218 },
    LiquidColor = { 215, 48, 42 },
    StrokeColor = { 120, 32, 32 },
    CapColor = { 103, 45, 35 },
    Motif = "strength",
}

local doubleCoinsIcon = {
    Key = "DoubleCoins",
    AssetKey = "Coin",
    IconColor = { 255, 200, 40 },
    Glyph = "$",
}

local doubleXPIcon = {
    Key = "DoubleXP",
    AssetKey = "XP",
    IconColor = { 180, 120, 255 },
    Glyph = "XP",
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
register("xp_2x", doubleXPIcon)

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
