-- ToolMeleeSettings  (mirrors Toolgunsettings but for melee weapons)
-- Each key matches the suffix of the tool name:  ToolBat → "bat", ToolSword → "sword"

local presets = {
    bat = {
        damage          = 40,
        cd              = 0.8,   -- seconds between swings
        range           = 8,     -- studs in front of the player the swing can reach
        arc             = 120,   -- degrees of the swing cone (wide)
        knockback       = 35,    -- impulse applied to the victim
        swing_anim_id   = "",    -- optional: custom swing animation asset id
        swing_sound     = "BatSwing",    -- key in ReplicatedStorage.Sounds.ToolMelee
        hit_sound       = "BatHit",
    },
    sword = {
        damage          = 28,
        cd              = 0.65,
        range           = 7,
        arc             = 90,    -- narrower slash
        knockback       = 12,
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
