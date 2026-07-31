local ServerScriptService = game:GetService("ServerScriptService")

local GamepassService = require(ServerScriptService:WaitForChild("GamepassService"))
GamepassService:Init()

print("[GamepassServiceInit] initialized")