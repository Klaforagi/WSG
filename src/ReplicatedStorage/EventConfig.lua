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
    -- TESTING values (fast iteration)
    -----------------------------------------------------------------
    EventConfig.EVENT_DURATION     = 45    -- event duration in seconds

    -- Probability rolling (debug)
    -- Starts at 50% so an event usually fires within the first 1–2 rolls.
    EventConfig.CHANCE_INITIAL     = 0.50  -- start at 50% (first roll already meaningful)
    EventConfig.CHANCE_STEP        = 0.25  -- +25% per interval
    EventConfig.CHANCE_CAP         = 0.75  -- never exceed 75%
    EventConfig.CHANCE_INTERVAL    = 5     -- seconds between each roll
    EventConfig.CHANCE_AFTER_EVENT = 0.50  -- reset here after event (no dead roll in debug)
else
    -----------------------------------------------------------------
    -- PRODUCTION values
    -----------------------------------------------------------------
    EventConfig.EVENT_DURATION     = 90    -- event duration in seconds

    -- Probability rolling (production)
    -- Rolls every 20s starting at 2%.  +2% per failed roll, cap 70%.
    -- Roll sequence: 2%, 4%, 6% … 70%, 70%, 70%…
    -- Expected time to first trigger ≈ 2:50.  Range roughly 0:20 – 6:00+.
    EventConfig.CHANCE_INITIAL     = 0.02  -- first roll at 2% (no wasted 0% roll)
    EventConfig.CHANCE_STEP        = 0.02  -- +2% per failed roll
    EventConfig.CHANCE_CAP         = 0.70  -- hard cap at 70%
    EventConfig.CHANCE_INTERVAL    = 20    -- seconds between each roll
    EventConfig.CHANCE_AFTER_EVENT = 0.02  -- reset to 2% after event (no wasted 0% roll)
end

-- Pulse animation cycle duration (seconds) – used by client indicator
EventConfig.PULSE_CYCLE = 1.75  -- full pulse cycle duration in seconds

---------------------------------------------------------------------
-- Event definitions (placeholder data for the info panel)
-- To add a new event, add an entry here keyed by a unique string id.
-- The client reads ActiveEventId to look up the matching def.
---------------------------------------------------------------------
EventConfig.EventDefs = {
    MeteorShower = {
        Name       = "Meteor Shower",
        Objective  = "Collect 3 Meteor Shards",
        Reward     = "50 Coins",
        RequiredShards = 3,
        CompletionRewardCoins = 50,
    },
}

-- Which event definition is used when an event activates.
-- Swap this value to change the active event type.
EventConfig.ActiveEventId = "MeteorShower"

return EventConfig
