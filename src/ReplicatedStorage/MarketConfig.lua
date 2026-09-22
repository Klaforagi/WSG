-- Shared market rules. These do not change crate rolls or weapon combat stats.
local MarketConfig = {}
MarketConfig.RefreshSeconds = 20 * 60
MarketConfig.Version = 2
MarketConfig.EnchantChance = 0.25
MarketConfig.SlotRarities = {
    { { name = "Common", weight = 100 } },
    { { name = "Uncommon", weight = 75 }, { name = "Rare", weight = 25 } },
    { { name = "Rare", weight = 75 }, { name = "Epic", weight = 20 }, { name = "Legendary", weight = 5 } },
}
MarketConfig.SizeTiers = {
    { name = "Tiny", min = 80, max = 89, weight = 15 },
    { name = "Normal", min = 90, max = 110, weight = 70 },
    { name = "Large", min = 111, max = 149, weight = 10 },
    { name = "Giant", min = 150, max = 189, weight = 4 },
    { name = "King", min = 190, max = 200, weight = 1 },
}
MarketConfig.FirstSlotSizeTiers = {
    { name = "Tiny", min = 80, max = 89, weight = 2 },
    { name = "Normal", min = 90, max = 110, weight = 18 },
    { name = "Large", min = 111, max = 149, weight = 40 },
    { name = "Giant", min = 150, max = 189, weight = 30 },
    { name = "King", min = 190, max = 200, weight = 10 },
}
MarketConfig.BasePrices = { Common = 40, Uncommon = 300, Rare = 1000, Epic = 5000, Legendary = 10000 }

function MarketConfig.RoundPrice(price)
    return math.floor(price / 5 + 0.5) * 5
end

local function weightedPick(rng, entries)
    local total = 0
    for _, entry in ipairs(entries) do total += entry.weight end
    local roll = rng:NextNumber() * total
    for _, entry in ipairs(entries) do
        roll -= entry.weight
        if roll < 0 then return entry end
    end
    return entries[#entries]
end

function MarketConfig.GetCycle(now)
    return math.floor(now / MarketConfig.RefreshSeconds)
end

function MarketConfig.GetPrice(rarity, size, enchanted)
    local base = assert(MarketConfig.BasePrices[rarity], "Unknown market rarity")
    local progress = math.clamp((size - 100) / 100, 0, 1)
    local price = base * (1 + 3 * (9 ^ progress - 1) / 8)
    if enchanted then
        price = price * 1.25 + 200
        if size >= 150 then price = (price + 500) * 1.5 end
    end
    return MarketConfig.RoundPrice(price)
end

function MarketConfig.GenerateOffers(cycle, pools, rng, enchants)
    rng = rng or Random.new(cycle * 10007 + MarketConfig.Version * 7919)
    local offers = {}
    for slot, rarities in ipairs(MarketConfig.SlotRarities) do
        local rarity = weightedPick(rng, rarities).name
        local pool = table.clone(assert(pools[rarity], "Missing market weapon pool"))
        table.sort(pool, function(a, b) return a.weapon < b.weapon end)
        assert(#pool > 0, "Empty market weapon pool")
        local weapon = pool[rng:NextInteger(1, #pool)]
        local tier = weightedPick(rng, slot == 1 and MarketConfig.FirstSlotSizeTiers or MarketConfig.SizeTiers)
        -- Triangular distribution with its peak at 100%, rather than flat normal sizes.
        local size = tier.name == "Normal" and (90 + rng:NextInteger(0, 10) + rng:NextInteger(0, 10))
            or rng:NextInteger(tier.min, tier.max)
        local enchantName = ""
        if rng:NextNumber() < MarketConfig.EnchantChance and enchants and #enchants > 0 then
            enchantName = enchants[rng:NextInteger(1, #enchants)].name
        end
        offers[slot] = {
            Slot = slot, Id = tostring(cycle) .. ":" .. slot, Category = "Weapon",
            WeaponName = weapon.weapon, WeaponCategory = weapon.category,
            DisplayName = weapon.weapon, Rarity = rarity, SizePercent = size, SizeTier = tier.name,
            EnchantName = enchantName,
            CoinPrice = MarketConfig.GetPrice(rarity, size, enchantName ~= ""),
        }
    end
    return offers
end

function MarketConfig.GeneratePotionOffers(cycle, pools, rng)
    rng = rng or Random.new(cycle * 10009 + MarketConfig.Version * 7907)
    local offers = {}
    for slot = 1, 3 do
        local pool = table.clone(pools[slot])
        table.sort(pool, function(a,b) return a.Id < b.Id end)
        assert(#pool > 0, "Empty market potion pool")
        local def = pool[rng:NextInteger(1,#pool)]
        offers[slot] = {
            Slot = slot, Id = tostring(cycle) .. ":p" .. slot, Category = "Potion",
            ItemId = def.Id, PotionKind = slot == 1 and "Battle" or "Boost",
            DisplayName = def.DisplayName, CoinPrice = def.PriceCoins,
            Stock = slot == 1 and 5 or rng:NextInteger(1,3),
            Quantity = def.PurchaseQuantity or 1, IconKey = def.IconKey,
            Description = def.DetailText or def.Description or "",
        }
    end
    return offers
end

return MarketConfig
