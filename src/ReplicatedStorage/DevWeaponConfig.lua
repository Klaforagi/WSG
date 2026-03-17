--------------------------------------------------------------------------------
-- DevWeaponConfig.lua  –  Shared config for developer-only weapons
-- ModuleScript in ReplicatedStorage (readable by both server & client).
--
-- All authorization and feature-flag checks live here so nothing is
-- hard-coded across multiple files.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local Config = {}

--------------------------------------------------------------------------------
-- FEATURE FLAGS
--------------------------------------------------------------------------------
Config.ENABLE_DEV_ROCKET   = true   -- master switch
Config.ALLOW_IN_STUDIO     = true   -- Roblox Studio play-solo / team test
Config.ALLOW_IN_TEAM_TEST  = true   -- team-test sessions
Config.ALLOW_IN_LIVE_SERVERS = true  -- live servers (still UserId-locked)

--------------------------------------------------------------------------------
-- AUTHORIZED DEVELOPER USER IDS
-- Key = UserId (number), Value = true
--------------------------------------------------------------------------------
Config.DEV_USER_IDS = {
    [285568988] = true, -- Edithonus
    [285563003] = true, -- Klaf
}

--------------------------------------------------------------------------------
-- ROCKET LAUNCHER SETTINGS
--------------------------------------------------------------------------------
Config.ROCKET_DAMAGE        = 100    -- flat damage (one-shot vs 100 HP)
Config.ROCKET_BLAST_RADIUS  = 15     -- studs
Config.ROCKET_SPEED         = 120    -- studs per second
Config.ROCKET_LIFETIME      = 6      -- seconds before self-destruct
Config.ROCKET_COOLDOWN      = 1.2    -- seconds between shots

Config.FRIENDLY_FIRE        = false  -- damage teammates?
Config.SELF_DAMAGE          = false  -- damage the shooter?

Config.TOOL_NAME            = "DevRocketLauncher"

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

--- Returns true if the given Player is an authorized dev.
function Config.IsAuthorizedDevPlayer(player)
    if not player or not player:IsA("Player") then return false end
    return Config.DEV_USER_IDS[player.UserId] == true
end

--- Returns true if the dev rocket feature is allowed in this server instance.
function Config.IsDevRocketAllowedInThisServer()
    if not Config.ENABLE_DEV_ROCKET then
        return false, "ENABLE_DEV_ROCKET is false"
    end

    local isStudio = RunService:IsStudio()

    if isStudio then
        if Config.ALLOW_IN_STUDIO then
            return true, "Studio environment"
        else
            return false, "Disabled in Studio"
        end
    end

    -- Non-studio: check if this could be a team-test style server.
    -- Team Test sessions are identified by RunService:IsServer() being true
    -- while the place is accessed from Studio (no easy direct flag).
    -- In practice, non-Studio servers are either team-test or live.
    -- We treat any non-Studio server as a live server for safety.
    if Config.ALLOW_IN_LIVE_SERVERS then
        return true, "Live servers allowed"
    end

    return false, "Disabled in live servers"
end

return Config
