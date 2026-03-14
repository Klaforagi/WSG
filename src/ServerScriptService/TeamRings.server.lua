local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RING_TEMPLATE = ServerStorage:FindFirstChild("Ring")
if not RING_TEMPLATE then
	warn("TeamRings.server: 'Ring' template not found in ServerStorage. Aborting.")
	return
end

local TEMPLATE_IS_MODEL = RING_TEMPLATE:IsA("Model")
local TEMPLATE_IS_PART = RING_TEMPLATE:IsA("BasePart")
if not (TEMPLATE_IS_MODEL or TEMPLATE_IS_PART) then
	warn("TeamRings.server: 'Ring' must be a Model or a BasePart in ServerStorage. Aborting.")
	return
end

-- Debug info to help troubleshoot Ring template
warn("TeamRings.server: Found Ring template ->", RING_TEMPLATE:GetFullName(), "Class=", RING_TEMPLATE.ClassName)
for _, child in ipairs(RING_TEMPLATE:GetChildren()) do
	warn("TeamRings.server: Ring child ->", child.Name, "Class=", child.ClassName)
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

	local ringInstance
	local segmentsOrdered = {}

	local function updateSegmentsFor(hum)
		if not hum or not hum.Parent then return end
		local total = #segmentsOrdered
		if total == 0 then return end
		local maxHealth = math.max(hum.MaxHealth or 1, 1)
		local frac = math.clamp((hum.Health or 0) / maxHealth, 0, 1)
		local showCount = math.floor(frac * total + 0.000001)
		for i, part in ipairs(segmentsOrdered) do
			if part and part.Parent then
				local target = (i <= showCount) and 0 or 1
				if part.Transparency ~= target then
					local tween = TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = target})
					tween:Play()
				end
			end
		end
	end
	if TEMPLATE_IS_MODEL then
		-- Clone the model template and position it under the root part.
		local modelClone = RING_TEMPLATE:Clone()
		-- Ensure there's a PrimaryPart to position the model; prefer a child named
		-- "PrimaryPart" if present, otherwise fall back to the first BasePart.
		if not modelClone.PrimaryPart then
			local explicit = modelClone:FindFirstChild("PrimaryPart", true)
			if explicit and explicit:IsA("BasePart") then
				modelClone.PrimaryPart = explicit
			else
				for _, d in ipairs(modelClone:GetDescendants()) do
					if d:IsA("BasePart") then
						modelClone.PrimaryPart = d
						break
					end
				end
			end
		end
		-- Position the model so its PrimaryPart sits directly under the player's root part
		-- and rotate it 90 degrees so the ring lays flat beneath the player.
		local targetCFrame = root.CFrame * CFrame.new(0, RING_OFFSET_Y, 0) * CFrame.Angles(math.rad(90), 0, 0)
		if modelClone.PrimaryPart then
			modelClone:SetPrimaryPartCFrame(targetCFrame)
		else
			-- Fallback: position each BasePart's CFrame to the target CFrame.
			for _, d in ipairs(modelClone:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = targetCFrame
				end
			end
		end
		modelClone.Parent = workspace

		-- Configure each part in the cloned model and weld it to the root so it follows the character.
		local numberedParts = {}
		for _, d in ipairs(modelClone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.Massless = true
				d.CanCollide = false
				d.Material = Enum.Material.Neon
				d.Color = teamColorOfPlayer(player)
				-- Only make the PrimaryPart fully transparent; keep other parts visible.
				if modelClone.PrimaryPart and d == modelClone.PrimaryPart then
					d.Transparency = 1
				else
					d.Transparency = 0
				end
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d

				-- If the part's name is numeric (e.g. "01", "02", ...), register it as a segment.
				local n = tonumber(d.Name)
				if n then
					table.insert(numberedParts, {index = n, part = d})
				end
			end
		end

		-- Sort numbered segments by their numeric index (ascending) and build ordered list.
		table.sort(numberedParts, function(a, b) return a.index < b.index end)
		segmentsOrdered = {}
		for _, entry in ipairs(numberedParts) do
			table.insert(segmentsOrdered, entry.part)
		end
		ringInstance = modelClone
	else
		local partClone = RING_TEMPLATE:Clone()
		partClone.Anchored = false
		partClone.Massless = true
		partClone.CanCollide = false
		-- keep single-part ring fully transparent as requested
		partClone.Transparency = 1
		partClone.Material = Enum.Material.Neon
		partClone.Color = teamColorOfPlayer(player)
		partClone.Parent = workspace
		partClone.CFrame = root.CFrame * CFrame.new(0, RING_OFFSET_Y, 0) * CFrame.Angles(math.rad(90), 0, 0)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = partClone
		weld.Parent = partClone
		ringInstance = partClone
	end

	local teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
		if ringInstance and ringInstance.Parent then
			if ringInstance:IsA("Model") then
				for _, d in ipairs(ringInstance:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Color = teamColorOfPlayer(player)
					end
				end
			elseif ringInstance:IsA("BasePart") then
				ringInstance.Color = teamColorOfPlayer(player)
			end
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
		if ringInstance and ringInstance.Parent then
			ringInstance:Destroy()
		end
	end

	local function connectHumanoid(hum)
		if not hum or humanoidConn then return end
		humanoidConn = hum.Died:Connect(cleanup)
		healthConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
			if hum.Health and hum.Health <= 0 then
				cleanup()
			else
				-- update segment visibility when health changes
				pcall(function() updateSegmentsFor(hum) end)
			end
		end)
		-- run initial update
		pcall(function() updateSegmentsFor(hum) end)
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
