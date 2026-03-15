--------------------------------------------------------------------------------
-- UpgradeServiceInit.server.lua
-- Creates remotes and integrates UpgradeService into the game:
--   • Purchase handling
--   • State queries
--   • Wraps CurrencyService.AddCoins for Coin Mastery + Objective Specialist
--   • Wraps QuestService.IncrementQuest for Quest Mastery
--   • Wraps respawn timing for Rapid Recovery
--   • Player lifecycle (load, save, cleanup)
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Require modules
--------------------------------------------------------------------------------
local UpgradeService = require(ServerScriptService:WaitForChild("UpgradeService", 10))

local CurrencyService
pcall(function()
	CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)

local QuestService
pcall(function()
	QuestService = require(ServerScriptService:WaitForChild("QuestService", 10))
end)

local UpgradeConfig
pcall(function()
	UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig", 10))
end)

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

-- Upgrades sub-folder
local upgradeFolder = remotesFolder:FindFirstChild("Upgrades")
if not upgradeFolder then
	upgradeFolder = Instance.new("Folder")
	upgradeFolder.Name = "Upgrades"
	upgradeFolder.Parent = remotesFolder
end

-- RequestPurchaseUpgrade: client requests an upgrade purchase
local purchaseRF = Instance.new("RemoteFunction")
purchaseRF.Name = "RequestPurchaseUpgrade"
purchaseRF.Parent = upgradeFolder

-- GetUpgradeStates: client requests current upgrade levels
local getStatesRF = Instance.new("RemoteFunction")
getStatesRF.Name = "GetUpgradeStates"
getStatesRF.Parent = upgradeFolder

-- UpgradeStateUpdated: server pushes state changes to client
local stateUpdatedRE = Instance.new("RemoteEvent")
stateUpdatedRE.Name = "UpgradeStateUpdated"
stateUpdatedRE.Parent = remotesFolder

--------------------------------------------------------------------------------
-- Init UpgradeService
--------------------------------------------------------------------------------
UpgradeService:Init()

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------

purchaseRF.OnServerInvoke = function(player, upgradeId)
	if type(upgradeId) ~= "string" then return false, "Invalid" end
	return UpgradeService:PurchaseUpgrade(player, upgradeId)
end

getStatesRF.OnServerInvoke = function(player)
	return UpgradeService:GetAllLevels(player)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		UpgradeService:LoadForPlayer(player)
		-- Push initial state to client
		pcall(function()
			stateUpdatedRE:FireClient(player, UpgradeService:GetAllLevels(player))
		end)
	end)
end)

-- Handle players already present (Team Test / late join)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		UpgradeService:LoadForPlayer(player)
		pcall(function()
			stateUpdatedRE:FireClient(player, UpgradeService:GetAllLevels(player))
		end)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local ok, err = pcall(function()
		UpgradeService:SaveForPlayer(player)
	end)
	if not ok then
		warn("[UpgradeServiceInit] SaveForPlayer error for", player.Name, err)
	end
	UpgradeService:ClearPlayer(player)
end)

-- BindToClose: save all on shutdown
game:BindToClose(function()
	local ok, err = pcall(function()
		UpgradeService:SaveAll()
	end)
	if not ok then
		warn("[UpgradeServiceInit] SaveAll on shutdown failed:", tostring(err))
	end
end)

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap CurrencyService.AddCoins for Coin Mastery + Obj Specialist
--
-- The existing AddCoins is already wrapped by BoostServiceInit for timed boost
-- multipliers. We wrap on top of that so both systems apply.
--
-- AddCoins signature is extended to accept an optional 3rd param `source`:
--   CurrencyService:AddCoins(player, amount, source)
--     source: "elimination" | "quest" | "objective" | "purchase" | "admin" | nil
--   nil/missing source on positive amounts → treated as earnable (Coin Mastery)
--   "purchase" / "admin" → no upgrade multiplier
--   "objective" → Coin Mastery + Objective Specialist
--
-- Calculation order for positive earnable amounts:
--   base → Coin Mastery upgrade → Objective Specialist upgrade (if source) →
--   (BoostServiceInit's existing 2x coin boost) → final
--------------------------------------------------------------------------------
if CurrencyService then
	local _previousAddCoins = CurrencyService.AddCoins

	function CurrencyService:AddCoins(player, amount, source)
		amount = math.floor(tonumber(amount) or 0)

		if amount <= 0 then
			-- Deductions pass through unchanged
			return _previousAddCoins(self, player, amount, source)
		end

		-- Determine if this is an earnable reward
		source = source or "earn"
		local isEarnable = (source ~= "purchase" and source ~= "admin")

		local modified = amount

		if isEarnable then
			-- Apply Coin Mastery upgrade multiplier
			local coinMult = UpgradeService:GetCoinMultiplier(player)
			modified = modified * coinMult

			-- Apply Objective Specialist if this is an objective reward
			if source == "objective" then
				local objMult = UpgradeService:GetObjectiveCoinMultiplier(player)
				modified = modified * objMult
			end

			modified = math.floor(modified)
			if modified < 1 then modified = 1 end
		end

		-- Call the previous wrapper (which includes BoostServiceInit's boost multiplier)
		return _previousAddCoins(self, player, modified, source)
	end

	print("[UpgradeServiceInit] CurrencyService.AddCoins wrapped with upgrade multipliers")
end

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap QuestService.IncrementQuest for Quest Mastery
--
-- The existing IncrementQuest is already wrapped by BoostServiceInit for the
-- 2x Quest Progress timed boost. We wrap on top.
--
-- Calculation order:
--   base → Quest Mastery upgrade → (BoostServiceInit's 2x quest boost) → final
--------------------------------------------------------------------------------
if QuestService then
	local _previousIncrement = QuestService.IncrementQuest

	function QuestService:IncrementQuest(player, questId, amount)
		amount = tonumber(amount) or 1

		-- Apply Quest Mastery upgrade multiplier
		local questMult = UpgradeService:GetQuestProgressMultiplier(player)
		local modified = math.floor(amount * questMult)
		if modified < 1 then modified = 1 end

		_previousIncrement(self, player, questId, modified)
	end

	print("[UpgradeServiceInit] QuestService.IncrementQuest wrapped with upgrade multiplier")
end

--------------------------------------------------------------------------------
-- INTEGRATION: Expose UpgradeService globally for respawn time integration
-- TeamSpawn.server.lua uses _G.GetRespawnTime(player) to get the modified
-- respawn duration.
--------------------------------------------------------------------------------
local BASE_RESPAWN_TIME = 6 -- seconds (matches TeamSpawn's current wait(6))

_G.GetRespawnTime = function(player)
	if not player then return BASE_RESPAWN_TIME end
	local mult = UpgradeService:GetRespawnMultiplier(player)
	local modified = BASE_RESPAWN_TIME * mult
	return math.max(2, modified) -- minimum 2 seconds
end

-- Also expose UpgradeService via _G for other scripts that need it
_G.UpgradeService = UpgradeService

print("[UpgradeServiceInit] Upgrade system initialized")
