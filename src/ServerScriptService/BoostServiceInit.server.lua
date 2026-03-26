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

--------------------------------------------------------------------------------
-- Init BoostService (passes remote references)
--------------------------------------------------------------------------------
BoostService:Init()

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------

buyBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    return BoostService:PurchaseOwnedBoost(player, boostId)
end

purchaseBoostRF.OnServerInvoke = function(player, boostId)
    if type(boostId) ~= "string" then return false, "Invalid" end
    return BoostService:PurchaseOwnedBoost(player, boostId)
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
local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

Players.PlayerRemoving:Connect(function(player)
    if SaveGuard:ClaimSave(player, "Boost") then
        BoostService:SaveForPlayer(player)
        SaveGuard:ReleaseSave(player, "Boost")
    end
    BoostService:ClearPlayer(player)
end)

Players.PlayerAdded:Connect(function(player)
    BoostService:LoadForPlayer(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        BoostService:LoadForPlayer(player)
    end)
end

game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if SaveGuard:ClaimSave(p, "Boost") then
                BoostService:SaveForPlayer(p)
                SaveGuard:ReleaseSave(p, "Boost")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
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
    --- Optional 3rd param `source` is passed through for upstream wrappers.
    function CurrencyService:AddCoins(player, amount, source)
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
