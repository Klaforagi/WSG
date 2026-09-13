--------------------------------------------------------------------------------
-- DailyRewardConfig.lua  –  Shared daily-reward definitions (ReplicatedStorage)
-- Readable by both server and client. All reward metadata lives here.
-- To change rewards, edit the REWARDS table below – no other code changes needed.
--------------------------------------------------------------------------------

local DailyRewardConfig = {}

--- Reward type constants (extensible for future types)
DailyRewardConfig.RewardType = {
    Coins           = "Coins",
    XPBoost         = "XPBoost",
    CoinBoost       = "CoinBoost",
    QuestReroll     = "QuestReroll",
    -- Future types (add here when implemented):
    -- Cosmetic      = "Cosmetic",
    -- Title         = "Title",
    -- Banner        = "Banner",
    -- Emote         = "Emote",
    -- EventToken    = "EventToken",
    -- PremiumReward = "PremiumReward",
}

--- Number of days in one streak cycle (loops after this)
DailyRewardConfig.CycleDays = 7

--- Hours of grace before a missed day resets the streak.
--- Player has until the end of the NEXT day (i.e. 48h from start of last
--- claim day) before streak resets.  This prevents unfair timezone issues.
DailyRewardConfig.GraceHours = 48

--- Icon glyphs used as fallback when no image asset is available.
DailyRewardConfig.IconGlyphs = {
    Coins       = "\u{1F4B0}",
    XPBoost     = "\u{26A1}",
    CoinBoost   = "\u{1F4B0}",
    QuestReroll = "\u{1F504}",
    Gift        = "\u{1F381}",
    Star        = "\u{2B50}",
}

--- Icon asset keys (maps to AssetCodes.Get). Set "" or nil for no image.
DailyRewardConfig.IconAssetKeys = {
    Coins       = "Coin",
    XPBoost     = "Boosts",
    CoinBoost   = "Coin",
    QuestReroll = "Quests",
}

--- Icon tint colors per reward type
DailyRewardConfig.IconColors = {
    Coins       = Color3.fromRGB(255, 215, 80),
    XPBoost     = Color3.fromRGB(100, 200, 255),
    CoinBoost   = Color3.fromRGB(255, 215, 80),
    QuestReroll = Color3.fromRGB(130, 255, 130),
}

--------------------------------------------------------------------------------
-- 7-day reward schedule
-- Each entry: { Day, RewardType, Amount, DisplayName, Description }
-- Optional fields: BoostId, Rarity, StyleTag, Metadata (for future expansion)
--------------------------------------------------------------------------------
DailyRewardConfig.Rewards = {
    {
        Day         = 1,
        RewardType  = DailyRewardConfig.RewardType.Coins,
        Amount      = 100,
        DisplayName = "100 Coins",
        Description = "A handful of coins to start your streak!",
    },
    {
        Day         = 2,
        RewardType  = "Shards",
        Amount      = 50,
        DisplayName = "50 Shards",
        Description = "Salvage shards for the stall.",
    },
    {
        Day         = 3,
        RewardType  = DailyRewardConfig.RewardType.Coins,
        Amount      = 200,
        DisplayName = "200 Coins",
        Description = "Keep the streak going!",
    },
    {
        Day         = 4,
        RewardType  = "Shards",
        Amount      = 100,
        DisplayName = "100 Shards",
        Description = "A bigger shard payout.",
    },
    {
        Day         = 5,
        RewardType  = DailyRewardConfig.RewardType.Coins,
        Amount      = 300,
        DisplayName = "300 Coins",
        Description = "A generous coin reward!",
    },
    {
        Day         = 6,
        RewardType  = "Shards",
        Amount      = 150,
        DisplayName = "150 Shards",
        Description = "A strong shard reward.",
    },
    {
        Day         = 7,
        RewardType  = "Key",
        Amount      = 1,
        DisplayName = "1 Golden Key",
        Description = "The grand weekly reward!",
        Rarity      = "Rare",
    },
}

--- Lookup reward entry by day number (1–CycleDays).
function DailyRewardConfig.GetReward(day)
    for _, entry in ipairs(DailyRewardConfig.Rewards) do
        if entry.Day == day then
            return entry
        end
    end
    return nil
end

--- Get display-friendly type label.
function DailyRewardConfig.GetTypeLabel(rewardType)
    if rewardType == DailyRewardConfig.RewardType.Coins then return "Coins" end
    if rewardType == DailyRewardConfig.RewardType.XPBoost then return "XP Boost" end
    if rewardType == DailyRewardConfig.RewardType.CoinBoost then return "Coin Boost" end
    if rewardType == DailyRewardConfig.RewardType.QuestReroll then return "Quest Reroll" end
    return tostring(rewardType)
end

return DailyRewardConfig
