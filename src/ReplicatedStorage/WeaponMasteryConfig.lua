--------------------------------------------------------------------------------
-- WeaponMasteryConfig.lua
-- Shared thresholds, point values, and milestone rewards for per-instance
-- weapon mastery.
--------------------------------------------------------------------------------

local WeaponMasteryConfig = {}

WeaponMasteryConfig.Levels = {
    { Level = 1, XP = 0,   Title = "Fresh" },
    { Level = 2, XP = 25,  Title = "Practiced",    Reward = { Coins = 20 } },
    { Level = 3, XP = 75,  Title = "Battle-Tested", Reward = { Salvage = 15 } },
    { Level = 4, XP = 150, Title = "Veteran",      Reward = { Coins = 50, Salvage = 25 } },
    { Level = 5, XP = 300, Title = "Mastered",     Reward = { Coins = 100, Salvage = 50 } },
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