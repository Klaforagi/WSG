--------------------------------------------------------------------------------
-- SkinsStallUI.lua
-- Compatibility module for the world Cosmetics podium/menu.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function formatCompactPrice(value)
	local n = math.floor(tonumber(value) or 0)
	if n >= 10000 and n % 1000 == 0 then
		return string.format("%dK", math.floor(n / 1000))
	end
	return formatNumber(n)
end

local function safeRequire(parent, moduleName, timeout)
	timeout = timeout or 5
	local mod = parent:WaitForChild(moduleName, timeout)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			return result
		end
		warn("[CosmeticsStallUI] Failed to require", moduleName, ":", tostring(result))
	end
	return nil
end

local modulesFolder = ReplicatedStorage:WaitForChild("Modules", 10)
local CosmeticsCatalog = safeRequire(ReplicatedStorage, "CosmeticsCatalog", 10)
local SkinDefs = safeRequire(ReplicatedStorage, "SkinDefinitions", 10)
local AssetCodes = safeRequire(ReplicatedStorage, "AssetCodes", 5)
local SkinPreview = modulesFolder and safeRequire(modulesFolder, "StandaloneSkinPreview", 10)

local PANEL_BG = Color3.fromRGB(26, 31, 46)
local PANEL_BG_LIGHT = Color3.fromRGB(45, 57, 86)
local PANEL_EDGE = Color3.fromRGB(108, 130, 194)
local CARD_BAND = Color3.fromRGB(54, 67, 99)
local CARD_BAND_SELECTED = Color3.fromRGB(45, 128, 94)
local CARD_LOCKED = Color3.fromRGB(72, 82, 109)
local CARD_SUBTEXT = Color3.fromRGB(222, 228, 244)
local ACCENT_BLUE = Color3.fromRGB(91, 188, 255)
local ACCENT_GOLD = Color3.fromRGB(255, 208, 95)
local CONTENT_BG = Color3.fromRGB(18, 23, 37)
local BUTTON_PRIMARY = Color3.fromRGB(67, 170, 108)
local BUTTON_PRIMARY_DISABLED = Color3.fromRGB(63, 79, 80)
local BUTTON_SECONDARY = Color3.fromRGB(235, 167, 58)
local BUTTON_SECONDARY_DISABLED = Color3.fromRGB(104, 87, 55)
local BUTTON_DANGER = Color3.fromRGB(198, 96, 84)
local TOGGLE_ON = Color3.fromRGB(63, 193, 109)
local TOGGLE_OFF = Color3.fromRGB(61, 72, 96)
local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local RED = Color3.fromRGB(208, 90, 76)

local CARD_THEMES = {
	{ Color3.fromRGB(138, 239, 76), Color3.fromRGB(89, 219, 71) },
	{ Color3.fromRGB(104, 212, 255), Color3.fromRGB(87, 172, 255) },
	{ Color3.fromRGB(255, 226, 93), Color3.fromRGB(255, 186, 72) },
	{ Color3.fromRGB(216, 154, 255), Color3.fromRGB(176, 118, 255) },
}

local QUICK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local remotes = nil
local activeConnections = {}
local closeCallbacks = setmetatable({}, { __mode = "k" })

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

local function getAsset(key)
	if AssetCodes and type(AssetCodes.Get) == "function" and key then
		local asset = AssetCodes.Get(key)
		if type(asset) == "string" and #asset > 0 then
			return asset
		end
	end
	return nil
end

local function ensureRemotes()
	if remotes then
		return true
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return false
	end

	local skinsFolder = remotesFolder:WaitForChild("Skins", 10)
	local effectsFolder = remotesFolder:WaitForChild("Effects", 10)
	local emotesFolder = remotesFolder:WaitForChild("Emotes", 10)
	if not (skinsFolder and effectsFolder and emotesFolder) then
		return false
	end

	remotes = {
		getCoinsRF = ReplicatedStorage:WaitForChild("GetCoins", 10),
		coinsUpdatedRE = ReplicatedStorage:WaitForChild("CoinsUpdated", 10),
		getPlayerSettingsRF = ReplicatedStorage:WaitForChild("GetPlayerSettings", 10),
		updatePlayerSettingRE = ReplicatedStorage:WaitForChild("UpdatePlayerSetting", 10),

		getOwnedSkinsRF = skinsFolder:WaitForChild("GetOwnedSkins", 10),
		purchaseSkinRF = skinsFolder:WaitForChild("PurchaseSkin", 10),
		equipSkinRE = skinsFolder:WaitForChild("EquipSkin", 10),
		getEquippedSkinRF = skinsFolder:WaitForChild("GetEquippedSkin", 10),
		equippedSkinChangedRE = skinsFolder:WaitForChild("EquippedSkinChanged", 10),
		ownedSkinsChangedRE = skinsFolder:WaitForChild("OwnedSkinsChanged", 10),

		getOwnedEffectsRF = effectsFolder:WaitForChild("GetOwnedEffects", 10),
		purchaseEffectRF = effectsFolder:WaitForChild("PurchaseEffect", 10),
		equipEffectRE = effectsFolder:WaitForChild("EquipEffect", 10),
		getEquippedEffectsRF = effectsFolder:WaitForChild("GetEquippedEffects", 10),
		equippedEffectsChangedRE = effectsFolder:WaitForChild("EquippedEffectsChanged", 10),

		getOwnedEmotesRF = emotesFolder:WaitForChild("GetOwnedEmotes", 10),
		purchaseEmoteRF = emotesFolder:WaitForChild("PurchaseEmote", 10),
		equipEmoteRE = emotesFolder:WaitForChild("EquipEmote", 10),
		unequipEmoteRE = emotesFolder:WaitForChild("UnequipEmote", 10),
		getEquippedEmotesRF = emotesFolder:WaitForChild("GetEquippedEmotes", 10),
		equippedEmotesChangedRE = emotesFolder:WaitForChild("EquippedEmotesChanged", 10),
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

local function makeIdSet(list, defaults)
	local owned = {}
	if type(defaults) == "table" then
		for id, value in pairs(defaults) do
			owned[id] = value == true
		end
	end
	if type(list) == "table" then
		for _, itemId in ipairs(list) do
			owned[itemId] = true
		end
	end
	return owned
end

local function invokeRemote(remote, ...)
	if not remote then
		return false, nil, nil, nil
	end
	local args = table.pack(...)
	local ok, resultA, resultB, resultC = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok then
		return true, resultA, resultB, resultC
	end
	warn("[CosmeticsStallUI] Remote invoke failed:", remote.Name, tostring(resultA))
	return false, nil, nil, nil
end

local function setButtonState(button, enabled, color)
	button.Active = true
	button.AutoButtonColor = false
	button.BackgroundColor3 = enabled and color or (color == BUTTON_PRIMARY and BUTTON_PRIMARY_DISABLED or BUTTON_SECONDARY_DISABLED)
	button.TextTransparency = enabled and 0 or 0.18
	button.BackgroundTransparency = enabled and 0 or 0.12
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = enabled and 0.18 or 0.45
	end
	button:SetAttribute("EnabledState", enabled)
	button:SetAttribute("BaseColorR", color.R)
	button:SetAttribute("BaseColorG", color.G)
	button:SetAttribute("BaseColorB", color.B)
	button:SetAttribute("DisabledColorR", button.BackgroundColor3.R)
	button:SetAttribute("DisabledColorG", button.BackgroundColor3.G)
	button:SetAttribute("DisabledColorB", button.BackgroundColor3.B)
	button.TextColor3 = WHITE
	button.Modal = false
	button.Selectable = true
	button.ClipsDescendants = true
	button.ZIndex = 6
end

local function createPriceButtonContent(button, iconAsset)
	button.Text = ""

	local content = Instance.new("Frame")
	content.Name = "PriceContent"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.new(1, -px(14), 1, -px(8))
	content.ZIndex = 7
	content.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, px(6))
	layout.Parent = content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(px(20), px(20))
	icon.Image = iconAsset or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 7
	icon.Parent = content

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.Text = ""
	label.TextColor3 = WHITE
	label.TextSize = px(17)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 7
	label.Parent = content
	local labelLimit = Instance.new("UITextSizeConstraint")
	labelLimit.MinTextSize = px(10)
	labelLimit.MaxTextSize = px(17)
	labelLimit.Parent = label

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.BackgroundTransparency = 1
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.new(1, -px(12), 1, -px(8))
	fallback.Font = Enum.Font.GothamBlack
	fallback.Text = ""
	fallback.TextColor3 = WHITE
	fallback.TextSize = px(15)
	fallback.TextScaled = true
	fallback.Visible = false
	fallback.ZIndex = 7
	fallback.Parent = button
	local fallbackLimit = Instance.new("UITextSizeConstraint")
	fallbackLimit.MinTextSize = px(10)
	fallbackLimit.MaxTextSize = px(15)
	fallbackLimit.Parent = fallback

	return {
		content = content,
		icon = icon,
		label = label,
		fallback = fallback,
	}
end

local function syncPriceButtonContent(parts, text, enabled, iconAsset, showIcon)
	if not parts then
		return
	end

	local transparency = enabled and 0 or 0.18
	showIcon = showIcon == true and type(iconAsset) == "string" and #iconAsset > 0 and type(text) == "string" and #text > 0

	parts.content.Visible = showIcon
	parts.icon.Visible = showIcon
	parts.label.Text = showIcon and text or ""
	parts.label.TextTransparency = transparency
	parts.icon.Image = iconAsset or ""
	parts.icon.ImageTransparency = transparency

	parts.fallback.Visible = not showIcon and type(text) == "string" and #text > 0
	parts.fallback.Text = parts.fallback.Visible and text or ""
	parts.fallback.TextTransparency = transparency
end

local function bindHover(button)
	trackConn(button.MouseEnter:Connect(function()
		if not button:GetAttribute("EnabledState") then
			return
		end
		local baseColor = Color3.new(
			button:GetAttribute("BaseColorR") or button.BackgroundColor3.R,
			button:GetAttribute("BaseColorG") or button.BackgroundColor3.G,
			button:GetAttribute("BaseColorB") or button.BackgroundColor3.B
		)
		TweenService:Create(button, QUICK_TWEEN, { BackgroundColor3 = baseColor:Lerp(WHITE, 0.12) }):Play()
	end))
	trackConn(button.MouseLeave:Connect(function()
		local color
		if button:GetAttribute("EnabledState") then
			color = Color3.new(
				button:GetAttribute("BaseColorR") or button.BackgroundColor3.R,
				button:GetAttribute("BaseColorG") or button.BackgroundColor3.G,
				button:GetAttribute("BaseColorB") or button.BackgroundColor3.B
			)
		else
			color = Color3.new(
				button:GetAttribute("DisabledColorR") or button.BackgroundColor3.R,
				button:GetAttribute("DisabledColorG") or button.BackgroundColor3.G,
				button:GetAttribute("DisabledColorB") or button.BackgroundColor3.B
			)
		end
		TweenService:Create(button, QUICK_TWEEN, { BackgroundColor3 = color }):Play()
	end))
end

local function makeKey(category, itemId)
	return tostring(category) .. ":" .. tostring(itemId)
end

local function getInitials(text)
	text = tostring(text or "")
	local initials = ""
	for word in text:gmatch("%w+") do
		initials ..= word:sub(1, 1):upper()
		if #initials >= 3 then
			break
		end
	end
	if #initials == 0 then
		return "?"
	end
	return initials
end

local SkinsStallUI = {}

function SkinsStallUI.SetCloseCallback(root, callback)
	if root then
		closeCallbacks[root] = callback
	end
end

function SkinsStallUI.Create(parent, options)
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

	if not CosmeticsCatalog then
		return createErrorLabel(parent, "Cosmetics unavailable: CosmeticsCatalog missing.")
	end
	if not SkinDefs then
		return createErrorLabel(parent, "Cosmetics unavailable: SkinDefinitions missing.")
	end
	if not SkinPreview then
		return createErrorLabel(parent, "Cosmetics unavailable: StandaloneSkinPreview missing.")
	end
	if not ensureRemotes() then
		return createErrorLabel(parent, "Cosmetics unavailable: required remotes not found.")
	end

	local sections = CosmeticsCatalog.GetSections()
	local itemByKey = {}
	local firstItem = nil
	for _, section in ipairs(sections) do
		for _, item in ipairs(section.Items or {}) do
			itemByKey[makeKey(item.Category, item.Id)] = item
			if not firstItem then
				firstItem = item
			end
		end
	end
	if not firstItem then
		return createErrorLabel(parent, "No cosmetics are configured for this menu.")
	end

	local _, ownedSkinList = invokeRemote(remotes.getOwnedSkinsRF)
	local _, equippedSkinId = invokeRemote(remotes.getEquippedSkinRF)
	local _, ownedEffectList = invokeRemote(remotes.getOwnedEffectsRF)
	local _, equippedEffects = invokeRemote(remotes.getEquippedEffectsRF)
	local _, ownedEmoteList = invokeRemote(remotes.getOwnedEmotesRF)
	local _, equippedEmotes = invokeRemote(remotes.getEquippedEmotesRF)
	local _, settings = invokeRemote(remotes.getPlayerSettingsRF)
	local _, initialCoins = invokeRemote(remotes.getCoinsRF)

	local ownedSkins = makeIdSet(ownedSkinList, { Default = true })
	local ownedEffects = makeIdSet(ownedEffectList, { DefaultTrail = true })
	local ownedEmotes = makeIdSet(ownedEmoteList)
	local equippedTrailId = "DefaultTrail"
	if type(equippedEffects) == "table" and type(equippedEffects.DashTrail) == "string" and equippedEffects.DashTrail ~= "" then
		equippedTrailId = equippedEffects.DashTrail
	end

	local emoteSlotCount = CosmeticsCatalog.GetSlotCount()
	local equippedEmoteSlots = {}
	local function setEquippedEmotesFromList(list)
		equippedEmoteSlots = {}
		if type(list) ~= "table" then
			return
		end
		for _, entry in ipairs(list) do
			if type(entry) == "table" then
				local slot = tonumber(entry.Slot)
				local emoteId = entry.Id
				if slot and slot >= 1 and slot <= emoteSlotCount and type(emoteId) == "string" and emoteId ~= "" then
					equippedEmoteSlots[math.floor(slot)] = emoteId
				end
			end
		end
	end
	setEquippedEmotesFromList(equippedEmotes)

	local playerSettings = type(settings) == "table" and settings or {}
	local showHelm = playerSettings.ShowHelm
	if showHelm == nil then
		showHelm = true
	end
	local coinBalance = math.max(0, math.floor(tonumber(initialCoins) or 0))

	local selectedCategory = firstItem.Category
	local selectedId = firstItem.Id
	if type(equippedSkinId) == "string" and equippedSkinId ~= "" then
		local equippedSkinItem = itemByKey[makeKey("Skin", equippedSkinId)]
		if equippedSkinItem then
			selectedCategory = "Skin"
			selectedId = equippedSkinId
		end
	end

	local root = Instance.new("Frame")
	root.Name = "SkinsStallRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = parent
	closeCallbacks[root] = options.onClose

	local viewportSize = getViewportSize()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromScale(0.72, 0.84)
	panel.BackgroundColor3 = PANEL_BG
	panel.BorderSizePixel = 0
	panel.Parent = root
	applyCorners(panel, px(28))
	applyStroke(panel, PANEL_EDGE, 2, 0.1)
	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(320, 300)
	panelConstraint.MaxSize = Vector2.new(math.max(360, math.floor(viewportSize.X * 0.96)), math.max(340, math.floor(viewportSize.Y * 0.94)))
	panelConstraint.Parent = panel

	local function applyResponsivePanelLayout()
		local vp = getViewportSize()
		if vp.X < vp.Y then
			panel.Size = UDim2.fromScale(0.96, 0.92)
			panel.Position = UDim2.fromScale(0.5, 0.52)
		else
			panel.Size = UDim2.fromScale(0.72, 0.84)
			panel.Position = UDim2.fromScale(0.5, 0.52)
		end
		panelConstraint.MaxSize = Vector2.new(
			math.max(360, math.floor(vp.X * 0.96)),
			math.max(340, math.floor(vp.Y * 0.94))
		)
	end

	local cameraViewportConn = nil
	local function bindViewportListener()
		if cameraViewportConn then
			pcall(function()
				cameraViewportConn:Disconnect()
			end)
			cameraViewportConn = nil
		end

		local camera = Workspace.CurrentCamera
		if camera then
			cameraViewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsivePanelLayout)
			trackConn(cameraViewportConn)
		end
	end

	trackConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewportListener()
		applyResponsivePanelLayout()
	end))
	bindViewportListener()
	task.defer(applyResponsivePanelLayout)

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
	title.Size = UDim2.new(1, -px(230), 1, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "COSMETICS"
	title.TextColor3 = WHITE
	title.TextSize = px(30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = header
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = BLACK
	titleStroke.Thickness = 1.6
	titleStroke.Transparency = 0.2
	titleStroke.Parent = title

	local balanceWrap = Instance.new("Frame")
	balanceWrap.Name = "BalanceWrap"
	balanceWrap.AnchorPoint = Vector2.new(1, 0)
	balanceWrap.Position = UDim2.new(1, -px(58), 0, px(5))
	balanceWrap.Size = UDim2.new(0, px(140), 0, px(38))
	balanceWrap.BackgroundColor3 = CONTENT_BG
	balanceWrap.BackgroundTransparency = 0.04
	balanceWrap.BorderSizePixel = 0
	balanceWrap.Parent = header
	applyCorners(balanceWrap, px(14))
	applyStroke(balanceWrap, ACCENT_GOLD, 1, 0.25)

	local balanceIcon = Instance.new("ImageLabel")
	balanceIcon.BackgroundTransparency = 1
	balanceIcon.Position = UDim2.new(0, px(12), 0.5, -px(10))
	balanceIcon.Size = UDim2.fromOffset(px(20), px(20))
	balanceIcon.Image = getAsset("Coin") or ""
	balanceIcon.ScaleType = Enum.ScaleType.Fit
	balanceIcon.Parent = balanceWrap

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Position = UDim2.new(0, px(38), 0, 0)
	balanceLabel.Size = UDim2.new(1, -px(48), 1, 0)
	balanceLabel.Font = Enum.Font.GothamBlack
	balanceLabel.Text = "0"
	balanceLabel.TextColor3 = WHITE
	balanceLabel.TextSize = px(16)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	balanceLabel.Parent = balanceWrap

	local closeButton = Instance.new("TextButton")
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
	bindHover(closeButton)
	setButtonState(closeButton, true, Color3.fromRGB(220, 87, 87))

	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "ToastHolder"
	toastHolder.BackgroundTransparency = 1
	toastHolder.ClipsDescendants = false
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, -px(18))
	toastHolder.Size = UDim2.new(0.62, 0, 0, px(54))
	toastHolder.ZIndex = 30
	toastHolder.Parent = panel

	local gridWrap = Instance.new("Frame")
	gridWrap.Name = "GridWrap"
	gridWrap.BackgroundColor3 = CONTENT_BG
	gridWrap.BorderSizePixel = 0
	gridWrap.Position = UDim2.new(0, px(20), 0, px(86))
	gridWrap.Size = UDim2.new(1, -px(40), 1, -px(216))
	gridWrap.Parent = panel
	gridWrap.ZIndex = 2
	applyCorners(gridWrap, px(24))
	applyStroke(gridWrap, Color3.fromRGB(123, 144, 200), 1.2, 0.2)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "CosmeticsScroller"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.new(0, px(14), 0, px(14))
	scroller.Size = UDim2.new(1, -px(28), 1, -px(28))
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = px(6)
	scroller.ScrollBarImageColor3 = Color3.fromRGB(151, 174, 230)
	scroller.Parent = gridWrap

	local scrollerPad = Instance.new("UIPadding")
	scrollerPad.PaddingRight = UDim.new(0, px(8))
	scrollerPad.PaddingBottom = UDim.new(0, px(12))
	scrollerPad.Parent = scroller

	local scrollerLayout = Instance.new("UIListLayout")
	scrollerLayout.FillDirection = Enum.FillDirection.Vertical
	scrollerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollerLayout.Padding = UDim.new(0, px(18))
	scrollerLayout.Parent = scroller

	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.BackgroundColor3 = CONTENT_BG
	actionBar.BorderSizePixel = 0
	actionBar.Position = UDim2.new(0, px(20), 1, -px(116))
	actionBar.Size = UDim2.new(1, -px(40), 0, px(96))
	actionBar.Parent = panel
	actionBar.ZIndex = 3
	applyCorners(actionBar, px(22))
	applyStroke(actionBar, Color3.fromRGB(123, 144, 200), 1.2, 0.2)

	local keepHeadRow = Instance.new("Frame")
	keepHeadRow.Name = "KeepHeadRow"
	keepHeadRow.BackgroundTransparency = 1
	keepHeadRow.Position = UDim2.new(0, px(16), 0.5, -px(22))
	keepHeadRow.Size = UDim2.new(0.22, -px(10), 0, px(44))
	keepHeadRow.Parent = actionBar

	local keepHeadButton = Instance.new("TextButton")
	keepHeadButton.Name = "KeepHeadButton"
	keepHeadButton.Text = ""
	keepHeadButton.AutoButtonColor = false
	keepHeadButton.BackgroundTransparency = 1
	keepHeadButton.Size = UDim2.fromScale(1, 1)
	keepHeadButton.Parent = keepHeadRow

	local keepHeadBox = Instance.new("Frame")
	keepHeadBox.BackgroundColor3 = TOGGLE_OFF
	keepHeadBox.BorderSizePixel = 0
	keepHeadBox.Position = UDim2.new(0, 0, 0.5, -px(18))
	keepHeadBox.Size = UDim2.new(0, px(58), 0, px(36))
	keepHeadBox.Parent = keepHeadRow
	applyCorners(keepHeadBox, px(14))
	applyStroke(keepHeadBox, WHITE, 1.2, 0.25)

	local keepHeadCheck = Instance.new("TextLabel")
	keepHeadCheck.BackgroundTransparency = 1
	keepHeadCheck.AnchorPoint = Vector2.new(0.5, 0.5)
	keepHeadCheck.Position = UDim2.fromScale(0.5, 0.5)
	keepHeadCheck.Size = UDim2.new(1, 0, 1, 0)
	keepHeadCheck.Font = Enum.Font.GothamBlack
	keepHeadCheck.Text = "OK"
	keepHeadCheck.TextColor3 = WHITE
	keepHeadCheck.TextSize = px(15)
	keepHeadCheck.Parent = keepHeadBox

	local keepHeadLabel = Instance.new("TextLabel")
	keepHeadLabel.BackgroundTransparency = 1
	keepHeadLabel.Position = UDim2.new(0, px(66), 0, 0)
	keepHeadLabel.Size = UDim2.new(1, -px(66), 1, 0)
	keepHeadLabel.Font = Enum.Font.FredokaOne
	keepHeadLabel.Text = "Keep Head"
	keepHeadLabel.TextColor3 = WHITE
	keepHeadLabel.TextSize = px(18)
	keepHeadLabel.TextScaled = true
	keepHeadLabel.TextXAlignment = Enum.TextXAlignment.Left
	keepHeadLabel.Parent = keepHeadRow
	local keepHeadTextLimit = Instance.new("UITextSizeConstraint")
	keepHeadTextLimit.MinTextSize = px(10)
	keepHeadTextLimit.MaxTextSize = px(18)
	keepHeadTextLimit.Parent = keepHeadLabel

	local detailsWrap = Instance.new("Frame")
	detailsWrap.Name = "DetailsWrap"
	detailsWrap.BackgroundTransparency = 1
	detailsWrap.Position = UDim2.new(0.24, 0, 0, 0)
	detailsWrap.Size = UDim2.new(0.34, 0, 1, 0)
	detailsWrap.Parent = actionBar

	local selectedName = Instance.new("TextLabel")
	selectedName.BackgroundTransparency = 1
	selectedName.Position = UDim2.new(0, 0, 0, px(10))
	selectedName.Size = UDim2.new(1, 0, 0, px(30))
	selectedName.Font = Enum.Font.FredokaOne
	selectedName.Text = ""
	selectedName.TextColor3 = WHITE
	selectedName.TextSize = px(22)
	selectedName.TextScaled = true
	selectedName.TextTruncate = Enum.TextTruncate.AtEnd
	selectedName.TextXAlignment = Enum.TextXAlignment.Center
	selectedName.Parent = detailsWrap
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MinTextSize = px(12)
	nameLimit.MaxTextSize = px(22)
	nameLimit.Parent = selectedName

	local selectedDesc = Instance.new("TextLabel")
	selectedDesc.BackgroundTransparency = 1
	selectedDesc.Position = UDim2.new(0, 0, 0, px(42))
	selectedDesc.Size = UDim2.new(1, 0, 0, px(42))
	selectedDesc.Font = Enum.Font.GothamBold
	selectedDesc.Text = ""
	selectedDesc.TextColor3 = CARD_SUBTEXT
	selectedDesc.TextSize = px(13)
	selectedDesc.TextWrapped = true
	selectedDesc.TextXAlignment = Enum.TextXAlignment.Center
	selectedDesc.TextYAlignment = Enum.TextYAlignment.Center
	selectedDesc.Parent = detailsWrap

	local buttonsWrap = Instance.new("Frame")
	buttonsWrap.Name = "ButtonsWrap"
	buttonsWrap.BackgroundTransparency = 1
	buttonsWrap.AnchorPoint = Vector2.new(0, 0.5)
	buttonsWrap.Position = UDim2.new(0.61, 0, 0.5, 0)
	buttonsWrap.Size = UDim2.new(0.37, -px(12), 0, px(50))
	buttonsWrap.Parent = actionBar

	local primaryButton = Instance.new("TextButton")
	primaryButton.Name = "PrimaryButton"
	primaryButton.AutoButtonColor = false
	primaryButton.BackgroundColor3 = BUTTON_PRIMARY
	primaryButton.BorderSizePixel = 0
	primaryButton.Font = Enum.Font.FredokaOne
	primaryButton.Text = "Equip"
	primaryButton.TextColor3 = WHITE
	primaryButton.TextSize = px(20)
	primaryButton.TextScaled = true
	primaryButton.TextWrapped = false
	primaryButton.Parent = buttonsWrap
	applyCorners(primaryButton, px(16))
	applyStroke(primaryButton, WHITE, 1.2, 0.26)
	setButtonState(primaryButton, true, BUTTON_PRIMARY)
	bindHover(primaryButton)
	local primaryTextLimit = Instance.new("UITextSizeConstraint")
	primaryTextLimit.MinTextSize = px(11)
	primaryTextLimit.MaxTextSize = px(20)
	primaryTextLimit.Parent = primaryButton

	local coinButton = Instance.new("TextButton")
	coinButton.Name = "CoinButton"
	coinButton.AutoButtonColor = false
	coinButton.BackgroundColor3 = BUTTON_SECONDARY
	coinButton.BorderSizePixel = 0
	coinButton.Font = Enum.Font.GothamBlack
	coinButton.Text = "Buy with Coins"
	coinButton.TextColor3 = WHITE
	coinButton.TextSize = px(16)
	coinButton.TextScaled = true
	coinButton.TextWrapped = false
	coinButton.Parent = buttonsWrap
	applyCorners(coinButton, px(16))
	applyStroke(coinButton, WHITE, 1.2, 0.26)
	setButtonState(coinButton, true, BUTTON_SECONDARY)
	bindHover(coinButton)
	local coinTextLimit = Instance.new("UITextSizeConstraint")
	coinTextLimit.MinTextSize = px(10)
	coinTextLimit.MaxTextSize = px(16)
	coinTextLimit.Parent = coinButton
	local coinButtonContent = createPriceButtonContent(coinButton, getAsset("Coin"))

	local robuxButton = Instance.new("TextButton")
	robuxButton.Name = "RobuxButton"
	robuxButton.AutoButtonColor = false
	robuxButton.BackgroundColor3 = ACCENT_BLUE
	robuxButton.BorderSizePixel = 0
	robuxButton.Font = Enum.Font.GothamBlack
	robuxButton.Text = "Buy with Robux"
	robuxButton.TextColor3 = WHITE
	robuxButton.TextSize = px(16)
	robuxButton.TextScaled = true
	robuxButton.TextWrapped = false
	robuxButton.Parent = buttonsWrap
	applyCorners(robuxButton, px(16))
	applyStroke(robuxButton, WHITE, 1.2, 0.26)
	setButtonState(robuxButton, true, ACCENT_BLUE)
	bindHover(robuxButton)
	local robuxTextLimit = Instance.new("UITextSizeConstraint")
	robuxTextLimit.MinTextSize = px(10)
	robuxTextLimit.MaxTextSize = px(16)
	robuxTextLimit.Parent = robuxButton
	local robuxButtonContent = createPriceButtonContent(robuxButton, getAsset("Robux"))

	local function setButtonMode(mode)
		primaryButton.Visible = false
		coinButton.Visible = false
		robuxButton.Visible = false
		if mode == "primary" then
			primaryButton.Visible = true
			primaryButton.Position = UDim2.fromScale(0, 0)
			primaryButton.Size = UDim2.fromScale(1, 1)
		elseif mode == "coin" then
			coinButton.Visible = true
			coinButton.Position = UDim2.fromScale(0, 0)
			coinButton.Size = UDim2.fromScale(1, 1)
		elseif mode == "coin_robux" then
			coinButton.Visible = true
			robuxButton.Visible = true
			coinButton.Position = UDim2.fromScale(0, 0)
			coinButton.Size = UDim2.new(0.48, 0, 1, 0)
			robuxButton.Position = UDim2.new(0.52, 0, 0, 0)
			robuxButton.Size = UDim2.new(0.48, 0, 1, 0)
		end
	end

	local toastToken = 0
	local function showToast(message, color)
		toastToken += 1
		local token = toastToken
		clearChildren(toastHolder)

		local toast = Instance.new("TextLabel")
		toast.BackgroundColor3 = color or CONTENT_BG
		toast.BackgroundTransparency = 0.08
		toast.Size = UDim2.new(1, 0, 1, 0)
		toast.Font = Enum.Font.GothamBold
		toast.Text = message
		toast.TextColor3 = WHITE
		toast.TextSize = px(18)
		toast.TextWrapped = true
		toast.ZIndex = 31
		toast.Parent = toastHolder
		applyCorners(toast, px(14))
		applyStroke(toast, WHITE, 1.2, 0.35)

		task.delay(2.2, function()
			if token ~= toastToken then
				return
			end
			clearChildren(toastHolder)
		end)
	end

	local cardRecords = {}
	local sectionRecords = {}

	local function getSelectedItem()
		return itemByKey[makeKey(selectedCategory, selectedId)]
	end

	local function getEmoteSlot(emoteId)
		for slot = 1, emoteSlotCount do
			if equippedEmoteSlots[slot] == emoteId then
				return slot
			end
		end
		return nil
	end

	local function countEquippedEmotes()
		local count = 0
		for slot = 1, emoteSlotCount do
			if equippedEmoteSlots[slot] then
				count += 1
			end
		end
		return count
	end

	local function isOwned(item)
		if not item then
			return false
		end
		if item.Category == "Skin" then
			return ownedSkins[item.Id] == true or item.IsDefault == true
		elseif item.Category == "Trail" then
			return ownedEffects[item.Id] == true or item.IsFree == true
		elseif item.Category == "Emote" then
			return ownedEmotes[item.Id] == true or item.IsFree == true
		end
		return false
	end

	local function isEquipped(item)
		if not item then
			return false
		end
		if item.Category == "Skin" then
			if item.Id == "Default" then
				return equippedSkinId == nil or equippedSkinId == "" or equippedSkinId == "Default"
			end
			return equippedSkinId == item.Id
		elseif item.Category == "Trail" then
			return equippedTrailId == item.Id
		elseif item.Category == "Emote" then
			return getEmoteSlot(item.Id) ~= nil
		end
		return false
	end

	local function syncBalance()
		balanceLabel.Text = formatNumber(coinBalance)
	end

	local function syncKeepHeadToggle()
		local keepHead = showHelm == false
		keepHeadBox.BackgroundColor3 = keepHead and TOGGLE_ON or TOGGLE_OFF
		keepHeadCheck.TextTransparency = keepHead and 0 or 1
	end

	local function refreshAllSkinPreviews()
		for _, record in pairs(cardRecords) do
			if record.item.Category == "Skin" and record.viewport then
				local ok, updated = pcall(function()
					record.viewport:SetAttribute("PreviewSkinId", nil)
					record.viewport:SetAttribute("PreviewShowHelm", nil)
					return SkinPreview.Update(record.viewport, record.item.Id, showHelm)
				end)
				if (not ok or not updated) and record.viewport and record.viewport.Parent then
					task.defer(function()
						if record.viewport and record.viewport.Parent then
							pcall(function()
								record.viewport:SetAttribute("PreviewSkinId", nil)
								record.viewport:SetAttribute("PreviewShowHelm", nil)
								SkinPreview.Update(record.viewport, record.item.Id, showHelm)
							end)
						end
					end)
				end
			end
		end
	end

	local function syncCard(record)
		local item = record.item
		local owned = isOwned(item)
		local equipped = isEquipped(item)
		local selected = selectedCategory == item.Category and selectedId == item.Id

		record.nameLabel.Text = item.DisplayName or item.Id
		record.stroke.Color = selected and WHITE or Color3.fromRGB(180, 200, 255)
		record.stroke.Thickness = selected and 2.2 or 1.2
		record.shadow.BackgroundTransparency = selected and 0.56 or 0.7
		local bandColor = selected and CARD_BAND_SELECTED or (owned and CARD_BAND or CARD_LOCKED)
		record.band.BackgroundColor3 = bandColor
		record.bandMask.BackgroundColor3 = bandColor

		if equipped then
			record.stateIcon.Image = ""
			if item.Category == "Emote" then
				record.stateLabel.Text = "Slot " .. tostring(getEmoteSlot(item.Id) or "")
			else
				record.stateLabel.Text = "Equipped"
			end
			record.stateLabel.Position = UDim2.new(0, px(10), 0, 0)
			record.stateLabel.Size = UDim2.new(1, -px(20), 1, 0)
		elseif owned then
			record.stateIcon.Image = ""
			record.stateLabel.Text = "Equip"
			record.stateLabel.Position = UDim2.new(0, px(10), 0, 0)
			record.stateLabel.Size = UDim2.new(1, -px(20), 1, 0)
		else
			local price = tonumber(item.CoinPrice) or 0
			if price > 0 then
				record.stateIcon.Image = getAsset("Coin") or ""
				record.stateLabel.Text = formatCompactPrice(price)
				record.stateLabel.Position = UDim2.new(0, px(34), 0, 0)
				record.stateLabel.Size = UDim2.new(1, -px(42), 1, 0)
			elseif item.IsFree then
				record.stateIcon.Image = ""
				record.stateLabel.Text = "Free"
				record.stateLabel.Position = UDim2.new(0, px(10), 0, 0)
				record.stateLabel.Size = UDim2.new(1, -px(20), 1, 0)
			else
				record.stateIcon.Image = ""
				record.stateLabel.Text = "Locked"
				record.stateLabel.Position = UDim2.new(0, px(10), 0, 0)
				record.stateLabel.Size = UDim2.new(1, -px(20), 1, 0)
			end
		end
	end

	local function syncAllCards()
		for _, record in pairs(cardRecords) do
			syncCard(record)
		end
	end

	local function syncActionBar()
		local item = getSelectedItem()
		if not item then
			selectedName.Text = "Select a cosmetic"
			selectedDesc.Text = ""
			setButtonMode(nil)
			return
		end

		selectedName.Text = item.DisplayName or item.Id
		selectedDesc.Text = item.Description or ""
		keepHeadRow.Visible = item.Category == "Skin"
		syncKeepHeadToggle()

		local owned = isOwned(item)
		local price = tonumber(item.CoinPrice) or 0

		if item.Category == "Skin" then
			if owned then
				setButtonMode("primary")
				if isEquipped(item) then
					primaryButton.Text = "Unequip"
					setButtonState(primaryButton, true, BUTTON_DANGER)
				else
					primaryButton.Text = "Equip"
					setButtonState(primaryButton, true, BUTTON_PRIMARY)
				end
			else
				setButtonMode("coin_robux")
				local coinEnabled = price > 0
				syncPriceButtonContent(coinButtonContent, coinEnabled and formatNumber(price) or "Coins Unavailable", coinEnabled, getAsset("Coin"), coinEnabled)
				setButtonState(coinButton, coinEnabled, BUTTON_SECONDARY)

				local productId = tonumber(item.RobuxProductId) or 0
				local robuxEnabled = productId > 0
				local robuxPrice = tonumber(item.RobuxPrice)
				syncPriceButtonContent(robuxButtonContent, robuxEnabled and (robuxPrice and tostring(math.floor(robuxPrice)) or "Buy") or "Robux Unavailable", robuxEnabled, getAsset("Robux"), robuxEnabled and robuxPrice ~= nil)
				setButtonState(robuxButton, robuxEnabled, ACCENT_BLUE)
			end
		elseif item.Category == "Trail" then
			if owned then
				setButtonMode("primary")
				if isEquipped(item) then
					primaryButton.Text = "Equipped"
					setButtonState(primaryButton, false, BUTTON_PRIMARY)
				else
					primaryButton.Text = "Equip"
					setButtonState(primaryButton, true, BUTTON_PRIMARY)
				end
			else
				setButtonMode("coin")
				local enabled = price > 0
				syncPriceButtonContent(coinButtonContent, enabled and formatNumber(price) or "Locked", enabled, getAsset("Coin"), enabled)
				setButtonState(coinButton, enabled, BUTTON_SECONDARY)
			end
		elseif item.Category == "Emote" then
			if owned then
				setButtonMode("primary")
				local slot = getEmoteSlot(item.Id)
				if slot then
					primaryButton.Text = "Unequip Slot " .. tostring(slot)
					setButtonState(primaryButton, true, BUTTON_DANGER)
				elseif countEquippedEmotes() >= emoteSlotCount then
					primaryButton.Text = "Slots Full"
					setButtonState(primaryButton, false, BUTTON_PRIMARY)
				else
					primaryButton.Text = "Equip to Slot " .. tostring(countEquippedEmotes() + 1)
					setButtonState(primaryButton, true, BUTTON_PRIMARY)
				end
			else
				setButtonMode("coin")
				local enabled = price > 0 or item.IsFree == true
				local label = price > 0 and formatNumber(price) or "Free"
				syncPriceButtonContent(coinButtonContent, label, enabled, getAsset("Coin"), price > 0)
				setButtonState(coinButton, enabled, BUTTON_SECONDARY)
			end
		end
	end

	local function refreshUi()
		syncBalance()
		syncAllCards()
		syncActionBar()
	end

	local function selectItem(item)
		if not item then
			return
		end
		selectedCategory = item.Category
		selectedId = item.Id
		refreshUi()
	end

	local function updateSectionGrid(record)
		local padding = px(12)
		local available = record.grid.AbsoluteSize.X
		if available <= 0 then
			return
		end
		local targetWidth = px(150)
		local columns = math.clamp(math.floor((available + padding) / (targetWidth + padding)), 1, 4)
		local cellWidth = math.floor((available - (padding * (columns - 1))) / columns)
		local cellHeight = math.max(px(156), math.floor(cellWidth * 1.12))
		local rows = math.max(1, math.ceil(record.count / columns))
		record.layout.CellPadding = UDim2.fromOffset(padding, padding)
		record.layout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
		record.grid.Size = UDim2.new(1, 0, 0, rows * cellHeight + math.max(0, rows - 1) * padding)
	end

	local function createSection(section, sectionIndex)
		local sectionFrame = Instance.new("Frame")
		sectionFrame.Name = section.Id .. "Section"
		sectionFrame.BackgroundTransparency = 1
		sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
		sectionFrame.Size = UDim2.new(1, -px(2), 0, 0)
		sectionFrame.LayoutOrder = sectionIndex
		sectionFrame.Parent = scroller

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, px(8))
		layout.Parent = sectionFrame

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Name = "SectionHeader"
		headerLabel.BackgroundTransparency = 1
		headerLabel.Size = UDim2.new(1, 0, 0, px(30))
		headerLabel.Font = Enum.Font.FredokaOne
		headerLabel.Text = section.Header or section.Id
		headerLabel.TextColor3 = WHITE
		headerLabel.TextSize = px(22)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.LayoutOrder = 1
		headerLabel.Parent = sectionFrame

		local grid = Instance.new("Frame")
		grid.Name = section.Id .. "Grid"
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, px(160))
		grid.LayoutOrder = 2
		grid.Parent = sectionFrame

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		gridLayout.Parent = grid

		local record = {
			grid = grid,
			layout = gridLayout,
			count = #(section.Items or {}),
		}
		table.insert(sectionRecords, record)
		return grid, record
	end

	local function createTrailPreview(parent, item)
		local previewFrame = Instance.new("Frame")
		previewFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
		previewFrame.BackgroundTransparency = 0.1
		previewFrame.BorderSizePixel = 0
		previewFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		previewFrame.Position = UDim2.fromScale(0.5, 0.53)
		previewFrame.Size = UDim2.new(0.82, 0, 0.58, 0)
		previewFrame.Parent = parent
		applyCorners(previewFrame, px(14))
		applyStroke(previewFrame, item.Color or ACCENT_BLUE, 1.1, 0.25)

		for i = 1, 3 do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = item.Color or WHITE
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.new(0.5, 0, 0.24 + (i * 0.18), 0)
			bar.Size = UDim2.new(0.76 - (i * 0.08), 0, 0, px(8))
			bar.Rotation = -10
			bar.Parent = previewFrame
			applyCorners(bar, px(6))
			if item.IsRainbow and item.TrailColorSequence then
				local gradient = Instance.new("UIGradient")
				gradient.Rotation = 0
				gradient.Color = item.TrailColorSequence
				gradient.Parent = bar
			end
		end
	end

	local function createEmotePreview(parent, item)
		local imageId = item.IconAssetId or getAsset(item.IconKey)
		if type(imageId) == "string" and #imageId > 0 then
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.53)
			image.Size = UDim2.fromScale(0.62, 0.62)
			image.Image = imageId
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = parent
			return
		end

		local glyph = Instance.new("TextLabel")
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.54)
		glyph.Size = UDim2.fromScale(0.78, 0.58)
		glyph.Font = Enum.Font.FredokaOne
		glyph.Text = getInitials(item.DisplayName or item.Id)
		glyph.TextColor3 = ACCENT_GOLD
		glyph.TextScaled = true
		glyph.Parent = parent
	end

	local function createCard(parentFrame, item, index)
		local theme = CARD_THEMES[((index - 1) % #CARD_THEMES) + 1]

		local button = Instance.new("TextButton")
		button.Name = item.Category .. "_" .. item.Id .. "Card"
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.LayoutOrder = index
		button.Parent = parentFrame

		local shadow = Instance.new("Frame")
		shadow.BackgroundColor3 = BLACK
		shadow.BackgroundTransparency = 0.7
		shadow.BorderSizePixel = 0
		shadow.Position = UDim2.new(0, px(4), 0, px(8))
		shadow.Size = UDim2.new(1, 0, 1, 0)
		shadow.Parent = button
		applyCorners(shadow, px(22))

		local card = Instance.new("Frame")
		card.BackgroundColor3 = theme[1]
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(1, 1)
		card.Parent = button
		applyCorners(card, px(18))
		local stroke = applyStroke(card, Color3.fromRGB(180, 200, 255), 1.2, 0.12)

		local art = Instance.new("Frame")
		art.BackgroundColor3 = theme[1]
		art.BorderSizePixel = 0
		art.Size = UDim2.new(1, 0, 0.76, 0)
		art.Parent = card
		local artCorner = Instance.new("UICorner")
		artCorner.CornerRadius = UDim.new(0, px(18))
		artCorner.Parent = art
		local artGradient = Instance.new("UIGradient")
		artGradient.Rotation = 125
		artGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme[1]),
			ColorSequenceKeypoint.new(0.58, theme[1]),
			ColorSequenceKeypoint.new(1, theme[2]),
		})
		artGradient.Parent = art

		local viewport = nil
		if item.Category == "Skin" then
			viewport = Instance.new("ViewportFrame")
			viewport.Name = "Preview"
			viewport.BackgroundTransparency = 1
			viewport.Size = UDim2.new(1, -px(10), 1, -px(14))
			viewport.Position = UDim2.new(0, px(5), 0, px(7))
			viewport.Ambient = Color3.fromRGB(190, 190, 190)
			viewport.LightColor = WHITE
			viewport.LightDirection = Vector3.new(0, -1, -1)
			viewport.Parent = art
			pcall(function()
				viewport:SetAttribute("PreviewSkinId", nil)
				viewport:SetAttribute("PreviewShowHelm", nil)
				SkinPreview.Update(viewport, item.Id, showHelm)
			end)
		elseif item.Category == "Trail" then
			createTrailPreview(art, item)
		else
			createEmotePreview(art, item)
		end

		local namePill = Instance.new("TextLabel")
		namePill.BackgroundColor3 = Color3.fromRGB(54, 69, 105)
		namePill.BackgroundTransparency = 0.06
		namePill.BorderSizePixel = 0
		namePill.AnchorPoint = Vector2.new(0.5, 0)
		namePill.Position = UDim2.new(0.5, 0, 0, px(6))
		namePill.Size = UDim2.new(1, -px(18), 0, px(22))
		namePill.Font = Enum.Font.GothamBlack
		namePill.Text = item.DisplayName or item.Id
		namePill.TextColor3 = WHITE
		namePill.TextSize = px(10)
		namePill.TextScaled = true
		namePill.TextTruncate = Enum.TextTruncate.AtEnd
		namePill.Parent = art
		applyCorners(namePill, px(10))
		applyStroke(namePill, WHITE, 1, 0.45)

		local band = Instance.new("Frame")
		band.Name = "Band"
		band.BackgroundColor3 = CARD_BAND
		band.BorderSizePixel = 0
		band.Position = UDim2.new(0, 0, 0.76, 0)
		band.Size = UDim2.new(1, 0, 0.24, 0)
		band.Parent = card
		local bandCorner = Instance.new("UICorner")
		bandCorner.CornerRadius = UDim.new(0, px(18))
		bandCorner.Parent = band

		local bandMask = Instance.new("Frame")
		bandMask.BackgroundColor3 = band.BackgroundColor3
		bandMask.BorderSizePixel = 0
		bandMask.Size = UDim2.new(1, 0, 0.5, 0)
		bandMask.Position = UDim2.new(0, 0, 0, 0)
		bandMask.Parent = band

		local stateIcon = Instance.new("ImageLabel")
		stateIcon.BackgroundTransparency = 1
		stateIcon.AnchorPoint = Vector2.new(0, 0.5)
		stateIcon.Position = UDim2.new(0, px(12), 0.5, 0)
		stateIcon.Size = UDim2.new(0, px(18), 0, px(18))
		stateIcon.Image = ""
		stateIcon.Parent = band

		local stateLabel = Instance.new("TextLabel")
		stateLabel.BackgroundTransparency = 1
		stateLabel.Position = UDim2.new(0, px(10), 0, 0)
		stateLabel.Size = UDim2.new(1, -px(20), 1, 0)
		stateLabel.Font = Enum.Font.FredokaOne
		stateLabel.Text = ""
		stateLabel.TextColor3 = WHITE
		stateLabel.TextSize = px(17)
		stateLabel.TextScaled = true
		stateLabel.TextTruncate = Enum.TextTruncate.AtEnd
		stateLabel.Parent = band
		local stateTextLimit = Instance.new("UITextSizeConstraint")
		stateTextLimit.MinTextSize = px(10)
		stateTextLimit.MaxTextSize = px(17)
		stateTextLimit.Parent = stateLabel

		local record = {
			key = makeKey(item.Category, item.Id),
			item = item,
			button = button,
			shadow = shadow,
			card = card,
			stroke = stroke,
			viewport = viewport,
			nameLabel = namePill,
			band = band,
			bandMask = bandMask,
			stateIcon = stateIcon,
			stateLabel = stateLabel,
		}
		cardRecords[record.key] = record

		trackConn(button.MouseButton1Click:Connect(function()
			selectItem(item)
		end))

		trackConn(button.MouseEnter:Connect(function()
			TweenService:Create(shadow, QUICK_TWEEN, { BackgroundTransparency = 0.58 }):Play()
		end))
		trackConn(button.MouseLeave:Connect(function()
			local selected = selectedCategory == item.Category and selectedId == item.Id
			local target = selected and 0.56 or 0.7
			TweenService:Create(shadow, QUICK_TWEEN, { BackgroundTransparency = target }):Play()
		end))

		return record
	end

	for sectionIndex, section in ipairs(sections) do
		if #(section.Items or {}) > 0 then
			local sectionGrid = createSection(section, sectionIndex)
			for itemIndex, item in ipairs(section.Items) do
				createCard(sectionGrid, item, itemIndex)
			end
		end
	end

	for _, record in ipairs(sectionRecords) do
		updateSectionGrid(record)
		task.defer(function()
			updateSectionGrid(record)
		end)
		trackConn(record.grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			updateSectionGrid(record)
		end))
	end

	trackConn(scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, record in ipairs(sectionRecords) do
			updateSectionGrid(record)
		end
	end))

	local function refreshOwnedEffectsFromServer()
		local ok, list = invokeRemote(remotes.getOwnedEffectsRF)
		if ok and type(list) == "table" then
			ownedEffects = makeIdSet(list, { DefaultTrail = true })
		end
	end

	local function refreshEquippedEffectsFromServer()
		local ok, equipped = invokeRemote(remotes.getEquippedEffectsRF)
		if ok and type(equipped) == "table" and type(equipped.DashTrail) == "string" and equipped.DashTrail ~= "" then
			equippedTrailId = equipped.DashTrail
		end
	end

	local function refreshOwnedEmotesFromServer()
		local ok, list = invokeRemote(remotes.getOwnedEmotesRF)
		if ok and type(list) == "table" then
			ownedEmotes = makeIdSet(list)
		end
	end

	local function refreshEquippedEmotesFromServer()
		local ok, list = invokeRemote(remotes.getEquippedEmotesRF)
		if ok then
			setEquippedEmotesFromList(list)
		end
	end

	refreshUi()

	trackConn(closeButton.MouseButton1Click:Connect(function()
		local closeCallback = closeCallbacks[root]
		if type(closeCallback) == "function" then
			closeCallback()
		elseif parent:IsA("ScreenGui") then
			parent.Enabled = false
		else
			root.Visible = false
		end
	end))

	trackConn(keepHeadButton.MouseButton1Click:Connect(function()
		local item = getSelectedItem()
		if not item or item.Category ~= "Skin" then
			return
		end
		showHelm = not showHelm
		playerSettings.ShowHelm = showHelm
		syncKeepHeadToggle()
		refreshAllSkinPreviews()
		if remotes.updatePlayerSettingRE then
			remotes.updatePlayerSettingRE:FireServer("ShowHelm", showHelm)
		end
	end))

	trackConn(primaryButton.MouseButton1Click:Connect(function()
		if not primaryButton:GetAttribute("EnabledState") then
			return
		end
		local item = getSelectedItem()
		if not item or not isOwned(item) then
			return
		end

		if item.Category == "Skin" then
			if isEquipped(item) then
				equippedSkinId = nil
				refreshUi()
				remotes.equipSkinRE:FireServer("Default")
			else
				equippedSkinId = item.Id
				refreshUi()
				remotes.equipSkinRE:FireServer(item.Id)
			end
		elseif item.Category == "Trail" then
			if not isEquipped(item) then
				remotes.equipEffectRE:FireServer(item.Id, "DashTrail")
			end
		elseif item.Category == "Emote" then
			local slot = getEmoteSlot(item.Id)
			if slot then
				remotes.unequipEmoteRE:FireServer(slot)
			elseif countEquippedEmotes() < emoteSlotCount then
				remotes.equipEmoteRE:FireServer(item.Id)
			else
				showToast("All emote slots are full.", RED)
			end
		end
	end))

	trackConn(coinButton.MouseButton1Click:Connect(function()
		if not coinButton:GetAttribute("EnabledState") then
			showToast("This cosmetic is not available for coin purchase.", BUTTON_SECONDARY_DISABLED)
			return
		end

		local item = getSelectedItem()
		if not item or isOwned(item) then
			refreshUi()
			return
		end

		local remote = nil
		if item.Category == "Skin" then
			remote = remotes.purchaseSkinRF
		elseif item.Category == "Trail" then
			remote = remotes.purchaseEffectRF
		elseif item.Category == "Emote" then
			remote = remotes.purchaseEmoteRF
		end

		local ok, success, newBalance, reason = invokeRemote(remote, item.Id)
		if not ok then
			showToast("Purchase failed.", RED)
			return
		end

		if success then
			if item.Category == "Skin" then
				ownedSkins[item.Id] = true
			elseif item.Category == "Trail" then
				ownedEffects[item.Id] = true
				refreshOwnedEffectsFromServer()
				refreshEquippedEffectsFromServer()
			elseif item.Category == "Emote" then
				ownedEmotes[item.Id] = true
				refreshOwnedEmotesFromServer()
				refreshEquippedEmotesFromServer()
			end
			coinBalance = math.max(0, math.floor(tonumber(newBalance) or coinBalance))
			showToast("Purchased " .. tostring(item.DisplayName or item.Id) .. ".", BUTTON_PRIMARY)
			refreshUi()
			return
		end

		if type(newBalance) == "number" then
			coinBalance = math.max(0, math.floor(newBalance))
		end
		local reasonText = ({
			not_enough_coins = "Not enough coins.",
			already_owned = "You already own this cosmetic.",
			not_purchasable = "This cosmetic cannot be bought with coins.",
		})[reason] or "Purchase failed."
		showToast(reasonText, RED)
		refreshUi()
	end))

	trackConn(robuxButton.MouseButton1Click:Connect(function()
		local item = getSelectedItem()
		if not item or item.Category ~= "Skin" then
			return
		end
		local productId = tonumber(item.RobuxProductId) or 0
		if productId <= 0 then
			showToast("Robux purchase is not configured for this skin.", RED)
			return
		end
		showToast("Complete the Roblox purchase prompt to unlock this skin.", ACCENT_BLUE)
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
		if not ok then
			warn("[CosmeticsStallUI] PromptProductPurchase failed:", tostring(err))
			showToast("Robux purchase prompt failed.", RED)
		end
	end))

	trackConn(remotes.coinsUpdatedRE.OnClientEvent:Connect(function(amount)
		if type(amount) == "number" then
			coinBalance = math.max(0, math.floor(amount))
			syncBalance()
		end
	end))

	trackConn(remotes.ownedSkinsChangedRE.OnClientEvent:Connect(function(list)
		ownedSkins = makeIdSet(list, { Default = true })
		refreshUi()
	end))

	trackConn(remotes.equippedSkinChangedRE.OnClientEvent:Connect(function(skinId)
		equippedSkinId = skinId
		refreshUi()
	end))

	trackConn(remotes.equippedEffectsChangedRE.OnClientEvent:Connect(function(equipped)
		if type(equipped) == "table" and type(equipped.DashTrail) == "string" and equipped.DashTrail ~= "" then
			equippedTrailId = equipped.DashTrail
		else
			equippedTrailId = "DefaultTrail"
		end
		refreshUi()
	end))

	trackConn(remotes.equippedEmotesChangedRE.OnClientEvent:Connect(function(list)
		setEquippedEmotesFromList(list)
		refreshUi()
	end))

	root.Destroying:Connect(function()
		closeCallbacks[root] = nil
		cleanupConnections()
	end)

	return root
end

return SkinsStallUI
