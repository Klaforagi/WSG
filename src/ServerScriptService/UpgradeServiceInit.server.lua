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
		print(("[UpgradeServiceInit] Purchase success: %s → '%s' now level %d"):format(
			player.Name, upgradeId, UpgradeService:GetLevel(player, upgradeId)))
	else
		print(("[UpgradeServiceInit] Purchase denied: %s → '%s' reason: %s"):format(
			player.Name, upgradeId, tostring(msg)))
	end
	return ok, msg
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
-- INTEGRATION: Expose weapon damage multipliers via _G
-- ToolGunSetup and ToolMeleeSetup read these to apply the upgrade bonus.
--------------------------------------------------------------------------------
_G.UpgradeService = UpgradeService

--- Convenience helpers for weapon scripts
_G.GetMeleeDamageMultiplier = function(player)
	if not player then return 1 end
	return UpgradeService:GetMeleeMultiplier(player)
end

_G.GetRangedDamageMultiplier = function(player)
	if not player then return 1 end
	return UpgradeService:GetRangedMultiplier(player)
end

print("[UpgradeServiceInit] Weapon upgrade system initialized")
