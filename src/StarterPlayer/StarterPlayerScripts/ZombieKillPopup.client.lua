local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fantasy PvP theme palette
local NAVY       = Color3.fromRGB(12, 14, 28)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)

-- create a ScreenGui that persists across respawns
local gui = Instance.new("ScreenGui")
gui.Name = "ZombieKillGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

local function showDGH()
    -- dark navy backdrop panel
    local panel = Instance.new("Frame")
    panel.Name = "DGHPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.35, 0)
    panel.Size = UDim2.new(0, 220, 0, 60)
    panel.BackgroundColor3 = NAVY
    panel.BackgroundTransparency = 0.1
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 65, 20)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.3
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = panel

    local label = Instance.new("TextLabel")
    label.Name = "DGH"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.Text = "DGH"
    label.TextColor3 = GOLD_TEXT
    label.TextTransparency = 1
    label.Parent = panel

    local lblStroke = Instance.new("UIStroke")
    lblStroke.Color = Color3.fromRGB(100, 80, 10)
    lblStroke.Thickness = 1.2
    lblStroke.Transparency = 0.2
    lblStroke.Parent = label

    -- pop-in: scale up from 80% + fade in
    panel.Size = UDim2.new(0, 176, 0, 48)
    local popIn = TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 220, 0, 60),
    })
    local fadeIn = TweenService:Create(label, TweenInfo.new(0.15), {
        TextTransparency = 0,
    })

    popIn:Play()
    fadeIn:Play()
    fadeIn.Completed:Wait()

    -- hold
    task.wait(1)

    -- fade out + slide up
    local fadeOut = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        TextTransparency = 1,
    })
    local slideUp = TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, 0, 0.30, 0),
        BackgroundTransparency = 1,
    })
    local strokeFade = TweenService:Create(stroke, TweenInfo.new(0.5), {
        Transparency = 1,
    })

    fadeOut:Play()
    slideUp:Play()
    strokeFade:Play()
    slideUp.Completed:Wait()
    panel:Destroy()
end

-- connect to ZombieKill remote when available without blocking
local zombieKillEvent = ReplicatedStorage:FindFirstChild("ZombieKill")
local function bindZombieKill(ev)
    if not ev then return end
    ev.OnClientEvent:Connect(function()
        showDGH()
    end)
end
if zombieKillEvent then
    bindZombieKill(zombieKillEvent)
else
    local conn
    conn = ReplicatedStorage.ChildAdded:Connect(function(child)
        if child and child.Name == "ZombieKill" and child:IsA("RemoteEvent") then
            bindZombieKill(child)
            if conn then conn:Disconnect() end
        end
    end)
end
