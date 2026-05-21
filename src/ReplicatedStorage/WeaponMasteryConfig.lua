--------------------------------------------------------------------------------
-- WeaponMasteryConfig.lua
-- Shared thresholds, point values, and automatic damage bonuses for
-- per-weapon-name weapon mastery.
--------------------------------------------------------------------------------

local WeaponMasteryConfig = {}

WeaponMasteryConfig.Levels = {
    { Level = 1,  XP = 0,     Title = "I",    RomanNumeral = "I",    DamageBonus = 0.0 },
    { Level = 2,  XP = 25,    Title = "II",   RomanNumeral = "II",   DamageBonus = 0.5 },
    { Level = 3,  XP = 75,    Title = "III",  RomanNumeral = "III",  DamageBonus = 1.0 },
    { Level = 4,  XP = 250,   Title = "IV",   RomanNumeral = "IV",   DamageBonus = 1.5 },
    { Level = 5,  XP = 500,   Title = "V",    RomanNumeral = "V",    DamageBonus = 2.0 },
    { Level = 6,  XP = 1000,  Title = "VI",   RomanNumeral = "VI",   DamageBonus = 2.5 },
    { Level = 7,  XP = 2000,  Title = "VII",  RomanNumeral = "VII",  DamageBonus = 3.0 },
    { Level = 8,  XP = 4000,  Title = "VIII", RomanNumeral = "VIII", DamageBonus = 3.5 },
    { Level = 9,  XP = 7000,  Title = "IX",   RomanNumeral = "IX",   DamageBonus = 4.0 },
    { Level = 10, XP = 10000, Title = "X",    RomanNumeral = "X",    DamageBonus = 5.0 },
}

WeaponMasteryConfig.XP = {
    PlayerElimination = 10,
    MobKill = 2,
    FlagCapture = 25,
    DamagePer100 = 1,
}

WeaponMasteryConfig.MaxLevel = WeaponMasteryConfig.Levels[#WeaponMasteryConfig.Levels].Level

function WeaponMasteryConfig.GetLevelDef(level)
    level = math.floor(tonumber(level) or 1)
    for _, def in ipairs(WeaponMasteryConfig.Levels) do
        if def.Level == level then
            return def
        end
    end
    return WeaponMasteryConfig.Levels[1]
end

function WeaponMasteryConfig.GetRomanNumeral(level)
    local def = WeaponMasteryConfig.GetLevelDef(level)
    return (def and def.RomanNumeral) or (def and def.Title) or "I"
end

function WeaponMasteryConfig.GetDamageBonus(level)
    local def = WeaponMasteryConfig.GetLevelDef(level)
    return tonumber(def and def.DamageBonus) or 0
end

function WeaponMasteryConfig.GetLevelForXP(xp)
    xp = math.max(0, math.floor(tonumber(xp) or 0))
    local level = 1
    for _, def in ipairs(WeaponMasteryConfig.Levels) do
        if xp >= def.XP then
            level = def.Level
        else
            break
        end
    end
    return level
end

function WeaponMasteryConfig.GetNextLevelDef(level)
    level = math.floor(tonumber(level) or 1)
    for _, def in ipairs(WeaponMasteryConfig.Levels) do
        if def.Level > level then
            return def
        end
    end
    return nil
end

function WeaponMasteryConfig.GetReward(level)
    local def = WeaponMasteryConfig.GetLevelDef(level)
    return def and def.Reward or nil
end

function WeaponMasteryConfig.GetProgressForXP(xp)
    xp = math.max(0, math.floor(tonumber(xp) or 0))
    local level = WeaponMasteryConfig.GetLevelForXP(xp)
    local currentDef = WeaponMasteryConfig.GetLevelDef(level)
    local nextDef = WeaponMasteryConfig.GetNextLevelDef(level)

    if not nextDef then
        return {
            level = level,
            currentLevelXP = currentDef.XP,
            nextLevelXP = currentDef.XP,
            progress = 1,
            maxed = true,
        }
    end

    local span = math.max(1, nextDef.XP - currentDef.XP)
    return {
        level = level,
        currentLevelXP = currentDef.XP,
        nextLevelXP = nextDef.XP,
        nextLevel = nextDef.Level,
        progress = math.clamp((xp - currentDef.XP) / span, 0, 1),
        maxed = false,
    }
end

return WeaponMasteryConfig