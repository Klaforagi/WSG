-- TeamFacing.client.lua
-- Ensure camera yaw matches team side on spawn (Red faces 180° yaw)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function applyTeamYaw(teamName)
    local cam = workspace.CurrentCamera
    if not cam then return end
    if teamName == "Red" or teamName == "Barbarian" then
        -- set camera to pitch=15°, yaw=180° (preserve position)
        local pos = cam.CFrame.Position
        cam.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(15), math.rad(180), 0)
    end
end

local function onCharacterAdded(char)
    -- small delay to let other camera scripts initialize
    task.delay(0.06, function()
        local team = player:GetAttribute("Team")
        applyTeamYaw(team)
    end)
end

-- Initial run for existing character (join case)
if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- Also react to explicit team attribute changes while alive
player:GetAttributeChangedSignal("Team"):Connect(function()
    -- apply yaw if team changes and character exists
    if player.Character then
        applyTeamYaw(player:GetAttribute("Team"))
    end
end)

return nil
