-- PlayerSettingsManager.server.lua
-- Centralized cache for PlayerSettings_v1.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

local DATASTORE_NAME = "PlayerSettings_v1"
local store = nil
local okStore, resolvedStore = pcall(function()
    return DataStoreService:GetDataStore(DATASTORE_NAME)
end)
if okStore then
    store = resolvedStore
end

local DEFAULTS = {
    MusicVolume = 1.0,
    SFXVolume = 1.0,
    CameraSensitivity = 0.5,
    InvertCamera = false,
    SprintMode = "Hold",
    ShowTooltips = true,
    ShowGameState = true,
    ShowHelm = true,
    ShowPlayerHighlights = false,
}

local cache = {}
local activePlayers = {}
local dirty = {}
local loading = {}
local sectionRegistered = false

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for key, value in pairs(orig) do
        copy[key] = deepCopy(value)
    end
    return copy
end

local function ensureDefaults(tbl)
    if type(tbl) ~= "table" then tbl = {} end
    local clean = {}
    for key, defaultValue in pairs(DEFAULTS) do
        if tbl[key] == nil then
            clean[key] = defaultValue
        else
            clean[key] = tbl[key]
        end
    end
    return clean
end

local function dataKeyForUserId(userId)
    return "user_" .. tostring(userId)
end

local function saveForUserId(userId, payload)
    local settings = payload or cache[userId]
    if type(settings) ~= "table" then
        return false, "missing settings"
    end
    if not store then
        warn("[PlayerSettingsManager] DataStore unavailable; skipping save for", userId)
        return false, "missing datastore"
    end

    local key = dataKeyForUserId(userId)
    local success, _, err = DataStoreOps.Update(store, key, "PlayerSettings/" .. key, function()
        return settings
    end)
    if success then
        dirty[userId] = nil
        return true
    end

    warn("[PlayerSettingsManager] Failed to save settings for", userId, tostring(err))
    return false, err
end

local function loadForUserId(userId)
    if cache[userId] then
        return cache[userId], "existing", nil
    end

    if loading[userId] then
        while loading[userId] do
            task.wait(0.05)
        end
        return cache[userId] or deepCopy(DEFAULTS), "existing", nil
    end

    loading[userId] = true

    if not store then
        cache[userId] = deepCopy(DEFAULTS)
        loading[userId] = nil
        return cache[userId], "failed", "missing datastore"
    end

    local key = dataKeyForUserId(userId)
    local success, data, err = DataStoreOps.Load(store, key, "PlayerSettings/" .. key)
    if success and type(data) == "table" then
        cache[userId] = ensureDefaults(data)
    else
        cache[userId] = deepCopy(DEFAULTS)
    end

    loading[userId] = nil
    if not success then
        return cache[userId], "failed", err
    end
    if data == nil then
        return cache[userId], "new", nil
    end
    return cache[userId], "existing", nil
end

local function getSaveDataForPlayer(player)
    if not player or not player.UserId then return nil end
    return deepCopy(cache[tostring(player.UserId)])
end

local function loadProfile(player)
    local userId = tostring(player.UserId)
    local settings, status, reason = loadForUserId(userId)
    activePlayers[userId] = player
    return {
        status = status,
        data = deepCopy(settings),
        reason = reason,
    }
end

local function registerSection()
    if sectionRegistered then
        return
    end
    sectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "PlayerSettings",
        Priority = 90,
        Critical = false,
        Load = loadProfile,
        GetSaveData = getSaveDataForPlayer,
        Save = function(player, currentData)
            return saveForUserId(tostring(player.UserId), currentData)
        end,
        Cleanup = function(player)
            local userId = tostring(player.UserId)
            activePlayers[userId] = nil
            dirty[userId] = nil
            loading[userId] = nil
            cache[userId] = nil
        end,
    })
end

local PlayerSettingsManager = {}

function PlayerSettingsManager.GetCachedSettings(player)
    if not player or not player.UserId then return deepCopy(DEFAULTS) end
    local userId = tostring(player.UserId)
    local settings = loadForUserId(userId)
    return deepCopy(settings)
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
    DataSaveCoordinator:MarkDirty(player, "PlayerSettings", "player_setting")
    return true
end

registerSection()

Players.PlayerAdded:Connect(function(player)
    activePlayers[tostring(player.UserId)] = player
    task.spawn(function()
        DataSaveCoordinator:LoadSection(player, "PlayerSettings")
    end)
end)

return PlayerSettingsManager
