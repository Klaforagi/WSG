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
SalvageConfig.CurrencyName = "Salvage"
SalvageConfig.CurrencyGlyph = "\u{2699}" -- ⚙
SalvageConfig.CurrencyColor = Color3.fromRGB(35, 190, 75)

--------------------------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------------------------

--- Get the salvage value for a given rarity string.
--- Returns the numeric value, or nil if the rarity has no defined value.
function SalvageConfig.GetValueForRarity(rarity)
    return SalvageConfig.ValueByRarity[rarity]
end

return SalvageConfig
