local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create end screen GUI (hidden by default)
local screen = Instance.new("ScreenGui")
screen.Name = "MatchEndGui"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0.12, 0)
frame.Size = UDim2.new(0.45, 0, 0.12, 0)
frame.BackgroundTransparency = 0.15
frame.BackgroundColor3 = Color3.fromRGB(20,20,28)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screen

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -32, 0.55, 0)
title.Position = UDim2.new(0, 16, 0, 12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Text = ""
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -32, 0.3, 0)
subtitle.Position = UDim2.new(0, 16, 0.6, 0)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamBold
subtitle.TextScaled = true
subtitle.TextColor3 = Color3.fromRGB(180, 180, 180)
subtitle.Text = ""
subtitle.Parent = frame

local hideThread = nil

local function showEnd(resultType, winner)
    -- cancel any pending hide
    if hideThread then
        pcall(function() task.cancel(hideThread) end)
        hideThread = nil
    end

    if resultType == "sudden" then
        title.Text = "SUDDEN DEATH"
        title.TextColor3 = Color3.fromRGB(255, 200, 60)
        subtitle.Text = "Next point wins!"
        pcall(function() playGameSound("SuddenDeath") end)
    elseif resultType == "win" and winner then
        title.Text = string.upper(winner) .. " TEAM WINS!"
        subtitle.Text = "New match starting soon..."
        if winner == "Blue" then
            title.TextColor3 = Color3.fromRGB(100, 160, 255)
        elseif winner == "Red" then
            title.TextColor3 = Color3.fromRGB(255, 100, 100)
        else
            title.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    else
        title.Text = "MATCH ENDED"
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        subtitle.Text = ""
    end
    frame.Visible = true

    -- auto-hide after 10 seconds (unless a new event overrides)
    hideThread = task.delay(10, function()
        frame.Visible = false
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        hideThread = nil
    end)
end

-- play a sound from ReplicatedStorage.Sounds.Game (search recursively)
local function playGameSound(soundName)
    if not soundName then return end
    local sounds = ReplicatedStorage:FindFirstChild("Sounds")
    if not sounds then
        warn("playGameSound: ReplicatedStorage.Sounds missing")
        return
    end
    local gameFolder = sounds:FindFirstChild("Game")
    if not gameFolder then
        warn("playGameSound: Sounds.Game folder missing")
        return
    end
    -- search recursively for the sound name to be more robust (avoid deprecated recursive FindFirstChild)
    local s = nil
    for _, v in ipairs(gameFolder:GetDescendants()) do
        if v.Name == soundName then
            s = v
            break
        end
    end
    if not s then
        warn("playGameSound: sound not found:", soundName)
        return
    end
    -- if the found instance is not a Sound, try to find a Sound descendant
    local soundInst = nil
    if s:IsA("Sound") then
        soundInst = s
    else
        soundInst = s:FindFirstChildOfClass("Sound") or s:FindFirstChild("ClockTick")
    end
    if not soundInst or not soundInst:IsA("Sound") then
        warn("playGameSound: no Sound instance for:", soundName)
        return
    end
    local cam = workspace.CurrentCamera
    local parent = cam or playerGui
    local snd = soundInst:Clone()
    snd.Parent = parent
    snd:Play()
    task.delay((snd.TimeLength or 2) + 0.2, function()
        if snd and snd.Parent then snd:Destroy() end
    end)
    -- debug
    print("playGameSound: playing", soundName)
end

-- listen for MatchEnd
local matchEndEvent = ReplicatedStorage:WaitForChild("MatchEnd")
matchEndEvent.OnClientEvent:Connect(function(resultType, winner)
    showEnd(resultType, winner)
    if resultType == "sudden" then
        pcall(function() playGameSound("SuddenDeath") end)
    end
end)

-- listen for MatchStart to hide the end screen when a new match begins
local matchStartEvent = ReplicatedStorage:WaitForChild("MatchStart")
matchStartEvent.OnClientEvent:Connect(function()
    if hideThread then
        pcall(function() task.cancel(hideThread) end)
        hideThread = nil
    end
    frame.Visible = false
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
end)
