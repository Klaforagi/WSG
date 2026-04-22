--------------------------------------------------------------------------------
-- AdminAuditService.lua  –  Logs admin actions to DataStore
--
-- DataStore: "AdminAuditLog_v1"
-- Key pattern: "AuditLog_<page>" (pages of up to 50 entries each)
-- Counter key: "AuditLogCounter" (tracks total entries + current page)
--
-- Each entry:
--   Action, AdminUserId, AdminUsername, TargetUserId, TargetUsername,
--   WeaponId, WeaponName, SizePercent, Enchant, Timestamp
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")

local DATASTORE_NAME   = "AdminAuditLog_v1"
local ENTRIES_PER_PAGE = 50
local RETRIES          = 3
local RETRY_DELAY      = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local AdminAuditService = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function retryUpdate(key, transformFunc)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:UpdateAsync(key, transformFunc)
        end)
        if success then return true end
        warn("[AdminAuditService] UpdateAsync failed (" .. key .. ", attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    return false, err
end

local function retryGet(key)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then return true, result end
        warn("[AdminAuditService] GetAsync failed (" .. key .. ", attempt " .. i .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    return false, result
end

--------------------------------------------------------------------------------
-- LOG AN ADMIN ACTION
--------------------------------------------------------------------------------
function AdminAuditService:LogAction(entry)
    if not entry then return false, "No entry provided" end

    local logEntry = {
        Action          = entry.Action or "Unknown",
        AdminUserId     = entry.AdminUserId,
        AdminUsername    = entry.AdminUsername or "Unknown",
        TargetUserId    = entry.TargetUserId,
        TargetUsername   = entry.TargetUsername or "Unknown",
        WeaponId        = entry.WeaponId or "",
        WeaponName      = entry.WeaponName or "",
        SizePercent     = entry.SizePercent or 100,
        Enchant         = entry.Enchant or "",
        Timestamp       = os.time(),
    }

    -- Append to the current audit page using UpdateAsync for atomicity
    local ok, err = retryUpdate("AuditLogCurrent", function(old)
        local page = old or { entries = {}, pageNum = 1 }
        if not page.entries then
            page.entries = {}
        end
        if not page.pageNum then
            page.pageNum = 1
        end

        table.insert(page.entries, logEntry)

        -- If page is full, we'll archive it on next write
        if #page.entries >= ENTRIES_PER_PAGE then
            -- We'll handle archival in a separate step
            page.needsArchive = true
        end

        return page
    end)

    if not ok then
        warn("[AdminAuditService] Failed to log action: " .. tostring(err))
        return false, "DataStore write failed"
    end

    -- Archive if needed (non-critical, best-effort)
    task.spawn(function()
        self:_TryArchive()
    end)

    return true
end

--------------------------------------------------------------------------------
-- ARCHIVE (moves full page to numbered key, starts fresh current page)
--------------------------------------------------------------------------------
function AdminAuditService:_TryArchive()
    local ok, current = retryGet("AuditLogCurrent")
    if not ok or not current or not current.needsArchive then return end

    local pageNum = current.pageNum or 1
    local archiveKey = "AuditLog_" .. tostring(pageNum)

    -- Write archive page
    local archiveOk = pcall(function()
        ds:SetAsync(archiveKey, current.entries)
    end)

    if archiveOk then
        -- Reset current page
        retryUpdate("AuditLogCurrent", function()
            return { entries = {}, pageNum = pageNum + 1 }
        end)
    end
end

--------------------------------------------------------------------------------
-- READ RECENT ENTRIES (returns up to `limit` most recent entries)
--------------------------------------------------------------------------------
function AdminAuditService:GetRecentEntries(limit)
    limit = limit or 20

    local ok, current = retryGet("AuditLogCurrent")
    if not ok or not current or not current.entries then
        return {}
    end

    local entries = current.entries
    local results = {}

    -- Return most recent entries (from end of array)
    local start = math.max(1, #entries - limit + 1)
    for i = #entries, start, -1 do
        table.insert(results, entries[i])
    end

    return results
end

return AdminAuditService
