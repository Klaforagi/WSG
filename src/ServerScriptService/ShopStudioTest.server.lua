--------------------------------------------------------------------------------
-- ShopStudioTest.server.lua
--
-- Studio-only purchase bypass for testing the shop without Roblox purchase
-- prompts. The client calls a RemoteFunction with the item it would have
-- purchased, and this script grants the equivalent reward directly.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoinProducts = require(ReplicatedStorage:WaitForChild("CoinProducts"))
local KeyProducts = require(ReplicatedStorage:WaitForChild("KeyProducts"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local CurrencyService
local GamepassService

local function getCurrencyService()
    if CurrencyService then
        return CurrencyService
    end
    local mod = script.Parent:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            CurrencyService = result
        else
            warn("[ShopStudioTest] Failed to require CurrencyService:", tostring(result))
        end
    end
    return CurrencyService
end

local function getGamepassService()
    if GamepassService then
        return GamepassService
    end
    local mod = script.Parent:FindFirstChild("GamepassService")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            GamepassService = result
        else
            warn("[ShopStudioTest] Failed to require GamepassService:", tostring(result))
        end
    end
    return GamepassService
end

local function ensureFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = parent
    end
    return folder
end

local function ensureRemoteFunction(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then
        return existing
    end
    if existing then
        existing:Destroy()
    end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = parent
    return rf
end

local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
local shopFolder = ensureFolder(remotesFolder, "Shop")
local studioPurchaseRF = ensureRemoteFunction(shopFolder, "ShopTestPurchase")

local function saveCurrencyIfPossible(player)
    local cur = getCurrencyService()
    if cur and type(cur.SaveForPlayer) == "function" then
        pcall(function()
            cur:SaveForPlayer(player)
        end)
    end
end

local function grantCurrencyPack(player, payload)
    local currencyType = tostring(payload.currencyType or "")
    local amount = math.floor(tonumber(payload.amount) or 0)
    if amount <= 0 then
        return false, "Invalid test amount"
    end

    local cur = getCurrencyService()
    if not cur then
        return false, "CurrencyService unavailable"
    end

    if currencyType == "Coins" then
        cur:AddCoins(player, amount, { reason = "purchase", skipMultipliers = true })
        saveCurrencyIfPossible(player)
        return true, string.format("Granted %s coins for Studio testing.", tostring(amount))
    end

    if currencyType == "Keys" then
        cur:AddKeys(player, amount)
        saveCurrencyIfPossible(player)
        return true, string.format("Granted %s keys for Studio testing.", tostring(amount))
    end

    if currencyType == "Salvage" then
        cur:AddSalvage(player, amount)
        saveCurrencyIfPossible(player)
        return true, string.format("Granted %s shards for Studio testing.", tostring(amount))
    end

    return false, "Unknown currency type"
end

local function grantStarterPack(player)
    local reward = nil
    if type(ShopCatalog.GetStarterPackReward) == "function" then
        reward = ShopCatalog.GetStarterPackReward()
    end
    if type(reward) ~= "table" then
        local item = ShopCatalog.GetById("starter_pack")
        reward = item and item.Reward or nil
    end
    if type(reward) ~= "table" then
        return false, "Starter Pack reward is unavailable"
    end

    local cur = getCurrencyService()
    if not cur then
        return false, "CurrencyService unavailable"
    end

    if reward.Coins then
        cur:AddCoins(player, reward.Coins, { reason = "purchase", skipMultipliers = true })
    end
    if reward.Keys then
        cur:AddKeys(player, reward.Keys)
    end
    if reward.Salvage then
        cur:AddSalvage(player, reward.Salvage)
    end
    saveCurrencyIfPossible(player)

    return true, "Granted Starter Pack for Studio testing."
end

local function grantGamepass(player, payload)
    local itemId = type(payload.itemId) == "string" and payload.itemId or nil
    if itemId == nil or itemId == "" then
        return false, "Missing gamepass itemId"
    end

    local item = ShopCatalog.GetById(itemId)
    if type(item) ~= "table" or item.Kind ~= "GamePass" then
        return false, "Unknown gamepass item"
    end

    local gp = getGamepassService()
    if not gp then
        return false, "GamepassService unavailable"
    end

    if type(gp.SetStudioTestOwnership) == "function" then
        local ok, result = pcall(function()
            return gp:SetStudioTestOwnership(player, item.Id, true)
        end)
        if not ok then
            return false, tostring(result)
        end
    else
        pcall(function()
            player:SetAttribute("StudioShopTestOwned_" .. tostring(item.Id), true)
        end)
        if type(gp.RefreshPlayer) == "function" then
            pcall(function()
                gp:RefreshPlayer(player)
            end)
        end
    end

    return true, tostring(item.DisplayName or item.Id or "Gamepass") .. " granted for Studio testing."
end

local function grantProductById(player, payload)
    local productId = math.floor(tonumber(payload.productId) or 0)
    local itemId = type(payload.itemId) == "string" and payload.itemId or nil

    if itemId == "starter_pack" then
        return grantStarterPack(player)
    end

    if productId > 0 then
        local coinAmount = CoinProducts.CoinsByProductId and CoinProducts.CoinsByProductId[productId]
        if coinAmount then
            return grantCurrencyPack(player, { currencyType = "Coins", amount = coinAmount })
        end

        local keyAmount = KeyProducts.KeysByProductId and KeyProducts.KeysByProductId[productId]
        if keyAmount then
            return grantCurrencyPack(player, { currencyType = "Keys", amount = keyAmount })
        end

        local shopItem = ShopCatalog.GetByProductId(productId)
        if type(shopItem) == "table" and type(shopItem.Reward) == "table" then
            return grantStarterPack(player)
        end
    end

    local currencyType = type(payload.currencyType) == "string" and payload.currencyType or nil
    if currencyType then
        return grantCurrencyPack(player, payload)
    end

    return false, "Unknown test product"
end

studioPurchaseRF.OnServerInvoke = function(player, payload)
    if not RunService:IsStudio() then
        return { success = false, error = "Studio testing is only available in Studio" }
    end
    if not player or not player:IsA("Player") then
        return { success = false, error = "Invalid player" }
    end
    if type(payload) ~= "table" then
        return { success = false, error = "Invalid payload" }
    end

    local kind = tostring(payload.kind or "")
    local ok, message = false, ""

    if kind == "GamePass" then
        ok, message = grantGamepass(player, payload)
    else
        ok, message = grantProductById(player, payload)
    end

    if not ok then
        return { success = false, error = message }
    end

    print(string.format("[ShopStudioTest] Granted %s to %s", tostring(payload.itemId or payload.currencyType or payload.productId), player.Name))
    return {
        success = true,
        message = message,
    }
end

print("[ShopStudioTest] Studio shop test remote ready under ReplicatedStorage/Remotes/Shop/")
