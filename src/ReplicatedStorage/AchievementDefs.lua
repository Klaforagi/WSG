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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 10),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 10),
        icon        = "🏹",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- ECONOMY
    ---------------------------------------------------------------------------
    {
        id          = "coin_collector",
        category    = "Economy",
        staged      = true,
        stat        = "totalCoinsEarned",
        titleFormat = "Coin Collector %s",
        descFormat  = "Earn %d total coins over time.",
        thresholds  = { 100, 250, 500, 1000, 2500 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "💰",
        hidden      = false,
    },
    {
        id          = "first_purchase",
        category    = "Economy",
        staged      = false,
        stat        = "totalPurchases",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "First Purchase",
        desc        = "Buy your first item from the shop.",
        icon        = "🛒",
        hidden      = false,
    },
    {
        id          = "big_spender",
        category    = "Economy",
        staged      = true,
        stat        = "totalCoinsSpent",
        titleFormat = "Big Spender %s",
        descFormat  = "Spend %d total coins in the shop.",
        thresholds  = { 250, 500, 1000, 2500, 5000 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "💸",
        hidden      = false,
    },
    {
        id          = "collector",
        category    = "Economy",
        staged      = true,
        stat        = "itemsOwned",
        titleFormat = "Collector %s",
        descFormat  = "Own %d unlockable items.",
        thresholds  = { 5, 10, 15, 25, 40 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🎒",
        hidden      = false,
    },
    {
        id          = "salvage_specialist",
        category    = "Economy",
        staged      = true,
        stat        = "salvageEarnedFromRecycling",
        titleFormat = "Dismantle Specialist %s",
        descFormat  = "Earn %d Shards by dismantling items.",
        thresholds  = { 100, 500, 1500, 5000 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 4),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 4),
        icon        = "◆",
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
        thresholds  = { 3, 10, 25, 50, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "banner_guardian",
        category    = "Objectives",
        staged      = true,
        stat        = "flagReturns",
        titleFormat = "Banner Guardian %s",
        descFormat  = "Return the flag %d times.",
        thresholds  = { 3, 10, 25, 50, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "first_capture",
        category    = "Objectives",
        staged      = false,
        stat        = "flagCaptures",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "First Capture",
        desc        = "Capture the flag for the first time.",
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "first_return",
        category    = "Objectives",
        staged      = false,
        stat        = "flagReturns",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "First Return",
        desc        = "Return your team's flag for the first time.",
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "flag_bearer",
        category    = "Objectives",
        staged      = true,
        stat        = "flagCarryTime",
        titleFormat = "Flag Bearer %s",
        descFormat  = "Carry the enemy flag for %d total seconds.",
        thresholds  = { 120, 300, 600, 1200, 2400 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🤲",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- PROGRESSION
    ---------------------------------------------------------------------------
    {
        id          = "dedicated_fighter",
        category    = "Progression",
        staged      = true,
        stat        = "matchesPlayed",
        titleFormat = "Dedicated Fighter %s",
        descFormat  = "Play %d matches.",
        thresholds  = { 5, 15, 30, 60, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🏟",
        hidden      = false,
    },
    {
        id          = "loyal_soldier",
        category    = "Progression",
        staged      = true,
        stat        = "consecutiveLogins",
        titleFormat = "Loyal Soldier %s",
        descFormat  = "Log in for %d consecutive days.",
        thresholds  = { 7, 14, 30, 60, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "📅",
        hidden      = false,
    },
    {
        id          = "first_victory",
        category    = "Progression",
        staged      = false,
        stat        = "matchWins",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "First Victory",
        desc        = "Get your first match win.",
        icon        = "🏆",
        hidden      = false,
    },
    {
        id          = "battle_victor",
        category    = "Progression",
        staged      = true,
        stat        = "matchWins",
        titleFormat = "Battle Victor %s",
        descFormat  = "Win %d matches.",
        thresholds  = { 5, 15, 30, 60, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🏆",
        hidden      = false,
    },
    {
        id          = "battle_tested",
        category    = "Progression",
        staged      = true,
        stat        = "matchMinutes",
        titleFormat = "Battle Tested %s",
        descFormat  = "Spend %d total minutes in matches.",
        thresholds  = { 60, 180, 360, 720, 1440 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "⏱",
        hidden      = false,
    },
    {
        id          = "daily_devotion",
        category    = "Progression",
        staged      = true,
        stat        = "dailyQuestsCompleted",
        titleFormat = "Daily Devotion %s",
        descFormat  = "Complete %d daily quests.",
        thresholds  = { 10, 25, 50, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 4),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 4),
        icon        = "📋",
        hidden      = false,
    },
    {
        id          = "weekly_warrior",
        category    = "Progression",
        staged      = true,
        stat        = "weeklyQuestsCompleted",
        titleFormat = "Weekly Warrior %s",
        descFormat  = "Complete %d weekly quests.",
        thresholds  = { 5, 15, 30, 60 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 4),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 4),
        icon        = "📅",
        hidden      = false,
    },
    {
        id          = "event_challenger",
        category    = "Progression",
        staged      = true,
        stat        = "eventQuestsCompleted",
        titleFormat = "Event Challenger %s",
        descFormat  = "Complete %d event quests.",
        thresholds  = { 5, 15, 30, 50 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 4),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 4),
        icon        = "🎉",
        hidden      = false,
    },
    {
        id          = "welcome_to_the_front",
        category    = "Progression",
        staged      = false,
        stat        = "matchesPlayed",
        target      = 1,
        reward      = STAGE_COIN_REWARDS[1],
        achievementPoints = STAGE_AP_REWARDS[1],
        title       = "Welcome to the Front",
        desc        = "Complete your first match.",
        icon        = "👋",
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
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
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
    -- PROGRESSION (continued) — Upgrade Milestones
    ---------------------------------------------------------------------------
    {
        id          = "close_quarters",
        category    = "Progression",
        staged      = true,
        stat        = "meleeUpgradeLevel",
        titleFormat = "Close Quarters %s",
        descFormat  = "Reach Melee Upgrade Level %d.",
        thresholds  = { 5, 10, 25, 50, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "⚔",
        hidden      = false,
    },
    {
        id          = "deadeye",
        category    = "Progression",
        staged      = true,
        stat        = "rangedUpgradeLevel",
        titleFormat = "Deadeye %s",
        descFormat  = "Reach Ranged Upgrade Level %d.",
        thresholds  = { 5, 10, 25, 50, 100 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "🎯",
        hidden      = false,
    },

    ---------------------------------------------------------------------------
    -- ECONOMY (continued) — Robux Spending Milestones
    ---------------------------------------------------------------------------
    {
        id          = "robux_spender",
        category    = "Economy",
        staged      = true,
        stat        = "totalRobuxSpent",
        titleFormat = "%s",
        descFormat  = "Spend %d Robux in the shop.",
        thresholds  = { 50, 250, 500, 1000, 2500 },
        rewards     = copyStages(STAGE_COIN_REWARDS, 5),
        achievementPoints = copyStages(STAGE_AP_REWARDS, 5),
        icon        = "💎",
        hidden      = false,
        -- Custom stage titles (not roman numerals)
        stageTitles = { "First Purchase", "Supporter", "Big Spender", "Premium Supporter", "Shop Patron" },
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
    -- Support custom per-stage titles (e.g. Robux spending milestones)
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

function AchievementDefs.GetStageReward(def, stageIndex)
    if not def.staged then return def.reward end
    return def.rewards[stageIndex] or 0
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
    player_slayer = "eliminator",
    flag_capturer = "capture_artist",
    flag_returner = "banner_guardian",
    safe_hands    = "flag_bearer",
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
