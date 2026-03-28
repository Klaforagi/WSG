--------------------------------------------------------------------------------
-- CrateConfig.lua  –  Shared crate definitions (server + client)
--
-- 4 crate types:
--   MeleeCrate          – Coins, melee weapons, all rarities
--   RangedCrate         – Coins, ranged weapons, all rarities
--   PremiumMeleeCrate   – Keys, melee weapons, Rare+ only (no Commons)
--   PremiumRangedCrate  – Keys, ranged weapons, Rare+ only (no Commons)
--
-- Each crate has: currency, cost, per-crate rarity weights, and an auto-built
-- weapon pool filtered by weapon type and available rarities.
--------------------------------------------------------------------------------

local CrateConfig = {}

--------------------------------------------------------------------------------
-- RARITY DEFINITIONS  (color, display label)
-- Global weights are a fallback for any crate that doesn't define its own
-- `rarities` table.  Currently all 4 crates define one, so these are mainly
-- used for color/label lookups.
--------------------------------------------------------------------------------
CrateConfig.Rarities = {
    Common    = { weight = 81, color = Color3.fromRGB(180, 180, 180), label = "Common"    },
    Rare      = { weight = 15, color = Color3.fromRGB(60, 140, 255),  label = "Rare"      },
    Epic      = { weight = 3,  color = Color3.fromRGB(180, 60, 255),  label = "Epic"      },
    Legendary = { weight = 1,  color = Color3.fromRGB(255, 180, 30),  label = "Legendary" },
}

-- Ordered for display (highest first)
CrateConfig.RarityOrder = { "Legendary", "Epic", "Rare", "Common" }

--------------------------------------------------------------------------------
-- WEAPON-TO-RARITY MAPPING
--
-- ┌────────────┬────────────────┬────────────────┐
-- │ Rarity     │ Melee          │ Ranged         │
-- ├────────────┼────────────────┼────────────────┤
-- │ Common     │ Wooden Sword   │ Slingshot      │
-- │ Rare       │ Dagger         │ Shortbow       │
-- │ Epic       │ Sword          │ Longbow        │
-- │ Legendary  │ Spear          │ Xbow           │
-- └────────────┴────────────────┴────────────────┘
--
-- >>> TO REASSIGN WEAPONS: move entries between the rarity keys below. <<<
-- >>> Pools are auto-built from this table – no pool edits needed.     <<<
--------------------------------------------------------------------------------
CrateConfig.WeaponsByRarity = {
    Common    = {
        { weapon = "Wooden Sword", category = "Melee"  },
        { weapon = "Punisher",    category = "Melee"  },
        { weapon = "Slingshot",    category = "Ranged" },
    },
    Rare      = {
        { weapon = "Dagger",   category = "Melee"  },
        { weapon = "Shortbow", category = "Ranged" },
    },
    Epic      = {
        { weapon = "Sword",   category = "Melee"  },
        { weapon = "Longbow", category = "Ranged" },
    },
    Legendary = {
        { weapon = "Spear", category = "Melee"  },
        { weapon = "Xbow",  category = "Ranged" },
    },
}

--------------------------------------------------------------------------------
-- CRATE DEFINITIONS
--
-- Fields:
--   id          – internal identifier (matches key in Crates table)
--   displayName – player-facing name shown in UI
--   description – short description on crate card
--   weaponType  – "Melee" or "Ranged" (filters WeaponsByRarity for pool)
--   category    – same as weaponType (used by CrateService as fallback)
--   currency    – "Coins" or "Keys"
--   cost        – amount of currency required to open
--   price       – alias for cost (backwards compat)
--   iconGlyph   – emoji/glyph shown on the crate card
--   rarities    – per-crate rarity weights (only listed rarities can drop)
--   pool        – auto-built at bottom of file; do NOT edit manually
--------------------------------------------------------------------------------
CrateConfig.Crates = {

    ---------------------------------------------------------------------------
    -- BASIC CRATES  (Coins)
    ---------------------------------------------------------------------------

    MeleeCrate = {
        id          = "MeleeCrate",
        displayName = "Melee Crate",
        description = "Contains a random melee weapon.",
        weaponType  = "Melee",
        category    = "Melee",
        currency    = "Coins",
        cost        = 100,
        price       = 100,
        iconGlyph   = "\u{2694}",        -- ⚔

        -- >>> EDIT PERCENTAGES HERE to rebalance melee crate odds <<<
        rarities = {
            Common    = 81,
            Rare      = 15,
            Epic      = 3,
            Legendary = 1,
        },

        pool = {},  -- auto-built below
    },

    RangedCrate = {
        id          = "RangedCrate",
        displayName = "Ranged Crate",
        description = "Contains a random ranged weapon.",
        weaponType  = "Ranged",
        category    = "Ranged",
        currency    = "Coins",
        cost        = 100,
        price       = 100,
        iconGlyph   = "\u{1F3F9}",      -- 🏹

        -- >>> EDIT PERCENTAGES HERE to rebalance ranged crate odds <<<
        rarities = {
            Common    = 81,
            Rare      = 15,
            Epic      = 3,
            Legendary = 1,
        },

        pool = {},  -- auto-built below
    },

    ---------------------------------------------------------------------------
    -- PREMIUM CRATES  (Keys – no Commons!)
    ---------------------------------------------------------------------------

    PremiumMeleeCrate = {
        id          = "PremiumMeleeCrate",
        displayName = "Premium Melee Crate",
        description = "A premium melee crate. Costs Keys. No Commons!",
        weaponType  = "Melee",
        category    = "Melee",
        currency    = "Keys",
        cost        = 1,
        price       = 1,
        iconGlyph   = "\u{1F5E1}",      -- 🗡

        -- >>> EDIT PERCENTAGES HERE to rebalance premium melee odds <<<
        -- No Common entry = Commons can never drop from this crate
        rarities = {
            Rare      = 80,
            Epic      = 15,
            Legendary = 5,
        },

        pool = {},  -- auto-built below
    },

    PremiumRangedCrate = {
        id          = "PremiumRangedCrate",
        displayName = "Premium Ranged Crate",
        description = "A premium ranged crate. Costs Keys. No Commons!",
        weaponType  = "Ranged",
        category    = "Ranged",
        currency    = "Keys",
        cost        = 1,
        price       = 1,
        iconGlyph   = "\u{1F3AF}",      -- 🎯

        -- >>> EDIT PERCENTAGES HERE to rebalance premium ranged odds <<<
        -- No Common entry = Commons can never drop from this crate
        rarities = {
            Rare      = 80,
            Epic      = 15,
            Legendary = 5,
        },

        pool = {},  -- auto-built below
    },
}

--------------------------------------------------------------------------------
-- AUTO-BUILD POOLS
--
-- For each crate, populates the pool from WeaponsByRarity filtered by:
--   1. weaponType  – only weapons matching the crate's weapon type
--   2. rarities    – only weapons whose rarity key exists in the crate
--------------------------------------------------------------------------------
for crateId, def in pairs(CrateConfig.Crates) do
    if def.rarities and def.weaponType then
        local pool = {}
        for rarity, _ in pairs(def.rarities) do
            local weapons = CrateConfig.WeaponsByRarity[rarity]
            if weapons then
                for _, entry in ipairs(weapons) do
                    if entry.category == def.weaponType then
                        table.insert(pool, {
                            weapon   = entry.weapon,
                            rarity   = rarity,
                            category = entry.category,
                        })
                    end
                end
            end
        end
        def.pool = pool
    end
end

-- Ordered list for UI display (fills left-to-right, top-to-bottom in 2x2 grid)
-- Row 1: Melee Crate, Premium Melee Crate
-- Row 2: Ranged Crate, Premium Ranged Crate
CrateConfig.CrateOrder = { "MeleeCrate", "PremiumMeleeCrate", "RangedCrate", "PremiumRangedCrate" }

--------------------------------------------------------------------------------
-- DEVELOPER USER IDS  (see instance IDs in inventory, debug info)
--------------------------------------------------------------------------------
CrateConfig.DeveloperUserIds = {
    -- Add your UserId(s) here for debug visibility
    -- e.g. 12345678,
    285563003
}

return CrateConfig
