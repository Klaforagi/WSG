local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Function to handle the killcam
local function onPlayerDied()
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        humanoid.Died:Connect(function()
            -- Wait 1 second before switching to the killer's camera
            task.wait(1)

            -- Get the killer's UserId from the player's humanoid attributes
            local killerUserId = humanoid:GetAttribute("lastDamagerUserId")
            if killerUserId then
                local killer = Players:GetPlayerByUserId(killerUserId)
                if killer and killer.Character then
                    local killerHumanoid = killer.Character:FindFirstChildOfClass("Humanoid")
                    local killerHRP = killer.Character:FindFirstChild("HumanoidRootPart")

                    if killerHumanoid and killerHRP then
                        -- Set the camera to follow the killer with free rotation
                        camera.CameraSubject = killerHumanoid
                        camera.CameraType = Enum.CameraType.Custom

                        -- Wait until the player respawns (server handles LoadCharacter)
                        local newCharacter = player.CharacterAdded:Wait()
                        local newHumanoid = newCharacter:WaitForChild("Humanoid")

                        -- Re-acquire camera in case it changed on respawn
                        camera = workspace.CurrentCamera
                        camera.CameraSubject = newHumanoid
                        camera.CameraType = Enum.CameraType.Custom
                    end
                end
            end
        end)
    end
end

-- Connect the function to the player's character
if player.Character then
    onPlayerDied()
end

player.CharacterAdded:Connect(onPlayerDied)