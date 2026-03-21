--------------------------------------------------------------------------------
-- DashServiceInit.server.lua
-- Creates the RequestDash remote and wires DashService into the game.
-- DashApproved is owner-only for local cooldown/UI response.
-- PlayDashVFX is broadcast to all clients so everyone sees dash effects.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DEBUG = true
local function dprint(...)
    if DEBUG then
        print("[DashServiceInit]", ...)
    end
end

--------------------------------------------------------------------------------
-- Require DashService
--------------------------------------------------------------------------------
local DashService = require(ServerScriptService:WaitForChild("DashService", 10))
DashService:Init()

--------------------------------------------------------------------------------
-- EffectDefs (for resolving equipped dash trail color)
--------------------------------------------------------------------------------
local EffectDefs = nil
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
    if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
end)

--------------------------------------------------------------------------------
-- Ensure Remotes folder exists (matches project convention)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

-- Dash sub-folder
local dashFolder = remotesFolder:FindFirstChild("Dash")
if not dashFolder then
    dashFolder = Instance.new("Folder")
    dashFolder.Name = "Dash"
    dashFolder.Parent = remotesFolder
end

-- RequestDash: client -> server (player wants to dash)
local requestDash = dashFolder:FindFirstChild("RequestDash")
if not requestDash then
    requestDash = Instance.new("RemoteEvent")
    requestDash.Name = "RequestDash"
    requestDash.Parent = dashFolder
end

-- DashApproved: server -> client (so client plays VFX / animation)
local dashApproved = dashFolder:FindFirstChild("DashApproved")
if not dashApproved then
    dashApproved = Instance.new("RemoteEvent")
    dashApproved.Name = "DashApproved"
    dashApproved.Parent = dashFolder
end

-- DashRejected: server -> client (so client can reset UI if needed)
local dashRejected = dashFolder:FindFirstChild("DashRejected")
if not dashRejected then
    dashRejected = Instance.new("RemoteEvent")
    dashRejected.Name = "DashRejected"
    dashRejected.Parent = dashFolder
end

-- PlayDashVFX: server -> all clients (all players render the same dash VFX)
local playDashVFX = dashFolder:FindFirstChild("PlayDashVFX")
if not playDashVFX then
    playDashVFX = Instance.new("RemoteEvent")
    playDashVFX.Name = "PlayDashVFX"
    playDashVFX.Parent = dashFolder
end

--------------------------------------------------------------------------------
-- Rate-limit: ignore requests that arrive faster than once per second
--------------------------------------------------------------------------------
local lastRequestTime = {}

--------------------------------------------------------------------------------
-- Handle dash requests
--------------------------------------------------------------------------------
requestDash.OnServerEvent:Connect(function(player)
    -- Basic rate limit
    local now = tick()
    if lastRequestTime[player] and (now - lastRequestTime[player]) < 1 then
        return
    end
    lastRequestTime[player] = now

    local success, reason = DashService:TryDash(player)
    if success then
        dprint("dash approved for", player.Name)
        dashApproved:FireClient(player)

        -- Read the equipped trail from player attribute (set by EffectsService)
        local equippedId = player:GetAttribute("EquippedDashTrail")
        dprint("raw EquippedDashTrail attribute for", player.Name, ":", equippedId or "NIL")

        -- Fallback to DefaultTrail if attribute is missing/blank
        if not equippedId or equippedId == "" then
            equippedId = "DefaultTrail"
            dprint("no equipped trail found, falling back to DefaultTrail")
        end

        -- Validate that the effect exists in EffectDefs
        if EffectDefs then
            local def = EffectDefs.GetById(equippedId)
            if not def then
                dprint("unknown trail id", equippedId, "– falling back to DefaultTrail")
                equippedId = "DefaultTrail"
            end
        end

        -- Send the effect id to all clients so they can resolve color/sequence locally
        dprint("broadcasting dash VFX for", player.Name, "trail:", equippedId)
        if equippedId == "RainbowTrail" then
            dprint("[Dash] Using Rainbow Trail sequence")
        end
        playDashVFX:FireAllClients(player, equippedId)
    else
        dprint("dash rejected for", player.Name, "reason=", reason)
        dashRejected:FireClient(player, reason)
    end
end)

--------------------------------------------------------------------------------
-- Cleanup on player leave
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    DashService:ClearPlayer(player)
    lastRequestTime[player] = nil
end)
