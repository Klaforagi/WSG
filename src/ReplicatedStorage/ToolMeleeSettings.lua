-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolBat or Bat → "bat", ToolSword or Sword → "sword"
--
-- Weapons define a `rarity` plus animation/sound fields.
-- Combat stats come from rarityDefaults and can be overridden per-weapon.
--
-- Size scaling, combo multipliers, and animation speed are handled by
-- ToolMeleeSetup.server.lua using this config as the baseline.

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function copyTable(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = copyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function mergeTables(base, override)
    local out = copyTable(base)
    for k, v in pairs(override) do
        out[k] = v
    end
    return out
end

--------------------------------------------------------------------------------
-- RARITY DEFAULTS  (combat / hitbox stats — all values are at 100% weapon size)
--
-- damage       : base damage before size/combo multipliers
-- cd           : base swing cooldown in seconds (scaled by weapon size)
-- knockback    : base knockback force (scaled by combo step + size)
-- hitboxDelay  : seconds into swing before the hitbox activates (scaled by size)
-- hitboxActive : how long the hitbox stays active (scaled by size)
-- hitboxSize   : spatial dimensions of the hitbox (NOT scaled by size)
-- hitboxOffset : offset from HRP center (NOT scaled by size)
--------------------------------------------------------------------------------

local rarityDefaults = {
    Common = {
        damage       = 5,
        cd           = 0.6,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.1,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(4, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Uncommon = {
        damage       = 7,
        cd           = 0.6,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.1,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(4, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Rare = {
        damage       = 8.5,
        cd           = 0.6,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.1,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(4, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Epic = {
        damage       = 10,
        cd           = 0.6,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.1,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(4, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Legendary = {
        damage       = 12,
        cd           = 0.6,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.1,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(4, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
}

--------------------------------------------------------------------------------
-- WEAPON PRESETS  (rarity + animation/sound + optional stat overrides)
--
-- Rarity themes:
--   Common    = trash / stick / branch / wooden junk
--   Uncommon  = primitive actual weapons (stone hammer, wooden spear)
--   Rare      = actual weapons (swords, axes, spear, flanged mace)
--   Epic      = stronger weapons (spiked mace, crusher)
--   Legendary = best badass 2H weapons (punisher, kingsblade)
--------------------------------------------------------------------------------

local presets = {
    -- Legendary
    ["punisher"] = {
        rarity          = "Legendary",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["kingsblade"] = {
        rarity          = "Legendary",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Epic
    ["spiked mace"] = {
        rarity          = "Epic",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["crusher"] = {
        rarity          = "Epic",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Rare
    ["flanged mace"] = {
        rarity          = "Rare",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["axe"] = {
        rarity          = "Rare",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["shortsword"] = {
        rarity          = "Rare",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["spear"] = {
        rarity          = "Rare",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Uncommon
    ["stone hammer"] = {
        rarity          = "Uncommon",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["wooden spear"] = {
        rarity          = "Uncommon",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Common
    ["starter sword"] = {
        rarity          = "Common",
        damage          = 7, -- override: early game feels better
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["wooden sword"] = {
        rarity          = "Common",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["branch"] = {
        rarity          = "Common",
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = { "82015832913253", "123046034669489", "95518688900800" },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
}

--------------------------------------------------------------------------------
-- MODULE
--------------------------------------------------------------------------------

local module = {}

function module.getPreset(toolType)
    if not toolType then return nil end
    local weapon = presets[tostring(toolType):lower()]
    if not weapon then return nil end
    local rarity = weapon.rarity
    local defaults = rarityDefaults[rarity] or rarityDefaults.Common
    return mergeTables(defaults, weapon)
end

module.presets        = presets
module.rarityDefaults = rarityDefaults

--------------------------------------------------------------------------------
-- COMBO SYSTEM CONFIG  (shared between client & server)
--
-- All cooldown values are baselines at 100% weapon size.
-- ToolMeleeSetup scales them by sizeSpeedMultiplier at runtime.
--
-- ATTACK_DAMAGE_MULTIPLIERS    : per-step scalar applied to base damage
-- ATTACK_KNOCKBACK_MULTIPLIERS : per-step scalar applied to base knockback
--   → attacks 1 & 2 have minimal knockback; attack 3 is the big finisher
--------------------------------------------------------------------------------
-- cd = exact swing cooldown per attack in seconds (steps 1 & 2).
-- Step 3 adds ATTACK3_EXTRA_CD on top (configurable below).
module.comboConfig = {
    COMBO_WINDOW                = 0.2,
    ATTACK3_EXTRA_CD            = 0.4,
    ATTACK_DAMAGE_MULTIPLIERS   = { 0.8, 0.85, 1.4 },
    ATTACK_KNOCKBACK_MULTIPLIERS = { 1.0, 1.25, 10.0 },
}

return module
