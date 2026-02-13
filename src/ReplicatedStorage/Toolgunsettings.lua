local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Preset configurations for named tool types (keys are lowercase, e.g. 'pistol', 'sniper')
local presets = {
    pistol = {
        damage = 5,
        cd = 1.5,
        bulletspeed = 300,
        range = 450,
        projectile_lifetime = 2,
        projectile_size = {0.3,0.3,0.4},
        bulletdrop = 0,
        showTracer = false,
        headshot_multiplier = 1.5,
    },
    sniper = {
        damage = 80,
        cd = 2.5,
        bulletspeed = 600,
        range = 5000,
        projectile_lifetime = 6,
        projectile_size = {0.2,0.2,9.8},
        bulletdrop = 0,
        showTracer = false,
        headshot_multiplier = 1.25,
    }
}

local module = {}

-- Return the preset table for a given tool type (e.g. 'pistol', 'sniper') or nil
function module.getPreset(toolType)
    if not toolType then return nil end
    return presets[tostring(toolType):lower()]
end

module.presets = presets

return module
