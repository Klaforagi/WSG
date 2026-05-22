--------------------------------------------------------------------------------
-- PotionsStallUI.lua
-- Standalone world-station menu for potions and timed potion-style boosts.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function getViewportSize()
	local cam = Workspace.CurrentCamera
	if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
		return cam.ViewportSize
	end
	return Vector2.new(1920, 1080)
end

local function px(base)
	local screenY = getViewportSize().Y
	return math.max(1, math.round(base * screenY / 1080))
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		pcall(function()
			child:Destroy()
		end)
	end
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
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return stroke
end

local function addTextLimit(label, minSize, maxSize)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = minSize
	limit.MaxTextSize = maxSize
	limit.Parent = label
	return limit
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

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds <= 0 then
		return ""
	end
	local minutes = math.floor(seconds / 60)
	if minutes >= 1 then
		return string.format("%d min", minutes)
	end
	return string.format("%d sec", seconds)
end

local function safeRequire(parent, moduleName, timeout)
	timeout = timeout or 5
	local mod = parent:WaitForChild(moduleName, timeout)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			return result
		end
		warn("[PotionsStallUI] Failed to require", moduleName, ":", tostring(result))
	end
	return nil
end

local PotionConfig = safeRequire(ReplicatedStorage, "PotionConfig", 10)
local BoostConfig = safeRequire(ReplicatedStorage, "BoostConfig", 10)
local AssetCodes = safeRequire(ReplicatedStorage, "AssetCodes", 5)

local PANEL_BG = Color3.fromRGB(26, 31, 46)
local PANEL_BG_LIGHT = Color3.fromRGB(45, 57, 86)
local PANEL_EDGE = Color3.fromRGB(108, 130, 194)
local CONTENT_BG = Color3.fromRGB(18, 23, 37)
local CARD_BG = Color3.fromRGB(42, 50, 74)
local CARD_BG_DARK = Color3.fromRGB(29, 35, 54)
local CARD_STROKE = Color3.fromRGB(123, 144, 200)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local DIM_TEXT = Color3.fromRGB(214, 222, 240)
local MUTED_TEXT = Color3.fromRGB(155, 166, 196)
local ACCENT_GOLD = Color3.fromRGB(255, 208, 95)
local ACCENT_BLUE = Color3.fromRGB(91, 188, 255)
local ACCENT_GREEN = Color3.fromRGB(98, 229, 95)
local RED = Color3.fromRGB(208, 90, 76)
local BUTTON_PRIMARY = Color3.fromRGB(67, 170, 108)
local BUTTON_PRIMARY_DISABLED = Color3.fromRGB(63, 79, 80)
local BUTTON_SECONDARY = Color3.fromRGB(235, 167, 58)
local BUTTON_SECONDARY_DISABLED = Color3.fromRGB(104, 87, 55)

local QUICK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeConnections = {}
local closeCallbacks = setmetatable({}, { __mode = "k" })
local remotes = nil

local function trackConn(conn)
	table.insert(activeConnections, conn)
	return conn
end

local function cleanupConnections()
	for _, conn in ipairs(activeConnections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	activeConnections = {}
end

local function colorFromRGBArray(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "table" then
		local r = tonumber(value[1])
		local g = tonumber(value[2])
		local b = tonumber(value[3])
		if r and g and b then
			return Color3.fromRGB(r, g, b)
		end
	end
	return fallback or ACCENT_GOLD
end

local function brightenColor(color, amount)
	return Color3.new(
		math.clamp(color.R + amount, 0, 1),
		math.clamp(color.G + amount, 0, 1),
		math.clamp(color.B + amount, 0, 1)
	)
end

local function mixColor(a, b, alpha)
	return Color3.new(
		a.R + ((b.R - a.R) * alpha),
		a.G + ((b.G - a.G) * alpha),
		a.B + ((b.B - a.B) * alpha)
	)
end

local function getServerNow()
	local ok, result = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(result) == "number" then
		return result
	end
	return os.time()
end

local function getAsset(key)
	if AssetCodes and type(AssetCodes.Get) == "function" and key then
		local asset = AssetCodes.Get(key)
		if type(asset) == "string" and #asset > 0 then
			return asset
		end
	end
	return nil
end

local function getIconImage(def)
	if type(def) ~= "table" then
		return nil
	end
	if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then
		return def.IconAssetId
	end
	return getAsset(def.IconKey)
end

local function ensureRemotes()
	if remotes then
		return true
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return false
	end

	local potionsFolder = remotesFolder:WaitForChild("Potions", 10)
	local boostsFolder = remotesFolder:WaitForChild("Boosts", 10)
	if not potionsFolder or not boostsFolder then
		return false
	end

	remotes = {
		getCoinsRF = ReplicatedStorage:WaitForChild("GetCoins", 10),
		coinsUpdatedRE = ReplicatedStorage:WaitForChild("CoinsUpdated", 10),
		potionGetStateRF = potionsFolder:WaitForChild("GetPotionState", 10),
		potionSetEquippedRF = potionsFolder:WaitForChild("SetPotionEquipped", 10),
		potionStateUpdatedRE = remotesFolder:WaitForChild("PotionStateUpdated", 10),
		boostPurchaseRF = boostsFolder:FindFirstChild("PurchaseBoost") or boostsFolder:WaitForChild("RequestBuyOrUseBoost", 10),
		boostActivateRF = boostsFolder:WaitForChild("ActivateInventoryBoost", 10),
		boostGetStatesRF = boostsFolder:WaitForChild("GetBoostStates", 10),
		boostStateUpdatedRE = remotesFolder:WaitForChild("BoostStateUpdated", 10),
	}

	for _, remote in pairs(remotes) do
		if remote == nil then
			remotes = nil
			return false
		end
	end

	return true
end

local function createErrorLabel(parent, text)
	clearChildren(parent)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = RED
	label.TextSize = px(22)
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function buildStallEntries()
	local entries = {}

	if PotionConfig then
		local potionDefs = {}
		if type(PotionConfig.GetStallPotions) == "function" then
			potionDefs = PotionConfig.GetStallPotions()
		elseif type(PotionConfig.GetOrderedPotions) == "function" then
			for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
				if potionDef.ShowInPotionsStall == true then
					table.insert(potionDefs, potionDef)
				end
			end
		end

		for _, potionDef in ipairs(potionDefs) do
			table.insert(entries, {
				Kind = "potion",
				Id = potionDef.Id,
				DisplayName = potionDef.DisplayName,
				Description = potionDef.Description,
				DetailText = potionDef.DetailText,
				DurationSeconds = potionDef.DurationSeconds,
				CooldownSeconds = potionDef.CooldownSeconds,
				PriceCoins = potionDef.PriceCoins,
				IconGlyph = potionDef.IconGlyph,
				BadgeText = potionDef.BadgeText,
				IconColor = potionDef.IconColor,
				IconAssetId = potionDef.IconAssetId,
				IconKey = potionDef.IconKey,
				SortOrder = potionDef.SortOrder or -1000,
			})
		end
	end

	if BoostConfig then
		local boostDefs = {}
		if type(BoostConfig.GetPotionsStallBoosts) == "function" then
			boostDefs = BoostConfig.GetPotionsStallBoosts()
		elseif type(BoostConfig.Boosts) == "table" then
			for _, boostDef in ipairs(BoostConfig.Boosts) do
				if boostDef.ShowInPotionsStall == true and not boostDef.InstantUse and boostDef.RemovedFromShop ~= true and boostDef.Purchasable ~= false then
					table.insert(boostDefs, boostDef)
				end
			end
		end

		for _, boostDef in ipairs(boostDefs) do
			table.insert(entries, {
				Kind = "boost",
				Id = boostDef.Id,
				DisplayName = boostDef.DisplayName,
				Description = boostDef.Description,
				DurationSeconds = boostDef.DurationSeconds,
				PriceCoins = boostDef.PriceCoins,
				IconGlyph = boostDef.IconGlyph,
				BadgeText = boostDef.BadgeText,
				IconColor = boostDef.IconColor,
				IconAssetId = boostDef.IconAssetId,
				IconKey = boostDef.IconKey,
				SortOrder = boostDef.SortOrder or 0,
			})
		end
	end

	table.sort(entries, function(a, b)
		local orderA = tonumber(a.SortOrder) or 0
		local orderB = tonumber(b.SortOrder) or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return tostring(a.DisplayName or a.Id) < tostring(b.DisplayName or b.Id)
	end)

	return entries
end

local function setButtonState(button, enabled, text, color)
	button.Active = enabled == true
	button.Selectable = enabled == true
	button.AutoButtonColor = false
	button.Text = text or button.Text
	button.BackgroundColor3 = enabled and color or (color == BUTTON_SECONDARY and BUTTON_SECONDARY_DISABLED or BUTTON_PRIMARY_DISABLED)
	button.BackgroundTransparency = enabled and 0 or 0.12
	button.TextColor3 = enabled and WHITE or Color3.fromRGB(190, 202, 212)
	button.TextTransparency = enabled and 0 or 0.15
	button:SetAttribute("EnabledState", enabled == true)
	button:SetAttribute("BaseColorR", color.R)
	button:SetAttribute("BaseColorG", color.G)
	button:SetAttribute("BaseColorB", color.B)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = enabled and 0.18 or 0.48
	end
end

local function bindButtonHover(button)
	trackConn(button.MouseEnter:Connect(function()
		if not button:GetAttribute("EnabledState") then
			return
		end
		local baseColor = Color3.new(
			button:GetAttribute("BaseColorR") or button.BackgroundColor3.R,
			button:GetAttribute("BaseColorG") or button.BackgroundColor3.G,
			button:GetAttribute("BaseColorB") or button.BackgroundColor3.B
		)
		TweenService:Create(button, QUICK_TWEEN, { BackgroundColor3 = brightenColor(baseColor, 0.08) }):Play()
	end))
	trackConn(button.MouseLeave:Connect(function()
		local baseColor = Color3.new(
			button:GetAttribute("BaseColorR") or button.BackgroundColor3.R,
			button:GetAttribute("BaseColorG") or button.BackgroundColor3.G,
			button:GetAttribute("BaseColorB") or button.BackgroundColor3.B
		)
		if button:GetAttribute("EnabledState") then
			TweenService:Create(button, QUICK_TWEEN, { BackgroundColor3 = baseColor }):Play()
		end
	end))
end

local PotionsStallUI = {}

function PotionsStallUI.SetCloseCallback(root, callback)
	if root then
		closeCallbacks[root] = callback
	end
end

function PotionsStallUI.Create(parent, options)
	if not parent then
		return nil
	end

	cleanupConnections()
	clearChildren(parent)

	options = type(options) == "table" and options or {}

	if parent:IsA("ScreenGui") then
		parent.ResetOnSpawn = false
		parent.IgnoreGuiInset = true
		parent.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end

	if not PotionConfig then
		return createErrorLabel(parent, "Potions unavailable: PotionConfig missing.")
	end
	if not BoostConfig then
		return createErrorLabel(parent, "Potions unavailable: BoostConfig missing.")
	end
	if not ensureRemotes() then
		return createErrorLabel(parent, "Potions unavailable: required remotes not found.")
	end

	local entries = buildStallEntries()
	if #entries == 0 then
		return createErrorLabel(parent, "No potions are configured for the stall.")
	end

	local potionState = {
		potions = {},
		equippedPotionId = nil,
		cooldownEndsAt = 0,
		serverTime = 0,
	}
	local boostStates = {}
	local boostTimeDelta = 0
	local coinBalance = 0

	local function ingestPotionState(state)
		if type(state) ~= "table" then
			return
		end
		potionState = {
			potions = type(state.potions) == "table" and state.potions or {},
			equippedPotionId = type(state.equippedPotionId) == "string" and state.equippedPotionId or nil,
			cooldownEndsAt = tonumber(state.cooldownEndsAt) or 0,
			serverTime = tonumber(state.serverTime) or 0,
		}
	end

	local function ingestBoostStates(states)
		if type(states) ~= "table" then
			return
		end
		boostStates = states
		boostTimeDelta = os.time() - (tonumber(states._serverTime) or os.time())
	end

	local function refreshCoinBalance()
		local ok, result = pcall(function()
			return remotes.getCoinsRF:InvokeServer()
		end)
		if ok and type(result) == "number" then
			coinBalance = math.max(0, math.floor(result))
		end
	end

	pcall(function()
		ingestPotionState(remotes.potionGetStateRF:InvokeServer())
	end)
	pcall(function()
		ingestBoostStates(remotes.boostGetStatesRF:InvokeServer())
	end)
	refreshCoinBalance()

	local root = Instance.new("Frame")
	root.Name = "PotionsStallRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = parent
	closeCallbacks[root] = options.onClose

	local viewportSize = getViewportSize()
	local compact = viewportSize.X < 760
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, compact and 0.51 or 0.52)
	panel.Size = UDim2.fromScale(compact and 0.94 or 0.7, compact and 0.86 or 0.8)
	panel.BackgroundColor3 = PANEL_BG
	panel.BorderSizePixel = 0
	panel.Parent = root
	applyCorners(panel, px(28))
	applyStroke(panel, PANEL_EDGE, 2, 0.1)

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(math.min(640, math.floor(viewportSize.X * 0.92)), math.min(px(470), math.floor(viewportSize.Y * 0.78)))
	panelConstraint.MaxSize = Vector2.new(math.max(320, math.floor(viewportSize.X * 0.94)), math.max(360, math.floor(viewportSize.Y * 0.88)))
	panelConstraint.Parent = panel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Rotation = 90
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PANEL_BG_LIGHT),
		ColorSequenceKeypoint.new(1, PANEL_BG),
	})
	panelGradient.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.new(0, px(20), 0, px(14))
	header.Size = UDim2.new(1, -px(40), 0, px(58))
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -px(220), 1, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "POTIONS"
	title.TextColor3 = WHITE
	title.TextSize = px(30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	addTextLimit(title, px(18), px(30))
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = BLACK
	titleStroke.Thickness = 1.6
	titleStroke.Transparency = 0.2
	titleStroke.Parent = title

	local balancePill = Instance.new("Frame")
	balancePill.Name = "BalancePill"
	balancePill.AnchorPoint = Vector2.new(1, 0)
	balancePill.Position = UDim2.new(1, -px(54), 0, px(4))
	balancePill.Size = UDim2.new(0, px(compact and 116 or 150), 0, px(40))
	balancePill.BackgroundColor3 = CONTENT_BG
	balancePill.BorderSizePixel = 0
	balancePill.Parent = header
	applyCorners(balancePill, px(14))
	applyStroke(balancePill, ACCENT_GOLD, 1.2, 0.28)

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Size = UDim2.new(1, -px(12), 1, 0)
	balanceLabel.Position = UDim2.new(0, px(6), 0, 0)
	balanceLabel.Font = Enum.Font.GothamBlack
	balanceLabel.TextColor3 = ACCENT_GOLD
	balanceLabel.TextSize = px(15)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Center
	balanceLabel.Text = "Coins: " .. formatNumber(coinBalance)
	balanceLabel.Parent = balancePill
	addTextLimit(balanceLabel, px(10), px(15))

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, px(4))
	closeButton.Size = UDim2.new(0, px(44), 0, px(40))
	closeButton.BackgroundColor3 = Color3.fromRGB(220, 87, 87)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.Text = "X"
	closeButton.TextColor3 = WHITE
	closeButton.TextSize = px(20)
	closeButton.Parent = header
	applyCorners(closeButton, px(16))
	applyStroke(closeButton, WHITE, 1.2, 0.35)
	setButtonState(closeButton, true, "X", Color3.fromRGB(220, 87, 87))
	bindButtonHover(closeButton)

	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "ToastHolder"
	toastHolder.BackgroundTransparency = 1
	toastHolder.ClipsDescendants = false
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, -px(18))
	toastHolder.Size = UDim2.new(0.68, 0, 0, px(54))
	toastHolder.ZIndex = 30
	toastHolder.Parent = panel

	local gridWrap = Instance.new("Frame")
	gridWrap.Name = "GridWrap"
	gridWrap.BackgroundColor3 = CONTENT_BG
	gridWrap.BorderSizePixel = 0
	gridWrap.Position = UDim2.new(0, px(20), 0, px(86))
	gridWrap.Size = UDim2.new(1, -px(40), 1, -px(106))
	gridWrap.Parent = panel
	gridWrap.ZIndex = 2
	applyCorners(gridWrap, px(24))
	applyStroke(gridWrap, CARD_STROKE, 1.2, 0.2)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "PotionScroller"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.new(0, px(14), 0, px(14))
	scroller.Size = UDim2.new(1, -px(28), 1, -px(28))
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = px(6)
	scroller.ScrollBarImageColor3 = Color3.fromRGB(151, 174, 230)
	scroller.Parent = gridWrap

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.CellPadding = UDim2.fromOffset(px(14), px(14))
	gridLayout.Parent = scroller

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, px(2))
	gridPad.PaddingLeft = UDim.new(0, px(2))
	gridPad.PaddingRight = UDim.new(0, px(2))
	gridPad.PaddingBottom = UDim.new(0, px(16))
	gridPad.Parent = scroller

	local cardRefs = {}

	local function showToast(message, color)
		local toast = Instance.new("TextLabel")
		toast.Name = "Toast"
		toast.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
		toast.BackgroundTransparency = 0.08
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position = UDim2.fromScale(0.5, 0)
		toast.Size = UDim2.new(1, 0, 0, px(42))
		toast.Font = Enum.Font.GothamBold
		toast.Text = tostring(message or "")
		toast.TextColor3 = color or ACCENT_GOLD
		toast.TextSize = px(15)
		toast.TextWrapped = true
		toast.ZIndex = 31
		toast.Parent = toastHolder
		applyCorners(toast, px(12))
		applyStroke(toast, color or ACCENT_GOLD, 1.1, 0.28)
		toast.BackgroundTransparency = 1
		toast.TextTransparency = 1
		TweenService:Create(toast, TweenInfo.new(0.18), { BackgroundTransparency = 0.12, TextTransparency = 0 }):Play()
		task.delay(2.2, function()
			if toast and toast.Parent then
				local tween = TweenService:Create(toast, TweenInfo.new(0.22), { BackgroundTransparency = 1, TextTransparency = 1 })
				tween:Play()
				tween.Completed:Connect(function()
					pcall(function()
						toast:Destroy()
					end)
				end)
			end
		end)
	end

	local function getPotionCount(potionId)
		local entry = type(potionState.potions) == "table" and potionState.potions[potionId]
		return math.max(0, math.floor(tonumber(type(entry) == "table" and entry.count or 0) or 0))
	end

	local function getEntryState(entry)
		if entry.Kind == "potion" then
			local owned = getPotionCount(entry.Id)
			local equipped = potionState.equippedPotionId == entry.Id and owned > 0
			local cooldownRemaining = math.max(0, (tonumber(potionState.cooldownEndsAt) or 0) - getServerNow())
			return owned, equipped, cooldownRemaining
		end

		local state = boostStates[entry.Id] or {}
		local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
		local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + boostTimeDelta
		local active = expiresAt > os.time()
		local remaining = active and math.max(0, expiresAt - os.time()) or 0
		return owned, active, remaining
	end

	local function updateBalanceLabel()
		balanceLabel.Text = "Coins: " .. formatNumber(coinBalance)
	end

	local refreshCards

	local function createButton(parentFrame, name, label, color)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.new(1, 0, 1, 0)
		button.BackgroundColor3 = color
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBlack
		button.Text = label
		button.TextColor3 = WHITE
		button.TextSize = px(13)
		button.TextWrapped = true
		button.Parent = parentFrame
		applyCorners(button, px(10))
		applyStroke(button, BLACK, 1.3, 0.2)
		addTextLimit(button, px(9), px(13))
		setButtonState(button, true, label, color)
		bindButtonHover(button)
		return button
	end

	local function createCard(entry, index)
		local iconColor = colorFromRGBArray(entry.IconColor, entry.Kind == "boost" and ACCENT_GOLD or ACCENT_BLUE)
		local baseBg = mixColor(CARD_BG, iconColor, 0.14)

		local card = Instance.new("Frame")
		card.Name = "PotionCard_" .. tostring(entry.Id)
		card.BackgroundColor3 = baseBg
		card.BorderSizePixel = 0
		card.LayoutOrder = index
		card.ClipsDescendants = true
		card.Parent = scroller
		applyCorners(card, px(14))
		local cardStroke = applyStroke(card, mixColor(iconColor, WHITE, 0.18), 1.4, 0.22)

		local cardGradient = Instance.new("UIGradient")
		cardGradient.Rotation = 90
		cardGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, brightenColor(baseBg, 0.06)),
			ColorSequenceKeypoint.new(1, CARD_BG_DARK),
		})
		cardGradient.Parent = card

		local iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconFrame"
		iconFrame.BackgroundColor3 = mixColor(CARD_BG_DARK, iconColor, 0.34)
		iconFrame.BorderSizePixel = 0
		iconFrame.Position = UDim2.new(0, px(12), 0, px(12))
		iconFrame.Size = UDim2.fromOffset(px(54), px(54))
		iconFrame.Parent = card
		applyCorners(iconFrame, px(12))
		applyStroke(iconFrame, iconColor, 1.2, 0.2)

		local iconImage = Instance.new("ImageLabel")
		iconImage.Name = "IconImage"
		iconImage.BackgroundTransparency = 1
		iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
		iconImage.Position = UDim2.fromScale(0.5, 0.5)
		iconImage.Size = UDim2.fromScale(0.74, 0.74)
		iconImage.ScaleType = Enum.ScaleType.Fit
		iconImage.Image = getIconImage(entry) or ""
		iconImage.Visible = iconImage.Image ~= ""
		iconImage.Parent = iconFrame

		local iconGlyph = Instance.new("TextLabel")
		iconGlyph.Name = "IconGlyph"
		iconGlyph.BackgroundTransparency = 1
		iconGlyph.Size = UDim2.fromScale(1, 1)
		iconGlyph.Font = Enum.Font.GothamBlack
		iconGlyph.Text = tostring(entry.IconGlyph or entry.BadgeText or "P")
		iconGlyph.TextColor3 = iconColor
		iconGlyph.TextScaled = true
		iconGlyph.Visible = not iconImage.Visible
		iconGlyph.Parent = iconFrame
		addTextLimit(iconGlyph, px(12), px(28))
		local glyphStroke = Instance.new("UIStroke")
		glyphStroke.Color = BLACK
		glyphStroke.Thickness = 1.2
		glyphStroke.Transparency = 0.18
		glyphStroke.Parent = iconGlyph

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, px(76), 0, px(10))
		nameLabel.Size = UDim2.new(1, -px(90), 0, px(26))
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = tostring(entry.DisplayName or entry.Id or "Potion")
		nameLabel.TextColor3 = WHITE
		nameLabel.TextSize = px(18)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card
		addTextLimit(nameLabel, px(12), px(18))

		local typeBadge = Instance.new("TextLabel")
		typeBadge.Name = "TypeBadge"
		typeBadge.BackgroundColor3 = mixColor(baseBg, BLACK, 0.24)
		typeBadge.Position = UDim2.new(0, px(76), 0, px(40))
		typeBadge.Size = UDim2.new(0, px(86), 0, px(20))
		typeBadge.Font = Enum.Font.GothamBold
		typeBadge.Text = entry.Kind == "boost" and "BOOST" or "POTION"
		typeBadge.TextColor3 = iconColor
		typeBadge.TextSize = px(11)
		typeBadge.Parent = card
		applyCorners(typeBadge, px(7))
		applyStroke(typeBadge, iconColor, 1, 0.44)
		addTextLimit(typeBadge, px(8), px(11))

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.new(0, px(12), 0, px(76))
		desc.Size = UDim2.new(1, -px(24), 0, px(44))
		desc.Font = Enum.Font.GothamMedium
		desc.Text = tostring(entry.Description or "")
		desc.TextColor3 = DIM_TEXT
		desc.TextSize = px(12)
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.Parent = card
		addTextLimit(desc, px(9), px(12))

		local detailLabel = Instance.new("TextLabel")
		detailLabel.Name = "DetailLabel"
		detailLabel.BackgroundTransparency = 1
		detailLabel.Position = UDim2.new(0, px(12), 0, px(124))
		detailLabel.Size = UDim2.new(1, -px(24), 0, px(18))
		detailLabel.Font = Enum.Font.GothamBold
		detailLabel.TextColor3 = iconColor
		detailLabel.TextSize = px(12)
		detailLabel.TextXAlignment = Enum.TextXAlignment.Left
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
		detailLabel.Text = entry.DetailText or ((entry.DurationSeconds and entry.DurationSeconds > 0) and ("Duration: " .. formatDuration(entry.DurationSeconds)) or "")
		detailLabel.Parent = card
		addTextLimit(detailLabel, px(9), px(12))

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.BackgroundTransparency = 1
		priceLabel.Position = UDim2.new(0, px(12), 1, -px(88))
		priceLabel.Size = UDim2.new(1, -px(24), 0, px(18))
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextColor3 = ACCENT_GOLD
		priceLabel.TextSize = px(12)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
		priceLabel.Parent = card
		addTextLimit(priceLabel, px(9), px(12))

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.BackgroundColor3 = mixColor(baseBg, BLACK, 0.28)
		statusLabel.Position = UDim2.new(0, px(12), 1, -px(66))
		statusLabel.Size = UDim2.new(1, -px(24), 0, px(24))
		statusLabel.Font = Enum.Font.GothamBold
		statusLabel.TextColor3 = WHITE
		statusLabel.TextSize = px(12)
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
		statusLabel.Parent = card
		applyCorners(statusLabel, px(8))
		local statusStroke = applyStroke(statusLabel, iconColor, 1, 0.42)
		addTextLimit(statusLabel, px(9), px(12))

		local buttonRow = Instance.new("Frame")
		buttonRow.Name = "ButtonRow"
		buttonRow.BackgroundTransparency = 1
		buttonRow.Position = UDim2.new(0, px(12), 1, -px(38))
		buttonRow.Size = UDim2.new(1, -px(24), 0, px(30))
		buttonRow.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, px(8))
		rowLayout.Parent = buttonRow

		local buyWrap = nil
		local buyButton = nil
		if entry.Kind == "boost" then
			buyWrap = Instance.new("Frame")
			buyWrap.Name = "BuyWrap"
			buyWrap.BackgroundTransparency = 1
			buyWrap.Size = UDim2.new(0.5, -px(4), 1, 0)
			buyWrap.Parent = buttonRow
			buyButton = createButton(buyWrap, "BuyButton", "BUY", BUTTON_SECONDARY)
		end

		local actionWrap = Instance.new("Frame")
		actionWrap.Name = "ActionWrap"
		actionWrap.BackgroundTransparency = 1
		actionWrap.Size = entry.Kind == "boost" and UDim2.new(0.5, -px(4), 1, 0) or UDim2.new(1, 0, 1, 0)
		actionWrap.Parent = buttonRow
		local actionButton = createButton(actionWrap, "ActionButton", entry.Kind == "boost" and "USE" or "EQUIP", BUTTON_PRIMARY)

		if buyButton then
			trackConn(buyButton.MouseButton1Click:Connect(function()
				if not buyButton.Active then
					return
				end
				local ok, success, message, states = pcall(function()
					return remotes.boostPurchaseRF:InvokeServer(entry.Id)
				end)
				if ok and success then
					ingestBoostStates(states)
					refreshCoinBalance()
					updateBalanceLabel()
					showToast((entry.DisplayName or "Potion") .. " purchased.", ACCENT_GREEN)
				else
					local reason = ok and message or "Purchase failed"
					showToast(tostring(reason), RED)
				end
				refreshCards()
			end))
		end

		trackConn(actionButton.MouseButton1Click:Connect(function()
			if not actionButton.Active then
				return
			end
			if entry.Kind == "potion" then
				local _, equipped = getEntryState(entry)
				local shouldEquip = not equipped
				local ok, success, message, state = pcall(function()
					return remotes.potionSetEquippedRF:InvokeServer(shouldEquip, entry.Id)
				end)
				if ok and type(state) == "table" then
					ingestPotionState(state)
				end
				if ok and success then
					showToast(shouldEquip and ((entry.DisplayName or "Potion") .. " equipped.") or "Potion unequipped.", ACCENT_BLUE)
				else
					showToast(tostring((ok and message) or "Equip failed"), RED)
				end
				refreshCards()
				return
			end

			local ok, success, message, states = pcall(function()
				return remotes.boostActivateRF:InvokeServer(entry.Id)
			end)
			if ok and success then
				ingestBoostStates(states)
				showToast((entry.DisplayName or "Potion") .. " activated.", ACCENT_GREEN)
			else
				if ok and type(states) == "table" then
					ingestBoostStates(states)
				end
				showToast(tostring((ok and message) or "Activation failed"), RED)
			end
			refreshCards()
		end))

		cardRefs[entry.Id] = {
			entry = entry,
			card = card,
			cardStroke = cardStroke,
			priceLabel = priceLabel,
			statusLabel = statusLabel,
			statusStroke = statusStroke,
			buyButton = buyButton,
			actionButton = actionButton,
			accent = iconColor,
			baseBg = baseBg,
		}
	end

	for index, entry in ipairs(entries) do
		createCard(entry, index)
	end

	refreshCards = function()
		for _, refs in pairs(cardRefs) do
			local entry = refs.entry
			local owned, active, remaining = getEntryState(entry)
			local accent = refs.accent

			refs.priceLabel.Visible = false
			if entry.Kind == "boost" then
				local price = math.max(0, math.floor(tonumber(entry.PriceCoins) or 0))
				refs.priceLabel.Visible = true
				refs.priceLabel.Text = string.format("Cost: %s Coins", formatNumber(price))
				local canAfford = price <= 0 or coinBalance >= price
				setButtonState(refs.buyButton, canAfford, canAfford and "BUY" or "NEED COINS", BUTTON_SECONDARY)

				if active then
					refs.statusLabel.Text = string.format("Active: %02d:%02d", math.floor(remaining / 60), remaining % 60)
					refs.statusLabel.TextColor3 = ACCENT_GREEN
					refs.statusStroke.Color = ACCENT_GREEN
					setButtonState(refs.actionButton, false, "ACTIVE", BUTTON_PRIMARY)
				elseif owned > 0 then
					refs.statusLabel.Text = "Owned: " .. tostring(owned)
					refs.statusLabel.TextColor3 = WHITE
					refs.statusStroke.Color = accent
					setButtonState(refs.actionButton, true, "USE", BUTTON_PRIMARY)
				else
					refs.statusLabel.Text = "Not Owned"
					refs.statusLabel.TextColor3 = MUTED_TEXT
					refs.statusStroke.Color = CARD_STROKE
					setButtonState(refs.actionButton, false, "USE", BUTTON_PRIMARY)
				end
			else
				if active and remaining > 0 then
					refs.statusLabel.Text = string.format("Equipped: cooldown %02d:%02d", math.floor(remaining / 60), remaining % 60)
					refs.statusLabel.TextColor3 = ACCENT_BLUE
					refs.statusStroke.Color = ACCENT_BLUE
					setButtonState(refs.actionButton, true, "UNEQUIP", BUTTON_PRIMARY)
				elseif active then
					refs.statusLabel.Text = "Equipped to Slot 4"
					refs.statusLabel.TextColor3 = WHITE
					refs.statusStroke.Color = accent
					setButtonState(refs.actionButton, true, "UNEQUIP", BUTTON_PRIMARY)
				elseif owned > 0 then
					refs.statusLabel.Text = "Owned: " .. tostring(owned)
					refs.statusLabel.TextColor3 = WHITE
					refs.statusStroke.Color = accent
					setButtonState(refs.actionButton, true, "EQUIP", BUTTON_PRIMARY)
				else
					refs.statusLabel.Text = "Not Owned"
					refs.statusLabel.TextColor3 = MUTED_TEXT
					refs.statusStroke.Color = CARD_STROKE
					setButtonState(refs.actionButton, false, "EQUIP", BUTTON_PRIMARY)
				end
			end

			refs.cardStroke.Color = active and ACCENT_GREEN or mixColor(accent, WHITE, 0.18)
			refs.cardStroke.Transparency = active and 0.08 or 0.22
		end
	end

	local function updateGridLayout()
		local width = math.max(1, scroller.AbsoluteSize.X - px(4))
		local gap = px(14)
		local minCell = compact and px(220) or px(230)
		local columns = math.max(1, math.floor((width + gap) / (minCell + gap)))
		columns = math.clamp(columns, 1, compact and 1 or 3)
		local cellWidth = math.max(px(210), math.floor((width - ((columns - 1) * gap)) / columns))
		gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
		gridLayout.CellSize = UDim2.fromOffset(cellWidth, px(compact and 250 or 240))
	end

	trackConn(scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridLayout))
	task.defer(updateGridLayout)

	trackConn(closeButton.MouseButton1Click:Connect(function()
		local callback = closeCallbacks[root]
		if type(callback) == "function" then
			callback()
		elseif parent:IsA("ScreenGui") then
			parent.Enabled = false
		else
			root.Visible = false
		end
	end))

	trackConn(remotes.coinsUpdatedRE.OnClientEvent:Connect(function(amount)
		if type(amount) == "number" then
			coinBalance = math.max(0, math.floor(amount))
			updateBalanceLabel()
			refreshCards()
		end
	end))

	trackConn(remotes.potionStateUpdatedRE.OnClientEvent:Connect(function(state)
		ingestPotionState(state)
		refreshCards()
	end))

	trackConn(remotes.boostStateUpdatedRE.OnClientEvent:Connect(function(states)
		ingestBoostStates(states)
		refreshCards()
	end))

	local lastTick = 0
	trackConn(RunService.Heartbeat:Connect(function()
		local now = os.time()
		if now == lastTick then
			return
		end
		lastTick = now
		refreshCards()
	end))

	trackConn(root.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			cleanupConnections()
		end
	end))

	refreshCards()
	return root
end

return PotionsStallUI