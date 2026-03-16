--------------------------------------------------------------------------------
-- StatService.lua  –  Centralized stat/event tracking for gameplay actions
-- ModuleScript in ServerScriptService.
--
-- SINGLE SOURCE OF TRUTH for all player match stats and gameplay events.
-- Every stat mutation flows through this module. Other systems (quests,
-- achievements, scoreboard, weekly quests) subscribe to the shared event
-- pipeline via StatService:OnStatEvent(callback).
--
-- Public API:
--   StatService.Actions                              -- canonical action names
--   StatService.DEBUG                                -- toggle debug logging
--   StatService:InitPlayer(player)
--   StatService:ResetMatchStats(player)
--   StatService:ClearPlayer(player)
--   StatService:GetStat(player, statName) -> number
--   StatService:OnStatEvent(callback) -> RBXScriptConnection
--   StatService:RegisterElimination(killer, victim)
--   StatService:RegisterMobKill(killer, mobName)
--   StatService:RegisterDeath(player)
--   StatService:RegisterFlagCapture(player)
--   StatService:RegisterFlagReturn(player)
--   StatService:RegisterFlagPickup(player)
--   StatService:RegisterMatchPlayed(player)
--   StatService:RegisterMatchWon(player)
--   StatService:TrackDeaths(player)
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local StatService = {}

--------------------------------------------------------------------------------
-- Debug flag  –  set to false to silence all [StatService] prints
--------------------------------------------------------------------------------
StatService.DEBUG = true

local function debugLog(...)
    if StatService.DEBUG then
        print(...)
    end
end

--------------------------------------------------------------------------------
-- Canonical action names  (single shared table for the entire codebase)
-- Quest defs, achievement defs, and event listeners all key off these strings.
--------------------------------------------------------------------------------
StatService.Actions = {
    Elimination  = "Elimination",      -- PvP player kill
    MobKill      = "MobKill",          -- NPC / zombie kill
    Death        = "Death",            -- Player death
    FlagCapture  = "FlagCapture",      -- Captured enemy flag at own stand
    FlagReturn   = "FlagReturn",       -- Returned own team's dropped flag
    FlagPickup   = "FlagPickup",       -- Picked up enemy flag
    MatchPlayed  = "MatchPlayed",      -- Completed a match
    MatchWon     = "MatchWon",         -- Was on the winning team
}

--------------------------------------------------------------------------------
-- Match stat defaults  (synced to player Attributes for UI / scoreboard)
--------------------------------------------------------------------------------
local MATCH_STAT_DEFAULTS = {
    Score         = 0,
    Eliminations  = 0,
    Deaths        = 0,
    FlagCaptures  = 0,
    FlagReturns   = 0,
    PlayerKills   = 0,
}

--------------------------------------------------------------------------------
-- Per-player stat storage  (server-authoritative, single source of truth)
--------------------------------------------------------------------------------
local playerStats = {}  -- [Player] -> { Score = 0, Eliminations = 0, ... }

--------------------------------------------------------------------------------
-- Central event pipeline  (BindableEvent)
-- Payload passed to listeners:
--   { player = Player, action = string, amount = number,
--     timestamp = number, metadata = table }
--------------------------------------------------------------------------------
local StatChanged = Instance.new("BindableEvent")
StatChanged.Name   = "StatChanged"
StatChanged.Parent = ServerScriptService

--- Subscribe to centralised stat/event changes.
--- @param callback function  receives a payload table
--- @return RBXScriptConnection
function StatService:OnStatEvent(callback)
    return StatChanged.Event:Connect(callback)
end

--- Direct reference to the BindableEvent (for edge-case usage).
StatService.StatChanged = StatChanged

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

local function getStats(player)
    return playerStats[player]
end

--- Increment a stat and sync the attribute to the player instance.
local function incrementStat(player, statName, amount)
    amount = amount or 1
    local stats = getStats(player)
    if not stats then
        -- Lazy-init if the player wasn't initialised yet (edge case)
        StatService:InitPlayer(player)
        stats = getStats(player)
        if not stats then return 0 end
    end
    stats[statName] = (stats[statName] or 0) + amount
    pcall(function()
        player:SetAttribute(statName, stats[statName])
    end)
    debugLog(string.format("[StatService] %s %s +%d = %d",
        player.Name, statName, amount, stats[statName]))
    return stats[statName]
end

--- Fire the centralised event so all subscribers are notified.
local function fireEvent(player, action, amount, metadata)
    local payload = {
        player    = player,
        action    = action,
        amount    = amount or 1,
        timestamp = os.time(),
        metadata  = metadata or {},
    }
    StatChanged:Fire(payload)
    debugLog(string.format("[StatService] Event: %s for %s (+%d)",
        action, player.Name, amount or 1))
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

--- Initialise match stat storage for a player. Safe to call multiple times.
function StatService:InitPlayer(player)
    if playerStats[player] then return end  -- already initialised
    local stats = {}
    for k, v in pairs(MATCH_STAT_DEFAULTS) do
        local existing = player:GetAttribute(k)
        if existing ~= nil then
            stats[k] = existing  -- preserve mid-match rejoin values
        else
            stats[k] = v
            player:SetAttribute(k, v)
        end
    end
    playerStats[player] = stats
    debugLog("[StatService] Initialized stats for", player.Name)
end

--- Reset all match-level stats to zero (called between matches).
function StatService:ResetMatchStats(player)
    local stats = playerStats[player]
    if not stats then return end
    for k, v in pairs(MATCH_STAT_DEFAULTS) do
        stats[k] = v
        pcall(function() player:SetAttribute(k, v) end)
    end
    debugLog("[StatService] Reset match stats for", player.Name)
end

--- Remove a player from memory (call on PlayerRemoving).
function StatService:ClearPlayer(player)
    playerStats[player] = nil
end

--- Read a single stat value.
function StatService:GetStat(player, statName)
    local stats = getStats(player)
    if not stats then return 0 end
    return stats[statName] or 0
end

--------------------------------------------------------------------------------
-- Registration: PvP Elimination
--------------------------------------------------------------------------------
function StatService:RegisterElimination(killer, victim)
    if not killer or not killer:IsA("Player") then return end
    incrementStat(killer, "Eliminations", 1)
    incrementStat(killer, "PlayerKills", 1)
    incrementStat(killer, "Score", 10)
    fireEvent(killer, self.Actions.Elimination, 1, {
        target     = victim,
        targetName = victim and (typeof(victim) == "Instance" and victim.Name or tostring(victim)) or nil,
    })
end

--------------------------------------------------------------------------------
-- Registration: Mob / NPC Kill
--------------------------------------------------------------------------------
function StatService:RegisterMobKill(killer, mobName)
    if not killer or not killer:IsA("Player") then return end
    incrementStat(killer, "Score", 3)
    fireEvent(killer, self.Actions.MobKill, 1, { mobName = mobName })
end

--------------------------------------------------------------------------------
-- Registration: Player Death
--------------------------------------------------------------------------------
function StatService:RegisterDeath(player)
    if not player or not player:IsA("Player") then return end
    incrementStat(player, "Deaths", 1)
    fireEvent(player, self.Actions.Death, 1)
end

--------------------------------------------------------------------------------
-- Registration: Flag Capture
--------------------------------------------------------------------------------
function StatService:RegisterFlagCapture(player)
    if not player or not player:IsA("Player") then return end
    incrementStat(player, "FlagCaptures", 1)
    incrementStat(player, "Score", 100)
    fireEvent(player, self.Actions.FlagCapture, 1)
end

--------------------------------------------------------------------------------
-- Registration: Flag Return
--------------------------------------------------------------------------------
function StatService:RegisterFlagReturn(player)
    if not player or not player:IsA("Player") then return end
    incrementStat(player, "FlagReturns", 1)
    incrementStat(player, "Score", 20)
    fireEvent(player, self.Actions.FlagReturn, 1)
end

--------------------------------------------------------------------------------
-- Registration: Flag Pickup  (informational event, no stat counter)
--------------------------------------------------------------------------------
function StatService:RegisterFlagPickup(player)
    if not player or not player:IsA("Player") then return end
    fireEvent(player, self.Actions.FlagPickup, 1)
end

--------------------------------------------------------------------------------
-- Registration: Match Played
--------------------------------------------------------------------------------
function StatService:RegisterMatchPlayed(player)
    if not player or not player:IsA("Player") then return end
    fireEvent(player, self.Actions.MatchPlayed, 1)
end

--------------------------------------------------------------------------------
-- Registration: Match Won
--------------------------------------------------------------------------------
function StatService:RegisterMatchWon(player)
    if not player or not player:IsA("Player") then return end
    fireEvent(player, self.Actions.MatchWon, 1)
end

--------------------------------------------------------------------------------
-- Death tracking helper  –  hooks Humanoid.Died for each character
--------------------------------------------------------------------------------
function StatService:TrackDeaths(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        humanoid.Died:Connect(function()
            self:RegisterDeath(player)
        end)
    end)
    -- Hook already-spawned character
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Died:Connect(function()
                self:RegisterDeath(player)
            end)
        end
    end
end

return StatService
