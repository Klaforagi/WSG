--------------------------------------------------------------------------------
-- CrateServiceInit.server.lua
-- Wires up remotes for the crate / weapon-instance system and handles
-- player join/leave lifecycle (load & save weapon inventories).
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require server modules
local CrateService          = require(ServerScriptService:WaitForChild("CrateService"))
local WeaponInstanceService = require(ServerScriptService:WaitForChild("WeaponInstanceService"))
local AchievementService
pcall(function()
    AchievementService = require(ServerScriptService:WaitForChild("AchievementService", 10))
end)

--------------------------------------------------------------------------------
-- REMOTE CREATION
--------------------------------------------------------------------------------
local function getOrCreateRF(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then return existing end
    if existing then existing:Destroy() end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = ReplicatedStorage
    return rf
end

local function getOrCreateRE(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then return existing end
    if existing then existing:Destroy() end
    local re = Instance.new("RemoteEvent")
    re.Name = name
    re.Parent = ReplicatedStorage
    return re
end

local openCrateRF        = getOrCreateRF("OpenCrate")
local getWeaponInvRF     = getOrCreateRF("GetWeaponInventory")
local favoriteWeaponRF   = getOrCreateRF("FavoriteWeapon")
local discardWeaponRF    = getOrCreateRF("DiscardWeapon")
local keepCrateRewardRF  = getOrCreateRF("KeepCrateReward")
local salvageCrateRewardRF = getOrCreateRF("SalvageCrateReward")
local weaponInvUpdatedRE = getOrCreateRE("WeaponInventoryUpdated")

--------------------------------------------------------------------------------
-- DEBOUNCE  (per-player open crate cooldown)
--------------------------------------------------------------------------------
local openDebounce = {} -- [Player] = tick

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

-- OpenCrate: client requests to open a crate
-- Returns: success (bool), resultData (table or string)
openCrateRF.OnServerInvoke = function(player, crateId)
    -- Anti-spam: 1-second cooldown
    local now = tick()
    if openDebounce[player] and (now - openDebounce[player]) < 1 then
        return false, "Too fast"
    end
    openDebounce[player] = now

    local success, result = CrateService:OpenCrate(player, crateId)

    if success then
        -- Track purchase for achievements (currency was deducted)
        if AchievementService then
            pcall(function() AchievementService:IncrementStat(player, "totalPurchases", 1) end)
        end
        -- NOTE: Do NOT fire WeaponInventoryUpdated here.
        -- Weapon is pending — client will see Keep/Salvage popup.
    end

    return success, result
end

-- GetWeaponInventory: client requests their full weapon inventory
getWeaponInvRF.OnServerInvoke = function(player)
    return WeaponInstanceService:GetInventory(player)
end

-- FavoriteWeapon: client toggles the favorite flag on a weapon instance
favoriteWeaponRF.OnServerInvoke = function(player, instanceId)
    if type(instanceId) ~= "string" then return false end
    local inst = WeaponInstanceService:GetInstance(player, instanceId)
    if not inst then return false end
    local newState = not (inst.favorited == true)
    WeaponInstanceService:SetFavorite(player, instanceId, newState)
    WeaponInstanceService:SaveForPlayer(player)
    return newState
end

-- DiscardWeapon: client requests to delete a weapon instance
discardWeaponRF.OnServerInvoke = function(player, instanceId)
    if type(instanceId) ~= "string" then return false, "Invalid ID" end
    local inst = WeaponInstanceService:GetInstance(player, instanceId)
    if not inst then return false, "Weapon not found" end
    -- Prevent discarding starter weapons
    if inst.source == "Starter" then return false, "Cannot discard starter weapons" end
    WeaponInstanceService:RemoveInstance(player, instanceId)
    WeaponInstanceService:SaveForPlayer(player)
    -- Notify client of inventory change
    pcall(function()
        weaponInvUpdatedRE:FireClient(player, WeaponInstanceService:GetInventory(player))
    end)
    return true, "Discarded"
end

--------------------------------------------------------------------------------
-- CRATE REWARD DECISION REMOTES (Keep / Salvage)
--------------------------------------------------------------------------------
local keepDebounce = {}   -- [Player] = tick
local salvageDebounce = {} -- [Player] = tick

-- KeepCrateReward: player chose to keep the pending crate reward
keepCrateRewardRF.OnServerInvoke = function(player)
    -- Anti-spam debounce
    local now = tick()
    if keepDebounce[player] and (now - keepDebounce[player]) < 1 then
        return false, "Too fast"
    end
    keepDebounce[player] = now

    print("[CrateReward] Keep selected for " .. tostring(player.Name))

    local success, result = CrateService:FinalizeCrateKeep(player)
    if success then
        -- Save inventory and notify client
        WeaponInstanceService:SaveForPlayer(player)
        pcall(function()
            weaponInvUpdatedRE:FireClient(player, WeaponInstanceService:GetInventory(player))
        end)
    end
    return success, result
end

-- SalvageCrateReward: player chose to salvage the pending crate reward
salvageCrateRewardRF.OnServerInvoke = function(player)
    -- Anti-spam debounce
    local now = tick()
    if salvageDebounce[player] and (now - salvageDebounce[player]) < 1 then
        return false, "Too fast"
    end
    salvageDebounce[player] = now

    -- Server re-validates pending reward exists and rarity
    local pending = CrateService:GetPendingReward(player)
    if not pending then
        return false, "No pending reward"
    end

    print("[CrateReward] Salvage selected for " .. tostring(player.Name))

    local success, result = CrateService:FinalizeCrateSalvage(player)
    if success then
        -- Fire salvage currency update to client
        pcall(function()
            local salvageUpdated = ReplicatedStorage:FindFirstChild("SalvageUpdated")
            if salvageUpdated and salvageUpdated:IsA("RemoteEvent") then
                salvageUpdated:FireClient(player, result.newBalance)
            end
        end)
    end
    return success, result
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    WeaponInstanceService:LoadForPlayer(player)

    -- Grant starter weapon instances if player doesn't already have them
    local STARTERS = {
        { weaponName = "Starter Sword",      category = "Melee"  },
        { weaponName = "Starter Slingshot",   category = "Ranged" },
    }
    for _, starter in ipairs(STARTERS) do
        if WeaponInstanceService:CountWeapon(player, starter.weaponName) == 0 then
            WeaponInstanceService:CreateInstance(
                player,
                starter.weaponName,
                "Common",
                starter.category,
                "Starter"
            )
        end
    end
    WeaponInstanceService:SaveForPlayer(player)

    -- Send initial inventory to client
    pcall(function()
        weaponInvUpdatedRE:FireClient(player, WeaponInstanceService:GetInventory(player))
    end)
end

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

local function onPlayerRemoving(player)
    -- Auto-keep any pending crate reward before saving
    CrateService:AutoKeepOnDisconnect(player)

    if SaveGuard:ClaimSave(player, "WeaponInstance") then
        WeaponInstanceService:SaveForPlayer(player)
        SaveGuard:ReleaseSave(player, "WeaponInstance")
    end
    WeaponInstanceService:RemovePlayer(player)
    openDebounce[player] = nil
    keepDebounce[player] = nil
    salvageDebounce[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players who joined before this script ran
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

-- Save all on shutdown
game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            -- Auto-keep any pending crate reward before shutdown save
            CrateService:AutoKeepOnDisconnect(p)
            if SaveGuard:ClaimSave(p, "WeaponInstance") then
                WeaponInstanceService:SaveForPlayer(p)
                SaveGuard:ReleaseSave(p, "WeaponInstance")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
end)

print("[CrateServiceInit] Crate system ready")
