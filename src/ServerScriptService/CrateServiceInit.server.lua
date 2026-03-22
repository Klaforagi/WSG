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
        -- Notify client of inventory change
        pcall(function()
            weaponInvUpdatedRE:FireClient(player, WeaponInstanceService:GetInventory(player))
        end)
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

local function onPlayerRemoving(player)
    WeaponInstanceService:SaveForPlayer(player)
    WeaponInstanceService:RemovePlayer(player)
    openDebounce[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players who joined before this script ran
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

-- Save all on shutdown
game:BindToClose(function()
    WeaponInstanceService:SaveAll()
end)

print("[CrateServiceInit] Crate system ready")
