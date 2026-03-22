--------------------------------------------------------------------------------
-- CrateService.lua  –  Server module: validates purchases, rolls loot, grants
--
-- Flow:  Client → OpenCrate RemoteFunction → validate funds → weighted roll
--        → deduct coins → WeaponInstanceService:CreateInstance → return result
--------------------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local CrateConfig = require(ReplicatedStorage:WaitForChild("CrateConfig"))

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
--------------------------------------------------------------------------------
local function rollWeapon(crateDef)
    local pool = crateDef.pool
    if not pool or #pool == 0 then return nil end

    -- Build weight table: each entry gets the weight of its rarity
    local entries = {}
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        local rarityDef = CrateConfig.Rarities[entry.rarity]
        local w = (rarityDef and rarityDef.weight) or 0
        if w > 0 then
            totalWeight = totalWeight + w
            table.insert(entries, { entry = entry, cumulative = totalWeight })
        end
    end

    if totalWeight == 0 or #entries == 0 then
        -- Fallback: pick uniformly from whole pool
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
--
-- Returns:  success, resultData
--   resultData = { instanceId, weaponName, rarity, category, newBalance }
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

    -- Check balance
    local balance = cs:GetCoins(player)
    local price = crateDef.price or 0
    if balance < price then
        return false, "Not enough coins"
    end

    -- Roll weapon
    local rolled = rollWeapon(crateDef)
    if not rolled then
        return false, "Empty pool"
    end

    -- Deduct coins
    cs:SetCoins(player, balance - price)

    -- Create weapon instance
    local instanceData = wis:CreateInstance(
        player,
        rolled.weapon,
        rolled.rarity,
        crateDef.category,
        crateId
    )

    if not instanceData then
        -- Refund on failure
        cs:SetCoins(player, balance)
        return false, "Failed to create instance"
    end

    local newBalance = cs:GetCoins(player)

    return true, {
        instanceId  = instanceData.instanceId,
        weaponName  = instanceData.weaponName,
        rarity      = instanceData.rarity,
        category    = instanceData.category,
        newBalance  = newBalance,
    }
end

--------------------------------------------------------------------------------
-- GET POOL INFO  (for client display of drop chances)
--------------------------------------------------------------------------------
function CrateService:GetPoolInfo(crateId)
    local crateDef = CrateConfig.Crates[crateId]
    if not crateDef then return nil end

    local totalWeight = 0
    for _, entry in ipairs(crateDef.pool) do
        local rarityDef = CrateConfig.Rarities[entry.rarity]
        totalWeight = totalWeight + ((rarityDef and rarityDef.weight) or 0)
    end

    local info = {}
    for _, entry in ipairs(crateDef.pool) do
        local rarityDef = CrateConfig.Rarities[entry.rarity]
        local w = (rarityDef and rarityDef.weight) or 0
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
