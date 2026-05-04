local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreConfig = require(ServerScriptService:WaitForChild("DataStoreConfig"))

local DataStoreOps = {}

local function debugLog(...)
    if DataStoreConfig.DebugLogs then
        print(...)
    end
end

function DataStoreOps.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = DataStoreOps.DeepCopy(nestedValue)
    end
    return copy
end

function DataStoreOps.DeepEqual(left, right)
    if left == right then
        return true
    end
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return false
    end

    for key, value in pairs(left) do
        if not DataStoreOps.DeepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

function DataStoreOps.CountEntries(value)
    if type(value) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(value) do
        count += 1
    end
    return count
end

function DataStoreOps.IsStudio()
    return RunService:IsStudio()
end

function DataStoreOps.WaitForBudget(requestType, label)
    local warned = false
    while true do
        local ok, budget = pcall(function()
            return DataStoreService:GetRequestBudgetForRequestType(requestType)
        end)
        if not ok or budget > (DataStoreConfig.MinimumBudgetThreshold or 0) then
            return true
        end

        if not warned then
            warned = true
            warn(string.format("[DataStore] waiting for budget | request=%s | label=%s", tostring(requestType), tostring(label)))
        end
        task.wait(DataStoreConfig.BudgetPollIntervalSeconds or 0.25)
    end
end

local function getRetryDelay(attempt)
    local backoff = DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }
    return backoff[attempt] or backoff[#backoff] or 1
end

function DataStoreOps.Load(store, key, label, callback)
    if store == nil then
        return false, nil, "missing datastore"
    end

    local lastError = nil
    local maxAttempts = #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 })
    for attempt = 1, maxAttempts do
        DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.GetAsync, label)

        local ok, result = pcall(function()
            if callback then
                return callback()
            end
            return store:GetAsync(key)
        end)
        if ok then
            debugLog(string.format("[DataStore] load success | label=%s | attempt=%d", tostring(label), attempt))
            return true, result, nil
        end

        lastError = result
        warn(string.format("[DataStore] load failed attempt %d | label=%s | error=%s", attempt, tostring(label), tostring(result)))
        if attempt < maxAttempts then
            task.wait(getRetryDelay(attempt))
        end
    end

    return false, nil, lastError
end

function DataStoreOps.Update(store, key, label, transformFunc)
    if store == nil then
        return false, nil, "missing datastore"
    end

    local lastError = nil
    local maxAttempts = #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 })
    for attempt = 1, maxAttempts do
        DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.UpdateAsync, label)

        local ok, result = pcall(function()
            return store:UpdateAsync(key, function(oldData)
                return transformFunc(DataStoreOps.DeepCopy(oldData))
            end)
        end)
        if ok then
            debugLog(string.format("[DataStore] update success | label=%s | attempt=%d", tostring(label), attempt))
            return true, result, nil
        end

        lastError = result
        warn(string.format("[DataStore] update failed attempt %d | label=%s | error=%s", attempt, tostring(label), tostring(result)))
        if attempt < maxAttempts then
            task.wait(getRetryDelay(attempt))
        end
    end

    return false, nil, lastError
end

return DataStoreOps