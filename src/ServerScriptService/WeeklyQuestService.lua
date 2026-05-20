--------------------------------------------------------------------------------
-- WeeklyQuestService.lua  –  Server-side Weekly Quest tracking & persistence
-- ModuleScript in ServerScriptService.
--
-- Manages per-player weekly quest state with DataStore persistence.
-- Assigns 3 random weekly quests from WeeklyQuestDefs pool.
-- Resets automatically when the calendar week changes (UTC, Monday-based).
--
-- Public API used by WeeklyQuestServiceInit.server.lua:
--   WeeklyQuestService:LoadPlayer(player)
--   WeeklyQuestService:SavePlayer(player)
--   WeeklyQuestService:GetWeeklyQuests(player)
--   WeeklyQuestService:IncrementByType(player, trackType, amount)
--   WeeklyQuestService:ClaimReward(player, questIndex)
--   WeeklyQuestService:ResetAllQuests(player)
--   WeeklyQuestService:ClearPlayer(player)
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local WeeklyQuestDefs = require(ReplicatedStorage:WaitForChild("WeeklyQuestDefs", 10))

local WeeklyQuestService = {}

--------------------------------------------------------------------------------
-- DataStore
--------------------------------------------------------------------------------
local DATASTORE_NAME = "WeeklyQuests_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- Per-player in-memory state
-- playerWeekly[player] = {
--     weekKey = "2026-W11",
--     quests  = {
--         [1] = { defId = "win_3_matches",       progress = 1, claimed = false },
--         [2] = { defId = "capture_5_flags",     progress = 2, claimed = false },
--         [3] = { defId = "play_60_min",         progress = 15, claimed = false },
--     },
--     dirty = false,   -- whether unsaved changes exist
-- }
--------------------------------------------------------------------------------
local playerWeekly = {}
local currentWeekKey

local function serializeWeeklyData(data)
    if type(data) ~= "table" then
        return {
            weekKey = currentWeekKey(),
            quests = {},
        }
    end

    local saveData = {
        weekKey = data.weekKey,
        quests = {},
    }
    if type(data.quests) == "table" then
        for index, quest in ipairs(data.quests) do
            saveData.quests[index] = {
                defId = quest.defId,
                progress = quest.progress,
                claimed = quest.claimed,
            }
        end
    end
    return saveData
end

local function questCount(data)
    if type(data) ~= "table" or type(data.quests) ~= "table" then
        return 0
    end
    return #data.quests
end

--------------------------------------------------------------------------------
-- Week key: anchored to Saturday 00:00 Eastern Time (server-authoritative)
--------------------------------------------------------------------------------
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))
currentWeekKey = function()
    return TimeHelper.GetWeeklyKey()
end

--------------------------------------------------------------------------------
-- CurrencyService (loaded lazily)
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
-- Quest assignment: pick 3 quests from different track types for variety
--------------------------------------------------------------------------------
local function shuffleInPlace(items)
    for i = #items, 2, -1 do
        local j = math.random(1, i)
        items[i], items[j] = items[j], items[i]
    end
end

local function normalizeQuestIdSet(questIds)
    local questIdSet = {}
    if type(questIds) ~= "table" then
        return questIdSet
    end

    for key, value in pairs(questIds) do
        if type(key) == "string" then
            if value then
                questIdSet[key] = true
            end
        elseif type(value) == "string" then
            questIdSet[value] = true
        elseif type(value) == "table" and type(value.defId) == "string" then
            questIdSet[value.defId] = true
        end
    end

    return questIdSet
end

local function pickQuestId(defs, usedQuestIds, excludedQuestIds, allowExcluded)
    local candidates = {}
    for _, def in ipairs(defs) do
        if not usedQuestIds[def.id] and (allowExcluded or not excludedQuestIds[def.id]) then
            table.insert(candidates, def.id)
        end
    end

    if #candidates == 0 then
        return nil
    end

    shuffleInPlace(candidates)
    return candidates[1]
end

local function appendQuestEntry(quests, usedQuestIds, defId)
    if not defId or usedQuestIds[defId] then
        return false
    end

    usedQuestIds[defId] = true
    table.insert(quests, {
        defId = defId,
        progress = 0,
        claimed = false,
    })
    return true
end

local function assignNewQuests(excludedQuestIds)
    local excludedQuestIdSet = normalizeQuestIdSet(excludedQuestIds)
    local trackTypes = {}
    for tt, _ in pairs(WeeklyQuestDefs.ByTrackType) do
        table.insert(trackTypes, tt)
    end

    shuffleInPlace(trackTypes)

    local quests = {}
    local usedQuestIds = {}

    for i = 1, math.min(3, #trackTypes) do
        local trackType = trackTypes[i]
        local pool = WeeklyQuestDefs.ByTrackType[trackType] or {}
        local defId = pickQuestId(pool, usedQuestIds, excludedQuestIdSet, false)
        if not defId then
            defId = pickQuestId(pool, usedQuestIds, excludedQuestIdSet, true)
        end
        appendQuestEntry(quests, usedQuestIds, defId)
    end

    while #quests < 3 do
        local defId = pickQuestId(WeeklyQuestDefs.Pool, usedQuestIds, excludedQuestIdSet, false)
        if not defId then
            break
        end
        appendQuestEntry(quests, usedQuestIds, defId)
    end

    while #quests < 3 do
        local defId = pickQuestId(WeeklyQuestDefs.Pool, usedQuestIds, excludedQuestIdSet, true)
        if not defId then
            break
        end
        appendQuestEntry(quests, usedQuestIds, defId)
    end

    return quests
end

--------------------------------------------------------------------------------
-- DataStore load
--------------------------------------------------------------------------------
local function loadFromStore(player)
    local key = getKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "WeeklyQuest/" .. key)
    if success and type(result) == "table" then
        return result, "existing", nil
    end
    return nil, success and "new" or "failed", err
end

--------------------------------------------------------------------------------
-- DataStore save
--------------------------------------------------------------------------------
local function saveToStore(player, data)
    local key = getKey(player)
    local saveData = serializeWeeklyData(data)
    local success, _, err = DataStoreOps.Update(ds, key, "WeeklyQuest/" .. key, function(oldData)
        if questCount(oldData) > 0 and questCount(saveData) == 0 then
            warn("[WeeklyQuestService] suspected wipe blocked for", player.Name)
            return oldData
        end
        return saveData
    end)
    return success, err
end

local function markDirty(player)
    local data = playerWeekly[player]
    if data then
        data.dirty = true
        DataSaveCoordinator:MarkDirty(player, "WeeklyQuest", "weekly_quest", {
            delaySeconds = 30,
        })
    end
end

--------------------------------------------------------------------------------
-- Fire live progress update to client
--------------------------------------------------------------------------------
local function fireProgressUpdate(player, questIndex, newProgress)
    local remote = ReplicatedStorage:FindFirstChild("Remotes")
    if not remote then return end
    local questRemotes = remote:FindFirstChild("Quests")
    if not questRemotes then return end
    local ev = questRemotes:FindFirstChild("WeeklyQuestProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, questIndex, newProgress)
        end)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Load (or initialize) weekly quest data for a player. Call on PlayerAdded.
function WeeklyQuestService:LoadPlayer(player)
    local week = currentWeekKey()
    local stored, status = loadFromStore(player)

    if stored and stored.weekKey == week and type(stored.quests) == "table" and #stored.quests == 3 then
        -- Validate all quest IDs still exist in the pool.
        -- If any saved quest ID was removed (e.g. after a quest pool redesign),
        -- the player gets fresh quests from the current pool instead.
        local valid = true
        for _, q in ipairs(stored.quests) do
            if not WeeklyQuestDefs.ById[q.defId] then
                valid = false
                break
            end
        end
        if valid then
            playerWeekly[player] = {
                weekKey = week,
                quests  = stored.quests,
                dirty   = false,
            }
            return {
                status = status,
                data = serializeWeeklyData(playerWeekly[player]),
            }
        end
    end

    -- New week or first time — assign fresh quests
    local quests = assignNewQuests()
    playerWeekly[player] = {
        weekKey = week,
        quests  = quests,
        dirty   = true,
    }
    markDirty(player)
    return {
        status = stored and "existing" or status,
        data = serializeWeeklyData(playerWeekly[player]),
    }
end

--- Save the player's weekly quest data. Call on PlayerRemoving.
function WeeklyQuestService:SavePlayer(player)
    local data = playerWeekly[player]
    if data then
        return saveToStore(player, data)
    end
    return false, "missing data"
end

function WeeklyQuestService:GetSaveData(player)
    local data = playerWeekly[player]
    if not data then return nil end
    return serializeWeeklyData(data)
end

function WeeklyQuestService:SaveProfileForPlayer(player, currentData)
    return saveToStore(player, currentData or playerWeekly[player])
end

--- Returns an array of quest snapshots for the client.
function WeeklyQuestService:GetWeeklyQuests(player)
    local data = playerWeekly[player]
    if not data then return {} end

    local out = {}
    for i, q in ipairs(data.quests) do
        local def = WeeklyQuestDefs.ById[q.defId]
        if def then
            table.insert(out, {
                index       = i,
                id          = def.id,
                title       = def.title,
                desc        = def.desc,
                goal        = def.goal,
                progress    = math.min(q.progress, def.goal),
                reward      = def.reward,
                claimed     = q.claimed,
                displayUnit = def.displayUnit,
            })
        end
    end
    return out
end

--- Increment progress for ALL weekly quests matching the given trackType.
function WeeklyQuestService:IncrementByType(player, trackType, amount)
    amount = tonumber(amount) or 1
    local data = playerWeekly[player]
    if not data then return end

    for i, q in ipairs(data.quests) do
        if q.claimed then continue end  -- skip claimed quests
        local def = WeeklyQuestDefs.ById[q.defId]
        if def and def.trackType == trackType then
            local oldProgress = q.progress
            q.progress = math.min(q.progress + amount, def.goal)
            if q.progress ~= oldProgress then
                fireProgressUpdate(player, i, q.progress)
            end
        end
    end

    markDirty(player)
end

--- Claim reward for the quest at the given index (1-3). Returns true on success.
function WeeklyQuestService:ClaimReward(player, questIndex)
    questIndex = tonumber(questIndex)
    if not questIndex then return false end

    local data = playerWeekly[player]
    if not data then return false end

    local q = data.quests[questIndex]
    if not q then return false end
    if q.claimed then return false end

    local def = WeeklyQuestDefs.ById[q.defId]
    if not def then return false end
    if q.progress < def.goal then return false end

    -- Grant reward
    local cs = getCurrencyService()
    if cs and cs.AddCoins then
        cs:AddCoins(player, def.reward, "weekly_quest")
    end

    q.claimed = true
    markDirty(player)

    -- Force immediate save after claim
    DataSaveCoordinator:RequestImmediateSave(player, "weekly_quest_claim", { sections = { "WeeklyQuest" }, force = true })

    return true
end

function WeeklyQuestService:ResetAllQuests(player)
    local data = playerWeekly[player]
    if not data then
        return false, "Weekly quests unavailable", {}
    end

    local previousQuestIds = {}
    for _, quest in ipairs(data.quests) do
        if type(quest.defId) == "string" then
            table.insert(previousQuestIds, quest.defId)
        end
    end

    local newQuests = assignNewQuests(previousQuestIds)
    if #newQuests < 3 then
        return false, "No alternative quests available", self:GetWeeklyQuests(player)
    end

    data.quests = newQuests
    markDirty(player)
    DataSaveCoordinator:RequestImmediateSave(player, "weekly_quest_reset", { sections = { "WeeklyQuest" }, force = true })

    return true, "Weekly quests reset", self:GetWeeklyQuests(player)
end

--- Replace the weekly quest at the given index with a different valid quest.
--- Returns success, message, updated weekly quest snapshots.
function WeeklyQuestService:RerollQuest(player, questIndex)
    questIndex = tonumber(questIndex)
    if not questIndex then
        return false, "Invalid quest index"
    end

    local data = playerWeekly[player]
    if not data then
        return false, "Weekly quests unavailable"
    end

    local current = data.quests[questIndex]
    if not current then
        return false, "Invalid quest index"
    end
    if current.claimed then
        return false, "Quest already claimed"
    end

    local currentDef = WeeklyQuestDefs.ById[current.defId]
    if not currentDef then
        return false, "Quest unavailable"
    end

    local assignedIds = {}
    for _, quest in ipairs(data.quests) do
        assignedIds[quest.defId] = true
    end

    local alternatives = {}
    local sameTrackPool = WeeklyQuestDefs.ByTrackType[currentDef.trackType] or {}
    for _, def in ipairs(sameTrackPool) do
        if def.id ~= current.defId and not assignedIds[def.id] then
            table.insert(alternatives, def)
        end
    end

    if #alternatives == 0 then
        for _, def in ipairs(WeeklyQuestDefs.Pool) do
            if def.id ~= current.defId and not assignedIds[def.id] then
                table.insert(alternatives, def)
            end
        end
    end

    if #alternatives == 0 then
        return false, "No alternative quests available"
    end

    local newDef = alternatives[math.random(1, #alternatives)]
    data.quests[questIndex] = {
        defId = newDef.id,
        progress = 0,
        claimed = false,
    }

    markDirty(player)
    DataSaveCoordinator:RequestImmediateSave(player, "weekly_quest_reroll", { sections = { "WeeklyQuest" }, force = true })

    return true, "Quest rerolled", self:GetWeeklyQuests(player)
end

--- Cleanup when player leaves. Save first, then clear memory.
function WeeklyQuestService:ClearPlayer(player)
    playerWeekly[player] = nil
end

return WeeklyQuestService
