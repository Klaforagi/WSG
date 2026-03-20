--------------------------------------------------------------------------------
-- UpgradeService.lua  –  Server-authoritative weapon upgrade management
-- ModuleScript in ServerScriptService.
--
-- NEW SYSTEM: Two infinite upgrade paths – melee_weapon & ranged_weapon.
-- Each level gives a small permanent damage multiplier increase.
--
-- Public API:
--   UpgradeService:Init()
--   UpgradeService:LoadForPlayer(player)  -> table
--   UpgradeService:SaveForPlayer(player)  -> bool
--   UpgradeService:SaveAll()
--   UpgradeService:PurchaseUpgrade(player, upgradeId)  -> bool, string
--   UpgradeService:GetLevel(player, upgradeId)  -> number
--   UpgradeService:GetAllLevels(player)  -> { [upgradeId] = level }
--   UpgradeService:GetMeleeMultiplier(player)  -> number
--   UpgradeService:GetRangedMultiplier(player)  -> number
--   UpgradeService:ClearPlayer(player)
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DATASTORE_NAME = "Upgrades_v2"   -- new key to avoid collisions with old system
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local UpgradeService = {}

--------------------------------------------------------------------------------
-- Lazy-require dependencies
--------------------------------------------------------------------------------
local UpgradeConfig
local function getUpgradeConfig()
	if UpgradeConfig then return UpgradeConfig end
	pcall(function()
		local mod = ReplicatedStorage:WaitForChild("UpgradeConfig", 10)
		if mod and mod:IsA("ModuleScript") then
			UpgradeConfig = require(mod)
		end
	end)
	return UpgradeConfig
end

local CurrencyService
local function getCurrencyService()
	if CurrencyService then return CurrencyService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("CurrencyService")
		if mod and mod:IsA("ModuleScript") then
			CurrencyService = require(mod)
		end
	end)
	return CurrencyService
end

--------------------------------------------------------------------------------
-- Per-player state: playerUpgrades[player] = { melee_weapon = N, ranged_weapon = N }
--------------------------------------------------------------------------------
local playerUpgrades = {}

-- RemoteEvent handle for pushing state updates to clients
local upgradeStateEvent

local function getKey(player)
	return "User_" .. tostring(player.UserId)
end

local function pushState(player)
	if not upgradeStateEvent then return end
	local levels = UpgradeService:GetAllLevels(player)
	pcall(function()
		upgradeStateEvent:FireClient(player, levels)
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
function UpgradeService:Init()
	getUpgradeConfig()
	getCurrencyService()

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		upgradeStateEvent = remotesFolder:FindFirstChild("UpgradeStateUpdated")
	end
end

--------------------------------------------------------------------------------
-- Data persistence
--------------------------------------------------------------------------------

function UpgradeService:LoadForPlayer(player)
	if not player then return {} end
	local key = getKey(player)
	local success, result
	for i = 1, RETRIES do
		success, result = pcall(function()
			return ds:GetAsync(key)
		end)
		if success then break end
		warn("UpgradeService: GetAsync failed (attempt", i, "):", tostring(result))
		task.wait(RETRY_DELAY * i)
	end

	local data = {}
	if success and type(result) == "table" then
		data = result
	elseif not success then
		warn("UpgradeService: failed to load for", tostring(player.Name), "; defaulting to empty")
	end

	local config = getUpgradeConfig()
	local validated = {}
	if config then
		-- Only load the two valid upgrade keys
		for id, _ in pairs(config.ValidIds) do
			local stored = data[id]
			if type(stored) == "number" and stored >= 0 then
				validated[id] = math.floor(stored)
			else
				validated[id] = 0
			end
		end
	end

	playerUpgrades[player] = validated
	print(("[UpgradeService] Loaded for %s: melee=%d, ranged=%d"):format(
		player.Name,
		validated.melee_weapon or 0,
		validated.ranged_weapon or 0))
	return validated
end

function UpgradeService:SaveForPlayer(player)
	if not player then return false end
	local key = getKey(player)
	local data = playerUpgrades[player] or {}
	local success, err
	for i = 1, RETRIES do
		success, err = pcall(function()
			ds:SetAsync(key, data)
		end)
		if success then break end
		warn("UpgradeService: SetAsync failed (attempt", i, "):", tostring(err))
		task.wait(RETRY_DELAY * i)
	end
	if not success then
		warn("UpgradeService: failed to save for", tostring(player.Name))
	end
	return success
end

function UpgradeService:SaveAll()
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		UpgradeService:SaveForPlayer(player)
	end
end

--------------------------------------------------------------------------------
-- Purchase
--------------------------------------------------------------------------------

function UpgradeService:PurchaseUpgrade(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return false, "Invalid request"
	end

	local config = getUpgradeConfig()
	if not config then return false, "Config unavailable" end

	if not config.IsValid(upgradeId) then
		return false, "Unknown upgrade"
	end

	local levels = playerUpgrades[player]
	if not levels then return false, "Player data not loaded" end

	local currentLevel = levels[upgradeId] or 0
	local price = config.GetCost(currentLevel)

	local cs = getCurrencyService()
	if not cs then return false, "Currency system unavailable" end

	local balance = cs:GetCoins(player)
	if balance < price then
		return false, "Insufficient coins"
	end

	-- Deduct coins (pass "purchase" source to prevent boost multiplier from applying)
	cs:AddCoins(player, -price, "purchase")

	-- Increase level
	levels[upgradeId] = currentLevel + 1
	print(("[UpgradeService] %s upgraded '%s' to level %d (cost %d coins)"):format(
		player.Name, upgradeId, levels[upgradeId], price))

	-- Save immediately
	task.spawn(function()
		UpgradeService:SaveForPlayer(player)
	end)

	-- Push updated state to client
	pushState(player)

	return true, "Upgraded"
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function UpgradeService:GetLevel(player, upgradeId)
	local levels = playerUpgrades[player]
	if not levels then return 0 end
	return levels[upgradeId] or 0
end

function UpgradeService:GetAllLevels(player)
	local levels = playerUpgrades[player]
	if not levels then return {} end
	local copy = {}
	for k, v in pairs(levels) do
		copy[k] = v
	end
	return copy
end

--- Returns the damage multiplier for melee weapons.
--- e.g. level 3 → 1.015
function UpgradeService:GetMeleeMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.MELEE)
	return config.GetMultiplier(level)
end

--- Returns the damage multiplier for ranged weapons.
function UpgradeService:GetRangedMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.RANGED)
	return config.GetMultiplier(level)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function UpgradeService:ClearPlayer(player)
	playerUpgrades[player] = nil
end

return UpgradeService
