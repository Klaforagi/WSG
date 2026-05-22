--------------------------------------------------------------------------------
-- SkinDefinitions.lua  –  Shared skin config (ReplicatedStorage)
--
-- Each skin entry defines: Id, DisplayName, Description, Price, Rarity,
-- Category, ShopVisible, IsDefault, ApplicationType, stall metadata, and
-- visual references.
--
-- Readable by both server and client.
--------------------------------------------------------------------------------

local SkinDefinitions = {}

SkinDefinitions.Skins = {
    ---------------------------------------------------------------------------
    -- DEFAULT  –  legacy fallback for the player's normal Roblox avatar
    ---------------------------------------------------------------------------
    {
        Id              = "Default",
        DisplayName     = "Default",
        Description     = "Your original Roblox avatar.",
        Price           = 0,
        CoinPrice       = 0,
        RobuxProductId  = 0,
        RobuxPrice      = nil,
        Rarity          = "Common",
        Category        = "Skin",
        ShopVisible     = false,   -- never shown in shop
        InventoryVisible = false,
        StallVisible    = false,
        SortOrder       = 0,
        IsDefault       = true,
        ApplicationType = "Avatar", -- restores normal avatar
    },

    ---------------------------------------------------------------------------
    -- KNIGHT  –  purchasable cosmetic skin
    ---------------------------------------------------------------------------
    {
        Id              = "Knight",
        DisplayName     = "Knight",
        Description     = "Don a full suit of knightly armor.",
        Price           = 150,
        CoinPrice       = 150,
        RobuxProductId  = 0,
        RobuxPrice      = nil,
        Rarity          = "Epic",
        Category        = "Skin",
        ShopVisible     = true,
        InventoryVisible = true,
        StallVisible    = true,
        SortOrder       = 10,
        IsDefault       = false,
        ApplicationType = "ReplacementModel", -- uses ServerStorage.Skins.Knight
        TemplateName    = "Knight",
        IconKey         = "KnightPreview",
        PreviewImageKey = "KnightPreview",

        -- Visual spec: shirt/pants overrides + welded armor parts
        -- All parts are built programmatically on the server
        ShirtColor      = Color3.fromRGB(50, 50, 55),
        PantsColor      = Color3.fromRGB(45, 42, 48),
        ArmorColor      = Color3.fromRGB(160, 165, 175),
        AccentColor     = Color3.fromRGB(200, 170, 50),  -- gold trim
        HelmetColor     = Color3.fromRGB(140, 145, 155),
        VisorColor      = Color3.fromRGB(30, 30, 35),
    },

    ---------------------------------------------------------------------------
    -- GOBLIN  –  purchasable replacement-model skin
    ---------------------------------------------------------------------------
    {
        Id              = "Goblin",
        DisplayName     = "Goblin",
        Description     = "Take on the look of a wiry goblin raider.",
        Price           = 100,
        CoinPrice       = 100,
        RobuxProductId  = 0,
        RobuxPrice      = nil,
        Rarity          = "Rare",
        Category        = "Skin",
        ShopVisible     = true,
        InventoryVisible = true,
        StallVisible    = true,
        SortOrder       = 20,
        IsDefault       = false,
        ApplicationType = "ReplacementModel", -- uses ServerStorage.Skins.Goblin
        TemplateName    = "Goblin",
    },

    ---------------------------------------------------------------------------
    -- IRON KNIGHT  –  purchasable dark armor skin
    ---------------------------------------------------------------------------
    {
        Id              = "IronKnight",
        DisplayName     = "Iron Knight",
        Description     = "A battle-worn suit of dark iron plate armor.",
        Price           = 300,
        CoinPrice       = 300,
        RobuxProductId  = 0,
        RobuxPrice      = nil,
        Rarity          = "Epic",
        Category        = "Skin",
        ShopVisible     = true,
        InventoryVisible = true,
        StallVisible    = true,
        SortOrder       = 30,
        IsDefault       = false,
        ApplicationType = "Cosmetic",
        IconKey         = "IronKnightPreview",
        PreviewImageKey = "IronKnightPreview",

        ShirtColor      = Color3.fromRGB(35, 35, 40),
        PantsColor      = Color3.fromRGB(30, 28, 32),
        ArmorColor      = Color3.fromRGB(90, 95, 100),
        AccentColor     = Color3.fromRGB(35, 190, 75),   -- salvage green trim
        HelmetColor     = Color3.fromRGB(80, 85, 90),
        VisorColor      = Color3.fromRGB(20, 22, 25),
    },
}

--------------------------------------------------------------------------------
-- Lookup helpers
--------------------------------------------------------------------------------
function SkinDefinitions.GetById(id)
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.Id == id then return def end
    end
    return nil
end

function SkinDefinitions.GetAll()
    return SkinDefinitions.Skins
end

function SkinDefinitions.GetShopSkins()
    local list = {}
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.ShopVisible then
            table.insert(list, def)
        end
    end
    return list
end

function SkinDefinitions.GetInventorySkins()
    local list = {}
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.InventoryVisible then
            table.insert(list, def)
        end
    end
    return list
end

function SkinDefinitions.GetCoinPrice(def)
    if type(def) ~= "table" then
        return 0
    end
    if type(def.CoinPrice) == "number" then
        return def.CoinPrice
    end
    if type(def.Price) == "number" then
        return def.Price
    end
    return 0
end

function SkinDefinitions.IsCoinPurchasable(def)
    if type(def) ~= "table" or def.IsDefault then
        return false
    end
    return SkinDefinitions.GetCoinPrice(def) > 0
end

function SkinDefinitions.GetStallSkins()
    local list = {}
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.StallVisible then
            table.insert(list, def)
        end
    end

    table.sort(list, function(a, b)
        local orderA = tonumber(a.SortOrder) or math.huge
        local orderB = tonumber(b.SortOrder) or math.huge
        if orderA ~= orderB then
            return orderA < orderB
        end
        return tostring(a.DisplayName or a.Id or "") < tostring(b.DisplayName or b.Id or "")
    end)

    return list
end

function SkinDefinitions.GetRobuxProductId(def)
    if type(def) ~= "table" then
        return 0
    end
    return tonumber(def.RobuxProductId) or 0
end

function SkinDefinitions.IsRobuxPurchasable(def)
    if type(def) ~= "table" or def.IsDefault then
        return false
    end
    return SkinDefinitions.GetRobuxProductId(def) > 0
end

function SkinDefinitions.GetDefault()
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.IsDefault then return def end
    end
    return SkinDefinitions.Skins[1]
end

return SkinDefinitions
