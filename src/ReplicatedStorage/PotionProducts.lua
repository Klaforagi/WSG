local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local BoostConfig = require(ReplicatedStorage:WaitForChild("BoostConfig"))

local PotionProducts = {}

PotionProducts.Products = {}
PotionProducts.ProductById = {}
PotionProducts.PriceByProductId = {}

local function addProduct(kind, def)
	local productId = math.max(0, math.floor(tonumber(def and def.RobuxProductId) or 0))
	local price = math.max(0, math.floor(tonumber(def and def.PriceRobux) or 0))

	local product = {
		Kind = kind,
		ItemId = def.Id,
		DisplayName = def.DisplayName,
		ProductId = productId,
		Price = price,
	}
	table.insert(PotionProducts.Products, product)

	if productId > 0 then
		PotionProducts.ProductById[productId] = product
		if price > 0 then
			PotionProducts.PriceByProductId[productId] = price
		end
	end
end

for _, potionDef in ipairs(PotionConfig.GetStallPotions()) do
	if potionDef.Purchasable == true and potionDef.RemovedFromShop ~= true and potionDef.Hidden ~= true then
		addProduct("potion", potionDef)
	end
end

for _, boostDef in ipairs(BoostConfig.GetPotionsStallBoosts()) do
	if boostDef.InstantUse ~= true and boostDef.Purchasable ~= false and boostDef.RemovedFromShop ~= true and boostDef.Hidden ~= true then
		addProduct("boost", boostDef)
	end
end

return PotionProducts