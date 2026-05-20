-- ShardProducts.lua  (ReplicatedStorage)
-- Shared config for Robux shard packs using Developer Products.

local ShardProducts = {}

----------------------------------------------------------------------
-- Developer Product IDs  ← REPLACE THESE WITH REAL IDS
----------------------------------------------------------------------
ShardProducts.SHARDS_250_PRODUCT_ID   = 0
ShardProducts.SHARDS_1000_PRODUCT_ID  = 0
ShardProducts.SHARDS_3000_PRODUCT_ID  = 0
ShardProducts.SHARDS_10000_PRODUCT_ID = 0

----------------------------------------------------------------------
-- Robux prices displayed in the UI
----------------------------------------------------------------------
ShardProducts.SHARDS_250_PRICE   = 99
ShardProducts.SHARDS_1000_PRICE  = 299
ShardProducts.SHARDS_3000_PRICE  = 699
ShardProducts.SHARDS_10000_PRICE = 1999

----------------------------------------------------------------------
-- Pack definitions (order = display order in the UI)
----------------------------------------------------------------------
ShardProducts.Packs = {
	{
		Name = "250 Shards",
		Shards = 250,
		ProductId = ShardProducts.SHARDS_250_PRODUCT_ID,
		Price = ShardProducts.SHARDS_250_PRICE,
	},
	{
		Name = "1,000 Shards",
		Shards = 1000,
		ProductId = ShardProducts.SHARDS_1000_PRODUCT_ID,
		Price = ShardProducts.SHARDS_1000_PRICE,
	},
	{
		Name = "3,000 Shards",
		Shards = 3000,
		ProductId = ShardProducts.SHARDS_3000_PRODUCT_ID,
		Price = ShardProducts.SHARDS_3000_PRICE,
	},
	{
		Name = "10,000 Shards",
		Shards = 10000,
		ProductId = ShardProducts.SHARDS_10000_PRODUCT_ID,
		Price = ShardProducts.SHARDS_10000_PRICE,
	},
}

----------------------------------------------------------------------
-- Lookup tables used by the server receipt handler
----------------------------------------------------------------------
ShardProducts.ShardsByProductId = {}
ShardProducts.PriceByProductId = {}
for _, pack in ipairs(ShardProducts.Packs) do
	if pack.ProductId and pack.ProductId > 0 then
		ShardProducts.ShardsByProductId[pack.ProductId] = pack.Shards
		ShardProducts.PriceByProductId[pack.ProductId] = pack.Price
	end
end

return ShardProducts