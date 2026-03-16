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

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

-- GetQuests: client asks for the full quest list
local getQuestsRF = Instance.new("RemoteFunction")
getQuestsRF.Name = "GetQuests"
getQuestsRF.Parent = remotesFolder

-- QuestProgress: server pushes live progress updates to client
local questProgressRE = Instance.new("RemoteEvent")
questProgressRE.Name = "QuestProgress"
questProgressRE.Parent = remotesFolder

-- ClaimQuest: client requests reward claim
local claimQuestRF = Instance.new("RemoteFunction")
claimQuestRF.Name = "ClaimQuest"
claimQuestRF.Parent = remotesFolder

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
--   MobKill      → zombie_hunter  daily quest
--   Elimination  → battle_ready   daily quest
--   FlagReturn   → team_defender  daily quest
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    if not player or not player:IsA("Player") then return end

    if action == Actions.MobKill then
        QuestService:IncrementQuest(player, "zombie_hunter", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed zombie_hunter for %s via %s", player.Name, action))
        end
    elseif action == Actions.Elimination then
        QuestService:IncrementQuest(player, "battle_ready", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed battle_ready for %s via %s", player.Name, action))
        end
    elseif action == Actions.FlagReturn then
        QuestService:IncrementQuest(player, "team_defender", 1)
        if StatService.DEBUG then
            print(string.format("[QuestService] Progressed team_defender for %s via %s", player.Name, action))
        end
    end
end)

print("[QuestServiceInit] Daily quest system initialized (via StatService)")
