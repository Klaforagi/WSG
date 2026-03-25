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

local function applyCharacterSettings(char: Model)
	-- Keep head/accessory no-collide for safety, but do not force upright or block humanoid states.
	applyHeadAndAccessoryNoCollide(char)
	-- Start server-authoritative passive health regen if enabled in config
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and PlayerSettingsConfig and PlayerSettingsConfig.HealthRegen and PlayerSettingsConfig.HealthRegen.Enabled then
		local amt = tonumber(PlayerSettingsConfig.HealthRegen.AmountPerTick) or 1
		local interval = tonumber(PlayerSettingsConfig.HealthRegen.TickInterval) or 5

		-- Enforce sane minimums to avoid extremely fast ticks
		if interval < 0.05 then interval = 0.05 end
		if amt <= 0 then amt = 1 end

		-- Prevent multiple regen loops for the same humanoid by using an attribute flag
		local regenFlag = "_ps_regen_active"
		if hum:GetAttribute(regenFlag) then
			return
		end
		hum:SetAttribute(regenFlag, true)

		-- Spawn a loop that heals the humanoid every `interval` seconds while alive.
		-- The loop exits when the humanoid dies or the character is removed.
		spawn(function()
			local conn
			local alive = true
			conn = hum.Died:Connect(function()
				alive = false
				if conn then conn:Disconnect() end
			end)

			while alive and hum and hum.Parent do
				-- Only heal if below MaxHealth
				local maxHp = hum.MaxHealth or 100
				if hum.Health > 0 and hum.Health < maxHp then
					hum.Health = math.min(maxHp, hum.Health + amt)
				end
				task.wait(interval)
			end

			if conn and conn.Connected then
				conn:Disconnect()
			end
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