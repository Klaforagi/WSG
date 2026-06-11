--------------------------------------------------------------------------------
-- WeaponMasteryConfig.lua
-- Shared rarity-based mastery progression for per-weapon-name weapon mastery.
--
-- Mastery levels now include a NIL tier (level 0). XP thresholds depend on
-- rarity, and weapon damage is resolved as a base stat by rarity + mastery
-- level instead of as a late-applied bonus.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponMasteryConfig = {}

local XP_PRECISION_SCALE = 10
local DAMAGE_PRECISION_SCALE = 1000

local function normalizeNumber(value, precisionScale)
    value = math.max(0, tonumber(value) or 0)
    precisionScale = math.max(1, tonumber(precisionScale) or 1)
    return math.round(value * precisionScale) / precisionScale
end

local function trimString(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function normalizeKey(value)
    return string.lower(trimString(tostring(value or "")))
end

local function canonicalizeRarity(rarity)
    local key = normalizeKey(rarity)
    if key == "legendary" then return "Legendary" end
    if key == "epic" then return "Epic" end
    if key == "rare" then return "Rare" end
    if key == "uncommon" then return "Uncommon" end
    return "Common"
end

local function canonicalizeCategory(category)
    local key = normalizeKey(category)
    if key == "ranged" then
        return "Ranged"
    end
    return "Melee"
end

local function copyTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function halveDamageTable(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = normalizeNumber((tonumber(value) or 0) / 2, DAMAGE_PRECISION_SCALE)
    end
    return result
end

local function buildRarityData(xpThresholds, meleeDamages)
    return {
        xp = copyTable(xpThresholds),
        damages = {
            Melee = copyTable(meleeDamages),
            Ranged = halveDamageTable(meleeDamages),
        },
    }
end

local function buildWeaponMetaCache()
    local cache = {}
    local ok, crateConfig = pcall(function()
        local mod = ReplicatedStorage:WaitForChild("CrateConfig", 10)
        if mod and mod:IsA("ModuleScript") then
            return require(mod)
        end
        return nil
    end)
    if ok and type(crateConfig) == "table" and type(crateConfig.WeaponsByRarity) == "table" then
        for rarity, list in pairs(crateConfig.WeaponsByRarity) do
            if type(list) == "table" then
                local normalizedRarity = canonicalizeRarity(rarity)
                for _, entry in ipairs(list) do
                    if type(entry) == "table" and type(entry.weapon) == "string" and entry.weapon ~= "" then
                        cache[normalizeKey(entry.weapon)] = {
                            rarity = normalizedRarity,
                            category = canonicalizeCategory(entry.category),
                        }
                    end
                end
            end
        end
    end
    return cache
end

local weaponMetaCache = nil

local function getWeaponMeta(weaponName)
    if not weaponMetaCache then
        weaponMetaCache = buildWeaponMetaCache()
    end
    local meta = weaponMetaCache[normalizeKey(weaponName)]
    if meta then
        return {
            rarity = meta.rarity,
            category = meta.category,
        }
    end
    return {
        rarity = "Common",
        category = "Melee",
    }
end

local function clampLevel(level)
    level = math.floor(tonumber(level) or 0)
    return math.clamp(level, 0, WeaponMasteryConfig.MaxLevel)
end

local function getRarityData(rarity)
    local key = canonicalizeRarity(rarity)
    return WeaponMasteryConfig.Progression[key] or WeaponMasteryConfig.Progression.Common
end

WeaponMasteryConfig.MaxLevel = 10
WeaponMasteryConfig.Levels = {
    { Level = 0, RomanNumeral = "NIL", Title = "NIL" },
    { Level = 1, RomanNumeral = "I",   Title = "I"   },
    { Level = 2, RomanNumeral = "II",  Title = "II"  },
    { Level = 3, RomanNumeral = "III", Title = "III" },
    { Level = 4, RomanNumeral = "IV",  Title = "IV"  },
    { Level = 5, RomanNumeral = "V",   Title = "V"   },
    { Level = 6, RomanNumeral = "VI",  Title = "VI"  },
    { Level = 7, RomanNumeral = "VII", Title = "VII" },
    { Level = 8, RomanNumeral = "VIII",Title = "VIII"},
    { Level = 9, RomanNumeral = "IX",   Title = "IX"  },
    { Level = 10, RomanNumeral = "X",   Title = "X"   },
}

WeaponMasteryConfig.Progression = {
    Common = buildRarityData(
        { 0, 200, 400, 600, 1000, 1400, 1800, 2500, 3200, 3900, 5000 },
        { 7, 7.5, 8, 8.5, 9.25, 10, 10.75, 11.65, 12.55, 13.45, 14 }
    ),
    Uncommon = buildRarityData(
        { 0, 400, 800, 1200, 2000, 2800, 3600, 5000, 6400, 7800, 10000 },
        { 8, 8.5, 9, 9.5, 10.4, 11.3, 12.2, 13.4, 14.6, 15.8, 17 }
    ),
    Rare = buildRarityData(
        { 0, 800, 1600, 2400, 4000, 5600, 7200, 10000, 12800, 15600, 20000 },
        { 9, 9.6, 10.2, 10.8, 11.8, 12.8, 13.8, 15.2, 16.6, 18, 20 }
    ),
    Epic = buildRarityData(
        { 0, 1600, 3200, 4800, 8000, 11200, 14400, 20000, 25600, 31200, 40000 },
        { 10, 10.8, 11.6, 12.4, 13.6, 14.8, 16, 18.2, 20.4, 22.6, 25 }
    ),
    Legendary = buildRarityData(
        { 0, 3000, 6000, 9000, 15000, 21000, 27000, 37500, 48000, 58500, 75000 },
        { 12, 12.5, 13, 13.5, 15, 17.5, 19, 21, 23, 26, 30 }
    ),
}

WeaponMasteryConfig.XP = {
    Hit = 0.3,
    PlayerElimination = 10,
    GoblinKill = 3,
    OrcKill = 7,
    OgreKill = 20,
}

function WeaponMasteryConfig.NormalizeRarity(rarity)
    return canonicalizeRarity(rarity)
end

function WeaponMasteryConfig.NormalizeCategory(category)
    return canonicalizeCategory(category)
end

function WeaponMasteryConfig.GetWeaponMeta(weaponName)
    return getWeaponMeta(weaponName)
end

function WeaponMasteryConfig.GetLevelDef(level, rarity, category)
    local numericLevel = clampLevel(level)
    local progression = getRarityData(rarity)
    local normalizedCategory = canonicalizeCategory(category)
    local index = numericLevel + 1
    local row = WeaponMasteryConfig.Levels[index] or WeaponMasteryConfig.Levels[1]
    local damageTables = progression and progression.damages
    local damageTable = damageTables and damageTables[normalizedCategory]
    if type(damageTable) ~= "table" then
        damageTable = damageTables and damageTables.Melee or nil
    end
    local xpTable = progression and progression.xp or nil

    return {
        Level = row.Level,
        XP = (type(xpTable) == "table" and xpTable[index]) or 0,
        Title = row.Title,
        RomanNumeral = row.RomanNumeral,
        Damage = (type(damageTable) == "table" and (damageTable[index] or damageTable[1])) or 0,
        Rarity = canonicalizeRarity(rarity),
        Category = normalizedCategory,
    }
end

function WeaponMasteryConfig.GetRomanNumeral(level)
    local def = WeaponMasteryConfig.GetLevelDef(level)
    return (def and def.RomanNumeral) or (def and def.Title) or "NIL"
end

function WeaponMasteryConfig.GetLevelForXP(xp, rarity)
    xp = normalizeNumber(xp, XP_PRECISION_SCALE)
    local progression = getRarityData(rarity)
    local level = 0
    for index, threshold in ipairs(progression.xp) do
        local candidate = index - 1
        if xp >= threshold then
            level = candidate
        else
            break
        end
    end
    return level
end

function WeaponMasteryConfig.GetNextLevelDef(level, rarity, category)
    local nextLevel = clampLevel(level) + 1
    if nextLevel > WeaponMasteryConfig.MaxLevel then
        return nil
    end
    return WeaponMasteryConfig.GetLevelDef(nextLevel, rarity, category)
end

function WeaponMasteryConfig.GetDamageForLevel(level, rarity, category)
    local progression = getRarityData(rarity)
    local normalizedCategory = canonicalizeCategory(category)
    local damages = progression.damages[normalizedCategory] or progression.damages.Melee
    local index = clampLevel(level) + 1
    return normalizeNumber(damages[index] or damages[1] or 0, DAMAGE_PRECISION_SCALE)
end

function WeaponMasteryConfig.GetDamageForXP(xp, rarity, category)
    local level = WeaponMasteryConfig.GetLevelForXP(xp, rarity)
    return WeaponMasteryConfig.GetDamageForLevel(level, rarity, category)
end

function WeaponMasteryConfig.GetDamageBonus(level, rarity, category)
    local currentDamage = WeaponMasteryConfig.GetDamageForLevel(level, rarity, category)
    local nilDamage = WeaponMasteryConfig.GetDamageForLevel(0, rarity, category)
    return math.max(0, normalizeNumber(currentDamage - nilDamage, DAMAGE_PRECISION_SCALE))
end

function WeaponMasteryConfig.GetProgressForXP(xp, rarity, category)
    xp = normalizeNumber(xp, XP_PRECISION_SCALE)
    local normalizedRarity = canonicalizeRarity(rarity)
    local normalizedCategory = canonicalizeCategory(category)
    local progression = getRarityData(normalizedRarity)
    local level = WeaponMasteryConfig.GetLevelForXP(xp, normalizedRarity)
    local currentDef = WeaponMasteryConfig.GetLevelDef(level, rarity, category)
    local nextDef = WeaponMasteryConfig.GetNextLevelDef(level, rarity, category)
    local currentDamage = WeaponMasteryConfig.GetDamageForLevel(level, normalizedRarity, normalizedCategory)
    local nilDamage = WeaponMasteryConfig.GetDamageForLevel(0, normalizedRarity, normalizedCategory)

    if not nextDef then
        return {
            level = level,
            currentLevelXP = progression.xp[#progression.xp] or 0,
            nextLevelXP = progression.xp[#progression.xp] or 0,
            nextLevel = nil,
            progress = 1,
            maxed = true,
            currentDamage = currentDamage,
            nextDamage = currentDamage,
            nilDamage = nilDamage,
        }
    end

    local currentLevelXP = currentDef.XP or 0
    local nextLevelXP = nextDef.XP or currentLevelXP
    local span = math.max(1, nextLevelXP - currentLevelXP)

    return {
        level = level,
        currentLevelXP = currentLevelXP,
        nextLevelXP = nextLevelXP,
        nextLevel = nextDef.Level,
        progress = math.clamp((xp - currentLevelXP) / span, 0, 1),
        maxed = false,
        currentDamage = currentDamage,
        nextDamage = WeaponMasteryConfig.GetDamageForLevel(nextDef.Level, normalizedRarity, normalizedCategory),
        nilDamage = nilDamage,
    }
end

function WeaponMasteryConfig.GetReward(level)
    local def = WeaponMasteryConfig.GetLevelDef(level)
    return def and def.Reward or nil
end

return WeaponMasteryConfig