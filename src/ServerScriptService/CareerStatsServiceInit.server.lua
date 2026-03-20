--------------------------------------------------------------------------------
-- CareerStatsServiceInit.server.lua
-- Wires CareerStatsService into the centralized StatService event pipeline:
--   • Loads/saves career data on player join/leave
--   • Subscribes to StatService events for all career stat tracking
--   • Tracks elimination streaks per player
--   • Tracks playtime per player
--   • Exposes GetCareerStats RemoteFunction for the client Career tab
--   • Hooks into match end for win/loss tracking
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CareerStatsService = require(ServerScriptService:WaitForChild("CareerStatsService", 10))
local StatService        = require(ServerScriptService:WaitForChild("StatService", 10))

--------------------------------------------------------------------------------
-- XPServiceModule (lazy: might not be ready instantly)
--------------------------------------------------------------------------------
local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local getCareerStatsRF = Instance.new("RemoteFunction")
getCareerStatsRF.Name = "GetCareerStats"
getCareerStatsRF.Parent = remotesFolder

getCareerStatsRF.OnServerInvoke = function(player)
    if not player or not player:IsA("Player") then return nil end
    local stats = CareerStatsService:GetCareerStats(player)
    if not stats then return nil end

    -- Enrich with live XP/Level data
    local xpData
    if XPModule and XPModule.GetPlayerData then
        pcall(function() xpData = XPModule.GetPlayerData(player) end)
    end
    if xpData then
        stats._Level = xpData.Level or 1
        stats._XP = xpData.XP or 0
        stats._TotalXP = xpData.TotalXP or 0
        local XPFormula
        pcall(function()
            XPFormula = require(ReplicatedStorage:WaitForChild("XPFormula", 5))
        end)
        if XPFormula and XPFormula.GetXPRequiredForLevel then
            stats._XPToNext = XPFormula.GetXPRequiredForLevel(xpData.Level or 1)
        end
    end

    return stats
end

--------------------------------------------------------------------------------
-- GetPublicCareerStats – lets a client request another player's public profile
--------------------------------------------------------------------------------
local getPublicCareerStatsRF = Instance.new("RemoteFunction")
getPublicCareerStatsRF.Name = "GetPublicCareerStats"
getPublicCareerStatsRF.Parent = remotesFolder

getPublicCareerStatsRF.OnServerInvoke = function(requestingPlayer, targetUserId)
    if not requestingPlayer or not requestingPlayer:IsA("Player") then return nil end
    if type(targetUserId) ~= "number" then return nil end

    -- Find the target player in the current server
    local targetPlayer = Players:GetPlayerByUserId(targetUserId)
    if not targetPlayer then return nil end

    local stats = CareerStatsService:GetCareerStats(targetPlayer)
    if not stats then return nil end

    -- Enrich with live XP/Level data (same as self-view)
    local xpData
    if XPModule and XPModule.GetPlayerData then
        pcall(function() xpData = XPModule.GetPlayerData(targetPlayer) end)
    end
    if xpData then
        stats._Level = xpData.Level or 1
        stats._XP = xpData.XP or 0
        stats._TotalXP = xpData.TotalXP or 0
        local XPFormula
        pcall(function()
            XPFormula = require(ReplicatedStorage:WaitForChild("XPFormula", 5))
        end)
        if XPFormula and XPFormula.GetXPRequiredForLevel then
            stats._XPToNext = XPFormula.GetXPRequiredForLevel(xpData.Level or 1)
        end
    end

    -- Attach display identity so the client knows who it's viewing
    stats._DisplayName = targetPlayer.DisplayName
    stats._Username    = targetPlayer.Name
    stats._UserId      = targetPlayer.UserId

    return stats
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
local joinTimes = {}  -- [Player] -> os.clock() when they joined

local function onPlayerAdded(player)
    task.spawn(function()
        task.wait(1) -- let other services init first
        CareerStatsService:LoadForPlayer(player)
        joinTimes[player] = os.clock()
        print("[CareerStatsServiceInit] Loaded career stats for", player.Name)
    end)
end

local function flushPlaytime(player)
    local joinTime = joinTimes[player]
    if joinTime then
        local elapsed = os.clock() - joinTime
        CareerStatsService:AddPlaytime(player, elapsed)
        joinTimes[player] = os.clock() -- reset for next interval
    end
end

Players.PlayerRemoving:Connect(function(player)
    flushPlaytime(player)
    pcall(function() CareerStatsService:SaveForPlayer(player) end)
    CareerStatsService:ClearPlayer(player)
    joinTimes[player] = nil
    currentStreaks[player] = nil
end)

game:BindToClose(function()
    for player, _ in pairs(joinTimes) do
        flushPlaytime(player)
    end
    CareerStatsService:SaveAll()
end)

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Periodic playtime flush + autosave (every 120s, matching XPService)
task.spawn(function()
    while true do
        task.wait(120)
        for player, _ in pairs(joinTimes) do
            flushPlaytime(player)
        end
        pcall(function() CareerStatsService:SaveAll() end)
    end
end)

--------------------------------------------------------------------------------
-- Elimination streak tracking (in-memory, per-session)
--------------------------------------------------------------------------------
currentStreaks = {}  -- [Player] -> number (declared before PlayerRemoving handler)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events
--------------------------------------------------------------------------------
local Actions = StatService.Actions

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    local amount = payload.amount or 1
    if not player or not player:IsA("Player") then return end

    if action == Actions.Elimination then
        CareerStatsService:IncrementStat(player, "PlayersEliminated", 1)
        -- Streak tracking
        currentStreaks[player] = (currentStreaks[player] or 0) + 1
        CareerStatsService:SetStatMax(player, "HighestEliminationStreak", currentStreaks[player])

    elseif action == Actions.MobKill then
        CareerStatsService:IncrementStat(player, "MonstersEliminated", 1)

    elseif action == Actions.Death then
        CareerStatsService:IncrementStat(player, "Deaths", 1)
        -- Reset elimination streak on death
        currentStreaks[player] = 0

    elseif action == Actions.FlagCapture then
        CareerStatsService:IncrementStat(player, "FlagCaptures", 1)

    elseif action == Actions.FlagReturn then
        CareerStatsService:IncrementStat(player, "FlagReturns", 1)

    elseif action == Actions.MatchPlayed then
        CareerStatsService:IncrementStat(player, "MatchesPlayed", 1)

    elseif action == Actions.MatchWon then
        CareerStatsService:IncrementStat(player, "Wins", 1)

    elseif action == Actions.CoinsEarned then
        CareerStatsService:IncrementStat(player, "TotalCoinsEarned", amount)

    elseif action == Actions.QuestClaimed then
        CareerStatsService:IncrementStat(player, "QuestsCompleted", 1)

    elseif action == Actions.AchievementClaimed then
        CareerStatsService:IncrementStat(player, "AchievementsCompleted", 1)
    end
end)

--------------------------------------------------------------------------------
-- Match end: track Losses
-- MatchPlayed fires for ALL players. MatchWon fires for winners only.
-- We listen to the MatchEnded BindableEvent to identify losers.
--------------------------------------------------------------------------------
local MatchEndedBE = ServerScriptService:WaitForChild("MatchEnded", 10)
if MatchEndedBE and MatchEndedBE:IsA("BindableEvent") then
    MatchEndedBE.Event:Connect(function(winnerTeam)
        if type(winnerTeam) ~= "string" then return end
        for _, pl in ipairs(Players:GetPlayers()) do
            pcall(function()
                if pl.Team and pl.Team.Name ~= winnerTeam then
                    CareerStatsService:IncrementStat(pl, "Losses", 1)
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- XP tracking: wrap XPServiceModule.AwardXP to capture TotalXP
--------------------------------------------------------------------------------
task.spawn(function()
    task.wait(3) -- Wait for XPService to overwrite XPModule exports

    if XPModule and XPModule.AwardXP then
        local _prevAwardXP = XPModule.AwardXP
        XPModule.AwardXP = function(player, reason, amountOverride, metadata)
            local result = _prevAwardXP(player, reason, amountOverride, metadata)
            -- After successful XP award, track the amount in career stats
            if result and player and typeof(player) == "Instance" and player:IsA("Player") then
                local xpAmount = 0
                if amountOverride and type(amountOverride) == "number" then
                    xpAmount = math.floor(amountOverride)
                else
                    -- Try to get from XPConfig
                    pcall(function()
                        local XPConfig = require(ReplicatedStorage:WaitForChild("XPConfig", 5))
                        if XPConfig and XPConfig.Reasons and XPConfig.Reasons[reason] then
                            xpAmount = math.floor(XPConfig.Reasons[reason])
                        end
                    end)
                end
                if xpAmount > 0 then
                    CareerStatsService:IncrementStat(player, "TotalXP", xpAmount)
                end
            end
            return result
        end
        print("[CareerStatsServiceInit] XPServiceModule.AwardXP wrapped for TotalXP tracking")
    else
        warn("[CareerStatsServiceInit] XPServiceModule not ready — TotalXP career stat won't auto-track")
    end
end)

print("[CareerStatsServiceInit] Career stats system initialized")
