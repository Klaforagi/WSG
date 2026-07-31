--------------------------------------------------------------------------------
-- ShopCatalog.lua
-- Shared catalog for the Shop menu, gamepasses, and starter pack receipt data.
-- Replace the placeholder Roblox IDs with the real ones from Creator Dashboard.
--------------------------------------------------------------------------------

local ShopCatalog = {}

ShopCatalog.Items = {
    {
        Id = "starter_pack",
        SortOrder = 1,
        Kind = "Product",
        DisplayName = "Starter Pack",
        BadgeText = "BUNDLE",
        Description = "1,000 Coins, 500 Salvage, and 3 Keys.",
        PriceRobux = 499,
        ProductId = 0,
        AccentColor = Color3.fromRGB(255, 188, 64),
        IconText = "SP",
        Reward = {
            Coins = 1000,
            Salvage = 500,
            Keys = 3,
        },
    },
    {
        Id = "vip_gamepass",
        SortOrder = 2,
        Kind = "GamePass",
        DisplayName = "VIP Gamepass",
        BadgeText = "VIP",
        Description = "[VIP] chat prefix plus 0.2x extra Coins, XP, and Mastery from all sources.",
        PriceRobux = 799,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(232, 72, 72),
        IconText = "VIP",
        OwnedAttribute = "ShopVIPOwned",
        ChatPrefix = "[VIP]",
        Bonus = {
            Coins = 0.2,
            XP = 0.2,
            Mastery = 0.2,
        },
    },
    {
        Id = "coins_2x_gamepass",
        SortOrder = 3,
        Kind = "GamePass",
        DisplayName = "2x Coins Gamepass",
        BadgeText = "COINS",
        Description = "Doubles all Coins from kills, quests, achievements, and other rewards.",
        PriceRobux = 399,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(255, 145, 20),
        IconText = "2X",
        OwnedAttribute = "ShopCoins2xOwned",
        Bonus = {
            Coins = 1,
        },
    },
    {
        Id = "xp_2x_gamepass",
        SortOrder = 4,
        Kind = "GamePass",
        DisplayName = "2x XP Gamepass",
        BadgeText = "XP",
        Description = "Doubles all XP from every source.",
        PriceRobux = 299,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(110, 180, 255),
        IconText = "XP",
        OwnedAttribute = "ShopXP2xOwned",
        Bonus = {
            XP = 1,
        },
    },
    {
        Id = "lucky_gamepass",
        SortOrder = 5,
        Kind = "GamePass",
        DisplayName = "Lucky Gamepass",
        BadgeText = "LUCK",
        Description = "Doubles Epic and Legendary odds in Weapon Crates.",
        PriceRobux = 299,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(70, 178, 96),
        IconText = "LCK",
        OwnedAttribute = "ShopLuckyOwned",
        LuckyCrateId = "WeaponCrate",
        LuckyWeights = {
            Common = 42.4,
            Uncommon = 37.6,
            Rare = 10,
            Epic = 9,
            Legendary = 1,
        },
    },
    {
        Id = "bandage_gamepass",
        SortOrder = 6,
        Kind = "GamePass",
        DisplayName = "Heal Gamepass",
        BadgeText = "HEAL",
        Description = "Unlocks the Heal tool and teammate healing.",
        PriceRobux = 349,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(114, 236, 196),
        IconText = "+",
        OwnedAttribute = "ShopBandageOwned",
    },
    {
        Id = "mastery_2x_gamepass",
        SortOrder = 7,
        Kind = "GamePass",
        DisplayName = "2x Mastery Gamepass",
        BadgeText = "MASTERY",
        Description = "Doubles all Mastery XP from every source.",
        PriceRobux = 399,
        GamePassId = 0,
        AccentColor = Color3.fromRGB(180, 120, 255),
        IconText = "MSY",
        OwnedAttribute = "ShopMastery2xOwned",
        Bonus = {
            Mastery = 1,
        },
    },
}

local function copyTable(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function sortByDisplayName(a, b)
    local orderA = tonumber(a.SortOrder) or 0
    local orderB = tonumber(b.SortOrder) or 0
    if orderA ~= orderB then
        return orderA < orderB
    end
    return tostring(a.DisplayName or a.Id or "") < tostring(b.DisplayName or b.Id or "")
end

function ShopCatalog.GetItems()
    local items = {}
    for _, item in ipairs(ShopCatalog.Items) do
        table.insert(items, item)
    end
    table.sort(items, sortByDisplayName)
    return items
end

function ShopCatalog.GetGamepassItems()
    local items = {}
    for _, item in ipairs(ShopCatalog.GetItems()) do
        if item.Kind == "GamePass" then
            table.insert(items, item)
        end
    end
    return items
end

function ShopCatalog.GetProductItems()
    local items = {}
    for _, item in ipairs(ShopCatalog.GetItems()) do
        if item.Kind == "Product" then
            table.insert(items, item)
        end
    end
    return items
end

function ShopCatalog.GetById(itemId)
    if type(itemId) ~= "string" then
        return nil
    end
    for _, item in ipairs(ShopCatalog.Items) do
        if item.Id == itemId then
            return item
        end
    end
    return nil
end

function ShopCatalog.GetByProductId(productId)
    local targetId = math.floor(tonumber(productId) or 0)
    if targetId <= 0 then
        return nil
    end
    for _, item in ipairs(ShopCatalog.Items) do
        if item.Kind == "Product" and math.floor(tonumber(item.ProductId) or 0) == targetId then
            return item
        end
    end
    return nil
end

function ShopCatalog.GetByGamePassId(gamePassId)
    local targetId = math.floor(tonumber(gamePassId) or 0)
    if targetId <= 0 then
        return nil
    end
    for _, item in ipairs(ShopCatalog.Items) do
        if item.Kind == "GamePass" and math.floor(tonumber(item.GamePassId) or 0) == targetId then
            return item
        end
    end
    return nil
end

function ShopCatalog.GetStarterPackReward()
    local item = ShopCatalog.GetById("starter_pack")
    return item and copyTable(item.Reward or {}) or {}
end

function ShopCatalog.GetLuckyWeights()
    local item = ShopCatalog.GetById("lucky_gamepass")
    return item and copyTable(item.LuckyWeights or {}) or nil
end

return ShopCatalog