--[[
	MobHealthFade.client.lua
	Shows overhead health bars instantly (no fade tween) based on visibility rules.
	Names stay visible; Options toggles hide only the health-bar pieces.
	Pairs with MobOverheadHealth.server.lua.
--]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local BILLBOARD_NAME = "MobOverheadHealth"
local OWNER_TYPE_ATTRIBUTE = "OverheadOwnerType"
local DEFAULT_NAME_POSITION = UDim2.new(0, 0, 0, 1)
local DEFAULT_NAME_SIZE = UDim2.new(1, 0, 0, 16)
local LOCAL_NAME_ONLY_POSITION = UDim2.new(0, 0, 0, 22)
local LOCAL_NAME_ONLY_SIZE = UDim2.new(1, 0, 0, 18)
local MARKER_SWAP_DISTANCE = 55

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

local DEFAULT_MY_HEALTH_DISPLAY_MODE = "BottomLeft"
local VALID_MY_HEALTH_DISPLAY_MODES = {
	BottomLeft = true,
	AboveCharacter = true,
	Both = true,
}

local function getLocalHealthDisplayMode()
	local settings = _G.PlayerSettings
	local mode = _G.MyHealthDisplayMode
	if type(settings) == "table" and settings.MyHealthDisplayMode ~= nil then
		mode = settings.MyHealthDisplayMode
	end
	if VALID_MY_HEALTH_DISPLAY_MODES[mode] then
		return mode
	end
	return DEFAULT_MY_HEALTH_DISPLAY_MODE
end

local function shouldShowLocalOverheadHealth()
	local mode = getLocalHealthDisplayMode()
	return mode == "AboveCharacter" or mode == "Both"
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function getOwnerType(billboard)
	local ownerType = billboard:GetAttribute(OWNER_TYPE_ATTRIBUTE)
	if ownerType == "Player" then
		return "Player"
	end
	return "NPC"
end

local function isLocalPlayerBillboard(billboard)
	local character = localPlayer and localPlayer.Character
	if not character then
		return false
	end
	return billboard:IsDescendantOf(character)
		or (billboard.Parent and billboard.Parent:IsDescendantOf(character))
end

local function getBillboardPlayer(billboard)
	local character = billboard and billboard.Parent and billboard.Parent.Parent
	if not character or not character:IsA("Model") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function isTeammateBillboard(billboard)
	local billboardPlayer = getBillboardPlayer(billboard)
	if not billboardPlayer then
		return false
	end
	if billboardPlayer == localPlayer then
		return false
	end
	local myTeam = localPlayer and localPlayer.Team
	local theirTeam = billboardPlayer.Team
	return myTeam and theirTeam and myTeam == theirTeam
end

local function healthBarsEnabled(billboard)
	if getOwnerType(billboard) == "Player" and isLocalPlayerBillboard(billboard) then
		return shouldShowLocalOverheadHealth()
	end
	if getOwnerType(billboard) == "Player" then
		if isTeammateBillboard(billboard) then
			return _G.ShowTeammateHealthBars == true
		end
		return _G.ShowEnemyHealthBars ~= false
	end
	return _G.ShowNPCHealthBars ~= false
end

local function shouldUseMarkerForPlayerBillboard(billboard, dist)
	if getOwnerType(billboard) ~= "Player" then
		return false
	end
	if isLocalPlayerBillboard(billboard) then
		return false
	end
	if _G.ShowPlayerMarkers == false then
		return false
	end
	if dist <= MARKER_SWAP_DISTANCE then
		return false
	end
	local targetPlayer = getBillboardPlayer(billboard)
	if not targetPlayer then
		return false
	end
	local carryingFlag = targetPlayer:GetAttribute("CarryingFlag")
	if type(carryingFlag) == "string" and carryingFlag ~= "" then
		return false
	end
	return true
end

local function getElements(billboard)
	local bg = billboard:FindFirstChild("Background")
	if not bg then return nil end

	local nameLabel  = bg:FindFirstChild("NameLabel")
	local barShadow  = bg:FindFirstChild("BarShadow")
	local barOuter   = bg:FindFirstChild("BarOuter")
	local hpText     = barOuter and barOuter:FindFirstChild("HPText")

	return {
		nameLabel = nameLabel,
		nameStroke = nameLabel and nameLabel:FindFirstChild("NameStroke"),
		barShadow = barShadow,
		barOuter = barOuter,
		barStroke = barOuter and barOuter:FindFirstChild("BarStroke"),
		fill = barOuter and barOuter:FindFirstChild("Fill"),
		damageBar = barOuter and barOuter:FindFirstChild("DamageBar"),
		hpText = hpText,
		hpStroke = hpText and hpText:FindFirstChild("HPStroke"),
	}
end

local function applyNameVisibility(elements, billboard)
	if elements.nameLabel then
		local nameOnlyMode = false
		if billboard and isLocalPlayerBillboard(billboard) then
			nameOnlyMode = not shouldShowLocalOverheadHealth()
		elseif billboard and getOwnerType(billboard) == "Player" and isTeammateBillboard(billboard)
			and _G.ShowTeammateHealthBars ~= true then
			nameOnlyMode = true
		end

		if nameOnlyMode then
			elements.nameLabel.Position = LOCAL_NAME_ONLY_POSITION
			elements.nameLabel.Size = LOCAL_NAME_ONLY_SIZE
		else
			elements.nameLabel.Position = DEFAULT_NAME_POSITION
			elements.nameLabel.Size = DEFAULT_NAME_SIZE
		end
		elements.nameLabel.TextTransparency = BASE.nameText
		elements.nameLabel.TextStrokeTransparency = 1
	end
	if elements.nameStroke then
		elements.nameStroke.Transparency = BASE.nameUIStroke
	end
end

local function applyHealthBarVisibility(elements, visible)
	if elements.barShadow then
		elements.barShadow.Visible = visible
	end
	if elements.barOuter then
		elements.barOuter.Visible = visible
	end
end

local function applyBillboardSettings(billboard)
	local elements = getElements(billboard)
	if not elements then return end
	applyNameVisibility(elements, billboard)
	applyHealthBarVisibility(elements, healthBarsEnabled(billboard))
end

local function refreshOverheadUISettings()
	for _, billboard in ipairs(Workspace:GetDescendants()) do
		if billboard:IsA("BillboardGui") and billboard.Name == BILLBOARD_NAME then
			applyBillboardSettings(billboard)
		end
	end
end

_G.RefreshOverheadUISettings = refreshOverheadUISettings

-- alpha: 0 = invisible, 1 = fully visible
local function applyAlpha(billboard, alpha)
	local elements = getElements(billboard)
	if not elements then return end

	applyNameVisibility(elements, billboard)

	local showHealthBar = healthBarsEnabled(billboard)
	applyHealthBarVisibility(elements, showHealthBar)
	if not showHealthBar then return end

	if elements.barShadow then
		elements.barShadow.BackgroundTransparency = lerp(1, BASE.barShadowBG, alpha)
	end

	if elements.barOuter then
		elements.barOuter.BackgroundTransparency = lerp(1, BASE.barOuterBG, alpha)
	end

	if elements.barStroke then
		elements.barStroke.Transparency = lerp(1, BASE.barStroke, alpha)
	end

	if elements.fill then
		elements.fill.BackgroundTransparency = lerp(1, BASE.fillBG, alpha)
	end

	if elements.damageBar then
		elements.damageBar.BackgroundTransparency = lerp(1, BASE.damageBarBG, alpha)
	end

	if elements.hpText then
		elements.hpText.TextTransparency       = lerp(1, BASE.hpText, alpha)
		elements.hpText.TextStrokeTransparency = 1  -- disabled; UIStroke handles it
	end

	if elements.hpStroke then
		elements.hpStroke.Transparency = lerp(1, BASE.hpUIStroke, alpha)
	end
end

Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("BillboardGui") and inst.Name == BILLBOARD_NAME then
		task.defer(function()
			if inst.Parent then
				applyBillboardSettings(inst)
			end
		end)
	end
end)

refreshOverheadUISettings()

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
		if billboard:IsA("BillboardGui") and billboard.Name == BILLBOARD_NAME then
			local part = billboard.Parent
			if part and part:IsA("BasePart") then
				local dist = (part.Position - playerPos).Magnitude
				local markerMode = shouldUseMarkerForPlayerBillboard(billboard, dist)
				billboard.Enabled = not markerMode
				if markerMode then
					continue
				end
				applyAlpha(billboard, 1)
			end
		end
	end
end)
