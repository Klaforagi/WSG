-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolBat or Bat → "bat", ToolSword or Sword → "sword"

local presets = {
    stick = {
        damage          = 15,
        cd              = 0.6,   -- seconds between swings
        knockback       = 15,    -- impulse applied to the victim
        hitboxDelay     = 0.3,   -- seconds before hitbox becomes active (animation sync)
        hitboxActive    = 0.8,   -- seconds the hitbox remains active
        showHitbox      = true, -- debug: show hitbox locally when swinging
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        hitboxSize      = Vector3.new(2, 5, 4),
        hitboxOffset    = Vector3.new(1, 1, 3.5),
        swing_anim_id   = "",    -- optional: custom swing animation asset id
        swing_sound     = "StickSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
        hit_sound       = "StickHit",
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
        swing_anim_id   = "",    -- optional: custom swing animation asset id
        swing_sound     = "SwordSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
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
        hitboxSize      = Vector3.new(2, 5.5, 4),
        hitboxOffset    = Vector3.new(1, 1, 3.5),
        swing_anim_id   = "",
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
