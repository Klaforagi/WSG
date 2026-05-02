--------------------------------------------------------------------------------
-- AdminService.lua  –  Server-side admin weapon management logic
--
-- Provides:
--   AdminService:SearchWeapons(adminPlayer, searchType, searchValue)
--   AdminService:GrantWeapon(adminPlayer, targetUserId, weaponName, sizePercent, enchantName)
--   AdminService:GrantCurrency(adminPlayer, targetUserId, currencyType, amount)
--   AdminService:ControlEvent(adminPlayer, action, eventId)
--
-- All operations verify the requesting player is a whitelisted dev.
-- Hooks into existing WeaponInstanceService for instance creation/save.
-- Writes to WeaponRegistryService for global search indexing.
-- Logs all grant actions via AdminAuditService.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevUserIds            = require(ReplicatedStorage.DevUserIds)
local CrateConfig           = require(ReplicatedStorage.CrateConfig)
local WeaponEnchantConfig   = require(ReplicatedStorage.WeaponEnchantConfig)
local SizeRollService       = require(ReplicatedStorage.SizeRollService)

-- Lazy-loaded server modules (avoid circular requires)
local _WeaponInstanceService
local _WeaponRegistryService
local _AdminAuditService
local _CurrencyService
local _EventScheduler

local function getWeaponInstanceService()
    if not _WeaponInstanceService then
        _WeaponInstanceService = require(script.Parent.WeaponInstanceService)
    end
    return _WeaponInstanceService
end

local function getWeaponRegistryService()
    if not _WeaponRegistryService then
        _WeaponRegistryService = require(script.Parent.WeaponRegistryService)
    end
    return _WeaponRegistryService
end

local function getAdminAuditService()
    if not _AdminAuditService then
        _AdminAuditService = require(script.Parent.AdminAuditService)
    end
    return _AdminAuditService
end

local function getCurrencyService()
    if not _CurrencyService then
        _CurrencyService = require(script.Parent.CurrencyService)
    end
    return _CurrencyService
end

local function getEventScheduler()
    if not _EventScheduler then
        _EventScheduler = require(script.Parent.EventScheduler)
    end
    return _EventScheduler
end

local AdminService = {}

--------------------------------------------------------------------------------
-- VALIDATION HELPERS
--------------------------------------------------------------------------------

--- Verify the requesting player is a whitelisted developer.
local function assertDev(player)
    if not player or not DevUserIds.IsDev(player) then
        return false, "Unauthorized: not a whitelisted developer"
    end
    return true
end

--- Build a lookup table of all valid weapon names from CrateConfig + starter weapons.
local VALID_WEAPONS = nil
local function getValidWeapons()
    if VALID_WEAPONS then return VALID_WEAPONS end
    VALID_WEAPONS = {}
    for _, weapons in pairs(CrateConfig.WeaponsByRarity) do
        for _, entry in ipairs(weapons) do
            VALID_WEAPONS[entry.weapon] = {
                category = entry.category,
            }
        end
    end
    -- Add starter weapons
    VALID_WEAPONS["Starter Sword"]     = { category = "Melee" }
    VALID_WEAPONS["Starter Slingshot"] = { category = "Ranged" }
    return VALID_WEAPONS
end

--- Look up rarity for a weapon name from CrateConfig.
local function getRarityForWeapon(weaponName)
    for rarity, weapons in pairs(CrateConfig.WeaponsByRarity) do
        for _, entry in ipairs(weapons) do
            if entry.weapon == weaponName then
                return rarity
            end
        end
    end
    -- Starters are Common
    if weaponName == "Starter Sword" or weaponName == "Starter Slingshot" then
        return "Common"
    end
    return "Common"
end

--- Validate and clamp size percent to allowed range (80-200).
local function clampSizePercent(sizePercent)
    if type(sizePercent) ~= "number" then
        sizePercent = 100
    end
    return math.clamp(math.floor(sizePercent), 80, 200)
end

--- Validate enchant name against WeaponEnchantConfig.
local function validateEnchant(enchantName)
    if type(enchantName) ~= "string" or enchantName == "" then
        return "" -- no enchant
    end
    if WeaponEnchantConfig.GetEnchantData(enchantName) then
        return enchantName
    end
    return nil -- invalid enchant name
end

local CURRENCY_GRANT_MAX = 1000000
local CURRENCY_RETRIES = 3
local CURRENCY_RETRY_DELAY = 0.5
local CURRENCY_DEFS = {
    Coins = {
        displayName = "Coins",
        datastoreName = "Coins_v1",
        getMethod = "GetCoins",
        addMethod = "AddCoins",
        saveMethod = "SaveForPlayer",
    },
    Keys = {
        displayName = "Keys",
        datastoreName = "Keys_v1",
        getMethod = "GetKeys",
        addMethod = "AddKeys",
        saveMethod = "SaveKeysForPlayer",
    },
    Salvage = {
        displayName = "Salvage",
        datastoreName = "Salvage_v1",
        getMethod = "GetSalvage",
        addMethod = "AddSalvage",
        saveMethod = "SaveSalvageForPlayer",
    },
}

local _currencyDataStores = {}
local function getCurrencyDataStore(def)
    if not _currencyDataStores[def.datastoreName] then
        _currencyDataStores[def.datastoreName] = DataStoreService:GetDataStore(def.datastoreName)
    end
    return _currencyDataStores[def.datastoreName]
end

local function currencyDataStoreKey(userId)
    return "User_" .. tostring(userId)
end

local function retryOfflineCurrencyAdd(def, targetUserId, amount)
    local dataStore = getCurrencyDataStore(def)
    local key = currencyDataStoreKey(targetUserId)
    local previousBalance = 0
    local newBalance = 0
    local lastErr

    for i = 1, CURRENCY_RETRIES do
        local ok, result = pcall(function()
            return dataStore:UpdateAsync(key, function(oldValue)
                local oldAmount = math.floor(tonumber(oldValue) or 0)
                if oldAmount < 0 then oldAmount = 0 end
                previousBalance = oldAmount
                newBalance = oldAmount + amount
                return newBalance
            end)
        end)
        if ok then
            if type(result) == "number" then
                newBalance = math.max(0, math.floor(result))
            end
            return true, previousBalance, newBalance
        end
        lastErr = result
        task.wait(CURRENCY_RETRY_DELAY * i)
    end

    return false, previousBalance, newBalance, lastErr
end

--------------------------------------------------------------------------------
-- SEARCH WEAPONS
--
-- searchType: "WeaponId" | "OwnerUserId" | "Username"
-- searchValue: string
--
-- Returns: { success = bool, results = { ... }, error = string? }
--------------------------------------------------------------------------------
function AdminService:SearchWeapons(adminPlayer, searchType, searchValue)
    -- 1. Verify admin
    local ok, err = assertDev(adminPlayer)
    if not ok then
        return { success = false, error = err }
    end

    -- 2. Validate inputs
    if type(searchType) ~= "string" then
        return { success = false, error = "Invalid search type" }
    end
    if type(searchValue) ~= "string" or searchValue == "" then
        return { success = false, error = "Search value cannot be empty" }
    end

    local registry = getWeaponRegistryService()

    -- 3. Dispatch by search type
    if searchType == "WeaponId" then
        local record, searchErr = registry:SearchWeaponById(searchValue)
        if record then
            return { success = true, results = { record } }
        else
            return { success = true, results = {}, error = searchErr }
        end

    elseif searchType == "OwnerUserId" then
        local userId = tonumber(searchValue)
        if not userId then
            return { success = false, error = "Invalid UserId (must be a number)" }
        end
        local results, searchErr = registry:SearchWeaponsByOwnerUserId(userId)
        return { success = true, results = results or {}, error = searchErr }

    elseif searchType == "Username" then
        local results, searchErr = registry:SearchWeaponsByUsername(searchValue)
        return { success = true, results = results or {}, error = searchErr }

    else
        return { success = false, error = "Unknown search type: " .. tostring(searchType) }
    end
end

--------------------------------------------------------------------------------
-- GRANT WEAPON
--
-- Creates a brand-new weapon instance and assigns it to the target player.
--
-- Returns: { success = bool, weaponRecord = table?, error = string? }
--------------------------------------------------------------------------------
function AdminService:GrantWeapon(adminPlayer, targetUserId, weaponName, sizePercent, enchantName)
    -- 1. Verify admin
    local ok, err = assertDev(adminPlayer)
    if not ok then
        return { success = false, error = err }
    end

    -- 2. Validate target userId
    if type(targetUserId) ~= "number" or targetUserId <= 0 then
        return { success = false, error = "Invalid target UserId" }
    end

    -- Verify the userId exists by trying to resolve the username
    local targetUsername
    local nameOk, nameResult = pcall(function()
        return Players:GetNameFromUserIdAsync(targetUserId)
    end)
    if not nameOk or not nameResult then
        return { success = false, error = "Could not resolve UserId " .. tostring(targetUserId) .. " to a username. The user may not exist." }
    end
    targetUsername = nameResult

    -- 3. Validate weapon name
    if type(weaponName) ~= "string" or weaponName == "" then
        return { success = false, error = "Weapon name is required" }
    end
    local validWeapons = getValidWeapons()
    local weaponInfo = validWeapons[weaponName]
    if not weaponInfo then
        return { success = false, error = "Unknown weapon: " .. tostring(weaponName) .. ". Check weapon name spelling." }
    end

    -- 4. Validate and clamp size percent
    sizePercent = clampSizePercent(sizePercent)
    local sizeTier = SizeRollService.GetSizeTier(sizePercent)

    -- 5. Validate enchant
    local validatedEnchant = validateEnchant(enchantName)
    if validatedEnchant == nil then
        -- Build list of valid enchant names for the error message
        local validNames = {}
        for _, e in ipairs(WeaponEnchantConfig.Enchants) do
            table.insert(validNames, e.name)
        end
        return { success = false, error = "Invalid enchant: " .. tostring(enchantName) .. ". Valid enchants: " .. table.concat(validNames, ", ") }
    end

    -- 6. Determine category and rarity
    local category = weaponInfo.category
    local rarity = getRarityForWeapon(weaponName)

    -- 7. Check if target player is online
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    local instanceService = getWeaponInstanceService()
    local instanceData

    if targetPlayer then
        -- Online: create instance in their live inventory
        instanceData = instanceService:CreateInstance(
            targetPlayer,
            weaponName,
            rarity,
            category,
            "AdminGrant",
            sizePercent,
            sizeTier,
            validatedEnchant
        )

        if not instanceData then
            return { success = false, error = "Failed to create weapon instance" }
        end

        -- Add admin grant metadata to the instance
        instanceData.grantedByUserId    = adminPlayer.UserId
        instanceData.grantedByUsername   = adminPlayer.Name
        instanceData.lastUpdatedAt      = os.time()

        -- Save immediately
        instanceService:SaveForPlayer(targetPlayer)

        -- Notify the online player's client to refresh inventory
        local weaponInventoryUpdated = game.ReplicatedStorage:FindFirstChild("WeaponInventoryUpdated")
        if weaponInventoryUpdated then
            weaponInventoryUpdated:FireClient(targetPlayer, instanceService:GetInventory(targetPlayer))
        end
    else
        -- Offline: load their DataStore, create instance, save back
        -- We need to temporarily load their inventory
        local DataStoreService = game:GetService("DataStoreService")
        local ds = DataStoreService:GetDataStore("WeaponInstances_v1")
        local dsKey = "WpnInv_" .. tostring(targetUserId)

        local loadOk, rawInv
        for i = 1, 3 do
            loadOk, rawInv = pcall(function()
                return ds:GetAsync(dsKey)
            end)
            if loadOk then break end
            task.wait(0.5 * i)
        end

        if not loadOk then
            return { success = false, error = "Failed to load target player's inventory from DataStore" }
        end

        local inv = (type(rawInv) == "table") and rawInv or {}

        -- Generate a unique weapon ID
        local HttpService = game:GetService("HttpService")
        local CHARSET = "0123456789ABCDEF"
        local newId
        for _ = 1, 50 do
            local parts = {}
            for _ = 1, 6 do
                local idx = math.random(1, #CHARSET)
                table.insert(parts, string.sub(CHARSET, idx, idx))
            end
            local candidate = "WPN-" .. table.concat(parts)
            if not inv[candidate] then
                newId = candidate
                break
            end
        end
        if not newId then
            local guid = string.gsub(HttpService:GenerateGUID(false), "-", "")
            newId = "WPN-" .. string.sub(guid, 1, 8)
        end

        instanceData = {
            instanceId         = newId,
            weaponName         = weaponName,
            rarity             = rarity,
            category           = category,
            source             = "AdminGrant",
            obtainedAt         = os.time(),
            sizePercent        = sizePercent,
            sizeTier           = sizeTier,
            enchantName        = validatedEnchant,
            grantedByUserId    = adminPlayer.UserId,
            grantedByUsername   = adminPlayer.Name,
            lastUpdatedAt      = os.time(),
        }

        inv[newId] = instanceData

        -- Save back to DataStore
        local saveOk, saveErr
        for i = 1, 3 do
            saveOk, saveErr = pcall(function()
                ds:SetAsync(dsKey, inv)
            end)
            if saveOk then break end
            task.wait(0.5 * i)
        end

        if not saveOk then
            return { success = false, error = "Failed to save weapon to target's inventory: " .. tostring(saveErr) }
        end
    end

    -- 8. Register in global weapon registry for search
    local registry = getWeaponRegistryService()
    local registryRecord = {
        WeaponId          = instanceData.instanceId,
        OwnerUserId       = targetUserId,
        OwnerUsername      = targetUsername,
        WeaponName        = weaponName,
        SizePercent       = sizePercent,
        Enchant           = validatedEnchant,
        Rarity            = rarity,
        ObtainedAt        = instanceData.obtainedAt,
        ObtainedMethod    = "AdminGrant",
        GrantedByUserId   = adminPlayer.UserId,
        GrantedByUsername  = adminPlayer.Name,
        LastUpdatedAt     = os.time(),
    }
    registry:RegisterWeapon(registryRecord)

    -- 9. Audit log
    local audit = getAdminAuditService()
    audit:LogAction({
        Action          = "GrantWeapon",
        AdminUserId     = adminPlayer.UserId,
        AdminUsername    = adminPlayer.Name,
        TargetUserId    = targetUserId,
        TargetUsername   = targetUsername,
        WeaponId        = instanceData.instanceId,
        WeaponName      = weaponName,
        SizePercent     = sizePercent,
        Enchant         = validatedEnchant,
    })

    -- 10. Return success
    return {
        success = true,
        weaponRecord = registryRecord,
    }
end

--------------------------------------------------------------------------------
-- GRANT CURRENCY
--
-- Adds coins, keys, or salvage to a target player by UserId.
-- Works for both online and offline players.
--
-- Returns: { success = bool, currencyRecord = table?, error = string? }
--------------------------------------------------------------------------------
function AdminService:GrantCurrency(adminPlayer, targetUserId, currencyType, amount)
    -- 1. Verify admin
    local ok, err = assertDev(adminPlayer)
    if not ok then
        return { success = false, error = err }
    end

    -- 2. Validate inputs
    if type(targetUserId) ~= "number" or targetUserId <= 0 then
        return { success = false, error = "Invalid target UserId" }
    end
    if type(currencyType) ~= "string" then
        return { success = false, error = "Invalid currency type" }
    end
    local currencyDef = CURRENCY_DEFS[currencyType]
    if not currencyDef then
        return { success = false, error = "Unknown currency type: " .. tostring(currencyType) }
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return { success = false, error = "Amount must be positive" }
    end
    if amount > CURRENCY_GRANT_MAX then
        return { success = false, error = "Amount is too large" }
    end

    -- Verify the userId exists by trying to resolve the username
    local targetUsername
    local nameOk, nameResult = pcall(function()
        return Players:GetNameFromUserIdAsync(targetUserId)
    end)
    if not nameOk or not nameResult then
        return { success = false, error = "Could not resolve UserId " .. tostring(targetUserId) .. " to a username. The user may not exist." }
    end
    targetUsername = nameResult

    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    local previousBalance = 0
    local newBalance = 0
    local wasOnline = targetPlayer ~= nil
    local warning

    if targetPlayer then
        local currencyService = getCurrencyService()
        local getMethod = currencyService[currencyDef.getMethod]
        local addMethod = currencyService[currencyDef.addMethod]
        local saveMethod = currencyService[currencyDef.saveMethod]

        if type(getMethod) ~= "function" or type(addMethod) ~= "function" or type(saveMethod) ~= "function" then
            return { success = false, error = "CurrencyService is missing required methods for " .. currencyDef.displayName }
        end

        previousBalance = math.floor(tonumber(getMethod(currencyService, targetPlayer)) or 0)
        local addOk, addErr = pcall(function()
            addMethod(currencyService, targetPlayer, amount)
        end)
        if not addOk then
            return { success = false, error = "Failed to grant " .. currencyDef.displayName .. ": " .. tostring(addErr) }
        end

        newBalance = math.floor(tonumber(getMethod(currencyService, targetPlayer)) or (previousBalance + amount))
        local saveOk, saveResult = pcall(function()
            return saveMethod(currencyService, targetPlayer)
        end)
        if not saveOk or saveResult == false then
            warning = "Granted live balance, but the immediate save failed; normal player-leave save may still persist it."
        end
    else
        local updateOk, oldAmount, updatedAmount, updateErr = retryOfflineCurrencyAdd(currencyDef, targetUserId, amount)
        if not updateOk then
            return { success = false, error = "Failed to update offline " .. currencyDef.displayName .. ": " .. tostring(updateErr) }
        end
        previousBalance = oldAmount
        newBalance = updatedAmount
    end

    -- 3. Audit log
    local audit = getAdminAuditService()
    audit:LogAction({
        Action          = "GrantCurrency",
        AdminUserId     = adminPlayer.UserId,
        AdminUsername    = adminPlayer.Name,
        TargetUserId    = targetUserId,
        TargetUsername   = targetUsername,
        WeaponId        = "",
        WeaponName      = currencyDef.displayName,
        SizePercent     = amount,
        Enchant         = string.format("old=%d; new=%d; online=%s", previousBalance, newBalance, tostring(wasOnline)),
    })

    return {
        success = true,
        currencyRecord = {
            TargetUserId = targetUserId,
            TargetUsername = targetUsername,
            CurrencyType = currencyType,
            CurrencyLabel = currencyDef.displayName,
            Amount = amount,
            PreviousBalance = previousBalance,
            NewBalance = newBalance,
            WasOnline = wasOnline,
            Warning = warning,
            GrantedByUserId = adminPlayer.UserId,
            GrantedByUsername = adminPlayer.Name,
        },
    }
end

--------------------------------------------------------------------------------
-- CONTROL EVENT
--
-- Starts/stops timed events for testing without waiting for scheduler rolls.
-- action: "GetState" | "Start" | "Stop"
-- eventId: event id from EventConfig.EventDefs for Start/Stop.
--
-- Returns: { success = bool, state = table?, message = string?, error = string? }
--------------------------------------------------------------------------------
function AdminService:ControlEvent(adminPlayer, action, eventId)
    local ok, err = assertDev(adminPlayer)
    if not ok then
        return { success = false, error = err }
    end

    if type(action) ~= "string" then
        return { success = false, error = "Invalid event action" }
    end

    local scheduler = getEventScheduler()

    if action == "GetState" then
        return {
            success = true,
            state = scheduler:GetAdminState(),
        }
    end

    if action == "Start" and (type(eventId) ~= "string" or eventId == "") then
        return { success = false, error = "Event id is required" }
    end
    if eventId ~= nil and eventId ~= "" and type(eventId) ~= "string" then
        return { success = false, error = "Invalid event id" }
    end
    if type(eventId) == "string" and #eventId > 50 then
        return { success = false, error = "Event id too long" }
    end

    local controlOk, controlErr
    if action == "Start" then
        controlOk, controlErr = scheduler:StartEvent(eventId)
    elseif action == "Stop" then
        controlOk, controlErr = scheduler:StopEvent(eventId)
    else
        return { success = false, error = "Unknown event action: " .. tostring(action) }
    end

    if not controlOk then
        return {
            success = false,
            error = controlErr or "Event command failed",
            state = scheduler:GetAdminState(),
        }
    end

    return {
        success = true,
        message = action .. " " .. tostring(eventId or "active event"),
        state = scheduler:GetAdminState(),
    }
end

--------------------------------------------------------------------------------
-- DELETE WEAPON
--
-- Admin-only: removes a weapon from any player's inventory by weaponId + ownerUserId.
-- Works for both online and offline players.
--
-- Returns: { success = bool, error = string? }
--------------------------------------------------------------------------------
function AdminService:DeleteWeapon(adminPlayer, ownerUserId, weaponId)
    -- 1. Verify admin
    local ok, err = assertDev(adminPlayer)
    if not ok then
        return { success = false, error = err }
    end

    -- 2. Validate inputs
    if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
        return { success = false, error = "Invalid owner UserId" }
    end
    if type(weaponId) ~= "string" or weaponId == "" then
        return { success = false, error = "Invalid weapon ID" }
    end

    -- Resolve owner username for audit log
    local ownerUsername = "Unknown"
    local nameOk, nameResult = pcall(function()
        return Players:GetNameFromUserIdAsync(ownerUserId)
    end)
    if nameOk and nameResult then
        ownerUsername = nameResult
    end

    local instanceService = getWeaponInstanceService()
    local deletedWeaponName = "Unknown"

    -- 3. Check if owner is online
    local targetPlayer = Players:GetPlayerByUserId(ownerUserId)
    if targetPlayer then
        local inst = instanceService:GetInstance(targetPlayer, weaponId)
        if not inst then
            return { success = false, error = "Weapon " .. weaponId .. " not found in online player's inventory" }
        end
        deletedWeaponName = inst.weaponName or deletedWeaponName
        instanceService:RemoveInstance(targetPlayer, weaponId)
        instanceService:SaveForPlayer(targetPlayer)

        -- Notify client
        local weaponInventoryUpdated = game.ReplicatedStorage:FindFirstChild("WeaponInventoryUpdated")
        if weaponInventoryUpdated then
            weaponInventoryUpdated:FireClient(targetPlayer, instanceService:GetInventory(targetPlayer))
        end
    else
        -- 4. Offline: load DataStore, remove, save back
        local DataStoreService = game:GetService("DataStoreService")
        local ds = DataStoreService:GetDataStore("WeaponInstances_v1")
        local dsKey = "WpnInv_" .. tostring(ownerUserId)

        local loadOk, rawInv
        for i = 1, 3 do
            loadOk, rawInv = pcall(function()
                return ds:GetAsync(dsKey)
            end)
            if loadOk then break end
            task.wait(0.5 * i)
        end

        if not loadOk then
            return { success = false, error = "Failed to load owner's inventory from DataStore" }
        end

        local inv = (type(rawInv) == "table") and rawInv or {}
        if not inv[weaponId] then
            return { success = false, error = "Weapon " .. weaponId .. " not found in offline player's inventory" }
        end

        deletedWeaponName = inv[weaponId].weaponName or deletedWeaponName
        inv[weaponId] = nil

        local saveOk, saveErr
        for i = 1, 3 do
            saveOk, saveErr = pcall(function()
                ds:SetAsync(dsKey, inv)
            end)
            if saveOk then break end
            task.wait(0.5 * i)
        end

        if not saveOk then
            return { success = false, error = "Failed to save after deletion: " .. tostring(saveErr) }
        end
    end

    -- 5. Audit log
    local audit = getAdminAuditService()
    audit:LogAction({
        Action          = "DeleteWeapon",
        AdminUserId     = adminPlayer.UserId,
        AdminUsername    = adminPlayer.Name,
        TargetUserId    = ownerUserId,
        TargetUsername   = ownerUsername,
        WeaponId        = weaponId,
        WeaponName      = deletedWeaponName,
    })

    return { success = true }
end

return AdminService
