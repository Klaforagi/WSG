local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local RING_TEMPLATE = ServerStorage:FindFirstChild("Ring")
if not RING_TEMPLATE or not RING_TEMPLATE:IsA("MeshPart") then
	warn("TeamRings.server: 'Ring' MeshPart not found in ServerStorage. Aborting.")
	return
end
	-- Debug info to help troubleshoot MeshPart appearance
	warn("TeamRings.server: Found Ring template ->", RING_TEMPLATE:GetFullName(), "Class=", RING_TEMPLATE.ClassName)
	for _, child in ipairs(RING_TEMPLATE:GetChildren()) do
		warn("TeamRings.server: Ring child ->", child.Name, "Class=", child.ClassName)
		if child:IsA("SpecialMesh") then
			warn("TeamRings.server: SpecialMesh MeshId=", child.MeshId, "Scale=", tostring(child.Scale))
		end
	end

local RING_SIZE = Vector3.new(4, 0.2, 4)
local RING_OFFSET_Y = -3.15

local function teamColorOfPlayer(player)
	if player and player.Team and player.Team.TeamColor then
		return player.Team.TeamColor.Color
	end
	return Color3.fromRGB(170, 170, 170)
end

local function findRootPart(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
end

local function createRingForCharacter(player, character)
	if not player or not character then return end
	local root = findRootPart(character)
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then return end
	end

	local ring = RING_TEMPLATE:Clone()
	ring.Anchored = false
	ring.Massless = true
	ring.CanCollide = false
	ring.Transparency = 0
	ring.Material = Enum.Material.Neon
	ring.Color = teamColorOfPlayer(player)
	ring.Parent = workspace
	ring.CFrame = root.CFrame * CFrame.new(0, RING_OFFSET_Y, 0) * CFrame.Angles(math.rad(90), 0, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ring
	weld.Parent = ring

	local teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
		if ring and ring.Parent then
			ring.Color = teamColorOfPlayer(player)
		else
			if teamConn then teamConn:Disconnect() end
		end
	end)

	local humanoidConn
	local healthConn
	local childAddedConn

	local function cleanup()
		if teamConn then
			teamConn:Disconnect()
			teamConn = nil
		end
		if humanoidConn then
			humanoidConn:Disconnect()
			humanoidConn = nil
		end
		if healthConn then
			healthConn:Disconnect()
			healthConn = nil
		end
		if childAddedConn then
			childAddedConn:Disconnect()
			childAddedConn = nil
		end
		if ring and ring.Parent then
			ring:Destroy()
		end
	end

	local function connectHumanoid(hum)
		if not hum or humanoidConn then return end
		humanoidConn = hum.Died:Connect(cleanup)
		healthConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
			if hum.Health and hum.Health <= 0 then
				cleanup()
			end
		end)
	end

	-- connect now if humanoid exists
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		connectHumanoid(humanoid)
	end
	-- or listen for it being added later (respawned characters etc.)
	childAddedConn = character.ChildAdded:Connect(function(child)
		if child and child:IsA("Humanoid") then
			connectHumanoid(child)
		end
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup() end
	end)

	player.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup() end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		createRingForCharacter(player, char)
	end)
	if player.Character then
		createRingForCharacter(player, player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		createRingForCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		createRingForCharacter(player, char)
	end)
end
