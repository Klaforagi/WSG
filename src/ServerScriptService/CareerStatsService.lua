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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))

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
    GoblinsEliminated      = 0,
    OrcsEliminated         = 0,
    OgresEliminated        = 0,
    Deaths                 = 0,
    TotalDamageDone        = 0,
    FlagCaptures           = 0,
    FlagReturns            = 0,
    HighestEliminationStreak = 0,
    TotalCoinsEarned       = 0,
    TotalXP                = 0,
    TotalPlaytimeSeconds   = 0,
    AchievementsCompleted  = 0,
    QuestsCompleted        = 0,
    MVPs                   = 0,
}

--- List of all stat keys for safe iteration
local STAT_KEYS = {}
for k in pairs(STAT_DEFAULTS) do
    table.insert(STAT_KEYS, k)
end
table.sort(STAT_KEYS)

-- Weekly and monthly buckets intentionally mirror the career keys.  They are
-- reset lazily at the Eastern-time boundaries supplied by TimeHelper, so a
-- player does not need to be online exactly when a new period starts.
local PERIOD_NAMES = { "Weekly", "Monthly" }

local statsChangedEvent = ServerScriptService:FindFirstChild("CareerStatsChanged")
if not statsChangedEvent then
    statsChangedEvent = Instance.new("BindableEvent")
    statsChangedEvent.Name = "CareerStatsChanged"
    statsChangedEvent.Parent = ServerScriptService
end

local function makePeriodStats()
    local stats = {}
    for _, key in ipairs(STAT_KEYS) do
        stats[key] = 0
    end
    return stats
end

local function getPeriodKey(periodName, now)
    if periodName == "Weekly" then
        return TimeHelper.GetWeeklyKey(now)
    end
    return TimeHelper.GetMonthlyKey(now)
end

local function normalizePeriods(savedPeriods)
    local periods = {}
    for _, periodName in ipairs(PERIOD_NAMES) do
        local key = getPeriodKey(periodName)
        local savedPeriod = type(savedPeriods) == "table" and savedPeriods[periodName] or nil
        local savedStats = type(savedPeriod) == "table" and savedPeriod.stats or nil
        local stats = makePeriodStats()
        if type(savedPeriod) == "table" and savedPeriod.key == key and type(savedStats) == "table" then
            for _, statKey in ipairs(STAT_KEYS) do
                stats[statKey] = math.max(0, math.floor(tonumber(savedStats[statKey]) or 0))
            end
        end
        periods[periodName] = { key = key, stats = stats }
    end
    return periods
end

local function getOrResetPeriod(data, periodName)
    data.periods = data.periods or {}
    local expectedKey = getPeriodKey(periodName)
    local period = data.periods[periodName]
    if type(period) ~= "table" or period.key ~= expectedKey or type(period.stats) ~= "table" then
        period = { key = expectedKey, stats = makePeriodStats() }
        data.periods[periodName] = period
    end
    return period
end

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
        coordinator:MarkDirty(player, "CareerStats", reason or "career_stats", {
            delaySeconds = 30,
        })
    end
end

--- Merge saved data with current defaults so new stat keys get 0.
local function mergeWithDefaults(saved)
    local stats = {}
    local src = (type(saved) == "table" and type(saved.stats) == "table") and saved.stats or {}
    for _, key in ipairs(STAT_KEYS) do
        stats[key] = (type(src[key]) == "number") and src[key] or STAT_DEFAULTS[key]
    end
    return {
        stats = stats,
        periods = normalizePeriods(type(saved) == "table" and saved.periods or nil),
    }
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
    local payload = { stats = data.stats, periods = data.periods }
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

--- Read a snapshot for a resettable leaderboard period ("Weekly" or "Monthly").
function CareerStatsService:GetPeriodStats(player, periodName)
    local data = playerData[player]
    if not data or (periodName ~= "Weekly" and periodName ~= "Monthly") then
        return nil
    end
    local period = getOrResetPeriod(data, periodName)
    local copy = {}
    for key, value in pairs(period.stats) do
        copy[key] = value
    end
    return copy, period.key
end

function CareerStatsService:NotifyStatChanged(player, statKey)
    if player and player:IsA("Player") then
        statsChangedEvent:Fire(player, statKey)
    end
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
    for _, periodName in ipairs(PERIOD_NAMES) do
        local period = getOrResetPeriod(data, periodName)
        period.stats[statKey] = (period.stats[statKey] or 0) + amount
    end
    markDirty(player, statKey)
    self:NotifyStatChanged(player, statKey)
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
        self:NotifyStatChanged(player, statKey)
    end
end

--- Add playtime seconds.
function CareerStatsService:AddPlaytime(player, seconds)
    self:IncrementStat(player, "TotalPlaytimeSeconds", math.floor(seconds))
end

return CareerStatsService
