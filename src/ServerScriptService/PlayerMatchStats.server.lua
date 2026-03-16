-- PlayerMatchStats.server.lua
-- Initializes per-player match stat tracking via the centralized StatService.
-- All stat storage, attribute syncing, and death tracking are delegated to
-- StatService so every system reads from a single source of truth.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local StatService = require(ServerScriptService:WaitForChild("StatService", 10))

local function onPlayerAdded(player)
	StatService:InitPlayer(player)
	StatService:TrackDeaths(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	StatService:ClearPlayer(player)
end)
