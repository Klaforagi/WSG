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
local CurrencyService
pcall(function()
    CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)
local QuestService
pcall(function()
    QuestService = require(ServerScriptService:WaitForChild("QuestService", 10))
end)

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

-- RequestBuyOrUseBoost: client requests purchase/activation of a timed boost
local buyBoostRF = Instance.new("RemoteFunction")
buyBoostRF.Name = "RequestBuyOrUseBoost"
buyBoostRF.Parent = boostFolder

-- RequestRerollQuest: client requests a reroll (passes quest index)
local rerollRF = Instance.new("RemoteFunction")
rerollRF.Name = "RequestRerollQuest"
rerollRF.Parent = boostFolder

-- RequestBonusClaim: client requests bonus claim (passes quest id)
local bonusClaimRF = Instance.new("RemoteFunction")
bonusClaimRF.Name = "RequestBonusClaim"
bonusClaimRF.Parent = boostFolder

-- GetBoostStates: client requests current boost states
local getStatesRF = Instance.new("RemoteFunction")
getStatesRF.Name = "GetBoostStates"
getStatesRF.Parent = boostFolder

-- BoostStateUpdated: server pushes state changes to client
local stateUpdatedRE = Instance.new("RemoteEvent")
stateUpdatedRE.Name = "BoostStateUpdated"
stateUpdatedRE.Parent = remotesFolder   -- placed at Remotes level for easy access

--------------------------------------------------------------------------------
-- Init BoostService (passes remote references)
--------------------------------------------------------------------------------
BoostService:Init()

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------

buyBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    return BoostService:BuyAndActivate(player, boostId)
end

rerollRF.OnServerInvoke = function(player, questIndex)
    if type(questIndex) ~= "number" then return false, "Invalid" end
    return BoostService:RerollQuest(player, questIndex)
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
Players.PlayerRemoving:Connect(function(player)
    BoostService:ClearPlayer(player)
end)

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap CurrencyService.AddCoins to apply coin multiplier
-- This is done via a wrapper so the existing callers (KillTracker, QuestService,
-- etc.) automatically get the boost applied without any changes.
--------------------------------------------------------------------------------
if CurrencyService then
    local _originalAddCoins = CurrencyService.AddCoins

    --- Wrapped AddCoins: applies coin boost multiplier to positive (reward) amounts.
    --- Returns the final amount actually added (after boost). Callers can use the
    --- return value for accurate UI display (e.g. reward popups).
    function CurrencyService:AddCoins(player, amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then
            -- Deductions (negative amounts) and zero should pass through unchanged
            _originalAddCoins(self, player, amount)
            return amount
        end

        -- Apply coin multiplier for positive (reward) amounts
        local multiplier = BoostService:GetCoinMultiplier(player)
        local boosted = math.floor(amount * multiplier)
        _originalAddCoins(self, player, boosted)
        return boosted
    end

    print("[BoostServiceInit] CurrencyService.AddCoins wrapped with boost multiplier")
end

--------------------------------------------------------------------------------
-- INTEGRATION: Wrap QuestService.IncrementQuest to apply quest progress multiplier
--------------------------------------------------------------------------------
if QuestService then
    local _originalIncrement = QuestService.IncrementQuest

    function QuestService:IncrementQuest(player, questId, amount)
        amount = tonumber(amount) or 1
        local multiplier = BoostService:GetQuestProgressMultiplier(player)
        local boosted = math.floor(amount * multiplier)
        _originalIncrement(self, player, questId, boosted)
    end

    print("[BoostServiceInit] QuestService.IncrementQuest wrapped with boost multiplier")
end

print("[BoostServiceInit] Boost system initialized")
