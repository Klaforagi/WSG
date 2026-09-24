-- Shared deterministic offers; persistent per-player reservations prevent rejoin/server-hop duplicates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage:WaitForChild("MarketConfig"))
local CrateConfig = require(ReplicatedStorage:WaitForChild("CrateConfig"))
local Enchants = require(ReplicatedStorage:WaitForChild("WeaponEnchantConfig"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local BoostConfig = require(ReplicatedStorage:WaitForChild("BoostConfig"))
local Potions = require(ServerScriptService:WaitForChild("HealthPotionService"))
local Boosts = require(ServerScriptService:WaitForChild("BoostService"))
local Currency = require(ServerScriptService:WaitForChild("CurrencyService"))
local Weapons = require(ServerScriptService:WaitForChild("WeaponInstanceService"))
local Mastery = require(ServerScriptService:WaitForChild("WeaponMasteryService"))
local Coordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local Ledger = require(ServerScriptService:WaitForChild("MarketPurchaseLedger"))
local store = game:GetService("DataStoreService"):GetDataStore("MarketPurchases_v1")

local function ensure(parent, class, name)
    local instance = parent:FindFirstChild(name)
    if not instance then
        instance = Instance.new(class)
        instance.Name = name
        instance.Parent = parent
    end
    return instance
end
local remotes = ensure(ensure(ReplicatedStorage, "Folder", "Remotes"), "Folder", "Market")
local getState = ensure(remotes, "RemoteFunction", "GetState")
local purchase = ensure(remotes, "RemoteFunction", "PurchaseWeapon")
local purchasePotion = ensure(remotes, "RemoteFunction", "PurchasePotion")
local changed = ensure(remotes, "RemoteEvent", "StateChanged")
local inventoryChanged = ensure(ReplicatedStorage, "RemoteEvent", "WeaponInventoryUpdated")
local cache, busy, lastRequest = {}, {}, {}
local activeCycle, offers, potionOffers
local potionPools = { {}, {}, {} }
for _, id in ipairs({"health_potion", "strength_potion", "speed_potion"}) do
    table.insert(potionPools[1], assert(PotionConfig.GetById(id)))
end
for _, def in ipairs(BoostConfig.Boosts) do
    if def.ShowInPotionsStall and not def.InstantUse and not def.RemovedFromShop and def.Purchasable ~= false then
        local slot = def.DisplayName:find("Flask", 1, true) and 2 or 3
        table.insert(potionPools[slot], def)
    end
end

-- Existing Studio place models are migrated without requiring a manual rename.
local function migrateStall(model)
    if model.Name ~= "SkinsStall" and model.Name ~= "CosmeticsStall" and model.Name ~= "MarketStall" then return end
    model.Name = "MarketStall"
    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("ProximityPrompt") then
            object.ObjectText = "Market Stall"
        elseif object:IsA("TextLabel") and (object.Text:upper():find("SKINS") or object.Text:upper():find("COSMETICS")) then
            object.Text = "MARKET"
        end
    end
end
for _, model in ipairs(workspace:GetChildren()) do migrateStall(model) end
workspace.ChildAdded:Connect(migrateStall)

local function currentOffers()
    local cycle = Config.GetCycle(workspace:GetServerTimeNow())
    if cycle ~= activeCycle then
        activeCycle = cycle
        offers = Config.GenerateOffers(cycle, CrateConfig.WeaponsByRarity, nil, Enchants.Enchants, Enchants.GuaranteedEnchantWeapons)
        potionOffers = Config.GeneratePotionOffers(cycle, potionPools)
    end
    return cycle, offers
end

local function ready(player)
    if player.Parent ~= Players then return false end
    local status = Coordinator:GetProfile(player).SectionStatus
    for _, section in ipairs({ "Currency", "WeaponInventory", "HealthPotions", "Boost" }) do
        if status[section] ~= "new" and status[section] ~= "existing" then return false end
    end
    return true
end

local function state(player)
    local cycle, items = currentOffers()
    local usage = cache[player]
    local bought = {}
    if usage and usage.cycle == cycle then
        for slot in pairs(usage.slots or {}) do bought[tostring(slot)] = true end
    end
    local remaining = {}
    for slot, offer in ipairs(potionOffers) do
        local count = offer.Stock
        for unit = 1, offer.Stock do
            if bought["p" .. slot .. ":" .. unit] then count -= 1 end
        end
        remaining[tostring(slot)] = count
    end
    return { Cycle = cycle, Offers = items, Purchased = bought, PotionOffers = potionOffers, PotionRemaining = remaining,
        RefreshAt = (cycle + 1) * Config.RefreshSeconds, Ready = usage ~= nil and ready(player) }
end

local function loadUsage(player)
    if cache[player] then return true end
    local ok, data = DataStoreOps.Load(store, tostring(player.UserId), "MarketPurchases")
    if ok and player.Parent == Players then
        cache[player] = type(data) == "table" and data or { cycle = -1, slots = {} }
        return true
    end
    return false
end

getState.OnServerInvoke = function(player)
    if not busy[player] and os.clock() - (lastRequest[player] or -math.huge) > 1 then
        lastRequest[player] = os.clock()
        busy[player] = true
        loadUsage(player)
        busy[player] = nil
    end
    return state(player)
end

local function purchaseOffer(player, cycle, slot, isPotion)
    if type(cycle) ~= "number" or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 3 then
        return false, "Invalid offer"
    end
    if busy[player] then return false, "Please wait" end
    if not ready(player) or not cache[player] then return false, "Your inventory is still loading" end
    local current, items = currentOffers()
    if cycle ~= current then return false, "The market has refreshed", state(player) end
    local offer = isPotion and potionOffers[slot] or items[slot]
    local key = tostring(slot)
    local usage = cache[player]
    if not isPotion and usage.cycle == cycle and usage.slots and usage.slots[key] then
        return false, "Already purchased this offer", state(player)
    end
    if Currency:GetCoins(player) < offer.CoinPrice then return false, "Not enough coins" end
    busy[player] = true
    local token = HttpService:GenerateGUID(false)
    local reserved = false
    local granted = false
    local ok, success, message = pcall(function()
        local saved, result = DataStoreOps.Update(store, tostring(player.UserId), "MarketPurchases", function(old)
            if isPotion then return Ledger.ReserveStock(old, cycle, "p" .. slot .. ":", offer.Stock, token) end
            return Ledger.Reserve(old, cycle, key, token)
        end)
        if not saved then return false, "Purchase could not be saved; please retry" end
        cache[player] = result
        if isPotion and result and result.cycle == cycle then
            for candidate, value in pairs(result.slots or {}) do
                if value == token then key = candidate; break end
            end
        end
        reserved = result and result.cycle == cycle and result.slots[key] == token
        if not reserved then return false, isPotion and "Sold out" or "Already purchased this offer" end
        if not ready(player) or Config.GetCycle(workspace:GetServerTimeNow()) ~= cycle then
            return false, "The market has refreshed; please retry"
        end
        if Currency:GetCoins(player) < offer.CoinPrice then return false, "Not enough coins" end
        -- No yielding between the balance check, charge, and grant.
        if isPotion then
            local bought, reason
            if offer.PotionKind == "Battle" then bought, reason = Potions:PurchasePotion(player, offer.ItemId)
            else bought, reason = Boosts:PurchaseOwnedBoost(player, offer.ItemId) end
            if not bought then return false, reason end
            granted = true
        else
            local instance = Weapons:CreateInstance(player, offer.WeaponName, offer.Rarity,
                offer.WeaponCategory, "Market:" .. offer.Id, offer.SizePercent, offer.SizeTier, offer.EnchantName, true)
            if not instance then return false, "Could not grant weapon" end
            granted = true
            Currency:SetCoins(player, Currency:GetCoins(player) - offer.CoinPrice)
            inventoryChanged:FireClient(player, Mastery:AttachMasteryToInventory(player, Weapons:GetInventory(player)))
        end
        -- Stock is already durably reserved; don't block the purchase response on profile saves.
        -- The grant/charge services also mark their sections dirty for normal save retries.
        task.defer(function()
            if player.Parent ~= Players then return end
            local saved, saveError = pcall(Coordinator.FlushPlayer, Coordinator, player)
            if not saved then warn("[Market] Background save error:", saveError) end
        end)
        return true, "Purchased " .. offer.DisplayName
    end)
    if reserved and not granted then
        local released, result = DataStoreOps.Update(store, tostring(player.UserId), "MarketRelease", function(old)
            return Ledger.Release(old, cycle, key, token)
        end)
        if released then cache[player] = result end
    end
    busy[player] = nil
    if player.Parent ~= Players then
        cache[player], lastRequest[player] = nil, nil
        return false, "Player left"
    end
    if not ok then
        warn("[Market] Purchase error:", success)
        return granted, granted and "Item granted" or "Purchase failed", state(player)
    end
    return success, message, state(player)
end
purchase.OnServerInvoke = function(player, cycle, slot)
    return purchaseOffer(player, cycle, slot, false)
end
purchasePotion.OnServerInvoke = function(player, cycle, slot)
    return purchaseOffer(player, cycle, slot, true)
end

Players.PlayerRemoving:Connect(function(player)
    cache[player], busy[player], lastRequest[player] = nil, nil, nil
end)
task.spawn(function()
    currentOffers()
    while true do
        task.wait(1)
        local previous = activeCycle
        currentOffers()
        if previous ~= activeCycle then
            for _, player in ipairs(Players:GetPlayers()) do changed:FireClient(player, state(player)) end
        end
    end
end)
