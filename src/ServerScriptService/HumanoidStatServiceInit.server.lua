local ServerScriptService = game:GetService("ServerScriptService")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

HumanoidStatService:Init()

_G.HumanoidStatService = HumanoidStatService

print("[HumanoidStatServiceInit] ready")