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

local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local BoostConfig = require(ReplicatedStorage:WaitForChild("BoostConfig"))

local REFRESH_INTERVAL = 600 -- 10 minutes

local PotionStockService = {}
PotionStockService.RefreshInterval = REFRESH_INTERVAL

-- [userId] = { cycle = number, purchases = { [itemId] = count } }
local playerStockUsage = {}
local getPlayerUsage

--------------------------------------------------------------------------------
-- Time helpers (server-authoritative)
--------------------------------------------------------------------------------
local function getServerNow()
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
    local stock = math.max(0, math.floor(tonumber(def.StockPerRefresh or def.stockPerRefresh) or 0))
    if stock <= 0 and (def.PriceCoins or def.coinPrice) then
        warn("[PotionStockService] Missing StockPerRefresh for:", tostring(def.Id or def.DisplayName or "unknown"))
    end
    return stock
end

local function getMaxStock(itemId)
    if type(itemId) ~= "string" or itemId == "" then
        warn("[PotionStockService] Invalid itemId:", tostring(itemId))
        return 0
    end

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

    if type(PotionConfig.GetStallPotions) == "function" then
        for _, def in ipairs(PotionConfig.GetStallPotions()) do
            local maxStock = readStock(def)
            if maxStock > 0 then
                table.insert(list, { id = def.Id, max = maxStock })
            end
        end
    end

    if type(BoostConfig.GetPotionsStallBoosts) == "function" then
        for _, def in ipairs(BoostConfig.GetPotionsStallBoosts()) do
            local maxStock = readStock(def)
            if maxStock > 0 then
                table.insert(list, { id = def.Id, max = maxStock })
            end
        end
    end

    return list
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
    if not usage or usage.cycle ~= currentCycle then
        usage = {
            cycle = currentCycle,
            purchases = {},
        }
        playerStockUsage[userId] = usage
    end

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
    return true
end

--- Builds the per-player stock snapshot for the client.
function PotionStockService:BuildState(player)
    local items = {}
    for _, info in ipairs(getStockableItems()) do
        items[info.id] = getPlayerItemStockInfo(player, info.id)
    end

    if next(items) == nil then
        warn("[PotionStockService] BuildState returned no stock items")
    end

    return {
        cycle = self:GetCurrentCycle(),
        secondsRemaining = self:GetSecondsUntilRefresh(),
        refreshInterval = REFRESH_INTERVAL,
        items = items,
    }
end

function PotionStockService:ClearPlayer(player)
    if player then
        playerStockUsage[player.UserId] = nil
    end
end

return PotionStockService
