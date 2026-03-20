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
        Color       = Color3.fromRGB(180, 220, 255),
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
    return (def and def.Color) or Color3.fromRGB(180, 220, 255)
end

return EffectDefs
