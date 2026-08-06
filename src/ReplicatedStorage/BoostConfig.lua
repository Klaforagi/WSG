--------------------------------------------------------------------------------
-- BoostConfig.lua  –  Shared boost definitions (ReplicatedStorage)
-- Readable by both server and client. All boost metadata lives here.
-- To add a new boost, just append another entry to BOOSTS.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionProductIds = require(ReplicatedStorage:WaitForChild("PotionProductIds"))

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
        DisplayName   = "Flask of Wealth",
        Category      = "Elixir",
        Description   = "2x coins",
        DetailText    = "2x coin gain for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 80,
        StockPerRefresh = 3,
        RobuxProductId = PotionProductIds.CoinsElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,       -- coin multiplier while active
        IconKey       = "2xCoinsElixir",
        IconGlyph     = "\u{1F4B0}",
        IconColor     = {255, 200, 40},
        IconAssetId   = "",      -- placeholder; set a Roblox decal id later
        ShowInPotionsStall = true,
        SortOrder     = 1,
    },
    {
        Id            = "mastery_2x",
        DisplayName   = "Flask of Expertise",
        Category      = "Elixir",
        Description   = "2x mastery XP",
        DetailText    = "2x mastery experience for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 19,
        StockPerRefresh = 3,
        RobuxProductId = PotionProductIds.XpElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,
        IconKey       = "2xMasteryElixir",
        IconGlyph     = "\u{2B50}",
        IconColor     = {180, 120, 255},
        IconAssetId   = "",
        ShowInPotionsStall = true,
        SortOrder     = 2,
    },
    {
        Id            = "xp_2x",
        DisplayName   = "Flask of Wisdom",
        Category      = "Elixir",
        Description   = "2x XP gain",
        DetailText    = "2x XP gain for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 19,
        StockPerRefresh = 3,
        RobuxProductId = PotionProductIds.XpElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        Multiplier    = 2,
        IconKey       = "2xXPElixir",
        IconGlyph     = "\u{2B50}",
        IconColor     = {80, 165, 255},
        IconAssetId   = "",
        ShowInPotionsStall = true,
        SortOrder     = 3,
    },
    {
        Id            = "speed_elixir",
        DisplayName   = "Swiftness Elixir",
        Category      = "Elixir",
        Description   = "+5% move speed",
        DetailText    = "+5% move speed for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 49,
        StockPerRefresh = 3,
        RobuxProductId = PotionProductIds.SpeedElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        AdditiveBonus = 1,
        IconKey       = "SpeedElixir",
        IconGlyph     = "",
        IconColor     = {92, 229, 132},
        IconAssetId   = "",
        ShowInPotionsStall = true,
        SortOrder     = 4,
    },
    {
        Id            = "power_elixir",
        DisplayName   = "Power Elixir",
        Category      = "Elixir",
        Description   = "+3 Melee Damage",
        DetailText    = "+3 melee damage for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 49,
        StockPerRefresh = 2,
        RobuxProductId = PotionProductIds.SpeedElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        -- Flat outgoing damage added to melee hits while active
        OutgoingFlatAdd = 3,
        IconKey       = "PowerElixir",
        IconGlyph     = "",
        IconColor     = {255, 165, 0},
        IconAssetId   = "",
        ShowInPotionsStall = true,
        SortOrder     = 5,
    },
    {
        Id            = "vitality_elixir",
        DisplayName   = "Vitality Elixir",
        Category      = "Elixir",
        Description   = "+5 HP every 5s",
        DetailText    = "+5 health regen every 5 seconds for 15 mins",
        PriceCoins    = 150,
        PriceRobux    = 49,
        StockPerRefresh = 2,
        RobuxProductId = PotionProductIds.SpeedElixirRobuxProductId,
        DurationSeconds = 900,  -- 15 minutes
        Type          = BoostConfig.Type.Timed,
        Stackable     = false,
        InstantUse    = false,
        -- Periodic heal: amount per tick and tick interval (seconds)
        HealthRegenPerTick = 5,
        HealthRegenTickInterval = 5,
        IconKey       = "VitalityElixir",
        IconGlyph     = "",
        IconColor     = {235, 75, 75},
        IconAssetId   = "",
        ShowInPotionsStall = true,
        SortOrder     = 6,
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

function BoostConfig.ShouldShowInPotionsStall(boostDefOrId)
    local boostDef = boostDefOrId
    if type(boostDefOrId) == "string" then
        boostDef = BoostConfig.GetById(boostDefOrId)
    end
    if type(boostDef) ~= "table" then
        return false
    end
    if boostDef.InstantUse == true or boostDef.Hidden == true or boostDef.Visible == false then
        return false
    end
    if boostDef.RemovedFromShop == true or boostDef.Purchasable == false then
        return false
    end
    return boostDef.ShowInPotionsStall == true
end

function BoostConfig.GetPotionsStallBoosts()
    local boosts = {}
    for _, def in ipairs(BoostConfig.Boosts) do
        if BoostConfig.ShouldShowInPotionsStall(def) then
            table.insert(boosts, def)
        end
    end
    table.sort(boosts, function(a, b)
        local orderA = tonumber(a.SortOrder) or 0
        local orderB = tonumber(b.SortOrder) or 0
        if orderA ~= orderB then
            return orderA < orderB
        end
        return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id)
    end)
    return boosts
end

function BoostConfig.GetRobuxProductId(boostDefOrId)
    local boostDef = boostDefOrId
    if type(boostDefOrId) == "string" then
        boostDef = BoostConfig.GetById(boostDefOrId)
    end
    if type(boostDef) ~= "table" then
        return 0
    end
    return math.max(0, math.floor(tonumber(boostDef.RobuxProductId) or 0))
end

function BoostConfig.IsRobuxPurchasable(boostDefOrId)
    return BoostConfig.GetRobuxProductId(boostDefOrId) > 0
end

return BoostConfig
