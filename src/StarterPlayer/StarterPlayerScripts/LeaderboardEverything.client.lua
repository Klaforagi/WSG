-- LeaderboardEverything.client.lua
-- Per-player interaction and rendering for Workspace.LeaderboardEverything.
-- Rendering locally lets every viewer choose a different stat/period without
-- changing the physical board for everyone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local getBoard = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GetLeaderboardEverything")
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))

local MODEL_NAME = "LeaderboardEverything"
local BOARD_FACE = Enum.NormalId.Right
local TITLE_ONE_PART = "Leaderboardtitlescreen1"
local TITLE_TWO_PART = "Leaderboardtitlescreen2"
local TITLE_THREE_PART = "Leaderboardtitlescreen3"
local LIST_PART = "Leaderboardscreen"
local TIMER_PART = "Leaderboardtimer"
local BLACKOUT_DISTANCE = 100

-- Title screens one and three are vertical selectors, ordered top to bottom.
local PERIODS = { "Weekly", "Monthly", "AllTime" }
local SCOPES = { "Global", "Server", "Friends" }
local STATS = {
    { id = "Eliminations", label = "ELIMINATIONS" },
    { id = "Wins", label = "WINS" },
    { id = "MVPs", label = "MVPS" },
    { id = "Coins", label = "COINS" },
    { id = "Captures", label = "CAPTURES" },
    { id = "Returns", label = "RETURNS" },
    { id = "AP", label = "AP", allTimeOnly = true },
    { id = "Playtime", label = "PLAYTIME", allTimeOnly = true },
}

local STAT_BY_ID = {}
for _, stat in ipairs(STATS) do
    STAT_BY_ID[stat.id] = stat
end

local COLORS = {
    panel = Color3.fromRGB(20, 25, 34),
    panelDark = Color3.fromRGB(12, 16, 23),
    row = Color3.fromRGB(31, 39, 52),
    selected = Color3.fromRGB(69, 133, 236),
    selectedGold = Color3.fromRGB(219, 169, 55),
    border = Color3.fromRGB(78, 95, 119),
    white = Color3.fromRGB(242, 246, 252),
    muted = Color3.fromRGB(160, 174, 194),
    gold = Color3.fromRGB(255, 207, 73),
}

local selectedPeriod = "Weekly"
local selectedStat = "Eliminations"
local selectedScope = "Global"
local currentResetAt = nil
local requestId = 0
local boardParts = {}
local refreshBoard
local updateButtons
local thumbnailCache = {}

local function getStatLabel(statId, fallback)
    local stat = STAT_BY_ID[statId]
    return stat and stat.label or fallback or tostring(statId)
end

local function getHeadingText(period, statId, scope, label)
    local periodLabel = period == "AllTime" and "ALL-TIME" or string.upper(period)
    return string.upper(scope) .. " " .. periodLabel .. " " .. getStatLabel(statId, label)
end

-- The heading represents the local selection, not the result of a potentially
-- slow global OrderedDataStore query. Keeping this assignment in one helper
-- prevents a selector click from briefly showing an intermediate title.
local function updateHeading()
    local listGui = boardParts.list and boardParts.list:FindFirstChild("LeaderboardEverythingList")
    local root = listGui and listGui:FindFirstChild("LeaderboardEverythingRoot")
    local heading = root and root:FindFirstChild("Heading")
    if heading and heading:IsA("TextLabel") then
        local text = getHeadingText(selectedPeriod, selectedStat, selectedScope)
        if heading.Text ~= text then
            heading.Text = text
        end
    end
end

local function getResetText()
    if selectedPeriod == "AllTime" then
        return "ALL-TIME LEADERBOARD"
    end
    if not currentResetAt then
        return string.upper(selectedPeriod) .. " RESETS IN --"
    end
    local seconds = math.max(0, currentResetAt - Workspace:GetServerTimeNow())
    return string.upper(selectedPeriod) .. " RESETS IN " .. TimeHelper.FormatCountdown(seconds)
end

-- Like the heading, the reset label is derived only from the active local
-- selection. Rebuilding the UI must never briefly reset it to another period.
local function updateResetLabel()
    local timerGui = boardParts.timer and boardParts.timer:FindFirstChild("LeaderboardEverythingTimer")
    local root = timerGui and timerGui:FindFirstChild("LeaderboardEverythingRoot")
    local label = root and root:FindFirstChild("TimerText")
    if label and label:IsA("TextLabel") then
        local text = getResetText()
        if label.Text ~= text then
            label.Text = text
        end
    end
end

local function ensureChild(parent, className, name)
    local child = parent:FindFirstChild(name)
    if child and not child:IsA(className) then
        child:Destroy()
        child = nil
    end
    if not child then
        child = Instance.new(className)
        child.Name = name
        child.Parent = parent
    end
    return child
end

local function addStroke(parent, color, thickness)
    local stroke = ensureChild(parent, "UIStroke", "Stroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = 0.05
    return stroke
end

local function addCorner(parent, radius)
    local corner = ensureChild(parent, "UICorner", "Corner")
    corner.CornerRadius = UDim.new(0, radius)
    return corner
end

local function addTextLimit(parent, minimum, maximum)
    local limit = ensureChild(parent, "UITextSizeConstraint", "TextSizeConstraint")
    limit.MinTextSize = minimum
    limit.MaxTextSize = maximum
end

local function ensureSurface(part, name, pixelsPerStud)
    local gui = ensureChild(part, "SurfaceGui", name)
    gui.Adornee = part
    gui.Active = true
    gui.Face = BOARD_FACE
    gui.ResetOnSpawn = false
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = pixelsPerStud
    gui.LightInfluence = 0
    gui.AlwaysOnTop = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    return gui
end

-- Each client owns these SurfaceGuis, so this visibility rule affects only
-- the local player. The board is unavailable once they move beyond 50 studs.
local function updateDistanceBlackout()
    if not boardParts.list then
        return
    end

    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local isTooFar = not rootPart
        or (rootPart.Position - boardParts.list.Position).Magnitude > BLACKOUT_DISTANCE

    local surfaces = {
        { boardParts.titleOne, "LeaderboardEverythingPeriods" },
        { boardParts.titleTwo, "LeaderboardEverythingStats" },
        { boardParts.titleThree, "LeaderboardEverythingScopes" },
        { boardParts.list, "LeaderboardEverythingList" },
        { boardParts.timer, "LeaderboardEverythingTimer" },
    }
    for _, surfaceInfo in ipairs(surfaces) do
        local part, surfaceName = surfaceInfo[1], surfaceInfo[2]
        local surfaceGui = part and part:FindFirstChild(surfaceName)
        if surfaceGui and surfaceGui:IsA("SurfaceGui") then
            surfaceGui.Active = not isTooFar
            local overlay = ensureChild(surfaceGui, "Frame", "DistanceBlackout")
            overlay.BackgroundColor3 = Color3.new(0, 0, 0)
            overlay.BackgroundTransparency = 0
            overlay.BorderSizePixel = 0
            overlay.Position = UDim2.fromScale(0, 0)
            overlay.Size = UDim2.fromScale(1, 1)
            overlay.ZIndex = 100
            overlay.Visible = isTooFar
        end
    end
end

local function createButton(parent, name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundColor3 = COLORS.panelDark
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = COLORS.muted
    button.TextScaled = true
    button.Parent = parent
    addCorner(button, 8)
    addStroke(button, COLORS.border, 1)
    addTextLimit(button, 13, 34)
    return button
end

local function findParts()
    local model = Workspace:FindFirstChild(MODEL_NAME)
    if not model or not model:IsA("Model") then
        return nil
    end
    local parts = {
        titleOne = model:FindFirstChild(TITLE_ONE_PART),
        titleTwo = model:FindFirstChild(TITLE_TWO_PART),
        titleThree = model:FindFirstChild(TITLE_THREE_PART),
        list = model:FindFirstChild(LIST_PART),
        timer = model:FindFirstChild(TIMER_PART),
    }
    if not (parts.titleOne and parts.titleOne:IsA("BasePart")
        and parts.titleTwo and parts.titleTwo:IsA("BasePart")
        and parts.titleThree and parts.titleThree:IsA("BasePart")
        and parts.list and parts.list:IsA("BasePart")
        and parts.timer and parts.timer:IsA("BasePart")) then
        return nil
    end
    return parts
end

local function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local reversed = string.reverse(text)
    reversed = string.gsub(reversed, "(%d%d%d)", "%1,")
    return string.reverse(reversed):gsub("^,", "")
end

local function formatValue(value)
    if selectedStat == "Playtime" then
        local total = math.max(0, math.floor(tonumber(value) or 0))
        local hours = math.floor(total / 3600)
        local minutes = math.floor((total % 3600) / 60)
        return string.format("%dh %02dm", hours, minutes)
    end
    return formatNumber(value)
end

local function getRoot(surfaceGui)
    local root = ensureChild(surfaceGui, "Frame", "LeaderboardEverythingRoot")
    root.BackgroundColor3 = COLORS.panel
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, 10, 0, 10)
    root.Size = UDim2.new(1, -20, 1, -20)
    addCorner(root, 10)
    addStroke(root, COLORS.border, 2)
    return root
end

local function buildUi()
    local parts = findParts()
    if not parts then
        return false
    end
    boardParts = parts

    local periodGui = ensureSurface(parts.titleOne, "LeaderboardEverythingPeriods", 60)
    local periodRoot = getRoot(periodGui)
    local periodLayout = ensureChild(periodRoot, "UIListLayout", "Layout")
    periodLayout.FillDirection = Enum.FillDirection.Vertical
    periodLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    periodLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    periodLayout.Padding = UDim.new(0, 9)
    periodLayout.SortOrder = Enum.SortOrder.LayoutOrder

    for order, period in ipairs(PERIODS) do
        local label = period == "AllTime" and "ALL-TIME" or string.upper(period)
        local button = ensureChild(periodRoot, "TextButton", "Period_" .. period)
        if not button:GetAttribute("Configured") then
            button:SetAttribute("Configured", true)
            button.Activated:Connect(function()
                if button.Active and selectedPeriod ~= period then
                    selectedPeriod = period
                    currentResetAt = nil
                    requestId += 1
                    updateButtons()
                    updateHeading()
                    updateResetLabel()
                    task.spawn(function()
                        if refreshBoard then
                            refreshBoard()
                        end
                    end)
                end
            end)
        end
        button.AutoButtonColor = false
        button.BackgroundColor3 = COLORS.panelDark
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.Text = label
        button.TextColor3 = COLORS.muted
        button.TextScaled = true
        button.LayoutOrder = order
        button.Size = UDim2.new(0.88, 0, 1 / 3, -12)
        button.Parent = periodRoot
        addCorner(button, 8)
        addStroke(button, COLORS.border, 1)
        addTextLimit(button, 12, 32)
    end

    local statGui = ensureSurface(parts.titleTwo, "LeaderboardEverythingStats", 56)
    local statRoot = getRoot(statGui)
    local grid = ensureChild(statRoot, "UIGridLayout", "Grid")
    grid.CellPadding = UDim2.new(0.016, 0, 0.12, 0)
    grid.CellSize = UDim2.new(0.235, 0, 0.42, 0)
    grid.FillDirectionMaxCells = 4
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Center
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    for order, stat in ipairs(STATS) do
        local button = ensureChild(statRoot, "TextButton", "Stat_" .. stat.id)
        if not button:GetAttribute("Configured") then
            button:SetAttribute("Configured", true)
            button.Activated:Connect(function()
                if selectedStat == stat.id then
                    return
                end
                selectedStat = stat.id
                if stat.allTimeOnly and selectedPeriod ~= "AllTime" then
                    selectedPeriod = "AllTime"
                    currentResetAt = nil
                end
                requestId += 1
                updateButtons()
                updateHeading()
                updateResetLabel()
                task.spawn(function()
                    if refreshBoard then
                        refreshBoard()
                    end
                end)
            end)
        end
        button.AutoButtonColor = false
        button.BackgroundColor3 = COLORS.panelDark
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.LayoutOrder = order
        button.Text = stat.label
        button.TextColor3 = COLORS.muted
        button.TextScaled = true
        button.Parent = statRoot
        addCorner(button, 7)
        addStroke(button, COLORS.border, 1)
        addTextLimit(button, 10, 26)
    end

    local scopeGui = ensureSurface(parts.titleThree, "LeaderboardEverythingScopes", 60)
    local scopeRoot = getRoot(scopeGui)
    local scopeLayout = ensureChild(scopeRoot, "UIListLayout", "Layout")
    scopeLayout.FillDirection = Enum.FillDirection.Vertical
    scopeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    scopeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    scopeLayout.Padding = UDim.new(0, 9)
    scopeLayout.SortOrder = Enum.SortOrder.LayoutOrder

    for order, scope in ipairs(SCOPES) do
        local button = ensureChild(scopeRoot, "TextButton", "Scope_" .. scope)
        if not button:GetAttribute("Configured") then
            button:SetAttribute("Configured", true)
            button.Activated:Connect(function()
                if selectedScope ~= scope then
                    selectedScope = scope
                    requestId += 1
                    updateButtons()
                    updateHeading()
                    task.spawn(function()
                        if refreshBoard then
                            refreshBoard()
                        end
                    end)
                end
            end)
        end
        button.AutoButtonColor = false
        button.BackgroundColor3 = COLORS.panelDark
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.Text = string.upper(scope)
        button.TextColor3 = COLORS.muted
        button.TextScaled = true
        button.LayoutOrder = order
        button.Size = UDim2.new(0.88, 0, 1 / 3, -12)
        button.Parent = scopeRoot
        addCorner(button, 8)
        addStroke(button, COLORS.border, 1)
        addTextLimit(button, 12, 32)
    end

    local listGui = ensureSurface(parts.list, "LeaderboardEverythingList", 48)
    local listRoot = getRoot(listGui)
    local heading = ensureChild(listRoot, "TextLabel", "Heading")
    heading.BackgroundTransparency = 1
    heading.Position = UDim2.new(0.04, 0, 0.025, 0)
    heading.Size = UDim2.new(0.92, 0, 0.11, 0)
    heading.Font = Enum.Font.GothamBlack
    heading.TextColor3 = COLORS.gold
    heading.TextScaled = true
    heading.TextXAlignment = Enum.TextXAlignment.Center
    addTextLimit(heading, 16, 48)

    local entries = ensureChild(listRoot, "ScrollingFrame", "Entries")
    entries.Active = true
    entries.AutomaticCanvasSize = Enum.AutomaticSize.Y
    entries.BackgroundTransparency = 1
    entries.BorderSizePixel = 0
    entries.CanvasSize = UDim2.fromOffset(0, 0)
    entries.Position = UDim2.new(0.035, 0, 0.15, 0)
    entries.ScrollBarImageColor3 = COLORS.selected
    entries.ScrollBarThickness = 8
    entries.ScrollingEnabled = true
    entries.ScrollingDirection = Enum.ScrollingDirection.Y
    entries.Size = UDim2.new(0.93, 0, 0.82, 0)
    local layout = ensureChild(entries, "UIListLayout", "Layout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local timerGui = ensureSurface(parts.timer, "LeaderboardEverythingTimer", 54)
    local timerRoot = getRoot(timerGui)
    local timerText = ensureChild(timerRoot, "TextLabel", "TimerText")
    timerText.BackgroundTransparency = 1
    timerText.Size = UDim2.fromScale(1, 1)
    timerText.Font = Enum.Font.GothamBold
    timerText.TextColor3 = COLORS.muted
    timerText.TextScaled = true
    timerText.TextXAlignment = Enum.TextXAlignment.Center
    addTextLimit(timerText, 14, 40)

    updateDistanceBlackout()
    return true
end

updateButtons = function()
    local periodGui = boardParts.titleOne and boardParts.titleOne:FindFirstChild("LeaderboardEverythingPeriods")
    local statGui = boardParts.titleTwo and boardParts.titleTwo:FindFirstChild("LeaderboardEverythingStats")
    local scopeGui = boardParts.titleThree and boardParts.titleThree:FindFirstChild("LeaderboardEverythingScopes")
    local stat = STAT_BY_ID[selectedStat]
    local allTimeOnly = stat and stat.allTimeOnly

    if periodGui then
        local root = periodGui:FindFirstChild("LeaderboardEverythingRoot")
        if root then
            for _, period in ipairs(PERIODS) do
                local button = root:FindFirstChild("Period_" .. period)
                if button and button:IsA("TextButton") then
                    local disabled = allTimeOnly and period ~= "AllTime"
                    local active = period == selectedPeriod
                    button.Active = not disabled
                    button.Selectable = not disabled
                    button.BackgroundColor3 = active and COLORS.selected or COLORS.panelDark
                    button.TextColor3 = disabled and Color3.fromRGB(92, 100, 113) or (active and COLORS.white or COLORS.muted)
                    local stroke = button:FindFirstChild("Stroke")
                    if stroke and stroke:IsA("UIStroke") then
                        stroke.Color = active and COLORS.selectedGold or COLORS.border
                        stroke.Transparency = disabled and 0.55 or 0.05
                    end
                end
            end
        end
    end
    if statGui then
        local root = statGui:FindFirstChild("LeaderboardEverythingRoot")
        if root then
            for _, statConfig in ipairs(STATS) do
                local button = root:FindFirstChild("Stat_" .. statConfig.id)
                if button and button:IsA("TextButton") then
                    local active = statConfig.id == selectedStat
                    button.BackgroundColor3 = active and COLORS.selected or COLORS.panelDark
                    button.TextColor3 = active and COLORS.white or COLORS.muted
                    local stroke = button:FindFirstChild("Stroke")
                    if stroke and stroke:IsA("UIStroke") then
                        stroke.Color = active and COLORS.selectedGold or COLORS.border
                    end
                end
            end
        end
    end
    if scopeGui then
        local root = scopeGui:FindFirstChild("LeaderboardEverythingRoot")
        if root then
            for _, scope in ipairs(SCOPES) do
                local button = root:FindFirstChild("Scope_" .. scope)
                if button and button:IsA("TextButton") then
                    local active = scope == selectedScope
                    button.BackgroundColor3 = active and COLORS.selected or COLORS.panelDark
                    button.TextColor3 = active and COLORS.white or COLORS.muted
                    local stroke = button:FindFirstChild("Stroke")
                    if stroke and stroke:IsA("UIStroke") then
                        stroke.Color = active and COLORS.selectedGold or COLORS.border
                    end
                end
            end
        end
    end
end

local function renderRows(entries)
    local listGui = boardParts.list and boardParts.list:FindFirstChild("LeaderboardEverythingList")
    local root = listGui and listGui:FindFirstChild("LeaderboardEverythingRoot")
    local entriesFrame = root and root:FindFirstChild("Entries")
    if not entriesFrame then
        return
    end
    for _, child in ipairs(entriesFrame:GetChildren()) do
        if child:GetAttribute("LeaderboardRow") then
            child:Destroy()
        end
    end

    if #entries == 0 then
        local empty = Instance.new("TextLabel")
        empty.Name = "Empty"
        empty:SetAttribute("LeaderboardRow", true)
        empty.BackgroundTransparency = 1
        empty.Size = UDim2.new(1, 0, 0.12, 0)
        empty.Font = Enum.Font.GothamMedium
        empty.Text = "No scores have been recorded yet."
        empty.TextColor3 = COLORS.muted
        empty.TextScaled = true
        empty.Parent = entriesFrame
        addTextLimit(empty, 13, 28)
        return
    end

    for index, entry in ipairs(entries) do
        local row = Instance.new("Frame")
        row.Name = "Entry_" .. tostring(index)
        row:SetAttribute("LeaderboardRow", true)
        row.BackgroundColor3 = COLORS.row
        row.BorderSizePixel = 0
        row.LayoutOrder = index
        row.Size = UDim2.new(1, -10, 0, 52)
        row.Parent = entriesFrame
        addCorner(row, 5)

        local rank = Instance.new("TextLabel")
        rank.BackgroundTransparency = 1
        rank.Position = UDim2.new(0.025, 0, 0, 0)
        rank.Size = UDim2.new(0.12, 0, 1, 0)
        rank.Font = Enum.Font.GothamBlack
        rank.Text = "#" .. tostring(entry.rank or index)
        rank.TextColor3 = (index <= 3) and COLORS.gold or COLORS.muted
        rank.TextScaled = true
        rank.TextXAlignment = Enum.TextXAlignment.Left
        rank.Parent = row
        addTextLimit(rank, 12, 30)

        local avatar = Instance.new("ImageLabel")
        avatar.Name = "Avatar"
        avatar.BackgroundColor3 = COLORS.panelDark
        avatar.BorderSizePixel = 0
        avatar.Position = UDim2.new(0.15, 0, 0.12, 0)
        avatar.Size = UDim2.new(0, 40, 0, 40)
        avatar.ScaleType = Enum.ScaleType.Crop
        avatar.Parent = row
        addCorner(avatar, 20)
        addStroke(avatar, COLORS.border, 1)

        local userId = tonumber(entry.userId)
        if userId then
            local cachedThumbnail = thumbnailCache[userId]
            if cachedThumbnail then
                avatar.Image = cachedThumbnail
            else
                task.spawn(function()
                    local ok, image = pcall(function()
                        local content, _ = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
                        return content
                    end)
                    if ok and type(image) == "string" then
                        thumbnailCache[userId] = image
                        if avatar.Parent then
                            avatar.Image = image
                        end
                    end
                end)
            end
        end

        local name = Instance.new("TextLabel")
        name.BackgroundTransparency = 1
        name.Position = UDim2.new(0.285, 0, 0, 0)
        name.Size = UDim2.new(0.445, 0, 1, 0)
        name.Font = Enum.Font.GothamBold
        name.Text = tostring(entry.name or "Unknown")
        name.TextColor3 = COLORS.white
        name.TextScaled = true
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.Parent = row
        addTextLimit(name, 12, 30)

        local value = Instance.new("TextLabel")
        value.BackgroundTransparency = 1
        value.Position = UDim2.new(0.74, 0, 0, 0)
        value.Size = UDim2.new(0.235, 0, 1, 0)
        value.Font = Enum.Font.GothamBlack
        value.Text = formatValue(entry.value)
        value.TextColor3 = COLORS.gold
        value.TextScaled = true
        value.TextTruncate = Enum.TextTruncate.AtEnd
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.Parent = row
        addTextLimit(value, 11, 28)
    end
end

refreshBoard = function()
    if not buildUi() then
        return
    end
    updateButtons()
    updateHeading()
    updateResetLabel()
    local localRequestId = requestId + 1
    requestId = localRequestId
    -- Capture the selection for this request. A later click can change the
    -- globals while InvokeServer is waiting, and that older response must not
    -- be allowed to redraw the newer board.
    local requestedPeriod = selectedPeriod
    local requestedStat = selectedStat
    local requestedScope = selectedScope
    local ok, payload = pcall(function()
        return getBoard:InvokeServer(requestedPeriod, requestedStat, requestedScope)
    end)
    if not ok or localRequestId ~= requestId or type(payload) ~= "table" then
        return
    end
    local responsePeriod = payload.period or requestedPeriod
    local responseStat = payload.stat or requestedStat
    local responseScope = payload.scope or requestedScope
    local selectionWasNormalized = responsePeriod ~= selectedPeriod
        or responseStat ~= selectedStat
        or responseScope ~= selectedScope
    selectedPeriod = responsePeriod
    selectedStat = responseStat
    selectedScope = responseScope
    currentResetAt = tonumber(payload.resetAt)
    updateButtons()
    updateResetLabel()
    -- The server only normalizes invalid combinations (for example AP to
    -- all-time). Normal clicks have already set the final title above, so a
    -- successful fetch never writes it a second time.
    if selectionWasNormalized then
        updateHeading()
    end
    renderRows(type(payload.entries) == "table" and payload.entries or {})
end

task.spawn(function()
    while true do
        updateResetLabel()
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        updateDistanceBlackout()
        task.wait(0.2)
    end
end)

task.spawn(function()
    while true do
        refreshBoard()
        task.wait(30)
    end
end)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == MODEL_NAME then
        task.defer(refreshBoard)
    end
end)

task.defer(refreshBoard)
