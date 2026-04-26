-- Toolgunsettings  (mirrors ToolMeleeSettings but for ranged weapons)
-- Each key matches the tool name (or the suffix when tools use a "Tool" prefix):
-- e.g. ToolSlingshot or Slingshot -> "slingshot"
--
-- Weapons define a `rarity` plus projectile/sound fields.
-- Combat stats come from rarityDefaults and can be overridden per-weapon.

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
-- RARITY DEFAULTS
--------------------------------------------------------------------------------

local rarityDefaults = {
    Common = {
        damage = 4,
        cd = 0.7,
        bulletspeed = 150,
        range = 450,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_wooden_sword_lifetime = 0.3,
        projectile_size = {0.3, 0.3, 0.3},
        bulletdrop = 55,
        showTracer = false,
        headshot_multiplier = 1.15,
    },

    Uncommon = {
        damage = 5.5,
        cd = 0.7,
        bulletspeed = 175,
        range = 650,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_wooden_sword_lifetime = 0.5,
        projectile_size = {0.25, 0.25, 0.8},
        bulletdrop = 50,
        showTracer = false,
        headshot_multiplier = 1.15,
    },

    Rare = {
        damage = 7,
        cd = 0.7,
        bulletspeed = 225,
        range = 1000,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 45,
        showTracer = false,
        headshot_multiplier = 1.2,
    },

    Epic = {
        damage = 8.5,
        cd = 0.7,
        bulletspeed = 275,
        range = 1500,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 35,
        showTracer = false,
        headshot_multiplier = 1.25,
    },

    Legendary = {
        damage = 10,
        cd = 0.7,
        bulletspeed = 325,
        range = 2000,
        projectile_lifetime = 4,
        LeaveProjectile = true,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 25,
        showTracer = false,
        headshot_multiplier = 1.3,
    },
}

--------------------------------------------------------------------------------
-- WEAPON PRESETS
--------------------------------------------------------------------------------

local presets = {
    ["starter slingshot"] = {
        rarity = "Uncommon",
        projectile_name = "Pebble",
        shoot_sound = "Slingshot_Shoot",
        hit_sound = "Slingshot_Hit",
    },

    slingshot = {
        rarity = "Common",
        projectile_name = "Pebble",
        shoot_sound = "Slingshot_Shoot",
        hit_sound = "Slingshot_Hit",
    },

    shortbow = {
        rarity = "Rare",
        projectile_name = "Arrow",
        shoot_sound = "BowShoot",
        hit_sound = "BowHit",
    },

    longbow = {
        rarity = "Epic",
        damage = 12,
        cd = 0.9,
        projectile_name = "Arrow",
        shoot_sound = "BowShoot",
        hit_sound = "BowHit",
    },

    xbow = {
        rarity = "Legendary",
        damage = 24,
        cd = 2.0,
        projectile_name = "Bolt",
        visual_flip = true,
        shoot_sound = "BowShoot",
        hit_sound = "BowHit",
    },
}

local module = {}

function module.getPreset(toolType)
    if not toolType then return nil end

    local weapon = presets[tostring(toolType):lower()]
    if not weapon then return nil end

    local rarity = weapon.rarity
    local defaults = rarityDefaults[rarity] or rarityDefaults.Common

    return mergeTables(defaults, weapon)
end

module.presets = presets
module.rarityDefaults = rarityDefaults

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
