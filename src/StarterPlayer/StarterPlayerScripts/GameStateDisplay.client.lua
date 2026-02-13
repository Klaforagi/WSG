local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI: compact panel on the right side that scales with viewport
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameStateUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "GameStateFrame"
frame.Size = UDim2.new(0.12, 0, 0.08, 0) -- scales with screen
frame.Position = UDim2.new(0.98, 0, 0.10, 0)
frame.AnchorPoint = Vector2.new(1, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.ZIndex = 50
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0.35, 0)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Text = "GAME STATE"
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(200, 200, 200)
title.Parent = frame

local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, -16, 0.6, 0)
stateLabel.Position = UDim2.new(0, 8, 0.35, 6)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = Enum.Font.GothamBlack
stateLabel.TextScaled = true
stateLabel.Text = "IDLE"
stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
stateLabel.Parent = frame

local function setState(name)
    if not name then name = "Idle" end
    local n = tostring(name)
    stateLabel.Text = string.upper(n)
    if n == "Game" then
        stateLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
    elseif n == "SuddenDeath" or n == "sudden" then
        stateLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
    elseif n == "EndGame" or n == "win" then
        stateLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    else
        stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

-- initial state
setState("Idle")

-- Wire events
local matchStart = ReplicatedStorage:FindFirstChild("MatchStart")
if matchStart and matchStart:IsA("RemoteEvent") then
    matchStart.OnClientEvent:Connect(function(duration, startTick)
        setState("Game")
    end)
end

local matchEnd = ReplicatedStorage:FindFirstChild("MatchEnd")
if matchEnd and matchEnd:IsA("RemoteEvent") then
    matchEnd.OnClientEvent:Connect(function(resultType, winner)
        if resultType == "sudden" then
            setState("SuddenDeath")
        else
            setState("EndGame")
        end
    end)
end

-- If events are created later, wire them
ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "MatchStart" and child:IsA("RemoteEvent") then
        child.OnClientEvent:Connect(function(duration, startTick)
            setState("Game")
        end)
    elseif child.Name == "MatchEnd" and child:IsA("RemoteEvent") then
        child.OnClientEvent:Connect(function(resultType, winner)
            if resultType == "sudden" then
                setState("SuddenDeath")
            else
                setState("EndGame")
            end
        end)
    end
end)

-- Resync on startup by invoking server's GetMatchState (if available)
spawn(function()
    local ok, fn = pcall(function() return ReplicatedStorage:WaitForChild("GetMatchState", 5) end)
    if not ok or not fn then return end
    if not fn:IsA("RemoteFunction") then return end
    local ok2, info = pcall(function() return fn:InvokeServer() end)
    if not ok2 or type(info) ~= "table" then return end
    if info.state == "Game" then
        setState("Game")
    elseif info.state == "SuddenDeath" then
        setState("SuddenDeath")
    elseif info.state == "EndGame" then
        setState("EndGame")
    else
        setState("Idle")
    end
end)

return nil
