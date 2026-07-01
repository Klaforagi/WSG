--------------------------------------------------------------------------------
-- DailyRewardService.lua  –  Simplified version for your fixed rewards
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "DailyRewards_v1"
local ds = game:GetService("DataStoreService"):GetDataStore(DATASTORE_NAME)

local DailyRewardService = {}

local playerData = {}
local sessionFlags = {}
local claimLocks = {}

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

-- Your fixed 7-day rewards
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

local function getTodayKey()
    return os.date("!%Y-%m-%d", os.time())
end

function DailyRewardService:LoadProfileForPlayer(player)
    if not player then return { status = "failed", data = makeEmptyState() } end

    local key = getKey(player)
    local success, result = pcall(function()
        return ds:GetAsync(key)
    end)

    if success and result then
        playerData[player] = normalizeState(result)
    else
        playerData[player] = makeEmptyState()
    end

    sessionFlags[player] = { autoPopupShown = false }
    return { status = success and "existing" or "new", data = playerData[player] }
end

function DailyRewardService:GetState(player)
    local pd = ensurePlayerData(player)
    local today = getTodayKey()
    local alreadyClaimed = (pd.lastClaimDate == today)

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
        currentStreak  = pd.currentStreak,
        currentDay     = pd.currentDay,
        canClaimToday  = not alreadyClaimed and pd.currentDay < 7,
        alreadyClaimed = alreadyClaimed,
        cycleDays      = 7,
        rewards        = rewards,
    }
end

function DailyRewardService:ClaimReward(player)
    if claimLocks[player] then return false, "Claim in progress" end
    claimLocks[player] = true

    local pd = ensurePlayerData(player)
    local today = getTodayKey()

    if pd.lastClaimDate == today then
        claimLocks[player] = nil
        return false, "Already claimed today"
    end

    local nextDay = pd.currentDay + 1
    if nextDay > 7 then nextDay = 1 end

    local reward = REWARDS[nextDay]
    if not reward then
        claimLocks[player] = nil
        return false, "No reward configured"
    end

    -- TODO: Replace these with your actual systems
    if reward.type == "Coins" then
        -- Example: CurrencyService:AddCoins(player, reward.amount, "daily_reward")
        print("[DailyReward] Gave", reward.amount, "Coins to", player.Name)

    elseif reward.type == "Shards" then
        -- Example: YourShardSystem:AddShards(player, reward.amount)
        print("[DailyReward] Gave", reward.amount, "Shards to", player.Name)

    elseif reward.type == "Key" then
        -- Example: InventoryService:GiveItem(player, "GoldenKey", 1)
        print("[DailyReward] Gave 1 Golden Key to", player.Name)
    end

    -- Update state
    pd.currentStreak = pd.currentStreak + 1
    pd.currentDay = nextDay
    pd.lastClaimDate = today
    pd.lastClaimTime = os.time()
    pd.totalClaims = pd.totalClaims + 1

    claimLocks[player] = nil
    return true, "Claimed " .. reward.displayName
end

function DailyRewardService:ClearPlayer(player)
    playerData[player] = nil
    sessionFlags[player] = nil
    claimLocks[player] = nil
end

return DailyRewardService