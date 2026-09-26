--------------------------------------------------------------------------------
-- MarketCatalog.lua
-- Shared adapter that groups existing cosmetic configs for the Market stall's trail and emote sections.
--------------------------------------------------------------------------------

local ReplicatedStorage = script.Parent

local EffectDefs = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
    if mod and mod:IsA("ModuleScript") then
        EffectDefs = require(mod)
    end
end)

local EmoteConfig = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("EmoteConfig")
    if mod and mod:IsA("ModuleScript") then
        EmoteConfig = require(mod)
    end
end)

local MarketCatalog = {}

MarketCatalog.SECTIONS = {
    { Id = "Trails", Category = "Trail", Header = "TRAILS", SortOrder = 20 },
    { Id = "Emotes", Category = "Emote", Header = "EMOTES", SortOrder = 30 },
}

local function sortedCopy(list)
    local result = {}
    if type(list) == "table" then
        for _, item in ipairs(list) do
            table.insert(result, item)
        end
    end
    table.sort(result, function(a, b)
        local orderA = tonumber(a.SortOrder) or math.huge
        local orderB = tonumber(b.SortOrder) or math.huge
        if orderA ~= orderB then
            return orderA < orderB
        end
        return tostring(a.DisplayName or a.Id or "") < tostring(b.DisplayName or b.Id or "")
    end)
    return result
end

local function normalizeTrail(def)
    local coinPrice = tonumber(def.CoinCost) or 0
    return {
        Id = def.Id,
        Category = "Trail",
        Type = "Trail",
        DisplayName = def.DisplayName or def.Id,
        Description = def.Description or "",
        CoinPrice = coinPrice,
        Currency = coinPrice > 0 and "Coins" or nil,
        SortOrder = tonumber(def.SortOrder) or 0,
        SubType = def.SubType or "DashTrail",
        Color = def.Color,
        TrailColorSequence = def.TrailColorSequence,
        GhostColors = def.GhostColors,
        IsRainbow = def.IsRainbow == true,
        IsTeamTrail = def.IsTeamTrail == true,
        IconGlyph = def.IconGlyph,
        IsFree = def.IsFree == true,
        ShopVisible = def.ShopVisible,
        Source = def,
    }
end

local function normalizeEmote(def)
    local coinPrice = tonumber(def.CoinCost) or 0
    return {
        Id = def.Id,
        Category = "Emote",
        Type = "Emote",
        DisplayName = def.DisplayName or def.Id,
        Description = def.Description or "",
        CoinPrice = coinPrice,
        Currency = coinPrice > 0 and "Coins" or nil,
        SortOrder = tonumber(def.SortOrder) or 0,
        Icon = def.Icon,
        IconImage = def.IconImage,
        IconAsset = def.IconAsset,
        IconAssetId = def.IconAssetId,
        Image = def.Image,
        ImageId = def.ImageId,
        AssetId = def.AssetId,
        Thumbnail = def.Thumbnail,
        Emoji = def.Emoji,
        DisplayIcon = def.DisplayIcon,
        IconGlyph = def.IconGlyph,
        IconKey = def.IconKey,
        IconImageKey = def.IconImageKey,
        ImageKey = def.ImageKey,
        ThumbnailKey = def.ThumbnailKey,
        DisplayIconKey = def.DisplayIconKey,
        AnimationId = def.AnimationId,
        Cooldown = def.Cooldown,
        Looped = def.Looped,
        UseRunning = def.UseRunning,
        IsFree = def.IsFree == true,
        Source = def,
    }
end

function MarketCatalog.GetItemsByCategory(category)
    local items = {}

    if category == "Trail" then
        local trails = {}
        if EffectDefs and type(EffectDefs.GetBySubType) == "function" then
            trails = EffectDefs.GetBySubType("DashTrail")
        end
        for _, def in ipairs(sortedCopy(trails)) do
            if type(def.Id) == "string" and def.Id ~= "" then
                table.insert(items, normalizeTrail(def))
            end
        end
        return items
    end

    if category == "Emote" then
        local emotes = {}
        if EmoteConfig and type(EmoteConfig.GetAll) == "function" then
            emotes = EmoteConfig.GetAll()
        end
        for _, def in ipairs(sortedCopy(emotes)) do
            if type(def.Id) == "string" and def.Id ~= "" and def.IsFree ~= true then
                table.insert(items, normalizeEmote(def))
            end
        end
        return items
    end

    return items
end

function MarketCatalog.GetSections()
    local sections = {}
    for _, sectionDef in ipairs(MarketCatalog.SECTIONS) do
        table.insert(sections, {
            Id = sectionDef.Id,
            Category = sectionDef.Category,
            Header = sectionDef.Header,
            SortOrder = sectionDef.SortOrder,
            Items = MarketCatalog.GetItemsByCategory(sectionDef.Category),
        })
    end
    return sections
end

function MarketCatalog.GetByCategoryAndId(category, id)
    for _, item in ipairs(MarketCatalog.GetItemsByCategory(category)) do
        if item.Id == id then
            return item
        end
    end
    return nil
end

function MarketCatalog.GetSlotCount()
    if EmoteConfig then
        return tonumber(EmoteConfig.SLOT_COUNT) or 8
    end
    return 8
end

return MarketCatalog
