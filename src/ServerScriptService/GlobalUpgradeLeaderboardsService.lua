local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local DataStoreConfig = require(ServerScriptService:WaitForChild("DataStoreConfig"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local UpgradeService = require(ServerScriptService:WaitForChild("UpgradeService"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes"))

local GlobalUpgradeLeaderboardsService = {}

local TITLE_PART_NAME = "Leaderboardtitlescreen"
local LIST_PART_NAME = "Leaderboardscreen"
local TITLE_GUI_FACE = Enum.NormalId.Right
local LIST_GUI_FACE = Enum.NormalId.Right
local MAX_ROWS = 50
local REFRESH_SECONDS = 300
local MIRROR_DEBOUNCE_SECONDS = 15
local PERIODIC_MIRROR_SECONDS = 180
local IDENTITY_CACHE_TTL_SECONDS = 600

local TITLE_PIXELS_PER_STUD = 34
local LIST_PIXELS_PER_STUD = 30
local TITLE_SIDE_MARGIN = 10
local LIST_SIDE_MARGIN = 12

local HEADER_HEIGHT = 40
local HEADER_TOP = 6
local COLUMNS_TOP = 8
local COLUMNS_HEIGHT = 22
local SCROLL_TOP = 48
local SCROLL_BOTTOM_MARGIN = 10
local ROW_HEIGHT_SCALE = 0.165
local ROW_SPACING = 6

local RANK_COLUMN_SCALE = 0.13
local PLAYER_COLUMN_START = 0.28
local PLAYER_COLUMN_WIDTH = 0.48
local VALUE_COLUMN_WIDTH = 0.15

local TITLE_PADDING = 8
local TITLE_STROKE_THICKNESS = 2
local PANEL_STROKE_THICKNESS = 2
local ACCENT_BAR_HEIGHT = 4
local SCROLL_PADDING = 3
local SCROLL_SIDE_PADDING = 1
local SCROLLBAR_THICKNESS = 4
local TITLE_ICON_SIZE = 26
local TITLE_ICON_RIGHT = 8
local TITLE_ICON_LEFT = 8

local HEADER_TEXT_MIN = 8
local HEADER_TEXT_MAX = 15
local RANK_TEXT_MIN = 10
local RANK_TEXT_MAX = 14
local NAME_TEXT_MIN = 10
local NAME_TEXT_MAX = 16
local VALUE_TEXT_MIN = 10
local VALUE_TEXT_MAX = 16
local EMPTY_TEXT_MIN = 10
local EMPTY_TEXT_MAX = 18

local PRIMARY_NAME_HEIGHT = 18
local AVATAR_HOLDER_HEIGHT = 0.68
local NAME_FRAME_TOP = 0.28
local NAME_FRAME_HEIGHT = 0.42
local TITLE_TEXT_COLOR = Color3.fromRGB(245, 198, 76)
local SHARED_ACCENT_COLOR = Color3.fromRGB(245, 198, 76)

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

local function getAccent(upgradeId, fallback)
    local display = UpgradeConfig.Display and UpgradeConfig.Display[upgradeId]
    if type(display) == "table" and typeof(display.Accent) == "Color3" then
        return display.Accent
    end
    return fallback
end

local BOARD_CONFIGS = {
    {
        key = "melee",
        orderedStoreName = "GlobalMeleeUpgradeLeaderboard",
        modelNames = { "LeaderboardMelee", "Leaderboard Melee" },
        titleGuiName = "GlobalMeleeUpgradeTitleSurfaceGui",
        listGuiName = "GlobalMeleeUpgradeListSurfaceGui",
        titleText = "Top Melee",
        valueHeaderText = "LVL",
        emptyStateText = "No saved melee upgrade data yet.",
        upgradeId = UpgradeConfig.MELEE,
        panelAccent = SHARED_ACCENT_COLOR,
        titleTextColor = TITLE_TEXT_COLOR,
        titleIcon = (AssetCodes.images and AssetCodes.images.Melee) or AssetCodes.Get("Melee"),
    },
    {
        key = "ranged",
        orderedStoreName = "GlobalRangedUpgradeLeaderboard",
        modelNames = { "Leaderboard Range", "LeaderboardRange" },
        titleGuiName = "GlobalRangedUpgradeTitleSurfaceGui",
        listGuiName = "GlobalRangedUpgradeListSurfaceGui",
        titleText = "Top Range",
        valueHeaderText = "LVL",
        emptyStateText = "No saved range upgrade data yet.",
        upgradeId = UpgradeConfig.RANGED,
        panelAccent = SHARED_ACCENT_COLOR,
        titleTextColor = TITLE_TEXT_COLOR,
        titleIcon = (AssetCodes.images and AssetCodes.images.Ranged) or AssetCodes.Get("Ranged"),
    },
}

local BOARDS_BY_UPGRADE_ID = {}
local BOARDS_BY_KEY = {}
for _, board in ipairs(BOARD_CONFIGS) do
    board.orderedStore = DataStoreService:GetOrderedDataStore(board.orderedStoreName)
    BOARDS_BY_UPGRADE_ID[board.upgradeId] = board
    BOARDS_BY_KEY[board.key] = board
end

local started = false
local connectionsByPlayer = {}
local mirrorStateByBoardKey = {}
local identityCache = {}
local missingModelWarned = {}

local function getRetryBackoff(attempt)
    local backoff = DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }
    return backoff[attempt] or backoff[#backoff] or 1
end

local function clampValue(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function isUpgradeSectionReady(player)
    local profile = DataSaveCoordinator:GetProfile(player)
    local status = profile and profile.SectionStatus and profile.SectionStatus.Upgrade
    return status == "existing" or status == "new"
end

local function getAuthoritativeUpgradeLevel(player, upgradeId)
    if not player or not player:IsA("Player") then
        return nil, "missing player"
    end

    local value = nil
    if UpgradeService and type(UpgradeService.GetLevel) == "function" then
        pcall(function()
            value = UpgradeService:GetLevel(player, upgradeId)
        end)
    end
    if type(value) == "number" then
        return clampValue(value), "UpgradeService:GetLevel"
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

local function ensureCorner(parent)
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

local function getLeaderboardParts(board)
    local model = nil
    for _, modelName in ipairs(board.modelNames) do
        local candidate = Workspace:FindFirstChild(modelName)
        if candidate and candidate:IsA("Model") then
            model = candidate
            break
        end
    end

    if not model then
        if not missingModelWarned[board.key] then
            missingModelWarned[board.key] = true
            warn("[GlobalUpgradeLeaderboards] Missing model in Workspace: " .. board.modelNames[1])
        end
        return nil, nil
    end

    missingModelWarned[board.key] = false
    local titlePart = model:FindFirstChild(TITLE_PART_NAME)
    local listPart = model:FindFirstChild(LIST_PART_NAME)
    if not (titlePart and titlePart:IsA("BasePart")) then
        warn("[GlobalUpgradeLeaderboards] Missing part in model: " .. TITLE_PART_NAME .. " | board=" .. board.key)
        return nil, nil
    end
    if not (listPart and listPart:IsA("BasePart")) then
        warn("[GlobalUpgradeLeaderboards] Missing part in model: " .. LIST_PART_NAME .. " | board=" .. board.key)
        return nil, nil
    end

    return titlePart, listPart
end

local function ensureTitleGui(board, titlePart)
    local surfaceGui = ensureSurfaceGui(titlePart, board.titleGuiName, TITLE_PIXELS_PER_STUD, TITLE_GUI_FACE)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = PANEL_COLOR
    root.BackgroundTransparency = 0.18
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, TITLE_SIDE_MARGIN, 0, TITLE_SIDE_MARGIN)
    root.Size = UDim2.new(1, -(TITLE_SIDE_MARGIN * 2), 1, -(TITLE_SIDE_MARGIN * 2))
    ensureCorner(root)
    ensureStroke(root, board.panelAccent, TITLE_STROKE_THICKNESS, 0.15)
    ensurePadding(root, UDim.new(0, TITLE_PADDING))

    local label = ensureChild(root, "TextLabel", "Title")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Position = UDim2.new(0, TITLE_ICON_SIZE + TITLE_ICON_LEFT + 8, 0, 0)
    label.Size = UDim2.new(1, -((TITLE_ICON_SIZE + TITLE_ICON_LEFT + 8) + (TITLE_ICON_SIZE + TITLE_ICON_RIGHT + 8)), 1, 0)
    label.Font = Enum.Font.GothamBlack
    label.Text = board.titleText
    label.TextColor3 = board.titleTextColor
    label.TextScaled = true
    label.TextStrokeColor3 = Color3.fromRGB(10, 28, 49)
    label.TextStrokeTransparency = 0.45
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    ensureTextConstraint(label, 10, 24)

    local leftIcon = ensureChild(root, "ImageLabel", "TitleIconLeft")
    leftIcon.BackgroundTransparency = 1
    leftIcon.BorderSizePixel = 0
    leftIcon.AnchorPoint = Vector2.new(0, 0.5)
    leftIcon.Position = UDim2.new(0, TITLE_ICON_LEFT, 0.5, 0)
    leftIcon.Size = UDim2.new(0, TITLE_ICON_SIZE, 0, TITLE_ICON_SIZE)
    leftIcon.Image = board.titleIcon or ""
    leftIcon.ImageColor3 = board.titleTextColor
    leftIcon.ScaleType = Enum.ScaleType.Fit
    leftIcon.Visible = type(board.titleIcon) == "string" and board.titleIcon ~= ""

    local rightIcon = ensureChild(root, "ImageLabel", "TitleIconRight")
    rightIcon.BackgroundTransparency = 1
    rightIcon.BorderSizePixel = 0
    rightIcon.AnchorPoint = Vector2.new(1, 0.5)
    rightIcon.Position = UDim2.new(1, -TITLE_ICON_RIGHT, 0.5, 0)
    rightIcon.Size = UDim2.new(0, TITLE_ICON_SIZE, 0, TITLE_ICON_SIZE)
    rightIcon.Image = board.titleIcon or ""
    rightIcon.ImageColor3 = board.titleTextColor
    rightIcon.ScaleType = Enum.ScaleType.Fit
    rightIcon.Visible = type(board.titleIcon) == "string" and board.titleIcon ~= ""

    return surfaceGui
end

local function ensureListGui(board, listPart)
    local surfaceGui = ensureSurfaceGui(listPart, board.listGuiName, LIST_PIXELS_PER_STUD, LIST_GUI_FACE)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = PANEL_COLOR
    root.BackgroundTransparency = 0.08
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, 0, 0, 0)
    root.Size = UDim2.fromScale(1, 1)
    ensureCorner(root)
    ensureStroke(root, board.panelAccent, PANEL_STROKE_THICKNESS, 1)

    local accent = ensureChild(root, "Frame", "AccentBar")
    accent.BackgroundColor3 = board.panelAccent
    accent.BorderSizePixel = 0
    accent.Position = UDim2.new(0, 0, 0, 0)
    accent.Size = UDim2.new(1, 0, 0, ACCENT_BAR_HEIGHT)

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
    columns.Position = UDim2.new(0, 0, 0, COLUMNS_TOP)
    columns.Size = UDim2.new(1, 0, 0, COLUMNS_HEIGHT)

    local rankLabel = ensureChild(columns, "TextLabel", "RankHeader")
    rankLabel.BackgroundTransparency = 1
    rankLabel.BorderSizePixel = 0
    rankLabel.Position = UDim2.new(0, 0, 0, 0)
    rankLabel.Size = UDim2.new(RANK_COLUMN_SCALE, 0, 1, 0)
    rankLabel.Font = Enum.Font.GothamBold
    rankLabel.Text = "RANK"
    rankLabel.TextColor3 = HEADER_TEXT_COLOR
    rankLabel.TextScaled = true
    rankLabel.TextSize = HEADER_TEXT_MAX
    rankLabel.TextXAlignment = Enum.TextXAlignment.Left
    ensureTextConstraint(rankLabel, HEADER_TEXT_MIN, HEADER_TEXT_MAX)

    local playerLabel = ensureChild(columns, "TextLabel", "PlayerHeader")
    playerLabel.BackgroundTransparency = 1
    playerLabel.BorderSizePixel = 0
    playerLabel.Position = UDim2.new(PLAYER_COLUMN_START, 0, 0, 0)
    playerLabel.Size = UDim2.new(PLAYER_COLUMN_WIDTH, 0, 1, 0)
    playerLabel.Font = Enum.Font.GothamBold
    playerLabel.Text = "PLAYER"
    playerLabel.TextColor3 = HEADER_TEXT_COLOR
    playerLabel.TextScaled = true
    playerLabel.TextSize = HEADER_TEXT_MAX
    playerLabel.TextXAlignment = Enum.TextXAlignment.Left
    ensureTextConstraint(playerLabel, HEADER_TEXT_MIN, HEADER_TEXT_MAX)

    local valueHeader = ensureChild(columns, "TextLabel", "ValueHeader")
    valueHeader.BackgroundTransparency = 1
    valueHeader.BorderSizePixel = 0
    valueHeader.AnchorPoint = Vector2.new(1, 0)
    valueHeader.Position = UDim2.new(1, 0, 0, 0)
    valueHeader.Size = UDim2.new(VALUE_COLUMN_WIDTH, 0, 1, 0)
    valueHeader.Font = Enum.Font.GothamBold
    valueHeader.Text = board.valueHeaderText
    valueHeader.TextColor3 = HEADER_TEXT_COLOR
    valueHeader.TextScaled = true
    valueHeader.TextSize = HEADER_TEXT_MAX
    valueHeader.TextXAlignment = Enum.TextXAlignment.Right
    ensureTextConstraint(valueHeader, HEADER_TEXT_MIN, HEADER_TEXT_MAX)

    local scroll = ensureChild(root, "ScrollingFrame", "Entries")
    scroll.Active = true
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Position = UDim2.new(0, LIST_SIDE_MARGIN, 0, SCROLL_TOP)
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ScrollingEnabled = true
    scroll.ScrollBarImageColor3 = board.panelAccent
    scroll.ScrollBarImageTransparency = 1
    scroll.ScrollBarThickness = SCROLLBAR_THICKNESS
    scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
    scroll.Size = UDim2.new(1, -(LIST_SIDE_MARGIN * 2), 1, -(SCROLL_TOP + SCROLL_BOTTOM_MARGIN))

    local padding = ensurePadding(scroll, UDim.new(0, SCROLL_PADDING))
    padding.PaddingLeft = UDim.new(0, SCROLL_SIDE_PADDING)
    padding.PaddingRight = UDim.new(0, SCROLL_SIDE_PADDING)

    local layout = ensureChild(scroll, "UIListLayout", "Layout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding = UDim.new(0, ROW_SPACING)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    return surfaceGui, scroll
end

local function writeOrderedValue(board, userId, value)
    local key = tostring(userId)
    local label = string.format("%s/%s", board.orderedStoreName, key)

    for attempt = 1, #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }) do
        DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync, label)

        local ok, err = pcall(function()
            board.orderedStore:UpdateAsync(key, function(oldValue)
                if tonumber(oldValue) == value then
                    return oldValue
                end
                return value
            end)
        end)
        if ok then
            return true
        end

        warn(string.format("[GlobalUpgradeLeaderboards] ordered mirror write failed | board=%s | userId=%s | attempt=%d | error=%s", board.key, key, attempt, tostring(err)))
        if attempt < #(DataStoreConfig.RetryBackoffSeconds or { 1, 2, 4 }) then
            task.wait(getRetryBackoff(attempt))
        end
    end

    return false
end

local function getMirrorState(boardKey, userId)
    local boardStates = mirrorStateByBoardKey[boardKey]
    if not boardStates then
        boardStates = {}
        mirrorStateByBoardKey[boardKey] = boardStates
    end

    local state = boardStates[userId]
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
    boardStates[userId] = state
    return state
end

local function flushMirror(board, userId)
    local boardStates = mirrorStateByBoardKey[board.key]
    local state = boardStates and boardStates[userId]
    if not state then
        return true
    end

    if state.writeInProgress then
        state.needsFlush = true
        return true
    end

    local valueToWrite = state.pendingValue
    local player = state.player
    if player and player.Parent and isUpgradeSectionReady(player) then
        local liveValue = getAuthoritativeUpgradeLevel(player, board.upgradeId)
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
    local ok = writeOrderedValue(board, userId, valueToWrite)
    state.writeInProgress = false

    if ok then
        state.lastSavedValue = valueToWrite
    else
        state.pendingValue = valueToWrite
    end

    if state.needsFlush then
        state.needsFlush = false
        task.spawn(function()
            flushMirror(board, userId)
        end)
    end

    return ok
end

local function queueMirror(board, player, value, immediate)
    if not player or not player.UserId then
        return
    end

    local userId = player.UserId
    local state = getMirrorState(board.key, userId)
    state.player = player
    state.pendingValue = clampValue(value)

    if immediate then
        flushMirror(board, userId)
        return
    end

    if state.writeScheduled then
        return
    end

    state.writeScheduled = true
    task.delay(MIRROR_DEBOUNCE_SECONDS, function()
        local boardStates = mirrorStateByBoardKey[board.key]
        local latestState = boardStates and boardStates[userId]
        if not latestState then
            return
        end
        latestState.writeScheduled = false
        flushMirror(board, userId)
    end)
end

local function syncPlayerBoard(player, board, immediate)
    if not player or not player.Parent or not isUpgradeSectionReady(player) then
        return false
    end

    local value = getAuthoritativeUpgradeLevel(player, board.upgradeId)
    if type(value) ~= "number" then
        return false
    end

    queueMirror(board, player, value, immediate)
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

    local identity = {
        username = username,
        displayName = displayName,
        primaryName = primaryName,
        secondaryName = "@" .. username,
        thumbnailUrl = thumbnailUrl,
        cachedAt = os.clock(),
    }
    identityCache[userId] = identity
    return identity
end

local function getTopEntries(board)
    local label = string.format("%s/read", board.orderedStoreName)
    DataStoreOps.WaitForBudget(Enum.DataStoreRequestType.GetSortedAsync, label)

    local ok, pages = pcall(function()
        return board.orderedStore:GetSortedAsync(false, MAX_ROWS)
    end)
    if not ok then
        warn("[GlobalUpgradeLeaderboards] Failed to fetch ordered data | board=" .. board.key .. " | error=" .. tostring(pages))
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

local function createEmptyState(scroll, board)
    local emptyFrame = Instance.new("Frame")
    emptyFrame.Name = "EmptyState"
    emptyFrame.BackgroundColor3 = DEFAULT_ROW_COLOR
    emptyFrame.BorderSizePixel = 0
    emptyFrame.LayoutOrder = 1
    emptyFrame.Size = UDim2.new(1, -4, ROW_HEIGHT_SCALE, 0)
    emptyFrame:SetAttribute("LeaderboardEntry", true)
    emptyFrame.Parent = scroll
    ensureCorner(emptyFrame)
    ensureStroke(emptyFrame, DEFAULT_STROKE_COLOR, 2, 0.2)

    local label = Instance.new("TextLabel")
    label.Name = "Message"
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamSemibold
    label.Text = board.emptyStateText
    label.TextColor3 = MUTED_TEXT_COLOR
    label.TextScaled = true
    label.TextSize = EMPTY_TEXT_MAX
    label.Parent = emptyFrame
    ensureTextConstraint(label, EMPTY_TEXT_MIN, EMPTY_TEXT_MAX)
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
    row.Size = UDim2.new(1, 0, ROW_HEIGHT_SCALE, 0)
    row:SetAttribute("LeaderboardEntry", true)
    row.Parent = scroll
    ensureCorner(row)
    ensureStroke(row, accentColor, entry.rank <= 3 and 3 or 2, entry.rank <= 3 and 0.05 or 0.18)

    local rankBadge = Instance.new("TextLabel")
    rankBadge.Name = "Rank"
    rankBadge.AnchorPoint = Vector2.new(0, 0.5)
    rankBadge.BackgroundColor3 = accentColor
    rankBadge.BackgroundTransparency = entry.rank <= 3 and 0.05 or 0.2
    rankBadge.BorderSizePixel = 0
    rankBadge.Position = UDim2.new(0.01, 0, 0.5, 0)
    rankBadge.Size = UDim2.new(0.095, 0, 0.42, 0)
    rankBadge.Font = Enum.Font.GothamBlack
    rankBadge.Text = "#" .. tostring(entry.rank)
    rankBadge.TextColor3 = entry.rank == 2 and Color3.fromRGB(19, 25, 35) or PANEL_COLOR
    rankBadge.TextScaled = true
    rankBadge.TextSize = RANK_TEXT_MAX
    rankBadge.Parent = row
    ensureTextConstraint(rankBadge, RANK_TEXT_MIN, RANK_TEXT_MAX)

    local avatarHolder = Instance.new("Frame")
    avatarHolder.Name = "AvatarHolder"
    avatarHolder.AnchorPoint = Vector2.new(0, 0.5)
    avatarHolder.BackgroundColor3 = Color3.fromRGB(24, 30, 40)
    avatarHolder.BorderSizePixel = 0
    avatarHolder.Position = UDim2.new(0.115, 0, 0.5, 0)
    avatarHolder.Size = UDim2.new(0.14, 0, AVATAR_HOLDER_HEIGHT, 0)
    avatarHolder.Parent = row
    ensureCorner(avatarHolder)
    ensureStroke(avatarHolder, accentColor, 2, 0.15)

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
    nameFrame.Position = UDim2.new(PLAYER_COLUMN_START, 0, NAME_FRAME_TOP, 0)
    nameFrame.Size = UDim2.new(PLAYER_COLUMN_WIDTH, 0, NAME_FRAME_HEIGHT, 0)
    nameFrame.Parent = row

    local primary = Instance.new("TextLabel")
    primary.Name = "PrimaryName"
    primary.BackgroundTransparency = 1
    primary.BorderSizePixel = 0
    primary.Position = UDim2.new(0, 0, 0, 0)
    primary.Size = UDim2.new(1, 0, 1, 0)
    primary.Font = Enum.Font.GothamBold
    primary.Text = identity.username
    primary.TextColor3 = BODY_TEXT_COLOR
    primary.TextScaled = true
    primary.TextSize = NAME_TEXT_MAX
    primary.TextTruncate = Enum.TextTruncate.None
    primary.TextWrapped = false
    primary.TextXAlignment = Enum.TextXAlignment.Left
    primary.Parent = nameFrame
    ensureTextConstraint(primary, NAME_TEXT_MIN, NAME_TEXT_MAX)

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
    valueLabel.TextSize = VALUE_TEXT_MAX
    valueLabel.TextWrapped = false
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row
    ensureTextConstraint(valueLabel, VALUE_TEXT_MIN, VALUE_TEXT_MAX)
end

function GlobalUpgradeLeaderboardsService:RefreshDisplay()
    local refreshedAny = false

    for _, board in ipairs(BOARD_CONFIGS) do
        local titlePart, listPart = getLeaderboardParts(board)
        if titlePart and listPart then
            ensureTitleGui(board, titlePart)
            local _, scroll = ensureListGui(board, listPart)
            clearEntryRows(scroll)

            local entries = getTopEntries(board)
            if #entries == 0 then
                createEmptyState(scroll, board)
            else
                for _, entry in ipairs(entries) do
                    createEntryRow(scroll, entry)
                end
            end

            refreshedAny = true
        end
    end

    return refreshedAny
end

local function trackPlayer(player)
    disconnectPlayer(player)
    connectionsByPlayer[player] = {}

    for _, board in ipairs(BOARD_CONFIGS) do
        local state = getMirrorState(board.key, player.UserId)
        state.player = player
    end

    task.spawn(function()
        local deadline = os.clock() + 30
        while started and player.Parent and os.clock() < deadline do
            if isUpgradeSectionReady(player) then
                for _, board in ipairs(BOARD_CONFIGS) do
                    syncPlayerBoard(player, board, true)
                end
                return
            end
            task.wait(0.5)
        end
    end)
end

function GlobalUpgradeLeaderboardsService:FlushAll()
    for _, player in ipairs(Players:GetPlayers()) do
        for _, board in ipairs(BOARD_CONFIGS) do
            syncPlayerBoard(player, board, true)
        end
    end
end

function GlobalUpgradeLeaderboardsService:Start()
    if started then
        return
    end
    started = true

    Players.PlayerAdded:Connect(trackPlayer)
    Players.PlayerRemoving:Connect(function(player)
        if isUpgradeSectionReady(player) then
            for _, board in ipairs(BOARD_CONFIGS) do
                local value = getAuthoritativeUpgradeLevel(player, board.upgradeId)
                if type(value) == "number" then
                    queueMirror(board, player, value, true)
                else
                    flushMirror(board, player.UserId)
                end
            end
        end

        for _, board in ipairs(BOARD_CONFIGS) do
            local boardStates = mirrorStateByBoardKey[board.key]
            local state = boardStates and boardStates[player.UserId]
            if state then
                state.player = nil
            end
        end
        disconnectPlayer(player)
    end)

    local upgradeStateSignal = UpgradeService:GetStateChangedEvent()
    if upgradeStateSignal then
        upgradeStateSignal:Connect(function(player, upgradeId)
            local board = BOARDS_BY_UPGRADE_ID[upgradeId]
            if not board or not player or not player:IsA("Player") then
                return
            end

            task.defer(function()
                syncPlayerBoard(player, board, false)
            end)
        end)
    end

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
                for _, board in ipairs(BOARD_CONFIGS) do
                    syncPlayerBoard(player, board, false)
                end
            end
        end
    end)

    game:BindToClose(function()
        self:FlushAll()
    end)
end

return GlobalUpgradeLeaderboardsService