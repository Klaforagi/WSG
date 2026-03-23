--[[
    EventScheduler.lua  (ServerScriptService – ModuleScript)
    Server-authoritative event scheduler for timed match events.

    Usage (from GameManager):
        local EventScheduler = require(EventScheduler)
        EventScheduler:StartMatch(matchStartTick)   -- call at match start
        EventScheduler:StopMatch()                   -- call at match end / reset

    The scheduler pre-rolls two random event times at match start, runs them
    for EVENT_DURATION seconds each, and replicates only a boolean "active"
    flag plus the event index to clients via a single RemoteEvent.

    Event overlap is prevented: if event 1's end would bleed into event 2's
    start, event 2 is pushed back to start after event 1 finishes.
]]

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")

local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))

---------------------------------------------------------------------
-- Remote: server → client  (EventStateChanged)
-- Payload:  (active: boolean, eventIndex: number?)
--   active = true  → an event just started   (eventIndex = 1 or 2)
--   active = false → the current event ended  (eventIndex = nil)
---------------------------------------------------------------------
local EventStateChanged = ReplicatedStorage:FindFirstChild("EventStateChanged")
if not EventStateChanged then
    EventStateChanged = Instance.new("RemoteEvent")
    EventStateChanged.Name = "EventStateChanged"
    EventStateChanged.Parent = ReplicatedStorage
end

---------------------------------------------------------------------
-- Module
---------------------------------------------------------------------
local EventScheduler = {}

local _running      = false   -- true while a match is active
local _activeIdx    = nil     -- currently active event index (1 or 2), or nil
local _thread       = nil     -- the scheduler coroutine
local _eventEndTime = nil     -- server timestamp when the active event ends
local _serverCallbacks = {} -- server-side listeners (registered via OnStateChanged)

---------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------
local function randomInRange(lo, hi)
    return lo + math.random() * (hi - lo)
end

local function broadcast(active, idx)
    pcall(function()
        EventStateChanged:FireAllClients(active, idx, _eventEndTime)
    end)
end

--- Notify server-side listeners of event state changes.
local function notifyServer(active, idx)
    for _, cb in ipairs(_serverCallbacks) do
        pcall(cb, active, idx)
    end
end

--- Send current event state to a single player (for late-joiners).
local function sendStateTo(player)
    pcall(function()
        EventStateChanged:FireClient(player, _activeIdx ~= nil, _activeIdx, _eventEndTime)
    end)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

--- Call at match start.  Rolls event times and begins the scheduler loop.
function EventScheduler:StartMatch(matchStartTick)
    -- Clean up any previous match first
    self:StopMatch()

    -- Pre-roll event start offsets (seconds into the match)
    -- Event 1 time window (configurable in EventConfig)
    local e1Start = randomInRange(EventConfig.EVENT1_MIN, EventConfig.EVENT1_MAX)
    -- Event 2 time window (configurable in EventConfig)
    local e2Start = randomInRange(EventConfig.EVENT2_MIN, EventConfig.EVENT2_MAX)

    -- Prevent overlap: push event 2 after event 1 ends if necessary
    local e1End = e1Start + EventConfig.EVENT_DURATION
    if e2Start < e1End then
        e2Start = e1End + 1  -- 1-second gap minimum
    end

    local events = {
        { startOffset = e1Start, duration = EventConfig.EVENT_DURATION },
        { startOffset = e2Start, duration = EventConfig.EVENT_DURATION },
    }

    print(("[EventScheduler] Match events rolled – E1 @ %.1fs  E2 @ %.1fs  duration %ds")
        :format(e1Start, e2Start, EventConfig.EVENT_DURATION))

    _running   = true
    _activeIdx = nil

    -- Broadcast initial inactive state
    broadcast(false, nil)

    _thread = task.spawn(function()
        for i, ev in ipairs(events) do
            if not _running then return end

            -- Wait until event start time
            while _running do
                local elapsed = workspace:GetServerTimeNow() - matchStartTick
                if elapsed >= ev.startOffset then break end
                task.wait(math.min(ev.startOffset - elapsed, 1))
            end
            if not _running then return end

            -- Activate event
            _activeIdx = i
            _eventEndTime = workspace:GetServerTimeNow() + ev.duration
            print(("[EventScheduler] Event %d ACTIVE"):format(i))
            broadcast(true, i)
            notifyServer(true, i)

            -- Wait for event duration
            local activatedAt = workspace:GetServerTimeNow()
            while _running do
                local dur = workspace:GetServerTimeNow() - activatedAt
                if dur >= ev.duration then break end
                task.wait(math.min(ev.duration - dur, 1))
            end
            if not _running then return end

            -- Deactivate event
            _activeIdx = nil
            _eventEndTime = nil
            print(("[EventScheduler] Event %d ENDED"):format(i))
            broadcast(false, nil)
            notifyServer(false, nil)
        end
    end)

    -- Late-join support: send current state to players who join mid-match
    -- (connection is cleaned up in StopMatch via _running guard)
end

--- Call at match end or reset.  Stops the scheduler and clears state.
function EventScheduler:StopMatch()
    _running      = false
    _activeIdx    = nil
    _eventEndTime = nil

    if _thread then
        pcall(task.cancel, _thread)
        _thread = nil
    end

    -- Broadcast inactive so any lingering client UI cleans up
    broadcast(false, nil)
    notifyServer(false, nil)
end

--- Register a server-side callback for event state changes.
--- callback(active: boolean, eventIndex: number?)
--- Used by systems like MeteorShowerService to start/stop during events.
function EventScheduler:OnStateChanged(callback)
    table.insert(_serverCallbacks, callback)
end

--- Returns whether an event is currently active and which index.
function EventScheduler:IsActive()
    return _activeIdx ~= nil, _activeIdx
end

--- Send state to a specific player (call from PlayerAdded handler).
function EventScheduler:SyncPlayer(player)
    sendStateTo(player)
end

return EventScheduler
