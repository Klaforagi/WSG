--------------------------------------------------------------------------------
-- BandageConfig.lua  –  Tunable values for the Bandage utility (slot 3)
-- ModuleScript in ReplicatedStorage (shared by client + server).
--------------------------------------------------------------------------------

local BandageConfig = {}

BandageConfig.CastDuration  = 6       -- seconds to channel
BandageConfig.TickInterval  = 0.5      -- seconds between heal ticks
BandageConfig.HealPerTick   = 10      -- HP restored per tick (10 HP/sec)
BandageConfig.MaxTotalHeal  = 100      -- max HP healed per use (4 ticks)
BandageConfig.Cooldown      = 10     -- seconds after use/interrupt before next use
BandageConfig.TargetRange   = 8       -- studs for teammate bandage prompt/use

-- Movement interrupt threshold (studs from start position)
BandageConfig.MoveThreshold = 1.5
-- Multiplier applied to TargetRange while a bandage is active so the healed
-- player can move further before the cast is interrupted. Default 3x.
BandageConfig.ActiveTargetRangeMultiplier = 3

return BandageConfig
