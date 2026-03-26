local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("PlayerSettings_v1")

local PlayerSettingsStore = {}

function PlayerSettingsStore:Load(player)
    local key = "user_" .. tostring(player.UserId)
    local ok, data = pcall(function()
        return store:GetAsync(key)
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

function PlayerSettingsStore:Save(player, settings)
    if type(settings) ~= "table" then return false end
    local key = "user_" .. tostring(player.UserId)
    local ok, err = pcall(function()
        store:SetAsync(key, settings)
    end)
    if not ok then
        warn("[PlayerSettingsStore] Failed to save settings for", player.Name, err)
        return false
    end
    return true
end

return PlayerSettingsStore
