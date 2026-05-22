-- SkinProducts.lua  (ReplicatedStorage)
-- Shared config for permanent skin developer products.
--
-- Product IDs live in SkinDefinitions so the standalone skins stall can read
-- the same metadata as the receipt handler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinDefinitions = require(ReplicatedStorage:WaitForChild("SkinDefinitions"))

local SkinProducts = {}

SkinProducts.Products = {}
SkinProducts.SkinIdByProductId = {}
SkinProducts.PriceByProductId = {}

for _, def in ipairs(SkinDefinitions.GetStallSkins()) do
	if not def.IsDefault then
		local productId = SkinDefinitions.GetRobuxProductId(def)
		local price = tonumber(def.RobuxPrice)

		table.insert(SkinProducts.Products, {
			SkinId = def.Id,
			DisplayName = def.DisplayName,
			ProductId = productId,
			Price = price,
		})

		if productId > 0 then
			SkinProducts.SkinIdByProductId[productId] = def.Id
			if price and price > 0 then
				SkinProducts.PriceByProductId[productId] = price
			end
		end
	end
end

return SkinProducts