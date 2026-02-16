local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Preset configurations for named tool types (keys are lowercase, e.g. 'pistol', 'sniper')
local presets = {
    pistol = {
        damage = 12,
        cd = 0.18,
        bulletspeed = 900,
        range = 450,
        projectile_lifetime = 2,
        LeaveProjectile = false,
        projectile_size = {0.3,0.3,0.4},
        bulletdrop = 0,
        showTracer = false,
        headshot_multiplier = 1.5,
    },
    sniper = {
        damage = 80,
        cd = 2.5,
        bulletspeed = 900,
        range = 5000,
        projectile_lifetime = 6,
        LeaveProjectile = false,
        projectile_size = {0.2,0.2,9.8},
        bulletdrop = 0,
        showTracer = false,
        headshot_multiplier = 1.25,
    }
    ,
    bow = {
        damage = 25,
        cd = 0.40,
        bulletspeed = 250,
        range = 1000,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_stick_lifetime = 2,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 55,
        showTracer = false,
        headshot_multiplier = 1.2,
        projectile_name = "Arrow",
    }
}

local module = {}

-- Return the preset table for a given tool type (e.g. 'pistol', 'sniper') or nil
function module.getPreset(toolType)
    if not toolType then return nil end
    return presets[tostring(toolType):lower()]
end

module.presets = presets

local ServerStorage = game:GetService("ServerStorage")
local projectilesFolder = ServerStorage:FindFirstChild("Projectiles")

-- Return a projectile Instance for the given tool type's preset.
-- If the preset contains `projectile_name` and a matching object exists
-- in ServerStorage/Projectiles, a clone of that object is returned.
-- Otherwise a simple Part is created using `projectile_size` and returned.
function module.getProjectileForPreset(toolType)
    local preset = module.getPreset(toolType)
    if not preset then return nil end

    if preset.projectile_name and projectilesFolder then
        local stored = projectilesFolder:FindFirstChild(tostring(preset.projectile_name))
        if stored then
            return stored:Clone()
        end
    end

    -- Fallback: construct a simple Part using projectile_size
    local sizeTbl = preset.projectile_size or {0.2, 0.2, 0.5}
    local part = Instance.new("Part")
    part.Name = (toolType or "Projectile") .. "_Auto"
    part.Size = Vector3.new(sizeTbl[1] or 0.2, sizeTbl[2] or 0.2, sizeTbl[3] or 0.5)
    part.CanCollide = false
    part.Anchored = false
    part.Material = Enum.Material.SmoothPlastic
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

return module
