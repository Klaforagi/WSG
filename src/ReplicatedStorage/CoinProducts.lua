-- CoinProducts.lua  (ReplicatedStorage)
-- Shared config for Robux coin packs using Developer Products.
-- ┌──────────────────────────────────────────────────────────────────┐
-- │  REPLACE the ProductId values below with your real Developer    │
-- │  Product IDs from the Roblox Creator Dashboard before going    │
-- │  live.  The placeholder IDs (0) will print a warning in Studio │
-- │  and skip the purchase prompt.                                  │
-- └──────────────────────────────────────────────────────────────────┘

local CoinProducts = {}

----------------------------------------------------------------------
-- Developer Product IDs  ← REPLACE THESE WITH REAL IDS
----------------------------------------------------------------------
CoinProducts.SMALL_COIN_PRODUCT_ID  = 0   -- ← Replace with real ID
CoinProducts.MEDIUM_COIN_PRODUCT_ID = 0   -- ← Replace with real ID
CoinProducts.LARGE_COIN_PRODUCT_ID  = 0   -- ← Replace with real ID
CoinProducts.ULTRA_COIN_PRODUCT_ID  = 0   -- ← Replace with real ID

----------------------------------------------------------------------
-- Robux prices displayed in the UI  ← UPDATE to match your Creator Dashboard
----------------------------------------------------------------------
CoinProducts.SMALL_PACK_PRICE  = 49     -- ← Robux price for Small Pack
CoinProducts.MEDIUM_PACK_PRICE = 99     -- ← Robux price for Medium Pack
CoinProducts.LARGE_PACK_PRICE  = 449    -- ← Robux price for Large Pack
CoinProducts.ULTRA_PACK_PRICE  = 1000   -- ← Robux price for Ultra Pack

----------------------------------------------------------------------
-- Pack definitions (order = display order in the popup)
----------------------------------------------------------------------
CoinProducts.Packs = {
	{
		Name       = "200 Coin Pack",
		Coins      = 200,
		ProductId  = CoinProducts.SMALL_COIN_PRODUCT_ID,
		Price      = CoinProducts.SMALL_PACK_PRICE,
		BestValue  = false,
	},
	{
		Name       = "450 Coin Pack",
		Coins      = 450,
		ProductId  = CoinProducts.MEDIUM_COIN_PRODUCT_ID,
		Price      = CoinProducts.MEDIUM_PACK_PRICE,
		BestValue  = false,
	},
	{
		Name       = "3,000 Coin Pack",
		Coins      = 3000,
		ProductId  = CoinProducts.LARGE_COIN_PRODUCT_ID,
		Price      = CoinProducts.LARGE_PACK_PRICE,
		BestValue  = false,
	},
	{
		Name       = "7,500 Coin Pack",
		Coins      = 7500,
		ProductId  = CoinProducts.ULTRA_COIN_PRODUCT_ID,
		Price      = CoinProducts.ULTRA_PACK_PRICE,
		BestValue  = true,
	},
}

----------------------------------------------------------------------
-- Lookup: ProductId → Coins  (used by the server ProcessReceipt)
----------------------------------------------------------------------
CoinProducts.CoinsByProductId = {}
for _, pack in ipairs(CoinProducts.Packs) do
	if pack.ProductId and pack.ProductId > 0 then
		CoinProducts.CoinsByProductId[pack.ProductId] = pack.Coins
	end
end

----------------------------------------------------------------------
-- Lookup: ProductId → Robux price  (used by CoinShopReceipt for
-- tracking cumulative Robux spent toward achievements)
----------------------------------------------------------------------
CoinProducts.PriceByProductId = {}
for _, pack in ipairs(CoinProducts.Packs) do
	if pack.ProductId and pack.ProductId > 0 and pack.Price then
		CoinProducts.PriceByProductId[pack.ProductId] = pack.Price
	end
end

return CoinProducts
