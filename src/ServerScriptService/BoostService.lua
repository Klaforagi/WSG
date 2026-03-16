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
--   BoostService:BuyAndActivate(player, boostId) -> bool, string
--   BoostService:RerollQuest(player, questType, questIndex) -> bool, string, updatedQuests
--   BoostService:BonusClaim(player, questId) -> bool, string
--   BoostService:HasActiveBoost(player, boostId) -> bool
--   BoostService:GetCoinMultiplier(player) -> number
--   BoostService:GetQuestProgressMultiplier(player) -> number
--   BoostService:GetPlayerBoostStates(player) -> { [boostId] = { active, expiresAt } }
--   BoostService:ClearPlayer(player)
--------------------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

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
--     timed = { [boostId] = { expiresAt = os.time() + duration } },
--     bonusClaimed = { [questId] = true },   -- tracks which quests received a bonus
-- }
local playerBoosts = {}

local function ensurePlayerData(player)
    if not playerBoosts[player] then
        playerBoosts[player] = {
            timed = {},
            bonusClaimed = {},
        }
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
-- Buy & Activate (timed boosts)
----------------------------------------------------------------------------
function BoostService:BuyAndActivate(player, boostId)
    if not player or type(boostId) ~= "string" then
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById(boostId)
    if not def then return false, "Unknown boost" end

    -- Instant-use boosts are not purchased through this path
    if def.InstantUse then
        return false, "Use the dedicated action for this boost"
    end

    local pd = ensurePlayerData(player)

    -- Non-stackable: reject if already active
    if not def.Stackable then
        local existing = pd.timed[boostId]
        if existing and existing.expiresAt > os.time() then
            return false, "Already active"
        end
    end

    -- Check coins
    local cs = getCurrencyService()
    if not cs then return false, "Currency system unavailable" end

    local balance = cs:GetCoins(player)
    if balance < def.PriceCoins then
        return false, "Insufficient coins"
    end

    -- Deduct coins
    cs:AddCoins(player, -def.PriceCoins)

    -- Activate
    pd.timed[boostId] = { expiresAt = os.time() + def.DurationSeconds }
    print(("[BoostService] %s activated '%s' (expires in %ds)"):format(
        player.Name, boostId, def.DurationSeconds))

    pushBoostState(player)
    return true, "Activated"
end

----------------------------------------------------------------------------
-- Reroll Quest
----------------------------------------------------------------------------
function BoostService:RerollQuest(player, questType, questIndex)
    if not player or type(questType) ~= "string" or type(questIndex) ~= "number" then
        return false, "Invalid request"
    end

    local config = getBoostConfig()
    if not config then return false, "Config unavailable" end
    local def = config.GetById("quest_reroll")
    if not def then return false, "Reroll config missing" end

    -- Validate coins
    local cs = getCurrencyService()
    if not cs then return false, "Currency system unavailable" end
    if cs:GetCoins(player) < def.PriceCoins then
        return false, "Insufficient coins"
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
    if target.claimed then
        return false, "Quest already claimed"
    end

    local success, msg, updatedQuests = service:RerollQuest(player, questIndex)
    if not success then
        return false, msg or "Reroll failed"
    end

    -- Deduct coins only after successful reroll
    cs:AddCoins(player, -def.PriceCoins)
    print(("[BoostService] %s rerolled %s quest index %d"):format(player.Name, questType, questIndex))

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
    cs:AddCoins(player, -def.PriceCoins)

    -- Grant bonus reward (same amount as the quest's normal reward)
    cs:AddCoins(player, questDef.reward)

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
    local pd = playerBoosts[player]
    if not pd then return false end
    local entry = pd.timed[boostId]
    if not entry then return false end
    if entry.expiresAt <= os.time() then
        pd.timed[boostId] = nil
        return false
    end
    return true
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

--- Returns a table of boost states for the client UI.
--- { [boostId] = { active = bool, expiresAt = number, bonusClaimed = { [questId]=true } } }
function BoostService:GetPlayerBoostStates(player)
    local pd = playerBoosts[player]
    local states = {}
    local config = getBoostConfig()
    if not config then return states end

    local now = os.time()
    for _, def in ipairs(config.Boosts) do
        local entry = {
            active = false,
            expiresAt = 0,
        }
        if pd then
            local timed = pd.timed[def.Id]
            if timed and timed.expiresAt > now then
                entry.active = true
                entry.expiresAt = timed.expiresAt
            end
        end
        states[def.Id] = entry
    end

    -- Attach bonus claimed set so client can grey out quests
    if pd then
        states._bonusClaimed = pd.bonusClaimed
    else
        states._bonusClaimed = {}
    end

    -- Include server time so client can compute remaining seconds accurately
    states._serverTime = now

    return states
end

----------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------
function BoostService:ClearPlayer(player)
    playerBoosts[player] = nil
end

return BoostService
