--------------------------------------------------------------------------------
-- AchievementDefs.lua  –  Shared achievement definitions (ReplicatedStorage)
-- Used by both server (AchievementService) and client (Achievements UI).
--
-- PHASE 1 OVERHAUL:
--   • Categories: Combat, Objectives, Economy, Progression, Special, Events
--   • Staged achievements: one line with multiple tier thresholds
--   • One-off achievements: single completion
--   • "First Blood" renamed to "First Strike" (alias kept for migration)
--
-- STRUCTURE:
--   staged = true  → thresholds = {t1, t2, ...}, rewards = {r1, r2, ...}
--   staged = false → target = N, reward = N  (one-off)
--
-- The server resolves the current visible stage from player data.
-- The client only sees one active stage at a time.
--------------------------------------------------------------------------------

local AchievementDefs = {}

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------
AchievementDefs.Categories = { "Combat", "Objectives", "Economy", "Progression", "Special", "Events" }

AchievementDefs.CategorySet = {}
for _, cat in ipairs(AchievementDefs.Categories) do
    AchievementDefs.CategorySet[cat] = true
end

--------------------------------------------------------------------------------
-- Achievement definitions
--
-- For staged achievements:
--   thresholds  = cumulative totals  (e.g. 25, 50, 100, 200, 500)
--   rewards     = coin reward per stage
--   titleFormat = "Name %s" where %s becomes Roman numeral (I, II, III...)
--   descFormat  = description with %d for current threshold
--
-- For one-off achievements:
--   target = number
--   reward = number
--------------------------------------------------------------------------------

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local STAGE_COIN_REWARDS = { 50, 75, 100, 200, 300, 500, 750, 1000, 2000, 5000 }
local STAGE_AP_REWARDS   = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }

local function copyStages(src, count)
    local out = {}
    for i = 1, count do
        out[i] = src[i]
    end
    return out
end

-- Stage V and X pay keys instead of coins.
local function copyCoinRewards(count)
    local out = copyStages(STAGE_COIN_REWARDS, count)
    if count >= 5 then
        out[5] = 0
    end
    if count >= 10 then
        out[10] = 0
    end
    return out
end

local function copyKeyRewards(count)
    local out = {}
    if count >= 5 then
        out[5] = 1
    end
    if count >= 10 then
        out[10] = 10
    end
    return out
end

AchievementDefs.Achievements = {
    ---------------------------------------------------------------------------
    -- COMBAT
    ---------------------------------------------------------------------------
    {
        id          = "goblin_hunter",
        category    = "Combat",
        staged      = true,
        stat        = "goblinElims",
        titleFormat = "Goblin Hunter %s",
        descFormat  = "Eliminate %d goblins.",
        thresholds  = { 10, 50, 125, 250, 500, 1000, 2500, 5000, 10000, 25000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "💀",
        hidden      = false,
    },
    {
        id          = "orc_raider",
        category    = "Combat",
        staged      = true,
        stat        = "orcElims",
        titleFormat = "Orc Raider %s",
        descFormat  = "Eliminate %d orcs.",
        thresholds  = { 5, 25, 75, 125, 250, 500, 1000, 2500, 5000, 10000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "💀",
        hidden      = false,
    },
    {
        id          = "ogre_slayer",
        category    = "Combat",
        staged      = true,
        stat        = "ogreElims",
        titleFormat = "Ogre Slayer %s",
        descFormat  = "Eliminate %d ogres.",
        thresholds  = { 1, 5, 15, 25, 50, 100, 200, 500, 1000, 2500 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "💀",
        hidden      = false,
    },
    {
        id          = "eliminator",
        category    = "Combat",
        staged      = true,
        stat        = "playerElims",
        titleFormat = "Eliminator %s",
        descFormat  = "Eliminate %d players.",
        thresholds  = { 10, 50, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🗡",
        hidden      = false,
    },
    {
        id          = "swordsman",
        category    = "Combat",
        staged      = true,
        stat        = "meleeDamage",
        titleFormat = "Swordsman %s",
        descFormat  = "Deal %d damage with melee weapons.",
        thresholds  = { 1000, 5000, 15000, 30000, 60000, 100000, 200000, 300000, 500000, 1000000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "⚔",
        hidden      = false,
    },
    {
        id          = "archer",
        category    = "Combat",
        staged      = true,
        stat        = "rangedDamage",
        titleFormat = "Archer %s",
        descFormat  = "Deal %d damage with ranged weapons.",
        thresholds  = { 1000, 5000, 15000, 30000, 60000, 100000, 200000, 300000, 500000, 1000000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🏹",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- ECONOMY
    ---------------------------------------------------------------------------
    {
        id          = "busy_earning",
        category    = "Economy",
        staged      = true,
        stat        = "totalCoinsEarned",
        titleFormat = "Busy Earning %s",
        descFormat  = "Earn %d total coins over time.",
        thresholds  = { 1000, 2000, 5000, 10000, 20000, 50000, 100000, 250000, 500000, 1000000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "💰",
        hidden      = false,
    },
    {
        id          = "blacksmith",
        category    = "Economy",
        staged      = true,
        stat        = "salvageEarnedFromRecycling",
        titleFormat = "Blacksmith %s",
        descFormat  = "Earn %d Shards by dismantling items.",
        thresholds  = { 100, 200, 300, 500, 1000, 2000, 3000, 4000, 5000, 10000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "◆",
        hidden      = false,
    },
    {
        id          = "weapon_supplier",
        category    = "Economy",
        staged      = true,
        stat        = "commonChestRolls",
        titleFormat = "Weapon Supplier %s",
        descFormat  = "Roll from a weapon chest %d times.",
        thresholds  = { 5, 25, 50, 75, 100, 150, 250, 500, 1000, 2000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "📦",
        hidden      = false,
    },
    {
        id          = "wheel_of_fortune",
        category    = "Economy",
        staged      = true,
        stat        = "spinWheelSpins",
        titleFormat = "Wheel of Fortune %s",
        descFormat  = "Spin the wheel %d times.",
        thresholds  = { 3, 10, 20, 30, 50, 75, 100, 250, 500, 1000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🎡",
        hidden      = false,
    },
    {
        id          = "locksmith",
        category    = "Economy",
        staged      = true,
        stat        = "keysCollected",
        titleFormat = "Locksmith %s",
        descFormat  = "Collect %d keys.",
        thresholds  = { 3, 5, 10, 25, 50, 75, 100, 250, 500, 1000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🔑",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- OBJECTIVES
    ---------------------------------------------------------------------------
    {
        id          = "capture_artist",
        category    = "Objectives",
        staged      = true,
        stat        = "flagCaptures",
        titleFormat = "Capture Artist %s",
        descFormat  = "Capture the flag %d times.",
        thresholds  = { 1, 5, 10, 25, 50, 100, 200, 500, 1000, 2000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "flag_defender",
        category    = "Objectives",
        staged      = true,
        stat        = "flagReturns",
        titleFormat = "Flag Defender %s",
        descFormat  = "Return the flag %d times.",
        thresholds  = { 1, 5, 10, 25, 50, 100, 200, 500, 1000, 2000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "flag_bearer",
        category    = "Objectives",
        staged      = true,
        stat        = "flagCarryTime",
        statScale   = 60, -- stored in seconds, displayed/thresholded in minutes
        titleFormat = "Flag Bearer %s",
        descFormat  = "Carry the enemy flag for %d total minutes.",
        thresholds  = { 5, 30, 60, 120, 240, 360, 480, 720, 1440, 2880 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🤲",
        hidden      = false,
    },
    {
        id          = "victorious",
        category    = "Objectives",
        staged      = true,
        stat        = "matchWins",
        titleFormat = "Victorious %s",
        descFormat  = "Win %d games.",
        thresholds  = { 1, 3, 5, 10, 20, 35, 50, 100, 250, 500 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🏆",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- PROGRESSION
    ---------------------------------------------------------------------------
    {
        id          = "daily_errand",
        category    = "Progression",
        staged      = true,
        stat        = "dailyQuestsCompleted",
        titleFormat = "Daily Errand %s",
        descFormat  = "Complete %d daily quests.",
        thresholds  = { 3, 6, 9, 15, 25, 50, 100, 200, 500, 1000 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "📋",
        hidden      = false,
    },
    {
        id          = "weekly_contract",
        category    = "Progression",
        staged      = true,
        stat        = "weeklyQuestsCompleted",
        titleFormat = "Weekly Contract %s",
        descFormat  = "Complete %d weekly quests.",
        thresholds  = { 3, 6, 9, 15, 24, 30, 50, 75, 100, 200 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "📅",
        hidden      = false,
    },
    {
        id          = "swordsman_training",
        category    = "Progression",
        staged      = true,
        stat        = "meleeUpgradeLevel",
        titleFormat = "Swordsman Training %s",
        descFormat  = "Reach Melee Upgrade Level %d.",
        thresholds  = { 5, 10, 15, 25, 35, 50, 75, 100, 250, 500 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "⚔",
        hidden      = false,
    },
    {
        id          = "archer_training",
        category    = "Progression",
        staged      = true,
        stat        = "rangedUpgradeLevel",
        titleFormat = "Archer Training %s",
        descFormat  = "Reach Ranged Upgrade Level %d.",
        thresholds  = { 5, 10, 15, 25, 35, 50, 75, 100, 250, 500 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🎯",
        hidden      = false,
    },
    {
        id          = "warrior_rank",
        category    = "Progression",
        staged      = true,
        stat        = "playerLevel",
        titleFormat = "Warrior Rank %s",
        descFormat  = "Reach level %d.",
        thresholds  = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 },
        rewards     = copyCoinRewards(10),
        keyRewards  = copyKeyRewards(10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "⭐",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- SPECIAL
    ---------------------------------------------------------------------------
    {
        id          = "untouchable",
        category    = "Special",
        staged      = false,
        stat        = "flawlessWins",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "Untouchable",
        desc        = "Win a match without being eliminated.",
        icon        = "🛡",
        hidden      = false,
    },
    {
        id          = "overachiever",
        category    = "Special",
        staged      = true,
        stat        = "achievementsCompleted",
        titleFormat = "Overachiever %s",
        descFormat  = "Complete %d achievements.",
        thresholds  = { 10, 20, 35, 50, 75 },
        rewards     = copyCoinRewards(5),
        keyRewards  = copyKeyRewards(5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "⭐",
        hidden      = false,
    },
    {
        id          = "jack_of_all_trades",
        category    = "Special",
        staged      = false,
        stat        = "categoriesWithCompletion",
        target      = 4,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "Jack of All Trades",
        desc        = "Complete at least 1 achievement in 4 different categories.",
        icon        = "🃏",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- EVENTS  (placeholder category — no active achievements yet)
    ---------------------------------------------------------------------------
}

--------------------------------------------------------------------------------
-- Roman numeral helper
--------------------------------------------------------------------------------
function AchievementDefs.GetRoman(stageIndex)
    return ROMAN[stageIndex] or tostring(stageIndex)
end

--------------------------------------------------------------------------------
-- Resolve display info for a staged achievement at a given stage index
--------------------------------------------------------------------------------
function AchievementDefs.GetStageTitle(def, stageIndex)
    if not def.staged then return def.title end
    -- Support custom per-stage titles when provided
    if def.stageTitles and def.stageTitles[stageIndex] then
        return def.stageTitles[stageIndex]
    end
    return string.format(def.titleFormat, ROMAN[stageIndex] or tostring(stageIndex))
end

function AchievementDefs.GetStageDesc(def, stageIndex)
    if not def.staged then return def.desc end
    local threshold = def.thresholds[stageIndex] or 0
    return string.format(def.descFormat, threshold)
end

function AchievementDefs.GetStageTarget(def, stageIndex)
    if not def.staged then return def.target end
    return def.thresholds[stageIndex] or 0
end

function AchievementDefs.GetStatScale(def)
    local scale = tonumber(def and def.statScale) or 1
    if scale < 1 then
        return 1
    end
    return scale
end

function AchievementDefs.GetRawTarget(def, stageIndex)
    return (AchievementDefs.GetStageTarget(def, stageIndex) or 0) * AchievementDefs.GetStatScale(def)
end

function AchievementDefs.GetDisplayStat(def, rawValue)
    local scale = AchievementDefs.GetStatScale(def)
    return math.floor((tonumber(rawValue) or 0) / scale)
end

function AchievementDefs.GetStageReward(def, stageIndex)
    if not def.staged then return def.reward end
    return def.rewards[stageIndex] or 0
end

function AchievementDefs.GetStageKeyReward(def, stageIndex)
    if not def then
        return 0
    end
    local keys = def.keyRewards
    if type(keys) == "number" then
        return math.max(0, math.floor(keys))
    end
    if type(keys) ~= "table" then
        return tonumber(def.keyReward) or 0
    end
    if not def.staged then
        return tonumber(keys[1] or keys) or 0
    end
    return tonumber(keys[stageIndex]) or 0
end

function AchievementDefs.GetStageCurrencyReward(def, stageIndex)
    local keyAmount = AchievementDefs.GetStageKeyReward(def, stageIndex)
    if keyAmount > 0 then
        return keyAmount, "keys"
    end
    return tonumber(AchievementDefs.GetStageReward(def, stageIndex)) or 0, "coins"
end

function AchievementDefs.GetStageAP(def, stageIndex)
    if not def.staged then return tonumber(def.achievementPoints) or 0 end
    if type(def.achievementPoints) == "table" then
        return def.achievementPoints[stageIndex] or 0
    end
    return 0
end

function AchievementDefs.GetMaxStage(def)
    if not def.staged then return 1 end
    return #def.thresholds
end

--- Check if a staged line is fully maxed at the given stage index.
function AchievementDefs.IsMaxedOut(def, stageIndex)
    if not def.staged then return stageIndex >= 1 end
    return stageIndex > #def.thresholds
end

--------------------------------------------------------------------------------
-- Quick lookup by id
--------------------------------------------------------------------------------
AchievementDefs.ById = {}
for _, def in ipairs(AchievementDefs.Achievements) do
    AchievementDefs.ById[def.id] = def
end

-- Migration aliases for renamed ids (deleted achievements are dropped on merge)
AchievementDefs.IdAliases = {
    player_slayer        = "eliminator",
    flag_capturer        = "capture_artist",
    banner_guardian      = "flag_defender",
    flag_returner        = "flag_defender",
    safe_hands           = "flag_bearer",
    coin_collector       = "busy_earning",
    salvage_specialist   = "blacksmith",
    daily_devotion       = "daily_errand",
    weekly_warrior       = "weekly_contract",
    close_quarters       = "swordsman_training",
    deadeye              = "archer_training",
}

--- Resolve an id that may be an old alias to the canonical id
function AchievementDefs.ResolveId(rawId)
    return AchievementDefs.IdAliases[rawId] or rawId
end

--------------------------------------------------------------------------------
-- Category helpers
--------------------------------------------------------------------------------

--- Get all achievement defs in a category
function AchievementDefs.GetByCategory(category)
    local result = {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        if def.category == category then
            table.insert(result, def)
        end
    end
    return result
end

return AchievementDefs
