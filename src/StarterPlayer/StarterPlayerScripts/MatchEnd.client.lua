local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))
local AlertBannerStyle = require(ReplicatedStorage:WaitForChild("AlertBannerStyle"))
local TopHudStack = require(ReplicatedStorage:WaitForChild("TopHudStack"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create end screen GUI (hidden by default)
local screen = Instance.new("ScreenGui")
screen.Name = "MatchEndGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 50
screen.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MatchBanner"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = TopHudStack.GetWinPosition()
frame.AutomaticSize = Enum.AutomaticSize.XY
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screen
AlertBannerStyle.BindResponsiveScale(frame)
frame:GetPropertyChangedSignal("Visible"):Connect(TopHudStack.NotifyLayoutChanged)
frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(TopHudStack.NotifyLayoutChanged)

local frameLayout = Instance.new("UIListLayout")
frameLayout.FillDirection = Enum.FillDirection.Vertical
frameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
frameLayout.SortOrder = Enum.SortOrder.LayoutOrder
frameLayout.Padding = UDim.new(0, 4)
frameLayout.Parent = frame

local title = Instance.new("TextLabel")
title.AutomaticSize = Enum.AutomaticSize.XY
title.BackgroundTransparency = 1
title.Font = AlertBannerStyle.Font
title.TextSize = AlertBannerStyle.WinTextSize
title.TextColor3 = AlertBannerStyle.TextColor
title.Text = ""
title.LayoutOrder = 1
title.Parent = frame
local titleStroke = AlertBannerStyle.ApplyTextStroke(title)

local subtitle = Instance.new("TextLabel")
subtitle.AutomaticSize = Enum.AutomaticSize.XY
subtitle.BackgroundTransparency = 1
subtitle.Font = AlertBannerStyle.BodyFont
subtitle.TextSize = AlertBannerStyle.FlagTextSize
subtitle.TextColor3 = AlertBannerStyle.TextColor
subtitle.Text = ""
subtitle.Visible = false
subtitle.LayoutOrder = 2
subtitle.Parent = frame
local subtitleStroke = AlertBannerStyle.ApplyTextStroke(subtitle)

local hideThread = nil
local playGameSound
local showingWinner = false
local function getBannerPosition()
    if showingWinner then return UDim2.new(0.5, 0, 0.01, 0) end
    return UDim2.new(0.5, 0, 0, TopHudStack.GetSuddenTop())
end

local function hideEndScreen()
    if hideThread then
        pcall(function() task.cancel(hideThread) end)
        hideThread = nil
    end
    frame.Visible = false
    title.TextTransparency = 0
    subtitle.TextTransparency = 0
    titleStroke.Transparency = AlertBannerStyle.StrokeTransparency
    subtitleStroke.Transparency = AlertBannerStyle.StrokeTransparency
    title.TextColor3 = AlertBannerStyle.TextColor
end

local function showEnd(resultType, winner)
    showingWinner = resultType ~= "sudden"
    frame:SetAttribute("SuddenDeath", resultType == "sudden")
    -- cancel any pending hide
    if hideThread then
        pcall(function() task.cancel(hideThread) end)
        hideThread = nil
    end

    if resultType == "sudden" then
        title.Text = "SUDDEN DEATH"
        title.TextSize = AlertBannerStyle.SuddenTextSize
        title.TextColor3 = AlertBannerStyle.TextColor
        subtitle.Text = "Next point wins!"
        subtitle.Visible = true
        pcall(function() playGameSound("SuddenDeath") end)
    elseif resultType == "win" and winner then
        title.Text = TeamDisplayNames.GetUpper(winner) .. " WIN!"
        title.TextSize = AlertBannerStyle.WinTextSize
        subtitle.Text = ""
        subtitle.Visible = false
        if winner == "Blue" then
            title.TextColor3 = AlertBannerStyle.KnightsColor
            pcall(function() playGameSound("KnightsWin") end)
        elseif winner == "Red" then
            title.TextColor3 = AlertBannerStyle.BarbariansColor
            pcall(function() playGameSound("BarbariansWin") end)
        else
            title.TextColor3 = AlertBannerStyle.TextColor
        end
    else
        title.Text = "MATCH ENDED"
        title.TextSize = AlertBannerStyle.SuddenTextSize
        title.TextColor3 = AlertBannerStyle.TextColor
        subtitle.Text = ""
        subtitle.Visible = false
    end
    frame.Position = getBannerPosition()
    frame.Visible = true
    task.defer(function()
        if frame.Visible then
            frame.Position = getBannerPosition()
        end
    end)
    title.TextTransparency = 1
    subtitle.TextTransparency = 1
    titleStroke.Transparency = 1
    subtitleStroke.Transparency = 1

    local fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(title, fadeIn, { TextTransparency = 0 }):Play()
    TweenService:Create(titleStroke, fadeIn, { Transparency = AlertBannerStyle.StrokeTransparency }):Play()
    if subtitle.Visible then
        TweenService:Create(subtitle, fadeIn, { TextTransparency = 0 }):Play()
        TweenService:Create(subtitleStroke, fadeIn, { Transparency = AlertBannerStyle.StrokeTransparency }):Play()
    end

    -- The winner replaces the scoreboard until intermission/the next match.
    if showingWinner then return end
    local displayTime = AlertBannerStyle.SuddenHoldSeconds
    hideThread = task.delay(displayTime, function()
        local fadeOut = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(title, fadeOut, { TextTransparency = 1 }):Play()
        TweenService:Create(titleStroke, fadeOut, { Transparency = 1 }):Play()
        TweenService:Create(subtitle, fadeOut, { TextTransparency = 1 }):Play()
        TweenService:Create(subtitleStroke, fadeOut, { Transparency = 1 }):Play()
        task.wait(0.4)
        frame.Visible = false
        title.TextTransparency = 0
        subtitle.TextTransparency = 0
        titleStroke.Transparency = AlertBannerStyle.StrokeTransparency
        subtitleStroke.Transparency = AlertBannerStyle.StrokeTransparency
        title.TextColor3 = AlertBannerStyle.TextColor
        hideThread = nil
    end)
end

-- Only interrupt transient match-alert audio when the win announcement starts.
-- World sounds (mob deaths, swings, impacts, etc.) are deliberately never
-- searched or stopped here.
local MATCH_ALERT_SOUND_NAMES = {
    ClockTick = true,
    SuddenDeath = true,
    KnightsStart = true,
    BarbariansStart = true,
}

local function stopPlayingMatchAlerts(exceptSound)
    local function stopIn(container)
        if not container then
            return
        end
        for _, inst in ipairs(container:GetDescendants()) do
            if inst:IsA("Sound") and inst ~= exceptSound and inst.IsPlaying
                and MATCH_ALERT_SOUND_NAMES[inst.Name] == true then
                pcall(function()
                    inst:Stop()
                end)
            end
        end
    end

    stopIn(workspace.CurrentCamera)
    stopIn(playerGui)
    stopIn(game:GetService("SoundService"))
end

-- play a sound from ReplicatedStorage.Sounds.Game (search recursively)
playGameSound = function(soundName)
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
    if soundName == "KnightsWin" or soundName == "BarbariansWin" then
        stopPlayingMatchAlerts(snd)
    end
    snd:Play()
    task.delay((snd.TimeLength or 2) + 0.2, function()
        if snd and snd.Parent then snd:Destroy() end
    end)
    -- debug
    print("playGameSound: playing", soundName)
end

-- listen for MatchEnd
local function waitForRemote(name, timeout)
    local t = timeout or 5
    local inst = ReplicatedStorage:FindFirstChild(name)
    if inst then return inst end
    local waited = 0
    while waited < t do
        task.wait(0.1)
        waited = waited + 0.1
        inst = ReplicatedStorage:FindFirstChild(name)
        if inst then return inst end
    end
    warn("MatchEnd client: remote '" .. name .. "' not found after " .. tostring(t) .. "s")
    return ReplicatedStorage:FindFirstChild(name)
end

local matchEndEvent = waitForRemote("MatchEnd", 5)
if matchEndEvent then
    matchEndEvent.OnClientEvent:Connect(function(resultType, winner)
        showEnd(resultType, winner)
        if resultType == "sudden" then
            pcall(function() playGameSound("SuddenDeath") end)
        end
    end)
end

-- listen for MatchStart to hide the end screen when a new match begins
local matchStartEvent = waitForRemote("MatchStart", 5)
if matchStartEvent then
    matchStartEvent.OnClientEvent:Connect(function()
        hideEndScreen()
        local teamName = player.Team and player.Team.Name
        if teamName == "Blue" then
            pcall(function() playGameSound("KnightsStart") end)
        elseif teamName == "Red" then
            pcall(function() playGameSound("BarbariansStart") end)
        end
    end)
end

local intermissionEvent = waitForRemote("IntermissionStart", 5)
if intermissionEvent then
    intermissionEvent.OnClientEvent:Connect(function()
        hideEndScreen()
    end)
end

TopHudStack.OnLayoutChanged(function()
    if frame.Visible then
        frame.Position = getBannerPosition()
    end
end)
