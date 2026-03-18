--------------------------------------------------------------------------------
-- DashServiceInit.server.lua
-- Creates the RequestDash remote and wires DashService into the game.
-- Fires DashApproved back to the client so it can play effects locally.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Require DashService
--------------------------------------------------------------------------------
local DashService = require(ServerScriptService:WaitForChild("DashService", 10))
DashService:Init()

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
        dashApproved:FireClient(player)
    else
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
