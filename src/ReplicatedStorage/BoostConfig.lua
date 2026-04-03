--------------------------------------------------------------------------------
-- BoostConfig.lua  –  Shared boost definitions (ReplicatedStorage)
-- Readable by both server and client. All boost metadata lives here.
-- To add a new boost, just append another entry to BOOSTS.
--------------------------------------------------------------------------------

local BoostConfig = {}

--- Boost type constants
BoostConfig.Type = {
    Timed   = "Timed",   -- has a duration, effect active while timer runs
    Instant = "Instant", -- consumed immediately on use
}

--- Master boost definitions list.  SortOrder controls display order in the UI.
BoostConfig.Boosts = {
    {
        Id            = "coins_2x",
        DisplayName   = "2x Coins",
        Description   = "Doubles all coin rewards for 30 minutes.",
        PriceCoins    = 40,
        DurationSeconds = 1800,  -- 30 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,       -- coin multiplier while active
        IconKey       = "Coin",
        IconGlyph     = "\u{1F4B0}",
        IconColor     = {255, 200, 40},
        IconAssetId   = "",      -- placeholder; set a Roblox decal id later
        SortOrder     = 1,
        -- TODO: Add PriceRobux field when Robux purchases are implemented
    },
    {
        Id            = "xp_2x",
        DisplayName   = "2x XP",
        Description   = "Doubles all XP rewards for 30 minutes.",
        PriceCoins    = 45,
        DurationSeconds = 1800,  -- 30 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,
        IconKey       = "XP",
        IconGlyph     = "\u{2B50}",
        IconColor     = {180, 120, 255},
        IconAssetId   = "",
        SortOrder     = 2,
    },
    {
        Id            = "quest_2x",
        DisplayName   = "2x Quest Progress",
        Description   = "Doubles daily quest progress for 30 minutes.",
        PriceCoins    = 35,
        DurationSeconds = 1800,
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,
        IconKey       = "Quests",
        IconGlyph     = "\u{2611}",
        IconColor     = {100, 180, 255},
        IconAssetId   = "",
        SortOrder     = 3,
    },
    {
        Id            = "quest_reroll",
        DisplayName   = "Quest Reroll",
        Description   = "Replace one daily quest with a new random quest.",
        PriceCoins    = 20,
        DurationSeconds = 0,
        Type          = BoostConfig.Type.Instant,
        Stackable     = true,
        InstantUse    = true,
        IconAssetId   = "",
        SortOrder     = 4,
    },
    {
        Id            = "bonus_claim",
        DisplayName   = "Bonus Reward",
        Description   = "Claim an extra reward from a completed daily quest.",
        PriceCoins    = 25,
        DurationSeconds = 0,
        Type          = BoostConfig.Type.Instant,
        Stackable     = true,
        InstantUse    = true,
        IconAssetId   = "",
        SortOrder     = 5,
    },
}

--- Lookup a boost definition by Id.
function BoostConfig.GetById(boostId)
    for _, def in ipairs(BoostConfig.Boosts) do
        if def.Id == boostId then
            return def
        end
    end
    return nil
end

return BoostConfig
