--------------------------------------------------------------------------------
-- OptionsUI.lua  –  Game settings menu (Audio · Graphics · Gameplay · UI · Other)
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / InventoryUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Assumptions:
--   • Parent is the modal ScrollingFrame with a UIListLayout + UIPadding.
--   • The main ScreenGui is named "MainUI" (used for UIScale adjustment).
--   • Sounds in a SoundGroup named "Music" / "SFX" under SoundService are
--     volume-adjusted. If those groups don't exist yet, placeholders are noted.
--   • Minimap ScreenGui at PlayerGui.Minimap (hidden/shown via Enabled).
--   • Game-state ScreenGui at PlayerGui.GameStateDisplay (hidden/shown).
--   • Camera sensitivity/invert are stored in _G.PlayerSettings for camera
--     scripts to read at their own pace.
--------------------------------------------------------------------------------

local Players            = game:GetService("Players")
local SoundService       = game:GetService("SoundService")
local Lighting           = game:GetService("Lighting")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / ShopUI)
--------------------------------------------------------------------------------
local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- Palette (sourced from shared UITheme – Team menu visual language)
--------------------------------------------------------------------------------
local ROW_BG           = UITheme.CARD_BG
local CARD_STROKE      = UITheme.CARD_STROKE
local GOLD             = UITheme.GOLD
local WHITE            = UITheme.WHITE
local DIM_TEXT         = UITheme.DIM_TEXT
local TOGGLE_ON        = UITheme.TOGGLE_ON
local TOGGLE_OFF       = UITheme.TOGGLE_OFF
local SLIDER_TRACK     = UITheme.SLIDER_TRACK
local SLIDER_FILL      = UITheme.GOLD
local KNOB_COLOR       = UITheme.KNOB_COLOR
local CHOICE_ACTIVE    = UITheme.GOLD
local CHOICE_INACTIVE  = UITheme.BTN_BG
local BTN_BG           = UITheme.BTN_BG
local BTN_STROKE       = UITheme.BTN_STROKE
local RED_BTN          = UITheme.RED_BTN
local POPUP_BG         = UITheme.POPUP_BG

local TWEEN_QUICK = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- Default settings
--------------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
	-- Audio
	MasterVolume      = 1.0,
	MusicVolume       = 0.5,
	SFXVolume         = 0.8,
	UISounds          = true,
	-- Graphics
	ReduceEffects     = false,
	Shadows           = true,
	GraphicsPreset    = "High",
	-- Gameplay
	CameraSensitivity = 0.5,   -- 0.1 .. 2.0
	InvertCamera      = false,
	SprintMode        = "Hold",
	ShowTooltips      = true,
	-- UI
	ShowMinimap       = true,
	ShowGameState     = true,
	UIScale           = "100%",
}

--------------------------------------------------------------------------------
-- Session-persistent settings (survives menu open / close)
--------------------------------------------------------------------------------
local PlayerSettings  -- initialised lazily

local function ensureSettings()
	if not PlayerSettings then
		PlayerSettings = {}
		for k, v in pairs(DEFAULT_SETTINGS) do
			PlayerSettings[k] = v
		end
	end
end
ensureSettings()

-- Expose globally so other scripts (camera, sprint, etc.) can read them
_G.PlayerSettings = PlayerSettings

--------------------------------------------------------------------------------
-- Connection cleanup (prevents leaks across repeated Create calls)
--------------------------------------------------------------------------------
local activeConnections = {}

local function trackConn(conn)
	table.insert(activeConnections, conn)
end

local function cleanupConnections()
	for _, conn in ipairs(activeConnections) do
		pcall(function() conn:Disconnect() end)
	end
	activeConnections = {}
end

--------------------------------------------------------------------------------
-- Popup management (module-level for reliable cleanup)
--------------------------------------------------------------------------------
local activePopup = nil

local function closePopup()
	if activePopup and activePopup.Parent then
		activePopup:Destroy()
	end
	activePopup = nil
end

--------------------------------------------------------------------------------
-- Apply settings to game systems
--------------------------------------------------------------------------------
local function ApplySettings(settings)
	-- AUDIO ──────────────────────────────────────────────────────────────
	-- Master Volume – SoundGroup "Master" under SoundService, or fall back
	pcall(function()
		local masterGroup = SoundService:FindFirstChild("Master")
		if masterGroup and masterGroup:IsA("SoundGroup") then
			masterGroup.Volume = settings.MasterVolume
		end
	end)

	-- Music Volume – SoundGroup "Music" under SoundService
	-- PLACEHOLDER: Create a SoundGroup called "Music" and parent music sounds
	-- to it for this slider to take effect.
	pcall(function()
		local musicGroup = SoundService:FindFirstChild("Music")
		if musicGroup and musicGroup:IsA("SoundGroup") then
			musicGroup.Volume = settings.MusicVolume
		end
	end)

	-- SFX Volume – SoundGroup "SFX" under SoundService
	-- PLACEHOLDER: Create a SoundGroup called "SFX" and parent effect sounds
	-- to it for this slider to take effect.
	pcall(function()
		local sfxGroup = SoundService:FindFirstChild("SFX")
		if sfxGroup and sfxGroup:IsA("SoundGroup") then
			sfxGroup.Volume = settings.SFXVolume
		end
	end)

	-- GRAPHICS ───────────────────────────────────────────────────────────
	pcall(function()
		Lighting.GlobalShadows = settings.Shadows
	end)

	-- Reduce Effects – PLACEHOLDER
	-- Tag your particle / trail / beam instances with CollectionService tag
	-- "GameEffect" and uncomment the block below to toggle them.
	-- pcall(function()
	--     local CollectionService = game:GetService("CollectionService")
	--     for _, obj in ipairs(CollectionService:GetTagged("GameEffect")) do
	--         if obj:IsA("ParticleEmitter") or obj:IsA("Trail")
	--            or obj:IsA("Beam") or obj:IsA("Fire")
	--            or obj:IsA("Smoke") or obj:IsA("Sparkles") then
	--             obj.Enabled = not settings.ReduceEffects
	--         end
	--     end
	-- end)

	-- Graphics Preset overrides
	pcall(function()
		if settings.GraphicsPreset == "Low" then
			Lighting.GlobalShadows = false
		elseif settings.GraphicsPreset == "High" then
			Lighting.GlobalShadows = true
		end
		-- "Medium" keeps the Shadows toggle value as-is
	end)

	-- GAMEPLAY ───────────────────────────────────────────────────────────
	-- Camera & sprint values are exposed via _G.PlayerSettings for
	-- CameraAndFacingLock.client.lua or other camera scripts to read.
	_G.PlayerSettings = settings

	-- UI ─────────────────────────────────────────────────────────────────
	-- Show Minimap
	pcall(function()
		local gui = playerGui:FindFirstChild("Minimap")
			or playerGui:FindFirstChild("MinimapGui")
		if gui then gui.Enabled = settings.ShowMinimap end
	end)

	-- Show Game State
	pcall(function()
		local gui = playerGui:FindFirstChild("GameStateDisplay")
			or playerGui:FindFirstChild("GameStateGui")
			or playerGui:FindFirstChild("MatchHUD")
		if gui then gui.Enabled = settings.ShowGameState end
	end)

	-- UI Scale – adjust UIScale on the main ScreenGui
	pcall(function()
		local mainGui = playerGui:FindFirstChild("MainUI")
		if mainGui then
			local uiScale = mainGui:FindFirstChildOfClass("UIScale")
			if not uiScale then
				uiScale = Instance.new("UIScale")
				uiScale.Parent = mainGui
			end
			local map = { ["90%"] = 0.9, ["100%"] = 1.0, ["110%"] = 1.1 }
			uiScale.Scale = map[settings.UIScale] or 1.0
		end
	end)

	-- Show Tooltips – PLACEHOLDER
	-- If you have tooltip frames, iterate and set Visible here.
end

_G.ApplySettings = ApplySettings

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local OptionsUI = {}

function OptionsUI.Create(parent, _coinApi, _inventoryApi)
	if not parent then return nil end

	-- Cleanup from previous open
	closePopup()
	cleanupConnections()

	for _, c in ipairs(parent:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
			and not c:IsA("UIPadding") then
			pcall(function() c:Destroy() end)
		end
	end

	ensureSettings()

	-- UI updater functions keyed by settingKey (for Reset Defaults)
	local uiUpdaters = {}

	---------------------------------------------------------------------------
	-- HELPER: Section header
	---------------------------------------------------------------------------
	local function createSectionHeader(parentFrame, text, layoutOrder)
		local headerWrap = Instance.new("Frame")
		headerWrap.Name = text .. "_Header"
		headerWrap.BackgroundTransparency = 1
		headerWrap.Size = UDim2.new(1, 0, 0, px(36))
		headerWrap.LayoutOrder = layoutOrder
		headerWrap.Parent = parentFrame

		local header = Instance.new("TextLabel")
		header.Name = "Title"
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.Text = text
		header.TextColor3 = GOLD
		header.TextSize = math.max(16, math.floor(px(18)))
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Size = UDim2.new(1, 0, 0, px(26))
		header.Position = UDim2.new(0, 0, 0, 0)
		header.Parent = headerWrap

		local accentBar = Instance.new("Frame")
		accentBar.Name = "AccentBar"
		accentBar.BackgroundColor3 = GOLD
		accentBar.BackgroundTransparency = 0.3
		accentBar.Size = UDim2.new(1, 0, 0, px(2))
		accentBar.Position = UDim2.new(0, 0, 1, -px(2))
		accentBar.BorderSizePixel = 0
		accentBar.Parent = headerWrap

		return headerWrap
	end

	---------------------------------------------------------------------------
	-- HELPER: Setting row container
	---------------------------------------------------------------------------
	local function createRow(parentFrame, layoutOrder)
		local row = Instance.new("Frame")
		row.Name = "SettingRow"
		row.BackgroundColor3 = ROW_BG
		row.Size = UDim2.new(1, 0, 0, px(42))
		row.LayoutOrder = layoutOrder
		row.Parent = parentFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, px(10))
		corner.Parent = row

		local stroke = Instance.new("UIStroke")
		stroke.Color = CARD_STROKE
		stroke.Thickness = 1.2
		stroke.Transparency = 0.4
		stroke.Parent = row

		local grad = Instance.new("UIGradient")
		grad.Color = UITheme.ROW_GRADIENT
		grad.Rotation = 90
		grad.Parent = row

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, px(12))
		pad.PaddingRight = UDim.new(0, px(12))
		pad.Parent = row

		return row
	end

	---------------------------------------------------------------------------
	-- HELPER: Toggle (ON / OFF)
	---------------------------------------------------------------------------
	local function createToggle(parentFrame, label, settingKey, layoutOrder)
		local row = createRow(parentFrame, layoutOrder)
		row.Name = "Toggle_" .. settingKey

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = label
		lbl.TextColor3 = WHITE
		lbl.TextSize = math.max(13, math.floor(px(14)))
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Size = UDim2.new(0.55, 0, 1, 0)
		lbl.Parent = row

		-- Status text
		local statusLbl = Instance.new("TextLabel")
		statusLbl.Name = "Status"
		statusLbl.BackgroundTransparency = 1
		statusLbl.Font = Enum.Font.GothamBold
		statusLbl.TextColor3 = GOLD
		statusLbl.TextSize = math.max(12, math.floor(px(13)))
		statusLbl.TextXAlignment = Enum.TextXAlignment.Right
		statusLbl.AnchorPoint = Vector2.new(1, 0.5)
		statusLbl.Position = UDim2.new(0.72, 0, 0.5, 0)
		statusLbl.Size = UDim2.new(0.14, 0, 1, 0)
		statusLbl.Parent = row

		-- Toggle track
		local trackW, trackH = px(48), px(24)
		local track = Instance.new("TextButton")
		track.Name = "ToggleTrack"
		track.Text = ""
		track.AutoButtonColor = false
		track.Size = UDim2.new(0, trackW, 0, trackH)
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, 0, 0.5, 0)
		track.BackgroundColor3 = TOGGLE_OFF
		track.Parent = row

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local trackStroke = Instance.new("UIStroke")
		trackStroke.Color = CARD_STROKE
		trackStroke.Thickness = 1
		trackStroke.Transparency = 0.5
		trackStroke.Parent = track

		local knobSize = trackH - px(4)
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.Size = UDim2.new(0, knobSize, 0, knobSize)
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.BackgroundColor3 = KNOB_COLOR
		knob.Parent = track

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1, 0)
		knobCorner.Parent = knob

		local function setVisual(on)
			local goalTrackColor = on and TOGGLE_ON or TOGGLE_OFF
			local goalStrokeColor = on and Color3.fromRGB(50, 220, 100) or CARD_STROKE
			local goalKnobPos = on
				and UDim2.new(1, -knobSize - px(2), 0.5, 0)
				or  UDim2.new(0, px(2), 0.5, 0)
			pcall(function()
				TweenService:Create(track, TWEEN_QUICK, {BackgroundColor3 = goalTrackColor}):Play()
				TweenService:Create(trackStroke, TWEEN_QUICK, {Color = goalStrokeColor, Transparency = on and 0.3 or 0.5}):Play()
				TweenService:Create(knob, TWEEN_QUICK, {Position = goalKnobPos}):Play()
			end)
			statusLbl.Text = on and "ON" or "OFF"
			statusLbl.TextColor3 = on and TOGGLE_ON or DIM_TEXT
		end
		setVisual(PlayerSettings[settingKey])

		track.MouseButton1Click:Connect(function()
			PlayerSettings[settingKey] = not PlayerSettings[settingKey]
			setVisual(PlayerSettings[settingKey])
			ApplySettings(PlayerSettings)
		end)

		uiUpdaters[settingKey] = function(val) setVisual(val) end
		return row
	end

	---------------------------------------------------------------------------
	-- HELPER: Slider
	---------------------------------------------------------------------------
	local function createSlider(parentFrame, label, settingKey, min, max, step, formatFn, layoutOrder)
		local row = createRow(parentFrame, layoutOrder)
		row.Name = "Slider_" .. settingKey
		row.Size = UDim2.new(1, 0, 0, px(46))

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = label
		lbl.TextColor3 = WHITE
		lbl.TextSize = math.max(13, math.floor(px(14)))
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Size = UDim2.new(0.30, 0, 1, 0)
		lbl.Parent = row

		-- Value display (right side)
		local valLabel = Instance.new("TextLabel")
		valLabel.Name = "Value"
		valLabel.BackgroundTransparency = 1
		valLabel.Font = Enum.Font.GothamBold
		valLabel.TextColor3 = GOLD
		valLabel.TextSize = math.max(13, math.floor(px(14)))
		valLabel.TextXAlignment = Enum.TextXAlignment.Right
		valLabel.AnchorPoint = Vector2.new(1, 0)
		valLabel.Position = UDim2.new(1, 0, 0, 0)
		valLabel.Size = UDim2.new(0.12, 0, 1, 0)
		valLabel.Parent = row

		-- Slider area (between label and value)
		local sliderArea = Instance.new("Frame")
		sliderArea.Name = "SliderArea"
		sliderArea.BackgroundTransparency = 1
		sliderArea.Size = UDim2.new(0.52, 0, 1, 0)
		sliderArea.Position = UDim2.new(0.32, 0, 0, 0)
		sliderArea.ClipsDescendants = false
		sliderArea.Parent = row

		-- Track
		local trackH = px(8)
		local trackFrame = Instance.new("Frame")
		trackFrame.Name = "Track"
		trackFrame.BackgroundColor3 = SLIDER_TRACK
		trackFrame.Size = UDim2.new(1, 0, 0, trackH)
		trackFrame.AnchorPoint = Vector2.new(0, 0.5)
		trackFrame.Position = UDim2.new(0, 0, 0.5, 0)
		trackFrame.ClipsDescendants = true
		trackFrame.Parent = sliderArea

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = trackFrame

		local trackStroke = Instance.new("UIStroke")
		trackStroke.Color = CARD_STROKE
		trackStroke.Thickness = 1
		trackStroke.Transparency = 0.5
		trackStroke.Parent = trackFrame

		-- Fill
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = SLIDER_FILL
		fill.Size = UDim2.new(0.5, 0, 1, 0)
		fill.Parent = trackFrame

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		-- Knob (sibling of track so it isn't clipped)
		local knobSize = px(18)
		local sliderKnob = Instance.new("Frame")
		sliderKnob.Name = "Knob"
		sliderKnob.BackgroundColor3 = KNOB_COLOR
		sliderKnob.Size = UDim2.new(0, knobSize, 0, knobSize)
		sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
		sliderKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
		sliderKnob.ZIndex = 2
		sliderKnob.Parent = sliderArea

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1, 0)
		knobCorner.Parent = sliderKnob

		local knobStroke = Instance.new("UIStroke")
		knobStroke.Color = GOLD
		knobStroke.Thickness = 1.5
		knobStroke.Transparency = 0.3
		knobStroke.Parent = sliderKnob

		local function updateVisual(value)
			local t = math.clamp((value - min) / (max - min), 0, 1)
			fill.Size = UDim2.new(t, 0, 1, 0)
			sliderKnob.Position = UDim2.new(t, 0, 0.5, 0)
			if formatFn then
				valLabel.Text = formatFn(value)
			else
				valLabel.Text = tostring(math.floor(value * 100)) .. "%"
			end
		end
		updateVisual(PlayerSettings[settingKey])

		-- Transparent hit area over slider for drag input
		local hitArea = Instance.new("TextButton")
		hitArea.Name = "HitArea"
		hitArea.Text = ""
		hitArea.BackgroundTransparency = 1
		hitArea.Size = UDim2.new(1, 0, 1, 0)
		hitArea.ZIndex = 3
		hitArea.Parent = sliderArea

		local dragging = false

		local function processInput(input)
			local absPos = trackFrame.AbsolutePosition.X
			local absSize = trackFrame.AbsoluteSize.X
			if absSize <= 0 then return end
			local relX = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
			local rawVal = min + relX * (max - min)
			if step > 0 then
				rawVal = math.floor(rawVal / step + 0.5) * step
			end
			rawVal = math.clamp(rawVal, min, max)
			PlayerSettings[settingKey] = rawVal
			updateVisual(rawVal)
			ApplySettings(PlayerSettings)
		end

		hitArea.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				processInput(input)
			end
		end)

		local c1 = UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				processInput(input)
			end
		end)
		trackConn(c1)

		local c2 = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		trackConn(c2)

		uiUpdaters[settingKey] = function(val) updateVisual(val) end
		return row
	end

	---------------------------------------------------------------------------
	-- HELPER: Choice selector (horizontal buttons)
	---------------------------------------------------------------------------
	local function createChoiceButtons(parentFrame, label, settingKey, choices, layoutOrder)
		local row = createRow(parentFrame, layoutOrder)
		row.Name = "Choice_" .. settingKey

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = label
		lbl.TextColor3 = WHITE
		lbl.TextSize = math.max(13, math.floor(px(14)))
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Size = UDim2.new(0.35, 0, 1, 0)
		lbl.Parent = row

		local btnArea = Instance.new("Frame")
		btnArea.Name = "ButtonArea"
		btnArea.BackgroundTransparency = 1
		btnArea.Size = UDim2.new(0.62, 0, 0.70, 0)
		btnArea.AnchorPoint = Vector2.new(1, 0.5)
		btnArea.Position = UDim2.new(1, 0, 0.5, 0)
		btnArea.Parent = row

		local btnLayout = Instance.new("UIListLayout")
		btnLayout.FillDirection = Enum.FillDirection.Horizontal
		btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		btnLayout.Padding = UDim.new(0, px(4))
		btnLayout.Parent = btnArea

		local buttons = {}

		local function refreshHighlights()
			local current = PlayerSettings[settingKey]
			for _, info in ipairs(buttons) do
				local isActive = (info.value == current)
				local goalBg = isActive and CHOICE_ACTIVE or CHOICE_INACTIVE
				local goalTxt = isActive and Color3.fromRGB(20, 20, 24) or WHITE
				pcall(function()
					TweenService:Create(info.btn, TWEEN_QUICK, {BackgroundColor3 = goalBg}):Play()
				end)
				info.btn.TextColor3 = goalTxt
			end
		end

		for i, choice in ipairs(choices) do
			local btn = Instance.new("TextButton")
			btn.Name = "Choice_" .. tostring(choice)
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = CHOICE_INACTIVE
			btn.Font = Enum.Font.GothamBold
			btn.Text = tostring(choice)
			btn.TextColor3 = WHITE
			btn.TextSize = math.max(11, math.floor(px(12)))
			btn.Size = UDim2.new(1 / #choices, -px(3), 1, 0)
			btn.LayoutOrder = i
			btn.Parent = btnArea

			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, px(8))
			c.Parent = btn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Color = CARD_STROKE
			btnStroke.Thickness = 1
			btnStroke.Transparency = 0.5
			btnStroke.Parent = btn

			table.insert(buttons, { btn = btn, value = choice })

			btn.MouseButton1Click:Connect(function()
				PlayerSettings[settingKey] = choice
				refreshHighlights()
				ApplySettings(PlayerSettings)
			end)
		end

		refreshHighlights()

		uiUpdaters[settingKey] = function(_val)
			refreshHighlights()
		end

		return row
	end

	---------------------------------------------------------------------------
	-- HELPER: Action button
	---------------------------------------------------------------------------
	local function createActionButton(parentFrame, label, color, callback, layoutOrder)
		local btn = Instance.new("TextButton")
		btn.Name = "ActionBtn_" .. label:gsub("%s+", "")
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = color or BTN_BG
		btn.Font = Enum.Font.GothamBold
		btn.Text = label
		btn.TextColor3 = WHITE
		btn.TextSize = math.max(13, math.floor(px(14)))
		btn.Size = UDim2.new(0.30, 0, 0, px(36))
		btn.LayoutOrder = layoutOrder or 0
		btn.Parent = parentFrame

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, px(10))
		c.Parent = btn

		local s = Instance.new("UIStroke")
		s.Color = BTN_STROKE
		s.Thickness = 1.2
		s.Transparency = 0.3
		s.Parent = btn

		local btnGrad = Instance.new("UIGradient")
		btnGrad.Color = ColorSequence.new(
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(200, 200, 200)
		)
		btnGrad.Rotation = 90
		btnGrad.Parent = btn

		btn.MouseEnter:Connect(function()
			pcall(function()
				TweenService:Create(btn, TWEEN_QUICK, {
					BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15)
				}):Play()
			end)
		end)
		btn.MouseLeave:Connect(function()
			pcall(function()
				TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = color}):Play()
			end)
		end)

		btn.MouseButton1Click:Connect(function()
			if type(callback) == "function" then callback() end
		end)

		return btn
	end

	---------------------------------------------------------------------------
	-- POPUP helper (Controls / Credits)
	---------------------------------------------------------------------------
	local window = parent.Parent -- ModalWindow frame

	local function showPopup(title, lines)
		closePopup()
		if not window then return end

		local overlay = Instance.new("Frame")
		overlay.Name = "OptionsPopup"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		overlay.BackgroundTransparency = 0.35
		overlay.ZIndex = 500
		overlay.Parent = window
		activePopup = overlay

		local popup = Instance.new("Frame")
		popup.Name = "PopupCard"
		popup.Size = UDim2.new(0.60, 0, 0.65, 0)
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.Position = UDim2.new(0.5, 0, 0.5, 0)
		popup.BackgroundColor3 = POPUP_BG
		popup.ZIndex = 510
		popup.Parent = overlay

		local popCorner = Instance.new("UICorner")
		popCorner.CornerRadius = UDim.new(0, px(14))
		popCorner.Parent = popup

		local popStroke = Instance.new("UIStroke")
		popStroke.Color = UITheme.GOLD_DIM
		popStroke.Thickness = 1.5
		popStroke.Transparency = 0.15
		popStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		popStroke.Parent = popup

		local popGrad = Instance.new("UIGradient")
		popGrad.Color = UITheme.PANEL_GRADIENT
		popGrad.Rotation = UITheme.PANEL_GRADIENT_ROTATION
		popGrad.Parent = popup

		-- Title
		local titleLbl = Instance.new("TextLabel")
		titleLbl.Name = "PopupTitle"
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBlack
		titleLbl.Text = title
		titleLbl.TextColor3 = GOLD
		titleLbl.TextSize = math.max(16, math.floor(px(20)))
		titleLbl.Size = UDim2.new(1, 0, 0, px(34))
		titleLbl.Position = UDim2.new(0, 0, 0, px(10))
		titleLbl.ZIndex = 520
		titleLbl.Parent = popup

		-- Close button — dark + gold style
		local CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
		local CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)
		local CLOSE_PRESS   = Color3.fromRGB(18, 20, 32)

		local popClose = Instance.new("TextButton")
		popClose.Name = "PopupClose"
		popClose.Text = "X"
		popClose.Font = Enum.Font.GothamBlack
		popClose.TextScaled = true
		popClose.Size = UDim2.new(0, px(30), 0, px(30))
		popClose.AnchorPoint = Vector2.new(1, 0)
		popClose.Position = UDim2.new(1, -px(6), 0, px(6))
		popClose.BackgroundColor3 = CLOSE_DEFAULT
		popClose.TextColor3 = GOLD
		popClose.AutoButtonColor = false
		popClose.BorderSizePixel = 0
		popClose.ZIndex = 530
		popClose.Parent = popup

		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, px(8))
		cbCorner.Parent = popClose

		local cbStroke = Instance.new("UIStroke")
		cbStroke.Color = GOLD
		cbStroke.Thickness = 1.2
		cbStroke.Transparency = 0.4
		cbStroke.Parent = popClose

		-- Hover / press feedback
		local closeFeedback = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		popClose.MouseEnter:Connect(function()
			TweenService:Create(popClose, closeFeedback, {BackgroundColor3 = CLOSE_HOVER}):Play()
			TweenService:Create(popClose, closeFeedback, {TextColor3 = WHITE}):Play()
		end)
		popClose.MouseLeave:Connect(function()
			TweenService:Create(popClose, closeFeedback, {BackgroundColor3 = CLOSE_DEFAULT}):Play()
			TweenService:Create(popClose, closeFeedback, {TextColor3 = GOLD}):Play()
		end)
		popClose.MouseButton1Down:Connect(function()
			TweenService:Create(popClose, closeFeedback, {BackgroundColor3 = CLOSE_PRESS}):Play()
		end)
		popClose.MouseButton1Up:Connect(function()
			TweenService:Create(popClose, closeFeedback, {BackgroundColor3 = CLOSE_HOVER}):Play()
		end)

		popClose.MouseButton1Click:Connect(function()
			closePopup()
		end)

		-- Scrolling content
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "PopupScroll"
		scroll.BackgroundTransparency = 1
		scroll.Size = UDim2.new(0.88, 0, 0.72, 0)
		scroll.AnchorPoint = Vector2.new(0.5, 1)
		scroll.Position = UDim2.new(0.5, 0, 1, -px(10))
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollBarThickness = px(3)
		scroll.ScrollBarImageColor3 = GOLD
		scroll.BorderSizePixel = 0
		scroll.ZIndex = 520
		scroll.Parent = popup

		local cl = Instance.new("UIListLayout")
		cl.SortOrder = Enum.SortOrder.LayoutOrder
		cl.Padding = UDim.new(0, px(4))
		cl.Parent = scroll

		local scrollPad = Instance.new("UIPadding")
		scrollPad.PaddingLeft = UDim.new(0, px(6))
		scrollPad.PaddingRight = UDim.new(0, px(6))
		scrollPad.Parent = scroll

		for i, line in ipairs(lines) do
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamMedium
			l.Text = line
			l.TextColor3 = WHITE
			l.TextSize = math.max(12, math.floor(px(14)))
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Size = UDim2.new(1, 0, 0, 0)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.LayoutOrder = i
			l.ZIndex = 520
			l.Parent = scroll
		end
	end

	---------------------------------------------------------------------------
	-- Root container
	---------------------------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name = "OptionsUI"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Parent = parent

	local rootLayout = Instance.new("UIListLayout")
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rootLayout.Padding = UDim.new(0, px(10))
	rootLayout.Parent = root

	local rootPad = Instance.new("UIPadding")
	rootPad.PaddingTop = UDim.new(0, px(6))
	rootPad.PaddingBottom = UDim.new(0, px(16))
	rootPad.PaddingLeft = UDim.new(0, px(8))
	rootPad.PaddingRight = UDim.new(0, px(8))
	rootPad.Parent = root

	-- Sequential layout order counter
	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	---------------------------------------------------------------------------
	-- AUDIO section
	---------------------------------------------------------------------------
	createSectionHeader(root, "AUDIO", nextOrder())
	createSlider(root, "Master Volume", "MasterVolume", 0, 1, 0.01,
		function(v) return math.floor(v * 100) .. "%" end, nextOrder())
	createSlider(root, "Music Volume", "MusicVolume", 0, 1, 0.01,
		function(v) return math.floor(v * 100) .. "%" end, nextOrder())
	createSlider(root, "SFX Volume", "SFXVolume", 0, 1, 0.01,
		function(v) return math.floor(v * 100) .. "%" end, nextOrder())
	createToggle(root, "UI Sounds", "UISounds", nextOrder())

	---------------------------------------------------------------------------
	-- GRAPHICS section
	---------------------------------------------------------------------------
	createSectionHeader(root, "GRAPHICS", nextOrder())
	createToggle(root, "Reduce Effects", "ReduceEffects", nextOrder())
	createToggle(root, "Shadows", "Shadows", nextOrder())
	createChoiceButtons(root, "Graphics Preset", "GraphicsPreset",
		{ "Low", "Medium", "High" }, nextOrder())

	---------------------------------------------------------------------------
	-- GAMEPLAY section
	---------------------------------------------------------------------------
	createSectionHeader(root, "GAMEPLAY", nextOrder())
	createSlider(root, "Camera Sensitivity", "CameraSensitivity", 0.1, 2.0, 0.1,
		function(v) return string.format("%.1f", v) end, nextOrder())
	createToggle(root, "Invert Camera", "InvertCamera", nextOrder())
	createChoiceButtons(root, "Sprint Mode", "SprintMode",
		{ "Hold", "Toggle" }, nextOrder())
	createToggle(root, "Show Tooltips", "ShowTooltips", nextOrder())

	---------------------------------------------------------------------------
	-- UI section
	---------------------------------------------------------------------------
	createSectionHeader(root, "UI", nextOrder())
	createToggle(root, "Show Minimap", "ShowMinimap", nextOrder())
	createToggle(root, "Show Scoreboard", "ShowGameState", nextOrder())
	createChoiceButtons(root, "UI Scale", "UIScale",
		{ "90%", "100%", "110%" }, nextOrder())

	---------------------------------------------------------------------------
	-- OTHER section
	---------------------------------------------------------------------------
	createSectionHeader(root, "OTHER", nextOrder())

	local btnRow = Instance.new("Frame")
	btnRow.Name = "ActionButtonRow"
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, px(38))
	btnRow.LayoutOrder = nextOrder()
	btnRow.Parent = root

	local btnRowLayout = Instance.new("UIListLayout")
	btnRowLayout.FillDirection = Enum.FillDirection.Horizontal
	btnRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnRowLayout.Padding = UDim.new(0, px(8))
	btnRowLayout.Parent = btnRow

	createActionButton(btnRow, "Controls", BTN_BG, function()
		showPopup("CONTROLS", {
			"WASD  –  Move",
			"Space  –  Jump",
			"Shift  –  Sprint",
			"E  –  Interact / Pick Up",
			"Q  –  Drop / Release",
			"1-9  –  Hotbar Slots",
			"Tab  –  Scoreboard",
			"M  –  Toggle Minimap",
			"Esc  –  Pause / Menu",
			"",
			"Mouse1  –  Attack / Fire",
			"Mouse2  –  Aim / Block",
			"R  –  Reload",
		})
	end, 1)

	createActionButton(btnRow, "Credits", BTN_BG, function()
		showPopup("CREDITS", {
			"KingsGround: WSG",
			"",
			"Game Design & Programming",
			"   Your Name Here",
			"",
			"Art & Assets",
			"   Your Name Here",
			"",
			"Sound & Music",
			"   Your Name Here",
			"",
			"Special Thanks",
			"   The Roblox Community",
			"",
			"Built with Roblox Studio",
		})
	end, 2)

	createActionButton(btnRow, "Reset Defaults", RED_BTN, function()
		for k, v in pairs(DEFAULT_SETTINGS) do
			PlayerSettings[k] = v
		end
		for key, updater in pairs(uiUpdaters) do
			pcall(updater, PlayerSettings[key])
		end
		ApplySettings(PlayerSettings)
	end, 3)

	---------------------------------------------------------------------------
	-- Apply current state on open
	---------------------------------------------------------------------------
	ApplySettings(PlayerSettings)

	return root
end

return OptionsUI
