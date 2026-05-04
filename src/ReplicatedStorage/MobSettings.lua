-- MobSettings
-- Per-mob configuration for MobSpawner.
-- Each entry only defines overrides; call MobSettings.Get(name) to get a
-- fully-merged config table with all defaults already applied.
--
-- Structure per mob:
--   Spawn      – spawning pool and tagging
--   Movement   – walking, chasing, enraged speeds and aggro
--   Attack     – damage, hitbox, cooldown, sound
--   Animation  – animation asset IDs (empty string = none / fallback)
--   Debug      – development helpers

local MobSettings = {}

---------------------------------------------------------------------------
-- Shared defaults (every mob inherits these unless overridden)
---------------------------------------------------------------------------
local Defaults = {
    Spawn = {
        Weight   = 1,           -- weighted pool entry count; 0 = disabled
        Tag      = "ZombieNPC", -- CollectionService tag applied on spawn
        XPReward = 1,           -- XP given to the killing player
        CoinReward = 1,         -- coins given to the killing player; number or { Min = x, Max = y }
    },
    Movement = {
        WalkSpeed        = 8,  -- passive wander speed
        ChaseSpeed       = 14,  -- speed while chasing an aggroed target
        EnragedSpeed     = 18,  -- speed after taking any damage (if UseEnraged = true)
        UseEnraged       = false,
        DetectionRadius  = 20,  -- studs; range for auto-detecting nearby players
        AggroDuration    = 8,   -- seconds to remain aggroed on the attacker
    },
    Attack = {
        Damage      = 5,
        Cooldown    = 1,        -- minimum seconds between swings
        Range       = 9,        -- studs; distance at which attack wind-up begins
        MinimumSpacingDistance = 3.5, -- stop advancing when closer than this
        Windup      = 1,        -- seconds mob is locked before hitbox fires
        Sound       = "MobSwing",
        HitboxSize  = Vector3.new(5, 6, 5),
        HitboxOffset = Vector3.new(0, 0, 3),
        Knockback   = 18,       -- horizontal hit impulse scalar (mass-scaled)
        KnockbackY  = 2,        -- optional upward pop impulse scalar (mass-scaled)
        PreferredDistanceOffset = 0.5, -- preferred stop distance = Range - offset (min 2.5)
    },
    Animation = {
        Walk   = "",            -- empty = R6 default walk anim
        Run    = "",            -- empty = falls back to Walk
        Idle   = "",            -- empty = none
        Attack = "",            -- empty = none (plays during Windup)
    },
    Debug = {
        ShowHitbox  = false,
        HitboxColor = Color3.fromRGB(255, 50, 50),
    },
}

---------------------------------------------------------------------------
-- Per-mob overrides
-- Only include keys that differ from the Defaults above.
---------------------------------------------------------------------------
local Presets = {
    Orc = {
        Spawn = {
            Weight   = 5,
            XPReward = 8,
            CoinReward = { Min = 4, Max = 10 },
        },
        Attack = {
            Damage      = 8,
            Cooldown    = .5,
            Windup      = 0.35,
            Sound       = "OrcSwing",
            Knockback   = 50,
            KnockbackY  = 4,
        },
        Animation = {
            Walk   = "rbxassetid://657552124",
            Run    = "rbxassetid://507767714",
            Idle   = "rbxassetid://507766388",
            Attack = "rbxassetid://122917464230305",
        },
        Debug = {
            ShowHitbox  = false,
            HitboxColor = Color3.fromRGB(50, 255, 50),
        },
    },

    Goblin = {
        Spawn = {
            Weight   = 10,  -- 2x Orc's weight of 5
            XPReward = 4,
            CoinReward = { Min = 1, Max = 6 },
        },
        Movement = {
            WalkSpeed    = 12,  -- Orc default (8) +4
            ChaseSpeed   = 18,  -- Orc default (14) +4
            EnragedSpeed = 22,  -- Orc default (18) +4
        },
        Attack = {
            Damage      = 3,   -- ~3x less than Orc's 8
            Cooldown    = 0.5,
            Windup      = 0.35,
            Sound       = "GoblinSwing",
            Knockback   = 20,
            KnockbackY  = 3,
            HitboxSize  = Vector3.new(3, 5, 4),  -- smaller than Orc default (5, 6, 5)
            HitboxOffset = Vector3.new(0, 0, 2.5),
        },
        Animation = {
            Walk   = "rbxassetid://657552124",
            Run    = "rbxassetid://507767714",
            Idle   = "rbxassetid://507766388",
            Attack = "rbxassetid://122917464230305",
        },
    },

    Ogre = {
        Spawn = {
            Weight   = 2,
            XPReward = 12,
            CoinReward = 12,
        },
        Attack = {
            Damage      = 12,
            Cooldown    = 1.5,
            Windup      = 0.5,
        },
        Animation = {
            Attack = "rbxassetid://72805951274249",
        },
        Debug = {
            ShowHitbox  = true,
            HitboxColor = Color3.fromRGB(180, 50, 255),
        },
    },
}

---------------------------------------------------------------------------
-- Deep-merge: copies keys from src into dst recursively.
-- dst is mutated and returned.
---------------------------------------------------------------------------
local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            deepMerge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function deepCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v
    end
    return copy
end

---------------------------------------------------------------------------
-- Validation (warns on obviously wrong values; non-fatal)
---------------------------------------------------------------------------
local REQUIRED_SECTIONS = { "Spawn", "Movement", "Attack", "Animation", "Debug" }

local function validate(name, cfg)
    for _, section in ipairs(REQUIRED_SECTIONS) do
        if not cfg[section] then
            warn(("[MobSettings] '%s' is missing section '%s'"):format(name, section))
        end
    end
    local sp = cfg.Spawn
    if sp and sp.Weight < 0 then
        warn(("[MobSettings] '%s' Spawn.Weight is negative (%d)"):format(name, sp.Weight))
    end
    if sp then
        local coinReward = sp.CoinReward
        if type(coinReward) == "number" then
            if coinReward < 0 then
                warn(("[MobSettings] '%s' Spawn.CoinReward must be non-negative"):format(name))
            end
        elseif type(coinReward) == "table" then
            local minReward = coinReward.Min
            local maxReward = coinReward.Max
            if type(minReward) ~= "number" or type(maxReward) ~= "number" then
                warn(("[MobSettings] '%s' Spawn.CoinReward range must define numeric Min and Max"):format(name))
            elseif minReward < 0 or maxReward < 0 or minReward > maxReward then
                warn(("[MobSettings] '%s' Spawn.CoinReward range is invalid (Min=%s, Max=%s)"):format(name, tostring(minReward), tostring(maxReward)))
            end
        else
            warn(("[MobSettings] '%s' Spawn.CoinReward must be a number or range table"):format(name))
        end
    end
    local atk = cfg.Attack
    if atk then
        if atk.Cooldown <= 0 then
            warn(("[MobSettings] '%s' Attack.Cooldown must be > 0 (got %s)"):format(name, tostring(atk.Cooldown)))
        end
        if atk.Range < 0 then
            warn(("[MobSettings] '%s' Attack.Range is negative (%s)"):format(name, tostring(atk.Range)))
        end
        if type(atk.MinimumSpacingDistance) ~= "number" or atk.MinimumSpacingDistance < 0 then
            warn(("[MobSettings] '%s' Attack.MinimumSpacingDistance must be a non-negative number"):format(name))
        end
        if typeof(atk.HitboxSize) ~= "Vector3" then
            warn(("[MobSettings] '%s' Attack.HitboxSize must be a Vector3"):format(name))
        end
        if typeof(atk.HitboxOffset) ~= "Vector3" then
            warn(("[MobSettings] '%s' Attack.HitboxOffset must be a Vector3"):format(name))
        end
        if type(atk.Knockback) ~= "number" or atk.Knockback < 0 then
            warn(("[MobSettings] '%s' Attack.Knockback must be a non-negative number"):format(name))
        end
        if type(atk.KnockbackY) ~= "number" then
            warn(("[MobSettings] '%s' Attack.KnockbackY must be a number"):format(name))
        end
        if type(atk.PreferredDistanceOffset) ~= "number" then
            warn(("[MobSettings] '%s' Attack.PreferredDistanceOffset must be a number"):format(name))
        end
    end
end

---------------------------------------------------------------------------
-- Resolved config cache (built once per mob name on first call)
---------------------------------------------------------------------------
local cache = {}

-- Returns the fully-merged config for mobName.
--- Falls back to pure Defaults if the mob has no preset.
function MobSettings.Get(mobName)
    if cache[mobName] then return cache[mobName] end

    -- start from a fresh copy of Defaults
    local cfg = deepCopy(Defaults)

    local overrides = Presets[mobName]
    if overrides then
        deepMerge(cfg, overrides)
    else
        warn(("[MobSettings] No preset found for '%s'; using defaults"):format(tostring(mobName)))
    end

    validate(mobName, cfg)
    cache[mobName] = cfg
    return cfg
end

--- Returns all preset names (regardless of Weight).
function MobSettings.GetAllNames()
    local names = {}
    for name in pairs(Presets) do
        table.insert(names, name)
    end
    return names
end

-- Legacy compatibility shim: expose raw presets in the old flat format so
-- any code that still reads MobSettings.presets[...] doesn't
-- hard-error before it can be migrated.
-- NOTE: these are NOT the resolved configs — use MobSettings.Get() instead.
MobSettings.presets = Presets

return MobSettings
