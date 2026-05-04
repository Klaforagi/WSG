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

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local DATASTORE_NAME = "Upgrades_v3"   -- bumped to reset all upgrade progress for testing
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

local function copyUpgradeData(data)
	return DataStoreOps.DeepCopy(data)
end

local function totalUpgradeLevels(data)
	if type(data) ~= "table" then
		return 0
	end
	local total = 0
	for _, value in pairs(data) do
		if type(value) == "number" then
			total += value
		end
	end
	return total
end

local function markUpgradeDirty(player, reason, options)
	DataSaveCoordinator:MarkDirty(player, "Upgrade", reason or "upgrade", options)
end

--------------------------------------------------------------------------------
-- Reusable cap helper: clamp upgrade level to player level
--------------------------------------------------------------------------------
local function clampUpgradeLevel(currentUpgradeLevel, playerLevel)
	return math.min(currentUpgradeLevel, math.max(0, playerLevel))
end

--- Returns the player's current XP level (reads the "Level" attribute set by XPService).
local function getPlayerLevel(player)
	local level = 1
	pcall(function()
		level = player:GetAttribute("Level") or 1
	end)
	return math.max(1, level)
end

-- RemoteEvent handle for pushing state updates to clients
local upgradeStateEvent

local function getKey(player)
	return "User_" .. tostring(player.UserId)
end

local function pushState(player)
	if not upgradeStateEvent then return end
	local levels = UpgradeService:GetAllLevels(player)
	levels._playerLevel = getPlayerLevel(player)
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
	local success, result, err = DataStoreOps.Load(ds, key, "Upgrade/" .. key)

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

	-- Note: We do NOT clamp upgrade levels on load. The player-level cap
	-- is enforced only at purchase time. Clamping on load caused a race
	-- condition where XPService hadn't set the "Level" attribute yet,
	-- resulting in getPlayerLevel returning 1 and destroying saved progress.

	playerUpgrades[player] = validated
	print(("[UpgradeService] Loaded for %s: melee=%d, ranged=%d"):format(
		player.Name,
		validated.melee_weapon or 0,
		validated.ranged_weapon or 0))
	return {
		status = success and (result == nil and "new" or "existing") or "failed",
		data = copyUpgradeData(validated),
		reason = err,
	}
end

function UpgradeService:SaveForPlayer(player, saveData)
	if not player then return false end
	local key = getKey(player)
	local data = saveData or playerUpgrades[player] or {}
	local success, _, err = DataStoreOps.Update(ds, key, "Upgrade/" .. key, function(oldData)
		if totalUpgradeLevels(oldData) > 0 and totalUpgradeLevels(data) == 0 then
			warn("[UpgradeService] suspected wipe blocked for", tostring(player.Name))
			return oldData
		end
		return data
	end)
	if not success then
		warn("UpgradeService: failed to save for", tostring(player.Name))
	end
	return success
end

function UpgradeService:GetSaveData(player)
	local data = playerUpgrades[player]
	if not data then return nil end
	return copyUpgradeData(data)
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

	-- Player-level gate (now disabled by default in UpgradeConfig).
	if config.REQUIRE_PLAYER_LEVEL == true then
		local pLevel = getPlayerLevel(player)
		if currentLevel >= pLevel then
			return false, "Upgrade capped by player level"
		end
	end

	local price = config.GetCost(currentLevel)
	local currency = (config.GetCurrency and config.GetCurrency()) or "scrap"

	local cs = getCurrencyService()
	if not cs then return false, "Currency system unavailable" end

	if currency == "scrap" then
		if not cs.GetSalvage or not cs.RemoveSalvage then
			return false, "Scrap currency unavailable"
		end
		local balance = cs:GetSalvage(player)
		if balance < price then
			return false, "Insufficient scrap"
		end
		cs:RemoveSalvage(player, price)
	else
		-- Legacy coin path
		local balance = cs:GetCoins(player)
		if balance < price then
			return false, "Insufficient coins"
		end
		cs:AddCoins(player, -price, "upgrade")
	end

	-- Increase level (no cap when REQUIRE_PLAYER_LEVEL=false)
	local newLevel = currentLevel + 1
	if config.REQUIRE_PLAYER_LEVEL == true then
		newLevel = clampUpgradeLevel(newLevel, getPlayerLevel(player))
	end
	levels[upgradeId] = newLevel
	print(("[UpgradeService] %s upgraded '%s' to level %d (cost %d %s)"):format(
		player.Name, upgradeId, levels[upgradeId], price, currency))

	markUpgradeDirty(player, "upgrade_purchase")
	DataSaveCoordinator:RequestImmediateSave(player, "upgrade_purchase", {
		sections = { "Upgrade" },
		force = true,
	})

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

--- Returns the damage multiplier for melee weapons (PvE, uncapped).
--- e.g. level 10 → 1.30
function UpgradeService:GetMeleeMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.MELEE)
	return config.GetPvEMultiplier(level, config.MELEE)
end

--- Returns the player's XP/player level (for cap checks).
function UpgradeService:GetPlayerLevel(player)
	return getPlayerLevel(player)
end

--- Returns the damage multiplier for ranged weapons (PvE, uncapped).
function UpgradeService:GetRangedMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.RANGED)
	return config.GetPvEMultiplier(level, config.RANGED)
end

--- PvP melee multiplier (capped).
function UpgradeService:GetMeleePvPMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.MELEE)
	return config.GetPvPMultiplier(level, config.MELEE)
end

--- PvE melee multiplier (uncapped).
function UpgradeService:GetMeleePvEMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.MELEE)
	return config.GetPvEMultiplier(level, config.MELEE)
end

--- PvP ranged multiplier (capped).
function UpgradeService:GetRangedPvPMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.RANGED)
	return config.GetPvPMultiplier(level, config.RANGED)
end

--- PvE ranged multiplier (uncapped).
function UpgradeService:GetRangedPvEMultiplier(player)
	local config = getUpgradeConfig()
	if not config then return 1 end
	local level = self:GetLevel(player, config.RANGED)
	return config.GetPvEMultiplier(level, config.RANGED)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function UpgradeService:ClearPlayer(player)
	playerUpgrades[player] = nil
end

return UpgradeService
