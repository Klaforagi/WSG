-- PlayerSettingsConfig.lua
-- Centralized server-side player settings used by PlayerSettings.server.lua
-- Add new tunables here; this module is safe to require from ServerScriptService.

local Config = {}

-- Health regeneration settings (server authoritative).
-- "AmountPerTick": how much health is restored each tick.
-- "TickInterval": how often (in seconds) each tick occurs.
-- Set "Enabled" to false to disable passive regen.
Config.HealthRegen = {
    Enabled = true,
    AmountPerTick = 1,   -- HP restored per tick (default: 2)
    TickInterval   = 10,  -- seconds between ticks (default: 5s)
}

-- Future settings can be added here (e.g., stabilizer flags, head/accessory rules)

return Config
