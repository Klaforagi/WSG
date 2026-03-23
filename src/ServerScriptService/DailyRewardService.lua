--------------------------------------------------------------------------------
-- DailyRewardService.lua  –  Server-authoritative daily-reward management
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player streak state, determines eligibility, grants rewards
-- using real game systems, and persists data to DataStore.
--
-- Public API (used by DailyRewardServiceInit.server.lua):
--   DailyRewardService:LoadForPlayer(player)  -> bool
--   DailyRewardService:SaveForPlayer(player)  -> bool
--   DailyRewardService:SaveAll()
--   DailyRewardService:ClearPlayer(player)
--   DailyRewardService:GetState(player)       -> stateSnapshot
--   DailyRewardService:ClaimReward(player)    -> bool, string
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local DATASTORE_NAME = "DailyRewards_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

--------------------------------------------------------------------------------
-- Lazy-require dependencies (load-order safe)
--------------------------------------------------------------------------------
local DailyRewardConfig
local function getConfig()
    if DailyRewardConfig then return DailyRewardConfig end
    pcall(function()
        local mod = ReplicatedStorage:WaitForChild("DailyRewardConfig", 10)
        if mod and mod:IsA("ModuleScript") then
            DailyRewardConfig = require(mod)
        end
    end)
    return DailyRewardConfig
end

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

local BoostService
local function getBoostService()
    if BoostService then return BoostService end
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("BoostService")
        if mod and mod:IsA("ModuleScript") then
            BoostService = require(mod)
        end
    end)
    return BoostService
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local DailyRewardService = {}

-- Per-player persistent state:
-- playerData[player] = {
--     currentStreak   = number,   -- consecutive days claimed (1-based)
--     currentDay      = number,   -- which day in the cycle (1..CycleDays)
--     lastClaimDate   = string,   -- "YYYY-MM-DD" UTC of last claim
--     lastClaimTime   = number,   -- os.time() of last claim
--     totalClaims     = number,   -- lifetime claims (stat tracking)
-- }
local playerData = {}

-- Session flags (not persisted) – prevent auto-popup more than once per session
local sessionFlags = {} -- [player] = { autoPopupShown = bool }

-- Claim lock – prevent double-claim from rapid remote calls
local claimLocks = {} -- [player] = true while processing

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- Date helpers (UTC-based, day-granularity)
--------------------------------------------------------------------------------

--- Get today's date key in UTC ("YYYY-MM-DD")
local function getTodayKey()
    return os.date("!%Y-%m-%d", os.time())
end

--- Parse a "YYYY-MM-DD" date string into a table { year, month, day }
local function parseDateKey(dateStr)
    if type(dateStr) ~= "string" then return nil end
    local y, m, d = dateStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return nil end
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

--- Convert a date key to a UTC epoch at midnight of that day
local function dateKeyToEpoch(dateStr)
    local p = parseDateKey(dateStr)
    if not p then return 0 end
    return os.time({ year = p.year, month = p.month, day = p.day, hour = 0, min = 0, sec = 0 })
end

--- Calculate number of calendar days between two date keys.
--- Returns 0 if same day, 1 if consecutive, etc.
local function daysBetween(dateKeyA, dateKeyB)
    local epochA = dateKeyToEpoch(dateKeyA)
    local epochB = dateKeyToEpoch(dateKeyB)
    if epochA == 0 or epochB == 0 then return 9999 end
    local diff = math.abs(epochB - epochA)
    return math.floor(diff / 86400)
end

--------------------------------------------------------------------------------
-- State management helpers
--------------------------------------------------------------------------------

local function makeEmptyState()
    return {
        currentStreak = 0,
        currentDay    = 0,   -- 0 means never claimed; will become 1 on first claim
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

--------------------------------------------------------------------------------
-- Eligibility logic
--------------------------------------------------------------------------------

--- Determine the player's claim eligibility.
--- Returns: canClaim (bool), nextDay (number), streakBroken (bool)
local function evaluateEligibility(pd)
    local config = getConfig()
    if not config then return false, 1, false end

    local today = getTodayKey()

    -- Never claimed before → eligible for day 1
    if pd.lastClaimDate == "" or pd.currentDay == 0 then
        return true, 1, false
    end

    -- Already claimed today
    if pd.lastClaimDate == today then
        return false, pd.currentDay, false
    end

    -- Check how many days since last claim
    local gap = daysBetween(pd.lastClaimDate, today)

    if gap == 1 then
        -- Consecutive day: advance streak
        local nextDay = pd.currentDay + 1
        if nextDay > config.CycleDays then
            nextDay = 1  -- loop the cycle
        end
        return true, nextDay, false
    elseif gap <= math.floor((config.GraceHours or 48) / 24) then
        -- Within grace period (default: missed 1 day is ok if gap <= 2)
        -- Be forgiving: advance streak normally
        local nextDay = pd.currentDay + 1
        if nextDay > config.CycleDays then
            nextDay = 1
        end
        return true, nextDay, false
    else
        -- Streak broken: reset to day 1
        return true, 1, true
    end
end

--------------------------------------------------------------------------------
-- Reward granting
--------------------------------------------------------------------------------

--- Grant the actual reward to the player based on config entry.
--- Returns true on success, false + reason on failure.
local function grantReward(player, rewardEntry)
    if not rewardEntry then return false, "No reward entry" end

    local config = getConfig()
    if not config then return false, "Config unavailable" end

    local rtype  = rewardEntry.RewardType
    local amount = rewardEntry.Amount or 1

    if rtype == config.RewardType.Coins then
        local cs = getCurrencyService()
        if cs then
            cs:AddCoins(player, amount)
            print("[DailyRewardService] Granted", amount, "coins to", player.Name)
            return true
        else
            warn("[DailyRewardService] CurrencyService not available")
            return false, "CurrencyService unavailable"
        end

    elseif rtype == config.RewardType.XPBoost then
        -- Grant quest_2x boosts (2x quest progress for 30 min each) to inventory
        local bs = getBoostService()
        if bs and bs.GrantFreeBoost then
            local granted = bs:GrantFreeBoost(player, "quest_2x", amount)
            if granted then
                print("[DailyRewardService] Granted", amount, "XP Boost(s) to", player.Name)
                return true
            end
        end
        warn("[DailyRewardService] Could not grant XP boost")
        return false, "Boost grant failed"

    elseif rtype == config.RewardType.QuestReroll then
        local bs = getBoostService()
        if bs and bs.GrantFreeReroll then
            bs:GrantFreeReroll(player, amount)
            print("[DailyRewardService] Granted", amount, "free reroll token(s) to", player.Name)
            return true
        end
        warn("[DailyRewardService] Could not grant free reroll – BoostService unavailable")
        return false, "BoostService unavailable for free reroll"

    else
        warn("[DailyRewardService] Unknown reward type:", tostring(rtype))
        return false, "Unknown reward type"
    end
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

function DailyRewardService:LoadForPlayer(player)
    if not player then return false end

    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[DailyRewardService] GetAsync failed (attempt", i, "):", tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    if success then
        playerData[player] = normalizeState(result)
    else
        warn("[DailyRewardService] Failed to load for", player.Name, "- using defaults")
        playerData[player] = makeEmptyState()
    end

    sessionFlags[player] = { autoPopupShown = false }
    return success ~= false
end

function DailyRewardService:SaveForPlayer(player)
    local pd = playerData[player]
    if not player or not pd then return false end

    local key = getKey(player)
    local payload = {
        currentStreak = pd.currentStreak,
        currentDay    = pd.currentDay,
        lastClaimDate = pd.lastClaimDate,
        lastClaimTime = pd.lastClaimTime,
        totalClaims   = pd.totalClaims,
    }

    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, payload)
        end)
        if success then break end
        warn("[DailyRewardService] SetAsync failed (attempt", i, "):", tostring(err))
        task.wait(RETRY_DELAY * i)
    end

    if not success then
        warn("[DailyRewardService] Failed to save for", player.Name)
    end
    return success ~= false
end

function DailyRewardService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(function()
            DailyRewardService:SaveForPlayer(player)
        end)
    end
end

function DailyRewardService:ClearPlayer(player)
    playerData[player] = nil
    sessionFlags[player] = nil
    claimLocks[player] = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Get a clean snapshot of the player's daily reward state for the client.
function DailyRewardService:GetState(player)
    local pd = ensurePlayerData(player)
    local config = getConfig()
    if not config then
        return {
            currentStreak    = 0,
            currentDay       = 0,
            canClaimToday    = false,
            alreadyClaimed   = false,
            lastClaimDate    = "",
            cycleDays        = 7,
            rewards          = {},
        }
    end

    local canClaim, nextDay, streakBroken = evaluateEligibility(pd)
    local today = getTodayKey()
    local alreadyClaimed = (pd.lastClaimDate == today)

    -- Build reward entries with claimed state
    local rewards = {}
    for i = 1, config.CycleDays do
        local entry = config.GetReward(i)
        if entry then
            local status = "future"  -- default
            if alreadyClaimed then
                if i < pd.currentDay then
                    status = "claimed"
                elseif i == pd.currentDay then
                    status = "claimed"  -- today, already claimed
                else
                    status = "future"
                end
            else
                -- Not yet claimed today
                if canClaim then
                    if streakBroken then
                        -- Streak broken, resetting to day 1
                        if i == 1 then
                            status = "claimable"
                        else
                            status = "future"
                        end
                    else
                        if i < nextDay then
                            status = "claimed"
                        elseif i == nextDay then
                            status = "claimable"
                        else
                            status = "future"
                        end
                    end
                else
                    -- Cannot claim (already claimed or other issue)
                    if i <= pd.currentDay then
                        status = "claimed"
                    else
                        status = "future"
                    end
                end
            end

            table.insert(rewards, {
                day         = i,
                rewardType  = entry.RewardType,
                amount      = entry.Amount,
                displayName = entry.DisplayName,
                description = entry.Description,
                rarity      = entry.Rarity,
                status      = status,
            })
        end
    end

    -- Next reward preview (tomorrow)
    local nextPreview = nil
    if alreadyClaimed then
        local previewDay = pd.currentDay + 1
        if previewDay > config.CycleDays then previewDay = 1 end
        local pe = config.GetReward(previewDay)
        if pe then
            nextPreview = {
                day         = previewDay,
                displayName = pe.DisplayName,
                rewardType  = pe.RewardType,
            }
        end
    end

    return {
        currentStreak    = pd.currentStreak,
        currentDay       = alreadyClaimed and pd.currentDay or (canClaim and nextDay or pd.currentDay),
        canClaimToday    = canClaim and not alreadyClaimed,
        alreadyClaimed   = alreadyClaimed,
        lastClaimDate    = pd.lastClaimDate,
        cycleDays        = config.CycleDays,
        rewards          = rewards,
        nextPreview      = nextPreview,
        autoPopup        = not (sessionFlags[player] and sessionFlags[player].autoPopupShown),
    }
end

--- Mark auto-popup as shown this session (called after sending initial state).
function DailyRewardService:MarkAutoPopupShown(player)
    if sessionFlags[player] then
        sessionFlags[player].autoPopupShown = true
    end
end

--- Claim today's reward. Returns success (bool) and a message string.
function DailyRewardService:ClaimReward(player)
    if not player then return false, "Invalid player" end

    -- Prevent double-claim from rapid calls
    if claimLocks[player] then
        return false, "Claim in progress"
    end
    claimLocks[player] = true

    local pd = ensurePlayerData(player)
    local config = getConfig()
    if not config then
        claimLocks[player] = nil
        return false, "Config unavailable"
    end

    local canClaim, nextDay, streakBroken = evaluateEligibility(pd)

    if not canClaim then
        claimLocks[player] = nil
        return false, "Not eligible today"
    end

    local today = getTodayKey()
    if pd.lastClaimDate == today then
        claimLocks[player] = nil
        return false, "Already claimed today"
    end

    -- Determine the reward
    local rewardEntry = config.GetReward(nextDay)
    if not rewardEntry then
        claimLocks[player] = nil
        return false, "No reward configured for day " .. tostring(nextDay)
    end

    -- Grant the reward
    local grantOk, grantMsg = grantReward(player, rewardEntry)
    if not grantOk then
        claimLocks[player] = nil
        return false, grantMsg or "Failed to grant reward"
    end

    -- Update state
    if streakBroken then
        pd.currentStreak = 1
    else
        pd.currentStreak = pd.currentStreak + 1
    end
    pd.currentDay    = nextDay
    pd.lastClaimDate = today
    pd.lastClaimTime = os.time()
    pd.totalClaims   = pd.totalClaims + 1

    -- Save immediately after claim
    task.spawn(function()
        DailyRewardService:SaveForPlayer(player)
    end)

    claimLocks[player] = nil
    print("[DailyRewardService]", player.Name, "claimed Day", nextDay, "reward:", rewardEntry.DisplayName)
    return true, "Claimed " .. rewardEntry.DisplayName
end

return DailyRewardService
