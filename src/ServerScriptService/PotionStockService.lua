--------------------------------------------------------------------------------
-- PotionStockService.lua  (ServerScriptService)
-- Server-authoritative gold/coin stock for the Potion Stall.
--
-- Design notes:
--  * Robux purchases are NOT tracked here and are never blocked by stock.
--  * Stock limits are PER-PLAYER. Player A buying an item never reduces what
--    Player B can buy.
--  * Refresh cycles are aligned to fixed REFRESH_INTERVAL windows derived from
--    server time, so every player on the same server shares the same countdown.
--  * Per-player usage is reset lazily: when a player's stored cycle no longer
--    matches the current cycle, their usage table is rebuilt. No per-cycle
--    sweep of every player is required.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")

local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local BoostConfig = require(ReplicatedStorage:WaitForChild("BoostConfig"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "PotionStock_v1"
local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local REFRESH_INTERVAL = 600 -- 10 minutes

local PotionStockService = {}
PotionStockService.RefreshInterval = REFRESH_INTERVAL

-- [userId] = { cycle = number, purchases = { [itemId] = count } }
local playerStockUsage = {}
local getPlayerUsage
local getServerNow

-- Current cycle shared stock (generated once per cycle by server)
local currentCycleStock = nil

-- Warning throttles
local buildStateEmptyWarnCycle = nil
local fallbackWarnCycle = {}

-- Simple string hash for deterministic per-item seeds
local function hashString(s)
    if type(s) ~= "string" then
        return 0
    end
    local h = 0
    for i = 1, #s do
        h = (h * 31 + s:byte(i)) % 2147483647
    end
    return math.abs(h)
end

-- Deterministic per-cycle stock generator using item id + cycle as seed
local function generateDeterministicStock(def)
    if type(def) ~= "table" then
        return 0
    end
    local id = tostring(def.Id or def.DisplayName or "")
    local cycle = PotionStockService:GetCurrentCycle()
    local seed = (cycle * 10007) + hashString(id)
    local rng = Random.new(seed)
    local r = rng:NextNumber()
    local category = tostring(def.Category or "")
    if category == "Elixir" then
        if r < 0.80 then
            return 0
        elseif r < 0.92 then
            return 1
        elseif r < 0.98 then
            return 2
        else
            return 3
        end
    else
        if r < 0.55 then
            return 0
        elseif r < 0.75 then
            return 1
        elseif r < 0.90 then
            return 2
        else
            return 3
        end
    end
end

local function ensureCycleStock()
    local cycle = PotionStockService:GetCurrentCycle()
    if currentCycleStock and currentCycleStock.cycle == cycle then
        return currentCycleStock
    end

    -- Generate randomized stock for this cycle using deterministic per-item seeds
    local items = {}
    -- Collect potion definitions robustly (mirror client logic)
    local potionDefs = {}
    if type(PotionConfig.GetStallPotions) == "function" then
        potionDefs = PotionConfig.GetStallPotions()
    elseif type(PotionConfig.GetOrderedPotions) == "function" then
        for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
            if potionDef.ShowInPotionsStall == true then
                table.insert(potionDefs, potionDef)
            end
        end
    elseif type(PotionConfig.Potions) == "table" then
        for _, potionDef in ipairs(PotionConfig.Potions) do
            if potionDef.ShowInPotionsStall == true then
                table.insert(potionDefs, potionDef)
            end
        end
    end

    -- Potions: values 0-3 with probabilities 55%,20%,15%,10% (deterministic per-cycle)
    for _, def in ipairs(potionDefs) do
        local max = generateDeterministicStock(def)
        items[def.Id] = max
    end

    -- Collect boost definitions robustly
    local boostDefs = {}
    if type(BoostConfig.GetPotionsStallBoosts) == "function" then
        boostDefs = BoostConfig.GetPotionsStallBoosts()
    elseif type(BoostConfig.Boosts) == "table" then
        for _, boostDef in ipairs(BoostConfig.Boosts) do
            if boostDef.ShowInPotionsStall == true and not boostDef.InstantUse and boostDef.RemovedFromShop ~= true and boostDef.Purchasable ~= false then
                table.insert(boostDefs, boostDef)
            end
        end
    end

    -- Elixirs and other boosts: deterministic per-cycle stock
    for _, def in ipairs(boostDefs) do
        local max = generateDeterministicStock(def)
        -- Non-elixir boosts keep small non-zero chance if definition implies it
        if tostring(def.Category) ~= "Elixir" then
            -- preserve occasional small stock for non-elixir boosts
            if max == 3 then
                max = math.random(1, 2)
            end
        end
        items[def.Id] = max
    end

    currentCycleStock = { cycle = cycle, items = items }
    -- Debug: log generated cycle items for troubleshooting stock fallbacks
    pcall(function()
        local count = 0
        local sample = {}
        for k, v in pairs(items) do
            count = count + 1
            if #sample < 8 then
                table.insert(sample, string.format("%s=%d", tostring(k), tonumber(v) or 0))
            end
        end
        warn(string.format("[PotionStockService] Generated cycle stock (cycle=%d) with %d entries: %s", cycle, count, table.concat(sample, ", ")))
    end)
    return currentCycleStock
end

--------------------------------------------------------------------------------
-- Time helpers (server-authoritative)
--------------------------------------------------------------------------------
getServerNow = function()
    local ok, result = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if ok and type(result) == "number" then
        return result
    end
    return os.time()
end

function PotionStockService:GetCurrentCycle()
    return math.floor(getServerNow() / REFRESH_INTERVAL)
end

function PotionStockService:GetSecondsUntilRefresh()
    local now = getServerNow()
    local currentCycle = math.floor(now / REFRESH_INTERVAL)
    local nextRefresh = (currentCycle + 1) * REFRESH_INTERVAL
    return math.max(0, math.ceil(nextRefresh - now))
end

--------------------------------------------------------------------------------
-- Stock configuration lookups
--------------------------------------------------------------------------------
local function readStock(def)
    if type(def) ~= "table" then
        return 0
    end
    -- Instead of returning the static configured StockPerRefresh, generate a
    -- deterministic per-cycle stock value that follows the desired distributions
    local generated = generateDeterministicStock(def)
    pcall(function()
        if (def.StockPerRefresh or def.stockPerRefresh) then
            local key = tostring(def.Id or def.DisplayName or "unknown")
            local cycle = PotionStockService:GetCurrentCycle()
            if not fallbackWarnCycle[key] or fallbackWarnCycle[key] ~= cycle then
                warn(string.format("[PotionStockService] Using generated fallback stock for %s (configured=%s -> generated=%d)", key, tostring(def.StockPerRefresh or def.stockPerRefresh), generated))
                fallbackWarnCycle[key] = cycle
            end
        end
    end)
    return generated
end

local function getMaxStock(itemId)
    if type(itemId) ~= "string" or itemId == "" then
        warn("[PotionStockService] Invalid itemId:", tostring(itemId))
        return 0
    end

    -- Prefer server-generated cycle stock when available
    local cycleStock = ensureCycleStock()
    if cycleStock and cycleStock.items and cycleStock.items[itemId] ~= nil then
        return math.max(0, math.floor(tonumber(cycleStock.items[itemId]) or 0))
    end

    -- Fallback to static StockPerRefresh value in definitions
    local potionDef = PotionConfig.GetById(itemId)
    if potionDef then
        return readStock(potionDef)
    end

    local boostDef = BoostConfig.GetById(itemId)
    if boostDef then
        return readStock(boostDef)
    end

    return 0
end

local function getPlayerItemStockInfo(player, itemId)
    local maxStock = getMaxStock(itemId)
    if maxStock <= 0 then
        return {
            used = 0,
            max = 0,
            remaining = 0,
            soldOut = true,
        }
    end

    local usage = getPlayerUsage(player)
    local used = math.max(0, math.floor(tonumber(usage.purchases[itemId]) or 0))
    local remaining = math.max(0, maxStock - used)

    return {
        used = used,
        max = maxStock,
        remaining = remaining,
        soldOut = used >= maxStock,
    }
end

-- Returns the list of stall items that participate in the stock system.
local function getStockableItems()
    local list = {}
    -- Build full list from definitions, preferring cycle-generated maxima
    local cycleStock = ensureCycleStock()

    -- Potions
    local potionDefs = {}
    if type(PotionConfig.GetStallPotions) == "function" then
        potionDefs = PotionConfig.GetStallPotions()
    elseif type(PotionConfig.GetOrderedPotions) == "function" then
        for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
            if potionDef.ShowInPotionsStall == true then
                table.insert(potionDefs, potionDef)
            end
        end
    elseif type(PotionConfig.Potions) == "table" then
        for _, potionDef in ipairs(PotionConfig.Potions) do
            if potionDef.ShowInPotionsStall == true then
                table.insert(potionDefs, potionDef)
            end
        end
    end
    for _, def in ipairs(potionDefs) do
        local max = 0
        if cycleStock and cycleStock.items and cycleStock.items[def.Id] ~= nil then
            max = math.max(0, math.floor(tonumber(cycleStock.items[def.Id]) or 0))
        else
            max = readStock(def)
        end
        table.insert(list, { id = def.Id, max = max })
    end

    -- Boosts
    local boostDefs = {}
    if type(BoostConfig.GetPotionsStallBoosts) == "function" then
        boostDefs = BoostConfig.GetPotionsStallBoosts()
    elseif type(BoostConfig.Boosts) == "table" then
        for _, boostDef in ipairs(BoostConfig.Boosts) do
            if boostDef.ShowInPotionsStall == true and not boostDef.InstantUse and boostDef.RemovedFromShop ~= true and boostDef.Purchasable ~= false then
                table.insert(boostDefs, boostDef)
            end
        end
    end
    for _, def in ipairs(boostDefs) do
        local max = 0
        if cycleStock and cycleStock.items and cycleStock.items[def.Id] ~= nil then
            max = math.max(0, math.floor(tonumber(cycleStock.items[def.Id]) or 0))
        else
            max = readStock(def)
        end
        table.insert(list, { id = def.Id, max = max })
    end

    return list
end

local function getKeyForPlayer(player)
    if not player or not player.UserId then return nil end
    return "User_" .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- Per-player usage (lazily reset per cycle)
--------------------------------------------------------------------------------
getPlayerUsage = function(player)
    if not player then
        return { cycle = PotionStockService:GetCurrentCycle(), purchases = {} }
    end

    local userId = player.UserId
    local currentCycle = PotionStockService:GetCurrentCycle()

    local usage = playerStockUsage[userId]
    if not usage then
        -- Attempt to load persisted usage for this player
        local key = getKeyForPlayer(player)
        if key then
            local ok, result, err = pcall(function()
                return DataStoreOps.Load(ds, key, "PotionStock/" .. key)
            end)
            if ok and type(result) == "table" and result.cycle and type(result.purchases) == "table" then
                usage = {
                    cycle = math.floor(tonumber(result.cycle) or currentCycle),
                    purchases = {},
                }
                for id, cnt in pairs(result.purchases) do
                    usage.purchases[tostring(id)] = math.max(0, math.floor(tonumber(cnt) or 0))
                end
            end
        end
    end

    if not usage or usage.cycle ~= currentCycle then
        usage = {
            cycle = currentCycle,
            purchases = {},
        }
    end

    playerStockUsage[userId] = usage
    return usage
end

--- Returns remaining, max for the player/item.
--- A max of 0 means the item has no stock cap (unlimited); remaining is math.huge.
function PotionStockService:GetRemaining(player, itemId)
    local info = getPlayerItemStockInfo(player, itemId)
    if info.max <= 0 then
        return math.huge, 0
    end
    return info.remaining, info.max
end

--- True when the player can still buy at least one of the item this cycle.
function PotionStockService:HasStock(player, itemId)
    local remaining, maxStock = self:GetRemaining(player, itemId)
    if maxStock <= 0 then
        return true
    end
    return remaining > 0
end

--- Records one coin purchase. Must only be called AFTER a successful purchase.
--- Returns true if the usage was recorded (or the item is unlimited).
function PotionStockService:Consume(player, itemId)
    local maxStock = getMaxStock(itemId)
    if maxStock <= 0 then
        return true
    end

    local usage = getPlayerUsage(player)
    local used = math.max(0, math.floor(tonumber(usage.purchases[itemId]) or 0))
    if used >= maxStock then
        return false
    end

    usage.purchases[itemId] = used + 1

    -- Persist the updated usage for this player (store per-cycle purchases)
    local key = getKeyForPlayer(player)
    if key then
        local cycle = usage.cycle or self:GetCurrentCycle()
        local ok, res, err = DataStoreOps.Update(ds, key, "PotionStock/" .. key, function(stored)
            stored = type(stored) == "table" and stored or {}
            if tonumber(stored.cycle) ~= cycle then
                stored.cycle = cycle
                stored.purchases = {}
            end
            stored.purchases = type(stored.purchases) == "table" and stored.purchases or {}
            stored.purchases[itemId] = math.max(0, math.floor(tonumber(stored.purchases[itemId]) or 0)) + 1
            return stored
        end)
        if not ok then
            warn("[PotionStockService] Failed to persist purchase for", tostring(key), "item", tostring(itemId), "err:", tostring(res or err))
        end
    end

    return true
end

--- Builds the per-player stock snapshot for the client.
function PotionStockService:BuildState(player)
    local items = {}
    for _, info in ipairs(getStockableItems()) do
        items[info.id] = getPlayerItemStockInfo(player, info.id)
    end

    if next(items) == nil then
        local cycle = self:GetCurrentCycle()
        if buildStateEmptyWarnCycle ~= cycle then
            warn("[PotionStockService] BuildState returned no stock items (cycle=" .. tostring(cycle) .. ")")
            buildStateEmptyWarnCycle = cycle
        end
    end

    return {
        cycle = self:GetCurrentCycle(),
        secondsRemaining = self:GetSecondsUntilRefresh(),
        refreshInterval = REFRESH_INTERVAL,
        items = items,
    }
end

function PotionStockService:GetCycleItems()
    local cycleStock = ensureCycleStock()
    if not cycleStock or type(cycleStock.items) ~= "table" then
        return {}
    end
    -- Return a shallow copy to avoid external mutation
    local copy = {}
    for k, v in pairs(cycleStock.items) do
        copy[k] = v
    end
    return copy
end

function PotionStockService:ClearPlayer(player)
    if player then
        playerStockUsage[player.UserId] = nil
    end
end

return PotionStockService
