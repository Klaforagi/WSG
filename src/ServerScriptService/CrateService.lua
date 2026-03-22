--------------------------------------------------------------------------------
-- CrateService.lua  –  Server module: validates purchases, rolls loot, grants
--
-- Flow:  Client → OpenCrate RemoteFunction → validate funds → weighted roll
--        → deduct currency → WeaponInstanceService:CreateInstance → return result
--
-- Generic handler for all crate types (MeleeCrate, RangedCrate,
-- PremiumMeleeCrate, PremiumRangedCrate).  Reads currency type, cost,
-- rarity weights, and weapon pool from CrateConfig per crate.
--------------------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local CrateConfig      = require(ReplicatedStorage:WaitForChild("CrateConfig"))
local SizeRollService  = require(ReplicatedStorage:WaitForChild("SizeRollService"))

-- Lazy-loaded server modules
local CurrencyService       = nil
local WeaponInstanceService = nil

local function ensureCurrencyService()
    if CurrencyService then return CurrencyService end
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
    return CurrencyService
end

local function ensureWeaponInstanceService()
    if WeaponInstanceService then return WeaponInstanceService end
    local mod = ServerScriptService:FindFirstChild("WeaponInstanceService")
    if mod and mod:IsA("ModuleScript") then
        WeaponInstanceService = require(mod)
    end
    return WeaponInstanceService
end

local CrateService = {}

--------------------------------------------------------------------------------
-- WEIGHTED RANDOM ROLL
-- PREMIUM CRATE / KEY SYSTEM  – uses per-crate rarities table if present,
-- otherwise falls back to global CrateConfig.Rarities[rarity].weight.
--------------------------------------------------------------------------------
local function rollWeapon(crateDef)
    local pool = crateDef.pool
    if not pool or #pool == 0 then return nil end

    -- Build weight table: each entry gets the weight of its rarity
    local entries = {}
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        -- PREMIUM CRATE / KEY SYSTEM  – prefer per-crate rarity weight
        local w = 0
        if crateDef.rarities and crateDef.rarities[entry.rarity] then
            w = crateDef.rarities[entry.rarity]
        else
            local rarityDef = CrateConfig.Rarities[entry.rarity]
            w = (rarityDef and rarityDef.weight) or 0
        end
        if w > 0 then
            totalWeight = totalWeight + w
            table.insert(entries, { entry = entry, cumulative = totalWeight })
        end
    end

    if totalWeight == 0 or #entries == 0 then
        -- Fallback: pick uniformly from whole pool
        warn("[CrateService] rollWeapon: totalWeight=0, falling back to uniform pick")
        return pool[math.random(1, #pool)]
    end

    local roll = math.random() * totalWeight
    for _, e in ipairs(entries) do
        if roll <= e.cumulative then
            return e.entry
        end
    end
    -- Shouldn't reach here, but safety
    return entries[#entries].entry
end

--------------------------------------------------------------------------------
-- OPEN CRATE  (called by RemoteFunction handler)
-- PREMIUM CRATE / KEY SYSTEM  – generic handler for any crate type.
-- Reads currency type from crateDef.currency ("Coins" or "Keys").
--
-- Returns:  success, resultData
--   resultData = { instanceId, weaponName, rarity, category, newBalance, newKeyBalance, crateType }
--   or errorString on failure
--------------------------------------------------------------------------------
function CrateService:OpenCrate(player, crateId)
    if type(crateId) ~= "string" then
        return false, "Invalid crate id"
    end

    local crateDef = CrateConfig.Crates[crateId]
    if not crateDef then
        return false, "Unknown crate"
    end

    local cs = ensureCurrencyService()
    if not cs then
        return false, "Currency service unavailable"
    end

    local wis = ensureWeaponInstanceService()
    if not wis then
        return false, "Instance service unavailable"
    end

    -- PREMIUM CRATE / KEY SYSTEM  – determine currency and validate
    local currencyType = crateDef.currency or "Coins"
    local price = crateDef.cost or crateDef.price or 0
    local balance

    print(string.format("[CrateService] %s attempting to open %s (currency=%s, cost=%d)",
        tostring(player.Name), crateId, currencyType, price))

    if currencyType == "Keys" then
        balance = cs:GetKeys(player)
        print(string.format("[CrateService] Key check: has %d, needs %d", balance, price))
        if balance < price then
            print("[CrateService] DENIED – not enough Keys")
            return false, "Not enough Keys"
        end
    else
        balance = cs:GetCoins(player)
        print(string.format("[CrateService] Coin check: has %d, needs %d", balance, price))
        if balance < price then
            print("[CrateService] DENIED – not enough Coins")
            return false, "Not enough coins"
        end
    end

    -- Roll weapon
    local rolled = rollWeapon(crateDef)
    if not rolled then
        print("[CrateService] FAILED – empty pool for " .. crateId)
        return false, "Empty pool"
    end

    -- Roll weapon size (80–200%) using weighted tiers
    local sizePercent, sizeTier = SizeRollService.RollSize()

    print(string.format("[CrateService] Rolled: %s (%s) Size: %d%% [%s]", rolled.weapon, rolled.rarity, sizePercent, sizeTier))

    -- Deduct currency BEFORE granting (prevents duplication on disconnect)
    if currencyType == "Keys" then
        cs:SetKeys(player, balance - price)
    else
        cs:SetCoins(player, balance - price)
    end

    -- Determine category from rolled entry or crateDef
    local category = rolled.category or crateDef.category or "Melee"

    -- Create weapon instance with rolled size data
    local instanceData = wis:CreateInstance(
        player,
        rolled.weapon,
        rolled.rarity,
        category,
        crateId,
        sizePercent,
        sizeTier
    )

    if not instanceData then
        -- Refund on failure
        print("[CrateService] REFUND – CreateInstance failed")
        if currencyType == "Keys" then
            cs:SetKeys(player, balance)
        else
            cs:SetCoins(player, balance)
        end
        return false, "Failed to create instance"
    end

    print(string.format("[CrateService] SUCCESS – granted %s (%s) %d%% [%s] id=%s to %s",
        instanceData.weaponName, instanceData.rarity, sizePercent, sizeTier,
        instanceData.instanceId, tostring(player.Name)))

    local newCoinBalance = cs:GetCoins(player)
    local newKeyBalance  = cs:GetKeys(player)

    return true, {
        instanceId     = instanceData.instanceId,
        weaponName     = instanceData.weaponName,
        rarity         = instanceData.rarity,
        category       = instanceData.category,
        sizePercent    = instanceData.sizePercent,   -- SIZE ROLL SYSTEM
        sizeTier       = instanceData.sizeTier,      -- SIZE ROLL SYSTEM
        newBalance     = newCoinBalance,
        newKeyBalance  = newKeyBalance,    -- PREMIUM CRATE / KEY SYSTEM
        crateType      = crateId,          -- PREMIUM CRATE / KEY SYSTEM
    }
end

--------------------------------------------------------------------------------
-- GET POOL INFO  (for client display of drop chances)
-- PREMIUM CRATE / KEY SYSTEM  – uses per-crate rarities if available
--------------------------------------------------------------------------------
function CrateService:GetPoolInfo(crateId)
    local crateDef = CrateConfig.Crates[crateId]
    if not crateDef then return nil end

    local totalWeight = 0
    for _, entry in ipairs(crateDef.pool) do
        local w = 0
        if crateDef.rarities and crateDef.rarities[entry.rarity] then
            w = crateDef.rarities[entry.rarity]
        else
            local rarityDef = CrateConfig.Rarities[entry.rarity]
            w = (rarityDef and rarityDef.weight) or 0
        end
        totalWeight = totalWeight + w
    end

    local info = {}
    for _, entry in ipairs(crateDef.pool) do
        local w = 0
        if crateDef.rarities and crateDef.rarities[entry.rarity] then
            w = crateDef.rarities[entry.rarity]
        else
            local rarityDef = CrateConfig.Rarities[entry.rarity]
            w = (rarityDef and rarityDef.weight) or 0
        end
        local chance = (totalWeight > 0) and (w / totalWeight * 100) or 0
        table.insert(info, {
            weapon  = entry.weapon,
            rarity  = entry.rarity,
            chance  = math.floor(chance * 10 + 0.5) / 10, -- 1 decimal
        })
    end
    return info
end

return CrateService
