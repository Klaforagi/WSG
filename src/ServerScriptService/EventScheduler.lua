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
local _manualThread = nil     -- admin-triggered auto-stop coroutine
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

local function cancelManualThread()
    if _manualThread then
        pcall(task.cancel, _manualThread)
        _manualThread = nil
    end
end

local function endActiveEvent(source)
    local endedEventId = _activeIdx
    if not endedEventId then return nil end

    _activeIdx = nil
    _eventEndTime = nil

    print(('[EventScheduler] Event \'%s\' ended (%s)'):format(tostring(endedEventId), tostring(source or "unknown")))
    broadcast(false, nil)
    notifyServer(false, nil)

    return endedEventId
end

local function startActiveEvent(eventId, durationSeconds, source)
    local def = getEventDef(eventId)
    if not def then
        return false, "Unknown event: " .. tostring(eventId)
    end

    if _activeIdx then
        endActiveEvent("replaced by " .. tostring(eventId))
    end

    local duration = math.max(1, tonumber(durationSeconds) or tonumber(EventConfig.EVENT_DURATION) or 60)
    EventConfig.ActiveEventId = eventId
    _activeIdx = eventId
    _eventEndTime = workspace:GetServerTimeNow() + duration

    print(('[EventScheduler] Event \'%s\' ACTIVE for %ds (%s)'):format(tostring(eventId), duration, tostring(source or "scheduler")))
    broadcast(true, eventId)
    announceEventStart(eventId)
    notifyServer(true, eventId)

    return true
end

local function buildAdminEventList()
    local list = {}
    local seen = {}

    local function addEvent(eventId)
        if type(eventId) ~= "string" or seen[eventId] then return end
        local def = getEventDef(eventId)
        if not def then return end
        seen[eventId] = true
        table.insert(list, {
            EventId = eventId,
            Name = def.Name or eventId,
            Objective = def.Objective or "",
            Reward = def.Reward or "",
        })
    end

    if type(EventConfig.EnabledEvents) == "table" then
        for _, entry in ipairs(EventConfig.EnabledEvents) do
            if type(entry) == "table" then
                addEvent(entry.Id or entry.id or entry.EventId or entry.eventId)
            else
                addEvent(entry)
            end
        end
    end

    local extraIds = {}
    if type(EventConfig.EventDefs) == "table" then
        for eventId, _ in pairs(EventConfig.EventDefs) do
            if not seen[eventId] then
                table.insert(extraIds, eventId)
            end
        end
    end
    table.sort(extraIds)
    for _, eventId in ipairs(extraIds) do
        addEvent(eventId)
    end

    return list
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

            if _activeIdx ~= nil then
                local remaining = (_eventEndTime or 0) - workspace:GetServerTimeNow()
                if remaining > 0 then
                    task.wait(math.min(remaining, EventConfig.CHANCE_INTERVAL))
                else
                    endActiveEvent("scheduler expiry")
                end
            else
                print(("[EventScheduler] Rolling for event… chance = %.0f%%"):format(chance * 100))

                if math.random() < chance then
                -- ---- EVENT START ----
                local eventId = chooseEventId()
                local started, startErr = startActiveEvent(eventId, EventConfig.EVENT_DURATION, ("triggered at %.0f%% chance"):format(chance * 100))
                if not started then
                    warn("[EventScheduler] Failed to start event: " .. tostring(startErr))
                    chance = math.min(chance + EventConfig.CHANCE_STEP, EventConfig.CHANCE_CAP)
                    continue
                end

                -- Run for EVENT_DURATION seconds
                while _running and _activeIdx == eventId do
                    local remaining = (_eventEndTime or 0) - workspace:GetServerTimeNow()
                    if remaining <= 0 then break end
                    task.wait(math.min(remaining, 1))
                end
                if not _running then return end

                -- ---- EVENT END ----
                if _activeIdx == eventId then
                    endActiveEvent("duration elapsed")
                end

                -- Reset chance; it will climb again from the next tick
                chance = EventConfig.CHANCE_AFTER_EVENT
                else
                -- Roll failed – increase chance for next interval
                chance = math.min(chance + EventConfig.CHANCE_STEP, EventConfig.CHANCE_CAP)
                print(("[EventScheduler] No event – chance raised to %.0f%%"):format(chance * 100))
                end
            end
        end
    end)
end

--- Call at match end or reset.  Stops the scheduler and clears state.
function EventScheduler:StopMatch()
    _running      = false
    _activeIdx    = nil
    _eventEndTime = nil
    cancelManualThread()

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

--- Starts a specific event immediately for admin/testing workflows.
--- Works whether or not the normal match scheduler is currently running.
function EventScheduler:StartEvent(eventId, durationSeconds)
    cancelManualThread()

    local started, err = startActiveEvent(eventId, durationSeconds or EventConfig.EVENT_DURATION, "admin")
    if not started then
        return false, err
    end

    local activeEventId = _activeIdx
    local activeEndTime = _eventEndTime
    _manualThread = task.spawn(function()
        while _activeIdx == activeEventId and _eventEndTime == activeEndTime do
            local remaining = (activeEndTime or 0) - workspace:GetServerTimeNow()
            if remaining <= 0 then break end
            task.wait(math.min(remaining, 1))
        end

        if _activeIdx == activeEventId and _eventEndTime == activeEndTime then
            endActiveEvent("admin duration elapsed")
        end
        _manualThread = nil
    end)

    return true
end

--- Stops the currently active event. If eventId is provided, it must match.
function EventScheduler:StopEvent(eventId)
    if not _activeIdx then
        return false, "No event is currently active"
    end
    if eventId and eventId ~= "" and eventId ~= _activeIdx then
        return false, tostring(eventId) .. " is not the active event"
    end

    cancelManualThread()
    endActiveEvent("admin stop")
    return true
end

--- Returns admin-panel friendly state and event metadata.
function EventScheduler:GetAdminState()
    return {
        Active = _activeIdx ~= nil,
        ActiveEventId = _activeIdx,
        EventEndTime = _eventEndTime,
        ServerTime = workspace:GetServerTimeNow(),
        MatchRunning = _running,
        Events = buildAdminEventList(),
    }
end

--- Send state to a specific player (call from PlayerAdded handler).
function EventScheduler:SyncPlayer(player)
    sendStateTo(player)
end

return EventScheduler
