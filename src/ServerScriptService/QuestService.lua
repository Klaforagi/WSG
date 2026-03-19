--------------------------------------------------------------------------------
-- QuestService.lua  –  Server-side Daily Quest tracking
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player quest progress in memory. Progress resets each
-- calendar day (UTC). Rewards are granted through CurrencyService.
--
-- Uses DailyQuestDefs (ReplicatedStorage) for the quest pool so
-- definitions are shared with the client UI.
--
-- Public API used by QuestServiceInit.server.lua:
--   QuestService:GetQuestsForPlayer(player) -> { {id, title, desc, goal, progress, reward, claimed}, ... }
--   QuestService:IncrementQuest(player, questId, amount)
--   QuestService:IncrementByType(player, trackType, amount)
--   QuestService:ClaimReward(player, questId) -> bool success
--   QuestService:RerollQuest(player, questIndex) -> bool, string, updatedQuests
--------------------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyQuestDefs = require(ReplicatedStorage:WaitForChild("DailyQuestDefs", 10))

local QuestService = {}

--------------------------------------------------------------------------------
-- Quest definitions sourced from shared DailyQuestDefs module
--------------------------------------------------------------------------------
local QUEST_DEFS          = DailyQuestDefs.Pool
local QUEST_DEF_BY_ID     = DailyQuestDefs.ById
local QUEST_DEFS_BY_TRACK = DailyQuestDefs.ByTrackType

-- Track types for assignment diversity (one quest per track type)
local DEFAULT_TRACK_ORDER = {}
for tt, _ in pairs(QUEST_DEFS_BY_TRACK) do
    table.insert(DEFAULT_TRACK_ORDER, tt)
end
table.sort(DEFAULT_TRACK_ORDER) -- deterministic order

--------------------------------------------------------------------------------
-- Per-player state:
-- playerData[player] = {
--     day = "2026-03-16",
--     questOrder = { "monster_hunter", "player_hunter", "battle_ready" },
--     quests = { [questId] = { progress, claimed } },
-- }
--------------------------------------------------------------------------------
local playerData = {}

local function todayKey()
    return os.date("!%Y-%m-%d")
end

local function shuffleInPlace(items)
    for i = #items, 2, -1 do
        local j = math.random(1, i)
        items[i], items[j] = items[j], items[i]
    end
end

-- Number of daily quests assigned per day (picks from different track types)
local DAILY_QUEST_COUNT = 3

local function assignQuestOrder()
    local order = {}
    local usedQuestIds = {}

    -- Shuffle track types so each day features a different mix
    local shuffledTracks = table.clone(DEFAULT_TRACK_ORDER)
    shuffleInPlace(shuffledTracks)

    for _, trackType in ipairs(shuffledTracks) do
        if #order >= DAILY_QUEST_COUNT then break end
        local pool = QUEST_DEFS_BY_TRACK[trackType]
        if pool and #pool > 0 then
            local candidates = table.clone(pool)
            shuffleInPlace(candidates)
            for _, def in ipairs(candidates) do
                if not usedQuestIds[def.id] then
                    usedQuestIds[def.id] = true
                    table.insert(order, def.id)
                    break
                end
            end
        end
    end

    return order
end

local function buildQuestState(order)
    local quests = {}
    for _, questId in ipairs(order) do
        quests[questId] = { progress = 0, claimed = false }
    end
    return quests
end

local function ensurePlayerData(player)
    local today = todayKey()
    local pd = playerData[player]
    if pd and pd.day == today then
        return pd
    end

    local order = assignQuestOrder()
    pd = {
        day = today,
        questOrder = order,
        quests = buildQuestState(order),
    }
    playerData[player] = pd
    return pd
end

--------------------------------------------------------------------------------
-- CurrencyService (loaded lazily so require order doesn't matter)
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

local function getQuestRemotesFolder()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return nil end
    return remotes:FindFirstChild("Quests")
end

local function fireQuestProgress(player, questId, newProgress)
    local questRemotes = getQuestRemotesFolder()
    if not questRemotes then return end

    local ev = questRemotes:FindFirstChild("QuestProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, questId, newProgress)
        end)
    end
end

local function getQuestSnapshot(pd, questId)
    local def = QUEST_DEF_BY_ID[questId]
    local state = pd.quests[questId]
    if not def or not state then return nil end

    return {
        id = def.id,
        title = def.title,
        desc = def.desc,
        goal = def.goal,
        progress = math.min(state.progress, def.goal),
        reward = def.reward,
        claimed = state.claimed,
    }
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function QuestService:GetQuestsForPlayer(player)
    local pd = ensurePlayerData(player)
    local out = {}

    for _, questId in ipairs(pd.questOrder) do
        local snapshot = getQuestSnapshot(pd, questId)
        if snapshot then
            table.insert(out, snapshot)
        end
    end

    return out
end

function QuestService:IncrementQuest(player, questId, amount)
    amount = tonumber(amount) or 1

    local pd = ensurePlayerData(player)
    local state = pd.quests[questId]
    local def = QUEST_DEF_BY_ID[questId]
    if not state or not def then return end
    if state.claimed then return end

    state.progress = math.min(state.progress + amount, def.goal)
    fireQuestProgress(player, questId, state.progress)
end

function QuestService:IncrementByType(player, trackType, amount)
    amount = tonumber(amount) or 1

    local pd = ensurePlayerData(player)
    for _, questId in ipairs(pd.questOrder) do
        local def = QUEST_DEF_BY_ID[questId]
        if def and def.trackType == trackType then
            self:IncrementQuest(player, questId, amount)
        end
    end
end

function QuestService:ClaimReward(player, questId)
    local pd = ensurePlayerData(player)
    local state = pd.quests[questId]
    local def = QUEST_DEF_BY_ID[questId]
    if not state or not def then return false end
    if state.claimed then return false end
    if state.progress < def.goal then return false end

    local cs = getCurrencyService()
    if cs and cs.AddCoins then
        cs:AddCoins(player, def.reward, "quest")
    end

    state.claimed = true
    return true
end

function QuestService:RerollQuest(player, questIndex)
    questIndex = tonumber(questIndex)
    if not questIndex then
        return false, "Invalid quest index"
    end

    local pd = ensurePlayerData(player)
    if questIndex < 1 or questIndex > #pd.questOrder then
        return false, "Invalid quest index"
    end

    local oldQuestId = pd.questOrder[questIndex]
    local oldState = pd.quests[oldQuestId]
    local oldDef = QUEST_DEF_BY_ID[oldQuestId]
    if not oldState or not oldDef then
        return false, "Quest unavailable"
    end
    if oldState.claimed then
        return false, "Quest already claimed"
    end

    local assignedIds = {}
    for _, questId in ipairs(pd.questOrder) do
        assignedIds[questId] = true
    end

    local alternatives = {}
    local sameTrackPool = QUEST_DEFS_BY_TRACK[oldDef.trackType] or {}
    for _, def in ipairs(sameTrackPool) do
        if def.id ~= oldQuestId and not assignedIds[def.id] then
            table.insert(alternatives, def)
        end
    end

    if #alternatives == 0 then
        for _, def in ipairs(QUEST_DEFS) do
            if def.id ~= oldQuestId and not assignedIds[def.id] then
                table.insert(alternatives, def)
            end
        end
    end

    if #alternatives == 0 then
        return false, "No alternative quests available"
    end

    local newDef = alternatives[math.random(1, #alternatives)]
    pd.quests[oldQuestId] = nil
    pd.questOrder[questIndex] = newDef.id
    pd.quests[newDef.id] = { progress = 0, claimed = false }

    return true, "Quest rerolled", self:GetQuestsForPlayer(player)
end

function QuestService:ClearPlayer(player)
    playerData[player] = nil
end

return QuestService
