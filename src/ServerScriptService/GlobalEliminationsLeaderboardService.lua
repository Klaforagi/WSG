local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local DataStoreConfig = require(ServerScriptService:WaitForChild("DataStoreConfig"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local CareerStatsService = require(ServerScriptService:WaitForChild("CareerStatsService"))
local StatService = require(ServerScriptService:WaitForChild("StatService"))

local GlobalEliminationsLeaderboardService = {}

local ORDERED_STORE_NAME = "GlobalEliminationsLeaderboard"
local LEADERBOARD_MODEL_NAME = "GiantLeaderboardEliminations"
local TITLE_PART_NAME = "Leaderboardtitlescreen"
local LIST_PART_NAME = "Leaderboardscreen"
local TITLE_GUI_NAME = "GlobalEliminationsTitleSurfaceGui"
local LIST_GUI_NAME = "GlobalEliminationsListSurfaceGui"
local TITLE_GUI_FACE = Enum.NormalId.Right
local LIST_GUI_FACE = Enum.NormalId.Right
local TITLE_TEXT = "Top Eliminations"
local VALUE_HEADER_TEXT = "ELIMS"
local EMPTY_STATE_TEXT = "No saved elimination data yet."
local MAX_ROWS = 50
local REFRESH_SECONDS = 300
local MIRROR_DEBOUNCE_SECONDS = 15
local PERIODIC_MIRROR_SECONDS = 180
local IDENTITY_CACHE_TTL_SECONDS = 600

local orderedStore = DataStoreService:GetOrderedDataStore(ORDERED_STORE_NAME)

local started = false
local connectionsByPlayer = {}
local mirrorStateByUserId = {}
local identityCache = {}
local missingModelWarned = false

local TOP_RANK_COLORS = {
    [1] = Color3.fromRGB(245, 198, 76),
    [2] = Color3.fromRGB(192, 202, 216),
    [3] = Color3.fromRGB(201, 136, 90),
}

local DEFAULT_ROW_COLOR = Color3.fromRGB(33, 40, 51)
local DEFAULT_STROKE_COLOR = Color3.fromRGB(74, 88, 106)
local HEADER_TEXT_COLOR = Color3.fromRGB(189, 201, 216)
local BODY_TEXT_COLOR = Color3.fromRGB(240, 244, 248)
local MUTED_TEXT_COLOR = Color3.fromRGB(157, 172, 191)
local PANEL_COLOR = Color3.fromRGB(15, 21, 30)
local PANEL_ACCENT = Color3.fromRGB(255, 86, 86)
local TITLE_TEXT_COLOR = Color3.fromRGB(255, 86, 86)
local TITLE_SIDE_MARGIN = 20
local LIST_SIDE_MARGIN = 36

local HEADER_HEIGHT = 96
local HEADER_TOP = 18
local SCROLL_TOP = 118
local SCROLL_BOTTOM_MARGIN = 28
local ROW_HEIGHT_SCALE = 0.165
local ROW_SPACING = 20

local RANK_COLUMN_SCALE = 0.13
local PLAYER_COLUMN_START = 0.28
local PLAYER_COLUMN_WIDTH = 0.48
local VALUE_COLUMN_WIDTH = 0.15

local function getRetryBackoff(attempt)
    local backoff = DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }
    return backoff[attempt] or backoff[#backoff] or 1
end

local function clampValue(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function isCareerStatsSectionReady(player)
    local profile = DataSaveCoordinator:GetProfile(player)
    local status = profile and profile.SectionStatus and profile.SectionStatus.CareerStats
    return status == "existing" or status == "new"
end

local function getAuthoritativeEliminations(player)
    if not player or not player:IsA("Player") then
        return nil, "missing player"
    end

    -- The authoritative persisted PvP elimination total comes from the
    -- CareerStats section. CareerStatsServiceInit increments PlayersEliminated
    -- only for StatService.Actions.Elimination events.
    local stats = CareerStatsService:GetCareerStats(player)
    if type(stats) == "table" and stats.PlayersEliminated ~= nil then
        return clampValue(stats.PlayersEliminated), "CareerStatsService:GetCareerStats"
    end

    return nil, "unavailable"
end

local function ensureChild(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end

    if not existing then
        existing = Instance.new(className)
        existing.Name = name
        existing.Parent = parent
    end

    return existing
end

local function ensureCorner(parent, _radius)
    local corner = ensureChild(parent, "UICorner", "Corner")
    corner.CornerRadius = UDim.new(0, 0)
    return corner
end

local function ensureStroke(parent, color, thickness, transparency)
    local stroke = ensureChild(parent, "UIStroke", "Stroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency or 0
    return stroke
end

local function ensurePadding(parent, padding)
    local uiPadding = ensureChild(parent, "UIPadding", "Padding")
    uiPadding.PaddingTop = padding
    uiPadding.PaddingBottom = padding
    uiPadding.PaddingLeft = padding
    uiPadding.PaddingRight = padding
    return uiPadding
end

local function ensureTextConstraint(parent, minSize, maxSize)
    local constraint = ensureChild(parent, "UITextSizeConstraint", "TextSizeConstraint")
    constraint.MinTextSize = minSize
    constraint.MaxTextSize = maxSize
    return constraint
end

local function ensureSurfaceGui(part, guiName, pixelsPerStud, face)
    local surfaceGui = ensureChild(part, "SurfaceGui", guiName)
    surfaceGui.Adornee = part
    surfaceGui.Face = face or Enum.NormalId.Front
    surfaceGui.ResetOnSpawn = false
    surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    surfaceGui.PixelsPerStud = pixelsPerStud
    surfaceGui.LightInfluence = 0
    surfaceGui.AlwaysOnTop = false
    surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    surfaceGui.ClipsDescendants = false
    return surfaceGui
end

local function getLeaderboardParts()
    local model = Workspace:FindFirstChild(LEADERBOARD_MODEL_NAME)
    if not model or not model:IsA("Model") then
        if not missingModelWarned then
            missingModelWarned = true
            warn("[GlobalEliminationsLeaderboard] Missing model in Workspace: " .. LEADERBOARD_MODEL_NAME)
        end
        return nil, nil
    end

    missingModelWarned = false
    local titlePart = model:FindFirstChild(TITLE_PART_NAME)
    local listPart = model:FindFirstChild(LIST_PART_NAME)
    if not (titlePart and titlePart:IsA("BasePart")) then
        warn("[GlobalEliminationsLeaderboard] Missing part in model: " .. TITLE_PART_NAME)
        return nil, nil
    end
    if not (listPart and listPart:IsA("BasePart")) then
        warn("[GlobalEliminationsLeaderboard] Missing part in model: " .. LIST_PART_NAME)
        return nil, nil
    end

    return titlePart, listPart
end

local function ensureTitleGui(titlePart)
    local surfaceGui = ensureSurfaceGui(titlePart, TITLE_GUI_NAME, 55, TITLE_GUI_FACE)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = PANEL_COLOR
    root.BackgroundTransparency = 0.18
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, TITLE_SIDE_MARGIN, 0, TITLE_SIDE_MARGIN)
    root.Size = UDim2.new(1, -(TITLE_SIDE_MARGIN * 2), 1, -(TITLE_SIDE_MARGIN * 2))
    ensureCorner(root, UDim.new(0, 0))
    ensureStroke(root, PANEL_ACCENT, 3, 0.15)
    ensurePadding(root, UDim.new(0, 24))

    local label = ensureChild(root, "TextLabel", "Title")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBlack
    label.Text = TITLE_TEXT
    label.TextColor3 = TITLE_TEXT_COLOR
    label.TextScaled = true
    label.TextStrokeColor3 = Color3.fromRGB(10, 28, 49)
    label.TextStrokeTransparency = 0.45
    label.TextWrapped = true

    return surfaceGui
end

local function ensureListGui(listPart)
    local surfaceGui = ensureSurfaceGui(listPart, LIST_GUI_NAME, 46, LIST_GUI_FACE)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = PANEL_COLOR
    root.BackgroundTransparency = 0.08
    root.BorderSizePixel = 0
    root.Size = UDim2.fromScale(1, 1)
    ensureCorner(root, UDim.new(0, 0))
    ensureStroke(root, PANEL_ACCENT, 3, 1)

    local accent = ensureChild(root, "Frame", "AccentBar")
    accent.BackgroundColor3 = PANEL_ACCENT
    accent.BorderSizePixel = 0
    accent.Position = UDim2.new(0, 0, 0, 0)
    accent.Size = UDim2.new(1, 0, 0, 8)

    local header = ensureChild(root, "Frame", "Header")
    header.BackgroundTransparency = 1
    header.BorderSizePixel = 0
    header.Position = UDim2.new(0, LIST_SIDE_MARGIN, 0, HEADER_TOP)
    header.Size = UDim2.new(1, -(LIST_SIDE_MARGIN * 2), 0, HEADER_HEIGHT)

    local divider = ensureChild(header, "Frame", "Divider")
    divider.BackgroundColor3 = DEFAULT_STROKE_COLOR
    divider.BackgroundTransparency = 0.2
    divider.BorderSizePixel = 0
    divider.Position = UDim2.new(0, 0, 0, 0)
    divider.Size = UDim2.new(1, 0, 0, 2)

    local columns = ensureChild(header, "Frame", "Columns")
    columns.BackgroundTransparency = 1
    columns.BorderSizePixel = 0
    columns.Position = UDim2.new(0, 0, 0, 12)
    columns.Size = UDim2.new(1, 0, 0, 74)

    local rankLabel = ensureChild(columns, "TextLabel", "RankHeader")
    rankLabel.BackgroundTransparency = 1
    rankLabel.BorderSizePixel = 0
    rankLabel.Position = UDim2.new(0, 0, 0, 0)
    rankLabel.Size = UDim2.new(RANK_COLUMN_SCALE, 0, 1, 0)
    rankLabel.Font = Enum.Font.GothamBold
    rankLabel.Text = "RANK"
    rankLabel.TextColor3 = HEADER_TEXT_COLOR
    rankLabel.TextScaled = true
    rankLabel.TextSize = 40
    rankLabel.TextXAlignment = Enum.TextXAlignment.Left
    ensureTextConstraint(rankLabel, 18, 40)

    local playerLabel = ensureChild(columns, "TextLabel", "PlayerHeader")
    playerLabel.BackgroundTransparency = 1
    playerLabel.BorderSizePixel = 0
    playerLabel.Position = UDim2.new(PLAYER_COLUMN_START, 0, 0, 0)
    playerLabel.Size = UDim2.new(PLAYER_COLUMN_WIDTH, 0, 1, 0)
    playerLabel.Font = Enum.Font.GothamBold
    playerLabel.Text = "PLAYER"
    playerLabel.TextColor3 = HEADER_TEXT_COLOR
    playerLabel.TextScaled = true
    playerLabel.TextSize = 40
    playerLabel.TextXAlignment = Enum.TextXAlignment.Left
    ensureTextConstraint(playerLabel, 18, 40)

    local valueHeader = ensureChild(columns, "TextLabel", "ValueHeader")
    valueHeader.BackgroundTransparency = 1
    valueHeader.BorderSizePixel = 0
    valueHeader.AnchorPoint = Vector2.new(1, 0)
    valueHeader.Position = UDim2.new(1, 0, 0, 0)
    valueHeader.Size = UDim2.new(VALUE_COLUMN_WIDTH, 0, 1, 0)
    valueHeader.Font = Enum.Font.GothamBold
    valueHeader.Text = VALUE_HEADER_TEXT
    valueHeader.TextColor3 = HEADER_TEXT_COLOR
    valueHeader.TextScaled = true
    valueHeader.TextSize = 40
    valueHeader.TextXAlignment = Enum.TextXAlignment.Right
    ensureTextConstraint(valueHeader, 18, 40)

    local scroll = ensureChild(root, "ScrollingFrame", "Entries")
    scroll.Active = true
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Position = UDim2.new(0, LIST_SIDE_MARGIN, 0, SCROLL_TOP)
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ScrollingEnabled = true
    scroll.ScrollBarImageColor3 = PANEL_ACCENT
    scroll.ScrollBarImageTransparency = 1
    scroll.ScrollBarThickness = 20
    scroll.Size = UDim2.new(1, -(LIST_SIDE_MARGIN * 2), 1, -(SCROLL_TOP + SCROLL_BOTTOM_MARGIN))

    local padding = ensurePadding(scroll, UDim.new(0, 6))
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)

    local layout = ensureChild(scroll, "UIListLayout", "Layout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding = UDim.new(0, ROW_SPACING)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    return surfaceGui, scroll
end

local function writeOrderedValue(userId, value)
    local key = tostring(userId)
    local label = string.format("GlobalEliminationsLeaderboard/%s", key)

    for attempt = 1, #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }) do
        DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, label)

        local ok, err = pcall(function()
            orderedStore:UpdateAsync(key, function(oldValue)
                if tonumber(oldValue) == value then
                    return oldValue
                end
                return value
            end)
        end)
        if ok then
            return true
        end

        warn(string.format("[GlobalEliminationsLeaderboard] ordered mirror write failed | userId=%s | attempt=%d | error=%s", key, attempt, tostring(err)))
        if attempt < #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }) then
            task.wait(getRetryBackoff(attempt))
        end
    end

    return false
end

local function getMirrorState(userId)
    local state = mirrorStateByUserId[userId]
    if state then
        return state
    end

    state = {
        pendingValue = nil,
        lastSavedValue = nil,
        writeScheduled = false,
        writeInProgress = false,
        needsFlush = false,
        player = nil,
    }
    mirrorStateByUserId[userId] = state
    return state
end

local function flushMirror(userId)
    local state = mirrorStateByUserId[userId]
    if not state then
        return true
    end

    if state.writeInProgress then
        state.needsFlush = true
        return true
    end

    local valueToWrite = state.pendingValue
    local player = state.player
    if player and player.Parent and isCareerStatsSectionReady(player) then
        local liveValue = getAuthoritativeEliminations(player)
        if liveValue then
            valueToWrite = liveValue
        end
    end

    if type(valueToWrite) ~= "number" then
        return false
    end

    if state.lastSavedValue == valueToWrite then
        state.pendingValue = nil
        return true
    end

    state.writeInProgress = true
    state.pendingValue = nil
    local ok = writeOrderedValue(userId, valueToWrite)
    state.writeInProgress = false

    if ok then
        state.lastSavedValue = valueToWrite
    else
        state.pendingValue = valueToWrite
    end

    if state.needsFlush then
        state.needsFlush = false
        task.spawn(function()
            flushMirror(userId)
        end)
    end

    return ok
end

local function queueMirror(player, value, immediate)
    if not player or not player.UserId then
        return
    end

    local userId = player.UserId
    local state = getMirrorState(userId)
    state.player = player
    state.pendingValue = clampValue(value)

    if immediate then
        flushMirror(userId)
        return
    end

    if state.writeScheduled then
        return
    end

    state.writeScheduled = true
    task.delay(MIRROR_DEBOUNCE_SECONDS, function()
        local latestState = mirrorStateByUserId[userId]
        if not latestState then
            return
        end
        latestState.writeScheduled = false
        flushMirror(userId)
    end)
end

local function syncPlayerEliminations(player, immediate)
    if not player or not player.Parent or not isCareerStatsSectionReady(player) then
        return false
    end

    local value = getAuthoritativeEliminations(player)
    if type(value) ~= "number" then
        return false
    end

    queueMirror(player, value, immediate)
    return true
end

local function disconnectPlayer(player)
    local tracked = connectionsByPlayer[player]
    if not tracked then
        return
    end

    for _, connection in ipairs(tracked) do
        connection:Disconnect()
    end
    connectionsByPlayer[player] = nil
end

local function getIdentity(userId)
    local cached = identityCache[userId]
    if cached and (os.clock() - cached.cachedAt) < IDENTITY_CACHE_TTL_SECONDS then
        return cached
    end

    local onlinePlayer = Players:GetPlayerByUserId(userId)
    local username = tostring(userId)
    local displayName = nil

    if onlinePlayer then
        username = onlinePlayer.Name
        displayName = onlinePlayer.DisplayName
    end

    local okInfo, userInfos = pcall(function()
        return UserService:GetUserInfosByUserIdsAsync({ userId })
    end)
    if okInfo and type(userInfos) == "table" then
        local info = userInfos[1]
        if type(info) == "table" then
            if type(info.Username) == "string" and info.Username ~= "" then
                username = info.Username
            end
            if type(info.DisplayName) == "string" and info.DisplayName ~= "" then
                displayName = info.DisplayName
            end
        end
    elseif not onlinePlayer then
        local okName, fetchedName = pcall(function()
            return Players:GetNameFromUserIdAsync(userId)
        end)
        if okName and type(fetchedName) == "string" and fetchedName ~= "" then
            username = fetchedName
        end
    end

    local thumbnailUrl = ""
    local okThumb, image = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    end)
    if okThumb and type(image) == "string" then
        thumbnailUrl = image
    end

    local primaryName = displayName
    if type(primaryName) ~= "string" or primaryName == "" then
        primaryName = username
    end

    local secondaryName = "@" .. username

    local identity = {
        username = username,
        displayName = displayName,
        primaryName = primaryName,
        secondaryName = secondaryName,
        thumbnailUrl = thumbnailUrl,
        cachedAt = os.clock(),
    }
    identityCache[userId] = identity
    return identity
end

local function getTopEntries()
    local label = string.format("%s/read", ORDERED_STORE_NAME)
    DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.GetSortedAsync, label)

    local ok, pages = pcall(function()
        return orderedStore:GetSortedAsync(false, MAX_ROWS)
    end)
    if not ok then
        warn("[GlobalEliminationsLeaderboard] Failed to fetch ordered data: " .. tostring(pages))
        return {}
    end

    local page = pages:GetCurrentPage()
    local entries = {}
    for rank, item in ipairs(page) do
        local userId = tonumber(item.key)
        local value = tonumber(item.value)
        if userId and value then
            table.insert(entries, {
                rank = rank,
                userId = userId,
                value = clampValue(value),
            })
        end
    end
    return entries
end

local function clearEntryRows(scroll)
    for _, child in ipairs(scroll:GetChildren()) do
        if child:GetAttribute("LeaderboardEntry") then
            child:Destroy()
        end
    end
end

local function createEmptyState(scroll)
    local emptyFrame = Instance.new("Frame")
    emptyFrame.Name = "EmptyState"
    emptyFrame.BackgroundColor3 = DEFAULT_ROW_COLOR
    emptyFrame.BorderSizePixel = 0
    emptyFrame.LayoutOrder = 1
    emptyFrame.Size = UDim2.new(1, -4, ROW_HEIGHT_SCALE, 0)
    emptyFrame:SetAttribute("LeaderboardEntry", true)
    emptyFrame.Parent = scroll
    ensureCorner(emptyFrame, UDim.new(0, 0))
    ensureStroke(emptyFrame, DEFAULT_STROKE_COLOR, 3, 0.2)

    local label = Instance.new("TextLabel")
    label.Name = "Message"
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamSemibold
    label.Text = EMPTY_STATE_TEXT
    label.TextColor3 = MUTED_TEXT_COLOR
    label.TextScaled = true
    label.TextSize = 50
    label.Parent = emptyFrame
    ensureTextConstraint(label, 18, 50)
end

local function createEntryRow(scroll, entry)
    local identity = getIdentity(entry.userId)
    local accentColor = TOP_RANK_COLORS[entry.rank] or DEFAULT_STROKE_COLOR
    local rowColor = TOP_RANK_COLORS[entry.rank] and Color3.fromRGB(43, 50, 61) or DEFAULT_ROW_COLOR

    local row = Instance.new("Frame")
    row.Name = string.format("Entry_%02d", entry.rank)
    row.BackgroundColor3 = rowColor
    row.BorderSizePixel = 0
    row.LayoutOrder = entry.rank
    row.Size = UDim2.new(1, -4, ROW_HEIGHT_SCALE, 0)
    row:SetAttribute("LeaderboardEntry", true)
    row.Parent = scroll
    ensureCorner(row, UDim.new(0, 0))
    ensureStroke(row, accentColor, entry.rank <= 3 and 4 or 3, entry.rank <= 3 and 0.05 or 0.18)

    local rankBadge = Instance.new("TextLabel")
    rankBadge.Name = "Rank"
    rankBadge.AnchorPoint = Vector2.new(0, 0.5)
    rankBadge.BackgroundColor3 = accentColor
    rankBadge.BackgroundTransparency = entry.rank <= 3 and 0.05 or 0.2
    rankBadge.BorderSizePixel = 0
    rankBadge.Position = UDim2.new(0.01, 0, 0.5, 0)
    rankBadge.Size = UDim2.new(0.095, 0, 0.46, 0)
    rankBadge.Font = Enum.Font.GothamBlack
    rankBadge.Text = "#" .. tostring(entry.rank)
    rankBadge.TextColor3 = entry.rank == 2 and Color3.fromRGB(19, 25, 35) or PANEL_COLOR
    rankBadge.TextScaled = true
    rankBadge.TextSize = 38
    rankBadge.Parent = row
    ensureTextConstraint(rankBadge, 18, 38)

    local avatarHolder = Instance.new("Frame")
    avatarHolder.Name = "AvatarHolder"
    avatarHolder.AnchorPoint = Vector2.new(0, 0.5)
    avatarHolder.BackgroundColor3 = Color3.fromRGB(24, 30, 40)
    avatarHolder.BorderSizePixel = 0
    avatarHolder.Position = UDim2.new(0.115, 0, 0.5, 0)
    avatarHolder.Size = UDim2.new(0.14, 0, 0.78, 0)
    avatarHolder.Parent = row
    ensureCorner(avatarHolder, UDim.new(0, 0))
    ensureStroke(avatarHolder, accentColor, 3, 0.15)

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.BorderSizePixel = 0
    avatar.Position = UDim2.new(0, 2, 0, 2)
    avatar.Size = UDim2.new(1, -4, 1, -4)
    avatar.Image = identity.thumbnailUrl
    avatar.Parent = avatarHolder

    local nameFrame = Instance.new("Frame")
    nameFrame.Name = "NameFrame"
    nameFrame.BackgroundTransparency = 1
    nameFrame.BorderSizePixel = 0
    nameFrame.Position = UDim2.new(PLAYER_COLUMN_START, 0, 0.14, 0)
    nameFrame.Size = UDim2.new(PLAYER_COLUMN_WIDTH, 0, 0.72, 0)
    nameFrame.Parent = row

    local nameLayout = Instance.new("UIListLayout")
    nameLayout.FillDirection = Enum.FillDirection.Vertical
    nameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    nameLayout.Padding = UDim.new(0, 8)
    nameLayout.SortOrder = Enum.SortOrder.LayoutOrder
    nameLayout.Parent = nameFrame

    local primary = Instance.new("TextLabel")
    primary.Name = "PrimaryName"
    primary.BackgroundTransparency = 1
    primary.BorderSizePixel = 0
    primary.LayoutOrder = 1
    primary.Size = UDim2.new(1, 0, 0, 58)
    primary.Font = Enum.Font.GothamBold
    primary.Text = identity.primaryName
    primary.TextColor3 = BODY_TEXT_COLOR
    primary.TextScaled = true
    primary.TextSize = 64
    primary.TextTruncate = Enum.TextTruncate.None
    primary.TextWrapped = false
    primary.TextXAlignment = Enum.TextXAlignment.Left
    primary.Parent = nameFrame
    ensureTextConstraint(primary, 22, 64)

    local secondary = Instance.new("TextLabel")
    secondary.Name = "SecondaryName"
    secondary.BackgroundTransparency = 1
    secondary.BorderSizePixel = 0
    secondary.LayoutOrder = 2
    secondary.Size = UDim2.new(1, 0, 0, 42)
    secondary.Font = Enum.Font.GothamSemibold
    secondary.Text = identity.secondaryName
    secondary.TextColor3 = MUTED_TEXT_COLOR
    secondary.TextScaled = true
    secondary.TextSize = 40
    secondary.TextTruncate = Enum.TextTruncate.None
    secondary.TextWrapped = false
    secondary.TextXAlignment = Enum.TextXAlignment.Left
    secondary.Parent = nameFrame
    ensureTextConstraint(secondary, 18, 40)

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.AnchorPoint = Vector2.new(1, 0.5)
    valueLabel.BackgroundTransparency = 1
    valueLabel.BorderSizePixel = 0
    valueLabel.Position = UDim2.new(1, -6, 0.5, 0)
    valueLabel.Size = UDim2.new(VALUE_COLUMN_WIDTH, 0, 0.7, 0)
    valueLabel.Font = Enum.Font.GothamBlack
    valueLabel.Text = tostring(entry.value)
    valueLabel.TextColor3 = BODY_TEXT_COLOR
    valueLabel.TextScaled = true
    valueLabel.TextSize = 64
    valueLabel.TextWrapped = false
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row
    ensureTextConstraint(valueLabel, 22, 64)
end

function GlobalEliminationsLeaderboardService:RefreshDisplay()
    local titlePart, listPart = getLeaderboardParts()
    if not titlePart or not listPart then
        return false
    end

    ensureTitleGui(titlePart)
    local _, scroll = ensureListGui(listPart)
    clearEntryRows(scroll)

    local entries = getTopEntries()
    if #entries == 0 then
        createEmptyState(scroll)
    else
        for _, entry in ipairs(entries) do
            createEntryRow(scroll, entry)
        end
    end

    return true
end

local function trackPlayer(player)
    disconnectPlayer(player)

    local state = getMirrorState(player.UserId)
    state.player = player

    local tracked = {}
    connectionsByPlayer[player] = tracked

    task.spawn(function()
        local deadline = os.clock() + 30
        while started and player.Parent and os.clock() < deadline do
            if syncPlayerEliminations(player, true) then
                return
            end
            task.wait(0.5)
        end
    end)
end

function GlobalEliminationsLeaderboardService:FlushAll()
    for _, player in ipairs(Players:GetPlayers()) do
        syncPlayerEliminations(player, true)
    end
end

function GlobalEliminationsLeaderboardService:Start()
    if started then
        return
    end
    started = true

    Players.PlayerAdded:Connect(trackPlayer)
    Players.PlayerRemoving:Connect(function(player)
        if isCareerStatsSectionReady(player) then
            local value = getAuthoritativeEliminations(player)
            if type(value) == "number" then
                queueMirror(player, value, true)
            else
                flushMirror(player.UserId)
            end
        end

        local state = mirrorStateByUserId[player.UserId]
        if state then
            state.player = nil
        end
        disconnectPlayer(player)
    end)

    StatService:OnStatEvent(function(payload)
        local player = payload and payload.player
        if not player or not player:IsA("Player") then
            return
        end
        if payload.action ~= StatService.Actions.Elimination then
            return
        end

        task.defer(function()
            syncPlayerEliminations(player, false)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        trackPlayer(player)
    end

    task.spawn(function()
        while started do
            self:RefreshDisplay()
            task.wait(REFRESH_SECONDS)
        end
    end)

    task.spawn(function()
        while started do
            task.wait(PERIODIC_MIRROR_SECONDS)
            for _, player in ipairs(Players:GetPlayers()) do
                syncPlayerEliminations(player, false)
            end
        end
    end)

    game:BindToClose(function()
        self:FlushAll()
    end)
end

return GlobalEliminationsLeaderboardService