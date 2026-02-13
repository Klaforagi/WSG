local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create a ScreenGui that persists across respawns
local gui = Instance.new("ScreenGui")
gui.Name = "ZombieKillGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

local function showDGH()
    local label = Instance.new("TextLabel")
    label.Name = "DGH"
    label.Size = UDim2.new(0, 300, 0, 80)
    label.Position = UDim2.new(0.5, -150, 0.35, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 52
    label.Text = "DGH"
    label.TextColor3 = Color3.fromRGB(255, 50, 50)
    label.TextStrokeTransparency = 0.4
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextTransparency = 0
    label.Parent = gui

    -- fade in, hold, then fade out and slide up
    local fadeIn = TweenService:Create(label, TweenInfo.new(0.15), {
        TextTransparency = 0,
    })
    local hold = TweenService:Create(label, TweenInfo.new(1), {})
    local fadeOut = TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        Position = UDim2.new(0.5, -150, 0.3, 0),
    })

    fadeIn:Play()
    fadeIn.Completed:Wait()
    hold:Play()
    hold.Completed:Wait()
    fadeOut:Play()
    fadeOut.Completed:Wait()
    label:Destroy()
end

-- wait for the ZombieKill remote (no timeout — the server creates it at startup)
local zombieKillEvent = ReplicatedStorage:WaitForChild("ZombieKill")
zombieKillEvent.OnClientEvent:Connect(function()
    showDGH()
end)
