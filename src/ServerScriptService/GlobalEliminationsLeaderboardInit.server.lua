local ServerScriptService = game:GetService("ServerScriptService")

local GlobalEliminationsLeaderboardService = require(ServerScriptService:WaitForChild("GlobalEliminationsLeaderboardService"))

GlobalEliminationsLeaderboardService:Start()