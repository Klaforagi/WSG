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

local DATASTORE_NAME = "WeaponInstances_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local WeaponInstanceService = {}

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

function WeaponInstanceService:LoadForPlayer(player)
    if not player then return {} end
    local key = dsKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[WeaponInstanceService] GetAsync failed (attempt " .. i .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    local inv = {}
    if success and type(result) == "table" then
        inv = result
    elseif not success then
        warn("[WeaponInstanceService] Failed to load for " .. tostring(player.Name) .. "; starting empty")
    end

    playerInventories[player] = inv
    -- Register all IDs in collision set
    for id in pairs(inv) do
        allIds[id] = true
    end
    return inv
end

function WeaponInstanceService:SaveForPlayer(player)
    if not player then return false end
    local inv = playerInventories[player]
    if not inv then return true end -- nothing to save

    local key = dsKey(player)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, inv)
        end)
        if success then break end
        warn("[WeaponInstanceService] SetAsync failed (attempt " .. i .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("[WeaponInstanceService] Failed to save for " .. tostring(player.Name))
    end
    return success == true
end

function WeaponInstanceService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        self:SaveForPlayer(player)
    end
end

function WeaponInstanceService:RemovePlayer(player)
    if playerInventories[player] then
        -- Unregister IDs
        for id in pairs(playerInventories[player]) do
            allIds[id] = nil
        end
        playerInventories[player] = nil
    end
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
    return inv[instanceId].favorited
end

return WeaponInstanceService
