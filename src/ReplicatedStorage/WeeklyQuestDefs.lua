--------------------------------------------------------------------------------
-- WeeklyQuestDefs.lua  –  Shared weekly quest pool (ReplicatedStorage)
-- Used by WeeklyQuestService (server) and DailyQuestsUI (client) for display.
--------------------------------------------------------------------------------

local WeeklyQuestDefs = {}

--------------------------------------------------------------------------------
-- Track types used for server-side event routing
--------------------------------------------------------------------------------
WeeklyQuestDefs.TrackTypes = {
    MATCHES_PLAYED       = "matches_played",
    TIME_PLAYED          = "time_played",
    ZOMBIES_ELIMINATED   = "zombies_eliminated",
    PLAYERS_ELIMINATED   = "players_eliminated",
    MATCHES_WON          = "matches_won",
}

--------------------------------------------------------------------------------
-- Quest pool  (15 quests – 3 per track type at easy/medium/hard tiers)
--
-- goal:       target value the player must reach
-- reward:     coins awarded on claim
-- trackType:  key used by the server to route game events to quest progress
-- displayUnit: optional – if set, progress text uses this label
--------------------------------------------------------------------------------
WeeklyQuestDefs.Pool = {
    -- Matches Played
    {
        id        = "play_5_matches",
        title     = "Play 5 Matches",
        desc      = "Complete 5 full matches",
        goal      = 5,
        reward    = 20,
        trackType = "matches_played",
    },
    {
        id        = "play_10_matches",
        title     = "Play 10 Matches",
        desc      = "Complete 10 full matches",
        goal      = 10,
        reward    = 30,
        trackType = "matches_played",
    },
    {
        id        = "play_15_matches",
        title     = "Play 15 Matches",
        desc      = "Complete 15 full matches",
        goal      = 15,
        reward    = 40,
        trackType = "matches_played",
    },

    -- Time Played  (goal in minutes)
    {
        id          = "play_30_min",
        title       = "Play for 30 Minutes",
        desc        = "Spend 30 minutes in matches",
        goal        = 30,
        reward      = 20,
        trackType   = "time_played",
        displayUnit = "min",
    },
    {
        id          = "play_60_min",
        title       = "Play for 60 Minutes",
        desc        = "Spend 60 minutes in matches",
        goal        = 60,
        reward      = 30,
        trackType   = "time_played",
        displayUnit = "min",
    },
    {
        id          = "play_120_min",
        title       = "Play for 120 Minutes",
        desc        = "Spend 120 minutes in matches",
        goal        = 120,
        reward      = 40,
        trackType   = "time_played",
        displayUnit = "min",
    },

    -- Zombies Eliminated
    {
        id        = "elim_25_zombies",
        title     = "Eliminate 25 Zombies",
        desc      = "Defeat 25 zombies",
        goal      = 25,
        reward    = 20,
        trackType = "zombies_eliminated",
    },
    {
        id        = "elim_50_zombies",
        title     = "Eliminate 50 Zombies",
        desc      = "Defeat 50 zombies",
        goal      = 50,
        reward    = 30,
        trackType = "zombies_eliminated",
    },
    {
        id        = "elim_100_zombies",
        title     = "Eliminate 100 Zombies",
        desc      = "Defeat 100 zombies",
        goal      = 100,
        reward    = 40,
        trackType = "zombies_eliminated",
    },

    -- Players Eliminated
    {
        id        = "elim_10_players",
        title     = "Eliminate 10 Players",
        desc      = "Defeat 10 enemy players",
        goal      = 10,
        reward    = 20,
        trackType = "players_eliminated",
    },
    {
        id        = "elim_20_players",
        title     = "Eliminate 20 Players",
        desc      = "Defeat 20 enemy players",
        goal      = 20,
        reward    = 30,
        trackType = "players_eliminated",
    },
    {
        id        = "elim_35_players",
        title     = "Eliminate 35 Players",
        desc      = "Defeat 35 enemy players",
        goal      = 35,
        reward    = 40,
        trackType = "players_eliminated",
    },

    -- Matches Won
    {
        id        = "win_2_matches",
        title     = "Win 2 Matches",
        desc      = "Win 2 matches with your team",
        goal      = 2,
        reward    = 20,
        trackType = "matches_won",
    },
    {
        id        = "win_3_matches",
        title     = "Win 3 Matches",
        desc      = "Win 3 matches with your team",
        goal      = 3,
        reward    = 30,
        trackType = "matches_won",
    },
    {
        id        = "win_5_matches",
        title     = "Win 5 Matches",
        desc      = "Win 5 matches with your team",
        goal      = 5,
        reward    = 40,
        trackType = "matches_won",
    },
}

-- Build a quick lookup by id
WeeklyQuestDefs.ById = {}
for _, def in ipairs(WeeklyQuestDefs.Pool) do
    WeeklyQuestDefs.ById[def.id] = def
end

-- Group by trackType for selection diversity
WeeklyQuestDefs.ByTrackType = {}
for _, def in ipairs(WeeklyQuestDefs.Pool) do
    if not WeeklyQuestDefs.ByTrackType[def.trackType] then
        WeeklyQuestDefs.ByTrackType[def.trackType] = {}
    end
    table.insert(WeeklyQuestDefs.ByTrackType[def.trackType], def)
end

return WeeklyQuestDefs
