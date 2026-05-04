--------------------------------------------------------------------------------
-- DailyRewardServiceInit.server.lua
-- Creates remotes and wires DailyRewardService into the game.
-- Handles: player lifecycle, remote handlers, state push.
-- Follows the same pattern as BoostServiceInit.server.lua.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Require modules
--------------------------------------------------------------------------------
local DailyRewardService = require(ServerScriptService:WaitForChild("DailyRewardService", 10))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

-- Lazy-load AchievementService (may not be ready yet at require time)
local AchievementService
local function getAchievementService()
    if AchievementService then return AchievementService end
    pcall(function()
        local mod = ServerScriptService:FindFirstChild("AchievementService")
        if mod and mod:IsA("ModuleScript") then
            AchievementService = require(mod)
        end
    end)
    return AchievementService
end

--- Sync the daily reward streak into the achievement stat "consecutiveLogins".
--- Uses SetStat (only-go-up) since achievements care about best streak reached.
local function syncStreakToAchievement(player)
    local achSvc = getAchievementService()
    if not achSvc then return end
    local state = DailyRewardService:GetState(player)
    local streak = state and state.currentStreak or 0
    if streak > 0 then
        achSvc:SetStat(player, "consecutiveLogins", streak)
    end
end

local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then return existing end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes.DailyRewards)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local drFolder = ensureInstance(remotesFolder, "Folder", "DailyRewards")

-- GetDailyRewardState: client requests current state snapshot
local getStateRF = ensureInstance(drFolder, "RemoteFunction", "GetDailyRewardState")

-- ClaimDailyReward: client requests to claim today's reward
local claimRF = ensureInstance(drFolder, "RemoteFunction", "ClaimDailyReward")

-- DailyRewardStateUpdated: server pushes updated state to client
local stateUpdatedRE = ensureInstance(drFolder, "RemoteEvent", "DailyRewardStateUpdated")
local dailyRewardSectionRegistered = false

local function validateDailyReward(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end
    if (tonumber(lastGoodData.totalClaims) or 0) > 0 and (tonumber(currentData.totalClaims) or 0) == 0 then
        return {
            suspicious = true,
            severity = "warning",
            reason = "daily reward totalClaims reset to zero",
        }
    end
    return nil
end

local function registerDailyRewardSection()
    if dailyRewardSectionRegistered then
        return
    end
    dailyRewardSectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "DailyReward",
        Priority = 42,
        Critical = false,
        Load = function(player)
            return DailyRewardService:LoadProfileForPlayer(player)
        end,
        GetSaveData = function(player)
            return DailyRewardService:GetSaveData(player)
        end,
        Save = function(player, currentData, lastGoodData)
            return DailyRewardService:SaveProfileForPlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            DailyRewardService:ClearPlayer(player)
        end,
        Validate = validateDailyReward,
    })
end

--------------------------------------------------------------------------------
-- Push state to client (helper)
--------------------------------------------------------------------------------
local function pushState(player)
    if not player or not player.Parent then return end
    local state = DailyRewardService:GetState(player)
    pcall(function()
        stateUpdatedRE:FireClient(player, state)
    end)
end

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------

getStateRF.OnServerInvoke = function(player)
    if not player then return {} end
    return DailyRewardService:GetState(player)
end

claimRF.OnServerInvoke = function(player)
    if not player then return false, "Invalid" end
    local success, message = DailyRewardService:ClaimReward(player)
    if success then
        -- Push refreshed state after successful claim
        task.defer(function()
            pushState(player)
        end)
        -- Sync updated streak into achievement stat
        task.defer(function()
            syncStreakToAchievement(player)
        end)
    end
    -- Return the updated state along with success/message so client can
    -- update immediately without a second round-trip
    local updatedState = DailyRewardService:GetState(player)
    return success, message, updatedState
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    DataSaveCoordinator:LoadSection(player, "DailyReward")

    -- Sync login streak into achievement stat after both services have loaded
    task.delay(2, function()
        if not player or not player.Parent then return end
        syncStreakToAchievement(player)
    end)

    -- Small delay to let client scripts initialize before pushing auto-popup state
    task.delay(3, function()
        if not player or not player.Parent then return end
        local state = DailyRewardService:GetState(player)
        -- Only auto-push if eligible (unclaimed) and auto-popup not yet shown
        if state.canClaimToday and state.autoPopup then
            DailyRewardService:MarkAutoPopupShown(player)
            pcall(function()
                stateUpdatedRE:FireClient(player, state)
            end)
        end
    end)
end

registerDailyRewardSection()
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in the server (Team Test / late join)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(player)
    end)
end

print("[DailyRewardServiceInit] Daily Reward system initialized")
