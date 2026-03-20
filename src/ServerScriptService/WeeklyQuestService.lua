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
--   WeeklyQuestService:ClearPlayer(player)
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

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

--------------------------------------------------------------------------------
-- Week key: year + Monday-based week number (UTC)
--------------------------------------------------------------------------------
local function currentWeekKey()
    return os.date("!%Y-W%W")
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
local function assignNewQuests()
    local trackTypes = {}
    for tt, _ in pairs(WeeklyQuestDefs.ByTrackType) do
        table.insert(trackTypes, tt)
    end

    -- Shuffle track types
    for i = #trackTypes, 2, -1 do
        local j = math.random(1, i)
        trackTypes[i], trackTypes[j] = trackTypes[j], trackTypes[i]
    end

    local quests = {}
    for i = 1, 3 do
        local tt = trackTypes[((i - 1) % #trackTypes) + 1]
        local pool = WeeklyQuestDefs.ByTrackType[tt]
        local def = pool[math.random(#pool)]
        table.insert(quests, {
            defId    = def.id,
            progress = 0,
            claimed  = false,
        })
    end
    return quests
end

--------------------------------------------------------------------------------
-- DataStore load
--------------------------------------------------------------------------------
local function loadFromStore(player)
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[WeeklyQuestService] GetAsync failed (attempt " .. i .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    if success and type(result) == "table" then
        return result
    end
    return nil
end

--------------------------------------------------------------------------------
-- DataStore save
--------------------------------------------------------------------------------
local function saveToStore(player, data)
    local key = getKey(player)
    local saveData = {
        weekKey = data.weekKey,
        quests  = {},
    }
    for i, q in ipairs(data.quests) do
        saveData.quests[i] = {
            defId    = q.defId,
            progress = q.progress,
            claimed  = q.claimed,
        }
    end

    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, saveData)
        end)
        if success then break end
        warn("[WeeklyQuestService] SetAsync failed (attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    return success
end

--------------------------------------------------------------------------------
-- Debounced auto-save: saves dirty data every 30 seconds
--------------------------------------------------------------------------------
local saveQueue = {} -- [player] = true

task.spawn(function()
    while true do
        task.wait(30)
        for player, _ in pairs(saveQueue) do
            if player and player.Parent then
                local data = playerWeekly[player]
                if data then
                    task.spawn(saveToStore, player, data)
                    data.dirty = false
                end
            end
            saveQueue[player] = nil
        end
    end
end)

local function markDirty(player)
    local data = playerWeekly[player]
    if data then
        data.dirty = true
        saveQueue[player] = true
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
    local stored = loadFromStore(player)

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
            return
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
    -- Save immediately for new assignments
    task.spawn(saveToStore, player, playerWeekly[player])
end

--- Save the player's weekly quest data. Call on PlayerRemoving.
function WeeklyQuestService:SavePlayer(player)
    local data = playerWeekly[player]
    if data then
        saveToStore(player, data)
    end
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
    task.spawn(saveToStore, player, data)

    return true
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
    task.spawn(saveToStore, player, data)

    return true, "Quest rerolled", self:GetWeeklyQuests(player)
end

--- Cleanup when player leaves. Save first, then clear memory.
function WeeklyQuestService:ClearPlayer(player)
    self:SavePlayer(player)
    playerWeekly[player] = nil
    saveQueue[player] = nil
end

return WeeklyQuestService
