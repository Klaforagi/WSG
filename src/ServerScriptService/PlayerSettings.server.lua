-- PlayerSettings.server.lua
-- Head + accessory no-collide, prevent FallingDown, and keep players upright WITHOUT blocking yaw turning.

local Players = game:GetService("Players")

-- Load server-side player settings module
local PlayerSettingsConfig = nil
do
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild("PlayerSettingsConfig"))
	end)
	if ok and type(mod) == "table" then
		PlayerSettingsConfig = mod
	else
		warn("[PlayerSettings] PlayerSettingsConfig missing or failed to load; using defaults")
		PlayerSettingsConfig = {}
	end
end

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

local function applySpawnForceField(char: Model)
	-- Remove any existing ForceField first (Roblox may create one via SpawnLocation)
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("ForceField") then
			v:Destroy()
		end
	end

	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = char

	local removed = false
	local function removeFF()
		if removed then return end
		removed = true
		if ff and ff.Parent then
			ff:Destroy()
		end
	end

	-- Remove when any Tool is equipped
	local toolConn
	toolConn = char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			toolConn:Disconnect()
			removeFF()
		end
	end)

	-- Remove after 2 seconds regardless
	task.delay(2, function()
		toolConn:Disconnect()
		removeFF()
	end)
end

local function applyCharacterSettings(char: Model)
	-- Keep head/accessory no-collide for safety, but do not force upright or block humanoid states.
	applyHeadAndAccessoryNoCollide(char)
	applySpawnForceField(char)

	-- Remove default Roblox health regen script if present
	local healthScript = char:FindFirstChild("Health")
	if healthScript and healthScript:IsA("Script") then
		healthScript:Destroy()
	end

	-- Start server-authoritative passive health regen if enabled in config
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and PlayerSettingsConfig and PlayerSettingsConfig.HealthRegen and PlayerSettingsConfig.HealthRegen.Enabled then
		local regenCfg = PlayerSettingsConfig.HealthRegen
		local configuredStages = regenCfg.Stages
		local stages = {}

		if type(configuredStages) == "table" then
			for _, stage in ipairs(configuredStages) do
				local delaySinceDamage = tonumber(stage.DelaySinceDamage)
				local amountPerTick = tonumber(stage.AmountPerTick)
				local tickInterval = tonumber(stage.TickInterval)
				if delaySinceDamage and amountPerTick and tickInterval and tickInterval > 0 and amountPerTick > 0 then
					table.insert(stages, {
						DelaySinceDamage = delaySinceDamage,
						AmountPerTick = amountPerTick,
						TickInterval = math.max(0.05, tickInterval),
					})
				end
			end
		end

		if #stages == 0 then
			stages = {
				{ DelaySinceDamage = 5, AmountPerTick = 1, TickInterval = 1 },
				{ DelaySinceDamage = 10, AmountPerTick = 2, TickInterval = 1 },
				{ DelaySinceDamage = 15, AmountPerTick = 1, TickInterval = 0.5 },
			}
			warn("[PlayerSettings] HealthRegen.Stages missing/invalid; using default staged regen")
		end

		table.sort(stages, function(a, b)
			return a.DelaySinceDamage < b.DelaySinceDamage
		end)

		-- Prevent multiple regen loops for the same humanoid by using an attribute flag
		local regenFlag = "_ps_regen_active"
		if hum:GetAttribute(regenFlag) then
			return
		end
		hum:SetAttribute(regenFlag, true)

		-- Spawn a staged regen loop:
		-- damage disables regen immediately, then regen ramps by time-since-damage.
		task.spawn(function()
			-- Listen for death to stop regen
			local alive = true
			local lastDamageAt = os.clock()
			local previousHealth = hum.Health
			local activeStageIndex = 0
			local nextRegenAt = math.huge

			local function getActiveStageIndex(secondsSinceDamage)
				local idx = 0
				for i, stage in ipairs(stages) do
					if secondsSinceDamage >= stage.DelaySinceDamage then
						idx = i
					end
				end
				return idx
			end

			local diedConn = hum.Died:Connect(function()
				alive = false
			end)
			local healthConn = hum.HealthChanged:Connect(function(newHealth)
				if newHealth < previousHealth then
					-- Any damage immediately disables regen and restarts the stage timer.
					lastDamageAt = os.clock()
					activeStageIndex = 0
					nextRegenAt = math.huge
				end
				previousHealth = newHealth
			end)
			-- Listen for character removal to stop regen
			local ancestryConn = char.AncestryChanged:Connect(function(_, parent)
				if not parent then
					alive = false
				end
			end)

			while alive and hum and hum.Parent do
				local now = os.clock()
				local secondsSinceDamage = now - lastDamageAt
				local stageIndex = getActiveStageIndex(secondsSinceDamage)

				if stageIndex ~= activeStageIndex then
					activeStageIndex = stageIndex
					if activeStageIndex > 0 then
						-- Apply first tick immediately when entering a regen stage.
						nextRegenAt = now
					else
						nextRegenAt = math.huge
					end
				end

				if activeStageIndex > 0 and now >= nextRegenAt then
					local activeStage = stages[activeStageIndex]
					local maxHp = hum.MaxHealth or 100
					if hum.Health > 0 and hum.Health < maxHp then
						hum.Health = math.min(maxHp, hum.Health + activeStage.AmountPerTick)
					end
					nextRegenAt = now + activeStage.TickInterval
				end

				task.wait(0.1)
			end

			-- Clean up connections
			if diedConn.Connected then diedConn:Disconnect() end
			if healthConn.Connected then healthConn:Disconnect() end
			if ancestryConn.Connected then ancestryConn:Disconnect() end
			-- Clear the regen flag
			if hum and hum.Parent then
				pcall(function() hum:SetAttribute(regenFlag, false) end)
			end
		end)
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