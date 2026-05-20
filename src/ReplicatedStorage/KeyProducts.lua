-- KeyProducts.lua  (ReplicatedStorage)
-- Shared config for Robux key packs using Developer Products.
-- ┌──────────────────────────────────────────────────────────────────┐
-- │  REPLACE the ProductId values below with your real Developer    │
-- │  Product IDs from the Roblox Creator Dashboard before going    │
-- │  live.  The placeholder IDs (0) will print a warning in Studio │
-- │  and skip the purchase prompt.                                  │
-- └──────────────────────────────────────────────────────────────────┘

local KeyProducts = {}

----------------------------------------------------------------------
-- Developer Product IDs  ← REPLACE THESE WITH REAL IDS
----------------------------------------------------------------------
KeyProducts.SMALL_KEY_PRODUCT_ID  = 0   -- ← Replace with real ID
KeyProducts.MEDIUM_KEY_PRODUCT_ID = 0   -- ← Replace with real ID
KeyProducts.LARGE_KEY_PRODUCT_ID  = 0   -- ← Replace with real ID

----------------------------------------------------------------------
-- Robux prices displayed in the UI  ← UPDATE to match your Creator Dashboard
----------------------------------------------------------------------
KeyProducts.SMALL_PACK_PRICE  = 99    -- ← Robux price for Small Pack
KeyProducts.MEDIUM_PACK_PRICE = 399   -- ← Robux price for Medium Pack
KeyProducts.LARGE_PACK_PRICE  = 1299  -- ← Robux price for Large Pack

----------------------------------------------------------------------
-- Pack definitions (order = display order in the popup)
----------------------------------------------------------------------
KeyProducts.Packs = {
	{
		Name       = "Single Key Pack",
		Keys       = 1,
		ProductId  = KeyProducts.SMALL_KEY_PRODUCT_ID,
		Price      = KeyProducts.SMALL_PACK_PRICE,
	},
	{
		Name       = "5 Key Pack",
		Keys       = 5,
		ProductId  = KeyProducts.MEDIUM_KEY_PRODUCT_ID,
		Price      = KeyProducts.MEDIUM_PACK_PRICE,
	},
	{
		Name       = "20 Key Pack",
		Keys       = 20,
		ProductId  = KeyProducts.LARGE_KEY_PRODUCT_ID,
		Price      = KeyProducts.LARGE_PACK_PRICE,
	},
}

----------------------------------------------------------------------
-- Lookup: ProductId → Keys  (used by the server ProcessReceipt)
----------------------------------------------------------------------
KeyProducts.KeysByProductId = {}
for _, pack in ipairs(KeyProducts.Packs) do
	if pack.ProductId and pack.ProductId > 0 then
		KeyProducts.KeysByProductId[pack.ProductId] = pack.Keys
	end
end

----------------------------------------------------------------------
-- Lookup: ProductId → Robux price  (used by receipt handler for
-- tracking cumulative Robux spent toward achievements)
----------------------------------------------------------------------
KeyProducts.PriceByProductId = {}
for _, pack in ipairs(KeyProducts.Packs) do
	if pack.ProductId and pack.ProductId > 0 and pack.Price then
		KeyProducts.PriceByProductId[pack.ProductId] = pack.Price
	end
end

return KeyProducts
