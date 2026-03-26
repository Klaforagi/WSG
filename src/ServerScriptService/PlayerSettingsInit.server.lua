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

local store = nil
local ok, mod = pcall(function()
    return require(script:FindFirstChild("PlayerSettingsStore") or script.Parent:FindFirstChild("PlayerSettingsStore"))
end)
if ok and mod then
    store = mod
else
    -- try sibling path
    pcall(function()
        store = require(script.Parent:FindFirstChild("PlayerSettingsStore"))
    end)
end

local getRF = getOrCreateRemoteFunction("GetPlayerSettings")
local setRF = getOrCreateRemoteFunction("SetPlayerSettings")

getRF.OnServerInvoke = function(player)
    if store and store.Load then
        local data = store:Load(player)
        return data or {}
    end
    return {}
end

setRF.OnServerInvoke = function(player, settings)
    if store and store.Save then
        local ok = store:Save(player, settings)
        return ok
    end
    return false
end
