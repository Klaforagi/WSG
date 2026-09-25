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

local WeaponMasteryConfig
pcall(function()
    local module = game:GetService("ReplicatedStorage"):FindFirstChild("WeaponMasteryConfig")
    if module and module:IsA("ModuleScript") then
        WeaponMasteryConfig = require(module)
    end
end)

local function getNilMasteryDamage(rarity)
    if WeaponMasteryConfig and type(WeaponMasteryConfig.GetDamageForLevel) == "function" then
        return WeaponMasteryConfig.GetDamageForLevel(0, rarity, "Ranged")
    end
    local fallback = {
        Common = 3.5,
        Uncommon = 4,
        Rare = 4.5,
        Epic = 5,
        Legendary = 6,
    }
    return fallback[rarity] or fallback.Common
end

--------------------------------------------------------------------------------
-- RARITY DEFAULTS
--------------------------------------------------------------------------------

local rarityDefaults = {
    Common = {
        damage = getNilMasteryDamage("Common"),
        cd = 0.5,
        movement_speed_penalty = -4,
        bulletspeed = 150,
        range = 450,
        projectile_lifetime = 4,
        LeaveProjectile = false,
        projectile_wooden_sword_lifetime = 0.3,
        projectile_size = {0.3, 0.3, 0.3},
        bulletdrop = 40,
        showTracer = false,
    },

    Uncommon = {
        damage = getNilMasteryDamage("Uncommon"),
        cd = 0.5,
        movement_speed_penalty = -4,
        bulletspeed = 163,
        range = 550,
        projectile_lifetime = 4,
        LeaveProjectile = false,
        projectile_wooden_sword_lifetime = 0.5,
        projectile_size = {0.25, 0.25, 0.8},
        bulletdrop = 37,
        showTracer = false,
    },

    Rare = {
        damage = getNilMasteryDamage("Rare"),
        cd = 0.5,
        movement_speed_penalty = -4,
        bulletspeed = 188,
        range = 725,
        projectile_lifetime = 4,
        LeaveProjectile = false,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 34,
        showTracer = false,
    },

    Epic = {
        damage = getNilMasteryDamage("Epic"),
        cd = 0.5,
        movement_speed_penalty = -4,
        bulletspeed = 213,
        range = 975,
        projectile_lifetime = 4,
        LeaveProjectile = false,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 32,
        showTracer = false,
    },

    Legendary = {
        damage = getNilMasteryDamage("Legendary"),
        cd = 0.5,
        movement_speed_penalty = -4,
        bulletspeed = 238,
        range = 1225,
        projectile_lifetime = 4,
        LeaveProjectile = false,
        projectile_wooden_sword_lifetime = 1,
        projectile_size = {0.2, 0.2, 2.0},
        bulletdrop = 29,
        showTracer = false,
    },
}

--------------------------------------------------------------------------------
-- WEAPON PRESETS
--
-- Keys match the tool name (or the suffix when tools use a "Tool" prefix),
-- lowercased: "Pixel Bow" / "ToolPixel Bow" -> "pixel bow".
--
-- projectile_name is cloned from ServerStorage.Projectiles. Expected names:
--   Pebble, Arrow, Pixel Arrow, Elderwood Arrow, Ironwood Arrow,
--   Skeletal Arrow, Ethereal Arrow, Golden Arrow
-- Shots spawn from Handle.Fire and line the projectile's Tip up with Fire.
-- Enchant visuals clone onto the projectile EnchantBlock, not the held weapon.
--------------------------------------------------------------------------------

local slingshotAudio = {
    shoot_sound = "Slingshot_Shoot",
    hit_sound = "Slingshot_Hit",
}

local bowAudio = {
    shoot_sound = "BowShoot",
    hit_sound = "BowHit",
    -- If arrows spawn backwards, set visual_flip = true.
    -- If they spawn on their side/upright wrong, set visual_rotation = {90, 0, 0}
    -- (degrees around X, Y, Z in look space). Example: {0, 180, 0} or {90, 0, 0}.
}

local presets = {
    -- Common
    ["starter slingshot"] = mergeTables(slingshotAudio, {
        rarity = "Common",
        projectile_name = "Pebble",
    }),
    slingshot = mergeTables(slingshotAudio, {
        rarity = "Common",
        projectile_name = "Pebble",
    }),
    bow = mergeTables(bowAudio, {
        rarity = "Common",
        projectile_name = "Arrow",
    }),

    -- Uncommon
    ["pixel bow"] = mergeTables(bowAudio, {
        rarity = "Uncommon",
        projectile_name = "Pixel Arrow",
    }),
    ["elderwood bow"] = mergeTables(bowAudio, {
        rarity = "Uncommon",
        projectile_name = "Elderwood Arrow",
    }),

    -- Rare
    ["ironwood bow"] = mergeTables(bowAudio, {
        rarity = "Rare",
        projectile_name = "Ironwood Arrow",
    }),
    ["skeletal bow"] = mergeTables(bowAudio, {
        rarity = "Rare",
        projectile_name = "Skeletal Arrow",
    }),

    -- Epic
    -- Always enchanted; mesh tint + icon come from the rolled enchant.
    ["ethereal bow"] = mergeTables(bowAudio, {
        rarity = "Epic",
        projectile_name = "Ethereal Arrow",
    }),

    -- Legendary
    ["golden bow"] = mergeTables(bowAudio, {
        rarity = "Legendary",
        projectile_name = "Golden Arrow",
    }),
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

local function isAttachmentNamed(instance, name)
    return instance and instance:IsA("Attachment") and instance.Name == name
end

function module.findNamedAttachment(root, name)
    if not root or type(name) ~= "string" or name == "" then
        return nil
    end

    local direct = root:FindFirstChild(name)
    if isAttachmentNamed(direct, name) then
        return direct
    end

    if root.GetDescendants then
        for _, descendant in ipairs(root:GetDescendants()) do
            if isAttachmentNamed(descendant, name) then
                return descendant
            end
        end
    end

    return nil
end

-- Fire lives under Handle (the whole mesh on 1-part weapons, or the welded
-- handle on multi-part weapons). Search Handle first, then the rest of the tool.
function module.getFireAttachment(tool)
    if not tool then return nil end

    local handle = tool:FindFirstChild("Handle")
    if handle then
        local fire = handle:FindFirstChild("Fire")
        if isAttachmentNamed(fire, "Fire") then
            return fire
        end
        local nestedFire = module.findNamedAttachment(handle, "Fire")
        if nestedFire then
            return nestedFire
        end
    end

    return module.findNamedAttachment(tool, "Fire")
end

function module.getFireOrigin(tool, fallback)
    local fire = module.getFireAttachment(tool)
    if fire then
        return fire.WorldPosition
    end

    local handle = tool and tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle.Position
    end

    return fallback
end

-- Return a projectile Instance for the given tool type's preset.
-- If the preset contains `projectile_name` and a matching object exists
-- in ServerStorage/Projectiles, a clone of that object is returned.
-- Otherwise a simple Part is created using `projectile_size` and returned.
function module.getProjectileForPreset(toolType)
    local preset = module.getPreset(toolType)
    if not preset then return nil end

    local ServerStorage = game:GetService("ServerStorage")
    local projectilesFolder = ServerStorage:FindFirstChild("Projectiles")
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
