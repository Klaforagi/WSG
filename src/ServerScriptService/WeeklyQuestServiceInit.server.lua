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
    return WeeklyQuestService:ClaimReward(player, questIndex)
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

local function onPlayerRemoving(player)
    WeeklyQuestService:ClearPlayer(player)
end

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events  (replaces ALL legacy hooks)
--
-- Mapping:
--   Elimination  → players_eliminated weekly quest trackType
--   MobKill      → zombies_eliminated weekly quest trackType
--   MatchPlayed  → matches_played     weekly quest trackType
--   MatchWon     → matches_won        weekly quest trackType
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    if not player or not player:IsA("Player") then return end

    if action == Actions.Elimination then
        WeeklyQuestService:IncrementByType(player, "players_eliminated", 1)
        if StatService.DEBUG then
            print(string.format("[WeeklyQuestService] %s: players_eliminated +1 for %s", action, player.Name))
        end
    elseif action == Actions.MobKill then
        WeeklyQuestService:IncrementByType(player, "zombies_eliminated", 1)
        if StatService.DEBUG then
            print(string.format("[WeeklyQuestService] %s: zombies_eliminated +1 for %s", action, player.Name))
        end
    elseif action == Actions.MatchPlayed then
        WeeklyQuestService:IncrementByType(player, "matches_played", 1)
        if StatService.DEBUG then
            print(string.format("[WeeklyQuestService] %s: matches_played +1 for %s", action, player.Name))
        end
    elseif action == Actions.MatchWon then
        WeeklyQuestService:IncrementByType(player, "matches_won", 1)
        if StatService.DEBUG then
            print(string.format("[WeeklyQuestService] %s: matches_won +1 for %s", action, player.Name))
        end
    end
end)

--------------------------------------------------------------------------------
-- Hook: Time Played (heartbeat every 60 seconds during active matches)
-- Uses MatchStarted/MatchEnded BindableEvents to track match state.
-- NOTE: Time tracking stays here because it's timer-based, not event-based.
--------------------------------------------------------------------------------
task.spawn(function()
    local matchActive = false

    local matchStartedBE = ServerScriptService:WaitForChild("MatchStarted", 30)
    local matchEndedBE   = ServerScriptService:WaitForChild("MatchEnded", 5)

    if matchStartedBE and matchStartedBE:IsA("BindableEvent") then
        matchStartedBE.Event:Connect(function()
            matchActive = true
        end)
    else
        warn("[WeeklyQuestServiceInit] MatchStarted BindableEvent not found – time quest won't auto-track")
    end

    if matchEndedBE and matchEndedBE:IsA("BindableEvent") then
        matchEndedBE.Event:Connect(function()
            matchActive = false
        end)
    end

    -- Credit 1 minute of play time every 60 seconds while match is active
    while true do
        task.wait(60)
        if matchActive then
            for _, player in ipairs(Players:GetPlayers()) do
                WeeklyQuestService:IncrementByType(player, "time_played", 1)
            end
        end
    end
end)

print("[WeeklyQuestServiceInit] Weekly quest system initialized (via StatService)")
