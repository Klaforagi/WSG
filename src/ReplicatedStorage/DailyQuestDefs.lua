--------------------------------------------------------------------------------
-- DailyQuestDefs.lua  –  Shared daily quest pool (ReplicatedStorage)
-- Used by QuestService (server) and DailyQuestsUI (client) for display.
--
-- DESIGN: Daily quests are quick, session-based goals focused on normal
-- participation and combat. They intentionally differ from weekly quests
-- which target longer-term wins, objectives, and sustained play.
--------------------------------------------------------------------------------

local DailyQuestDefs = {}

--------------------------------------------------------------------------------
-- Track types used for server-side event routing
--------------------------------------------------------------------------------
DailyQuestDefs.TrackTypes = {
    -- Specific mob kills (uses mob name normalized to lowercase)
    MOB_GOBLIN         = "mob_goblin",
    MOB_ORC            = "mob_orc",
    MOB_OGRE           = "mob_ogre",

    PLAYERS_ELIMINATED = "players_eliminated",
    MATCHES_PLAYED     = "matches_played",
    MATCHES_WON        = "matches_won",
    COINS_EARNED       = "coins_earned",
    -- Damage split by source
    DAMAGE_MELEE       = "damage_melee",
    DAMAGE_RANGED      = "damage_ranged",
    DAMAGE_GENERIC     = "damage_dealt",
    -- Objectives
    FLAG_CAPTURES      = "flag_captures",
    FLAG_RETURNS       = "flag_returns",
}

--------------------------------------------------------------------------------
-- Daily quest pool  (10 quests – 2 per track type at easy/hard tiers)
--
-- goal:       target value the player must reach
-- reward:     coins awarded on claim
-- trackType:  key used by the server to route game events to quest progress
--------------------------------------------------------------------------------
DailyQuestDefs.Pool = {
    -- Monster Eliminations  (quick PvE combat)
    {
        id        = "goblin_hunter",
        title     = "Goblin Hunter",
        desc      = "Eliminate 20 goblins",
        goal      = 20,
        reward    = 80,
        trackType = "mob_goblin",
    },
    {
        id        = "orc_raider",
        title     = "Orc Raider",
        desc      = "Eliminate 12 orcs",
        goal      = 12,
        reward    = 110,
        trackType = "mob_orc",
    },
    {
        id        = "ogre_slayer",
        title     = "Ogre Slayer",
        desc      = "Eliminate 3 ogres",
        goal      = 3,
        reward    = 150,
        trackType = "mob_ogre",
    },

    -- Player Eliminations  (PvP combat)
    {
        id        = "eliminator",
        title     = "Eliminator",
        desc      = "Eliminate 10 enemy players",
        goal      = 10,
        reward    = 125,
        trackType = "players_eliminated",
    },

    -- Matches Played  (participation)
    {
        id        = "battle_ready",
        title     = "Battle Ready",
        desc      = "Play 3 matches",
        goal      = 3,
        reward    = 100,
        trackType = "matches_played",
    },
    {
        id        = "victory",
        title     = "Victory",
        desc      = "Win 1 match",
        goal      = 1,
        reward    = 110,
        trackType = "matches_won",
    },

    -- Damage Dealt  (combat output)
    {
        id        = "damage_dealer",
        title     = "Damage Dealer",
        desc      = "Deal 3,000 total damage",
        goal      = 3000,
        reward    = 90,
        trackType = "damage_dealt",
    },
    {
        id        = "frontline_damage",
        title     = "Frontline Damage",
        desc      = "Deal 1,500 Melee damage",
        goal      = 1500,
        reward    = 90,
        trackType = "damage_melee",
    },
    {
        id        = "sharpshooter",
        title     = "Sharpshooter",
        desc      = "Deal 1,500 Ranged damage",
        goal      = 1500,
        reward    = 90,
        trackType = "damage_ranged",
    },

    -- Objective based
    {
        id        = "capture_the_flag",
        title     = "Capture the Flag",
        desc      = "Capture the flag 1 time",
        goal      = 1,
        reward    = 150,
        trackType = "flag_captures",
    },
    {
        id        = "flag_defender",
        title     = "Flag Defender",
        desc      = "Return the flag 3 times",
        goal      = 3,
        reward    = 100,
        trackType = "flag_returns",
    },
}

-- Build a quick lookup by id
DailyQuestDefs.ById = {}
for _, def in ipairs(DailyQuestDefs.Pool) do
    DailyQuestDefs.ById[def.id] = def
end

-- Group by trackType for selection diversity and rerolls
DailyQuestDefs.ByTrackType = {}
for _, def in ipairs(DailyQuestDefs.Pool) do
    if not DailyQuestDefs.ByTrackType[def.trackType] then
        DailyQuestDefs.ByTrackType[def.trackType] = {}
    end
    table.insert(DailyQuestDefs.ByTrackType[def.trackType], def)
end

return DailyQuestDefs
