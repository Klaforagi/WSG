--[[
    EventConfig.lua  (ReplicatedStorage)
    Shared configuration for the timed match-event system.
    Both server (EventScheduler) and client (EventIndicator) read from here.
]]

local EventConfig = {}

---------------------------------------------------------------------
-- Debug / testing mode
-- Set to true to use short timings for rapid iteration.
-- Set to false before shipping to restore production timings.
---------------------------------------------------------------------
EventConfig.EventDebugMode = true

if EventConfig.EventDebugMode then
    -----------------------------------------------------------------
    -- TESTING values (fast iteration – events fire within seconds)
    -----------------------------------------------------------------
    EventConfig.EVENT_DURATION = 45      -- event duration in seconds (testing)

    EventConfig.EVENT1_MIN = 10          -- 10 s into the match (testing)
    EventConfig.EVENT1_MAX = 15          -- 15 s into the match (testing)

    EventConfig.EVENT2_MIN = 25          -- 25 s into the match (testing)
    EventConfig.EVENT2_MAX = 35          -- 35 s into the match (testing)
else
    -----------------------------------------------------------------
    -- PRODUCTION values (real match timings)
    -----------------------------------------------------------------
    EventConfig.EVENT_DURATION = 90      -- event duration in seconds

    EventConfig.EVENT1_MIN = 2 * 60 + 15   -- 2:15 into the match
    EventConfig.EVENT1_MAX = 3 * 60 + 15   -- 3:15 into the match

    EventConfig.EVENT2_MIN = 6 * 60         -- 6:00 into the match
    EventConfig.EVENT2_MAX = 7 * 60 + 15    -- 7:15 into the match
end

-- Pulse animation cycle duration (seconds) – used by client indicator
EventConfig.PULSE_CYCLE = 1.75  -- full pulse cycle duration in seconds

return EventConfig
