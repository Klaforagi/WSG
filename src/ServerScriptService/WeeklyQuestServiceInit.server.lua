--------------------------------------------------------------------------------
-- WeeklyQuestServiceInit.server.lua
-- Creates remotes and hooks weekly quest progress into existing game systems:
--   • Matches Played  → MatchEnded BindableEvent (from GameManager)
--   • Matches Won     → MatchEnded BindableEvent (winner team check)
--   • Time Played     → 60-second heartbeat during active matches
--   • Zombies Elim.   → CollectionService "ZombieNPC" death hook
--   • Players Elim.   → _G.AwardPlayerKill wrap + attribute fallback
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local WeeklyQuestService = require(ServerScriptService:WaitForChild("WeeklyQuestService", 10))

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local getWeeklyRF = Instance.new("RemoteFunction")
getWeeklyRF.Name = "GetWeeklyQuests"
getWeeklyRF.Parent = remotesFolder

local claimWeeklyRF = Instance.new("RemoteFunction")
claimWeeklyRF.Name = "ClaimWeeklyQuest"
claimWeeklyRF.Parent = remotesFolder

local weeklyProgressRE = Instance.new("RemoteEvent")
weeklyProgressRE.Name = "WeeklyQuestProgress"
weeklyProgressRE.Parent = remotesFolder

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
-- Hook: Matches Played & Matches Won (MatchEnded BindableEvent from GameManager)
-- GameManager fires: MatchEnded:Fire(winnerTeam)
--------------------------------------------------------------------------------
task.spawn(function()
    -- Wait for or create the BindableEvent
    local matchEndedBE = ServerScriptService:WaitForChild("MatchEnded", 30)
    if not matchEndedBE or not matchEndedBE:IsA("BindableEvent") then
        warn("[WeeklyQuestServiceInit] MatchEnded BindableEvent not found – match quests won't auto-track")
        return
    end

    matchEndedBE.Event:Connect(function(winnerTeam)
        for _, player in ipairs(Players:GetPlayers()) do
            -- All players in the server completed a match
            WeeklyQuestService:IncrementByType(player, "matches_played", 1)

            -- Check if player was on the winning team
            if winnerTeam and type(winnerTeam) == "string" then
                pcall(function()
                    if player.Team and player.Team.Name == winnerTeam then
                        WeeklyQuestService:IncrementByType(player, "matches_won", 1)
                    end
                end)
            end
        end
    end)
    print("[WeeklyQuestServiceInit] MatchEnded hook connected")
end)

--------------------------------------------------------------------------------
-- Hook: Time Played (heartbeat every 60 seconds during active matches)
-- Uses MatchStarted/MatchEnded BindableEvents to track match state.
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

--------------------------------------------------------------------------------
-- Hook: Zombies Eliminated (CollectionService "ZombieNPC" death)
-- Same pattern as QuestServiceInit but routes to weekly quest system.
--------------------------------------------------------------------------------
local MOB_TAG = "ZombieNPC"

local function hookMobForWeeklyQuest(mob)
    if not mob:IsA("Model") then return end
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = mob:WaitForChild("Humanoid", 3)
    end
    if not humanoid then return end

    local hooked = false
    humanoid.Died:Connect(function()
        if hooked then return end
        hooked = true

        local damagerUserId = humanoid:GetAttribute("lastDamagerUserId")
        local damagerName   = humanoid:GetAttribute("lastDamagerName")
        if not damagerName then return end

        local killer
        if damagerUserId then
            killer = Players:GetPlayerByUserId(damagerUserId)
        end
        if not killer then
            killer = Players:FindFirstChild(damagerName)
        end
        if killer then
            WeeklyQuestService:IncrementByType(killer, "zombies_eliminated", 1)
        end
    end)
end

for _, mob in ipairs(CollectionService:GetTagged(MOB_TAG)) do
    task.spawn(hookMobForWeeklyQuest, mob)
end
CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(mob)
    task.spawn(hookMobForWeeklyQuest, mob)
end)

--------------------------------------------------------------------------------
-- Hook: Players Eliminated (wrap _G.AwardPlayerKill + attribute fallback)
-- Same pattern as QuestServiceInit but routes to weekly quest system.
--------------------------------------------------------------------------------
task.spawn(function()
    -- Wait briefly for PvpKills.server.lua to set up _G.AwardPlayerKill
    -- and for QuestServiceInit to wrap it first.
    task.wait(6)

    local currentAward = _G.AwardPlayerKill
    if type(currentAward) == "function" then
        _G.AwardPlayerKill = function(killerPlayer, victimPlayer)
            currentAward(killerPlayer, victimPlayer)
            if typeof(killerPlayer) == "Instance" and killerPlayer:IsA("Player") then
                WeeklyQuestService:IncrementByType(killerPlayer, "players_eliminated", 1)
            end
        end
    else
        warn("[WeeklyQuestServiceInit] _G.AwardPlayerKill not found – PvP weekly quest won't auto-track via global")
    end

    -- Attribute-based fallback: hook player character deaths
    local function hookPlayerCharForWeeklyPvp(player)
        player.CharacterAdded:Connect(function(char)
            local hum = char:WaitForChild("Humanoid", 5)
            if not hum then return end
            local awarded = false
            hum.Died:Connect(function()
                if awarded then return end
                awarded = true

                local damagerName   = hum:GetAttribute("lastDamagerName")
                local damagerUserId = hum:GetAttribute("lastDamagerUserId")
                if not damagerName then return end
                if damagerName == player.Name then return end

                local killer
                if damagerUserId then
                    killer = Players:GetPlayerByUserId(damagerUserId)
                end
                if not killer then
                    killer = Players:FindFirstChild(damagerName)
                end
                if killer and killer:IsA("Player") then
                    WeeklyQuestService:IncrementByType(killer, "players_eliminated", 1)
                end
            end)
        end)
    end

    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(hookPlayerCharForWeeklyPvp, p)
    end
    Players.PlayerAdded:Connect(function(p)
        hookPlayerCharForWeeklyPvp(p)
    end)
end)

print("[WeeklyQuestServiceInit] Weekly quest system initialized")
