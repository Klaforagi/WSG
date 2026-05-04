--------------------------------------------------------------------------------
-- CareerStatsService.lua  –  Persistent career stat tracking & persistence
-- ModuleScript in ServerScriptService.
--
-- Stores lifetime player stats in DataStore "CareerStats_v1".
-- Integrated with StatService event pipeline for automatic tracking.
--
-- Public API:
--   CareerStatsService:LoadForPlayer(player)
--   CareerStatsService:SaveForPlayer(player)
--   CareerStatsService:SaveAll()
--   CareerStatsService:ClearPlayer(player)
--   CareerStatsService:IncrementStat(player, statKey, amount)
--   CareerStatsService:SetStatMax(player, statKey, value)
--   CareerStatsService:GetCareerStats(player) -> table or nil
--   CareerStatsService:AddPlaytime(player, seconds)
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "CareerStats_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local CareerStatsService = {}
local _saveCoordinator

--------------------------------------------------------------------------------
-- Default career stats template
--------------------------------------------------------------------------------
local STAT_DEFAULTS = {
    MatchesPlayed          = 0,
    Wins                   = 0,
    Losses                 = 0,
    PlayersEliminated      = 0,
    MonstersEliminated     = 0,
    Deaths                 = 0,
    FlagCaptures           = 0,
    FlagReturns            = 0,
    HighestEliminationStreak = 0,
    TotalCoinsEarned       = 0,
    TotalXP                = 0,
    TotalPlaytimeSeconds   = 0,
    AchievementsCompleted  = 0,
    QuestsCompleted        = 0,
}

--- List of all stat keys for safe iteration
local STAT_KEYS = {}
for k in pairs(STAT_DEFAULTS) do
    table.insert(STAT_KEYS, k)
end
table.sort(STAT_KEYS)

--------------------------------------------------------------------------------
-- Per-player in-memory state
--------------------------------------------------------------------------------
local playerData = {}  -- [Player] -> { stats = { ... } }

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

local function getSaveCoordinator()
    if _saveCoordinator == nil then
        local ok, coordinator = pcall(function()
            return require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
        end)
        if ok then
            _saveCoordinator = coordinator
        else
            _saveCoordinator = false
        end
    end
    if _saveCoordinator == false then
        return nil
    end
    return _saveCoordinator
end

local function markDirty(player, reason)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "CareerStats", reason or "career_stats")
    end
end

--- Merge saved data with current defaults so new stat keys get 0.
local function mergeWithDefaults(saved)
    local stats = {}
    local src = (type(saved) == "table" and type(saved.stats) == "table") and saved.stats or {}
    for _, key in ipairs(STAT_KEYS) do
        stats[key] = (type(src[key]) == "number") and src[key] or STAT_DEFAULTS[key]
    end
    return { stats = stats }
end

--------------------------------------------------------------------------------
-- DataStore I/O
--------------------------------------------------------------------------------

function CareerStatsService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = mergeWithDefaults(nil),
            reason = "missing player",
        }
    end
    local key = getKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "CareerStats/" .. key)

    local data = mergeWithDefaults(success and result or nil)
    playerData[player] = data
    print("[CareerStatsService] Loaded career stats for", player.Name)
    if not success then
        return {
            status = "failed",
            data = DataStoreOps.DeepCopy(data),
            reason = err,
        }
    end
    if result == nil then
        return {
            status = "new",
            data = DataStoreOps.DeepCopy(data),
        }
    end
    return {
        status = "existing",
        data = DataStoreOps.DeepCopy(data),
    }
end

function CareerStatsService:LoadForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    return result and result.data or nil
end

function CareerStatsService:GetSaveData(player)
    if not player then return nil end
    return DataStoreOps.DeepCopy(playerData[player])
end

function CareerStatsService:SaveProfileForPlayer(player, currentData, oldData)
    if not player then return false, "missing player" end
    local data = currentData or playerData[player]
    if not data then return false, "missing data" end
    local key = getKey(player)
    local payload = { stats = data.stats }
    local success, _, err = DataStoreOps.Update(ds, key, "CareerStats/" .. key, function(storedPayload)
        local previous = type(oldData) == "table" and oldData or storedPayload or { stats = {} }
        local previousStats = type(previous.stats) == "table" and previous.stats or {}
        local newStats = type(payload.stats) == "table" and payload.stats or {}
        local previousTotal = 0
        local newTotal = 0
        for _, statKey in ipairs(STAT_KEYS) do
            previousTotal += math.max(0, math.floor(tonumber(previousStats[statKey]) or 0))
            newTotal += math.max(0, math.floor(tonumber(newStats[statKey]) or 0))
        end
        if previousTotal > 0 and newTotal == 0 then
            warn("[CareerStatsService] suspected wipe blocked for", player.Name)
            return storedPayload
        end
        return payload
    end)
    if success then
        return true
    end
    warn("[CareerStatsService] Failed to save career stats for", player.Name)
    return false, err
end

function CareerStatsService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

function CareerStatsService:SaveAll()
    for player, _ in pairs(playerData) do
        pcall(function() self:SaveForPlayer(player) end)
    end
end

function CareerStatsService:ClearPlayer(player)
    playerData[player] = nil
end

--------------------------------------------------------------------------------
-- Stat accessors
--------------------------------------------------------------------------------

--- Read-only snapshot of all career stats for a player.
function CareerStatsService:GetCareerStats(player)
    local data = playerData[player]
    if not data then return nil end
    -- Return a shallow copy to prevent mutation
    local copy = {}
    for k, v in pairs(data.stats) do
        copy[k] = v
    end
    return copy
end

--- Increment a numeric career stat by amount (default 1).
function CareerStatsService:IncrementStat(player, statKey, amount)
    amount = amount or 1
    local data = playerData[player]
    if not data then return end
    if data.stats[statKey] == nil then
        data.stats[statKey] = 0
    end
    data.stats[statKey] = data.stats[statKey] + amount
    markDirty(player, statKey)
end

--- Set a stat only if the new value is higher (for "highest" records).
function CareerStatsService:SetStatMax(player, statKey, value)
    local data = playerData[player]
    if not data then return end
    if data.stats[statKey] == nil then
        data.stats[statKey] = 0
    end
    if value > data.stats[statKey] then
        data.stats[statKey] = value
        markDirty(player, statKey)
    end
end

--- Add playtime seconds.
function CareerStatsService:AddPlaytime(player, seconds)
    self:IncrementStat(player, "TotalPlaytimeSeconds", math.floor(seconds))
end

return CareerStatsService
