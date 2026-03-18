--------------------------------------------------------------------------------
-- EmoteUI.lua  –  Emote panel renderer for KingsGround
-- Place in: ReplicatedStorage > SideUI
--
-- This module builds and manages the emote panel UI. It is consumed by
-- EmoteClient.client.lua, which owns the ScreenGui, keybind, and
-- MenuController registration.
--
-- Public API:
--   EmoteUI.Build(screenGui)       → returns panelFrame
--   EmoteUI.Show(panelFrame)       → tween open
--   EmoteUI.Hide(panelFrame)       → tween close
--   EmoteUI.HideInstant(panelFrame)→ instant hide (menu switching)
--   EmoteUI.IsVisible(panelFrame)  → bool
--   EmoteUI.RenderEquippedEmotes(panelFrame, emoteList)
--   EmoteUI.ShowEmptyState(panelFrame)
--
-- Future hooks (stubs only):
--   EmoteUI.RequestPlayEmote(emoteId)
--   EmoteUI.StopCurrentEmote()
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EmoteUI = {}

-- ── Shared theme ─────────────────────────────────────────────────────────
local UITheme = nil
do
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("UITheme")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then UITheme = result end
    end
end
-- Fallback palette if UITheme is unavailable
local NAVY       = UITheme and UITheme.NAVY       or Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT = UITheme and UITheme.NAVY_LIGHT or Color3.fromRGB(22, 26, 48)
local GOLD       = UITheme and UITheme.GOLD       or Color3.fromRGB(255, 215, 80)
local GOLD_DIM   = UITheme and UITheme.GOLD_DIM   or Color3.fromRGB(180, 150, 50)
local WHITE      = UITheme and UITheme.WHITE      or Color3.fromRGB(245, 245, 252)
local DIM_TEXT   = UITheme and UITheme.DIM_TEXT   or Color3.fromRGB(145, 150, 175)
local CARD_BG    = UITheme and UITheme.CARD_BG    or Color3.fromRGB(26, 30, 48)
local CARD_STROKE= UITheme and UITheme.CARD_STROKE or Color3.fromRGB(55, 62, 95)
local DISABLED_BG= UITheme and UITheme.DISABLED_BG or Color3.fromRGB(35, 38, 52)
local NAVY_MID   = UITheme and UITheme.NAVY_MID   or Color3.fromRGB(16, 20, 40)

-- ── Responsive scaling ────────────────────────────────────────────────────
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- ── Tween info ────────────────────────────────────────────────────────────
local TWEEN_IN  = TweenInfo.new(0.24, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad,  Enum.EasingDirection.In)

-- ── EmoteConfig ───────────────────────────────────────────────────────────
local EmoteConfig = nil
do
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("EmoteConfig")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then EmoteConfig = result end
    end
end
local SLOT_COUNT = (EmoteConfig and EmoteConfig.SLOT_COUNT) or 6

-- ── Panel constants ───────────────────────────────────────────────────────
local PANEL_W_SCALE = 0.42       -- fraction of screen width
local PANEL_H_SCALE = 0.46       -- fraction of screen height
local COLS          = 3          -- slot columns
local ROWS          = math.ceil(SLOT_COUNT / COLS)

--------------------------------------------------------------------------------
-- Build the emote panel and attach it to screenGui (hidden by default).
-- Returns the root panel frame.
--------------------------------------------------------------------------------
function EmoteUI.Build(screenGui)
    -- Guard: destroy any stale instance from a previous call
    local existing = screenGui:FindFirstChild("EmotePanel")
    if existing then existing:Destroy() end

    -- ── Root panel ────────────────────────────────────────────────────────
    local panel = Instance.new("Frame")
    panel.Name         = "EmotePanel"
    panel.AnchorPoint  = Vector2.new(0.5, 0.5)
    panel.Position     = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size         = UDim2.new(PANEL_W_SCALE, 0, PANEL_H_SCALE, 0)
    panel.BackgroundColor3 = NAVY
    panel.BackgroundTransparency = 0.04
    panel.BorderSizePixel = 0
    panel.Visible      = false
    panel.ZIndex       = 310
    panel.Parent       = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(14))
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = GOLD_DIM
    stroke.Thickness = 1.8
    stroke.Transparency = 0.15
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = panel

    -- Subtle vertical gradient (same as modal window)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
    })
    gradient.Rotation = 90
    gradient.Parent = panel

    -- ── Header bar ────────────────────────────────────────────────────────
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, px(40))
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = NAVY_LIGHT
    header.BackgroundTransparency = 0
    header.BorderSizePixel = 0
    header.ZIndex = 312
    header.Parent = panel

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, px(14))
    headerCorner.Parent = header

    -- Square off bottom corners of header so it merges with the panel body
    local headerBottomMask = Instance.new("Frame")
    headerBottomMask.Name = "BottomMask"
    headerBottomMask.Size = UDim2.new(1, 0, 0.5, 0)
    headerBottomMask.Position = UDim2.new(0, 0, 0.5, 0)
    headerBottomMask.BackgroundColor3 = NAVY_LIGHT
    headerBottomMask.BorderSizePixel = 0
    headerBottomMask.ZIndex = 311
    headerBottomMask.Parent = header

    local headerStroke = Instance.new("UIStroke")
    headerStroke.Color = GOLD_DIM
    headerStroke.Thickness = 1.2
    headerStroke.Transparency = 0.35
    headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    headerStroke.Parent = header

    -- Title label
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0.7, 0, 1, 0)
    title.AnchorPoint = Vector2.new(0.5, 0.5)
    title.Position = UDim2.new(0.5, 0, 0.5, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBlack
    title.Text = "EMOTES"
    title.TextColor3 = GOLD
    title.TextScaled = true
    title.ZIndex = 313
    title.Parent = header

    -- Key hint label (bottom-right of header)
    local hint = Instance.new("TextLabel")
    hint.Name = "HintLabel"
    hint.Size = UDim2.new(0.34, 0, 0.55, 0)
    hint.AnchorPoint = Vector2.new(1, 0.5)
    hint.Position = UDim2.new(0.97, 0, 0.5, 0)
    hint.BackgroundTransparency = 1
    hint.Font = Enum.Font.Gotham
    hint.Text = "[ E ] to close"
    hint.TextColor3 = DIM_TEXT
    hint.TextScaled = true
    hint.TextXAlignment = Enum.TextXAlignment.Right
    hint.ZIndex = 313
    hint.Parent = header

    -- Close X button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBlack
    closeBtn.TextScaled = true
    closeBtn.Size = UDim2.new(0, px(28), 0, px(28))
    closeBtn.AnchorPoint = Vector2.new(1, 0.5)
    closeBtn.Position = UDim2.new(1, -px(8), 0.5, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(26, 30, 48)
    closeBtn.TextColor3 = GOLD
    closeBtn.AutoButtonColor = false
    closeBtn.BorderSizePixel = 0
    closeBtn.ZIndex = 315
    closeBtn.Parent = header

    local closeBtnCorner = Instance.new("UICorner")
    closeBtnCorner.CornerRadius = UDim.new(0, px(6))
    closeBtnCorner.Parent = closeBtn

    local closeBtnStroke = Instance.new("UIStroke")
    closeBtnStroke.Color = GOLD_DIM
    closeBtnStroke.Thickness = 1.2
    closeBtnStroke.Transparency = 0.4
    closeBtnStroke.Parent = closeBtn

    local closeFeedback = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = Color3.fromRGB(55, 30, 38)}):Play()
        TweenService:Create(closeBtn, closeFeedback, {TextColor3 = Color3.new(1,1,1)}):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = Color3.fromRGB(26, 30, 48)}):Play()
        TweenService:Create(closeBtn, closeFeedback, {TextColor3 = GOLD}):Play()
    end)
    -- The click connection is wired from EmoteClient so it can call MenuController.
    -- Store a reference on the panel so EmoteClient can find it.
    panel:SetAttribute("CloseBtnName", "CloseBtn")

    -- ── Slot grid area (below header) ────────────────────────────────────
    local slotArea = Instance.new("Frame")
    slotArea.Name = "SlotArea"
    slotArea.Size = UDim2.new(1, -px(24), 1, -(px(40) + px(16)))
    slotArea.Position = UDim2.new(0, px(12), 0, px(40) + px(8))
    slotArea.BackgroundTransparency = 1
    slotArea.ZIndex = 311
    slotArea.Parent = panel

    -- ── Empty state frame (shown when no emotes are equipped) ─────────────
    local emptyState = Instance.new("Frame")
    emptyState.Name = "EmptyState"
    emptyState.Size = UDim2.new(1, 0, 1, 0)
    emptyState.BackgroundTransparency = 1
    emptyState.Visible = true   -- default visible until emotes are rendered
    emptyState.ZIndex = 312
    emptyState.Parent = slotArea

    local emptyLayout = Instance.new("UIListLayout")
    emptyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    emptyLayout.Padding = UDim.new(0, px(10))
    emptyLayout.Parent = emptyState

    -- Emote face icon (drawn with frames, matches InventoryUI emotes style)
    local iconWrap = Instance.new("Frame")
    iconWrap.Name = "IconWrap"
    iconWrap.LayoutOrder = 1
    iconWrap.BackgroundTransparency = 1
    iconWrap.Size = UDim2.new(0, px(52), 0, px(52))
    iconWrap.Parent = emptyState

    local faceOuter = Instance.new("Frame")
    faceOuter.Name = "Face"
    faceOuter.Size = UDim2.new(1, 0, 1, 0)
    faceOuter.BackgroundColor3 = GOLD_DIM
    faceOuter.BorderSizePixel = 0
    faceOuter.ZIndex = 313
    faceOuter.Parent = iconWrap
    local faceCorner = Instance.new("UICorner")
    faceCorner.CornerRadius = UDim.new(1, 0)
    faceCorner.Parent = faceOuter

    local faceInner = Instance.new("Frame")
    faceInner.Size = UDim2.new(0.82, 0, 0.82, 0)
    faceInner.AnchorPoint = Vector2.new(0.5, 0.5)
    faceInner.Position = UDim2.new(0.5, 0, 0.5, 0)
    faceInner.BackgroundColor3 = NAVY_MID
    faceInner.BorderSizePixel = 0
    faceInner.ZIndex = 314
    faceInner.Parent = faceOuter
    local faceInnerCorner = Instance.new("UICorner")
    faceInnerCorner.CornerRadius = UDim.new(1, 0)
    faceInnerCorner.Parent = faceInner

    -- Eyes
    local eyeL = Instance.new("Frame")
    eyeL.Size = UDim2.new(0, px(6), 0, px(6))
    eyeL.Position = UDim2.new(0.28, 0, 0.28, 0)
    eyeL.BackgroundColor3 = GOLD
    eyeL.BorderSizePixel = 0
    eyeL.ZIndex = 315
    eyeL.Parent = faceInner
    local eyeLCorner = Instance.new("UICorner"); eyeLCorner.CornerRadius = UDim.new(1,0); eyeLCorner.Parent = eyeL

    local eyeR = Instance.new("Frame")
    eyeR.Size = UDim2.new(0, px(6), 0, px(6))
    eyeR.Position = UDim2.new(0.58, 0, 0.28, 0)
    eyeR.BackgroundColor3 = GOLD
    eyeR.BorderSizePixel = 0
    eyeR.ZIndex = 315
    eyeR.Parent = faceInner
    local eyeRCorner = Instance.new("UICorner"); eyeRCorner.CornerRadius = UDim.new(1,0); eyeRCorner.Parent = eyeR

    -- Smile arc (approximated with a rounded bar)
    local smile = Instance.new("Frame")
    smile.Size = UDim2.new(0.52, 0, 0, px(5))
    smile.AnchorPoint = Vector2.new(0.5, 0.5)
    smile.Position = UDim2.new(0.5, 0, 0.66, 0)
    smile.BackgroundColor3 = GOLD
    smile.BorderSizePixel = 0
    smile.ZIndex = 315
    smile.Parent = faceInner
    local smileCorner = Instance.new("UICorner"); smileCorner.CornerRadius = UDim.new(1,0); smileCorner.Parent = smile

    -- Primary empty-state label
    local emptyLabel = Instance.new("TextLabel")
    emptyLabel.Name = "EmptyLabel"
    emptyLabel.LayoutOrder = 2
    emptyLabel.BackgroundTransparency = 1
    emptyLabel.Size = UDim2.new(0.90, 0, 0, px(20))
    emptyLabel.Font = Enum.Font.GothamBold
    emptyLabel.Text = "No emotes equipped"
    emptyLabel.TextColor3 = WHITE
    emptyLabel.TextScaled = true
    emptyLabel.ZIndex = 312
    emptyLabel.Parent = emptyState

    -- Secondary hint label
    local emptyHint = Instance.new("TextLabel")
    emptyHint.Name = "EmptyHint"
    emptyHint.LayoutOrder = 3
    emptyHint.BackgroundTransparency = 1
    emptyHint.Size = UDim2.new(0.90, 0, 0, px(28))
    emptyHint.Font = Enum.Font.Gotham
    emptyHint.Text = "Buy emotes in the Shop and equip them in Inventory."
    emptyHint.TextColor3 = DIM_TEXT
    emptyHint.TextScaled = true
    emptyHint.TextWrapped = true
    emptyHint.ZIndex = 312
    emptyHint.Parent = emptyState

    -- ── Slot grid (shown when emotes are equipped) ────────────────────────
    local slotGrid = Instance.new("Frame")
    slotGrid.Name = "SlotGrid"
    slotGrid.Size = UDim2.new(1, 0, 1, 0)
    slotGrid.BackgroundTransparency = 1
    slotGrid.Visible = false
    slotGrid.ZIndex = 312
    slotGrid.Parent = slotArea

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, px(90), 0, px(90))
    gridLayout.CellPadding = UDim2.new(0, px(12), 0, px(12))
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.FillDirectionMaxCells = COLS
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = slotGrid

    -- Pre-build SLOT_COUNT empty slot frames so they're ready for RenderEquippedEmotes
    for i = 1, SLOT_COUNT do
        local slot = Instance.new("Frame")
        slot.Name = "Slot_" .. i
        slot.BackgroundColor3 = DISABLED_BG
        slot.BorderSizePixel = 0
        slot.LayoutOrder = i
        slot.ZIndex = 313
        slot.Parent = slotGrid

        local slotCorner = Instance.new("UICorner")
        slotCorner.CornerRadius = UDim.new(0, px(10))
        slotCorner.Parent = slot

        local slotStroke = Instance.new("UIStroke")
        slotStroke.Color = CARD_STROKE
        slotStroke.Thickness = 1.4
        slotStroke.Transparency = 0.35
        slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        slotStroke.Parent = slot

        -- Slot index label (bottom-left)
        local indexLabel = Instance.new("TextLabel")
        indexLabel.Name = "IndexLabel"
        indexLabel.Size = UDim2.new(0, px(16), 0, px(16))
        indexLabel.Position = UDim2.new(0, px(4), 1, -px(18))
        indexLabel.BackgroundTransparency = 1
        indexLabel.Font = Enum.Font.GothamBold
        indexLabel.Text = tostring(i)
        indexLabel.TextColor3 = DIM_TEXT
        indexLabel.TextSize = px(12)
        indexLabel.ZIndex = 314
        indexLabel.Parent = slot

        -- Emote name label (centered, hidden until emote assigned)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(0.94, 0, 0.30, 0)
        nameLabel.AnchorPoint = Vector2.new(0.5, 1)
        nameLabel.Position = UDim2.new(0.5, 0, 1, -px(4))
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = ""
        nameLabel.TextColor3 = WHITE
        nameLabel.TextScaled = true
        nameLabel.TextWrapped = false
        nameLabel.ZIndex = 314
        nameLabel.Parent = slot

        -- Icon image (hidden until emote assigned)
        local iconImg = Instance.new("ImageLabel")
        iconImg.Name = "IconImg"
        iconImg.Size = UDim2.new(0.60, 0, 0.60, 0)
        iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
        iconImg.Position = UDim2.new(0.5, 0, 0.42, 0)
        iconImg.BackgroundTransparency = 1
        iconImg.Image = ""
        iconImg.ScaleType = Enum.ScaleType.Fit
        iconImg.Visible = false
        iconImg.ZIndex = 314
        iconImg.Parent = slot

        -- Empty-slot lock icon (shown by default)
        local lockLabel = Instance.new("TextLabel")
        lockLabel.Name = "LockLabel"
        lockLabel.Size = UDim2.new(0.55, 0, 0.55, 0)
        lockLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        lockLabel.Position = UDim2.new(0.5, 0, 0.44, 0)
        lockLabel.BackgroundTransparency = 1
        lockLabel.Font = Enum.Font.GothamBold
        lockLabel.Text = "—"
        lockLabel.TextColor3 = Color3.fromRGB(65, 70, 92)
        lockLabel.TextScaled = true
        lockLabel.ZIndex = 314
        lockLabel.Parent = slot
    end

    return panel
end

--------------------------------------------------------------------------------
-- Show the panel with a tween-in animation.
--------------------------------------------------------------------------------
function EmoteUI.Show(panel)
    if not panel then return end
    -- Start slightly scaled down and fully transparent, then tween to normal
    panel.Visible = true
    local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", panel)
    scale.Scale = 0.88
    panel.BackgroundTransparency = 0.85
    local infoScale  = TweenInfo.new(0.24, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
    local infoAlpha  = TweenInfo.new(0.20, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
    TweenService:Create(scale, infoScale, {Scale = 1.0}):Play()
    TweenService:Create(panel, infoAlpha, {BackgroundTransparency = 0.04}):Play()
end

--------------------------------------------------------------------------------
-- Hide the panel with a tween-out animation, then set Visible = false.
--------------------------------------------------------------------------------
function EmoteUI.Hide(panel)
    if not panel then return end
    local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", panel)
    local infoScale  = TweenInfo.new(0.16, Enum.EasingStyle.Quad,  Enum.EasingDirection.In)
    local infoAlpha  = TweenInfo.new(0.16, Enum.EasingStyle.Quad,  Enum.EasingDirection.In)
    local t = TweenService:Create(scale, infoScale, {Scale = 0.90})
    TweenService:Create(panel, infoAlpha, {BackgroundTransparency = 0.85}):Play()
    t:Play()
    t.Completed:Connect(function()
        if panel then panel.Visible = false end
        if scale then scale.Scale = 0.88 end
        if panel then panel.BackgroundTransparency = 0.04 end
    end)
end

--------------------------------------------------------------------------------
-- Instant hide (used when another menu is being opened).
--------------------------------------------------------------------------------
function EmoteUI.HideInstant(panel)
    if not panel then return end
    panel.Visible = false
    local scale = panel:FindFirstChildOfClass("UIScale")
    if scale then scale.Scale = 0.88 end
    panel.BackgroundTransparency = 0.04
end

--------------------------------------------------------------------------------
-- Returns true if the panel is currently visible.
--------------------------------------------------------------------------------
function EmoteUI.IsVisible(panel)
    return panel ~= nil and panel.Visible
end

--------------------------------------------------------------------------------
-- Render a list of equipped emote definitions into the slot grid.
-- emoteList: array of { Id, DisplayName, IconAssetId? }
-- Hides the empty-state and shows the grid.
-- Slots without an entry revert to the empty placeholder.
--------------------------------------------------------------------------------
function EmoteUI.RenderEquippedEmotes(panel, emoteList)
    if not panel then return end
    local slotArea  = panel:FindFirstChild("SlotArea")
    if not slotArea then return end
    local emptyState = slotArea:FindFirstChild("EmptyState")
    local slotGrid   = slotArea:FindFirstChild("SlotGrid")
    if not slotGrid then return end

    local hasAny = emoteList and #emoteList > 0
    if not hasAny then
        EmoteUI.ShowEmptyState(panel)
        return
    end

    if emptyState then emptyState.Visible = false end
    slotGrid.Visible = true

    for i = 1, SLOT_COUNT do
        local slot = slotGrid:FindFirstChild("Slot_" .. i)
        if not slot then continue end
        local emote = emoteList[i]
        local nameLabel = slot:FindFirstChild("NameLabel")
        local iconImg   = slot:FindFirstChild("IconImg")
        local lockLabel = slot:FindFirstChild("LockLabel")
        local slotStroke = slot:FindFirstChildOfClass("UIStroke")

        if emote then
            -- Populated slot
            slot.BackgroundColor3 = CARD_BG
            if slotStroke then slotStroke.Color = GOLD_DIM; slotStroke.Transparency = 0.15 end
            if nameLabel then nameLabel.Text = emote.DisplayName or "" end
            if lockLabel then lockLabel.Visible = false end
            if iconImg then
                iconImg.Visible = (emote.IconAssetId and #emote.IconAssetId > 0) and true or false
                if emote.IconAssetId then iconImg.Image = emote.IconAssetId end
            end
        else
            -- Empty slot
            slot.BackgroundColor3 = DISABLED_BG
            if slotStroke then slotStroke.Color = CARD_STROKE; slotStroke.Transparency = 0.35 end
            if nameLabel then nameLabel.Text = "" end
            if lockLabel then lockLabel.Visible = true; lockLabel.Text = "—" end
            if iconImg   then iconImg.Visible = false end
        end
    end

    print("[EmoteUI] Equipped emotes rendered, count:", #emoteList)
end

--------------------------------------------------------------------------------
-- Show the empty state (no emotes owned / equipped).
--------------------------------------------------------------------------------
function EmoteUI.ShowEmptyState(panel)
    if not panel then return end
    local slotArea = panel:FindFirstChild("SlotArea")
    if not slotArea then return end
    local emptyState = slotArea:FindFirstChild("EmptyState")
    local slotGrid   = slotArea:FindFirstChild("SlotGrid")
    if emptyState then emptyState.Visible = true end
    if slotGrid   then slotGrid.Visible   = false end
    print("[EmoteUI] Empty state shown")
end

--------------------------------------------------------------------------------
-- FUTURE STUB: Request the server to play an emote animation.
-- Wire this to a RemoteEvent (e.g. Remotes.Emotes.PlayEmote) when ready.
--------------------------------------------------------------------------------
function EmoteUI.RequestPlayEmote(emoteId)
    -- TODO: fire Remotes.Emotes.PlayEmote:FireServer(emoteId)
    print("[EmoteUI] RequestPlayEmote stub called for:", emoteId)
end

--------------------------------------------------------------------------------
-- FUTURE STUB: Cancel any currently playing emote.
--------------------------------------------------------------------------------
function EmoteUI.StopCurrentEmote()
    -- TODO: fire Remotes.Emotes.StopEmote:FireServer()
    print("[EmoteUI] StopCurrentEmote stub called")
end

return EmoteUI
