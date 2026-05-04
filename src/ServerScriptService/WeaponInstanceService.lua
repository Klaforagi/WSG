--------------------------------------------------------------------------------
-- WeaponInstanceService.lua  –  Server-only unique weapon instance manager
--
-- Every weapon obtained from a crate gets a unique instanceId (WPN-XXXXXX).
-- Instances are persisted per-player in DataStore "WeaponInstances_v1".
--
-- Data shape per player:
--   { [instanceId] = { weaponName, rarity, category, source, obtainedAt } }
--------------------------------------------------------------------------------

local DataStoreService = game:GetService("DataStoreService")
local HttpService      = game:GetService("HttpService")
local Players          = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "WeaponInstances_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local WeaponInstanceService = {}
local _saveCoordinator

-- In-memory cache: [Player] = { [instanceId] = instanceData }
local playerInventories = {}

-- Set of all instanceIds currently in memory (collision guard)
local allIds = {}

--------------------------------------------------------------------------------
-- ID GENERATION  (WPN-XXXXXX, 6 hex chars = 16.7 M combos)
--------------------------------------------------------------------------------
local CHARSET = "0123456789ABCDEF"

local function generateId()
    for _ = 1, 50 do -- up to 50 attempts to avoid collision
        local parts = {}
        for _ = 1, 6 do
            local idx = math.random(1, #CHARSET)
            table.insert(parts, string.sub(CHARSET, idx, idx))
        end
        local id = "WPN-" .. table.concat(parts)
        if not allIds[id] then
            return id
        end
    end
    -- Fallback: use GUID suffix for guaranteed uniqueness
    local guid = string.gsub(HttpService:GenerateGUID(false), "-", "")
    return "WPN-" .. string.sub(guid, 1, 8)
end

--------------------------------------------------------------------------------
-- DATASTORE HELPERS
--------------------------------------------------------------------------------
local function dsKey(player)
    return "WpnInv_" .. tostring(player.UserId)
end

local function getSaveCoordinator()
    if _saveCoordinator == nil then
        local ok, coordinator = pcall(function()
            return require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
        end)
        if ok then
            _saveCoordinator = coordinator
        else
            _saveCoordinator = false
        end
    end
    if _saveCoordinator == false then
        return nil
    end
    return _saveCoordinator
end

local function clearInventoryIds(inventory)
    if type(inventory) ~= "table" then return end
    for id in pairs(inventory) do
        allIds[id] = nil
    end
end

local function registerInventoryIds(inventory)
    if type(inventory) ~= "table" then return end
    for id in pairs(inventory) do
        allIds[id] = true
    end
end

local function setInventory(player, inventory)
    clearInventoryIds(playerInventories[player])
    playerInventories[player] = inventory or {}
    registerInventoryIds(playerInventories[player])
end

local function markDirty(player, reason)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "WeaponInventory", reason or "weapon_inventory")
    end
end

function WeaponInstanceService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = {},
            reason = "missing player",
        }
    end
    local key = dsKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "WeaponInventory/" .. key)

    local inv = {}
    if success and type(result) == "table" then
        inv = result
    end

    setInventory(player, inv)
    if not success then
        warn("[WeaponInstanceService] Failed to load for " .. tostring(player.Name) .. "; using temporary empty inventory")
        return {
            status = "failed",
            data = inv,
            reason = err,
        }
    end
    if result == nil then
        return {
            status = "new",
            data = inv,
        }
    end
    return {
        status = "existing",
        data = inv,
    }
end

function WeaponInstanceService:LoadForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    return result and result.data or {}
end

function WeaponInstanceService:GetSaveData(player)
    if not player then return nil end
    return DataStoreOps.DeepCopy(playerInventories[player] or {})
end

function WeaponInstanceService:SaveProfileForPlayer(player, inv, oldInventory)
    if not player then return false, "missing player" end
    inv = DataStoreOps.DeepCopy(inv or playerInventories[player] or {})
    oldInventory = oldInventory or {}

    local key = dsKey(player)
    local success, _, err = DataStoreOps.Update(ds, key, "WeaponInventory/" .. key, function(storedInventory)
        local storedCount = DataStoreOps.CountEntries(storedInventory)
        local previousCount = DataStoreOps.CountEntries(oldInventory)
        local newCount = DataStoreOps.CountEntries(inv)
        if storedCount > 0 and previousCount > 0 and newCount == 0 then
            warn("[WeaponInstanceService] suspected wipe blocked for " .. tostring(player.Name))
            return storedInventory
        end
        return inv
    end)
    if success then
        return true
    end
    warn("[WeaponInstanceService] Failed to save for " .. tostring(player.Name))
    return false, err
end

function WeaponInstanceService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

function WeaponInstanceService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        self:SaveForPlayer(player)
    end
end

function WeaponInstanceService:RemovePlayer(player)
    clearInventoryIds(playerInventories[player])
    playerInventories[player] = nil
end

--------------------------------------------------------------------------------
-- INSTANCE MANAGEMENT
--------------------------------------------------------------------------------

--- Create a new weapon instance for a player. Returns the instance data table.
--- sizePercent and sizeTier are optional; if omitted, defaults to 100% / "Normal".
--- enchantName is optional; if omitted, defaults to "" (no enchant).
function WeaponInstanceService:CreateInstance(player, weaponName, rarity, category, source, sizePercent, sizeTier, enchantName)
    if not player then return nil end
    local inv = playerInventories[player]
    if not inv then
        inv = {}
        playerInventories[player] = inv
    end

    local id = generateId()
    allIds[id] = true

    local instanceData = {
        instanceId  = id,
        weaponName  = weaponName,
        rarity      = rarity or "Common",
        category    = category or "Melee",
        source      = source or "Crate",
        obtainedAt  = os.time(),
        sizePercent = sizePercent or 100,   -- SIZE ROLL SYSTEM (80–200)
        sizeTier    = sizeTier or "Normal", -- SIZE ROLL SYSTEM
        enchantName    = (type(enchantName) == "string" and enchantName) or "", -- ENCHANT SYSTEM
    }

    inv[id] = instanceData
    markDirty(player, "weapon_created")
    return instanceData
end

--- Get a player's full weapon inventory (table of instanceData keyed by id).
function WeaponInstanceService:GetInventory(player)
    return playerInventories[player] or {}
end

--- Get a single instance by id.
function WeaponInstanceService:GetInstance(player, instanceId)
    local inv = playerInventories[player]
    if not inv then return nil end
    return inv[instanceId]
end

--- Remove an instance (e.g. trading, destroying). Returns true if removed.
function WeaponInstanceService:RemoveInstance(player, instanceId)
    local inv = playerInventories[player]
    if not inv or not inv[instanceId] then return false end
    inv[instanceId] = nil
    allIds[instanceId] = nil
    markDirty(player, "weapon_removed")
    return true
end

--- Count how many of a specific weapon a player owns.
function WeaponInstanceService:CountWeapon(player, weaponName)
    local inv = playerInventories[player]
    if not inv then return 0 end
    local count = 0
    for _, data in pairs(inv) do
        if data.weaponName == weaponName then
            count = count + 1
        end
    end
    return count
end

--- Get all instances of a given category ("Melee" / "Ranged").
function WeaponInstanceService:GetByCategory(player, category)
    local inv = playerInventories[player]
    if not inv then return {} end
    local results = {}
    for id, data in pairs(inv) do
        if data.category == category then
            results[id] = data
        end
    end
    return results
end

--- Toggle or set the favorited flag on a weapon instance. Returns the new state.
function WeaponInstanceService:SetFavorite(player, instanceId, state)
    local inv = playerInventories[player]
    if not inv or not inv[instanceId] then return false end
    inv[instanceId].favorited = (state == true)
    markDirty(player, "weapon_favorited")
    return inv[instanceId].favorited
end

return WeaponInstanceService
