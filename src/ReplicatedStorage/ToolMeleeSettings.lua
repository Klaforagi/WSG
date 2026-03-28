-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolBat or Bat → "bat", ToolSword or Sword → "sword"

local presets = {
    ["starter sword"] = {
        damage          = 15,
        cd              = 0.5,
        knockback       = 15,
        hitboxDelay     = 0.35,
        hitboxActive    = 0.1,
        showHitbox      = false,
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(4, 10, 4),
        hitboxOffset    = Vector3.new(1, 0, 3.5),
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = {
            "82015832913253",
            "123046034669489",
            "95518688900800",
        },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    ["wooden sword"] = {
        damage          = 15,
        cd              = 0.45,   -- seconds between swings
        knockback       = 15,    -- impulse applied to the victim
        hitboxDelay     = 0.27,   -- seconds before hitbox becomes active (animation sync)
        hitboxActive    = 0.1,   -- seconds the hitbox remains active
        showHitbox      = false, -- debug: show hitbox locally when swinging
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(4, 10, 4),
        hitboxOffset    = Vector3.new(1, 0, 3.5),
        swing_anim_id   = "82015832913253",    -- fallback: single anim (used if swing_anim_ids is empty)
        swing_anim_ids  = {                      -- ordered cycle: plays 1 → 2 → 3 → 1 …
            "82015832913253",
            "123046034669489",
            "95518688900800",        
        },
        swing_sound     = "SwordSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
        hit_sound       = "SwordHit",
    },
    ["punisher"] = {
        damage          = 15,
        cd              = 0.45,
        knockback       = 15,
        hitboxDelay     = 0.27,
        hitboxActive    = 0.1,
        showHitbox      = false,
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(4, 10, 4),
        hitboxOffset    = Vector3.new(1, 0, 3.5),
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = {
            "82015832913253",
            "123046034669489",
            "95518688900800",
        },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    dagger = {
        damage          = 6,
        cd              = 0.25,   -- seconds between swings
        knockback       = 2,    -- impulse applied to the victim
        hitboxDelay     = 0.1,   -- seconds before hitbox becomes active (animation sync)
        hitboxActive    = 0.1,   -- seconds the hitbox remains active
        showHitbox      = true, -- debug: show hitbox locally when swinging
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(2, 3, 2),
        hitboxOffset    = Vector3.new(1, 1, 3.5),
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = {
            "82015832913253",
            "123046034669489",
            "95518688900800",
        },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    sword = {
        damage          = 25,
        cd              = 0.70,
        knockback       = 12,
        hitboxDelay     = 0.3,
        hitboxActive    = 0.3,
        showHitbox      = false,
        hitboxColor     = Color3.fromRGB(180, 180, 255),
        hitboxSize      = Vector3.new(2, 8, 4),
        hitboxOffset    = Vector3.new(1, 0, 3.5),
        swing_anim_id   = "82015832913253",
        swing_anim_ids  = {
            "82015832913253",
            "123046034669489",
            "95518688900800",
        },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
    spear = {
        damage          = 20,
        cd              = 1.20,
        knockback       = 18,
        hitboxDelay     = 0.3,
        hitboxActive    = 0.3,
        showHitbox      = true,
        hitboxColor     = Color3.fromRGB(180, 180, 255),
        hitboxSize      = Vector3.new(2, 2, 8),
        hitboxOffset    = Vector3.new(1, 1, 3.5),
        swing_anim_id   = "",
        swing_anim_ids  = {
            "135263926933355",
            "84391444206704",
            "138752532534641",
        },
        swing_sound     = "SwordSwing",
        hit_sound       = "SwordHit",
    },
}

local module = {}

function module.getPreset(toolType)
    if not toolType then return nil end
    return presets[tostring(toolType):lower()]
end

module.presets = presets

--------------------------------------------------------------------------------
-- COMBO SYSTEM CONFIG  (shared between client & server)
-- Tweak these values to tune the feel of sword combo chains.
--------------------------------------------------------------------------------
module.comboConfig = {
    COMBO_WINDOW              = 0.2,              -- seconds after a step ends to chain the next
    ATTACK_COOLDOWNS          = { 0.5, 0.5, 0.7 },-- per-step cooldowns: Attack1, Attack2, Attack3
    ATTACK3_DAMAGE_MULTIPLIER = 1.25,             -- Attack3 deals baseDamage * this
    -- ATTACK3_DAMAGE_BONUS   = 5,                -- alternative flat bonus (set multiplier to 1 to use)
}

return module
