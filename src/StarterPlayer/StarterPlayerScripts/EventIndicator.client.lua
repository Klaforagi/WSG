--[[
    EventIndicator.client.lua  (StarterPlayerScripts)
    Shows a clickable "EVENT" card inside the left-side menu panel
    whenever the server signals that a timed event is active.

    The card is inserted directly into the MainUICard panel's
    UIListLayout at LayoutOrder 100, so it sits below the existing
    buttons (Quests, Upgrade, Team) as part of the natural stack.
    A timer label sits at LayoutOrder 101 directly below the card.
    The panel's AutomaticSize.Y grows/shrinks cleanly when the
    event activates or ends — no manual absolute positioning needed.

    Features:
      - Clickable event card that toggles a modal-style event popup
      - Separate countdown timer label below the Event button
      - Event popup matches the KingsGround menu window style
      - All UI is created when event activates and destroyed when it ends

    Event card layer stack (bottom to top):
      1. Base frame  (dark background + gradient)           ZIndex 0
      2. SilhouetteArt  (medieval battle atmosphere)        ZIndex 1
      3. TeamPulseOverlay  (team-coloured tint, animates)   ZIndex 2
      4. GoldBorderStroke  (UIStroke on base frame)         ZIndex n/a
      5. EventLabel + Shadow  (centered "EVENT" text)       ZIndex 9-10
      6. ClickOverlay  (transparent button for clicks)      ZIndex 11

    Pulse animation:
      - Starts inside createIndicator() after all layers are built
      - Runs in pulseThread (task.spawn loop)
      - Tweens TeamPulseOverlay.BackgroundTransparency between
        PULSE_MIN_TRANSPARENCY (strong tint) and PULSE_MAX_TRANSPARENCY (weak tint)
      - Stops in destroyIndicator() via task.cancel + tween cleanup
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Load shared config
local EventConfig
do
    local mod = ReplicatedStorage:WaitForChild("EventConfig", 10)
    if mod then
        local ok, cfg = pcall(require, mod)
        if ok then EventConfig = cfg end
    end
end

---------------------------------------------------------------------
-- Tunable pulse constants
---------------------------------------------------------------------
local PULSE_BLUE_COLOR       = Color3.fromRGB(40, 90, 220)   -- blue team overlay
local PULSE_RED_COLOR        = Color3.fromRGB(220, 45, 45)   -- red team overlay
local PULSE_MIN_TRANSPARENCY = 0.25                           -- strongest tint (most visible)
local PULSE_MAX_TRANSPARENCY = 0.70                           -- weakest tint  (background shows through)
local PULSE_CYCLE            = (EventConfig and EventConfig.PULSE_CYCLE) or 1.75

---------------------------------------------------------------------
-- Responsive pixel helper (mirrors SideUI.px)
---------------------------------------------------------------------
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local deviceTextScale = 1.0  -- always 1.0; old 0.75 desktop scale killed readability

---------------------------------------------------------------------
-- Colour helpers
---------------------------------------------------------------------
local COLORS = {
    gold      = Color3.fromRGB(255, 215, 80),
    brown     = Color3.fromRGB(122, 85, 46),
    darkBase  = Color3.fromRGB(8, 10, 20),
    ember     = Color3.fromRGB(180, 70, 20),
}

local function getTeamPulseColor()
    local team = player and player.Team
    if team and team.Name == "Blue" then
        return PULSE_BLUE_COLOR
    elseif team and team.Name == "Red" then
        return PULSE_RED_COLOR
    end
    return PULSE_BLUE_COLOR -- default fallback
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local currentCard       = nil   -- the Frame inserted into the panel
local pulseThread       = nil   -- coroutine running the pulse loop
local pulseTweens       = {}    -- current active tweens (for cleanup)
local eventPopup        = nil   -- the popup ScreenGui (overlay + window)
local eventEndTime      = nil   -- server timestamp when event ends
local timerConnection   = nil   -- Heartbeat connection for live timer
local timerLabel        = nil   -- separate timer TextLabel below the Event card
local popupTimerLabel   = nil   -- timer TextLabel inside the popup
local popupVisible      = false -- whether the popup is shown
local objectiveTracker  = nil   -- right-side objective tracker ScreenGui
local trackerObjLabel   = nil   -- TextLabel that shows shard progress
local shardProgressConn = nil   -- connection for EventShardProgress remote

---------------------------------------------------------------------
-- Current event definition (read from EventConfig)
---------------------------------------------------------------------
local function getEventDef()
    if not EventConfig then return nil end
    local id = EventConfig.ActiveEventId
    if id and EventConfig.EventDefs then
        return EventConfig.EventDefs[id]
    end
    return nil
end

---------------------------------------------------------------------
-- Time formatting — M:SS when >= 60, otherwise just seconds
---------------------------------------------------------------------
local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d:%02d", m, s)
    end
    return tostring(seconds)
end



---------------------------------------------------------------------
-- Cleanup — stops pulse, cancels tweens, destroys card/timer/popup
---------------------------------------------------------------------
local function destroyIndicator()
    if shardProgressConn then
        pcall(function() shardProgressConn:Disconnect() end)
        shardProgressConn = nil
    end
    if timerConnection then
        pcall(function() timerConnection:Disconnect() end)
        timerConnection = nil
    end
    if pulseThread then
        pcall(task.cancel, pulseThread)
        pulseThread = nil
    end
    for _, tw in ipairs(pulseTweens) do
        pcall(function() tw:Cancel() end)
    end
    pulseTweens = {}
    if eventPopup then
        pcall(function() eventPopup:Destroy() end)
        eventPopup = nil
    end
    if objectiveTracker then
        pcall(function() objectiveTracker:Destroy() end)
        objectiveTracker = nil
    end
    trackerObjLabel = nil
    popupVisible = false
    popupTimerLabel = nil
    eventEndTime = nil
    if timerLabel then
        pcall(function() timerLabel:Destroy() end)
        timerLabel = nil
    end
    if currentCard then
        pcall(function() currentCard:Destroy() end)
        currentCard = nil
    end
end

---------------------------------------------------------------------
-- Layer 2: Decorative silhouette art (medieval battle atmosphere)
-- Lighter shapes against the dark card base (~30-60 RGB vs ~8-14).
---------------------------------------------------------------------
local function buildSilhouetteArt(parent)
    local artContainer = Instance.new("Frame")
    artContainer.Name = "SilhouetteArt"
    artContainer.BackgroundTransparency = 1
    artContainer.Size = UDim2.new(1, 0, 1, 0)
    artContainer.ZIndex = 1
    artContainer.ClipsDescendants = true
    artContainer.Parent = parent

    local function sil(name, pos, size, color, transparency, rotation)
        local f = Instance.new("Frame")
        f.Name = name
        f.BackgroundColor3 = color or Color3.fromRGB(28, 32, 52)
        f.BackgroundTransparency = transparency or 0.40
        f.BorderSizePixel = 0
        f.Size = size
        f.Position = pos
        f.Rotation = rotation or 0
        f.ZIndex = 1
        f.Parent = artContainer
        return f
    end

    -- Ground / horizon line
    sil("Ground", UDim2.new(0, 0, 0.78, 0), UDim2.new(1, 0, 0.22, 0),
        Color3.fromRGB(22, 24, 40), 0.25)

    -- Left tower silhouette
    local tower1 = sil("Tower1", UDim2.new(0.04, 0, 0.22, 0), UDim2.new(0.10, 0, 0.58, 0),
        Color3.fromRGB(30, 34, 54), 0.30)
    local t1corner = Instance.new("UICorner")
    t1corner.CornerRadius = UDim.new(0, px(3))
    t1corner.Parent = tower1

    -- Tower 1 battlement
    sil("T1Top", UDim2.new(0.02, 0, 0.18, 0), UDim2.new(0.14, 0, 0.08, 0),
        Color3.fromRGB(30, 34, 54), 0.30)

    -- Right tower (taller, thinner)
    local tower2 = sil("Tower2", UDim2.new(0.82, 0, 0.15, 0), UDim2.new(0.08, 0, 0.65, 0),
        Color3.fromRGB(26, 30, 48), 0.35)
    local t2corner = Instance.new("UICorner")
    t2corner.CornerRadius = UDim.new(0, px(2))
    t2corner.Parent = tower2

    -- Tower 2 spire
    sil("T2Spire", UDim2.new(0.83, 0, 0.08, 0), UDim2.new(0.06, 0, 0.10, 0),
        Color3.fromRGB(26, 30, 48), 0.38)

    -- Left banner (angled flag on tower)
    sil("Banner1", UDim2.new(0.12, 0, 0.28, 0), UDim2.new(0.08, 0, 0.12, 0),
        Color3.fromRGB(34, 30, 50), 0.40, 15)

    -- Mid-ground wall segment
    sil("Wall", UDim2.new(0.18, 0, 0.58, 0), UDim2.new(0.60, 0, 0.22, 0),
        Color3.fromRGB(24, 26, 42), 0.45)

    -- Smoke / haze wisps
    sil("Smoke1", UDim2.new(0.25, 0, 0.30, 0), UDim2.new(0.20, 0, 0.14, 0),
        Color3.fromRGB(40, 38, 55), 0.60)
    sil("Smoke2", UDim2.new(0.55, 0, 0.24, 0), UDim2.new(0.18, 0, 0.12, 0),
        Color3.fromRGB(40, 38, 55), 0.65)

    -- Faint ember glow at base
    local ember = sil("Ember", UDim2.new(0.30, 0, 0.72, 0), UDim2.new(0.40, 0, 0.10, 0),
        COLORS.ember, 0.72)
    local emberCorner = Instance.new("UICorner")
    emberCorner.CornerRadius = UDim.new(1, 0)
    emberCorner.Parent = ember

    -- Small dragon/bird silhouette
    sil("DragonWingL", UDim2.new(0.62, 0, 0.18, 0), UDim2.new(0.06, 0, 0.04, 0),
        Color3.fromRGB(32, 36, 56), 0.42, -20)
    sil("DragonWingR", UDim2.new(0.67, 0, 0.17, 0), UDim2.new(0.06, 0, 0.04, 0),
        Color3.fromRGB(32, 36, 56), 0.42, 20)
    sil("DragonBody", UDim2.new(0.645, 0, 0.185, 0), UDim2.new(0.035, 0, 0.025, 0),
        Color3.fromRGB(32, 36, 56), 0.38)

    return artContainer
end

---------------------------------------------------------------------
-- Build the event popup (modal-style window matching KingsGround menus)
---------------------------------------------------------------------
local TWEEN_IN_INFO  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local popupShowFn  -- forward-declare closures for togglePopup access
local popupHideFn

local function createEventPopup()
    if eventPopup then return end

    local def = getEventDef()
    local eventName = def and def.Name     or "Event"
    local objective = def and def.Objective or "..."
    local reward    = def and def.Reward    or "..."

    -- Dedicated ScreenGui so the popup renders above other HUD
    local popupGui = Instance.new("ScreenGui")
    popupGui.Name = "EventPopupGui"
    popupGui.ResetOnSpawn = false
    popupGui.IgnoreGuiInset = true
    popupGui.DisplayOrder = 260
    popupGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    popupGui.Parent = playerGui

    -- Semi-transparent overlay (click to close)
    local overlay = Instance.new("TextButton")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundTransparency = 0.5
    overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    overlay.Text = ""
    overlay.AutoButtonColor = false
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 1
    overlay.Visible = false
    overlay.Parent = popupGui

    -- Window frame — matches SideUI modal style
    local window = Instance.new("Frame")
    window.Name = "EventWindow"
    window.Size = UDim2.new(0.40, 0, 0.50, 0)
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.Position = UDim2.new(0.5, 0, -0.35, 0) -- start offscreen
    window.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
    window.BackgroundTransparency = 0.04
    window.BorderSizePixel = 0
    window.ClipsDescendants = true
    window.ZIndex = 10
    window.Parent = popupGui

    local winCorner = Instance.new("UICorner")
    winCorner.CornerRadius = UDim.new(0, px(14))
    winCorner.Parent = window

    local winStroke = Instance.new("UIStroke")
    winStroke.Color = Color3.fromRGB(180, 150, 50)
    winStroke.Thickness = 2.0
    winStroke.Transparency = 0.15
    winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    winStroke.Parent = window

    local winGrad = Instance.new("UIGradient")
    winGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
    })
    winGrad.Rotation = 90
    winGrad.Parent = window

    local winPad = Instance.new("UIPadding")
    winPad.PaddingTop    = UDim.new(0, px(18))
    winPad.PaddingBottom = UDim.new(0, px(20))
    winPad.PaddingLeft   = UDim.new(0, px(20))
    winPad.PaddingRight  = UDim.new(0, px(20))
    winPad.Parent = window

    -- ── Header bar ──────────────────────────────────────────────────
    local HEADER_H = 0.14
    local headerBar = Instance.new("Frame")
    headerBar.Name = "HeaderBar"
    headerBar.Size = UDim2.new(1, 0, HEADER_H, 0)
    headerBar.BackgroundTransparency = 1
    headerBar.ZIndex = 20
    headerBar.Parent = window

    -- Title pill (matches other menus)
    local titlePill = Instance.new("Frame")
    titlePill.Name = "TitlePill"
    titlePill.Size = UDim2.new(0.65, 0, 0.85, 0)
    titlePill.AnchorPoint = Vector2.new(0.5, 0.5)
    titlePill.Position = UDim2.new(0.5, 0, 0.5, 0)
    titlePill.BackgroundColor3 = Color3.fromRGB(22, 26, 48)
    titlePill.ZIndex = 20
    titlePill.Parent = headerBar

    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(0, px(8))
    pillCorner.Parent = titlePill

    local pillStroke = Instance.new("UIStroke")
    pillStroke.Color = Color3.fromRGB(180, 150, 50)
    pillStroke.Thickness = 2.0
    pillStroke.Transparency = 0.25
    pillStroke.Parent = titlePill

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "TitleLabel"
    titleLbl.Size = UDim2.new(1, 0, 1, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBlack
    titleLbl.TextScaled = false
    titleLbl.TextSize = px(24)
    titleLbl.TextColor3 = COLORS.gold
    titleLbl.Text = string.upper(eventName)
    titleLbl.ZIndex = 21
    titleLbl.Parent = titlePill

    local titleStroke = Instance.new("UIStroke")
    titleStroke.Color = Color3.fromRGB(30, 20, 6)
    titleStroke.Thickness = 1.5
    titleStroke.Transparency = 0.1
    titleStroke.Parent = titleLbl

    -- Close X button (matches other menus)
    local CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
    local CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBlack
    closeBtn.TextScaled = true
    closeBtn.Size = UDim2.new(0.08, 0, HEADER_H * 0.85, 0)
    closeBtn.SizeConstraint = Enum.SizeConstraint.RelativeYY
    closeBtn.AnchorPoint = Vector2.new(1, 0)
    closeBtn.Position = UDim2.new(1, 0, 0, 0)
    closeBtn.BackgroundColor3 = CLOSE_DEFAULT
    closeBtn.TextColor3 = COLORS.gold
    closeBtn.AutoButtonColor = false
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 25
    closeBtn.Parent = window

    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, px(8))
    closeBtnCorner.Parent = closeBtn

    local closeBtnStroke = Instance.new("UIStroke")
    closeBtnStroke.Color = COLORS.gold
    closeBtnStroke.Thickness = 1.2
    closeBtnStroke.Transparency = 0.4
    closeBtnStroke.Parent = closeBtn

    local closeFeedback = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_HOVER}):Play()
        TweenService:Create(closeBtn, closeFeedback, {TextColor3 = Color3.new(1, 1, 1)}):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_DEFAULT}):Play()
        TweenService:Create(closeBtn, closeFeedback, {TextColor3 = COLORS.gold}):Play()
    end)

    -- ── Content area (below header) ─────────────────────────────────
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1 - HEADER_H - 0.04, 0)
    content.Position = UDim2.new(0, 0, HEADER_H + 0.02, 0)
    content.BackgroundTransparency = 1
    content.ZIndex = 15
    content.Parent = window

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, px(14))
    contentLayout.Parent = content

    local contentPad = Instance.new("UIPadding")
    contentPad.PaddingTop   = UDim.new(0, px(14))
    contentPad.PaddingLeft  = UDim.new(0, px(10))
    contentPad.PaddingRight = UDim.new(0, px(10))
    contentPad.Parent = content

    -- Helper: create a styled info row (label + value card)
    local function addInfoCard(labelText, valueText, valueColor, order)
        local row = Instance.new("Frame")
        row.Name = labelText .. "Row"
        row.LayoutOrder = order
        row.Size = UDim2.new(1, 0, 0, px(68))
        row.BackgroundColor3 = Color3.fromRGB(26, 30, 48)
        row.BackgroundTransparency = 0
        row.BorderSizePixel = 0
        row.ZIndex = 16
        row.Parent = content

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, px(6))
        rowCorner.Parent = row

        local rowGrad = Instance.new("UIGradient")
        rowGrad.Color = ColorSequence.new(
            Color3.fromRGB(30, 35, 55),
            Color3.fromRGB(22, 26, 42)
        )
        rowGrad.Parent = row

        local rowPad = Instance.new("UIPadding")
        rowPad.PaddingLeft  = UDim.new(0, px(14))
        rowPad.PaddingRight = UDim.new(0, px(14))
        rowPad.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Name = "Label"
        lbl.Size = UDim2.new(1, 0, 0.42, 0)
        lbl.Position = UDim2.new(0, 0, 0.06, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(145, 150, 175)
        lbl.TextSize = px(16)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 17
        lbl.Parent = row

        local val = Instance.new("TextLabel")
        val.Name = "Value"
        val.Size = UDim2.new(1, 0, 0.50, 0)
        val.Position = UDim2.new(0, 0, 0.46, 0)
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.GothamBold
        val.Text = valueText
        val.TextColor3 = valueColor
        val.TextSize = px(20)
        val.TextXAlignment = Enum.TextXAlignment.Left
        val.ZIndex = 17
        val.Parent = row

        return val
    end

    addInfoCard("Objective", objective, Color3.fromRGB(245, 245, 252), 1)
    addInfoCard("Reward", reward, COLORS.gold, 2)
    local timeValLabel = addInfoCard("Time Remaining", "--:--", Color3.fromRGB(245, 245, 252), 3)
    popupTimerLabel = timeValLabel

    -- ── Tween helpers ───────────────────────────────────────────────
    popupShowFn = function()
        overlay.Visible = true
        local tw = TweenService:Create(window, TWEEN_IN_INFO, {
            Position = UDim2.new(0.5, 0, 0.5, 0),
        })
        tw:Play()
    end

    popupHideFn = function()
        local tw = TweenService:Create(window, TWEEN_OUT_INFO, {
            Position = UDim2.new(0.5, 0, -0.35, 0),
        })
        tw:Play()
        tw.Completed:Connect(function()
            overlay.Visible = false
        end)
    end

    -- Wire close actions
    closeBtn.Activated:Connect(function()
        if popupVisible then
            popupVisible = false
            popupHideFn()
        end
    end)
    overlay.Activated:Connect(function()
        if popupVisible then
            popupVisible = false
            popupHideFn()
        end
    end)

    eventPopup = popupGui
    -- Register EventPopup GUI with MenuState so visibility is authoritative
    do
        local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
        if sideUI then
            local ms = sideUI:FindFirstChild("MenuState")
            if ms then
                pcall(function()
                    local menuState = require(ms)
                    if menuState and menuState.RegisterMenu then
                        menuState.RegisterMenu("EventPopup", { gui = eventPopup, isOpen = function() return popupVisible end })
                    end
                end)
            end
        end
    end
end

---------------------------------------------------------------------
-- Toggle the event popup open/closed
---------------------------------------------------------------------
-- MenuController integration: register EventPopup so the global
-- menu-lock system knows when this popup is open.
local EventMenuController = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    if sideUI then
        local mc = sideUI:FindFirstChild("MenuController")
        if mc then EventMenuController = require(mc) end
    end
end)

local eventPopupRegistered = false
local function ensureEventPopupRegistered()
    if eventPopupRegistered or not EventMenuController then return end
    eventPopupRegistered = true
    EventMenuController.RegisterMenu("EventPopup", {
        open = function() end, -- opened by togglePopup directly
        close = function()
            if popupVisible and popupHideFn then
                popupVisible = false
                popupHideFn()
            end
        end,
        closeInstant = function()
            if popupVisible and popupHideFn then
                popupVisible = false
                popupHideFn()
            end
        end,
        isOpen = function()
            return popupVisible
        end,
    })
end

local function togglePopup()
    if not eventPopup then return end
    ensureEventPopupRegistered()
    popupVisible = not popupVisible
    if popupVisible then
        -- Notify MenuController that this popup is opening
        if EventMenuController and eventPopupRegistered then
            EventMenuController.CloseAllMenus("EventPopup")
        end
        popupShowFn()
        -- Fire state change callback manually since we bypass OpenMenu
        if EventMenuController and EventMenuController.OnMenuStateChanged then
            -- The callback system is fired via OpenMenu normally, but since
            -- we toggle directly, we need the polling fallback in
            -- MenuLockEnforcer to catch this. That 0.25s poll handles it.
        end
    else
        popupHideFn()
    end
end

---------------------------------------------------------------------
-- Build the event card
---------------------------------------------------------------------
local function createIndicator()
    destroyIndicator()

    -- Find the MainUICard panel inside the MainUI ScreenGui
    local mainUI = playerGui:FindFirstChild("MainUI")
    if not mainUI then
        mainUI = playerGui:WaitForChild("MainUI", 5)
    end
    if not mainUI then
        warn("[EventIndicator] MainUI not found – cannot show event card")
        return
    end
    local panel = mainUI:FindFirstChild("MainUICard")
    if not panel then
        panel = mainUI:WaitForChild("MainUICard", 5)
    end
    if not panel then
        warn("[EventIndicator] MainUICard not found – cannot show event card")
        return
    end

    -- Card height: similar to the Shop/Inventory row
    local function calcCardHeight()
        local screenY = 720
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then screenY = cam.ViewportSize.Y end
        return math.max(42, math.floor(screenY * 0.075))
    end
    local cardH = calcCardHeight()

    -----------------------------------------------------------------
    -- Clean up any stale EventCard / EventTimerLabel left over from
    -- a previous indicator (prevents duplicates).
    -----------------------------------------------------------------
    for _, child in ipairs(panel:GetChildren()) do
        if child.Name == "EventCard" or child.Name == "EventTimerLabel" then
            pcall(function() child:Destroy() end)
        end
    end

    -----------------------------------------------------------------
    -- LAYER 1: Base frame (dark background + gradient)
    -- Inserted directly into MainUICard's UIListLayout at
    -- LayoutOrder 100 so it sits below the menu grid.
    -----------------------------------------------------------------
    local card = Instance.new("Frame")
    card.Name = "EventCard"
    card.LayoutOrder = 100
    card.Size = UDim2.new(1, 0, 0, cardH)
    card.BackgroundColor3 = COLORS.darkBase
    card.BackgroundTransparency = 0
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = panel
    currentCard = card

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, px(8))
    cardCorner.Parent = card

    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 12, 26)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 18)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 8, 16)),
    })
    bgGrad.Rotation = 90
    bgGrad.Parent = card

    -----------------------------------------------------------------
    -- LAYER 2: Silhouette art (background art — always visible)
    -----------------------------------------------------------------
    buildSilhouetteArt(card)

    -----------------------------------------------------------------
    -- LAYER 3: Team-coloured pulse overlay
    -- This is the overlay whose transparency is animated by the pulse.
    -- It tints the entire card with the local player's team colour.
    -----------------------------------------------------------------
    local teamPulseOverlay = Instance.new("Frame")
    teamPulseOverlay.Name = "TeamPulseOverlay"
    teamPulseOverlay.BackgroundColor3 = getTeamPulseColor()
    teamPulseOverlay.BackgroundTransparency = PULSE_MAX_TRANSPARENCY
    teamPulseOverlay.Size = UDim2.new(1, 0, 1, 0)
    teamPulseOverlay.BorderSizePixel = 0
    teamPulseOverlay.ZIndex = 2
    teamPulseOverlay.Parent = card

    local pulseOverlayCorner = Instance.new("UICorner")
    pulseOverlayCorner.CornerRadius = UDim.new(0, px(8))
    pulseOverlayCorner.Parent = teamPulseOverlay

    -- Update overlay color when team changes
    player:GetPropertyChangedSignal("Team"):Connect(function()
        pcall(function()
            teamPulseOverlay.BackgroundColor3 = getTeamPulseColor()
        end)
    end)

    -----------------------------------------------------------------
    -- LAYER 4: Gold border stroke (always visible, sits on base frame)
    -----------------------------------------------------------------
    local goldStroke = Instance.new("UIStroke")
    goldStroke.Name = "GoldBorderStroke"
    goldStroke.Color = COLORS.gold
    goldStroke.Thickness = 2
    goldStroke.Transparency = 0.15
    goldStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    goldStroke.Parent = card

    -----------------------------------------------------------------
    -- LAYER 5: "EVENT" label + shadow (centered on card)
    -----------------------------------------------------------------
    local shadow = Instance.new("TextLabel")
    shadow.Name = "Shadow"
    shadow.BackgroundTransparency = 1
    shadow.Size = UDim2.new(0.9, 0, 0.85, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.new(0.5, px(1), 0.5, px(1))
    shadow.Font = Enum.Font.GothamBold
    shadow.Text = "EVENT"
    shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    shadow.TextTransparency = 0.55
    shadow.TextSize = math.max(13, math.floor(cardH * 0.50 * deviceTextScale))
    shadow.TextXAlignment = Enum.TextXAlignment.Center
    shadow.TextYAlignment = Enum.TextYAlignment.Center
    shadow.ZIndex = 9
    shadow.Parent = card

    local label = Instance.new("TextLabel")
    label.Name = "EventLabel"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.9, 0, 0.85, 0)
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.new(0.5, 0, 0.5, 0)
    label.Font = Enum.Font.GothamBold
    label.Text = "EVENT"
    label.TextColor3 = COLORS.gold
    label.TextSize = math.max(13, math.floor(cardH * 0.50 * deviceTextScale))
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 10
    label.Parent = card

    local labelStroke = Instance.new("UIStroke")
    labelStroke.Color = Color3.fromRGB(30, 20, 6)
    labelStroke.Thickness = 1
    labelStroke.Transparency = 0.1
    labelStroke.Parent = label

    -----------------------------------------------------------------
    -- LAYER 6: Click overlay (transparent button on top of all layers)
    -----------------------------------------------------------------
    local clickBtn = Instance.new("TextButton")
    clickBtn.Name = "ClickOverlay"
    clickBtn.Size = UDim2.new(1, 0, 1, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.AutoButtonColor = false
    clickBtn.ZIndex = 11
    clickBtn.Parent = card

    clickBtn.Activated:Connect(function()
        togglePopup()
    end)

    -----------------------------------------------------------------
    -- Separate timer label below the card
    -----------------------------------------------------------------
    local tmrLbl = Instance.new("TextLabel")
    tmrLbl.Name = "EventTimerLabel"
    tmrLbl.LayoutOrder = 101
    tmrLbl.Size = UDim2.new(1, 0, 0, px(26))
    tmrLbl.BackgroundTransparency = 1
    tmrLbl.Font = Enum.Font.GothamBold
    tmrLbl.Text = "--:--"
    tmrLbl.TextColor3 = Color3.fromRGB(235, 235, 245)
    tmrLbl.TextSize = px(15)
    tmrLbl.TextXAlignment = Enum.TextXAlignment.Center
    tmrLbl.ZIndex = 10
    tmrLbl.Parent = panel  -- inside the panel UIListLayout, below the card
    timerLabel = tmrLbl

    local tmrStroke = Instance.new("UIStroke")
    tmrStroke.Color = Color3.fromRGB(0, 0, 0)
    tmrStroke.Thickness = 1.2
    tmrStroke.Transparency = 0.1
    tmrStroke.Parent = tmrLbl

    -----------------------------------------------------------------
    -- Build the event popup (hidden by default)
    -----------------------------------------------------------------
    createEventPopup()

    -----------------------------------------------------------------
    -- Right-side objective tracker (lightweight HUD element)
    -----------------------------------------------------------------
    do
        -- Clean up any leftover tracker (prevents duplicates)
        if objectiveTracker then
            pcall(function() objectiveTracker:Destroy() end)
            objectiveTracker = nil
        end

        local def = getEventDef()
        local evtName   = def and def.Name     or "Event"
        local objective = def and def.Objective or "..."

        local trackerGui = Instance.new("ScreenGui")
        trackerGui.Name = "EventObjectiveTracker"
        trackerGui.ResetOnSpawn = false
        trackerGui.IgnoreGuiInset = false
        trackerGui.DisplayOrder = 240 -- lower than MainUI (250) so modals render above
        trackerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        trackerGui.Parent = playerGui

        -- Main container — anchored to the right side, below the top HUD
        local container = Instance.new("Frame")
        container.Name = "TrackerContainer"
        container.Size = UDim2.new(0, px(460), 0, px(120))
        container.AnchorPoint = Vector2.new(1, 0)
        container.Position = UDim2.new(1, -px(14), 0, px(90))
        container.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
        container.BackgroundTransparency = 0.10
        container.BorderSizePixel = 0
        container.Parent = trackerGui

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, px(12))
        cCorner.Parent = container

        local cStroke = Instance.new("UIStroke")
        cStroke.Color = Color3.fromRGB(180, 150, 50)
        cStroke.Thickness = 2
        cStroke.Transparency = 0.2
        cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        cStroke.Parent = container

        local cGrad = Instance.new("UIGradient")
        cGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 190)),
        })
        cGrad.Rotation = 90
        cGrad.Parent = container

        local cPad = Instance.new("UIPadding")
        cPad.PaddingTop    = UDim.new(0, px(20))
        cPad.PaddingBottom = UDim.new(0, px(20))
        cPad.PaddingLeft   = UDim.new(0, px(24))
        cPad.PaddingRight  = UDim.new(0, px(24))
        cPad.Parent = container

        local cLayout = Instance.new("UIListLayout")
        cLayout.SortOrder = Enum.SortOrder.LayoutOrder
        cLayout.Padding = UDim.new(0, px(10))
        cLayout.Parent = container

        -- Title line: "Event: Meteor Shower"
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name = "TrackerTitle"
        titleLbl.LayoutOrder = 1
        titleLbl.Size = UDim2.new(1, 0, 0, px(34))
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextSize = px(25)
        titleLbl.TextColor3 = COLORS.gold
        titleLbl.Text = "Event: " .. evtName
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
        titleLbl.Parent = container

        local titleStroke = Instance.new("UIStroke")
        titleStroke.Color = Color3.fromRGB(0, 0, 0)
        titleStroke.Thickness = 1
        titleStroke.Transparency = 0.15
        titleStroke.Parent = titleLbl

        -- Objective line: "- Collect 3 Meteor Shards (0/3)"
        local objLbl = Instance.new("TextLabel")
        objLbl.Name = "TrackerObjective"
        objLbl.LayoutOrder = 2
        objLbl.Size = UDim2.new(1, 0, 0, px(30))
        objLbl.BackgroundTransparency = 1
        objLbl.Font = Enum.Font.Gotham
        objLbl.TextSize = px(20)
        objLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
        objLbl.Text = "- " .. objective .. "  (0/" .. (def and def.RequiredShards or "3") .. ")"
        objLbl.TextXAlignment = Enum.TextXAlignment.Left
        objLbl.TextTruncate = Enum.TextTruncate.AtEnd
        objLbl.Parent = container
        trackerObjLabel = objLbl

        local objStroke = Instance.new("UIStroke")
        objStroke.Color = Color3.fromRGB(0, 0, 0)
        objStroke.Thickness = 0.8
        objStroke.Transparency = 0.2
        objStroke.Parent = objLbl

        -- Auto-size container height to fit content
        cLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            container.Size = UDim2.new(0, px(460), 0,
                cLayout.AbsoluteContentSize.Y + px(40))  -- 20+20 padding
        end)
        container.Size = UDim2.new(0, px(460), 0,
            cLayout.AbsoluteContentSize.Y + px(40))

        objectiveTracker = trackerGui
    end

    -----------------------------------------------------------------
    -- Listen for shard progress updates from server
    -----------------------------------------------------------------
    do
        if shardProgressConn then
            pcall(function() shardProgressConn:Disconnect() end)
            shardProgressConn = nil
        end

        local progressRemote = ReplicatedStorage:FindFirstChild("EventShardProgress")
        if progressRemote then
            shardProgressConn = progressRemote.OnClientEvent:Connect(function(current, required)
                if trackerObjLabel then
                    local def = getEventDef()
                    local objective = def and def.Objective or "..."
                    if current >= required then
                        trackerObjLabel.Text = "- " .. objective .. "  (" .. current .. "/" .. required .. ")  COMPLETE!"
                        trackerObjLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
                    else
                        trackerObjLabel.Text = "- " .. objective .. "  (" .. current .. "/" .. required .. ")"
                    end
                end
            end)
        end
    end

    -----------------------------------------------------------------
    -- Heartbeat timer update (updates card timer + panel timer)
    -----------------------------------------------------------------
    if timerConnection then
        pcall(function() timerConnection:Disconnect() end)
    end
    timerConnection = RunService.Heartbeat:Connect(function()
        if not eventEndTime then return end
        local remaining = eventEndTime - workspace:GetServerTimeNow()
        local text = formatTime(remaining)
        if remaining <= 0 then text = "0" end
        -- Left-side timer: full human-readable phrase
        if timerLabel then
            local secs = math.max(0, math.floor(remaining))
            if secs < 60 then
                timerLabel.Text = secs .. " seconds remaining"
            else
                timerLabel.Text = text .. " remaining"
            end
        end
        if popupTimerLabel and popupVisible then
            popupTimerLabel.Text = text
        end
    end)

    -----------------------------------------------------------------
    -- Pulse animation  (STARTS HERE)
    -- Tweens teamPulseOverlay.BackgroundTransparency between
    -- PULSE_MIN_TRANSPARENCY (strong tint) and PULSE_MAX_TRANSPARENCY
    -- (weak tint).  Gold stroke stays constant.  Background art
    -- remains visible underneath at all times.
    -----------------------------------------------------------------
    pulseThread = task.spawn(function()
        local halfCycle = PULSE_CYCLE / 2
        local tweenInfo = TweenInfo.new(halfCycle, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

        while currentCard and currentCard.Parent do
            -- Phase 1: overlay becomes more visible (stronger team tint)
            local tw1 = TweenService:Create(teamPulseOverlay, tweenInfo, {
                BackgroundTransparency = PULSE_MIN_TRANSPARENCY,
            })
            pulseTweens = { tw1 }
            tw1:Play()
            tw1.Completed:Wait()

            if not currentCard or not currentCard.Parent then break end

            -- Phase 2: overlay fades back (weaker tint, background shows more)
            local tw2 = TweenService:Create(teamPulseOverlay, tweenInfo, {
                BackgroundTransparency = PULSE_MAX_TRANSPARENCY,
            })
            pulseTweens = { tw2 }
            tw2:Play()
            tw2.Completed:Wait()
        end
        -- Pulse STOPS when the loop exits (card destroyed or unparented)
    end)
end

---------------------------------------------------------------------
-- Listen for server event state changes
---------------------------------------------------------------------
local EventStateChanged = ReplicatedStorage:WaitForChild("EventStateChanged", 15)
if EventStateChanged then
    EventStateChanged.OnClientEvent:Connect(function(active, eventIndex, endTime)
        if active then
            createIndicator()
            eventEndTime = endTime  -- set after createIndicator (which calls destroyIndicator first)
        else
            destroyIndicator()
        end
    end)
else
    warn("[EventIndicator] EventStateChanged remote not found – event UI will not work")
end

---------------------------------------------------------------------
-- Meteor shard collection: floating "+N coins" popup + Collect sound
---------------------------------------------------------------------
do
    local shardCollectedRemote = ReplicatedStorage:FindFirstChild("MeteorShardCollected")
        or ReplicatedStorage:WaitForChild("MeteorShardCollected", 15)

    if shardCollectedRemote then
        shardCollectedRemote.OnClientEvent:Connect(function(shardPos, amount)
            -- Play Collect sound
            local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
            local collectSound = soundsFolder and soundsFolder:FindFirstChild("Collect")
            if collectSound and collectSound:IsA("Sound") then
                local s = collectSound:Clone()
                s.Parent = workspace
                s:Play()
                game:GetService("Debris"):AddItem(s, 4)
            end

            -- Floating "+N coins" billboard at the shard position
            local anchor = Instance.new("Part")
            anchor.Size = Vector3.new(0.1, 0.1, 0.1)
            anchor.Transparency = 1
            anchor.Anchored = true
            anchor.CanCollide = false
            anchor.CanTouch = false
            anchor.CFrame = CFrame.new(shardPos)
            anchor.Parent = workspace

            local gui = Instance.new("BillboardGui")
            gui.Size = UDim2.new(0, 120, 0, 44)
            gui.StudsOffset = Vector3.new(0, 3, 0)
            gui.AlwaysOnTop = true
            gui.Adornee = anchor
            gui.Parent = anchor

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Text = "+" .. tostring(amount) .. " coins"
            label.Font = Enum.Font.GothamBold
            label.TextSize = 22
            label.TextColor3 = Color3.fromRGB(180, 225, 255)
            label.TextStrokeColor3 = Color3.fromRGB(0, 60, 120)
            label.TextStrokeTransparency = 0.3
            label.Parent = gui

            -- Float upward while fading
            local ts = game:GetService("TweenService")
            local floatTween = ts:Create(gui,
                TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { StudsOffset = Vector3.new(0, 5.5, 0) }
            )
            floatTween:Play()

            task.spawn(function()
                task.wait(0.6)
                for t = 0, 1, 0.06 do
                    label.TextTransparency = t
                    label.TextStrokeTransparency = 0.3 + t * 0.7
                    task.wait(0.06)
                end
                floatTween:Cancel()
                anchor:Destroy()
            end)
        end)
    end
end

-- Clean up on match end
local MatchEnd = ReplicatedStorage:FindFirstChild("MatchEnd")
if MatchEnd and MatchEnd:IsA("RemoteEvent") then
    MatchEnd.OnClientEvent:Connect(function()
        destroyIndicator()
    end)
end
