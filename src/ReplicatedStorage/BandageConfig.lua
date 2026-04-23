--------------------------------------------------------------------------------
-- BandageConfig.lua  –  Tunable values for the Bandage utility (slot 3)
-- ModuleScript in ReplicatedStorage (shared by client + server).
--------------------------------------------------------------------------------

local BandageConfig = {}

BandageConfig.CastDuration  = 4       -- seconds to channel
BandageConfig.TickInterval  = 1       -- seconds between heal ticks
BandageConfig.HealPerTick   = 10      -- HP restored per tick (10 HP/sec)
BandageConfig.MaxTotalHeal  = 40      -- max HP healed per use (4 ticks)
BandageConfig.Cooldown      = 20      -- seconds after use/interrupt before next use

-- Movement interrupt threshold (studs from start position)
BandageConfig.MoveThreshold = 1.5

return BandageConfig
