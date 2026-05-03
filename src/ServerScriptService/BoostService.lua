--------------------------------------------------------------------------------
-- BoostService.lua  –  Server-authoritative boost management
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player active timed boosts and handles purchase / activation /
-- expiry logic.  Instant-use boosts (reroll, bonus claim) are validated and
-- executed here as well.
--
-- Public API (used by BoostServiceInit.server.lua):
--   BoostService:Init()
--   BoostService:PurchaseOwnedBoost(player, boostId) -> bool, string, states
--   BoostService:ActivateOwnedBoost(player, boostId) -> bool, string, states
--   BoostService:BuyAndActivate(player, boostId) -> bool, string, states  -- legacy alias
--   BoostService:RerollQuest(player, questType, questIndex) -> bool, string, updatedQuests
--   BoostService:GetRerollCooldowns(player) -> { daily = number, weekly = number }
--   BoostService:BonusClaim(player, questId) -> bool, string
--   BoostService:HasActiveBoost(player, boostId) -> bool
--   BoostService:GetCoinMultiplier(player) -> number
--   BoostService:GetQuestProgressMultiplier(player) -> number
--   BoostService:GetPlayerBoostStates(player) -> { [boostId] = { active, expiresAt, owned } }
--   BoostService:LoadForPlayer(player) -> bool
--   BoostService:SaveForPlayer(player) -> bool
--   BoostService:ClearPlayer(player)
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local DATASTORE_NAME = "Boosts_v2"
local RETRIES = 3
local RETRY_DELAY = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

----------------------------------------------------------------------------
-- Lazy-require dependencies so load order doesn't matter
----------------------------------------------------------------------------
local BoostConfig
local function getBoostConfig()
    if BoostConfig then return BoostConfig end
    pcall(function()
        local mod = ReplicatedStorage:WaitForChild("BoostConfig", 10)
        if mod and mod:IsA("ModuleScript") then
            BoostConfig = require(mod)
        end
    end)
    return BoostConfig
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

local QuestService
local function getQuestService()
    if QuestService then return QuestService end
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("QuestService")
        if mod and mod:IsA("ModuleScript") then
            QuestService = require(mod)
        end
    end)
    return QuestService
end

local WeeklyQuestService
local function getWeeklyQuestService()
    if WeeklyQuestService then return WeeklyQuestService end
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("WeeklyQuestService")
        if mod and mod:IsA("ModuleScript") then
            WeeklyQuestService = require(mod)
        end
    end)
    return WeeklyQuestService
end

----------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------
local BoostService = {}

-- Per-player state.
-- playerBoosts[player] = {
--     inventory = { [boostId] = ownedCount },
--     active = { [boostId] = { expiresAt = os.time() + duration } },
--     bonusClaimed = { [questId] = true },
-- }
local playerBoosts = {}

----------------------------------------------------------------------------
-- Reroll cooldown tracking (server-authoritative, in-memory only)
-- rerollCooldowns[player] = { daily = expiresAt, weekly = expiresAt }
----------------------------------------------------------------------------
local DAILY_REROLL_COOLDOWN  = 45   -- seconds
local WEEKLY_REROLL_COOLDOWN = 90   -- seconds

local rerollCooldowns = {}

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

local function makeEmptyState()
    local state = {
        inventory = {},
        active = {},
        bonusClaimed = {},
        freeRerolls = 0,  -- free quest reroll tokens (from Daily Login Rewards Day 4)
    }

    local config = getBoostConfig()
    if config and config.Boosts then
        for _, def in ipairs(config.Boosts) do
            if not def.InstantUse then
                state.inventory[def.Id] = 0
                state.active[def.Id] = { expiresAt = 0 }
            end
        end
    end

    return state
end

local function normalizePlayerState(raw)
    local state = makeEmptyState()
    raw = type(raw) == "table" and raw or {}

    -- Free reroll tokens
    state.freeRerolls = math.max(0, math.floor(tonumber(raw.freeRerolls) or 0))

    if type(raw.inventory) == "table" then
        for boostId, count in pairs(raw.inventory) do
            state.inventory[boostId] = math.max(0, math.floor(tonumber(count) or 0))
        end
    end

    if type(raw.active) == "table" then
        for boostId, entry in pairs(raw.active) do
            local expiresAt = 0
            if type(entry) == "table" then
                expiresAt = math.floor(tonumber(entry.expiresAt) or 0)
            end
            state.active[boostId] = { expiresAt = expiresAt }
        end
    elseif type(raw.timed) == "table" then
        for boostId, entry in pairs(raw.timed) do
            local expiresAt = 0
            if type(entry) == "table" then
                expiresAt = math.floor(tonumber(entry.expiresAt) or 0)
            end
            state.active[boostId] = { expiresAt = expiresAt }
        end
    end

    if type(raw.bonusClaimed) == "table" then
        for questId, claimed in pairs(raw.bonusClaimed) do
            if claimed then
                state.bonusClaimed[questId] = true
            end
        end
    end

    return state
end

local function clearExpiredBoosts(player)
    local pd = playerBoosts[player]
    if not pd then return end

    local now = os.time()
    for boostId, entry in pairs(pd.active) do
        if type(entry) ~= "table" or (entry.expiresAt or 0) <= now then
            pd.active[boostId] = { expiresAt = 0 }
        end
    end
end

local function serializePlayerState(pd)
    local payload = {
        inventory = {},
        active = {},
        bonusClaimed = {},
        freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0)),
    }

    local now = os.time()

    for boostId, count in pairs(pd.inventory) do
        payload.inventory[boostId] = math.max(0, math.floor(tonumber(count) or 0))
    end

    for boostId, entry in pairs(pd.active) do
        local expiresAt = 0
        if type(entry) == "table" then
            expiresAt = math.floor(tonumber(entry.expiresAt) or 0)
        end
        if expiresAt > now then
            payload.active[boostId] = { expiresAt = expiresAt }
        end
    end

    for questId, claimed in pairs(pd.bonusClaimed) do
        if claimed then
            payload.bonusClaimed[questId] = true
        end
    end

    return payload
end

local function ensurePlayerData(player)
    if not playerBoosts[player] then
        playerBoosts[player] = makeEmptyState()
    end
    return playerBoosts[player]
end

-- BoostStateUpdated RemoteEvent handle, set during Init
local boostStateEvent

----------------------------------------------------------------------------
-- Notify client of current boost states (fire after any mutation)
----------------------------------------------------------------------------
local function pushBoostState(player)
    if not boostStateEvent then return end
    local states = BoostService:GetPlayerBoostStates(player)
    pcall(function()
        boostStateEvent:FireClient(player, states)
    end)
end

----------------------------------------------------------------------------
-- Init: resolve config once at startup
----------------------------------------------------------------------------
function BoostService:Init()
    getBoostConfig()
    getCurrencyService()
    getQuestService()
    getWeeklyQuestService()

    -- resolve or create the remote event used to push state to clients
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if remotesFolder then
        boostStateEvent = remotesFolder:FindFirstChild("BoostStateUpdated")
    end
end

----------------------------------------------------------------------------
-- Persistence helpers
----------------------------------------------------------------------------
function BoostService:LoadForPlayer(player)
    if not player then return false end

    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[BoostService] GetAsync failed (attempt", i, "):", tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    if success then
        playerBoosts[player] = normalizePlayerState(result)
    else
        warn("[BoostService] Failed to load boost data for", player.Name, "- using defaults")
        playerBoosts[player] = makeEmptyState()
    end

    clearExpiredBoosts(player)
    pushBoostState(player)
    return success
end

function BoostService:SaveForPlayer(player)
    local pd = playerBoosts[player]
    if not player or not pd then return false end

    clearExpiredBoosts(player)

    local key = getKey(player)
    local payload = serializePlayerState(pd)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, payload)
        end)
        if success then break end
        warn("[BoostService] SetAsync failed (attempt", i, "):", tostring(err))
        task.wait(RETRY_DELAY * i)
    end

    if not success then
        warn("[BoostService] Failed to save boost data for", player.Name)
    end

    return success
end

function BoostService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        self:SaveForPlayer(player)
    end
end

----------------------------------------------------------------------------
-- Purchase / activation
----------------------------------------------------------------------------
function BoostService:PurchaseOwnedBoost(player, boostId)
    if not player or type(boostId) ~= "string" then
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById(boostId)
    if not def then return false, "Unknown boost" end

    if def.InstantUse then
        return false, "Use the dedicated action for this boost"
    end

    local pd = ensurePlayerData(player)

    local cs = getCurrencyService()
    if not cs then return false, "Currency system unavailable" end

    local balance = cs:GetCoins(player)
    if balance < def.PriceCoins then
        return false, "Insufficient coins"
    end

    cs:AddCoins(player, -def.PriceCoins)

    pd.inventory[boostId] = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0)) + 1
    print(("[BoostService] %s purchased '%s' (owned=%d)"):format(
        player.Name, boostId, pd.inventory[boostId]))

    pushBoostState(player)
    return true, "Purchased", self:GetPlayerBoostStates(player)
end

function BoostService:ActivateOwnedBoost(player, boostId)
    if not player or type(boostId) ~= "string" then
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById(boostId)
    if not def then return false, "Unknown boost" end
    if def.InstantUse then
        return false, "Use the dedicated action for this boost"
    end

    local pd = ensurePlayerData(player)
    clearExpiredBoosts(player)

    local owned = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0))
    if owned < 1 then
        return false, "Not owned", self:GetPlayerBoostStates(player)
    end

    local activeEntry = pd.active[boostId]
    if not def.Stackable and activeEntry and (activeEntry.expiresAt or 0) > os.time() then
        return false, "Already active", self:GetPlayerBoostStates(player)
    end

    pd.inventory[boostId] = owned - 1
    pd.active[boostId] = { expiresAt = os.time() + def.DurationSeconds }

    print(("[BoostService] %s activated '%s' from inventory (remaining=%d)"):format(
        player.Name, boostId, pd.inventory[boostId]))

    pushBoostState(player)
    return true, "Activated", self:GetPlayerBoostStates(player)
end

function BoostService:BuyAndActivate(player, boostId)
    return self:PurchaseOwnedBoost(player, boostId)
end

----------------------------------------------------------------------------
-- Reroll Quest
----------------------------------------------------------------------------
local function getRerollCooldownRemaining(player, questType)
    local cd = rerollCooldowns[player]
    if not cd then return 0 end
    local expiresAt = cd[questType] or 0
    local remaining = expiresAt - os.time()
    return math.max(0, remaining)
end

local function setRerollCooldown(player, questType)
    if not rerollCooldowns[player] then
        rerollCooldowns[player] = { daily = 0, weekly = 0 }
    end
    local duration = questType == "weekly" and WEEKLY_REROLL_COOLDOWN or DAILY_REROLL_COOLDOWN
    rerollCooldowns[player][questType] = os.time() + duration
    print(string.format("[BoostService] Reroll cooldown set: %s %s = %ds", player.Name, questType, duration))
end

function BoostService:GetRerollCooldowns(player)
    if not player then return { daily = 0, weekly = 0, freeRerolls = 0 } end
    local pd = ensurePlayerData(player)
    return {
        daily = getRerollCooldownRemaining(player, "daily"),
        weekly = getRerollCooldownRemaining(player, "weekly"),
        freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0)),
    }
end

function BoostService:RerollQuest(player, questType, questIndex)
    if not player or type(questType) ~= "string" or type(questIndex) ~= "number" then
        print(string.format("[BoostService] Reroll rejected: invalid request params"))
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById("quest_reroll")
    if not def then return false, "Reroll config missing" end

    -- Check cooldown (server-authoritative)
    local cdRemaining = getRerollCooldownRemaining(player, questType)
    if cdRemaining > 0 then
        print(string.format("[BoostService] Reroll rejected: %s %s cooldown active (%ds remaining)", player.Name, questType, cdRemaining))
        return false, "Reroll on cooldown", nil, cdRemaining
    end

    -- Check free reroll entitlement before charging coins
    local pd = ensurePlayerData(player)
    local usedFreeReroll = false
    if pd.freeRerolls and pd.freeRerolls > 0 then
        print(string.format("[FreeReroll] %s has %d free reroll(s) – using 1 (no coin charge)", player.Name, pd.freeRerolls))
        usedFreeReroll = true
    else
        -- Validate coins only if no free reroll
        local cs = getCurrencyService()
        if not cs then return false, "Currency system unavailable" end
        if cs:GetCoins(player) < def.PriceCoins then
            print(string.format("[BoostService] Reroll rejected: %s insufficient coins", player.Name))
            return false, "Insufficient coins"
        end
    end

    local service
    local quests
    if questType == "daily" then
        service = getQuestService()
        if not service then return false, "Quest system unavailable" end
        quests = service:GetQuestsForPlayer(player)
    elseif questType == "weekly" then
        service = getWeeklyQuestService()
        if not service then return false, "Weekly quest system unavailable" end
        quests = service:GetWeeklyQuests(player)
    else
        return false, "Invalid quest type"
    end

    if not quests or questIndex < 1 or questIndex > #quests then
        return false, "Invalid quest index"
    end

    local target = quests[questIndex]

    -- Block completed quests (progress >= goal)
    if target.progress >= target.goal then
        print(string.format("[BoostService] Reroll rejected: %s quest index %d is completed (progress=%d goal=%d)", player.Name, questIndex, target.progress, target.goal))
        return false, "Completed quests cannot be rerolled"
    end

    -- Block claimed quests
    if target.claimed then
        print(string.format("[BoostService] Reroll rejected: %s quest index %d is already claimed", player.Name, questIndex))
        return false, "Quest already claimed"
    end

    local success, msg, updatedQuests = service:RerollQuest(player, questIndex)
    if not success then
        return false, msg or "Reroll failed"
    end

    -- Consume free reroll OR deduct coins (never both)
    if usedFreeReroll then
        pd.freeRerolls = pd.freeRerolls - 1
        print(string.format("[FreeReroll] %s consumed free reroll – remaining: %d", player.Name, pd.freeRerolls))
        -- Persist change immediately
        task.spawn(function() BoostService:SaveForPlayer(player) end)
    else
        local cs = getCurrencyService()
        if cs then
            cs:AddCoins(player, -def.PriceCoins)
        end
    end

    -- Set shared category cooldown
    setRerollCooldown(player, questType)

    print(("[BoostService] %s rerolled %s quest index %d (cost=%s, cooldown=%ds)"):format(
        player.Name, questType, questIndex,
        usedFreeReroll and "FREE" or (def.PriceCoins .. " coins"),
        questType == "weekly" and WEEKLY_REROLL_COOLDOWN or DAILY_REROLL_COOLDOWN))

    pushBoostState(player)
    return true, "Quest rerolled", updatedQuests
end

----------------------------------------------------------------------------
-- Bonus Reward Claim
----------------------------------------------------------------------------
function BoostService:BonusClaim(player, questId)
    if not player or type(questId) ~= "string" then
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById("bonus_claim")
    if not def then return false, "Bonus claim config missing" end

    local pd = ensurePlayerData(player)

    -- Already bonus-claimed this quest?
    if pd.bonusClaimed[questId] then
        return false, "Bonus already claimed for this quest"
    end

    -- Validate coins
    local cs = getCurrencyService()
    if not cs then return false, "Currency system unavailable" end
    if cs:GetCoins(player) < def.PriceCoins then
        return false, "Insufficient coins"
    end

    -- Validate quest is completed
    local qs = getQuestService()
    if not qs then return false, "Quest system unavailable" end

    local quests = qs:GetQuestsForPlayer(player)
    local questDef
    for _, q in ipairs(quests) do
        if q.id == questId then questDef = q break end
    end
    if not questDef then
        return false, "Quest not found"
    end
    if questDef.progress < questDef.goal then
        return false, "Quest not completed"
    end

    -- Deduct coins
    cs:AddCoins(player, -def.PriceCoins, "bonus_claim")

    -- Grant bonus reward (same amount as the quest's normal reward)
    cs:AddCoins(player, questDef.reward, "quest_bonus")

    pd.bonusClaimed[questId] = true
    print(("[BoostService] %s bonus-claimed quest '%s' (+%d coins)"):format(
        player.Name, questId, questDef.reward))

    pushBoostState(player)
    return true, "Bonus reward claimed"
end

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------

function BoostService:HasActiveBoost(player, boostId)
    clearExpiredBoosts(player)
    local pd = playerBoosts[player]
    if not pd then return false end
    local entry = pd.active[boostId]
    if not entry then return false end
    return (entry.expiresAt or 0) > os.time()
end

function BoostService:GetCoinMultiplier(player)
    if self:HasActiveBoost(player, "coins_2x") then
        local def = getBoostConfig() and getBoostConfig().GetById("coins_2x")
        return def and def.Multiplier or 2
    end
    return 1
end

function BoostService:GetQuestProgressMultiplier(player)
    if self:HasActiveBoost(player, "quest_2x") then
        local def = getBoostConfig() and getBoostConfig().GetById("quest_2x")
        return def and def.Multiplier or 2
    end
    return 1
end

function BoostService:GetXPMultiplier(player)
    if self:HasActiveBoost(player, "xp_2x") then
        local def = getBoostConfig() and getBoostConfig().GetById("xp_2x")
        return def and def.Multiplier or 2
    end
    return 1
end

--- Returns a table of boost states for the client UI.
--- { [boostId] = { active = bool, expiresAt = number, bonusClaimed = { [questId]=true } } }
function BoostService:GetPlayerBoostStates(player)
    local pd = ensurePlayerData(player)
    clearExpiredBoosts(player)
    local states = {}
    local config = getBoostConfig()
    if not config then return states end

    local now = os.time()
    for _, def in ipairs(config.Boosts) do
        local entry = {
            active = false,
            expiresAt = 0,
            owned = 0,
        }
        if not def.InstantUse then
            entry.owned = math.max(0, math.floor(tonumber(pd.inventory[def.Id]) or 0))
            local active = pd.active[def.Id]
            if active and (active.expiresAt or 0) > now then
                entry.active = true
                entry.expiresAt = active.expiresAt
            end
        end
        states[def.Id] = entry
    end

    states._bonusClaimed = pd.bonusClaimed

    states._serverTime = now

    -- Include free reroll count so client can display "Free" state
    states._freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0))

    return states
end

----------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------
function BoostService:ClearPlayer(player)
    playerBoosts[player] = nil
end

----------------------------------------------------------------------------
-- Free quest reroll tokens  (granted by Daily Login Rewards Day 4)
-- Stored as a simple integer count in the player's boost state.
-- Persisted to DataStore so they survive across sessions.
----------------------------------------------------------------------------

--- Grant one or more free quest reroll tokens to the player.
function BoostService:GrantFreeReroll(player, count)
    if not player then return false end
    count = math.max(1, math.floor(tonumber(count) or 1))
    local pd = ensurePlayerData(player)
    local before = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0))
    pd.freeRerolls = before + count
    print(string.format("[FreeReroll] Granted %d free reroll(s) to %s (before=%d, after=%d)",
        count, player.Name, before, pd.freeRerolls))
    pushBoostState(player)
    -- Persist immediately so the token survives if the player disconnects
    task.spawn(function() BoostService:SaveForPlayer(player) end)
    return true
end

--- Get the number of free quest reroll tokens available.
function BoostService:GetFreeRerolls(player)
    if not player then return 0 end
    local pd = ensurePlayerData(player)
    return math.max(0, math.floor(tonumber(pd.freeRerolls) or 0))
end

----------------------------------------------------------------------------
-- Free boost grant (for reward systems like Daily Rewards)
-- Adds count to the player's inventory without charging coins.
-- Returns true on success.
----------------------------------------------------------------------------
function BoostService:GrantFreeBoost(player, boostId, count)
    if not player or type(boostId) ~= "string" then return false end
    count = math.max(1, math.floor(tonumber(count) or 1))

    local config = getBoostConfig()
    if not config then return false end
    local def = config.GetById(boostId)
    if not def then return false end

    local pd = ensurePlayerData(player)
    if def.InstantUse then
        -- Instant-use boosts don't have inventory; do nothing here
        return false
    end

    pd.inventory[boostId] = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0)) + count
    print(("[BoostService] Granted %d free '%s' to %s (owned=%d)"):format(
        count, boostId, player.Name, pd.inventory[boostId]))
    pushBoostState(player)
    return true
end

return BoostService
