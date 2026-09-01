--------------------------------------------------------------------------------
-- DashConfig.lua  –  Tunable values for the player dash ability
-- ModuleScript in ReplicatedStorage (shared by client + server).
--
-- Change values here to tweak dash feel without touching logic scripts.
--------------------------------------------------------------------------------

local DashConfig = {}

-- Movement
DashConfig.Distance     = 22      -- studs to travel (same on ground and in air)
DashConfig.Duration     = 0.2     -- seconds the dash lasts
DashConfig.DecelDuration = 0.2    -- seconds to ease extra dash speed down to WalkSpeed
DashConfig.Cooldown     = 8       -- seconds between dashes

-- Physics
DashConfig.VerticalDamp = 0       -- no vertical boost; dash is a flat XZ burst
DashConfig.WallRayExtra = 3       -- extra studs for wall-detection raycast
DashConfig.MaxForce     = 1e6     -- high enough to fully override existing velocity

-- Visual effects
DashConfig.EffectEnabled    = true
DashConfig.TrailLifetime    = 0.35   -- seconds the trail stays visible from dash start
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
