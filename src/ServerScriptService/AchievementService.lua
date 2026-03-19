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
local ACHIEVEMENT_DATA_VERSION = 2 -- Bump to force a one-time global reset of old achievement saves.
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local AchievementService = {}

--------------------------------------------------------------------------------
-- Per-player state:
--   playerData[player] = {
--       achievementDataVersion = 2,
--       stats = { totalElims = 0, zombieElims = 0, ... },
--       achievements = {
--           [achievementId] = { completed = false, claimed = false, achievedOn = nil },
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
    "totalCoinsEarned", "flagCaptures", "flagReturns", "matchesPlayed",
}

local function sanitizeAchievedOn(value)
    local num = tonumber(value)
    if not num then
        return nil
    end
    if num <= 0 then
        return nil
    end
    return math.floor(num)
end

local function defaultData()
    local data = {
        achievementDataVersion = ACHIEVEMENT_DATA_VERSION,
        stats = {},
        achievements = {},
    }
    for _, key in ipairs(STAT_KEYS) do
        data.stats[key] = 0
    end
    for _, def in ipairs(AchievementDefs.Achievements) do
        data.achievements[def.id] = { completed = false, claimed = false, achievedOn = nil }
    end
    return data
end

--- Merge saved data with current definitions so new achievements get defaults.
local function mergeWithDefaults(saved)
    if type(saved) ~= "table" then
        return defaultData(), false
    end

    local savedVersion = tonumber(saved.achievementDataVersion or saved.dataVersion or 1) or 1
    if savedVersion < ACHIEVEMENT_DATA_VERSION then
        -- Discard all previous completion/progress/claim metadata for a clean reset.
        return defaultData(), true
    end

    local data = {
        achievementDataVersion = ACHIEVEMENT_DATA_VERSION,
        stats = {},
        achievements = {},
    }
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
            local completed = (prev.completed == true)
            data.achievements[def.id] = {
                completed = completed,
                claimed   = completed and (prev.claimed == true) or false,
                achievedOn = completed and sanitizeAchievedOn(prev.achievedOn) or nil,
            }
        else
            data.achievements[def.id] = { completed = false, claimed = false, achievedOn = nil }
        end
    end
    return data, false
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

local function pushProgress(player, achievementId, progress, completed, achievedOn, claimed)
    local ev = getRemote("AchievementProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, achievementId, progress, completed, achievedOn, claimed)
        end)
    end
end

local function pushAllAchievements(player)
    local ev = getRemote("AchievementProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, "__full_refresh", 0, false, nil, false)
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

    local data, wasResetByVersion = mergeWithDefaults(success and result or nil)

    -- Retroactively mark completed for stats that already exceeded target
    for _, def in ipairs(AchievementDefs.Achievements) do
        local st = data.stats[def.stat] or 0
        local ach = data.achievements[def.id]
        if st >= def.target and not ach.completed then
            ach.completed = true
            -- Stamp first completion time once; keep existing values stable.
            if ach.achievedOn == nil then
                ach.achievedOn = os.time()
            end
        elseif st < def.target then
            ach.completed = false
            ach.claimed = false
            ach.achievedOn = nil
        end
    end

    playerData[player] = data

    if wasResetByVersion then
        task.spawn(function()
            AchievementService:SaveForPlayer(player)
        end)
    end
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
                    -- Set achievedOn exactly once at first completion.
                    if ach.achievedOn == nil then
                        ach.achievedOn = os.time()
                    end
                    pushProgress(player, def.id, currentValue, true, ach.achievedOn, ach.claimed == true)
                else
                    pushProgress(player, def.id, currentValue, false, nil, ach.claimed == true)
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
        local ach = data.achievements[def.id] or { completed = false, claimed = false, achievedOn = nil }
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
            achievedOn = ach.achievedOn,
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
    pushProgress(player, achievementId, def.target, true, ach.achievedOn, true)

    return true
end

return AchievementService
