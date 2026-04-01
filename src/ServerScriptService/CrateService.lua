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

local CrateConfig       = require(ReplicatedStorage:WaitForChild("CrateConfig"))
local SizeRollService   = require(ReplicatedStorage:WaitForChild("SizeRollService"))
local WeaponPerkConfig  = require(ReplicatedStorage:WaitForChild("WeaponPerkConfig"))

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

local SalvageConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("SalvageConfig")
    if mod and mod:IsA("ModuleScript") then
        SalvageConfig = require(mod)
    end
end)

local CrateService = {}

-- Pending crate rewards: PendingRewards[player] = { weaponName, rarity, ... }
local PendingRewards = {}

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

    -- PERK SYSTEM: 20% chance to receive one elemental perk
    local perkName = WeaponPerkConfig.RollPerk() or ""

    print(string.format("[CrateService] Rolled: %s (%s) Size: %d%% [%s] Perk: %s",
        rolled.weapon, rolled.rarity, sizePercent, sizeTier, perkName ~= "" and perkName or "None"))

    -- Deduct currency BEFORE granting (prevents duplication on disconnect)
    if currencyType == "Keys" then
        cs:SetKeys(player, balance - price)
    else
        cs:SetCoins(player, balance - price)
    end

    -- Determine category from rolled entry or crateDef
    local category = rolled.category or crateDef.category or "Melee"

    -- Compute salvage value for display on the client popup
    local salvageValue = 0
    if SalvageConfig and SalvageConfig.GetValueForRarity then
        salvageValue = SalvageConfig.GetValueForRarity(rolled.rarity) or 0
    end

    -- Store as PENDING reward (weapon NOT yet in inventory)
    local pendingData = {
        weaponName  = rolled.weapon,
        rarity      = rolled.rarity,
        category    = category,
        source      = crateId,
        sizePercent = sizePercent,
        sizeTier    = sizeTier,
        perkName    = perkName,            -- PERK SYSTEM
        salvageValue = salvageValue,
        crateType   = crateId,
        timestamp   = tick(),
    }
    PendingRewards[player] = pendingData

    print(string.format("[CrateReward] Pending reward created for %s: %s (%s) %d%% [%s] Perk: %s",
        tostring(player.Name), rolled.weapon, rolled.rarity, sizePercent, sizeTier,
        perkName ~= "" and perkName or "None"))

    local newCoinBalance = cs:GetCoins(player)
    local newKeyBalance  = cs:GetKeys(player)

    return true, {
        weaponName     = rolled.weapon,
        rarity         = rolled.rarity,
        category       = category,
        sizePercent    = sizePercent,       -- SIZE ROLL SYSTEM
        sizeTier       = sizeTier,          -- SIZE ROLL SYSTEM
        perkName       = perkName,          -- PERK SYSTEM
        salvageValue   = salvageValue,
        isPending      = true,             -- signals client to show Keep/Salvage UI
        newBalance     = newCoinBalance,
        newKeyBalance  = newKeyBalance,     -- PREMIUM CRATE / KEY SYSTEM
        crateType      = crateId,           -- PREMIUM CRATE / KEY SYSTEM
    }
end

--------------------------------------------------------------------------------
-- FINALIZE: KEEP  –  player chose to keep the pending crate reward
-- Creates the weapon instance and clears the pending state.
-- Returns: success, resultData
--------------------------------------------------------------------------------
function CrateService:FinalizeCrateKeep(player)
    local pending = PendingRewards[player]
    if not pending then
        return false, "No pending reward"
    end

    local wis = ensureWeaponInstanceService()
    if not wis then
        return false, "Instance service unavailable"
    end

    -- Create weapon instance from pending data
    local instanceData = wis:CreateInstance(
        player,
        pending.weaponName,
        pending.rarity,
        pending.category,
        pending.source,
        pending.sizePercent,
        pending.sizeTier,
        pending.perkName             -- PERK SYSTEM
    )

    if not instanceData then
        return false, "Failed to create instance"
    end

    PendingRewards[player] = nil

    print(string.format("[CrateReward] Finalized keep: %s (%s) id=%s for %s",
        instanceData.weaponName, instanceData.rarity,
        instanceData.instanceId, tostring(player.Name)))

    return true, {
        instanceId  = instanceData.instanceId,
        weaponName  = instanceData.weaponName,
        rarity      = instanceData.rarity,
        category    = instanceData.category,
        sizePercent = instanceData.sizePercent,
        sizeTier    = instanceData.sizeTier,
        perkName    = instanceData.perkName,    -- PERK SYSTEM
    }
end

--------------------------------------------------------------------------------
-- FINALIZE: SALVAGE  –  player chose to salvage the pending crate reward
-- Does NOT create a weapon instance. Awards salvage currency directly.
-- Returns: success, resultData
--------------------------------------------------------------------------------
function CrateService:FinalizeCrateSalvage(player)
    local pending = PendingRewards[player]
    if not pending then
        return false, "No pending reward"
    end

    local cs = ensureCurrencyService()
    if not cs then
        return false, "Currency service unavailable"
    end

    local salvageValue = pending.salvageValue or 0
    if salvageValue <= 0 then
        -- Fallback: recalculate from config
        if SalvageConfig and SalvageConfig.GetValueForRarity then
            salvageValue = SalvageConfig.GetValueForRarity(pending.rarity) or 0
        end
    end

    if salvageValue <= 0 then
        return false, "No salvage value for this rarity"
    end

    -- Award salvage currency
    cs:AddSalvage(player, salvageValue)
    local newBalance = cs:GetSalvage(player)

    PendingRewards[player] = nil

    print(string.format("[CrateReward] Finalized salvage payout: %d for %s (%s) from %s",
        salvageValue, pending.weaponName, pending.rarity, tostring(player.Name)))

    return true, {
        weaponName   = pending.weaponName,
        rarity       = pending.rarity,
        awarded      = salvageValue,
        newBalance   = newBalance,
    }
end

--------------------------------------------------------------------------------
-- PENDING REWARD ACCESSORS
--------------------------------------------------------------------------------

function CrateService:GetPendingReward(player)
    return PendingRewards[player]
end

function CrateService:ClearPendingReward(player)
    PendingRewards[player] = nil
end

--- Auto-keep: grant pending reward on disconnect so items are never lost.
function CrateService:AutoKeepOnDisconnect(player)
    local pending = PendingRewards[player]
    if not pending then return end

    local wis = ensureWeaponInstanceService()
    if not wis then
        warn("[CrateReward] Cannot auto-keep for " .. tostring(player.Name) .. ": WIS unavailable")
        PendingRewards[player] = nil
        return
    end

    local instanceData = wis:CreateInstance(
        player,
        pending.weaponName,
        pending.rarity,
        pending.category,
        pending.source,
        pending.sizePercent,
        pending.sizeTier,
        pending.perkName             -- PERK SYSTEM
    )

    PendingRewards[player] = nil

    if instanceData then
        print(string.format("[CrateReward] Auto-kept on disconnect: %s (%s) for %s",
            pending.weaponName, pending.rarity, tostring(player.Name)))
    else
        warn("[CrateReward] Auto-keep CreateInstance failed for " .. tostring(player.Name))
    end
end

--------------------------------------------------------------------------------
-- ROLL AND GRANT  (no currency deduction — used by SalvageShopService)
-- Runs the same roll + size + grant pipeline as OpenCrate but skips payment.
-- Returns:  success, resultData
--------------------------------------------------------------------------------
function CrateService:RollAndGrant(player, crateId)
    if type(crateId) ~= "string" then
        return false, "Invalid crate id"
    end

    local crateDef = CrateConfig.Crates[crateId]
    if not crateDef then
        return false, "Unknown crate"
    end

    local wis = ensureWeaponInstanceService()
    if not wis then
        return false, "Instance service unavailable"
    end

    -- Roll weapon (same weighted logic as OpenCrate)
    local rolled = rollWeapon(crateDef)
    if not rolled then
        print("[CrateService] RollAndGrant FAILED – empty pool for " .. crateId)
        return false, "Empty pool"
    end

    -- Roll weapon size
    local sizePercent, sizeTier = SizeRollService.RollSize()

    -- PERK SYSTEM: 20% chance to receive one elemental perk
    local perkName = WeaponPerkConfig.RollPerk() or ""

    print(string.format("[CrateService] RollAndGrant: %s (%s) Size: %d%% [%s] Perk: %s",
        rolled.weapon, rolled.rarity, sizePercent, sizeTier, perkName ~= "" and perkName or "None"))

    local category = rolled.category or crateDef.category or "Melee"

    local instanceData = wis:CreateInstance(
        player,
        rolled.weapon,
        rolled.rarity,
        category,
        crateId,
        sizePercent,
        sizeTier,
        perkName              -- PERK SYSTEM
    )

    if not instanceData then
        print("[CrateService] RollAndGrant FAILED – CreateInstance failed")
        return false, "Failed to create instance"
    end

    print(string.format("[CrateService] RollAndGrant SUCCESS – granted %s (%s) %d%% [%s] id=%s to %s",
        instanceData.weaponName, instanceData.rarity, sizePercent, sizeTier,
        instanceData.instanceId, tostring(player.Name)))

    return true, {
        instanceId  = instanceData.instanceId,
        weaponName  = instanceData.weaponName,
        rarity      = instanceData.rarity,
        category    = instanceData.category,
        sizePercent = instanceData.sizePercent,
        sizeTier    = instanceData.sizeTier,
        perkName    = instanceData.perkName,    -- PERK SYSTEM
        crateType   = crateId,
    }
end

--------------------------------------------------------------------------------
-- ROLL AND PEND  (no currency deduction, no grant — stores pending reward)
-- Same roll pipeline as RollAndGrant but stores result in PendingRewards
-- instead of creating a weapon instance. Used by SalvageShopService crates
-- so they share the same Keep/Salvage decision UI as gold crates.
-- Returns:  success, resultData (with isPending=true + salvageValue)
--------------------------------------------------------------------------------
function CrateService:RollAndPend(player, crateId)
    if type(crateId) ~= "string" then
        return false, "Invalid crate id"
    end

    local crateDef = CrateConfig.Crates[crateId]
    if not crateDef then
        return false, "Unknown crate"
    end

    -- Roll weapon (same weighted logic as OpenCrate)
    local rolled = rollWeapon(crateDef)
    if not rolled then
        print("[CrateService] RollAndPend FAILED – empty pool for " .. crateId)
        return false, "Empty pool"
    end

    -- Roll weapon size
    local sizePercent, sizeTier = SizeRollService.RollSize()

    -- PERK SYSTEM: 20% chance to receive one elemental perk
    local perkName = WeaponPerkConfig.RollPerk() or ""

    local category = rolled.category or crateDef.category or "Melee"

    -- Compute salvage value for display on the client popup
    local salvageValue = 0
    if SalvageConfig and SalvageConfig.GetValueForRarity then
        salvageValue = SalvageConfig.GetValueForRarity(rolled.rarity) or 0
    end

    -- Store as PENDING reward (weapon NOT yet in inventory)
    local pendingData = {
        weaponName   = rolled.weapon,
        rarity       = rolled.rarity,
        category     = category,
        source       = crateId,
        sizePercent  = sizePercent,
        sizeTier     = sizeTier,
        perkName     = perkName,           -- PERK SYSTEM
        salvageValue = salvageValue,
        crateType    = crateId,
        timestamp    = tick(),
    }
    PendingRewards[player] = pendingData

    print(string.format("[CrateReward] Pending reward created (salvage crate) for %s: %s (%s) %d%% [%s] Perk: %s",
        tostring(player.Name), rolled.weapon, rolled.rarity, sizePercent, sizeTier,
        perkName ~= "" and perkName or "None"))

    return true, {
        weaponName   = rolled.weapon,
        rarity       = rolled.rarity,
        category     = category,
        sizePercent  = sizePercent,
        sizeTier     = sizeTier,
        perkName     = perkName,         -- PERK SYSTEM
        salvageValue = salvageValue,
        isPending    = true,
        crateType    = crateId,
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
