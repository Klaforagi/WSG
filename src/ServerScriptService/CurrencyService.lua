-- CurrencyService Module
-- Server-only. Keeps an in-memory table of coin/key/salvage balances keyed by Player
-- and persists them to DataStores named "Coins_v1", "Keys_v1", and "Salvage_v1".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

function CurrencyService:GetCoins(player)
    if not player then return 0 end
    return balances[player] or 0
end

function CurrencyService:SetCoins(player, amount)
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    balances[player] = amount
    updateLeaderstat(player, amount)
    -- notify client of new balance (server-authoritative)
    if CoinsUpdatedEvent and CoinsUpdatedEvent.FireClient then
        pcall(function()
            CoinsUpdatedEvent:FireClient(player, amount)
        end)
    end
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
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    keyBalances[player] = amount
    if KeysUpdatedEvent and KeysUpdatedEvent.FireClient then
        pcall(function()
            KeysUpdatedEvent:FireClient(player, amount)
        end)
    end
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
    if not player then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 then amount = 0 end
    salvageBalances[player] = amount
    if SalvageUpdatedEvent and SalvageUpdatedEvent.FireClient then
        pcall(function()
            SalvageUpdatedEvent:FireClient(player, amount)
        end)
    end
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

-- Loads coins for a player from the datastore (with retries). Returns the loaded amount (or 0).
function CurrencyService:LoadForPlayer(player)
    if not player then return 0 end
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("CurrencyService: GetAsync failed (attempt ", i, "): ", tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    local coins = 0
    if success and type(result) == "number" then
        coins = result
    else
        if not success then
            warn("CurrencyService: failed to load coins for ", tostring(player.Name), "; defaulting to 0")
        end
    end
    balances[player] = math.max(0, math.floor(coins))
    -- we don't create leaderstats here; callers should decide how to present balance
    -- but notify client in case they are already listening
    if CoinsUpdatedEvent and CoinsUpdatedEvent.FireClient then
        pcall(function()
            CoinsUpdatedEvent:FireClient(player, balances[player])
        end)
    end
    return balances[player]
end

--------------------------------------------------------------------------------
-- PREMIUM CRATE / KEY SYSTEM  – Load Keys from DataStore
--------------------------------------------------------------------------------
function CurrencyService:LoadKeysForPlayer(player)
    if not player then return 0 end
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return keysDs:GetAsync(key)
        end)
        if success then break end
        warn("CurrencyService: Keys GetAsync failed (attempt ", i, "): ", tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    local keys = 0
    if success and type(result) == "number" then
        keys = result
    else
        if not success then
            warn("CurrencyService: failed to load keys for ", tostring(player.Name), "; defaulting to 0")
        end
    end
    keyBalances[player] = math.max(0, math.floor(keys))
    if KeysUpdatedEvent and KeysUpdatedEvent.FireClient then
        pcall(function()
            KeysUpdatedEvent:FireClient(player, keyBalances[player])
        end)
    end
    return keyBalances[player]
end

-- PREMIUM CRATE / KEY SYSTEM  – Save Keys to DataStore
function CurrencyService:SaveKeysForPlayer(player)
    if not player then return false end
    local key = getKey(player)
    local amount = keyBalances[player] or 0
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            keysDs:SetAsync(key, amount)
        end)
        if success then break end
        warn("CurrencyService: Keys SetAsync failed (attempt ", i, "): ", tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("CurrencyService: failed to save keys for ", tostring(player.Name))
    end
    return success
end

--------------------------------------------------------------------------------
-- SALVAGE SYSTEM  – Load Salvage from DataStore
--------------------------------------------------------------------------------
function CurrencyService:LoadSalvageForPlayer(player)
    if not player then return 0 end
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return salvageDs:GetAsync(key)
        end)
        if success then break end
        warn("CurrencyService: Salvage GetAsync failed (attempt ", i, "): ", tostring(result))
        task.wait(RETRY_DELAY * i)
    end
    local salvage = 0
    if success and type(result) == "number" then
        salvage = result
    else
        if not success then
            warn("CurrencyService: failed to load salvage for ", tostring(player.Name), "; defaulting to 0")
        end
    end
    salvageBalances[player] = math.max(0, math.floor(salvage))
    if SalvageUpdatedEvent and SalvageUpdatedEvent.FireClient then
        pcall(function()
            SalvageUpdatedEvent:FireClient(player, salvageBalances[player])
        end)
    end
    return salvageBalances[player]
end

-- SALVAGE SYSTEM  – Save Salvage to DataStore
function CurrencyService:SaveSalvageForPlayer(player)
    if not player then return false end
    local key = getKey(player)
    local amount = salvageBalances[player] or 0
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            salvageDs:SetAsync(key, amount)
        end)
        if success then break end
        warn("CurrencyService: Salvage SetAsync failed (attempt ", i, "): ", tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("CurrencyService: failed to save salvage for ", tostring(player.Name))
    end
    return success
end

-- Saves coins for a player to the datastore (with retries). Returns boolean success.
function CurrencyService:SaveForPlayer(player)
    if not player then return false end
    local key = getKey(player)
    local amount = balances[player] or 0
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, amount)
        end)
        if success then break end
        warn("CurrencyService: SetAsync failed (attempt ", i, "): ", tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("CurrencyService: failed to save coins for ", tostring(player.Name))
    end
    return success
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
end

-- Example usage: award 5 coins to a killer on kill
-- CurrencyService:AddCoins(killer, 5)

return CurrencyService
