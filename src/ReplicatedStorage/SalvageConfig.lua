--------------------------------------------------------------------------------
-- SalvageConfig.lua  –  Shared salvage value definitions (server + client)
--
-- Defines how much Salvage currency each item rarity is worth, plus rules
-- for eligibility.  Readable by both server (for awarding) and client
-- (for displaying predicted values in UI).
--------------------------------------------------------------------------------

local SalvageConfig = {}

--------------------------------------------------------------------------------
-- RARITY → SALVAGE VALUE MAPPING
--
-- >>> EDIT VALUES HERE to rebalance salvage rewards <<<
-- If you add new rarities to CrateConfig.Rarities, add a matching entry here.
--------------------------------------------------------------------------------
SalvageConfig.ValueByRarity = {
    Common    = 5,
    Uncommon  = 12,
    Rare      = 25,
    Epic      = 45,
    Legendary = 80,
}

SalvageConfig.SizeBonusByTier = {
    Tiny  = 10,
    Large = 10,
    Giant = 25,
    King  = 50,
}

SalvageConfig.EnchantBonus = 25

local CANONICAL_TIER_NAMES = {
    tiny = "Tiny",
    normal = "Normal",
    large = "Large",
    giant = "Giant",
    king = "King",
}

local function normalizeTierName(tierName)
    if type(tierName) ~= "string" then
        return nil
    end

    local trimmed = tierName:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end

    return CANONICAL_TIER_NAMES[string.lower(trimmed)] or trimmed
end

local function hasEnchant(enchantName)
    if type(enchantName) ~= "string" then
        return false
    end

    local trimmed = enchantName:match("^%s*(.-)%s*$")
    return trimmed ~= nil and trimmed ~= "" and trimmed ~= "None"
end

--------------------------------------------------------------------------------
-- ELIGIBILITY RULES (queried by SalvageService; also used client-side for UI)
--------------------------------------------------------------------------------

-- Items with source == "Starter" can never be salvaged
SalvageConfig.BlockStarter = true

-- Items that are currently equipped cannot be salvaged
SalvageConfig.BlockEquipped = true

-- Items that are favorited cannot be salvaged (safety net)
SalvageConfig.BlockFavorited = true

-- Specific weapon names that should never be salvaged regardless of rarity
-- (e.g., promo exclusives, default starter names)
SalvageConfig.UnsalvageableWeapons = {
    ["Starter Sword"]    = true,
    ["Starter Slingshot"] = true,
}

--------------------------------------------------------------------------------
-- DISPLAY HELPERS (for client UI)
--------------------------------------------------------------------------------
SalvageConfig.CurrencyName = "Shards"
SalvageConfig.CurrencyGlyph = "\u{25C6}"
SalvageConfig.CurrencyColor = Color3.fromRGB(35, 190, 75)

--------------------------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------------------------

--- Get the salvage value for a given rarity string.
--- Returns the numeric value, or nil if the rarity has no defined value.
function SalvageConfig.GetValueForRarity(rarity)
    return SalvageConfig.ValueByRarity[rarity]
end

function SalvageConfig.GetSizeBonus(tierName)
    local normalizedTierName = normalizeTierName(tierName)
    if not normalizedTierName then
        return 0
    end

    return SalvageConfig.SizeBonusByTier[normalizedTierName] or 0
end

function SalvageConfig.GetEnchantBonus(enchantName)
    if not hasEnchant(enchantName) then
        return 0
    end

    return SalvageConfig.EnchantBonus or 0
end

function SalvageConfig.GetValueForItem(itemData)
    if type(itemData) ~= "table" then
        return nil
    end

    local baseValue = SalvageConfig.GetValueForRarity(itemData.rarity)
    if not baseValue or baseValue <= 0 then
        return baseValue
    end

    return baseValue
        + SalvageConfig.GetSizeBonus(itemData.sizeTier)
        + SalvageConfig.GetEnchantBonus(itemData.enchantName)
end

return SalvageConfig
