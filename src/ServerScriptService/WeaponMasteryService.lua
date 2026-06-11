--------------------------------------------------------------------------------
-- WeaponMasteryService.lua
-- Server-authoritative per-weapon-name progression and automatic damage bonuses.
-- Public APIs still accept weapon instance IDs for compatibility with tools/UI.
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("WeaponMasteryConfig"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "WeaponMastery_v1"
local DATA_VERSION = 2
local RETRIES = 3
local RETRY_DELAY = 0.5
local SAVE_DELAY = 30

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local WeaponMasteryService = {}

local playerMasteries = {}
local dirtyPlayers = {}
local saveScheduled = {}

local _WeaponInstanceService
local _SaveCoordinator

local function getWeaponInstanceService()
    if not _WeaponInstanceService then
        local mod = ServerScriptService:FindFirstChild("WeaponInstanceService")
        if mod and mod:IsA("ModuleScript") then
            _WeaponInstanceService = require(mod)
        end
    end
    return _WeaponInstanceService
end

local function getSaveCoordinator()
    if _SaveCoordinator == nil then
        local ok, coordinator = pcall(function()
            return require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
        end)
        if ok then
            _SaveCoordinator = coordinator
        else
            _SaveCoordinator = false
        end
    end
    if _SaveCoordinator == false then
        return nil
    end
    return _SaveCoordinator
end

local function ensureRemote(className, name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA(className) then
        return existing
    end
    if existing then existing:Destroy() end
    local remote = Instance.new(className)
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local masteryUpdatedRE = ensureRemote("RemoteEvent", "WeaponMasteryUpdated")
local XP_PRECISION_SCALE = 10
local TRACKED_MOB_XP = {
    Goblin = Config.XP.GoblinKill or 0,
    Orc = Config.XP.OrcKill or 0,
    Ogre = Config.XP.OgreKill or 0,
}

local function normalizeXPValue(xp)
    xp = math.max(0, tonumber(xp) or 0)
    return math.round(xp * XP_PRECISION_SCALE) / XP_PRECISION_SCALE
end

local function isTrackedTeamPlayer(player)
    if not player or not player:IsA("Player") then return false end
    local team = player.Team
    if not team then return false end
    return team.Name ~= "Neutral"
end

local function getTrackedMobType(mobName)
    if type(mobName) ~= "string" or mobName == "" then
        return nil
    end
    local lowered = string.lower(mobName)
    if string.find(lowered, "goblin", 1, true) then
        return "Goblin"
    end
    if string.find(lowered, "orc", 1, true) then
        return "Orc"
    end
    if string.find(lowered, "ogre", 1, true) then
        return "Ogre"
    end
    return nil
end

local function dsKey(player)
    return "WpnMastery_" .. tostring(player.UserId)
end

local function copyTable(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function newEntry()
    return {
        xp = 0,
        level = 0,
        rarity = "Common",
        category = "Melee",
        eliminations = 0,
        mobKills = 0,
        captures = 0,
        damage = 0,
        claimedRewards = {},
        lastUsedAt = 0,
    }
end

local function resolveWeaponMeta(weaponName, meta)
    local resolved = type(meta) == "table" and meta or nil
    if not resolved then
        resolved = Config.GetWeaponMeta(weaponName)
    end
    local rarity = Config.NormalizeRarity(resolved and resolved.rarity or "Common")
    local category = Config.NormalizeCategory(resolved and resolved.category or "Melee")
    return {
        rarity = rarity,
        category = category,
    }
end

local function normalizeEntry(entry, weaponName, meta)
    if type(entry) ~= "table" then
        entry = newEntry()
    end
    local resolved = resolveWeaponMeta(weaponName, meta)
    entry.rarity = resolved.rarity
    entry.category = resolved.category
    entry.xp = normalizeXPValue(entry.xp)
    entry.level = Config.GetLevelForXP(entry.xp, entry.rarity)
    entry.eliminations = math.max(0, math.floor(tonumber(entry.eliminations) or 0))
    entry.mobKills = math.max(0, math.floor(tonumber(entry.mobKills) or 0))
    entry.captures = math.max(0, math.floor(tonumber(entry.captures) or 0))
    entry.damage = math.max(0, math.floor(tonumber(entry.damage) or 0))
    entry.lastUsedAt = math.max(0, math.floor(tonumber(entry.lastUsedAt) or 0))
    if type(entry.claimedRewards) ~= "table" then
        entry.claimedRewards = {}
    end
    local normalizedClaims = {}
    for key, value in pairs(entry.claimedRewards) do
        if value == true then
            normalizedClaims[tostring(key)] = true
        end
    end
    entry.claimedRewards = normalizedClaims
    return entry
end

local function newDataRecord()
    return {
        __version = DATA_VERSION,
        byWeaponName = {},
        legacyByInstance = {},
    }
end

local function ensureDataForPlayer(player)
    local data = playerMasteries[player]
    if type(data) ~= "table" then
        data = newDataRecord()
        playerMasteries[player] = data
    end
    data.__version = DATA_VERSION
    if type(data.byWeaponName) ~= "table" then
        data.byWeaponName = {}
    end
    if type(data.legacyByInstance) ~= "table" then
        data.legacyByInstance = {}
    end
    return data
end

local function mergeEntryInto(targetEntry, sourceEntry, weaponName, meta)
    targetEntry = normalizeEntry(targetEntry or newEntry(), weaponName, meta)
    sourceEntry = normalizeEntry(copyTable(sourceEntry), weaponName, meta)

    targetEntry.xp = normalizeXPValue((targetEntry.xp or 0) + (sourceEntry.xp or 0))
    targetEntry.eliminations = (targetEntry.eliminations or 0) + (sourceEntry.eliminations or 0)
    targetEntry.mobKills = (targetEntry.mobKills or 0) + (sourceEntry.mobKills or 0)
    targetEntry.captures = (targetEntry.captures or 0) + (sourceEntry.captures or 0)
    targetEntry.damage = (targetEntry.damage or 0) + (sourceEntry.damage or 0)
    targetEntry.lastUsedAt = math.max(targetEntry.lastUsedAt or 0, sourceEntry.lastUsedAt or 0)

    for rewardLevel, claimed in pairs(sourceEntry.claimedRewards or {}) do
        if claimed == true then
            targetEntry.claimedRewards[tostring(rewardLevel)] = true
        end
    end

    targetEntry.level = Config.GetLevelForXP(targetEntry.xp, targetEntry.rarity)
    return targetEntry
end

local function getInventory(player)
    local weaponInstanceService = getWeaponInstanceService()
    if not weaponInstanceService then return {} end
    local ok, inventory = pcall(function()
        return weaponInstanceService:GetInventory(player)
    end)
    if ok and type(inventory) == "table" then
        return inventory
    end
    return {}
end

local function getWeaponNameFromInventory(inventory, instanceId)
    if type(inventory) ~= "table" or type(instanceId) ~= "string" then return nil end
    local instanceData = inventory[instanceId]
    if type(instanceData) == "table" and type(instanceData.weaponName) == "string" and instanceData.weaponName ~= "" then
        return instanceData.weaponName
    end
    return nil
end

local function getOwnedWeaponName(player, instanceId)
    if not player or type(instanceId) ~= "string" or instanceId == "" then return nil end
    local weaponInstanceService = getWeaponInstanceService()
    if not weaponInstanceService then return nil end
    local ok, instanceData = pcall(function()
        return weaponInstanceService:GetInstance(player, instanceId)
    end)
    if ok and type(instanceData) == "table" and type(instanceData.weaponName) == "string" and instanceData.weaponName ~= "" then
        return instanceData.weaponName
    end
    return nil
end

local function getEntryForWeaponName(player, weaponName, createIfMissing, meta)
    if not player or type(weaponName) ~= "string" or weaponName == "" then return nil end
    local data = ensureDataForPlayer(player)
    local entry = data.byWeaponName[weaponName]
    if not entry and createIfMissing then
        entry = newEntry()
        data.byWeaponName[weaponName] = entry
    end
    if entry then
        data.byWeaponName[weaponName] = normalizeEntry(entry, weaponName, meta)
    end
    return data.byWeaponName[weaponName]
end

local function getEntryForInstance(player, instanceId, createIfMissing)
    local weaponName = getOwnedWeaponName(player, instanceId)
    if not weaponName then return nil, nil, nil end
    local weaponInstanceService = getWeaponInstanceService()
    local instanceData = nil
    if weaponInstanceService then
        local ok, result = pcall(function()
            return weaponInstanceService:GetInstance(player, instanceId)
        end)
        if ok and type(result) == "table" then
            instanceData = result
        end
    end
    local meta = resolveWeaponMeta(weaponName, instanceData)
    return getEntryForWeaponName(player, weaponName, createIfMissing, meta), weaponName, meta
end

local function buildPayload(entry, weaponName, meta)
    meta = resolveWeaponMeta(weaponName, meta)
    entry = normalizeEntry(entry or newEntry(), weaponName, meta)
    local progress = Config.GetProgressForXP(entry.xp, meta.rarity, meta.category)
    local romanNumeral = Config.GetRomanNumeral(entry.level)
    local baseDamage = Config.GetDamageForLevel(entry.level, meta.rarity, meta.category)
    local nilDamage = Config.GetDamageForLevel(0, meta.rarity, meta.category)

    return {
        weaponName = weaponName,
        masteryKey = weaponName,
        rarity = meta.rarity,
        category = meta.category,
        xp = entry.xp,
        level = entry.level,
        title = romanNumeral,
        romanNumeral = romanNumeral,
        eliminations = entry.eliminations,
        mobKills = entry.mobKills,
        captures = entry.captures,
        damage = entry.damage,
        baseDamage = baseDamage,
        currentDamage = baseDamage,
        damageBonus = math.max(0, baseDamage - nilDamage),
        nilDamage = nilDamage,
        nextDamage = progress.nextDamage,
        currentLevelXP = progress.currentLevelXP,
        nextLevelXP = progress.nextLevelXP,
        nextLevel = progress.nextLevel,
        progress = progress.progress,
        maxed = progress.maxed == true,
    }
end

function WeaponMasteryService:GetMasteryPayloadForWeaponName(player, weaponName)
    local entry = getEntryForWeaponName(player, weaponName, false)
    return buildPayload(entry or newEntry(), weaponName)
end

function WeaponMasteryService:GetMasteryPayload(player, instanceId)
    local entry, weaponName, meta = getEntryForInstance(player, instanceId, false)
    return buildPayload(entry or newEntry(), weaponName, meta)
end

function WeaponMasteryService:GetMasteryBaseDamageForWeaponName(player, weaponName)
    if not player or type(weaponName) ~= "string" or weaponName == "" then
        return 0
    end
    local entry = getEntryForWeaponName(player, weaponName, false)
    local meta = resolveWeaponMeta(weaponName)
    return Config.GetDamageForLevel(entry and entry.level or 0, meta.rarity, meta.category)
end

function WeaponMasteryService:GetMasteryBaseDamage(player, instanceId)
    if not player or type(instanceId) ~= "string" or instanceId == "" then
        return 0
    end
    local entry, weaponName, meta = getEntryForInstance(player, instanceId, false)
    meta = meta or resolveWeaponMeta(weaponName)
    return Config.GetDamageForLevel(entry and entry.level or 0, meta.rarity, meta.category)
end

function WeaponMasteryService:GetDamageBonusForWeaponName(player, weaponName)
    if not player or type(weaponName) ~= "string" or weaponName == "" then
        return 0
    end
    local entry = getEntryForWeaponName(player, weaponName, false)
    local meta = resolveWeaponMeta(weaponName)
    return Config.GetDamageBonus(entry and entry.level or 0, meta.rarity, meta.category)
end

function WeaponMasteryService:GetDamageBonus(player, instanceId)
    if not player or type(instanceId) ~= "string" or instanceId == "" then
        return 0
    end
    local entry, weaponName, meta = getEntryForInstance(player, instanceId, false)
    meta = meta or resolveWeaponMeta(weaponName)
    return Config.GetDamageBonus(entry and entry.level or 0, meta.rarity, meta.category)
end

function WeaponMasteryService:AttachMasteryToInventory(player, inventory)
    local enriched = {}
    if type(inventory) ~= "table" then return enriched end
    for instanceId, data in pairs(inventory) do
        if type(data) == "table" then
            local copy = copyTable(data)
            copy.mastery = self:GetMasteryPayloadForWeaponName(player, copy.weaponName)
            enriched[instanceId] = copy
        end
    end
    return enriched
end

local function fireUpdated(player, instanceId, weaponName, meta)
    if not player or not player.Parent then return end
    local updateMeta = meta or {}
    updateMeta.weaponName = weaponName or updateMeta.weaponName
    pcall(function()
        masteryUpdatedRE:FireClient(player, instanceId, WeaponMasteryService:GetMasteryPayloadForWeaponName(player, updateMeta.weaponName), updateMeta)
    end)
end

local function markDirty(player)
    if not player then return end
    dirtyPlayers[player] = true
    saveScheduled[player] = true
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "WeaponMastery", "weapon_mastery", {
            delaySeconds = SAVE_DELAY,
        })
    end
end

local function addProgress(player, instanceId, xpAmount, statKey, statAmount, meta)
    if not player or not player.Parent then return nil end
    if not isTrackedTeamPlayer(player) then return nil end
    if type(instanceId) ~= "string" or instanceId == "" then return nil end

    local entry, weaponName, meta = getEntryForInstance(player, instanceId, true)
    if not entry or not weaponName then return nil end

    xpAmount = normalizeXPValue(xpAmount)
    statAmount = math.max(0, math.floor(tonumber(statAmount) or 0))
    local oldLevel = entry.level or 0

    if statKey and statAmount > 0 then
        entry[statKey] = math.max(0, math.floor(tonumber(entry[statKey]) or 0)) + statAmount
    end
    if xpAmount > 0 then
        entry.xp = normalizeXPValue((entry.xp or 0) + xpAmount)
        entry.level = Config.GetLevelForXP(entry.xp, (meta and meta.rarity) or entry.rarity, (meta and meta.category) or entry.category)
    end
    entry.lastUsedAt = os.time()

    markDirty(player)

    local updateMeta = meta or {}
    updateMeta.deltaXP = xpAmount
    updateMeta.leveledUp = (entry.level or 0) > oldLevel
    updateMeta.oldLevel = oldLevel
    if updateMeta.leveledUp then
        updateMeta.newLevel = entry.level
    end
    updateMeta.rarity = meta and meta.rarity or entry.rarity
    updateMeta.category = meta and meta.category or entry.category
    fireUpdated(player, instanceId, weaponName, updateMeta)
    return WeaponMasteryService:GetMasteryPayloadForWeaponName(player, weaponName)
end

local function loadVersioned(result)
    local loaded = newDataRecord()
    if type(result.byWeaponName) == "table" then
        for weaponName, entry in pairs(result.byWeaponName) do
            if type(weaponName) == "string" and weaponName ~= "" then
                loaded.byWeaponName[weaponName] = normalizeEntry(copyTable(entry), weaponName)
            end
        end
    end
    if type(result.legacyByInstance) == "table" then
        for instanceId, entry in pairs(result.legacyByInstance) do
            if type(instanceId) == "string" and instanceId ~= "" then
                loaded.legacyByInstance[instanceId] = normalizeEntry(copyTable(entry), nil, nil)
            end
        end
    end
    return loaded
end

local function loadLegacy(result)
    local loaded = newDataRecord()
    if type(result) == "table" then
        for instanceId, entry in pairs(result) do
            if type(instanceId) == "string" and instanceId ~= "__version" and type(entry) == "table" then
                loaded.legacyByInstance[instanceId] = normalizeEntry(copyTable(entry), entry.weaponName)
            end
        end
    end
    return loaded
end

local function migrateLegacyByInstance(player, data)
    local inventory = getInventory(player)
    local changed = false

    for instanceId, entry in pairs(copyTable(data.legacyByInstance)) do
        local weaponName = getWeaponNameFromInventory(inventory, instanceId)
        if weaponName then
            data.byWeaponName[weaponName] = mergeEntryInto(data.byWeaponName[weaponName], entry, weaponName)
            data.legacyByInstance[instanceId] = nil
            changed = true
        end
    end

    return changed
end

function WeaponMasteryService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = newDataRecord(),
            reason = "missing player",
        }
    end
    local key = dsKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "WeaponMastery/" .. key)

    local loaded = newDataRecord()
    local needsSave = false
    if success and type(result) == "table" then
        if result.__version == DATA_VERSION and type(result.byWeaponName) == "table" then
            loaded = loadVersioned(result)
        else
            loaded = loadLegacy(result)
            needsSave = true
        end
    end

    if migrateLegacyByInstance(player, loaded) then
        needsSave = true
    end

    for weaponName, entry in pairs(loaded.byWeaponName) do
        loaded.byWeaponName[weaponName] = normalizeEntry(entry, weaponName)
    end

    playerMasteries[player] = loaded
    dirtyPlayers[player] = nil
    saveScheduled[player] = nil

    if needsSave then
        markDirty(player)
    end

    if not success then
        warn("[WeaponMasteryService] Failed to load for " .. tostring(player.Name) .. "; using temporary empty mastery")
        return {
            status = "failed",
            data = DataStoreOps.DeepCopy(loaded),
            reason = err,
        }
    end
    if result == nil then
        return {
            status = "new",
            data = DataStoreOps.DeepCopy(loaded),
            markDirty = needsSave,
        }
    end
    return {
        status = "existing",
        data = DataStoreOps.DeepCopy(loaded),
        markDirty = needsSave,
    }
end

function WeaponMasteryService:LoadForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    return result and result.data or newDataRecord()
end

function WeaponMasteryService:GetSaveData(player)
    if not player then return nil end
    return DataStoreOps.DeepCopy(ensureDataForPlayer(player))
end

function WeaponMasteryService:SaveProfileForPlayer(player, saveData, oldData)
    if not player then return false, "missing player" end
    local data = DataStoreOps.DeepCopy(saveData or ensureDataForPlayer(player))
    for weaponName, entry in pairs(data.byWeaponName) do
        if type(weaponName) == "string" then
            data.byWeaponName[weaponName] = normalizeEntry(entry, weaponName)
        end
    end
    for instanceId, entry in pairs(data.legacyByInstance) do
        if type(instanceId) == "string" then
            data.legacyByInstance[instanceId] = normalizeEntry(entry, entry and entry.weaponName or nil)
        end
    end

    local key = dsKey(player)
    local success, _, err = DataStoreOps.Update(ds, key, "WeaponMastery/" .. key, function(storedData)
        local previousData = oldData or storedData or newDataRecord()
        local previousCount = DataStoreOps.CountEntries(type(previousData) == "table" and previousData.byWeaponName or nil)
        local storedCount = DataStoreOps.CountEntries(type(storedData) == "table" and storedData.byWeaponName or nil)
        local newCount = DataStoreOps.CountEntries(data.byWeaponName)
        if storedCount > 0 and previousCount > 0 and newCount == 0 then
            warn("[WeaponMasteryService] suspected wipe blocked for " .. tostring(player.Name))
            return storedData
        end
        return data
    end)
    if success then
        dirtyPlayers[player] = nil
        saveScheduled[player] = nil
    else
        warn("[WeaponMasteryService] Failed to save for " .. tostring(player.Name))
    end
    return success == true, err
end

function WeaponMasteryService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

-- Only saves players whose data has changed since the last save.
function WeaponMasteryService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if dirtyPlayers[player] then
            self:SaveForPlayer(player)
        end
    end
end

function WeaponMasteryService:RemovePlayer(player)
    playerMasteries[player] = nil
    dirtyPlayers[player] = nil
    saveScheduled[player] = nil
end

function WeaponMasteryService:RemoveWeapon(player, instanceId)
    local data = ensureDataForPlayer(player)
    local removedLegacy = false
    if type(instanceId) == "string" and data.legacyByInstance[instanceId] then
        data.legacyByInstance[instanceId] = nil
        removedLegacy = true
        markDirty(player)
    end
    if removedLegacy then
        fireUpdated(player, instanceId, nil, { removed = true })
    end
    return removedLegacy
end

function WeaponMasteryService:RegisterElimination(player, instanceId)
    return addProgress(player, instanceId, Config.XP.PlayerElimination, "eliminations", 1, { kind = "PlayerElimination" })
end

function WeaponMasteryService:RegisterMobKill(player, instanceId, mobName)
    local mobType = getTrackedMobType(mobName)
    local xpAmount = mobType and TRACKED_MOB_XP[mobType] or 0
    if xpAmount <= 0 then
        return nil
    end
    return addProgress(player, instanceId, xpAmount, "mobKills", 1, {
        kind = "MobKill",
        mobType = mobType,
        mobName = mobName,
    })
end

function WeaponMasteryService:RegisterCapture(player, instanceId)
    return nil
end

function WeaponMasteryService:RegisterDamage(player, instanceId, amount)
    if not player or not player.Parent then return nil end
    if not isTrackedTeamPlayer(player) then return nil end
    if type(instanceId) ~= "string" or instanceId == "" then return nil end

    local entry, weaponName, meta = getEntryForInstance(player, instanceId, true)
    if not entry or not weaponName then return nil end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return nil end

    entry.damage = (entry.damage or 0) + amount
    entry.lastUsedAt = os.time()
    local xpAmount = normalizeXPValue(Config.XP.Hit or 0)

    if xpAmount > 0 then
        local oldLevel = entry.level or 0
        entry.xp = normalizeXPValue((entry.xp or 0) + xpAmount)
        entry.level = Config.GetLevelForXP(entry.xp, (meta and meta.rarity) or entry.rarity, (meta and meta.category) or entry.category)
        fireUpdated(player, instanceId, weaponName, {
            kind = "Hit",
            deltaXP = xpAmount,
            leveledUp = (entry.level or 0) > oldLevel,
            oldLevel = oldLevel,
            newLevel = entry.level,
            rarity = (meta and meta.rarity) or entry.rarity,
            category = (meta and meta.category) or entry.category,
        })
    end

    markDirty(player)
    return self:GetMasteryPayloadForWeaponName(player, weaponName)
end

-- BindToClose is intentionally NOT registered here.
-- CrateServiceInit.server.lua owns the shutdown lifecycle for both
-- WeaponInstance and WeaponMastery and uses SaveGuard to prevent
-- double-saves when PlayerRemoving and BindToClose fire concurrently.

return WeaponMasteryService