-- Deprecated shim: PlayerSettingsStore used to access DataStore directly.
-- DataStore access is now centralized in PlayerSettingsManager.server.lua.
-- This shim returns cached settings via the manager and prevents direct SetAsync usage.

local PlayerSettingsStore = {}

local manager = nil
pcall(function()
    manager = require(script.Parent:FindFirstChild("PlayerSettingsManager"))
end)

function PlayerSettingsStore:Load(player)
    if manager and manager.GetCachedSettings then
        return manager.GetCachedSettings(player)
    end
    return nil
end

function PlayerSettingsStore:Save(player, settings)
    -- Direct saving is deprecated. Use remote event UpdatePlayerSetting to update cache,
    -- and let the centralized manager autosave. Return false to indicate no direct save occurred.
    warn("[PlayerSettingsStore] Save() called but direct saving is disabled. Use PlayerSettingsManager.")
    return false
end

return PlayerSettingsStore
