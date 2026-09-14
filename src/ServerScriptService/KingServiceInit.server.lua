local ServerScriptService = game:GetService("ServerScriptService")

local KingService = require(ServerScriptService:WaitForChild("KingService"))
KingService:Init()

_G.KingService = KingService
