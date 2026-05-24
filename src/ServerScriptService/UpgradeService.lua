--------------------------------------------------------------------------------
-- UpgradeService.lua  –  Server-authoritative upgrade management
-- ModuleScript in ServerScriptService.
--
-- Upgrade paths:
--   • melee_weapon  → infinite damage upgrade
--   • ranged_weapon → infinite damage upgrade
--   • max_health    → capped health upgrade with player-level gates
--
-- Public API:
--   UpgradeService:Init()
--   UpgradeService:LoadForPlayer(player)  -> table
--   UpgradeService:SaveForPlayer(player)  -> bool
--   UpgradeService:SaveAll()
--   UpgradeService:PurchaseUpgrade(player, upgradeId)  -> bool, string, table?
--   UpgradeService:GetLevel(player, upgradeId)  -> number
--   UpgradeService:GetAllLevels(player)  -> { [upgradeId] = level }
--   UpgradeService:GetMeleeMultiplier(player)  -> number
--   UpgradeService:GetRangedMultiplier(player)  -> number
--   UpgradeService:GetHealthBonus(player)  -> number
--   UpgradeService:ApplyHealthUpgrade(player, humanoid, options?)  -> number, number
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
-- Per-player state: playerUpgrades[player] = { melee_weapon = N, ranged_weapon = N, max_health = N }
--------------------------------------------------------------------------------
local playerUpgrades = {}
local purchaseLocks = {}
local stateChangedEvent = Instance.new("BindableEvent")
local BASE_MAX_HEALTH_ATTRIBUTE = "_upgradeBaseMaxHealth"

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

local function getHumanoid(player)
	if not player then return nil end
	local character = player.Character
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Parent then
		return humanoid
	end
	return nil
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

local function getCurrencyBalance(currencyService, player, currency)
	if not currencyService then
		return 0
	end
	if currency == "scrap" then
		if currencyService.GetSalvage then
			return math.max(0, math.floor(tonumber(currencyService:GetSalvage(player)) or 0))
		end
		return 0
	end
	if currencyService.GetCoins then
		return math.max(0, math.floor(tonumber(currencyService:GetCoins(player)) or 0))
	end
	return 0
end

local function buildPurchaseResult(player, upgradeId, success, message, extra)
	extra = type(extra) == "table" and extra or {}

	local config = getUpgradeConfig()
	local levels = playerUpgrades[player]
	local currentLevel = 0
	if type(levels) == "table" and type(upgradeId) == "string" then
		currentLevel = math.max(0, math.floor(tonumber(levels[upgradeId]) or 0))
	end

	local currency = "scrap"
	local nextCost = nil
	local maxLevel = false
	if config and type(upgradeId) == "string" and config.IsValid and config.IsValid(upgradeId) then
		currency = (config.GetCurrency and config.GetCurrency(upgradeId)) or currency
		maxLevel = (config.IsCapped and config.IsCapped(currentLevel, upgradeId)) or false
		if not maxLevel and config.GetCost then
			nextCost = config.GetCost(currentLevel, upgradeId)
		end
	end

	local currencyService = getCurrencyService()
	local currentCurrency = getCurrencyBalance(currencyService, player, currency)
	local updatedUpgradeData = UpgradeService:GetAllLevels(player)
	updatedUpgradeData._playerLevel = getPlayerLevel(player)

	local result = {
		success = success == true,
		reason = success == true and nil or tostring(message or "Upgrade failed"),
		message = tostring(message or (success and "Upgraded" or "Upgrade failed")),
		category = upgradeId,
		upgradeId = upgradeId,
		newLevel = currentLevel,
		nextCost = nextCost,
		currentCurrency = currentCurrency,
		currency = currency,
		maxLevel = maxLevel,
		playerLevel = updatedUpgradeData._playerLevel,
		updatedUpgradeData = updatedUpgradeData,
		levels = updatedUpgradeData,
	}

	if currency == "scrap" then
		result.shardBalance = currentCurrency
	else
		result.coins = currentCurrency
	end

	for key, value in pairs(extra) do
		result[key] = value
	end

	return result
end

local function acquirePurchaseLock(player, upgradeId)
	local locks = purchaseLocks[player]
	if not locks then
		locks = {}
		purchaseLocks[player] = locks
	end
	if locks[upgradeId] then
		return false
	end
	locks[upgradeId] = true
	return true
end

local function releasePurchaseLock(player, upgradeId)
	local locks = purchaseLocks[player]
	if not locks then
		return
	end
	locks[upgradeId] = nil
	if next(locks) == nil then
		purchaseLocks[player] = nil
	end
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
	print(("[UpgradeService] Loaded for %s: melee=%d, ranged=%d, health=%d"):format(
		player.Name,
		validated.melee_weapon or 0,
		validated.ranged_weapon or 0,
		validated.max_health or 0))
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

function UpgradeService:_PurchaseUpgradeUnlocked(player, upgradeId)
	local function fail(message)
		return false, message, buildPurchaseResult(player, upgradeId, false, message)
	end

	if not player or type(upgradeId) ~= "string" then
		return fail("Invalid request")
	end

	local config = getUpgradeConfig()
	if not config then return fail("Config unavailable") end

	if not config.IsValid(upgradeId) then
		return fail("Unknown upgrade")
	end

	local levels = playerUpgrades[player]
	if not levels then return fail("Player data not loaded") end

	local currentLevel = levels[upgradeId] or 0
	if config.IsCapped and config.IsCapped(currentLevel, upgradeId) then
		return fail("Upgrade maxed")
	end

	local pLevel = getPlayerLevel(player)
	if config.IsPlayerLevelLocked then
		local isLocked, requiredLevel = config.IsPlayerLevelLocked(currentLevel, pLevel, upgradeId)
		if isLocked then
			if upgradeId == config.HEALTH and requiredLevel then
				return fail(string.format("Reach player level %d to buy this upgrade", requiredLevel))
			end
			return fail("Upgrade capped by player level")
		end
	elseif config.REQUIRE_PLAYER_LEVEL == true and currentLevel >= pLevel then
		return fail("Upgrade capped by player level")
	end

	local price = config.GetCost(currentLevel, upgradeId)
	local currency = (config.GetCurrency and config.GetCurrency(upgradeId)) or "scrap"

	local cs = getCurrencyService()
	if not cs then return fail("Currency system unavailable") end

	if currency == "scrap" then
		if not cs.GetSalvage or not cs.RemoveSalvage then
			return fail("Shard currency unavailable")
		end
		local balance = cs:GetSalvage(player)
		if balance < price then
			return fail("Insufficient Shards")
		end
		cs:RemoveSalvage(player, price)
	else
		-- Legacy coin path
		local balance = cs:GetCoins(player)
		if balance < price then
			return fail("Insufficient coins")
		end
		cs:AddCoins(player, -price, "upgrade")
	end

	-- Increase level (no cap when REQUIRE_PLAYER_LEVEL=false)
	local newLevel = currentLevel + 1
	if config.IsCapped and config.IsCapped(newLevel, upgradeId) then
		local maxLevel = config.GetMaxLevel and config.GetMaxLevel(upgradeId)
		if maxLevel then
			newLevel = maxLevel
		end
	elseif config.REQUIRE_PLAYER_LEVEL == true then
		newLevel = clampUpgradeLevel(newLevel, getPlayerLevel(player))
	end
	levels[upgradeId] = newLevel
	print(("[UpgradeService] %s upgraded '%s' to level %d (cost %d %s)"):format(
		player.Name, upgradeId, levels[upgradeId], price, currency))

	markUpgradeDirty(player, "upgrade_purchase")

	if upgradeId == config.HEALTH then
		local humanoid = getHumanoid(player)
		if humanoid and humanoid.Health > 0 then
			self:ApplyHealthUpgrade(player, humanoid, {
				adjustCurrentHealth = true,
			})
		end
	end

	-- Push updated state to client
	pushState(player)
	stateChangedEvent:Fire(player, upgradeId, newLevel, copyUpgradeData(levels))

	return true, "Upgraded", buildPurchaseResult(player, upgradeId, true, "Upgraded", {
		costPaid = price,
	})
end

function UpgradeService:PurchaseUpgrade(player, upgradeId)
	if not player or type(upgradeId) ~= "string" then
		return false, "Invalid request", buildPurchaseResult(player, upgradeId, false, "Invalid request")
	end

	if not acquirePurchaseLock(player, upgradeId) then
		return false, "Upgrade already in progress", buildPurchaseResult(player, upgradeId, false, "Upgrade already in progress")
	end

	local ok, success, message, result = pcall(function()
		return self:_PurchaseUpgradeUnlocked(player, upgradeId)
	end)
	releasePurchaseLock(player, upgradeId)

	if not ok then
		warn("[UpgradeService] purchase failed unexpectedly:", tostring(success))
		return false, "Upgrade failed", buildPurchaseResult(player, upgradeId, false, "Upgrade failed")
	end

	return success, message, result
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

function UpgradeService:GetStateChangedEvent()
	return stateChangedEvent.Event
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

function UpgradeService:GetHealthBonus(player)
	local config = getUpgradeConfig()
	if not config or type(config.GetHealthBonus) ~= "function" then
		return 0
	end
	local level = self:GetLevel(player, config.HEALTH)
	return config.GetHealthBonus(level)
end

function UpgradeService:ApplyHealthUpgrade(player, humanoid, options)
	if not player or not humanoid then
		return 0, 0
	end

	local currentMax = humanoid.MaxHealth
	if type(currentMax) ~= "number" or currentMax <= 0 then
		currentMax = 100
	end

	local baseMax = humanoid:GetAttribute(BASE_MAX_HEALTH_ATTRIBUTE)
	if type(baseMax) ~= "number" or baseMax <= 0 then
		baseMax = currentMax
		pcall(function()
			humanoid:SetAttribute(BASE_MAX_HEALTH_ATTRIBUTE, baseMax)
		end)
	end

	local targetMax = math.max(1, baseMax + self:GetHealthBonus(player))
	local delta = targetMax - currentMax
	if delta == 0 then
		return targetMax, 0
	end

	humanoid.MaxHealth = targetMax
	if not options or options.adjustCurrentHealth ~= false then
		if delta > 0 then
			humanoid.Health = math.min(targetMax, humanoid.Health + delta)
		else
			humanoid.Health = math.min(targetMax, humanoid.Health)
		end
	end

	return targetMax, delta
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
	purchaseLocks[player] = nil
end

return UpgradeService
