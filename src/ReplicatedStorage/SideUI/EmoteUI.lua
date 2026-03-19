--------------------------------------------------------------------------------
-- EmoteUI.lua  –  Radial Emote Wheel for KingsGround
-- Place in: ReplicatedStorage > SideUI
--
-- This module builds and manages a radial emote wheel UI, inspired by the
-- default Roblox emote wheel but styled to match KingsGround's dark navy/gold
-- visual language. Consumed by EmoteClient.client.lua.
--
-- Public API:
--   EmoteUI.Build(screenGui)       → returns panelFrame
--   EmoteUI.Show(panelFrame)       → tween open
--   EmoteUI.Hide(panelFrame)       → tween close
--   EmoteUI.HideInstant(panelFrame)→ instant hide (menu switching)
--   EmoteUI.IsVisible(panelFrame)  → bool
--   EmoteUI.RenderEquippedEmotes(panelFrame, emoteList)
--   EmoteUI.ShowEmptyState(panelFrame)
--   EmoteUI.RequestPlayEmote(emoteId)
--   EmoteUI.StopCurrentEmote()
--
-- Callback (set by EmoteClient):
--   EmoteUI.OnSlotSelected   → called after a slot click (to close wheel)
--------------------------------------------------------------------------------

local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EmoteUI = {}

-- ── Callback: set by EmoteClient for close-after-selection ───────────────
EmoteUI.OnSlotSelected = nil   -- function(emoteId) or nil

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
local SLOT_COUNT = (EmoteConfig and EmoteConfig.SLOT_COUNT) or 8

-- ── Wheel layout constants ───────────────────────────────────────────────
local NUM_SLOTS   = SLOT_COUNT
local SLICE_ANGLE = (2 * math.pi) / NUM_SLOTS

-- ── AssetCodes for icon lookup ────────────────────────────────────────────
local AssetCodes = nil
do
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then AssetCodes = result end
    end
end

local function resolveIcon(emote)
    if emote.IconAssetId and type(emote.IconAssetId) == "string" and #emote.IconAssetId > 0 then
        return emote.IconAssetId
    end
    if emote.IconKey and AssetCodes and type(AssetCodes.Get) == "function" then
        local img = AssetCodes.Get(emote.IconKey)
        if img and type(img) == "string" and #img > 0 then return img end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Build the radial emote wheel and attach it to screenGui (hidden by default).
-- Returns the root panel frame.
--------------------------------------------------------------------------------
function EmoteUI.Build(screenGui)
    -- Guard: destroy any stale instance from a previous call
    local existing = screenGui:FindFirstChild("EmotePanel")
    if existing then existing:Destroy() end

    -- ── Compute responsive wheel dimensions ──────────────────────────────
    local WHEEL_DIAMETER  = px(560)
    local WHEEL_RADIUS    = WHEEL_DIAMETER / 2
    local SLOT_RADIUS     = px(210)
    local SLOT_DIAMETER   = px(96)
    local CENTER_DIAMETER = px(160)
    local CENTER_RADIUS_V = CENTER_DIAMETER / 2
    local wheelSize       = WHEEL_DIAMETER + SLOT_DIAMETER + px(24)

    print("[EmoteUI] emote wheel created")
    print("[EmoteUI] wheel size/diameter:", WHEEL_DIAMETER)
    print("[EmoteUI] slot radius:", SLOT_RADIUS, "slot diameter:", SLOT_DIAMETER)
    print("[EmoteUI] center diameter:", CENTER_DIAMETER, "container size:", wheelSize)

    -- ── Root panel (full-screen overlay, hidden by default) ──────────────
    local panel = Instance.new("Frame")
    panel.Name                 = "EmotePanel"
    panel.Size                 = UDim2.new(1, 0, 1, 0)
    panel.Position             = UDim2.new(0, 0, 0, 0)
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel      = 0
    panel.Visible              = false
    panel.ZIndex               = 310
    panel.Parent               = screenGui

    -- ── Backdrop (semi-transparent, click to close) ─────────────────────
    local backdrop = Instance.new("TextButton")
    backdrop.Name                 = "Backdrop"
    backdrop.Size                 = UDim2.new(1, 0, 1, 0)
    backdrop.BackgroundColor3     = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 0.55
    backdrop.BorderSizePixel      = 0
    backdrop.Text                 = ""
    backdrop.AutoButtonColor      = false
    backdrop.ZIndex               = 311
    backdrop.Parent               = panel

    backdrop.MouseButton1Click:Connect(function()
        print("[EmoteUI] backdrop clicked → closing wheel")
        if EmoteUI.OnSlotSelected then
            EmoteUI.OnSlotSelected(nil)
        end
    end)

    -- ── Wheel container (centered, fixed pixel size) ────────────────────
    local wheel = Instance.new("Frame")
    wheel.Name                 = "WheelFrame"
    wheel.AnchorPoint          = Vector2.new(0.5, 0.5)
    wheel.Position             = UDim2.new(0.5, 0, 0.5, 0)
    wheel.Size                 = UDim2.new(0, wheelSize, 0, wheelSize)
    wheel.BackgroundTransparency = 1
    wheel.BorderSizePixel      = 0
    wheel.ZIndex               = 312
    wheel.Parent               = panel

    -- ── Outer ring (dark circle background) ─────────────────────────────
    local outerRing = Instance.new("Frame")
    outerRing.Name                 = "OuterRing"
    outerRing.AnchorPoint          = Vector2.new(0.5, 0.5)
    outerRing.Position             = UDim2.new(0.5, 0, 0.5, 0)
    outerRing.Size                 = UDim2.new(0, WHEEL_DIAMETER, 0, WHEEL_DIAMETER)
    outerRing.BackgroundColor3     = NAVY
    outerRing.BackgroundTransparency = 0.12
    outerRing.BorderSizePixel      = 0
    outerRing.ZIndex               = 313
    outerRing.Parent               = wheel

    local outerCorner = Instance.new("UICorner")
    outerCorner.CornerRadius = UDim.new(1, 0)
    outerCorner.Parent = outerRing

    local outerStroke = Instance.new("UIStroke")
    outerStroke.Color           = GOLD_DIM
    outerStroke.Thickness       = px(2)
    outerStroke.Transparency    = 0.2
    outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outerStroke.Parent          = outerRing

    -- ── Divider/spoke lines removed entirely for a clean wheel ──────────
    print("[EmoteUI] divider/spoke lines: REMOVED (0 rendered)")

    -- ── Slot buttons (circular, positioned radially) ────────────────────
    for i = 1, NUM_SLOTS do
        local angle   = (i - 1) * SLICE_ANGLE
        local offsetX = math.sin(angle) * SLOT_RADIUS
        local offsetY = -math.cos(angle) * SLOT_RADIUS

        if i == 1 then
            print("[EmoteUI] top slot (1) position offset:", offsetX, offsetY)
        end

        local slot = Instance.new("Frame")
        slot.Name                 = "Slot_" .. i
        slot.AnchorPoint          = Vector2.new(0.5, 0.5)
        slot.Position             = UDim2.new(0.5, offsetX, 0.5, offsetY)
        slot.Size                 = UDim2.new(0, SLOT_DIAMETER, 0, SLOT_DIAMETER)
        slot.BackgroundColor3     = DISABLED_BG
        slot.BackgroundTransparency = 0.1
        slot.BorderSizePixel      = 0
        slot.ZIndex               = 315
        slot.Parent               = wheel

        local slotCorner = Instance.new("UICorner")
        slotCorner.CornerRadius = UDim.new(1, 0)
        slotCorner.Parent = slot

        local slotStroke = Instance.new("UIStroke")
        slotStroke.Color           = CARD_STROKE
        slotStroke.Thickness       = px(1.5)
        slotStroke.Transparency    = 0.3
        slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        slotStroke.Parent          = slot

        -- Icon image (centered in slot; primary display when icon exists)
        local iconImg = Instance.new("ImageLabel")
        iconImg.Name                 = "IconImg"
        iconImg.Size                 = UDim2.new(0.55, 0, 0.55, 0)
        iconImg.AnchorPoint          = Vector2.new(0.5, 0.5)
        iconImg.Position             = UDim2.new(0.5, 0, 0.42, 0)
        iconImg.BackgroundTransparency = 1
        iconImg.Image                = ""
        iconImg.ScaleType            = Enum.ScaleType.Fit
        iconImg.Visible              = false
        iconImg.ZIndex               = 316
        iconImg.Parent               = slot

        -- Emote name label (bottom of slot; shown when no icon, or as sub-label)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name                 = "NameLabel"
            nameLabel.Size                 = UDim2.new(0.82, 0, 0.34, 0)
            nameLabel.AnchorPoint          = Vector2.new(0.5, 0.5)
            nameLabel.Position             = UDim2.new(0.5, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font                 = Enum.Font.GothamBold
        nameLabel.Text                 = ""
        nameLabel.TextColor3           = WHITE
        nameLabel.TextScaled           = true
            nameLabel.TextXAlignment       = Enum.TextXAlignment.Center
            nameLabel.TextYAlignment       = Enum.TextYAlignment.Center
        nameLabel.ZIndex               = 316
        nameLabel.Parent               = slot

        -- Empty-slot dash (visible when no emote assigned)
        local lockLabel = Instance.new("TextLabel")
        lockLabel.Name                 = "LockLabel"
        lockLabel.Size                 = UDim2.new(0.50, 0, 0.50, 0)
        lockLabel.AnchorPoint          = Vector2.new(0.5, 0.5)
        lockLabel.Position             = UDim2.new(0.5, 0, 0.45, 0)
        lockLabel.BackgroundTransparency = 1
        lockLabel.Font                 = Enum.Font.GothamBold
        lockLabel.Text                 = "—"
        lockLabel.TextColor3           = Color3.fromRGB(65, 70, 92)
        lockLabel.TextScaled           = true
        lockLabel.TextXAlignment       = Enum.TextXAlignment.Center
        lockLabel.TextYAlignment       = Enum.TextYAlignment.Center
        lockLabel.ZIndex               = 316
        lockLabel.Parent               = slot
    end

    print("[EmoteUI] slot count rendered:", NUM_SLOTS)
    print("[EmoteUI] top slot (Slot_1) center position: 0.5 +", 0, ", 0.5 +", -SLOT_RADIUS)
    print("[EmoteUI] center circle position: 0.5, 0.5 | size:", CENTER_DIAMETER)

    -- ── Center circle (info panel) ──────────────────────────────────────
    local centerCircle = Instance.new("Frame")
    centerCircle.Name                 = "CenterCircle"
    centerCircle.AnchorPoint          = Vector2.new(0.5, 0.5)
    centerCircle.Position             = UDim2.new(0.5, 0, 0.5, 0)
    centerCircle.Size                 = UDim2.new(0, CENTER_DIAMETER, 0, CENTER_DIAMETER)
    centerCircle.BackgroundColor3     = NAVY_MID
    centerCircle.BackgroundTransparency = 0.05
    centerCircle.BorderSizePixel      = 0
    centerCircle.ZIndex               = 318
    centerCircle.Parent               = wheel

    local centerCorner = Instance.new("UICorner")
    centerCorner.CornerRadius = UDim.new(1, 0)
    centerCorner.Parent = centerCircle

    local centerStroke = Instance.new("UIStroke")
    centerStroke.Color           = GOLD_DIM
    centerStroke.Thickness       = px(2)
    centerStroke.Transparency    = 0.15
    centerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    centerStroke.Parent          = centerCircle

    -- Title ("EMOTES" or hovered emote name)
    local centerTitle = Instance.new("TextLabel")
    centerTitle.Name                 = "CenterTitle"
    centerTitle.Size                 = UDim2.new(0.85, 0, 0.30, 0)
    centerTitle.AnchorPoint          = Vector2.new(0.5, 0)
    centerTitle.Position             = UDim2.new(0.5, 0, 0.12, 0)
    centerTitle.BackgroundTransparency = 1
    centerTitle.Font                 = Enum.Font.GothamBlack
    centerTitle.Text                 = "EMOTES"
    centerTitle.TextColor3           = GOLD
    centerTitle.TextScaled           = true
    centerTitle.ZIndex               = 319
    centerTitle.Parent               = centerCircle

    -- Subtext ("Select an Emote" / "No Emotes equipped" / "Click to play")
    local centerSubtext = Instance.new("TextLabel")
    centerSubtext.Name                 = "CenterSubtext"
    centerSubtext.Size                 = UDim2.new(0.80, 0, 0.25, 0)
    centerSubtext.AnchorPoint          = Vector2.new(0.5, 0.5)
    centerSubtext.Position             = UDim2.new(0.5, 0, 0.58, 0)
    centerSubtext.BackgroundTransparency = 1
    centerSubtext.Font                 = Enum.Font.Gotham
    centerSubtext.Text                 = "Select an Emote"
    centerSubtext.TextColor3           = DIM_TEXT
    centerSubtext.TextScaled           = true
    centerSubtext.ZIndex               = 319
    centerSubtext.Parent               = centerCircle

    -- Keybind hint at bottom of center circle
    local hintLabel = Instance.new("TextLabel")
    hintLabel.Name                 = "HintLabel"
    hintLabel.Size                 = UDim2.new(0.80, 0, 0.16, 0)
    hintLabel.AnchorPoint          = Vector2.new(0.5, 1)
    hintLabel.Position             = UDim2.new(0.5, 0, 0.92, 0)
    hintLabel.BackgroundTransparency = 1
    hintLabel.Font                 = Enum.Font.Gotham
    hintLabel.Text                 = "[ E ] close"
    hintLabel.TextColor3           = Color3.fromRGB(100, 105, 130)
    hintLabel.TextScaled           = true
    hintLabel.ZIndex               = 319
    hintLabel.Parent               = centerCircle

    return panel
end

--------------------------------------------------------------------------------
-- Show the wheel with a scale-in + fade animation.
--------------------------------------------------------------------------------
function EmoteUI.Show(panel)
    if not panel then return end
    print("[EmoteUI] emote wheel opened")
    panel.Visible = true

    local wheel = panel:FindFirstChild("WheelFrame")
    if wheel then
        local scale = wheel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", wheel)
        scale.Scale = 0.6
        local infoScale = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        TweenService:Create(scale, infoScale, {Scale = 1.0}):Play()
    end

    local backdrop = panel:FindFirstChild("Backdrop")
    if backdrop then
        backdrop.BackgroundTransparency = 1
        local infoFade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(backdrop, infoFade, {BackgroundTransparency = 0.55}):Play()
    end
end

--------------------------------------------------------------------------------
-- Hide the wheel with a scale-out + fade animation.
--------------------------------------------------------------------------------
function EmoteUI.Hide(panel)
    if not panel then return end
    print("[EmoteUI] emote wheel closed")

    local wheel    = panel:FindFirstChild("WheelFrame")
    local backdrop = panel:FindFirstChild("Backdrop")
    local infoOut  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    if wheel then
        local scale = wheel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", wheel)
        local t = TweenService:Create(scale, infoOut, {Scale = 0.7})
        t:Play()
        t.Completed:Connect(function()
            if panel then panel.Visible = false end
            if scale then scale.Scale = 0.6 end
        end)
    else
        task.delay(0.14, function()
            if panel then panel.Visible = false end
        end)
    end

    if backdrop then
        TweenService:Create(backdrop, infoOut, {BackgroundTransparency = 1}):Play()
    end
end

--------------------------------------------------------------------------------
-- Instant hide (used when another menu is being opened or after selection).
--------------------------------------------------------------------------------
function EmoteUI.HideInstant(panel)
    if not panel then return end
    print("[EmoteUI] emote wheel closed (instant)")
    panel.Visible = false
    local wheel = panel:FindFirstChild("WheelFrame")
    if wheel then
        local scale = wheel:FindFirstChildOfClass("UIScale")
        if scale then scale.Scale = 0.6 end
    end
end

--------------------------------------------------------------------------------
-- Returns true if the wheel is currently visible.
--------------------------------------------------------------------------------
function EmoteUI.IsVisible(panel)
    return panel ~= nil and panel.Visible
end

--------------------------------------------------------------------------------
-- Render equipped emotes into the radial wheel slots.
-- emoteList: array of { Id, DisplayName, IconKey?, IconAssetId?, Slot? }
-- Populates matching slots; all others revert to the empty placeholder.
-- Clicking a populated slot fires RequestPlayEmote then OnSlotSelected.
--------------------------------------------------------------------------------
function EmoteUI.RenderEquippedEmotes(panel, emoteList)
    if not panel then return end
    local wheel = panel:FindFirstChild("WheelFrame")
    if not wheel then return end

    local hasAny = emoteList and #emoteList > 0
    if not hasAny then
        EmoteUI.ShowEmptyState(panel)
        return
    end

    -- Update center text
    local centerCircle = wheel:FindFirstChild("CenterCircle")
    if centerCircle then
        local sub = centerCircle:FindFirstChild("CenterSubtext")
        if sub then sub.Text = "Select an Emote" end
        local ct = centerCircle:FindFirstChild("CenterTitle")
        if ct then ct.Text = "EMOTES" end
    end

    -- Build a map: slot index → emote data
    local slotMap = {}
    for i, emote in ipairs(emoteList) do
        local idx = (emote.Slot and tonumber(emote.Slot)) or i
        slotMap[idx] = emote
    end

    for i = 1, NUM_SLOTS do
        local slot = wheel:FindFirstChild("Slot_" .. i)
        if not slot then continue end
        local emote     = slotMap[i]
        local nameLabel = slot:FindFirstChild("NameLabel")
        local iconImg   = slot:FindFirstChild("IconImg")
        local lockLabel = slot:FindFirstChild("LockLabel")
        local slotStroke = slot:FindFirstChildOfClass("UIStroke")

        -- Remove any previous click overlay to avoid stacking
        local oldBtn = slot:FindFirstChild("PlayBtn")
        if oldBtn then oldBtn:Destroy() end

        if emote then
            -- ── Populated slot ──────────────────────────────────────────
            slot.BackgroundColor3       = CARD_BG
            slot.BackgroundTransparency = 0.05
            if slotStroke then slotStroke.Color = GOLD_DIM; slotStroke.Transparency = 0.15 end
            if nameLabel then nameLabel.Text = emote.DisplayName or "" end
            if lockLabel then lockLabel.Visible = false end

            local iconSrc = resolveIcon(emote)
            if iconImg then
                if iconSrc then
                    iconImg.Image   = iconSrc
                    iconImg.Visible = true
                else
                    iconImg.Visible = false
                end
            end

            -- Overlay click button
            local playBtn = Instance.new("TextButton")
            playBtn.Name = "PlayBtn"
            playBtn.Size = UDim2.new(1, 0, 1, 0)
            playBtn.BackgroundTransparency = 1
            playBtn.Text = ""
            playBtn.ZIndex = 317
            playBtn.Parent = slot

            local playCorner = Instance.new("UICorner")
            playCorner.CornerRadius = UDim.new(1, 0)
            playCorner.Parent = playBtn

            local emoteId   = emote.Id
            local emoteName = emote.DisplayName or emoteId

            playBtn.MouseButton1Click:Connect(function()
                print("[EmoteUI] clicked slot", i, "→ selected emote:", emoteId, emoteName)
                EmoteUI.RequestPlayEmote(emoteId)
                print("[EmoteUI] wheel closed after selection")
                if EmoteUI.OnSlotSelected then
                    EmoteUI.OnSlotSelected(emoteId)
                end
            end)

            -- Hover: highlight slot + update center text
            local hoverInfo = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            playBtn.MouseEnter:Connect(function()
                print("[EmoteUI] hovered slot", i)
                TweenService:Create(slot, hoverInfo, {
                    BackgroundColor3       = Color3.fromRGB(42, 48, 72),
                    BackgroundTransparency = 0,
                }):Play()
                if slotStroke then
                    TweenService:Create(slotStroke, hoverInfo, {
                        Color        = GOLD,
                        Transparency = 0,
                    }):Play()
                end
                if centerCircle then
                    local ct = centerCircle:FindFirstChild("CenterTitle")
                    local cs = centerCircle:FindFirstChild("CenterSubtext")
                    if ct then ct.Text = emoteName end
                    if cs then cs.Text = "Click to play" end
                end
            end)
            playBtn.MouseLeave:Connect(function()
                TweenService:Create(slot, hoverInfo, {
                    BackgroundColor3       = CARD_BG,
                    BackgroundTransparency = 0.05,
                }):Play()
                if slotStroke then
                    TweenService:Create(slotStroke, hoverInfo, {
                        Color        = GOLD_DIM,
                        Transparency = 0.15,
                    }):Play()
                end
                if centerCircle then
                    local ct = centerCircle:FindFirstChild("CenterTitle")
                    local cs = centerCircle:FindFirstChild("CenterSubtext")
                    if ct then ct.Text = "EMOTES" end
                    if cs then cs.Text = "Select an Emote" end
                end
            end)
        else
            -- ── Empty slot ──────────────────────────────────────────────
            slot.BackgroundColor3       = DISABLED_BG
            slot.BackgroundTransparency = 0.15
            if slotStroke then slotStroke.Color = CARD_STROKE; slotStroke.Transparency = 0.4 end
            if nameLabel then nameLabel.Text = "" end
            if lockLabel then lockLabel.Visible = true; lockLabel.Text = "—" end
            if iconImg   then iconImg.Visible = false end
        end
    end

    print("[EmoteUI] equipped emotes rendered on wheel, count:", #emoteList)
end

--------------------------------------------------------------------------------
-- Show empty state (no emotes equipped) — updates center text and resets slots.
--------------------------------------------------------------------------------
function EmoteUI.ShowEmptyState(panel)
    if not panel then return end
    local wheel = panel:FindFirstChild("WheelFrame")
    if not wheel then return end

    -- Update center text
    local centerCircle = wheel:FindFirstChild("CenterCircle")
    if centerCircle then
        local ct = centerCircle:FindFirstChild("CenterTitle")
        local cs = centerCircle:FindFirstChild("CenterSubtext")
        if ct then ct.Text = "EMOTES" end
        if cs then cs.Text = "No Emotes equipped" end
    end

    -- Reset all slots to empty state
    for i = 1, NUM_SLOTS do
        local slot = wheel:FindFirstChild("Slot_" .. i)
        if not slot then continue end
        slot.BackgroundColor3       = DISABLED_BG
        slot.BackgroundTransparency = 0.15
        local slotStroke = slot:FindFirstChildOfClass("UIStroke")
        if slotStroke then slotStroke.Color = CARD_STROKE; slotStroke.Transparency = 0.4 end
        local nameLabel = slot:FindFirstChild("NameLabel")
        if nameLabel then nameLabel.Text = "" end
        local lockLabel = slot:FindFirstChild("LockLabel")
        if lockLabel then lockLabel.Visible = true; lockLabel.Text = "—" end
        local iconImg = slot:FindFirstChild("IconImg")
        if iconImg then iconImg.Visible = false end
        local oldBtn = slot:FindFirstChild("PlayBtn")
        if oldBtn then oldBtn:Destroy() end
    end

    print("[EmoteUI] empty state shown on wheel")
end

--------------------------------------------------------------------------------
-- Request the server to play an emote animation.
--------------------------------------------------------------------------------
function EmoteUI.RequestPlayEmote(emoteId)
    print("[EmoteUI] play emote request fired for:", emoteId)
    local remotes   = ReplicatedStorage:FindFirstChild("Remotes")
    local emotesDir = remotes and remotes:FindFirstChild("Emotes")
    local playRE    = emotesDir and emotesDir:FindFirstChild("PlayEmote")
    if playRE and playRE:IsA("RemoteEvent") then
        pcall(function() playRE:FireServer(emoteId) end)
        print("[EmoteUI] PlayEmote remote fired for:", emoteId)
    else
        warn("[EmoteUI] PlayEmote remote not found")
    end
end

--------------------------------------------------------------------------------
-- Cancel any currently playing emote.
--------------------------------------------------------------------------------
function EmoteUI.StopCurrentEmote()
    local remotes   = ReplicatedStorage:FindFirstChild("Remotes")
    local emotesDir = remotes and remotes:FindFirstChild("Emotes")
    local stopRE    = emotesDir and emotesDir:FindFirstChild("StopEmote")
    if stopRE and stopRE:IsA("RemoteEvent") then
        pcall(function() stopRE:FireServer() end)
        print("[EmoteUI] StopEmote fired")
    else
        warn("[EmoteUI] StopEmote remote not found")
    end
end

return EmoteUI
