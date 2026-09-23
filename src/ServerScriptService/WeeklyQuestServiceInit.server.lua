--------------------------------------------------------------------------------
-- WeeklyQuestServiceInit.server.lua
-- Creates remotes and hooks weekly quest progress into the centralized
-- StatService event pipeline:
--   • Matches Played  → StatService MatchPlayed event
--   • Matches Won     → StatService MatchWon event
--   • Mob kills       → StatService MobKill event
--   • Players Elim.   → StatService Elimination event
--   • Damage dealt    → StatService DamageDealt event
--   • Flag capture/return → StatService FlagCapture / FlagReturn
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local WeeklyQuestService = require(ServerScriptService:WaitForChild("WeeklyQuestService", 10))
local StatService         = require(ServerScriptService:WaitForChild("StatService", 10))
local BoostService        = require(ServerScriptService:WaitForChild("BoostService", 10))

local weeklySectionRegistered = false

local function registerWeeklySection()
    if weeklySectionRegistered then
        return
    end
    weeklySectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "WeeklyQuest",
        Priority = 55,
        Critical = false,
        Load = function(player)
            return WeeklyQuestService:LoadPlayer(player)
        end,
        GetSaveData = function(player)
            return WeeklyQuestService:GetSaveData(player)
        end,
        Save = function(player, currentData)
            return WeeklyQuestService:SaveProfileForPlayer(player, currentData)
        end,
        Cleanup = function(player)
            WeeklyQuestService:ClearPlayer(player)
        end,
        Validate = function(_, currentData, lastGoodData)
            local currentCount = currentData and currentData.quests and #currentData.quests or 0
            local lastCount = lastGoodData and lastGoodData.quests and #lastGoodData.quests or 0
            if lastCount > 0 and currentCount == 0 then
                return {
                    suspicious = true,
                    severity = "warning",
                    reason = "weekly quests became empty",
                }
            end
            return nil
        end,
    })
end

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

local weeklyStateChangedRE = ensureInstance(questsFolder, "RemoteEvent", "WeeklyQuestStateChanged")

local rerollWeeklyRF = ensureInstance(questsFolder, "RemoteFunction", "RequestRerollWeeklyQuest")

local resetWeeklyRF = ensureInstance(questsFolder, "RemoteFunction", "RequestResetWeeklyQuests")

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
        weeklyStateChangedRE:FireClient(player, questIndex, "claimed")
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

resetWeeklyRF.OnServerInvoke = function(player)
    local success, message, updatedQuests = WeeklyQuestService:ResetAllQuests(player)
    if success then
        weeklyStateChangedRE:FireClient(player, "__all__", "reset")
    end
    return success, message, updatedQuests
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    task.spawn(function()
        DataSaveCoordinator:LoadSection(player, "WeeklyQuest")
    end)
end

registerWeeklySection()

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events
-- Weekly quests mirror daily track types, so they listen to the same actions.
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    local amount = payload.amount or 1
    if not player or not player:IsA("Player") then return end

    if action == Actions.MobKill then
        local mobName = payload.metadata and payload.metadata.mobName or nil
        if type(mobName) == "string" and mobName ~= "" then
            local key = ("mob_%s"):format(tostring(mobName):lower())
            WeeklyQuestService:IncrementByType(player, key, 1)
        end
    elseif action == Actions.Elimination then
        WeeklyQuestService:IncrementByType(player, "players_eliminated", 1)
    elseif action == Actions.MatchPlayed then
        WeeklyQuestService:IncrementByType(player, "matches_played", 1)
    elseif action == Actions.MatchWon then
        WeeklyQuestService:IncrementByType(player, "matches_won", 1)
    elseif action == Actions.DamageDealt then
        -- Total damage includes every source, including typed weapon hits.
        WeeklyQuestService:IncrementByType(player, "damage_dealt", amount)
        local dmgType = payload.metadata and payload.metadata.damageType or nil
        if dmgType == "melee" then
            WeeklyQuestService:IncrementByType(player, "damage_melee", amount)
        elseif dmgType == "ranged" then
            WeeklyQuestService:IncrementByType(player, "damage_ranged", amount)
        end
    elseif action == Actions.CoinsEarned then
        WeeklyQuestService:IncrementByType(player, "coins_earned", amount)
    elseif action == Actions.FlagCapture then
        WeeklyQuestService:IncrementByType(player, "flag_captures", 1)
    elseif action == Actions.FlagReturn then
        WeeklyQuestService:IncrementByType(player, "flag_returns", 1)
    end
end)

print("[WeeklyQuestServiceInit] Weekly quest system initialized (via StatService)")
