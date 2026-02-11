local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlagStatusGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Parent = playerGui

local FlagStatus = ReplicatedStorage:WaitForChild("FlagStatus")

local function showMessage(text, teamName)
    -- pick team color
    local color = Color3.new(1, 1, 1)
    if teamName == "Blue" then
        color = Color3.fromRGB(0, 162, 255)
    elseif teamName == "Red" then
        color = Color3.fromRGB(255, 75, 75)
    end

    local label = Instance.new("TextLabel")
    label.Name = "FlagMsg"
    label.Size = UDim2.new(0.6, 0, 0, 50)
    label.Position = UDim2.new(0.2, 0, 0.12, 0)
    label.AnchorPoint = Vector2.new(0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.Text = text
    label.ZIndex = 100
    label.Parent = screenGui

    -- fade out after 3 seconds
    task.delay(3, function()
        if label and label.Parent then
            for i = 1, 10 do
                label.TextTransparency = i / 10
                label.TextStrokeTransparency = i / 10
                task.wait(0.05)
            end
            if label and label.Parent then
                label:Destroy()
            end
        end
    end)
end

FlagStatus.OnClientEvent:Connect(function(eventType, playerName, teamName)
    if eventType == "pickup" then
        showMessage(playerName .. " picked up the " .. teamName .. " Flag!", teamName)
    elseif eventType == "returned" then
        showMessage("The " .. teamName .. " Flag has been returned!", teamName)
    end
end)
