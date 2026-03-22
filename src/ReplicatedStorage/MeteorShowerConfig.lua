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
MeteorShowerConfig.METEOR_COLOR       = Color3.fromRGB(45, 35, 30)    -- dark rocky body
MeteorShowerConfig.FIRE_COLOR         = Color3.fromRGB(255, 120, 20)  -- primary flame
MeteorShowerConfig.FIRE_SEC_COLOR     = Color3.fromRGB(255, 60, 10)   -- secondary flame / embers
MeteorShowerConfig.GLOW_COLOR         = Color3.fromRGB(255, 140, 40)  -- PointLight colour
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
-- Target zones
-- Meteors land inside invisible anchored parts placed in this folder.
-- If the folder is missing, a default 200x200 fallback zone is created
-- at the world origin so testing works immediately.
---------------------------------------------------------------------
MeteorShowerConfig.ZONE_FOLDER_NAME   = "EventMeteorZones"

return MeteorShowerConfig
