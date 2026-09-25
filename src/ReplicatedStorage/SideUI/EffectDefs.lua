--------------------------------------------------------------------------------
-- EffectDefs.lua  –  Shared configuration for cosmetic effects
-- Readable by both server and client (lives in ReplicatedStorage/SideUI).
--
-- Usage:
--   local EffectDefs = require(path.to.EffectDefs)
--   local all        = EffectDefs.GetAll()
--   local def        = EffectDefs.GetById("RedTrail")
--   local trails     = EffectDefs.GetBySubType("DashTrail")
--------------------------------------------------------------------------------

local EffectDefs = {}

EffectDefs.Effects = {
    {
        Id          = "RedTrail",
        DisplayName = "Red Trail",
        Description = "A blazing red dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(255, 60, 60),
        CoinCost    = 5000,
        IsFree      = false,
        SortOrder   = 9,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "BlueTrail",
        DisplayName = "Blue Trail",
        Description = "A cool blue dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(20, 80, 255),
        CoinCost    = 5000,
        IsFree      = false,
        SortOrder   = 8,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "BlackTrail",
        DisplayName = "Black Trail",
        Description = "A sleek dark charcoal dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(45, 45, 50),
        CoinCost    = 3000,
        IsFree      = false,
        SortOrder   = 7,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "RainbowTrail",
        DisplayName = "Rainbow Trail",
        Description = "A premium multicolored dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(180, 120, 255),   -- representative purple for fallback
        CoinCost    = 50000,
        IsFree      = false,
        SortOrder   = 11,
        IconGlyph   = "\u{2550}",
        IsRainbow   = true,
        TrailColorSequence = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,  60,  60)),  -- red
            ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 160,  40)),  -- orange
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230,  60)),  -- yellow
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB( 40, 220,  80)),  -- green
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB( 40, 210, 255)),  -- cyan
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB( 60,  80, 255)),  -- blue
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(200,  60, 255)),  -- magenta
        }),
        -- Colors used for afterimage ghost (smooth average of the sequence)
        GhostColors = {
            Color3.fromRGB(255,  60,  60),
            Color3.fromRGB(255, 230,  60),
            Color3.fromRGB( 40, 220,  80),
            Color3.fromRGB( 60,  80, 255),
            Color3.fromRGB(200,  60, 255),
        },
    },

    ---------------------------------------------------------------------------
    -- PREMIUM COIN TRAILS
    ---------------------------------------------------------------------------
    {
        Id          = "EmeraldTrail",
        DisplayName = "Green Trail",
        Description = "A vivid green dash trail that gleams like gemstone.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(35, 190, 75),
        CoinCost    = 500,
        IsFree      = false,
        ShopVisible = true,
        SortOrder   = 1,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "GoldenTrail",
        DisplayName = "Yellow Trail",
        Description = "A luxurious golden dash trail worthy of royalty.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(255, 200, 50),
        CoinCost    = 500,
        IsFree      = false,
        ShopVisible = true,
        SortOrder   = 2,
        IconGlyph   = "\u{2550}",
    },
    {
        Id = "PinkTrail", DisplayName = "Pink Trail", Category = "Effects", SubType = "DashTrail",
        Color = Color3.fromRGB(255, 105, 180), CoinCost = 500, IsFree = false, ShopVisible = true, SortOrder = 3, IconGlyph = "\u{2550}",
    },
    {
        Id = "PurpleTrail", DisplayName = "Purple Trail", Category = "Effects", SubType = "DashTrail",
        Color = Color3.fromRGB(155, 85, 255), CoinCost = 2000, IsFree = false, ShopVisible = true, SortOrder = 4, IconGlyph = "\u{2550}",
    },
    {
        Id = "OrangeTrail", DisplayName = "Orange Trail", Category = "Effects", SubType = "DashTrail",
        Color = Color3.fromRGB(255, 135, 35), CoinCost = 2000, IsFree = false, ShopVisible = true, SortOrder = 5, IconGlyph = "\u{2550}",
    },
    {
        Id = "WhiteTrail", DisplayName = "White Trail", Category = "Effects", SubType = "DashTrail",
        Color = Color3.fromRGB(255, 255, 255), CoinCost = 3000, IsFree = false, ShopVisible = true, SortOrder = 6, IconGlyph = "\u{2550}",
    },
    {
        Id = "TeamTrail", DisplayName = "Team Color Trail", Category = "Effects", SubType = "DashTrail",
        Color = Color3.fromRGB(255, 220, 55), CoinCost = 10000, IsFree = false, ShopVisible = true, SortOrder = 10, IconGlyph = "\u{2550}", IsTeamTrail = true,
    },
}

function EffectDefs.GetAll()
    return EffectDefs.Effects
end

function EffectDefs.GetById(id)
    for _, def in ipairs(EffectDefs.Effects) do
        if def.Id == id then return def end
    end
    return nil
end

function EffectDefs.GetBySubType(subType)
    local results = {}
    for _, def in ipairs(EffectDefs.Effects) do
        if def.SubType == subType then
            table.insert(results, def)
        end
    end
    return results
end

function EffectDefs.GetDisplayName(id)
    local def = EffectDefs.GetById(id)
    return (def and def.DisplayName) or tostring(id)
end

function EffectDefs.GetColor(id)
    local def = EffectDefs.GetById(id)
    return (def and def.Color) or Color3.fromRGB(255, 255, 255)
end

function EffectDefs.GetTrailColorSequence(id)
    local def = EffectDefs.GetById(id)
    if def and def.TrailColorSequence then
        return def.TrailColorSequence
    end
    local color = (def and def.Color) or Color3.fromRGB(255, 255, 255)
    return ColorSequence.new(color, color)
end

return EffectDefs
