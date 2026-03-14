-- PlayerSettings.server.lua
-- Head + accessory no-collide, prevent FallingDown, and keep players upright WITHOUT blocking yaw turning.

local Players = game:GetService("Players")

-- FallingDown is often reached via Physics/Ragdoll first during torque events.
-- NOTE: Upright stabilizer and blocked-state enforcement removed per request.

local function setNoCollide(part: BasePart)
	part.CanCollide = false
end

local function applyHeadAndAccessoryNoCollide(char: Model)
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		setNoCollide(head)
	end

	local function handleAccessory(inst: Instance)
		if inst:IsA("Accessory") then
			local handle = inst:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				setNoCollide(handle)
			end
		end
	end

	for _, child in ipairs(char:GetChildren()) do
		handleAccessory(child)
	end
	char.ChildAdded:Connect(handleAccessory)
end

-- lockHumanoidStates removed to avoid forcing upright or blocking states

-- Keeps the character upright (resists tipping) but allows free yaw turning.
-- addUprightStabilizer removed to avoid forcing upright alignment

local function applyCharacterSettings(char: Model)
	-- Keep head/accessory no-collide for safety, but do not force upright or block humanoid states.
	applyHeadAndAccessoryNoCollide(char)
	-- Intentionally do not modify humanoid states or add stabilizers here.
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			applyCharacterSettings(char)
		end)
	end)

	if player.Character then
		applyCharacterSettings(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end