-- LeaderboardEverythingService.lua
-- Shared backend for the selectable world leaderboard.  Lifetime values are
-- mirrored to permanent OrderedDataStores; weekly/monthly values use a store
-- name containing the current Eastern-time period key, so old periods never
-- bleed into a new board.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CareerStatsService = require(ServerScriptService:WaitForChild("CareerStatsService"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))

local LeaderboardEverythingService = {}

-- OrderedDataStore names have a strict maximum length.  Keep these machine
-- identifiers compact; the player-facing labels remain in STATS below.
local STORE_PREFIX = "LEB1"
local MAX_ENTRIES = 50
local SYNC_DEBOUNCE_SECONDS = 12
-- A cold OrderedDataStore read can take several seconds. Keep a shared cache
-- warm long enough for players to reach the board, then refresh stale entries
-- in the background rather than making the viewer wait.
local CACHE_SECONDS = 120
local FRIEND_CACHE_SECONDS = 60
local WARM_REQUEST_DELAY_SECONDS = 0.1

local STATS = {
    Eliminations = { careerKey = "PlayersEliminated", label = "ELIMINATIONS" },
    Wins = { careerKey = "Wins", label = "WINS" },
    MVPs = { careerKey = "MVPs", label = "MVPS" },
    Coins = { careerKey = "TotalCoinsEarned", label = "COINS" },
    Captures = { careerKey = "FlagCaptures", label = "CAPTURES" },
    Returns = { careerKey = "FlagReturns", label = "RETURNS" },
    AP = { careerKey = "AchievementPoints", label = "AP", allTimeOnly = true },
    Playtime = { careerKey = "TotalPlaytimeSeconds", label = "PLAYTIME", allTimeOnly = true },
}

local STORE_STAT_CODES = {
    Eliminations = "E",
    Wins = "W",
    MVPs = "V",
    Coins = "C",
    Captures = "P",
    Returns = "R",
    AP = "A",
    Playtime = "T",
}

local STORE_PERIOD_CODES = {
    Weekly = "W",
    Monthly = "M",
    AllTime = "A",
}

local statIdByCareerKey = {}
for statId, config in pairs(STATS) do
    statIdByCareerKey[config.careerKey] = statId
end

local started = false
local pendingSyncs = {}
local queryCache = {}
local identityCache = {}
local friendIdCache = {}
local friendEntriesCache = {}
local queryInFlight = {}
local globalCacheWarmInProgress = false
local refreshEntriesInBackground

local function clamp(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function getPeriodKey(period)
    if period == "Weekly" then
        return TimeHelper.GetWeeklyKey()
    elseif period == "Monthly" then
        return TimeHelper.GetMonthlyKey()
    end
    return "AllTime"
end

local function getStoreName(period, statId)
    local periodCode = STORE_PERIOD_CODES[period] or STORE_PERIOD_CODES.AllTime
    local statCode = STORE_STAT_CODES[statId] or STORE_STAT_CODES.Eliminations
    if periodCode == "A" then
        return string.format("%s_%s_%s", STORE_PREFIX, periodCode, statCode)
    end
    return string.format("%s_%s_%s_%s", STORE_PREFIX, periodCode, getPeriodKey(period), statCode)
end

local function getResetTimestamp(period)
    if period == "Weekly" then
        return os.time() + TimeHelper.SecondsUntilNextWeeklyReset()
    elseif period == "Monthly" then
        return os.time() + TimeHelper.SecondsUntilNextMonthlyReset()
    end
    return nil
end

local function getAchievementPoints(player)
    local achievementService = ServerScriptService:FindFirstChild("AchievementService")
    if not achievementService then
        return 0
    end
    local ok, service = pcall(require, achievementService)
    if not ok or not service or not service.GetAchievementPoints then
        return 0
    end
    local success, points = pcall(function()
        return service:GetAchievementPoints(player)
    end)
    return success and clamp(points) or 0
end

local function getPlayerValue(player, period, statId)
    local config = STATS[statId]
    if not config then
        return 0
    end
    if statId == "AP" then
        return getAchievementPoints(player)
    end

    local stats
    if period == "AllTime" then
        stats = CareerStatsService:GetCareerStats(player)
    else
        stats = CareerStatsService:GetPeriodStats(player, period)
    end
    return clamp(type(stats) == "table" and stats[config.careerKey] or 0)
end

local function writeValue(player, period, statId)
    if not player or not player:IsA("Player") then
        return
    end
    local config = STATS[statId]
    if not config or (config.allTimeOnly and period ~= "AllTime") then
        return
    end

    local store = DataStoreService:GetOrderedDataStore(getStoreName(period, statId))
    local value = getPlayerValue(player, period, statId)
    local ok, err = pcall(function()
        store:SetAsync(tostring(player.UserId), value)
    end)
    if not ok then
        warn(string.format("[LeaderboardEverything] Could not sync %s/%s for %s: %s", period, statId, player.Name, tostring(err)))
        return
    end
    local cached = queryCache[getStoreName(period, statId)]
    if cached then
        -- Preserve the last complete result for instant reads while the
        -- updated OrderedDataStore page is fetched in the background.
        cached.updatedAt = 0
        if refreshEntriesInBackground then
            refreshEntriesInBackground(period, statId)
        end
    end
end

function LeaderboardEverythingService:SyncPlayer(player, careerStatKey)
    if not player or not player:IsA("Player") then
        return
    end

    local statIds = {}
    local specificStatId = careerStatKey and statIdByCareerKey[careerStatKey]
    if specificStatId then
        statIds[1] = specificStatId
    elseif careerStatKey == "AchievementPoints" then
        statIds[1] = "AP"
    elseif careerStatKey then
        -- Most career stats are not shown by this board (damage, deaths,
        -- quest count, etc.), so they should not trigger an unnecessary full
        -- OrderedDataStore sync.
        return
    else
        for statId in pairs(STATS) do
            table.insert(statIds, statId)
        end
    end

    for _, statId in ipairs(statIds) do
        writeValue(player, "AllTime", statId)
        if not STATS[statId].allTimeOnly then
            writeValue(player, "Weekly", statId)
            writeValue(player, "Monthly", statId)
        end
    end
end

local function scheduleSync(player, careerStatKey)
    if not player or not player:IsA("Player") then
        return
    end
    local state = pendingSyncs[player]
    if not state then
        state = { all = false, stats = {} }
        pendingSyncs[player] = state
        task.delay(SYNC_DEBOUNCE_SECONDS, function()
            local pending = pendingSyncs[player]
            pendingSyncs[player] = nil
            if not pending or not player.Parent then
                return
            end
            if pending.all then
                LeaderboardEverythingService:SyncPlayer(player)
            else
                for statKey in pairs(pending.stats) do
                    LeaderboardEverythingService:SyncPlayer(player, statKey)
                end
            end
        end)
    end
    if careerStatKey then
        state.stats[careerStatKey] = true
    else
        state.all = true
    end
end

local function resolveName(userId)
    local cached = identityCache[userId]
    if cached then
        return cached
    end
    local player = Players:GetPlayerByUserId(userId)
    if player then
        identityCache[userId] = player.Name
        return player.Name
    end
    local name = "Unknown"
    local ok, result = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    if ok and type(result) == "string" and result ~= "" then
        name = result
    end
    identityCache[userId] = name
    return name
end

local function loadEntries(period, statId)
    local storeName = getStoreName(period, statId)
    local store = DataStoreService:GetOrderedDataStore(storeName)
    DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.GetSortedAsync, "LeaderboardEverything/" .. storeName)
    local ok, pagesOrError = pcall(function()
        return store:GetSortedAsync(false, MAX_ENTRIES)
    end)
    if not ok then
        warn("[LeaderboardEverything] Could not fetch " .. storeName .. ": " .. tostring(pagesOrError))
        return nil, false
    end

    local entries = {}
    for rank, entry in ipairs(pagesOrError:GetCurrentPage()) do
        local userId = tonumber(entry.key)
        if userId then
            table.insert(entries, {
                rank = rank,
                userId = userId,
                name = resolveName(userId),
                value = clamp(entry.value),
            })
        end
    end
    return entries, true
end

refreshEntriesInBackground = function(period, statId)
    local storeName = getStoreName(period, statId)
    if queryInFlight[storeName] then
        return
    end
    queryInFlight[storeName] = true
    task.spawn(function()
        local entries, success = loadEntries(period, statId)
        if success then
            queryCache[storeName] = { updatedAt = os.clock(), entries = entries }
        end
        queryInFlight[storeName] = nil
    end)
end

local function fetchEntries(period, statId)
    local storeName = getStoreName(period, statId)
    local cached = queryCache[storeName]
    if cached then
        if (os.clock() - cached.updatedAt) >= CACHE_SECONDS then
            refreshEntriesInBackground(period, statId)
        end
        return cached.entries
    end

    -- If the loading-screen warmup already owns this store, share its result
    -- instead of starting a duplicate OrderedDataStore request.
    while queryInFlight[storeName] do
        task.wait()
    end
    cached = queryCache[storeName]
    if cached then
        return cached.entries
    end

    queryInFlight[storeName] = true
    local entries, success = loadEntries(period, statId)
    queryInFlight[storeName] = nil
    if success then
        queryCache[storeName] = { updatedAt = os.clock(), entries = entries }
        return entries
    end
    return {}
end

local function rankEntries(entries)
    table.sort(entries, function(a, b)
        if a.value == b.value then
            return a.userId < b.userId
        end
        return a.value > b.value
    end)
    while #entries > MAX_ENTRIES do
        table.remove(entries)
    end
    for rank, entry in ipairs(entries) do
        entry.rank = rank
    end
    return entries
end

local function fetchServerEntries(period, statId)
    local entries = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(entries, {
            userId = player.UserId,
            name = player.Name,
            value = getPlayerValue(player, period, statId),
        })
    end
    return rankEntries(entries)
end

local function getFriendIds(player)
    local cached = friendIdCache[player.UserId]
    if cached and cached.expiresAt > os.clock() then
        return cached.ids
    end

    local ids = { player.UserId }
    local seen = { [player.UserId] = true }
    local ok, pagesOrError = pcall(function()
        return Players:GetFriendsAsync(player.UserId)
    end)
    if ok and pagesOrError then
        local pages = pagesOrError
        while true do
            for _, friendInfo in ipairs(pages:GetCurrentPage()) do
                local userId = tonumber(friendInfo.Id or friendInfo.UserId)
                if userId and not seen[userId] then
                    seen[userId] = true
                    table.insert(ids, userId)
                end
            end
            if pages.IsFinished then
                break
            end
            local advanced = pcall(function()
                pages:AdvanceToNextPageAsync()
            end)
            if not advanced then
                break
            end
        end
    else
        warn("[LeaderboardEverything] Could not load friends for " .. player.Name .. ": " .. tostring(pagesOrError))
    end
    friendIdCache[player.UserId] = { ids = ids, expiresAt = os.clock() + FRIEND_CACHE_SECONDS }
    return ids
end

local function fetchFriendEntries(viewer, period, statId)
    local cacheKey = string.format("%d:%s:%s:%s", viewer.UserId, period, statId, getPeriodKey(period))
    local cached = friendEntriesCache[cacheKey]
    if cached and cached.expiresAt > os.clock() then
        return cached.entries
    end

    local store = DataStoreService:GetOrderedDataStore(getStoreName(period, statId))
    local entries = {}
    for _, userId in ipairs(getFriendIds(viewer)) do
        local value = 0
        local onlinePlayer = Players:GetPlayerByUserId(userId)
        if onlinePlayer then
            value = getPlayerValue(onlinePlayer, period, statId)
        else
            local ok, storedValue = pcall(function()
                return store:GetAsync(tostring(userId))
            end)
            if ok then
                value = clamp(storedValue)
            end
        end
        table.insert(entries, {
            userId = userId,
            name = resolveName(userId),
            value = value,
        })
    end
    entries = rankEntries(entries)
    friendEntriesCache[cacheKey] = { entries = entries, expiresAt = os.clock() + FRIEND_CACHE_SECONDS }
    return entries
end

function LeaderboardEverythingService:GetBoard(viewer, period, statId, scope)
    period = (period == "Weekly" or period == "Monthly" or period == "AllTime") and period or "Weekly"
    statId = STATS[statId] and statId or "Eliminations"
    scope = (scope == "Server" or scope == "Friends" or scope == "Global") and scope or "Global"
    if STATS[statId].allTimeOnly then
        period = "AllTime"
    end

    local entries
    if scope == "Server" then
        entries = fetchServerEntries(period, statId)
    elseif scope == "Friends" and viewer and viewer:IsA("Player") then
        entries = fetchFriendEntries(viewer, period, statId)
    else
        entries = fetchEntries(period, statId)
    end

    return {
        period = period,
        stat = statId,
        scope = scope,
        label = STATS[statId].label,
        resetAt = getResetTimestamp(period),
        entries = entries,
    }
end

-- Warm Global boards in the order players encounter them: Weekly first
-- (the default), then Monthly and All-Time. Server reads are in-memory, while
-- Friends data remains a per-player, on-demand query.
function LeaderboardEverythingService:WarmGlobalCache()
    if globalCacheWarmInProgress then
        return
    end
    globalCacheWarmInProgress = true

    task.spawn(function()
        local periods = { "Weekly", "Monthly", "AllTime" }
        local statIds = { "Eliminations", "Wins", "MVPs", "Coins", "Captures", "Returns", "AP", "Playtime" }
        for _, period in ipairs(periods) do
            for _, statId in ipairs(statIds) do
                if not (STATS[statId].allTimeOnly and period ~= "AllTime") then
                    fetchEntries(period, statId)
                    task.wait(WARM_REQUEST_DELAY_SECONDS)
                end
            end
        end
        globalCacheWarmInProgress = false
    end)
end

function LeaderboardEverythingService:Start()
    if started then
        return
    end
    started = true

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        remotes = Instance.new("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
    end
    local remote = remotes:FindFirstChild("GetLeaderboardEverything")
    if remote and not remote:IsA("RemoteFunction") then
        remote:Destroy()
        remote = nil
    end
    if not remote then
        remote = Instance.new("RemoteFunction")
        remote.Name = "GetLeaderboardEverything"
        remote.Parent = remotes
    end
    remote.OnServerInvoke = function(player, period, statId, scope)
        return self:GetBoard(player, period, statId, scope)
    end

    local warmRemote = remotes:FindFirstChild("WarmLeaderboardEverything")
    if warmRemote and not warmRemote:IsA("RemoteEvent") then
        warmRemote:Destroy()
        warmRemote = nil
    end
    if not warmRemote then
        warmRemote = Instance.new("RemoteEvent")
        warmRemote.Name = "WarmLeaderboardEverything"
        warmRemote.Parent = remotes
    end
    warmRemote.OnServerEvent:Connect(function()
        self:WarmGlobalCache()
    end)

    -- Begin before the first client reaches the world leaderboard.
    self:WarmGlobalCache()

    local changedEvent = ServerScriptService:WaitForChild("CareerStatsChanged")
    changedEvent.Event:Connect(function(player, statKey)
        scheduleSync(player, statKey)
    end)

    Players.PlayerAdded:Connect(function(player)
        task.delay(4, function()
            if player.Parent then
                scheduleSync(player)
            end
        end)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        task.delay(4, function()
            if player.Parent then
                scheduleSync(player)
            end
        end)
    end

    task.spawn(function()
        while true do
            -- Event-driven updates keep active scores current.  This slower
            -- reconciliation catches stats granted by future systems without
            -- spending an OrderedDataStore write for every player each minute.
            task.wait(300)
            for _, player in ipairs(Players:GetPlayers()) do
                scheduleSync(player)
            end
        end
    end)
end

return LeaderboardEverythingService
