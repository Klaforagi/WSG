--------------------------------------------------------------------------------
-- UpgradeServiceInit.server.lua
-- Creates remotes and integrates UpgradeService into the game:
--   • Purchase handling (melee_weapon / ranged_weapon)
--   • State queries
--   • Exposes damage multiplier functions via _G for weapon scripts
--   • Player lifecycle (load, save, cleanup)
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Require modules
--------------------------------------------------------------------------------
local UpgradeService = require(ServerScriptService:WaitForChild("UpgradeService", 10))

--------------------------------------------------------------------------------
-- AchievementService (lazy-loaded to avoid require-order issues)
--------------------------------------------------------------------------------
local AchievementService
local function getAchievementService()
	if AchievementService then return AchievementService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("AchievementService")
		if mod and mod:IsA("ModuleScript") then
			AchievementService = require(mod)
		end
	end)
	return AchievementService
end

--- Sync a player's current upgrade levels to AchievementService as stats.
--- Uses SetStat so the achievement only advances when the level is a new high.
local function syncUpgradeLevelAchievements(player)
	local achSvc = getAchievementService()
	if not achSvc then return end
	local levels = UpgradeService:GetAllLevels(player)
	if not levels then return end
	if levels.melee_weapon then
		achSvc:SetStat(player, "meleeUpgradeLevel", levels.melee_weapon)
	end
	if levels.ranged_weapon then
		achSvc:SetStat(player, "rangedUpgradeLevel", levels.ranged_weapon)
	end
end

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
	print(("[UpgradeServiceInit] Purchase request from %s for '%s'"):format(player.Name, upgradeId))
	local ok, msg = UpgradeService:PurchaseUpgrade(player, upgradeId)
	if ok then
		local newLevel = UpgradeService:GetLevel(player, upgradeId)
		print(("[UpgradeServiceInit] Purchase success: %s → '%s' now level %d"):format(
			player.Name, upgradeId, newLevel))
		-- Track upgrade level for achievements
		task.spawn(function()
			syncUpgradeLevelAchievements(player)
		end)
	else
		print(("[UpgradeServiceInit] Purchase denied: %s → '%s' reason: %s"):format(
			player.Name, upgradeId, tostring(msg)))
	end
	return ok, msg
end

getStatesRF.OnServerInvoke = function(player)
	local levels = UpgradeService:GetAllLevels(player)
	levels._playerLevel = UpgradeService:GetPlayerLevel(player)
	return levels
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		UpgradeService:LoadForPlayer(player)
		-- Wait for XPService to set the Level attribute so we send the
		-- correct player level to the client and purchase validation works.
		local waited = 0
		while not player:GetAttribute("Level") and waited < 10 and player.Parent do
			task.wait(0.2)
			waited = waited + 0.2
		end
		local state = UpgradeService:GetAllLevels(player)
		state._playerLevel = UpgradeService:GetPlayerLevel(player)
		pcall(function()
			stateUpdatedRE:FireClient(player, state)
		end)
		-- Sync existing upgrade levels to achievement system on join
		task.wait(1) -- let AchievementService load first
		syncUpgradeLevelAchievements(player)
	end)
end)

-- Handle players already present (Team Test / late join)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		UpgradeService:LoadForPlayer(player)
		-- Wait for XPService to set the Level attribute
		local waited = 0
		while not player:GetAttribute("Level") and waited < 10 and player.Parent do
			task.wait(0.2)
			waited = waited + 0.2
		end
		local state = UpgradeService:GetAllLevels(player)
		state._playerLevel = UpgradeService:GetPlayerLevel(player)
		pcall(function()
			stateUpdatedRE:FireClient(player, state)
		end)
		task.wait(1)
		syncUpgradeLevelAchievements(player)
	end)
end

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

Players.PlayerRemoving:Connect(function(player)
	if SaveGuard:ClaimSave(player, "Upgrade") then
		local ok, err = pcall(function()
			UpgradeService:SaveForPlayer(player)
		end)
		if not ok then
			warn("[UpgradeServiceInit] SaveForPlayer error for", player.Name, err)
		end
		SaveGuard:ReleaseSave(player, "Upgrade")
	end
	UpgradeService:ClearPlayer(player)
end)

-- BindToClose: save all on shutdown
game:BindToClose(function()
	SaveGuard:BeginShutdown()
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			if SaveGuard:ClaimSave(p, "Upgrade") then
				local ok, err = pcall(function()
					UpgradeService:SaveForPlayer(p)
				end)
				if not ok then
					warn("[UpgradeServiceInit] SaveAll shutdown error for", p.Name, err)
				end
				SaveGuard:ReleaseSave(p, "Upgrade")
			end
		end)
	end
	SaveGuard:WaitForAll(5)
end)

--------------------------------------------------------------------------------
-- INTEGRATION: Expose weapon damage multipliers via _G
-- ToolGunSetup and ToolMeleeSetup read these to apply the upgrade bonus.
-- Each function accepts an optional isPvP flag to return the capped PvP
-- multiplier or the uncapped PvE multiplier.
--------------------------------------------------------------------------------
_G.UpgradeService = UpgradeService

--- Melee damage multiplier (isPvP = true → capped, false/nil → uncapped PvE)
_G.GetMeleeDamageMultiplier = function(player, isPvP)
	if not player then return 1 end
	if isPvP then
		return UpgradeService:GetMeleePvPMultiplier(player)
	end
	return UpgradeService:GetMeleePvEMultiplier(player)
end

--- Ranged damage multiplier (isPvP = true → capped, false/nil → uncapped PvE)
_G.GetRangedDamageMultiplier = function(player, isPvP)
	if not player then return 1 end
	if isPvP then
		return UpgradeService:GetRangedPvPMultiplier(player)
	end
	return UpgradeService:GetRangedPvEMultiplier(player)
end

print("[UpgradeServiceInit] Weapon upgrade system initialized")
