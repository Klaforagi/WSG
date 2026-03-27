--------------------------------------------------------------------------------
-- SalvageShopConfig.lua  –  Salvage shop item definitions
--
-- Items purchasable with Salvage currency in the Salvage Shop tab.
--
-- Each entry defines:
--   Id            – unique string identifier
--   DisplayName   – player-facing name
--   Description   – short description
--   Category      – "Skin" | "Effect" | "Crate"
--   SalvagePrice  – amount of Salvage currency required
--   RewardType    – "Skin" | "Effect" | "Crate" (how the reward is granted)
--   RewardId      – the Id used by the target reward system
--   Rarity        – display rarity tag (cosmetic, for card styling)
--   IconGlyph     – fallback text glyph if no image asset is available
--   Unique        – true = can only be purchased once (blocks if already owned)
--   Enabled       – false = hidden from shop; true = available for purchase
--------------------------------------------------------------------------------

local SalvageShopConfig = {}

SalvageShopConfig.Items = {
    {
        Id           = "salvage_trail_emerald",
        DisplayName  = "Emerald Trail",
        Description  = "A vivid green dash trail forged from salvage.",
        Category     = "Effect",
        SalvagePrice = 120,
        RewardType   = "Effect",
        RewardId     = "EmeraldTrail",
        Rarity       = "Rare",
        IconGlyph    = "\u{2550}",
        Unique       = true,
        Enabled      = true,
    },
    {
        Id           = "salvage_skin_iron",
        DisplayName  = "Iron Knight",
        Description  = "Battered armor from countless salvaged weapons.",
        Category     = "Skin",
        SalvagePrice = 300,
        RewardType   = "Skin",
        RewardId     = "IronKnight",
        Rarity       = "Epic",
        IconGlyph    = "\u{1F6E1}",
        Unique       = true,
        Enabled      = true,
    },
    {
        Id           = "salvage_crate_melee",
        DisplayName  = "Salvage Melee Crate",
        Description  = "A melee weapon crate, paid with salvage.",
        Category     = "Crate",
        SalvagePrice = 60,
        RewardType   = "Crate",
        RewardId     = "MeleeCrate",
        Rarity       = "Common",
        IconGlyph    = "\u{1F4E6}",
        Unique       = false,
        Enabled      = true,
    },
    {
        Id           = "salvage_crate_ranged",
        DisplayName  = "Salvage Ranged Crate",
        Description  = "A ranged weapon crate, paid with salvage.",
        Category     = "Crate",
        SalvagePrice = 60,
        RewardType   = "Crate",
        RewardId     = "RangedCrate",
        Rarity       = "Common",
        IconGlyph    = "\u{1F4E6}",
        Unique       = false,
        Enabled      = true,
    },
    {
        Id           = "salvage_trail_gold",
        DisplayName  = "Golden Trail",
        Description  = "A shimmering gold dash trail.",
        Category     = "Effect",
        SalvagePrice = 200,
        RewardType   = "Effect",
        RewardId     = "GoldenTrail",
        Rarity       = "Epic",
        IconGlyph    = "\u{2550}",
        Unique       = true,
        Enabled      = true,
    },
}

--- Lookup helper: find an item entry by Id.
function SalvageShopConfig.GetById(id)
    for _, item in ipairs(SalvageShopConfig.Items) do
        if item.Id == id then return item end
    end
    return nil
end

--- Return all currently enabled items.
function SalvageShopConfig.GetEnabled()
    local result = {}
    for _, item in ipairs(SalvageShopConfig.Items) do
        if item.Enabled then
            table.insert(result, item)
        end
    end
    return result
end

return SalvageShopConfig
