-- PvpKills.server.lua
-- Server-authoritative PvP kill tracking
-- Adds a PlayerKills IntValue under each player's leaderstats (creates leaderstats if missing)
-- Exposes a reusable function AwardPlayerKill(killerPlayer, victimPlayer) (also available at _G.AwardPlayerKill)

local Players = game:GetService("Players")
local DEBUG = true

-- Ensure a player's `leaderstats` folder and `PlayerKills` IntValue exist.
-- Use player Attributes for tracking kills so values don't appear on the
-- in-game leaderboard (which only displays values inside a `leaderstats` folder).
local function ensurePlayerKillsAttribute(player)
    if player:GetAttribute("PlayerKills") == nil then
        if DEBUG then
            print("[PvpKills] initializing PlayerKills attribute for", player.Name)
        end
        -- If an old leaderstats.PlayerKills IntValue exists, migrate its value and remove it
        local migrated = false
        local ls = player:FindFirstChild("leaderstats")
        if ls then
            local old = ls:FindFirstChild("PlayerKills")
            if old and old:IsA("IntValue") then
                local v = old.Value or 0
                player:SetAttribute("PlayerKills", v)
                old:Destroy()
                migrated = true
                if DEBUG then
                    print("[PvpKills] migrated leaderstats.PlayerKills for", player.Name, "-> attribute (", v, ")")
                end
            end
        end
        if not migrated then
            player:SetAttribute("PlayerKills", 0)
        end
    end
    return player:GetAttribute("PlayerKills")
end

-- Reusable function to award a PvP kill. Guards against self-kills and missing leaderstats.
local function AwardPlayerKill(killerPlayer, victimPlayer)
    if typeof(killerPlayer) ~= "Instance" or not killerPlayer:IsA("Player") then
        return
    end
    if killerPlayer == victimPlayer then
        return
    end

    -- increment attribute (server authoritative)
    ensurePlayerKillsAttribute(killerPlayer)
    local prev = killerPlayer:GetAttribute("PlayerKills") or 0
    local now = prev + 1
    killerPlayer:SetAttribute("PlayerKills", now)
    if DEBUG then
        print(string.format("[PvpKills] Awarded PvP kill: %s -> %s (new=%d)", killerPlayer.Name, victimPlayer and victimPlayer.Name or "?", now))
    end
end

-- Expose function globally on the server for easy reuse by other server scripts.
-- Note: Using _G is an explicit choice here so other server scripts can call this
-- without requiring a module. If you prefer a ModuleScript, convert this to one.
_G.AwardPlayerKill = AwardPlayerKill

-- Helper: safely get the Player instance from a character
local function getPlayerFromCharacter(character)
    if not character then return nil end
    return Players:GetPlayerFromCharacter(character)
end

-- Hook up a single character to award PvP kills on humanoid death.
local function watchCharacterForPvPKills(character)
    if not character then return end
    local player = getPlayerFromCharacter(character)
    if not player then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:FindFirstChild("Humanoid")
    if not humanoid then
        humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
    end

    local awarded = false
    humanoid.Died:Connect(function()
        if awarded then return end
        awarded = true

        -- Standard Roblox pattern: weapons set an ObjectValue named "creator" on the humanoid
        local handled = false
        local creator = humanoid:FindFirstChild("creator")
        if creator and creator.Value and typeof(creator.Value) == "Instance" then
            local possiblePlayer = creator.Value
            if possiblePlayer:IsA("Player") then
                local victimPlayer = player
                -- Ignore self-kills
                if possiblePlayer ~= victimPlayer then
                    AwardPlayerKill(possiblePlayer, victimPlayer)
                    handled = true
                end
            end
        end

        -- Fallback: some damage code tags the humanoid with attributes instead of a `creator` ObjectValue.
        -- Common attributes: `lastDamagerUserId` and `lastDamageTime` (set by ToolGun/weapon code).
        if not handled then
            local lastDamagerUserId = humanoid:GetAttribute("lastDamagerUserId")
            local lastDamageTime = humanoid:GetAttribute("lastDamageTime")
            if lastDamagerUserId and type(lastDamagerUserId) == "number" then
                -- find player by UserId
                local possiblePlayer = nil
                for _, pl in ipairs(Players:GetPlayers()) do
                    if pl.UserId == lastDamagerUserId then
                        possiblePlayer = pl
                        break
                    end
                end
                if possiblePlayer and possiblePlayer ~= player then
                    -- optional freshness guard: ensure lastDamageTime is recent
                    if not lastDamageTime or (type(lastDamageTime) == "number" and tick() - lastDamageTime < 10) then
                        AwardPlayerKill(possiblePlayer, player)
                        handled = true
                    end
                end
            end
        end
        -- If the killer is not a Player (NPC or nil), do nothing.
    end)
end

-- When a player joins, ensure leaderstats and hook CharacterAdded
local function onPlayerAdded(player)
    -- Ensure PlayerKills attribute exists (do not touch leaderstats folder)
    ensurePlayerKillsAttribute(player)

    player.CharacterAdded:Connect(function(character)
        -- Guard against double connections by watching each character separately
        watchCharacterForPvPKills(character)
    end)

    -- If player already has a character (rare on join), watch it
    if player.Character then
        watchCharacterForPvPKills(player.Character)
    end
end

-- Connect existing players and future players
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Simple API return for other server scripts that may require this file as a ModuleScript
return {
    AwardPlayerKill = AwardPlayerKill,
}
