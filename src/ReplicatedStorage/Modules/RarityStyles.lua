--------------------------------------------------------------------------------
-- RarityStyles.lua
-- Shared UI rarity palette and lightweight label/card helpers.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrateConfig = nil
pcall(function()
	local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
	if mod and mod:IsA("ModuleScript") then
		CrateConfig = require(mod)
	end
end)

local RarityStyles = {}

RarityStyles.Colors = {
	Common = Color3.fromRGB(150, 150, 155),
	Uncommon = Color3.fromRGB(120, 200, 120),
	Rare = Color3.fromRGB(60, 140, 255),
	Epic = Color3.fromRGB(180, 60, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
}

RarityStyles.BgColors = {
	Common = Color3.fromRGB(42, 44, 55),
	Uncommon = Color3.fromRGB(22, 48, 36),
	Rare = Color3.fromRGB(22, 38, 68),
	Epic = Color3.fromRGB(46, 22, 65),
	Legendary = Color3.fromRGB(58, 46, 18),
}

RarityStyles.WeaponCardBg = {
	Common = Color3.fromRGB(105, 110, 120),
	Uncommon = Color3.fromRGB(56, 131, 49),
	Rare = Color3.fromRGB(45, 90, 175),
	Epic = Color3.fromRGB(114, 38, 176),
	Legendary = Color3.fromRGB(195, 150, 25),
}

RarityStyles.WeaponCardBorder = {
	Common = Color3.fromRGB(70, 75, 82),
	Uncommon = Color3.fromRGB(60, 110, 80),
	Rare = Color3.fromRGB(30, 62, 125),
	Epic = Color3.fromRGB(70, 30, 90),
	Legendary = Color3.fromRGB(140, 108, 16),
}

local function normalizeRarity(rarity)
	local text = type(rarity) == "string" and rarity or "Common"
	if RarityStyles.Colors[text] then
		return text
	end
	local lowered = string.lower(text)
	for known in pairs(RarityStyles.Colors) do
		if string.lower(known) == lowered then
			return known
		end
	end
	return text ~= "" and text or "Common"
end

function RarityStyles.Normalize(rarity)
	return normalizeRarity(rarity)
end

function RarityStyles.GetColor(rarity)
	local normalized = normalizeRarity(rarity)
	local color = RarityStyles.Colors[normalized]
	if color then
		return color
	end
	local def = CrateConfig and CrateConfig.Rarities and CrateConfig.Rarities[normalized]
	if def and typeof(def.color) == "Color3" then
		return def.color
	end
	return RarityStyles.Colors.Common
end

function RarityStyles.GetBgColor(rarity)
	return RarityStyles.BgColors[normalizeRarity(rarity)] or RarityStyles.BgColors.Common
end

function RarityStyles.GetWeaponCardBg(rarity)
	return RarityStyles.WeaponCardBg[normalizeRarity(rarity)] or RarityStyles.WeaponCardBg.Common
end

function RarityStyles.GetWeaponCardBorder(rarity)
	return RarityStyles.WeaponCardBorder[normalizeRarity(rarity)] or RarityStyles.WeaponCardBorder.Common
end

function RarityStyles.BrightenColor(color, amount)
	amount = amount or 0.06
	return Color3.new(
		math.clamp(color.R + amount, 0, 1),
		math.clamp(color.G + amount, 0, 1),
		math.clamp(color.B + amount, 0, 1)
	)
end

function RarityStyles.ShadeColor(color, factor)
	factor = factor or 0.6
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

function RarityStyles.AddTextOutline(label, transparency, thickness)
	if not label then
		return nil
	end
	local outline = label:FindFirstChild("RarityTextOutline")
	if not outline then
		outline = Instance.new("UIStroke")
		outline.Name = "RarityTextOutline"
		outline.Parent = label
	end
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = thickness or 1
	outline.Transparency = transparency or 0.3
	return outline
end

function RarityStyles.ApplyToText(label, rarity, options)
	if not label then
		return nil
	end
	options = type(options) == "table" and options or {}
	local normalized = normalizeRarity(rarity)
	label.TextColor3 = RarityStyles.GetColor(normalized)
	if options.font then
		label.Font = options.font
	end
	if options.text ~= nil then
		label.Text = tostring(options.text)
	elseif options.setText ~= false then
		label.Text = normalized
	end
	if options.outline ~= false then
		RarityStyles.AddTextOutline(label, options.outlineTransparency or 0.3, options.outlineThickness or 1)
	end
	return normalized
end

function RarityStyles.AddCardSheen(parent, accentColor, pxFn, heightScale)
	if not parent then
		return nil
	end
	local px = type(pxFn) == "function" and pxFn or function(value) return value end
	local scale = tonumber(heightScale) or 0.36
	if scale < 0 then scale = 0 end
	if scale > 1 then scale = 1 end
	local sheen = Instance.new("Frame")
	sheen.Name = "CardSheen"
	sheen.BackgroundColor3 = RarityStyles.BrightenColor(accentColor or Color3.new(1, 1, 1), 0.08)
	sheen.BackgroundTransparency = 0.78
	sheen.BorderSizePixel = 0
	sheen.Size = UDim2.new(1, 0, scale, 0)
	sheen.ZIndex = 1
	sheen.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px(10))
	corner.Parent = sheen
	return sheen
end

return RarityStyles