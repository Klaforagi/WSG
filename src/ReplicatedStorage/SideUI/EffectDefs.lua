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
        Id          = "DefaultTrail",
        DisplayName = "Default Trail",
        Description = "The standard white dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(255, 255, 255),
        CoinCost    = 0,
        IsFree      = true,
        Rarity      = "Common",
        SortOrder   = 0,
        IconGlyph   = "\u{2550}",       -- placeholder visual
    },
    {
        Id          = "RedTrail",
        DisplayName = "Crimson Trail",
        Description = "A blazing red dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(255, 60, 60),
        CoinCost    = 75,
        IsFree      = false,
        Rarity      = "Uncommon",
        SortOrder   = 1,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "BlueTrail",
        DisplayName = "Azure Trail",
        Description = "A cool blue dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(20, 80, 255),
        CoinCost    = 75,
        IsFree      = false,
        Rarity      = "Uncommon",
        SortOrder   = 2,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "BlackTrail",
        DisplayName = "Black Trail",
        Description = "A sleek dark charcoal dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(45, 45, 50),
        CoinCost    = 75,
        IsFree      = false,
        Rarity      = "Uncommon",
        SortOrder   = 3,
        IconGlyph   = "\u{2550}",
    },
    {
        Id          = "RainbowTrail",
        DisplayName = "Rainbow Trail",
        Description = "A premium multicolored dash trail.",
        Category    = "Effects",
        SubType     = "DashTrail",
        Color       = Color3.fromRGB(180, 120, 255),   -- representative purple for fallback
        CoinCost    = 150,
        IsFree      = false,
        Rarity      = "Epic",
        SortOrder   = 4,
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
