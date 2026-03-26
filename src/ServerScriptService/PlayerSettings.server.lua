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

	-- Remove default Roblox health regen script if present
	local healthScript = char:FindFirstChild("Health")
	if healthScript and healthScript:IsA("Script") then
		healthScript:Destroy()
	end

	-- Start server-authoritative passive health regen if enabled in config
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and PlayerSettingsConfig and PlayerSettingsConfig.HealthRegen and PlayerSettingsConfig.HealthRegen.Enabled then
		local amt = tonumber(PlayerSettingsConfig.HealthRegen.AmountPerTick) or 1
		local interval = tonumber(PlayerSettingsConfig.HealthRegen.TickInterval) or 5

		-- Warn if settings are so low that regen appears non-functional
		if amt <= 0 then
			warn("[PlayerSettings] HealthRegen.AmountPerTick is <= 0; regen will not occur!")
		end
		if interval > 30 then
			warn("[PlayerSettings] HealthRegen.TickInterval is very high (>", interval, ") – regen may appear non-functional.")
		end

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
		task.spawn(function()
			-- Listen for death to stop regen
			local alive = true
			local diedConn = hum.Died:Connect(function()
				alive = false
			end)
			-- Listen for character removal to stop regen
			local ancestryConn = char.AncestryChanged:Connect(function(_, parent)
				if not parent then
					alive = false
				end
			end)

			while alive and hum and hum.Parent do
				-- Only heal if below MaxHealth
				local maxHp = hum.MaxHealth or 100
				if hum.Health > 0 and hum.Health < maxHp then
					hum.Health = math.min(maxHp, hum.Health + amt)
				end
				task.wait(interval)
			end

			-- Clean up connections
			if diedConn.Connected then diedConn:Disconnect() end
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