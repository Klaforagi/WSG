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
-- Payload:  (active: boolean, eventId: string?)
--   active = true  → an event just started   (eventId = selected event id)
--   active = false → the current event ended  (eventId = nil)
---------------------------------------------------------------------
local EventStateChanged = ReplicatedStorage:FindFirstChild("EventStateChanged")
if not EventStateChanged then
    EventStateChanged = Instance.new("RemoteEvent")
    EventStateChanged.Name = "EventStateChanged"
    EventStateChanged.Parent = ReplicatedStorage
end

local FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
if not FlagStatus or not FlagStatus:IsA("RemoteEvent") then
    if FlagStatus then FlagStatus:Destroy() end
    FlagStatus = Instance.new("RemoteEvent")
    FlagStatus.Name = "FlagStatus"
    FlagStatus.Parent = ReplicatedStorage
end

local EVENT_ACTIVE_ATTR = "EventActive"
local EVENT_ID_ATTR     = "ActiveEventId"
local EVENT_END_ATTR    = "EventEndTime"

---------------------------------------------------------------------
-- Module
---------------------------------------------------------------------
local EventScheduler = {}

local _running      = false   -- true while a match is active
local _activeIdx    = nil     -- currently active event id, or nil
local _thread       = nil     -- the scheduler coroutine
local _eventEndTime = nil     -- server timestamp when the active event ends
local _serverCallbacks = {} -- server-side listeners (registered via OnStateChanged)

---------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------

local function setReplicatedEventState(active, idx)
    pcall(function()
        ReplicatedStorage:SetAttribute(EVENT_ACTIVE_ATTR, active == true)
        ReplicatedStorage:SetAttribute(EVENT_ID_ATTR, active and tostring(idx or "") or "")
        ReplicatedStorage:SetAttribute(EVENT_END_ATTR, active and (_eventEndTime or 0) or 0)
    end)
end

local function getEventDef(eventId)
    return EventConfig.EventDefs and EventConfig.EventDefs[eventId]
end

local function chooseEventId()
    local forced = EventConfig.ForcedEventId
    if forced and getEventDef(forced) then
        return forced
    end

    local entries = {}
    local totalWeight = 0
    local enabledEvents = EventConfig.EnabledEvents

    if type(enabledEvents) == "table" then
        for _, entry in ipairs(enabledEvents) do
            local eventId = entry
            local weight = 1
            if type(entry) == "table" then
                eventId = entry.Id or entry.id or entry.EventId or entry.eventId
                weight = tonumber(entry.Weight or entry.weight) or 1
            end

            if eventId and getEventDef(eventId) and weight > 0 then
                totalWeight = totalWeight + weight
                table.insert(entries, { id = eventId, cumulativeWeight = totalWeight })
            end
        end
    end

    if #entries == 0 then
        local fallback = EventConfig.ActiveEventId or "MeteorShower"
        if getEventDef(fallback) then
            return fallback
        end
        return "MeteorShower"
    end

    local roll = math.random() * totalWeight
    for _, entry in ipairs(entries) do
        if roll <= entry.cumulativeWeight then
            return entry.id
        end
    end

    return entries[#entries].id
end

local function broadcast(active, idx)
    setReplicatedEventState(active, idx)
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

local function announceEventStart(eventId)
    local def = getEventDef(eventId)
    local text = def and def.Announcement
    if not text or text == "" then return end
    local color = def.AnnouncementColor or Color3.fromRGB(255, 180, 55)
    pcall(function()
        FlagStatus:FireAllClients("event", text, nil, nil, color)
    end)
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

--- Call at match start.  Begins the probability-based event roll loop.
--- Every CHANCE_INTERVAL seconds a roll is made against the current chance.
--- If the roll succeeds the event runs for EVENT_DURATION seconds, then
--- chance resets to CHANCE_AFTER_EVENT and climbs again.
--- If the roll fails, chance increases by CHANCE_STEP for the next roll.
function EventScheduler:StartMatch(_matchStartTick)
    -- Clean up any previous match first
    self:StopMatch()

    _running   = true
    _activeIdx = nil

    print(("[EventScheduler] Match started – initial event chance %.0f%%  interval %ds")
        :format(EventConfig.CHANCE_INITIAL * 100, EventConfig.CHANCE_INTERVAL))

    -- Broadcast initial inactive state
    broadcast(false, nil)

    _thread = task.spawn(function()
        local chance = EventConfig.CHANCE_INITIAL

        while _running do
            -- Wait one roll interval
            task.wait(EventConfig.CHANCE_INTERVAL)
            if not _running then return end

            print(("[EventScheduler] Rolling for event… chance = %.0f%%"):format(chance * 100))

            if math.random() < chance then
                -- ---- EVENT START ----
                local eventId = chooseEventId()
                _activeIdx    = eventId
                _eventEndTime = workspace:GetServerTimeNow() + EventConfig.EVENT_DURATION
                print((("[EventScheduler] Event '%s' ACTIVE (triggered at %.0f%% chance)"):format(eventId, chance * 100)))
                broadcast(true, eventId)
                announceEventStart(eventId)
                notifyServer(true, eventId)

                -- Run for EVENT_DURATION seconds
                local activatedAt = workspace:GetServerTimeNow()
                while _running do
                    local elapsed = workspace:GetServerTimeNow() - activatedAt
                    if elapsed >= EventConfig.EVENT_DURATION then break end
                    task.wait(math.min(EventConfig.EVENT_DURATION - elapsed, 1))
                end
                if not _running then return end

                -- ---- EVENT END ----
                _activeIdx    = nil
                _eventEndTime = nil
                print("[EventScheduler] Event ENDED – resetting chance to 0%")
                broadcast(false, nil)
                notifyServer(false, nil)

                -- Reset chance; it will climb again from the next tick
                chance = EventConfig.CHANCE_AFTER_EVENT
            else
                -- Roll failed – increase chance for next interval
                chance = math.min(chance + EventConfig.CHANCE_STEP, EventConfig.CHANCE_CAP)
                print(("[EventScheduler] No event – chance raised to %.0f%%"):format(chance * 100))
            end
        end
    end)
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
--- callback(active: boolean, eventId: string?)
--- Used by systems like MeteorShowerService to start/stop during events.
function EventScheduler:OnStateChanged(callback)
    table.insert(_serverCallbacks, callback)
end

--- Returns whether an event is currently active and which event id.
function EventScheduler:IsActive()
    return _activeIdx ~= nil, _activeIdx
end

--- Send state to a specific player (call from PlayerAdded handler).
function EventScheduler:SyncPlayer(player)
    sendStateTo(player)
end

return EventScheduler
