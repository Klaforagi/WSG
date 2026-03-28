--------------------------------------------------------------------------------
-- WeeklyQuestServiceInit.server.lua
-- Creates remotes and hooks weekly quest progress into the centralized
-- StatService event pipeline:
--   • Matches Played  → StatService MatchPlayed event
--   • Matches Won     → StatService MatchWon event
--   • Time Played     → 60-second heartbeat during active matches (kept as-is)
--   • Zombies Elim.   → StatService MobKill event
--   • Players Elim.   → StatService Elimination event
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeeklyQuestService = require(ServerScriptService:WaitForChild("WeeklyQuestService", 10))
local StatService         = require(ServerScriptService:WaitForChild("StatService", 10))
local BoostService        = require(ServerScriptService:WaitForChild("BoostService", 10))

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

local getWeeklyRF = ensureInstance(questsFolder, "RemoteFunction", "GetWeeklyQuests")

local claimWeeklyRF = ensureInstance(questsFolder, "RemoteFunction", "ClaimWeeklyQuest")

local weeklyProgressRE = ensureInstance(questsFolder, "RemoteEvent", "WeeklyQuestProgress")

local rerollWeeklyRF = ensureInstance(questsFolder, "RemoteFunction", "RequestRerollWeeklyQuest")

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------
getWeeklyRF.OnServerInvoke = function(player)
    return WeeklyQuestService:GetWeeklyQuests(player)
end

claimWeeklyRF.OnServerInvoke = function(player, questIndex)
    if type(questIndex) ~= "number" then return false end
    local result = WeeklyQuestService:ClaimReward(player, questIndex)
    if result then
        -- Track weekly quest completion for achievements
        pcall(function()
            local AchievementService = require(ServerScriptService:FindFirstChild("AchievementService"))
            if AchievementService then
                AchievementService:IncrementStat(player, "weeklyQuestsCompleted", 1)
            end
        end)
    end
    return result
end

rerollWeeklyRF.OnServerInvoke = function(player, questIndex)
    if type(questIndex) ~= "number" then
        return false, "Invalid"
    end
    return BoostService:RerollQuest(player, "weekly", questIndex)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    task.spawn(function()
        WeeklyQuestService:LoadPlayer(player)
    end)
end

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

local function onPlayerRemoving(player)
    if SaveGuard:ClaimSave(player, "WeeklyQuest") then
        WeeklyQuestService:ClearPlayer(player)
        SaveGuard:ReleaseSave(player, "WeeklyQuest")
    else
        pcall(function() WeeklyQuestService:ClearPlayer(player) end)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Save all on shutdown (was missing – data loss risk)
game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if SaveGuard:ClaimSave(p, "WeeklyQuest") then
                WeeklyQuestService:ClearPlayer(p)
                SaveGuard:ReleaseSave(p, "WeeklyQuest")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
end)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events
--
-- Weekly quest track types:
--   MatchWon     → matches_won
--   FlagCapture  → flag_captures
--   FlagReturn   → flag_returns
--   MatchPlayed  → matches_played
--   CoinsEarned  → coins_earned
--   (time_played is handled by the 60-second heartbeat below)
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    local amount = payload.amount or 1
    if not player or not player:IsA("Player") then return end

    if action == Actions.MatchWon then
        WeeklyQuestService:IncrementByType(player, "matches_won", 1)
    elseif action == Actions.FlagCapture then
        WeeklyQuestService:IncrementByType(player, "flag_captures", 1)
    elseif action == Actions.FlagReturn then
        WeeklyQuestService:IncrementByType(player, "flag_returns", 1)
    elseif action == Actions.MatchPlayed then
        WeeklyQuestService:IncrementByType(player, "matches_played", 1)
    elseif action == Actions.CoinsEarned then
        WeeklyQuestService:IncrementByType(player, "coins_earned", amount)
    end
end)

--------------------------------------------------------------------------------
-- Hook: Time Played (heartbeat every 60 seconds during active matches)
-- Polls the MatchState attribute (set by GameManager) instead of relying on
-- BindableEvents, which suffer from a race condition where the first match
-- fires MatchStarted before this script connects.
--------------------------------------------------------------------------------
task.spawn(function()
    -- Credit 1 minute of play time every 60 seconds while match is active
    while true do
        task.wait(60)
        local state = ServerScriptService:GetAttribute("MatchState")
        if state == "Game" or state == "SuddenDeath" then
            for _, player in ipairs(Players:GetPlayers()) do
                WeeklyQuestService:IncrementByType(player, "time_played", 1)
            end
        end
    end
end)

print("[WeeklyQuestServiceInit] Weekly quest system initialized (via StatService)")
