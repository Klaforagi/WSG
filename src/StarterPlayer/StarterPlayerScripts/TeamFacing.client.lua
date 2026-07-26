-- TeamFacing.client.lua
-- Ensure camera yaw matches team side on spawn (Red faces 180° yaw)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function applyTeamYaw(teamName)
    local cam = workspace.CurrentCamera
    if not cam then return end

    local desiredYaw = nil
    if teamName == "Red" or teamName == "Barbarian" then
        desiredYaw = math.pi -- 180°
    elseif teamName == "Blue" then
        desiredYaw = 0
    else
        return
    end

    -- Preserve the camera's pitch (elevation) by building a new lookVector
    -- from the current pitch and the desired yaw. This avoids Euler gimbal
    -- flips that invert the pitch when yaw is rotated by 180°.
    local pos = cam.CFrame.Position
    local look = cam.CFrame.LookVector
    local pitch = math.asin(math.clamp(look.Y, -1, 1)) -- current pitch in radians

    local yaw = desiredYaw
    local cp = math.cos(pitch)
    local newLook = Vector3.new(math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp)

    cam.CFrame = CFrame.new(pos, pos + newLook)
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
