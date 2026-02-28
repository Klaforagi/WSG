local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fantasy PvP theme palette
local NAVY       = Color3.fromRGB(12, 14, 28)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)
local WHITE       = GOLD_TEXT

-- UI: compact panel on the right side
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameStateUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "GameStateFrame"
frame.Size = UDim2.new(0.14, 0, 0.13, 0)
-- moved to intermediate position between top and minimap
frame.Position = UDim2.new(0.98, 0, 0.44, 0)
frame.AnchorPoint = Vector2.new(1, 0)
frame.BackgroundColor3 = NAVY
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.ZIndex = 50
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(60, 55, 35)
frameStroke.Thickness = 1.5
frameStroke.Transparency = 0.4
frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
frameStroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0.28, 0)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Text = "GAME STATE"
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = GOLD_TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Top
title.Parent = frame

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(80, 60, 0)
titleStroke.Thickness = 0.8
titleStroke.Transparency = 0.3
titleStroke.Parent = title

local stateLabel = Instance.new("TextLabel")
stateLabel.Size = UDim2.new(1, -16, 0.32, 0)
stateLabel.Position = UDim2.new(0, 8, 0.28, 0)
stateLabel.BackgroundTransparency = 1
stateLabel.Font = Enum.Font.GothamBlack
stateLabel.TextScaled = true
stateLabel.Text = "IDLE"
stateLabel.TextColor3 = GOLD_TEXT
stateLabel.TextXAlignment = Enum.TextXAlignment.Left
stateLabel.TextYAlignment = Enum.TextYAlignment.Center
stateLabel.ClipsDescendants = true
stateLabel.Parent = frame

local stateLblStroke = Instance.new("UIStroke")
stateLblStroke.Color = Color3.fromRGB(0, 0, 0)
stateLblStroke.Thickness = 0.8
stateLblStroke.Transparency = 0.4
stateLblStroke.Parent = stateLabel

local playerStateLabel = Instance.new("TextLabel")
playerStateLabel.Size = UDim2.new(1, -16, 0.32, 0)
playerStateLabel.Position = UDim2.new(0, 8, 0.60, 0)
playerStateLabel.BackgroundTransparency = 1
playerStateLabel.Font = Enum.Font.GothamBold
playerStateLabel.TextScaled = true
playerStateLabel.Text = ""
playerStateLabel.TextColor3 = Color3.fromRGB(140, 180, 230)
playerStateLabel.TextXAlignment = Enum.TextXAlignment.Left
playerStateLabel.TextYAlignment = Enum.TextYAlignment.Center
playerStateLabel.ClipsDescendants = true
playerStateLabel.Parent = frame

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
        stateLabel.TextColor3 = GOLD_TEXT
    end
end


-- initial state
setState("Idle")
playerStateLabel.Text = ""

-- Update player movement state
local function updatePlayerStateLabel()
    local char = player.Character
    if not char then playerStateLabel.Text = "" return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then playerStateLabel.Text = "" return end
    local state = hum:GetState()
    local stateName = tostring(state):gsub("Enum.HumanoidStateType.", "")
    playerStateLabel.Text = "State: " .. stateName
end

-- Listen for state changes
local function hookHumanoidState()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.StateChanged:Connect(function(_, newState)
        local stateName = tostring(newState):gsub("Enum.HumanoidStateType.", "")
        playerStateLabel.Text = "State: " .. stateName
    end)
    -- set initial
    updatePlayerStateLabel()
end

if player.Character then hookHumanoidState() end
player.CharacterAdded:Connect(function()
    hookHumanoidState()
end)

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
