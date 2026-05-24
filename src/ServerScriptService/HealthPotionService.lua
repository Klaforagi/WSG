local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local PotionConfig = require(ReplicatedStorage:WaitForChild("PotionConfig"))
local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local DATASTORE_NAME = "HealthPotions_v1"
local DEFAULT_POTION_ID = "health_potion"
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local OUTGOING_DAMAGE_EFFECT = "OutgoingDamageMultiplier"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local HealthPotionService = {}

local playerData = {}
local loadedPlayers = {}
local DEFEAT_LOCK_ATTR = "DefeatLockActive"
local _saveCoordinator
local stateChangedEvent = Instance.new("BindableEvent")
local effectStartedEvent = Instance.new("BindableEvent")
local activeOutgoingDamageModifiers = {}

local function getServerTime()
    local ok, result = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if ok and type(result) == "number" then
        return result
    end
    return os.time()
end

local function getSaveCoordinator()
    if _saveCoordinator == nil then
        local ok, coordinator = pcall(function()
            return require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
        end)
        if ok then
            _saveCoordinator = coordinator
        else
            _saveCoordinator = false
        end
    end

    if _saveCoordinator == false then
        return nil
    end
    return _saveCoordinator
end

local CurrencyService
local function getCurrencyService()
    if CurrencyService then
        return CurrencyService
    end

    pcall(function()
        local mod = ServerScriptService:FindFirstChild("CurrencyService")
        if mod and mod:IsA("ModuleScript") then
            CurrencyService = require(mod)
        end
    end)

    return CurrencyService
end

local function markDirty(player, reason, options)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "HealthPotions", reason or "health_potions", options)
    end
end

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

local function getPotionDefinition(potionId)
    if type(potionId) ~= "string" or potionId == "" then
        return nil
    end
    return PotionConfig.GetById(potionId)
end

local function resolvePotionId(potionId)
    local resolvedPotionId = potionId
    if type(resolvedPotionId) ~= "string" or resolvedPotionId == "" then
        resolvedPotionId = DEFAULT_POTION_ID
    end
    return getPotionDefinition(resolvedPotionId) and resolvedPotionId or nil
end

local function normalizePotionEntry(rawEntry)
    return {
        count = math.max(0, math.floor(tonumber(type(rawEntry) == "table" and rawEntry.count or 0) or 0)),
        totalGranted = math.max(0, math.floor(tonumber(type(rawEntry) == "table" and rawEntry.totalGranted or 0) or 0)),
    }
end

local function makePotionTable()
    local potions = {}
    for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
        potions[potionDef.Id] = normalizePotionEntry(nil)
    end
    return potions
end

local function makeEmptyState()
    return {
        potions = makePotionTable(),
        equippedPotionId = nil,
        cooldownEndTime = 0,
    }
end

local function sanitizeEquippedPotion(state)
    local equippedPotionId = type(state.equippedPotionId) == "string" and state.equippedPotionId or nil
    local equippedPotion = equippedPotionId and state.potions[equippedPotionId] or nil
    if not equippedPotionId or not getPotionDefinition(equippedPotionId) or type(equippedPotion) ~= "table" then
        state.equippedPotionId = nil
        return nil
    end
    if math.max(0, math.floor(tonumber(equippedPotion.count) or 0)) <= 0 then
        state.equippedPotionId = nil
        return nil
    end
    return equippedPotionId
end

local function normalizeState(raw)
    local state = makeEmptyState()
    if type(raw) ~= "table" then
        return state
    end

    if type(raw.potions) == "table" then
        for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
            state.potions[potionDef.Id] = normalizePotionEntry(raw.potions[potionDef.Id])
        end
        state.equippedPotionId = type(raw.equippedPotionId) == "string" and raw.equippedPotionId or nil
    else
        local healthEntry = state.potions[DEFAULT_POTION_ID] or normalizePotionEntry(nil)
        healthEntry.count = math.max(0, math.floor(tonumber(raw.count) or 0))
        healthEntry.totalGranted = math.max(0, math.floor(tonumber(raw.totalGranted) or 0))
        state.potions[DEFAULT_POTION_ID] = healthEntry
        if raw.equipped == true and healthEntry.count > 0 then
            state.equippedPotionId = DEFAULT_POTION_ID
        end
    end

    sanitizeEquippedPotion(state)
    return state
end

local function getSavedState(state)
    local normalized = normalizeState(state)
    local potions = {}
    for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
        local entry = normalized.potions[potionDef.Id] or normalizePotionEntry(nil)
        potions[potionDef.Id] = {
            count = math.max(0, math.floor(tonumber(entry.count) or 0)),
            totalGranted = math.max(0, math.floor(tonumber(entry.totalGranted) or 0)),
        }
    end

    return {
        potions = potions,
        equippedPotionId = sanitizeEquippedPotion(normalized),
    }
end

local function ensurePlayerData(player)
    if not playerData[player] then
        playerData[player] = makeEmptyState()
    end
    return playerData[player]
end

local function ensurePotionEntry(state, potionId)
    state.potions = type(state.potions) == "table" and state.potions or makePotionTable()
    if not state.potions[potionId] then
        state.potions[potionId] = normalizePotionEntry(nil)
    end
    return state.potions[potionId]
end

local function buildPotionSnapshot(state, potionId)
    local entry = ensurePotionEntry(state, potionId)
    local count = math.max(0, math.floor(tonumber(entry.count) or 0))
    local totalGranted = math.max(0, math.floor(tonumber(entry.totalGranted) or 0))
    return {
        count = count,
        totalGranted = totalGranted,
        equipped = state.equippedPotionId == potionId and count > 0,
    }
end

local function getStateSnapshot(player, state)
    local pd = state or ensurePlayerData(player)
    local equippedPotionId = sanitizeEquippedPotion(pd)
    local cooldownEndsAt = tonumber(pd.cooldownEndTime) or 0
    local serverTime = getServerTime()
    local potions = {}
    local counts = {}

    for _, potionDef in ipairs(PotionConfig.GetOrderedPotions()) do
        local entrySnapshot = buildPotionSnapshot(pd, potionDef.Id)
        potions[potionDef.Id] = entrySnapshot
        counts[potionDef.Id] = entrySnapshot.count
    end

    local equippedSnapshot = equippedPotionId and potions[equippedPotionId] or nil
    return {
        isLoaded = loadedPlayers[player] == true,
        potions = potions,
        counts = counts,
        equippedPotionId = equippedPotionId,
        count = equippedSnapshot and equippedSnapshot.count or 0,
        totalGranted = equippedSnapshot and equippedSnapshot.totalGranted or 0,
        equipped = equippedSnapshot ~= nil,
        cooldownEndsAt = cooldownEndsAt,
        cooldownRemaining = math.max(0, cooldownEndsAt - serverTime),
        serverTime = serverTime,
    }
end

local function fireStateChanged(player)
    if not player then
        return
    end
    stateChangedEvent:Fire(player, getStateSnapshot(player))
end

local function removeOutgoingDamageModifier(player, modifierId)
    local modifiers = activeOutgoingDamageModifiers[player]
    if not modifiers then
        return false
    end

    if modifierId then
        if not modifiers[modifierId] then
            return false
        end
        modifiers[modifierId] = nil
    else
        table.clear(modifiers)
    end

    if next(modifiers) == nil then
        activeOutgoingDamageModifiers[player] = nil
    end
    return true
end

local function scheduleOutgoingDamageExpiry(player, modifierId, token, durationSeconds)
    task.delay(durationSeconds, function()
        local modifiers = activeOutgoingDamageModifiers[player]
        local modifier = modifiers and modifiers[modifierId]
        if not modifier or modifier.token ~= token then
            return
        end
        if modifier.expiresAt > getServerTime() + 0.05 then
            return
        end
        removeOutgoingDamageModifier(player, modifierId)
    end)
end

local function applyPotionEffect(player, potionDef, humanoid)
    if potionDef.EffectType == "Heal" then
        local missingHealth = math.max(0, humanoid.MaxHealth - humanoid.Health)
        if missingHealth <= 0 then
            return false, "Health is already full", nil
        end

        local healAmount = math.min(
            missingHealth,
            math.max(1, math.floor(tonumber(potionDef.HealAmount) or 40))
        )
        humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
        return true, nil, {
            healed = healAmount,
        }
    end

    if potionDef.EffectType == "MovementSpeed" then
        local additiveBonus = tonumber(potionDef.AdditiveBonus) or 0
        local durationSeconds = math.max(0, tonumber(potionDef.DurationSeconds) or 0)
        HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, potionDef.ModifierId or potionDef.Id, {
            additive = additiveBonus,
            duration = durationSeconds > 0 and durationSeconds or nil,
            source = potionDef.DisplayName,
        })
        return true, nil, {
            additive = additiveBonus,
            duration = durationSeconds,
        }
    end

    if potionDef.EffectType == OUTGOING_DAMAGE_EFFECT then
        local durationSeconds = math.max(0, tonumber(potionDef.DurationSeconds) or 0)
        local damageMultiplier = tonumber(potionDef.DamageMultiplier) or 1
        if durationSeconds <= 0 or damageMultiplier <= 0 then
            return false, "Potion effect unavailable", nil
        end

        local modifierId = potionDef.ModifierId or potionDef.Id
        local modifiers = activeOutgoingDamageModifiers[player]
        if not modifiers then
            modifiers = {}
            activeOutgoingDamageModifiers[player] = modifiers
        end

        local existing = modifiers[modifierId]
        local token = (existing and existing.token or 0) + 1
        local expiresAt = getServerTime() + durationSeconds
        modifiers[modifierId] = {
            multiplier = damageMultiplier,
            expiresAt = expiresAt,
            token = token,
            source = potionDef.DisplayName,
        }
        scheduleOutgoingDamageExpiry(player, modifierId, token, durationSeconds)

        return true, nil, {
            duration = durationSeconds,
            multiplier = damageMultiplier,
            damageMultiplier = damageMultiplier,
            modifierId = modifierId,
            description = string.format("%s: +%d%% damage", potionDef.DisplayName or "Strength", math.floor(((damageMultiplier - 1) * 100) + 0.5)),
        }
    end

    return false, "Potion effect unavailable", nil
end

function HealthPotionService:MarkLoading(player)
    if not player then
        return
    end
    loadedPlayers[player] = false
    ensurePlayerData(player)
end

function HealthPotionService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = makeEmptyState(),
            reason = "missing player",
        }
    end

    if loadedPlayers[player] == true and playerData[player] then
        return {
            status = "existing",
            data = DataStoreOps.DeepCopy(getSavedState(playerData[player])),
        }
    end

    local key = getKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "HealthPotions/" .. key)

    if success then
        playerData[player] = normalizeState(result)
    else
        warn("[HealthPotionService] Failed to load for", player.Name, "- using defaults")
        playerData[player] = makeEmptyState()
    end
    loadedPlayers[player] = true

    if not success then
        return {
            status = "failed",
            data = DataStoreOps.DeepCopy(getSavedState(playerData[player])),
            reason = err,
        }
    end
    if result == nil then
        return {
            status = "new",
            data = DataStoreOps.DeepCopy(getSavedState(playerData[player])),
        }
    end
    return {
        status = "existing",
        data = DataStoreOps.DeepCopy(getSavedState(playerData[player])),
    }
end

function HealthPotionService:GetSaveData(player)
    if not player then
        return nil
    end
    return DataStoreOps.DeepCopy(getSavedState(playerData[player]))
end

function HealthPotionService:SaveProfileForPlayer(player, currentData)
    if not player then
        return false, "missing player"
    end

    local pd = currentData or playerData[player]
    if not pd then
        return false, "missing state"
    end

    local payload = getSavedState(pd)
    local key = getKey(player)
    local success, _, err = DataStoreOps.Update(ds, key, "HealthPotions/" .. key, function()
        return payload
    end)

    if not success then
        warn("[HealthPotionService] Failed to save for", player.Name)
    end
    return success ~= false, err
end

function HealthPotionService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

function HealthPotionService:ClearPlayer(player)
    activeOutgoingDamageModifiers[player] = nil
    playerData[player] = nil
    loadedPlayers[player] = nil
end

function HealthPotionService:ClearTemporaryPotionEffects(player)
    if not player then
        return false
    end

    local modifiers = activeOutgoingDamageModifiers[player]
    if not modifiers then
        return false
    end

    local clearedPotionIds = {}
    for modifierId in pairs(modifiers) do
        clearedPotionIds[modifierId] = true
    end
    activeOutgoingDamageModifiers[player] = nil

    local serverTime = getServerTime()
    for potionId in pairs(clearedPotionIds) do
        effectStartedEvent:Fire(player, {
            potionId = potionId,
            duration = 0,
            expiresAt = serverTime,
        })
    end
    return true
end

function HealthPotionService:GetOutgoingDamageMultiplier(player)
    local modifiers = activeOutgoingDamageModifiers[player]
    if not modifiers then
        return 1
    end

    local serverTime = getServerTime()
    local totalMultiplier = 1
    local hadExpired = false
    for modifierId, modifier in pairs(modifiers) do
        local expiresAt = tonumber(modifier.expiresAt) or 0
        if expiresAt <= serverTime then
            modifiers[modifierId] = nil
            hadExpired = true
        else
            local multiplier = tonumber(modifier.multiplier) or 1
            if multiplier > 0 then
                totalMultiplier *= multiplier
            end
        end
    end
    if hadExpired and next(modifiers) == nil then
        activeOutgoingDamageModifiers[player] = nil
    end
    return totalMultiplier
end

function HealthPotionService:ApplyOutgoingDamageModifiers(player, baseDamage, _damageContext)
    local damage = tonumber(baseDamage) or 0
    local multiplier = self:GetOutgoingDamageMultiplier(player)
    if multiplier <= 0 then
        return damage
    end
    return damage * multiplier
end

function HealthPotionService:GetPotionCount(player, potionId)
    if not player then
        return 0
    end

    local resolvedPotionId = resolvePotionId(potionId)
    if not resolvedPotionId then
        return 0
    end

    local pd = ensurePlayerData(player)
    local entry = ensurePotionEntry(pd, resolvedPotionId)
    return math.max(0, math.floor(tonumber(entry.count) or 0))
end

function HealthPotionService:GetState(player)
    return getStateSnapshot(player)
end

function HealthPotionService:GrantPotions(player, amount, potionId)
    if not player then
        return false, "missing player"
    end

    local resolvedPotionId = resolvePotionId(potionId)
    local potionDef = resolvedPotionId and getPotionDefinition(resolvedPotionId) or nil
    if not potionDef then
        return false, "invalid potion"
    end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return false, "invalid amount"
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    local entry = ensurePotionEntry(pd, resolvedPotionId)
    entry.count += amount
    entry.totalGranted += amount

    markDirty(player, resolvedPotionId .. "_grant", { force = true })
    fireStateChanged(player)

    return true, entry.count
end

function HealthPotionService:GrantPotion(player, potionId, amount)
    return self:GrantPotions(player, amount, potionId)
end

function HealthPotionService:PurchasePotion(player, potionId)
    if not player or type(potionId) ~= "string" then
        return false, "Invalid request", player and self:GetState(player) or nil
    end

    local resolvedPotionId = resolvePotionId(potionId)
    local potionDef = resolvedPotionId and getPotionDefinition(resolvedPotionId) or nil
    if not potionDef then
        return false, "Unknown potion", self:GetState(player)
    end

    if potionDef.Purchasable ~= true or potionDef.RemovedFromShop == true or potionDef.Hidden == true then
        return false, "Potion unavailable", self:GetState(player)
    end

    local price = math.floor(tonumber(potionDef.PriceCoins) or 0)
    if price <= 0 then
        return false, "Potion unavailable", self:GetState(player)
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local currencyService = getCurrencyService()
    if not currencyService or type(currencyService.GetCoins) ~= "function" then
        return false, "Currency system unavailable", self:GetState(player)
    end

    local balance = math.max(0, math.floor(tonumber(currencyService:GetCoins(player)) or 0))
    if balance < price then
        return false, "Insufficient coins", self:GetState(player)
    end

    if type(currencyService.AddCoins) == "function" then
        currencyService:AddCoins(player, -price, "potion_purchase")
    elseif type(currencyService.SetCoins) == "function" then
        currencyService:SetCoins(player, balance - price)
    else
        return false, "Currency system unavailable", self:GetState(player)
    end

    local pd = ensurePlayerData(player)
    local entry = ensurePotionEntry(pd, resolvedPotionId)
    entry.count += 1
    entry.totalGranted += 1

    markDirty(player, resolvedPotionId .. "_purchase", { force = true })
    fireStateChanged(player)

    return true, "Purchased", self:GetState(player)
end

function HealthPotionService:GetStateChangedEvent()
    return stateChangedEvent.Event
end

function HealthPotionService:GetEffectStartedEvent()
    return effectStartedEvent.Event
end

function HealthPotionService:SetEquipped(player, shouldEquip, potionId)
    if not player then
        return false, "missing player", nil
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    shouldEquip = shouldEquip == true

    if shouldEquip then
        local resolvedPotionId = resolvePotionId(potionId)
        local potionDef = resolvedPotionId and getPotionDefinition(resolvedPotionId) or nil
        if not potionDef then
            return false, "Invalid potion", self:GetState(player)
        end

        local entry = ensurePotionEntry(pd, resolvedPotionId)
        if entry.count <= 0 then
            return false, string.format("No %s owned", potionDef.DisplayName), self:GetState(player)
        end

        local changed = pd.equippedPotionId ~= resolvedPotionId
        pd.equippedPotionId = resolvedPotionId
        if changed then
            markDirty(player, resolvedPotionId .. "_equip", { force = true })
            fireStateChanged(player)
        end

        return true, string.format("%s equipped", potionDef.DisplayName), self:GetState(player)
    end

    local changed = sanitizeEquippedPotion(pd) ~= nil
    pd.equippedPotionId = nil
    if changed then
        markDirty(player, "potion_unequip", { force = true })
        fireStateChanged(player)
    end
    return true, "Potion unequipped", self:GetState(player)
end

function HealthPotionService:UseEquippedPotion(player)
    if not player then
        return false, "missing player", { state = nil }
    end

    if player:GetAttribute(DEFEAT_LOCK_ATTR) == true then
        return false, "You cannot use that right now", { state = self:GetState(player) }
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    local currentState = self:GetState(player)
    local equippedPotionId = currentState.equippedPotionId

    if not equippedPotionId then
        return false, "Equip a potion first", { state = currentState }
    end

    local potionDef = getPotionDefinition(equippedPotionId)
    if not potionDef then
        pd.equippedPotionId = nil
        fireStateChanged(player)
        return false, "Potion is unavailable", { state = self:GetState(player) }
    end

    local entry = ensurePotionEntry(pd, equippedPotionId)
    if entry.count <= 0 then
        pd.equippedPotionId = nil
        markDirty(player, equippedPotionId .. "_empty", { force = true })
        fireStateChanged(player)
        return false, string.format("No %s left", potionDef.DisplayName), { state = self:GetState(player) }
    end

    if currentState.cooldownRemaining > 0 then
        return false, "Potion is cooling down", { state = currentState }
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false, "You cannot use that right now", { state = currentState }
    end

    local ok, errorMessage, payload = applyPotionEffect(player, potionDef, humanoid)
    if not ok then
        return false, errorMessage or "Potion effect failed", { state = currentState }
    end

    entry.count = math.max(0, entry.count - 1)
    if entry.count <= 0 and pd.equippedPotionId == equippedPotionId then
        pd.equippedPotionId = nil
    end

    local cooldownSeconds = math.max(0, tonumber(potionDef.CooldownSeconds) or 0)
    pd.cooldownEndTime = getServerTime() + cooldownSeconds

    markDirty(player, equippedPotionId .. "_use", { force = true })
    fireStateChanged(player)

    payload = payload or {}
    payload.cooldown = cooldownSeconds
    payload.potionId = equippedPotionId
    payload.state = self:GetState(player)

    local effectDuration = math.max(0, tonumber(payload.duration or potionDef.DurationSeconds) or 0)
    if effectDuration > 0 then
        payload.duration = effectDuration
        payload.expiresAt = getServerTime() + effectDuration
        payload.displayName = potionDef.DisplayName
        payload.description = payload.description or potionDef.DetailText or potionDef.Description
        effectStartedEvent:Fire(player, payload)
    end

    return true, "Potion used", payload
end

return HealthPotionService