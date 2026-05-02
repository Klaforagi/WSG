--------------------------------------------------------------------------------
-- UpgradesUI.lua  –  Weapon Upgrade menu (2 cards: Melee + Ranged)
-- Place in ReplicatedStorage > SideUI alongside BoostsUI / ShopUI etc.
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Redesigned: two large side-by-side weapon upgrade cards with infinite
-- levelling, auto-scaling cost, and live refresh after purchase.
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
-- Palette (from shared UITheme)
--------------------------------------------------------------------------------
local CARD_BG       = UITheme.CARD_BG
local CARD_STROKE   = UITheme.CARD_STROKE
local GOLD          = UITheme.GOLD
local GOLD_DIM      = UITheme.GOLD_DIM
local WHITE         = UITheme.WHITE
local DIM_TEXT      = UITheme.DIM_TEXT
local BTN_BG        = UITheme.BTN_BG
local BTN_STROKE_C  = UITheme.BTN_STROKE
local GREEN_BTN     = UITheme.GREEN_BTN
local RED_TEXT       = UITheme.RED_TEXT

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
-- Scrap icon widget (mirrors coin look but with steel/grey palette).
--------------------------------------------------------------------------------
local function makeScrapIcon(parentFrame, size)
	local scrap = Instance.new("Frame")
	scrap.Name            = "ScrapIcon"
	scrap.Size            = UDim2.new(0, size, 0, size)
	scrap.BackgroundColor3 = Color3.fromRGB(170, 178, 190)
	scrap.BorderSizePixel = 0
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0, math.max(1, math.floor(size * 0.18)))
	cr.Parent = scrap
	local stroke = Instance.new("UIStroke")
	stroke.Color           = Color3.fromRGB(80, 88, 98)
	stroke.Thickness       = math.max(1, math.floor(size * 0.10))
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent          = scrap
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Text = "S"
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextColor3 = Color3.fromRGB(35, 40, 48)
	lbl.TextScaled = true
	lbl.Parent = scrap
	scrap.Parent = parentFrame
	return scrap
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local UpgradesUI = {}

function UpgradesUI.Create(parent, _coinApi, _inventoryApi)
	if not parent then return nil end

	cleanupConnections()
	print("[UpgradesUI] Opening upgrades menu")

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

	-- Extract player level from server response (or fall back to attribute)
	local playerLevel = upgradeLevels._playerLevel
		or player:GetAttribute("Level")
		or 1
	upgradeLevels._playerLevel = nil  -- strip metadata before iterating as upgrade ids

	---------------------------------------------------------------------------
	-- Root container
	---------------------------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name = "UpgradesRoot"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 1, 0)
	root.LayoutOrder = 1
	root.Parent = parent

	local rootPad = Instance.new("UIPadding")
	rootPad.PaddingTop    = UDim.new(0, px(8))
	rootPad.PaddingBottom = UDim.new(0, px(16))
	rootPad.PaddingLeft   = UDim.new(0, px(12))
	rootPad.PaddingRight  = UDim.new(0, px(12))
	rootPad.Parent = root

	---------------------------------------------------------------------------
	-- Header
	---------------------------------------------------------------------------
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
	header.Parent = root

	local subHeader = Instance.new("TextLabel")
	subHeader.Name = "SubHeader"
	subHeader.BackgroundTransparency = 1
	subHeader.Font = Enum.Font.GothamMedium
	subHeader.Text = "Upgrade your weapons for permanent power increases."
	subHeader.TextColor3 = DIM_TEXT
	subHeader.TextSize = math.max(11, math.floor(px(12)))
	subHeader.TextXAlignment = Enum.TextXAlignment.Left
	subHeader.Size = UDim2.new(1, 0, 0, px(16))
	subHeader.Position = UDim2.new(0, 0, 0, px(32))
	subHeader.Parent = root

	-- Gold accent bar under header
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = GOLD
	accentBar.BackgroundTransparency = 0.3
	accentBar.Size = UDim2.new(1, 0, 0, px(2))
	accentBar.Position = UDim2.new(0, 0, 0, px(54))
	accentBar.BorderSizePixel = 0
	accentBar.Parent = root

	---------------------------------------------------------------------------
	-- Cards container (side by side)
	---------------------------------------------------------------------------
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "CardsFrame"
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Size = UDim2.new(1, 0, 1, -px(66))
	cardsFrame.Position = UDim2.new(0, 0, 0, px(66))
	cardsFrame.Parent = root

	-- Table to hold both card update functions
	local cardUpdaters = {}

	-- The two upgrade definitions: left=melee, right=ranged
	local CARD_DEFS = {
		{ id = UpgradeConfig.MELEE,  layoutOrder = 1 },
		{ id = UpgradeConfig.RANGED, layoutOrder = 2 },
	}

	local GAP = px(16)
	local cardWidth = UDim2.new(0.5, -GAP / 2, 1, -px(16))

	for idx, cardDef in ipairs(CARD_DEFS) do
		local upgradeId = cardDef.id
		local display = UpgradeConfig.Display[upgradeId]
		local currentLevel = upgradeLevels[upgradeId] or 0

		print(("[UpgradesUI] Rendering card '%s' at level %d"):format(upgradeId, currentLevel))

		-- Card frame
		local card = Instance.new("Frame")
		card.Name = "Card_" .. upgradeId
		card.BackgroundColor3 = CARD_BG
		card.Size = cardWidth
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.Position = UDim2.new((idx - 1) * 0.5, (idx == 2) and (GAP / 2) or 0, 0.5, 0)
		card.Parent = cardsFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, px(14))
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD_DIM
		stroke.Thickness = 1.5
		stroke.Transparency = 0.3
		stroke.Parent = card

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft   = UDim.new(0, px(16))
		pad.PaddingRight  = UDim.new(0, px(16))
		pad.PaddingTop    = UDim.new(0, px(18))
		pad.PaddingBottom = UDim.new(0, px(16))
		pad.Parent = card

		-----------------------------------------------------------------------
		-- Weapon Showcase (hero image area — upper portion of card)
		-----------------------------------------------------------------------
		local showcaseFrame = Instance.new("Frame")
		showcaseFrame.Name = "WeaponShowcase"
		showcaseFrame.Size = UDim2.new(1, 0, 0.52, 0)
		showcaseFrame.Position = UDim2.new(0, 0, 0, 0)
		showcaseFrame.BackgroundTransparency = 1
		showcaseFrame.ClipsDescendants = false
		showcaseFrame.Parent = card

		-- Outer glow (soft, large radial)
		local glowOuterSize = px(200)
		local glowOuter = Instance.new("Frame")
		glowOuter.Name = "GlowOuter"
		glowOuter.Size = UDim2.new(0, glowOuterSize, 0, glowOuterSize)
		glowOuter.AnchorPoint = Vector2.new(0.5, 0.5)
		glowOuter.Position = UDim2.new(0.5, 0, 0.5, 0)
		glowOuter.BackgroundColor3 = display.Accent
		glowOuter.BackgroundTransparency = 0.88
		glowOuter.BorderSizePixel = 0
		glowOuter.ZIndex = 1
		glowOuter.Parent = showcaseFrame

		local goCr = Instance.new("UICorner")
		goCr.CornerRadius = UDim.new(0.5, 0)
		goCr.Parent = glowOuter

		-- Mid glow (medium intensity)
		local glowMidSize = px(140)
		local glowMid = Instance.new("Frame")
		glowMid.Name = "GlowMid"
		glowMid.Size = UDim2.new(0, glowMidSize, 0, glowMidSize)
		glowMid.AnchorPoint = Vector2.new(0.5, 0.5)
		glowMid.Position = UDim2.new(0.5, 0, 0.5, 0)
		glowMid.BackgroundColor3 = display.Accent
		glowMid.BackgroundTransparency = 0.78
		glowMid.BorderSizePixel = 0
		glowMid.ZIndex = 2
		glowMid.Parent = showcaseFrame

		local gmCr = Instance.new("UICorner")
		gmCr.CornerRadius = UDim.new(0.5, 0)
		gmCr.Parent = glowMid

		-- Inner glow (bright core)
		local glowInnerSize = px(90)
		local glowInner = Instance.new("Frame")
		glowInner.Name = "GlowInner"
		glowInner.Size = UDim2.new(0, glowInnerSize, 0, glowInnerSize)
		glowInner.AnchorPoint = Vector2.new(0.5, 0.5)
		glowInner.Position = UDim2.new(0.5, 0, 0.5, 0)
		glowInner.BackgroundColor3 = display.Accent
		glowInner.BackgroundTransparency = 0.65
		glowInner.BorderSizePixel = 0
		glowInner.ZIndex = 3
		glowInner.Parent = showcaseFrame

		local giCr = Instance.new("UICorner")
		giCr.CornerRadius = UDim.new(0.5, 0)
		giCr.Parent = glowInner

		-- Weapon image or fallback large glyph
		local weaponRotation = display.ImageRotation or -12

		if display.ImageId and display.ImageId ~= "" then
			-- Custom weapon art (ImageLabel)
			local artSize = px(160)

			-- Drop shadow
			local shadow = Instance.new("ImageLabel")
			shadow.Name = "WeaponShadow"
			shadow.Size = UDim2.new(0, artSize, 0, artSize)
			shadow.AnchorPoint = Vector2.new(0.5, 0.5)
			shadow.Position = UDim2.new(0.5, px(4), 0.5, px(4))
			shadow.BackgroundTransparency = 1
			shadow.Image = display.ImageId
			shadow.ImageTransparency = 0.7
			shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
			shadow.ScaleType = Enum.ScaleType.Fit
			shadow.Rotation = weaponRotation
			shadow.ZIndex = 4
			shadow.Parent = showcaseFrame

			-- Main weapon image
			local weaponImg = Instance.new("ImageLabel")
			weaponImg.Name = "WeaponArt"
			weaponImg.Size = UDim2.new(0, artSize, 0, artSize)
			weaponImg.AnchorPoint = Vector2.new(0.5, 0.5)
			weaponImg.Position = UDim2.new(0.5, 0, 0.5, 0)
			weaponImg.BackgroundTransparency = 1
			weaponImg.Image = display.ImageId
			weaponImg.ScaleType = Enum.ScaleType.Fit
			weaponImg.Rotation = weaponRotation
			weaponImg.ZIndex = 6
			weaponImg.Parent = showcaseFrame
		else
			-- Fallback: oversized glyph with shadow for depth
			local glyphSize = math.max(70, math.floor(px(100)))

			-- Glyph shadow
			local glyphShadow = Instance.new("TextLabel")
			glyphShadow.Name = "GlyphShadow"
			glyphShadow.BackgroundTransparency = 1
			glyphShadow.Size = UDim2.new(1, 0, 1, 0)
			glyphShadow.AnchorPoint = Vector2.new(0.5, 0.5)
			glyphShadow.Position = UDim2.new(0.5, px(3), 0.5, px(3))
			glyphShadow.Font = Enum.Font.GothamBold
			glyphShadow.Text = display.Glyph
			glyphShadow.TextSize = glyphSize
			glyphShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
			glyphShadow.TextTransparency = 0.55
			glyphShadow.Rotation = weaponRotation
			glyphShadow.ZIndex = 4
			glyphShadow.Parent = showcaseFrame

			-- Main glyph
			local bigGlyph = Instance.new("TextLabel")
			bigGlyph.Name = "BigGlyph"
			bigGlyph.BackgroundTransparency = 1
			bigGlyph.Size = UDim2.new(1, 0, 1, 0)
			bigGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
			bigGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
			bigGlyph.Font = Enum.Font.GothamBold
			bigGlyph.Text = display.Glyph
			bigGlyph.TextSize = glyphSize
			bigGlyph.TextColor3 = WHITE
			bigGlyph.Rotation = weaponRotation
			bigGlyph.ZIndex = 6
			bigGlyph.Parent = showcaseFrame
		end

		-- Bottom fade (blends showcase into card background)
		local fade = Instance.new("Frame")
		fade.Name = "BottomFade"
		fade.Size = UDim2.new(1, px(32), 0, px(30))
		fade.AnchorPoint = Vector2.new(0.5, 1)
		fade.Position = UDim2.new(0.5, 0, 1, 0)
		fade.BackgroundColor3 = CARD_BG
		fade.BorderSizePixel = 0
		fade.ZIndex = 8
		fade.Parent = showcaseFrame

		local fadeGrad = Instance.new("UIGradient")
		fadeGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		fadeGrad.Rotation = 90
		fadeGrad.Parent = fade

		-- Accent line separating showcase from info
		local accentLine = Instance.new("Frame")
		accentLine.Name = "AccentLine"
		accentLine.Size = UDim2.new(0.6, 0, 0, px(2))
		accentLine.AnchorPoint = Vector2.new(0.5, 0)
		accentLine.Position = UDim2.new(0.5, 0, 0.53, px(2))
		accentLine.BackgroundColor3 = display.Accent
		accentLine.BackgroundTransparency = 0.5
		accentLine.BorderSizePixel = 0
		accentLine.ZIndex = 10
		accentLine.Parent = card

		-----------------------------------------------------------------------
		-- Info section (below showcase, above button)
		-- Uses scale Y (0.55) + pixel offsets for compact stacking
		-----------------------------------------------------------------------
		local infoY = 0.55

		-- Title
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.Text = display.Title
		title.TextColor3 = GOLD
		title.TextSize = math.max(18, math.floor(px(22)))
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.Size = UDim2.new(1, 0, 0, px(24))
		title.Position = UDim2.new(0, 0, infoY, px(4))
		title.ZIndex = 10
		title.Parent = card

		-- Description
		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.GothamMedium
		desc.Text = display.Description
		desc.TextColor3 = DIM_TEXT
		desc.TextSize = math.max(11, math.floor(px(12)))
		desc.TextXAlignment = Enum.TextXAlignment.Center
		desc.TextWrapped = true
		desc.Size = UDim2.new(1, 0, 0, px(16))
		desc.Position = UDim2.new(0, 0, infoY, px(32))
		desc.ZIndex = 10
		desc.Parent = card

		-- Level display
		local levelLabel = Instance.new("TextLabel")
		levelLabel.Name = "LevelLabel"
		levelLabel.BackgroundTransparency = 1
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.TextColor3 = WHITE
		levelLabel.TextSize = math.max(14, math.floor(px(16)))
		levelLabel.TextXAlignment = Enum.TextXAlignment.Center
		levelLabel.Size = UDim2.new(1, 0, 0, px(18))
		levelLabel.Position = UDim2.new(0, 0, infoY, px(60))
		levelLabel.Text = "Weapon Level: " .. currentLevel
		levelLabel.ZIndex = 10
		levelLabel.Parent = card

		-- Bonus display
		local bonusLabel = Instance.new("TextLabel")
		bonusLabel.Name = "BonusLabel"
		bonusLabel.BackgroundTransparency = 1
		bonusLabel.Font = Enum.Font.GothamMedium
		bonusLabel.TextColor3 = GOLD
		bonusLabel.TextSize = math.max(12, math.floor(px(14)))
		bonusLabel.TextXAlignment = Enum.TextXAlignment.Center
		bonusLabel.Size = UDim2.new(1, 0, 0, px(16))
		bonusLabel.Position = UDim2.new(0, 0, infoY, px(88))
		bonusLabel.Text = (currentLevel == 0) and UpgradeConfig.GetBonusText(currentLevel, upgradeId) or ("Bonus: " .. UpgradeConfig.GetBonusText(currentLevel, upgradeId))
		bonusLabel.ZIndex = 10
		bonusLabel.Parent = card

		-----------------------------------------------------------------------
		-- UPGRADE button (anchored at bottom)
		-----------------------------------------------------------------------
		local btnH = px(46)
		local btn = Instance.new("TextButton")
		btn.Name = "UpgradeBtn"
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamBold
		btn.Text = "UPGRADE"
		btn.TextSize = math.max(15, math.floor(px(18)))
		btn.TextColor3 = WHITE
		btn.BackgroundColor3 = BTN_BG
		btn.Size = UDim2.new(1, 0, 0, btnH)
		btn.AnchorPoint = Vector2.new(0, 1)
		btn.Position = UDim2.new(0, 0, 1, 0)
		btn.ZIndex = 10
		btn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, px(12))
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = BTN_STROKE_C
		btnStroke.Thickness = 1.5
		btnStroke.Transparency = 0.2
		btnStroke.Parent = btn

		-----------------------------------------------------------------------
		-- Next upgrade cost (positioned directly above the button)
		-----------------------------------------------------------------------
		local costContainer = Instance.new("Frame")
		costContainer.Name = "CostContainer"
		costContainer.BackgroundTransparency = 1
		costContainer.Size = UDim2.new(1, 0, 0, px(38))
		costContainer.AnchorPoint = Vector2.new(0, 1)
		costContainer.Position = UDim2.new(0, 0, 1, -(btnH + px(8)))
		costContainer.ZIndex = 10
		costContainer.Parent = card

		-- "Next Upgrade:" header
		local costHeader = Instance.new("TextLabel")
		costHeader.Name = "CostHeader"
		costHeader.BackgroundTransparency = 1
		costHeader.Font = Enum.Font.GothamMedium
		costHeader.Text = "Next Upgrade (Scrap):"
		costHeader.TextColor3 = DIM_TEXT
		costHeader.TextSize = math.max(10, math.floor(px(11)))
		costHeader.TextXAlignment = Enum.TextXAlignment.Center
		costHeader.Size = UDim2.new(1, 0, 0, px(14))
		costHeader.Position = UDim2.new(0, 0, 0, 0)
		costHeader.ZIndex = 10
		costHeader.Parent = costContainer

		-- Price row (number + coin icon, centered)
		local nextCost = UpgradeConfig.GetCost(currentLevel)
		local costCoinSize = px(16)
		local priceRowH = px(20)

		local priceRow = Instance.new("Frame")
		priceRow.Name = "PriceRow"
		priceRow.BackgroundTransparency = 1
		priceRow.AnchorPoint = Vector2.new(0.5, 0)
		priceRow.Size = UDim2.new(0, px(80), 0, priceRowH)
		priceRow.Position = UDim2.new(0.5, 0, 0, px(15))
		priceRow.ZIndex = 10
		priceRow.Parent = costContainer

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextColor3 = GOLD
		priceLabel.TextSize = math.max(14, math.floor(px(16)))
		priceLabel.Text = tostring(nextCost)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Right
		priceLabel.Size = UDim2.new(0.5, -(costCoinSize / 2 + px(3)), 1, 0)
		priceLabel.Position = UDim2.new(0, 0, 0, 0)
		priceLabel.ZIndex = 10
		priceLabel.Parent = priceRow

		local costCoin = makeScrapIcon(priceRow, costCoinSize)
		costCoin.AnchorPoint = Vector2.new(0, 0.5)
		costCoin.Position = UDim2.new(0.5, (costCoinSize / 2 + px(1)), 0.5, 0)
		costCoin.ZIndex = 10

		-- Cap hint label (shown when upgrade is capped by player level)
		local capLabel = Instance.new("TextLabel")
		capLabel.Name = "CapLabel"
		capLabel.BackgroundTransparency = 1
		capLabel.Font = Enum.Font.GothamMedium
		capLabel.TextColor3 = DIM_TEXT
		capLabel.TextSize = math.max(10, math.floor(px(11)))
		capLabel.TextXAlignment = Enum.TextXAlignment.Center
		capLabel.TextWrapped = true
		capLabel.Size = UDim2.new(1, 0, 0, px(14))
		capLabel.AnchorPoint = Vector2.new(0, 1)
		capLabel.Position = UDim2.new(0, 0, 1, -(btnH + px(4)))
		capLabel.ZIndex = 10
		capLabel.Text = ""
		capLabel.Visible = false
		capLabel.Parent = card

		-----------------------------------------------------------------------
		-- Update function for this card (cap-aware)
		-----------------------------------------------------------------------
		local function updateCard(level, pLevel)
			if pLevel then playerLevel = pLevel end
			levelLabel.Text  = "Weapon Level: " .. level
			local bonusTxt = UpgradeConfig.GetBonusText(level, upgradeId)
			bonusLabel.Text  = (level == 0) and bonusTxt or ("Bonus: " .. bonusTxt)
			local cost       = UpgradeConfig.GetCost(level)

			-- Player-level cap is disabled by default (UpgradeConfig.REQUIRE_PLAYER_LEVEL).
			local capped = (UpgradeConfig.REQUIRE_PLAYER_LEVEL == true) and (level >= playerLevel) or false
			if capped then
				btn.Text = "MAXED"
				btn.Active = false
				btn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
				btnStroke.Color = DIM_TEXT
				costContainer.Visible = false
				capLabel.Text = "Reach player level " .. (level + 1) .. " to upgrade further"
				capLabel.Visible = true
			else
				btn.Text = "UPGRADE"
				btn.Active = true
				btn.BackgroundColor3 = BTN_BG
				btnStroke.Color = BTN_STROKE_C
				costContainer.Visible = true
				priceLabel.Text = tostring(cost)
				capLabel.Visible = false
			end
		end

		-- Run initial cap check
		updateCard(currentLevel, playerLevel)

		cardUpdaters[upgradeId] = { updateCard = updateCard, btn = btn, capLabel = capLabel, costContainer = costContainer }

		-----------------------------------------------------------------------
		-- Hover feedback
		-----------------------------------------------------------------------
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

		-----------------------------------------------------------------------
		-- Click handler (purchase)
		-----------------------------------------------------------------------
		trackConn(btn.MouseButton1Click:Connect(function()
			if not btn.Active then return end
			btn.Active = false
			btn.Text = "..."

			local success, msg = false, "Error"
			pcall(function()
				success, msg = purchaseRF:InvokeServer(upgradeId)
			end)

			if success then
				currentLevel = currentLevel + 1
				upgradeLevels[upgradeId] = currentLevel
				updateCard(currentLevel, playerLevel)

				showToast(root, display.Title .. " upgraded to Level " .. currentLevel .. "!", GREEN_BTN, 2.5)

				-- Success flash
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
					toastMsg = "Not enough scrap!"
				elseif tostring(msg):find("capped") then
					toastMsg = "Upgrade capped by player level!"
				end
				showToast(root, toastMsg, toastColor, 2.5)
			end

			-- Restore button state respecting current cap
			local isCapped = (currentLevel >= playerLevel)
			if isCapped then
				btn.Text = "MAXED"
				btn.Active = false
				btn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
			else
				btn.Text = "UPGRADE"
				btn.Active = true
				btn.BackgroundColor3 = BTN_BG
			end
		end))
	end

	---------------------------------------------------------------------------
	-- Listen for server push updates (live refresh)
	---------------------------------------------------------------------------
	if stateUpdatedRE then
		trackConn(stateUpdatedRE.OnClientEvent:Connect(function(levels)
			if type(levels) ~= "table" then return end

			-- Update player level from server payload
			if levels._playerLevel then
				playerLevel = levels._playerLevel
				levels._playerLevel = nil
			end
			upgradeLevels = levels

			for _, cardDef in ipairs(CARD_DEFS) do
				local id = cardDef.id
				local level = levels[id] or 0
				local refs = cardUpdaters[id]
				if refs then
					refs.updateCard(level, playerLevel)
				end
			end
		end))
	end

	---------------------------------------------------------------------------
	-- Listen for player level attribute changes (e.g. after leveling up)
	---------------------------------------------------------------------------
	trackConn(player:GetAttributeChangedSignal("Level"):Connect(function()
		local newLevel = player:GetAttribute("Level") or 1
		if newLevel ~= playerLevel then
			playerLevel = newLevel
			for _, cardDef in ipairs(CARD_DEFS) do
				local id = cardDef.id
				local level = upgradeLevels[id] or 0
				local refs = cardUpdaters[id]
				if refs then
					refs.updateCard(level, playerLevel)
				end
			end
		end
	end))

	return root
end

return UpgradesUI
