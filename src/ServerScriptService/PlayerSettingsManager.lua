-- PlayerSettingsManager.server.lua
-- Centralized save manager for PlayerSettings_v1
-- Ensures: single DataStore access, in-memory cache, dirty flags, autosave, and safe remotes

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

local DATASTORE_NAME = "PlayerSettings_v1"
local store = nil
local ok_ds, ds = pcall(function()
    return DataStoreService:GetDataStore(DATASTORE_NAME)
end)
if ok_ds then store = ds end

local DEFAULTS = {
    MusicVolume = 1.0,
    SFXVolume = 1.0,
    CameraSensitivity = 0.5,
    InvertCamera = false,
    SprintMode = "Hold",
    ShowTooltips = true,
    ShowMinimap = true,
    ShowGameState = true,
    ShowHelm = true,
}

-- In-memory structures
local cache = {}               -- cache[userId] = settings table
local activePlayers = {}       -- activePlayers[userId] = player instance
local dirty = {}               -- dirty[userId] = true
local loading = {}             -- loading[userId] = true while DataStore read is in-flight

local AUTOSAVE_INTERVAL = 60   -- seconds

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = deepCopy(v) end
    return copy
end

local function ensureDefaults(tbl)
    if type(tbl) ~= "table" then tbl = {} end
    for k, v in pairs(DEFAULTS) do
        if tbl[k] == nil then tbl[k] = v end
    end
    return tbl
end

local function dataKeyForUserId(userId)
    return "user_" .. tostring(userId)
end

-- Save function (single SetAsync, no retry loop)
local function saveForUserId(userId)
    local settings = cache[userId]
    if type(settings) ~= "table" then return false end

    if not store then
        warn("[PlayerSettingsManager] DataStore unavailable; skipping save for", userId)
        return false
    end

    local key = dataKeyForUserId(userId)
    local ok, err = pcall(function()
        store:SetAsync(key, settings)
    end)
    if ok then
        dirty[userId] = nil
        return true
    else
        warn("[PlayerSettingsManager] Failed to save settings for", userId, tostring(err))
        return false
    end
end

local function loadForUserId(userId)
    -- Already cached – return immediately
    if cache[userId] then return cache[userId] end

    -- Another thread is already loading – wait for it to finish
    if loading[userId] then
        while loading[userId] do task.wait(0.05) end
        return cache[userId] or deepCopy(DEFAULTS)
    end

    loading[userId] = true

    if not store then
        cache[userId] = deepCopy(DEFAULTS)
        loading[userId] = nil
        return cache[userId]
    end

    local key = dataKeyForUserId(userId)
    local ok, data = pcall(function() return store:GetAsync(key) end)
    if ok and type(data) == "table" then
        cache[userId] = ensureDefaults(data)
    else
        cache[userId] = deepCopy(DEFAULTS)
    end

    loading[userId] = nil
    return cache[userId]
end

-- Public API
local PlayerSettingsManager = {}

function PlayerSettingsManager.GetCachedSettings(player)
    if not player or not player.UserId then return deepCopy(DEFAULTS) end
    local userId = tostring(player.UserId)
    -- Ensure data is loaded (blocks until DataStore read finishes if needed)
    local s = loadForUserId(userId)
    return deepCopy(s)
end

function PlayerSettingsManager.UpdateSetting(player, key, value)
    if not player or not player.UserId then return false end
    local userId = tostring(player.UserId)
    if cache[userId] == nil then
        cache[userId] = deepCopy(DEFAULTS)
    end
    if DEFAULTS[key] == nil then
        warn("[PlayerSettingsManager] Attempt to set unknown key", key)
        return false
    end
    cache[userId][key] = value
    dirty[userId] = true
    return true
end

-- Player lifecycle
Players.PlayerAdded:Connect(function(player)
    local userId = tostring(player.UserId)
    activePlayers[userId] = player
    task.spawn(function()
        loadForUserId(userId)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local userId = tostring(player.UserId)
    if dirty[userId] and SaveGuard:ClaimSave(player, "PlayerSettings") then
        pcall(function() saveForUserId(userId) end)
        SaveGuard:ReleaseSave(player, "PlayerSettings")
    end
    activePlayers[userId] = nil
end)

-- Autosave loop: only saves dirty players, once per interval
task.spawn(function()
    while true do
        task.wait(AUTOSAVE_INTERVAL)
        if SaveGuard:IsShuttingDown() then break end
        for userId, _ in pairs(dirty) do
            if cache[userId] and not SaveGuard:IsShuttingDown() then
                pcall(function() saveForUserId(userId) end)
            end
        end
    end
end)

-- BindToClose: save all dirty players before shutdown
game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for userId, _ in pairs(dirty) do
        if cache[userId] then
            -- Use userId as the player identifier since player object may be gone
            local playerObj = activePlayers[userId]
            local saveKey = playerObj or userId
            task.spawn(function()
                if SaveGuard:ClaimSave(saveKey, "PlayerSettings") then
                    pcall(function() saveForUserId(userId) end)
                    SaveGuard:ReleaseSave(saveKey, "PlayerSettings")
                end
            end)
        end
    end
    SaveGuard:WaitForAll(5)
end)

return PlayerSettingsManager
