-- MobSettings: per-mob configuration for the spawner
-- Keys match the template instance Name (e.g. "Zombie", "Zack").

local presets = {
    Zombie = {
        walk_speed       = 16,
        chase_speed      = 25,   -- speed when damaged / chasing
        attack_damage    = 60,
        attack_cooldown  = 1,
        attack_range     = 6,    -- studs; proximity distance to land a hit
        attack_sound     = "ZombieAttack",
        detection_radius = 40,   -- aggro range in studs
        aggro_duration   = 12,   -- seconds to chase attacker after being hit
        tag              = "ZombieNPC",
        walk_anim_id     = "",   -- leave empty to use default R6 walk
    },
    Zack = {
        walk_speed       = 16,
        chase_speed      = 16,
        attack_damage    = 40,
        attack_cooldown  = 1.2,
        attack_range     = 6,
        attack_sound     = "Zombie_Attack",
        detection_radius = 40,
        aggro_duration   = 12,
        tag              = "ZombieNPC",
        walk_anim_id     = "",
    },
}

local module = {}
module.presets = presets
return module
