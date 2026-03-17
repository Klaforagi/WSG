-- MobSettings: per-mob configuration for the spawner
-- Keys match the template instance Name (e.g. "Zombie", "Zack").

local presets = {
    Zombie = {
        walk_speed       = 12,
        chase_speed      = 12,   -- speed when chasing/aggroed
        enraged_speed    = 16,   -- speed when damaged (health < max)
        enraged          = false, -- true = use enraged_speed when damaged
        attack_damage    = 5,
        attack_cooldown  = 1,
        attack_range     = 5,    -- studs; distance to start attack wind-up
        attack_windup    = 1,    -- seconds the mob is locked in place before hitbox fires
        attack_sound     = "ZombieAttack",
        hitbox_size      = Vector3.new(4, 6, 4),   -- hitbox dimensions (X, Y, Z)
        hitbox_offset    = Vector3.new(0, 0, 3),    -- offset from mob root (Z = forward)
        attack_anim_id   = "",   -- animation played during attack wind-up (empty = none)
        detection_radius = 15,   -- aggro range in studs
        aggro_duration   = 5,   -- seconds to chase attacker after being hit
        tag              = "ZombieNPC",
        walk_anim_id     = "",   -- animation when wandering (empty = default R6 walk)
        run_anim_id      = "",   -- animation when aggroed/chasing (empty = uses walk_anim_id)
        idle_anim_id     = "",   -- animation when standing still (empty = none)
        xp_reward        = 3,    -- XP awarded to the player who kills this mob
        spawn_chance     = 0,   -- weighted chance: higher = more likely to be picked
    },
    Zack = {
        walk_speed       = 16,
        chase_speed      = 16,
        enraged_speed    = 20,
        enraged          = false,
        attack_damage    = 20,
        attack_cooldown  = 1.2,
        attack_range     = 7,
        attack_windup    = 1,
        attack_sound     = "Zombie_Attack",
        hitbox_size      = Vector3.new(5, 6, 5),
        hitbox_offset    = Vector3.new(0, 0, 3.5),
        attack_anim_id   = "",
        detection_radius = 40,
        aggro_duration   = 12,
        tag              = "ZombieNPC",
        walk_anim_id     = "",   -- animation when wandering
        run_anim_id      = "",   -- animation when aggroed/chasing
        idle_anim_id     = "",   -- animation when standing still
        xp_reward        = 5,    -- XP awarded to the player who kills this mob
        spawn_chance     = 0,    -- weighted chance: higher = more likely to be picked
    },
    Orc = {
        walk_speed       = 8,
        chase_speed      = 16,   -- faster when aggroed
        enraged_speed    = 16,
        enraged          = false,
        attack_damage    = 12,
        attack_cooldown  = 1,
        attack_range     = 5,
        attack_windup    = 1,
        attack_sound     = "OrcAttack",
        hitbox_size      = Vector3.new(5, 6, 5),
        hitbox_offset    = Vector3.new(0, 0, 3),
        attack_anim_id   = "",
        detection_radius = 20,
        aggro_duration   = 8,
        tag              = "ZombieNPC",
        walk_anim_id     = "rbxassetid://657552124",                         -- R15 walk animation when wandering
        run_anim_id      = "rbxassetid://507767714",   -- R15 run animation when aggroed/chasing
        idle_anim_id     = "rbxassetid://507766388",   -- R15 idle animation when standing still
        xp_reward        = 8,
        spawn_chance     = 5,
    },
}

local module = {}
module.presets = presets
return module
