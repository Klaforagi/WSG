--------------------------------------------------------------------------------
-- AchievementServiceInit.server.lua
-- Wires AchievementService into the centralized StatService event pipeline:
--   • Creates remotes for client communication
--   • Loads/saves achievement data on player join/leave
--   • Subscribes to StatService events to track:
--     totalElims, zombieElims, playerElims, flagActions, matchesPlayed
--   • Wraps CurrencyService.AddCoins for totalCoinsEarned
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AchievementService = require(ServerScriptService:WaitForChild("AchievementService", 10))
local StatService         = require(ServerScriptService:WaitForChild("StatService", 10))

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

-- GetAchievements: client asks for the full achievement list
local getAchievementsRF = Instance.new("RemoteFunction")
getAchievementsRF.Name = "GetAchievements"
getAchievementsRF.Parent = remotesFolder

-- AchievementProgress: server pushes live progress updates to client
local achievProgressRE = Instance.new("RemoteEvent")
achievProgressRE.Name = "AchievementProgress"
achievProgressRE.Parent = remotesFolder

-- ClaimAchievement: client requests reward claim
local claimAchievRF = Instance.new("RemoteFunction")
claimAchievRF.Name = "ClaimAchievement"
claimAchievRF.Parent = remotesFolder

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------
getAchievementsRF.OnServerInvoke = function(player)
    return AchievementService:GetAchievementsForPlayer(player)
end

claimAchievRF.OnServerInvoke = function(player, achievementId)
    if type(achievementId) ~= "string" then return false end
    local result = AchievementService:ClaimReward(player, achievementId)
    if result and StatService then
        pcall(function() StatService:RegisterAchievementClaimed(player) end)
    end
    return result
end

--------------------------------------------------------------------------------
-- Player lifecycle  (load/save)
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    -- Small delay to let CurrencyService and other modules initialize first
    task.spawn(function()
        task.wait(0.5)
        AchievementService:LoadForPlayer(player)
        print("[AchievementServiceInit] Loaded achievements for", player.Name)
    end)
end

Players.PlayerRemoving:Connect(function(player)
    pcall(function() AchievementService:SaveForPlayer(player) end)
    AchievementService:ClearPlayer(player)
end)

game:BindToClose(function()
    AchievementService:SaveAll()
end)

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events
--
-- Mapping:
--   Elimination  → totalElims + playerElims
--   MobKill      → totalElims + zombieElims
--   FlagCapture  → flagCaptures
--   FlagReturn   → flagReturns
--   MatchPlayed  → matchesPlayed
--   MatchWon     → matchWins
--   DamageDealt  → totalDamage
--
-- Stats not yet wired (TODO in future phases):
--   flagCarrierElims, bestElimStreak, doubleElims, tripleElims,
--   totalCoinsSpent, totalPurchases, itemsOwned, flagCarryTime,
--   matchMinutes, consecutiveLogins, flawlessWins
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    if not player or not player:IsA("Player") then return end

    if action == Actions.Elimination then
        AchievementService:IncrementStat(player, "totalElims", 1)
        AchievementService:IncrementStat(player, "playerElims", 1)
    elseif action == Actions.MobKill then
        AchievementService:IncrementStat(player, "totalElims", 1)
        AchievementService:IncrementStat(player, "zombieElims", 1)
    elseif action == Actions.FlagCapture then
        AchievementService:IncrementStat(player, "flagCaptures", 1)
    elseif action == Actions.FlagReturn then
        AchievementService:IncrementStat(player, "flagReturns", 1)
    elseif action == Actions.MatchPlayed then
        AchievementService:IncrementStat(player, "matchesPlayed", 1)
    elseif action == Actions.MatchWon then
        AchievementService:IncrementStat(player, "matchWins", 1)
    elseif action == Actions.DamageDealt then
        local amount = tonumber(payload.amount) or 0
        if amount > 0 then
            AchievementService:IncrementStat(player, "totalDamage", amount)
        end
    end
end)

--------------------------------------------------------------------------------
-- Hook: Coins earned  (wrap CurrencyService.AddCoins at the outermost layer)
-- This wraps on top of any existing wrappers (Boost, Upgrade) so we see the
-- final boosted amount.  Only positive amounts count as "earned".
-- NOTE: This is kept separate from StatService because coin tracking is
-- achievement-specific and wraps the reward pipeline, not the stat pipeline.
--------------------------------------------------------------------------------
task.spawn(function()
    task.wait(2) -- Wait for BoostServiceInit and UpgradeServiceInit to wrap first

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

            -- Track positive coin earnings for achievements
            local earned = tonumber(result) or tonumber(amount) or 0
            if earned > 0 and typeof(player) == "Instance" and player:IsA("Player") then
                -- Don't count achievement rewards themselves to avoid feedback loops
                if source ~= "achievement" then
                    task.spawn(function()
                        AchievementService:IncrementStat(player, "totalCoinsEarned", earned)
                    end)
                end
            end

            return result
        end
        print("[AchievementServiceInit] CurrencyService.AddCoins wrapped for coin tracking")
    else
        warn("[AchievementServiceInit] CurrencyService not found – coin achievement won't track")
    end
end)

print("[AchievementServiceInit] Achievement system initialized (via StatService)")
