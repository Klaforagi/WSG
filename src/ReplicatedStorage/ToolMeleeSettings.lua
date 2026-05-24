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

local SizeRollService
pcall(function()
    local module = script.Parent:FindFirstChild("SizeRollService")
    if module and module:IsA("ModuleScript") then
        SizeRollService = require(module)
    end
end)

local defaultSwingAnimationConfig = {
    swing_anim_id   = "131848181334604",
    swing_anim_ids  = { "131848181334604", "86527473231278", "81535913836580" },
}

local giantAndKingSwingAnimationConfig = {
    swing_anim_id   = "83160499580272",
    swing_anim_ids  = { "83160499580272", "132121098575411", "99187479200316" },
}

local SPEAR_WEAPON_TAG = "Spear"
local SPEAR_SWING_ANIMATION_ID = "74251114610007"

local defaultSwingAnimationConfigsBySizeTier = {
    Giant = giantAndKingSwingAnimationConfig,
    King  = giantAndKingSwingAnimationConfig,
}

local function resolveSizeTier(sizePercentOrTier)
    if type(sizePercentOrTier) == "number" then
        if SizeRollService and SizeRollService.GetSizeTier then
            return SizeRollService.GetSizeTier(sizePercentOrTier)
        end
        if sizePercentOrTier >= 190 then return "King" end
        if sizePercentOrTier >= 150 then return "Giant" end
        if sizePercentOrTier >= 111 then return "Large" end
        if sizePercentOrTier >= 90 then return "Normal" end
        return "Tiny"
    end

    if type(sizePercentOrTier) == "string" then
        local normalized = string.lower(sizePercentOrTier)
        if string.find(normalized, "king", 1, true) then return "King" end
        if string.find(normalized, "giant", 1, true) then return "Giant" end
        if string.find(normalized, "large", 1, true) then return "Large" end
        if string.find(normalized, "normal", 1, true) then return "Normal" end
        if string.find(normalized, "tiny", 1, true) then return "Tiny" end
    end

    return nil
end

local function buildPresets(overrides)
    local out = {}
    for weaponName, weaponOverride in pairs(overrides) do
        out[weaponName] = mergeTables(defaultSwingAnimationConfig, weaponOverride)
    end
    return out
end

local function hasWeaponTag(cfg, tagName)
    if type(cfg) ~= "table" or tagName == nil then return false end
    local tags = cfg.weaponTags
    if type(tags) ~= "table" then return false end

    local normalizedTag = string.lower(tostring(tagName))
    for key, value in pairs(tags) do
        if value == true and string.lower(tostring(key)) == normalizedTag then
            return true
        end
        if type(value) == "string" and string.lower(value) == normalizedTag then
            return true
        end
    end
    return false
end

local function usesComboAttacks(cfg)
    if type(cfg) ~= "table" then return false end
    if cfg.usesCombo == false then return false end
    if hasWeaponTag(cfg, SPEAR_WEAPON_TAG) then return false end
    return type(cfg.swing_anim_ids) == "table" and #cfg.swing_anim_ids >= 3
end

local spearAttackConfig = {
    weaponTags            = { [SPEAR_WEAPON_TAG] = true },
    usesCombo             = false,
    useSizeTierAnimations = false,
    ignoreSizeHitboxScale = true,
    cd                    = 0.8,
    hitboxDelay           = 0.35,
    hitboxActive          = 0.2,
    hitboxSize            = Vector3.new(5, 10, 6),
    hitboxOffset          = Vector3.new(0, 0, 4.8),
    swing_anim_id         = SPEAR_SWING_ANIMATION_ID,
    swing_anim_ids        = { SPEAR_SWING_ANIMATION_ID },
}

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
        damage       = 7,
        cd           = 0.6,
        movement_speed_penalty = -3,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.2,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(5, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Uncommon = {
        damage       = 10,
        cd           = 0.6,
        movement_speed_penalty = -3,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.2,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(5, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Rare = {
        damage       = 13,
        cd           = 0.6,
        movement_speed_penalty = -3,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.2,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(5, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Epic = {
        damage       = 17,
        cd           = 0.6,
        movement_speed_penalty = -3,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.2,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(6, 10, 4),
        hitboxOffset = Vector3.new(1, 0, 3.5),
    },
    Legendary = {
        damage       = 21,
        cd           = 0.6,
        movement_speed_penalty = -3,
        knockback    = 2,
        hitboxDelay  = 0.35,
        hitboxActive = 0.2,
        showHitbox   = false,
        hitboxColor  = Color3.fromRGB(255, 100, 50),
        hitboxSize   = Vector3.new(6, 10, 4),
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
--   Legendary = best badass 2H weapons (punisher, kingsblade, doom sword)
--------------------------------------------------------------------------------

local presetOverrides = {
    -- Legendary
    ["punisher"] = {
        rarity          = "Legendary",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },
    ["kingsblade"] = {
        rarity          = "Legendary",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["doom sword"] = {
        rarity          = "Legendary",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Epic
    ["spiked mace"] = {
        rarity          = "Epic",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },
    ["crusher"] = {
        rarity          = "Epic",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },
    ["ethereal sword"] = {
        rarity          = "Epic",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Rare
    ["flanged mace"] = {
        rarity          = "Rare",
        swing_sound     = "SwordSwing",
        hit_sound       = "BluntHit",
    },
    ["shortsword"] = {
        rarity          = "Rare",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["spear"] = mergeTables(spearAttackConfig, {
        rarity          = "Rare",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    }),
    ["lil crusher"] = {
        rarity          = "Rare",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },

    -- Uncommon
    ["stone hammer"] = {
        rarity          = "Uncommon",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },
    ["wooden spear"] = mergeTables(spearAttackConfig, {
        rarity          = "Uncommon",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    }),
    ["axe"] = {
        rarity          = "Uncommon",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },

    -- Common
    ["starter sword"] = {
        rarity          = "Common",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["wooden sword"] = {
        rarity          = "Common",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["branch"] = {
        rarity          = "Common",
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["bat"] = {
        rarity          = "Common",
        swing_sound     = "BluntSwing",
        hit_sound       = "BluntHit",
    },
    ["plunger"] = {
        rarity          = "Common",
        swing_sound     = "SwordSwing",
        hit_sound       = "PlungerHit",
    },
}

local presets = buildPresets(presetOverrides)

local function collectAllSwingAnimationIds()
    local ids = {}
    local seen = {}

    local function add(animId)
        if animId == nil or animId == "" then return end
        local normalized = tostring(animId)
        if seen[normalized] then return end
        seen[normalized] = true
        table.insert(ids, normalized)
    end

    local function addConfig(cfg)
        if not cfg then return end
        add(cfg.swing_anim_id)
        if type(cfg.swing_anim_ids) == "table" then
            for _, animId in ipairs(cfg.swing_anim_ids) do
                add(animId)
            end
        end
    end

    addConfig(defaultSwingAnimationConfig)
    for _, sizeCfg in pairs(defaultSwingAnimationConfigsBySizeTier) do
        addConfig(sizeCfg)
    end
    for _, weaponOverride in pairs(presetOverrides) do
        addConfig(weaponOverride)
    end

    return ids
end

local allSwingAnimationIds = collectAllSwingAnimationIds()

--------------------------------------------------------------------------------
-- MODULE
--------------------------------------------------------------------------------

local module = {}

function module.getPreset(toolType, sizePercentOrTier)
    if not toolType then return nil end
    local weaponOverride = presetOverrides[tostring(toolType):lower()]
    if not weaponOverride then return nil end

    local weapon = copyTable(defaultSwingAnimationConfig)
    local sizeTier = resolveSizeTier(sizePercentOrTier)
    local sizeTierCfg = sizeTier and defaultSwingAnimationConfigsBySizeTier[sizeTier] or nil
    local useSizeTierAnimations = weaponOverride.useSizeTierAnimations ~= false
    if hasWeaponTag(weaponOverride, SPEAR_WEAPON_TAG) then
        useSizeTierAnimations = false
    end
    if useSizeTierAnimations and sizeTierCfg then
        weapon = mergeTables(weapon, sizeTierCfg)
    end
    weapon = mergeTables(weapon, weaponOverride)

    local rarity = weapon.rarity
    local defaults = rarityDefaults[rarity] or rarityDefaults.Common
    return mergeTables(defaults, weapon)
end

module.presets        = presets
module.rarityDefaults = rarityDefaults
module.defaultSwingAnimationConfig = defaultSwingAnimationConfig
module.defaultSwingAnimationConfigsBySizeTier = defaultSwingAnimationConfigsBySizeTier
module.weaponTags = {
    Spear = SPEAR_WEAPON_TAG,
}
module.hasWeaponTag = hasWeaponTag
module.usesComboAttacks = usesComboAttacks
module.allSwingAnimationIds = allSwingAnimationIds
module.getAllSwingAnimationIds = collectAllSwingAnimationIds

--------------------------------------------------------------------------------
-- COMBO SYSTEM CONFIG  (shared between client & server)
--
-- All cooldown values are baselines at 100% weapon size.
-- ToolMeleeSetup scales them by sizeSpeedMultiplier at runtime.
--
-- ATTACK_DAMAGE_MULTIPLIERS    : per-step scalar applied to base damage
-- ATTACK_DAMAGE_ROLL_RANGES    : per-step random roll range applied after size/combo scaling
-- ATTACK_KNOCKBACK_MULTIPLIERS : per-step scalar applied to base knockback
--   → attacks 1 & 2 have minimal knockback; attack 3 is the big finisher
--------------------------------------------------------------------------------
-- cd = exact swing cooldown per attack in seconds (steps 1 & 2).
-- Step 3 adds ATTACK3_EXTRA_CD on top (configurable below).
module.comboConfig = {
    COMBO_WINDOW                = 0.2,
    ATTACK3_EXTRA_CD            = 0.4,
    ATTACK_DAMAGE_MULTIPLIERS   = { 1.0, 1.0, 1.0 },
    ATTACK_DAMAGE_ROLL_RANGES   = {
        { 0.7, 1.0 },
        { 0.7, 1.0 },
        { 1.2, 1.5 },
    },
    ATTACK_KNOCKBACK_MULTIPLIERS = { 1.0, 1.25, 10.0 },
}

return module
