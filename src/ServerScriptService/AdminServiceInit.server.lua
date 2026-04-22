--------------------------------------------------------------------------------
-- AdminServiceInit.server.lua  –  Wires admin remotes to AdminService
--
-- Creates RemoteFunctions:
--   AdminSearchWeaponsRF  – search weapons by ID, owner userId, or username
--   AdminGrantWeaponRF    – grant a weapon to a target player
--
-- Both remotes verify the calling player is a whitelisted dev on every call.
-- Rate-limited to 1 request per second per player per remote.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local AdminService = require(script.Parent.AdminService)
local DevUserIds   = require(ReplicatedStorage.DevUserIds)

--------------------------------------------------------------------------------
-- CREATE REMOTES
--------------------------------------------------------------------------------
local function findOrCreate(className, name, parent)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA(className) then
        return existing
    end
    local obj = Instance.new(className)
    obj.Name = name
    obj.Parent = parent
    return obj
end

local searchRF  = findOrCreate("RemoteFunction", "AdminSearchWeaponsRF", ReplicatedStorage)
local grantRF   = findOrCreate("RemoteFunction", "AdminGrantWeaponRF", ReplicatedStorage)
local deleteRF  = findOrCreate("RemoteFunction", "AdminDeleteWeaponRF", ReplicatedStorage)

--------------------------------------------------------------------------------
-- RATE LIMITING
--------------------------------------------------------------------------------
local searchDebounce = {} -- [Player] = tick
local grantDebounce  = {} -- [Player] = tick
local deleteDebounce = {} -- [Player] = tick
local DEBOUNCE_TIME  = 1.0

local function checkDebounce(player, debounceTable)
    local now = tick()
    if debounceTable[player] and (now - debounceTable[player]) < DEBOUNCE_TIME then
        return false
    end
    debounceTable[player] = now
    return true
end

--------------------------------------------------------------------------------
-- SEARCH HANDLER
--------------------------------------------------------------------------------
searchRF.OnServerInvoke = function(player, searchType, searchValue)
    -- Rate limit
    if not checkDebounce(player, searchDebounce) then
        return { success = false, error = "Too many requests. Please wait." }
    end

    -- Server-side dev check (redundant with AdminService but defense-in-depth)
    if not DevUserIds.IsDev(player) then
        return { success = false, error = "Unauthorized" }
    end

    -- Sanitize inputs
    if type(searchType) ~= "string" then
        return { success = false, error = "Invalid search type" }
    end
    if type(searchValue) ~= "string" then
        return { success = false, error = "Invalid search value" }
    end

    -- Clamp search value length to prevent abuse
    if #searchValue > 100 then
        return { success = false, error = "Search value too long" }
    end

    local result = AdminService:SearchWeapons(player, searchType, searchValue)
    return result
end

--------------------------------------------------------------------------------
-- GRANT HANDLER
--------------------------------------------------------------------------------
grantRF.OnServerInvoke = function(player, targetUserId, weaponName, sizePercent, enchantName)
    -- Rate limit
    if not checkDebounce(player, grantDebounce) then
        return { success = false, error = "Too many requests. Please wait." }
    end

    -- Server-side dev check
    if not DevUserIds.IsDev(player) then
        return { success = false, error = "Unauthorized" }
    end

    -- Sanitize inputs
    if type(targetUserId) ~= "number" then
        targetUserId = tonumber(targetUserId)
        if not targetUserId then
            return { success = false, error = "Target UserId must be a number" }
        end
    end
    if type(weaponName) ~= "string" then
        return { success = false, error = "Weapon name must be a string" }
    end
    if type(sizePercent) ~= "number" then
        sizePercent = tonumber(sizePercent)
    end
    if type(enchantName) ~= "string" then
        enchantName = ""
    end

    -- Clamp string lengths
    if #weaponName > 50 then
        return { success = false, error = "Weapon name too long" }
    end
    if #enchantName > 50 then
        return { success = false, error = "Enchant name too long" }
    end

    local result = AdminService:GrantWeapon(player, targetUserId, weaponName, sizePercent, enchantName)
    return result
end

--------------------------------------------------------------------------------
-- DELETE HANDLER
--------------------------------------------------------------------------------
deleteRF.OnServerInvoke = function(player, ownerUserId, weaponId)
    -- Rate limit
    if not checkDebounce(player, deleteDebounce) then
        return { success = false, error = "Too many requests. Please wait." }
    end

    -- Server-side dev check
    if not DevUserIds.IsDev(player) then
        return { success = false, error = "Unauthorized" }
    end

    -- Sanitize inputs
    if type(ownerUserId) ~= "number" then
        ownerUserId = tonumber(ownerUserId)
        if not ownerUserId then
            return { success = false, error = "Owner UserId must be a number" }
        end
    end
    if type(weaponId) ~= "string" or #weaponId > 20 then
        return { success = false, error = "Invalid weapon ID" }
    end

    local result = AdminService:DeleteWeapon(player, ownerUserId, weaponId)
    return result
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    searchDebounce[player] = nil
    grantDebounce[player] = nil
    deleteDebounce[player] = nil
end)

print("[AdminServiceInit] Admin remotes ready.")
