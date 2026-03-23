--------------------------------------------------------------------------------
-- QuestService.lua  –  Server-side Daily Quest tracking & persistence
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player daily quest progress with DataStore persistence.
-- Quests persist across rejoins and only reset when the UTC calendar day
-- changes – synchronized with the same daily boundary used by
-- DailyRewardService (os.date("!%Y-%m-%d")).
--
-- Uses DailyQuestDefs (ReplicatedStorage) for the quest pool so
-- definitions are shared with the client UI.
--
-- Public API used by QuestServiceInit.server.lua:
--   QuestService:LoadForPlayer(player)
--   QuestService:SaveForPlayer(player)
--   QuestService:GetQuestsForPlayer(player) -> { {id, title, desc, goal, progress, reward, claimed}, ... }
--   QuestService:IncrementQuest(player, questId, amount)
--   QuestService:IncrementByType(player, trackType, amount)
--   QuestService:ClaimReward(player, questId) -> bool success
--   QuestService:RerollQuest(player, questIndex) -> bool, string, updatedQuests
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyQuestDefs = require(ReplicatedStorage:WaitForChild("DailyQuestDefs", 10))

local QuestService = {}

--------------------------------------------------------------------------------
-- DataStore (mirrors pattern from WeeklyQuestService / DailyRewardService)
--------------------------------------------------------------------------------
local DATASTORE_NAME = "DailyQuests_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

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
--     quests = { [questId] = { progress = 0, claimed = false } },
--     dirty = false,  -- whether unsaved changes exist
-- }
--------------------------------------------------------------------------------
local playerData = {}

--- Same daily boundary used by DailyRewardService (UTC calendar day)
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

--------------------------------------------------------------------------------
-- DataStore save / load helpers
--------------------------------------------------------------------------------

local saveQueue = {} -- [player] = true

--- Debounced auto-save: saves dirty data every 30 seconds
task.spawn(function()
    while true do
        task.wait(30)
        for player, _ in pairs(saveQueue) do
            if player and player.Parent then
                local pd = playerData[player]
                if pd then
                    task.spawn(function()
                        QuestService:SaveForPlayer(player)
                    end)
                    pd.dirty = false
                end
            end
            saveQueue[player] = nil
        end
    end
end)

local function markDirty(player)
    local pd = playerData[player]
    if pd then
        pd.dirty = true
        saveQueue[player] = true
    end
end

--- Save daily quest state to DataStore for a single player.
function QuestService:SaveForPlayer(player)
    local pd = playerData[player]
    if not player or not pd then return false end

    local key = getKey(player)

    -- Serialize quest state
    local questsSave = {}
    for questId, state in pairs(pd.quests) do
        questsSave[questId] = {
            progress = state.progress,
            claimed  = state.claimed,
        }
    end

    local payload = {
        day        = pd.day,
        questOrder = pd.questOrder,
        quests     = questsSave,
    }

    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, payload)
        end)
        if success then break end
        warn("[DailyQuestSave] SetAsync failed (attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end

    if success then
        print("[DailyQuestSave]", player.Name, "| day:", pd.day,
            "| quests:", table.concat(pd.questOrder, ", "))
    else
        warn("[DailyQuestSave] Failed to save for", player.Name)
    end
    return success ~= false
end

--- Load daily quest state from DataStore. If the saved day matches today,
--- restores the exact same quests and progress. Otherwise generates fresh quests.
--- Uses the same UTC day boundary as DailyRewardService.
function QuestService:LoadForPlayer(player)
    if not player then return false end

    local key = getKey(player)
    local today = todayKey()

    -- Load from DataStore
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[DailyQuestLoad] GetAsync failed (attempt " .. i .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    local stored = success and type(result) == "table" and result or nil

    -- Check if saved data is valid and for the current day
    if stored
        and stored.day == today
        and type(stored.questOrder) == "table"
        and #stored.questOrder == DAILY_QUEST_COUNT
        and type(stored.quests) == "table"
    then
        -- Validate all saved quest IDs still exist in the pool
        local valid = true
        for _, questId in ipairs(stored.questOrder) do
            if not QUEST_DEF_BY_ID[questId] then
                valid = false
                break
            end
        end

        if valid then
            -- Restore saved quests with progress
            local quests = {}
            for _, questId in ipairs(stored.questOrder) do
                local sq = stored.quests[questId]
                if type(sq) == "table" then
                    quests[questId] = {
                        progress = math.max(0, math.floor(tonumber(sq.progress) or 0)),
                        claimed  = sq.claimed == true,
                    }
                else
                    quests[questId] = { progress = 0, claimed = false }
                end
            end

            playerData[player] = {
                day        = today,
                questOrder = stored.questOrder,
                quests     = quests,
                dirty      = false,
            }

            print("[DailyQuestLoad]", player.Name,
                "| PRESERVED existing quests | day:", today,
                "| quests:", table.concat(stored.questOrder, ", "),
                "| progress:", (function()
                    local parts = {}
                    for _, qid in ipairs(stored.questOrder) do
                        local s = quests[qid]
                        table.insert(parts, qid .. "=" .. tostring(s and s.progress or 0))
                    end
                    return table.concat(parts, ", ")
                end)())
            return true
        end
    end

    -- New day or no valid saved data → generate fresh quests
    local reason = "new day"
    if not stored then
        reason = "no saved data"
    elseif stored.day ~= today then
        reason = "day changed (saved=" .. tostring(stored.day) .. " current=" .. today .. ")"
    else
        reason = "invalid saved data"
    end

    local order = assignQuestOrder()
    playerData[player] = {
        day        = today,
        questOrder = order,
        quests     = buildQuestState(order),
        dirty      = true,
    }
    markDirty(player)

    print("[DailyQuestReset]", player.Name,
        "| GENERATED new quests | reason:", reason,
        "| day:", today,
        "| quests:", table.concat(order, ", "))

    -- Save immediately so the new assignment persists
    task.spawn(function()
        QuestService:SaveForPlayer(player)
    end)
    return true
end

--- Returns in-memory data, loading if needed. Called by all progress/query APIs.
local function ensurePlayerData(player)
    local pd = playerData[player]
    if pd and pd.day == todayKey() then
        return pd
    end

    -- If we get here without loaded data (shouldn't normally happen since
    -- QuestServiceInit calls LoadForPlayer on join), do a fallback load.
    -- This preserves backward compatibility.
    warn("[DailyQuestLoad]", player.Name, "| ensurePlayerData fallback – data not pre-loaded")
    QuestService:LoadForPlayer(player)
    return playerData[player]
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
    markDirty(player)
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
    markDirty(player)

    -- Force immediate save after claim
    task.spawn(function()
        QuestService:SaveForPlayer(player)
    end)
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
    markDirty(player)

    -- Force immediate save after reroll
    task.spawn(function()
        QuestService:SaveForPlayer(player)
    end)

    return true, "Quest rerolled", self:GetQuestsForPlayer(player)
end

--- Cleanup when player leaves. Save first, then clear memory.
function QuestService:ClearPlayer(player)
    self:SaveForPlayer(player)
    playerData[player] = nil
    saveQueue[player] = nil
end

return QuestService
