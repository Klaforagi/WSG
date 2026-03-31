-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolBat or Bat → "bat", ToolSword or Sword → "sword"

local presets = {
    -- Legendary (keep listed first)
    ["punisher"] = {
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
    ["kingsblade"] = {
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

    -- Epic
    ["spiked mace"] = {
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
    ["crusher"] = {
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

    -- Rare
    ["flanged mace"] = {
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
    ["shortsword"] = {
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

    -- Common (starter + commons)
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
    ["stone hammer"] = {
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
    ["wooden spear"] = {
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
    ["spear"] = {
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
    ["branch"] = {
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
