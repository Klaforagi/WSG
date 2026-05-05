--------------------------------------------------------------------------------
-- BuffBarConfig.lua
-- Shared display metadata for the compact lower-right buff/event HUD.
--------------------------------------------------------------------------------

local BuffBarConfig = {}

BuffBarConfig.StaticEntries = {
    event = {
        Id = "event",
        DisplayName = "Event",
        IconKey = "Event",
        IconGlyph = "\u{2605}",
        IconLabel = "EVENT",
        IconColor = {255, 215, 80},
        SortOrder = 10,
    },
    hut_heal = {
        Id = "hut_heal",
        DisplayName = "Heal Buff",
        IconKey = "HealBuff",
        IconGlyph = "+",
        IconColor = {35, 220, 95},
        SortOrder = 20,
    },
    bandage = {
        Id = "bandage",
        DisplayName = "Bandage",
        IconKey = "Bandage",
        IconGlyph = "+",
        IconColor = {80, 210, 130},
        SortOrder = 30,
        TintImage = false,
    },
    flag_blue = {
        Id = "flag_blue",
        DisplayName = "Blue Flag",
        IconKey = "BlueFlag",
        IconGlyph = "FLAG",
        IconColor = {85, 150, 255},
        SortOrder = 40,
        TintImage = false,
    },
    flag_red = {
        Id = "flag_red",
        DisplayName = "Red Flag",
        IconKey = "RedFlag",
        IconGlyph = "FLAG",
        IconColor = {255, 95, 95},
        SortOrder = 40,
        TintImage = false,
    },
}

function BuffBarConfig.GetStaticEntry(id)
    local entry = BuffBarConfig.StaticEntries[id]
    if not entry then
        return nil
    end

    local copy = {}
    for key, value in pairs(entry) do
        copy[key] = value
    end
    return copy
end

function BuffBarConfig.FromBoostDef(def)
    if type(def) ~= "table" or not def.Id then
        return nil
    end

    return {
        Id = "boost_" .. tostring(def.Id),
        SourceId = def.Id,
        Kind = "boost",
        DisplayName = def.DisplayName or def.Id,
        IconKey = def.IconKey,
        IconGlyph = def.IconGlyph or "2x",
        IconColor = def.IconColor or {255, 215, 80},
        IconAssetId = def.IconAssetId,
        SortOrder = 100 + (tonumber(def.SortOrder) or 0),
    }
end

return BuffBarConfig