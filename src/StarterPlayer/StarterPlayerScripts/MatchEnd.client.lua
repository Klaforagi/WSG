local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fantasy PvP theme palette
local NAVY       = Color3.fromRGB(12, 14, 28)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)
local WHITE       = GOLD_TEXT

-- create end screen GUI (hidden by default)
local screen = Instance.new("ScreenGui")
screen.Name = "MatchEndGui"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0.12, 0)
frame.Size = UDim2.new(0.45, 0, 0.12, 0)
frame.BackgroundColor3 = NAVY
frame.BackgroundTransparency = 0.06
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screen

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(80, 65, 20)
frameStroke.Thickness = 2
frameStroke.Transparency = 0.2
frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
frameStroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -32, 0.55, 0)
title.Position = UDim2.new(0, 16, 0, 12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = GOLD_TEXT
title.Text = ""
title.Parent = frame

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(100, 80, 10)
titleStroke.Thickness = 1.2
titleStroke.Transparency = 0.2
titleStroke.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -32, 0.3, 0)
subtitle.Position = UDim2.new(0, 16, 0.6, 0)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamBold
subtitle.TextScaled = true
subtitle.TextColor3 = Color3.fromRGB(180, 180, 195)
subtitle.Text = ""
subtitle.Parent = frame

local subtitleStroke = Instance.new("UIStroke")
subtitleStroke.Color = Color3.fromRGB(0, 0, 0)
subtitleStroke.Thickness = 0.8
subtitleStroke.Transparency = 0.4
subtitleStroke.Parent = subtitle

local hideThread = nil

local function showEnd(resultType, winner)
    -- cancel any pending hide
    if hideThread then
        pcall(function() task.cancel(hideThread) end)
        hideThread = nil
    end

    if resultType == "sudden" then
        title.Text = "⚔ SUDDEN DEATH ⚔"
        title.TextColor3 = GOLD_TEXT
        subtitle.Text = "Next point wins!"
        pcall(function() playGameSound("SuddenDeath") end)
    elseif resultType == "win" and winner then
        title.Text = "⚔ " .. string.upper(winner) .. " TEAM WINS! ⚔"
        subtitle.Text = "New match starting soon..."
        if winner == "Blue" then
            title.TextColor3 = Color3.fromRGB(65, 130, 255)
        elseif winner == "Red" then
            title.TextColor3 = Color3.fromRGB(255, 75, 75)
        else
            title.TextColor3 = GOLD_TEXT
        end
    else
        title.Text = "MATCH ENDED"
        title.TextColor3 = GOLD_TEXT
        subtitle.Text = ""
    end
    frame.Visible = true

    -- measure text bounds so the frame is only slightly wider than the text
    -- ensure the UI updates first
    title.TextTransparency = 0
    subtitle.TextTransparency = 0
    task.wait()
    local maxTextW = 0
    if title.Text and title.Text ~= "" then maxTextW = math.max(maxTextW, title.TextBounds.X) end
    if subtitle.Text and subtitle.Text ~= "" then maxTextW = math.max(maxTextW, subtitle.TextBounds.X) end
    if maxTextW < 120 then maxTextW = 120 end
    local padX = 48
    local targetW = math.ceil(maxTextW + padX)
    -- compute height from title/subtitle bounds with vertical padding
    local tH = (title.TextBounds.Y ~= 0) and title.TextBounds.Y or 28
    local sH = (subtitle.TextBounds.Y ~= 0) and subtitle.TextBounds.Y or 18
    local targetH = math.ceil(tH + sH + 36)

    -- pop-in animation from a compact pixel size to the computed target size
    frame.Size = UDim2.new(0, math.max(120, math.floor(targetW * 0.75)), 0, math.max(48, math.floor(targetH * 0.75)))
    frame.BackgroundTransparency = 0.5
    TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, targetW, 0, targetH),
        BackgroundTransparency = 0.06,
    }):Play()

    -- auto-hide after a duration (shorter for sudden death)
    local displayTime = (resultType == "sudden") and 3 or 10
    hideThread = task.delay(displayTime, function()
        local fadeOut = TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1,
        })
        TweenService:Create(title, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
        TweenService:Create(subtitle, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
        TweenService:Create(frameStroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
        fadeOut:Play()
        fadeOut.Completed:Wait()
        frame.Visible = false
        -- reset for next use
        title.TextTransparency = 0
        subtitle.TextTransparency = 0
        frameStroke.Transparency = 0.2
        frame.BackgroundTransparency = 0.06
        title.TextColor3 = GOLD_TEXT
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
    title.TextTransparency = 0
    subtitle.TextTransparency = 0
    frameStroke.Transparency = 0.2
    frame.BackgroundTransparency = 0.06
    title.TextColor3 = GOLD_TEXT
end)
