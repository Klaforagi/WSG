-- PlayerSettingsConfig.lua
-- Centralized server-side player settings used by PlayerSettings.server.lua
-- Add new tunables here; this module is safe to require from ServerScriptService.

local Config = {}

-- Health regeneration settings (server authoritative).
-- Regen is disabled immediately when damage is taken and ramps up in stages
-- based on time since last damage.
-- Set "Enabled" to false to disable passive regen entirely.
Config.HealthRegen = {
    Enabled = true,
    Stages = {
        -- After 5s without taking damage: heal 1 HP every 1s
        {
            DelaySinceDamage = 5,
            AmountPerTick = 1,
            TickInterval = 1,
        },
        -- After 10s without taking damage: heal 1.5 HP every 1s
        {
            DelaySinceDamage = 10,
            AmountPerTick = 1.5,
            TickInterval = 1,
        },
        -- After 15s without taking damage: heal 2 HP every 1s
        -- This stage remains active until damage is taken again.
        {
            DelaySinceDamage = 15,
            AmountPerTick = 2,
            TickInterval = 1,
        },
    },
}

-- Future settings can be added here (e.g., stabilizer flags, head/accessory rules)

return Config
