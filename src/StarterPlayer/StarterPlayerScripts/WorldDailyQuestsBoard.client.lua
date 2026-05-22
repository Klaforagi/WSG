local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BOARD_MODEL_NAME = "LeaderboardQuests"
local TITLE_PART_NAME = "Leaderboardtitlescreen"
local LIST_PART_NAME = "Leaderboardscreen"
local TIMER_PART_NAME = "Leaderboardtimer"
local RESET_PART_NAME = "ResetQuests"
local TITLE_GUI_NAME = "DailyQuestBoardTitleSurfaceGui"
local LIST_GUI_NAME = "DailyQuestBoardListSurfaceGui"
local TIMER_GUI_NAME = "DailyQuestBoardTimerSurfaceGui"
local RESET_OVERLAY_GUI_NAME = "DailyQuestResetOverlayGui"
local BOARD_FACE = Enum.NormalId.Right
local REFRESH_INTERVAL_SECONDS = 15

local TITLE_MARGIN = 16
local LIST_MARGIN = 20

local TITLE_BG = Color3.fromRGB(28, 29, 30)
local PANEL_BG = Color3.fromRGB(24, 25, 27)
local ROW_BG = Color3.fromRGB(29, 31, 34)
local ROW_BORDER = Color3.fromRGB(50, 53, 58)
local GOLD = Color3.fromRGB(255, 208, 64)
local WHITE = Color3.fromRGB(245, 247, 250)
local MUTED = Color3.fromRGB(170, 176, 186)
local BLUE_FILL = Color3.fromRGB(37, 135, 255)
local BLUE_TRACK = Color3.fromRGB(45, 57, 72)
local CLAIMED = Color3.fromRGB(82, 194, 112)
local CLAIMABLE_BG = Color3.fromRGB(44, 138, 74)
local ERROR_RED = Color3.fromRGB(255, 120, 120)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local questRemotesFolder = remotesFolder:WaitForChild("Quests")
local getQuestsRF = questRemotesFolder:WaitForChild("GetQuests")
local questProgressRE = questRemotesFolder:WaitForChild("QuestProgress")
local questStateChangedRE = questRemotesFolder:WaitForChild("QuestStateChanged")
local claimQuestRF = questRemotesFolder:WaitForChild("ClaimQuest")
local resetDailyQuestsRF = questRemotesFolder:WaitForChild("RequestResetDailyQuests")
local TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))

local claimSoundOk, ClaimSound = pcall(function()
    return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClaimSound"))
end)
if not claimSoundOk then
    ClaimSound = nil
end

local assetCodesOk, AssetCodes = pcall(function()
    return require(ReplicatedStorage:WaitForChild("AssetCodes"))
end)
local coinImage = "rbxassetid://6740408107"
if assetCodesOk and type(AssetCodes) == "table" then
    coinImage = (AssetCodes.images and AssetCodes.images.Coin) or AssetCodes.Coin or coinImage
end

local latestQuests = {}
local questIndexById = {}
local rowByQuestId = {}
local pendingClaimsById = {}
local titleGui = nil
local fetchQuests
local applyQuestList
local activeResetPart = nil
local resetTouchConnection = nil
local resetModalLayer = nil
local resetRequestInFlight = false

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

local function ensureStroke(parent, color, thickness, transparency)
    local stroke = ensureChild(parent, "UIStroke", "Stroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency or 0
    return stroke
end

local function ensurePadding(parent, left, right, top, bottom)
    local padding = ensureChild(parent, "UIPadding", "Padding")
    padding.PaddingLeft = left
    padding.PaddingRight = right or left
    padding.PaddingTop = top or left
    padding.PaddingBottom = bottom or top or left
    return padding
end

local function ensureTextConstraint(parent, minSize, maxSize)
    local constraint = ensureChild(parent, "UITextSizeConstraint", "TextSizeConstraint")
    constraint.MinTextSize = minSize
    constraint.MaxTextSize = maxSize
    return constraint
end

local function ensureSurfaceGui(part, guiName, pixelsPerStud)
    local surfaceGui = ensureChild(part, "SurfaceGui", guiName)
    surfaceGui.Adornee = part
    surfaceGui.Active = true
    surfaceGui.Face = BOARD_FACE
    surfaceGui.ResetOnSpawn = false
    surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    surfaceGui.PixelsPerStud = pixelsPerStud
    surfaceGui.LightInfluence = 0
    surfaceGui.AlwaysOnTop = false
    surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    return surfaceGui
end

local function ensureOverlayGui()
    local overlayGui = ensureChild(playerGui, "ScreenGui", RESET_OVERLAY_GUI_NAME)
    overlayGui.DisplayOrder = 80
    overlayGui.IgnoreGuiInset = true
    overlayGui.ResetOnSpawn = false
    overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    return overlayGui
end

local function findBoardModel()
    local model = Workspace:FindFirstChild(BOARD_MODEL_NAME)
    if model and model:IsA("Model") then
        return model
    end
    return nil
end

local function findBoardParts()
    local model = findBoardModel()
    if not model then
        return nil, nil, nil
    end

    local titlePart = model:FindFirstChild(TITLE_PART_NAME)
    local listPart = model:FindFirstChild(LIST_PART_NAME)
    local timerPart = model:FindFirstChild(TIMER_PART_NAME)
    if not (titlePart and titlePart:IsA("BasePart")) then
        return nil, nil, nil
    end
    if not (listPart and listPart:IsA("BasePart")) then
        return nil, nil, nil
    end
    if not (timerPart and timerPart:IsA("BasePart")) then
        return nil, nil, nil
    end

    return titlePart, listPart, timerPart
end

local function findResetPart()
    local model = findBoardModel()
    if not model then
        return nil
    end

    local resetPart = model:FindFirstChild(RESET_PART_NAME)
    if resetPart and resetPart:IsA("BasePart") then
        return resetPart
    end

    return nil
end

local function clearResetPrompts(resetPart)
    if not resetPart then
        return
    end

    for _, child in ipairs(resetPart:GetChildren()) do
        if child:IsA("ProximityPrompt") then
            child:Destroy()
        end
    end
end

local function buildCoinIcon(parent)
    if coinImage then
        local image = Instance.new("ImageLabel")
        image.Name = "CoinIcon"
        image.BackgroundTransparency = 1
        image.Size = UDim2.fromScale(0.26, 0.34)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.Position = UDim2.new(0.26, 0.5, 0.5, 0)
        image.Image = coinImage
        image.ScaleType = Enum.ScaleType.Fit
        image.Parent = parent
        return image
    end

    local coin = Instance.new("Frame")
    coin.Name = "CoinIcon"
    coin.BackgroundColor3 = GOLD
    coin.BorderSizePixel = 0
    coin.Size = UDim2.fromScale(0.22, 0.28)
    coin.AnchorPoint = Vector2.new(0.5, 0.5)
    coin.Position = UDim2.new(0.24, 0, 0.5, 0)
    coin.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = coin

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(196, 144, 20)
    stroke.Thickness = 2
    stroke.Parent = coin

    return coin
end

local function closeResetPurchaseModal()
    resetRequestInFlight = false
    if resetModalLayer then
        resetModalLayer:Destroy()
        resetModalLayer = nil
    end
end

local function disconnectResetTouchConnection()
    if resetTouchConnection then
        resetTouchConnection:Disconnect()
        resetTouchConnection = nil
    end
    activeResetPart = nil
end

local function isLocalCharacterHit(hit)
    local character = localPlayer.Character
    return character ~= nil and hit ~= nil and hit:IsDescendantOf(character)
end

local function showResetPurchaseModal()
    if resetModalLayer then
        return
    end

    local overlayGui = ensureOverlayGui()
    local layer = Instance.new("Frame")
    layer.Name = "ResetPurchaseLayer"
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.fromScale(1, 1)
    layer.ZIndex = 900
    layer.Parent = overlayGui
    resetModalLayer = layer

    local dimmer = Instance.new("TextButton")
    dimmer.Name = "Dimmer"
    dimmer.AutoButtonColor = false
    dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
    dimmer.BackgroundTransparency = 0.35
    dimmer.BorderSizePixel = 0
    dimmer.Size = UDim2.fromScale(1, 1)
    dimmer.Text = ""
    dimmer.ZIndex = 901
    dimmer.Parent = layer

    local modal = Instance.new("Frame")
    modal.Name = "Modal"
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.BackgroundColor3 = Color3.fromRGB(19, 21, 24)
    modal.BorderSizePixel = 0
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.Size = UDim2.fromOffset(440, 270)
    modal.ZIndex = 910
    modal.Parent = layer
    ensureStroke(modal, Color3.fromRGB(74, 146, 87), 2, 0.15)
    ensurePadding(modal, UDim.new(0, 22), UDim.new(0, 22), UDim.new(0, 20), UDim.new(0, 20))

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBlack
    title.Size = UDim2.new(1, 0, 0, 34)
    title.Text = "BUY DAILY QUEST RESET?"
    title.TextColor3 = GOLD
    title.TextScaled = true
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.ZIndex = 911
    title.Parent = modal
    ensureTextConstraint(title, 16, 30)

    local body = Instance.new("TextLabel")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.Font = Enum.Font.GothamMedium
    body.Position = UDim2.new(0, 0, 0, 48)
    body.Size = UDim2.new(1, 0, 0, 94)
    body.Text = "This will replace all 3 current daily quests with 3 new ones.\n\nPlaceholder purchase flow: confirming here will reset them immediately."
    body.TextColor3 = WHITE
    body.TextScaled = true
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Center
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.ZIndex = 911
    body.Parent = modal
    ensureTextConstraint(body, 14, 22)

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.GothamBold
    status.Position = UDim2.new(0, 0, 0, 146)
    status.Size = UDim2.new(1, 0, 0, 24)
    status.Text = ""
    status.TextColor3 = ERROR_RED
    status.TextScaled = true
    status.TextWrapped = true
    status.ZIndex = 911
    status.Parent = modal
    ensureTextConstraint(status, 12, 18)

    local cancelButton = Instance.new("TextButton")
    cancelButton.Name = "CancelButton"
    cancelButton.AutoButtonColor = false
    cancelButton.BackgroundColor3 = Color3.fromRGB(82, 44, 44)
    cancelButton.BorderSizePixel = 0
    cancelButton.Position = UDim2.new(0, 0, 1, -48)
    cancelButton.Size = UDim2.new(0.48, -6, 0, 48)
    cancelButton.Text = "CANCEL"
    cancelButton.Font = Enum.Font.GothamBold
    cancelButton.TextColor3 = WHITE
    cancelButton.TextScaled = true
    cancelButton.ZIndex = 911
    cancelButton.Parent = modal
    ensureTextConstraint(cancelButton, 14, 22)
    ensureStroke(cancelButton, Color3.fromRGB(170, 84, 84), 1, 0.2)

    local confirmButton = Instance.new("TextButton")
    confirmButton.Name = "ConfirmButton"
    confirmButton.AutoButtonColor = false
    confirmButton.BackgroundColor3 = CLAIMABLE_BG
    confirmButton.BorderSizePixel = 0
    confirmButton.Position = UDim2.new(0.52, 6, 1, -48)
    confirmButton.Size = UDim2.new(0.48, -6, 0, 48)
    confirmButton.Text = "CONFIRM"
    confirmButton.Font = Enum.Font.GothamBold
    confirmButton.TextColor3 = WHITE
    confirmButton.TextScaled = true
    confirmButton.ZIndex = 911
    confirmButton.Parent = modal
    ensureTextConstraint(confirmButton, 14, 22)
    ensureStroke(confirmButton, CLAIMED, 1, 0.15)

    dimmer.MouseButton1Click:Connect(function()
        if resetRequestInFlight then
            return
        end
        closeResetPurchaseModal()
    end)

    cancelButton.MouseButton1Click:Connect(function()
        if resetRequestInFlight then
            return
        end
        closeResetPurchaseModal()
    end)

    confirmButton.MouseButton1Click:Connect(function()
        if resetRequestInFlight then
            return
        end

        resetRequestInFlight = true
        confirmButton.Active = false
        cancelButton.Active = false
        status.TextColor3 = WHITE
        status.Text = "Resetting daily quests..."

        local success, message, updatedQuests = false, "Request failed", nil
        local ok = pcall(function()
            success, message, updatedQuests = resetDailyQuestsRF:InvokeServer()
        end)

        resetRequestInFlight = false
        confirmButton.Active = true
        cancelButton.Active = true

        if ok and success then
            if type(updatedQuests) == "table" and applyQuestList then
                applyQuestList(updatedQuests)
            elseif fetchQuests then
                fetchQuests()
            end
            closeResetPurchaseModal()
            return
        end

        status.TextColor3 = ERROR_RED
        status.Text = tostring(message or "Could not reset daily quests.")
    end)
end

local function bindResetTouchTrigger()
    local resetPart = findResetPart()
    if resetPart == activeResetPart and resetTouchConnection then
        return
    end

    disconnectResetTouchConnection()

    if not resetPart then
        closeResetPurchaseModal()
        return
    end

    clearResetPrompts(resetPart)
    activeResetPart = resetPart
    resetTouchConnection = resetPart.Touched:Connect(function(hit)
        if not isLocalCharacterHit(hit) then
            return
        end
        if resetModalLayer or resetRequestInFlight then
            return
        end
        showResetPurchaseModal()
    end)
end

local function ensureTitleGui(titlePart)
    local surfaceGui = ensureSurfaceGui(titlePart, TITLE_GUI_NAME, 72)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = TITLE_BG
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, TITLE_MARGIN, 0, TITLE_MARGIN)
    root.Size = UDim2.new(1, -(TITLE_MARGIN * 2), 1, -(TITLE_MARGIN * 2))
    ensureStroke(root, Color3.fromRGB(18, 18, 19), 2, 0.15)
    ensurePadding(root, UDim.new(0, 16))

    local label = ensureChild(root, "TextLabel", "Title")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBlack
    label.Text = "DAILY QUESTS"
    label.TextColor3 = GOLD
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    ensureTextConstraint(label, 28, 96)

    return surfaceGui
end

local function ensureTimerGui(timerPart)
    local surfaceGui = ensureSurfaceGui(timerPart, TIMER_GUI_NAME, 72)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = TITLE_BG
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, TITLE_MARGIN, 0, TITLE_MARGIN)
    root.Size = UDim2.new(1, -(TITLE_MARGIN * 2), 1, -(TITLE_MARGIN * 2))
    ensureStroke(root, Color3.fromRGB(18, 18, 19), 2, 0.15)
    ensurePadding(root, UDim.new(0, 16))

    local label = ensureChild(root, "TextLabel", "Timer")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBlack
    label.Text = "Resets in 0m 00s"
    label.TextColor3 = GOLD
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    ensureTextConstraint(label, 28, 96)

    return surfaceGui
end

local function ensureListGui(listPart)
    local surfaceGui = ensureSurfaceGui(listPart, LIST_GUI_NAME, 48)

    local root = ensureChild(surfaceGui, "Frame", "Root")
    root.BackgroundColor3 = PANEL_BG
    root.BorderSizePixel = 0
    root.Position = UDim2.new(0, LIST_MARGIN, 0, LIST_MARGIN)
    root.Size = UDim2.new(1, -(LIST_MARGIN * 2), 1, -(LIST_MARGIN * 2))
    ensureStroke(root, Color3.fromRGB(20, 21, 24), 2, 0.2)

    local scroll = ensureChild(root, "ScrollingFrame", "Entries")
    scroll.Active = false
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Position = UDim2.new(0, 10, 0, 8)
    scroll.ScrollingEnabled = false
    scroll.ScrollBarThickness = 0
    scroll.Size = UDim2.new(1, -20, 1, -16)

    local layout = ensureChild(scroll, "UIListLayout", "Layout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    return surfaceGui, scroll
end

local function clearQuestRows(scroll)
    rowByQuestId = {}
    for _, child in ipairs(scroll:GetChildren()) do
        if child:GetAttribute("QuestRow") then
            child:Destroy()
        end
    end
end

local function setRowState(row, quest)
    local progress = math.clamp(tonumber(quest.progress) or 0, 0, tonumber(quest.goal) or 0)
    local goal = math.max(1, tonumber(quest.goal) or 1)
    local complete = progress >= goal
    local claimed = quest.claimed == true
    local claimable = complete and not claimed and not pendingClaimsById[quest.id]

    local titleLabel = row:FindFirstChild("QuestTitle", true)
    local progressLabel = row:FindFirstChild("ProgressText", true)
    local rewardText = row:FindFirstChild("RewardText", true)
    local fillBar = row:FindFirstChild("ProgressFill", true)
    local rewardPanel = row:FindFirstChild("RewardPanel", true)
    local claimButton = row:FindFirstChild("ClaimButton", true)

    if titleLabel and titleLabel:IsA("TextLabel") then
        titleLabel.Text = tostring(quest.desc or quest.title or "Daily Quest")
        titleLabel.TextColor3 = claimed and MUTED or WHITE
    end
    if progressLabel and progressLabel:IsA("TextLabel") then
        if claimed then
            progressLabel.Text = "CLAIMED"
            progressLabel.TextColor3 = CLAIMED
        else
            progressLabel.Text = string.format("%d/%d", progress, goal)
            progressLabel.TextColor3 = complete and WHITE or MUTED
        end
    end
    if rewardText and rewardText:IsA("TextLabel") then
        rewardText.Text = tostring(quest.reward or 0)
        rewardText.TextColor3 = claimed and CLAIMED or (claimable and WHITE or GOLD)
    end
    if fillBar and fillBar:IsA("Frame") then
        fillBar.Size = UDim2.new(math.clamp(progress / goal, 0, 1), 0, 1, 0)
        fillBar.BackgroundColor3 = claimed and CLAIMED or BLUE_FILL
    end
    if rewardPanel and rewardPanel:IsA("Frame") then
        rewardPanel.BackgroundColor3 = claimable and CLAIMABLE_BG or Color3.fromRGB(34, 35, 37)
        rewardPanel.BackgroundTransparency = claimed and 0.35 or (claimable and 0.05 or 0.12)

        local stroke = rewardPanel:FindFirstChild("Stroke")
        if stroke and stroke:IsA("UIStroke") then
            stroke.Color = claimable and CLAIMED or Color3.fromRGB(56, 57, 60)
            stroke.Transparency = claimable and 0.05 or 0.3
        end
    end
    if claimButton and claimButton:IsA("TextButton") then
        claimButton.Active = claimable
        claimButton.AutoButtonColor = claimable
        claimButton.Selectable = claimable
    end
end

local function createQuestRow(scroll, quest, layoutOrder)
    local row = Instance.new("Frame")
    row.Name = tostring(quest.id or ("Quest_" .. tostring(layoutOrder)))
    row.BackgroundColor3 = ROW_BG
    row.BorderSizePixel = 0
    row.LayoutOrder = layoutOrder
    row.Size = UDim2.new(1, 0, 0, 96)
    row:SetAttribute("QuestRow", true)
    row.Parent = scroll
    ensureStroke(row, ROW_BORDER, 1, 0.2)

    local rewardPanel = Instance.new("Frame")
    rewardPanel.Name = "RewardPanel"
    rewardPanel.BackgroundColor3 = Color3.fromRGB(34, 35, 37)
    rewardPanel.BackgroundTransparency = 0.12
    rewardPanel.BorderSizePixel = 0
    rewardPanel.AnchorPoint = Vector2.new(1, 0)
    rewardPanel.Position = UDim2.new(1, 0, 0, 0)
    rewardPanel.Size = UDim2.new(0.25, 0, 1, 0)
    rewardPanel.Parent = row
    ensureStroke(rewardPanel, Color3.fromRGB(56, 57, 60), 1, 0.3)

    buildCoinIcon(rewardPanel)

    local rewardText = Instance.new("TextLabel")
    rewardText.Name = "RewardText"
    rewardText.BackgroundTransparency = 1
    rewardText.BorderSizePixel = 0
    rewardText.Position = UDim2.new(0.46, 0, 0, 0)
    rewardText.Size = UDim2.new(0.48, 0, 1, 0)
    rewardText.Font = Enum.Font.GothamBlack
    rewardText.Text = "0"
    rewardText.TextScaled = true
    rewardText.TextColor3 = GOLD
    rewardText.TextXAlignment = Enum.TextXAlignment.Left
    rewardText.Parent = rewardPanel
    ensureTextConstraint(rewardText, 12, 34)

    local claimButton = Instance.new("TextButton")
    claimButton.Name = "ClaimButton"
    claimButton.Active = false
    claimButton.AutoButtonColor = false
    claimButton.BackgroundTransparency = 1
    claimButton.BorderSizePixel = 0
    claimButton.Selectable = false
    claimButton.Size = UDim2.fromScale(1, 1)
    claimButton.Text = ""
    claimButton.TextTransparency = 1
    claimButton.Parent = rewardPanel

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.Position = UDim2.new(0, 12, 0, 8)
    content.Size = UDim2.new(0.75, -18, 1, -16)
    content.Parent = row

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "QuestTitle"
    titleLabel.BackgroundTransparency = 1
    titleLabel.BorderSizePixel = 0
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.Size = UDim2.new(0.72, 0, 0.48, 0)
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Text = tostring(quest.desc or quest.title or "Daily Quest")
    titleLabel.TextScaled = true
    titleLabel.TextColor3 = WHITE
    titleLabel.TextWrapped = false
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = content
    ensureTextConstraint(titleLabel, 22, 60)

    local progressLabel = Instance.new("TextLabel")
    progressLabel.Name = "ProgressText"
    progressLabel.BackgroundTransparency = 1
    progressLabel.BorderSizePixel = 0
    progressLabel.AnchorPoint = Vector2.new(1, 0)
    progressLabel.Position = UDim2.new(1, 0, 0, 0)
    progressLabel.Size = UDim2.new(0.26, 0, 0.36, 0)
    progressLabel.Font = Enum.Font.GothamBold
    progressLabel.Text = "0/0"
    progressLabel.TextScaled = true
    progressLabel.TextColor3 = MUTED
    progressLabel.TextXAlignment = Enum.TextXAlignment.Right
    progressLabel.Parent = content
    ensureTextConstraint(progressLabel, 11, 26)

    local progressTrack = Instance.new("Frame")
    progressTrack.Name = "ProgressTrack"
    progressTrack.BackgroundColor3 = BLUE_TRACK
    progressTrack.BorderSizePixel = 0
    progressTrack.Position = UDim2.new(0, 0, 0.6, 0)
    progressTrack.Size = UDim2.new(1, 0, 0.24, 0)
    progressTrack.Parent = content

    local progressFill = Instance.new("Frame")
    progressFill.Name = "ProgressFill"
    progressFill.BackgroundColor3 = BLUE_FILL
    progressFill.BorderSizePixel = 0
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.Parent = progressTrack

    claimButton.MouseButton1Click:Connect(function()
        local currentQuest = latestQuests[questIndexById[quest.id] or layoutOrder]
        if not currentQuest or pendingClaimsById[quest.id] then
            return
        end

        local currentGoal = math.max(1, tonumber(currentQuest.goal) or 1)
        local currentProgress = math.clamp(tonumber(currentQuest.progress) or 0, 0, currentGoal)
        if currentQuest.claimed == true or currentProgress < currentGoal then
            setRowState(row, currentQuest)
            return
        end

        pendingClaimsById[quest.id] = true
        setRowState(row, currentQuest)

        local success = false
        local ok = pcall(function()
            success = claimQuestRF:InvokeServer(quest.id)
        end)

        pendingClaimsById[quest.id] = nil

        if ok and success then
            currentQuest.claimed = true
            currentQuest.progress = currentGoal
            setRowState(row, currentQuest)
            if ClaimSound then
                pcall(ClaimSound.Play)
            end
            return
        end

        fetchQuests()
    end)

    rowByQuestId[quest.id] = row
    setRowState(row, quest)
end

local function renderQuestBoard(quests)
    local titlePart, listPart = findBoardParts()
    if not titlePart or not listPart then
        return false
    end

    titleGui = ensureTitleGui(titlePart)
    local _, scroll = ensureListGui(listPart)
    clearQuestRows(scroll)

    if #quests == 0 then
        local empty = Instance.new("TextLabel")
        empty.Name = "EmptyState"
        empty.BackgroundTransparency = 1
        empty.BorderSizePixel = 0
        empty.Size = UDim2.new(1, 0, 0, 120)
        empty.Font = Enum.Font.GothamBold
        empty.Text = "No daily quests available."
        empty.TextColor3 = MUTED
        empty.TextScaled = true
        empty.Parent = scroll
        empty:SetAttribute("QuestRow", true)
        ensureTextConstraint(empty, 16, 36)
        return true
    end

    for index, quest in ipairs(quests) do
        createQuestRow(scroll, quest, index)
    end

    return true
end

local function renderResetTimer()
    local _, _, timerPart = findBoardParts()
    if not timerPart then
        return false
    end

    local surfaceGui = ensureTimerGui(timerPart)
    local root = surfaceGui:FindFirstChild("Root")
    local label = root and root:FindFirstChild("Timer")
    if label and label:IsA("TextLabel") then
        label.Text = "Resets in " .. TimeHelper.FormatCountdown(TimeHelper.SecondsUntilNextDailyReset())
    end
    return true
end

applyQuestList = function(result)
    latestQuests = {}
    questIndexById = {}
    pendingClaimsById = {}
    for index, quest in ipairs(result) do
        if type(quest) == "table" and type(quest.id) == "string" then
            latestQuests[index] = {
                id = quest.id,
                title = quest.title,
                desc = quest.desc,
                progress = tonumber(quest.progress) or 0,
                goal = tonumber(quest.goal) or 1,
                reward = tonumber(quest.reward) or 0,
                claimed = quest.claimed == true,
            }
            questIndexById[quest.id] = index
        end
    end

    renderQuestBoard(latestQuests)
    return true
end

fetchQuests = function()
    local ok, result = pcall(function()
        return getQuestsRF:InvokeServer()
    end)
    if not ok or type(result) ~= "table" then
        return false
    end

    return applyQuestList(result)
end

local function updateQuestProgress(questId, newProgress)
    local index = questIndexById[questId]
    if not index then
        fetchQuests()
        return
    end

    local quest = latestQuests[index]
    if not quest then
        fetchQuests()
        return
    end

    quest.progress = math.min(tonumber(newProgress) or 0, quest.goal)
    local row = rowByQuestId[questId]
    if row and row.Parent then
        setRowState(row, quest)
    else
        renderQuestBoard(latestQuests)
    end
end

questProgressRE.OnClientEvent:Connect(function(questId, newProgress)
    if type(questId) ~= "string" then
        return
    end
    updateQuestProgress(questId, newProgress)
end)

questStateChangedRE.OnClientEvent:Connect(function(questId, state)
    if type(questId) ~= "string" then
        return
    end
    if state == "claimed" or state == "reset" then
        fetchQuests()
    end
end)

task.spawn(function()
    while not fetchQuests() do
        task.wait(1)
    end
    bindResetTouchTrigger()
end)

task.spawn(function()
    while true do
        task.wait(REFRESH_INTERVAL_SECONDS)
        fetchQuests()
    end
end)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == BOARD_MODEL_NAME then
        task.defer(function()
            fetchQuests()
            renderResetTimer()
            bindResetTouchTrigger()
        end)
    end
end)

if RunService:IsStudio() then
    task.defer(function()
        fetchQuests()
        renderResetTimer()
        bindResetTouchTrigger()
    end)
end

task.spawn(function()
    while true do
        renderResetTimer()
        task.wait(1)
    end
end)