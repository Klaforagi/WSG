--------------------------------------------------------------------------------
-- DashConfig.lua  –  Tunable values for the player dash ability
-- ModuleScript in ReplicatedStorage (shared by client + server).
--
-- Change values here to tweak dash feel without touching logic scripts.
--------------------------------------------------------------------------------

local DashConfig = {}

-- Movement
DashConfig.Distance     = 22      -- studs to travel
DashConfig.Duration     = 0.18    -- seconds the dash lasts
DashConfig.Cooldown     = 3      -- seconds between dashes

-- Physics
DashConfig.VerticalDamp = 0.05    -- small upward nudge to stay grounded over bumps
DashConfig.WallRayExtra = 3       -- extra studs for wall-detection raycast

-- Visual effects
DashConfig.EffectEnabled    = true
DashConfig.TrailLifetime    = 0.25   -- seconds the trail stays visible
DashConfig.ParticleCount    = 18     -- speed-streak particles emitted per dash
DashConfig.GhostTransparency = 0.7  -- afterimage starting transparency
DashConfig.GhostFadeDuration = 0.35 -- seconds for afterimage to vanish

-- Animation (leave empty string to skip; set an rbxassetid to play)
DashConfig.AnimationId  = ""

-- Default effect color (white – used when no cosmetic trail is equipped)
DashConfig.DefaultEffectColor = Color3.fromRGB(255, 255, 255)

-- The EffectDefs Id that every player starts with
DashConfig.DefaultTrailId = "DefaultTrail"

return DashConfig
