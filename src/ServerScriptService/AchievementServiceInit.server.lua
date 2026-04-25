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

-- ClaimAchievement: player manually claims a completed achievement reward
local claimAchievRF = Instance.new("RemoteFunction")
claimAchievRF.Name = "ClaimAchievement"
claimAchievRF.Parent = remotesFolder

-- GetCompletedHistory: client asks for completed achievement history
local getHistoryRF = Instance.new("RemoteFunction")
getHistoryRF.Name = "GetCompletedHistory"
getHistoryRF.Parent = remotesFolder

-- GetCategoryProgress: client asks for per-category completion summary
local getCategoryProgressRF = Instance.new("RemoteFunction")
getCategoryProgressRF.Name = "GetCategoryProgress"
getCategoryProgressRF.Parent = remotesFolder

-- GetAchievementPoints: client asks for lifetime AP total
local getAchievPointsRF = Instance.new("RemoteFunction")
getAchievPointsRF.Name = "GetAchievementPoints"
getAchievPointsRF.Parent = remotesFolder

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

getHistoryRF.OnServerInvoke = function(player)
    return AchievementService:GetCompletedHistory(player)
end

getCategoryProgressRF.OnServerInvoke = function(player)
    return AchievementService:GetCategoryProgressSummary(player)
end

getAchievPointsRF.OnServerInvoke = function(player)
    return AchievementService:GetAchievementPoints(player)
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

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

Players.PlayerRemoving:Connect(function(player)
    if SaveGuard:ClaimSave(player, "Achievements") then
        pcall(function() AchievementService:SaveForPlayer(player) end)
        SaveGuard:ReleaseSave(player, "Achievements")
    end
    AchievementService:ClearPlayer(player)
end)

game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if SaveGuard:ClaimSave(p, "Achievements") then
                pcall(function() AchievementService:SaveForPlayer(p) end)
                SaveGuard:ReleaseSave(p, "Achievements")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
end)

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

--------------------------------------------------------------------------------
-- Subscribe to centralized stat events
--
-- Mapping:
--   Elimination  → totalElims + playerElims + streak/multi-kill/flag-carrier
--   MobKill      → totalElims + zombieElims
--   Death        → streak reset + multi-kill window reset
--   FlagCapture  → flagCaptures
--   FlagReturn   → flagReturns
--   MatchPlayed  → matchesPlayed
--   MatchWon     → matchWins
--   DamageDealt  → totalDamage
--
-- Stats not yet wired (TODO in future phases):
--   totalPurchases
-- Wired elsewhere:
--   consecutiveLogins (via DailyRewardServiceInit), flagCarryTime (via CarryingFlag poll below)
-- Wired in this file:
--   totalCoinsSpent (via SetCoins wrapper), itemsOwned (via BindableFunction queries),
--   matchMinutes (via MatchStartedBE/MatchEndedBE),
--   flagCarrierElims, bestElimStreak, doubleElims, tripleElims (below)
--------------------------------------------------------------------------------
local Actions = StatService.Actions

--------------------------------------------------------------------------------
-- Per-player combat achievement tracking state
--   elimStreaks:  current kill-streak counter (reset on death)
--   recentElims: array of os.clock() timestamps for multi-kill window
--------------------------------------------------------------------------------
local elimStreaks  = {} -- [Player] = number
local recentElims = {} -- [Player] = { clock1, clock2, ... }

local DOUBLE_KILL_WINDOW = 10  -- seconds (matches Double Trouble description)
local TRIPLE_KILL_WINDOW = 15  -- seconds (matches Triple Threat description)

-- Cleanup tracking state when players leave
Players.PlayerRemoving:Connect(function(player)
    elimStreaks[player]  = nil
    recentElims[player] = nil
end)

StatService:OnStatEvent(function(payload)
    local player = payload.player
    local action = payload.action
    if not player or not player:IsA("Player") then return end

    if action == Actions.Elimination then
        AchievementService:IncrementStat(player, "totalElims", 1)
        AchievementService:IncrementStat(player, "playerElims", 1)

        --------------------------------------------------------------------
        -- Unstoppable: elimination streak (reset on death, see below)
        --------------------------------------------------------------------
        elimStreaks[player] = (elimStreaks[player] or 0) + 1
        local streak = elimStreaks[player]
        AchievementService:SetStat(player, "bestElimStreak", streak)
        print(string.format("[Achievements] Unstoppable streak for %s: %d", player.Name, streak))

        --------------------------------------------------------------------
        -- Double Trouble / Triple Threat: timed multi-kill window
        --------------------------------------------------------------------
        local now = os.clock()
        if not recentElims[player] then recentElims[player] = {} end
        table.insert(recentElims[player], now)

        -- Prune timestamps older than the longest window (15s)
        local pruned = {}
        for _, t in ipairs(recentElims[player]) do
            if now - t <= TRIPLE_KILL_WINDOW then
                table.insert(pruned, t)
            end
        end
        recentElims[player] = pruned

        -- Count kills within each window
        local countIn10s = 0
        for _, t in ipairs(pruned) do
            if now - t <= DOUBLE_KILL_WINDOW then
                countIn10s = countIn10s + 1
            end
        end
        local countIn15s = #pruned

        -- Trigger exactly when the threshold is reached (== not >=)
        -- to avoid repeated increments from the same burst
        if countIn10s == 2 then
            AchievementService:IncrementStat(player, "doubleElims", 1)
            print(string.format("[Achievements] Double Trouble window count for %s: 2", player.Name))
        end
        if countIn15s == 3 then
            AchievementService:IncrementStat(player, "tripleElims", 1)
            print(string.format("[Achievements] Triple Threat window count for %s: 3", player.Name))
        end

        --------------------------------------------------------------------
        -- Flagbreaker: check if victim was carrying a flag
        --------------------------------------------------------------------
        local victim = payload.metadata and payload.metadata.target
        if victim and typeof(victim) == "Instance" and victim:IsA("Player") then
            local victimCarrier = victim:GetAttribute("CarryingFlag")
            if victimCarrier then
                AchievementService:IncrementStat(player, "flagCarrierElims", 1)
                print(string.format("[Achievements] Flagbreaker check: victim=%s victimCarrier=true", victim.Name))
            end
        end

    elseif action == Actions.Death then
        --------------------------------------------------------------------
        -- Reset streak and multi-kill window on death
        --------------------------------------------------------------------
        local prevStreak = elimStreaks[player] or 0
        if prevStreak > 0 then
            print(string.format("[Achievements] Streak reset for %s (was %d)", player.Name, prevStreak))
        end
        elimStreaks[player] = 0
        recentElims[player] = {}

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
        -- Flawless win detection (Untouchable achievement):
        -- StatService per-match Deaths is still readable here because
        -- ResetMatchStats hasn't been called yet in GameManager's endMatch flow.
        local matchDeaths = StatService:GetStat(player, "Deaths")
        if matchDeaths == 0 then
            AchievementService:IncrementStat(player, "flawlessWins", 1)
        end
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
        local _suppressSpendTracking = false   -- set true inside AddCoins for non-shop sources

        function CurrencyService:AddCoins(player, amount, source)
            -- Suppress Big Spender tracking for upgrade spending
            local suppress = (source == "upgrade") and (tonumber(amount) or 0) < 0
            if suppress then _suppressSpendTracking = true end

            local result = _prevAddCoins(self, player, amount, source)

            if suppress then _suppressSpendTracking = false end

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

        -----------------------------------------------------------------------
        -- Hook: Coins spent  (wrap CurrencyService.SetCoins)
        -- All coin purchases flow through SetCoins (called directly by
        -- CrateService, SkinService, EffectsService, EmoteService, Loadout)
        -- or indirectly via AddCoins (BoostService, UpgradeService).
        -- We detect when the balance decreases and track the delta.
        -----------------------------------------------------------------------
        local _prevSetCoins = CurrencyService.SetCoins

        function CurrencyService:SetCoins(player, amount)
            local prevBalance = self:GetCoins(player)
            _prevSetCoins(self, player, amount)
            local newBalance = self:GetCoins(player)
            local spent = prevBalance - newBalance
            if spent > 0 and typeof(player) == "Instance" and player:IsA("Player") then
                -- Only count shop spending, not upgrades (suppressed via AddCoins wrapper)
                if not _suppressSpendTracking then
                    task.spawn(function()
                        AchievementService:IncrementStat(player, "totalCoinsSpent", spent)
                    end)
                end
                -- Schedule an itemsOwned recount after purchase
                task.spawn(function()
                    task.wait(0.5) -- let ownership data settle
                    recalcItemsOwned(player)
                end)
            end
        end
        print("[AchievementServiceInit] CurrencyService.SetCoins wrapped for spending + itemsOwned tracking")
    else
        warn("[AchievementServiceInit] CurrencyService not found – coin achievement won't track")
    end
end)

--------------------------------------------------------------------------------
-- Hook: itemsOwned  (Collector achievement)
-- Queries ownership counts from SkinService, EffectsService, EmoteServiceInit
-- via dedicated BindableFunctions. Called on player load and after purchases.
--------------------------------------------------------------------------------
function recalcItemsOwned(player)
    if not player or not player:IsA("Player") or not player.Parent then return end
    local total = 0
    pcall(function()
        local bf = ServerScriptService:FindFirstChild("GetSkinOwnedCount")
        if bf then total = total + (bf:Invoke(player) or 0) end
    end)
    pcall(function()
        local bf = ServerScriptService:FindFirstChild("GetEffectOwnedCount")
        if bf then total = total + (bf:Invoke(player) or 0) end
    end)
    pcall(function()
        local bf = ServerScriptService:FindFirstChild("GetEmoteOwnedCount")
        if bf then total = total + (bf:Invoke(player) or 0) end
    end)
    if total > 0 then
        AchievementService:SetStat(player, "itemsOwned", total)
    end
end

-- Recount on player load  (delayed to let all services load data first)
task.spawn(function()
    local function onPlayerReady(player)
        task.spawn(function()
            task.wait(4) -- let SkinService, EffectsService, EmoteService load
            recalcItemsOwned(player)
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do onPlayerReady(p) end
    Players.PlayerAdded:Connect(onPlayerReady)
end)

-- Also recount when items are granted via SalvageShop BindableFunctions
task.spawn(function()
    task.wait(3)
    local grantSkinBF = ServerScriptService:FindFirstChild("GrantSkin")
    if grantSkinBF and grantSkinBF:IsA("BindableFunction") then
        local _prevGrantSkin
        local okPrev = pcall(function()
            _prevGrantSkin = grantSkinBF.OnInvoke
        end)
        if okPrev and type(_prevGrantSkin) == "function" then
            grantSkinBF.OnInvoke = function(player, skinId)
                local result = _prevGrantSkin(player, skinId)
                if result then
                    task.spawn(function()
                        task.wait(0.5)
                        recalcItemsOwned(player)
                    end)
                end
                return result
            end
            print("[AchievementServiceInit] GrantSkin wrapped for itemsOwned tracking")
        else
            warn("[AchievementServiceInit] GrantSkin OnInvoke is write-only here; skipping wrapper")
        end
    end
    local grantEffectBF = ServerScriptService:FindFirstChild("GrantEffect")
    if grantEffectBF and grantEffectBF:IsA("BindableFunction") then
        local _prevGrantEffect
        local okPrev = pcall(function()
            _prevGrantEffect = grantEffectBF.OnInvoke
        end)
        if okPrev and type(_prevGrantEffect) == "function" then
            grantEffectBF.OnInvoke = function(player, effectId)
                local result = _prevGrantEffect(player, effectId)
                if result then
                    task.spawn(function()
                        task.wait(0.5)
                        recalcItemsOwned(player)
                    end)
                end
                return result
            end
            print("[AchievementServiceInit] GrantEffect wrapped for itemsOwned tracking")
        else
            warn("[AchievementServiceInit] GrantEffect OnInvoke is write-only here; skipping wrapper")
        end
    end
end)

--------------------------------------------------------------------------------
-- Hook: matchMinutes  (Battle Tested achievement)
-- Polls the MatchState attribute (set by GameManager) every TICK seconds and
-- increments matchMinutes for each player on a real team (Red/Blue).
-- This avoids the old race condition where the BindableEvent-based approach
-- missed the first match because GameManager fires MatchStarted before this
-- script connects.
--------------------------------------------------------------------------------
task.spawn(function()
    local TICK = 10  -- seconds between each check
    local INCREMENT = TICK / 60  -- fractional minutes per tick

    local Teams = game:GetService("Teams")

    print("[BattleTested] matchMinutes tracker started — tick every", TICK, "s, increment", string.format("%.4f", INCREMENT), "min/tick")

    while true do
        task.wait(TICK)

        local state = ServerScriptService:GetAttribute("MatchState")
        local isActive = (state == "Game" or state == "SuddenDeath")

        if isActive then
            for _, player in ipairs(Players:GetPlayers()) do
                -- Only credit players assigned to a real team
                local team = player.Team
                if team and (team.Name == "Red" or team.Name == "Blue") then
                    task.spawn(function()
                        AchievementService:IncrementStat(player, "matchMinutes", INCREMENT)
                    end)
                end
            end
        end
    end
end)

print("[AchievementServiceInit] Achievement system initialized (via StatService)")

--------------------------------------------------------------------------------
-- Hook: flagCarryTime  (Flag Bearer achievement)
-- Polls each player's "CarryingFlag" attribute (set/cleared by FlagPickup.server)
-- every TICK seconds. If set, the player is actively carrying a flag and we
-- increment their flagCarryTime stat by TICK seconds.
--------------------------------------------------------------------------------
task.spawn(function()
    local TICK = 5  -- seconds between each check

    print("[FlagBearer] flagCarryTime tracker started — tick every", TICK, "s")

    while true do
        task.wait(TICK)
        for _, player in ipairs(Players:GetPlayers()) do
            local carryingFlag = player:GetAttribute("CarryingFlag")
            if carryingFlag then
                task.spawn(function()
                    AchievementService:IncrementStat(player, "flagCarryTime", TICK)
                end)
            end
        end
    end
end)
