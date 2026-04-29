--------------------------------------------------------------------------------
-- PlayerDataAdminInit.server.lua
--
-- Wires up the Admin "User Data" tab:
--   * Records every joining player into the SavedPlayersIndex.
--   * Creates and serves the four admin RemoteFunctions:
--       AdminGetSavedPlayers    (page, pageSize) -> list page
--       AdminSearchSavedPlayers (query)          -> matched entries
--       AdminGetUserData        (userId)         -> full snapshot
--       AdminResetUserData      (userId, type)   -> reset confirmation
--
-- Defense-in-depth:
--   * Every handler verifies DevUserIds.IsDev before doing any work.
--   * Per-player rate limit on every remote.
--   * All inputs are sanitized and clamped.
--   * Reset type is whitelisted against AdminUserDataConfig.ResetTypes.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevUserIds            = require(ReplicatedStorage:WaitForChild("DevUserIds"))
local AdminUserDataConfig   = require(ReplicatedStorage:WaitForChild("AdminUserDataConfig"))

local SavedPlayersIndexService = require(script.Parent.SavedPlayersIndexService)
local PlayerDataAdminService   = require(script.Parent.PlayerDataAdminService)

--------------------------------------------------------------------------------
-- Remote folder: ReplicatedStorage/Remotes/Admin/
--------------------------------------------------------------------------------
local function ensureFolder(parent, name)
    local f = parent:FindFirstChild(name)
    if not f then
        f = Instance.new("Folder")
        f.Name = name
        f.Parent = parent
    end
    return f
end

local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
local adminFolder   = ensureFolder(remotesFolder, "Admin")

local function ensureRF(name, parent)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then return existing end
    if existing then existing:Destroy() end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = parent
    return rf
end

local getSavedRF   = ensureRF("AdminGetSavedPlayers",    adminFolder)
local searchSavedRF = ensureRF("AdminSearchSavedPlayers", adminFolder)
local getUserRF    = ensureRF("AdminGetUserData",        adminFolder)
local resetUserRF  = ensureRF("AdminResetUserData",      adminFolder)

-- Reset-history / restore remotes (User Data (R) tab).
local getHistoryRF    = ensureRF("AdminGetResetHistory",      adminFolder)
local searchHistoryRF = ensureRF("AdminSearchResetHistory",   adminFolder)
local getBackupRF     = ensureRF("AdminGetResetBackup",       adminFolder)
local restoreRF       = ensureRF("AdminRestoreUserDataBackup", adminFolder)

--------------------------------------------------------------------------------
-- Rate limiting (per-remote, per-player)
--------------------------------------------------------------------------------
local DEBOUNCE = {
    list    = 0.5,
    search  = 1.0,
    get     = 0.5,
    reset   = 2.0,
    history = 0.5,
    backup  = 0.5,
    restore = 2.0,
}
local lastCall = {} -- [remoteKey][player] = tick()

local function checkLimit(remoteKey, player)
    lastCall[remoteKey] = lastCall[remoteKey] or {}
    local t = tick()
    local last = lastCall[remoteKey][player]
    if last and (t - last) < DEBOUNCE[remoteKey] then return false end
    lastCall[remoteKey][player] = t
    return true
end

--------------------------------------------------------------------------------
-- Auth helper
--------------------------------------------------------------------------------
local function isAdmin(player)
    return player and DevUserIds.IsDev(player)
end

--------------------------------------------------------------------------------
-- Handlers
--------------------------------------------------------------------------------
getSavedRF.OnServerInvoke = function(player, page, pageSize)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("list", player) then return { success = false, error = "Too many requests" } end

    page     = tonumber(page)     or 1
    pageSize = tonumber(pageSize) or AdminUserDataConfig.PageSize
    page     = math.clamp(math.floor(page), 1, 10000)
    pageSize = math.clamp(math.floor(pageSize), 1, 100)

    return PlayerDataAdminService:GetSavedPlayers(player, page, pageSize)
end

searchSavedRF.OnServerInvoke = function(player, query)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("search", player) then return { success = false, error = "Too many requests" } end

    if type(query) ~= "string" then return { success = false, error = "Invalid query" } end
    if #query > 50 then return { success = false, error = "Query too long" } end

    return PlayerDataAdminService:SearchSavedPlayers(player, query)
end

getUserRF.OnServerInvoke = function(player, userId)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("get", player) then return { success = false, error = "Too many requests" } end

    userId = tonumber(userId)
    if not userId or userId <= 0 then return { success = false, error = "Invalid UserId" } end

    return PlayerDataAdminService:GetUserData(player, userId)
end

resetUserRF.OnServerInvoke = function(player, userId, resetType)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("reset", player) then return { success = false, error = "Too many requests" } end

    userId = tonumber(userId)
    if not userId or userId <= 0 then return { success = false, error = "Invalid UserId" } end

    if type(resetType) ~= "string" or not AdminUserDataConfig.ResetTypes[resetType] then
        return { success = false, error = "Invalid reset type" }
    end

    return PlayerDataAdminService:ResetUserData(player, userId, resetType)
end

--------------------------------------------------------------------------------
-- RESTORE-HISTORY HANDLERS
--------------------------------------------------------------------------------
getHistoryRF.OnServerInvoke = function(player, page, pageSize)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("history", player) then return { success = false, error = "Too many requests" } end

    page     = tonumber(page)     or 1
    pageSize = tonumber(pageSize) or 25
    page     = math.clamp(math.floor(page), 1, 10000)
    pageSize = math.clamp(math.floor(pageSize), 1, 100)

    return PlayerDataAdminService:GetResetHistory(player, page, pageSize)
end

searchHistoryRF.OnServerInvoke = function(player, query)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("search", player) then return { success = false, error = "Too many requests" } end

    if type(query) ~= "string" then return { success = false, error = "Invalid query" } end
    if #query > 50 then return { success = false, error = "Query too long" } end

    return PlayerDataAdminService:SearchResetHistory(player, query)
end

getBackupRF.OnServerInvoke = function(player, backupId)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("backup", player) then return { success = false, error = "Too many requests" } end

    if type(backupId) ~= "string" or #backupId == 0 or #backupId > 80 then
        return { success = false, error = "Invalid backupId" }
    end

    return PlayerDataAdminService:GetResetBackup(player, backupId)
end

restoreRF.OnServerInvoke = function(player, backupId)
    if not isAdmin(player) then return { success = false, error = "Unauthorized" } end
    if not checkLimit("restore", player) then return { success = false, error = "Too many requests" } end

    if type(backupId) ~= "string" or #backupId == 0 or #backupId > 80 then
        return { success = false, error = "Invalid backupId" }
    end

    return PlayerDataAdminService:RestoreUserDataBackup(player, backupId)
end

--------------------------------------------------------------------------------
-- Player index recording
--------------------------------------------------------------------------------
local function recordSafely(player)
    task.spawn(function()
        local ok, err = pcall(function()
            SavedPlayersIndexService:RecordPlayer(player)
        end)
        if not ok then
            warn("[PlayerDataAdminInit] RecordPlayer failed for " .. player.Name .. ": " .. tostring(err))
        end
    end)
end

Players.PlayerAdded:Connect(recordSafely)
Players.PlayerRemoving:Connect(function(player)
    -- Refresh lastSeen on leave so the index reflects most-recent activity.
    recordSafely(player)
    for _, tbl in pairs(lastCall) do tbl[player] = nil end
end)
-- Catch players that joined before this script ran.
for _, p in ipairs(Players:GetPlayers()) do
    recordSafely(p)
end

print("[PlayerDataAdminInit] Admin User Data remotes ready under ReplicatedStorage/Remotes/Admin/")
