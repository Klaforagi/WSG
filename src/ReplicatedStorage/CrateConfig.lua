--------------------------------------------------------------------------------
-- CrateConfig.lua  –  Shared crate definitions (server + client)
--
-- 2 crate types:
--   WeaponCrate          – Coins, melee + ranged weapons, all rarities
--   PremiumWeaponCrate   – Keys, melee + ranged weapons, Rare+ only
--
-- Legacy crate ids are resolved at the service boundary so old references keep
-- working while the shop only presents the merged weapon crates.
--------------------------------------------------------------------------------

local CrateConfig = {}

CrateConfig.LegacyCrateIdMap = {
    MeleeCrate = "WeaponCrate",
    RangedCrate = "WeaponCrate",
    PremiumMeleeCrate = "PremiumWeaponCrate",
    PremiumRangedCrate = "PremiumWeaponCrate",
}

function CrateConfig.ResolveCrateId(crateId)
    if type(crateId) ~= "string" then return crateId end
    return CrateConfig.LegacyCrateIdMap[crateId] or crateId
end

--------------------------------------------------------------------------------
-- RARITY DEFINITIONS  (color, display label)
-- Global weights are a fallback for any crate that doesn't define its own
-- `rarities` table.  Both shop crates define one, so these are mainly
-- used for color/label lookups.
--------------------------------------------------------------------------------
CrateConfig.Rarities = {
    Common    = { weight = 81, color = Color3.fromRGB(180, 180, 180), label = "Common"    },
    Uncommon  = { weight = 10, color = Color3.fromRGB(80, 200, 120),  label = "Uncommon"  },
    Rare      = { weight = 15, color = Color3.fromRGB(60, 140, 255),  label = "Rare"      },
    Epic      = { weight = 3,  color = Color3.fromRGB(150, 50, 230),  label = "Epic"      }, -- purple (tweaked)
    Legendary = { weight = 1,  color = Color3.fromRGB(255, 180, 30),  label = "Legendary" },
}

-- Ordered for display (highest first)
CrateConfig.RarityOrder = { "Legendary", "Epic", "Rare", "Uncommon", "Common" }

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
-- (updated: removed Dagger/Sword/Spear; new melee list below)
--
-- >>> TO REASSIGN WEAPONS: move entries between the rarity keys below. <<<
-- >>> Pools are auto-built from this table – no pool edits needed.     <<<
--------------------------------------------------------------------------------
CrateConfig.WeaponsByRarity = {
    Common    = {
        { weapon = "Wooden Sword", category = "Melee"  },
        { weapon = "Branch",       category = "Melee"  },
        { weapon = "Slingshot",    category = "Ranged" },
    },
    Uncommon = {
        { weapon = "Stone Hammer", category = "Melee" },
        { weapon = "Wooden Spear", category = "Melee" },
        { weapon = "Axe",          category = "Melee" },
    },
    Rare      = {
        { weapon = "Flanged Mace", category = "Melee" },
        { weapon = "Shortsword",   category = "Melee" },
        { weapon = "Spear",        category = "Melee" },
        { weapon = "Shortbow", category = "Ranged" },
    },
    Epic      = {
        { weapon = "Spiked Mace", category = "Melee" },
        { weapon = "Crusher",     category = "Melee" },
        { weapon = "Longbow", category = "Ranged" },
    },
    Legendary = {
        { weapon = "Punisher", category = "Melee" },
        { weapon = "Kingsblade", category = "Melee" },
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
--   weaponTypes – included item categories, preserving each rolled weapon's category
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

    WeaponCrate = {
        id          = "WeaponCrate",
        displayName = "Weapon Crate",
        description = "Contains a random melee or ranged weapon.",
        weaponTypes = { "Melee", "Ranged" },
        currency    = "Coins",
        cost        = 100,
        price       = 100,
        iconGlyph   = "\u{2694}",        -- ⚔

        -- >>> EDIT PERCENTAGES HERE to rebalance weapon crate odds <<<
        rarities = {
            Legendary = 1,
            Epic      = 4,
            Rare      = 15,
            Uncommon  = 40,
            Common    = 40,
        },

        pool = {},  -- auto-built below
    },

    ---------------------------------------------------------------------------
    -- PREMIUM CRATES  (Keys – no Commons!)
    ---------------------------------------------------------------------------

    PremiumWeaponCrate = {
        id          = "PremiumWeaponCrate",
        displayName = "Premium Weapon Crate",
        description = "A premium weapon crate. Costs Keys. No Commons!",
        weaponTypes = { "Melee", "Ranged" },
        currency    = "Keys",
        cost        = 1,
        price       = 1,
        iconGlyph   = "\u{2728}",      -- ✨

        -- >>> EDIT PERCENTAGES HERE to rebalance premium weapon odds <<<
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
--   1. weaponTypes  – only weapons matching an included category
--   2. rarities     – only weapons whose rarity key exists in the crate
--------------------------------------------------------------------------------
local function buildAllowedWeaponTypes(def)
    local allowed = {}
    if type(def.weaponTypes) == "table" then
        for _, weaponType in ipairs(def.weaponTypes) do
            allowed[weaponType] = true
        end
    elseif def.weaponType then
        allowed[def.weaponType] = true
    end
    return allowed
end

for crateId, def in pairs(CrateConfig.Crates) do
    if def.rarities then
        local pool = {}
        local allowedTypes = buildAllowedWeaponTypes(def)
        for rarity, _ in pairs(def.rarities) do
            local weapons = CrateConfig.WeaponsByRarity[rarity]
            if weapons then
                for _, entry in ipairs(weapons) do
                    if not next(allowedTypes) or allowedTypes[entry.category] then
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

-- Ordered list for UI display
CrateConfig.CrateOrder = { "WeaponCrate", "PremiumWeaponCrate" }

--------------------------------------------------------------------------------
-- DEVELOPER USER IDS  (see instance IDs in inventory, debug info)
--------------------------------------------------------------------------------
CrateConfig.DeveloperUserIds = {
    -- Add your UserId(s) here for debug visibility
    -- e.g. 12345678,
    285563003
}

return CrateConfig
