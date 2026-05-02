--[[
    GoldRushInit.server.lua  (ServerScriptService - Script)
    Wires GoldRushService into the shared EventScheduler lifecycle.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local EventScheduler
pcall(function()
    EventScheduler = require(ServerScriptService:WaitForChild("EventScheduler", 10))
end)

local GoldRushService
pcall(function()
    GoldRushService = require(ServerScriptService:WaitForChild("GoldRushService", 10))
end)

if not EventScheduler then
    warn("[GoldRushInit] EventScheduler not found - Gold Rush will not run")
    return
end

if not GoldRushService then
    warn("[GoldRushInit] GoldRushService not found - Gold Rush will not run")
    return
end

EventScheduler:OnStateChanged(function(active, eventId)
    if active and eventId == "GoldRush" then
        GoldRushService:Start()
    elseif not active then
        GoldRushService:Stop()
    end
end)

local MatchEndedBE = ServerScriptService:FindFirstChild("MatchEnded")
if MatchEndedBE and MatchEndedBE:IsA("BindableEvent") then
    MatchEndedBE.Event:Connect(function()
        GoldRushService:Stop()
    end)
end

local isActive, eventId = EventScheduler:IsActive()
if isActive and eventId == "GoldRush" then
    GoldRushService:Start()
end

print("[GoldRushInit] Gold Rush system ready")
