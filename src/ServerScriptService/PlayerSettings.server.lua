-- PlayerSettings.server.lua
-- Head + accessory no-collide, prevent FallingDown, and keep players upright WITHOUT blocking yaw turning.

local Players = game:GetService("Players")

-- FallingDown is often reached via Physics/Ragdoll first during torque events.
local BLOCKED_STATES = {
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
}

local ENABLE_UPRIGHT_STABILIZER = true

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

local function lockHumanoidStates(hum: Humanoid)
	for stateType in pairs(BLOCKED_STATES) do
		hum:SetStateEnabled(stateType, false)
	end

	hum.StateChanged:Connect(function(_, newState)
		if BLOCKED_STATES[newState] then
			hum.PlatformStand = false
			if hum.FloorMaterial == Enum.Material.Air then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			else
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
		end
	end)
end

-- Keeps the character upright (resists tipping) but allows free yaw turning.
local function addUprightStabilizer(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	-- clean duplicates
	local oldAlign = hrp:FindFirstChild("UprightAlign")
	if oldAlign then oldAlign:Destroy() end
	local oldAtt = hrp:FindFirstChild("UprightAttach")
	if oldAtt then oldAtt:Destroy() end

	local att = Instance.new("Attachment")
	att.Name = "UprightAttach"
	att.Parent = hrp

	-- Make the attachment's PRIMARY axis be "up" in HRP local space.
	-- AlignOrientation will try to align this axis with the target axis in world space.
	att.Axis = Vector3.new(0, 1, 0)

	local align = Instance.new("AlignOrientation")
	align.Name = "UprightAlign"
	align.Attachment0 = att
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment

	-- This is the key: only align the primary axis (up), allowing yaw freely.
	align.PrimaryAxisOnly = true

	-- Tuning: higher = more "firm" upright. Too high can feel snappy.
	align.Responsiveness = 40
	align.MaxTorque = 250000

	-- Target orientation: we set the TARGET X-axis (RightVector) to world UP.
	-- Because PrimaryAxisOnly aligns Attachment0.Axis to the target's X-axis.
	align.CFrame = CFrame.fromMatrix(
		Vector3.zero,
		Vector3.new(0, 1, 0),  -- target X axis = world up
		Vector3.new(0, 0, -1)  -- target Y axis = world -Z (just needs to be orthonormal)
	)

	align.Parent = hrp
end

local function applyCharacterSettings(char: Model)
	applyHeadAndAccessoryNoCollide(char)

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		lockHumanoidStates(hum)
	end

	if ENABLE_UPRIGHT_STABILIZER then
		addUprightStabilizer(char)
	end
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