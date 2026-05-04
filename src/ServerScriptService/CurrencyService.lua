-- CurrencyService Module
-- Server-only. Keeps an in-memory table of coin/key/salvage balances keyed by Player
-- and persists them to DataStores named "Coins_v1", "Keys_v1", and "Salvage_v1".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "Coins_v1"
local RETRIES = 3
local RETRY_DELAY = 0.5

-- PREMIUM CRATE / KEY SYSTEM  – Keys DataStore
local KEYS_DATASTORE_NAME = "Keys_v1"

-- SALVAGE SYSTEM  – Salvage DataStore
local SALVAGE_DATASTORE_NAME = "Salvage_v1"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)
local keysDs = DataStoreService:GetDataStore(KEYS_DATASTORE_NAME) -- PREMIUM CRATE / KEY SYSTEM
local salvageDs = DataStoreService:GetDataStore(SALVAGE_DATASTORE_NAME) -- SALVAGE SYSTEM

local CurrencyService = {}

-- in-memory balances keyed by Player (the Player object)
local balances = {}
local keyBalances = {} -- PREMIUM CRATE / KEY SYSTEM
local salvageBalances = {} -- SALVAGE SYSTEM
local recentMutations = {}
local _saveCoordinator

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

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

-- internal: update leaderstats IntValue if present
local function updateLeaderstat(player, amount)
    if not player then return end
    local stats = player:FindFirstChild("leaderstats")
    if stats and stats:IsA("Folder") then
        local val = stats:FindFirstChild("Coins")
        if val and val:IsA("IntValue") then
            val.Value = amount
        end
    end
end

-- Remote API: RemoteEvent "CoinsUpdated" (server->client) and RemoteFunction "GetCoins" (client->server)
local function ensureRemoteObjects()
    local event = ReplicatedStorage:FindFirstChild("CoinsUpdated")
    if not event then
        event = Instance.new("RemoteEvent")
        event.Name = "CoinsUpdated"
        event.Parent = ReplicatedStorage
    end
    local fn = ReplicatedStorage:FindFirstChild("GetCoins")
    if not fn then
        fn = Instance.new("RemoteFunction")
        fn.Name = "GetCoins"
        fn.Parent = ReplicatedStorage
    end
    -- Server-side handler for GetCoins
    fn.OnServerInvoke = function(player)
        return CurrencyService:GetCoins(player)
    end

    -- PREMIUM CRATE / KEY SYSTEM  – Keys remotes
    local keysEvent = ReplicatedStorage:FindFirstChild("KeysUpdated")
    if not keysEvent then
        keysEvent = Instance.new("RemoteEvent")
        keysEvent.Name = "KeysUpdated"
        keysEvent.Parent = ReplicatedStorage
    end
    local keysFn = ReplicatedStorage:FindFirstChild("GetKeys")
    if not keysFn then
        keysFn = Instance.new("RemoteFunction")
        keysFn.Name = "GetKeys"
        keysFn.Parent = ReplicatedStorage
    end
    keysFn.OnServerInvoke = function(player)
        return CurrencyService:GetKeys(player)
    end

    -- SALVAGE SYSTEM  – Salvage remotes
    local salvageEvent = ReplicatedStorage:FindFirstChild("SalvageUpdated")
    if not salvageEvent then
        salvageEvent = Instance.new("RemoteEvent")
        salvageEvent.Name = "SalvageUpdated"
        salvageEvent.Parent = ReplicatedStorage
    end
    local salvageFn = ReplicatedStorage:FindFirstChild("GetSalvage")
    if not salvageFn then
        salvageFn = Instance.new("RemoteFunction")
        salvageFn.Name = "GetSalvage"
        salvageFn.Parent = ReplicatedStorage
    end
    salvageFn.OnServerInvoke = function(player)
        return CurrencyService:GetSalvage(player)
    end

    return event, fn, keysEvent, keysFn, salvageEvent, salvageFn
end

local CoinsUpdatedEvent, _, KeysUpdatedEvent, _, SalvageUpdatedEvent = ensureRemoteObjects()

local function rememberMutation(player, sectionName, reason)
    if not player then return end
    recentMutations[player] = recentMutations[player] or {}
    recentMutations[player][sectionName] = {
        at = os.clock(),
        reason = tostring(reason or "unknown"),
    }
end

local function markDirty(player, reason)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "Currency", reason or "currency")
    end
end

local function applyCoins(player, amount, options)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    balances[player] = amount
    updateLeaderstat(player, amount)
    if CoinsUpdatedEvent and CoinsUpdatedEvent.FireClient then
        pcall(function()
            CoinsUpdatedEvent:FireClient(player, amount)
        end)
    end
    if not (options and options.skipDirty) then
        rememberMutation(player, "coins", options and options.reason)
        markDirty(player, options and options.reason or "coins")
    end
end

local function applyKeys(player, amount, options)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    keyBalances[player] = amount
    if KeysUpdatedEvent and KeysUpdatedEvent.FireClient then
        pcall(function()
            KeysUpdatedEvent:FireClient(player, amount)
        end)
    end
    if not (options and options.skipDirty) then
        rememberMutation(player, "keys", options and options.reason)
        markDirty(player, options and options.reason or "keys")
    end
end

local function applySalvage(player, amount, options)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    salvageBalances[player] = amount
    if SalvageUpdatedEvent and SalvageUpdatedEvent.FireClient then
        pcall(function()
            SalvageUpdatedEvent:FireClient(player, amount)
        end)
    end
    if not (options and options.skipDirty) then
        rememberMutation(player, "salvage", options and options.reason)
        markDirty(player, options and options.reason or "salvage")
    end
end

local function applyProfileData(player, payload, options)
    payload = payload or {}
    applyCoins(player, payload.coins or 0, options)
    applyKeys(player, payload.keys or 0, options)
    applySalvage(player, payload.salvage or 0, options)
end

local function loadNumberFromStore(store, key, label)
    local ok, result, err = DataStoreOps.Load(store, key, label)
    if not ok then
        return false, nil, err
    end
    if result == nil then
        return true, nil, nil
    end
    return true, math.max(0, math.floor(tonumber(result) or 0)), nil
end

local function hasRecentMutation(player, sectionName)
    local sectionMutations = recentMutations[player]
    if type(sectionMutations) ~= "table" then
        return false
    end
    local mutation = sectionMutations[sectionName]
    if type(mutation) ~= "table" then
        return false
    end
    return (os.clock() - (mutation.at or 0)) <= 15
end

local function saveNumberToStore(player, store, key, label, sectionName, newValue, oldValue)
    local success, _, err = DataStoreOps.Update(store, key, label, function(storedValue)
        local storedNumber = tonumber(storedValue)
        local previousValue = tonumber(oldValue) or 0
        local sanitizedValue = math.max(0, math.floor(tonumber(newValue) or 0))

        if storedNumber and storedNumber > 0 and previousValue > 0 and sanitizedValue == 0 and not hasRecentMutation(player, sectionName) then
            warn(string.format("[DataStore] suspected wipe blocked | player=%s | section=%s | old=%d | attempted=%d", tostring(player.Name), sectionName, storedNumber, sanitizedValue))
            return storedValue
        end

        return sanitizedValue
    end)
    return success, err
end

function CurrencyService:GetCoins(player)
    if not player then return 0 end
    return balances[player] or 0
end

function CurrencyService:SetCoins(player, amount)
    applyCoins(player, amount)
end

function CurrencyService:AddCoins(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return end
    local cur = CurrencyService:GetCoins(player)
    CurrencyService:SetCoins(player, cur + amount)
end

--------------------------------------------------------------------------------
-- PREMIUM CRATE / KEY SYSTEM  – Keys currency helpers
--------------------------------------------------------------------------------
function CurrencyService:GetKeys(player)
    if not player then return 0 end
    return keyBalances[player] or 0
end

function CurrencyService:SetKeys(player, amount)
    applyKeys(player, amount)
end

function CurrencyService:AddKeys(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return end
    local cur = CurrencyService:GetKeys(player)
    CurrencyService:SetKeys(player, cur + amount)
end

function CurrencyService:RemoveKeys(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local cur = CurrencyService:GetKeys(player)
    CurrencyService:SetKeys(player, math.max(0, cur - amount))
end

function CurrencyService:HasEnoughKeys(player, amount)
    if not player then return false end
    amount = math.floor(tonumber(amount) or 0)
    return CurrencyService:GetKeys(player) >= amount
end
-- END PREMIUM CRATE / KEY SYSTEM (Keys helpers)

--------------------------------------------------------------------------------
-- SALVAGE SYSTEM  – Salvage currency helpers
--------------------------------------------------------------------------------
function CurrencyService:GetSalvage(player)
    if not player then return 0 end
    return salvageBalances[player] or 0
end

function CurrencyService:SetSalvage(player, amount)
    applySalvage(player, amount)
end

function CurrencyService:AddSalvage(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return end
    local cur = CurrencyService:GetSalvage(player)
    CurrencyService:SetSalvage(player, cur + amount)
end

function CurrencyService:RemoveSalvage(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local cur = CurrencyService:GetSalvage(player)
    CurrencyService:SetSalvage(player, math.max(0, cur - amount))
end

function CurrencyService:HasEnoughSalvage(player, amount)
    if not player then return false end
    amount = math.floor(tonumber(amount) or 0)
    return CurrencyService:GetSalvage(player) >= amount
end
-- END SALVAGE SYSTEM (Salvage helpers)

function CurrencyService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = nil,
            reason = "missing player",
        }
    end

    local key = getKey(player)
    local coinsOk, coins, coinsErr = loadNumberFromStore(ds, key, "Currency/Coins/" .. key)
    local keysOk, keys, keysErr = loadNumberFromStore(keysDs, key, "Currency/Keys/" .. key)
    local salvageOk, salvage, salvageErr = loadNumberFromStore(salvageDs, key, "Currency/Salvage/" .. key)
    local payload = {
        coins = coins or 0,
        keys = keys or 0,
        salvage = salvage or 0,
    }

    if not coinsOk or not keysOk or not salvageOk then
        applyProfileData(player, payload, { skipDirty = true, reason = "load_failed" })
        return {
            status = "failed",
            data = payload,
            reason = tostring(coinsErr or keysErr or salvageErr or "currency load failed"),
        }
    end

    applyProfileData(player, payload, { skipDirty = true, reason = "load" })
    if coins == nil and keys == nil and salvage == nil then
        return {
            status = "new",
            data = payload,
        }
    end

    return {
        status = "existing",
        data = payload,
    }
end

function CurrencyService:LoadForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    if result and result.status ~= "failed" then
        return result.data and result.data.coins or 0
    end
    return 0
end

--------------------------------------------------------------------------------
-- PREMIUM CRATE / KEY SYSTEM  – Load Keys from DataStore
--------------------------------------------------------------------------------
function CurrencyService:LoadKeysForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    if result and result.status ~= "failed" then
        return result.data and result.data.keys or 0
    end
    return 0
end

-- PREMIUM CRATE / KEY SYSTEM  – Save Keys to DataStore
function CurrencyService:SaveKeysForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

--------------------------------------------------------------------------------
-- SALVAGE SYSTEM  – Load Salvage from DataStore
--------------------------------------------------------------------------------
function CurrencyService:LoadSalvageForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    if result and result.status ~= "failed" then
        return result.data and result.data.salvage or 0
    end
    return 0
end

-- SALVAGE SYSTEM  – Save Salvage to DataStore
function CurrencyService:SaveSalvageForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

-- Saves coins for a player to the datastore (with retries). Returns boolean success.
function CurrencyService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

function CurrencyService:GetSaveData(player)
    if not player then
        return nil
    end
    return {
        coins = self:GetCoins(player),
        keys = self:GetKeys(player),
        salvage = self:GetSalvage(player),
    }
end

function CurrencyService:GetRecentMutationInfo(player)
    local state = recentMutations[player]
    if type(state) ~= "table" then
        return {}
    end
    return DataStoreOps.DeepCopy(state)
end

function CurrencyService:SaveProfileForPlayer(player, payload, oldData)
    if not player then return false, "missing player" end
    payload = payload or self:GetSaveData(player)
    if type(payload) ~= "table" then
        return false, "missing payload"
    end

    local key = getKey(player)
    local previous = type(oldData) == "table" and oldData or {}

    local coinsOk, coinsErr = saveNumberToStore(player, ds, key, "Currency/Coins/" .. key, "coins", payload.coins, previous.coins)
    local keysOk, keysErr = saveNumberToStore(player, keysDs, key, "Currency/Keys/" .. key, "keys", payload.keys, previous.keys)
    local salvageOk, salvageErr = saveNumberToStore(player, salvageDs, key, "Currency/Salvage/" .. key, "salvage", payload.salvage, previous.salvage)

    if coinsOk and keysOk and salvageOk then
        return true
    end
    return false, tostring(coinsErr or keysErr or salvageErr or "currency save failed")
end

-- Convenience to save all current players (used in BindToClose)
function CurrencyService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        local ok = CurrencyService:SaveForPlayer(player)
        if not ok then
            warn("CurrencyService: SaveAll failed for ", tostring(player.Name))
        end
        -- PREMIUM CRATE / KEY SYSTEM  – also save keys
        local ok2 = CurrencyService:SaveKeysForPlayer(player)
        if not ok2 then
            warn("CurrencyService: SaveAll keys failed for ", tostring(player.Name))
        end
        -- SALVAGE SYSTEM  – also save salvage
        local ok3 = CurrencyService:SaveSalvageForPlayer(player)
        if not ok3 then
            warn("CurrencyService: SaveAll salvage failed for ", tostring(player.Name))
        end
    end
end

-- Cleanup when a player leaves
function CurrencyService:RemovePlayer(player)
    if balances[player] ~= nil then
        balances[player] = nil
    end
    -- PREMIUM CRATE / KEY SYSTEM
    if keyBalances[player] ~= nil then
        keyBalances[player] = nil
    end
    -- SALVAGE SYSTEM
    if salvageBalances[player] ~= nil then
        salvageBalances[player] = nil
    end
    recentMutations[player] = nil
end

-- Example usage: award 5 coins to a killer on kill
-- CurrencyService:AddCoins(killer, 5)

return CurrencyService
