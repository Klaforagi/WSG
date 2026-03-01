-- CurrencyService Module
-- Server-only. Keeps an in-memory table of coin balances keyed by Player
-- and persists them to a DataStore named "Coins_v1".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DATASTORE_NAME = "Coins_v1"
local RETRIES = 3
local RETRY_DELAY = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local CurrencyService = {}

-- in-memory balances keyed by Player (the Player object)
local balances = {}

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
    return event, fn
end

local CoinsUpdatedEvent = ensureRemoteObjects()

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
    end
end

-- Cleanup when a player leaves
function CurrencyService:RemovePlayer(player)
    if balances[player] ~= nil then
        balances[player] = nil
    end
end

-- Example usage: award 5 coins to a killer on kill
-- CurrencyService:AddCoins(killer, 5)

return CurrencyService
