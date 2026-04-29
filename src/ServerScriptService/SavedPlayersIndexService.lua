--------------------------------------------------------------------------------
-- SavedPlayersIndexService.lua
--
-- Lightweight index of every player whose data we have ever saved on this game,
-- so the Admin "User Data" tab can browse them.
--
-- DataStores:
--   "SavedPlayersOrdered_v1" (OrderedDataStore)
--     key   = tostring(userId)
--     value = lastSeen (os.time())
--     Used to list saved players ordered by most-recently-seen.
--
--   "SavedPlayersMeta_v1" (regular DataStore)
--     key   = "User_" .. userId
--     value = { userId, username, displayName, firstSeen, lastSeen }
--     Used to look up display info per UserId.
--
-- IMPORTANT: only players who join AFTER this service is deployed will appear
-- in the index. Existing saved-data players will be discovered the first time
-- they rejoin and trigger RecordPlayer.
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")

local ORDERED_NAME = "SavedPlayersOrdered_v1"
local META_NAME    = "SavedPlayersMeta_v1"
local META_KEY_FMT = "User_%d"
local RETRIES      = 3
local RETRY_DELAY  = 0.5

local orderedDS = DataStoreService:GetOrderedDataStore(ORDERED_NAME)
local metaDS    = DataStoreService:GetDataStore(META_NAME)

local SavedPlayersIndexService = {}

-- Small in-process cache so repeated lookups during one admin session are fast.
local metaCache = {} -- [userId] = { userId, username, displayName, lastSeen, firstSeen }

--------------------------------------------------------------------------------
-- Internal: pcall+retry helpers
--------------------------------------------------------------------------------
local function tryGet(ds, key)
    local lastErr
    for i = 1, RETRIES do
        local ok, result = pcall(function() return ds:GetAsync(key) end)
        if ok then return true, result end
        lastErr = result
        task.wait(RETRY_DELAY * i)
    end
    return false, lastErr
end

local function trySet(ds, key, value)
    local lastErr
    for i = 1, RETRIES do
        local ok, err = pcall(function() ds:SetAsync(key, value) end)
        if ok then return true end
        lastErr = err
        task.wait(RETRY_DELAY * i)
    end
    return false, lastErr
end

--------------------------------------------------------------------------------
-- RecordPlayer: call when a player joins (or whenever their data is saved).
-- Updates the OrderedDataStore (lastSeen) and the metadata entry.
--------------------------------------------------------------------------------
function SavedPlayersIndexService:RecordPlayer(player)
    if not player or not player.UserId or player.UserId <= 0 then
        return false, "invalid player"
    end

    local userId      = player.UserId
    local username    = player.Name
    local displayName = player.DisplayName or username
    local now         = os.time()

    -- Read existing meta to preserve firstSeen.
    local _, existing = tryGet(metaDS, string.format(META_KEY_FMT, userId))
    local firstSeen = (type(existing) == "table" and existing.firstSeen) or now

    local entry = {
        userId      = userId,
        username    = username,
        displayName = displayName,
        firstSeen   = firstSeen,
        lastSeen    = now,
    }

    metaCache[userId] = entry

    -- Write meta
    local okMeta, errMeta = trySet(metaDS, string.format(META_KEY_FMT, userId), entry)
    if not okMeta then
        warn("[SavedPlayersIndexService] meta write failed for " .. userId .. ": " .. tostring(errMeta))
    end

    -- Update ordered timestamp (best-effort)
    local okOrd, errOrd = trySet(orderedDS, tostring(userId), now)
    if not okOrd then
        warn("[SavedPlayersIndexService] ordered write failed for " .. userId .. ": " .. tostring(errOrd))
    end

    return okMeta and okOrd
end

--------------------------------------------------------------------------------
-- GetMeta(userId)  ->  { userId, username, displayName, firstSeen, lastSeen } | nil
--------------------------------------------------------------------------------
function SavedPlayersIndexService:GetMeta(userId)
    userId = tonumber(userId)
    if not userId then return nil end

    if metaCache[userId] then return metaCache[userId] end

    local ok, result = tryGet(metaDS, string.format(META_KEY_FMT, userId))
    if not ok then return nil end
    if type(result) == "table" then
        metaCache[userId] = result
        return result
    end
    return nil
end

--------------------------------------------------------------------------------
-- ListPage(page, pageSize) -> { entries, page, pageSize, hasNextPage, totalKnown }
--
-- Pages are ordered by lastSeen DESC. Best-effort: we read up to MAX_SCAN
-- entries and slice in-process (acceptable for a moderation tool).
--------------------------------------------------------------------------------
local MAX_SCAN = 500 -- hard cap on how deep we'll page through OrderedDataStore in one call

function SavedPlayersIndexService:ListPage(page, pageSize)
    page     = math.max(1, tonumber(page) or 1)
    pageSize = math.clamp(tonumber(pageSize) or 25, 1, 100)

    local needed = page * pageSize + 1 -- +1 to know if there's a next page
    needed = math.min(needed, MAX_SCAN)

    local all = {}
    local ok, pages = pcall(function()
        return orderedDS:GetSortedAsync(false, math.min(100, needed))
    end)
    if not ok or not pages then
        warn("[SavedPlayersIndexService] GetSortedAsync failed: " .. tostring(pages))
        return { entries = {}, page = page, pageSize = pageSize, hasNextPage = false, totalKnown = 0 }
    end

    while #all < needed do
        local batch = pages:GetCurrentPage()
        for _, item in ipairs(batch) do
            local uid = tonumber(item.key)
            if uid then
                table.insert(all, { userId = uid, lastSeen = item.value })
            end
            if #all >= needed then break end
        end
        if pages.IsFinished then break end
        local advanceOk = pcall(function() pages:AdvanceToNextPageAsync() end)
        if not advanceOk then break end
    end

    local startIdx = (page - 1) * pageSize + 1
    local endIdx   = math.min(#all, startIdx + pageSize - 1)

    local entries = {}
    for i = startIdx, endIdx do
        local row = all[i]
        local meta = self:GetMeta(row.userId) or {}
        table.insert(entries, {
            userId      = row.userId,
            username    = meta.username    or "?",
            displayName = meta.displayName or meta.username or "?",
            lastSeen    = row.lastSeen,
        })
    end

    return {
        entries     = entries,
        page        = page,
        pageSize    = pageSize,
        hasNextPage = #all > endIdx,
        totalKnown  = #all,
    }
end

--------------------------------------------------------------------------------
-- Search(query) -> { entries, error? }
--
-- query is a string. If numeric, treat as UserId. Otherwise, attempt to resolve
-- via Players:GetUserIdFromNameAsync.
--------------------------------------------------------------------------------
local Players = game:GetService("Players")

function SavedPlayersIndexService:Search(query)
    if type(query) ~= "string" then return { entries = {}, error = "Invalid query" } end
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return { entries = {}, error = "Empty query" } end

    local userId = tonumber(query)
    if not userId then
        local ok, resolved = pcall(function()
            return Players:GetUserIdFromNameAsync(query)
        end)
        if ok and resolved then
            userId = resolved
        else
            return { entries = {}, error = "Username not found" }
        end
    end

    local meta = self:GetMeta(userId)
    if not meta then
        -- Player exists on Roblox but never saved here. Return a synthetic entry
        -- so the admin can still inspect / wipe data (which will be empty).
        local username = "?"
        local okName, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
        if okName and n then username = n end
        return { entries = { {
            userId      = userId,
            username    = username,
            displayName = username,
            lastSeen    = 0,
            unindexed   = true,
        } } }
    end

    return { entries = { {
        userId      = meta.userId,
        username    = meta.username,
        displayName = meta.displayName,
        lastSeen    = meta.lastSeen,
    } } }
end

return SavedPlayersIndexService
