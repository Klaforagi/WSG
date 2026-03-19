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
    ZOMBIES_ELIMINATED = "zombies_eliminated",
    PLAYERS_ELIMINATED = "players_eliminated",
    MATCHES_PLAYED     = "matches_played",
    COINS_EARNED       = "coins_earned",
    DAMAGE_DEALT       = "damage_dealt",
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
        id        = "monster_hunter",
        title     = "Monster Hunter",
        desc      = "Eliminate 15 monsters",
        goal      = 15,
        reward    = 12,
        trackType = "zombies_eliminated",
    },
    {
        id        = "monster_slayer",
        title     = "Monster Slayer",
        desc      = "Eliminate 25 monsters",
        goal      = 25,
        reward    = 18,
        trackType = "zombies_eliminated",
    },

    -- Player Eliminations  (PvP combat)
    {
        id        = "player_hunter",
        title     = "Player Hunter",
        desc      = "Eliminate 5 enemy players",
        goal      = 5,
        reward    = 15,
        trackType = "players_eliminated",
    },
    {
        id        = "headhunter",
        title     = "Headhunter",
        desc      = "Eliminate 10 enemy players",
        goal      = 10,
        reward    = 22,
        trackType = "players_eliminated",
    },

    -- Matches Played  (participation)
    {
        id        = "battle_ready",
        title     = "Battle Ready",
        desc      = "Play 3 matches",
        goal      = 3,
        reward    = 12,
        trackType = "matches_played",
    },
    {
        id        = "warpath",
        title     = "Warpath",
        desc      = "Play 5 matches",
        goal      = 5,
        reward    = 18,
        trackType = "matches_played",
    },

    -- Coins Earned  (smaller daily target)
    {
        id        = "coin_grab",
        title     = "Coin Grab",
        desc      = "Earn 75 coins",
        goal      = 75,
        reward    = 15,
        trackType = "coins_earned",
    },
    {
        id        = "coin_collector",
        title     = "Coin Collector",
        desc      = "Earn 150 coins",
        goal      = 150,
        reward    = 22,
        trackType = "coins_earned",
    },

    -- Damage Dealt  (combat output)
    {
        id        = "heavy_hitter",
        title     = "Heavy Hitter",
        desc      = "Deal 1,000 total damage",
        goal      = 1000,
        reward    = 15,
        trackType = "damage_dealt",
    },
    {
        id        = "devastator",
        title     = "Devastator",
        desc      = "Deal 2,500 total damage",
        goal      = 2500,
        reward    = 22,
        trackType = "damage_dealt",
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
