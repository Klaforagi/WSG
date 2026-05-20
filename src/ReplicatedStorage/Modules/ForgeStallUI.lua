--------------------------------------------------------------------------------
-- ForgeStallUI.lua
-- Standalone world-station forge screen.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function px(base)
	local cam = Workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

local function safeRequire(parent, moduleName, timeout)
	timeout = timeout or 5
	local mod = parent:WaitForChild(moduleName, timeout)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			return result
		end
		warn("[ForgeStallUI] Failed to require", moduleName, ":", tostring(result))
	end
	return nil
end

local UpgradeConfig = safeRequire(ReplicatedStorage, "UpgradeConfig", 10)
local AssetCodes = safeRequire(ReplicatedStorage, "AssetCodes", 5)
local ShardProducts = safeRequire(ReplicatedStorage, "ShardProducts", 5)

local PANEL_BG = Color3.fromRGB(8, 8, 9)
local PANEL_BG_LIGHT = Color3.fromRGB(13, 13, 15)
local CARD_BG = Color3.fromRGB(16, 16, 18)
local CARD_BG_HOVER = Color3.fromRGB(22, 22, 24)
local CARD_BG_ALT = Color3.fromRGB(20, 20, 22)
local ART_BG = Color3.fromRGB(21, 14, 8)
local ORANGE = Color3.fromRGB(255, 145, 20)
local ORANGE_SOFT = Color3.fromRGB(212, 111, 18)
local ORANGE_DARK = Color3.fromRGB(112, 52, 9)
local ORANGE_BRIGHT = Color3.fromRGB(255, 191, 72)
local WHITE = Color3.fromRGB(246, 246, 246)
local GRAY = Color3.fromRGB(166, 166, 166)
local DARK_GRAY = Color3.fromRGB(72, 72, 74)
local GREEN = Color3.fromRGB(123, 255, 72)
local GREEN_DARK = Color3.fromRGB(48, 97, 33)
local RED = Color3.fromRGB(194, 62, 46)
local TRACK_GRAY = Color3.fromRGB(44, 46, 48)
local BLACK = Color3.fromRGB(0, 0, 0)

local BUTTON_READY = Color3.fromRGB(126, 62, 12)
local BUTTON_READY_HOVER = Color3.fromRGB(149, 74, 14)
local BUTTON_LOCKED = Color3.fromRGB(71, 71, 74)
local BUTTON_MAX = Color3.fromRGB(84, 84, 86)

local QUICK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local remotesFolder
local upgradeFolder
local purchaseRF
local getStatesRF
local stateUpdatedRE
local getSalvageRF
local salvageUpdatedRE

local activeConnections = {}

local function trackConn(conn)
	table.insert(activeConnections, conn)
end

local function cleanupConnections()
	for _, conn in ipairs(activeConnections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	activeConnections = {}
end

local function ensureRemotes()
	if upgradeFolder then
		return true
	end

	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return false
	end

	upgradeFolder = remotesFolder:WaitForChild("Upgrades", 5)
	stateUpdatedRE = remotesFolder:WaitForChild("UpgradeStateUpdated", 5)
	if not upgradeFolder then
		return false
	end

	purchaseRF = upgradeFolder:WaitForChild("RequestPurchaseUpgrade", 5)
	getStatesRF = upgradeFolder:WaitForChild("GetUpgradeStates", 5)
	getSalvageRF = ReplicatedStorage:WaitForChild("GetSalvage", 5)
	salvageUpdatedRE = ReplicatedStorage:WaitForChild("SalvageUpdated", 5)

	return purchaseRF ~= nil and getStatesRF ~= nil and getSalvageRF ~= nil
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		pcall(function()
			child:Destroy()
		end)
	end
end

local function formatNumber(value)
	local n = math.floor(tonumber(value) or 0)
	local sign = ""
	if n < 0 then
		sign = "-"
		n = math.abs(n)
	end
	local text = tostring(n)
	while true do
		local replaced
		text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return sign .. text
end

local function trimTrailingZeroes(text)
	text = text:gsub("(%..-)0+$", "%1")
	text = text:gsub("%.$", "")
	return text
end

local function formatCompactNumber(value)
	local n = tonumber(value) or 0
	local absN = math.abs(n)
	if absN >= 1000000 then
		return trimTrailingZeroes(string.format("%.2fM", n / 1000000))
	end
	if absN >= 1000 then
		return trimTrailingZeroes(string.format("%.2fK", n / 1000))
	end
	return formatNumber(n)
end

local function getAsset(key)
	if AssetCodes and type(AssetCodes.Get) == "function" then
		local asset = AssetCodes.Get(key)
		if type(asset) == "string" and #asset > 0 then
			return asset
		end
	end
	return nil
end

local function getShardImage()
	return getAsset("Shards") or getAsset("Shard")
end

local function getRobuxImage()
	return getAsset("Robux")
end

local function getUpgradeArt(upgradeId)
	if not UpgradeConfig then
		return nil
	end
	if upgradeId == UpgradeConfig.MELEE then
		return getAsset("Melee")
	end
	if upgradeId == UpgradeConfig.RANGED then
		return getAsset("Ranged")
	end
	return nil
end

local function applyCorners(frame, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	return corner
end

local function applyStroke(frame, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = frame
	return stroke
end

local function makeCircleGlow(parent, size, position, color, transparency)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = position
	glow.Size = UDim2.new(0, size, 0, size)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = transparency
	glow.BorderSizePixel = 0
	glow.ZIndex = 0
	glow.Parent = parent
	applyCorners(glow, size)
	return glow
end

local function makeShardIcon(parent, size)
	local image = getShardImage()
	if image then
		local icon = Instance.new("ImageLabel")
		icon.Name = "ShardIcon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, size, 0, size)
		icon.Image = image
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = parent
		return icon
	end

	local fallback = Instance.new("Frame")
	fallback.BackgroundColor3 = ORANGE
	fallback.BorderSizePixel = 0
	fallback.Size = UDim2.new(0, size, 0, size)
	fallback.Rotation = 45
	fallback.Parent = parent
	applyCorners(fallback, math.max(4, math.floor(size * 0.18)))
	return fallback
end

local function makeRobuxIcon(parent, size)
	local image = getRobuxImage()
	if image then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, size, 0, size)
		icon.Image = image
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = parent
		return icon
	end

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, size + px(4), 0, size)
	label.Font = Enum.Font.GothamBlack
	label.Text = "R$"
	label.TextColor3 = ORANGE_BRIGHT
	label.TextSize = math.max(10, math.floor(size * 0.78))
	label.Parent = parent
	return label
end

local function createHealthEmblem(parent, size)
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.new(0, size, 0, size)
	wrapper.Parent = parent

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = UDim2.new(0.8, 0, 0.8, 0)
	badge.BackgroundColor3 = ART_BG
	badge.BorderSizePixel = 0
	badge.Rotation = 45
	badge.Parent = wrapper
	applyCorners(badge, px(10))
	applyStroke(badge, ORANGE, 2, 0.18)

	local plusV = Instance.new("Frame")
	plusV.AnchorPoint = Vector2.new(0.5, 0.5)
	plusV.Position = UDim2.fromScale(0.5, 0.5)
	plusV.Size = UDim2.new(0, math.max(8, math.floor(size * 0.14)), 0, math.max(28, math.floor(size * 0.5)))
	plusV.BackgroundColor3 = ORANGE
	plusV.BorderSizePixel = 0
	plusV.Parent = wrapper
	applyCorners(plusV, px(6))

	local plusH = Instance.new("Frame")
	plusH.AnchorPoint = Vector2.new(0.5, 0.5)
	plusH.Position = UDim2.fromScale(0.5, 0.5)
	plusH.Size = UDim2.new(0, math.max(28, math.floor(size * 0.5)), 0, math.max(8, math.floor(size * 0.14)))
	plusH.BackgroundColor3 = ORANGE
	plusH.BorderSizePixel = 0
	plusH.Parent = wrapper
	applyCorners(plusH, px(6))

	return wrapper
end

local function showToast(parent, message, color, duration)
	color = color or ORANGE_BRIGHT
	duration = duration or 2.5

	local toast = Instance.new("TextLabel")
	toast.Name = "ForgeToast"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, px(12))
	toast.Size = UDim2.new(0.52, 0, 0, px(34))
	toast.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	toast.BackgroundTransparency = 1
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamBold
	toast.Text = message
	toast.TextColor3 = color
	toast.TextTransparency = 1
	toast.TextSize = math.max(12, px(12))
	toast.ZIndex = 50
	toast.Parent = parent
	applyCorners(toast, px(10))
	applyStroke(toast, color, 1.2, 0.25)

	TweenService:Create(toast, TweenInfo.new(0.18), {
		BackgroundTransparency = 0.08,
		TextTransparency = 0,
	}):Play()

	task.delay(duration, function()
		if toast and toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.18), {
				BackgroundTransparency = 1,
				TextTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				pcall(function()
					toast:Destroy()
				end)
			end)
		end
	end)
end

local function createErrorLabel(parent, text)
	clearChildren(parent)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = RED
	label.TextSize = px(18)
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local ForgeStallUI = {}

function ForgeStallUI.Create(parent, options)
	if not parent then
		return nil
	end

	cleanupConnections()
	clearChildren(parent)

	options = type(options) == "table" and options or {}

	if parent:IsA("ScreenGui") then
		parent.ResetOnSpawn = false
		parent.IgnoreGuiInset = true
	end

	if not UpgradeConfig then
		return createErrorLabel(parent, "Forge unavailable: UpgradeConfig not found.")
	end

	if not ensureRemotes() then
		return createErrorLabel(parent, "Forge unavailable: required remotes not found.")
	end

	local upgradeLevels = {}
	pcall(function()
		upgradeLevels = getStatesRF:InvokeServer()
	end)
	if type(upgradeLevels) ~= "table" then
		upgradeLevels = {}
	end

	local playerLevel = math.max(1, math.floor(tonumber(upgradeLevels._playerLevel or player:GetAttribute("Level") or 1) or 1))
	upgradeLevels._playerLevel = nil

	local shardBalance = 0
	pcall(function()
		local result = getSalvageRF:InvokeServer()
		if type(result) == "number" then
			shardBalance = math.max(0, math.floor(result))
		end
	end)

	local root = Instance.new("Frame")
	root.Name = "ForgeRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = parent

	local stageTopPadding = px(58)
	local stageBottomPadding = px(12)
	local railGap = px(18)
	local leftWidth = px(186)
	local balanceHeight = px(110)
	local cardGap = px(12)
	local packHeight = px(108)
	local rowGap = px(12)
	local rowHeightRegular = px(192)
	local rowHeightHealth = px(268)
	local contentTopInset = px(42)
	local contentBottomInset = px(16)
	local contentSideInset = px(14)
	local packCount = 0
	if ShardProducts and type(ShardProducts.Packs) == "table" then
		packCount = #ShardProducts.Packs
	end
	local rowsHeight = (rowHeightRegular * 2) + rowHeightHealth + (rowGap * 2)
	local panelHeight = rowsHeight + contentTopInset + contentBottomInset
	local leftColumnHeight = (packCount * packHeight) + (math.max(0, packCount - 1) * cardGap) + cardGap + balanceHeight
	local stageInnerHeight = math.max(panelHeight, leftColumnHeight + px(18))
	local stageHeight = stageInnerHeight + stageTopPadding + stageBottomPadding

	local stage = Instance.new("Frame")
	stage.Name = "ForgeStage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.53)
	stage.Size = UDim2.new(0.58, 0, 0, stageHeight)
	stage.BackgroundTransparency = 1
	stage.BorderSizePixel = 0
	stage.Parent = root
	local stageConstraint = Instance.new("UISizeConstraint")
	stageConstraint.MaxSize = Vector2.new(860, px(900))
	stageConstraint.MinSize = Vector2.new(660, px(700))
	stageConstraint.Parent = stage

	local panelPosition = UDim2.new(1, 0, 0, stageTopPadding)
	local panelSize = UDim2.new(1, -(leftWidth + railGap), 0, panelHeight)

	local shadow = Instance.new("Frame")
	shadow.AnchorPoint = Vector2.new(1, 0)
	shadow.Position = UDim2.new(1, px(8), 0, stageTopPadding + px(8))
	shadow.Size = panelSize
	shadow.BackgroundColor3 = BLACK
	shadow.BackgroundTransparency = 0.58
	shadow.BorderSizePixel = 0
	shadow.Parent = stage
	applyCorners(shadow, px(18))

	local panel = Instance.new("Frame")
	panel.Name = "ForgePanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = panelPosition
	panel.Size = panelSize
	panel.BackgroundColor3 = PANEL_BG
	panel.BorderSizePixel = 0
	panel.Parent = stage
	applyCorners(panel, px(18))
	applyStroke(panel, ORANGE, 1.4, 0.08)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Rotation = 90
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PANEL_BG_LIGHT),
		ColorSequenceKeypoint.new(1, PANEL_BG),
	})
	panelGradient.Parent = panel

	local titleBadge = Instance.new("Frame")
	titleBadge.Name = "TitleBadge"
	titleBadge.Position = UDim2.new(0, px(18), 0, -px(18))
	titleBadge.Size = UDim2.new(0, px(214), 0, px(56))
	titleBadge.BackgroundColor3 = Color3.fromRGB(19, 19, 20)
	titleBadge.BorderSizePixel = 0
	titleBadge.Parent = panel
	applyCorners(titleBadge, px(12))
	applyStroke(titleBadge, ORANGE, 1.2, 0.04)

	local titleText = Instance.new("TextLabel")
	titleText.BackgroundTransparency = 1
	titleText.Position = UDim2.new(0, px(18), 0, -px(2))
	titleText.Size = UDim2.new(1, -px(28), 1, 0)
	titleText.Font = Enum.Font.FredokaOne
	titleText.Text = "FORGE"
	titleText.TextColor3 = WHITE
	titleText.TextSize = math.max(28, px(28))
	titleText.TextXAlignment = Enum.TextXAlignment.Left
	titleText.Parent = titleBadge

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -px(8), 0, -px(8))
	closeButton.Size = UDim2.new(0, px(36), 0, px(36))
	closeButton.BackgroundColor3 = RED
	closeButton.BorderSizePixel = 0
	closeButton.AutoButtonColor = false
	closeButton.Text = "X"
	closeButton.TextColor3 = WHITE
	closeButton.TextSize = math.max(16, px(16))
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.Parent = panel
	applyCorners(closeButton, px(10))

	trackConn(closeButton.MouseEnter:Connect(function()
		TweenService:Create(closeButton, QUICK_TWEEN, { BackgroundColor3 = Color3.fromRGB(214, 84, 68) }):Play()
	end))
	trackConn(closeButton.MouseLeave:Connect(function()
		TweenService:Create(closeButton, QUICK_TWEEN, { BackgroundColor3 = RED }):Play()
	end))
	trackConn(closeButton.MouseButton1Click:Connect(function()
		if type(options.onClose) == "function" then
			options.onClose()
		elseif parent:IsA("ScreenGui") then
			parent.Enabled = false
		else
			root.Visible = false
		end
	end))

	local leftColumn = Instance.new("Frame")
	leftColumn.BackgroundTransparency = 1
	leftColumn.Position = UDim2.new(0, 0, 0, stageTopPadding + math.max(0, math.floor((panelHeight - leftColumnHeight) * 0.5)))
	leftColumn.Size = UDim2.new(0, leftWidth, 0, leftColumnHeight)
	leftColumn.Parent = stage

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, contentSideInset, 0, contentTopInset)
	content.Size = UDim2.new(1, -(contentSideInset * 2), 1, -(contentTopInset + contentBottomInset))
	content.Parent = panel

	local packsHost = Instance.new("Frame")
	packsHost.BackgroundTransparency = 1
	packsHost.Size = UDim2.new(1, 0, 1, -(balanceHeight + cardGap))
	packsHost.Parent = leftColumn

	local packsLayout = Instance.new("UIListLayout")
	packsLayout.Padding = UDim.new(0, cardGap)
	packsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packsLayout.Parent = packsHost

	local bestPackIndex = nil
	local bestRatio = -math.huge
	local packs = (ShardProducts and ShardProducts.Packs) or {}
	for index, pack in ipairs(packs) do
		local ratio = 0
		if type(pack.Price) == "number" and pack.Price > 0 then
			ratio = (tonumber(pack.Shards) or 0) / pack.Price
		end
		if ratio > bestRatio then
			bestRatio = ratio
			bestPackIndex = index
		end
	end

	local promptDebounce = false
	local robuxImage = getRobuxImage()

	local function createPackCard(pack, layoutOrder, isBest)
		local card = Instance.new("TextButton")
		card.Name = "Pack_" .. tostring(layoutOrder)
		card.Size = UDim2.new(1, 0, 0, packHeight)
		card.BackgroundColor3 = CARD_BG
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.LayoutOrder = layoutOrder
		card.Parent = packsHost
		applyCorners(card, px(14))
		local cardStroke = applyStroke(card, ORANGE, 1.1, 0.12)

		local iconBubble = Instance.new("Frame")
		iconBubble.AnchorPoint = Vector2.new(0, 0.5)
		iconBubble.Position = UDim2.new(0, -px(20), 0.5, 0)
		iconBubble.Size = UDim2.new(0, px(88), 0, px(88))
		iconBubble.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		iconBubble.BackgroundTransparency = 1
		iconBubble.BorderSizePixel = 0
		iconBubble.Parent = card

		local iconWrap = Instance.new("Frame")
		iconWrap.AnchorPoint = Vector2.new(0.5, 0.5)
		iconWrap.Position = UDim2.fromScale(0.5, 0.5)
		iconWrap.Size = UDim2.new(0, px(80), 0, px(80))
		iconWrap.BackgroundTransparency = 1
		iconWrap.Parent = iconBubble
		makeShardIcon(iconWrap, px(80))

		local amountLabel = Instance.new("TextLabel")
		amountLabel.BackgroundTransparency = 1
		amountLabel.Position = UDim2.new(0, px(54), 0, px(12))
		amountLabel.Size = UDim2.new(1, -px(58), 0, px(28))
		amountLabel.Font = Enum.Font.GothamBlack
		amountLabel.Text = formatNumber(pack.Shards)
		amountLabel.TextColor3 = WHITE
		amountLabel.TextSize = math.max(18, px(18))
		amountLabel.TextXAlignment = Enum.TextXAlignment.Left
		amountLabel.Parent = card

		local priceRow = Instance.new("Frame")
		priceRow.BackgroundTransparency = 1
		priceRow.Position = UDim2.new(0, px(54), 0, px(46))
		priceRow.Size = UDim2.new(1, -px(58), 0, px(22))
		priceRow.Parent = card

		if robuxImage then
			local robuxIcon = makeRobuxIcon(priceRow, px(15))
			robuxIcon.Position = UDim2.new(0, 0, 0.5, -px(7))
		end

		local priceLabel = Instance.new("TextLabel")
		priceLabel.BackgroundTransparency = 1
		priceLabel.Position = UDim2.new(0, robuxImage and px(16) or 0, 0, 0)
		priceLabel.Size = UDim2.new(1, -(robuxImage and px(16) or 0), 1, 0)
		priceLabel.Font = Enum.Font.GothamBlack
		priceLabel.Text = tostring(pack.Price or 0)
		priceLabel.TextColor3 = ORANGE_BRIGHT
		priceLabel.TextSize = math.max(14, px(14))
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.Parent = priceRow

		if isBest then
			local bestLabel = Instance.new("TextLabel")
			bestLabel.AnchorPoint = Vector2.new(1, 1)
			bestLabel.BackgroundTransparency = 1
			bestLabel.Position = UDim2.new(1, -px(8), 1, -px(7))
			bestLabel.Size = UDim2.new(0, px(84), 0, px(18))
			bestLabel.Font = Enum.Font.GothamBlack
			bestLabel.Text = "BEST VALUE"
			bestLabel.TextColor3 = ORANGE_BRIGHT
			bestLabel.TextSize = math.max(10, px(10))
			bestLabel.TextXAlignment = Enum.TextXAlignment.Right
			bestLabel.Parent = card
		end

		trackConn(card.MouseEnter:Connect(function()
			TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG_HOVER }):Play()
			cardStroke.Color = ORANGE_BRIGHT
		end))
		trackConn(card.MouseLeave:Connect(function()
			TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG }):Play()
			cardStroke.Color = ORANGE
		end))
		trackConn(card.MouseButton1Click:Connect(function()
			if promptDebounce then
				return
			end
			if not pack.ProductId or pack.ProductId <= 0 then
				showToast(panel, "Shard product ID not set for " .. tostring(pack.Name), RED, 2.7)
				return
			end
			promptDebounce = true
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			end)
			if not ok then
				warn("[ForgeStallUI] PromptProductPurchase failed:", tostring(err))
				showToast(panel, "Could not open the purchase prompt.", RED, 2.5)
			end
			task.delay(1.5, function()
				promptDebounce = false
			end)
		end))
	end

	for index, pack in ipairs(packs) do
		createPackCard(pack, index, index == bestPackIndex)
	end

	local balanceCard = Instance.new("Frame")
	balanceCard.Name = "BalanceCard"
	balanceCard.AnchorPoint = Vector2.new(0, 1)
	balanceCard.Position = UDim2.new(0, 0, 1, 0)
	balanceCard.Size = UDim2.new(1, 0, 0, balanceHeight)
	balanceCard.BackgroundColor3 = CARD_BG_ALT
	balanceCard.BorderSizePixel = 0
	balanceCard.Parent = leftColumn
	applyCorners(balanceCard, px(14))
	applyStroke(balanceCard, ORANGE, 1.1, 0.12)

	local balanceTitle = Instance.new("TextLabel")
	balanceTitle.BackgroundTransparency = 1
	balanceTitle.Position = UDim2.new(0, px(12), 0, px(10))
	balanceTitle.Size = UDim2.new(1, -px(24), 0, px(14))
	balanceTitle.Font = Enum.Font.GothamBlack
	balanceTitle.Text = "YOUR SHARDS"
	balanceTitle.TextColor3 = ORANGE_BRIGHT
	balanceTitle.TextSize = math.max(10, px(10))
	balanceTitle.TextXAlignment = Enum.TextXAlignment.Left
	balanceTitle.Parent = balanceCard

	local balanceIconWrap = Instance.new("Frame")
	balanceIconWrap.BackgroundTransparency = 1
	balanceIconWrap.Position = UDim2.new(0, -px(20), 0, px(12))
	balanceIconWrap.Size = UDim2.new(0, px(84), 0, px(84))
	balanceIconWrap.Parent = balanceCard
	makeShardIcon(balanceIconWrap, px(84))

	local balanceValue = Instance.new("TextLabel")
	balanceValue.BackgroundTransparency = 1
	balanceValue.Position = UDim2.new(0, px(58), 0, px(42))
	balanceValue.Size = UDim2.new(1, -px(62), 0, px(28))
	balanceValue.Font = Enum.Font.GothamBlack
	balanceValue.TextColor3 = WHITE
	balanceValue.TextSize = math.max(20, px(20))
	balanceValue.TextXAlignment = Enum.TextXAlignment.Left
	balanceValue.Parent = balanceCard

	local rightColumn = Instance.new("Frame")
	rightColumn.BackgroundTransparency = 1
	rightColumn.Position = UDim2.new(0, 0, 0, 0)
	rightColumn.Size = UDim2.fromScale(1, 1)
	rightColumn.Parent = content

	local rowsHost = Instance.new("Frame")
	rowsHost.BackgroundTransparency = 1
	rowsHost.Size = UDim2.fromScale(1, 1)
	rowsHost.Parent = rightColumn

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, rowGap)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rowsLayout.Parent = rowsHost

	local rowRefs = {}

	local function createRow(upgradeId, layoutOrder)
		local def = UpgradeConfig.GetDefinition and UpgradeConfig.GetDefinition(upgradeId) or {}
		local isHealth = upgradeId == UpgradeConfig.HEALTH
		local rowHeight = isHealth and rowHeightHealth or rowHeightRegular
		local actionWidth = px(188)
		local artWidth = px(126)

		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(upgradeId)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.BackgroundColor3 = CARD_BG
		row.BorderSizePixel = 0
		row.LayoutOrder = layoutOrder
		row.Parent = rowsHost
		row.ClipsDescendants = false
		applyCorners(row, px(14))
		local rowStroke = applyStroke(row, ORANGE, 1.15, 0.08)

		local artPanel = Instance.new("Frame")
		artPanel.BackgroundColor3 = ART_BG
		artPanel.BorderSizePixel = 0
		artPanel.Position = UDim2.new(0, px(14), 0, px(14))
		artPanel.Size = UDim2.new(0, artWidth, 1, -px(28))
		artPanel.Parent = row
		applyCorners(artPanel, px(18))

		local artGlow = Instance.new("Frame")
		artGlow.AnchorPoint = Vector2.new(0.5, 0.5)
		artGlow.Position = UDim2.fromScale(0.5, 0.56)
		artGlow.Size = UDim2.new(0, px(60), 0, px(60))
		artGlow.BackgroundColor3 = ORANGE
		artGlow.BackgroundTransparency = 0.9
		artGlow.BorderSizePixel = 0
		artGlow.Parent = artPanel
		applyCorners(artGlow, px(30))

		local artImage = getUpgradeArt(upgradeId)
		if artImage then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.Size = UDim2.new(0.68, 0, 0.68, 0)
			image.Image = artImage
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = artPanel
		else
			local emblem = createHealthEmblem(artPanel, px(70))
			emblem.Position = UDim2.new(0.5, -px(35), 0.5, -px(35))
		end

		local details = Instance.new("Frame")
		details.BackgroundTransparency = 1
		details.Position = UDim2.new(0, artWidth + px(26), 0, px(16))
		details.Size = UDim2.new(1, -(artWidth + actionWidth + px(58)), 1, -px(32))
		details.Parent = row

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 0, 0, 0)
		title.Size = UDim2.new(1, 0, 0, px(40))
		title.Font = Enum.Font.GothamBlack
		title.Text = string.upper(def.Title or tostring(upgradeId))
		title.TextColor3 = WHITE
		title.TextSize = math.max(27, px(27))
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = details

		local subtitle = Instance.new("TextLabel")
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.new(0, 0, 0, px(40))
		subtitle.Size = UDim2.new(1, 0, 0, px(20))
		subtitle.Font = Enum.Font.GothamBlack
		subtitle.TextColor3 = ORANGE_BRIGHT
		subtitle.TextSize = math.max(14, px(14))
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.Parent = details

		local description = Instance.new("TextLabel")
		description.BackgroundTransparency = 1
		description.Size = UDim2.new(1, 0, 0, px(22))
		description.Font = Enum.Font.GothamBold
		description.TextColor3 = GRAY
		description.TextSize = math.max(14, px(14))
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.Parent = details

		local progressTrack = Instance.new("Frame")
		progressTrack.BackgroundColor3 = TRACK_GRAY
		progressTrack.BorderSizePixel = 0
		progressTrack.Position = UDim2.new(0, 0, 0, px(90))
		progressTrack.Size = UDim2.new(1, 0, 0, px(20))
		progressTrack.Visible = isHealth
		progressTrack.Parent = details
		progressTrack.ClipsDescendants = true
		applyCorners(progressTrack, px(10))

		local progressFill = Instance.new("Frame")
		progressFill.BackgroundColor3 = GREEN
		progressFill.BorderSizePixel = 0
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.Parent = progressTrack
		applyCorners(progressFill, px(10))
		applyStroke(progressTrack, ORANGE, 1.05, 0.2)

		local progressOverlay = Instance.new("Frame")
		progressOverlay.BackgroundTransparency = 1
		progressOverlay.Size = UDim2.fromScale(1, 1)
		progressOverlay.Parent = progressTrack

		local segmentLines = {}
		local maxLevel = UpgradeConfig.GetMaxLevel and UpgradeConfig.GetMaxLevel(upgradeId) or 0
		if isHealth and maxLevel > 1 then
			for segmentIndex = 1, maxLevel - 1 do
				local line = Instance.new("Frame")
				line.AnchorPoint = Vector2.new(0.5, 0)
				line.Position = UDim2.new(segmentIndex / maxLevel, 0, 0, 0)
				line.Size = UDim2.new(0, 1, 1, 0)
				line.BackgroundColor3 = Color3.fromRGB(34, 35, 37)
				line.BorderSizePixel = 0
				line.Parent = progressOverlay
				segmentLines[segmentIndex] = line
			end
		end

		if isHealth then
			description.Position = UDim2.new(0, 0, 0, px(122))
		else
			description.Position = UDim2.new(0, 0, 0, px(76))
		end

		local levelLabel = Instance.new("TextLabel")
		levelLabel.BackgroundTransparency = 1
		levelLabel.AnchorPoint = Vector2.new(1, 0)
		levelLabel.Position = UDim2.new(1, -px(14), 0, px(12))
		levelLabel.Size = UDim2.new(0, actionWidth, 0, px(22))
		levelLabel.Font = Enum.Font.GothamBlack
		levelLabel.TextColor3 = GREEN
		levelLabel.TextSize = math.max(14, px(14))
		levelLabel.TextXAlignment = Enum.TextXAlignment.Right
		levelLabel.Parent = row

		local purchaseBox = Instance.new("Frame")
		purchaseBox.BackgroundColor3 = CARD_BG_ALT
		purchaseBox.BorderSizePixel = 0
		purchaseBox.AnchorPoint = Vector2.new(1, 1)
		purchaseBox.Position = UDim2.new(1, -px(14), 1, -px(16))
		purchaseBox.Size = UDim2.new(0, actionWidth, 0, px(94))
		purchaseBox.Parent = row
		purchaseBox.ClipsDescendants = false
		applyCorners(purchaseBox, px(12))
		applyStroke(purchaseBox, ORANGE, 1.05, 0.1)

		local costPill = Instance.new("Frame")
		costPill.BackgroundTransparency = 1
		costPill.BorderSizePixel = 0
		costPill.Position = UDim2.new(0, px(14), 0, px(10))
		costPill.Size = UDim2.new(1, -px(24), 0, px(36))
		costPill.Parent = purchaseBox

		local costIconWrap = Instance.new("Frame")
		costIconWrap.BackgroundTransparency = 1
		costIconWrap.Position = UDim2.new(0, -px(18), 0.5, -px(24))
		costIconWrap.Size = UDim2.new(0, px(48), 0, px(48))
		costIconWrap.Parent = costPill
		local costIcon = makeShardIcon(costIconWrap, px(48))

		local costValue = Instance.new("TextLabel")
		costValue.BackgroundTransparency = 1
		costValue.Position = UDim2.new(0, px(34), 0, 0)
		costValue.Size = UDim2.new(1, -px(20), 1, 0)
		costValue.Font = Enum.Font.GothamBlack
		costValue.TextColor3 = WHITE
		costValue.TextSize = math.max(16, px(16))
		costValue.TextXAlignment = Enum.TextXAlignment.Center
		costValue.Parent = costPill

		local actionButton = Instance.new("TextButton")
		actionButton.AutoButtonColor = false
		actionButton.BackgroundColor3 = BUTTON_READY
		actionButton.BorderSizePixel = 0
		actionButton.Position = UDim2.new(0, px(10), 1, -px(40))
		actionButton.Size = UDim2.new(1, -px(20), 0, px(32))
		actionButton.Font = Enum.Font.GothamBlack
		actionButton.Text = "UPGRADE"
		actionButton.TextColor3 = WHITE
		actionButton.TextSize = math.max(15, px(15))
		actionButton.Parent = purchaseBox
		applyCorners(actionButton, px(10))

		local refs = {
			upgradeId = upgradeId,
			isHealth = isHealth,
			subtitle = subtitle,
			description = description,
			levelLabel = levelLabel,
			progressTrack = progressTrack,
			progressFill = progressFill,
			segmentLines = segmentLines,
			rowStroke = rowStroke,
			costPill = costPill,
			costIcon = costIcon,
			costValue = costValue,
			actionButton = actionButton,
			currentMode = "ready",
			currentCost = 0,
			lockedLevel = nil,
			canAfford = false,
		}

		trackConn(actionButton.MouseEnter:Connect(function()
			if refs.currentMode ~= "ready" then
				return
			end
			TweenService:Create(actionButton, QUICK_TWEEN, { BackgroundColor3 = BUTTON_READY_HOVER }):Play()
			refs.rowStroke.Color = ORANGE_BRIGHT
		end))
		trackConn(actionButton.MouseLeave:Connect(function()
			if refs.currentMode ~= "ready" then
				return
			end
			TweenService:Create(actionButton, QUICK_TWEEN, {
				BackgroundColor3 = refs.canAfford and BUTTON_READY or ORANGE_DARK,
			}):Play()
			refs.rowStroke.Color = ORANGE
		end))

		rowRefs[upgradeId] = refs
	end

	createRow(UpgradeConfig.MELEE, 1)
	createRow(UpgradeConfig.RANGED, 2)
	createRow(UpgradeConfig.HEALTH, 3)

	local function updateBalance()
		balanceValue.Text = formatCompactNumber(shardBalance)
	end

	local function setButtonMode(refs, mode, cost, canAfford, requiredLevel)
		refs.currentMode = mode
		refs.currentCost = cost or 0
		refs.canAfford = canAfford == true
		refs.lockedLevel = requiredLevel

		if mode == "max" then
			refs.costPill.Visible = true
			refs.costValue.Text = "MAX"
			refs.actionButton.Text = "MAX LEVEL"
			refs.actionButton.BackgroundColor3 = BUTTON_MAX
			refs.rowStroke.Color = ORANGE
			return
		end

		refs.costPill.Visible = true
		refs.costValue.Text = formatNumber(cost)
		refs.costIcon.Visible = true

		if mode == "locked" then
			refs.actionButton.Text = "LOCKED"
			refs.actionButton.BackgroundColor3 = BUTTON_LOCKED
			refs.rowStroke.Color = ORANGE
			return
		end

		refs.actionButton.Text = "UPGRADE"
		refs.actionButton.BackgroundColor3 = canAfford and BUTTON_READY or ORANGE_DARK
		refs.rowStroke.Color = ORANGE
	end

	local function updateRow(upgradeId)
		local refs = rowRefs[upgradeId]
		if not refs then
			return
		end

		local level = math.max(0, math.floor(tonumber(upgradeLevels[upgradeId]) or 0))
		local cost = UpgradeConfig.GetCost(level, upgradeId)
		local maxLevel = UpgradeConfig.GetMaxLevel and UpgradeConfig.GetMaxLevel(upgradeId) or 0
		local isMax = UpgradeConfig.IsCapped and UpgradeConfig.IsCapped(level, upgradeId) or false
		local locked = false
		local requiredLevel = nil
		if UpgradeConfig.IsPlayerLevelLocked then
			locked, requiredLevel = UpgradeConfig.IsPlayerLevelLocked(level, playerLevel, upgradeId)
		end
		local canAfford = shardBalance >= cost

		if refs.isHealth then
			refs.levelLabel.Text = string.format("Lv. %d/%d", level, maxLevel)
			refs.subtitle.Text = string.format("+%d max health per upgrade", UpgradeConfig.HEALTH_BONUS_PER_LEVEL or 10)
			if locked and requiredLevel and not isMax then
				refs.description.Text = string.format("Increase your max health. Unlocks at player level %d.", requiredLevel)
			else
				refs.description.Text = "Increase your maximum health."
			end
			local fillScale = 0
			if maxLevel > 0 then
				fillScale = math.clamp(level / maxLevel, 0, 1)
			end
			refs.progressFill.Size = UDim2.new(fillScale, 0, 1, 0)
		else
			refs.levelLabel.Text = "Lv. " .. formatNumber(level)
			local bonusText = UpgradeConfig.GetBonusText(level, upgradeId)
			if bonusText == "No bonus" then
				bonusText = "+0%"
			end
			refs.subtitle.Text = "Current bonus " .. bonusText
			if upgradeId == UpgradeConfig.MELEE then
				refs.description.Text = "Increase your melee damage."
			else
				refs.description.Text = "Increase your ranged damage."
			end
		end

		if isMax then
			setButtonMode(refs, "max", cost, canAfford, requiredLevel)
		elseif locked then
			setButtonMode(refs, "locked", cost, canAfford, requiredLevel)
		else
			setButtonMode(refs, "ready", cost, canAfford, requiredLevel)
		end
	end

	local function refreshAll()
		updateBalance()
		updateRow(UpgradeConfig.MELEE)
		updateRow(UpgradeConfig.RANGED)
		updateRow(UpgradeConfig.HEALTH)
	end

	for upgradeId, refs in pairs(rowRefs) do
		trackConn(refs.actionButton.MouseButton1Click:Connect(function()
			local level = math.max(0, math.floor(tonumber(upgradeLevels[upgradeId]) or 0))
			local definition = UpgradeConfig.GetDefinition and UpgradeConfig.GetDefinition(upgradeId) or {}
			local title = definition.Title or "Upgrade"

			if refs.currentMode == "max" then
				showToast(panel, title .. " is already maxed.", ORANGE_BRIGHT, 2.2)
				return
			end
			if refs.currentMode == "locked" then
				showToast(panel, string.format("Reach player level %d to unlock that upgrade.", refs.lockedLevel or 0), ORANGE_BRIGHT, 2.4)
				return
			end
			if shardBalance < refs.currentCost then
				showToast(panel, "You need more Shards for that upgrade.", RED, 2.4)
				return
			end

			refs.actionButton.Text = "..."
			local success, msg = false, "Upgrade failed"
			pcall(function()
				success, msg = purchaseRF:InvokeServer(upgradeId)
			end)
			if success then
				upgradeLevels[upgradeId] = level + 1
				shardBalance = math.max(0, shardBalance - refs.currentCost)
				showToast(panel, title .. " upgraded.", GREEN, 2.0)
			else
				showToast(panel, tostring(msg or "Upgrade failed"), RED, 2.5)
			end
			refreshAll()
		end))
	end

	trackConn(player:GetAttributeChangedSignal("Level"):Connect(function()
		playerLevel = math.max(1, math.floor(tonumber(player:GetAttribute("Level") or playerLevel) or 1))
		refreshAll()
	end))

	if stateUpdatedRE then
		trackConn(stateUpdatedRE.OnClientEvent:Connect(function(levels)
			if type(levels) ~= "table" then
				return
			end
			local nextLevels = {}
			for key, value in pairs(levels) do
				if key ~= "_playerLevel" then
					nextLevels[key] = value
				end
			end
			upgradeLevels = nextLevels
			if levels._playerLevel ~= nil then
				playerLevel = math.max(1, math.floor(tonumber(levels._playerLevel) or playerLevel))
			end
			refreshAll()
		end))
	end

	if salvageUpdatedRE then
		trackConn(salvageUpdatedRE.OnClientEvent:Connect(function(amount)
			shardBalance = math.max(0, math.floor(tonumber(amount) or 0))
			refreshAll()
		end))
	end

	refreshAll()
	return root
end

return ForgeStallUI