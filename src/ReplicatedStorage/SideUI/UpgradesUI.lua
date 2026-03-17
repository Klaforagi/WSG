--------------------------------------------------------------------------------
-- UpgradesUI.lua  –  Client-side Upgrades panel
-- Place in ReplicatedStorage > SideUI alongside BoostsUI / ShopUI etc.
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Shows purchasable permanent upgrades with level display, pricing, and
-- real-time state updates.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(script.Parent.UITheme)

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / BoostsUI)
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
local CARD_BG       = UITheme.CARD_BG
local CARD_STROKE   = UITheme.CARD_STROKE
local ICON_BG       = UITheme.ICON_BG
local GOLD          = UITheme.GOLD
local WHITE         = UITheme.WHITE
local DIM_TEXT      = UITheme.DIM_TEXT
local BTN_BG        = UITheme.BTN_BG
local BTN_STROKE_C  = UITheme.BTN_STROKE
local GREEN_BTN     = UITheme.GREEN_BTN
local RED_TEXT       = UITheme.RED_TEXT
local MAXED_COLOR   = UITheme.GREEN_GLOW
local DISABLED_BG   = UITheme.DISABLED_BG
local PIP_ACTIVE    = UITheme.PIP_ACTIVE
local PIP_INACTIVE  = UITheme.PIP_INACTIVE
local SUCCESS_FLASH = UITheme.GREEN_GLOW

local ACCENT_COLORS = {
	coin_mastery         = Color3.fromRGB(255, 200, 40),
	quest_mastery        = Color3.fromRGB(80, 165, 255),
	rapid_recovery       = Color3.fromRGB(120, 220, 160),
	objective_specialist = Color3.fromRGB(255, 120, 65),
}

local UPGRADE_GLYPHS = {
	coin_mastery         = "\u{1F4B0}",  -- 💰
	quest_mastery        = "\u{26A1}",   -- ⚡
	rapid_recovery       = "\u{1F3C3}",  -- 🏃
	objective_specialist = "\u{1F3AF}",  -- 🎯
}

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- UpgradeConfig (shared)
--------------------------------------------------------------------------------
local UpgradeConfig
pcall(function()
	local mod = ReplicatedStorage:WaitForChild("UpgradeConfig", 10)
	if mod and mod:IsA("ModuleScript") then
		UpgradeConfig = require(mod)
	end
end)

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local remotesFolder
local upgradeFolder
local purchaseRF
local getStatesRF
local stateUpdatedRE

local function ensureRemotes()
	if upgradeFolder then return true end
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then return false end
	upgradeFolder   = remotesFolder:WaitForChild("Upgrades", 5)
	stateUpdatedRE  = remotesFolder:WaitForChild("UpgradeStateUpdated", 5)
	if not upgradeFolder then return false end
	purchaseRF      = upgradeFolder:WaitForChild("RequestPurchaseUpgrade", 5)
	getStatesRF     = upgradeFolder:WaitForChild("GetUpgradeStates", 5)
	return purchaseRF ~= nil
end

--------------------------------------------------------------------------------
-- Connection cleanup
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
-- Notification toast (matches BoostsUI)
--------------------------------------------------------------------------------
local function showToast(parent, message, color, duration)
	color = color or GOLD
	duration = duration or 2.5
	local toast = Instance.new("TextLabel")
	toast.Name                = "Toast"
	toast.BackgroundColor3    = Color3.fromRGB(18, 20, 36)
	toast.BackgroundTransparency = 0.08
	toast.Size                = UDim2.new(0.85, 0, 0, px(40))
	toast.AnchorPoint         = Vector2.new(0.5, 0)
	toast.Position            = UDim2.new(0.5, 0, 0, px(6))
	toast.Font                = Enum.Font.GothamBold
	toast.TextSize            = math.max(13, math.floor(px(14)))
	toast.TextColor3          = color
	toast.Text                = message
	toast.TextWrapped         = true
	toast.ZIndex              = 400
	toast.Parent              = parent

	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0, px(10))
	cr.Parent = toast

	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = 1.2
	st.Transparency = 0.35
	st.Parent = toast

	-- Animate in
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency = 0.15, TextTransparency = 0}):Play()

	task.delay(duration, function()
		if toast and toast.Parent then
			local t = TweenService:Create(toast, TweenInfo.new(0.3), {BackgroundTransparency = 1, TextTransparency = 1})
			t:Play()
			t.Completed:Connect(function()
				pcall(function() toast:Destroy() end)
			end)
		end
	end)
end

--------------------------------------------------------------------------------
-- Coin icon widget (matches BoostsUI / DailyQuestsUI pattern)
--------------------------------------------------------------------------------
local function makeCoinIcon(parentFrame, size)
	local coin = Instance.new("Frame")
	coin.Name            = "CoinIcon"
	coin.Size            = UDim2.new(0, size, 0, size)
	coin.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
	coin.BorderSizePixel = 0
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = coin
	local stroke = Instance.new("UIStroke")
	stroke.Color           = Color3.fromRGB(172, 125, 10)
	stroke.Thickness       = math.max(1, math.floor(size * 0.1))
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent          = coin
	local hl = Instance.new("Frame")
	hl.Size                  = UDim2.new(0, math.max(2, math.floor(size * 0.28)), 0, math.max(2, math.floor(size * 0.28)))
	hl.Position              = UDim2.new(0, math.floor(size * 0.22), 0, math.floor(size * 0.16))
	hl.BackgroundColor3      = Color3.fromRGB(255, 245, 185)
	hl.BackgroundTransparency = 0.3
	hl.BorderSizePixel       = 0
	local hlcr = Instance.new("UICorner")
	hlcr.CornerRadius = UDim.new(0.5, 0)
	hlcr.Parent = hl
	hl.Parent = coin
	coin.Parent = parentFrame
	return coin
end

--------------------------------------------------------------------------------
-- Upgrade icon (colored circle with emoji-style glyph, matches BoostsUI)
--------------------------------------------------------------------------------
local function makeUpgradeIcon(parent, upgradeId, size)
	local frame = Instance.new("Frame")
	frame.Name = "UpgradeIcon"
	frame.Size = UDim2.new(0, size, 0, size)
	frame.BackgroundColor3 = ACCENT_COLORS[upgradeId] or Color3.fromRGB(80, 80, 90)
	frame.BorderSizePixel = 0
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0, px(14))
	cr.Parent = frame
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 255, 255)
	iconStroke.Thickness = 1.5
	iconStroke.Transparency = 0.7
	iconStroke.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = UPGRADE_GLYPHS[upgradeId] or "?"
	lbl.TextSize = math.max(18, math.floor(size * 0.52))
	lbl.TextColor3 = WHITE
	lbl.Parent = frame
	frame.Parent = parent
	return frame
end

--------------------------------------------------------------------------------
-- Level pips row
--------------------------------------------------------------------------------
local function createLevelPips(parent, currentLevel, maxLevel, pipSize)
	pipSize = pipSize or px(12)
	local pipsFrame = Instance.new("Frame")
	pipsFrame.Name = "LevelPips"
	pipsFrame.BackgroundTransparency = 1
	pipsFrame.Size = UDim2.new(0, (pipSize + px(4)) * maxLevel, 0, pipSize)
	pipsFrame.Parent = parent

	local pipsLayout = Instance.new("UIListLayout")
	pipsLayout.FillDirection = Enum.FillDirection.Horizontal
	pipsLayout.Padding = UDim.new(0, px(4))
	pipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipsLayout.Parent = pipsFrame

	local pips = {}
	for i = 1, maxLevel do
		local pip = Instance.new("Frame")
		pip.Name = "Pip_" .. i
		pip.Size = UDim2.new(0, pipSize, 0, pipSize)
		pip.BackgroundColor3 = (i <= currentLevel) and PIP_ACTIVE or PIP_INACTIVE
		pip.BorderSizePixel = 0
		pip.LayoutOrder = i
		pip.Parent = pipsFrame

		local pipCorner = Instance.new("UICorner")
		pipCorner.CornerRadius = UDim.new(0, px(3))
		pipCorner.Parent = pip

		pips[i] = pip
	end

	return pipsFrame, pips
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local UpgradesUI = {}

function UpgradesUI.Create(parent, _coinApi, _inventoryApi)
	if not parent then return nil end

	cleanupConnections()

	for _, c in ipairs(parent:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
			and not c:IsA("UIPadding") then
			pcall(function() c:Destroy() end)
		end
	end

	if not UpgradeConfig then
		local errLabel = Instance.new("TextLabel")
		errLabel.BackgroundTransparency = 1
		errLabel.Font      = Enum.Font.GothamMedium
		errLabel.Text      = "Upgrades unavailable \u{2013} config not found."
		errLabel.TextColor3 = DIM_TEXT
		errLabel.TextSize  = px(16)
		errLabel.Size      = UDim2.new(1, 0, 0, px(60))
		errLabel.Parent    = parent
		return nil
	end

	if not ensureRemotes() then
		local errLabel = Instance.new("TextLabel")
		errLabel.BackgroundTransparency = 1
		errLabel.Font      = Enum.Font.GothamMedium
		errLabel.Text      = "Upgrades unavailable \u{2013} remotes not found."
		errLabel.TextColor3 = DIM_TEXT
		errLabel.TextSize  = px(16)
		errLabel.Size      = UDim2.new(1, 0, 0, px(60))
		errLabel.Parent    = parent
		return nil
	end

	-- Fetch initial state from server
	local upgradeLevels = {}
	pcall(function()
		upgradeLevels = getStatesRF:InvokeServer()
	end)
	if type(upgradeLevels) ~= "table" then upgradeLevels = {} end

	---------------------------------------------------------------------------
	-- Root container
	---------------------------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name = "UpgradesRoot"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.LayoutOrder = 1
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

	---------------------------------------------------------------------------
	-- Header
	---------------------------------------------------------------------------
	local headerWrap = Instance.new("Frame")
	headerWrap.Name = "HeaderWrap"
	headerWrap.BackgroundTransparency = 1
	headerWrap.Size = UDim2.new(1, 0, 0, px(54))
	headerWrap.LayoutOrder = 1
	headerWrap.Parent = root

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.Text = "\u{2B50} UPGRADES"
	header.TextColor3 = GOLD
	header.TextSize = math.max(20, math.floor(px(24)))
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Size = UDim2.new(1, 0, 0, px(30))
	header.Position = UDim2.new(0, 0, 0, 0)
	header.Parent = headerWrap

	local subHeader = Instance.new("TextLabel")
	subHeader.Name = "SubHeader"
	subHeader.BackgroundTransparency = 1
	subHeader.Font = Enum.Font.GothamMedium
	subHeader.Text = "Spend coins on permanent account improvements."
	subHeader.TextColor3 = DIM_TEXT
	subHeader.TextSize = math.max(11, math.floor(px(12)))
	subHeader.TextXAlignment = Enum.TextXAlignment.Left
	subHeader.Size = UDim2.new(1, 0, 0, px(16))
	subHeader.Position = UDim2.new(0, 0, 0, px(30))
	subHeader.Parent = headerWrap

	-- Gold accent bar under header
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = GOLD
	accentBar.BackgroundTransparency = 0.3
	accentBar.Size = UDim2.new(1, 0, 0, px(2))
	accentBar.Position = UDim2.new(0, 0, 1, -px(2))
	accentBar.BorderSizePixel = 0
	accentBar.Parent = headerWrap

	---------------------------------------------------------------------------
	-- Upgrade cards
	---------------------------------------------------------------------------
	local cardButtons  = {}  -- [upgradeId] = TextButton
	local cardLevels   = {}  -- [upgradeId] = { levelLabel, pips, nextEffectLabel, priceLabel, card }
	local cardBorders  = {}  -- [upgradeId] = UIStroke

	-- Sort upgrades by SortOrder
	local sortedUpgrades = {}
	for _, def in ipairs(UpgradeConfig.Upgrades) do
		table.insert(sortedUpgrades, def)
	end
	table.sort(sortedUpgrades, function(a, b) return a.SortOrder < b.SortOrder end)

	for i, def in ipairs(sortedUpgrades) do
		local currentLevel = upgradeLevels[def.Id] or 0
		local isMaxed = currentLevel >= def.MaxLevel

		local CARD_H = px(140)

		local card = Instance.new("Frame")
		card.Name = "Upgrade_" .. def.Id
		card.BackgroundColor3 = CARD_BG
		card.Size = UDim2.new(1, 0, 0, CARD_H)
		card.LayoutOrder = 10 + i
		card.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, px(12))
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = isMaxed and MAXED_COLOR or CARD_STROKE
		stroke.Thickness = isMaxed and 2.5 or 1.2
		stroke.Transparency = isMaxed and 0.1 or 0.35
		stroke.Parent = card
		cardBorders[def.Id] = stroke

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft   = UDim.new(0, px(14))
		pad.PaddingRight  = UDim.new(0, px(14))
		pad.PaddingTop    = UDim.new(0, px(12))
		pad.PaddingBottom = UDim.new(0, px(12))
		pad.Parent = card

		-- Subtle accent glow behind icon area
		local iconSize = px(60)
		local iconGlow = Instance.new("Frame")
		iconGlow.Name = "IconGlow"
		iconGlow.Size = UDim2.new(0, iconSize + px(10), 0, iconSize + px(10))
		iconGlow.AnchorPoint = Vector2.new(0, 0.5)
		iconGlow.Position = UDim2.new(0, -px(5), 0.45, 0)
		iconGlow.BackgroundColor3 = ACCENT_COLORS[def.Id] or CARD_STROKE
		iconGlow.BackgroundTransparency = 0.82
		iconGlow.BorderSizePixel = 0
		local glowCr = Instance.new("UICorner")
		glowCr.CornerRadius = UDim.new(0, px(18))
		glowCr.Parent = iconGlow
		iconGlow.Parent = card

		-- Left: icon
		local iconFrame = makeUpgradeIcon(card, def.Id, iconSize)
		iconFrame.Position = UDim2.new(0, 0, 0.45, 0)
		iconFrame.AnchorPoint = Vector2.new(0, 0.5)

		-- Middle-top: name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = def.DisplayName
		nameLabel.TextColor3 = WHITE
		nameLabel.TextSize = math.max(15, math.floor(px(17)))
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Size = UDim2.new(0.50, 0, 0, px(22))
		nameLabel.Position = UDim2.new(0, iconSize + px(14), 0, 0)
		nameLabel.Parent = card

		-- Middle: description
		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "Desc"
		descLabel.BackgroundTransparency = 1
		descLabel.Font = Enum.Font.GothamMedium
		descLabel.Text = def.Description
		descLabel.TextColor3 = DIM_TEXT
		descLabel.TextSize = math.max(11, math.floor(px(12)))
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextWrapped = true
		descLabel.Size = UDim2.new(0.50, 0, 0, px(20))
		descLabel.Position = UDim2.new(0, iconSize + px(14), 0, px(22))
		descLabel.Parent = card

		-- Level display: "Level X / Y"
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelLabel"
		levelLabel.BackgroundTransparency = 1
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.RichText = true
		levelLabel.TextColor3 = isMaxed and MAXED_COLOR or GOLD
		levelLabel.TextSize = math.max(12, math.floor(px(13)))
		levelLabel.TextXAlignment = Enum.TextXAlignment.Left
		levelLabel.Size = UDim2.new(0.50, 0, 0, px(16))
		levelLabel.Position = UDim2.new(0, iconSize + px(14), 0, px(46))
		levelLabel.Parent = card
		if isMaxed then
			levelLabel.Text = '<font color="#32E66E">Level ' .. currentLevel .. " / " .. def.MaxLevel .. '  \u{2714} MAXED</font>'
		else
			levelLabel.Text = "Level " .. currentLevel .. " / " .. def.MaxLevel
		end

		-- Level pips
		local pipsFrame, pips = createLevelPips(card, currentLevel, def.MaxLevel, px(10))
		pipsFrame.Position = UDim2.new(0, iconSize + px(14), 0, px(64))
		pipsFrame.AnchorPoint = Vector2.new(0, 0)

		-- Next effect text
		local nextEffectLabel = Instance.new("TextLabel")
		nextEffectLabel.Name = "NextEffect"
		nextEffectLabel.BackgroundTransparency = 1
		nextEffectLabel.Font = Enum.Font.GothamMedium
		nextEffectLabel.RichText = true
		nextEffectLabel.TextColor3 = DIM_TEXT
		nextEffectLabel.TextSize = math.max(10, math.floor(px(11)))
		nextEffectLabel.TextXAlignment = Enum.TextXAlignment.Left
		nextEffectLabel.Size = UDim2.new(0.50, 0, 0, px(14))
		nextEffectLabel.Position = UDim2.new(0, iconSize + px(14), 0, px(80))
		nextEffectLabel.Parent = card
		if isMaxed then
			nextEffectLabel.Text = '<font color="#9096af">Fully upgraded!</font>'
		else
			local nextText = UpgradeConfig.GetNextLevelText(def.Id, currentLevel)
			nextEffectLabel.Text = '<font color="#9096af">Next: </font><font color="#FFD73C">' .. nextText .. '</font>'
		end

		-- Right side: price row + button
		-- Price row
		local priceRow = Instance.new("Frame")
		priceRow.Name = "PriceRow"
		priceRow.BackgroundTransparency = 1
		priceRow.Size = UDim2.new(0.28, 0, 0, px(22))
		priceRow.AnchorPoint = Vector2.new(1, 0)
		priceRow.Position = UDim2.new(1, 0, 0, 0)
		priceRow.Parent = card

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "Price"
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextScaled = true
		priceLabel.TextColor3 = GOLD
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceLabel.Size = UDim2.new(0.60, 0, 1, 0)
		priceLabel.Parent = priceRow

		if isMaxed then
			priceLabel.Text = "---"
			priceLabel.TextColor3 = DIM_TEXT
		else
			local nextPrice = UpgradeConfig.GetPrice(def.Id, currentLevel)
			priceLabel.Text = tostring(nextPrice or "?")
		end

		local coinIconSize = px(18)
		local cIcon = makeCoinIcon(priceRow, coinIconSize)
		cIcon.AnchorPoint = Vector2.new(0, 0.5)
		cIcon.Position = UDim2.new(0.66, 0, 0.5, 0)
		if isMaxed then cIcon.Visible = false end

		-- Action button
		local btn = Instance.new("TextButton")
		btn.Name = "ActionBtn"
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = math.max(13, math.floor(px(14)))
		btn.TextColor3 = WHITE
		btn.Size = UDim2.new(0.28, 0, 0, px(36))
		btn.AnchorPoint = Vector2.new(1, 0)
		btn.Position = UDim2.new(1, 0, 0, px(28))
		btn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, px(10))
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = BTN_STROKE_C
		btnStroke.Thickness = 1.4
		btnStroke.Transparency = 0.25
		btnStroke.Parent = btn

		cardButtons[def.Id] = btn

		-- Status label below button (shows current total effect)
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "Status"
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.TextSize = math.max(10, math.floor(px(11)))
		statusLabel.TextColor3 = DIM_TEXT
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.TextWrapped = true
		statusLabel.Size = UDim2.new(0.28, 0, 0, px(30))
		statusLabel.AnchorPoint = Vector2.new(1, 0)
		statusLabel.Position = UDim2.new(1, 0, 0, px(67))
		statusLabel.Parent = card

		-- Show current total effect
		local function getTotalEffectText(level)
			if level <= 0 then return "No bonus" end
			local totalPct = math.floor(def.EffectPerLevel * level * 100 + 0.5)
			local effectType = def.EffectType
			if effectType == UpgradeConfig.EffectType.CoinMultiplier then
				return "+" .. totalPct .. "% coins"
			elseif effectType == UpgradeConfig.EffectType.QuestProgress then
				return "+" .. totalPct .. "% quest"
			elseif effectType == UpgradeConfig.EffectType.RespawnReduction then
				return "-" .. totalPct .. "% respawn"
			elseif effectType == UpgradeConfig.EffectType.ObjectiveCoinBonus then
				return "+" .. totalPct .. "% obj coins"
			end
			return "+" .. totalPct .. "%"
		end

		statusLabel.Text = getTotalEffectText(currentLevel)

		-- Store UI refs for updates
		cardLevels[def.Id] = {
			levelLabel      = levelLabel,
			pips            = pips,
			nextEffectLabel = nextEffectLabel,
			priceLabel      = priceLabel,
			statusLabel     = statusLabel,
			card            = card,
			coinIcon        = cIcon,
			priceRow        = priceRow,
			getTotalEffectText = getTotalEffectText,
		}

		---------------------------------------------------------------------------
		-- Update card state
		---------------------------------------------------------------------------
		local function updateCardState(level)
			local maxed = level >= def.MaxLevel

			-- level label
			if maxed then
				levelLabel.Text = '<font color="#32E66E">Level ' .. level .. " / " .. def.MaxLevel .. '  \u{2714} MAXED</font>'
				levelLabel.TextColor3 = MAXED_COLOR
			else
				levelLabel.Text = "Level " .. level .. " / " .. def.MaxLevel
				levelLabel.TextColor3 = GOLD
			end

			-- pips
			for idx, pip in ipairs(pips) do
				pip.BackgroundColor3 = (idx <= level) and PIP_ACTIVE or PIP_INACTIVE
			end

			-- next effect
			if maxed then
				nextEffectLabel.Text = '<font color="#9096af">Fully upgraded!</font>'
			else
				local nextText = UpgradeConfig.GetNextLevelText(def.Id, level)
				nextEffectLabel.Text = '<font color="#9096af">Next: </font><font color="#FFD73C">' .. nextText .. '</font>'
			end

			-- price
			if maxed then
				priceLabel.Text = "---"
				priceLabel.TextColor3 = DIM_TEXT
				cIcon.Visible = false
			else
				local nextPrice = UpgradeConfig.GetPrice(def.Id, level)
				priceLabel.Text = tostring(nextPrice or "?")
				priceLabel.TextColor3 = GOLD
				cIcon.Visible = true
			end

			-- button
			if maxed then
				btn.Text = "MAXED"
				btn.BackgroundColor3 = DISABLED_BG
				btn.Active = false
				btn.TextColor3 = MAXED_COLOR
			else
				btn.Text = "UPGRADE"
				btn.BackgroundColor3 = BTN_BG
				btn.Active = true
				btn.TextColor3 = WHITE
			end

			-- border
			if maxed then
				stroke.Color = MAXED_COLOR
				stroke.Thickness = 2.5
				stroke.Transparency = 0.1
			else
				stroke.Color = CARD_STROKE
				stroke.Thickness = 1.2
				stroke.Transparency = 0.35
			end

			-- status
			statusLabel.Text = getTotalEffectText(level)
		end

		-- Initial state
		updateCardState(currentLevel)

		-- Hover feedback
		trackConn(btn.MouseEnter:Connect(function()
			if btn.Active then
				TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
			end
		end))
		trackConn(btn.MouseLeave:Connect(function()
			if btn.Active then
				TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
			end
		end))

		-- Click handler
		trackConn(btn.MouseButton1Click:Connect(function()
			if not btn.Active then return end

			btn.Active = false
			btn.Text = "..."

			local success, msg = false, "Error"
			pcall(function()
				success, msg = purchaseRF:InvokeServer(def.Id)
			end)

			if success then
				currentLevel = currentLevel + 1
				upgradeLevels[def.Id] = currentLevel
				updateCardState(currentLevel)

				showToast(root, def.DisplayName .. " upgraded to Level " .. currentLevel .. "!", GREEN_BTN, 2.5)

				-- Success flash animation on the card
				local origBg = card.BackgroundColor3
				TweenService:Create(card, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(30, 60, 40)}):Play()
				task.delay(0.15, function()
					if card and card.Parent then
						TweenService:Create(card, TweenInfo.new(0.3), {BackgroundColor3 = CARD_BG}):Play()
					end
				end)

				-- Refresh header coins
				pcall(function()
					if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
				end)
			else
				local toastMsg = msg or "Purchase failed"
				local toastColor = RED_TEXT
				if tostring(msg):find("Insufficient") then
					toastMsg = "Not enough coins!"
				elseif tostring(msg):find("maxed") or tostring(msg):find("Maxed") then
					toastMsg = "Already at max level!"
				end
				showToast(root, toastMsg, toastColor, 2.5)

				-- Restore button
				if currentLevel < def.MaxLevel then
					btn.Text = "UPGRADE"
					btn.BackgroundColor3 = BTN_BG
					btn.Active = true
				else
					btn.Text = "MAXED"
					btn.BackgroundColor3 = DISABLED_BG
					btn.Active = false
				end
			end
		end))
	end

	---------------------------------------------------------------------------
	-- Listen for server push updates
	---------------------------------------------------------------------------
	if stateUpdatedRE then
		trackConn(stateUpdatedRE.OnClientEvent:Connect(function(levels)
			if type(levels) ~= "table" then return end
			upgradeLevels = levels

			for _, def in ipairs(UpgradeConfig.Upgrades) do
				local level = levels[def.Id] or 0
				local refs = cardLevels[def.Id]
				if refs then
					local maxed = level >= def.MaxLevel
					local btn2 = cardButtons[def.Id]
					local border = cardBorders[def.Id]

					-- level label
					if maxed then
						refs.levelLabel.Text = '<font color="#32E66E">Level ' .. level .. " / " .. def.MaxLevel .. '  \u{2714} MAXED</font>'
						refs.levelLabel.TextColor3 = MAXED_COLOR
					else
						refs.levelLabel.Text = "Level " .. level .. " / " .. def.MaxLevel
						refs.levelLabel.TextColor3 = GOLD
					end

					-- pips
					if refs.pips then
						for idx, pip in ipairs(refs.pips) do
							pip.BackgroundColor3 = (idx <= level) and PIP_ACTIVE or PIP_INACTIVE
						end
					end

					-- next effect
					if maxed then
						refs.nextEffectLabel.Text = '<font color="#9096af">Fully upgraded!</font>'
					else
						local nextText = UpgradeConfig.GetNextLevelText(def.Id, level)
						refs.nextEffectLabel.Text = '<font color="#9096af">Next: </font><font color="#FFD73C">' .. nextText .. '</font>'
					end

					-- price
					if maxed then
						refs.priceLabel.Text = "---"
						refs.priceLabel.TextColor3 = DIM_TEXT
						if refs.coinIcon then refs.coinIcon.Visible = false end
					else
						local nextPrice = UpgradeConfig.GetPrice(def.Id, level)
						refs.priceLabel.Text = tostring(nextPrice or "?")
						refs.priceLabel.TextColor3 = GOLD
						if refs.coinIcon then refs.coinIcon.Visible = true end
					end

					-- button
					if btn2 then
						if maxed then
							btn2.Text = "MAXED"
							btn2.BackgroundColor3 = DISABLED_BG
							btn2.Active = false
							btn2.TextColor3 = MAXED_COLOR
						else
							btn2.Text = "UPGRADE"
							btn2.BackgroundColor3 = BTN_BG
							btn2.Active = true
							btn2.TextColor3 = WHITE
						end
					end

					-- border
					if border then
						if maxed then
							border.Color = MAXED_COLOR
							border.Thickness = 2.5
							border.Transparency = 0.1
						else
							border.Color = CARD_STROKE
							border.Thickness = 1.2
							border.Transparency = 0.35
						end
					end

					-- status
					if refs.statusLabel and refs.getTotalEffectText then
						refs.statusLabel.Text = refs.getTotalEffectText(level)
					end
				end
			end
		end))
	end

	return root
end

return UpgradesUI
