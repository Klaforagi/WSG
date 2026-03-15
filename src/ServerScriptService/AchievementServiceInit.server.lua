--------------------------------------------------------------------------------
-- AchievementServiceInit.server.lua
-- Wires AchievementService into the game:
--   • Creates remotes for client communication
--   • Loads/saves achievement data on player join/leave
--   • Hooks into existing kill, flag, match, and coin systems
--   • Tracks: totalElims, zombieElims, playerElims,
--             totalCoinsEarned, flagActions, matchesPlayed
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local AchievementService = require(ServerScriptService:WaitForChild("AchievementService", 10))

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
    return AchievementService:ClaimReward(player, achievementId)
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
-- Hook: Zombie kills  (CollectionService tag "ZombieNPC")
-- Same approach as QuestServiceInit — watch tagged NPCs for deaths.
-- Increments both "totalElims" and "zombieElims".
--------------------------------------------------------------------------------
local MOB_TAG = "ZombieNPC"

local function hookMobForAchievements(mob)
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
            AchievementService:IncrementStat(killer, "totalElims", 1)
            AchievementService:IncrementStat(killer, "zombieElims", 1)
        end
    end)
end

for _, mob in ipairs(CollectionService:GetTagged(MOB_TAG)) do
    task.spawn(hookMobForAchievements, mob)
end
CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(mob)
    task.spawn(hookMobForAchievements, mob)
end)

--------------------------------------------------------------------------------
-- Hook: PvP kills  (wrap _G.AwardPlayerKill)
-- Increments both "totalElims" and "playerElims".
-- We wrap on top of whatever QuestServiceInit already wrapped.
--------------------------------------------------------------------------------
task.spawn(function()
    local tries = 0
    while not _G.AwardPlayerKill and tries < 20 do
        task.wait(0.25)
        tries = tries + 1
    end

    local previousAward = _G.AwardPlayerKill
    if type(previousAward) == "function" then
        _G.AwardPlayerKill = function(killerPlayer, victimPlayer)
            previousAward(killerPlayer, victimPlayer)
            if typeof(killerPlayer) == "Instance" and killerPlayer:IsA("Player") then
                AchievementService:IncrementStat(killerPlayer, "totalElims", 1)
                AchievementService:IncrementStat(killerPlayer, "playerElims", 1)
            end
        end
        print("[AchievementServiceInit] _G.AwardPlayerKill wrapped for achievements")
    else
        warn("[AchievementServiceInit] _G.AwardPlayerKill not found – PvP achievement tracking limited")
    end

    -- Also hook player character deaths for attribute-based PvP detection
    -- (same pattern as QuestServiceInit for edge cases)
    local function hookPlayerCharForAchievements(player)
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
                    AchievementService:IncrementStat(killer, "totalElims", 1)
                    AchievementService:IncrementStat(killer, "playerElims", 1)
                end
            end)
        end)
    end

    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(hookPlayerCharForAchievements, p)
    end
    Players.PlayerAdded:Connect(function(p)
        hookPlayerCharForAchievements(p)
    end)
end)

--------------------------------------------------------------------------------
-- Hook: Flag actions  (FlagReturned BindableEvent from FlagPickup.server.lua)
-- Covers both returns and captures that fire through FlagReturned.
--------------------------------------------------------------------------------
task.spawn(function()
    local flagReturnedEvent = ServerScriptService:WaitForChild("FlagReturned", 15)
    if not flagReturnedEvent or not flagReturnedEvent:IsA("BindableEvent") then
        warn("[AchievementServiceInit] FlagReturned BindableEvent not found – flag achievement won't track")
        return
    end

    flagReturnedEvent.Event:Connect(function(player)
        if typeof(player) == "Instance" and player:IsA("Player") then
            AchievementService:IncrementStat(player, "flagActions", 1)
        end
    end)
    print("[AchievementServiceInit] FlagReturned hook connected")
end)

--------------------------------------------------------------------------------
-- Hook: Matches played  (MatchStart RemoteEvent from GameManager)
-- Every time a new match starts, increment matchesPlayed for all online players.
--------------------------------------------------------------------------------
task.spawn(function()
    local matchStart = ReplicatedStorage:WaitForChild("MatchStart", 15)
    if not matchStart or not matchStart:IsA("RemoteEvent") then
        warn("[AchievementServiceInit] MatchStart remote not found – match achievement won't track")
        return
    end

    -- MatchStart is server→client, so we can't listen OnServerEvent.
    -- Instead, hook via a BindableEvent bridge. We create a small BindableEvent
    -- that GameManager can fire, OR we watch for the match state change.
    -- Simplest: watch the remote's FireAllClients by wrapping it.
    local _originalFire = matchStart.FireAllClients
    matchStart.FireAllClients = function(self2, ...)
        _originalFire(self2, ...)
        -- Award "matchesPlayed" to all players
        for _, p in ipairs(Players:GetPlayers()) do
            task.spawn(function()
                AchievementService:IncrementStat(p, "matchesPlayed", 1)
            end)
        end
    end
    print("[AchievementServiceInit] MatchStart hook connected (wrapping FireAllClients)")
end)

--------------------------------------------------------------------------------
-- Hook: Coins earned  (wrap CurrencyService.AddCoins at the outermost layer)
-- This wraps on top of any existing wrappers (Boost, Upgrade) so we see the
-- final boosted amount.  Only positive amounts count as "earned".
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

print("[AchievementServiceInit] Achievement system initialized")
