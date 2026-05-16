local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local SpinWheelConfig = require(ReplicatedStorage:WaitForChild("SpinWheelConfig"))

local DATASTORE_NAME = "SpinWheel_v1"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local SpinWheelService = {}

local playerData = {}
local loadedPlayers = {}
local spinLocks = {}
local randomSource = Random.new()
local _saveCoordinator
local CurrencyService

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

local function getCurrencyService()
    if CurrencyService then
        return CurrencyService
    end

    pcall(function()
        CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService"))
    end)
    return CurrencyService
end

local function markDirty(player, reason, options)
    local coordinator = getSaveCoordinator()
    if coordinator then
        coordinator:MarkDirty(player, "SpinWheel", reason or "spin_wheel", options)
    end
end

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

local function makeEmptyState()
    return {
        nextFreeSpinAt = 0,
        wheelSpins = 0,
        lastSpinAt = 0,
        lastReward = 0,
        totalSpins = 0,
    }
end

local function normalizeState(raw)
    local state = makeEmptyState()
    if type(raw) ~= "table" then
        return state
    end

    state.nextFreeSpinAt = math.max(0, math.floor(tonumber(raw.nextFreeSpinAt) or 0))
    state.wheelSpins = math.max(0, math.floor(tonumber(raw.wheelSpins) or 0))
    state.lastSpinAt = math.max(0, math.floor(tonumber(raw.lastSpinAt) or 0))
    state.lastReward = math.max(0, math.floor(tonumber(raw.lastReward) or 0))
    state.totalSpins = math.max(0, math.floor(tonumber(raw.totalSpins) or 0))
    return state
end

local function ensurePlayerData(player)
    if not playerData[player] then
        playerData[player] = makeEmptyState()
    end
    return playerData[player]
end

local function getNow()
    return os.time()
end

local function getSecondsRemaining(state, now)
    now = now or getNow()
    return math.max(0, (state.nextFreeSpinAt or 0) - now)
end

local function getSectorPayload(sectorIndex)
    local sector = SpinWheelConfig.GetRewardSector(sectorIndex)
    if not sector then
        return nil
    end

    local sectorAngle = SpinWheelConfig.GetSectorAngle()
    local landingAngle = (sectorIndex - 0.5) * sectorAngle
    return {
        sectorIndex = sectorIndex,
        sectorLabel = sector.label,
        reward = math.floor(tonumber(sector.reward) or 0),
        landingAngle = landingAngle,
    }
end

function SpinWheelService:MarkLoading(player)
    if not player then
        return
    end
    loadedPlayers[player] = false
    ensurePlayerData(player)
end

function SpinWheelService:LoadProfileForPlayer(player)
    if not player then
        return {
            status = "failed",
            data = makeEmptyState(),
            reason = "missing player",
        }
    end

    local key = getKey(player)
    local success, result, err = DataStoreOps.Load(ds, key, "SpinWheel/" .. key)

    if success then
        playerData[player] = normalizeState(result)
    else
        warn("[SpinWheelService] Failed to load for", player.Name, "- using defaults")
        playerData[player] = makeEmptyState()
    end
    loadedPlayers[player] = true

    if not success then
        return {
            status = "failed",
            data = DataStoreOps.DeepCopy(playerData[player]),
            reason = err,
        }
    end
    if result == nil then
        return {
            status = "new",
            data = DataStoreOps.DeepCopy(playerData[player]),
        }
    end
    return {
        status = "existing",
        data = DataStoreOps.DeepCopy(playerData[player]),
    }
end

function SpinWheelService:LoadForPlayer(player)
    local result = self:LoadProfileForPlayer(player)
    return result and result.status ~= "failed"
end

function SpinWheelService:GetSaveData(player)
    if not player then
        return nil
    end
    return DataStoreOps.DeepCopy(playerData[player])
end

function SpinWheelService:SaveProfileForPlayer(player, currentData)
    if not player then
        return false, "missing player"
    end

    local pd = currentData or playerData[player]
    if not pd then
        return false, "missing state"
    end

    local payload = normalizeState(pd)
    local key = getKey(player)
    local success, _, err = DataStoreOps.Update(ds, key, "SpinWheel/" .. key, function()
        return payload
    end)

    if not success then
        warn("[SpinWheelService] Failed to save for", player.Name)
    end
    return success ~= false, err
end

function SpinWheelService:SaveForPlayer(player)
    return self:SaveProfileForPlayer(player)
end

function SpinWheelService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(function()
            self:SaveForPlayer(player)
        end)
    end
end

function SpinWheelService:ClearPlayer(player)
    playerData[player] = nil
    loadedPlayers[player] = nil
    spinLocks[player] = nil
end

function SpinWheelService:GetState(player)
    local now = getNow()
    if loadedPlayers[player] ~= true then
        return {
            isLoaded = false,
            canSpinNow = false,
            canUseFreeSpin = false,
            canUsePaidSpin = false,
            canAttemptSpin = false,
            serverTime = now,
            nextFreeSpinAt = 0,
            secondsRemaining = 0,
            cooldownSeconds = SpinWheelConfig.CooldownSeconds,
            wheelSpins = 0,
            lastSpinAt = 0,
            lastReward = 0,
            totalSpins = 0,
            rewardSectors = SpinWheelConfig.RewardSectors,
            spinPacks = SpinWheelConfig.SpinPacks,
            modelName = SpinWheelConfig.ModelName,
        }
    end

    local pd = ensurePlayerData(player)
    local secondsRemaining = getSecondsRemaining(pd, now)
    local canUseFreeSpin = secondsRemaining <= 0
    local canUsePaidSpin = (pd.wheelSpins or 0) > 0

    return {
        isLoaded = true,
        canSpinNow = canUseFreeSpin,
        canUseFreeSpin = canUseFreeSpin,
        canUsePaidSpin = canUsePaidSpin,
        canAttemptSpin = canUseFreeSpin or canUsePaidSpin,
        serverTime = now,
        nextFreeSpinAt = pd.nextFreeSpinAt,
        secondsRemaining = secondsRemaining,
        cooldownSeconds = SpinWheelConfig.CooldownSeconds,
        wheelSpins = pd.wheelSpins,
        lastSpinAt = pd.lastSpinAt,
        lastReward = pd.lastReward,
        totalSpins = pd.totalSpins,
        rewardSectors = SpinWheelConfig.RewardSectors,
        spinPacks = SpinWheelConfig.SpinPacks,
        modelName = SpinWheelConfig.ModelName,
    }
end

function SpinWheelService:RequestSpin(player)
    if not player then
        return false, "Invalid player", { canSpinNow = false }
    end

    if loadedPlayers[player] ~= true then
        return false, "Loading spin data", {
            reasonCode = "loading",
            state = self:GetState(player),
        }
    end

    if spinLocks[player] then
        return false, "Spin already in progress", {
            reasonCode = "busy",
            state = self:GetState(player),
        }
    end

    spinLocks[player] = true

    local pd = ensurePlayerData(player)
    local now = getNow()
    local secondsRemaining = getSecondsRemaining(pd, now)
    local spinSource = nil
    if secondsRemaining <= 0 then
        spinSource = "free"
        pd.nextFreeSpinAt = now + SpinWheelConfig.CooldownSeconds
    elseif (pd.wheelSpins or 0) > 0 then
        spinSource = "paid"
        pd.wheelSpins = math.max(0, pd.wheelSpins - 1)
    else
        spinLocks[player] = nil
        return false, "You are out of Wheel Spins", {
            reasonCode = "purchase_required",
            state = self:GetState(player),
        }
    end

    local currencyService = getCurrencyService()
    if not currencyService then
        spinLocks[player] = nil
        return false, "CurrencyService unavailable", {
            reasonCode = "currency_unavailable",
            state = self:GetState(player),
        }
    end

    local sectorIndex = randomSource:NextInteger(1, SpinWheelConfig.GetSectorCount())
    local sectorPayload = getSectorPayload(sectorIndex)
    if not sectorPayload then
        spinLocks[player] = nil
        return false, "Invalid reward sector", {
            reasonCode = "invalid_sector",
            state = self:GetState(player),
        }
    end

    currencyService:AddCoins(player, sectorPayload.reward, "spin_wheel")

    pd.lastSpinAt = now
    pd.lastReward = sectorPayload.reward
    pd.totalSpins += 1

    markDirty(player, spinSource == "free" and "spin_wheel_free" or "spin_wheel_paid", { force = true })

    local updatedState = self:GetState(player)
    spinLocks[player] = nil

    return true, "Spin granted", {
        reward = sectorPayload.reward,
        sectorLabel = sectorPayload.sectorLabel,
        sectorIndex = sectorPayload.sectorIndex,
        landingAngle = sectorPayload.landingAngle,
        spinSource = spinSource,
        spinDuration = SpinWheelConfig.SpinDuration,
        fullRotations = SpinWheelConfig.FullRotations,
        nextFreeSpinAt = pd.nextFreeSpinAt,
        state = updatedState,
    }
end

function SpinWheelService:GrantSpinPack(player, packIndex)
    if not player then
        return false, "Invalid player", {
            reasonCode = "invalid_player",
            state = { isLoaded = false },
        }
    end

    if loadedPlayers[player] ~= true then
        return false, "Loading spin data", {
            reasonCode = "loading",
            state = self:GetState(player),
        }
    end

    local pack = SpinWheelConfig.GetSpinPack(packIndex)
    if type(pack) ~= "table" then
        return false, "Invalid Wheel Spin pack", {
            reasonCode = "invalid_pack",
            state = self:GetState(player),
        }
    end

    local spinsGranted = math.max(0, math.floor(tonumber(pack.spins) or 0))
    if spinsGranted <= 0 then
        return false, "Invalid Wheel Spin amount", {
            reasonCode = "invalid_amount",
            state = self:GetState(player),
        }
    end

    local pd = ensurePlayerData(player)
    pd.wheelSpins += spinsGranted
    markDirty(player, "spin_wheel_pack_grant", { force = true })

    return true, string.format("Added %d Wheel Spins", spinsGranted), {
        packIndex = packIndex,
        spinsGranted = spinsGranted,
        state = self:GetState(player),
    }
end

return SpinWheelService