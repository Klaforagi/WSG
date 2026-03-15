--------------------------------------------------------------------------------
-- UpgradeService.lua  –  Server-authoritative upgrade management
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player upgrade levels in memory, persists to DataStore,
-- and provides query APIs for gameplay integration.
--
-- Public API (used by UpgradeServiceInit.server.lua):
--   UpgradeService:Init()
--   UpgradeService:LoadForPlayer(player)  -> table
--   UpgradeService:SaveForPlayer(player)  -> bool
--   UpgradeService:SaveAll()
--   UpgradeService:PurchaseUpgrade(player, upgradeId)  -> bool, string
--   UpgradeService:GetLevel(player, upgradeId)  -> number
--   UpgradeService:GetAllLevels(player)  -> { [upgradeId] = level }
--   UpgradeService:GetCoinMultiplier(player)  -> number (1 + bonus)
--   UpgradeService:GetQuestProgressMultiplier(player)  -> number (1 + bonus)
--   UpgradeService:GetRespawnMultiplier(player)  -> number (1 - reduction)
--   UpgradeService:GetObjectiveCoinMultiplier(player)  -> number (1 + bonus)
--   UpgradeService:ClearPlayer(player)
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DATASTORE_NAME = "Upgrades_v1"
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
-- Per-player state: playerUpgrades[player] = { [upgradeId] = level }
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

	-- Validate levels against config
	local config = getUpgradeConfig()
	local validated = {}
	if config then
		for _, def in ipairs(config.Upgrades) do
			local stored = data[def.Id]
			if type(stored) == "number" and stored >= 0 and stored <= def.MaxLevel then
				validated[def.Id] = math.floor(stored)
			else
				validated[def.Id] = 0
			end
		end
	end

	playerUpgrades[player] = validated
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

	local def = config.GetById(upgradeId)
	if not def then return false, "Unknown upgrade" end

	local levels = playerUpgrades[player]
	if not levels then return false, "Player data not loaded" end

	local currentLevel = levels[upgradeId] or 0
	if currentLevel >= def.MaxLevel then
		return false, "Already maxed"
	end

	local price = def.LevelPrices[currentLevel + 1]
	if not price then return false, "Price not found" end

	local cs = getCurrencyService()
	if not cs then return false, "Currency system unavailable" end

	local balance = cs:GetCoins(player)
	if balance < price then
		return false, "Insufficient coins"
	end

	-- Deduct coins (pass "purchase" source to prevent upgrade multiplier from applying)
	cs:AddCoins(player, -price, "purchase")

	-- Increase level
	levels[upgradeId] = currentLevel + 1
	print(("[UpgradeService] %s upgraded '%s' to level %d"):format(
		player.Name, upgradeId, levels[upgradeId]))

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
	-- Return a copy
	local copy = {}
	for k, v in pairs(levels) do
		copy[k] = v
	end
	return copy
end

--- Returns the multiplier for earnable coin rewards (1 + bonus).
--- e.g. level 3 at 5% per level = 1.15
function UpgradeService:GetCoinMultiplier(player)
	local level = self:GetLevel(player, "coin_mastery")
	local config = getUpgradeConfig()
	if not config then return 1 end
	return 1 + config.GetEffect("coin_mastery", level)
end

--- Returns the multiplier for quest progress (1 + bonus).
function UpgradeService:GetQuestProgressMultiplier(player)
	local level = self:GetLevel(player, "quest_mastery")
	local config = getUpgradeConfig()
	if not config then return 1 end
	return 1 + config.GetEffect("quest_mastery", level)
end

--- Returns the multiplier for respawn time (1 - reduction).
--- e.g. level 3 at 5% per level = 0.85
function UpgradeService:GetRespawnMultiplier(player)
	local level = self:GetLevel(player, "rapid_recovery")
	local config = getUpgradeConfig()
	if not config then return 1 end
	return math.max(0.5, 1 - config.GetEffect("rapid_recovery", level))
end

--- Returns the multiplier for objective coin rewards (1 + bonus).
function UpgradeService:GetObjectiveCoinMultiplier(player)
	local level = self:GetLevel(player, "objective_specialist")
	local config = getUpgradeConfig()
	if not config then return 1 end
	return 1 + config.GetEffect("objective_specialist", level)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function UpgradeService:ClearPlayer(player)
	playerUpgrades[player] = nil
end

return UpgradeService
