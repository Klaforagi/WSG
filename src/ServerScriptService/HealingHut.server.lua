local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local HEAL_PART_NAME = "HealPart"

local HEAL_PER_TICK = 11
local HEAL_DURATION = 8
local TOTAL_TICKS = 9 -- first tick is instant, then 8 delayed ticks
local TICK_DELAY = HEAL_DURATION / (TOTAL_TICKS - 1)
local RESPAWN_TIME = 30
local HUT_HEAL_ACTIVE_ATTR = "_hut_heal_active"
local PICKUP_BOB_HEIGHT = 0.6
local PICKUP_BOB_SPEED = 1.4
local PICKUP_SPIN_SPEED = math.rad(40)

-- Guard against overlapping hut-heal runners on the same humanoid.
local activeHutHeals = {} -- [Humanoid] = true

local SoundsFolder = ReplicatedStorage:WaitForChild("Sounds")
local VFXFolder = ReplicatedStorage:WaitForChild("VFX")

local HealSoundTemplate = SoundsFolder:WaitForChild("Heal")
local HealWaveTemplate = VFXFolder:WaitForChild("HealWave")
local PlusHealsTemplate = VFXFolder:WaitForChild("PlusHeals")

local function getAnimationTarget(part)
	if not part or not part:IsA("BasePart") then
		return nil, nil
	end

	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		return model, model:GetPivot()
	end

	return part, part.CFrame
end

local function applyAnimatedCFrame(target, cframe)
	if not target or not target.Parent then
		return
	end

	if target:IsA("Model") then
		target:PivotTo(cframe)
	else
		target.CFrame = cframe
	end
end

local function startPickupAnimation(part)
	local target, baseCFrame = getAnimationTarget(part)
	if not target or not baseCFrame then
		return function() end
	end

	local startTime = os.clock()
	local phaseOffset = math.rad((math.abs(baseCFrame.Position.X) + math.abs(baseCFrame.Position.Z)) * 30)
	local baseRotation = baseCFrame - baseCFrame.Position
	local connection

	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		local elapsed = os.clock() - startTime
		local bobOffset = math.sin((elapsed * PICKUP_BOB_SPEED) + phaseOffset) * PICKUP_BOB_HEIGHT
		local spinOffset = elapsed * PICKUP_SPIN_SPEED
		local animatedPosition = baseCFrame.Position + Vector3.new(0, bobOffset, 0)
		local animatedCFrame = CFrame.new(animatedPosition) * CFrame.Angles(0, spinOffset, 0) * baseRotation
		applyAnimatedCFrame(target, animatedCFrame)
	end)

	return function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if target and target.Parent then
			applyAnimatedCFrame(target, baseCFrame)
		end
	end
end

local function setTransparencyRecursive(instance, transparency)
	if instance:IsA("BasePart") then
		instance.Transparency = transparency
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = transparency
		end
	end
end

local function setReadyState(instance, isReady)
	if instance:IsA("BasePart") then
		instance.CanCollide = false
		instance.CanTouch = isReady
		instance.CanQuery = isReady
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = isReady
			descendant.CanQuery = isReady
		end
	end

	local pointLight = instance:FindFirstChildWhichIsA("PointLight", true)
	if pointLight then
		pointLight.Enabled = isReady
	end
end

local function getEffectAttachPart(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("Head")
end

local function playPickupSound(character)
	local attachPart = getEffectAttachPart(character)
	if not attachPart then
		return
	end

	local sound = HealSoundTemplate:Clone()
	sound.Parent = attachPart
	sound:Play()

	Debris:AddItem(sound, math.max(sound.TimeLength + 1, 3))
end

local function startHealEffects(character)
	local attachPart = getEffectAttachPart(character)
	if not attachPart then
		return nil
	end

	local spawnedEffects = {}

	local healWave = HealWaveTemplate:Clone()
	healWave.Parent = attachPart
	table.insert(spawnedEffects, healWave)

	local plusHeals = PlusHealsTemplate:Clone()
	plusHeals.Parent = attachPart
	table.insert(spawnedEffects, plusHeals)

	for _, effect in ipairs(spawnedEffects) do
		if effect:IsA("ParticleEmitter") then
			effect.Enabled = true
		end
	end

	local function stop()
		for _, effect in ipairs(spawnedEffects) do
			if effect and effect.Parent then
				if effect:IsA("ParticleEmitter") then
					effect.Enabled = false
					Debris:AddItem(effect, 2)
				else
					effect:Destroy()
				end
			end
		end
	end

	return stop
end

local function healCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if activeHutHeals[humanoid] then
		return
	end

	activeHutHeals[humanoid] = true
	pcall(function()
		humanoid:SetAttribute(HUT_HEAL_ACTIVE_ATTR, true)
	end)

	local canceled = false
	local lastHealth = humanoid.Health

	local stopEffects = startHealEffects(character)
	playPickupSound(character)

	local healthConn
	healthConn = humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth then
			canceled = true
		end
		lastHealth = newHealth
	end)

	for tick = 1, TOTAL_TICKS do
		if canceled or humanoid.Health <= 0 then
			break
		end

		if tick > 1 then
			-- First tick is instant, remaining ticks are spaced across the full duration.
			task.wait(TICK_DELAY)
		end

		-- Apply evenly spaced pulses over 8 seconds (instant first pulse).
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.Health + HEAL_PER_TICK, humanoid.MaxHealth)
		end
	end
	
	if healthConn then
		healthConn:Disconnect()
	end

	if stopEffects then
		stopEffects()
	end

	activeHutHeals[humanoid] = nil
	if humanoid and humanoid.Parent then
		pcall(function()
			humanoid:SetAttribute(HUT_HEAL_ACTIVE_ATTR, false)
		end)
	end
end

local function setupHealPart(part)
	local template = part:Clone()
	local respawnParent = part.Parent
	local respawnCFrame = part.CFrame
	local stopAnimation = startPickupAnimation(part)

	local claimed = false

	local function connectPickup(currentPart)
		currentPart.Touched:Connect(function(hit)
			if claimed then
				return
			end

			local character = hit.Parent
			if not character then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return
			end

			if humanoid.Health >= humanoid.MaxHealth then
				return
			end

			claimed = true
			stopAnimation()

			task.spawn(function()
				healCharacter(character)
			end)

			currentPart:Destroy()

			task.spawn(function()
				task.wait(RESPAWN_TIME)

				local newPart = template:Clone()
				newPart.CFrame = respawnCFrame
				newPart.Parent = respawnParent
				stopAnimation = startPickupAnimation(newPart)

				setTransparencyRecursive(newPart, 1)
				setReadyState(newPart, false)

				for second = 1, RESPAWN_TIME do
					task.wait(1)
					local transparency = 1 - (second / RESPAWN_TIME)
					setTransparencyRecursive(newPart, transparency)
				end

				setTransparencyRecursive(newPart, 0)
				setReadyState(newPart, true)

				claimed = false
				connectPickup(newPart)
			end)
		end)
	end

	connectPickup(part)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("BasePart") and descendant.Name == HEAL_PART_NAME then
		setupHealPart(descendant)
	end
end