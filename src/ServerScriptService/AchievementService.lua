--------------------------------------------------------------------------------
-- AchievementService.lua  –  Server-side achievement tracking & persistence
-- ModuleScript in ServerScriptService.
--
-- Responsibilities:
--   • Load / save per-player achievement data (DataStore "Achievements_v1")
--   • Track lifetime stat counters
--   • Mark achievements complete when targets are hit
--   • Let players claim coin rewards (once per achievement)
--   • Push live progress to clients via RemoteEvent
--
-- Public API (called by AchievementServiceInit.server.lua):
--   AchievementService:LoadForPlayer(player)
--   AchievementService:SaveForPlayer(player)
--   AchievementService:SaveAll()
--   AchievementService:ClearPlayer(player)
--   AchievementService:IncrementStat(player, statKey, amount)
--   AchievementService:GetAchievementsForPlayer(player)
--   AchievementService:ClaimReward(player, achievementId) -> bool
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AchievementDefs = require(ReplicatedStorage:WaitForChild("AchievementDefs", 10))

local DATASTORE_NAME = "Achievements_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local AchievementService = {}

--------------------------------------------------------------------------------
-- Per-player state:
--   playerData[player] = {
--       stats = { totalElims = 0, zombieElims = 0, ... },
--       achievements = {
--           [achievementId] = { completed = false, claimed = false },
--       },
--   }
--------------------------------------------------------------------------------
local playerData = {}

--------------------------------------------------------------------------------
-- CurrencyService  (lazy-loaded so require order doesn't matter)
--------------------------------------------------------------------------------
local CurrencyService
local function getCurrencyService()
    if CurrencyService then return CurrencyService end
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("CurrencyService")
        if mod and mod:IsA("ModuleScript") then
            CurrencyService = require(mod)
        end
    end)
    return CurrencyService
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local STAT_KEYS = {
    "totalElims", "zombieElims", "playerElims",
    "totalCoinsEarned", "flagActions", "matchesPlayed",
}

local function defaultData()
    local data = { stats = {}, achievements = {} }
    for _, key in ipairs(STAT_KEYS) do
        data.stats[key] = 0
    end
    for _, def in ipairs(AchievementDefs.Achievements) do
        data.achievements[def.id] = { completed = false, claimed = false }
    end
    return data
end

--- Merge saved data with current definitions so new achievements get defaults.
local function mergeWithDefaults(saved)
    if type(saved) ~= "table" then return defaultData() end
    local data = { stats = {}, achievements = {} }
    -- Stats
    local ss = (type(saved.stats) == "table") and saved.stats or {}
    for _, key in ipairs(STAT_KEYS) do
        data.stats[key] = (type(ss[key]) == "number") and ss[key] or 0
    end
    -- Achievements
    local sa = (type(saved.achievements) == "table") and saved.achievements or {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        local prev = sa[def.id]
        if type(prev) == "table" then
            data.achievements[def.id] = {
                completed = (prev.completed == true),
                claimed   = (prev.claimed == true),
            }
        else
            data.achievements[def.id] = { completed = false, claimed = false }
        end
    end
    return data
end

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- Remote helpers (created by AchievementServiceInit, resolved lazily)
--------------------------------------------------------------------------------
local remotesFolder

local function getRemote(name)
    if not remotesFolder then
        remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    end
    return remotesFolder and remotesFolder:FindFirstChild(name)
end

local function pushProgress(player, achievementId, progress, completed)
    local ev = getRemote("AchievementProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, achievementId, progress, completed)
        end)
    end
end

local function pushAllAchievements(player)
    local ev = getRemote("AchievementProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, "__full_refresh", 0, false)
        end)
    end
end

--------------------------------------------------------------------------------
-- DataStore I/O
--------------------------------------------------------------------------------

function AchievementService:LoadForPlayer(player)
    if not player then return end
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[AchievementService] GetAsync attempt", i, "failed:", tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    local data = mergeWithDefaults(success and result or nil)

    -- Retroactively mark completed for stats that already exceeded target
    for _, def in ipairs(AchievementDefs.Achievements) do
        local st = data.stats[def.stat] or 0
        if st >= def.target and not data.achievements[def.id].completed then
            data.achievements[def.id].completed = true
        end
    end

    playerData[player] = data
end

function AchievementService:SaveForPlayer(player)
    if not player then return false end
    local data = playerData[player]
    if not data then return false end
    local key = getKey(player)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, data)
        end)
        if success then break end
        warn("[AchievementService] SetAsync attempt", i, "failed:", tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("[AchievementService] failed to save for", tostring(player.Name))
    end
    return success == true
end

function AchievementService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(function() AchievementService:SaveForPlayer(player) end)
    end
end

function AchievementService:ClearPlayer(player)
    playerData[player] = nil
end

--------------------------------------------------------------------------------
-- Core tracking
--------------------------------------------------------------------------------

--- Increment a lifetime stat and update any related achievements.
function AchievementService:IncrementStat(player, statKey, amount)
    amount = tonumber(amount) or 1
    if amount <= 0 then return end

    local data = playerData[player]
    if not data then return end

    data.stats[statKey] = (data.stats[statKey] or 0) + amount

    -- Check all achievements that use this stat
    local currentValue = data.stats[statKey]
    for _, def in ipairs(AchievementDefs.Achievements) do
        if def.stat == statKey then
            local ach = data.achievements[def.id]
            if ach and not ach.completed then
                if currentValue >= def.target then
                    ach.completed = true
                    pushProgress(player, def.id, currentValue, true)
                else
                    pushProgress(player, def.id, currentValue, false)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Client-facing API
--------------------------------------------------------------------------------

--- Returns an array of achievement snapshots for the client.
function AchievementService:GetAchievementsForPlayer(player)
    local data = playerData[player]
    if not data then return {} end

    local out = {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        local ach = data.achievements[def.id] or { completed = false, claimed = false }
        local progress = math.min(data.stats[def.stat] or 0, def.target)
        table.insert(out, {
            id        = def.id,
            title     = def.title,
            desc      = def.desc,
            icon      = def.icon,
            target    = def.target,
            reward    = def.reward,
            progress  = progress,
            completed = ach.completed,
            claimed   = ach.claimed,
            hidden    = def.hidden,
        })
    end
    return out
end

--- Claim the reward for a completed achievement.  Returns true on success.
function AchievementService:ClaimReward(player, achievementId)
    if type(achievementId) ~= "string" then return false end
    local data = playerData[player]
    if not data then return false end

    local def = AchievementDefs.ById[achievementId]
    if not def then return false end

    local ach = data.achievements[achievementId]
    if not ach then return false end
    if not ach.completed then return false end
    if ach.claimed then return false end

    -- Double-check stat meets target (server-authoritative)
    if (data.stats[def.stat] or 0) < def.target then return false end

    -- Grant coins
    local cs = getCurrencyService()
    if cs and cs.AddCoins then
        cs:AddCoins(player, def.reward, "achievement")
    end

    ach.claimed = true

    -- Push a progress update so the client refreshes the card
    pushProgress(player, achievementId, def.target, true)

    return true
end

return AchievementService
