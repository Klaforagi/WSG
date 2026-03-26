--------------------------------------------------------------------------------
-- CoinShopReceipt.server.lua  –  Server-side Developer Product receipt handler
-- Place in ServerScriptService.
--
-- Handles MarketplaceService.ProcessReceipt for coin packs defined in
-- ReplicatedStorage.CoinProducts and key packs defined in
-- ReplicatedStorage.KeyProducts.  Awards currency via the existing
-- CurrencyService module and persists receipt IDs to prevent duplicates.
--------------------------------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local SSS                = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Load shared CoinProducts config
--------------------------------------------------------------------------------
local CoinProducts
do
	local mod = ReplicatedStorage:WaitForChild("CoinProducts", 15)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			CoinProducts = result
		else
			warn("[CoinShopReceipt] Failed to require CoinProducts:", tostring(result))
		end
	else
		warn("[CoinShopReceipt] CoinProducts module not found – coin receipt handler disabled")
	end
end

--------------------------------------------------------------------------------
-- Load shared KeyProducts config
--------------------------------------------------------------------------------
local KeyProducts
do
	local mod = ReplicatedStorage:WaitForChild("KeyProducts", 15)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			KeyProducts = result
		else
			warn("[CoinShopReceipt] Failed to require KeyProducts:", tostring(result))
		end
	else
		warn("[CoinShopReceipt] KeyProducts module not found – key receipt handler disabled")
	end
end

--------------------------------------------------------------------------------
-- Load existing CurrencyService (server module under ServerScriptService)
--------------------------------------------------------------------------------
local CurrencyService
do
	local mod = SSS:WaitForChild("CurrencyService", 15)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			CurrencyService = result
		else
			warn("[CoinShopReceipt] Failed to require CurrencyService:", tostring(result))
		end
	else
		warn("[CoinShopReceipt] CurrencyService module not found – coins cannot be awarded")
	end
end

--------------------------------------------------------------------------------
-- AchievementService (lazy-loaded for Robux spending achievements)
--------------------------------------------------------------------------------
local AchievementService
local function getAchievementService()
	if AchievementService then return AchievementService end
	pcall(function()
		local mod = SSS:FindFirstChild("AchievementService")
		if mod and mod:IsA("ModuleScript") then
			AchievementService = require(mod)
		end
	end)
	return AchievementService
end

--------------------------------------------------------------------------------
-- Receipt tracking DataStore (prevents granting coins more than once per receipt)
--------------------------------------------------------------------------------
local RECEIPT_DS_NAME = "CoinShopReceipts_v1"
local receiptStore = DataStoreService:GetDataStore(RECEIPT_DS_NAME)

local function receiptKey(receiptId)
	return "receipt_" .. tostring(receiptId)
end

--- Returns true if this receipt was already processed.
local function isReceiptProcessed(receiptId)
	local ok, val = pcall(function()
		return receiptStore:GetAsync(receiptKey(receiptId))
	end)
	if ok and val then
		return true
	end
	return false
end

--- Mark a receipt as processed.
local function markReceiptProcessed(receiptId, playerId, productId, coins)
	local ok, err = pcall(function()
		receiptStore:SetAsync(receiptKey(receiptId), {
			playerId  = playerId,
			productId = productId,
			coins     = coins,
			time      = os.time(),
		})
	end)
	if not ok then
		warn("[CoinShopReceipt] Failed to save receipt", receiptId, ":", tostring(err))
	end
	return ok
end

--------------------------------------------------------------------------------
-- ProcessReceipt callback
--------------------------------------------------------------------------------
local function processReceipt(receiptInfo)
	local playerId  = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local receiptId = receiptInfo.PurchaseId

	print("[CoinShopReceipt] Processing receipt:", receiptId,
		"Player:", playerId, "Product:", productId)

	-- 1) Determine what this product grants (coins or keys)
	local coinsToAward = CoinProducts and CoinProducts.CoinsByProductId and CoinProducts.CoinsByProductId[productId]
	local keysToAward  = KeyProducts and KeyProducts.KeysByProductId and KeyProducts.KeysByProductId[productId]

	if not coinsToAward and not keysToAward then
		-- Not one of our products – another ProcessReceipt handler may
		-- handle it if you add one later. Return NotProcessedYet so Roblox
		-- retries and the correct handler can pick it up (or it times out).
		warn("[CoinShopReceipt] Unknown product ID:", productId, "– skipping")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2) Check for duplicate receipt
	if isReceiptProcessed(receiptId) then
		print("[CoinShopReceipt] Receipt already processed:", receiptId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 3) Find the player in the server
	local playerObj = Players:GetPlayerByUserId(playerId)
	if not playerObj then
		-- Player left before we could grant. Return NotProcessedYet so
		-- Roblox re-delivers the receipt when they rejoin.
		warn("[CoinShopReceipt] Player", playerId, "not in server – will retry later")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 4) Award currency via CurrencyService
	if not CurrencyService then
		warn("[CoinShopReceipt] CurrencyService unavailable – cannot award currency")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if coinsToAward then
		local awardOk, awardErr = pcall(function()
			CurrencyService:AddCoins(playerObj, coinsToAward, "purchase")
		end)
		if not awardOk then
			warn("[CoinShopReceipt] AddCoins failed for", playerObj.Name, ":", tostring(awardErr))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	if keysToAward then
		local awardOk, awardErr = pcall(function()
			CurrencyService:AddKeys(playerObj, keysToAward, "purchase")
		end)
		if not awardOk then
			warn("[CoinShopReceipt] AddKeys failed for", playerObj.Name, ":", tostring(awardErr))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	-- 5) Save immediately so the balance is persisted
	pcall(function()
		CurrencyService:SaveForPlayer(playerObj)
	end)

	-- 6) Mark receipt as processed
	local awardedAmount = coinsToAward or keysToAward
	local awardedType = coinsToAward and "coins" or "keys"
	markReceiptProcessed(receiptId, playerId, productId, awardedAmount)

	-- 7) Track Robux spent for achievements
	local robuxPrice = nil
	if coinsToAward and CoinProducts and CoinProducts.PriceByProductId then
		robuxPrice = CoinProducts.PriceByProductId[productId]
	elseif keysToAward and KeyProducts and KeyProducts.PriceByProductId then
		robuxPrice = KeyProducts.PriceByProductId[productId]
	end
	if robuxPrice and robuxPrice > 0 then
		task.spawn(function()
			local achSvc = getAchievementService()
			if achSvc then
				achSvc:IncrementStat(playerObj, "totalRobuxSpent", robuxPrice)
			end
		end)
	end

	print("[CoinShopReceipt] Awarded", awardedAmount, awardedType, "to", playerObj.Name,
		"(receipt:", receiptId, ")")

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--------------------------------------------------------------------------------
-- Register the callback
--------------------------------------------------------------------------------
MarketplaceService.ProcessReceipt = processReceipt
print("[CoinShopReceipt] ProcessReceipt handler registered")
