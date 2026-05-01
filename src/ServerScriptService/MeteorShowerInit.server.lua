--[[
    MeteorShowerInit.server.lua  (ServerScriptService – Script)
    Wires MeteorShowerService into the EventScheduler lifecycle.

    When an event becomes active  → starts the meteor shower
    When an event ends            → stops the meteor shower
    When the match ends           → ensures the shower is stopped

    This is the only file that knows about both EventScheduler and
    MeteorShowerService; neither of those modules depends on each other.
]]

local ServerScriptService = game:GetService("ServerScriptService")

---------------------------------------------------------------------
-- Require dependencies (safe waits; order does not matter because
-- EventScheduler's events fire ≥10 s into the match in debug mode)
---------------------------------------------------------------------
local EventScheduler
pcall(function()
    EventScheduler = require(ServerScriptService:WaitForChild("EventScheduler", 10))
end)

local MeteorShowerService
pcall(function()
    MeteorShowerService = require(ServerScriptService:WaitForChild("MeteorShowerService", 10))
end)

if not EventScheduler then
    warn("[MeteorShowerInit] EventScheduler not found – meteor shower will not run")
    return
end

if not MeteorShowerService then
    warn("[MeteorShowerInit] MeteorShowerService not found – meteor shower will not run")
    return
end

---------------------------------------------------------------------
-- Hook into event state changes
---------------------------------------------------------------------
EventScheduler:OnStateChanged(function(active, eventId)
    if active and eventId == "MeteorShower" then
        MeteorShowerService:Start()
    elseif not active then
        MeteorShowerService:Stop()
    end
end)

-- Safety net: also listen for MatchEnded bindable in case the match
-- ends abruptly (e.g. all players leave).  EventScheduler:StopMatch()
-- already fires the callback above, but this is a belt-and-suspenders guard.
local MatchEndedBE = ServerScriptService:FindFirstChild("MatchEnded")
if MatchEndedBE and MatchEndedBE:IsA("BindableEvent") then
    MatchEndedBE.Event:Connect(function()
        MeteorShowerService:Stop()
    end)
end

-- Catch the case where an event is already active when this script loads
-- (unlikely in practice but safe to check).
local isActive, idx = EventScheduler:IsActive()
if isActive and idx == "MeteorShower" then
    MeteorShowerService:Start()
end

print("[MeteorShowerInit] Meteor shower system ready")
