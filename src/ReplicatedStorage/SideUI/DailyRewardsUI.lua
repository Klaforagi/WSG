--------------------------------------------------------------------------------
-- DailyRewardsUI.lua  –  Daily Rewards popup panel (ReplicatedStorage/SideUI)
-- Renders the 7-day reward track inside a standalone popup with animations.
-- Called from DailyRewardsClient.client.lua – NOT part of the SideUI modal.
--
-- API:
--   DailyRewardsUI.Create(screenGui, state, callbacks) -> popupFrame
--   DailyRewardsUI.Refresh(state)
--   DailyRewardsUI.IsOpen() -> bool
--   DailyRewardsUI.Close()
--   DailyRewardsUI.Destroy()
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- Load shared modules
--------------------------------------------------------------------------------
local UITheme
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("SideUI", 5)
    if mod then
        local tm = mod:FindFirstChild("UITheme")
        if tm and tm:IsA("ModuleScript") then UITheme = require(tm) end
    end
end)

local AssetCodes
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("AssetCodes", 5)
    if mod and mod:IsA("ModuleScript") then AssetCodes = require(mod) end
end)

local DailyRewardConfig
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("DailyRewardConfig", 5)
    if mod and mod:IsA("ModuleScript") then DailyRewardConfig = require(mod) end
end)

--------------------------------------------------------------------------------
-- Fallback theme colors
--------------------------------------------------------------------------------
local T = {
    NAVY         = UITheme and UITheme.NAVY or Color3.fromRGB(12, 14, 28),
    NAVY_LIGHT   = UITheme and UITheme.NAVY_LIGHT or Color3.fromRGB(22, 26, 48),
    NAVY_MID     = UITheme and UITheme.NAVY_MID or Color3.fromRGB(16, 20, 40),
    GOLD         = UITheme and UITheme.GOLD or Color3.fromRGB(255, 215, 80),
    GOLD_DIM     = UITheme and UITheme.GOLD_DIM or Color3.fromRGB(180, 150, 50),
    GOLD_WARM    = UITheme and UITheme.GOLD_WARM or Color3.fromRGB(255, 200, 40),
    WHITE        = UITheme and UITheme.WHITE or Color3.fromRGB(245, 245, 252),
    DIM_TEXT     = UITheme and UITheme.DIM_TEXT or Color3.fromRGB(145, 150, 175),
    GREEN_BTN    = UITheme and UITheme.GREEN_BTN or Color3.fromRGB(35, 190, 75),
    GREEN_GLOW   = UITheme and UITheme.GREEN_GLOW or Color3.fromRGB(50, 230, 110),
    RED_TEXT      = UITheme and UITheme.RED_TEXT or Color3.fromRGB(255, 80, 80),
    CARD_BG      = UITheme and UITheme.CARD_BG or Color3.fromRGB(26, 30, 48),
    CARD_STROKE  = UITheme and UITheme.CARD_STROKE or Color3.fromRGB(55, 62, 95),
    CARD_OWNED   = UITheme and UITheme.CARD_OWNED or Color3.fromRGB(22, 38, 34),
    CARD_HIGHLIGHT = UITheme and UITheme.CARD_HIGHLIGHT or Color3.fromRGB(36, 33, 18),
    ICON_BG      = UITheme and UITheme.ICON_BG or Color3.fromRGB(16, 18, 30),
    CLOSE_DEFAULT = UITheme and UITheme.CLOSE_DEFAULT or Color3.fromRGB(26, 30, 48),
    CLOSE_HOVER   = UITheme and UITheme.CLOSE_HOVER or Color3.fromRGB(55, 30, 38),
    CLOSE_PRESS   = UITheme and UITheme.CLOSE_PRESS or Color3.fromRGB(18, 20, 32),
    DISABLED_BG   = UITheme and UITheme.DISABLED_BG or Color3.fromRGB(35, 38, 52),
    POPUP_BG      = UITheme and UITheme.POPUP_BG or Color3.fromRGB(16, 18, 32),
    OVERLAY_CLR   = UITheme and UITheme.OVERLAY_CLR or Color3.fromRGB(10, 10, 10),
}

--------------------------------------------------------------------------------
-- px scaling helper (same as SideUI.client.lua)
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local isMobile = UserInputService.TouchEnabled
local deviceTextScale = isMobile and 1.0 or 0.75
local function tpx(base)
    return math.max(1, math.round(px(base) * deviceTextScale))
end

--------------------------------------------------------------------------------
-- Tween helpers
--------------------------------------------------------------------------------
local function tweenProp(inst, props, info)
    info = info or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local ok, tw = pcall(function() return TweenService:Create(inst, info, props) end)
    if ok and tw then tw:Play() return tw end
    return nil
end

--------------------------------------------------------------------------------
-- Icon helpers
--------------------------------------------------------------------------------
local function getRewardAssetId(rewardType)
    if not DailyRewardConfig or not AssetCodes then return nil end
    local key = DailyRewardConfig.IconAssetKeys and DailyRewardConfig.IconAssetKeys[rewardType]
    if key and AssetCodes.Get then
        local id = AssetCodes.Get(key)
        if id and #id > 0 then return id end
    end
    return nil
end

local function getRewardGlyph(rewardType)
    if DailyRewardConfig and DailyRewardConfig.IconGlyphs then
        return DailyRewardConfig.IconGlyphs[rewardType] or "\u{1F381}"
    end
    return "\u{1F381}"
end

local function getRewardColor(rewardType)
    if DailyRewardConfig and DailyRewardConfig.IconColors then
        return DailyRewardConfig.IconColors[rewardType] or T.GOLD
    end
    return T.GOLD
end

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------
local DailyRewardsUI = {}

local popup          = nil  -- root ScreenGui overlay (or Frame)
local overlayFrame   = nil
local windowFrame    = nil
local dayCards       = {}   -- [dayIndex] = { frame, statusLabel, ... }
local claimButton    = nil
local streakLabel    = nil
local subtitleLabel  = nil
local nextRewardLabel = nil
local currentState   = nil
local onClaimCallback = nil
local onCloseCallback = nil
local isOpen         = false
local isAnimating    = false
local claimCooldown  = false

--------------------------------------------------------------------------------
-- Build a single day card
--------------------------------------------------------------------------------
local pulseConns = {} -- cleanup table for pulse tweens

local function buildDayCard(dayNum, reward, parent)
    local status = reward.status or "future"
    local rewardType = reward.rewardType or "Coins"
    local amount = reward.amount or 0
    local displayName = reward.displayName or ""

    local cardW = isMobile and px(118) or px(140)
    local cardH = isMobile and px(300) or px(350)

    local card = Instance.new("Frame")
    card.Name = "Day" .. dayNum
    card.Size = UDim2.new(0, cardW, 0, cardH)
    card.LayoutOrder = dayNum
    card.BackgroundColor3 = T.CARD_BG
    card.BorderSizePixel = 0
    card.ZIndex = 513
    card.Parent = parent

    Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(12))

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = T.CARD_STROKE
    cardStroke.Thickness = 1.5
    cardStroke.Transparency = 0.2
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card

    -- Day label
    local dayLabel = Instance.new("TextLabel")
    dayLabel.Name = "DayLabel"
    dayLabel.Size = UDim2.new(1, 0, 0, px(34))
    dayLabel.Position = UDim2.new(0, 0, 0, px(12))
    dayLabel.BackgroundTransparency = 1
    dayLabel.Font = Enum.Font.GothamBold
    dayLabel.TextSize = tpx(32)
    dayLabel.TextColor3 = T.WHITE
    dayLabel.Text = "DAY " .. dayNum
    dayLabel.TextXAlignment = Enum.TextXAlignment.Center
    dayLabel.ZIndex = 514
    dayLabel.Parent = card

    -- Icon well
    local iconWell = Instance.new("Frame")
    iconWell.Name = "IconWell"
    iconWell.Size = UDim2.new(0, px(76), 0, px(76))
    iconWell.AnchorPoint = Vector2.new(0.5, 0)
    iconWell.Position = UDim2.new(0.5, 0, 0, px(52))
    iconWell.BackgroundColor3 = T.ICON_BG
    iconWell.ZIndex = 514
    iconWell.Parent = card
    Instance.new("UICorner", iconWell).CornerRadius = UDim.new(0, px(10))

    -- Icon image or glyph
    local assetId = getRewardAssetId(rewardType)
    if assetId then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.new(0.7, 0, 0.7, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.BackgroundTransparency = 1
        icon.Image = assetId
        icon.ImageColor3 = getRewardColor(rewardType)
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ZIndex = 515
        icon.Parent = iconWell
    else
        local glyph = Instance.new("TextLabel")
        glyph.Name = "Glyph"
        glyph.Size = UDim2.new(1, 0, 1, 0)
        glyph.BackgroundTransparency = 1
        glyph.Font = Enum.Font.GothamBold
        glyph.Text = getRewardGlyph(rewardType)
        glyph.TextSize = tpx(56)
        glyph.TextColor3 = getRewardColor(rewardType)
        glyph.ZIndex = 515
        glyph.Parent = iconWell
    end

    -- Reward label
    local rewardLabel = Instance.new("TextLabel")
    rewardLabel.Name = "RewardLabel"
    rewardLabel.Size = UDim2.new(1, -px(4), 0, px(30))
    rewardLabel.AnchorPoint = Vector2.new(0.5, 0)
    rewardLabel.Position = UDim2.new(0.5, 0, 0, px(140))
    rewardLabel.BackgroundTransparency = 1
    rewardLabel.Font = Enum.Font.GothamBold
    rewardLabel.TextSize = tpx(28)
    rewardLabel.TextWrapped = true
    rewardLabel.TextColor3 = T.WHITE
    rewardLabel.Text = displayName
    rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
    rewardLabel.ZIndex = 514
    rewardLabel.Parent = card

    -- Amount label (below reward label)
    local amountLabel = Instance.new("TextLabel")
    amountLabel.Name = "AmountLabel"
    amountLabel.Size = UDim2.new(1, 0, 0, px(26))
    amountLabel.AnchorPoint = Vector2.new(0.5, 0)
    amountLabel.Position = UDim2.new(0.5, 0, 0, px(174))
    amountLabel.BackgroundTransparency = 1
    amountLabel.Font = Enum.Font.Gotham
    amountLabel.TextSize = tpx(26)
    amountLabel.TextColor3 = T.DIM_TEXT
    amountLabel.ZIndex = 514
    amountLabel.Parent = card
    if DailyRewardConfig then
        amountLabel.Text = "x" .. tostring(amount)
    else
        amountLabel.Text = ""
    end

    -- Status indicator area (bottom of card)
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0, px(36))
    statusLabel.AnchorPoint = Vector2.new(0.5, 1)
    statusLabel.Position = UDim2.new(0.5, 0, 1, -px(12))
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = tpx(30)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.ZIndex = 515
    statusLabel.Parent = card

    -- Glow frame (for claimable pulse)
    local glowFrame = Instance.new("Frame")
    glowFrame.Name = "Glow"
    glowFrame.Size = UDim2.new(1, px(8), 1, px(8))
    glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    glowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    glowFrame.BackgroundColor3 = T.GOLD_WARM
    glowFrame.BackgroundTransparency = 1
    glowFrame.ZIndex = 512
    glowFrame.Parent = card
    Instance.new("UICorner", glowFrame).CornerRadius = UDim.new(0, px(16))

    -- Checkmark overlay (for claimed)
    local checkOverlay = Instance.new("TextLabel")
    checkOverlay.Name = "Check"
    checkOverlay.Size = UDim2.new(0, px(36), 0, px(36))
    checkOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
    checkOverlay.Position = UDim2.new(0.5, 0, 0.5, px(12))
    checkOverlay.BackgroundColor3 = Color3.fromRGB(35, 75, 52)
    checkOverlay.Font = Enum.Font.GothamBold
    checkOverlay.Text = "\u{2713}"
    checkOverlay.TextSize = tpx(34)
    checkOverlay.TextColor3 = T.WHITE
    checkOverlay.ZIndex = 518
    checkOverlay.Visible = false
    checkOverlay.Parent = card
    Instance.new("UICorner", checkOverlay).CornerRadius = UDim.new(1, 0)

    -- Lock overlay (for future)
    local lockOverlay = Instance.new("Frame")
    lockOverlay.Name = "LockOverlay"
    lockOverlay.Size = UDim2.new(1, 0, 1, 0)
    lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
    lockOverlay.BackgroundTransparency = 0.7
    lockOverlay.ZIndex = 517
    lockOverlay.Visible = false
    lockOverlay.Parent = card
    Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0, px(12))

    return {
        frame       = card,
        dayLabel    = dayLabel,
        iconWell    = iconWell,
        rewardLabel = rewardLabel,
        amountLabel = amountLabel,
        statusLabel = statusLabel,
        glowFrame   = glowFrame,
        checkOverlay= checkOverlay,
        lockOverlay = lockOverlay,
        cardStroke  = cardStroke,
    }
end

--------------------------------------------------------------------------------
-- Update a single day card's visual state
--------------------------------------------------------------------------------
local function updateCardVisual(cardData, status)
    if not cardData or not cardData.frame then return end

    -- Clear any existing pulse animation
    if pulseConns[cardData.frame] then
        pcall(function() pulseConns[cardData.frame]:Cancel() end)
        pulseConns[cardData.frame] = nil
    end

    local card  = cardData.frame
    local glow  = cardData.glowFrame
    local check = cardData.checkOverlay
    local lock  = cardData.lockOverlay
    local stroke = cardData.cardStroke
    local sLabel = cardData.statusLabel

    if status == "claimed" then
        card.BackgroundColor3 = T.CARD_OWNED
        stroke.Color = Color3.fromRGB(50, 85, 62)
        stroke.Transparency = 0.35
        glow.BackgroundTransparency = 1
        check.Visible = true
        lock.Visible = false
        sLabel.Text = "CLAIMED"
        sLabel.TextColor3 = Color3.fromRGB(85, 140, 100)
        -- Dim the card content slightly
        for _, child in ipairs(card:GetChildren()) do
            if child:IsA("TextLabel") and child.Name ~= "StatusLabel" and child.Name ~= "Check" then
                child.TextTransparency = 0.3
            end
        end

    elseif status == "claimable" then
        card.BackgroundColor3 = T.CARD_HIGHLIGHT
        stroke.Color = T.GOLD
        stroke.Transparency = 0
        glow.BackgroundTransparency = 0.75
        check.Visible = false
        lock.Visible = false
        sLabel.Text = "TODAY"
        sLabel.TextColor3 = T.GOLD

        -- Restore full visibility
        for _, child in ipairs(card:GetChildren()) do
            if child:IsA("TextLabel") then
                child.TextTransparency = 0
            end
        end

        -- Pulse glow animation
        local pulseInfo = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
        local pulseTween = TweenService:Create(glow, pulseInfo, { BackgroundTransparency = 0.88 })
        pulseTween:Play()
        pulseConns[card] = pulseTween

    else -- "future"
        card.BackgroundColor3 = T.CARD_BG
        stroke.Color = T.CARD_STROKE
        stroke.Transparency = 0.4
        glow.BackgroundTransparency = 1
        check.Visible = false
        lock.Visible = true
        sLabel.Text = ""
        sLabel.TextColor3 = T.DIM_TEXT
        -- Dim content
        for _, child in ipairs(card:GetChildren()) do
            if child:IsA("TextLabel") and child.Name ~= "StatusLabel" then
                child.TextTransparency = 0.4
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Build the popup
--------------------------------------------------------------------------------
function DailyRewardsUI.Create(screenGui, state, callbacks)
    if popup then return popup end

    callbacks = callbacks or {}
    onClaimCallback = callbacks.onClaim
    onCloseCallback = callbacks.onClose
    currentState = state or {}

    -- ── Overlay ──────────────────────────────────────────────────────────
    -- Daily Rewards should not use a full-screen active input blocker because
    -- it prevents right-click camera rotation. Only actual buttons should
    -- capture input. The dim backdrop is purely decorative (Active = false,
    -- and not a TextButton/ImageButton), matching the Inventory pattern.
    overlayFrame = Instance.new("Frame")
    overlayFrame.Name = "DailyRewardsOverlay"
    overlayFrame.Size = UDim2.new(1, 0, 1, 0)
    overlayFrame.Position = UDim2.new(0, 0, 0, 0)
    overlayFrame.BackgroundColor3 = T.OVERLAY_CLR
    overlayFrame.BackgroundTransparency = 0.45
    overlayFrame.BorderSizePixel = 0
    overlayFrame.Active = false
    overlayFrame.ZIndex = 500
    overlayFrame.Visible = false
    overlayFrame.Parent = screenGui

    -- ── Window ────────────────────────────────────────────────────────────
    local winW = isMobile and 0.92 or 0.55
    local winH = isMobile and 0.60 or 0.56
    windowFrame = Instance.new("Frame")
    windowFrame.Name = "DailyRewardsWindow"
    windowFrame.Size = UDim2.new(winW, 0, winH, 0)
    windowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    windowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    windowFrame.BackgroundColor3 = T.NAVY
    windowFrame.BackgroundTransparency = 0.02
    windowFrame.BorderSizePixel = 0
    windowFrame.ZIndex = 510
    windowFrame.ClipsDescendants = true
    windowFrame.Parent = overlayFrame

    local winCorner = Instance.new("UICorner")
    winCorner.CornerRadius = UDim.new(0, px(14))
    winCorner.Parent = windowFrame

    local winStroke = Instance.new("UIStroke")
    winStroke.Color = T.GOLD_DIM
    winStroke.Thickness = 1.5
    winStroke.Transparency = 0.15
    winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    winStroke.Parent = windowFrame

    -- Subtle gradient
    local winGrad = Instance.new("UIGradient")
    winGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
    })
    winGrad.Rotation = 90
    winGrad.Parent = windowFrame

    local winPad = Instance.new("UIPadding")
    winPad.PaddingTop = UDim.new(0, px(14))
    winPad.PaddingBottom = UDim.new(0, px(14))
    winPad.PaddingLeft = UDim.new(0, px(8))
    winPad.PaddingRight = UDim.new(0, px(8))
    winPad.Parent = windowFrame

    -- Prevent clicks on the window from falling through to the overlay close
    local winBlock = Instance.new("TextButton")
    winBlock.Name = "WindowClickBlock"
    winBlock.Size = UDim2.new(1, 0, 1, 0)
    winBlock.BackgroundTransparency = 1
    winBlock.Text = ""
    winBlock.ZIndex = 509
    winBlock.Parent = windowFrame

    -- ── Close button ──────────────────────────────────────────────────────
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBlack
    closeBtn.TextScaled = true
    closeBtn.Size = UDim2.new(0, px(32), 0, px(32))
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.Position = UDim2.new(1, px(6), 0, -px(6))
    closeBtn.BackgroundColor3 = T.CLOSE_DEFAULT
    closeBtn.TextColor3 = T.GOLD
    closeBtn.AutoButtonColor = false
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 520
    closeBtn.Parent = windowFrame

    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, px(8))
    local cbStroke = Instance.new("UIStroke")
    cbStroke.Color = T.GOLD
    cbStroke.Thickness = 1.2
    cbStroke.Transparency = 0.4
    cbStroke.Parent = closeBtn

    local closeTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    closeBtn.MouseEnter:Connect(function()
        tweenProp(closeBtn, { BackgroundColor3 = T.CLOSE_HOVER, TextColor3 = T.WHITE }, closeTween)
    end)
    closeBtn.MouseLeave:Connect(function()
        tweenProp(closeBtn, { BackgroundColor3 = T.CLOSE_DEFAULT, TextColor3 = T.GOLD }, closeTween)
    end)
    closeBtn.MouseButton1Down:Connect(function()
        tweenProp(closeBtn, { BackgroundColor3 = T.CLOSE_PRESS }, closeTween)
    end)
    closeBtn.Activated:Connect(function()
        DailyRewardsUI.Close()
    end)

    -- ── Title ─────────────────────────────────────────────────────────────
    local titlePill = Instance.new("Frame")
    titlePill.Name = "TitlePill"
    titlePill.Size = UDim2.new(0.48, 0, 0, px(52))
    titlePill.AnchorPoint = Vector2.new(0.5, 0)
    titlePill.Position = UDim2.new(0.5, 0, 0, px(0))
    titlePill.BackgroundColor3 = T.NAVY_LIGHT
    titlePill.ZIndex = 515
    titlePill.Parent = windowFrame
    Instance.new("UICorner", titlePill).CornerRadius = UDim.new(0, px(10))
    local tpStroke = Instance.new("UIStroke")
    tpStroke.Color = T.GOLD_DIM
    tpStroke.Thickness = 1.5
    tpStroke.Transparency = 0.25
    tpStroke.Parent = titlePill

    local titleText = Instance.new("TextLabel")
    titleText.Name = "Title"
    titleText.Size = UDim2.new(1, 0, 1, 0)
    titleText.BackgroundTransparency = 1
    titleText.Font = Enum.Font.GothamBlack
    titleText.TextScaled = true
    titleText.TextColor3 = T.GOLD
    titleText.Text = "DAILY REWARDS"
    titleText.ZIndex = 516
    titleText.Parent = titlePill

    -- ── Streak label ──────────────────────────────────────────────────────
    streakLabel = Instance.new("TextLabel")
    streakLabel.Name = "StreakLabel"
    streakLabel.Size = UDim2.new(1, 0, 0, px(34))
    streakLabel.Position = UDim2.new(0, 0, 0, px(56))
    streakLabel.BackgroundTransparency = 1
    streakLabel.Font = Enum.Font.GothamBold
    streakLabel.TextSize = tpx(42)
    streakLabel.TextColor3 = T.GOLD_WARM
    streakLabel.Text = ""
    streakLabel.TextXAlignment = Enum.TextXAlignment.Center
    streakLabel.ZIndex = 515
    streakLabel.Parent = windowFrame

    -- ── Subtitle ──────────────────────────────────────────────────────────
    subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Name = "Subtitle"
    subtitleLabel.Size = UDim2.new(1, 0, 0, px(26))
    subtitleLabel.Position = UDim2.new(0, 0, 0, px(94))
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Font = Enum.Font.Gotham
    subtitleLabel.TextSize = tpx(30)
    subtitleLabel.TextColor3 = T.DIM_TEXT
    subtitleLabel.Text = "Come back daily to build your streak!"
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
    subtitleLabel.ZIndex = 515
    subtitleLabel.Parent = windowFrame

    -- ── Day cards container ───────────────────────────────────────────────
    local cardsContainer = Instance.new("Frame")
    cardsContainer.Name = "CardsContainer"
    cardsContainer.Size = UDim2.new(1, 0, 0, px(356))
    cardsContainer.Position = UDim2.new(0, 0, 0, px(126))
    cardsContainer.BackgroundTransparency = 1
    cardsContainer.ZIndex = 512
    cardsContainer.Parent = windowFrame

    local cardsLayout = Instance.new("UIListLayout")
    cardsLayout.FillDirection = Enum.FillDirection.Horizontal
    cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardsLayout.Padding = UDim.new(0, px(8))
    cardsLayout.Parent = cardsContainer

    -- Build 7 day cards
    local cycleDays = (currentState and currentState.cycleDays) or 7
    local rewards = (currentState and currentState.rewards) or {}
    dayCards = {}

    for i = 1, cycleDays do
        local reward = rewards[i] or {}
        local card = buildDayCard(i, reward, cardsContainer)
        dayCards[i] = card
    end

    -- ── Claim button ──────────────────────────────────────────────────────
    claimButton = Instance.new("TextButton")
    claimButton.Name = "ClaimButton"
    claimButton.Size = UDim2.new(0.65, 0, 0, px(60))
    claimButton.AnchorPoint = Vector2.new(0.5, 0)
    claimButton.Position = UDim2.new(0.5, 0, 0, px(490))
    claimButton.BackgroundColor3 = T.GREEN_BTN
    claimButton.TextColor3 = T.WHITE
    claimButton.Font = Enum.Font.GothamBlack
    claimButton.TextSize = tpx(44)
    claimButton.Text = "CLAIM REWARD"
    claimButton.AutoButtonColor = false
    claimButton.BorderSizePixel = 0
    claimButton.ZIndex = 515
    claimButton.Parent = windowFrame

    Instance.new("UICorner", claimButton).CornerRadius = UDim.new(0, px(10))
    local claimStroke = Instance.new("UIStroke")
    claimStroke.Color = T.GREEN_GLOW
    claimStroke.Thickness = 2
    claimStroke.Transparency = 0.3
    claimStroke.Parent = claimButton

    -- scale effect (UIScale inside claim)
    local claimScale = Instance.new("UIScale")
    claimScale.Parent = claimButton

    -- Claim button hover/press
    local claimTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    claimButton.MouseEnter:Connect(function()
        if claimButton.Active then
            tweenProp(claimScale, { Scale = 1.04 }, claimTween)
            tweenProp(claimButton, { BackgroundColor3 = T.GREEN_GLOW }, claimTween)
        end
    end)
    claimButton.MouseLeave:Connect(function()
        tweenProp(claimScale, { Scale = 1 }, claimTween)
        tweenProp(claimButton, { BackgroundColor3 = claimButton.Active and T.GREEN_BTN or T.DISABLED_BG }, claimTween)
    end)
    claimButton.MouseButton1Down:Connect(function()
        if claimButton.Active then
            tweenProp(claimScale, { Scale = 0.96 }, TweenInfo.new(0.06))
        end
    end)
    claimButton.MouseButton1Up:Connect(function()
        tweenProp(claimScale, { Scale = 1 }, claimTween)
    end)

    claimButton.Activated:Connect(function()
        if claimCooldown then return end
        if not claimButton.Active then return end
        claimCooldown = true
        claimButton.Active = false
        claimButton.Text = "CLAIMING..."

        if type(onClaimCallback) == "function" then
            task.spawn(function()
                local ok = pcall(onClaimCallback)
                -- Cooldown released by Refresh call after server responds
                task.delay(2, function()
                    claimCooldown = false
                end)
            end)
        else
            task.delay(1, function() claimCooldown = false end)
        end
    end)

    -- ── Next reward preview ───────────────────────────────────────────────
    nextRewardLabel = Instance.new("TextLabel")
    nextRewardLabel.Name = "NextReward"
    nextRewardLabel.Size = UDim2.new(1, 0, 0, px(28))
    nextRewardLabel.Position = UDim2.new(0, 0, 0, px(556))
    nextRewardLabel.BackgroundTransparency = 1
    nextRewardLabel.Font = Enum.Font.Gotham
    nextRewardLabel.TextSize = tpx(30)
    nextRewardLabel.TextColor3 = T.DIM_TEXT
    nextRewardLabel.Text = ""
    nextRewardLabel.TextXAlignment = Enum.TextXAlignment.Center
    nextRewardLabel.ZIndex = 515
    nextRewardLabel.Parent = windowFrame

    popup = overlayFrame

    -- Initial refresh
    DailyRewardsUI.Refresh(currentState)

    return popup
end

--------------------------------------------------------------------------------
-- Refresh all UI from state data
--------------------------------------------------------------------------------
function DailyRewardsUI.Refresh(state)
    currentState = state or currentState or {}

    local streak = currentState.currentStreak or 0
    local canClaim = currentState.canClaimToday
    local alreadyClaimed = currentState.alreadyClaimed
    local rewards = currentState.rewards or {}

    -- Update streak label
    if streakLabel then
        if streak > 0 then
            streakLabel.Text = "Current Streak: " .. tostring(streak) .. " Day" .. (streak == 1 and "" or "s")
        else
            streakLabel.Text = "Start your streak today!"
        end
    end

    -- Update day cards
    for i, cardData in ipairs(dayCards) do
        local reward = rewards[i]
        if reward then
            updateCardVisual(cardData, reward.status or "future")
        end
    end

    -- Update claim button
    if claimButton then
        if canClaim and not alreadyClaimed then
            claimButton.Active = true
            claimButton.BackgroundColor3 = T.GREEN_BTN
            claimButton.Text = "CLAIM REWARD"
            claimButton.TextColor3 = T.WHITE
            claimCooldown = false
            -- Restore claim button stroke for active state
            local claimStrokeActive = claimButton:FindFirstChildWhichIsA("UIStroke")
            if claimStrokeActive then
                claimStrokeActive.Color = T.GREEN_GLOW
                claimStrokeActive.Transparency = 0.3
            end
        else
            claimButton.Active = false
            if alreadyClaimed then
                claimButton.BackgroundColor3 = Color3.fromRGB(20, 28, 26)
                claimButton.TextColor3 = T.GOLD_DIM
                claimButton.Text = "\u{2713}  CLAIMED TODAY"
            else
                claimButton.BackgroundColor3 = T.DISABLED_BG
                claimButton.TextColor3 = T.DIM_TEXT
                claimButton.Text = "COME BACK TOMORROW"
            end
            -- Update claim button stroke to match non-active state
            local claimStrokeObj = claimButton:FindFirstChildWhichIsA("UIStroke")
            if claimStrokeObj then
                if alreadyClaimed then
                    claimStrokeObj.Color = Color3.fromRGB(65, 90, 70)
                    claimStrokeObj.Transparency = 0.4
                else
                    claimStrokeObj.Color = T.CARD_STROKE
                    claimStrokeObj.Transparency = 0.5
                end
            end
        end
    end

    -- Next reward preview
    if nextRewardLabel then
        if currentState.nextPreview then
            local np = currentState.nextPreview
            nextRewardLabel.Text = "Tomorrow: " .. (np.displayName or "")
            nextRewardLabel.Visible = true
        else
            nextRewardLabel.Visible = false
        end
    end
end

--------------------------------------------------------------------------------
-- Claim success animation (called after server confirms claim)
--------------------------------------------------------------------------------
function DailyRewardsUI.PlayClaimAnimation(dayIndex)
    if not dayCards[dayIndex] then return end
    local cardData = dayCards[dayIndex]

    -- Pulse the card briefly white then settle to claimed state
    local flashInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    tweenProp(cardData.frame, { BackgroundColor3 = T.GOLD_WARM }, flashInfo)

    task.delay(0.2, function()
        local settleInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        tweenProp(cardData.frame, { BackgroundColor3 = T.CARD_OWNED }, settleInfo)
        updateCardVisual(cardData, "claimed")
    end)

    -- Scale pop on checkmark
    task.delay(0.15, function()
        if cardData.checkOverlay then
            cardData.checkOverlay.Visible = true
            cardData.checkOverlay.Size = UDim2.new(0, px(4), 0, px(4))
            tweenProp(cardData.checkOverlay, {
                Size = UDim2.new(0, px(36), 0, px(36))
            }, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
        end
    end)
end

--------------------------------------------------------------------------------
-- Open / Close with animation
--------------------------------------------------------------------------------
function DailyRewardsUI.Open()
    if isOpen or isAnimating then return end
    if not overlayFrame then return end

    isAnimating = true
    isOpen = true
    overlayFrame.Visible = true

    -- Start scaled down + transparent
    windowFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    local winScale = windowFrame:FindFirstChildOfClass("UIScale")
    if not winScale then
        winScale = Instance.new("UIScale")
        winScale.Parent = windowFrame
    end
    winScale.Scale = 0.85
    overlayFrame.BackgroundTransparency = 1
    windowFrame.BackgroundTransparency = 1

    -- Animate in
    local inInfo = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local fadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    tweenProp(overlayFrame, { BackgroundTransparency = 0.45 }, fadeInfo)
    tweenProp(windowFrame, { BackgroundTransparency = 0.02 }, fadeInfo)
    local tw = tweenProp(winScale, { Scale = 1 }, inInfo)

    if tw then
        tw.Completed:Connect(function()
            isAnimating = false
        end)
    else
        isAnimating = false
    end
end

function DailyRewardsUI.Close()
    if not isOpen or isAnimating then return end
    isAnimating = true

    local outInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local winScale = windowFrame and windowFrame:FindFirstChildOfClass("UIScale")

    if winScale then
        tweenProp(winScale, { Scale = 0.9 }, outInfo)
    end
    tweenProp(overlayFrame, { BackgroundTransparency = 1 }, outInfo)
    local tw = tweenProp(windowFrame, { BackgroundTransparency = 1 }, outInfo)

    local function finishClose()
        isOpen = false
        isAnimating = false
        if overlayFrame then overlayFrame.Visible = false end
        if type(onCloseCallback) == "function" then
            pcall(onCloseCallback)
        end
    end

    if tw then
        tw.Completed:Connect(finishClose)
    else
        finishClose()
    end
end

function DailyRewardsUI.IsOpen()
    return isOpen
end

function DailyRewardsUI.Destroy()
    isOpen = false
    isAnimating = false
    -- Clean up pulse tweens
    for _, tw in pairs(pulseConns) do
        pcall(function() tw:Cancel() end)
    end
    pulseConns = {}
    dayCards = {}
    if popup then
        pcall(function() popup:Destroy() end)
        popup = nil
    end
    overlayFrame = nil
    windowFrame = nil
    claimButton = nil
    streakLabel = nil
    subtitleLabel = nil
    nextRewardLabel = nil
end

return DailyRewardsUI
