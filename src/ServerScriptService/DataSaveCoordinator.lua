local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreConfig = require(ServerScriptService:WaitForChild("DataStoreConfig"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DataSaveCoordinator = {}

local registeredSections = {}
local orderedSectionNames = {}
local profilesByUserId = {}
local activeWrites = 0
local shutdownStarted = false

local function logInfo(...)
    if DataStoreConfig.DebugLogs then
        print(...)
    end
end

local function getUserIdKey(player)
    if typeof(player) == "Instance" and player:IsA("Player") then
        return tostring(player.UserId)
    end
    return tostring(player)
end

local function ensureProfile(player)
    local userId = getUserIdKey(player)
    local profile = profilesByUserId[userId]
    if profile then
        if typeof(player) == "Instance" and player:IsA("Player") then
            profile.Player = player
        end
        return profile
    end

    profile = {
        UserId = userId,
        Player = player,
        SectionStatus = {},
        LastLoadedData = {},
        LastSavedData = {},
        DirtySections = {},
        PendingSave = nil,
        SaveScheduled = false,
        SaveInProgress = false,
        LastSaveSucceeded = true,
        LoadedSuccessfully = false,
        CanSave = false,
        IsNewPlayer = false,
        LoadFailed = false,
        CleanupCompleted = false,
    }
    profilesByUserId[userId] = profile
    return profile
end

local function recomputeProfileFlags(profile)
    local anyLoaded = false
    local anyExisting = false
    local anyNew = false
    local anyCriticalFailure = false

    for sectionName, status in pairs(profile.SectionStatus) do
        local definition = registeredSections[sectionName]
        local isCritical = definition == nil or definition.Critical ~= false
        if status == "existing" or status == "new" then
            anyLoaded = true
        end
        if status == "existing" then
            anyExisting = true
        elseif status == "new" then
            anyNew = true
        elseif status == "failed" and isCritical then
            anyCriticalFailure = true
        end
    end

    profile.LoadFailed = anyCriticalFailure
    profile.LoadedSuccessfully = anyLoaded and not anyCriticalFailure
    profile.CanSave = profile.LoadedSuccessfully and not profile.LoadFailed
    profile.IsNewPlayer = anyLoaded and anyNew and not anyExisting and not anyCriticalFailure
end

local function sortSections()
    table.sort(orderedSectionNames, function(leftName, rightName)
        local left = registeredSections[leftName]
        local right = registeredSections[rightName]
        local leftPriority = left and left.Priority or 100
        local rightPriority = right and right.Priority or 100
        if leftPriority == rightPriority then
            return leftName < rightName
        end
        return leftPriority < rightPriority
    end)
end

local function acquireWriteSlot()
    while activeWrites >= (DataStoreConfig.MaxConcurrentWrites or 2) do
        task.wait(0.1)
    end
    activeWrites += 1
end

local function releaseWriteSlot()
    activeWrites = math.max(0, activeWrites - 1)
end

local function canSaveProfile(profile)
    if not profile then
        return false, "missing profile"
    end
    if profile.LoadFailed then
        return false, "LoadFailed flag set"
    end
    if not profile.LoadedSuccessfully then
        return false, "LoadedSuccessfully flag is false"
    end
    if not profile.CanSave then
        return false, "CanSave flag is false"
    end
    return true, nil
end

local function normalizeLoadResult(result)
    if type(result) ~= "table" then
        return {
            status = "failed",
            data = nil,
            reason = "invalid load result",
        }
    end

    local status = result.status
    if status ~= "existing" and status ~= "new" and status ~= "failed" then
        status = "failed"
    end

    return {
        status = status,
        data = result.data,
        reason = result.reason,
        markDirty = result.markDirty == true,
    }
end

local function collectSectionSnapshots(profile, player)
    local changedSections = {}
    local suspiciousSections = {}
    local unchangedCount = 0

    for _, sectionName in ipairs(orderedSectionNames) do
        local definition = registeredSections[sectionName]
        if definition and definition.GetSaveData then
            local currentData = definition.GetSaveData(player, profile)
            local lastGoodData = profile.LastSavedData[sectionName] or profile.LastLoadedData[sectionName]
            local hasChanged = not DataStoreOps.DeepEqual(currentData, lastGoodData)

            if hasChanged then
                local validation = nil
                if definition.Validate then
                    validation = definition.Validate(player, currentData, lastGoodData, profile)
                end
                if type(validation) == "table" and validation.suspicious then
                    suspiciousSections[sectionName] = validation
                end
                changedSections[sectionName] = {
                    currentData = currentData,
                    lastGoodData = lastGoodData,
                }
            else
                unchangedCount += 1
            end
        end
    end

    return changedSections, suspiciousSections, unchangedCount
end

local function shouldBlockSuspiciousSave(suspiciousSections)
    local suspiciousCount = 0
    for _, validation in pairs(suspiciousSections) do
        suspiciousCount += 1
        if validation.severity == "severe" then
            return true, validation.reason
        end
    end

    if suspiciousCount >= (DataStoreConfig.SuspiciousSectionThreshold or 2) then
        return true, string.format("%d sections look like a wipe", suspiciousCount)
    end

    return false, nil
end

function DataSaveCoordinator:RegisterSection(definition)
    if type(definition) ~= "table" then
        error("DataSaveCoordinator:RegisterSection expects a table")
    end
    if type(definition.Name) ~= "string" or definition.Name == "" then
        error("DataSaveCoordinator:RegisterSection requires Name")
    end

    registeredSections[definition.Name] = definition
    local alreadyInserted = false
    for _, sectionName in ipairs(orderedSectionNames) do
        if sectionName == definition.Name then
            alreadyInserted = true
            break
        end
    end
    if not alreadyInserted then
        table.insert(orderedSectionNames, definition.Name)
        sortSections()
    end
end

function DataSaveCoordinator:GetProfile(player)
    return ensureProfile(player)
end

function DataSaveCoordinator:LoadSection(player, sectionName)
    local definition = registeredSections[sectionName]
    if not definition or not definition.Load then
        warn(string.format("[DataStore] load skipped, section not registered: %s", tostring(sectionName)))
        return nil
    end

    if RunService:IsStudio() and DataStoreConfig.LoadInStudio == false then
        warn(string.format("[DataStore] Studio load skipped | section=%s | player=%s", sectionName, tostring(player and player.Name)))
        return nil
    end

    local profile = ensureProfile(player)
    logInfo(string.format("[DataStore] profile load started | player=%s | section=%s", tostring(player and player.Name), sectionName))
    local rawResult = definition.Load(player, profile)
    local loadResult = normalizeLoadResult(rawResult)
    profile.SectionStatus[sectionName] = loadResult.status

    if loadResult.status == "existing" or loadResult.status == "new" then
        profile.LastLoadedData[sectionName] = DataStoreOps.DeepCopy(loadResult.data)
        profile.LastSavedData[sectionName] = DataStoreOps.DeepCopy(loadResult.data)
        if loadResult.markDirty then
            profile.DirtySections[sectionName] = true
        end
        if loadResult.status == "new" then
            logInfo(string.format("[DataStore] true new player default created | player=%s | section=%s", tostring(player and player.Name), sectionName))
        else
            logInfo(string.format("[DataStore] profile load success | player=%s | section=%s", tostring(player and player.Name), sectionName))
        end
    else
        warn(string.format("[DataStore] load failed, saves blocked | player=%s | section=%s | reason=%s", tostring(player and player.Name), sectionName, tostring(loadResult.reason)))
    end

    recomputeProfileFlags(profile)
    return loadResult
end

function DataSaveCoordinator:MarkDirty(player, sectionName, reason, options)
    local definition = registeredSections[sectionName]
    if not definition then
        return false
    end

    local profile = ensureProfile(player)
    profile.DirtySections[sectionName] = true

    if shutdownStarted then
        return true
    end
    if RunService:IsStudio() and DataStoreConfig.SaveInStudio == false then
        return true
    end

    options = options or {}
    local debounce = options.delaySeconds
    if type(debounce) ~= "number" then
        debounce = DataStoreConfig.SaveDebounceSeconds or 15
    end

    if profile.PendingSave then
        profile.PendingSave.reason = tostring(reason or profile.PendingSave.reason or "dirty")
        profile.PendingSave.force = profile.PendingSave.force or options.force == true
        logInfo(string.format("[DataStore] save merged/debounced | player=%s | section=%s | reason=%s", tostring(player and player.Name), sectionName, tostring(reason)))
    else
        profile.PendingSave = {
            reason = tostring(reason or "dirty"),
            force = options.force == true,
            final = options.final == true,
            cleanupAfterSave = options.cleanupAfterSave == true,
        }
        logInfo(string.format("[DataStore] save queued | player=%s | section=%s | reason=%s", tostring(player and player.Name), sectionName, tostring(reason)))
    end

    if profile.SaveScheduled or profile.SaveInProgress then
        return true
    end

    profile.SaveScheduled = true
    task.delay(debounce, function()
        profile.SaveScheduled = false
        if profile.PendingSave and profile.Player and profile.Player.Parent then
            task.spawn(function()
                self:FlushPlayer(profile.Player)
            end)
        end
    end)

    return true
end

function DataSaveCoordinator:FlushPlayer(player)
    local profile = ensureProfile(player)
    if profile.SaveInProgress then
        while profile.SaveInProgress do
            task.wait(0.05)
        end
        return profile.LastSaveSucceeded
    end

    local pending = profile.PendingSave
    if not pending then
        return true
    end

    profile.PendingSave = nil
    profile.SaveInProgress = true
    acquireWriteSlot()

    local allowed, blockedReason = canSaveProfile(profile)
    if not allowed then
        warn(string.format("[DataStore] save blocked because profile did not load safely | player=%s | reason=%s", tostring(player and player.Name), tostring(blockedReason)))
        releaseWriteSlot()
        profile.SaveInProgress = false
        profile.LastSaveSucceeded = false
        return false
    end

    if RunService:IsStudio() and DataStoreConfig.SaveInStudio == false then
        warn(string.format("[DataStore] Studio save skipped | player=%s", tostring(player and player.Name)))
        releaseWriteSlot()
        profile.SaveInProgress = false
        profile.LastSaveSucceeded = true
        return true
    end

    local changedSections, suspiciousSections, unchangedCount = collectSectionSnapshots(profile, player)
    local shouldBlock, suspiciousReason = shouldBlockSuspiciousSave(suspiciousSections)
    if shouldBlock then
        warn(string.format("[DataStore] save blocked because suspected data wipe | player=%s | reason=%s", tostring(player and player.Name), tostring(suspiciousReason)))
        releaseWriteSlot()
        profile.SaveInProgress = false
        profile.LastSaveSucceeded = false
        return false
    end

    local changedSectionCount = 0
    for _ in pairs(changedSections) do
        changedSectionCount += 1
    end
    if changedSectionCount == 0 then
        logInfo(string.format("[DataStore] save skipped because unchanged | player=%s | unchanged=%d", tostring(player and player.Name), unchangedCount))
        releaseWriteSlot()
        profile.SaveInProgress = false
        profile.LastSaveSucceeded = true
        return true
    end

    local allSucceeded = true
    for _, sectionName in ipairs(orderedSectionNames) do
        local sectionChange = changedSections[sectionName]
        local definition = registeredSections[sectionName]
        if sectionChange and definition and definition.Save then
            local ok, err = definition.Save(player, sectionChange.currentData, sectionChange.lastGoodData, profile, pending)
            if ok then
                profile.LastLoadedData[sectionName] = DataStoreOps.DeepCopy(sectionChange.currentData)
                profile.LastSavedData[sectionName] = DataStoreOps.DeepCopy(sectionChange.currentData)
                profile.DirtySections[sectionName] = nil
                logInfo(string.format("[DataStore] save success | player=%s | section=%s", tostring(player and player.Name), sectionName))
            else
                allSucceeded = false
                warn(string.format("[DataStore] save failed after retries | player=%s | section=%s | error=%s", tostring(player and player.Name), sectionName, tostring(err)))
            end
        end
    end

    releaseWriteSlot()
    profile.SaveInProgress = false
    profile.LastSaveSucceeded = allSucceeded
    if pending.cleanupAfterSave then
        self:CleanupPlayer(player)
    end

    if profile.PendingSave and player and player.Parent then
        task.spawn(function()
            self:FlushPlayer(player)
        end)
    end

    return allSucceeded
end

function DataSaveCoordinator:RequestImmediateSave(player, reason, options)
    local profile = ensureProfile(player)
    profile.PendingSave = {
        reason = tostring(reason or "manual"),
        force = options and options.force == true,
        final = options and options.final == true,
        cleanupAfterSave = options and options.cleanupAfterSave == true,
    }
    return self:FlushPlayer(player)
end

function DataSaveCoordinator:CleanupPlayer(player)
    local profile = ensureProfile(player)
    if profile.CleanupCompleted then
        return
    end
    profile.CleanupCompleted = true

    for _, sectionName in ipairs(orderedSectionNames) do
        local definition = registeredSections[sectionName]
        if definition and definition.Cleanup then
            local ok, err = pcall(function()
                definition.Cleanup(player, profile)
            end)
            if not ok then
                warn(string.format("[DataStore] cleanup failed | player=%s | section=%s | error=%s", tostring(player and player.Name), sectionName, tostring(err)))
            end
        end
    end

    profilesByUserId[profile.UserId] = nil
end

function DataSaveCoordinator:HandlePlayerRemoving(player)
    local profile = ensureProfile(player)
    if profile.SaveInProgress then
        while profile.SaveInProgress do
            task.wait(0.05)
        end
    end

    self:RequestImmediateSave(player, "PlayerRemoving", {
        force = true,
        final = true,
        cleanupAfterSave = true,
    })
end

function DataSaveCoordinator:BeginShutdown()
    shutdownStarted = true
end

function DataSaveCoordinator:HandleShutdown()
    if shutdownStarted == false then
        self:BeginShutdown()
    end

    local startedAt = os.clock()
    for index, player in ipairs(Players:GetPlayers()) do
        if (os.clock() - startedAt) > (DataStoreConfig.ShutdownTimeoutSeconds or 20) then
            warn("[DataStore] shutdown save timed out before all players were processed")
            break
        end

        self:RequestImmediateSave(player, "BindToClose", {
            force = true,
            final = true,
            cleanupAfterSave = true,
        })
        if index < #Players:GetPlayers() then
            task.wait(DataStoreConfig.ShutdownSaveSpacingSeconds or 0.2)
        end
    end
end

return DataSaveCoordinator