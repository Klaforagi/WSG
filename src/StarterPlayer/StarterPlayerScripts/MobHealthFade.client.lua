--[[
	MobHealthFade.client.lua
	Fades mob overhead health bars in/out based on distance from the local player.
	Pairs with MobOverheadHealth.server.lua.
--]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local BILLBOARD_NAME = "MobOverheadHealth"

-- Distance band: UI is barely visible at FADE_START (the billboard's MaxDistance),
-- and fully opaque at FADE_FULL. Alpha ramps linearly from 0.01 → 1 across this range.
local FADE_START = 55   -- studs — matches MaxDistance; barely visible here
local FADE_FULL  = 22   -- studs — fully opaque

-- Base (fully-visible) transparencies for each element.
-- Must stay in sync with buildBillboard in MobOverheadHealth.server.lua.
local BASE = {
	barShadowBG  = 0.60, -- BarShadow drop-shadow frame
	barOuterBG   = 0.50, -- BarOuter frame background
	fillBG       = 0,    -- Fill frame background
	damageBarBG  = 0,    -- DamageBar frame background
	nameText     = 0,    -- NameLabel TextTransparency
	nameUIStroke = 0.1,  -- NameStroke UIStroke.Transparency
	hpText       = 0,    -- HPText TextTransparency
	hpUIStroke   = 0.15, -- HPStroke UIStroke.Transparency
	barStroke    = 0.35, -- BarStroke UIStroke.Transparency
}

local localPlayer = Players.LocalPlayer

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- alpha: 0 = invisible, 1 = fully visible
local function applyAlpha(billboard, alpha)
	local bg = billboard:FindFirstChild("Background")
	if not bg then return end

	local nameLabel  = bg:FindFirstChild("NameLabel")
	local nameStroke = nameLabel and nameLabel:FindFirstChild("NameStroke")
	local barShadow  = bg:FindFirstChild("BarShadow")
	local barOuter   = bg:FindFirstChild("BarOuter")
	local barStroke  = barOuter and barOuter:FindFirstChild("BarStroke")
	local fill       = barOuter and barOuter:FindFirstChild("Fill")
	local damageBar  = barOuter and barOuter:FindFirstChild("DamageBar")
	local hpText     = barOuter and barOuter:FindFirstChild("HPText")
	local hpStroke   = hpText and hpText:FindFirstChild("HPStroke")

	if nameLabel then
		nameLabel.TextTransparency = lerp(1, BASE.nameText, alpha)
		-- TextStrokeTransparency is disabled (= 1); UIStroke below handles it
	end

	if nameStroke then
		nameStroke.Transparency = lerp(1, BASE.nameUIStroke, alpha)
	end

	if barShadow then
		barShadow.BackgroundTransparency = lerp(1, BASE.barShadowBG, alpha)
	end

	if barOuter then
		barOuter.BackgroundTransparency = lerp(1, BASE.barOuterBG, alpha)
	end

	if barStroke then
		barStroke.Transparency = lerp(1, BASE.barStroke, alpha)
	end

	if fill then
		fill.BackgroundTransparency = lerp(1, BASE.fillBG, alpha)
	end

	if damageBar then
		damageBar.BackgroundTransparency = lerp(1, BASE.damageBarBG, alpha)
	end

	if hpText then
		hpText.TextTransparency       = lerp(1, BASE.hpText, alpha)
		hpText.TextStrokeTransparency = 1  -- disabled; UIStroke handles it
	end

	if hpStroke then
		hpStroke.Transparency = lerp(1, BASE.hpUIStroke, alpha)
	end
end

RunService.Heartbeat:Connect(function()
	local character = localPlayer.Character
	local root = character and (
		character:FindFirstChild("HumanoidRootPart") or
		character:FindFirstChild("Torso")
	)
	if not root then return end

	local playerPos = root.Position

	-- Walk all BillboardGuis in Workspace named MobOverheadHealth
	for _, billboard in ipairs(Workspace:GetDescendants()) do
		if billboard:IsA("BillboardGui") and billboard.Name == BILLBOARD_NAME and billboard.Enabled then
			local part = billboard.Parent
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				local t = 1 - math.clamp((dist - FADE_FULL) / (FADE_START - FADE_FULL), 0, 1)
				-- Remap so the far edge is 0.01 (barely visible) not 0 (invisible pop-in)
				local alpha = 0.01 + t * 0.99
				applyAlpha(billboard, alpha)
			end
		end
	end
end)
