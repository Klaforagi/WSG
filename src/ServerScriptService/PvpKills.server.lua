-- PvpKills.server.lua
-- LEGACY: PvP kill tracking has been centralized into StatService.
-- KillTracker.server.lua is now the single kill-detection entry point and
-- calls StatService:RegisterElimination / RegisterMobKill.
--
-- This script only provides a backward-compatible _G.AwardPlayerKill stub
-- so any external weapon scripts that reference it will not error.
-- The stub is a no-op; all real stat work flows through StatService.

local DEBUG = true

local function AwardPlayerKill(killerPlayer, victimPlayer)
    -- No-op: StatService handles all stat mutations via KillTracker.
    if DEBUG then
        local kName = (typeof(killerPlayer) == "Instance" and killerPlayer.Name) or "?"
        local vName = (typeof(victimPlayer) == "Instance" and victimPlayer.Name) or "?"
        print(string.format("[PvpKills] Legacy AwardPlayerKill(%s, %s) – no-op, handled by StatService", kName, vName))
    end
end

_G.AwardPlayerKill = AwardPlayerKill

return {
    AwardPlayerKill = AwardPlayerKill,
}
