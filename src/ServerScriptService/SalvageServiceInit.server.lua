--------------------------------------------------------------------------------
-- SalvageServiceInit.server.lua
-- Wires up the SalvageWeapon RemoteFunction and handles per-player debounce.
-- Also exposes GetSalvageValue so the client can preview values before confirm.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require server modules
local SalvageService        = require(ServerScriptService:WaitForChild("SalvageService"))
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

local salvageWeaponRF   = getOrCreateRF("SalvageWeapon")
local getSalvageValueRF = getOrCreateRF("GetSalvageValue")

-- Re-use the WeaponInventoryUpdated event to notify the client of inventory changes
local weaponInvUpdatedRE = ReplicatedStorage:FindFirstChild("WeaponInventoryUpdated")
if not weaponInvUpdatedRE then
    weaponInvUpdatedRE = getOrCreateRE("WeaponInventoryUpdated")
end

--------------------------------------------------------------------------------
-- DEBOUNCE  (per-player salvage cooldown to prevent double-click duping)
--------------------------------------------------------------------------------
local salvageDebounce = {} -- [Player] = tick

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

-- SalvageWeapon: client requests to salvage a specific weapon instance
-- Args: instanceId (string)
-- Returns: success (bool), resultData (table)
salvageWeaponRF.OnServerInvoke = function(player, instanceId)
    -- Type validation
    if type(instanceId) ~= "string" then
        return false, { reason = "Invalid instance ID" }
    end

    -- Anti-spam: 0.5-second cooldown per player
    local now = tick()
    if salvageDebounce[player] and (now - salvageDebounce[player]) < 0.5 then
        return false, { reason = "Too fast" }
    end
    salvageDebounce[player] = now

    print("[SalvageServiceInit] Salvage request from", player.Name, "for", instanceId)

    local success, result = SalvageService:SalvageItem(player, instanceId)

    if success then
        -- Notify client of inventory change (same pattern as crate/discard)
        pcall(function()
            weaponInvUpdatedRE:FireClient(player, WeaponInstanceService:GetInventory(player))
        end)
    end

    return success, result
end

-- GetSalvageValue: client queries the salvage value for a specific item
-- Used by UI to display "Salvage for X ⚙" before confirming
getSalvageValueRF.OnServerInvoke = function(player, instanceId)
    if type(instanceId) ~= "string" then return nil end
    return SalvageService:GetSalvageValueById(player, instanceId)
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    salvageDebounce[player] = nil
end)

print("[SalvageServiceInit] Salvage system ready")
