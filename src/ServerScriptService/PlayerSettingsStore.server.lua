-- PlayerSettingsStore.server.lua
-- DEPRECATED: Direct DataStore access moved to PlayerSettingsManager.server.lua
-- This file is kept as a no-op to prevent errors from any legacy require() calls.
-- It does NOT open any DataStore connections.

local PlayerSettingsStore = {}

function PlayerSettingsStore:Load(player)
    warn("[PlayerSettingsStore.server] Load() is deprecated. Use GetPlayerSettings remote instead.")
    return nil
end

function PlayerSettingsStore:Save(player, settings)
    warn("[PlayerSettingsStore.server] Save() is deprecated. Use UpdatePlayerSetting remote instead.")
    return false
end

return PlayerSettingsStore
