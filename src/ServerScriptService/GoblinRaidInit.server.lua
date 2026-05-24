--[[
    GoblinRaidInit.server.lua  (ServerScriptService - Script)
    Wires GoblinRaidService into the shared EventScheduler lifecycle.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local EventScheduler
pcall(function()
    EventScheduler = require(ServerScriptService:WaitForChild("EventScheduler", 10))
end)

local GoblinRaidService
pcall(function()
    GoblinRaidService = require(ServerScriptService:WaitForChild("GoblinRaidService", 10))
end)

if not EventScheduler then
    warn("[GoblinRaidInit] EventScheduler not found - Goblin Raid will not run")
    return
end

if not GoblinRaidService then
    warn("[GoblinRaidInit] GoblinRaidService not found - Goblin Raid will not run")
    return
end

EventScheduler:OnStateChanged(function(active, eventId)
    if active and eventId == "GoblinRaid" then
        GoblinRaidService:Start()
    else
        GoblinRaidService:Stop()
    end
end)

local isActive, eventId = EventScheduler:IsActive()
if isActive and eventId == "GoblinRaid" then
    GoblinRaidService:Start()
end

print("[GoblinRaidInit] Goblin Raid system ready")