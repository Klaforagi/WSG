local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

Players.PlayerRemoving:Connect(function(player)
    DataSaveCoordinator:HandlePlayerRemoving(player)
end)

game:BindToClose(function()
    DataSaveCoordinator:HandleShutdown()
end)