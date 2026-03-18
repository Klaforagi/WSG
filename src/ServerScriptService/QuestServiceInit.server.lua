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
    return QuestService:ClaimReward(player, questId)
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
-- Mapping:
--   MobKill      → zombies_eliminated daily quest track
--   Elimination  → players_eliminated daily quest track
--   FlagReturn   → flag_returns daily quest track
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    if not player or not player:IsA("Player") then return end

    if action == Actions.MobKill then
        QuestService:IncrementByType(player, "zombies_eliminated", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed daily zombie quests for %s via %s", player.Name, action))
        end
    elseif action == Actions.Elimination then
        QuestService:IncrementByType(player, "players_eliminated", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed daily player-elimination quests for %s via %s", player.Name, action))
        end
    elseif action == Actions.FlagReturn then
        QuestService:IncrementByType(player, "flag_returns", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed daily flag-return quests for %s via %s", player.Name, action))
        end
    end
end)

print("[QuestServiceInit] Daily quest system initialized (via StatService)")
