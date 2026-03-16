-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolBat or Bat → "bat", ToolSword or Sword → "sword"

local presets = {
    ["wooden sword"] = {
        damage          = 15,
        cd              = 0.6,   -- seconds between swings
        knockback       = 15,    -- impulse applied to the victim
        hitboxDelay     = 0.27,   -- seconds before hitbox becomes active (animation sync)
        hitboxActive    = 0.1,   -- seconds the hitbox remains active
        showHitbox      = true, -- debug: show hitbox locally when swinging
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(2, 10, 4),
        hitboxOffset    = Vector3.new(1, 1, 3.5),
        swing_anim_id   = "138752532534641",    -- fallback: single anim (used if swing_anim_ids is empty)
        swing_anim_ids  = {                      -- ordered cycle: plays 1 → 2 → 3 → 1 …
            "79533685138501",  -- swing 1  (replace with your asset ids)
            "138752532534641",                 -- swing 2  (fill in)
            "",                 -- swing 3  (fill in)
        },
        swing_sound     = "SwordSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
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
        swing_anim_id   = "91239654979526",
        swing_anim_ids  = { "", "", "" },  -- ordered cycle (fill in asset ids)
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
        swing_anim_id   = "",
        swing_anim_ids  = { "", "", "" },  -- ordered cycle (fill in asset ids)
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
        swing_anim_ids  = { "", "", "" },  -- ordered cycle (fill in asset ids)
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

return module
