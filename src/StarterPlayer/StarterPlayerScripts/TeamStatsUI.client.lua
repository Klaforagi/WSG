-- TeamStatsUI.client.lua
-- Custom Team Stats overlay for KingsGround.
-- Shows per-player stats organized by Blue/Red team.
-- Toggle: Teams button (SideUI), press Tab, or MenuController.
-- Now managed through the shared MenuController so it participates in
-- the same open/close system as Shop, Inventory, Quests, etc.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- MenuController: centralized menu management (loaded from ReplicatedStorage.SideUI)
local MenuController = nil
do
	local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI", 10)
	if sideUIFolder then
		local mcMod = sideUIFolder:WaitForChild("MenuController", 5)
		if mcMod and mcMod:IsA("ModuleScript") then
			local ok, result = pcall(require, mcMod)
			if ok then
				MenuController = result
				print("[TeamStatsUI] MenuController loaded")
			else
				warn("[TeamStatsUI] MenuController failed:", tostring(result))
			end
		end
	end
end

-- Wait for viewport to be ready (same pattern as SideUI / MatchHUD)
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

---------------------------------------------------------------------------
-- Color palette (matches KingsGround MatchHUD / SideUI)
---------------------------------------------------------------------------
local NAVY         = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT   = Color3.fromRGB(22, 26, 48)
local GOLD         = Color3.fromRGB(255, 215, 80)
local GOLD_DIM     = Color3.fromRGB(180, 150, 50)
local BLUE_ACCENT  = Color3.fromRGB(65, 105, 225)
local BLUE_BG      = Color3.fromRGB(16, 24, 56)
local RED_ACCENT   = Color3.fromRGB(255, 75, 75)
local RED_BG       = Color3.fromRGB(56, 16, 20)
local WHITE        = Color3.fromRGB(235, 235, 240)
local GRAY         = Color3.fromRGB(140, 140, 155)

---------------------------------------------------------------------------
-- Column definitions
---------------------------------------------------------------------------
local COLUMNS = {
	{ key = "Level",        label = "Level",          width = 0.07 },
	{ key = "Name",         label = "Player",         width = 0.27 },
	{ key = "Score",        label = "Score",          width = 0.10 },
	{ key = "Eliminations", label = "Eliminations",   width = 0.14 },
	{ key = "Deaths",       label = "Deaths",         width = 0.10 },
	{ key = "FlagCaptures", label = "Flag Captures",  width = 0.16 },
	{ key = "FlagReturns",  label = "Flag Returns",   width = 0.16 },
}

local AVATAR_SIZE        = 46
local ROW_HEIGHT         = 56
local TEAM_HEADER_HEIGHT = 46

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local isVisible = false
local isPinned  = false   -- true when open (from either Teams button or Tab)

---------------------------------------------------------------------------
-- ScreenGui
---------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "TeamStatsUI"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.DisplayOrder    = 270
screenGui.Parent          = playerGui

---------------------------------------------------------------------------
-- Full-screen dark overlay behind panel (matches SideUI modal pattern)
---------------------------------------------------------------------------
local modalOverlay = Instance.new("Frame")
modalOverlay.Name                 = "ModalOverlay"
modalOverlay.Size                 = UDim2.new(1, 0, 1, 0)
modalOverlay.Position             = UDim2.new(0, 0, 0, 0)
modalOverlay.BackgroundColor3     = Color3.fromRGB(10, 10, 10)
modalOverlay.BackgroundTransparency = 0.5
modalOverlay.BorderSizePixel      = 0
modalOverlay.Visible              = false
modalOverlay.ZIndex               = 0
modalOverlay.Parent               = screenGui

---------------------------------------------------------------------------
-- Main panel
---------------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name                 = "TeamStatsPanel"
panel.AnchorPoint          = Vector2.new(0.5, 0.5)
panel.Position             = UDim2.new(0.5, 0, 0.5, 0)
panel.Size                 = UDim2.new(0.72, 0, 0.82, 0)
panel.BackgroundColor3     = NAVY
panel.BackgroundTransparency = 0.04
panel.Visible              = false
panel.ClipsDescendants     = true
panel.ZIndex               = 1
panel.Parent               = screenGui

do
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, px(12))

	local s = Instance.new("UIStroke")
	s.Color            = GOLD_DIM
	s.Thickness        = 1.5
	s.Transparency     = 0.15
	s.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
	s.Parent           = panel

	local g = Instance.new("UIGradient")
	g.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
	})
	g.Rotation = 90
	g.Parent   = panel

	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(740, 480)
	sc.MaxSize = Vector2.new(1600, 1050)
	sc.Parent  = panel
end

local panelPad = Instance.new("UIPadding")
panelPad.PaddingTop    = UDim.new(0, px(18))
panelPad.PaddingBottom = UDim.new(0, px(16))
panelPad.PaddingLeft   = UDim.new(0, px(28))
panelPad.PaddingRight  = UDim.new(0, px(28))
panelPad.Parent        = panel

---------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------
local HEADER_H = px(58)

local header = Instance.new("Frame")
header.Name                 = "Header"
header.Size                 = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundTransparency = 1
header.Parent               = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name                 = "Title"
titleLabel.Size                 = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font                 = Enum.Font.GothamBlack
titleLabel.Text                 = "STATS"
titleLabel.TextSize             = px(44)
titleLabel.TextColor3           = GOLD
titleLabel.TextXAlignment       = Enum.TextXAlignment.Center
titleLabel.Parent               = header

do
	local ts = Instance.new("UIStroke")
	ts.Color        = Color3.fromRGB(120, 100, 30)
	ts.Thickness    = 1.5
	ts.Transparency = 0.4
	ts.Parent       = titleLabel
end

---------------------------------------------------------------------------
-- Close X button (top-right, matches SideUI modal style)
---------------------------------------------------------------------------
local CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
local CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)
local CLOSE_PRESS   = Color3.fromRGB(18, 20, 32)

local closeBtn = Instance.new("TextButton")
closeBtn.Name                 = "Close"
closeBtn.Text                 = "X"
closeBtn.Font                 = Enum.Font.GothamBlack
closeBtn.TextScaled           = true
closeBtn.Size                 = UDim2.new(0, px(40), 0, px(40))
closeBtn.AnchorPoint          = Vector2.new(1, 0)
closeBtn.Position             = UDim2.new(1, 0, 0, 0)
closeBtn.BackgroundColor3     = CLOSE_DEFAULT
closeBtn.TextColor3           = GOLD
closeBtn.AutoButtonColor      = false
closeBtn.BorderSizePixel      = 0
closeBtn.ZIndex               = 10
closeBtn.Parent               = header

do
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, px(8))
	cc.Parent       = closeBtn
end
do
	local cs = Instance.new("UIStroke")
	cs.Color        = GOLD
	cs.Thickness    = 1.2
	cs.Transparency = 0.4
	cs.Parent       = closeBtn
end

do
	local fi = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, fi, {BackgroundColor3 = CLOSE_HOVER}):Play()
		TweenService:Create(closeBtn, fi, {TextColor3 = Color3.new(1, 1, 1)}):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, fi, {BackgroundColor3 = CLOSE_DEFAULT}):Play()
		TweenService:Create(closeBtn, fi, {TextColor3 = GOLD}):Play()
	end)
	closeBtn.MouseButton1Down:Connect(function()
		TweenService:Create(closeBtn, fi, {BackgroundColor3 = CLOSE_PRESS}):Play()
	end)
	closeBtn.MouseButton1Up:Connect(function()
		TweenService:Create(closeBtn, fi, {BackgroundColor3 = CLOSE_HOVER}):Play()
	end)
end

do
	local sep = Instance.new("Frame")
	sep.Size                 = UDim2.new(1, 0, 0, 1)
	sep.Position             = UDim2.new(0, 0, 1, px(2))
	sep.BackgroundColor3     = GOLD_DIM
	sep.BackgroundTransparency = 0.55
	sep.BorderSizePixel      = 0
	sep.Parent               = header
end

---------------------------------------------------------------------------
-- Tab bar (Team Stats / Career)
---------------------------------------------------------------------------
local TAB_BAR_H = px(42)
local TAB_GAP   = px(8)
local TAB_BAR_Y = HEADER_H + px(8)

local tabBar = Instance.new("Frame")
tabBar.Name                 = "TabBar"
tabBar.Size                 = UDim2.new(1, 0, 0, TAB_BAR_H)
tabBar.Position             = UDim2.new(0, 0, 0, TAB_BAR_Y)
tabBar.BackgroundTransparency = 1
tabBar.Parent               = panel

local TAB_ACTIVE_BG     = Color3.fromRGB(32, 30, 18)
local TAB_INACTIVE_BG   = NAVY_LIGHT
local TAB_ACTIVE_TEXT    = GOLD
local TAB_INACTIVE_TEXT  = GRAY
local TAB_ACTIVE_STROKE  = GOLD_DIM
local TAB_INACTIVE_STROKE = Color3.fromRGB(55, 62, 95)

local activeTab = "TeamStats"  -- default tab

local function createTabButton(name, label, layoutOrder)
	local btn = Instance.new("TextButton")
	btn.Name                 = name .. "Tab"
	btn.Size                 = UDim2.new(0.5, -TAB_GAP / 2, 1, 0)
	btn.BackgroundColor3     = TAB_INACTIVE_BG
	btn.BackgroundTransparency = 0.05
	btn.Font                 = Enum.Font.GothamBold
	btn.Text                 = label
	btn.TextSize             = px(20)
	btn.TextColor3           = TAB_INACTIVE_TEXT
	btn.AutoButtonColor      = false
	btn.BorderSizePixel      = 0
	btn.LayoutOrder          = layoutOrder
	btn.Parent               = tabBar
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, px(8))
	local stroke = Instance.new("UIStroke")
	stroke.Color           = TAB_INACTIVE_STROKE
	stroke.Thickness       = 1.2
	stroke.Transparency    = 0.3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent          = btn

	-- Hover effect
	local fi = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		if activeTab ~= name then
			TweenService:Create(btn, fi, {BackgroundColor3 = Color3.fromRGB(28, 26, 18)}):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		if activeTab ~= name then
			TweenService:Create(btn, fi, {BackgroundColor3 = TAB_INACTIVE_BG}):Play()
		end
	end)

	return btn, stroke
end

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection       = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
tabLayout.Padding             = UDim.new(0, TAB_GAP)
tabLayout.SortOrder           = Enum.SortOrder.LayoutOrder
tabLayout.Parent              = tabBar

local teamStatsTabBtn, teamStatsTabStroke = createTabButton("TeamStats", "TEAM STATS", 1)
local careerTabBtn, careerTabStroke       = createTabButton("Career",    "CAREER",     2)

-- Tab separator
do
	local sep = Instance.new("Frame")
	sep.Size                 = UDim2.new(1, 0, 0, 1)
	sep.Position             = UDim2.new(0, 0, 0, TAB_BAR_Y + TAB_BAR_H + px(4))
	sep.BackgroundColor3     = GOLD_DIM
	sep.BackgroundTransparency = 0.55
	sep.BorderSizePixel      = 0
	sep.Parent               = panel
end

---------------------------------------------------------------------------
-- Content area offset (accounts for header + tab bar)
---------------------------------------------------------------------------
local CONTENT_AREA_TOP = TAB_BAR_Y + TAB_BAR_H + px(8)

---------------------------------------------------------------------------
-- Team Stats container (wraps column headers + scoreboard + footer)
---------------------------------------------------------------------------
local teamStatsContainer = Instance.new("Frame")
teamStatsContainer.Name                 = "TeamStatsContainer"
teamStatsContainer.Size                 = UDim2.new(1, 0, 1, -CONTENT_AREA_TOP)
teamStatsContainer.Position             = UDim2.new(0, 0, 0, CONTENT_AREA_TOP)
teamStatsContainer.BackgroundTransparency = 1
teamStatsContainer.Visible              = true
teamStatsContainer.Parent               = panel

---------------------------------------------------------------------------
-- Career container (populated on demand)
---------------------------------------------------------------------------
local careerContainer = Instance.new("ScrollingFrame")
careerContainer.Name                    = "CareerContainer"
careerContainer.Size                    = UDim2.new(1, 0, 1, -CONTENT_AREA_TOP)
careerContainer.Position                = UDim2.new(0, 0, 0, CONTENT_AREA_TOP)
careerContainer.BackgroundTransparency  = 1
careerContainer.ScrollBarThickness      = px(5)
careerContainer.ScrollBarImageColor3    = GOLD_DIM
careerContainer.ScrollBarImageTransparency = 0.3
careerContainer.CanvasSize              = UDim2.new(0, 0, 0, 0)
careerContainer.AutomaticCanvasSize     = Enum.AutomaticSize.Y
careerContainer.BorderSizePixel         = 0
careerContainer.Visible                 = false
careerContainer.Parent                  = panel

local careerLayout = Instance.new("UIListLayout")
careerLayout.SortOrder         = Enum.SortOrder.LayoutOrder
careerLayout.Padding           = UDim.new(0, px(14))
careerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
careerLayout.Parent            = careerContainer

local careerPad = Instance.new("UIPadding")
careerPad.PaddingTop    = UDim.new(0, px(10))
careerPad.PaddingBottom = UDim.new(0, px(20))
careerPad.PaddingLeft   = UDim.new(0, px(10))
careerPad.PaddingRight  = UDim.new(0, px(10))
careerPad.Parent        = careerContainer

---------------------------------------------------------------------------
-- Tab switching logic
---------------------------------------------------------------------------
local function updateTabVisuals()
	local fi = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if activeTab == "TeamStats" then
		TweenService:Create(teamStatsTabBtn, fi, {BackgroundColor3 = TAB_ACTIVE_BG, TextColor3 = TAB_ACTIVE_TEXT}):Play()
		teamStatsTabStroke.Color = TAB_ACTIVE_STROKE
		TweenService:Create(careerTabBtn, fi, {BackgroundColor3 = TAB_INACTIVE_BG, TextColor3 = TAB_INACTIVE_TEXT}):Play()
		careerTabStroke.Color = TAB_INACTIVE_STROKE
	else
		TweenService:Create(careerTabBtn, fi, {BackgroundColor3 = TAB_ACTIVE_BG, TextColor3 = TAB_ACTIVE_TEXT}):Play()
		careerTabStroke.Color = TAB_ACTIVE_STROKE
		TweenService:Create(teamStatsTabBtn, fi, {BackgroundColor3 = TAB_INACTIVE_BG, TextColor3 = TAB_INACTIVE_TEXT}):Play()
		teamStatsTabStroke.Color = TAB_INACTIVE_STROKE
	end
end

local function selectTab(tabName)
	if activeTab == tabName then return end
	activeTab = tabName
	teamStatsContainer.Visible = (tabName == "TeamStats")
	careerContainer.Visible    = (tabName == "Career")
	updateTabVisuals()
	if tabName == "Career" then
		populateCareerTab()  -- forward-declared below
	end
end

-- Initialize active tab visuals
updateTabVisuals()

teamStatsTabBtn.MouseButton1Click:Connect(function() selectTab("TeamStats") end)
careerTabBtn.MouseButton1Click:Connect(function() selectTab("Career") end)

---------------------------------------------------------------------------
-- Column headers (now inside teamStatsContainer)
---------------------------------------------------------------------------
local COL_H_Y = px(4)
local COL_H_H = px(38)

local colHeaderRow = Instance.new("Frame")
colHeaderRow.Name                 = "ColumnHeaders"
colHeaderRow.Size                 = UDim2.new(1, 0, 0, COL_H_H)
colHeaderRow.Position             = UDim2.new(0, 0, 0, COL_H_Y)
colHeaderRow.BackgroundTransparency = 1
colHeaderRow.Parent               = teamStatsContainer

for i, col in ipairs(COLUMNS) do
	local xOff = 0
	for j = 1, i - 1 do xOff = xOff + COLUMNS[j].width end

	local lbl = Instance.new("TextLabel")
	lbl.Name                 = "ColH_" .. col.key
	lbl.BackgroundTransparency = 1
	lbl.Font                 = Enum.Font.GothamBold
	lbl.TextSize             = px(20)
	lbl.TextColor3           = GRAY
	lbl.Text                 = col.label
	lbl.TextXAlignment       = (col.key == "Name") and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center

	if col.key == "Name" then
		lbl.Position = UDim2.new(xOff, px(AVATAR_SIZE + 16), 0, 0)
		lbl.Size     = UDim2.new(col.width, -px(AVATAR_SIZE + 16), 1, 0)
	else
		lbl.Position = UDim2.new(xOff, 0, 0, 0)
		lbl.Size     = UDim2.new(col.width, 0, 1, 0)
	end
	lbl.Parent = colHeaderRow
end

do
	local sep = Instance.new("Frame")
	sep.Size                 = UDim2.new(1, 0, 0, 1)
	sep.Position             = UDim2.new(0, 0, 1, px(1))
	sep.BackgroundColor3     = GOLD_DIM
	sep.BackgroundTransparency = 0.70
	sep.BorderSizePixel      = 0
	sep.Parent               = colHeaderRow
end

---------------------------------------------------------------------------
-- Footer sizing constants
---------------------------------------------------------------------------
local FOOTER_BTN_H     = px(44)
local FOOTER_PAD       = px(10)
local FOOTER_SEP       = 1
local FOOTER_TEAM_H    = px(46)
local FOOTER_COLLAPSED  = FOOTER_SEP + FOOTER_PAD + FOOTER_BTN_H + FOOTER_PAD
local FOOTER_EXPANDED   = FOOTER_COLLAPSED + FOOTER_TEAM_H + FOOTER_PAD

local currentFooterH = FOOTER_COLLAPSED

---------------------------------------------------------------------------
-- Scrolling content  (leaves room for footer)
---------------------------------------------------------------------------
local CONTENT_TOP = COL_H_Y + COL_H_H + px(4)

local contentScroll = Instance.new("ScrollingFrame")
contentScroll.Name                    = "Content"
contentScroll.Position                = UDim2.new(0, 0, 0, CONTENT_TOP)
contentScroll.Size                    = UDim2.new(1, 0, 1, -CONTENT_TOP - currentFooterH)
contentScroll.BackgroundTransparency  = 1
contentScroll.ScrollBarThickness      = px(5)
contentScroll.ScrollBarImageColor3    = GOLD_DIM
contentScroll.ScrollBarImageTransparency = 0.3
contentScroll.CanvasSize              = UDim2.new(0, 0, 0, 0)
contentScroll.AutomaticCanvasSize     = Enum.AutomaticSize.Y
contentScroll.BorderSizePixel         = 0
contentScroll.Parent                  = teamStatsContainer

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding   = UDim.new(0, px(12))
contentLayout.Parent    = contentScroll

---------------------------------------------------------------------------
-- Footer: Change Team section
---------------------------------------------------------------------------
local footer = Instance.new("Frame")
footer.Name                 = "ChangeTeamFooter"
footer.Size                 = UDim2.new(1, 0, 0, currentFooterH)
footer.Position             = UDim2.new(0, 0, 1, -currentFooterH)
footer.BackgroundTransparency = 1
footer.ClipsDescendants     = true
footer.Parent               = teamStatsContainer

-- Separator
do
	local sep = Instance.new("Frame")
	sep.Name                 = "FooterSep"
	sep.Size                 = UDim2.new(1, 0, 0, FOOTER_SEP)
	sep.Position             = UDim2.new(0, 0, 0, 0)
	sep.BackgroundColor3     = GOLD_DIM
	sep.BackgroundTransparency = 0.55
	sep.BorderSizePixel      = 0
	sep.Parent               = footer
end

-- "CHANGE TEAM" button
local changeTeamBtn = Instance.new("TextButton")
changeTeamBtn.Name                 = "ChangeTeamBtn"
changeTeamBtn.Size                 = UDim2.new(0, px(240), 0, FOOTER_BTN_H)
changeTeamBtn.Position             = UDim2.new(0.5, 0, 0, FOOTER_SEP + FOOTER_PAD)
changeTeamBtn.AnchorPoint          = Vector2.new(0.5, 0)
changeTeamBtn.BackgroundColor3     = NAVY_LIGHT
changeTeamBtn.BackgroundTransparency = 0.05
changeTeamBtn.Font                 = Enum.Font.GothamBold
changeTeamBtn.Text                 = "CHANGE TEAM"
changeTeamBtn.TextSize             = px(18)
changeTeamBtn.TextColor3           = GOLD
changeTeamBtn.AutoButtonColor      = true
changeTeamBtn.Parent               = footer
Instance.new("UICorner", changeTeamBtn).CornerRadius = UDim.new(0, px(8))
do
	local s = Instance.new("UIStroke")
	s.Color           = GOLD_DIM
	s.Thickness       = 1.5
	s.Transparency    = 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = changeTeamBtn
end

-- Team picker row (hidden initially)
local teamPicker = Instance.new("Frame")
teamPicker.Name                 = "TeamPicker"
teamPicker.Size                 = UDim2.new(1, 0, 0, FOOTER_TEAM_H)
teamPicker.Position             = UDim2.new(0, 0, 0, FOOTER_SEP + FOOTER_PAD + FOOTER_BTN_H + FOOTER_PAD)
teamPicker.BackgroundTransparency = 1
teamPicker.Visible              = false
teamPicker.Parent               = footer

do
	local lay = Instance.new("UIListLayout")
	lay.FillDirection       = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment   = Enum.VerticalAlignment.Center
	lay.Padding             = UDim.new(0, px(24))
	lay.Parent              = teamPicker
end

local function makeTeamButton(name, accentColor, bgColor)
	local btn = Instance.new("TextButton")
	btn.Name                 = "Join" .. name .. "Btn"
	btn.Size                 = UDim2.new(0, px(210), 0, FOOTER_TEAM_H)
	btn.BackgroundColor3     = bgColor
	btn.BackgroundTransparency = 0.12
	btn.Font                 = Enum.Font.GothamBold
	btn.Text                 = "JOIN " .. string.upper(name) .. " TEAM"
	btn.TextSize             = px(17)
	btn.TextColor3           = WHITE
	btn.AutoButtonColor      = true
	btn.Parent               = teamPicker
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, px(8))
	local s = Instance.new("UIStroke")
	s.Color           = accentColor
	s.Thickness       = 1.5
	s.Transparency    = 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent          = btn
	return btn
end

local joinBlueBtn = makeTeamButton("Blue", BLUE_ACCENT, BLUE_BG)
local joinRedBtn  = makeTeamButton("Red",  RED_ACCENT,  RED_BG)

-- Track team picker expanded state
local teamPickerOpen = false

local function setFooterHeight(h)
	currentFooterH = h
	footer.Size     = UDim2.new(1, 0, 0, h)
	footer.Position = UDim2.new(0, 0, 1, -h)
	contentScroll.Size = UDim2.new(1, 0, 1, -CONTENT_TOP - h)
end

local function refreshTeamButtons()
	local currentTeamName = player.Team and player.Team.Name or ""
	if currentTeamName == "Blue" then
		joinBlueBtn.Text            = "CURRENT TEAM"
		joinBlueBtn.TextColor3      = GRAY
		joinBlueBtn.AutoButtonColor = false
		joinBlueBtn.BackgroundTransparency = 0.45
		joinRedBtn.Text             = "JOIN RED TEAM"
		joinRedBtn.TextColor3       = WHITE
		joinRedBtn.AutoButtonColor  = true
		joinRedBtn.BackgroundTransparency = 0.12
	elseif currentTeamName == "Red" then
		joinRedBtn.Text             = "CURRENT TEAM"
		joinRedBtn.TextColor3       = GRAY
		joinRedBtn.AutoButtonColor  = false
		joinRedBtn.BackgroundTransparency = 0.45
		joinBlueBtn.Text            = "JOIN BLUE TEAM"
		joinBlueBtn.TextColor3      = WHITE
		joinBlueBtn.AutoButtonColor = true
		joinBlueBtn.BackgroundTransparency = 0.12
	else
		joinBlueBtn.Text            = "JOIN BLUE TEAM"
		joinBlueBtn.TextColor3      = WHITE
		joinBlueBtn.AutoButtonColor = true
		joinBlueBtn.BackgroundTransparency = 0.12
		joinRedBtn.Text             = "JOIN RED TEAM"
		joinRedBtn.TextColor3       = WHITE
		joinRedBtn.AutoButtonColor  = true
		joinRedBtn.BackgroundTransparency = 0.12
	end
end

local function toggleTeamPicker()
	teamPickerOpen = not teamPickerOpen
	teamPicker.Visible = teamPickerOpen
	if teamPickerOpen then
		refreshTeamButtons()
		changeTeamBtn.Text = "CANCEL"
		setFooterHeight(FOOTER_EXPANDED)
	else
		changeTeamBtn.Text = "CHANGE TEAM"
		setFooterHeight(FOOTER_COLLAPSED)
	end
end

local function collapseTeamPicker()
	if teamPickerOpen then
		teamPickerOpen = false
		teamPicker.Visible = false
		changeTeamBtn.Text = "CHANGE TEAM"
		setFooterHeight(FOOTER_COLLAPSED)
	end
end

changeTeamBtn.MouseButton1Click:Connect(toggleTeamPicker)

-- Fire team change requests
local changeTeamRequest  = nil  -- resolved lazily
local changeTeamResponse = nil

local function getChangeRemotes()
	if not changeTeamRequest then
		changeTeamRequest  = ReplicatedStorage:WaitForChild("ChangeTeamRequest", 10)
		changeTeamResponse = ReplicatedStorage:WaitForChild("ChangeTeamResponse", 10)
	end
	return changeTeamRequest, changeTeamResponse
end

joinBlueBtn.MouseButton1Click:Connect(function()
	if player.Team and player.Team.Name == "Blue" then return end
	local req = getChangeRemotes()
	if req then req:FireServer("Blue") end
end)

joinRedBtn.MouseButton1Click:Connect(function()
	if player.Team and player.Team.Name == "Red" then return end
	local req = getChangeRemotes()
	if req then req:FireServer("Red") end
end)

-- Listen for server response
task.spawn(function()
	local _, resp = getChangeRemotes()
	if resp then
		resp.OnClientEvent:Connect(function(success, _msg)
			if success then
				collapseTeamPicker()
				-- Rebuild stats after short delay to let team switch propagate
				task.wait(0.4)
				if isVisible then rebuildAll() end
			end
		end)
	end
end)

-- Refresh buttons when local player team changes
player:GetPropertyChangedSignal("Team"):Connect(refreshTeamButtons)

---------------------------------------------------------------------------
-- Team section builder
---------------------------------------------------------------------------
local function createTeamSection(teamName, layoutOrder)
	local teamColor = (teamName == "Blue") and BLUE_ACCENT or RED_ACCENT
	local teamBg    = (teamName == "Blue") and BLUE_BG or RED_BG

	local section = Instance.new("Frame")
	section.Name                 = teamName .. "Section"
	section.Size                 = UDim2.new(1, 0, 0, 0)
	section.AutomaticSize        = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	section.LayoutOrder          = layoutOrder
	section.Parent               = contentScroll

	local secLayout = Instance.new("UIListLayout")
	secLayout.SortOrder = Enum.SortOrder.LayoutOrder
	secLayout.Padding   = UDim.new(0, px(4))
	secLayout.Parent    = section

	-- Team header bar
	local teamHeader = Instance.new("Frame")
	teamHeader.Name                 = "TeamHeader"
	teamHeader.Size                 = UDim2.new(1, 0, 0, px(TEAM_HEADER_HEIGHT))
	teamHeader.BackgroundColor3     = teamBg
	teamHeader.BackgroundTransparency = 0.25
	teamHeader.LayoutOrder          = 0
	teamHeader.Parent               = section
	Instance.new("UICorner", teamHeader).CornerRadius = UDim.new(0, px(6))

	-- Colored accent bar
	local accent = Instance.new("Frame")
	accent.Name            = "AccentBar"
	accent.Size            = UDim2.new(0, px(5), 0.55, 0)
	accent.Position        = UDim2.new(0, px(8), 0.225, 0)
	accent.BackgroundColor3 = teamColor
	accent.BorderSizePixel = 0
	accent.Parent          = teamHeader
	Instance.new("UICorner", accent).CornerRadius = UDim.new(0, px(3))

	-- Team label with player count
	local teamLabel = Instance.new("TextLabel")
	teamLabel.Name                 = "TeamLabel"
	teamLabel.Size                 = UDim2.new(1, -px(28), 1, 0)
	teamLabel.Position             = UDim2.new(0, px(22), 0, 0)
	teamLabel.BackgroundTransparency = 1
	teamLabel.Font                 = Enum.Font.GothamBold
	teamLabel.TextSize             = px(22)
	teamLabel.TextColor3           = teamColor
	teamLabel.TextXAlignment       = Enum.TextXAlignment.Left
	teamLabel.Parent               = teamHeader

	-- Update label text with player count
	local function updateTeamLabel()
		local count = 0
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Team and plr.Team.Name == teamName then count = count + 1 end
		end
		teamLabel.Text = string.upper(teamName) .. " TEAM  (" .. count .. ")"
	end
	updateTeamLabel()

	return section, updateTeamLabel
end

---------------------------------------------------------------------------
-- Avatar cache
---------------------------------------------------------------------------
local avatarCache = {}

local function fetchAvatar(userId, callback)
	if avatarCache[userId] then
		callback(avatarCache[userId])
		return
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48
			)
		end)
		if ok and url then
			avatarCache[userId] = url
			callback(url)
		end
	end)
end

---------------------------------------------------------------------------
-- Stat helpers
---------------------------------------------------------------------------
local function getPlayerStat(plr, key)
	if key == "Level" then
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			local lv = ls:FindFirstChild("Level")
			if lv then return lv.Value end
		end
		return plr:GetAttribute("Level") or 1
	end
	return plr:GetAttribute(key) or 0
end

---------------------------------------------------------------------------
-- Player row builder
---------------------------------------------------------------------------
local function createPlayerRow(plr, teamName, order)
	local isLocal = (plr == player)

	local row = Instance.new("Frame")
	row.Name                 = "Row_" .. plr.Name
	row.Size                 = UDim2.new(1, 0, 0, px(ROW_HEIGHT))
	row.BackgroundColor3     = isLocal and Color3.fromRGB(30, 34, 58) or NAVY_LIGHT
	row.BackgroundTransparency = isLocal and 0.05 or 0.30
	row.LayoutOrder          = order
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(6))

	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft  = UDim.new(0, px(8))
	rowPad.PaddingRight = UDim.new(0, px(8))
	rowPad.Parent       = row

	if isLocal then
		local hs = Instance.new("UIStroke")
		hs.Color           = GOLD_DIM
		hs.Thickness       = 1.5
		hs.Transparency    = 0.30
		hs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		hs.Parent          = row
	end

	local cells = {}

	for i, col in ipairs(COLUMNS) do
		local xOff = 0
		for j = 1, i - 1 do xOff = xOff + COLUMNS[j].width end

		if col.key == "Name" then
			-- Avatar
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.Name                 = "Avatar"
			avatarImg.Size                 = UDim2.new(0, px(AVATAR_SIZE), 0, px(AVATAR_SIZE))
			avatarImg.Position             = UDim2.new(xOff, px(8), 0.5, 0)
			avatarImg.AnchorPoint          = Vector2.new(0, 0.5)
			avatarImg.BackgroundColor3     = Color3.fromRGB(40, 40, 52)
			avatarImg.BackgroundTransparency = 0.25
			avatarImg.Parent               = row
			Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)

			do
				local avStroke = Instance.new("UIStroke")
				avStroke.Color        = Color3.fromRGB(70, 70, 90)
				avStroke.Thickness    = 1.5
				avStroke.Transparency = 0.3
				avStroke.Parent       = avatarImg
			end

			fetchAvatar(plr.UserId, function(url)
				if avatarImg and avatarImg.Parent then avatarImg.Image = url end
			end)

			-- Player name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name                 = "CellName"
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position             = UDim2.new(xOff, px(AVATAR_SIZE + 16), 0, 0)
			nameLabel.Size                 = UDim2.new(col.width, -px(AVATAR_SIZE + 22), 1, 0)
			nameLabel.Font                 = Enum.Font.GothamBold
			nameLabel.TextSize             = px(22)
			nameLabel.TextColor3           = isLocal and GOLD or WHITE
			nameLabel.TextXAlignment       = Enum.TextXAlignment.Left
			nameLabel.TextTruncate         = Enum.TextTruncate.AtEnd
			nameLabel.Text                 = plr.DisplayName
			nameLabel.Parent               = row
			cells["Name"] = nameLabel
		else
			local cell = Instance.new("TextLabel")
			cell.Name                 = "Cell_" .. col.key
			cell.BackgroundTransparency = 1
			cell.Position             = UDim2.new(xOff, 0, 0, 0)
			cell.Size                 = UDim2.new(col.width, 0, 1, 0)
			cell.Font                 = (col.key == "Score") and Enum.Font.GothamBlack or Enum.Font.GothamBold
			cell.TextSize             = px(22)
			cell.TextColor3           = (col.key == "Score") and GOLD or WHITE
			cell.TextXAlignment       = Enum.TextXAlignment.Center
			cell.Text                 = tostring(getPlayerStat(plr, col.key))
			cell.Parent               = row
			cells[col.key] = cell
		end
	end

	return row, cells
end

---------------------------------------------------------------------------
-- Data management
---------------------------------------------------------------------------
local playerRows = {}  -- plr -> { row, cells, connections }

local blueSection, updateBlueLabel = createTeamSection("Blue", 1)
local redSection,  updateRedLabel  = createTeamSection("Red", 2)

local function updateRow(plr)
	local info = playerRows[plr]
	if not info then return end
	for _, col in ipairs(COLUMNS) do
		if col.key ~= "Name" and info.cells[col.key] then
			info.cells[col.key].Text = tostring(getPlayerStat(plr, col.key))
		end
	end
end

local function sortTeamSection(section, teamName)
	local teamPlayers = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and playerRows[plr] then
			table.insert(teamPlayers, plr)
		end
	end
	table.sort(teamPlayers, function(a, b)
		local sa, sb = getPlayerStat(a, "Score"), getPlayerStat(b, "Score")
		if sa ~= sb then return sa > sb end
		return getPlayerStat(a, "Eliminations") > getPlayerStat(b, "Eliminations")
	end)
	for i, plr in ipairs(teamPlayers) do
		playerRows[plr].row.LayoutOrder = i
	end
end

local function cleanupPlayerRow(plr)
	local info = playerRows[plr]
	if not info then return end
	if info.row then pcall(function() info.row:Destroy() end) end
	for _, conn in ipairs(info.connections or {}) do
		pcall(function() conn:Disconnect() end)
	end
	playerRows[plr] = nil
end

local function addPlayerRow(plr)
	if playerRows[plr] then return end
	local teamName = plr.Team and plr.Team.Name
	if teamName ~= "Blue" and teamName ~= "Red" then return end

	local section = (teamName == "Blue") and blueSection or redSection
	local row, cells = createPlayerRow(plr, teamName, 999)
	row.Parent = section

	local connections = {}

	-- Listen for attribute stat changes
	for _, key in ipairs({"Score", "Eliminations", "Deaths", "FlagCaptures", "FlagReturns", "Level"}) do
		table.insert(connections, plr:GetAttributeChangedSignal(key):Connect(function()
			updateRow(plr)
			sortTeamSection(section, teamName)
		end))
	end

	-- leaderstats.Level
	task.spawn(function()
		local ls = plr:WaitForChild("leaderstats", 5)
		if not ls then return end
		local lv = ls:WaitForChild("Level", 3)
		if lv and lv:IsA("IntValue") then
			table.insert(connections, lv.Changed:Connect(function()
				if cells["Level"] then cells["Level"].Text = tostring(lv.Value) end
			end))
		end
	end)

	playerRows[plr] = { row = row, cells = cells, connections = connections }
	sortTeamSection(section, teamName)
end

local function rebuildAll()
	-- Clear previous rows
	for plr, _ in pairs(playerRows) do
		cleanupPlayerRow(plr)
	end
	-- Rebuild
	for _, plr in ipairs(Players:GetPlayers()) do
		addPlayerRow(plr)
	end
	updateBlueLabel()
	updateRedLabel()
end

---------------------------------------------------------------------------
-- Player lifecycle + team changes
---------------------------------------------------------------------------
local teamConns = {}

local function watchPlayer(plr)
	if teamConns[plr] then pcall(function() teamConns[plr]:Disconnect() end) end
	teamConns[plr] = plr:GetPropertyChangedSignal("Team"):Connect(function()
		cleanupPlayerRow(plr)
		if isVisible then
			task.wait(0.1)
			addPlayerRow(plr)
			updateBlueLabel()
			updateRedLabel()
		end
	end)
	if isVisible then addPlayerRow(plr) end
end

local function unwatchPlayer(plr)
	if teamConns[plr] then pcall(function() teamConns[plr]:Disconnect() end) end
	teamConns[plr] = nil
	cleanupPlayerRow(plr)
	if isVisible then
		updateBlueLabel()
		updateRedLabel()
	end
end

for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
Players.PlayerAdded:Connect(function(plr) watchPlayer(plr) end)
Players.PlayerRemoving:Connect(function(plr) unwatchPlayer(plr) end)

---------------------------------------------------------------------------
-- Career Tab: Helpers & Builder
---------------------------------------------------------------------------

--- Format a number with commas (e.g. 12345 → "12,345")
local function formatStatNumber(value)
	local n = tonumber(value) or 0
	if n == 0 then return "0" end
	local str = tostring(math.floor(n))
	local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then formatted = formatted:sub(2) end
	return formatted
end

--- Format seconds into human-readable playtime (e.g. 8043 → "2h 14m")
local function formatPlaytime(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds < 60 then
		return seconds .. "s"
	end
	local mins = math.floor(seconds / 60)
	local hrs  = math.floor(mins / 60)
	mins = mins % 60
	if hrs > 0 then
		return string.format("%dh %02dm", hrs, mins)
	end
	return mins .. "m"
end

--- Lazily resolve the GetCareerStats remote
local careerStatsRemote = nil
local function getCareerStatsRemote()
	if careerStatsRemote then return careerStatsRemote end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
	if remotes then
		careerStatsRemote = remotes:WaitForChild("GetCareerStats", 5)
	end
	return careerStatsRemote
end

--- Whether the Career tab has been populated at least once
local careerBuilt = false

--- Build or update the Career tab content
function populateCareerTab()
	-- Fetch stats from server
	local remote = getCareerStatsRemote()
	if not remote then
		warn("[TeamStatsUI] GetCareerStats remote not found")
		return
	end

	local ok, profileData = pcall(function()
		return remote:InvokeServer()
	end)
	if not ok or type(profileData) ~= "table" then
		warn("[TeamStatsUI] Failed to fetch career stats:", tostring(profileData))
		return
	end

	-- Clear previous content if rebuilding
	for _, child in ipairs(careerContainer:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local layoutOrder = 0
	local function nextOrder()
		layoutOrder = layoutOrder + 1
		return layoutOrder
	end

	---------------------------------------------------------------------------
	-- Player Profile Header
	---------------------------------------------------------------------------
	local profileFrame = Instance.new("Frame")
	profileFrame.Name                 = "ProfileHeader"
	profileFrame.Size                 = UDim2.new(1, 0, 0, px(150))
	profileFrame.BackgroundColor3     = NAVY_LIGHT
	profileFrame.BackgroundTransparency = 0.15
	profileFrame.LayoutOrder          = nextOrder()
	profileFrame.Parent               = careerContainer
	Instance.new("UICorner", profileFrame).CornerRadius = UDim.new(0, px(10))
	do
		local s = Instance.new("UIStroke")
		s.Color           = GOLD_DIM
		s.Thickness       = 1.2
		s.Transparency    = 0.35
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent          = profileFrame
	end

	local profPad = Instance.new("UIPadding")
	profPad.PaddingLeft   = UDim.new(0, px(20))
	profPad.PaddingRight  = UDim.new(0, px(20))
	profPad.PaddingTop    = UDim.new(0, px(14))
	profPad.PaddingBottom = UDim.new(0, px(14))
	profPad.Parent        = profileFrame

	-- Avatar
	local avatarSize = px(96)
	local avatarFrame = Instance.new("ImageLabel")
	avatarFrame.Name                 = "Avatar"
	avatarFrame.Size                 = UDim2.new(0, avatarSize, 0, avatarSize)
	avatarFrame.Position             = UDim2.new(0, 0, 0.5, 0)
	avatarFrame.AnchorPoint          = Vector2.new(0, 0.5)
	avatarFrame.BackgroundColor3     = Color3.fromRGB(40, 40, 52)
	avatarFrame.BackgroundTransparency = 0.2
	avatarFrame.Parent               = profileFrame
	Instance.new("UICorner", avatarFrame).CornerRadius = UDim.new(0, px(12))
	do
		local as = Instance.new("UIStroke")
		as.Color        = GOLD_DIM
		as.Thickness    = 1.5
		as.Transparency = 0.3
		as.Parent       = avatarFrame
	end

	-- Load avatar thumbnail
	task.spawn(function()
		local okA, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if okA and url and avatarFrame and avatarFrame.Parent then
			avatarFrame.Image = url
		end
	end)

	-- Player info (right of avatar)
	local infoX = avatarSize + px(16)

	local displayNameLabel = Instance.new("TextLabel")
	displayNameLabel.Name                 = "DisplayName"
	displayNameLabel.Size                 = UDim2.new(1, -infoX, 0, px(34))
	displayNameLabel.Position             = UDim2.new(0, infoX, 0, px(4))
	displayNameLabel.BackgroundTransparency = 1
	displayNameLabel.Font                 = Enum.Font.GothamBlack
	displayNameLabel.TextSize             = px(30)
	displayNameLabel.TextColor3           = GOLD
	displayNameLabel.TextXAlignment       = Enum.TextXAlignment.Left
	displayNameLabel.Text                 = player.DisplayName
	displayNameLabel.TextTruncate         = Enum.TextTruncate.AtEnd
	displayNameLabel.Parent               = profileFrame

	local usernameLabel = Instance.new("TextLabel")
	usernameLabel.Name                 = "Username"
	usernameLabel.Size                 = UDim2.new(1, -infoX, 0, px(22))
	usernameLabel.Position             = UDim2.new(0, infoX, 0, px(36))
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Font                 = Enum.Font.Gotham
	usernameLabel.TextSize             = px(19)
	usernameLabel.TextColor3           = GRAY
	usernameLabel.TextXAlignment       = Enum.TextXAlignment.Left
	usernameLabel.Text                 = "@" .. player.Name
	usernameLabel.Parent               = profileFrame

	-- Level / XP display
	local playerLevel = profileData._Level or player:GetAttribute("Level") or 1
	local playerXP    = profileData._XP or player:GetAttribute("XP") or 0
	local xpToNext    = profileData._XPToNext or player:GetAttribute("XPToNext") or 100
	local totalXP     = profileData._TotalXP or profileData.TotalXP or 0

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name                 = "Level"
	levelLabel.Size                 = UDim2.new(0.5, -infoX / 2, 0, px(26))
	levelLabel.Position             = UDim2.new(0, infoX, 0, px(62))
	levelLabel.BackgroundTransparency = 1
	levelLabel.Font                 = Enum.Font.GothamBold
	levelLabel.TextSize             = px(22)
	levelLabel.TextColor3           = WHITE
	levelLabel.TextXAlignment       = Enum.TextXAlignment.Left
	levelLabel.Text                 = "Level " .. tostring(playerLevel)
	levelLabel.Parent               = profileFrame

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name                 = "XPLabel"
	xpLabel.Size                 = UDim2.new(0.5, 0, 0, px(22))
	xpLabel.Position             = UDim2.new(0.5, 0, 0, px(64))
	xpLabel.BackgroundTransparency = 1
	xpLabel.Font                 = Enum.Font.GothamBold
	xpLabel.TextSize             = px(18)
	xpLabel.TextColor3           = GRAY
	xpLabel.TextXAlignment       = Enum.TextXAlignment.Right
	xpLabel.Text                 = formatStatNumber(playerXP) .. " / " .. formatStatNumber(xpToNext) .. " XP"
	xpLabel.Parent               = profileFrame

	-- XP progress bar
	local barBG = Instance.new("Frame")
	barBG.Name                 = "XPBarBG"
	barBG.Size                 = UDim2.new(1, -infoX, 0, px(14))
	barBG.Position             = UDim2.new(0, infoX, 0, px(92))
	barBG.BackgroundColor3     = Color3.fromRGB(35, 38, 58)
	barBG.BackgroundTransparency = 0
	barBG.Parent               = profileFrame
	Instance.new("UICorner", barBG).CornerRadius = UDim.new(1, 0)

	local fillPct = (xpToNext > 0) and math.clamp(playerXP / xpToNext, 0, 1) or 0
	local barFill = Instance.new("Frame")
	barFill.Name                 = "XPBarFill"
	barFill.Size                 = UDim2.new(fillPct, 0, 1, 0)
	barFill.BackgroundColor3     = GOLD
	barFill.BackgroundTransparency = 0
	barFill.Parent               = barBG
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	-- Win Rate placeholder
	local wins    = profileData.Wins or 0
	local losses  = profileData.Losses or 0
	local matches = profileData.MatchesPlayed or 0
	local winRate = (matches > 0) and math.floor((wins / matches) * 100 + 0.5) or 0

	local winRateLabel = Instance.new("TextLabel")
	winRateLabel.Name                 = "WinRate"
	winRateLabel.Size                 = UDim2.new(0, px(160), 0, px(30))
	winRateLabel.Position             = UDim2.new(1, -px(160), 0, px(4))
	winRateLabel.BackgroundColor3     = Color3.fromRGB(22, 38, 34)
	winRateLabel.BackgroundTransparency = 0.3
	winRateLabel.Font                 = Enum.Font.GothamBold
	winRateLabel.TextSize             = px(19)
	winRateLabel.TextColor3           = Color3.fromRGB(35, 190, 75)
	winRateLabel.Text                 = winRate .. "% WIN RATE"
	winRateLabel.Parent               = profileFrame
	Instance.new("UICorner", winRateLabel).CornerRadius = UDim.new(0, px(6))

	---------------------------------------------------------------------------
	-- Stat Section Builder
	---------------------------------------------------------------------------
	local function buildStatSection(sectionTitle, stats)
		local section = Instance.new("Frame")
		section.Name                 = sectionTitle .. "Section"
		section.Size                 = UDim2.new(1, 0, 0, 0)
		section.AutomaticSize        = Enum.AutomaticSize.Y
		section.BackgroundColor3     = NAVY_LIGHT
		section.BackgroundTransparency = 0.20
		section.LayoutOrder          = nextOrder()
		section.Parent               = careerContainer
		Instance.new("UICorner", section).CornerRadius = UDim.new(0, px(10))
		do
			local s = Instance.new("UIStroke")
			s.Color           = Color3.fromRGB(55, 62, 95)
			s.Thickness       = 1
			s.Transparency    = 0.4
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent          = section
		end

		local secPad = Instance.new("UIPadding")
		secPad.PaddingLeft   = UDim.new(0, px(20))
		secPad.PaddingRight  = UDim.new(0, px(20))
		secPad.PaddingTop    = UDim.new(0, px(14))
		secPad.PaddingBottom = UDim.new(0, px(14))
		secPad.Parent        = section

		local secLayout = Instance.new("UIListLayout")
		secLayout.SortOrder = Enum.SortOrder.LayoutOrder
		secLayout.Padding   = UDim.new(0, px(6))
		secLayout.Parent    = section

		-- Section header
		local headerLbl = Instance.new("TextLabel")
		headerLbl.Name                 = "SectionHeader"
		headerLbl.Size                 = UDim2.new(1, 0, 0, px(38))
		headerLbl.BackgroundTransparency = 1
		headerLbl.Font                 = Enum.Font.GothamBlack
		headerLbl.TextSize             = px(26)
		headerLbl.TextColor3           = GOLD
		headerLbl.TextXAlignment       = Enum.TextXAlignment.Left
		headerLbl.Text                 = string.upper(sectionTitle)
		headerLbl.LayoutOrder          = 0
		headerLbl.Parent               = section

		-- Section separator
		local secSep = Instance.new("Frame")
		secSep.Name                 = "Sep"
		secSep.Size                 = UDim2.new(1, 0, 0, 1)
		secSep.BackgroundColor3     = GOLD_DIM
		secSep.BackgroundTransparency = 0.65
		secSep.BorderSizePixel      = 0
		secSep.LayoutOrder          = 1
		secSep.Parent               = section

		-- Stat rows
		for i, stat in ipairs(stats) do
			local row = Instance.new("Frame")
			row.Name                 = stat.key
			row.Size                 = UDim2.new(1, 0, 0, px(48))
			row.BackgroundColor3     = (i % 2 == 0) and Color3.fromRGB(18, 20, 38) or Color3.fromRGB(24, 28, 52)
			row.BackgroundTransparency = (i % 2 == 0) and 0.20 or 0.45
			row.LayoutOrder          = i + 1
			row.Parent               = section
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(4))

			local rowPad = Instance.new("UIPadding")
			rowPad.PaddingLeft  = UDim.new(0, px(10))
			rowPad.PaddingRight = UDim.new(0, px(10))
			rowPad.Parent       = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name                 = "Label"
			nameLbl.Size                 = UDim2.new(0.65, 0, 1, 0)
			nameLbl.Position             = UDim2.new(0, 0, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font                 = Enum.Font.GothamBold
			nameLbl.TextSize             = px(22)
			nameLbl.TextColor3           = WHITE
			nameLbl.TextXAlignment       = Enum.TextXAlignment.Left
			nameLbl.Text                 = stat.label
			nameLbl.Parent               = row

			local rawValue = profileData[stat.key] or 0
			local displayValue
			if stat.formatter then
				displayValue = stat.formatter(rawValue)
			else
				displayValue = formatStatNumber(rawValue)
			end

			local valLbl = Instance.new("TextLabel")
			valLbl.Name                 = "Value"
			valLbl.Size                 = UDim2.new(0.35, 0, 1, 0)
			valLbl.Position             = UDim2.new(0.65, 0, 0, 0)
			valLbl.BackgroundTransparency = 1
			valLbl.Font                 = Enum.Font.GothamBlack
			valLbl.TextSize             = px(24)
			valLbl.TextColor3           = GOLD
			valLbl.TextXAlignment       = Enum.TextXAlignment.Right
			valLbl.Text                 = displayValue
			valLbl.Parent               = row
		end
	end

	---------------------------------------------------------------------------
	-- Build stat sections
	---------------------------------------------------------------------------
	buildStatSection("Combat", {
		{ key = "PlayersEliminated",       label = "Players Eliminated" },
		{ key = "MonstersEliminated",      label = "Monsters Eliminated" },
		{ key = "Deaths",                  label = "Deaths" },
		{ key = "HighestEliminationStreak", label = "Highest Elimination Streak" },
	})

	buildStatSection("Objective", {
		{ key = "FlagCaptures", label = "Flag Captures" },
		{ key = "FlagReturns",  label = "Flag Returns" },
	})

	buildStatSection("Progression", {
		{ key = "MatchesPlayed",        label = "Matches Played" },
		{ key = "Wins",                 label = "Wins" },
		{ key = "Losses",               label = "Losses" },
		{ key = "TotalXP",              label = "Total XP" },
		{ key = "TotalCoinsEarned",     label = "Total Coins Earned" },
		{ key = "AchievementsCompleted", label = "Achievements Completed" },
		{ key = "QuestsCompleted",      label = "Quests Completed" },
	})

	buildStatSection("Time", {
		{ key = "TotalPlaytimeSeconds", label = "Total Playtime", formatter = formatPlaytime },
	})

	-- Future placeholder: Title / Badge area
	local futureFrame = Instance.new("Frame")
	futureFrame.Name                 = "FuturePlaceholder"
	futureFrame.Size                 = UDim2.new(1, 0, 0, px(60))
	futureFrame.BackgroundColor3     = NAVY_LIGHT
	futureFrame.BackgroundTransparency = 0.5
	futureFrame.LayoutOrder          = nextOrder()
	futureFrame.Parent               = careerContainer
	Instance.new("UICorner", futureFrame).CornerRadius = UDim.new(0, px(10))

	local futureLbl = Instance.new("TextLabel")
	futureLbl.Size                 = UDim2.new(1, 0, 1, 0)
	futureLbl.BackgroundTransparency = 1
	futureLbl.Font                 = Enum.Font.Gotham
	futureLbl.TextSize             = px(20)
	futureLbl.TextColor3           = GRAY
	futureLbl.Text                 = "Titles & Badges coming soon..."
	futureLbl.Parent               = futureFrame

	careerBuilt = true
end

---------------------------------------------------------------------------
-- Show / Hide with tween
---------------------------------------------------------------------------
local TWEEN_IN  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function show()
	if isVisible then return end
	print("[TeamStatsUI] show() called")
	isVisible = true
	-- Default to Team Stats tab on open
	activeTab = "TeamStats"
	teamStatsContainer.Visible = true
	careerContainer.Visible    = false
	updateTabVisuals()
	collapseTeamPicker()
	refreshTeamButtons()
	rebuildAll()
	modalOverlay.Visible = true
	panel.Visible  = true

	-- Slide in from above
	panel.Position  = UDim2.new(0.5, 0, -0.35, 0)

	TweenService:Create(panel,  TWEEN_IN, { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
end

local function hide()
	if not isVisible then return end
	print("[TeamStatsUI] hide() called (animated)")
	isVisible = false
	collapseTeamPicker()

	local tw = TweenService:Create(panel, TWEEN_OUT, { Position = UDim2.new(0.5, 0, -0.35, 0) })
	tw:Play()
	tw.Completed:Connect(function()
		if not isVisible then
			panel.Visible  = false
			modalOverlay.Visible = false
			print("[TeamStatsUI] hide tween completed: panel+overlay hidden")
		end
	end)
end

---------------------------------------------------------------------------
-- Instant hide (no animation). Used by MenuController when switching menus.
-- sameGroup:    true when same overlay group (always false for Team).
-- isSwitching:  true when MenuController is opening another menu right
--               after this close.  When true we must keep our overlay
--               alive so the screen doesn't flash before the next menu's
--               overlay appears.
---------------------------------------------------------------------------
local function hideInstant(sameGroup, isSwitching)
	print(string.format(
		"[TeamStatsUI] hideInstant | sameGroup=%s | isSwitching=%s",
		tostring(sameGroup), tostring(isSwitching)))

	isVisible = false
	isPinned  = false
	collapseTeamPicker()
	panel.Visible = false

	if isSwitching then
		-- Another menu is about to open. Keep our dark overlay visible
		-- for this frame so there is no flash. The incoming menu will
		-- bring its own overlay; we defer cleanup to the next frame so
		-- the two overlays overlap briefly rather than leaving a gap.
		print("[TeamStatsUI] switch-away: overlay kept alive (deferred hide)")
		task.defer(function()
			-- Only hide if Team is still closed (another open would have
			-- set isVisible back to true).
			if not isVisible then
				modalOverlay.Visible = false
				print("[TeamStatsUI] deferred overlay hide executed")
			end
		end)
	else
		-- True close (no menu following). Hide overlay immediately.
		modalOverlay.Visible = false
		print("[TeamStatsUI] full close: overlay hidden immediately")
	end
end

---------------------------------------------------------------------------
-- Register "Team" with the shared MenuController
---------------------------------------------------------------------------
if MenuController then
	MenuController.RegisterMenu("Team", {
		group = "team",  -- own group (not modal)
		open = function(_sameGroup)
			print("[TeamStatsUI] open callback | sameGroup=", tostring(_sameGroup))
			show()
		end,
		close = function()
			print("[TeamStatsUI] close callback (animated)")
			hide()
		end,
		closeInstant = function(sameGroup, isSwitching)
			hideInstant(sameGroup, isSwitching)
		end,
		isOpen = function()
			return isVisible
		end,
	})
end

---------------------------------------------------------------------------
-- Toggle (shared by Teams button, Tab, and MenuController)
---------------------------------------------------------------------------
local function toggle()
	if MenuController then
		MenuController.ToggleMenu("Team")
	else
		-- Fallback if MenuController unavailable
		if isVisible then
			isPinned = false
			print("[TeamStatsUI] Team Stats board toggled CLOSED")
			hide()
		else
			isPinned = true
			print("[TeamStatsUI] Team Stats board toggled OPEN")
			show()
		end
	end
end

-- Keep legacy global for backward compatibility
_G.TeamStatsToggle = toggle

-- X button closes Team (routes through MenuController)
closeBtn.MouseButton1Click:Connect(function()
	if MenuController then
		MenuController.CloseMenu("Team")
	else
		if isVisible then isPinned = false; hide() end
	end
end)

---------------------------------------------------------------------------
-- Tab press-to-toggle
-- We intentionally do NOT check gameProcessed for Tab because Roblox's
-- core playerlist CoreScript always consumes it, which would block us.
-- Instead we only guard against typing in a TextBox.
---------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if input.KeyCode ~= Enum.KeyCode.Tab then return end
	print("[TeamStatsUI] Tab callback fired")
	if UserInputService:GetFocusedTextBox() then
		print("[TeamStatsUI] Toggle skipped — TextBox focused")
		return
	end
	toggle()
end)
print("[TeamStatsUI] Tab input listener connected via UserInputService")

-- Escape closes panel
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		if isVisible then
			if MenuController then
				MenuController.CloseMenu("Team")
			else
				isPinned = false
				hide()
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Match restart: refresh when stats reset
---------------------------------------------------------------------------
task.spawn(function()
	local matchStart = ReplicatedStorage:WaitForChild("MatchStart", 15)
	if matchStart and matchStart:IsA("RemoteEvent") then
		matchStart.OnClientEvent:Connect(function()
			if isVisible then
				task.wait(0.3)
				rebuildAll()
			end
		end)
	end
end)

return nil
