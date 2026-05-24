--------------------------------------------------------------------------------
-- CosmeticsCatalog.lua
-- Shared adapter that groups existing cosmetic configs for the world Cosmetics UI.
--------------------------------------------------------------------------------

local ReplicatedStorage = script.Parent

local SkinDefinitions = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("SkinDefinitions")
    if mod and mod:IsA("ModuleScript") then
        SkinDefinitions = require(mod)
    end
end)

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

local CosmeticsCatalog = {}

CosmeticsCatalog.SECTIONS = {
    { Id = "Skins", Category = "Skin", Header = "SKINS", SortOrder = 10 },
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

local function normalizeSkin(def)
    local coinPrice = 0
    if SkinDefinitions and type(SkinDefinitions.GetCoinPrice) == "function" then
        coinPrice = SkinDefinitions.GetCoinPrice(def)
    elseif type(def.CoinPrice) == "number" then
        coinPrice = def.CoinPrice
    elseif type(def.Price) == "number" then
        coinPrice = def.Price
    end

    local robuxProductId = 0
    if SkinDefinitions and type(SkinDefinitions.GetRobuxProductId) == "function" then
        robuxProductId = SkinDefinitions.GetRobuxProductId(def)
    else
        robuxProductId = tonumber(def.RobuxProductId) or 0
    end

    return {
        Id = def.Id,
        Category = "Skin",
        Type = "Skin",
        DisplayName = def.DisplayName or def.Id,
        Description = def.Description or "",
        CoinPrice = coinPrice,
        Currency = coinPrice > 0 and "Coins" or nil,
        RobuxProductId = robuxProductId,
        RobuxPrice = def.RobuxPrice,
        Rarity = def.Rarity or "Common",
        SortOrder = tonumber(def.SortOrder) or 0,
        IconKey = def.IconKey,
        PreviewImageKey = def.PreviewImageKey,
        IsDefault = def.IsDefault == true,
        Source = def,
    }
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
        Rarity = def.Rarity or "Common",
        SortOrder = tonumber(def.SortOrder) or 0,
        SubType = def.SubType or "DashTrail",
        Color = def.Color,
        TrailColorSequence = def.TrailColorSequence,
        GhostColors = def.GhostColors,
        IsRainbow = def.IsRainbow == true,
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
        Rarity = def.Rarity or "Common",
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

function CosmeticsCatalog.GetItemsByCategory(category)
    local items = {}

    if category == "Skin" then
        local skins = {}
        if SkinDefinitions and type(SkinDefinitions.GetStallSkins) == "function" then
            skins = SkinDefinitions.GetStallSkins()
        end
        for _, def in ipairs(sortedCopy(skins)) do
            if type(def.Id) == "string" and def.Id ~= "" then
                table.insert(items, normalizeSkin(def))
            end
        end
        return items
    end

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
            if type(def.Id) == "string" and def.Id ~= "" then
                table.insert(items, normalizeEmote(def))
            end
        end
        return items
    end

    return items
end

function CosmeticsCatalog.GetSections()
    local sections = {}
    for _, sectionDef in ipairs(CosmeticsCatalog.SECTIONS) do
        table.insert(sections, {
            Id = sectionDef.Id,
            Category = sectionDef.Category,
            Header = sectionDef.Header,
            SortOrder = sectionDef.SortOrder,
            Items = CosmeticsCatalog.GetItemsByCategory(sectionDef.Category),
        })
    end
    return sections
end

function CosmeticsCatalog.GetByCategoryAndId(category, id)
    for _, item in ipairs(CosmeticsCatalog.GetItemsByCategory(category)) do
        if item.Id == id then
            return item
        end
    end
    return nil
end

function CosmeticsCatalog.GetSlotCount()
    if EmoteConfig then
        return tonumber(EmoteConfig.SLOT_COUNT) or 8
    end
    return 8
end

return CosmeticsCatalog
