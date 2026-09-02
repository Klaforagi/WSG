local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local CurrencyService
local XPModule
pcall(function()
	local mod = ServerScriptService:FindFirstChild("CurrencyService")
	if mod and mod:IsA("ModuleScript") then
		CurrencyService = require(mod)
	end
end)

local StatService
pcall(function()
	StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

pcall(function()
	local mod = ServerScriptService:FindFirstChild("WeaponMasteryService")
	if mod and mod:IsA("ModuleScript") then
		require(mod)
	end
end)

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local FLAG_CARRY_SPEED_MODIFIER_ID = "flag_carry"
local FLAG_CARRY_SPEED_PENALTY = -1

local function applyFlagCarrySlow(player)
	if not player then
		return
	end
	HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, FLAG_CARRY_SPEED_MODIFIER_ID, {
		additive = FLAG_CARRY_SPEED_PENALTY,
		source = "FlagCarry",
	})
end

local function clearFlagCarrySlow(player)
	if not player then
		return
	end
	pcall(function()
		HumanoidStatService:RemoveModifier(player, MOVEMENT_SPEED_STAT, FLAG_CARRY_SPEED_MODIFIER_ID)
	end)
end

local FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
if not FlagStatus or not FlagStatus:IsA("RemoteEvent") then
	if FlagStatus then
		FlagStatus:Destroy()
	end
	FlagStatus = Instance.new("RemoteEvent")
	FlagStatus.Name = "FlagStatus"
	FlagStatus.Parent = ReplicatedStorage
end

local ForceDropFlagRequest = ReplicatedStorage:FindFirstChild("ForceDropFlagRequest")
if ForceDropFlagRequest and not ForceDropFlagRequest:IsA("BindableEvent") then
	ForceDropFlagRequest:Destroy()
	ForceDropFlagRequest = nil
end
if not ForceDropFlagRequest then
	ForceDropFlagRequest = Instance.new("BindableEvent")
	ForceDropFlagRequest.Name = "ForceDropFlagRequest"
	ForceDropFlagRequest.Parent = ReplicatedStorage
end

local FlagStatesFolder = ReplicatedStorage:FindFirstChild("FlagStates")
if FlagStatesFolder and not FlagStatesFolder:IsA("Folder") then
	FlagStatesFolder:Destroy()
	FlagStatesFolder = nil
end
if not FlagStatesFolder then
	FlagStatesFolder = Instance.new("Folder")
	FlagStatesFolder.Name = "FlagStates"
	FlagStatesFolder.Parent = ReplicatedStorage
end

local FLAG_NAMES = { "BlueFlag", "RedFlag", "Blue Flag", "Red Flag" }
local FLAG_TEAMS_BY_NAME = {
	BlueFlag = "Blue",
	["Blue Flag"] = "Blue",
	RedFlag = "Red",
	["Red Flag"] = "Red",
}
local FLAG_STAND_TEAMS_BY_NAME = {
	BlueFlagStand = "Blue",
	RedFlagStand = "Red",
}
local PLAYABLE_TEAMS = {
	Blue = true,
	Red = true,
}
local FLAG_TEAM_ORDER = { "Blue", "Red" }

local function getFlagTeamFromModelName(name)
	return FLAG_TEAMS_BY_NAME[tostring(name)]
end

local function getFlagTeamFromStandName(name)
	return FLAG_STAND_TEAMS_BY_NAME[tostring(name)]
end

local function isPlayableTeamName(teamName)
	return PLAYABLE_TEAMS[tostring(teamName)] == true
end

local function isFlagInteractionState(matchState)
	return matchState == "Game" or matchState == "SuddenDeath"
end

local function areFlagsInteractive()
	return isFlagInteractionState(ServerScriptService:GetAttribute("MatchState"))
end

local flags = {}
local carrying = {}
local carrierTeamChangeConns = {}
local captureDebounce = {}
local lastCarrierPos = {}

local function getFlagStateObject(team)
	local stateObject = FlagStatesFolder:FindFirstChild(team)
	if not stateObject or not stateObject:IsA("Folder") then
		if stateObject then
			stateObject:Destroy()
		end
		stateObject = Instance.new("Folder")
		stateObject.Name = team
		stateObject.Parent = FlagStatesFolder
	end
	return stateObject
end

local function getCarrierForFlag(team)
	for carrierPlayer, carryData in pairs(carrying) do
		if carryData and carryData.team == team then
			return carrierPlayer
		end
	end
	return nil
end

local function getStandRoot(instance)
	local current = instance
	while current and current ~= Workspace do
		if getFlagTeamFromStandName(current.Name) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getStandTeamFromInstance(instance)
	local standRoot = getStandRoot(instance)
	if standRoot then
		return getFlagTeamFromStandName(standRoot.Name)
	end
	return nil
end

local function canonicalizeTeamName(rawName)
	if not rawName then
		return rawName
	end
	local ok, TeamDisplayNames = pcall(function()
		return ReplicatedStorage:FindFirstChild("TeamDisplayNames") and require(ReplicatedStorage:FindFirstChild("TeamDisplayNames"))
	end)
	if ok and TeamDisplayNames then
		if TeamDisplayNames.Get("Blue") == rawName then
			return "Blue"
		elseif TeamDisplayNames.Get("Red") == rawName then
			return "Red"
		end
	end
	local lower = string.lower(tostring(rawName))
	if string.find(lower, "knight") then
		return "Blue"
	end
	if string.find(lower, "barbar") or string.find(lower, "barb") then
		return "Red"
	end
	return rawName
end

local function getStandPromptPart(instance)
	local standRoot = getStandRoot(instance) or instance
	if not standRoot then
		return nil
	end

	if standRoot:IsA("Model") then
		local stonePart = standRoot:FindFirstChild("Stone", true)
		if stonePart and stonePart:IsA("BasePart") then
			return stonePart
		end
		if standRoot.PrimaryPart and standRoot.PrimaryPart:IsA("BasePart") then
			return standRoot.PrimaryPart
		end
		return standRoot:FindFirstChildWhichIsA("BasePart", true)
	end

	if standRoot:IsA("BasePart") then
		local parent = standRoot.Parent
		if parent and parent:IsA("Model") then
			local stonePart = parent:FindFirstChild("Stone", true)
			if stonePart and stonePart:IsA("BasePart") then
				return stonePart
			end
		end
		return standRoot
	end

	return nil
end

local function findStandInstance(team)
	for standName, standTeam in pairs(FLAG_STAND_TEAMS_BY_NAME) do
		if standTeam == team then
			local standInstance = Workspace:FindFirstChild(standName, true)
			if standInstance and (standInstance:IsA("BasePart") or standInstance:IsA("Model")) then
				return standInstance
			end
		end
	end
	return nil
end

local function findFlagStandPart(team)
	return getStandPromptPart(findStandInstance(team))
end

local function setFlagInstanceAttributes(instance, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
	if not instance then
		return
	end
	local carrierTeamName = ""
	if carrierPlayer and carrierPlayer.Team then
		carrierTeamName = carrierPlayer.Team.Name
	end

	instance:SetAttribute("Team", team)
	instance:SetAttribute("AtBase", atBase == true)
	instance:SetAttribute("CarrierUserId", carrierPlayer and carrierPlayer.UserId or 0)
	instance:SetAttribute("CarrierTeam", carrierTeamName)
	instance:SetAttribute("CarrierName", carrierPlayer and carrierPlayer.Name or "")
	instance:SetAttribute("IsCarried", isCarried == true)
	instance:SetAttribute("IsDropped", isDropped == true)
	instance:SetAttribute("ReturnDeadline", tonumber(returnDeadline) or 0)
end

local function syncFlagState(team)
	local flagInfo = flags[team]
	local carrierPlayer = getCarrierForFlag(team)
	local isCarried = carrierPlayer ~= nil
	local isDropped = flagInfo and flagInfo.dropped == true
	local activeModel = flagInfo and (flagInfo.dropModel or flagInfo.model) or nil
	local returnDeadline = (isDropped and flagInfo and tonumber(flagInfo.returnDeadline)) or 0
	local atBase = false

	if flagInfo and flagInfo.model and flagInfo.model.Parent and not isCarried and not isDropped then
		atBase = true
	end

	local stateObject = getFlagStateObject(team)
	setFlagInstanceAttributes(stateObject, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)

	if activeModel then
		setFlagInstanceAttributes(activeModel, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
	end

	local standPart = findFlagStandPart(team)
	if standPart then
		setFlagInstanceAttributes(standPart, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
	end
end

local function syncAllFlagStates()
	for _, team in ipairs(FLAG_TEAM_ORDER) do
		syncFlagState(team)
	end
end

local function freezeDroppedFlagReturns()
	for team, info in pairs(flags) do
		if info and info.dropped == true then
			info._dropVersion = (info._dropVersion or 0) + 1
			info.returnDeadline = 0
			syncFlagState(team)
		end
	end
end

for _, team in ipairs(FLAG_TEAM_ORDER) do
	getFlagStateObject(team)
end

local forceDropFlag

for _, playerInstance in ipairs(Players:GetPlayers()) do
	playerInstance:GetPropertyChangedSignal("Team"):Connect(function()
		syncAllFlagStates()
		if carrying[playerInstance] then
			forceDropFlag(playerInstance, lastCarrierPos[playerInstance])
		end
	end)
end
Players.PlayerAdded:Connect(function(playerInstance)
	playerInstance:GetPropertyChangedSignal("Team"):Connect(function()
		syncAllFlagStates()
		if carrying[playerInstance] then
			forceDropFlag(playerInstance, lastCarrierPos[playerInstance])
		end
	end)
	syncAllFlagStates()
end)

local FLAG_RETURN_TIME = 15
local FLAG_ACTION_PROMPT_NAME = "FlagActionPrompt"
local startDroppedFlagReturnTimer
local setupFlagModel
local wiredStandPromptParts = {}

local function makeCarryClone(originalModel, character)
	if not originalModel or not character then
		return nil
	end
	local clone = originalModel:Clone()
	clone.Name = originalModel.Name .. "_Carried"
	if not clone.PrimaryPart then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				clone.PrimaryPart = d
				break
			end
		end
	end

	clone.Parent = character
	local attachPart = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	if attachPart then
		if clone.PrimaryPart then
			local primary = clone.PrimaryPart
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("SpecialMesh") then
					d.Scale = d.Scale * 0.5
				end
			end
			for _, p in ipairs(clone:GetDescendants()) do
				if p:IsA("BasePart") then
					if p == primary then
						p.Size = p.Size * 0.5
					else
						local rel = primary.CFrame:ToObjectSpace(p.CFrame)
						local rx, ry, rz = rel:ToEulerAnglesXYZ()
						local newPos = rel.Position * 0.5
						p.Size = p.Size * 0.5
						p.CFrame = primary.CFrame * CFrame.new(newPos) * CFrame.Angles(rx, ry, rz)
					end
				end
			end

			local offset = CFrame.new(0, 1.8, 0.7) * CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
			offset = offset * CFrame.Angles(math.rad(180), 0, 0)
			clone:SetPrimaryPartCFrame(attachPart.CFrame * offset)
		end
		for _, v in ipairs(clone:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false
				v.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = v
				weld.Part1 = attachPart
				weld.Parent = v
			end
		end
		for _, name in ipairs({ "PickupPart", "Pickup", "Flag", "Base" }) do
			local p = clone:FindFirstChild(name, true)
			if p and p:IsA("BasePart") and p ~= clone.PrimaryPart then
				p:Destroy()
			end
		end
	end

	local trailPlane = clone:FindFirstChild("Plane", true)
	local flagTrail = trailPlane and trailPlane:FindFirstChild("FlagTrail")
	if flagTrail then
		flagTrail.Enabled = false
		task.spawn(function()
			local moveThreshold = 0.01
			local stopGraceSeconds = 0.15
			local lastMovingAt = 0
			while clone and clone.Parent do
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local isMoving = hrp.AssemblyLinearVelocity.Magnitude > moveThreshold
					if isMoving then
						lastMovingAt = os.clock()
					end
					flagTrail.Enabled = isMoving or ((os.clock() - lastMovingAt) <= stopGraceSeconds)
				else
					flagTrail.Enabled = false
				end
				task.wait(0.03)
			end
			pcall(function()
				flagTrail.Enabled = false
			end)
		end)
	end

	return clone
end

local function getMapModel()
	for _, candidate in ipairs(Workspace:GetChildren()) do
		if candidate:IsA("Model") or candidate:IsA("Folder") then
			if candidate:FindFirstChild("BlueFlagStand", true) or candidate:FindFirstChild("RedFlagStand", true) then
				return candidate
			end
		end
	end
	return nil
end

local function destroyFlagModelsInWorld(teamFilter)
	local toDestroy = {}
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") then
			local childTeam = getFlagTeamFromModelName(inst.Name)
			if childTeam and (not teamFilter or childTeam == teamFilter) then
				table.insert(toDestroy, inst)
			end
		end
	end
	for _, inst in ipairs(toDestroy) do
		pcall(function()
			inst:Destroy()
		end)
	end
end

local function respawnFlag(team)
	local info = flags[team]
	if not info or not info.original then
		warn("[FlagPickup] respawnFlag skipped; no original for", tostring(team))
		return
	end

	destroyFlagModelsInWorld(team)

	local spawnModel = info.original:Clone()
	spawnModel.Parent = getMapModel() or Workspace
	if not spawnModel.PrimaryPart then
		for _, d in ipairs(spawnModel:GetDescendants()) do
			if d:IsA("BasePart") then
				spawnModel.PrimaryPart = d
				break
			end
		end
	end
	if info.spawnCFrame and spawnModel.PrimaryPart then
		spawnModel:SetPrimaryPartCFrame(info.spawnCFrame)
	end
	setupFlagModel(spawnModel)
	info.model = spawnModel
	info.dropped = false
	info.returnDeadline = 0
	syncFlagState(team)
end

local function findPickupPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	for _, name in ipairs({ "PickupPart", "Pickup", "Flag", "Base" }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function awardFlagReturnRewards(player)
	if not player then
		return
	end
	if XPModule and XPModule.AwardXP then
		pcall(function()
			XPModule.AwardXP(player, "FlagReturn")
		end)
	end
	if CurrencyService and CurrencyService.AddCoins then
		pcall(function()
			CurrencyService:AddCoins(player, 5, "objective")
		end)
	end
	if StatService then
		StatService:RegisterFlagReturn(player)
	end
end

local function returnDroppedFlag(team, player, allowDirectRespawn)
	if not areFlagsInteractive() then
		return false
	end
	local flagInfo = flags[team]
	if not flagInfo then
		return false
	end
	if flagInfo.dropped ~= true and allowDirectRespawn ~= true then
		return false
	end

	local dropModel = flagInfo.dropModel
	if dropModel and dropModel.Parent then
		pcall(function()
			dropModel:Destroy()
		end)
	end

	flagInfo.dropped = false
	flagInfo.dropModel = nil
	flagInfo.returnDeadline = 0
	respawnFlag(team)

	local playerName = player and player.Name or nil
	local playerTeamName = player and player.Team and player.Team.Name or nil
	FlagStatus:FireAllClients("returned", playerName, playerTeamName, team)
	FlagStatus:FireAllClients("playSound", "Flag_return")

	if player then
		awardFlagReturnRewards(player)
	end

	return true
end

local function pickUpFlag(team, model, player)
	if not player or not model then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if carrying[player] then
		return false
	end

	local playerTeamName = canonicalizeTeamName(player.Team and player.Team.Name or nil)

	if model.Parent then
		for _, obj in ipairs(model:GetDescendants()) do
			if obj and obj:IsA("ProximityPrompt") and obj.Name == FLAG_ACTION_PROMPT_NAME then
				pcall(function()
					obj:Destroy()
				end)
			end
		end

		model.Parent = ServerStorage
		if flags[team] then
			flags[team].dropped = false
			flags[team].dropModel = nil
			flags[team].model = nil
			flags[team].returnDeadline = 0
		end

		for _, d in ipairs(model:GetDescendants()) do
			if d and (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) then
				pcall(function()
					d:Destroy()
				end)
			end
		end

		if not flags[team].pickupTemplate then
			local pickupTemplate = (flags[team].original and flags[team].original:Clone()) or model:Clone()
			for _, d in ipairs(pickupTemplate:GetDescendants()) do
				if d and (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) then
					pcall(function()
						d:Destroy()
					end)
				end
			end
			pickupTemplate.Parent = ServerStorage
			flags[team].pickupTemplate = pickupTemplate
		end
	end

	local template = flags[team].pickupTemplate or flags[team].original
	local carried = makeCarryClone(template, character)
	if not carried then
		return false
	end

	carrying[player] = { team = team, model = carried }
	carrying[player].carrierTeamAtPickup = canonicalizeTeamName(player.Team and player.Team.Name or nil)

	local function onTeamChanged()
		local data = carrying[player]
		if not data then
			return
		end
		local currentTeam = player and player.Team and canonicalizeTeamName(player.Team.Name) or nil
		if currentTeam and data.carrierTeamAtPickup and currentTeam ~= data.carrierTeamAtPickup then
			forceDropFlag(player, lastCarrierPos[player])
		end
	end
	local propConn = player:GetPropertyChangedSignal("Team"):Connect(onTeamChanged)
	local attrConn = player:GetAttributeChangedSignal("Team"):Connect(onTeamChanged)
	carrierTeamChangeConns[player] = { propConn = propConn, attrConn = attrConn }
	player:SetAttribute("CarryingFlag", team)
	setFlagInstanceAttributes(carried, team, false, true, false, player, 0)
	syncFlagState(team)
	applyFlagCarrySlow(player)
	FlagStatus:FireAllClients("pickup", player.Name, playerTeamName, team)
	local takenSoundName = "Flag_taken"
	if playerTeamName == "Blue" and team == "Red" then
		takenSoundName = "Flag_taken_blue"
	elseif playerTeamName == "Red" and team == "Blue" then
		takenSoundName = "Flag_taken_red"
	end
	FlagStatus:FireAllClients("playSound", takenSoundName)

	local function onDied()
		if not carrying[player] or carrying[player].team ~= team then
			return
		end

		local dropModel = nil
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and flags[team] and flags[team].original then
			dropModel = flags[team].original:Clone()
			dropModel.Parent = getMapModel() or Workspace
		end

		if carrying[player] and carrying[player].model then
			pcall(function()
				carrying[player].model:Destroy()
			end)
		end
		if carrying[player] and carrying[player].deathConn then
			pcall(function()
				carrying[player].deathConn:Disconnect()
			end)
		end
		if carrierTeamChangeConns[player] then
			pcall(function()
				if carrierTeamChangeConns[player].propConn then
					carrierTeamChangeConns[player].propConn:Disconnect()
				end
				if carrierTeamChangeConns[player].attrConn then
					carrierTeamChangeConns[player].attrConn:Disconnect()
				end
			end)
			carrierTeamChangeConns[player] = nil
		end
		carrying[player] = nil
		pcall(function()
			player:SetAttribute("CarryingFlag", nil)
		end)
		clearFlagCarrySlow(player)
		if not areFlagsInteractive() then
			return
		end

		if hrp and dropModel then
			if dropModel.PrimaryPart then
				local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
				carryRot = carryRot * CFrame.Angles(math.rad(180), 0, 0)
				dropModel:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0.5, 0) * carryRot)
			end
			setupFlagModel(dropModel, true)
			flags[team].dropped = true
			flags[team].dropModel = dropModel
			syncFlagState(team)
			startDroppedFlagReturnTimer(team, dropModel)
		else
			task.delay(FLAG_RETURN_TIME, function()
				if not areFlagsInteractive() then
					return
				end
				returnDroppedFlag(team, nil, true)
			end)
		end
	end

	local deathConn = humanoid.Died:Connect(onDied)
	if carrying[player] then
		carrying[player].deathConn = deathConn
	end

	return true
end

local function setupFlagActionPrompt(team, model)
	local pickupPart = findPickupPart(model)
	if not pickupPart then
		return
	end

	pcall(function()
		pickupPart.CanQuery = true
	end)

	local prompt = pickupPart:FindFirstChild(FLAG_ACTION_PROMPT_NAME)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = pickupPart
	end

	prompt.Name = FLAG_ACTION_PROMPT_NAME
	prompt.ActionText = "Steal"
	prompt.ObjectText = team .. " Flag"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Enabled = true
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("FlagTeam", team)

	prompt.Triggered:Connect(function(player)
		if not player or not areFlagsInteractive() then
			return
		end

		local playerTeamName = canonicalizeTeamName(player.Team and player.Team.Name or nil)
		if not isPlayableTeamName(playerTeamName) then
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		if not flags[team] then
			return
		end

		local isDroppedFlag = flags[team].dropped == true and flags[team].dropModel == model
		local isBaseFlag = flags[team].dropped ~= true and flags[team].model == model
		if not isDroppedFlag and not isBaseFlag then
			return
		end

		if playerTeamName == team then
			if isDroppedFlag then
				returnDroppedFlag(team, player)
			end
			return
		end

		pickUpFlag(team, model, player)
	end)
end

startDroppedFlagReturnTimer = function(team, dropModel)
	if not dropModel then
		return
	end

	setupFlagActionPrompt(team, dropModel)
	if flags[team] then
		flags[team].returnDeadline = workspace:GetServerTimeNow() + FLAG_RETURN_TIME
	end
	syncFlagState(team)

	local dropVersion = (flags[team]._dropVersion or 0) + 1
	flags[team]._dropVersion = dropVersion

	print("[FlagPickup] auto-return timer started for", team, "flag (" .. FLAG_RETURN_TIME .. "s)")
	task.spawn(function()
		while true do
			if not flags[team] or not flags[team].dropped or flags[team]._dropVersion ~= dropVersion or flags[team].dropModel ~= dropModel then
				return
			end
			if not areFlagsInteractive() then
				return
			end
			local remaining = (flags[team].returnDeadline or 0) - workspace:GetServerTimeNow()
			if remaining <= 0 then
				break
			end
			task.wait(math.min(1, remaining))
		end

		if not flags[team] or not flags[team].dropped or flags[team]._dropVersion ~= dropVersion or flags[team].dropModel ~= dropModel then
			return
		end
		if not areFlagsInteractive() then
			return
		end

		returnDroppedFlag(team, nil)
	end)
end

setupFlagModel = function(model, isDrop)
	if not model or not model:IsA("Model") then
		return
	end
	local team = getFlagTeamFromModelName(model.Name)
	if not team then
		return
	end
	print(string.format("[FlagPickup] setupFlagModel called for '%s' (team=%s drop=%s)", tostring(model:GetFullName()), tostring(team), tostring(isDrop)))
	local pickupPart = findPickupPart(model)
	if not pickupPart then
		warn("[FlagPickup] no pickup part on", model:GetFullName())
		return
	end
	-- Ensure the pickup part is queryable so clients can see ProximityPrompts
	pcall(function() pickupPart.CanQuery = true end)
	flags[team] = flags[team] or {}
	flags[team].model = model
	flags[team].pickupPart = pickupPart

	do
		local plane = model:FindFirstChild("Plane", true)
		if plane and plane:IsA("BasePart") then
			local teamColor = Color3.new(1, 1, 1)
			if team == "Blue" then
				teamColor = Color3.fromRGB(100, 160, 255)
			elseif team == "Red" then
				teamColor = Color3.fromRGB(220, 80, 80)
			end
			if not plane:FindFirstChild("FlagTrail") then
				local att0 = Instance.new("Attachment")
				att0.Name = "FlagTrail_Att0"
				att0.Position = Vector3.new(-1.4, -0.5, 0.1)
				att0.Parent = plane

				local att1 = Instance.new("Attachment")
				att1.Name = "FlagTrail_Att1"
				att1.Position = Vector3.new(-1.4, 0.5, 0.1)
				att1.Parent = plane

				local trail = Instance.new("Trail")
				trail.Name = "FlagTrail"
				trail.Attachment0 = att0
				trail.Attachment1 = att1
				trail.Enabled = false
				trail.Lifetime = 2
				trail.FaceCamera = false
				trail.LightInfluence = 0.4
				trail.MinLength = 0
				trail.Color = ColorSequence.new(teamColor)
				trail.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.6, 0.25),
					NumberSequenceKeypoint.new(1, 1),
				})
				trail.WidthScale = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1.6),
					NumberSequenceKeypoint.new(1, 0.2),
				})
				trail.Parent = plane
			end
		end
	end

	if not isDrop then
		if flags[team].original then
			pcall(function()
				flags[team].original:Destroy()
			end)
		end
		if flags[team].pickupTemplate then
			pcall(function()
				flags[team].pickupTemplate:Destroy()
			end)
		end
		flags[team].original = model:Clone()
		flags[team].spawnCFrame = (model.PrimaryPart and model:GetPrimaryPartCFrame()) or model:GetPivot()
		flags[team].original.Parent = ServerStorage
		local pickupTemplate = flags[team].original:Clone()
		for _, d in ipairs(pickupTemplate:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
				pcall(function()
					d:Destroy()
				end)
			end
		end
		pickupTemplate.Parent = ServerStorage
		flags[team].pickupTemplate = pickupTemplate
	end

	syncFlagState(team)
	setupFlagActionPrompt(team, model)
end

local function isActualMapRoot(root)
	if not root then
		return false
	end
	if not (root:IsA("Model") or root:IsA("Folder")) then
		return false
	end
	if getFlagTeamFromModelName(root.Name) then
		return false -- this is a flag, not a map
	end
	return root:FindFirstChild("BlueFlagStand", true) ~= nil
		or root:FindFirstChild("RedFlagStand", true) ~= nil
end

local function captureFlagsFromMap(root)
	if not isActualMapRoot(root) then
		return
	end

	print("[FlagPickup] capturing flags from", root:GetFullName(), root.ClassName)

	for _, name in ipairs(FLAG_NAMES) do
		local found = root:FindFirstChild(name, true)
		if found and found:IsA("Model") then
			if not found.PrimaryPart then
				for _, d in ipairs(found:GetDescendants()) do
					if d:IsA("BasePart") then
						found.PrimaryPart = d
						break
					end
				end
			end
			setupFlagModel(found)
		end
	end

	-- only hide during lobby / prematch
	if not areFlagsInteractive() then
		destroyFlagModelsInWorld()
	end
end

for _, child in ipairs(Workspace:GetChildren()) do
	captureFlagsFromMap(child)
end

Workspace.ChildAdded:Connect(function(child)
	captureFlagsFromMap(child)
end)

local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
	AddScore = Instance.new("BindableEvent")
	AddScore.Name = "AddScore"
	AddScore.Parent = ServerScriptService
end

pcall(function()
	XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

local function ensureBindable(name)
	local ev = ServerScriptService:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		return ev
	end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = ServerScriptService
	return ev
end

local FlagCaptured = ensureBindable("FlagCaptured")
ensureBindable("FlagReturned")

local function awardPoints(teamName, points)
	if not teamName or type(points) ~= "number" then
		return
	end
	pcall(function()
		AddScore:Fire(teamName, points)
	end)
end

local function captureFlagAtStand(pl, standTeam)
	if not pl or not areFlagsInteractive() then
		return false
	end

	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end

	local playerTeamName = canonicalizeTeamName(pl.Team and pl.Team.Name or nil)
	if not isPlayableTeamName(playerTeamName) or playerTeamName ~= standTeam then
		return false
	end

	local carry = carrying[pl]
	if not carry then
		return false
	end
	local flagTeam = carry.team
	if flagTeam == standTeam then
		return false
	end

	local ownFlagInfo = flags[standTeam]
	local ownFlagPresent = ownFlagInfo and ownFlagInfo.model and (ownFlagInfo.dropped ~= true)
	if not ownFlagPresent then
		return false
	end

	if captureDebounce[pl] then
		return false
	end
	captureDebounce[pl] = true
	task.delay(5, function()
		captureDebounce[pl] = nil
	end)

	if carry.model then
		pcall(function()
			carry.model:Destroy()
		end)
	end
	if carry.deathConn then
		pcall(function()
			carry.deathConn:Disconnect()
		end)
	end
	carrying[pl] = nil
	pcall(function()
		pl:SetAttribute("CarryingFlag", nil)
	end)
	clearFlagCarrySlow(pl)
	syncFlagState(flagTeam)

	awardPoints(playerTeamName, 100)

	if XPModule and XPModule.AwardXP then
		pcall(function()
			XPModule.AwardXP(pl, "FlagCapture")
		end)
	end
	if CurrencyService and CurrencyService.AddCoins then
		pcall(function()
			CurrencyService:AddCoins(pl, 10, "objective")
		end)
	end
	if StatService then
		StatService:RegisterFlagCapture(pl)
	end
	pcall(function()
		FlagCaptured:Fire(pl, playerTeamName, flagTeam)
	end)

	FlagStatus:FireAllClients("captured", pl.Name, playerTeamName, flagTeam)
	local captureSoundName = "Flag_capture"
	if playerTeamName == "Blue" and flagTeam == "Red" then
		captureSoundName = "Flag_capture_blue"
	elseif playerTeamName == "Red" and flagTeam == "Blue" then
		captureSoundName = "Flag_capture_red"
	end
	FlagStatus:FireAllClients("playSound", captureSoundName)

	task.delay(5, function()
		if not areFlagsInteractive() then
			return
		end
		respawnFlag(flagTeam)
		FlagStatus:FireAllClients("returned", nil, nil, flagTeam)
		FlagStatus:FireAllClients("playSound", "Flag_return")
	end)

	return true
end

local function setupStand(standInstance)
	local standPart = getStandPromptPart(standInstance)
	local standTeam = getStandTeamFromInstance(standInstance)
	if not standPart or not standTeam then
		return
	end
	if wiredStandPromptParts[standPart] then
		return
	end
	wiredStandPromptParts[standPart] = true

	local prompt = standPart:FindFirstChild("FlagCapturePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
	end

	standPart.Touched:Connect(function(hit)
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		captureFlagAtStand(player, standTeam)
	end)
end

for _, obj in ipairs(Workspace:GetDescendants()) do
	if (obj:IsA("BasePart") or obj:IsA("Model")) and (obj.Name == "BlueFlagStand" or obj.Name == "RedFlagStand") then
		setupStand(obj)
	end
end
Workspace.DescendantAdded:Connect(function(desc)
	if (desc:IsA("BasePart") or desc:IsA("Model")) and (desc.Name == "BlueFlagStand" or desc.Name == "RedFlagStand") then
		setupStand(desc)
	end
end)

local function destroyAllFlags()
	for pl, data in pairs(carrying) do
		if data.model then
			pcall(function()
				data.model:Destroy()
			end)
		end
		if data.deathConn then
			pcall(function()
				data.deathConn:Disconnect()
			end)
		end
		pcall(function()
			pl:SetAttribute("CarryingFlag", nil)
		end)
		clearFlagCarrySlow(pl)
	end
	carrying = {}
	captureDebounce = {}
	lastCarrierPos = {}

	destroyFlagModelsInWorld()

	for _, team in ipairs({ "Blue", "Red" }) do
		if flags[team] then
			flags[team].dropped = false
			flags[team].dropModel = nil
			flags[team].model = nil
			flags[team]._dropVersion = (flags[team]._dropVersion or 0) + 1
		end
	end
	syncAllFlagStates()
	print("[FlagPickup] All flags destroyed")
end

local function spawnAllFlags()
	for _, team in ipairs({ "Blue", "Red" }) do
		if flags[team] and flags[team].original then
			flags[team].dropped = false
			flags[team].dropModel = nil
			respawnFlag(team)
		else
			warn("[FlagPickup] spawnAllFlags: no original for", team)
		end
	end
	print("[FlagPickup] All flags spawned")
end

local function resetAllFlags(mode)
	if mode == "destroy" then
		destroyAllFlags()
	else
		spawnAllFlags()
	end
end

local ResetFlags = ServerScriptService:FindFirstChild("ResetFlags")
if not ResetFlags then
	ResetFlags = Instance.new("BindableEvent")
	ResetFlags.Name = "ResetFlags"
	ResetFlags.Parent = ServerScriptService
end
ResetFlags.Event:Connect(resetAllFlags)

forceDropFlag = function(pl, lastPos)
	local carry = carrying[pl]
	if not carry then
		return
	end
	local team = carry.team

	if carry.model then
		pcall(function()
			carry.model:Destroy()
		end)
	end
	if carry.deathConn then
		pcall(function()
			carry.deathConn:Disconnect()
		end)
	end
	if carrierTeamChangeConns[pl] then
		pcall(function()
			if carrierTeamChangeConns[pl].propConn then
				carrierTeamChangeConns[pl].propConn:Disconnect()
			end
			if carrierTeamChangeConns[pl].attrConn then
				carrierTeamChangeConns[pl].attrConn:Disconnect()
			end
		end)
		carrierTeamChangeConns[pl] = nil
	end
	carrying[pl] = nil
	pcall(function()
		pl:SetAttribute("CarryingFlag", nil)
	end)
	clearFlagCarrySlow(pl)

	if not areFlagsInteractive() then
		syncFlagState(team)
		return
	end

	local dropCFrame
	local char = pl.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		dropCFrame = hrp.CFrame * CFrame.new(0, 0.5, 0)
	elseif lastPos then
		dropCFrame = CFrame.new(lastPos + Vector3.new(0, 0.5, 0))
	end

	if dropCFrame and flags[team] and flags[team].original then
		local dropModel = flags[team].original:Clone()
		dropModel.Parent = getMapModel() or Workspace

		if not dropModel.PrimaryPart then
			for _, d in ipairs(dropModel:GetDescendants()) do
				if d:IsA("BasePart") then
					dropModel.PrimaryPart = d
					break
				end
			end
		end

		if dropModel.PrimaryPart then
			local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90)) * CFrame.Angles(math.rad(180), 0, 0)
			dropModel:SetPrimaryPartCFrame(dropCFrame * carryRot)
		end

		setupFlagModel(dropModel, true)
		flags[team].dropped = true
		flags[team].dropModel = dropModel
		syncFlagState(team)
		startDroppedFlagReturnTimer(team, dropModel)
	else
		returnDroppedFlag(team, nil, true)
	end
end

if ForceDropFlagRequest and ForceDropFlagRequest:IsA("BindableEvent") then
	ForceDropFlagRequest.Event:Connect(function(pl)
		if type(pl) ~= "userdata" then
			return
		end
		pcall(function()
			forceDropFlag(pl, lastCarrierPos[pl])
		end)
	end)
end

RunService.Heartbeat:Connect(function()
	for pl in pairs(carrying) do
		local char = pl.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			lastCarrierPos[pl] = hrp.Position
		end
	end
end)

ServerScriptService:GetAttributeChangedSignal("MatchState"):Connect(function()
	if not areFlagsInteractive() then
		freezeDroppedFlagReturns()
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	if not carrying[pl] then
		lastCarrierPos[pl] = nil
		captureDebounce[pl] = nil
		return
	end
	forceDropFlag(pl, lastCarrierPos[pl])
	lastCarrierPos[pl] = nil
	captureDebounce[pl] = nil
end)

task.spawn(function()
	while true do
		task.wait(5)
		for pl, data in pairs(carrying) do
			local valid = pl and pl.Parent ~= nil
			if valid then
				local char = pl.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				valid = char ~= nil and hum ~= nil and hum.Health > 0
			end
			if not valid then
				forceDropFlag(pl, lastCarrierPos[pl])
				lastCarrierPos[pl] = nil
			end
			if data and data.carrierTeamAtPickup then
				local currentTeamName = pl and pl.Team and canonicalizeTeamName(pl.Team.Name) or nil
				if currentTeamName and currentTeamName ~= data.carrierTeamAtPickup then
					forceDropFlag(pl, lastCarrierPos[pl])
					lastCarrierPos[pl] = nil
				end
			end
		end
	end
end)

return nil