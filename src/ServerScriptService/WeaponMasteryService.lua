--------------------------------------------------------------------------------
-- WeaponMasteryService.lua
-- Server-authoritative per-weapon-instance progression and milestone rewards.
--------------------------------------------------------------------------------

local DataStoreService   = game:GetService("DataStoreService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("WeaponMasteryConfig"))

local DATASTORE_NAME = "WeaponMastery_v1"
local RETRIES = 3
local RETRY_DELAY = 0.5
local SAVE_DELAY = 30

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local WeaponMasteryService = {}

local playerMasteries = {}
local dirtyPlayers = {}
local saveScheduled = {}

local _WeaponInstanceService
local _CurrencyService

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
local claimRewardRF = ensureRemote("RemoteFunction", "ClaimWeaponMasteryReward")

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
        level = 1,
        eliminations = 0,
        mobKills = 0,
        captures = 0,
        damage = 0,
        claimedRewards = {},
        lastUsedAt = 0,
    }
end

local function normalizeEntry(entry)
    if type(entry) ~= "table" then
        entry = newEntry()
    end
    entry.xp = math.max(0, math.floor(tonumber(entry.xp) or 0))
    entry.level = Config.GetLevelForXP(entry.xp)
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

local function getEntry(player, instanceId, createIfMissing)
    if not player or type(instanceId) ~= "string" or instanceId == "" then return nil end
    local tableForPlayer = playerMasteries[player]
    if not tableForPlayer then
        tableForPlayer = {}
        playerMasteries[player] = tableForPlayer
    end
    local entry = tableForPlayer[instanceId]
    if not entry and createIfMissing then
        entry = newEntry()
        tableForPlayer[instanceId] = entry
    end
    if entry then
        tableForPlayer[instanceId] = normalizeEntry(entry)
    end
    return tableForPlayer[instanceId]
end

local function ownsInstance(player, instanceId)
    local wis = getWeaponInstanceService()
    if not wis or type(instanceId) ~= "string" then return false end
    return wis:GetInstance(player, instanceId) ~= nil
end

local function getReadyRewardLevel(entry)
    if not entry then return nil end
    for _, def in ipairs(Config.Levels) do
        if def.Reward and def.Level <= (entry.level or 1) then
            local claimKey = tostring(def.Level)
            if entry.claimedRewards[claimKey] ~= true then
                return def.Level
            end
        end
    end
    return nil
end

function WeaponMasteryService:GetMasteryPayload(player, instanceId)
    local entry = getEntry(player, instanceId, false) or newEntry()
    entry = normalizeEntry(entry)

    local progress = Config.GetProgressForXP(entry.xp)
    local levelDef = Config.GetLevelDef(entry.level)

    return {
        xp = entry.xp,
        level = entry.level,
        title = levelDef and levelDef.Title or "Fresh",
        eliminations = entry.eliminations,
        mobKills = entry.mobKills,
        captures = entry.captures,
        damage = entry.damage,
        claimedRewards = copyTable(entry.claimedRewards),
        readyRewardLevel = getReadyRewardLevel(entry),
        currentLevelXP = progress.currentLevelXP,
        nextLevelXP = progress.nextLevelXP,
        nextLevel = progress.nextLevel,
        progress = progress.progress,
        maxed = progress.maxed == true,
    }
end

function WeaponMasteryService:AttachMasteryToInventory(player, inventory)
    local enriched = {}
    if type(inventory) ~= "table" then return enriched end
    for instanceId, data in pairs(inventory) do
        if type(data) == "table" then
            local copy = copyTable(data)
            copy.mastery = self:GetMasteryPayload(player, instanceId)
            enriched[instanceId] = copy
        end
    end
    return enriched
end

local function fireUpdated(player, instanceId, meta)
    if not player or not player.Parent then return end
    pcall(function()
        masteryUpdatedRE:FireClient(player, instanceId, WeaponMasteryService:GetMasteryPayload(player, instanceId), meta or {})
    end)
end

local function markDirty(player)
    if not player then return end
    dirtyPlayers[player] = true
    if saveScheduled[player] then return end
    saveScheduled[player] = true
    task.delay(SAVE_DELAY, function()
        saveScheduled[player] = nil
        if dirtyPlayers[player] and player.Parent then
            WeaponMasteryService:SaveForPlayer(player)
        end
    end)
end

local function addProgress(player, instanceId, xpAmount, statKey, statAmount, meta)
    if not player or not player.Parent then return nil end
    if type(instanceId) ~= "string" or instanceId == "" then return nil end
    if not ownsInstance(player, instanceId) then return nil end

    local entry = getEntry(player, instanceId, true)
    if not entry then return nil end

    xpAmount = math.max(0, math.floor(tonumber(xpAmount) or 0))
    statAmount = math.max(0, math.floor(tonumber(statAmount) or 0))
    local oldLevel = entry.level or 1

    if statKey and statAmount > 0 then
        entry[statKey] = math.max(0, math.floor(tonumber(entry[statKey]) or 0)) + statAmount
    end
    if xpAmount > 0 then
        entry.xp = (entry.xp or 0) + xpAmount
        entry.level = Config.GetLevelForXP(entry.xp)
    end
    entry.lastUsedAt = os.time()

    markDirty(player)

    local updateMeta = meta or {}
    updateMeta.deltaXP = xpAmount
    updateMeta.leveledUp = (entry.level or 1) > oldLevel
    if updateMeta.leveledUp then
        updateMeta.newLevel = entry.level
    end
    fireUpdated(player, instanceId, updateMeta)
    return WeaponMasteryService:GetMasteryPayload(player, instanceId)
end

function WeaponMasteryService:LoadForPlayer(player)
    if not player then return {} end
    local key = dsKey(player)
    local success, result
    for attempt = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[WeaponMasteryService] GetAsync failed (attempt " .. attempt .. "): " .. tostring(result))
        task.wait(RETRY_DELAY * attempt)
    end

    local loaded = {}
    if success and type(result) == "table" then
        for instanceId, entry in pairs(result) do
            if type(instanceId) == "string" then
                loaded[instanceId] = normalizeEntry(entry)
            end
        end
    elseif not success then
        warn("[WeaponMasteryService] Failed to load for " .. tostring(player.Name) .. "; starting empty")
    end

    playerMasteries[player] = loaded
    dirtyPlayers[player] = nil
    return loaded
end

function WeaponMasteryService:SaveForPlayer(player)
    if not player then return false end
    local data = playerMasteries[player]
    if not data then return true end
    for _, entry in pairs(data) do
        normalizeEntry(entry)
    end

    local key = dsKey(player)
    local success, err
    for attempt = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, data)
        end)
        if success then break end
        warn("[WeaponMasteryService] SetAsync failed (attempt " .. attempt .. "): " .. tostring(err))
        task.wait(RETRY_DELAY * attempt)
    end
    if success then
        dirtyPlayers[player] = nil
    else
        warn("[WeaponMasteryService] Failed to save for " .. tostring(player.Name))
    end
    return success == true
end

function WeaponMasteryService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        self:SaveForPlayer(player)
    end
end

function WeaponMasteryService:RemovePlayer(player)
    playerMasteries[player] = nil
    dirtyPlayers[player] = nil
    saveScheduled[player] = nil
end

function WeaponMasteryService:RemoveWeapon(player, instanceId)
    local data = playerMasteries[player]
    if data and data[instanceId] then
        data[instanceId] = nil
        markDirty(player)
        fireUpdated(player, instanceId, { removed = true })
        return true
    end
    return false
end

function WeaponMasteryService:RegisterElimination(player, instanceId)
    return addProgress(player, instanceId, Config.XP.PlayerElimination, "eliminations", 1, { kind = "PlayerElimination" })
end

function WeaponMasteryService:RegisterMobKill(player, instanceId)
    return addProgress(player, instanceId, Config.XP.MobKill, "mobKills", 1, { kind = "MobKill" })
end

function WeaponMasteryService:RegisterCapture(player, instanceId)
    return addProgress(player, instanceId, Config.XP.FlagCapture, "captures", 1, { kind = "FlagCapture" })
end

function WeaponMasteryService:RegisterDamage(player, instanceId, amount)
    if not player or not player.Parent then return nil end
    if type(instanceId) ~= "string" or instanceId == "" then return nil end
    if not ownsInstance(player, instanceId) then return nil end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return nil end

    local entry = getEntry(player, instanceId, true)
    if not entry then return nil end

    local beforeBucket = math.floor((entry.damage or 0) / 100)
    entry.damage = (entry.damage or 0) + amount
    entry.lastUsedAt = os.time()
    local afterBucket = math.floor((entry.damage or 0) / 100)
    local xpAmount = math.max(0, afterBucket - beforeBucket) * (Config.XP.DamagePer100 or 0)

    if xpAmount > 0 then
        local oldLevel = entry.level or 1
        entry.xp = (entry.xp or 0) + xpAmount
        entry.level = Config.GetLevelForXP(entry.xp)
        fireUpdated(player, instanceId, {
            kind = "Damage",
            deltaXP = xpAmount,
            leveledUp = (entry.level or 1) > oldLevel,
            newLevel = entry.level,
        })
    end

    markDirty(player)
    return self:GetMasteryPayload(player, instanceId)
end

function WeaponMasteryService:ClaimReward(player, instanceId, level)
    if not player or not player.Parent then return false, { reason = "No player" } end
    if type(instanceId) ~= "string" or instanceId == "" then return false, { reason = "Invalid weapon" } end
    if not ownsInstance(player, instanceId) then return false, { reason = "Weapon not found" } end

    level = math.floor(tonumber(level) or 0)
    local reward = Config.GetReward(level)
    if not reward then return false, { reason = "No reward for this level" } end

    local entry = getEntry(player, instanceId, false)
    if not entry or (entry.level or 1) < level then
        return false, { reason = "Mastery level not reached" }
    end

    local claimKey = tostring(level)
    if entry.claimedRewards[claimKey] == true then
        return false, { reason = "Reward already claimed" }
    end

    local currency = getCurrencyService()
    if currency then
        if reward.Coins and currency.AddCoins then
            pcall(function() currency:AddCoins(player, reward.Coins, "weaponMastery") end)
        end
        if reward.Salvage and currency.AddSalvage then
            pcall(function() currency:AddSalvage(player, reward.Salvage) end)
        end
    end

    entry.claimedRewards[claimKey] = true
    markDirty(player)
    self:SaveForPlayer(player)
    fireUpdated(player, instanceId, { kind = "RewardClaimed", rewardLevel = level })

    return true, {
        level = level,
        reward = copyTable(reward),
        mastery = self:GetMasteryPayload(player, instanceId),
    }
end

claimRewardRF.OnServerInvoke = function(player, instanceId, level)
    return WeaponMasteryService:ClaimReward(player, instanceId, level)
end

game:BindToClose(function()
    WeaponMasteryService:SaveAll()
end)

return WeaponMasteryService