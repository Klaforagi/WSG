--------------------------------------------------------------------------------
-- WeeklyQuestDefs.lua  –  Shared weekly quest pool (ReplicatedStorage)
-- Used by WeeklyQuestService (server) and DailyQuestsUI (client) for display.
--
-- DESIGN: Weekly quests are longer-term commitment goals focused on wins,
-- objectives, and sustained play. They intentionally differ from daily quests
-- which target quick session-based combat and participation.
--------------------------------------------------------------------------------

local WeeklyQuestDefs = {}

--------------------------------------------------------------------------------
-- Track types used for server-side event routing
--------------------------------------------------------------------------------
WeeklyQuestDefs.TrackTypes = {
    MATCHES_WON     = "matches_won",
    FLAG_CAPTURES   = "flag_captures",
    FLAG_RETURNS    = "flag_returns",
    TIME_PLAYED     = "time_played",
    COINS_EARNED    = "coins_earned",
    MATCHES_PLAYED  = "matches_played",
}

--------------------------------------------------------------------------------
-- Quest pool  (17 quests – 2-3 per track type at easy/medium/hard tiers)
--
-- goal:       target value the player must reach
-- reward:     coins awarded on claim
-- trackType:  key used by the server to route game events to quest progress
-- displayUnit: optional – if set, progress text uses this label
--------------------------------------------------------------------------------
WeeklyQuestDefs.Pool = {
    -- Matches Won  (requires victories, not just participation)
    {
        id        = "win_3_matches",
        title     = "Champion",
        desc      = "Win 3 matches with your team",
        goal      = 3,
        reward    = 180,
        trackType = "matches_won",
    },
    {
        id        = "win_5_matches",
        title     = "Grand Champion",
        desc      = "Win 5 matches with your team",
        goal      = 5,
        reward    = 230,
        trackType = "matches_won",
    },
    {
        id        = "win_10_matches",
        title     = "Legendary Victor",
        desc      = "Win 10 matches with your team",
        goal      = 10,
        reward    = 300,
        trackType = "matches_won",
    },

    -- Flag Captures  (objective play)
    {
        id        = "capture_3_flags",
        title     = "Flag Runner",
        desc      = "Capture 3 enemy flags",
        goal      = 3,
        reward    = 180,
        trackType = "flag_captures",
    },
    {
        id        = "capture_5_flags",
        title     = "Flag Dominator",
        desc      = "Capture 5 enemy flags",
        goal      = 5,
        reward    = 230,
        trackType = "flag_captures",
    },
    {
        id        = "capture_8_flags",
        title     = "Capture King",
        desc      = "Capture 8 enemy flags",
        goal      = 8,
        reward    = 280,
        trackType = "flag_captures",
    },

    -- Flag Returns  (defensive objective play)
    {
        id        = "return_3_flags",
        title     = "Banner Guardian",
        desc      = "Return your team's flag 3 times",
        goal      = 3,
        reward    = 180,
        trackType = "flag_returns",
    },
    {
        id        = "return_5_flags",
        title     = "Flag Defender",
        desc      = "Return your team's flag 5 times",
        goal      = 5,
        reward    = 230,
        trackType = "flag_returns",
    },
    {
        id        = "return_8_flags",
        title     = "Loyal Protector",
        desc      = "Return your team's flag 8 times",
        goal      = 8,
        reward    = 280,
        trackType = "flag_returns",
    },

    -- Time Played  (sustained presence in matches)
    {
        id          = "play_30_min",
        title       = "Battlefield Veteran",
        desc        = "Spend 30 minutes in matches",
        goal        = 30,
        reward      = 180,
        trackType   = "time_played",
        displayUnit = "min",
    },
    {
        id          = "play_60_min",
        title       = "War Veteran",
        desc        = "Spend 60 minutes in matches",
        goal        = 60,
        reward      = 230,
        trackType   = "time_played",
        displayUnit = "min",
    },
    {
        id          = "play_120_min",
        title       = "Ironclad",
        desc        = "Spend 120 minutes in matches",
        goal        = 120,
        reward      = 280,
        trackType   = "time_played",
        displayUnit = "min",
    },

    -- Coins Earned  (larger weekly target)
    {
        id        = "earn_500_coins",
        title     = "Wealth Builder",
        desc      = "Earn 500 coins from gameplay",
        goal      = 500,
        reward    = 200,
        trackType = "coins_earned",
    },
    {
        id        = "earn_1000_coins",
        title     = "Fortune Seeker",
        desc      = "Earn 1,000 coins from gameplay",
        goal      = 1000,
        reward    = 280,
        trackType = "coins_earned",
    },

    -- Matches Played  (larger commitment than daily)
    {
        id        = "complete_15_matches",
        title     = "Loyal Fighter",
        desc      = "Complete 15 matches",
        goal      = 15,
        reward    = 180,
        trackType = "matches_played",
    },
    {
        id        = "complete_25_matches",
        title     = "Dedicated Warrior",
        desc      = "Complete 25 matches",
        goal      = 25,
        reward    = 230,
        trackType = "matches_played",
    },
    {
        id        = "complete_40_matches",
        title     = "Marathon Runner",
        desc      = "Complete 40 matches",
        goal      = 40,
        reward    = 280,
        trackType = "matches_played",
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
