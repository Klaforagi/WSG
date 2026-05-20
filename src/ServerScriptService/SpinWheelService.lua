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
local CrateService
local HealthPotionService

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

local function getCrateService()
    if CrateService then
        return CrateService
    end

    pcall(function()
        CrateService = require(ServerScriptService:WaitForChild("CrateService"))
    end)
    return CrateService
end

local function getHealthPotionService()
    if HealthPotionService then
        return HealthPotionService
    end

    pcall(function()
        HealthPotionService = require(ServerScriptService:WaitForChild("HealthPotionService"))
    end)
    return HealthPotionService
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

local function makeEmptyRewardState()
    return {
        rewardType = "",
        rewardText = "",
        amount = 0,
        sliceId = "",
        sliceLabel = "",
        crateType = "",
    }
end

local function normalizeRewardState(raw)
    local rewardState = makeEmptyRewardState()

    if type(raw) == "number" then
        local amount = math.max(0, math.floor(tonumber(raw) or 0))
        rewardState.rewardType = amount > 0 and "coins" or ""
        rewardState.rewardText = amount > 0 and string.format("%d Coins", amount) or ""
        rewardState.amount = amount
        return rewardState
    end

    if type(raw) ~= "table" then
        return rewardState
    end

    rewardState.rewardType = type(raw.rewardType) == "string" and raw.rewardType or ""
    rewardState.rewardText = type(raw.rewardText) == "string" and raw.rewardText or ""
    rewardState.amount = math.max(0, math.floor(tonumber(raw.amount) or 0))
    rewardState.sliceId = type(raw.sliceId) == "string" and raw.sliceId or ""
    rewardState.sliceLabel = type(raw.sliceLabel) == "string" and raw.sliceLabel or ""
    rewardState.crateType = type(raw.crateType) == "string" and raw.crateType or ""
    return rewardState
end

local function buildRewardState(slice, rewardType, rewardText, amount, crateType)
    local rewardState = makeEmptyRewardState()
    rewardState.rewardType = type(rewardType) == "string" and rewardType or ""
    rewardState.rewardText = type(rewardText) == "string" and rewardText or ""
    rewardState.amount = math.max(0, math.floor(tonumber(amount) or 0))
    rewardState.sliceId = type(slice) == "table" and (slice.id or "") or ""
    rewardState.sliceLabel = type(slice) == "table" and (slice.label or "") or ""
    rewardState.crateType = type(crateType) == "string" and crateType or ""
    return rewardState
end

local function formatCountLabel(amount, singularLabel, pluralLabel)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 1 then
        return string.format("1 %s", singularLabel)
    end
    return string.format("%d %s", amount, pluralLabel)
end

local function normalizeOptionalText(value)
    if type(value) ~= "string" then
        return ""
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "None" then
        return ""
    end
    return value
end

local function getSpinAnnouncementDelaySeconds(rewardType)
    local startupDuration = (tonumber(SpinWheelConfig.LightShowStartDuration) or 0) + 0.5
    local spinDuration = tonumber(SpinWheelConfig.SpinDuration) or 0
    local totalDelay = startupDuration + spinDuration
    if rewardType == "crate" then
        totalDelay += 3.9
    end
    return math.max(0, totalDelay)
end

local function formatWeaponRewardText(rewardData)
    if type(rewardData) ~= "table" then
        return ""
    end

    local weaponName = normalizeOptionalText(rewardData.weaponName)
    if weaponName == "" then
        return ""
    end

    local parts = {}
    local sizePercent = math.max(0, math.floor(tonumber(rewardData.sizePercent) or 0))
    if sizePercent > 0 then
        table.insert(parts, string.format("%d%%", sizePercent))
    end

    local enchantName = normalizeOptionalText(rewardData.enchantName)
    if enchantName ~= "" then
        table.insert(parts, enchantName)
    end

    table.insert(parts, weaponName)
    return table.concat(parts, " ")
end

local function buildChatAnnouncement(player, rewardResult)
    if not player or type(rewardResult) ~= "table" then
        return nil
    end

    if rewardResult.rewardType == "crate" then
        local rewardData = type(rewardResult.rewardData) == "table" and rewardResult.rewardData or nil
        local weaponText = formatWeaponRewardText(rewardData)
        if weaponText == "" then
            return nil
        end

        local rarity = normalizeOptionalText(rewardData and rewardData.rarity)
        if string.lower(rarity) == "legendary" then
            return {
                scope = "global",
                text = string.format("%s has won %s!", player.Name, weaponText),
                bodyText = string.format("%s has won ", player.Name),
                highlightText = weaponText,
                highlightRarity = rarity,
                suffixText = "!",
                delaySeconds = getSpinAnnouncementDelaySeconds("crate"),
            }
        end

        return {
            scope = "local",
            text = string.format("You won %s!", weaponText),
            bodyText = "You won ",
            highlightText = weaponText,
            highlightRarity = rarity,
            suffixText = "!",
        }
    end

    local rewardText = normalizeOptionalText(rewardResult.rewardText)
    if rewardText == "" then
        return nil
    end

    return {
        scope = "local",
        text = string.format("You won %s!", rewardText),
        bodyText = string.format("You won %s!", rewardText),
    }
end

local function grantCurrencyReward(player, amount, addMethodName, rewardType, rewardText, source)
    local currencyService = getCurrencyService()
    if not currencyService or type(currencyService[addMethodName]) ~= "function" then
        return false, rewardText .. " unavailable", "currency_unavailable"
    end

    local ok, err = pcall(function()
        if addMethodName == "AddCoins" then
            currencyService:AddCoins(player, amount, source or "spin_wheel")
        else
            currencyService[addMethodName](currencyService, player, amount)
        end
    end)
    if not ok then
        warn("[SpinWheelService] Failed to grant reward:", tostring(err))
        return false, rewardText .. " unavailable", "grant_failed"
    end

    return true, {
        rewardType = rewardType,
        rewardAmount = amount,
        rewardText = rewardText,
    }
end

local function grantRewardForSlice(player, slice)
    if type(slice) ~= "table" then
        return false, "Invalid reward slice", "invalid_slice"
    end

    if slice.rewardType == "coins" then
        local rewardEntry = SpinWheelConfig.RollWeightedReward(slice.rewards or {}, randomSource)
        local amount = rewardEntry and math.max(0, math.floor(tonumber(rewardEntry.amount) or 0)) or 0
        if amount <= 0 then
            return false, "Invalid coin reward", "invalid_reward"
        end
        return grantCurrencyReward(player, amount, "AddCoins", "coins", string.format("%d Coins", amount), "spin_wheel")
    end

    if slice.rewardType == "scrap" then
        local rewardEntry = SpinWheelConfig.RollWeightedReward(slice.rewards or {}, randomSource)
        local amount = rewardEntry and math.max(0, math.floor(tonumber(rewardEntry.amount) or 0)) or 0
        if amount <= 0 then
            return false, "Invalid shard reward", "invalid_reward"
        end
        return grantCurrencyReward(player, amount, "AddSalvage", "scrap", string.format("%d Shards", amount))
    end

    if slice.rewardType == "keys" then
        local amount = math.max(0, math.floor(tonumber(slice.amount) or 0))
        if amount <= 0 then
            return false, "Invalid key reward", "invalid_reward"
        end
        return grantCurrencyReward(player, amount, "AddKeys", "keys", formatCountLabel(amount, "Key", "Keys"))
    end

    if slice.rewardType == "health_potions" then
        local rewardEntry = SpinWheelConfig.RollWeightedReward(slice.rewards or {}, randomSource)
        local amount = rewardEntry and math.max(0, math.floor(tonumber(rewardEntry.amount) or 0)) or 0
        local potionService = getHealthPotionService()
        if amount <= 0 or not potionService or type(potionService.GrantPotions) ~= "function" then
            return false, "Health Potions unavailable", "health_potions_unavailable"
        end

        local ok, granted = pcall(function()
            return potionService:GrantPotions(player, amount)
        end)
        if not ok or granted == false then
            return false, "Health Potions unavailable", "health_potions_unavailable"
        end

        return true, {
            rewardType = "health_potions",
            rewardAmount = amount,
            rewardText = formatCountLabel(amount, "Health Potion", "Health Potions"),
        }
    end

    if slice.rewardType == "crate" then
        local crateService = getCrateService()
        if not crateService or type(crateService.RollAndPend) ~= "function" then
            return false, "Chest reward unavailable", "crate_unavailable"
        end

        local ok, success, result = pcall(function()
            return crateService:RollAndPend(player, slice.crateId)
        end)
        if not ok then
            warn("[SpinWheelService] Crate reward failed:", tostring(success))
            return false, "Chest reward unavailable", "crate_unavailable"
        end
        if success ~= true or type(result) ~= "table" then
            return false, type(result) == "string" and result or "Chest reward unavailable", "crate_unavailable"
        end

        return true, {
            rewardType = "crate",
            rewardAmount = 0,
            rewardText = slice.label or "Chest Reward",
            rewardData = result,
            crateType = result.crateType or slice.crateId,
        }
    end

    return false, "Unsupported reward", "unsupported_reward"
end

local function makeEmptyState()
    return {
        nextFreeSpinAt = 0,
        wheelSpins = 0,
        lastSpinAt = 0,
        lastReward = makeEmptyRewardState(),
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
    state.lastReward = normalizeRewardState(raw.lastReward)
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

local function getSlicePayload(slice)
    if type(slice) ~= "table" then
        return nil
    end

    local landingAngle = SpinWheelConfig.RollLandingAngle(slice, randomSource, SpinWheelConfig.LandingPaddingDegrees)
    if type(landingAngle) ~= "number" then
        return nil
    end

    return {
        sliceId = slice.id,
        sliceLabel = slice.label,
        rewardType = slice.rewardType,
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
            lastReward = makeEmptyRewardState(),
            totalSpins = 0,
            rewardSlices = SpinWheelConfig.RewardSlices,
            rewardSectors = SpinWheelConfig.RewardSlices,
            tickBoundaryAngles = SpinWheelConfig.GetTickBoundaryAngles(),
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
        rewardSlices = SpinWheelConfig.RewardSlices,
        rewardSectors = SpinWheelConfig.RewardSlices,
        tickBoundaryAngles = SpinWheelConfig.GetTickBoundaryAngles(),
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
    elseif (pd.wheelSpins or 0) > 0 then
        spinSource = "paid"
    else
        spinLocks[player] = nil
        return false, "You are out of Wheel Spins", {
            reasonCode = "purchase_required",
            state = self:GetState(player),
        }
    end

    local slice = SpinWheelConfig.RollWeightedReward(SpinWheelConfig.RewardSlices, randomSource)
    local slicePayload = getSlicePayload(slice)
    if not slicePayload then
        spinLocks[player] = nil
        return false, "Invalid reward slice", {
            reasonCode = "invalid_slice",
            state = self:GetState(player),
        }
    end

    local granted, rewardResult, reasonCode = grantRewardForSlice(player, slice)
    if granted ~= true then
        spinLocks[player] = nil
        return false, rewardResult or "Reward unavailable", {
            reasonCode = reasonCode or "reward_unavailable",
            state = self:GetState(player),
        }
    end

    if spinSource == "free" then
        pd.nextFreeSpinAt = now + SpinWheelConfig.CooldownSeconds
    else
        pd.wheelSpins = math.max(0, pd.wheelSpins - 1)
    end

    pd.lastSpinAt = now
    pd.lastReward = buildRewardState(slice, rewardResult.rewardType, rewardResult.rewardText, rewardResult.rewardAmount, rewardResult.crateType)
    pd.totalSpins += 1

    markDirty(player, spinSource == "free" and "spin_wheel_free" or "spin_wheel_paid", { force = true })

    local updatedState = self:GetState(player)
    local chatAnnouncement = buildChatAnnouncement(player, rewardResult)
    spinLocks[player] = nil

    return true, "Spin granted", {
        reward = rewardResult.rewardAmount,
        rewardType = rewardResult.rewardType,
        rewardText = rewardResult.rewardText,
        rewardData = rewardResult.rewardData,
        crateType = rewardResult.crateType,
        sliceId = slicePayload.sliceId,
        sliceLabel = slicePayload.sliceLabel,
        sectorLabel = slicePayload.sliceLabel,
        landingAngle = slicePayload.landingAngle,
        spinSource = spinSource,
        spinDuration = SpinWheelConfig.SpinDuration,
        fullRotations = SpinWheelConfig.FullRotations,
        chatAnnouncement = chatAnnouncement,
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