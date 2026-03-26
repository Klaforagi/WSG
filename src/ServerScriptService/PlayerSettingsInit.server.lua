local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreateRemoteFunction(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then return existing end
    if existing then existing:Destroy() end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = ReplicatedStorage
    return rf
end

local function getOrCreateRemoteEvent(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then return existing end
    if existing then existing:Destroy() end
    local ev = Instance.new("RemoteEvent")
    ev.Name = name
    ev.Parent = ReplicatedStorage
    return ev
end

-- Use the centralized manager for all settings operations
local manager = nil
pcall(function()
    manager = require(script:FindFirstChild("PlayerSettingsManager") or script.Parent:FindFirstChild("PlayerSettingsManager"))
end)

local getRF = getOrCreateRemoteFunction("GetPlayerSettings")
local updateEV = getOrCreateRemoteEvent("UpdatePlayerSetting")

-- RemoteFunction: returns cached data ONLY (no DataStore calls here)
getRF.OnServerInvoke = function(player)
    if manager and manager.GetCachedSettings then
        return manager.GetCachedSettings(player)
    end
    return {}
end

-- RemoteEvent: clients fire this to update a single setting
-- Server updates cache and marks player dirty; NO saving here
updateEV.OnServerEvent:Connect(function(player, key, value)
    if manager and manager.UpdateSetting then
        manager.UpdateSetting(player, key, value)
    end
end)
