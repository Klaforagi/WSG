--------------------------------------------------------------------------------
-- BoostServiceInit.server.lua
-- Creates remotes and wires BoostService into the game.
-- Handles: purchase/activation, reroll, bonus claim, state queries.
-- Integrates coin multiplier into CurrencyService.AddCoins and quest
-- progress multiplier into QuestService.IncrementQuest.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Require modules
--------------------------------------------------------------------------------
local BoostService  = require(ServerScriptService:WaitForChild("BoostService", 10))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local CurrencyService
pcall(function()
    CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)
local QuestService
pcall(function()
    QuestService = require(ServerScriptService:WaitForChild("QuestService", 10))
end)
local AchievementService
pcall(function()
    AchievementService = require(ServerScriptService:WaitForChild("AchievementService", 10))
end)

local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing
    end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

-- Boosts sub-folder
local boostFolder = remotesFolder:FindFirstChild("Boosts")
if not boostFolder then
    boostFolder = Instance.new("Folder")
    boostFolder.Name = "Boosts"
    boostFolder.Parent = remotesFolder
end

-- Legacy purchase alias kept for compatibility with older clients.
local buyBoostRF = ensureInstance(boostFolder, "RemoteFunction", "RequestBuyOrUseBoost")

-- Primary purchase remote for Shop > Boosts.
local purchaseBoostRF = ensureInstance(boostFolder, "RemoteFunction", "PurchaseBoost")

-- Activation remote for Inventory > Boosts.
local activateBoostRF = ensureInstance(boostFolder, "RemoteFunction", "ActivateInventoryBoost")

-- RequestBonusClaim: client requests bonus claim (passes quest id)
local bonusClaimRF = ensureInstance(boostFolder, "RemoteFunction", "RequestBonusClaim")

-- GetBoostStates: client requests current boost states
local getStatesRF = ensureInstance(boostFolder, "RemoteFunction", "GetBoostStates")

-- BoostStateUpdated: server pushes state changes to client
local stateUpdatedRE = ensureInstance(remotesFolder, "RemoteEvent", "BoostStateUpdated")
local boostSectionRegistered = false

local function validateBoostData(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end
    local previousOwned = 0
    local newOwned = 0
    if type(lastGoodData.inventory) == "table" then
        for _, amount in pairs(lastGoodData.inventory) do
            if (tonumber(amount) or 0) > 0 then
                previousOwned += 1
            end
        end
    end
    if type(currentData.inventory) == "table" then
        for _, amount in pairs(currentData.inventory) do
            if (tonumber(amount) or 0) > 0 then
                newOwned += 1
            end
        end
    end
    if previousOwned > 0 and newOwned == 0 and (tonumber(currentData.freeRerolls) or 0) == 0 then
        return {
            suspicious = true,
            severity = "warning",
            reason = "boost inventory became empty",
        }
    end
    return nil
end

local function registerBoostSection()
    if boostSectionRegistered then
        return
    end
    boostSectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "Boost",
        Priority = 35,
        Critical = false,
        Load = function(player)
            return BoostService:LoadProfileForPlayer(player)
        end,
        GetSaveData = function(player)
            return BoostService:GetSaveData(player)
        end,
        Save = function(player, currentData, lastGoodData)
            return BoostService:SaveProfileForPlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            BoostService:ClearPlayer(player)
        end,
        Validate = validateBoostData,
    })
end

--------------------------------------------------------------------------------
-- Init BoostService (passes remote references)
--------------------------------------------------------------------------------
registerBoostSection()
BoostService:Init()

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------

buyBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    local ok, msg = BoostService:PurchaseOwnedBoost(player, boostId)
    if ok and AchievementService then
        pcall(function() AchievementService:IncrementStat(player, "totalPurchases", 1) end)
    end
    return ok, msg
end

purchaseBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    local ok, msg = BoostService:PurchaseOwnedBoost(player, boostId)
    if ok and AchievementService then
        pcall(function() AchievementService:IncrementStat(player, "totalPurchases", 1) end)
    end
    return ok, msg
end

activateBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    return BoostService:ActivateOwnedBoost(player, boostId)
end

bonusClaimRF.OnServerInvoke = function(player, questId)
    if type(questId) ~= "string" then return false, "Invalid" end
    return BoostService:BonusClaim(player, questId)
end

getStatesRF.OnServerInvoke = function(player)
    return BoostService:GetPlayerBoostStates(player)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function()
end)

Players.PlayerAdded:Connect(function(player)
    DataSaveCoordinator:LoadSection(player, "Boost")
end)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        DataSaveCoordinator:LoadSection(player, "Boost")
    end)
end

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap CurrencyService.AddCoins to apply coin multiplier
-- This is done via a wrapper so tagged gameplay/event rewards automatically get
-- the boost without letting large claim rewards or purchases inflate.
--------------------------------------------------------------------------------
if CurrencyService then
    local _originalAddCoins = CurrencyService.AddCoins
    local BOOSTED_COIN_SOURCES = {
        elimination = true,
        objective = true,
        GoldRushPickup = true,
        GoldRushObjective = true,
        MeteorShard = true,
        MeteorShowerObjective = true,
    }

    --- Wrapped AddCoins: applies coin boost multiplier to positive gameplay/event amounts.
    --- Returns the final amount actually added (after boost). Callers can use the
    --- return value for accurate UI display (e.g. reward popups).
    --- Optional 3rd param `source` is passed through for upstream wrappers.
    function CurrencyService:AddCoins(player, amount, source)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then
            -- Deductions (negative amounts) and zero should pass through unchanged
            _originalAddCoins(self, player, amount, source)
            return amount
        end

        -- Apply coin multiplier only to active gameplay/event rewards.
        local shouldBoost = type(source) == "string" and BOOSTED_COIN_SOURCES[source] == true
        local multiplier = shouldBoost and BoostService:GetCoinMultiplier(player) or 1
        local boosted = math.floor(amount * multiplier)
        _originalAddCoins(self, player, boosted, source)
        return boosted
    end

    print("[BoostServiceInit] CurrencyService.AddCoins wrapped with source-aware boost multiplier")
end

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap QuestService.IncrementQuest to apply quest progress multiplier
--------------------------------------------------------------------------------
if QuestService then
    local _originalIncrement = QuestService.IncrementQuest
    local _originalIncrementByType = QuestService.IncrementByType

    function QuestService:IncrementQuest(player, questId, amount)
        amount = tonumber(amount) or 1
        local multiplier = BoostService:GetQuestProgressMultiplier(player)
        local boosted = math.floor(amount * multiplier)
        _originalIncrement(self, player, questId, boosted)
    end

    function QuestService:IncrementByType(player, trackType, amount)
        amount = tonumber(amount) or 1
        local multiplier = BoostService:GetQuestProgressMultiplier(player)
        local boosted = math.floor(amount * multiplier)
        _originalIncrementByType(self, player, trackType, boosted)
    end

    print("[BoostServiceInit] QuestService increment functions wrapped with boost multiplier")
end

print("[BoostServiceInit] Boost system initialized")
