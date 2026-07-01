--------------------------------------------------------------------------------
-- DailyRewardService.lua  –  Fixed & Clean Version
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

-- ==================== YOUR FIXED 7-DAY REWARDS ====================
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

local function daysSinceLastClaim(lastClaimDate)
    if lastClaimDate == "" then return 999 end
    local today = getTodayKey()

    local y1, m1, d1 = lastClaimDate:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    local y2, m2, d2 = today:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y1 or not y2 then return 999 end

    local date1 = os.time({year = tonumber(y1), month = tonumber(m1), day = tonumber(d1)})
    local date2 = os.time({year = tonumber(y2), month = tonumber(m2), day = tonumber(d2)})

    return math.floor((date2 - date1) / 86400)
end

--------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
--------------------------------------------------------------------------------

function DailyRewardService:LoadProfileForPlayer(player)
    if not player then return { status = "failed", data = makeEmptyState() } end

    local key = getKey(player)
    local success, result = pcall(function() return ds:GetAsync(key) end)

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
    local alreadyClaimedToday = (pd.lastClaimDate == today)
    local daysSince = daysSinceLastClaim(pd.lastClaimDate)

    local canClaim = false
    local claimDay = 1

    if not alreadyClaimedToday then
        if pd.currentDay == 0 then
            -- First time ever
            canClaim = true
            claimDay = 1
        elseif daysSince == 1 then
            -- Consecutive day
            canClaim = true
            claimDay = pd.currentDay + 1
            if claimDay > 7 then claimDay = 1 end
        elseif daysSince > 1 then
            -- Missed day(s) → reset
            canClaim = true
            claimDay = 1
        end
    end

    -- Build reward list with correct status
    local rewards = {}
    for i = 1, 7 do
        local r = REWARDS[i]
        local status = "future"

        if alreadyClaimedToday then
            if i <= pd.currentDay then
                status = "claimed"
            end
        else
            if canClaim and i == claimDay then
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
        canClaimToday  = canClaim,
        alreadyClaimed = alreadyClaimedToday,
        cycleDays      = 7,
        rewards        = rewards,
    }
end

function DailyRewardService:ClaimReward(player)
    if claimLocks[player] then return false, "Claim in progress" end
    claimLocks[player] = true

    local pd = ensurePlayerData(player)
    local today = getTodayKey()
    local daysSince = daysSinceLastClaim(pd.lastClaimDate)

    if pd.lastClaimDate == today then
        claimLocks[player] = nil
        return false, "Already claimed today"
    end

    local claimDay = 1

    if pd.currentDay == 0 or daysSince > 1 then
        -- First claim or reset
        claimDay = 1
        pd.currentStreak = 1
    else
        -- Normal consecutive claim
        claimDay = pd.currentDay + 1
        if claimDay > 7 then claimDay = 1 end
        pd.currentStreak = pd.currentStreak + 1
    end

    local reward = REWARDS[claimDay]
    if not reward then
        claimLocks[player] = nil
        return false, "No reward configured"
    end

    -- ==================== GIVE THE REWARD ====================
    if reward.type == "Coins" then
        print("[DailyReward] Gave", reward.amount, "Coins to", player.Name)
        -- TODO: Put your actual coin giving code here

    elseif reward.type == "Shards" then
        print("[DailyReward] Gave", reward.amount, "Shards to", player.Name)
        -- TODO: Put your actual shards giving code here

    elseif reward.type == "Key" then
        print("[DailyReward] Gave 1 Golden Key to", player.Name)
        -- TODO: Put your actual key/item giving code here
    end

    -- Update state
    pd.currentDay = claimDay
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