--------------------------------------------------------------------------------
-- BuffBarConfig.lua
-- Shared display metadata for the compact lower-right buff/event HUD.
--------------------------------------------------------------------------------

local BuffBarConfig = {}

BuffBarConfig.StaticEntries = {
    event = {
        Id = "event",
        DisplayName = "Event",
        Description = "Meteor Shower active - collect shards for coins.",
        IconAssetId = "", -- Set to "rbxassetid://..." when a dedicated event icon is uploaded.
        FallbackSymbol = "\u{2605}",
        IconGlyph = "\u{2605}",
        IconColor = {255, 215, 80},
        AccentColor = {255, 215, 80},
        IconTextMaxSize = 86,
        ShowTimer = true,
        SortOrder = 10,
    },
    hut_heal = {
        Id = "hut_heal",
        DisplayName = "Heal Buff",
        Description = "Healing is active near your team's hut.",
        IconShape = "plus",
        IconColor = {35, 220, 95},
        ShowTimer = true,
        SortOrder = 20,
    },
    bandage = {
        Id = "bandage",
        DisplayName = "Bandage",
        Description = "Bandaging wounds.",
        IconShape = "plus",
        IconColor = {80, 210, 130},
        ShowTimer = true,
        SortOrder = 30,
    },
    revenge_curse = {
        Id = "revenge_curse",
        Kind = "debuff",
        DisplayName = "Revenge Curse",
        Description = "Reduced movement speed and damage.",
        IconGlyph = "!",
        FallbackSymbol = "!",
        IconColor = {190, 60, 50},
        AccentColor = {255, 95, 95},
        IconTextMaxSize = 70,
        ShowTimer = true,
        SortOrder = 35,
    },
    defeat = {
        Id = "defeat",
        Kind = "debuff",
        DisplayName = "Defeat",
        Description = "-10 Movement Speed.",
        IconShape = "flag",
        IconGlyph = "\u{2691}",
        IconColor = {255, 255, 255},
        AccentColor = {255, 255, 255},
        IconTextMaxSize = 52,
        ShowTimer = true,
        SortOrder = 38,
        TintImage = false,
    },
    flag_blue = {
        Id = "flag_blue",
        DisplayName = "Blue Flag",
        Description = "You are carrying the enemy flag. -1 Movement Speed.",
        IconShape = "flag",
        IconGlyph = "\u{2691}",
        IconColor = {85, 150, 255},
        IconTextMaxSize = 52,
        ShowTimer = false,
        SortOrder = 40,
        TintImage = false,
    },
    flag_red = {
        Id = "flag_red",
        DisplayName = "Red Flag",
        Description = "You are carrying the enemy flag. -1 Movement Speed.",
        IconShape = "flag",
        IconGlyph = "\u{2691}",
        IconColor = {255, 95, 95},
        IconTextMaxSize = 52,
        ShowTimer = false,
        SortOrder = 40,
        TintImage = false,
    },
}

BuffBarConfig.StaticAliases = {
    EVENT = "event",
    Event = "event",
    meteor_event = "event",
    meteorshower = "event",
    MeteorEvent = "event",
    MeteorShower = "event",
    gold_rush = "event",
    goldrush = "event",
    GoldRush = "event",
    flag = "flag_red",
    Flag = "flag_red",
    FLAG = "flag_red",
    blueflag = "flag_blue",
    BlueFlag = "flag_blue",
    redflag = "flag_red",
    RedFlag = "flag_red",
    RevengeCurse = "revenge_curse",
    revengecurse = "revenge_curse",
    revenge_curse = "revenge_curse",
    MarkedByRevenge = "revenge_curse",
    markedbyrevenge = "revenge_curse",
    defeat = "defeat",
    Defeat = "defeat",
}

local function normalizeStaticId(id)
    if id == nil then
        return nil
    end

    local key = tostring(id)
    if BuffBarConfig.StaticEntries[key] then
        return key
    end
    if BuffBarConfig.StaticAliases[key] then
        return BuffBarConfig.StaticAliases[key]
    end

    local lowerKey = string.lower(key)
    if BuffBarConfig.StaticEntries[lowerKey] then
        return lowerKey
    end
    if BuffBarConfig.StaticAliases[lowerKey] then
        return BuffBarConfig.StaticAliases[lowerKey]
    end

    local compactKey = lowerKey:gsub("[^%w]", "")
    if BuffBarConfig.StaticEntries[compactKey] then
        return compactKey
    end
    return BuffBarConfig.StaticAliases[compactKey]
end

function BuffBarConfig.GetStaticEntry(id)
    local normalizedId = normalizeStaticId(id)
    local entry = normalizedId and BuffBarConfig.StaticEntries[normalizedId]
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
        Description = def.Description or "Extra boost effect is active.",
        IconKey = def.IconKey,
        IconGlyph = def.IconGlyph or "2x",
        IconColor = def.IconColor or {255, 215, 80},
        IconAssetId = def.IconAssetId,
        ShowTimer = true,
        SortOrder = 100 + (tonumber(def.SortOrder) or 0),
    }
end

return BuffBarConfig