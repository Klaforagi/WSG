--------------------------------------------------------------------------------
-- SalvageService.lua  –  Server-only salvage logic module
--
-- Validates salvage eligibility, calculates values, removes items, and awards
-- Salvage currency.  All salvage operations MUST go through this module.
--
-- Dependencies:
--   WeaponInstanceService (item inventory)
--   CurrencyService       (salvage currency balance)
--   SalvageConfig         (rarity values + eligibility rules)
--   IsInstanceEquipped    (BindableFunction from Loadout.server.lua)
--------------------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SalvageService = {}

-- Lazy-loaded dependencies (resolved on first use to avoid circular require)
local _WeaponInstanceService
local _CurrencyService
local _SalvageConfig

local function getWeaponInstanceService()
    if not _WeaponInstanceService then
        local mod = ServerScriptService:FindFirstChild("WeaponInstanceService")
        if mod and mod:IsA("ModuleScript") then
            _WeaponInstanceService = require(mod)
        end
    end
    return _WeaponInstanceService
end

local function getCurrencyService()
    if not _CurrencyService then
        local mod = ServerScriptService:FindFirstChild("CurrencyService")
        if mod and mod:IsA("ModuleScript") then
            _CurrencyService = require(mod)
        end
    end
    return _CurrencyService
end

local function getSalvageConfig()
    if not _SalvageConfig then
        local mod = ReplicatedStorage:FindFirstChild("SalvageConfig")
        if mod and mod:IsA("ModuleScript") then
            _SalvageConfig = require(mod)
        end
    end
    return _SalvageConfig
end

--------------------------------------------------------------------------------
-- EQUIPPED CHECK  (queries Loadout.server.lua via BindableFunction)
--------------------------------------------------------------------------------
local function isInstanceEquipped(player, instanceId)
    -- The BindableFunction is created by Loadout.server.lua in ServerScriptService
    local bf = ServerScriptService:FindFirstChild("IsInstanceEquipped")
    if bf and bf:IsA("BindableFunction") then
        local ok, result = pcall(function()
            return bf:Invoke(player, instanceId)
        end)
        if ok then return result == true end
    end
    return false
end

--------------------------------------------------------------------------------
-- GetSalvageValueForItem(instanceData)
--
-- Calculates the Salvage currency value for a weapon instance based on its
-- rarity, using SalvageConfig.ValueByRarity.
-- Returns: number or nil (nil = no value / unsalvageable rarity)
--------------------------------------------------------------------------------
function SalvageService:GetSalvageValueForItem(instanceData)
    if not instanceData or type(instanceData) ~= "table" then return nil end
    local config = getSalvageConfig()
    if not config then return nil end
    local rarity = instanceData.rarity
    if not rarity then return nil end
    return config.GetValueForRarity(rarity)
end

--- Convenience: look up by player + instanceId
function SalvageService:GetSalvageValueById(player, instanceId)
    local wis = getWeaponInstanceService()
    if not wis then return nil end
    local inst = wis:GetInstance(player, instanceId)
    if not inst then return nil end
    return self:GetSalvageValueForItem(inst)
end

--------------------------------------------------------------------------------
-- CanSalvageItem(player, instanceId)
--
-- Validates ALL salvage rules server-side.
-- Returns: (bool canSalvage, string reason)
--------------------------------------------------------------------------------
function SalvageService:CanSalvageItem(player, instanceId)
    if not player then return false, "No player" end
    if type(instanceId) ~= "string" or #instanceId == 0 then
        return false, "Invalid instance ID"
    end

    local wis = getWeaponInstanceService()
    if not wis then return false, "Inventory service unavailable" end

    local inst = wis:GetInstance(player, instanceId)
    if not inst then return false, "Item not found in inventory" end

    local config = getSalvageConfig()
    if not config then return false, "Salvage config unavailable" end

    -- Rule: starter weapons
    if config.BlockStarter and inst.source == "Starter" then
        return false, "Cannot salvage starter weapons"
    end

    -- Rule: specific unsalvageable weapon names
    if config.UnsalvageableWeapons and config.UnsalvageableWeapons[inst.weaponName] then
        return false, "This weapon cannot be salvaged"
    end

    -- Rule: favorited items
    if config.BlockFavorited and inst.favorited == true then
        return false, "Unfavorite the weapon before salvaging"
    end

    -- Rule: equipped items
    if config.BlockEquipped and isInstanceEquipped(player, instanceId) then
        return false, "Cannot salvage equipped weapons"
    end

    -- Rule: rarity must have a defined salvage value
    local value = config.GetValueForRarity(inst.rarity)
    if not value or value <= 0 then
        return false, "No salvage value defined for rarity: " .. tostring(inst.rarity)
    end

    return true, "OK"
end

--------------------------------------------------------------------------------
-- SalvageItem(player, instanceId)
--
-- Performs the full salvage operation:
--   1. Validate eligibility
--   2. Calculate value
--   3. Remove item from inventory
--   4. Award Salvage currency
--   5. Save inventory
--
-- Returns: (bool success, table result)
--   result.reason      = denial reason (on failure)
--   result.weaponName  = name of salvaged weapon (on success)
--   result.rarity      = rarity of salvaged weapon (on success)
--   result.awarded     = Salvage amount awarded (on success)
--   result.newBalance  = new Salvage balance (on success)
--------------------------------------------------------------------------------
function SalvageService:SalvageItem(player, instanceId)
    -- 1. Validate
    local canSalvage, reason = self:CanSalvageItem(player, instanceId)
    if not canSalvage then
        print("[SalvageService] DENIED for", player.Name, "item", instanceId, "reason:", reason)
        return false, { reason = reason }
    end

    local wis = getWeaponInstanceService()
    local cs  = getCurrencyService()
    if not wis or not cs then
        return false, { reason = "Service unavailable" }
    end

    -- 2. Snapshot item data before removal (needed for value calculation)
    local inst = wis:GetInstance(player, instanceId)
    if not inst then
        return false, { reason = "Item disappeared" }
    end
    local weaponName = inst.weaponName
    local rarity     = inst.rarity
    local value      = self:GetSalvageValueForItem(inst)
    if not value or value <= 0 then
        return false, { reason = "No salvage value" }
    end

    -- 3. Remove item from inventory
    local removed = wis:RemoveInstance(player, instanceId)
    if not removed then
        return false, { reason = "Failed to remove item" }
    end

    -- 4. Award Salvage currency (only after successful removal)
    cs:AddSalvage(player, value)
    local newBalance = cs:GetSalvage(player)

    -- 5. Save inventory to DataStore
    wis:SaveForPlayer(player)

    print("[SalvageService] SUCCESS", player.Name, "salvaged", weaponName,
        "(" .. rarity .. ") for", value, "salvage. New balance:", newBalance)

    return true, {
        weaponName = weaponName,
        rarity     = rarity,
        awarded    = value,
        newBalance = newBalance,
    }
end

return SalvageService
