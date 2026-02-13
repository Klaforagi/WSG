-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the suffix of the tool name:  ToolBat → "bat", ToolSword → "sword"

local presets = {
    bat = {
        damage          = 40,
        cd              = 0.8,   -- seconds between swings
        knockback       = 35,    -- impulse applied to the victim
        hitboxDelay     = 0.1,   -- seconds before hitbox becomes active (animation sync)
        hitboxActive    = 0.2,   -- seconds the hitbox remains active
        showHitbox      = false, -- debug: show hitbox locally when swinging
        hitboxColor     = Color3.fromRGB(255, 100, 50),
        -- box hitbox: size (X,Y,Z) in studs and offset relative to HRP CFrame
        -- if provided, the server will use this box instead of range/arc cone
        hitboxSize      = Vector3.new(6, 4, 10),
        hitboxOffset    = Vector3.new(0, 1, 4),
        swing_anim_id   = "",    -- optional: custom swing animation asset id
        swing_sound     = "BatSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
        hit_sound       = "BatHit",
    },
    sword = {
        damage          = 28,
        cd              = 0.70,
        knockback       = 12,
        hitboxDelay     = 0.3,
        hitboxActive    = 0.22,
        showHitbox      = true,
        hitboxColor     = Color3.fromRGB(180, 180, 255),
        hitboxSize      = Vector3.new(2, 5, 4),
        hitboxOffset    = Vector3.new(0, 1, 3.5),
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
