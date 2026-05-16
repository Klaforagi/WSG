local ServerScriptService = game:GetService("ServerScriptService")

local GlobalUpgradeLeaderboardsService = require(ServerScriptService:WaitForChild("GlobalUpgradeLeaderboardsService"))

GlobalUpgradeLeaderboardsService:Start()