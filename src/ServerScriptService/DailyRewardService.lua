--------------------------------------------------------------------------------
-- DailyRewardService.lua  –  Simplified version for your fixed rewards
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))

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
local profilesLoaded = {}

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
    if state.lastClaimTime <= 0 or state.totalClaims <= 0 or state.lastClaimDate == "" then
        state.currentStreak = 0
        state.currentDay = 0
        state.lastClaimTime = 0
        state.lastClaimDate = ""
        state.totalClaims = 0
    end
    return state
end

local function ensurePlayerData(player)
    if not playerData[player] then
        playerData[player] = makeEmptyState()
    end
    return playerData[player]
end

local function getDateKeyFromTime(t)
    return TimeHelper.GetDailyKey(t)
end

local function daysBetween(t1, t2)
    if not t1 or t1 <= 0 then return math.huge end
    t2 = t2 or os.time()
    local et1 = TimeHelper.UtcToEasternEpoch(t1)
    local et2 = TimeHelper.UtcToEasternEpoch(t2)
    local d1 = os.date("!*t", et1)
    local d2 = os.date("!*t", et2)
    local midnight1 = et1 - ((d1.hour * 3600) + (d1.min * 60) + d1.sec)
    local midnight2 = et2 - ((d2.hour * 3600) + (d2.min * 60) + d2.sec)
    return math.floor((midnight2 - midnight1) / 86400 + 0.5)
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
    profilesLoaded[player] = true
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
    profilesLoaded[player] = nil
end

function DailyRewardService:MarkAutoPopupShown(player)
    if not player then return end
    sessionFlags[player] = sessionFlags[player] or {}
    sessionFlags[player].autoPopupShown = true
end

local function buildRewardStatuses(lastClaimedDay, claimedToday)
    local rewards = {}
    for i = 1, 7 do
        local r = REWARDS[i]
        local status = "future"
        if lastClaimedDay <= 0 then
            if i == 1 then
                status = "claimable"
            end
        elseif claimedToday then
            if i <= lastClaimedDay then
                status = "claimed"
            end
        else
            if i <= lastClaimedDay then
                status = "claimed"
            elseif i == lastClaimedDay + 1 then
                status = "claimable"
            end
        end
        table.insert(rewards, {
            day = i,
            displayName = r.displayName,
            amount = r.amount,
            rewardType = r.type,
            status = status,
        })
    end
    return rewards
end

function DailyRewardService:GetState(player)
    local pd
    if profilesLoaded[player] then
        pd = ensurePlayerData(player)
    else
        pd = makeEmptyState()
    end

    local lastClaimTime = tonumber(pd.lastClaimTime) or 0
    local lastClaimedDay = 0
    local claimedToday = false
    local currentStreak = math.max(0, tonumber(pd.currentStreak) or 0)
    if lastClaimTime > 0 then
        lastClaimedDay = math.max(0, math.floor(tonumber(pd.currentDay) or 0))
        claimedToday = getDateKeyFromTime(lastClaimTime) == getDateKeyFromTime()
    end
    -- Project the same reset that ClaimReward will apply, before the player claims.
    if daysBetween(lastClaimTime, os.time()) > 1 or currentStreak == 0 then
        lastClaimedDay = 0
        currentStreak = 0
    elseif not claimedToday and lastClaimedDay >= 7 then
        -- A new reward cycle starts at day 1 without losing the consecutive streak.
        lastClaimedDay = 0
    end
    if lastClaimedDay <= 0 then
        lastClaimTime = 0
        lastClaimedDay = 0
        claimedToday = false
    end

    return {
        currentStreak = currentStreak,
        currentDay = lastClaimedDay,
        lastClaimTime = lastClaimTime,
        totalClaims = pd.totalClaims or 0,
        canClaimToday = not claimedToday,
        alreadyClaimed = claimedToday,
        cycleDays = 7,
        rewards = buildRewardStatuses(lastClaimedDay, claimedToday),
        autoPopup = not (sessionFlags[player] and sessionFlags[player].autoPopupShown),
    }
end

function DailyRewardService:ClaimReward(player)
    if not player then return false, "invalid player" end
    if profilesLoaded[player] ~= true then
        return false, "Loading"
    end
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
