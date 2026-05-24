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

local function dpx(base, minimum)
	return math.max(minimum or 1, px(base))
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

local function addTextLimit(label, minTextSize, maxTextSize)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minTextSize
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label
	return constraint
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
	if not parent then
		return nil
	end
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
local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI", 10)
local CosmeticsCatalog = safeRequire(ReplicatedStorage, "CosmeticsCatalog", 10)
local SkinDefs = safeRequire(ReplicatedStorage, "SkinDefinitions", 10)
local AssetCodes = safeRequire(ReplicatedStorage, "AssetCodes", 5)
local SkinThumbnailPreview = modulesFolder and safeRequire(modulesFolder, "StandaloneSkinPreview", 10)
local CosmeticPreviewController = safeRequire(sideUIFolder, "CosmeticPreviewController", 10)

local STYLE = {
	MainPanelPadding = 18,
	SectionSpacing = 18,
	LeftScrollPanelWidth = 0.70,
	RightPreviewPanelWidth = 318,
	RightPreviewMinWidth = 246,
	RightPreviewMaxWidth = 340,
	PreviewViewportHeight = 280,
	SkinCardWidth = 148,
	SkinCardHeight = 178,
	CompactCosmeticCardWidth = 200,
	CompactCosmeticCardHeight = 120,
	HeaderTextSize = 30,
	CardTitleTextSize = 19,
	SkinCardTitleTextSize = 18,
	CardSubtitleTextSize = 15,
	CardButtonTextSize = 17,
	SectionHeaderTextSize = 24,
	DetailTitleTextSize = 26,
	DetailDescriptionTextSize = 17,
	ButtonTextSize = 19,
	CompactCardPadding = 10,
	CompactButtonHeight = 32,
	CornerRadius = 14,
	PanelCornerRadius = 22,
	StrokeTransparency = 0.22,
	HeaderHeight = 60,
	BottomDetailHeight = 128,
	BodyGap = 14,
	CardGap = 10,
}

local COLORS = {
	PanelBg = Color3.fromRGB(18, 22, 35),
	PanelTop = Color3.fromRGB(35, 44, 68),
	PanelStroke = Color3.fromRGB(102, 127, 190),
	Surface = Color3.fromRGB(12, 16, 27),
	SurfaceSoft = Color3.fromRGB(20, 26, 42),
	Card = Color3.fromRGB(27, 34, 51),
	CardHover = Color3.fromRGB(34, 43, 64),
	CardSelected = Color3.fromRGB(38, 61, 73),
	CardEquipped = Color3.fromRGB(28, 61, 49),
	CardLocked = Color3.fromRGB(46, 50, 66),
	Stroke = Color3.fromRGB(115, 139, 199),
	DimStroke = Color3.fromRGB(72, 88, 128),
	Text = Color3.fromRGB(246, 248, 255),
	Muted = Color3.fromRGB(177, 188, 214),
	Subtle = Color3.fromRGB(113, 126, 156),
	Blue = Color3.fromRGB(89, 184, 255),
	Gold = Color3.fromRGB(255, 204, 90),
	Green = Color3.fromRGB(76, 202, 122),
	GreenDark = Color3.fromRGB(46, 130, 82),
	Orange = Color3.fromRGB(231, 156, 58),
	Red = Color3.fromRGB(209, 88, 76),
	RedDark = Color3.fromRGB(113, 55, 55),
	White = Color3.fromRGB(255, 255, 255),
	Black = Color3.fromRGB(0, 0, 0),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(190, 198, 214),
	Uncommon = Color3.fromRGB(111, 220, 139),
	Rare = Color3.fromRGB(95, 169, 255),
	Epic = Color3.fromRGB(191, 125, 255),
	Legendary = Color3.fromRGB(255, 193, 83),
}

local SECTION_META = {
	Skins = { Subtitle = "Character appearances", Accent = Color3.fromRGB(114, 185, 255) },
	Trails = { Subtitle = "Movement effects", Accent = Color3.fromRGB(101, 218, 169) },
	Emotes = { Subtitle = "Express yourself", Accent = Color3.fromRGB(255, 202, 93) },
}

local QUICK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local remotes = nil
local activeConnections = {}
local closeCallbacks = setmetatable({}, { __mode = "k" })
local warnedMissingVisual = {}

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

local function warnMissingOnce(item, visualType)
	if not item then
		return
	end
	local key = tostring(visualType) .. ":" .. tostring(item.Category) .. ":" .. tostring(item.Id)
	if warnedMissingVisual[key] then
		return
	end
	warnedMissingVisual[key] = true
	warn("[CosmeticsStallUI] Missing", visualType, "for", tostring(item.Category), tostring(item.Id), "- using fallback visual")
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

local function getRarityColor(item)
	return RARITY_COLORS[item and item.Rarity or "Common"] or RARITY_COLORS.Common
end

local function mixColor(a, b, alpha)
	return a:Lerp(b, math.clamp(alpha or 0.5, 0, 1))
end

local function makeKey(category, itemId)
	return tostring(category) .. ":" .. tostring(itemId)
end

local function normalizeImageAsset(asset)
	if type(asset) == "number" then
		return "rbxassetid://" .. tostring(asset)
	end
	if type(asset) ~= "string" then
		return nil
	end
	local trimmed = asset:match("^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end
	local lower = string.lower(trimmed)
	if string.find(lower, "put_", 1, true) or string.find(lower, "placeholder", 1, true) then
		return nil
	end
	if tonumber(trimmed) then
		return "rbxassetid://" .. trimmed
	end
	if string.sub(lower, 1, 13) == "rbxassetid://"
		or string.sub(lower, 1, 11) == "rbxasset://"
		or string.sub(lower, 1, 11) == "rbxthumb://"
		or string.sub(lower, 1, 7) == "http://"
		or string.sub(lower, 1, 8) == "https://" then
		return trimmed
	end
	return nil
end

local function resolveEmoteIconAsset(item)
	local source = item and item.Source
	local directCandidates = {
		item and item.Icon,
		item and item.IconImage,
		item and item.Image,
		item and item.Thumbnail,
		item and item.IconAssetId,
		source and source.Icon,
		source and source.IconImage,
		source and source.Image,
		source and source.Thumbnail,
		source and source.IconAssetId,
	}
	for _, candidate in ipairs(directCandidates) do
		local asset = normalizeImageAsset(candidate)
		if asset then
			return asset
		end
	end

	local keyCandidates = {
		item and item.IconKey,
		item and item.IconImageKey,
		item and item.ImageKey,
		item and item.ThumbnailKey,
		source and source.IconKey,
		source and source.IconImageKey,
		source and source.ImageKey,
		source and source.ThumbnailKey,
	}
	for _, key in ipairs(keyCandidates) do
		local asset = normalizeImageAsset(getAsset(key))
		if asset then
			return asset
		end
	end
	return nil
end

local function createGlyphPart(parent, name, size, position, color, radius, rotation, anchorPoint)
	local part = Instance.new("Frame")
	part.Name = name
	part.BackgroundColor3 = color
	part.BorderSizePixel = 0
	part.AnchorPoint = anchorPoint or Vector2.new(0.5, 0.5)
	part.Position = position
	part.Size = size
	part.Rotation = rotation or 0
	part.Parent = parent
	applyCorners(part, radius or px(4))
	return part
end

local EMOTE_GLYPH_POSES = {
	wave = { leftArmRotation = 35, rightArmRotation = -55, rightArmX = 37, rightArmY = 22, leftLegRotation = 18, rightLegRotation = -18 },
	dance = { leftArmRotation = -42, rightArmRotation = 42, leftLegRotation = -22, rightLegRotation = 22 },
	floss = { leftArmRotation = 72, rightArmRotation = 72, leftArmX = 21, rightArmX = 35, leftLegRotation = -12, rightLegRotation = 12 },
	dab = { headX = 30, leftArmRotation = -52, rightArmRotation = -52, leftArmX = 22, rightArmX = 36, leftLegRotation = 18, rightLegRotation = -18 },
	headless = { hideHead = true, leftArmRotation = -32, rightArmRotation = 32, leftLegRotation = -18, rightLegRotation = 18 },
}

local function createFallbackEmoteGlyph(parent, item, accentColor)
	local id = string.lower(tostring(item and item.Id or ""))
	local pose = EMOTE_GLYPH_POSES[id] or EMOTE_GLYPH_POSES.dance
	local color = accentColor or COLORS.Gold
	local softColor = mixColor(COLORS.SurfaceSoft, color, 0.32)

	local root = Instance.new("Frame")
	root.Name = "FallbackGlyph"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	local glow = createGlyphPart(root, "Glow", UDim2.fromOffset(px(40), px(40)), UDim2.fromScale(0.5, 0.52), mixColor(COLORS.Surface, color, 0.14), px(15), 0)
	glow.BackgroundTransparency = 0.1

	if pose.hideHead then
		local collar = createGlyphPart(root, "HeadlessCollar", UDim2.fromOffset(px(15), px(4)), UDim2.new(0.5, 0, 0, px(19)), color, px(4), 0)
		collar.BackgroundTransparency = 0.08
	else
		createGlyphPart(root, "Head", UDim2.fromOffset(px(11), px(11)), UDim2.new(0.5, px(pose.headX or 0), 0, px(15)), COLORS.Text, px(8), 0)
	end

	createGlyphPart(root, "Torso", UDim2.fromOffset(px(7), px(16)), UDim2.new(0.5, 0, 0, px(29)), softColor, px(4), pose.torsoRotation or 0)
	createGlyphPart(root, "LeftArm", UDim2.fromOffset(px(4), px(22)), UDim2.new(0, px(pose.leftArmX or 21), 0, px(pose.leftArmY or 28)), color, px(3), pose.leftArmRotation or -36)
	createGlyphPart(root, "RightArm", UDim2.fromOffset(px(4), px(22)), UDim2.new(0, px(pose.rightArmX or 35), 0, px(pose.rightArmY or 28)), color, px(3), pose.rightArmRotation or 36)
	createGlyphPart(root, "LeftLeg", UDim2.fromOffset(px(4), px(17)), UDim2.new(0, px(25), 0, px(42)), COLORS.Muted, px(3), pose.leftLegRotation or -18)
	createGlyphPart(root, "RightLeg", UDim2.fromOffset(px(4), px(17)), UDim2.new(0, px(32), 0, px(42)), COLORS.Muted, px(3), pose.rightLegRotation or 18)

	local motion = createGlyphPart(root, "MotionLine", UDim2.fromOffset(px(24), px(3)), UDim2.new(0.5, 0, 1, -px(8)), color, px(3), -8)
	motion.BackgroundTransparency = 0.18
end

local function getCategoryLabel(category)
	if category == "Trail" then
		return "Trail"
	elseif category == "Emote" then
		return "Emote"
	end
	return "Skin"
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
	label.TextColor3 = COLORS.Red
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
	icon.Size = UDim2.fromOffset(px(19), px(19))
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
	label.TextColor3 = COLORS.Text
	label.TextSize = px(16)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 7
	label.Parent = content
	addTextLimit(label, px(10), px(16))

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.BackgroundTransparency = 1
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.new(1, -px(12), 1, -px(8))
	fallback.Font = Enum.Font.GothamBlack
	fallback.Text = ""
	fallback.TextColor3 = COLORS.Text
	fallback.TextScaled = true
	fallback.Visible = false
	fallback.ZIndex = 7
	fallback.Parent = button
	addTextLimit(fallback, px(10), px(15))

	return { content = content, icon = icon, label = label, fallback = fallback }
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

local function setButtonState(button, enabled, color, disabledColor)
	button.Active = true
	button.AutoButtonColor = false
	button.BackgroundColor3 = enabled and color or (disabledColor or COLORS.CardLocked)
	button.TextTransparency = enabled and 0 or 0.18
	button.BackgroundTransparency = enabled and 0 or 0.08
	button:SetAttribute("EnabledState", enabled)
	button:SetAttribute("BaseColorR", color.R)
	button:SetAttribute("BaseColorG", color.G)
	button:SetAttribute("BaseColorB", color.B)
	button:SetAttribute("DisabledColorR", button.BackgroundColor3.R)
	button:SetAttribute("DisabledColorG", button.BackgroundColor3.G)
	button:SetAttribute("DisabledColorB", button.BackgroundColor3.B)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = enabled and 0.22 or 0.5
	end
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
		TweenService:Create(button, QUICK_TWEEN, { BackgroundColor3 = baseColor:Lerp(COLORS.White, 0.1) }):Play()
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
	if not SkinThumbnailPreview then
		return createErrorLabel(parent, "Cosmetics unavailable: StandaloneSkinPreview missing.")
	end
	if not CosmeticPreviewController then
		return createErrorLabel(parent, "Cosmetics unavailable: preview controller missing.")
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
	panel.Size = UDim2.fromScale(0.84, 0.86)
	panel.BackgroundColor3 = COLORS.PanelBg
	panel.BorderSizePixel = 0
	panel.Parent = root
	applyCorners(panel, px(STYLE.PanelCornerRadius))
	applyStroke(panel, COLORS.PanelStroke, 1.5, 0.18)
	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(760, 520)
	panelConstraint.MaxSize = Vector2.new(math.max(820, math.floor(viewportSize.X * 0.92)), math.max(560, math.floor(viewportSize.Y * 0.92)))
	panelConstraint.Parent = panel

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Rotation = 90
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.PanelTop),
		ColorSequenceKeypoint.new(0.36, COLORS.PanelBg),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 15, 25)),
	})
	panelGradient.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.new(0, px(STYLE.MainPanelPadding), 0, px(10))
	header.Size = UDim2.new(1, -px(STYLE.MainPanelPadding * 2), 0, px(STYLE.HeaderHeight))
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -px(240), 1, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "COSMETICS"
	title.TextColor3 = COLORS.Text
	title.TextSize = px(STYLE.HeaderTextSize)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = header
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = COLORS.Black
	titleStroke.Thickness = 1.4
	titleStroke.Transparency = 0.35
	titleStroke.Parent = title

	local balanceWrap = Instance.new("Frame")
	balanceWrap.Name = "BalanceWrap"
	balanceWrap.AnchorPoint = Vector2.new(1, 0.5)
	balanceWrap.Position = UDim2.new(1, -px(52), 0.5, 0)
	balanceWrap.Size = UDim2.new(0, px(142), 0, px(36))
	balanceWrap.BackgroundColor3 = COLORS.Surface
	balanceWrap.BackgroundTransparency = 0.02
	balanceWrap.BorderSizePixel = 0
	balanceWrap.Parent = header
	applyCorners(balanceWrap, px(12))
	applyStroke(balanceWrap, COLORS.Gold, 1, 0.3)

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
	balanceLabel.TextColor3 = COLORS.Text
	balanceLabel.TextSize = px(15)
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	balanceLabel.Parent = balanceWrap

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, 0, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(px(40), px(36))
	closeButton.BackgroundColor3 = COLORS.Red
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.Text = "X"
	closeButton.TextColor3 = COLORS.Text
	closeButton.TextSize = px(18)
	closeButton.Parent = header
	applyCorners(closeButton, px(12))
	applyStroke(closeButton, COLORS.White, 1, 0.45)
	setButtonState(closeButton, true, COLORS.Red)
	bindHover(closeButton)

	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "ToastHolder"
	toastHolder.BackgroundTransparency = 1
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, -px(16))
	toastHolder.Size = UDim2.new(0.54, 0, 0, px(48))
	toastHolder.ZIndex = 30
	toastHolder.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, px(STYLE.MainPanelPadding), 0, px(STYLE.HeaderHeight + 18))
	body.Size = UDim2.new(1, -px(STYLE.MainPanelPadding * 2), 1, -px(STYLE.HeaderHeight + STYLE.BottomDetailHeight + 50))
	body.Parent = panel

	local listPanel = Instance.new("Frame")
	listPanel.Name = "ListPanel"
	listPanel.BackgroundColor3 = COLORS.Surface
	listPanel.BorderSizePixel = 0
	listPanel.Position = UDim2.fromOffset(0, 0)
	listPanel.Size = UDim2.new(1, -px(STYLE.RightPreviewPanelWidth + STYLE.BodyGap), 1, 0)
	listPanel.Parent = body
	applyCorners(listPanel, px(STYLE.CornerRadius))
	applyStroke(listPanel, COLORS.Stroke, 1.2, STYLE.StrokeTransparency)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "CosmeticsScroller"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.new(0, px(14), 0, px(14))
	scroller.Size = UDim2.new(1, -px(30), 1, -px(28))
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = px(5)
	scroller.ScrollBarImageColor3 = COLORS.Stroke
	scroller.Parent = listPanel

	local scrollerPad = Instance.new("UIPadding")
	scrollerPad.PaddingRight = UDim.new(0, px(10))
	scrollerPad.PaddingBottom = UDim.new(0, px(12))
	scrollerPad.Parent = scroller

	local scrollerLayout = Instance.new("UIListLayout")
	scrollerLayout.FillDirection = Enum.FillDirection.Vertical
	scrollerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollerLayout.Padding = UDim.new(0, px(STYLE.SectionSpacing))
	scrollerLayout.Parent = scroller

	local previewPanel = Instance.new("Frame")
	previewPanel.Name = "PreviewPanel"
	previewPanel.AnchorPoint = Vector2.new(1, 0)
	previewPanel.BackgroundColor3 = COLORS.Surface
	previewPanel.BorderSizePixel = 0
	previewPanel.Position = UDim2.new(1, 0, 0, 0)
	previewPanel.Size = UDim2.new(0, px(STYLE.RightPreviewPanelWidth), 1, 0)
	previewPanel.Parent = body
	applyCorners(previewPanel, px(STYLE.CornerRadius))
	local previewPanelStroke = applyStroke(previewPanel, COLORS.Stroke, 1.2, STYLE.StrokeTransparency)

	local previewHeader = Instance.new("TextLabel")
	previewHeader.Name = "PreviewHeader"
	previewHeader.BackgroundTransparency = 1
	previewHeader.Position = UDim2.new(0, px(14), 0, px(10))
	previewHeader.Size = UDim2.new(1, -px(28), 0, px(22))
	previewHeader.Font = Enum.Font.GothamBlack
	previewHeader.Text = "PREVIEW"
	previewHeader.TextColor3 = COLORS.Muted
	previewHeader.TextSize = px(14)
	previewHeader.TextXAlignment = Enum.TextXAlignment.Left
	previewHeader.Parent = previewPanel

	local previewName = Instance.new("TextLabel")
	previewName.Name = "PreviewName"
	previewName.BackgroundTransparency = 1
	previewName.Position = UDim2.new(0, px(14), 0, px(32))
	previewName.Size = UDim2.new(1, -px(28), 0, px(30))
	previewName.Font = Enum.Font.FredokaOne
	previewName.Text = "Select a cosmetic"
	previewName.TextColor3 = COLORS.Text
	previewName.TextSize = px(21)
	previewName.TextScaled = true
	previewName.TextTruncate = Enum.TextTruncate.AtEnd
	previewName.TextXAlignment = Enum.TextXAlignment.Left
	previewName.Parent = previewPanel
	addTextLimit(previewName, px(12), px(21))

	local previewViewport = Instance.new("ViewportFrame")
	previewViewport.Name = "PreviewViewport"
	previewViewport.BackgroundColor3 = Color3.fromRGB(9, 12, 22)
	previewViewport.BorderSizePixel = 0
	previewViewport.Position = UDim2.new(0, px(14), 0, px(70))
	previewViewport.Size = UDim2.new(1, -px(28), 1, -px(84))
	previewViewport.Ambient = Color3.fromRGB(110, 118, 150)
	previewViewport.LightColor = COLORS.White
	previewViewport.ClipsDescendants = true
	previewViewport.Parent = previewPanel
	applyCorners(previewViewport, px(12))
	local previewViewportStroke = applyStroke(previewViewport, COLORS.DimStroke, 1.1, 0.22)

	local previewController = CosmeticPreviewController.new(previewViewport)
	local currentPreviewKey = nil

	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.BackgroundColor3 = COLORS.Surface
	actionBar.BorderSizePixel = 0
	actionBar.Position = UDim2.new(0, px(STYLE.MainPanelPadding), 1, -px(STYLE.MainPanelPadding + STYLE.BottomDetailHeight))
	actionBar.Size = UDim2.new(1, -px(STYLE.MainPanelPadding * 2), 0, px(STYLE.BottomDetailHeight))
	actionBar.Parent = panel
	actionBar.ZIndex = 3
	applyCorners(actionBar, px(STYLE.CornerRadius))
	applyStroke(actionBar, COLORS.Stroke, 1.2, STYLE.StrokeTransparency)

	local detailInfo = Instance.new("Frame")
	detailInfo.Name = "DetailInfo"
	detailInfo.BackgroundTransparency = 1
	detailInfo.Position = UDim2.new(0, px(16), 0, px(12))
	detailInfo.Size = UDim2.new(1, -px(340), 1, -px(24))
	detailInfo.Parent = actionBar

	local selectedName = Instance.new("TextLabel")
	selectedName.BackgroundTransparency = 1
	selectedName.Position = UDim2.new(0, 0, 0, 0)
	selectedName.Size = UDim2.new(0.62, 0, 0, px(32))
	selectedName.Font = Enum.Font.FredokaOne
	selectedName.Text = ""
	selectedName.TextColor3 = COLORS.Text
	selectedName.TextSize = px(STYLE.DetailTitleTextSize)
	selectedName.TextScaled = true
	selectedName.TextTruncate = Enum.TextTruncate.AtEnd
	selectedName.TextXAlignment = Enum.TextXAlignment.Left
	selectedName.Parent = detailInfo
	addTextLimit(selectedName, px(13), px(STYLE.DetailTitleTextSize))

	local categoryPill = Instance.new("TextLabel")
	categoryPill.Name = "CategoryPill"
	categoryPill.BackgroundColor3 = COLORS.Card
	categoryPill.BorderSizePixel = 0
	categoryPill.Position = UDim2.new(0.64, px(8), 0, px(3))
	categoryPill.Size = UDim2.new(0, px(92), 0, px(26))
	categoryPill.Font = Enum.Font.GothamBlack
	categoryPill.Text = "SKIN"
	categoryPill.TextColor3 = COLORS.Muted
	categoryPill.TextSize = px(14)
	categoryPill.Parent = detailInfo
	applyCorners(categoryPill, px(9))
	local categoryPillStroke = applyStroke(categoryPill, COLORS.DimStroke, 1, 0.35)

	local selectedDesc = Instance.new("TextLabel")
	selectedDesc.BackgroundTransparency = 1
	selectedDesc.Position = UDim2.new(0, 0, 0, px(38))
	selectedDesc.Size = UDim2.new(1, -px(18), 0, px(46))
	selectedDesc.Font = Enum.Font.GothamMedium
	selectedDesc.Text = ""
	selectedDesc.TextColor3 = COLORS.Muted
	selectedDesc.TextSize = px(STYLE.DetailDescriptionTextSize)
	selectedDesc.TextWrapped = true
	selectedDesc.TextXAlignment = Enum.TextXAlignment.Left
	selectedDesc.TextYAlignment = Enum.TextYAlignment.Top
	selectedDesc.Parent = detailInfo

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 0, 1, -px(22))
	statusLabel.Size = UDim2.new(1, -px(18), 0, px(22))
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = ""
	statusLabel.TextColor3 = COLORS.Gold
	statusLabel.TextSize = px(14)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Parent = detailInfo

	local keepHeadRow = Instance.new("Frame")
	keepHeadRow.Name = "KeepHeadRow"
	keepHeadRow.BackgroundTransparency = 1
	keepHeadRow.AnchorPoint = Vector2.new(1, 0.5)
	keepHeadRow.Position = UDim2.new(1, -px(268), 0.5, 0)
	keepHeadRow.Size = UDim2.new(0, px(150), 0, px(42))
	keepHeadRow.Parent = actionBar

	local keepHeadButton = Instance.new("TextButton")
	keepHeadButton.Name = "KeepHeadButton"
	keepHeadButton.Text = ""
	keepHeadButton.AutoButtonColor = false
	keepHeadButton.BackgroundTransparency = 1
	keepHeadButton.Size = UDim2.fromScale(1, 1)
	keepHeadButton.Parent = keepHeadRow

	local keepHeadBox = Instance.new("Frame")
	keepHeadBox.BackgroundColor3 = COLORS.CardLocked
	keepHeadBox.BorderSizePixel = 0
	keepHeadBox.Position = UDim2.new(0, 0, 0.5, -px(13))
	keepHeadBox.Size = UDim2.new(0, px(46), 0, px(26))
	keepHeadBox.Parent = keepHeadRow
	applyCorners(keepHeadBox, px(10))
	applyStroke(keepHeadBox, COLORS.White, 1, 0.45)

	local keepHeadKnob = Instance.new("Frame")
	keepHeadKnob.Name = "Knob"
	keepHeadKnob.BackgroundColor3 = COLORS.White
	keepHeadKnob.BorderSizePixel = 0
	keepHeadKnob.AnchorPoint = Vector2.new(0, 0.5)
	keepHeadKnob.Position = UDim2.new(0, px(4), 0.5, 0)
	keepHeadKnob.Size = UDim2.fromOffset(px(18), px(18))
	keepHeadKnob.Parent = keepHeadBox
	applyCorners(keepHeadKnob, px(8))

	local keepHeadLabel = Instance.new("TextLabel")
	keepHeadLabel.BackgroundTransparency = 1
	keepHeadLabel.Position = UDim2.new(0, px(54), 0, 0)
	keepHeadLabel.Size = UDim2.new(1, -px(54), 1, 0)
	keepHeadLabel.Font = Enum.Font.GothamBold
	keepHeadLabel.Text = "Keep Head"
	keepHeadLabel.TextColor3 = COLORS.Text
	keepHeadLabel.TextSize = px(14)
	keepHeadLabel.TextXAlignment = Enum.TextXAlignment.Left
	keepHeadLabel.Parent = keepHeadRow

	local buttonsWrap = Instance.new("Frame")
	buttonsWrap.Name = "ButtonsWrap"
	buttonsWrap.BackgroundTransparency = 1
	buttonsWrap.AnchorPoint = Vector2.new(1, 0.5)
	buttonsWrap.Position = UDim2.new(1, -px(16), 0.5, 0)
	buttonsWrap.Size = UDim2.new(0, px(238), 0, px(48))
	buttonsWrap.Parent = actionBar

	local primaryButton = Instance.new("TextButton")
	primaryButton.Name = "PrimaryButton"
	primaryButton.AutoButtonColor = false
	primaryButton.BackgroundColor3 = COLORS.GreenDark
	primaryButton.BorderSizePixel = 0
	primaryButton.Font = Enum.Font.FredokaOne
	primaryButton.Text = "EQUIP"
	primaryButton.TextColor3 = COLORS.Text
	primaryButton.TextSize = px(STYLE.ButtonTextSize)
	primaryButton.TextScaled = true
	primaryButton.TextWrapped = false
	primaryButton.Parent = buttonsWrap
	applyCorners(primaryButton, px(13))
	applyStroke(primaryButton, COLORS.White, 1.1, 0.32)
	addTextLimit(primaryButton, px(11), px(STYLE.ButtonTextSize))
	setButtonState(primaryButton, true, COLORS.GreenDark)
	bindHover(primaryButton)

	local coinButton = Instance.new("TextButton")
	coinButton.Name = "CoinButton"
	coinButton.AutoButtonColor = false
	coinButton.BackgroundColor3 = COLORS.Orange
	coinButton.BorderSizePixel = 0
	coinButton.Font = Enum.Font.GothamBlack
	coinButton.Text = ""
	coinButton.TextColor3 = COLORS.Text
	coinButton.TextSize = px(16)
	coinButton.TextScaled = true
	coinButton.TextWrapped = false
	coinButton.Parent = buttonsWrap
	applyCorners(coinButton, px(13))
	applyStroke(coinButton, COLORS.White, 1.1, 0.32)
	addTextLimit(coinButton, px(10), px(16))
	setButtonState(coinButton, true, COLORS.Orange)
	bindHover(coinButton)
	local coinButtonContent = createPriceButtonContent(coinButton, getAsset("Coin"))

	local robuxButton = Instance.new("TextButton")
	robuxButton.Name = "RobuxButton"
	robuxButton.AutoButtonColor = false
	robuxButton.BackgroundColor3 = COLORS.Blue
	robuxButton.BorderSizePixel = 0
	robuxButton.Font = Enum.Font.GothamBlack
	robuxButton.Text = ""
	robuxButton.TextColor3 = COLORS.Text
	robuxButton.TextSize = px(16)
	robuxButton.TextScaled = true
	robuxButton.TextWrapped = false
	robuxButton.Parent = buttonsWrap
	applyCorners(robuxButton, px(13))
	applyStroke(robuxButton, COLORS.White, 1.1, 0.32)
	addTextLimit(robuxButton, px(10), px(16))
	setButtonState(robuxButton, true, COLORS.Blue)
	bindHover(robuxButton)
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
			coinButton.Size = UDim2.new(0.49, -px(3), 1, 0)
			robuxButton.Position = UDim2.new(0.51, px(3), 0, 0)
			robuxButton.Size = UDim2.new(0.49, -px(3), 1, 0)
		end
	end

	local function showToast(message, color)
		clearChildren(toastHolder)
		local toast = Instance.new("TextLabel")
		toast.BackgroundColor3 = color or COLORS.SurfaceSoft
		toast.BackgroundTransparency = 0.04
		toast.Size = UDim2.fromScale(1, 1)
		toast.Font = Enum.Font.GothamBold
		toast.Text = message
		toast.TextColor3 = COLORS.Text
		toast.TextSize = px(16)
		toast.TextWrapped = true
		toast.ZIndex = 31
		toast.Parent = toastHolder
		applyCorners(toast, px(12))
		applyStroke(toast, COLORS.White, 1, 0.45)
		task.delay(2.2, function()
			if toast and toast.Parent then
				toast:Destroy()
			end
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

	local function getStatusText(item)
		if not item then
			return ""
		end
		if isEquipped(item) then
			if item.Category == "Emote" then
				return "Equipped: Slot " .. tostring(getEmoteSlot(item.Id) or "")
			end
			return "Equipped"
		end
		if isOwned(item) then
			return item.Category == "Trail" and "Owned" or "Owned - ready to equip"
		end
		local price = tonumber(item.CoinPrice) or 0
		if price > 0 then
			return "Price: " .. formatNumber(price) .. " coins"
		end
		if item.IsFree then
			return "Free"
		end
		return "Locked"
	end

	local function syncBalance()
		balanceLabel.Text = formatNumber(coinBalance)
	end

	local function syncKeepHeadToggle()
		local keepHead = showHelm == false
		keepHeadBox.BackgroundColor3 = keepHead and COLORS.GreenDark or COLORS.CardLocked
		keepHeadKnob.Position = keepHead and UDim2.new(1, -px(22), 0.5, 0) or UDim2.new(0, px(4), 0.5, 0)
	end

	local function refreshAllSkinThumbnails()
		for _, record in pairs(cardRecords) do
			if record.item.Category == "Skin" and record.viewport then
				pcall(function()
					record.viewport:SetAttribute("PreviewSkinId", nil)
					record.viewport:SetAttribute("PreviewShowHelm", nil)
					SkinThumbnailPreview.Update(record.viewport, record.item.Id, showHelm)
				end)
			end
		end
	end

	local function updatePreview(item, force)
		if not previewController then
			return
		end
		local key = "idle"
		if item then
			key = makeKey(item.Category, item.Id)
			if item.Category == "Skin" then
				key ..= ":" .. tostring(showHelm)
			end
		end
		if key == currentPreviewKey and not force then
			return
		end
		currentPreviewKey = key

		if item then
			local rarityColor = getRarityColor(item)
			previewName.Text = item.DisplayName or item.Id
			previewHeader.Text = string.upper(getCategoryLabel(item.Category)) .. " PREVIEW"
			previewPanelStroke.Color = rarityColor
			previewPanelStroke.Transparency = 0.18
			previewViewportStroke.Color = rarityColor
			previewViewportStroke.Transparency = 0.18
			previewViewport.BackgroundColor3 = mixColor(Color3.fromRGB(8, 11, 21), rarityColor, item.Category == "Trail" and 0.16 or 0.08)
			pcall(function()
				previewController:ShowItem(item, showHelm)
			end)
		else
			previewName.Text = "Idle Avatar"
			previewHeader.Text = "PREVIEW"
			previewPanelStroke.Color = COLORS.Stroke
			previewViewportStroke.Color = COLORS.DimStroke
			pcall(function()
				previewController:ShowIdle()
			end)
		end
	end

	local function syncCard(record)
		local item = record.item
		local owned = isOwned(item)
		local equipped = isEquipped(item)
		local selected = selectedCategory == item.Category and selectedId == item.Id
		local rarityColor = getRarityColor(item)

		record.nameLabel.Text = item.DisplayName or item.Id
		record.stroke.Color = selected and COLORS.Gold or (equipped and COLORS.Green or rarityColor)
		record.stroke.Thickness = selected and 2.2 or (equipped and 1.8 or 1.2)
		record.stroke.Transparency = selected and 0 or (equipped and 0.14 or 0.34)
		record.card.BackgroundColor3 = selected and COLORS.CardSelected or (equipped and COLORS.CardEquipped or (owned and COLORS.Card or COLORS.CardLocked))
		if record.accentBar then
			record.accentBar.BackgroundColor3 = equipped and COLORS.Green or rarityColor
			record.accentBar.BackgroundTransparency = selected and 0 or 0.12
		end

		if equipped then
			record.statusLabel.Text = item.Category == "Emote" and ("Slot " .. tostring(getEmoteSlot(item.Id) or "")) or "EQUIPPED"
			record.statusLabel.TextColor3 = COLORS.Green
		elseif owned then
			record.statusLabel.Text = item.Category == "Trail" and "OWNED" or "EQUIP"
			record.statusLabel.TextColor3 = COLORS.Text
		else
			local price = tonumber(item.CoinPrice) or 0
			record.statusLabel.Text = price > 0 and formatCompactPrice(price) or (item.IsFree and "FREE" or "LOCKED")
			record.statusLabel.TextColor3 = price > 0 and COLORS.Gold or COLORS.Muted
		end

		if record.priceIcon then
			local showIcon = not owned and not equipped and (tonumber(item.CoinPrice) or 0) > 0 and record.statusLabel.Text ~= "LOCKED"
			record.priceIcon.Visible = showIcon
			if showIcon then
				record.statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				record.statusLabel.Position = UDim2.new(0.5, px(10), 0.5, 0)
				record.statusLabel.Size = UDim2.new(1, -px(36), 1, -px(4))
			else
				record.statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
				record.statusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
				record.statusLabel.Size = UDim2.new(1, -px(16), 1, -px(4))
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
			statusLabel.Text = ""
			setButtonMode(nil)
			updatePreview(nil)
			return
		end

		local rarityColor = getRarityColor(item)
		selectedName.Text = item.DisplayName or item.Id
		selectedDesc.Text = item.Description or ""
		categoryPill.Text = string.upper(getCategoryLabel(item.Category))
		categoryPill.TextColor3 = rarityColor
		categoryPillStroke.Color = rarityColor
		statusLabel.Text = getStatusText(item)
		statusLabel.TextColor3 = isEquipped(item) and COLORS.Green or ((tonumber(item.CoinPrice) or 0) > 0 and not isOwned(item) and COLORS.Gold or COLORS.Muted)
		keepHeadRow.Visible = item.Category == "Skin"
		syncKeepHeadToggle()

		local owned = isOwned(item)
		local price = tonumber(item.CoinPrice) or 0
		if item.Category == "Skin" then
			if owned then
				setButtonMode("primary")
				if isEquipped(item) then
					primaryButton.Text = "UNEQUIP"
					setButtonState(primaryButton, true, COLORS.RedDark)
				else
					primaryButton.Text = "EQUIP"
					setButtonState(primaryButton, true, COLORS.GreenDark)
				end
			else
				setButtonMode("coin_robux")
				local coinEnabled = price > 0
				syncPriceButtonContent(coinButtonContent, coinEnabled and ("BUY " .. formatNumber(price)) or "NO COINS", coinEnabled, getAsset("Coin"), coinEnabled)
				setButtonState(coinButton, coinEnabled, COLORS.Orange)
				local productId = tonumber(item.RobuxProductId) or 0
				local robuxEnabled = productId > 0
				local robuxPrice = tonumber(item.RobuxPrice)
				syncPriceButtonContent(robuxButtonContent, robuxEnabled and (robuxPrice and tostring(math.floor(robuxPrice)) or "ROBUX") or "NO ROBUX", robuxEnabled, getAsset("Robux"), robuxEnabled and robuxPrice ~= nil)
				setButtonState(robuxButton, robuxEnabled, COLORS.Blue)
			end
		elseif item.Category == "Trail" then
			if owned then
				setButtonMode("primary")
				if isEquipped(item) then
					primaryButton.Text = "EQUIPPED"
					setButtonState(primaryButton, false, COLORS.GreenDark)
				else
					primaryButton.Text = "EQUIP TRAIL"
					setButtonState(primaryButton, true, COLORS.GreenDark)
				end
			else
				setButtonMode("coin")
				local enabled = price > 0
				syncPriceButtonContent(coinButtonContent, enabled and ("BUY " .. formatNumber(price)) or "LOCKED", enabled, getAsset("Coin"), enabled)
				setButtonState(coinButton, enabled, COLORS.Orange)
			end
		elseif item.Category == "Emote" then
			if owned then
				setButtonMode("primary")
				local slot = getEmoteSlot(item.Id)
				if slot then
					primaryButton.Text = "UNEQUIP SLOT " .. tostring(slot)
					setButtonState(primaryButton, true, COLORS.RedDark)
				elseif countEquippedEmotes() >= emoteSlotCount then
					primaryButton.Text = "SLOTS FULL"
					setButtonState(primaryButton, false, COLORS.GreenDark)
				else
					primaryButton.Text = "EQUIP SLOT " .. tostring(countEquippedEmotes() + 1)
					setButtonState(primaryButton, true, COLORS.GreenDark)
				end
			else
				setButtonMode("coin")
				local enabled = price > 0 or item.IsFree == true
				local label = price > 0 and ("BUY " .. formatNumber(price)) or "FREE"
				syncPriceButtonContent(coinButtonContent, label, enabled, getAsset("Coin"), price > 0)
				setButtonState(coinButton, enabled, COLORS.Orange)
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
		updatePreview(item)
	end

	local function updateSectionGrid(record)
		local available = record.grid.AbsoluteSize.X
		if available <= 0 then
			return
		end
		local gap = dpx(STYLE.CardGap, 8)
		local targetWidth = dpx(record.cardWidth, record.minWidth)
		local targetHeight = dpx(record.cardHeight, record.minHeight)
		local columns = math.clamp(math.floor((available + gap) / (targetWidth + gap)), 1, record.maxColumns)
		local cellWidth = math.floor((available - gap * (columns - 1)) / columns)
		local rows = math.max(1, math.ceil(record.count / columns))
		record.layout.CellPadding = UDim2.fromOffset(gap, gap)
		record.layout.CellSize = UDim2.fromOffset(cellWidth, targetHeight)
		record.grid.Size = UDim2.new(1, 0, 0, rows * targetHeight + math.max(0, rows - 1) * gap)
	end

	local function createSection(section, sectionIndex)
		local meta = SECTION_META[section.Id] or {}
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

		local headerRow = Instance.new("Frame")
		headerRow.Name = "SectionHeader"
		headerRow.BackgroundTransparency = 1
		headerRow.Size = UDim2.new(1, 0, 0, px(40))
		headerRow.LayoutOrder = 1
		headerRow.Parent = sectionFrame

		local accent = Instance.new("Frame")
		accent.BackgroundColor3 = meta.Accent or COLORS.Gold
		accent.BorderSizePixel = 0
		accent.Position = UDim2.new(0, 0, 1, -px(3))
		accent.Size = UDim2.new(1, 0, 0, px(2))
		accent.Parent = headerRow
		applyCorners(accent, px(2))

		local headerLabel = Instance.new("TextLabel")
		headerLabel.BackgroundTransparency = 1
		headerLabel.Position = UDim2.new(0, 0, 0, 0)
		headerLabel.Size = UDim2.new(0.5, 0, 0, px(26))
		headerLabel.Font = Enum.Font.FredokaOne
		headerLabel.Text = section.Header or section.Id
		headerLabel.TextColor3 = COLORS.Text
		headerLabel.TextSize = px(STYLE.SectionHeaderTextSize)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.Parent = headerRow

		local subtitle = Instance.new("TextLabel")
		subtitle.BackgroundTransparency = 1
		subtitle.AnchorPoint = Vector2.new(1, 0)
		subtitle.Position = UDim2.new(1, 0, 0, px(4))
		subtitle.Size = UDim2.new(0.48, 0, 0, px(20))
		subtitle.Font = Enum.Font.GothamBold
		subtitle.Text = string.format("%s  -  %d", meta.Subtitle or "Cosmetics", #(section.Items or {}))
		subtitle.TextColor3 = COLORS.Muted
		subtitle.TextSize = px(STYLE.CardSubtitleTextSize)
		subtitle.TextXAlignment = Enum.TextXAlignment.Right
		subtitle.TextTruncate = Enum.TextTruncate.AtEnd
		subtitle.Parent = headerRow

		local grid = Instance.new("Frame")
		grid.Name = section.Id .. "Grid"
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, 0, 0, px(100))
		grid.LayoutOrder = 2
		grid.Parent = sectionFrame

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		gridLayout.Parent = grid

		local isSkin = section.Category == "Skin"
		local record = {
			grid = grid,
			layout = gridLayout,
			count = #(section.Items or {}),
			cardWidth = isSkin and STYLE.SkinCardWidth or STYLE.CompactCosmeticCardWidth,
			cardHeight = isSkin and STYLE.SkinCardHeight or STYLE.CompactCosmeticCardHeight,
			minWidth = isSkin and 132 or 180,
			minHeight = isSkin and 164 or 114,
			maxColumns = isSkin and 5 or 4,
		}
		table.insert(sectionRecords, record)
		return grid
	end

	local function createTrailVisual(parent, item, compact)
		local visual = Instance.new("Frame")
		visual.Name = "TrailVisual"
		visual.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
		visual.BorderSizePixel = 0
		visual.Size = compact and UDim2.fromOffset(px(56), px(56)) or UDim2.new(1, -px(14), 0, px(66))
		visual.AnchorPoint = compact and Vector2.new(0, 0) or Vector2.new(0, 0)
		visual.Position = compact and UDim2.new(0, px(STYLE.CompactCardPadding), 0, px(STYLE.CompactCardPadding)) or UDim2.new(0, px(7), 0, px(36))
		visual.Parent = parent
		applyCorners(visual, px(10))
		applyStroke(visual, item.Color or COLORS.Blue, 1, 0.28)

		for i = 1, 3 do
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = item.Color or COLORS.White
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.new(0.5, 0, 0.3 + i * 0.14, 0)
			bar.Size = UDim2.new(0.72 - i * 0.07, 0, 0, px(compact and 5 or 7))
			bar.Rotation = -12
			bar.Parent = visual
			applyCorners(bar, px(5))
			if item.IsRainbow and item.TrailColorSequence then
				local gradient = Instance.new("UIGradient")
				gradient.Color = item.TrailColorSequence
				gradient.Parent = bar
			end
		end
		return visual
	end

	local function createEmoteVisual(parent, item)
		local iconAsset = resolveEmoteIconAsset(item)
		local accentColor = COLORS.Gold
		local iconBox = Instance.new("Frame")
		iconBox.Name = "EmoteVisual"
		iconBox.BackgroundColor3 = mixColor(COLORS.SurfaceSoft, accentColor, 0.13)
		iconBox.BorderSizePixel = 0
		iconBox.Position = UDim2.new(0, px(STYLE.CompactCardPadding), 0, px(STYLE.CompactCardPadding))
		iconBox.Size = UDim2.fromOffset(px(56), px(56))
		iconBox.ClipsDescendants = true
		iconBox.Parent = parent
		applyCorners(iconBox, px(12))
		applyStroke(iconBox, accentColor, 1, 0.34)

		if iconAsset then
			local image = Instance.new("ImageLabel")
			image.Name = "IconImage"
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.Size = UDim2.fromScale(0.72, 0.72)
			image.Image = iconAsset
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = iconBox
		else
			createFallbackEmoteGlyph(iconBox, item, accentColor)
		end
		return iconBox
	end

	local function createStatusPill(parent, xScale)
		local pill = Instance.new("Frame")
		pill.Name = "StatusPill"
		pill.BackgroundColor3 = COLORS.SurfaceSoft
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(xScale or 0.5, 0, 1, -px(8))
		pill.Size = UDim2.new(1, -px(16), 0, px(26))
		pill.Parent = parent
		applyCorners(pill, px(8))
		applyStroke(pill, COLORS.DimStroke, 1, 0.42)

		local icon = Instance.new("ImageLabel")
		icon.Name = "PriceIcon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, px(10), 0.5, 0)
		icon.Size = UDim2.fromOffset(px(16), px(16))
		icon.Image = getAsset("Coin") or ""
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Visible = false
		icon.Parent = pill

		local label = Instance.new("TextLabel")
		label.Name = "StatusLabel"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.Size = UDim2.new(1, -px(16), 1, -px(4))
		label.Font = Enum.Font.GothamBlack
		label.Text = ""
		label.TextColor3 = COLORS.Text
		label.TextSize = px(STYLE.CardButtonTextSize)
		label.TextScaled = true
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Parent = pill
		addTextLimit(label, px(11), px(STYLE.CardButtonTextSize))

		return pill, label, icon
	end

	local function createSkinCard(parentFrame, item, index)
		local rarityColor = getRarityColor(item)
		local button = Instance.new("TextButton")
		button.Name = "Skin_" .. item.Id .. "Card"
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.LayoutOrder = index
		button.Parent = parentFrame

		local card = Instance.new("Frame")
		card.BackgroundColor3 = COLORS.Card
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(1, 1)
		card.Parent = button
		applyCorners(card, px(12))
		local stroke = applyStroke(card, rarityColor, 1.2, 0.34)

		local accentBar = Instance.new("Frame")
		accentBar.BackgroundColor3 = rarityColor
		accentBar.BorderSizePixel = 0
		accentBar.Size = UDim2.new(1, 0, 0, px(3))
		accentBar.Parent = card
		applyCorners(accentBar, px(2))

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, px(10), 0, px(8))
		nameLabel.Size = UDim2.new(1, -px(20), 0, px(24))
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = item.DisplayName or item.Id
		nameLabel.TextColor3 = COLORS.Text
		nameLabel.TextSize = px(STYLE.SkinCardTitleTextSize)
		nameLabel.TextScaled = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card
		addTextLimit(nameLabel, px(13), px(STYLE.SkinCardTitleTextSize))

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Preview"
		viewport.BackgroundColor3 = mixColor(COLORS.Surface, rarityColor, 0.10)
		viewport.BorderSizePixel = 0
		viewport.Position = UDim2.new(0, px(9), 0, px(34))
		viewport.Size = UDim2.new(1, -px(18), 1, -px(70))
		viewport.Ambient = Color3.fromRGB(190, 190, 200)
		viewport.LightColor = COLORS.White
		viewport.LightDirection = Vector3.new(0, -1, -1)
		viewport.Parent = card
		applyCorners(viewport, px(10))
		pcall(function()
			SkinThumbnailPreview.Update(viewport, item.Id, showHelm)
		end)

		local _, statusLabelRef, priceIcon = createStatusPill(card, 0.5)
		local record = { key = makeKey(item.Category, item.Id), item = item, button = button, card = card, stroke = stroke, accentBar = accentBar, nameLabel = nameLabel, statusLabel = statusLabelRef, priceIcon = priceIcon, viewport = viewport }
		cardRecords[record.key] = record

		trackConn(button.MouseButton1Click:Connect(function()
			selectItem(item)
		end))
		trackConn(button.MouseEnter:Connect(function()
			if not (selectedCategory == item.Category and selectedId == item.Id) then
				TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = COLORS.CardHover }):Play()
			end
		end))
		trackConn(button.MouseLeave:Connect(function()
			syncCard(record)
		end))
		return record
	end

	local function createCompactCard(parentFrame, item, index)
		local rarityColor = getRarityColor(item)
		local button = Instance.new("TextButton")
		button.Name = item.Category .. "_" .. item.Id .. "Card"
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.LayoutOrder = index
		button.Parent = parentFrame

		local card = Instance.new("Frame")
		card.BackgroundColor3 = COLORS.Card
		card.BorderSizePixel = 0
		card.Size = UDim2.fromScale(1, 1)
		card.Parent = button
		applyCorners(card, px(12))
		local stroke = applyStroke(card, rarityColor, 1.2, 0.38)

		local accentBar = Instance.new("Frame")
		accentBar.BackgroundColor3 = rarityColor
		accentBar.BorderSizePixel = 0
		accentBar.Position = UDim2.new(0, 0, 0, 0)
		accentBar.Size = UDim2.new(0, px(4), 1, 0)
		accentBar.Parent = card
		applyCorners(accentBar, px(3))

		if item.Category == "Trail" then
			createTrailVisual(card, item, true)
		else
			createEmoteVisual(card, item)
		end

		local pad = px(STYLE.CompactCardPadding)
		local visualSize = px(56)
		local textLeft = pad + visualSize + px(10)
		local buttonHeight = px(STYLE.CompactButtonHeight)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, textLeft, 0, pad)
		nameLabel.Size = UDim2.new(1, -(textLeft + pad), 0, px(24))
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.Text = item.DisplayName or item.Id
		nameLabel.TextColor3 = COLORS.Text
		nameLabel.TextSize = px(STYLE.CardTitleTextSize)
		nameLabel.TextScaled = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card
		addTextLimit(nameLabel, px(13), px(STYLE.CardTitleTextSize))

		local subLabel = Instance.new("TextLabel")
		subLabel.BackgroundTransparency = 1
		subLabel.Position = UDim2.new(0, textLeft, 0, pad + px(26))
		subLabel.Size = UDim2.new(1, -(textLeft + pad), 0, px(18))
		subLabel.Font = Enum.Font.GothamMedium
		subLabel.Text = item.Category == "Trail" and (item.Rarity or "Effect") or "Emote"
		subLabel.TextColor3 = COLORS.Muted
		subLabel.TextSize = px(STYLE.CardSubtitleTextSize)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.Parent = card
		addTextLimit(subLabel, px(10), px(STYLE.CardSubtitleTextSize))

		local pill, statusLabelRef, priceIcon = createStatusPill(card, 0.5)
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -pad)
		pill.Size = UDim2.new(1, -pad * 2, 0, buttonHeight)

		local record = { key = makeKey(item.Category, item.Id), item = item, button = button, card = card, stroke = stroke, accentBar = accentBar, nameLabel = nameLabel, statusLabel = statusLabelRef, priceIcon = priceIcon }
		cardRecords[record.key] = record

		trackConn(button.MouseButton1Click:Connect(function()
			selectItem(item)
		end))
		trackConn(button.MouseEnter:Connect(function()
			if not (selectedCategory == item.Category and selectedId == item.Id) then
				TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = COLORS.CardHover }):Play()
			end
		end))
		trackConn(button.MouseLeave:Connect(function()
			syncCard(record)
		end))
		return record
	end

	for sectionIndex, section in ipairs(sections) do
		if #(section.Items or {}) > 0 then
			local sectionGrid = createSection(section, sectionIndex)
			for itemIndex, item in ipairs(section.Items) do
				if item.Category == "Skin" then
					createSkinCard(sectionGrid, item, itemIndex)
				else
					createCompactCard(sectionGrid, item, itemIndex)
				end
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

	local function applyResponsiveLayout()
		local vp = getViewportSize()
		if vp.X < vp.Y then
			panel.Size = UDim2.fromScale(0.96, 0.92)
		else
			panel.Size = UDim2.fromScale(0.84, 0.86)
		end
		panelConstraint.MaxSize = Vector2.new(math.max(820, math.floor(vp.X * 0.92)), math.max(560, math.floor(vp.Y * 0.92)))
		local previewWidth = math.clamp(px(STYLE.RightPreviewPanelWidth), STYLE.RightPreviewMinWidth, STYLE.RightPreviewMaxWidth)
		previewPanel.Size = UDim2.new(0, previewWidth, 1, 0)
		listPanel.Size = UDim2.new(1, -(previewWidth + px(STYLE.BodyGap)), 1, 0)
		for _, record in ipairs(sectionRecords) do
			updateSectionGrid(record)
		end
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
			cameraViewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveLayout)
			trackConn(cameraViewportConn)
		end
	end
	trackConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewportListener()
		applyResponsiveLayout()
	end))
	bindViewportListener()
	task.defer(applyResponsiveLayout)

	local function refreshOwnedEffectsFromServer()
		local ok, list = invokeRemote(remotes.getOwnedEffectsRF)
		if ok and type(list) == "table" then
			ownedEffects = makeIdSet(list, { DefaultTrail = true })
		end
	end

	local function refreshEquippedEffectsFromServer()
		local ok, equipped = invokeRemote(remotes.getEquippedEffectsRF)
		if ok and type(equipped) == "table" then
			if type(equipped.DashTrail) == "string" and equipped.DashTrail ~= "" then
				equippedTrailId = equipped.DashTrail
			else
				equippedTrailId = "DefaultTrail"
			end
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
	updatePreview(getSelectedItem(), true)

	trackConn(root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible then
			updatePreview(getSelectedItem(), true)
		elseif previewController then
			previewController:Stop()
			currentPreviewKey = nil
		end
	end))

	trackConn(closeButton.MouseButton1Click:Connect(function()
		if previewController then
			previewController:Stop()
			currentPreviewKey = nil
		end
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
		refreshAllSkinThumbnails()
		updatePreview(item, true)
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
				showToast("All emote slots are full.", COLORS.Red)
			end
		end
	end))

	trackConn(coinButton.MouseButton1Click:Connect(function()
		if not coinButton:GetAttribute("EnabledState") then
			showToast("This cosmetic is not available for coin purchase.", COLORS.CardLocked)
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
			showToast("Purchase failed.", COLORS.Red)
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
			showToast("Purchased " .. tostring(item.DisplayName or item.Id) .. ".", COLORS.GreenDark)
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
		showToast(reasonText, COLORS.Red)
		refreshUi()
	end))

	trackConn(robuxButton.MouseButton1Click:Connect(function()
		local item = getSelectedItem()
		if not item or item.Category ~= "Skin" then
			return
		end
		local productId = tonumber(item.RobuxProductId) or 0
		if productId <= 0 then
			showToast("Robux purchase is not configured for this skin.", COLORS.Red)
			return
		end
		showToast("Complete the Roblox purchase prompt to unlock this skin.", COLORS.Blue)
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
		if not ok then
			warn("[CosmeticsStallUI] PromptProductPurchase failed:", tostring(err))
			showToast("Robux purchase prompt failed.", COLORS.Red)
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
		if previewController then
			previewController:Stop()
		end
		cleanupConnections()
	end)

	return root
end

return SkinsStallUI
