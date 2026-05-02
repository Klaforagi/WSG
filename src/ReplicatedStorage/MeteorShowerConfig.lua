--[[
    MeteorShowerConfig.lua  (ReplicatedStorage)
    Centralized tuning constants for the Meteor Shower event.
    Readable by both server (MeteorShowerService) and client (future UI).

    All major values are exposed here so you can iterate quickly
    without digging through implementation code.
]]

local MeteorShowerConfig = {}

---------------------------------------------------------------------
-- Spawn timing
---------------------------------------------------------------------
MeteorShowerConfig.SPAWN_INTERVAL_MIN = 1.0   -- minimum seconds between meteor spawns
MeteorShowerConfig.SPAWN_INTERVAL_MAX = 2.5   -- maximum seconds between meteor spawns

---------------------------------------------------------------------
-- Spawn position
---------------------------------------------------------------------
MeteorShowerConfig.SPAWN_HEIGHT       = 200    -- studs above the target landing point
MeteorShowerConfig.SPAWN_ANGLE_JITTER = 15     -- max horizontal offset (studs) at spawn height
                                                -- gives each meteor a slightly diagonal trajectory

---------------------------------------------------------------------
-- Meteor appearance
---------------------------------------------------------------------
MeteorShowerConfig.METEOR_DIAMETER    = 6      -- diameter in studs (Part is a ball)
MeteorShowerConfig.METEOR_COLOR       = Color3.fromRGB(220, 235, 255)  -- pale icy body
MeteorShowerConfig.FIRE_COLOR         = Color3.fromRGB(160, 210, 255)  -- cool blue flame
MeteorShowerConfig.FIRE_SEC_COLOR     = Color3.fromRGB(220, 240, 255)  -- white-blue embers
MeteorShowerConfig.GLOW_COLOR         = Color3.fromRGB(160, 210, 255)  -- PointLight colour
MeteorShowerConfig.GLOW_BRIGHTNESS    = 2
MeteorShowerConfig.GLOW_RANGE         = 30

---------------------------------------------------------------------
-- Fall behaviour
---------------------------------------------------------------------
MeteorShowerConfig.FALL_DURATION      = 1.2    -- seconds from sky to ground
                                                -- uses Quad-In easing (accelerates like real gravity)

---------------------------------------------------------------------
-- Safety caps
---------------------------------------------------------------------
MeteorShowerConfig.MAX_ACTIVE_METEORS = 8      -- hard cap; spawns are skipped if at limit

---------------------------------------------------------------------
-- Impact & cleanup
---------------------------------------------------------------------
MeteorShowerConfig.IMPACT_FLASH_DURATION  = 0.5  -- seconds for the flash expand+fade
MeteorShowerConfig.IMPACT_CLEANUP_DELAY   = 0.6  -- seconds after impact before meteor part is removed

---------------------------------------------------------------------
-- Impact damage
---------------------------------------------------------------------
MeteorShowerConfig.DIRECT_HIT_RADIUS       = 8    -- studs – full damage zone
MeteorShowerConfig.SPLASH_RADIUS           = 20   -- studs – outer splash zone
MeteorShowerConfig.IMPACT_DAMAGE           = 10   -- flat damage for direct and splash hits

---------------------------------------------------------------------
-- Meteor Shards (collectible drops)
---------------------------------------------------------------------
MeteorShowerConfig.SHARD_SPAWN_CHANCE      = 1.0  -- 1.0 = every impact drops a shard
MeteorShowerConfig.SHARD_LIFETIME          = 20   -- seconds before uncollected shard despawns
MeteorShowerConfig.SHARD_REWARD_COINS      = 5    -- coins granted per shard collected
MeteorShowerConfig.SHARD_SIZE              = Vector3.new(2.5, 2.5, 2.5)  -- sphere diameter
MeteorShowerConfig.SHARD_COLOR             = Color3.fromRGB(180, 225, 255)  -- light bright blue
MeteorShowerConfig.SHARD_LIGHT_RANGE       = 18
MeteorShowerConfig.SHARD_LIGHT_BRIGHTNESS  = 1.5
MeteorShowerConfig.SHARD_Y_OFFSET          = -1    -- studs above ground level

---------------------------------------------------------------------
-- Target zones
-- Meteors land inside invisible anchored parts placed in this folder.
-- If the folder is missing, a default 200x200 fallback zone is created
-- at the world origin so testing works immediately.
---------------------------------------------------------------------
MeteorShowerConfig.ZONE_FOLDER_NAME   = "EventMeteorZones"

return MeteorShowerConfig
