--------------------------------------------------------------------------------
-- WeaponRegistryService.lua  –  Global weapon registry + owner index
--
-- Provides cross-player weapon lookup for admin search.
--   - Global registry: WeaponId -> weapon record (DataStore "WeaponRegistry_v1")
--   - Owner index:     UserId  -> { WeaponId, ... } (DataStore "OwnerIndex_v1")
--
-- Used by AdminService for:
--   SearchWeaponById(weaponId)
--   SearchWeaponsByOwnerUserId(userId)
--   SearchWeaponsByUsername(username)  (username -> userId lookup first)
--
-- Records are written when a weapon is granted via admin. Crate-opened weapons
-- are NOT indexed here (to avoid retroactive migration). Only admin-granted
-- weapons are indexed in the global registry.
--
-- To search crate-opened weapons for an ONLINE player, AdminService falls back
-- to WeaponInstanceService:GetInventory() directly.
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

local REGISTRY_DS_NAME = "WeaponRegistry_v1"
local OWNER_IDX_NAME   = "OwnerIndex_v1"
local RETRIES          = 3
local RETRY_DELAY      = 0.5

local registryDs = DataStoreService:GetDataStore(REGISTRY_DS_NAME)
local ownerIdxDs = DataStoreService:GetDataStore(OWNER_IDX_NAME)

local WeaponRegistryService = {}

--------------------------------------------------------------------------------
-- DATASTORE HELPERS
--------------------------------------------------------------------------------
local function retryGet(ds, key)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then return true, result end
        warn("[WeaponRegistryService] GetAsync failed (" .. key .. ", attempt " .. i .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    return false, result
end

local function retrySet(ds, key, value)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, value)
        end)
        if success then return true end
        warn("[WeaponRegistryService] SetAsync failed (" .. key .. ", attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    return false, err
end

local function retryUpdate(ds, key, transformFunc)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:UpdateAsync(key, transformFunc)
        end)
        if success then return true end
        warn("[WeaponRegistryService] UpdateAsync failed (" .. key .. ", attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    return false, err
end

--------------------------------------------------------------------------------
-- REGISTER WEAPON
-- Called after a weapon is admin-granted. Writes to both registry + owner index.
--------------------------------------------------------------------------------
function WeaponRegistryService:RegisterWeapon(record)
    if not record or not record.WeaponId then
        return false, "Invalid record"
    end

    -- 1. Write global registry entry (keyed by WeaponId)
    local ok1, err1 = retrySet(registryDs, record.WeaponId, record)
    if not ok1 then
        return false, "Failed to write registry: " .. tostring(err1)
    end

    -- 2. Append WeaponId to owner index list
    local ownerKey = "Owner_" .. tostring(record.OwnerUserId)
    local ok2, err2 = retryUpdate(ownerIdxDs, ownerKey, function(old)
        local list = old or {}
        table.insert(list, record.WeaponId)
        return list
    end)
    if not ok2 then
        warn("[WeaponRegistryService] Owner index update failed: " .. tostring(err2))
        -- Registry entry was written; owner index is best-effort
    end

    return true
end

--------------------------------------------------------------------------------
-- SEARCH BY WEAPON ID
-- Returns a single weapon record or nil.
--------------------------------------------------------------------------------
function WeaponRegistryService:SearchWeaponById(weaponId)
    if type(weaponId) ~= "string" or weaponId == "" then
        return nil, "Invalid weaponId"
    end

    -- 1. Try global registry (admin-granted weapons)
    local ok, record = retryGet(registryDs, weaponId)
    if ok and record then
        return record
    end

    -- 2. Fallback: search online players' inventories
    local WeaponInstanceService = require(script.Parent.WeaponInstanceService)
    for _, player in ipairs(Players:GetPlayers()) do
        local inst = WeaponInstanceService:GetInstance(player, weaponId)
        if inst then
            return {
                WeaponId        = inst.instanceId,
                OwnerUserId     = player.UserId,
                OwnerUsername    = player.Name,
                WeaponName      = inst.weaponName,
                SizePercent     = inst.sizePercent or 100,
                Enchant         = inst.enchantName or "",
                Rarity          = inst.rarity or "Common",
                ObtainedAt      = inst.obtainedAt or 0,
                ObtainedMethod  = inst.source or "Unknown",
                GrantedByUserId = inst.grantedByUserId,
                GrantedByUsername = inst.grantedByUsername,
                LastUpdatedAt   = inst.lastUpdatedAt or inst.obtainedAt or 0,
            }
        end
    end

    return nil, "Weapon not found"
end

--------------------------------------------------------------------------------
-- SEARCH BY OWNER USERID
-- Returns a list of weapon records for a given owner.
--------------------------------------------------------------------------------
function WeaponRegistryService:SearchWeaponsByOwnerUserId(userId)
    if type(userId) ~= "number" then
        return {}, "Invalid userId"
    end

    local results = {}

    -- 1. Check if player is online -> use live inventory
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local WeaponInstanceService = require(script.Parent.WeaponInstanceService)
        local inv = WeaponInstanceService:GetInventory(player)
        for _, inst in pairs(inv) do
            table.insert(results, {
                WeaponId        = inst.instanceId,
                OwnerUserId     = player.UserId,
                OwnerUsername    = player.Name,
                WeaponName      = inst.weaponName,
                SizePercent     = inst.sizePercent or 100,
                Enchant         = inst.enchantName or "",
                Rarity          = inst.rarity or "Common",
                ObtainedAt      = inst.obtainedAt or 0,
                ObtainedMethod  = inst.source or "Unknown",
                GrantedByUserId = inst.grantedByUserId,
                GrantedByUsername = inst.grantedByUsername,
                LastUpdatedAt   = inst.lastUpdatedAt or inst.obtainedAt or 0,
            })
        end
        return results
    end

    -- 2. Offline: look up owner index -> fetch each weapon from registry
    local ownerKey = "Owner_" .. tostring(userId)
    local ok, weaponIds = retryGet(ownerIdxDs, ownerKey)
    if ok and type(weaponIds) == "table" then
        for _, wid in ipairs(weaponIds) do
            local ok2, record = retryGet(registryDs, wid)
            if ok2 and record then
                table.insert(results, record)
            end
        end
    end

    -- 3. Also load the player's DataStore inventory directly for crate weapons
    local dsName = "WeaponInstances_v1"
    local ds = DataStoreService:GetDataStore(dsName)
    local dsKey = "WpnInv_" .. tostring(userId)
    local okDs, rawInv = retryGet(ds, dsKey)
    if okDs and type(rawInv) == "table" then
        -- Deduplicate: skip IDs already in results
        local seen = {}
        for _, r in ipairs(results) do
            seen[r.WeaponId] = true
        end

        -- We need the username for display
        local username = "[Offline]"
        local nameOk, nameResult = pcall(function()
            return Players:GetNameFromUserIdAsync(userId)
        end)
        if nameOk and nameResult then
            username = nameResult
        end

        for id, inst in pairs(rawInv) do
            if not seen[id] then
                table.insert(results, {
                    WeaponId        = inst.instanceId or id,
                    OwnerUserId     = userId,
                    OwnerUsername    = username,
                    WeaponName      = inst.weaponName,
                    SizePercent     = inst.sizePercent or 100,
                    Enchant         = inst.enchantName or "",
                    Rarity          = inst.rarity or "Common",
                    ObtainedAt      = inst.obtainedAt or 0,
                    ObtainedMethod  = inst.source or "Unknown",
                    GrantedByUserId = inst.grantedByUserId,
                    GrantedByUsername = inst.grantedByUsername,
                    LastUpdatedAt   = inst.lastUpdatedAt or inst.obtainedAt or 0,
                })
            end
        end
    end

    return results
end

--------------------------------------------------------------------------------
-- SEARCH BY USERNAME
-- Resolves username -> userId, then delegates to SearchWeaponsByOwnerUserId.
--------------------------------------------------------------------------------
function WeaponRegistryService:SearchWeaponsByUsername(username)
    if type(username) ~= "string" or username == "" then
        return {}, "Invalid username"
    end

    local ok, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if not ok or not userId then
        return {}, "Username not found: " .. tostring(username)
    end

    return self:SearchWeaponsByOwnerUserId(userId)
end

return WeaponRegistryService
