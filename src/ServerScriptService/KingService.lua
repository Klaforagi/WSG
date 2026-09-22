--------------------------------------------------------------------------------
-- KingService.lua
-- One active king at a time. Granted on flag capture or periodic score check.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local KingService = {}

local DURATION_SECONDS = 150
local MAX_HEALTH_ADD = 100
local DAMAGE_MULT = 1.3
local SIZE_ADD = 1
local SPEED_ADD = 1
local SLAY_SCORE = 10
local CROWN_HEIGHT = 6.25
local SPIN_RAD_PER_SEC = 1.35
local PERIODIC_IDLE_SECONDS = 60
local SPEED_STAT = "MovementSpeed"
local SIZE_MOD_ID = "king_size"
local SPEED_MOD_ID = "king_speed"

local currentKing = nil
local kingExpiresAt = 0
local lastKingEndedAt = 0
local expiryToken = 0
local crownSpinConn = nil
local deathConn = nil
local charAddedConn = nil
local charRemovingConn = nil

local StatService
local FlagStatus
local KingStateRemote
local AddScore

local function now()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function displayNameOf(player)
	if not player then
		return "Someone"
	end
	if type(player.DisplayName) == "string" and player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

local function teamNameOf(player)
	return player and player.Team and player.Team.Name or nil
end

local function ensureRemotes()
	FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
	if not (FlagStatus and FlagStatus:IsA("RemoteEvent")) then
		FlagStatus = Instance.new("RemoteEvent")
		FlagStatus.Name = "FlagStatus"
		FlagStatus.Parent = ReplicatedStorage
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	KingStateRemote = remotes:FindFirstChild("KingState")
	if not (KingStateRemote and KingStateRemote:IsA("RemoteEvent")) then
		KingStateRemote = Instance.new("RemoteEvent")
		KingStateRemote.Name = "KingState"
		KingStateRemote.Parent = remotes
	end

	AddScore = ServerScriptService:FindFirstChild("AddScore")
	if not (AddScore and AddScore:IsA("BindableEvent")) then
		AddScore = Instance.new("BindableEvent")
		AddScore.Name = "AddScore"
		AddScore.Parent = ServerScriptService
	end
end

local function getCrownTemplate()
	local items = ServerStorage:FindFirstChild("Items")
	local crown = items and items:FindFirstChild("Crown")
	if crown then
		return crown
	end
	return nil
end

local function destroyCrown(character)
	if not character then
		return
	end
	local existing = character:FindFirstChild("KingCrown")
	if existing then
		pcall(function()
			existing:Destroy()
		end)
	end
	local anchor = character:FindFirstChild("KingCrownAnchor")
	if anchor then
		pcall(function()
			anchor:Destroy()
		end)
	end
end

local function stopCrownSpin()
	if crownSpinConn then
		crownSpinConn:Disconnect()
		crownSpinConn = nil
	end
end

local function attachCrown(player)
	local character = player and player.Character
	if not character then
		return
	end
	destroyCrown(character)

	local template = getCrownTemplate()
	if not template then
		warn("[KingService] ServerStorage.Items.Crown is missing")
		return
	end

	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "KingCrownAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CFrame = head.CFrame * CFrame.new(0, CROWN_HEIGHT, 0)
	anchor.Parent = character

	local weld = Instance.new("Weld")
	weld.Name = "KingCrownWeld"
	weld.Part0 = head
	weld.Part1 = anchor
	weld.C0 = CFrame.new(0, CROWN_HEIGHT, 0)
	weld.Parent = anchor

	local crown = template:Clone()
	crown.Name = "KingCrown"
	local function weldPart(part)
		if not part:IsA("BasePart") then
			return
		end
		part.CanCollide = false
		part.Massless = true
		part.Anchored = false
		local cw = Instance.new("WeldConstraint")
		cw.Part0 = anchor
		cw.Part1 = part
		cw.Parent = crown
	end
	if crown:IsA("BasePart") then
		crown.CFrame = anchor.CFrame
		crown.Parent = character
		weldPart(crown)
	else
		crown.Parent = character
		pcall(function()
			crown:PivotTo(anchor.CFrame)
		end)
		if crown:IsA("Model") then
			for _, inst in ipairs(crown:GetDescendants()) do
				weldPart(inst)
			end
		end
	end

	stopCrownSpin()
	local t0 = os.clock()
	crownSpinConn = RunService.Heartbeat:Connect(function()
		if not weld.Parent or not anchor.Parent then
			stopCrownSpin()
			return
		end
		local angle = (os.clock() - t0) * SPIN_RAD_PER_SEC
		weld.C0 = CFrame.new(0, CROWN_HEIGHT, 0) * CFrame.Angles(0, angle, 0)
	end)
end

local function applyHealthBonus(player, enable)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if enable then
		if tonumber(player:GetAttribute("KingHealthBonus")) then
			return
		end
		if not humanoid then
			return
		end
		humanoid.MaxHealth = humanoid.MaxHealth + MAX_HEALTH_ADD
		humanoid.Health = humanoid.MaxHealth
		player:SetAttribute("KingHealthBonus", MAX_HEALTH_ADD)
		return
	end

	local bonus = tonumber(player:GetAttribute("KingHealthBonus"))
	player:SetAttribute("KingHealthBonus", nil)
	if not humanoid or not bonus then
		return
	end
	humanoid.MaxHealth = math.max(1, humanoid.MaxHealth - bonus)
	if humanoid.Health > humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
end

local function applyKingStats(player, enable)
	if enable then
		HumanoidStatService:SetModifier(player, SPEED_STAT, SPEED_MOD_ID, {
			additive = SPEED_ADD,
			duration = DURATION_SECONDS,
			source = "King",
		})
		HumanoidStatService:SetModifier(player, "Size", SIZE_MOD_ID, {
			additive = SIZE_ADD,
			duration = DURATION_SECONDS,
			source = "King",
		})
		player:SetAttribute("KingDamageMult", DAMAGE_MULT)
		applyHealthBonus(player, true)
	else
		pcall(function()
			HumanoidStatService:RemoveModifier(player, SPEED_STAT, SPEED_MOD_ID)
		end)
		pcall(function()
			HumanoidStatService:RemoveModifier(player, "Size", SIZE_MOD_ID)
		end)
		player:SetAttribute("KingDamageMult", nil)
		applyHealthBonus(player, false)
	end
end

local function pushKingState(player, active, expiresAt)
	if not KingStateRemote or not player then
		return
	end
	pcall(function()
		KingStateRemote:FireClient(player, {
			active = active == true,
			expiresAt = expiresAt or 0,
		})
	end)
end

local function fireCrownedAlert(player)
	if not FlagStatus then
		return
	end
	pcall(function()
		FlagStatus:FireAllClients(
			"crowned",
			displayNameOf(player),
			teamNameOf(player),
			nil,
			nil,
			player.UserId
		)
	end)
end

local function fireSlainAlert(slayer)
	if not FlagStatus or not slayer then
		return
	end
	pcall(function()
		FlagStatus:FireAllClients(
			"slain_king",
			displayNameOf(slayer),
			teamNameOf(slayer),
			nil,
			nil,
			slayer.UserId
		)
	end)
end

local function awardSlayBonus(slayer)
	if not slayer then
		return
	end
	if StatService and type(StatService.AddScore) == "function" then
		pcall(function()
			StatService:AddScore(slayer, SLAY_SCORE)
		end)
	end
	local team = teamNameOf(slayer)
	if team and AddScore then
		pcall(function()
			AddScore:Fire(team, SLAY_SCORE)
		end)
	end
end

local Uncrown

local function bindKingCharacter(player)
	if deathConn then
		deathConn:Disconnect()
		deathConn = nil
	end
	if charRemovingConn then
		charRemovingConn:Disconnect()
		charRemovingConn = nil
	end

	local character = player.Character
	if not character then
		return
	end
	attachCrown(player)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		deathConn = humanoid.Died:Connect(function()
			local slayer = nil
			local slayerId = humanoid:GetAttribute("lastDamagerUserId")
			if type(slayerId) == "number" then
				slayer = Players:GetPlayerByUserId(slayerId)
				if slayer == player then
					slayer = nil
				end
			end
			Uncrown(player, slayer)
		end)
	end
	charRemovingConn = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and currentKing == player then
			destroyCrown(character)
		end
	end)
end

Uncrown = function(player, slayer)
	if currentKing ~= player then
		return
	end
	expiryToken += 1
	stopCrownSpin()
	if deathConn then
		deathConn:Disconnect()
		deathConn = nil
	end
	if charAddedConn then
		charAddedConn:Disconnect()
		charAddedConn = nil
	end
	if charRemovingConn then
		charRemovingConn:Disconnect()
		charRemovingConn = nil
	end

	local character = player.Character
	destroyCrown(character)
	applyKingStats(player, false)
	player:SetAttribute("IsKing", false)
	pushKingState(player, false, 0)

	currentKing = nil
	kingExpiresAt = 0
	lastKingEndedAt = now()

	if slayer and slayer.Parent then
		awardSlayBonus(slayer)
		fireSlainAlert(slayer)
	end
end

function KingService:GetKing()
	return currentKing
end

function KingService:HasKing()
	return currentKing ~= nil and currentKing.Parent ~= nil
end

function KingService:IsKing(player)
	return player ~= nil and currentKing == player
end

-- Used by transitions such as a voluntary return to the Neutral lobby.
function KingService:RemoveKing(player)
	if currentKing ~= player then
		return false
	end
	Uncrown(player, nil)
	return true
end

function KingService:TryCrown(player, _source)
	if not player or not player.Parent then
		return false
	end
	if KingService:HasKing() then
		return false
	end
	local team = teamNameOf(player)
	if team ~= "Blue" and team ~= "Red" then
		return false
	end

	ensureRemotes()
	currentKing = player
	kingExpiresAt = now() + DURATION_SECONDS
	player:SetAttribute("IsKing", true)
	applyKingStats(player, true)
	bindKingCharacter(player)
	if charAddedConn then
		charAddedConn:Disconnect()
	end
	charAddedConn = player.CharacterAdded:Connect(function()
		if currentKing ~= player then
			return
		end
		task.defer(function()
			if currentKing == player then
				applyHealthBonus(player, true)
				bindKingCharacter(player)
			end
		end)
	end)

	pushKingState(player, true, kingExpiresAt)
	fireCrownedAlert(player)

	local token = expiryToken + 1
	expiryToken = token
	task.delay(DURATION_SECONDS, function()
		if expiryToken ~= token then
			return
		end
		if currentKing == player then
			Uncrown(player, nil)
		end
	end)
	return true
end

function KingService:TryCrownFromCapture(player)
	return KingService:TryCrown(player, "capture")
end

function KingService:TryPeriodicCrown()
	if KingService:HasKing() then
		return false
	end
	if now() - lastKingEndedAt < PERIODIC_IDLE_SECONDS then
		return false
	end

	local bestPlayer = nil
	local bestScore = -1
	for _, player in ipairs(Players:GetPlayers()) do
		local team = teamNameOf(player)
		if team == "Blue" or team == "Red" then
			local score = 0
			if StatService then
				score = tonumber(StatService:GetStat(player, "Score")) or 0
			else
				score = tonumber(player:GetAttribute("Score")) or 0
			end
			if score > bestScore then
				bestScore = score
				bestPlayer = player
			end
		end
	end
	if not bestPlayer then
		return false
	end
	return KingService:TryCrown(bestPlayer, "periodic")
end

function KingService:OnMatchStart()
	if currentKing then
		Uncrown(currentKing, nil)
	end
	lastKingEndedAt = now()
end

function KingService:OnMatchEnd()
	if currentKing then
		Uncrown(currentKing, nil)
	end
end

function KingService:Init()
	ensureRemotes()
	pcall(function()
		StatService = require(ServerScriptService:WaitForChild("StatService", 10))
	end)

	Players.PlayerRemoving:Connect(function(player)
		if currentKing == player then
			Uncrown(player, nil)
		end
	end)
end

return KingService
