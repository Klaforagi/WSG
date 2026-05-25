--[[
	MobOverheadHealth.server.lua
	- Disables default Roblox humanoid name/health display for all players and mobs.
	- Adds the shared polished overhead name + health UI to every player and mob.
	- Visual animations (smooth tween, damage lag bar, hit flash) are handled
	  client-side in MobHealthBar.client.lua.
	Mob detection: CollectionService tag "ZombieNPC" or "PracticeDummy",
	               OR model name "Dummy", OR Humanoid + attribute IsMob = true.
--]]

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local MOB_TAG              = "ZombieNPC"
local PRACTICE_DUMMY_TAG   = "PracticeDummy"
local BILLBOARD_NAME       = "MobOverheadHealth"
local OWNER_TYPE_ATTRIBUTE = "OverheadOwnerType"
local ATTACHED_ATTRIBUTE   = "_overheadUIAttached"
local BILLBOARD_SIZE       = UDim2.fromOffset(200, 50)
local NPC_NAMEPLATE_OFFSET = Vector3.new(0, 3.5, 0)
local PLAYER_NAMEPLATE_OFFSET = Vector3.new(0, 1.25, 0)
local NAMEPLATE_OFFSET_PADDING = 0.65
local NAMEPLATE_OFFSET_MAX_Y = 6
local NAMEPLATE_OFFSET_RECALC_DELAY = 0.15
local PLAYER_NAMEPLATE_MAX_DISTANCE = 45
local NPC_NAMEPLATE_MAX_DISTANCE    = 35
local DEBUG_OVERHEAD_OFFSET = false

-- Health-percent color thresholds (mirrored in MobHealthBar.client.lua)
local COLOR_HIGH = Color3.fromRGB(80, 210, 80)
local COLOR_MID  = Color3.fromRGB(235, 165, 40)
local COLOR_LOW  = Color3.fromRGB(210, 55, 55)
local COLOR_DMG  = Color3.fromRGB(180, 40, 40)
local PLAYER_TEAM_COLOR_FALLBACK = Color3.fromRGB(80, 220, 120)

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function isMob(model)
	if not model or not model:IsA("Model") then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	if Players:GetPlayerFromCharacter(model) then return false end
	if CollectionService:HasTag(model, MOB_TAG) then return true end
	if CollectionService:HasTag(model, PRACTICE_DUMMY_TAG) then return true end
	if model.Name == "Dummy" then return true end
	if model:GetAttribute("IsMob") == true then return true end
	return false
end

local function getAttachPart(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function healthColor(pct)
	if pct > 0.6 then return COLOR_HIGH
	elseif pct > 0.3 then return COLOR_MID
	else return COLOR_LOW end
end

local function getPlayerTeamColor(player)
	local team = player and player.Team
	if team then
		local okTeamColor, teamColor = pcall(function()
			return team.TeamColor
		end)
		if okTeamColor and typeof(teamColor) == "BrickColor" then
			return teamColor.Color
		end

		local attributeColor = team:GetAttribute("Color")
		if typeof(attributeColor) == "Color3" then
			return attributeColor
		end

		local okColor, color = pcall(function()
			return team.Color
		end)
		if okColor and typeof(color) == "Color3" then
			return color
		end
	end

	return PLAYER_TEAM_COLOR_FALLBACK
end

local function getFillColor(ownerType, pct, ownerPlayer)
	if ownerType == "Player" then
		return getPlayerTeamColor(ownerPlayer)
	end
	return healthColor(pct)
end

local function getNameTextColor(ownerType, ownerPlayer)
	if ownerType == "Player" then
		return Color3.fromRGB(255, 255, 255):Lerp(getPlayerTeamColor(ownerPlayer), 0.34)
	end
	return Color3.fromRGB(255, 255, 255)
end

local function getPlayerDisplayName(player)
	local displayName = player.DisplayName
	if displayName and displayName ~= "" then
		return displayName
	end
	return player.Name
end

local function getNameplateOffset(ownerType)
	if ownerType == "Player" then
		return PLAYER_NAMEPLATE_OFFSET
	end
	return NPC_NAMEPLATE_OFFSET
end

local function getNameplateMinOffsetY(ownerType)
	return getNameplateOffset(ownerType).Y
end

local function getNameplateMaxOffsetY(ownerType)
	return math.max(getNameplateMinOffsetY(ownerType), NAMEPLATE_OFFSET_MAX_Y)
end

local function isOffsetRelevantPart(part)
	if not part or not part:IsA("BasePart") then return false end
	if part.Transparency >= 0.99 then return false end
	if part:FindFirstAncestorOfClass("Tool") then return false end
	return true
end

local function getPartTopY(part)
	local halfSize = part.Size * 0.5
	local cf = part.CFrame
	local yExtent = math.abs(cf.RightVector.Y) * halfSize.X
		+ math.abs(cf.UpVector.Y) * halfSize.Y
		+ math.abs(cf.LookVector.Y) * halfSize.Z
	return cf.Position.Y + yExtent
end

local function getVisibleModelTopY(model)
	local topY = nil
	for _, desc in ipairs(model:GetDescendants()) do
		if isOffsetRelevantPart(desc) then
			local partTopY = getPartTopY(desc)
			if not topY or partTopY > topY then
				topY = partTopY
			end
		end
	end
	return topY
end

local function getBoundingBoxTopY(model)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf and size then
		return cf.Position.Y + (size.Y * 0.5)
	end
	return nil
end

local function calculateDynamicOverheadOffset(model, attachPart, ownerType)
	local defaultOffsetY = getNameplateMinOffsetY(ownerType)
	if not model or not model:IsA("Model") then
		return defaultOffsetY
	end

	local referencePart = attachPart
	if not referencePart or not referencePart:IsA("BasePart") then
		referencePart = getAttachPart(model)
	end

	local topY = getVisibleModelTopY(model) or getBoundingBoxTopY(model)
	if not topY then
		return defaultOffsetY
	end

	local baseY = nil
	if referencePart and referencePart:IsA("BasePart") then
		baseY = referencePart.Position.Y
	else
		local pivotOk, pivot = pcall(function()
			return model:GetPivot()
		end)
		baseY = (pivotOk and pivot and pivot.Position.Y) or topY
	end

	local distanceAboveBase = math.max(0, topY - baseY)
	local offsetY = math.clamp(
		distanceAboveBase + NAMEPLATE_OFFSET_PADDING,
		defaultOffsetY,
		getNameplateMaxOffsetY(ownerType)
	)

	if DEBUG_OVERHEAD_OFFSET then
		print(string.format(
			"[OverheadUI] Offset %s: top=%.2f base=%.2f final=%.2f",
			model.Name,
			topY,
			baseY,
			offsetY
		))
	end

	return offsetY
end

local function updateNameplateOffset(model, billboard, ownerType, attachPart)
	if not model or not billboard or not billboard.Parent then return end
	billboard.StudsOffset = Vector3.new(0, calculateDynamicOverheadOffset(model, attachPart or billboard.Parent, ownerType), 0)
end

local function getNameplateMaxDistance(ownerType)
	if ownerType == "Player" then
		return PLAYER_NAMEPLATE_MAX_DISTANCE
	end
	return NPC_NAMEPLATE_MAX_DISTANCE
end

------------------------------------------------------------------------
-- Disable default Roblox display
------------------------------------------------------------------------
local function disableDefaultDisplay(hum)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
	pcall(function() hum.NameDisplayDistance = 0 end)
	pcall(function() hum.HealthDisplayDistance = 0 end)
end

------------------------------------------------------------------------
-- Build BillboardGui
------------------------------------------------------------------------
local function buildBillboard(model, attachPart, displayName, ownerType, ownerPlayer)
	local existing = attachPart:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing:SetAttribute(OWNER_TYPE_ATTRIBUTE, ownerType)
		updateNameplateOffset(model, existing, ownerType, attachPart)
		existing.MaxDistance = getNameplateMaxDistance(ownerType)
		existing.AlwaysOnTop = false
		local bg = existing:FindFirstChild("Background")
		local nameLabel = bg and bg:FindFirstChild("NameLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = displayName
			nameLabel.TextColor3 = getNameTextColor(ownerType, ownerPlayer)
		end
		return existing
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name         = BILLBOARD_NAME
	billboard.Size         = BILLBOARD_SIZE
	billboard.StudsOffset  = getNameplateOffset(ownerType)
	billboard.AlwaysOnTop  = false
	billboard.MaxDistance  = getNameplateMaxDistance(ownerType)
	billboard.ResetOnSpawn = false
	billboard.Enabled      = true
	billboard:SetAttribute(OWNER_TYPE_ATTRIBUTE, ownerType)

	local bg = Instance.new("Frame")
	bg.Name                   = "Background"
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.Position               = UDim2.fromScale(0, 0)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel        = 0
	bg.Parent                 = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "NameLabel"
	nameLabel.Size                   = UDim2.new(1, 0, 0, 16)
	nameLabel.Position               = UDim2.new(0, 0, 0, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = displayName
	nameLabel.TextColor3             = getNameTextColor(ownerType, ownerPlayer)
	nameLabel.TextSize               = 14
	nameLabel.Font                   = Enum.Font.GothamBlack
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Center
	nameLabel.TextTransparency       = 0
	nameLabel.TextStrokeTransparency = 1
	nameLabel.ZIndex                 = 2
	nameLabel.Parent                 = bg

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Name            = "NameStroke"
	nameStroke.Color           = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness       = 1.5
	nameStroke.Transparency    = 0.1
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nameStroke.Parent          = nameLabel

	local barShadow = Instance.new("Frame")
	barShadow.Name                   = "BarShadow"
	barShadow.Size                   = UDim2.new(0.76, 6, 0, 20)
	barShadow.Position               = UDim2.new(0.12, -3, 0, 20)
	barShadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	barShadow.BackgroundTransparency = 0.60
	barShadow.BorderSizePixel        = 0
	barShadow.ZIndex                 = 0
	barShadow.Parent                 = bg

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 10)
	shadowCorner.Parent       = barShadow

	local barOuter = Instance.new("Frame")
	barOuter.Name                   = "BarOuter"
	barOuter.Size                   = UDim2.new(0.76, 0, 0, 16)
	barOuter.Position               = UDim2.new(0.12, 0, 0, 22)
	barOuter.BackgroundColor3       = Color3.fromRGB(18, 18, 18)
	barOuter.BackgroundTransparency = 0.50
	barOuter.BorderSizePixel        = 0
	barOuter.ClipsDescendants       = true
	barOuter.ZIndex                 = 1
	barOuter.Parent                 = bg

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 8)
	outerCorner.Parent       = barOuter

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name            = "BarStroke"
	outerStroke.Color           = Color3.fromRGB(0, 0, 0)
	outerStroke.Thickness       = 1
	outerStroke.Transparency    = 0.35
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Parent          = barOuter

	local barScale = Instance.new("UIScale")
	barScale.Name   = "BarScale"
	barScale.Scale  = 1
	barScale.Parent = barOuter

	local damageBar = Instance.new("Frame")
	damageBar.Name             = "DamageBar"
	damageBar.Size             = UDim2.fromScale(1, 1)
	damageBar.Position         = UDim2.fromScale(0, 0)
	damageBar.BackgroundColor3 = COLOR_DMG
	damageBar.BorderSizePixel  = 0
	damageBar.ZIndex           = 2
	damageBar.Parent           = barOuter

	local damageBarCorner = Instance.new("UICorner")
	damageBarCorner.CornerRadius = UDim.new(0, 8)
	damageBarCorner.Parent       = damageBar

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(1, 1)
	fill.Position         = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = COLOR_HIGH
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 3
	fill.Parent           = barOuter

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent       = fill

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Name     = "FillGradient"
	fillGradient.Rotation = 90
	fillGradient.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(210, 210, 210)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(115, 115, 115)),
	})
	fillGradient.Parent = fill

	local hpText = Instance.new("TextLabel")
	hpText.Name                   = "HPText"
	hpText.Size                   = UDim2.fromScale(1, 1)
	hpText.Position               = UDim2.fromScale(0, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text                   = ""
	hpText.TextColor3             = Color3.fromRGB(255, 255, 255)
	hpText.TextSize               = 11
	hpText.Font                   = Enum.Font.GothamBold
	hpText.TextXAlignment         = Enum.TextXAlignment.Center
	hpText.TextStrokeTransparency = 1
	hpText.ZIndex                 = 4
	hpText.Parent                 = barOuter

	local hpStroke = Instance.new("UIStroke")
	hpStroke.Name            = "HPStroke"
	hpStroke.Color           = Color3.fromRGB(0, 0, 0)
	hpStroke.Thickness       = 1.2
	hpStroke.Transparency    = 0.15
	hpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	hpStroke.Parent          = hpText

	local hitFlash = Instance.new("Frame")
	hitFlash.Name                   = "HitFlash"
	hitFlash.Size                   = UDim2.fromScale(1, 1)
	hitFlash.Position               = UDim2.fromScale(0, 0)
	hitFlash.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	hitFlash.BackgroundTransparency = 1
	hitFlash.BorderSizePixel        = 0
	hitFlash.ZIndex                 = 5
	hitFlash.Parent                 = barOuter

	billboard.Parent = attachPart
	updateNameplateOffset(model, billboard, ownerType, attachPart)
	return billboard
end

------------------------------------------------------------------------
-- Set or refresh authoritative bar state
------------------------------------------------------------------------
local function updateBarState(billboard, health, maxHealth, ownerPlayer)
	local pct    = (maxHealth > 0) and math.clamp(health / maxHealth, 0, 1) or 0
	local bg     = billboard:FindFirstChild("Background")
	local outer  = bg and bg:FindFirstChild("BarOuter")
	local fill   = outer and outer:FindFirstChild("Fill")
	local dmgBar = outer and outer:FindFirstChild("DamageBar")
	local hpText = outer and outer:FindFirstChild("HPText")
	local ownerType = billboard:GetAttribute(OWNER_TYPE_ATTRIBUTE)

	if fill then
		fill.Size             = UDim2.fromScale(pct, 1)
		fill.BackgroundColor3 = getFillColor(ownerType, pct, ownerPlayer)
	end
	if dmgBar then
		dmgBar.Size = UDim2.fromScale(pct, 1)
	end
	if hpText then
		hpText.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
	end
end

------------------------------------------------------------------------
-- Attach shared overhead UI to a character or NPC model
------------------------------------------------------------------------
local function attachOverheadUI(model, ownerType, displayName, ownerPlayer)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		hum = model:WaitForChild("Humanoid", ownerType == "Player" and 10 or 2)
	end
	if not hum or not hum:IsA("Humanoid") then return end

	disableDefaultDisplay(hum)

	local attachPart = getAttachPart(model)
	if not attachPart then
		local head = model:WaitForChild("Head", ownerType == "Player" and 5 or 1)
		if head and head:IsA("BasePart") then
			attachPart = head
		end
	end
	if not attachPart then
		warn("[OverheadUI] No attach part found for " .. model:GetFullName())
		return
	end

	local existingBillboard = attachPart:FindFirstChild(BILLBOARD_NAME)
	if model:GetAttribute(ATTACHED_ATTRIBUTE) and existingBillboard then
		buildBillboard(model, attachPart, displayName, ownerType, ownerPlayer)
		return
	end
	model:SetAttribute(ATTACHED_ATTRIBUTE, true)

	local billboard = buildBillboard(model, attachPart, displayName, ownerType, ownerPlayer)
	local ownerLabel = (ownerType == "NPC") and "NPC" or "player"
	print(string.format("[OverheadUI] Attached %s nameplate for %s", ownerLabel, displayName))

	updateBarState(billboard, hum.Health, hum.MaxHealth, ownerPlayer)

	local cleaned = false
	local connections = {}
	local transparencyConnections = {}
	local pendingOffsetUpdate = false

	local function scheduleOffsetUpdate(delaySeconds)
		if pendingOffsetUpdate then return end
		pendingOffsetUpdate = true
		task.delay(delaySeconds or NAMEPLATE_OFFSET_RECALC_DELAY, function()
			pendingOffsetUpdate = false
			if cleaned or not model.Parent or not billboard or not billboard.Parent then return end
			updateNameplateOffset(model, billboard, ownerType, attachPart)
		end)
	end

	local function watchPartTransparency(part)
		if not part or not part:IsA("BasePart") or transparencyConnections[part] then return end
		transparencyConnections[part] = part:GetPropertyChangedSignal("Transparency"):Connect(function()
			scheduleOffsetUpdate()
		end)
	end

	local function unwatchPartTransparency(part)
		local connection = transparencyConnections[part]
		if connection then
			connection:Disconnect()
			transparencyConnections[part] = nil
		end
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			watchPartTransparency(desc)
		end
	end

	scheduleOffsetUpdate(0.15)
	task.delay(0.5, function()
		if cleaned or not model.Parent or not billboard or not billboard.Parent then return end
		updateNameplateOffset(model, billboard, ownerType, attachPart)
	end)

	local function cleanup()
		if cleaned then return end
		cleaned = true
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		local watchedParts = {}
		for part in pairs(transparencyConnections) do
			watchedParts[#watchedParts + 1] = part
		end
		for _, part in ipairs(watchedParts) do
			unwatchPartTransparency(part)
		end
	end

	connections[1] = hum.HealthChanged:Connect(function(newHealth)
		if billboard and billboard.Parent then
			updateBarState(billboard, newHealth, hum.MaxHealth, ownerPlayer)
		end
	end)

	connections[2] = hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if billboard and billboard.Parent then
			updateBarState(billboard, hum.Health, hum.MaxHealth, ownerPlayer)
		end
	end)

	if ownerType == "Player" and ownerPlayer then
		connections[#connections + 1] = ownerPlayer:GetPropertyChangedSignal("Team"):Connect(function()
			if billboard and billboard.Parent then
				buildBillboard(model, attachPart, displayName, ownerType, ownerPlayer)
				updateBarState(billboard, hum.Health, hum.MaxHealth, ownerPlayer)
			end
		end)
	end

	connections[#connections + 1] = model.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			watchPartTransparency(desc)
			scheduleOffsetUpdate()
		elseif desc:IsA("Accessory") or desc:IsA("Hat") or desc:IsA("Model") then
			scheduleOffsetUpdate()
		end
	end)

	connections[#connections + 1] = model.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") then
			unwatchPartTransparency(desc)
			scheduleOffsetUpdate()
		elseif desc:IsA("Accessory") or desc:IsA("Hat") or desc:IsA("Model") then
			scheduleOffsetUpdate()
		end
	end)

	connections[#connections + 1] = hum.Died:Connect(function()
		if billboard and billboard.Parent then
			billboard.Enabled = false
			task.delay(0.5, function()
				if billboard and billboard.Parent then
					billboard:Destroy()
				end
			end)
		end
		cleanup()
	end)

	connections[#connections + 1] = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			cleanup()
		end
	end)
end

local function attachMobUI(model)
	attachOverheadUI(model, "NPC", model.Name)
end

------------------------------------------------------------------------
-- Player setup
------------------------------------------------------------------------
local function setupPlayer(player)
	local function onCharacter(character)
		task.defer(function()
			attachOverheadUI(character, "Player", getPlayerDisplayName(player), player)
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
print(string.format("[OverheadUI] Player max distance = %d", PLAYER_NAMEPLATE_MAX_DISTANCE))
print(string.format("[OverheadUI] NPC max distance = %d", NPC_NAMEPLATE_MAX_DISTANCE))

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)

for _, model in ipairs(CollectionService:GetTagged(MOB_TAG)) do
	if isMob(model) then
		attachMobUI(model)
	end
end

for _, model in ipairs(CollectionService:GetTagged(PRACTICE_DUMMY_TAG)) do
	if isMob(model) then
		attachMobUI(model)
	end
end

CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(model)
	task.defer(function()
		if isMob(model) then
			attachMobUI(model)
		end
	end)
end)

CollectionService:GetInstanceAddedSignal(PRACTICE_DUMMY_TAG):Connect(function(model)
	task.defer(function()
		if isMob(model) then
			attachMobUI(model)
		end
	end)
end)

local function scanWorkspace()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and isMob(desc) then
			attachMobUI(desc)
		end
	end
end
scanWorkspace()

Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then
		task.defer(function()
			if isMob(desc) then
				attachMobUI(desc)
			end
		end)
	elseif desc:IsA("Humanoid") then
		local model = desc.Parent
		if model and model:IsA("Model") then
			task.defer(function()
				if isMob(model) then
					attachMobUI(model)
				end
			end)
		end
	end
end)