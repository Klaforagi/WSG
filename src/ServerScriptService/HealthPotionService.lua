local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local HealthPotionConfig = require(ReplicatedStorage:WaitForChild("HealthPotionConfig"))

local DATASTORE_NAME = "HealthPotions_v1"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local HealthPotionService = {}

local playerData = {}
local loadedPlayers = {}
local _saveCoordinator
local stateChangedEvent = Instance.new("BindableEvent")

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

local function markDirty(player, reason, options)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "HealthPotions", reason or "health_potions", options)
    end
end

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

local function makeEmptyState()
    return {
        count = 0,
        totalGranted = 0,
        equipped = false,
        cooldownEndTime = 0,
    }
end

local function normalizeState(raw)
    local state = makeEmptyState()
    if type(raw) ~= "table" then
        return state
    end

    state.count = math.max(0, math.floor(tonumber(raw.count) or 0))
    state.totalGranted = math.max(0, math.floor(tonumber(raw.totalGranted) or 0))
    state.equipped = raw.equipped == true and state.count > 0
    return state
end

local function getSavedState(state)
    local normalized = normalizeState(state)
    return {
        count = normalized.count,
        totalGranted = normalized.totalGranted,
        equipped = normalized.equipped == true and normalized.count > 0,
    }
end

local function ensurePlayerData(player)
    if not playerData[player] then
        playerData[player] = makeEmptyState()
    end
    return playerData[player]
end

local function getStateSnapshot(player, state)
    local pd = state or ensurePlayerData(player)
    if pd.count <= 0 then
        pd.equipped = false
    end

    local cooldownEndsAt = tonumber(pd.cooldownEndTime) or 0
    local serverTime = getServerTime()
    return {
        isLoaded = loadedPlayers[player] == true,
        count = math.max(0, math.floor(tonumber(pd.count) or 0)),
        totalGranted = math.max(0, math.floor(tonumber(pd.totalGranted) or 0)),
        equipped = pd.equipped == true and math.max(0, math.floor(tonumber(pd.count) or 0)) > 0,
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
    playerData[player] = nil
    loadedPlayers[player] = nil
end

function HealthPotionService:GetPotionCount(player)
    if not player then
        return 0
    end
    local pd = ensurePlayerData(player)
    return math.max(0, math.floor(tonumber(pd.count) or 0))
end

function HealthPotionService:GetState(player)
    return getStateSnapshot(player)
end

function HealthPotionService:GrantPotions(player, amount)
    if not player then
        return false, "missing player"
    end

    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return false, "invalid amount"
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    pd.count += amount
    pd.totalGranted += amount
    markDirty(player, "health_potions_grant", { force = true })
    fireStateChanged(player)

    return true, pd.count
end

function HealthPotionService:GetStateChangedEvent()
    return stateChangedEvent.Event
end

function HealthPotionService:SetEquipped(player, shouldEquip)
    if not player then
        return false, "missing player", nil
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    shouldEquip = shouldEquip == true

    if shouldEquip and pd.count <= 0 then
        return false, "No Health Potions owned", self:GetState(player)
    end

    if pd.count <= 0 then
        shouldEquip = false
    end

    local changed = pd.equipped ~= shouldEquip
    pd.equipped = shouldEquip

    if changed then
        markDirty(player, "health_potions_equip", { force = true })
        fireStateChanged(player)
    end

    return true, shouldEquip and "Potion equipped" or "Potion unequipped", self:GetState(player)
end

function HealthPotionService:UseEquippedPotion(player)
    if not player then
        return false, "missing player", { state = nil }
    end

    if loadedPlayers[player] ~= true then
        self:LoadProfileForPlayer(player)
    end

    local pd = ensurePlayerData(player)
    local currentState = self:GetState(player)

    if pd.count <= 0 then
        pd.equipped = false
        markDirty(player, "health_potions_empty", { force = true })
        fireStateChanged(player)
        return false, "No Health Potions left", { state = self:GetState(player) }
    end

    if pd.equipped ~= true then
        return false, "Equip a Health Potion first", { state = currentState }
    end

    if currentState.cooldownRemaining > 0 then
        return false, "Potion is cooling down", { state = currentState }
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false, "You cannot use that right now", { state = currentState }
    end

    local missingHealth = math.max(0, humanoid.MaxHealth - humanoid.Health)
    if missingHealth <= 0 then
        return false, "Health is already full", { state = currentState }
    end

    local healAmount = math.min(
        missingHealth,
        math.max(1, math.floor(tonumber(HealthPotionConfig.HealAmount) or 40))
    )
    humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)

    pd.count = math.max(0, pd.count - 1)
    if pd.count <= 0 then
        pd.equipped = false
    end
    pd.cooldownEndTime = getServerTime() + math.max(0, tonumber(HealthPotionConfig.CooldownSeconds) or 0)

    markDirty(player, "health_potions_use", { force = true })
    fireStateChanged(player)

    return true, "Potion used", {
        healed = healAmount,
        cooldown = math.max(0, tonumber(HealthPotionConfig.CooldownSeconds) or 0),
        state = self:GetState(player),
    }
end

return HealthPotionService