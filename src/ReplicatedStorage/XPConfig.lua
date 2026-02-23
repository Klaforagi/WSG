-- XPConfig.lua
-- Centralized XP values for different actions. Edit these numbers to tweak progression.

local XPConfig = {
    Reasons = {
        PlayerKill  = 10,
        FlagCapture = 100,
        FlagReturn  = 20,
        WinGame     = 50,
    },

    -- Default XP for a mob kill when MobSettings doesn't specify xp_reward
    DefaultMobXP = 3,
}

return XPConfig
