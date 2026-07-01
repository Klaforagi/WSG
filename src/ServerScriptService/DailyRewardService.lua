--------------------------------------------------------------------------------
-- DailyRewardService.lua  –  Simplified version for your fixed rewards
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

local CurrencyService = nil
pcall(function()
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

local DATASTORE_NAME = "DailyRewards_v1"
local ds = game:GetService("DataStoreService"):GetDataStore(DATASTORE_NAME)

local DailyRewardService = {}

local playerData = {}
local sessionFlags = {}
local claimLocks = {}

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

-- Fixed 7-day rewards
local REWARDS = {
    [1] = { type = "Coins",  amount = 100, displayName = "100 Coins" },
    [2] = { type = "Shards", amount = 50,  displayName = "50 Shards" },
    [3] = { type = "Coins",  amount = 200, displayName = "200 Coins" },
    [4] = { type = "Shards", amount = 100, displayName = "100 Shards" },
    [5] = { type = "Coins",  amount = 300, displayName = "300 Coins" },
    [6] = { type = "Shards", amount = 150, displayName = "150 Shards" },
    [7] = { type = "Key",    amount = 1,   displayName = "1 Golden Key" },
}

local function makeEmptyState()
    return {
        currentStreak = 0,
        currentDay    = 0,
        lastClaimDate = "",
        lastClaimTime = 0,
        totalClaims   = 0,
    }
end

local function normalizeState(raw)
    local state = makeEmptyState()
    if type(raw) ~= "table" then return state end
    state.currentStreak = math.max(0, math.floor(tonumber(raw.currentStreak) or 0))
    state.currentDay    = math.max(0, math.floor(tonumber(raw.currentDay) or 0))
    state.lastClaimDate = type(raw.lastClaimDate) == "string" and raw.lastClaimDate or ""
    state.lastClaimTime = math.max(0, math.floor(tonumber(raw.lastClaimTime) or 0))
    state.totalClaims   = math.max(0, math.floor(tonumber(raw.totalClaims) or 0))
    return state
end

local function ensurePlayerData(player)
    if not playerData[player] then
        playerData[player] = makeEmptyState()
    end
    return playerData[player]
end

local function getDateKeyFromTime(t)
    return os.date("!%Y-%m-%d", t or os.time())
end

local function daysBetween(t1, t2)
    if not t1 or t1 <= 0 then return math.huge end
    t2 = t2 or os.time()
    local d1 = os.date("!*t", t1)
    local d2 = os.date("!*t", t2)
    -- normalize to UTC midnight
    local s1 = os.time({year=d1.year, month=d1.month, day=d1.day, hour=0})
    local s2 = os.time({year=d2.year, month=d2.month, day=d2.day, hour=0})
    return math.floor((s2 - s1) / 86400 + 0.5)
end

local function markDirty(player, reason)
    pcall(function()
        DataSaveCoordinator:MarkDirty(player, "DailyReward", reason or "daily_reward")
    end)
end

function DailyRewardService:LoadProfileForPlayer(player)
    if not player then return { status = "failed", data = makeEmptyState() } end

    local key = getKey(player)
    local ok, result, err = DataStoreOps.Load(ds, key, "DailyReward/" .. key)
    if ok and result then
        playerData[player] = normalizeState(result)
    else
        playerData[player] = makeEmptyState()
    end

    sessionFlags[player] = { autoPopupShown = false }
    if not ok then
        return { status = "failed", data = playerData[player], reason = tostring(err) }
    end
    if result == nil then
        return { status = "new", data = playerData[player] }
    end
    return { status = "existing", data = playerData[player] }
end

function DailyRewardService:GetSaveData(player)
    local pd = playerData[player]
    if not pd then return nil end
    return {
        currentStreak = pd.currentStreak,
        currentDay = pd.currentDay,
        lastClaimDate = pd.lastClaimDate,
        lastClaimTime = pd.lastClaimTime,
        totalClaims = pd.totalClaims,
    }
end

function DailyRewardService:SaveProfileForPlayer(player, payload, oldData)
    if not player then return false, "missing player" end
    local pd = playerData[player]
    if not pd and not payload then return false, "missing state" end

    payload = payload or self:GetSaveData(player)
    local key = getKey(player)
    local success, _, err = DataStoreOps.Update(ds, key, "DailyReward/" .. key, function(stored)
        stored = stored or {}
        local previous = type(oldData) == "table" and oldData or stored or {}
        -- basic wipe detection: if previous.totalClaims > 0 and new totalClaims == 0 then block
        if (tonumber(previous.totalClaims) or 0) > 0 and (tonumber(payload.totalClaims) or 0) == 0 then
            warn("[DailyRewardService] suspected wipe blocked for", player.Name)
            return stored
        end
        return payload
    end)

    if not success then
        warn("[DailyRewardService] Failed to save daily reward data for", player.Name, "err=", tostring(err))
    end
    return success, err
end

function DailyRewardService:ClearPlayer(player)
    playerData[player] = nil
    sessionFlags[player] = nil
    claimLocks[player] = nil
end

function DailyRewardService:MarkAutoPopupShown(player)
    if not player then return end
    sessionFlags[player] = sessionFlags[player] or {}
    sessionFlags[player].autoPopupShown = true
end

function DailyRewardService:GetState(player)
    local pd = ensurePlayerData(player)
    local now = os.time()
    local days = daysBetween(pd.lastClaimTime, now)
    local alreadyClaimed = (days == 0)

    local rewards = {}
    for i = 1, 7 do
        local r = REWARDS[i]
        local status = "future"
        if alreadyClaimed then
            if i <= pd.currentDay then
                status = "claimed"
            end
        else
            if i == pd.currentDay + 1 then
                status = "claimable"
            elseif i <= pd.currentDay then
                status = "claimed"
            end
        end
        table.insert(rewards, {
            day = i,
            displayName = r.displayName,
            amount = r.amount,
            status = status,
        })
    end

    return {
        currentStreak = pd.currentStreak,
        currentDay = pd.currentDay,
        canClaimToday = (not alreadyClaimed),
        alreadyClaimed = alreadyClaimed,
        cycleDays = 7,
        rewards = rewards,
        autoPopup = not (sessionFlags[player] and sessionFlags[player].autoPopupShown),
    }
end

function DailyRewardService:ClaimReward(player)
    if not player then return false, "invalid player" end
    if claimLocks[player] then return false, "Claim in progress" end
    claimLocks[player] = true

    local pd = ensurePlayerData(player)
    local now = os.time()
    local days = daysBetween(pd.lastClaimTime, now)

    if days == 0 then
        claimLocks[player] = nil
        return false, "Already claimed today"
    end

    local nextDay
    if days == 1 then
        -- consecutive day
        nextDay = pd.currentDay + 1
        if nextDay > 7 then nextDay = 1 end
        pd.currentStreak = pd.currentStreak + 1
    else
        -- missed at least one day: reset streak and day
        nextDay = 1
        pd.currentStreak = 1
    end

    local reward = REWARDS[nextDay]
    if not reward then
        claimLocks[player] = nil
        return false, "No reward configured"
    end

    -- Grant reward using CurrencyService where available
    if reward.type == "Coins" then
        if CurrencyService and CurrencyService.AddCoins then
            pcall(function() CurrencyService:AddCoins(player, reward.amount) end)
        else
            print("[DailyReward] (Stub) Gave", reward.amount, "Coins to", player.Name)
        end
    elseif reward.type == "Shards" then
        if CurrencyService and CurrencyService.AddSalvage then
            pcall(function() CurrencyService:AddSalvage(player, reward.amount) end)
        else
            print("[DailyReward] (Stub) Gave", reward.amount, "Shards to", player.Name)
        end
    elseif reward.type == "Key" then
        if CurrencyService and CurrencyService.AddKeys then
            pcall(function() CurrencyService:AddKeys(player, reward.amount) end)
        else
            print("[DailyReward] (Stub) Gave", reward.amount, "Key(s) to", player.Name)
        end
    end

    -- Update state
    pd.currentDay = nextDay
    pd.lastClaimDate = getDateKeyFromTime(now)
    pd.lastClaimTime = now
    pd.totalClaims = pd.totalClaims + 1

    -- Mark dirty to have DataSaveCoordinator save this section
    markDirty(player, "claim")

    claimLocks[player] = nil
    return true, "Claimed " .. (reward.displayName or "reward")
end

return DailyRewardService