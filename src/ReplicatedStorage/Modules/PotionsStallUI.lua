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

local function readablePx(base, minimum)
	return math.max(px(base), minimum or base)
end

local function textPx(base, minimum, maximum)
	minimum = minimum or base
	maximum = maximum or base
	return math.clamp(px(base), minimum, maximum)
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

local function addTextOutline(label, transparency, thickness)
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = thickness or 1.1
	outline.Transparency = transparency or 0.45
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label
	return outline
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
local ItemIconRegistry = safeRequire(ReplicatedStorage, "ItemIconRegistry", 5)

local PANEL_BG = Color3.fromRGB(26, 31, 46)
local PANEL_BG_LIGHT = Color3.fromRGB(45, 57, 86)
local PANEL_EDGE = Color3.fromRGB(108, 130, 194)
local CONTENT_BG = Color3.fromRGB(18, 23, 37)
local CARD_BG = Color3.fromRGB(42, 50, 74)
local CARD_BG_DARK = Color3.fromRGB(29, 35, 54)
local CARD_STROKE = Color3.fromRGB(123, 144, 200)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local DIM_TEXT = Color3.fromRGB(232, 238, 248)
local MUTED_TEXT = Color3.fromRGB(196, 207, 230)
local ACCENT_GOLD = Color3.fromRGB(255, 208, 95)
local ACCENT_BLUE = Color3.fromRGB(91, 188, 255)
local ACCENT_GREEN = Color3.fromRGB(98, 229, 95)
local RED = Color3.fromRGB(208, 90, 76)
local BUTTON_PRIMARY = Color3.fromRGB(67, 170, 108)
local BUTTON_PRIMARY_DISABLED = Color3.fromRGB(63, 79, 80)
local BUTTON_SECONDARY = Color3.fromRGB(235, 167, 58)
local BUTTON_SECONDARY_DISABLED = Color3.fromRGB(104, 87, 55)

local CATEGORY_BATTLE = "Battle"
local CATEGORY_ELIXIR = "Elixir"
local POTION_SECTION_DEFS = {
	{
		Id = "Battle",
		Category = CATEGORY_BATTLE,
		Header = "BATTLE",
		Subtitle = "Equip these to slot 4 and use them during battle.",
		EmptyText = "No battle potions available.",
		Accent = Color3.fromRGB(239, 111, 91),
	},
	{
		Id = "Elixir",
		Category = CATEGORY_ELIXIR,
		Header = "ELIXIR",
		Subtitle = "Activate these for longer-lasting buffs.",
		EmptyText = "No elixirs available.",
		Accent = Color3.fromRGB(190, 139, 255),
	},
}

local function normalizePotionCategory(category, fallback)
	if category == CATEGORY_ELIXIR then
		return CATEGORY_ELIXIR
	end
	if category == CATEGORY_BATTLE then
		return CATEGORY_BATTLE
	end
	return fallback or CATEGORY_BATTLE
end

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

local function getItemIconData(def)
	if not ItemIconRegistry or type(ItemIconRegistry.Get) ~= "function" or type(def) ~= "table" then
		return nil
	end
	return ItemIconRegistry.Get(def.Id) or ItemIconRegistry.Get(def.IconKey)
end

local function getIconImage(def, iconData)
	if type(def) ~= "table" then
		return nil
	end
	if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then
		return def.IconAssetId
	end
	iconData = iconData or getItemIconData(def)
	if type(iconData) == "table" then
		if type(iconData.IconAssetId) == "string" and #iconData.IconAssetId > 0 then
			return iconData.IconAssetId
		end
		-- Procedurally-drawn potion/elixir bottles must not fall back to an
		-- AssetCodes image (e.g. IconKey = "Coin" on the 2x Coins elixir would
		-- otherwise resolve to a flat coin image and hide the generated bottle).
		if iconData.Kind == "PotionBottle" then
			return nil
		end
		if type(iconData.AssetKey) == "string" then
			local asset = getAsset(iconData.AssetKey)
			if asset then
				return asset
			end
		end
	end
	return getAsset(def.IconKey)
end

local function getEntryPrice(entry)
	return math.max(0, math.floor(tonumber(type(entry) == "table" and entry.PriceCoins or 0) or 0))
end

local function isEntryPurchasable(entry)
	return type(entry) == "table" and entry.Purchasable ~= false and getEntryPrice(entry) > 0
end

local function buildPotionBottleIcon(parent, iconData, fallbackColor)
	iconData = type(iconData) == "table" and iconData or {}

	local liquidColor = colorFromRGBArray(iconData.LiquidColor, fallbackColor or ACCENT_BLUE)
	local glassColor = colorFromRGBArray(iconData.GlassColor, mixColor(WHITE, liquidColor, 0.18))
	local strokeColor = colorFromRGBArray(iconData.StrokeColor, mixColor(liquidColor, BLACK, 0.45))
	local capColor = colorFromRGBArray(iconData.CapColor, strokeColor)
	local zBase = (parent and parent.ZIndex or 1) + 1

	local root = Instance.new("Frame")
	root.Name = "GeneratedPotionIcon"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.88, 0.88)
	root.BackgroundTransparency = 1
	root.ZIndex = zBase
	root.Parent = parent

	local isElixir = iconData.Shape == "elixir"

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, isElixir and 0.97 or 0.96)
	body.Size = isElixir and UDim2.fromScale(0.68, 0.56) or UDim2.fromScale(0.56, 0.62)
	body.BackgroundColor3 = glassColor
	body.BorderSizePixel = 0
	body.ZIndex = zBase + 1
	body.Parent = root
	applyCorners(body, px(9))
	if isElixir then
		for _, child in ipairs(body:GetChildren()) do
			if child:IsA("UICorner") then
				child.CornerRadius = UDim.new(1, 0)
			end
		end
	end
	applyStroke(body, strokeColor, 1.2, 0.08)

	local neck = Instance.new("Frame")
	neck.Name = "Neck"
	neck.AnchorPoint = Vector2.new(0.5, 1)
	neck.Position = UDim2.fromScale(0.5, 0.39)
	neck.Size = UDim2.fromScale(0.22, 0.24)
	neck.BackgroundColor3 = glassColor
	neck.BorderSizePixel = 0
	neck.ZIndex = zBase + 2
	neck.Parent = root
	applyCorners(neck, px(5))
	applyStroke(neck, strokeColor, 1, 0.12)

	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.Position = UDim2.fromScale(0.5, 0.08)
	cap.Size = UDim2.fromScale(0.34, 0.11)
	cap.BackgroundColor3 = capColor
	cap.BorderSizePixel = 0
	cap.ZIndex = zBase + 4
	cap.Parent = root
	applyCorners(cap, px(5))

	local liquid = Instance.new("Frame")
	liquid.Name = "Liquid"
	liquid.AnchorPoint = Vector2.new(0.5, 1)
	liquid.Position = UDim2.fromScale(0.5, 0.9)
	liquid.Size = UDim2.fromScale(0.44, 0.34)
	liquid.BackgroundColor3 = liquidColor
	liquid.BorderSizePixel = 0
	liquid.ZIndex = zBase + 3
	liquid.Parent = root
	applyCorners(liquid, px(7))

	local shine = Instance.new("Frame")
	shine.Name = "Highlight"
	shine.AnchorPoint = Vector2.new(0, 0)
	shine.Position = UDim2.fromScale(0.36, 0.38)
	shine.Size = UDim2.fromScale(0.09, 0.34)
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.32
	shine.BorderSizePixel = 0
	shine.Rotation = 14
	shine.ZIndex = zBase + 5
	shine.Parent = root
	applyCorners(shine, px(5))

	if iconData.Motif == "speed" then
		for index = 1, 3 do
			local streak = Instance.new("Frame")
			streak.Name = "SpeedStreak" .. tostring(index)
			streak.AnchorPoint = Vector2.new(0.5, 0.5)
			streak.Position = UDim2.fromScale(0.34 + (index * 0.11), 0.55 + ((index - 2) * 0.08))
			streak.Size = UDim2.fromScale(0.24 - (index * 0.025), 0.045)
			streak.BackgroundColor3 = WHITE
			streak.BackgroundTransparency = 0.08
			streak.BorderSizePixel = 0
			streak.Rotation = -16
			streak.ZIndex = zBase + 6
			streak.Parent = root
			applyCorners(streak, px(5))
		end
	elseif iconData.Motif == "health" then
		local plusH = Instance.new("Frame")
		plusH.Name = "PlusH"
		plusH.AnchorPoint = Vector2.new(0.5, 0.5)
		plusH.Position = UDim2.fromScale(0.5, 0.62)
		plusH.Size = UDim2.fromScale(0.25, 0.075)
		plusH.BackgroundColor3 = WHITE
		plusH.BorderSizePixel = 0
		plusH.ZIndex = zBase + 6
		plusH.Parent = root
		applyCorners(plusH, px(5))

		local plusV = Instance.new("Frame")
		plusV.Name = "PlusV"
		plusV.AnchorPoint = Vector2.new(0.5, 0.5)
		plusV.Position = UDim2.fromScale(0.5, 0.62)
		plusV.Size = UDim2.fromScale(0.075, 0.25)
		plusV.BackgroundColor3 = WHITE
		plusV.BorderSizePixel = 0
		plusV.ZIndex = zBase + 6
		plusV.Parent = root
		applyCorners(plusV, px(5))
	end

	return root
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
		potionPurchaseRF = potionsFolder:WaitForChild("PurchasePotion", 10),
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
	label.TextSize = textPx(22, 18, 22)
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
				Category = normalizePotionCategory(potionDef.Category, CATEGORY_BATTLE),
				Description = potionDef.Description,
				DetailText = potionDef.DetailText,
				DurationSeconds = potionDef.DurationSeconds,
				CooldownSeconds = potionDef.CooldownSeconds,
				PriceCoins = potionDef.PriceCoins,
				Purchasable = potionDef.Purchasable == true,
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
				Purchasable = boostDef.Purchasable ~= false,
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
	button.TextColor3 = enabled and WHITE or Color3.fromRGB(224, 232, 242)
	button.TextTransparency = enabled and 0 or 0.04
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
	title.TextSize = textPx(30, 24, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	addTextLimit(title, 24, 30)
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = BLACK
	titleStroke.Thickness = 1.6
	titleStroke.Transparency = 0.2
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
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

	local balanceIcon = Instance.new("ImageLabel")
	balanceIcon.Name = "CoinIcon"
	balanceIcon.BackgroundTransparency = 1
	balanceIcon.Position = UDim2.new(0, px(12), 0.5, -px(10))
	balanceIcon.Size = UDim2.fromOffset(px(20), px(20))
	balanceIcon.Image = getAsset("Coin") or ""
	balanceIcon.ScaleType = Enum.ScaleType.Fit
	balanceIcon.Parent = balancePill

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Position = UDim2.new(0, px(38), 0, 0)
	balanceLabel.Size = UDim2.new(1, -px(48), 1, 0)
	balanceLabel.Font = Enum.Font.GothamBlack
	balanceLabel.TextColor3 = ACCENT_GOLD
	balanceLabel.TextSize = textPx(18, 16, 18)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	balanceLabel.Text = formatNumber(coinBalance)
	balanceLabel.Parent = balancePill
	addTextLimit(balanceLabel, 16, 18)
	addTextOutline(balanceLabel, 0.48, 1)

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
	closeButton.TextSize = textPx(22, 18, 22)
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

	local scrollerLayout = Instance.new("UIListLayout")
	scrollerLayout.FillDirection = Enum.FillDirection.Vertical
	scrollerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollerLayout.Padding = UDim.new(0, px(18))
	scrollerLayout.Parent = scroller

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, px(2))
	gridPad.PaddingLeft = UDim.new(0, px(2))
	gridPad.PaddingRight = UDim.new(0, px(2))
	gridPad.PaddingBottom = UDim.new(0, px(16))
	gridPad.Parent = scroller

	local cardRefs = {}
	local sectionRecords = {}
	local entriesByCategory = {}
	for _, sectionDef in ipairs(POTION_SECTION_DEFS) do
		entriesByCategory[sectionDef.Category] = {}
	end
	for _, entry in ipairs(entries) do
		local fallback = entry.Kind == "boost" and CATEGORY_ELIXIR or CATEGORY_BATTLE
		entry.Category = normalizePotionCategory(entry.Category, fallback)
		local group = entriesByCategory[entry.Category]
		if group then
			table.insert(group, entry)
		end
	end

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
		toast.TextSize = textPx(17, 15, 17)
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
		balanceLabel.Text = formatNumber(coinBalance)
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
		button.TextSize = textPx(16, 15, 16)
		button.TextWrapped = true
		button.Parent = parentFrame
		applyCorners(button, px(10))
		applyStroke(button, BLACK, 1.3, 0.2)
		addTextLimit(button, 15, 16)
		addTextOutline(button, 0.42, 1)
		setButtonState(button, true, label, color)
		bindButtonHover(button)
		return button
	end

	local function createPotionSection(sectionDef, sectionIndex, itemCount)
		local accent = sectionDef.Accent or ACCENT_GOLD

		local sectionFrame = Instance.new("Frame")
		sectionFrame.Name = tostring(sectionDef.Id or sectionDef.Category) .. "Section"
		sectionFrame.BackgroundTransparency = 1
		sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
		sectionFrame.Size = UDim2.new(1, 0, 0, 0)
		sectionFrame.LayoutOrder = sectionIndex
		sectionFrame.Parent = scroller

		local sectionLayout = Instance.new("UIListLayout")
		sectionLayout.FillDirection = Enum.FillDirection.Vertical
		sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
		sectionLayout.Padding = UDim.new(0, px(10))
		sectionLayout.Parent = sectionFrame

		local header = Instance.new("Frame")
		header.Name = "SectionHeader"
		header.BackgroundColor3 = mixColor(CARD_BG_DARK, accent, 0.14)
		header.BorderSizePixel = 0
		header.Size = UDim2.new(1, 0, 0, readablePx(70, 68))
		header.LayoutOrder = 1
		header.Parent = sectionFrame
		applyCorners(header, px(14))
		applyStroke(header, mixColor(accent, WHITE, 0.1), 1.1, 0.3)

		local accentBar = Instance.new("Frame")
		accentBar.Name = "AccentBar"
		accentBar.BackgroundColor3 = accent
		accentBar.BorderSizePixel = 0
		accentBar.Position = UDim2.new(0, 0, 0, 0)
		accentBar.Size = UDim2.new(0, px(5), 1, 0)
		accentBar.Parent = header
		applyCorners(accentBar, px(12))

		local headerTitle = Instance.new("TextLabel")
		headerTitle.Name = "Title"
		headerTitle.BackgroundTransparency = 1
		headerTitle.Position = UDim2.new(0, readablePx(17, 17), 0, readablePx(7, 7))
		headerTitle.Size = UDim2.new(1, -readablePx(34, 34), 0, readablePx(31, 30))
		headerTitle.Font = Enum.Font.FredokaOne
		headerTitle.Text = tostring(sectionDef.Header or sectionDef.Category or "POTIONS")
		headerTitle.TextColor3 = WHITE
		headerTitle.TextSize = textPx(26, 24, 26)
		headerTitle.TextXAlignment = Enum.TextXAlignment.Left
		headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
		headerTitle.Parent = header
		addTextLimit(headerTitle, 24, 26)
		addTextOutline(headerTitle, 0.38, 1.2)

		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.new(0, readablePx(17, 17), 0, readablePx(40, 40))
		subtitle.Size = UDim2.new(1, -readablePx(34, 34), 0, readablePx(23, 22))
		subtitle.Font = Enum.Font.GothamBold
		subtitle.Text = tostring(sectionDef.Subtitle or "")
		subtitle.TextColor3 = Color3.fromRGB(224, 233, 248)
		subtitle.TextSize = textPx(15, 14, 15)
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd
		subtitle.Parent = header
		addTextLimit(subtitle, 14, 15)

		local grid = Instance.new("Frame")
		grid.Name = tostring(sectionDef.Id or sectionDef.Category) .. "Grid"
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, px(1))
		grid.LayoutOrder = 2
		grid.Visible = itemCount > 0
		grid.Parent = sectionFrame

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		gridLayout.CellPadding = UDim2.fromOffset(px(14), px(14))
		gridLayout.Parent = grid

		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyMessage"
		emptyLabel.BackgroundColor3 = mixColor(CONTENT_BG, accent, 0.08)
		emptyLabel.BorderSizePixel = 0
		emptyLabel.Size = UDim2.new(1, 0, 0, readablePx(58, 56))
		emptyLabel.LayoutOrder = 3
		emptyLabel.Font = Enum.Font.GothamBold
		emptyLabel.Text = tostring(sectionDef.EmptyText or "No items available.")
		emptyLabel.TextColor3 = MUTED_TEXT
		emptyLabel.TextSize = textPx(15, 14, 15)
		emptyLabel.TextWrapped = true
		emptyLabel.Visible = itemCount <= 0
		emptyLabel.Parent = sectionFrame
		applyCorners(emptyLabel, px(12))
		applyStroke(emptyLabel, CARD_STROKE, 1, 0.48)
		addTextLimit(emptyLabel, 14, 15)
		addTextOutline(emptyLabel, 0.62, 0.8)

		local record = {
			grid = grid,
			layout = gridLayout,
			empty = emptyLabel,
			count = itemCount,
		}
		table.insert(sectionRecords, record)
		return record
	end

	local function createCard(entry, index, parentFrame)
		local iconData = getItemIconData(entry)
		local iconColor = colorFromRGBArray(entry.IconColor, entry.Kind == "boost" and ACCENT_GOLD or ACCENT_BLUE)
		if type(iconData) == "table" then
			iconColor = colorFromRGBArray(iconData.IconColor or iconData.LiquidColor, iconColor)
		end
		local baseBg = mixColor(CARD_BG, iconColor, 0.14)

		local card = Instance.new("Frame")
		card.Name = "PotionCard_" .. tostring(entry.Id)
		card.BackgroundColor3 = baseBg
		card.BorderSizePixel = 0
		card.LayoutOrder = index
		card.ClipsDescendants = true
		card.Parent = parentFrame or scroller
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
		iconFrame.Position = UDim2.new(0, readablePx(12, 12), 0, readablePx(12, 12))
		iconFrame.Size = UDim2.fromOffset(readablePx(58, 54), readablePx(58, 54))
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
		iconImage.Image = getIconImage(entry, iconData) or ""
		iconImage.Visible = iconImage.Image ~= ""
		iconImage.Parent = iconFrame

		local generatedIcon = nil
		if not iconImage.Visible and type(iconData) == "table" and iconData.Kind == "PotionBottle" then
			generatedIcon = buildPotionBottleIcon(iconFrame, iconData, iconColor)
		end

		local iconGlyph = Instance.new("TextLabel")
		iconGlyph.Name = "IconGlyph"
		iconGlyph.BackgroundTransparency = 1
		iconGlyph.Size = UDim2.fromScale(1, 1)
		iconGlyph.Font = Enum.Font.GothamBlack
		local glyphText = type(iconData) == "table" and iconData.Glyph or nil
		if type(glyphText) ~= "string" or glyphText == "" then
			glyphText = entry.IconGlyph or entry.BadgeText
		end
		if type(glyphText) ~= "string" or glyphText == "" then
			glyphText = entry.Kind == "boost" and "!" or "P"
		end
		iconGlyph.Text = tostring(glyphText)
		iconGlyph.TextColor3 = iconColor
		iconGlyph.TextScaled = true
		iconGlyph.Visible = not iconImage.Visible and generatedIcon == nil
		iconGlyph.Parent = iconFrame
		addTextLimit(iconGlyph, 14, 30)
		local glyphStroke = Instance.new("UIStroke")
		glyphStroke.Color = BLACK
		glyphStroke.Thickness = 1.2
		glyphStroke.Transparency = 0.18
		glyphStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glyphStroke.Parent = iconGlyph

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, readablePx(82, 76), 0, readablePx(11, 10))
		nameLabel.Size = UDim2.new(1, -readablePx(96, 88), 0, readablePx(31, 30))
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = tostring(entry.DisplayName or entry.Id or "Potion")
		nameLabel.TextColor3 = WHITE
		nameLabel.TextSize = textPx(21, 19, 21)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card
		addTextLimit(nameLabel, 19, 21)
		addTextOutline(nameLabel, 0.48, 1.1)

		local typeBadge = Instance.new("TextLabel")
		typeBadge.Name = "TypeBadge"
		typeBadge.BackgroundColor3 = mixColor(baseBg, BLACK, 0.24)
		typeBadge.Position = UDim2.new(0, readablePx(82, 76), 0, readablePx(44, 41))
		typeBadge.Size = UDim2.new(0, readablePx(100, 94), 0, readablePx(23, 22))
		typeBadge.Font = Enum.Font.GothamBold
		typeBadge.Text = entry.Kind == "boost" and "BOOST" or "POTION"
		typeBadge.TextColor3 = mixColor(iconColor, WHITE, 0.2)
		typeBadge.TextSize = textPx(13, 12, 13)
		typeBadge.Parent = card
		applyCorners(typeBadge, px(7))
		applyStroke(typeBadge, iconColor, 1, 0.44)
		addTextLimit(typeBadge, 12, 13)
		addTextOutline(typeBadge, 0.55, 0.8)

		local desc = Instance.new("TextLabel")
		desc.Name = "Description"
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.new(0, readablePx(12, 12), 0, readablePx(82, 78))
		desc.Size = UDim2.new(1, -readablePx(24, 24), 0, readablePx(64, 60))
		desc.Font = Enum.Font.GothamMedium
		desc.Text = tostring(entry.Description or "")
		desc.TextColor3 = DIM_TEXT
		desc.TextSize = textPx(16, 15, 16)
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.Parent = card
		addTextLimit(desc, 15, 16)

		local detailLabel = Instance.new("TextLabel")
		detailLabel.Name = "DetailLabel"
		detailLabel.BackgroundTransparency = 1
		detailLabel.Position = UDim2.new(0, readablePx(12, 12), 0, readablePx(154, 148))
		detailLabel.Size = UDim2.new(1, -readablePx(24, 24), 0, readablePx(24, 22))
		detailLabel.Font = Enum.Font.GothamBold
		detailLabel.TextColor3 = brightenColor(iconColor, 0.08)
		detailLabel.TextSize = textPx(16, 15, 16)
		detailLabel.TextXAlignment = Enum.TextXAlignment.Left
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
		detailLabel.Text = entry.DetailText or ((entry.DurationSeconds and entry.DurationSeconds > 0) and ("Duration: " .. formatDuration(entry.DurationSeconds)) or "")
		detailLabel.Parent = card
		addTextLimit(detailLabel, 15, 16)
		addTextOutline(detailLabel, 0.56, 0.9)

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.BackgroundTransparency = 1
		priceLabel.Position = UDim2.new(0, readablePx(12, 12), 1, -readablePx(104, 100))
		priceLabel.Size = UDim2.new(1, -readablePx(24, 24), 0, readablePx(24, 22))
		priceLabel.Font = Enum.Font.GothamBlack
		priceLabel.TextColor3 = ACCENT_GOLD
		priceLabel.TextSize = textPx(16, 15, 16)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.TextTruncate = Enum.TextTruncate.AtEnd
		priceLabel.Parent = card
		addTextLimit(priceLabel, 15, 16)
		addTextOutline(priceLabel, 0.52, 0.9)

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.BackgroundColor3 = mixColor(baseBg, BLACK, 0.28)
		statusLabel.Position = UDim2.new(0, readablePx(12, 12), 1, -readablePx(76, 74))
		statusLabel.Size = UDim2.new(1, -readablePx(24, 24), 0, readablePx(30, 28))
		statusLabel.Font = Enum.Font.GothamBlack
		statusLabel.TextColor3 = WHITE
		statusLabel.TextSize = textPx(16, 15, 16)
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.TextYAlignment = Enum.TextYAlignment.Center
		statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
		statusLabel.Parent = card
		applyCorners(statusLabel, px(8))
		local statusStroke = applyStroke(statusLabel, iconColor, 1, 0.42)
		addTextLimit(statusLabel, 15, 16)
		addTextOutline(statusLabel, 0.4, 1)

		local buttonRow = Instance.new("Frame")
		buttonRow.Name = "ButtonRow"
		buttonRow.BackgroundTransparency = 1
		buttonRow.Position = UDim2.new(0, readablePx(12, 12), 1, -readablePx(40, 40))
		buttonRow.Size = UDim2.new(1, -readablePx(24, 24), 0, readablePx(34, 34))
		buttonRow.Parent = card

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, px(8))
		rowLayout.Parent = buttonRow

		local purchasable = isEntryPurchasable(entry)
		local buyWrap = nil
		local buyButton = nil
		if purchasable then
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
		actionWrap.Size = purchasable and UDim2.new(0.5, -px(4), 1, 0) or UDim2.new(1, 0, 1, 0)
		actionWrap.Parent = buttonRow
		local actionButton = createButton(actionWrap, "ActionButton", entry.Kind == "boost" and "USE" or "EQUIP", BUTTON_PRIMARY)

		if buyButton then
			trackConn(buyButton.MouseButton1Click:Connect(function()
				if not buyButton.Active then
					return
				end
				if entry.Kind == "potion" then
					local ok, success, message, state = pcall(function()
						return remotes.potionPurchaseRF:InvokeServer(entry.Id)
					end)
					if ok and type(state) == "table" then
						ingestPotionState(state)
					end
					if ok and success then
						refreshCoinBalance()
						updateBalanceLabel()
						showToast((entry.DisplayName or "Potion") .. " purchased.", ACCENT_GREEN)
					else
						local reason = ok and message or "Purchase failed"
						showToast(tostring(reason), RED)
					end
					refreshCards()
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

	for sectionIndex, sectionDef in ipairs(POTION_SECTION_DEFS) do
		local sectionEntries = entriesByCategory[sectionDef.Category] or {}
		local sectionRecord = createPotionSection(sectionDef, sectionIndex, #sectionEntries)
		for index, entry in ipairs(sectionEntries) do
			createCard(entry, index, sectionRecord.grid)
		end
	end

	refreshCards = function()
		for _, refs in pairs(cardRefs) do
			local entry = refs.entry
			local owned, active, remaining = getEntryState(entry)
			local accent = refs.accent
			local price = getEntryPrice(entry)
			local canAfford = price <= 0 or coinBalance >= price

			refs.priceLabel.Visible = refs.buyButton ~= nil
			if refs.buyButton then
				refs.priceLabel.Text = string.format("Cost: %s Coins", formatNumber(price))
				setButtonState(refs.buyButton, canAfford, canAfford and "BUY" or "NEED COINS", BUTTON_SECONDARY)
			end

			if entry.Kind == "boost" then
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
				if active then
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
		local minCell = compact and readablePx(260, 260) or readablePx(280, 280)
		local columns = math.max(1, math.floor((width + gap) / (minCell + gap)))
		columns = math.clamp(columns, 1, compact and 1 or 4)
		local minCellWidth = math.min(readablePx(248, 248), width)
		local cellWidth = math.max(minCellWidth, math.floor((width - ((columns - 1) * gap)) / columns))
		local cellHeight = compact and readablePx(310, 300) or readablePx(292, 286)

		for _, record in ipairs(sectionRecords) do
			local count = math.max(0, tonumber(record.count) or 0)
			record.layout.CellPadding = UDim2.fromOffset(gap, gap)
			record.layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
			record.grid.Visible = count > 0
			if record.empty then
				record.empty.Visible = count <= 0
			end
			local rows = count > 0 and math.ceil(count / columns) or 0
			local height = rows > 0 and ((rows * cellHeight) + (math.max(0, rows - 1) * gap)) or px(1)
			record.grid.Size = UDim2.new(1, 0, 0, height)
		end
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