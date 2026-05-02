--------------------------------------------------------------------------------
-- EventAtmosphere.client.lua
--
-- Listens for timed event state and applies client-only Lighting/Sky/
-- Atmosphere mood changes through EventAtmosphereController.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local EventAtmosphereController = require(modules:WaitForChild("EventAtmosphereController"))

local function syncFromReplicatedState()
    local active = ReplicatedStorage:GetAttribute("EventActive") == true
    local eventId = ReplicatedStorage:GetAttribute("ActiveEventId")

    if active and eventId and eventId ~= "" then
        EventAtmosphereController.Start(eventId)
    else
        EventAtmosphereController.Stop()
    end
end

local EventStateChanged = ReplicatedStorage:WaitForChild("EventStateChanged", 15)
if EventStateChanged then
    EventStateChanged.OnClientEvent:Connect(function(active, eventId)
        if active then
            EventAtmosphereController.Start(eventId)
        else
            EventAtmosphereController.Stop(eventId)
        end
    end)
else
    warn("[EventAtmosphere] EventStateChanged remote not found")
end

ReplicatedStorage:GetAttributeChangedSignal("EventActive"):Connect(syncFromReplicatedState)
ReplicatedStorage:GetAttributeChangedSignal("ActiveEventId"):Connect(syncFromReplicatedState)

task.defer(syncFromReplicatedState)
