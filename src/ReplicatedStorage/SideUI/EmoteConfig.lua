--------------------------------------------------------------------------------
-- EmoteConfig.lua  –  Shared configuration for the Emote system
-- Readable by both server and client (lives in ReplicatedStorage/SideUI).
--
-- Future usage:
--   local EmoteConfig = require(path.to.EmoteConfig)
--   local slotCount   = EmoteConfig.SLOT_COUNT
--   local allEmotes   = EmoteConfig.GetAll()
--   local emote       = EmoteConfig.GetById("wave")
--------------------------------------------------------------------------------

local EmoteConfig = {}

-- ── Slot configuration ────────────────────────────────────────────────────
-- How many equip slots the player has in the Emote wheel/panel.
EmoteConfig.SLOT_COUNT = 8

-- ── Emote definitions ─────────────────────────────────────────────────────
-- Each entry represents an emote that *could* exist in the game.
-- Add real entries here once emotes are created.
--
-- Fields:
--   Id          (string)  unique emote identifier
--   DisplayName (string)  shown in the emote slot label
--   Description (string)  shown in Shop / tooltip
--   IconKey     (string)  key for AssetCodes.Get() lookup (optional)
--   Icon/IconImage/Image/Thumbnail (string) direct image asset id (optional)
--   IconAssetId (string)  fallback direct asset id (optional)
--   DisplayIcon/Emoji (string) text or emoji thumbnail used when no image exists
--   AnimationId (string)  Roblox animation asset id (placeholder for now)
--   CoinCost    (number)  purchase price in the Shop
--   Cooldown    (number)  seconds before this emote can be played again
--   Looped      (boolean) nil/true repeats until the server cancels it; false plays once
--   UseRunning  (boolean) false/nil cancels on movement; true allows movement without canceling
--   IsFree      (boolean) granted to all players automatically if true
--
-- To add a new emote: copy one of the entries below, give it a unique Id,
-- set the DisplayName / Description / CoinCost / AnimationId, and register
-- an icon in AssetCodes.lua under the IconKey name.
EmoteConfig.Emotes = {
    {
        Id          = "wave",
        DisplayName = "Wave",
        Description = "Give a friendly wave.",
        IconKey     = "EmoteWave",
        DisplayIcon = "\u{1F44B}",
        -- REPLACE the animation id below with a real uploaded Wave animation asset.
        -- This placeholder (507770239) is a generic Roblox wave animation.
        AnimationId = "rbxassetid://507770239",
        CoinCost    = 0,
        Cooldown    = 1,
        Looped      = false,
        IsFree      = true,
    },
    {
        Id          = "dance",
        DisplayName = "Dance",
        Description = "Break into a dance.",
        IconKey     = "EmoteDance",
        DisplayIcon = "\u{1F57A}",
        AnimationId = "rbxassetid://122221160021248",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "i_want_money",
        DisplayName = "I Want Money",
        Description = "Make it rain.",
        IconKey     = "EmoteMoney",
        DisplayIcon = "\u{1F4B0}",
        AnimationId = "rbxassetid://100054170665680",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "take_the_l",
        DisplayName = "Take The L",
        Description = "Rub in the win.",
        IconKey     = "EmoteTakeTheL",
        DisplayIcon = "L",
        AnimationId = "rbxassetid://78954441062079",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "headless",
        DisplayName = "Headless",
        Description = "Go full headless mode.",
        IconKey     = "EmoteHeadless",
        DisplayIcon = "\u{1F480}",
        AnimationId = "rbxassetid://76606692073439",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "rat_dance",
        DisplayName = "Rat Dance",
        Description = "Do the rat dance.",
        IconKey     = "EmoteRatDance",
        DisplayIcon = "\u{1F400}",
        AnimationId = "rbxassetid://119292485335481",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "floss",
        DisplayName = "Floss",
        Description = "Hit the floss.",
        IconKey     = "EmoteFloss",
        DisplayIcon = "\u{1F57A}",
        AnimationId = "rbxassetid://130811327314009",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "dab",
        DisplayName = "Dab",
        Description = "Throw a quick dab.",
        IconKey     = "EmoteDab",
        DisplayIcon = "DAB",
        AnimationId = "rbxassetid://75003807251572",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = false,
        IsFree      = false,
    },
    {
        Id          = "macarena",
        DisplayName = "Macarena",
        Description = "Everybody do the Macarena.",
        IconKey     = "EmoteMacarena",
        DisplayIcon = "\u{1F483}",
        AnimationId = "rbxassetid://114789325138547",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "ride_the_pony",
        DisplayName = "Ride The Pony",
        Description = "Bring back the classic.",
        IconKey     = "EmoteRideThePony",
        DisplayIcon = "\u{1F434}",
        AnimationId = "rbxassetid://94326793594112",
        CoinCost    = 20,
        Cooldown    = 1,
        UseRunning  = true,
        IsFree      = false,
    },
    {
        Id          = "the_robot",
        DisplayName = "The Robot",
        Description = "Lock into robot mode.",
        IconKey     = "EmoteRobot",
        DisplayIcon = "\u{1F916}",
        AnimationId = "rbxassetid://140192311385186",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    -- Future emotes go here.
}

-- ── Cooldown defaults ─────────────────────────────────────────────────────
EmoteConfig.DEFAULT_COOLDOWN = 1  -- seconds
EmoteConfig.FALLBACK_DISPLAY_ICON = "\u{1F3AD}"

-- ── Lookup helpers ────────────────────────────────────────────────────────

local IMAGE_FIELDS = {
    "Icon",
    "IconImage",
    "IconAsset",
    "Image",
    "ImageId",
    "AssetId",
    "Thumbnail",
    "IconAssetId",
    "DisplayIcon",
}

local IMAGE_KEY_FIELDS = {
    "IconKey",
    "IconImageKey",
    "ImageKey",
    "ThumbnailKey",
    "DisplayIconKey",
}

local TEXT_ICON_FIELDS = {
    "Emoji",
    "DisplayIcon",
    "IconGlyph",
    "IconText",
    "Icon",
    "IconImage",
    "Image",
    "Thumbnail",
}

local function trim(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:match("^%s*(.-)%s*$")
end

local function normalizeLookupKey(value)
    if value == nil then
        return ""
    end
    local text = trim(tostring(value))
    if not text or text == "" then
        return ""
    end
    text = string.lower(text)
    text = text:gsub("[%s_%-%p]+", "")
    return text
end

local function normalizeImageAsset(asset)
    if type(asset) == "number" then
        return "rbxassetid://" .. tostring(asset)
    end
    if type(asset) ~= "string" then
        return nil
    end

    local value = trim(asset)
    if not value or value == "" then
        return nil
    end

    local lower = string.lower(value)
    if string.find(lower, "put_", 1, true) or string.find(lower, "placeholder", 1, true) then
        return nil
    end
    if tonumber(value) then
        return "rbxassetid://" .. value
    end
    if string.sub(lower, 1, 13) == "rbxassetid://"
        or string.sub(lower, 1, 11) == "rbxasset://"
        or string.sub(lower, 1, 11) == "rbxthumb://"
        or string.sub(lower, 1, 7) == "http://"
        or string.sub(lower, 1, 8) == "https://" then
        return value
    end
    return nil
end

local function getAssetByKey(assetCodes, key)
    if not assetCodes or type(assetCodes.Get) ~= "function" or not key then
        return nil
    end
    local ok, asset = pcall(function()
        return assetCodes.Get(key)
    end)
    if ok then
        return normalizeImageAsset(asset)
    end
    return nil
end

local function addSource(sources, source)
    if type(source) ~= "table" then
        return
    end
    for _, existing in ipairs(sources) do
        if existing == source then
            return
        end
    end
    table.insert(sources, source)
end

--- Return all emote definitions.
function EmoteConfig.GetAll()
    return EmoteConfig.Emotes
end

--- Return the emote definition for the given id, or nil.
function EmoteConfig.GetById(id)
    for _, def in ipairs(EmoteConfig.Emotes) do
        if def.Id == id then
            return def
        end
    end
    return nil
end

--- Return the emote definition by exact id first, then unique display/name fallback.
function EmoteConfig.GetByIdOrName(value)
    if value == nil then
        return nil
    end

    local text = trim(tostring(value))
    if not text or text == "" then
        return nil
    end

    local exact = EmoteConfig.GetById(text)
    if exact then
        return exact
    end

    local lowered = string.lower(text)
    for _, def in ipairs(EmoteConfig.Emotes) do
        if string.lower(tostring(def.Id or "")) == lowered
            or string.lower(tostring(def.DisplayName or "")) == lowered
            or string.lower(tostring(def.Name or "")) == lowered then
            return def
        end
    end

    local normalized = normalizeLookupKey(text)
    if normalized == "" then
        return nil
    end

    local match = nil
    for _, def in ipairs(EmoteConfig.Emotes) do
        local candidates = { def.Id, def.DisplayName, def.Name }
        for _, candidate in ipairs(candidates) do
            if normalizeLookupKey(candidate) == normalized then
                if match and match ~= def then
                    return nil
                end
                match = def
            end
        end
    end

    return match
end

--- Return the display name for an emote id (or a fallback string).
function EmoteConfig.GetDisplayName(id)
    local def = EmoteConfig.GetByIdOrName(id)
    return (def and def.DisplayName) or tostring(id)
end

local function getIconSources(emoteOrId)
    local sources = {}

    if type(emoteOrId) == "table" then
        addSource(sources, emoteOrId)
        addSource(sources, emoteOrId.Source)
        addSource(sources, EmoteConfig.GetByIdOrName(emoteOrId.Id))
        addSource(sources, EmoteConfig.GetByIdOrName(emoteOrId.DisplayName))
        addSource(sources, EmoteConfig.GetByIdOrName(emoteOrId.Name))
    else
        addSource(sources, EmoteConfig.GetByIdOrName(emoteOrId))
    end

    return sources
end

local function resolveImageIcon(emoteOrId, assetCodes)
    for _, source in ipairs(getIconSources(emoteOrId)) do
        for _, fieldName in ipairs(IMAGE_FIELDS) do
            local value = source[fieldName]
            local directAsset = normalizeImageAsset(value)
            if directAsset then
                return directAsset, fieldName
            end
            if type(value) == "string" then
                local keyedAsset = getAssetByKey(assetCodes, value)
                if keyedAsset then
                    return keyedAsset, fieldName
                end
            end
        end

        for _, fieldName in ipairs(IMAGE_KEY_FIELDS) do
            local keyedAsset = getAssetByKey(assetCodes, source[fieldName])
            if keyedAsset then
                return keyedAsset, fieldName
            end
        end
    end

    return nil, nil
end

local function resolveTextIcon(emoteOrId)
    for _, source in ipairs(getIconSources(emoteOrId)) do
        for _, fieldName in ipairs(TEXT_ICON_FIELDS) do
            local value = source[fieldName]
            if type(value) == "string" then
                local text = trim(value)
                if text and text ~= "" and not normalizeImageAsset(text) then
                    return text, fieldName
                end
            end
        end
    end
    return nil, nil
end

--- Return a resolved image asset string for an emote, if one exists.
function EmoteConfig.GetIconImage(emoteOrId, assetCodes)
    local asset = resolveImageIcon(emoteOrId, assetCodes)
    return asset
end

--- Return a text/emoji icon for an emote. Pass true to include the fallback icon.
function EmoteConfig.GetIconText(emoteOrId, includeFallback)
    local text = resolveTextIcon(emoteOrId)
    if text then
        return text
    end
    if includeFallback then
        return EmoteConfig.FALLBACK_DISPLAY_ICON
    end
    return nil
end

--- Return icon data for UI renderers: { Kind = "Image"|"Text", Value = string }.
function EmoteConfig.GetIconData(emoteOrId, assetCodes)
    local image, imageSource = resolveImageIcon(emoteOrId, assetCodes)
    if image then
        return { Kind = "Image", Value = image, SourceField = imageSource, IsFallback = false }
    end

    local text, textSource = resolveTextIcon(emoteOrId)
    if text then
        return { Kind = "Text", Value = text, SourceField = textSource, IsFallback = false }
    end

    return { Kind = "Text", Value = EmoteConfig.FALLBACK_DISPLAY_ICON, SourceField = "Fallback", IsFallback = true }
end

return EmoteConfig
