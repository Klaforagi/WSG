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

-- Base (fully-visible) transparencies for each element
local BASE = {
	barTrackBG    = 0.25, -- BarTrack background
	fillBG        = 0,    -- Fill background
	nameText      = 0,
	nameStroke    = 0.3,
	hpText        = 0,
	hpStroke      = 0.4,
}

local localPlayer = Players.LocalPlayer

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- alpha: 0 = invisible, 1 = fully visible
local function applyAlpha(billboard, alpha)
	local bg = billboard:FindFirstChild("Background")
	if not bg then return end

	local nameLabel = bg:FindFirstChild("NameLabel")
	local barTrack  = bg:FindFirstChild("BarTrack")
	local fill      = barTrack and barTrack:FindFirstChild("Fill")
	local hpText    = barTrack and barTrack:FindFirstChild("HPText")

	if nameLabel then
		nameLabel.TextTransparency       = lerp(1, BASE.nameText,   alpha)
		nameLabel.TextStrokeTransparency = lerp(1, BASE.nameStroke, alpha)
	end

	if barTrack then
		barTrack.BackgroundTransparency = lerp(1, BASE.barTrackBG, alpha)
	end

	if fill then
		fill.BackgroundTransparency = lerp(1, BASE.fillBG, alpha)
	end

	if hpText then
		hpText.TextTransparency       = lerp(1, BASE.hpText,  alpha)
		hpText.TextStrokeTransparency = lerp(1, BASE.hpStroke, alpha)
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
