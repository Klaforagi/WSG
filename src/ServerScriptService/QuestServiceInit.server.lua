--------------------------------------------------------------------------------
-- QuestServiceInit.server.lua
-- Creates remotes and hooks quest progress into the centralized StatService
-- event pipeline. All gameplay events (kills, flags, etc.) flow through
-- StatService, and this script subscribes to route them to daily quest progress.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require modules
local QuestService = require(ServerScriptService:WaitForChild("QuestService", 10))
local StatService  = require(ServerScriptService:WaitForChild("StatService", 10))
local BoostService = require(ServerScriptService:WaitForChild("BoostService", 10))

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

local questsFolder = ensureInstance(remotesFolder, "Folder", "Quests")

-- GetQuests: client asks for the full quest list
local getQuestsRF = ensureInstance(questsFolder, "RemoteFunction", "GetQuests")

-- QuestProgress: server pushes live progress updates to client
local questProgressRE = ensureInstance(questsFolder, "RemoteEvent", "QuestProgress")

-- ClaimQuest: client requests reward claim
local claimQuestRF = ensureInstance(questsFolder, "RemoteFunction", "ClaimQuest")

-- RequestRerollDailyQuest: client requests a daily quest reroll (passes quest index)
local rerollDailyRF = ensureInstance(questsFolder, "RemoteFunction", "RequestRerollDailyQuest")

-- GetRerollCooldowns: client queries current reroll cooldown state
local getRerollCooldownsRF = ensureInstance(questsFolder, "RemoteFunction", "GetRerollCooldowns")

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------
getQuestsRF.OnServerInvoke = function(player)
    return QuestService:GetQuestsForPlayer(player)
end

claimQuestRF.OnServerInvoke = function(player, questId)
    if type(questId) ~= "string" then return false end
    local result = QuestService:ClaimReward(player, questId)
    if result and StatService then
        pcall(function() StatService:RegisterQuestClaimed(player) end)
    end
    return result
end

rerollDailyRF.OnServerInvoke = function(player, questIndex)
    if type(questIndex) ~= "number" then
        return false, "Invalid"
    end
    return BoostService:RerollQuest(player, "daily", questIndex)
end

getRerollCooldownsRF.OnServerInvoke = function(player)
    return BoostService:GetRerollCooldowns(player)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    QuestService:ClearPlayer(player)
end)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events  (replaces ALL legacy hooks)
--
-- Daily quest track types:
--   MobKill      → zombies_eliminated
--   Elimination  → players_eliminated
--   MatchPlayed  → matches_played
--   DamageDealt  → damage_dealt
--   CoinsEarned  → coins_earned
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    local amount = payload.amount or 1
    if not player or not player:IsA("Player") then return end

    if action == Actions.MobKill then
        QuestService:IncrementByType(player, "zombies_eliminated", 1)
    elseif action == Actions.Elimination then
        QuestService:IncrementByType(player, "players_eliminated", 1)
    elseif action == Actions.MatchPlayed then
        QuestService:IncrementByType(player, "matches_played", 1)
    elseif action == Actions.DamageDealt then
        QuestService:IncrementByType(player, "damage_dealt", amount)
    elseif action == Actions.CoinsEarned then
        QuestService:IncrementByType(player, "coins_earned", amount)
    end
end)

--------------------------------------------------------------------------------
-- Hook: Wrap CurrencyService.AddCoins to fire CoinsEarned stat events.
-- Delayed to wrap AFTER BoostServiceInit's coin multiplier wrapper.
-- Excludes quest/achievement rewards to prevent feedback loops.
--------------------------------------------------------------------------------
task.spawn(function()
    task.wait(3) -- Wait for BoostServiceInit wrapper to be applied first

    local CurrencyService
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("CurrencyService")
        if mod and mod:IsA("ModuleScript") then
            CurrencyService = require(mod)
        end
    end)

    if CurrencyService then
        local _prevAddCoins = CurrencyService.AddCoins

        function CurrencyService:AddCoins(player, amount, source)
            local result = _prevAddCoins(self, player, amount, source)

            -- Fire coins_earned stat event for positive, non-reward amounts
            local earned = tonumber(result) or tonumber(amount) or 0
            if earned > 0 and typeof(player) == "Instance" and player:IsA("Player") then
                -- Exclude quest/achievement/weekly_quest rewards to avoid feedback loops
                if source ~= "quest" and source ~= "weekly_quest" and source ~= "achievement" then
                    task.spawn(function()
                        StatService:RegisterCoinsEarned(player, earned)
                    end)
                end
            end

            return result
        end
        print("[QuestServiceInit] CurrencyService.AddCoins wrapped for coins_earned tracking")
    end
end)

print("[QuestServiceInit] Daily quest system initialized (via StatService)")
