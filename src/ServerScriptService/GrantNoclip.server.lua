-- GrantNoclip.server.lua
-- Clones ServerStorage.Tools.Dev.Noclip into each player's StarterGear and Backpack
-- so the client can equip/unequip it locally.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local TOOLS_ROOT = ServerStorage:WaitForChild("Tools")
local DEV_FOLDER = TOOLS_ROOT:FindFirstChild("Dev")
local TEMPLATE_NAME = "Noclip"

local function grantOnce(player)
    if not DEV_FOLDER then return end
    local template = DEV_FOLDER:FindFirstChild(TEMPLATE_NAME)
    if not template then return end

    local ok, sg = pcall(function() return player:WaitForChild("StarterGear", 5) end)
    local bp = player:FindFirstChildOfClass("Backpack")

    -- StarterGear (persistent across respawn)
    if ok and sg and not sg:FindFirstChild(TEMPLATE_NAME) then
        local c = template:Clone()
        c.Parent = sg
    end

    -- Backpack (immediate availability)
    if bp and not bp:FindFirstChild(TEMPLATE_NAME) then
        local c = template:Clone()
        c.Parent = bp
    end
end

local function onPlayerAdded(player)
    -- give immediately
    grantOnce(player)

    -- also ensure on character spawn (engine may create Backpack/StarterGear after join)
    player.CharacterAdded:Connect(function()
        task.wait(0.15)
        grantOnce(player)
    end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- handle existing players in Studio
for _,p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end
