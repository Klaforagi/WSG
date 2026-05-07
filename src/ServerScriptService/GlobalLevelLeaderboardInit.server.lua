local ServerScriptService = game:GetService("ServerScriptService")

local GlobalLevelLeaderboardService = require(ServerScriptService:WaitForChild("GlobalLevelLeaderboardService"))

GlobalLevelLeaderboardService:Start()