local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local START_TIME_SECONDS = 20 * 60 -- 20 minutes

-- State
local blueScore = 0
local redScore = 0
local remaining = START_TIME_SECONDS
local running = true

-- Create HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, 8)
root.Size = UDim2.new(0.9, 0, 0, 60)
root.BackgroundTransparency = 1
root.Parent = screenGui

local uiLayout = Instance.new("UIListLayout")
uiLayout.FillDirection = Enum.FillDirection.Horizontal
uiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiLayout.VerticalAlignment = Enum.VerticalAlignment.Center
uiLayout.Padding = UDim.new(0, 8)
uiLayout.Parent = root

local function makePanel()
    local p = Instance.new("Frame")
    p.Size = UDim2.new(0.3, 0, 1, 0)
    p.BackgroundTransparency = 0.15
    p.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    p.BorderSizePixel = 0
    local corner = Instance.new("UICorner") corner.CornerRadius = UDim.new(0, 8) corner.Parent = p
    return p
end

local bluePanel = makePanel()
bluePanel.Parent = root
local centerPanel = makePanel()
centerPanel.Size = UDim2.new(0.25, 0, 1, 0)
centerPanel.Parent = root
local redPanel = makePanel()
redPanel.Parent = root

-- Blue panel contents
local blueName = Instance.new("TextLabel")
blueName.Text = "BLUE"
blueName.Font = Enum.Font.GothamBold
blueName.TextScaled = true
blueName.TextColor3 = Color3.fromRGB(170, 200, 255)
blueName.BackgroundTransparency = 1
blueName.Size = UDim2.new(1, -16, 0.5, 0)
blueName.Position = UDim2.new(0, 8, 0, 2)
blueName.Parent = bluePanel

local blueCountLabel = Instance.new("TextLabel")
blueCountLabel.Text = tostring(blueScore)
blueCountLabel.Font = Enum.Font.GothamBlack
blueCountLabel.TextScaled = true
blueCountLabel.TextColor3 = Color3.fromRGB(220, 240, 255)
blueCountLabel.BackgroundTransparency = 1
blueCountLabel.Size = UDim2.new(1, -16, 0.5, -4)
blueCountLabel.Position = UDim2.new(0, 8, 0.5, 2)
blueCountLabel.Parent = bluePanel

-- Red panel contents
local redName = Instance.new("TextLabel")
redName.Text = "RED"
redName.Font = Enum.Font.GothamBold
redName.TextScaled = true
redName.TextColor3 = Color3.fromRGB(255, 150, 150)
redName.BackgroundTransparency = 1
redName.Size = UDim2.new(1, -16, 0.5, 0)
redName.Position = UDim2.new(0, 8, 0, 2)
redName.Parent = redPanel

local redCountLabel = Instance.new("TextLabel")
redCountLabel.Text = tostring(redScore)
redCountLabel.Font = Enum.Font.GothamBlack
redCountLabel.TextScaled = true
redCountLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
redCountLabel.BackgroundTransparency = 1
redCountLabel.Size = UDim2.new(1, -16, 0.5, -4)
redCountLabel.Position = UDim2.new(0, 8, 0.5, 2)
redCountLabel.Parent = redPanel

-- Center timer
local timerLabel = Instance.new("TextLabel")
timerLabel.Text = "20:00"
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextScaled = true
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.BackgroundTransparency = 1
timerLabel.Size = UDim2.new(1, -16, 1, 0)
timerLabel.Position = UDim2.new(0, 8, 0, 0)
timerLabel.Parent = centerPanel

-- Helpers
local function formatTime(sec)
    if sec < 0 then sec = 0 end
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%02d:%02d", m, s)
end

local function refresh()
    blueCountLabel.Text = tostring(blueScore)
    redCountLabel.Text = tostring(redScore)
    timerLabel.Text = formatTime(remaining)
end

-- Timer loop
spawn(function()
    while true do
        if running then
            remaining = remaining - 1
            if remaining < 0 then
                running = false
                remaining = 0
            end
            refresh()
        end
        wait(1)
    end
end)

-- Remote event handlers (optional server hooks)
local function wireScoreEvent(ev)
    ev.OnClientEvent:Connect(function(teamName, value, absolute)
        -- If absolute is true, set score to value; otherwise treat as delta
        if teamName == "Blue" then
            if absolute then blueScore = value else blueScore = blueScore + value end
        elseif teamName == "Red" then
            if absolute then redScore = value else redScore = redScore + value end
        end
        refresh()
    end)
end

local function wireMatchStart(ev)
    ev.OnClientEvent:Connect(function(durationSeconds)
        if type(durationSeconds) == "number" then
            remaining = durationSeconds
        else
            remaining = START_TIME_SECONDS
        end
        running = true
        refresh()
    end)
end

-- Connect if events already exist, or wait for them to be created
local scoreEv = ReplicatedStorage:FindFirstChild("ScoreUpdate")
if scoreEv and scoreEv:IsA("RemoteEvent") then wireScoreEvent(scoreEv) end
local matchEv = ReplicatedStorage:FindFirstChild("MatchStart")
if matchEv and matchEv:IsA("RemoteEvent") then wireMatchStart(matchEv) end

ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "ScoreUpdate" and child:IsA("RemoteEvent") then
        wireScoreEvent(child)
    elseif child.Name == "MatchStart" and child:IsA("RemoteEvent") then
        wireMatchStart(child)
    end
end)

-- initial refresh
refresh()
