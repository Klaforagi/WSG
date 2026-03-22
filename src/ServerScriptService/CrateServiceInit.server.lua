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

local openCrateRF       = getOrCreateRF("OpenCrate")
local getWeaponInvRF    = getOrCreateRF("GetWeaponInventory")
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

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    WeaponInstanceService:LoadForPlayer(player)
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
