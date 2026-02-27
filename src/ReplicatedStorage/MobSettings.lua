-- MobSettings: per-mob configuration for the spawner
-- Keys match the template instance Name (e.g. "Zombie", "Zack").

local presets = {
    Zombie = {
        walk_speed       = 16,
        chase_speed      = 16,   -- speed when damaged / chasing
        attack_damage    = 20,
        attack_cooldown  = 1,
        attack_range     = 6,    -- studs; proximity distance to land a hit
        attack_sound     = "ZombieAttack",
        detection_radius = 40,   -- aggro range in studs
        aggro_duration   = 12,   -- seconds to chase attacker after being hit
        tag              = "ZombieNPC",
        walk_anim_id     = "",   -- leave empty to use default R6 walk
        xp_reward        = 3,    -- XP awarded to the player who kills this mob
        spawn_chance     = 99,   -- weighted chance: higher = more likely to be picked
    },
    Zack = {
        walk_speed       = 16,
        chase_speed      = 16,
        attack_damage    = 20,
        attack_cooldown  = 1.2,
        attack_range     = 6,
        attack_sound     = "Zombie_Attack",
        detection_radius = 40,
        aggro_duration   = 12,
        tag              = "ZombieNPC",
        walk_anim_id     = "",
        xp_reward        = 5,    -- XP awarded to the player who kills this mob
        spawn_chance     = 1,    -- weighted chance: higher = more likely to be picked
    },
}

local module = {}
module.presets = presets
return module
