--------------------------------------------------------------------------------
-- PlayerDataAdminService.lua
--
-- Server-side admin tool for inspecting and resetting saved player data.
--
-- Public API (all require an admin Player object that DevUserIds.IsDev approves):
--   PlayerDataAdminService:GetSavedPlayers(adminPlayer, page, pageSize)
--   PlayerDataAdminService:SearchSavedPlayers(adminPlayer, query)
--   PlayerDataAdminService:GetUserData(adminPlayer, userId)
--   PlayerDataAdminService:ResetUserData(adminPlayer, userId, resetType)
--
-- Strategy:
--   * Reads use direct GetAsync against each subsystem's DataStore so the tool
--     works for OFFLINE players as well as online ones.
--   * Resets wipe the relevant DataStore keys via RemoveAsync so the next time
--     that player joins they receive fresh defaults from the existing services.
--   * For ONLINE players, currency is also live-updated via CurrencyService so
--     leaderstats and the client UI refresh immediately. For other subsystems
--     the admin gets a notice that the player should rejoin to fully refresh
--     in-memory state (or is auto-kicked on Full Reset).
--   * Before any destructive write, a backup snapshot is written to the
--     "AdminDataBackups_v1" DataStore. If the backup write fails on a Full
--     Reset, the reset is aborted.
--   * Every reset is logged via AdminAuditService and a server warn().
--------------------------------------------------------------------------------

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevUserIds            = require(ReplicatedStorage:WaitForChild("DevUserIds"))
local AdminUserDataConfig   = require(ReplicatedStorage:WaitForChild("AdminUserDataConfig"))

local SavedPlayersIndexService = require(script.Parent.SavedPlayersIndexService)

-- Lazy-loaded peer modules to avoid circular requires.
local _CurrencyService, _AdminAuditService
local function getCurrencyService()
    if not _CurrencyService then
        local ok, mod = pcall(function() return require(script.Parent.CurrencyService) end)
        if ok then _CurrencyService = mod end
    end
    return _CurrencyService
end
local function getAdminAuditService()
    if not _AdminAuditService then
        local ok, mod = pcall(function() return require(script.Parent.AdminAuditService) end)
        if ok then _AdminAuditService = mod end
    end
    return _AdminAuditService
end

--------------------------------------------------------------------------------
-- DATASTORE TABLE
--   Single source of truth for every (subsystem -> DataStore name + key format).
--   Key formats use %d for the numeric UserId.
--------------------------------------------------------------------------------
local DATASTORES = {
    Coins        = { name = "Coins_v1",          keyFmt = "User_%d"  },
    Keys         = { name = "Keys_v1",           keyFmt = "User_%d"  },
    Salvage      = { name = "Salvage_v1",        keyFmt = "User_%d"  },
    XP           = { name = "WSG_XP_v1",         keyFmt = "%d"       },
    Upgrades     = { name = "Upgrades_v3",       keyFmt = "User_%d"  },
    Weapons      = { name = "WeaponInstances_v1",keyFmt = "WpnInv_%d"},
    Skins        = { name = "Skins_v1",          keyFmt = "User_%d"  },
    Effects      = { name = "Effects_v1",        keyFmt = "User_%d"  },
    Emotes       = { name = "Emotes_v1",         keyFmt = "User_%d"  },
    Loadout      = { name = "Loadout_v1",        keyFmt = "user_%d"  },
    DailyQuests  = { name = "DailyQuests_v1",    keyFmt = "User_%d"  },
    WeeklyQuests = { name = "WeeklyQuests_v1",   keyFmt = "User_%d"  },
    Achievements = { name = "Achievements_v1",   keyFmt = "User_%d"  },
    Boosts       = { name = "Boosts_v2",         keyFmt = "User_%d"  },
    DailyRewards = { name = "DailyRewards_v1",   keyFmt = "User_%d"  },
    CareerStats  = { name = "CareerStats_v1",    keyFmt = "User_%d"  },
    -- PlayerSettings_v1 is intentionally excluded from resets:
    -- it stores user prefs (volume, sensitivity) unrelated to game progress.
}

-- DataStore handle cache.
local _dsCache = {}
local function dsHandle(spec)
    if not _dsCache[spec.name] then
        _dsCache[spec.name] = DataStoreService:GetDataStore(spec.name)
    end
    return _dsCache[spec.name]
end

-- Reset section -> list of subsystem keys (referencing DATASTORES) to wipe.
local RESET_GROUPS = {
    Currency     = { "Coins", "Keys", "Salvage" },
    Progression  = { "XP", "Upgrades" },
    Inventory    = { "Weapons", "Skins", "Effects", "Emotes", "Loadout" },
    Quests       = { "DailyQuests", "WeeklyQuests" },
    Achievements = { "Achievements" },
}

-- Full Reset wipes every DataStore listed above plus a few extras.
local function buildFullResetList()
    local set, list = {}, {}
    for _, group in pairs(RESET_GROUPS) do
        for _, key in ipairs(group) do
            if not set[key] then set[key] = true; table.insert(list, key) end
        end
    end
    -- Extras included only in Full Reset
    for _, extra in ipairs({ "Boosts", "DailyRewards", "CareerStats" }) do
        if not set[extra] then set[extra] = true; table.insert(list, extra) end
    end
    return list
end
RESET_GROUPS.Full = buildFullResetList()

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local RETRIES, RETRY_DELAY = 3, 0.5

local function tryGet(ds, key)
    for i = 1, RETRIES do
        local ok, result = pcall(function() return ds:GetAsync(key) end)
        if ok then return true, result end
        task.wait(RETRY_DELAY * i)
    end
    return false, nil
end

local function tryRemove(ds, key)
    for i = 1, RETRIES do
        local ok, err = pcall(function() ds:RemoveAsync(key) end)
        if ok then return true end
        task.wait(RETRY_DELAY * i)
        if i == RETRIES then return false, err end
    end
    return false
end

local function trySet(ds, key, value)
    for i = 1, RETRIES do
        local ok, err = pcall(function() ds:SetAsync(key, value) end)
        if ok then return true end
        task.wait(RETRY_DELAY * i)
        if i == RETRIES then return false, err end
    end
    return false
end

local function assertDev(player)
    if not player or not DevUserIds.IsDev(player) then
        return false, "Unauthorized: not a whitelisted developer"
    end
    return true
end

local function findOnlinePlayer(userId)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.UserId == userId then return p end
    end
    return nil
end

--------------------------------------------------------------------------------
-- READ: full snapshot of a user's saved data across every subsystem.
--------------------------------------------------------------------------------
local function readAll(userId)
    local snapshot = {}
    for sub, spec in pairs(DATASTORES) do
        local key = string.format(spec.keyFmt, userId)
        local _, value = tryGet(dsHandle(spec), key)
        snapshot[sub] = value -- may be nil if never saved
    end
    return snapshot
end

--------------------------------------------------------------------------------
-- BACKUP
--   AdminDataBackups_v1      key = backupId  -> full backup record
--   AdminDataBackupIndex_v1  (OrderedDataStore) key = backupId, value = ts
--     Used by the User Data (R) tab to list backups newest-first.
--   AdminRestoreSafety_v1    key = restore_safety_<uid>_<ts> -> snapshot of
--     a player's data captured immediately BEFORE a restore overwrites it.
--------------------------------------------------------------------------------
local backupDS        = DataStoreService:GetDataStore("AdminDataBackups_v1")
local backupIndexODS  = DataStoreService:GetOrderedDataStore("AdminDataBackupIndex_v1")
local restoreSafetyDS = DataStoreService:GetDataStore("AdminRestoreSafety_v1")

-- In-process counter so two backups in the same second don't collide.
local _backupSeq = 0
local function nextBackupId(userId)
    _backupSeq = _backupSeq + 1
    return string.format("bk_%d_%d_%d", userId, os.time(), _backupSeq)
end

local function writeBackup(adminPlayer, userId, resetType, snapshot)
    local backupId = nextBackupId(userId)
    local ts       = os.time()

    local meta = SavedPlayersIndexService:GetMeta(userId) or {}
    local targetUsername    = meta.username
    local targetDisplayName = meta.displayName
    local online = findOnlinePlayer(userId)
    if online then
        targetUsername    = online.Name
        targetDisplayName = online.DisplayName or online.Name
    end

    local payload = {
        backupId           = backupId,
        targetUserId       = userId,
        targetUsername     = targetUsername    or "?",
        targetDisplayName  = targetDisplayName or targetUsername or "?",
        adminUserId        = adminPlayer.UserId,
        adminUsername      = adminPlayer.Name,
        resetType          = resetType,
        timestamp          = ts,
        previousData       = snapshot,
        restored           = false,
        restoredByUserId   = nil,
        restoredByUsername = nil,
        restoredAt         = nil,
    }

    local ok, err = trySet(backupDS, backupId, payload)
    if not ok then
        warn("[PlayerDataAdminService] backup write FAILED for " .. tostring(userId) ..
             " (" .. tostring(resetType) .. "): " .. tostring(err))
        return false, nil
    end

    -- Index entry (best-effort; failure does not invalidate the backup itself).
    local idxOk, idxErr = trySet(backupIndexODS, backupId, ts)
    if not idxOk then
        warn("[PlayerDataAdminService] backup index write failed: " .. tostring(idxErr))
    end

    return true, backupId
end

--------------------------------------------------------------------------------
-- AUDIT LOG WRAPPER
--------------------------------------------------------------------------------
local function logAudit(adminPlayer, userId, resetType, details)
    local audit = getAdminAuditService()
    if not audit then return end
    -- Reuse existing schema: place reset metadata into descriptive fields.
    pcall(function()
        audit:LogAction({
            Action          = "UserDataReset_" .. tostring(resetType),
            AdminUserId     = adminPlayer.UserId,
            AdminUsername   = adminPlayer.Name,
            TargetUserId    = userId,
            TargetUsername  = (Players:GetPlayerByUserId(userId) and Players:GetPlayerByUserId(userId).Name) or "(offline)",
            WeaponId        = "",
            WeaponName      = tostring(resetType),
            SizePercent     = 0,
            Enchant         = tostring(details or ""),
        })
    end)
    warn(string.format(
        "[AdminAudit] %s (%d) reset '%s' on UserId=%d  (%s)",
        adminPlayer.Name, adminPlayer.UserId, tostring(resetType), userId, tostring(details or "")
    ))
end

--------------------------------------------------------------------------------
-- ONLINE LIVE UPDATE: refresh whatever the in-game services let us refresh.
--   `valueOverrides` (optional) is a table mapping subsystem -> new value to
--   apply (used by Restore). When nil/missing, values default to 0 (Reset).
--   Returns: { liveRefreshedSubsystems = {...}, needsRejoin = bool }
--------------------------------------------------------------------------------
local function applyLiveOnlineUpdate(player, subsystems, valueOverrides)
    local refreshed = {}
    local needsRejoin = false
    local subsetSet = {}
    for _, s in ipairs(subsystems) do subsetSet[s] = true end
    valueOverrides = valueOverrides or {}

    local function num(sub)
        local v = valueOverrides[sub]
        if type(v) == "number" then return v end
        return 0
    end

    -- Currency: clean live-update API exists.
    if subsetSet.Coins or subsetSet.Keys or subsetSet.Salvage then
        local cur = getCurrencyService()
        if cur then
            if subsetSet.Coins and cur.SetCoins then
                local v = num("Coins")
                pcall(function() cur:SetCoins(player, v) end)
                table.insert(refreshed, "Coins=" .. tostring(v))
            end
            if subsetSet.Keys and cur.SetKeys then
                local v = num("Keys")
                pcall(function() cur:SetKeys(player, v) end)
                table.insert(refreshed, "Keys=" .. tostring(v))
            end
            if subsetSet.Salvage and cur.SetSalvage then
                local v = num("Salvage")
                pcall(function() cur:SetSalvage(player, v) end)
                table.insert(refreshed, "Salvage=" .. tostring(v))
            end
        else
            -- Without CurrencyService we can't push live; force a rejoin.
            needsRejoin = true
        end
    end

    -- Anything outside currency: in-memory state will overwrite our wiped
    -- DataStore key on PlayerRemoving's save. Without per-service reset hooks
    -- we can't safely nuke that in-memory state, so the only reliable path is
    -- to ask the player to rejoin (or kick on Full Reset, see caller).
    for _, s in ipairs(subsystems) do
        if s ~= "Coins" and s ~= "Keys" and s ~= "Salvage" then
            needsRejoin = true
            break
        end
    end

    return { liveRefreshedSubsystems = refreshed, needsRejoin = needsRejoin }
end

-- Deep copy helper used by Restore so the live cache never holds direct
-- references back into the backup record table.
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[deepCopy(k)] = deepCopy(vv) end
    return out
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------
local PlayerDataAdminService = {}

function PlayerDataAdminService:GetSavedPlayers(adminPlayer, page, pageSize)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    page     = tonumber(page) or 1
    pageSize = tonumber(pageSize) or AdminUserDataConfig.PageSize

    local result = SavedPlayersIndexService:ListPage(page, pageSize)

    -- Tag online status for each entry.
    for _, entry in ipairs(result.entries) do
        entry.isOnline = (findOnlinePlayer(entry.userId) ~= nil)
    end

    result.success = true
    return result
end

function PlayerDataAdminService:SearchSavedPlayers(adminPlayer, query)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    if type(query) ~= "string" then
        return { success = false, error = "Invalid query" }
    end
    if #query > 50 then
        return { success = false, error = "Query too long" }
    end

    local result = SavedPlayersIndexService:Search(query)
    if result.error then
        return { success = false, error = result.error, entries = {} }
    end

    for _, entry in ipairs(result.entries) do
        entry.isOnline = (findOnlinePlayer(entry.userId) ~= nil)
    end

    result.success = true
    return result
end

function PlayerDataAdminService:GetUserData(adminPlayer, userId)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    userId = tonumber(userId)
    if not userId or userId <= 0 then
        return { success = false, error = "Invalid UserId" }
    end

    local meta = SavedPlayersIndexService:GetMeta(userId) or {}
    local username    = meta.username
    local displayName = meta.displayName

    -- Fall back to Roblox API for identity if not indexed.
    if not username then
        local okName, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
        if okName and n then username = n; displayName = displayName or n end
    end

    local snapshot = readAll(userId)

    return {
        success     = true,
        userId      = userId,
        username    = username    or "?",
        displayName = displayName or username or "?",
        firstSeen   = meta.firstSeen,
        lastSeen    = meta.lastSeen,
        isOnline    = (findOnlinePlayer(userId) ~= nil),
        data        = snapshot,
    }
end

function PlayerDataAdminService:ResetUserData(adminPlayer, userId, resetType)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    userId = tonumber(userId)
    if not userId or userId <= 0 then
        return { success = false, error = "Invalid UserId" }
    end

    if type(resetType) ~= "string" or not AdminUserDataConfig.ResetTypes[resetType] then
        return { success = false, error = "Invalid reset type" }
    end

    local subsystems = RESET_GROUPS[resetType]
    if not subsystems then
        return { success = false, error = "No subsystems mapped for reset type" }
    end

    -- 1. Snapshot for backup
    local snapshot = readAll(userId)

    -- 2. Backup (mandatory for Full Reset, best-effort otherwise)
    local backupOk, backupKey = writeBackup(adminPlayer, userId, resetType, snapshot)
    if resetType == "Full" and not backupOk then
        return { success = false, error = "Aborted: backup write failed (refusing Full Reset)" }
    end

    -- 3. Wipe the relevant DataStore keys
    local wiped, failed = {}, {}
    for _, sub in ipairs(subsystems) do
        local spec = DATASTORES[sub]
        if spec then
            local key = string.format(spec.keyFmt, userId)
            local rok, rerr = tryRemove(dsHandle(spec), key)
            if rok then
                table.insert(wiped, sub)
            else
                table.insert(failed, sub .. ":" .. tostring(rerr))
                warn("[PlayerDataAdminService] remove failed " .. spec.name .. "/" .. key)
            end
        end
    end

    -- 4. Online refresh
    local liveResult = { liveRefreshedSubsystems = {}, needsRejoin = false }
    local online = findOnlinePlayer(userId)
    local kicked = false
    if online then
        liveResult = applyLiveOnlineUpdate(online, subsystems)

        -- If any subsystem can't be live-refreshed, the player's in-memory
        -- state would overwrite the wiped DataStore key on PlayerRemoving's
        -- save and silently undo the reset. Kick to guarantee a clean reload.
        if liveResult.needsRejoin or resetType == "Full" then
            task.delay(1.0, function()
                if online and online.Parent then
                    online:Kick("Your saved data was reset by an administrator. Please rejoin.")
                end
            end)
            kicked = true
        end
    end

    -- 5. Audit
    logAudit(adminPlayer, userId, resetType, string.format(
        "wiped=%d failed=%d backupOk=%s online=%s kicked=%s",
        #wiped, #failed, tostring(backupOk), tostring(online ~= nil), tostring(kicked)
    ))

    return {
        success            = true,
        resetType          = resetType,
        userId             = userId,
        wiped              = wiped,
        failed             = failed,
        backupOk           = backupOk,
        backupKey          = backupOk and backupKey or nil,
        backupId           = backupOk and backupKey or nil,
        wasOnline          = online ~= nil,
        kicked             = kicked,
        liveRefreshed      = liveResult.liveRefreshedSubsystems,
        needsRejoinForFull = liveResult.needsRejoin and not kicked,
    }
end

--------------------------------------------------------------------------------
-- RESET HISTORY (User Data (R) tab)
--   Lists backup records newest-first using the OrderedDataStore index.
--   Each entry returned is a lightweight summary; full data is loaded on demand
--   via GetResetBackup(backupId).
--------------------------------------------------------------------------------
local MAX_INDEX_SCAN = 500

-- Pull a flat list of {backupId, timestamp} from the OrderedDataStore, newest
-- first, up to `needed` entries (capped by MAX_INDEX_SCAN).
local function readIndex(needed)
    needed = math.min(needed, MAX_INDEX_SCAN)
    local out = {}
    local ok, pages = pcall(function()
        return backupIndexODS:GetSortedAsync(false, math.min(100, needed))
    end)
    if not ok or not pages then
        warn("[PlayerDataAdminService] backup index GetSortedAsync failed: " .. tostring(pages))
        return out
    end
    while #out < needed do
        local batch = pages:GetCurrentPage()
        for _, item in ipairs(batch) do
            table.insert(out, { backupId = item.key, timestamp = item.value })
            if #out >= needed then break end
        end
        if pages.IsFinished then break end
        local advOk = pcall(function() pages:AdvanceToNextPageAsync() end)
        if not advOk then break end
    end
    return out
end

-- Lightweight backup-record summary used in list rows.
local function summarizeBackup(record)
    if type(record) ~= "table" then return nil end
    return {
        backupId          = record.backupId,
        targetUserId      = record.targetUserId,
        targetUsername    = record.targetUsername,
        targetDisplayName = record.targetDisplayName,
        adminUserId       = record.adminUserId,
        adminUsername     = record.adminUsername,
        resetType         = record.resetType,
        timestamp         = record.timestamp,
        restored          = record.restored == true,
        restoredAt        = record.restoredAt,
        restoredByUserId  = record.restoredByUserId,
        restoredByUsername = record.restoredByUsername,
    }
end

function PlayerDataAdminService:GetResetHistory(adminPlayer, page, pageSize)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    page     = math.max(1, tonumber(page) or 1)
    pageSize = math.clamp(tonumber(pageSize) or 25, 1, 100)

    local needed = page * pageSize + 1
    local indexed = readIndex(needed)

    local startIdx = (page - 1) * pageSize + 1
    local endIdx   = math.min(#indexed, startIdx + pageSize - 1)

    local entries = {}
    for i = startIdx, endIdx do
        local row = indexed[i]
        local _, rec = tryGet(backupDS, row.backupId)
        if type(rec) == "table" then
            local s = summarizeBackup(rec)
            if s then table.insert(entries, s) end
        else
            -- Index points at a missing backup record; surface a stub so the
            -- admin can still see something happened (and we can clean up).
            table.insert(entries, {
                backupId    = row.backupId,
                timestamp   = row.timestamp,
                resetType   = "?",
                targetUserId = 0,
                targetUsername = "(missing record)",
                restored    = false,
            })
        end
    end

    return {
        success     = true,
        entries     = entries,
        page        = page,
        pageSize    = pageSize,
        hasNextPage = #indexed > endIdx,
    }
end

function PlayerDataAdminService:SearchResetHistory(adminPlayer, query)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    if type(query) ~= "string" then return { success = false, error = "Invalid query" } end
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return { success = false, error = "Empty query" } end
    if #query > 50 then return { success = false, error = "Query too long" } end

    -- Resolve query -> userId
    local userId = tonumber(query)
    if not userId then
        local okUid, uid = pcall(function()
            return Players:GetUserIdFromNameAsync(query)
        end)
        if okUid and uid then userId = uid end
    end

    -- Linear scan over the index (capped). Filter by userId or fuzzy username match.
    local indexed = readIndex(MAX_INDEX_SCAN)
    local lowerQuery = string.lower(query)
    local matches = {}

    for _, row in ipairs(indexed) do
        local _, rec = tryGet(backupDS, row.backupId)
        if type(rec) == "table" then
            local matched = false
            if userId and rec.targetUserId == userId then
                matched = true
            elseif type(rec.targetUsername) == "string" and string.find(string.lower(rec.targetUsername), lowerQuery, 1, true) then
                matched = true
            end
            if matched then
                local s = summarizeBackup(rec)
                if s then table.insert(matches, s) end
            end
        end
        if #matches >= 100 then break end
    end

    return { success = true, entries = matches }
end

function PlayerDataAdminService:GetResetBackup(adminPlayer, backupId)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    if type(backupId) ~= "string" or #backupId == 0 or #backupId > 80 then
        return { success = false, error = "Invalid backupId" }
    end

    local gotOk, rec = tryGet(backupDS, backupId)
    if not gotOk or type(rec) ~= "table" then
        return { success = false, error = "Backup not found" }
    end

    return { success = true, record = rec }
end

--------------------------------------------------------------------------------
-- RESTORE
--   Overwrites a player's saved data using a previously captured backup.
--   * Captures a "restore_safety" snapshot of the target's CURRENT data first
--     so we can recover from a wrong-backup restore.
--   * Marks the backup record restored=true with restorer metadata.
--   * If the target is online, kicks them so the in-memory state can't undo
--     the restore on save.
--------------------------------------------------------------------------------
local function writeRestoreSafety(adminPlayer, userId, sourceBackupId, snapshot)
    local key = string.format("restore_safety_%d_%d", userId, os.time())
    local payload = {
        key            = key,
        targetUserId   = userId,
        adminUserId    = adminPlayer.UserId,
        adminUsername  = adminPlayer.Name,
        sourceBackupId = sourceBackupId,
        timestamp      = os.time(),
        previousData   = snapshot,
    }
    local ok, err = trySet(restoreSafetyDS, key, payload)
    if not ok then
        warn("[PlayerDataAdminService] restore-safety write FAILED for " .. userId .. ": " .. tostring(err))
        return false, nil
    end
    return true, key
end

function PlayerDataAdminService:RestoreUserDataBackup(adminPlayer, backupId)
    local ok, err = assertDev(adminPlayer)
    if not ok then return { success = false, error = err } end

    if type(backupId) ~= "string" or #backupId == 0 or #backupId > 80 then
        return { success = false, error = "Invalid backupId" }
    end

    -- 1. Load and validate the backup
    local gotOk, rec = tryGet(backupDS, backupId)
    if not gotOk or type(rec) ~= "table" then
        return { success = false, error = "Backup not found" }
    end
    if rec.restored == true then
        return { success = false, error = "Backup has already been restored" }
    end
    if type(rec.previousData) ~= "table" then
        return { success = false, error = "Backup has no previousData" }
    end
    local userId = tonumber(rec.targetUserId)
    if not userId or userId <= 0 then
        return { success = false, error = "Backup has no valid targetUserId" }
    end

    print(string.format("[AdminRestore] Loaded backup for userId=%d backupId=%s resetType=%s",
        userId, tostring(backupId), tostring(rec.resetType)))

    -- Determine which subsystems to restore. Mirror the original reset:
    -- only touch subsystems that the original reset wiped, so currency-only
    -- restores stay currency-only and avoid the kick fallback.
    local resetType = rec.resetType
    local subsystems = resetType and RESET_GROUPS[resetType] or nil
    if not subsystems then
        -- Unknown reset type (legacy backup): fall back to every subsystem
        -- that has a non-nil previousData entry.
        subsystems = {}
        for sub in pairs(DATASTORES) do
            if rec.previousData[sub] ~= nil then table.insert(subsystems, sub) end
        end
    end

    -- Deep-copy previousData so live updates / DataStore writes never share
    -- references with the backup record table.
    local restoredData = deepCopy(rec.previousData)

    -- 2. Snapshot current state and write it as a restore-safety backup.
    local currentSnapshot = readAll(userId)
    local safetyOk, safetyKey = writeRestoreSafety(adminPlayer, userId, backupId, currentSnapshot)
    if not safetyOk then
        return { success = false, error = "Aborted: restore-safety backup write failed" }
    end

    -- 3. Apply the previousData ONLY for the subsystems originally reset.
    --    Subsystems whose previous value was nil are removed so the player
    --    gets fresh defaults next join.
    local restored, failed = {}, {}
    for _, sub in ipairs(subsystems) do
        local spec = DATASTORES[sub]
        if spec then
            local key   = string.format(spec.keyFmt, userId)
            local value = restoredData[sub]
            local ds    = dsHandle(spec)
            if value == nil then
                local rok, rerr = tryRemove(ds, key)
                if rok then table.insert(restored, sub .. ":cleared")
                else table.insert(failed, sub .. ":" .. tostring(rerr)) end
            else
                local sok, serr = trySet(ds, key, value)
                if sok then table.insert(restored, sub)
                else table.insert(failed, sub .. ":" .. tostring(serr)) end
            end
        end
    end
    print(string.format("[AdminRestore] Saved restored data to DataStore: %d ok / %d failed",
        #restored, #failed))

    -- 4. Online live-refresh path. Mirrors ResetUserData semantics.
    local online = findOnlinePlayer(userId)
    print(string.format("[AdminRestore] Target player online = %s", tostring(online ~= nil)))
    local liveResult = { liveRefreshedSubsystems = {}, needsRejoin = false }
    local kicked = false
    local liveApplied = false
    if online then
        print("[AdminRestore] Applying live refresh")
        liveResult = applyLiveOnlineUpdate(online, subsystems, restoredData)
        if #liveResult.liveRefreshedSubsystems > 0 then
            print("[AdminRestore] Updated currency values: " .. table.concat(liveResult.liveRefreshedSubsystems, ", "))
        end

        if liveResult.needsRejoin then
            -- Some non-currency subsystem changed; in-memory state would
            -- clobber the restored DataStore key on PlayerRemoving's save.
            -- Match the reset path and kick to guarantee a clean reload.
            task.delay(1.0, function()
                if online and online.Parent then
                    online:Kick("Your saved data was restored by an administrator. Please rejoin.")
                end
            end)
            kicked = true
        else
            liveApplied = true
        end
    end

    -- 5. Mark the backup record as restored (best-effort; non-fatal on failure).
    local markOk = false
    pcall(function()
        backupDS:UpdateAsync(backupId, function(old)
            if type(old) ~= "table" then return old end
            old.restored           = true
            old.restoredByUserId   = adminPlayer.UserId
            old.restoredByUsername = adminPlayer.Name
            old.restoredAt         = os.time()
            return old
        end)
        markOk = true
    end)
    if not markOk then
        warn("[PlayerDataAdminService] failed to mark backup " .. backupId .. " restored")
    end

    -- 6. Audit
    logAudit(adminPlayer, userId, "Restore_" .. tostring(rec.resetType or "?"),
        string.format("backupId=%s restored=%d failed=%d safety=%s online=%s liveApplied=%s kicked=%s",
            backupId, #restored, #failed, tostring(safetyKey),
            tostring(online ~= nil), tostring(liveApplied), tostring(kicked)))

    print(string.format("[AdminRestore] Restore complete liveApplied = %s", tostring(liveApplied)))

    local message
    if not online then
        message = "Backup restored. Player is offline and will receive restored data next time they join."
    elseif liveApplied then
        message = "Backup restored and live refreshed."
    elseif kicked then
        message = "Backup restored. Player was kicked so the restored data can take effect."
    else
        message = "Backup saved, but live refresh failed. Player may need to rejoin."
    end

    return {
        success           = true,
        backupId          = backupId,
        userId            = userId,
        restored          = restored,
        failed            = failed,
        safetyBackupKey   = safetyKey,
        wasOnline         = online ~= nil,
        kicked            = kicked,
        liveApplied       = liveApplied,
        liveRefreshed     = liveResult.liveRefreshedSubsystems,
        markedRestored    = markOk,
        message           = message,
    }
end

return PlayerDataAdminService
