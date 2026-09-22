-- Run with the Luau CLI: luau tests/market.spec.luau
local Config = require("../src/ReplicatedStorage/MarketConfig")
local Ledger = require("../src/ServerScriptService/MarketPurchaseLedger")
local function rng(seed)
    return {
        NextNumber = function(self)
            seed = (seed * 16807) % 2147483647
            return (seed - 1) / 2147483646
        end,
        NextInteger = function(self, minimum, maximum)
            return minimum + math.floor(self:NextNumber() * (maximum - minimum + 1))
        end,
    }
end
assert(Config.RoundPrice(148) == 150)
assert(Config.RoundPrice(133) == 135)
assert(Config.RoundPrice(4609) == 4610)
assert(Config.RoundPrice(146) == 145)
assert(Config.GetPrice("Uncommon",100) == 300)
assert(Config.GetPrice("Rare",100) == 1000)
assert(Config.GetPrice("Epic",100) == 5000)
assert(Config.GetPrice("Legendary",100) == 10000)
local pools = {}
for rarity in pairs(Config.BasePrices) do
    pools[rarity] = { { weapon = "Z Bow", category = "Ranged" }, { weapon = "A Sword", category = "Melee" } }
end
assert(Config.GetCycle(1199.99) == 0)
assert(Config.GetCycle(1200) == 1)
assert(Config.GetCycle(2400) == 2)
assert(Config.GetPrice("Legendary",200) == 40000)
assert(Config.GetPrice("Legendary",150) == 17500)
assert(Config.GetPrice("Legendary",250) == 40000)
assert(Config.GetPrice("Legendary",200,true) == 76050)
assert(Config.GetPrice("Legendary",150,true) == 33865)
assert(Config.GetPrice("Common",200,true) == 1350)
assert(Config.GetPrice("Legendary",149,true) == Config.RoundPrice(Config.BasePrices.Legendary * (1 + 3 * (9 ^ .49 - 1) / 8) * 1.25 + 200))
assert(Config.GetPrice("Common",100) == 40)
assert(Config.GetPrice("Common",80,true) == 250)
for rarity, base in pairs(Config.BasePrices) do
    local previous = 0
    for size=80,200 do
        local price=Config.GetPrice(rarity,size)
        assert(price>=previous and price%5==0 and price<=base*4)
        if size<=100 then assert(price==base) end
        previous=price
    end
end
local enchants={{name="Fiery"},{name="Icy"},{name="Void"}}
local a=Config.GenerateOffers(10,pools,rng(10),enchants)
local b=Config.GenerateOffers(10,pools,rng(10),enchants)
for slot=1,3 do
    for key,value in pairs(a[slot]) do assert(b[slot][key]==value, "Shared offer mismatch") end
end
local seen, tiers, rarities = {}, {}, {}
local legendaryKing, exact200, enchanted = 0,0,0
local bigBySlot={0,0,0}
local enchantedBySlot={0,0,0}
local normalBySlot={0,0,0}
local kingBySlot={0,0,0}
local random=rng(198321)
local samples=100000
for cycle=1,samples do
    local offers=Config.GenerateOffers(cycle,pools,random,enchants)
    assert(#offers==3)
    assert(offers[1].Rarity=="Common")
    assert(offers[2].Rarity=="Uncommon" or offers[2].Rarity=="Rare")
    assert(offers[3].Rarity=="Rare" or offers[3].Rarity=="Epic" or offers[3].Rarity=="Legendary")
    for slot,offer in ipairs(offers) do
        assert(offer.SizePercent>=80 and offer.SizePercent<=200 and offer.SizePercent%1==0)
        assert(offer.CoinPrice==Config.GetPrice(offer.Rarity,offer.SizePercent,offer.EnchantName~=""))
        if offer.SizePercent>110 then bigBySlot[slot]+=1 end
        if offer.SizeTier=="Normal" then normalBySlot[slot]+=1 end
        if offer.SizeTier=="King" then kingBySlot[slot]+=1 end
        if offer.EnchantName~="" then enchanted+=1; enchantedBySlot[slot]+=1 end
        seen[offer.SizePercent]=(seen[offer.SizePercent] or 0)+1
        tiers[offer.SizeTier]=(tiers[offer.SizeTier] or 0)+1
    end
    local third=offers[3]
    rarities[third.Rarity]=(rarities[third.Rarity] or 0)+1
    if third.Rarity=="Legendary" and third.SizeTier=="King" then legendaryKing+=1 end
    if third.Rarity=="Legendary" and third.SizePercent==200 then exact200+=1 end
end
for size=80,200 do assert(seen[size], "Unreachable size") end
assert(seen[100]>seen[90] and seen[100]>seen[110])
assert(math.abs(bigBySlot[1]/samples-.80)<.01)
assert(math.abs(normalBySlot[1]/samples-.18)<.01)
assert(math.abs(kingBySlot[1]/samples-.10)<.01)
for slot=2,3 do
    assert(math.abs(bigBySlot[slot]/samples-.15)<.01)
    assert(math.abs(normalBySlot[slot]/samples-.70)<.01)
    assert(math.abs(kingBySlot[slot]/samples-.01)<.003)
end
for slot=1,3 do assert(math.abs(enchantedBySlot[slot]/samples-.25)<.01) end
assert(math.abs(rarities.Legendary/samples-.05)<.005)
local usage=Ledger.Reserve(nil,10,"1","first")
assert(usage.slots["1"]=="first")
assert(Ledger.Reserve(usage,10,"1","first").slots["1"]=="first", "Retry not idempotent")
assert(Ledger.Reserve(usage,10,"1","otherServer").slots["1"]=="first", "Duplicate purchase accepted")
assert(Ledger.Release(usage,10,"1","otherServer").slots["1"]=="first", "Foreign rollback accepted")
assert(Ledger.Reserve(usage,9,"2","stale").slots["2"]==nil, "Stale cycle replaced current stock")
assert(Ledger.Reserve(nil,10,"1","secondPlayer").slots["1"]=="secondPlayer", "Stock not per player")
usage=Ledger.Reserve(usage,10,"2","secondSlot")
usage=Ledger.Release(usage,10,"2","secondSlot")
assert(usage.slots["2"]==nil and usage.slots["1"]=="first")
usage=Ledger.Reserve(usage,11,"1","newCycle")
assert(usage.cycle==11 and usage.slots["1"]=="newCycle" and usage.slots["2"]==nil)
local potionPools={
    {{Id="health_potion",DisplayName="Health Potion",PriceCoins=50,PurchaseQuantity=3}},
    {{Id="coins_2x",DisplayName="Flask of Wealth",PriceCoins=150}},
    {{Id="power_elixir",DisplayName="Power Elixir",PriceCoins=300}},
}
local stocksSeen={}
for cycle=1,1000 do
    local potions=Config.GeneratePotionOffers(cycle,potionPools,rng(cycle*7919))
    local duplicate=Config.GeneratePotionOffers(cycle,potionPools,rng(cycle*7919))
    for slot=1,3 do
        local offer=potions[slot]
        assert(offer.CoinPrice==potionPools[slot][1].PriceCoins)
        assert(offer.ItemId==potionPools[slot][1].Id)
        assert(offer.Stock==duplicate[slot].Stock)
        if slot==1 then assert(offer.Stock==5 and offer.Quantity==3)
        else assert(offer.Stock>=1 and offer.Stock<=3);stocksSeen[offer.Stock]=true end
    end
end
assert(stocksSeen[1] and stocksSeen[2] and stocksSeen[3])
for limit=1,5 do
    local stock=Ledger.Reserve(nil,10,"1","weapon")
    for index=1,limit do
        local token="potion"..index
        stock=Ledger.ReserveStock(stock,10,"p1:",limit,token)
        assert(stock.slots["p1:"..index]==token)
        stock=Ledger.ReserveStock(stock,10,"p1:",limit,token)
        assert(stock.slots["p1:"..(index+1)]==nil,"Datastore retry consumed extra stock")
    end
    stock=Ledger.ReserveStock(stock,10,"p1:",limit,"extra")
    assert(stock.slots["p1:"..(limit+1)]==nil)
    assert(stock.slots["1"]=="weapon")
    stock=Ledger.Release(stock,10,"p1:1","potion1")
    stock=Ledger.ReserveStock(stock,10,"p1:",limit,"retry")
    assert(stock.slots["p1:1"]=="retry")
end
print(string.format("PASS: %d weapon offers; enchanted %.2f%%; larger sizes slot 1 %.2f%%, slot 2 %.2f%%, slot 3 %.2f%%; potion stock/ledger/prices/boundaries passed",
    samples*3,enchanted/(samples*3)*100,bigBySlot[1]/samples*100,bigBySlot[2]/samples*100,bigBySlot[3]/samples*100))
