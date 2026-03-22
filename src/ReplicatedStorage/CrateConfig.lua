--------------------------------------------------------------------------------
-- CrateConfig.lua  –  Shared crate definitions (server + client)
--
-- Each crate has a price, weapon pool with rarity weights, and display info.
-- Rarity tiers: Common, Rare, Epic, Legendary (extensible).
--------------------------------------------------------------------------------

local CrateConfig = {}

--------------------------------------------------------------------------------
-- RARITY DEFINITIONS  (color, weight, display label)
--------------------------------------------------------------------------------
CrateConfig.Rarities = {
    Common    = { weight = 75, color = Color3.fromRGB(180, 180, 180), label = "Common"    },
    Rare      = { weight = 25, color = Color3.fromRGB(60, 140, 255),  label = "Rare"      },
    Epic      = { weight = 0,  color = Color3.fromRGB(180, 60, 255),  label = "Epic"      },
    Legendary = { weight = 0,  color = Color3.fromRGB(255, 180, 30),  label = "Legendary" },
}

-- Ordered for display (highest first)
CrateConfig.RarityOrder = { "Legendary", "Epic", "Rare", "Common" }

--------------------------------------------------------------------------------
-- CRATE DEFINITIONS
--------------------------------------------------------------------------------
CrateConfig.Crates = {
    ---------------------------------------------------------------------------
    MeleeCrate = {
        id          = "MeleeCrate",
        displayName = "Melee Crate",
        description = "Contains a random melee weapon.",
        price       = 1,
        category    = "Melee",   -- tool folder in ServerStorage
        iconGlyph   = "\u{2694}", -- ⚔

        pool = {
            { weapon = "Wooden Sword", rarity = "Common" },
            { weapon = "Dagger",       rarity = "Common" },
            { weapon = "Sword",        rarity = "Common" },
            -- Rares
            { weapon = "Spear",   rarity = "Rare"   },
        },
    },

    ---------------------------------------------------------------------------
    RangedCrate = {
        id          = "RangedCrate",
        displayName = "Ranged Crate",
        description = "Contains a random ranged weapon.",
        price       = 1,
        category    = "Ranged",
        iconGlyph   = "\u{1F3F9}", -- 🏹

        pool = {
            { weapon = "Slingshot", rarity = "Common" },
            { weapon = "Shortbow",  rarity = "Common" },
            { weapon = "Longbow",   rarity = "Common" },
            -- Rares
            { weapon = "Xbow",  rarity = "Rare"   },
        },
    },
}

-- Ordered list for UI display
CrateConfig.CrateOrder = { "MeleeCrate", "RangedCrate" }

--------------------------------------------------------------------------------
-- DEVELOPER USER IDS  (see instance IDs in inventory, debug info)
--------------------------------------------------------------------------------
CrateConfig.DeveloperUserIds = {
    -- Add your UserId(s) here for debug visibility
    -- e.g. 12345678,
    285563003
}

return CrateConfig
