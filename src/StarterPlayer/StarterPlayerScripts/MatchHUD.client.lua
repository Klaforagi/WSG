local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local START_TIME_SECONDS = 1 * 60

-- Fantasy PvP theme palette
local NAVY        = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT  = Color3.fromRGB(22, 26, 48)
local GOLD_TEXT    = Color3.fromRGB(255, 215, 80)
local BLUE_ACCENT  = Color3.fromRGB(65, 130, 255)
local BLUE_GLOW    = Color3.fromRGB(40, 80, 180)
local RED_ACCENT   = Color3.fromRGB(255, 75, 75)
local RED_GLOW     = Color3.fromRGB(180, 40, 40)
local WHITE        = GOLD_TEXT

-- State
local blueScore = 0
local redScore = 0
local remaining = START_TIME_SECONDS
local running = true
local matchStartTick = nil
local matchDuration = START_TIME_SECONDS
local lastIntegerRemaining = nil
local lastTickSoundTime = 0

-- Create HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0.01, 0)
root.Size = UDim2.new(0.43, 0, 0.055, 0)
root.BackgroundTransparency = 1
root.Parent = screenGui

local rootConstraint = Instance.new("UISizeConstraint")
rootConstraint.MinSize = Vector2.new(200, 28)
rootConstraint.MaxSize = Vector2.new(math.huge, 60)
rootConstraint.Parent = root

local uiLayout = Instance.new("UIListLayout")
uiLayout.FillDirection = Enum.FillDirection.Horizontal
uiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiLayout.VerticalAlignment = Enum.VerticalAlignment.Center
uiLayout.Padding = UDim.new(0, 2)
uiLayout.Parent = root

local function makePanel(accentColor)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(0.28, 0, 1, 0)
    p.BackgroundColor3 = NAVY
    p.BackgroundTransparency = 0.08
    p.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = p
    -- subtle team-colored glow border
    local stroke = Instance.new("UIStroke")
    stroke.Color = accentColor or Color3.fromRGB(60, 60, 80)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = p
    return p
end

local bluePanel = makePanel(BLUE_GLOW)
bluePanel.Parent = root
local centerPanel = makePanel(Color3.fromRGB(80, 70, 40))
centerPanel.Size = UDim2.new(0.14, 0, 1, 0)
centerPanel.Parent = root
local redPanel = makePanel(RED_GLOW)
redPanel.Parent = root

local FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")

-- makeFlagSlot: creates two square indicators and keeps them responsive to panel size
local function makeFlagSlot(panel, alignRight)
    local slot = Instance.new("Frame")
    slot.Size = UDim2.new(1, 0, 1, 0)
    slot.BackgroundTransparency = 1
    slot.ZIndex = 2
    slot.Parent = panel

    -- carried squares for both flag colors; only shown when that flag is carried by this team
    local blueCarried = Instance.new("Frame")
    blueCarried.Name = "BlueCarriedSquare"
    blueCarried.AnchorPoint = Vector2.new(0, 0)
    blueCarried.BackgroundTransparency = 0
    blueCarried.BorderSizePixel = 0
    blueCarried.Visible = false
    blueCarried.Parent = slot

    local redCarried = Instance.new("Frame")
    redCarried.Name = "RedCarriedSquare"
    redCarried.AnchorPoint = Vector2.new(0, 0)
    redCarried.BackgroundTransparency = 0
    redCarried.BorderSizePixel = 0
    redCarried.Visible = false
    redCarried.Parent = slot

    local function updateSizes()
        local abs = slot.AbsoluteSize
        if abs.X == 0 or abs.Y == 0 then return end
        local squareSize = math.clamp(math.floor(abs.Y * 0.6), 12, 48)
        local spacing = math.max(4, math.floor(squareSize * 0.25))
        local y = math.floor((abs.Y - squareSize) / 2)

        if alignRight then
            local rightPadding = 8
            local rightOffset = -rightPadding - squareSize
            local leftOffset = rightOffset - spacing - squareSize
            -- if both visible, keep left/right order near the inner edge; if only one, anchor it at the inner edge
            if blueCarried.Visible and redCarried.Visible then
                blueCarried.Position = UDim2.new(1, leftOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            elseif redCarried.Visible then
                -- red alone: place at inner (right) edge between text and timer
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
                blueCarried.Position = UDim2.new(1, rightOffset, 0, y)
            elseif blueCarried.Visible then
                -- blue alone: place at inner edge as well
                blueCarried.Position = UDim2.new(1, rightOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            else
                blueCarried.Position = UDim2.new(1, leftOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            end
        else
            local leftPadding = 8
            local leftX = leftPadding
            local rightX = leftX + squareSize + spacing
            if blueCarried.Visible and redCarried.Visible then
                blueCarried.Position = UDim2.new(0, leftX, 0, y)
                redCarried.Position = UDim2.new(0, rightX, 0, y)
            elseif blueCarried.Visible then
                blueCarried.Position = UDim2.new(0, leftX, 0, y)
                redCarried.Position = UDim2.new(0, leftX, 0, y)
            elseif redCarried.Visible then
                redCarried.Position = UDim2.new(0, leftX, 0, y)
                blueCarried.Position = UDim2.new(0, leftX, 0, y)
            else
                blueCarried.Position = UDim2.new(0, leftX, 0, y)
                redCarried.Position = UDim2.new(0, rightX, 0, y)
            end
        end
        blueCarried.Size = UDim2.new(0, squareSize, 0, squareSize)
        redCarried.Size = UDim2.new(0, squareSize, 0, squareSize)
    end

    slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSizes)
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSizes)
    blueCarried:GetPropertyChangedSignal("Visible"):Connect(updateSizes)
    redCarried:GetPropertyChangedSignal("Visible"):Connect(updateSizes)
    -- initial call (may run once layout resolves)
    spawn(function()
        wait()
        updateSizes()
    end)

    return {slot = slot, blue = blueCarried, red = redCarried}
end

local blueFlagSlot = makeFlagSlot(bluePanel, true)
local redFlagSlot = makeFlagSlot(redPanel, false)

-- color the carried squares appropriately
blueFlagSlot.blue.BackgroundColor3 = Color3.fromRGB(65,105,225)
blueFlagSlot.red.BackgroundColor3 = Color3.fromRGB(255,75,75)
redFlagSlot.blue.BackgroundColor3 = Color3.fromRGB(65,105,225)
redFlagSlot.red.BackgroundColor3 = Color3.fromRGB(255,75,75)

local function setCarriedFlag(teamName, flagTeamName, present)
    local slot = (teamName == "Blue") and blueFlagSlot or redFlagSlot
    if flagTeamName == "Blue" then
        slot.blue.Visible = present
    elseif flagTeamName == "Red" then
        slot.red.Visible = present
    end
end

-- Blue panel contents
local blueName = Instance.new("TextLabel")
blueName.Text = "BLUE"
blueName.Font = Enum.Font.GothamBlack
blueName.TextScaled = true
blueName.TextColor3 = GOLD_TEXT
blueName.BackgroundTransparency = 1
blueName.Size = UDim2.new(1, -16, 0.45, 0)
blueName.Position = UDim2.new(0, 8, 0, 2)
blueName.Parent = bluePanel
local blueNameStroke = Instance.new("UIStroke")
blueNameStroke.Color = Color3.fromRGB(80, 60, 0)
blueNameStroke.Thickness = 1
blueNameStroke.Transparency = 0.3
blueNameStroke.Parent = blueName

local blueCountLabel = Instance.new("TextLabel")
blueCountLabel.Text = tostring(blueScore)
blueCountLabel.Font = Enum.Font.GothamBlack
blueCountLabel.TextScaled = true
blueCountLabel.TextColor3 = BLUE_ACCENT
blueCountLabel.BackgroundTransparency = 1
blueCountLabel.Size = UDim2.new(1, -16, 0.55, -4)
blueCountLabel.Position = UDim2.new(0, 8, 0.45, 2)
blueCountLabel.Parent = bluePanel
local blueCountStroke = Instance.new("UIStroke")
blueCountStroke.Color = Color3.fromRGB(20, 40, 100)
blueCountStroke.Thickness = 1.2
blueCountStroke.Transparency = 0.2
blueCountStroke.Parent = blueCountLabel

-- Red panel contents
local redName = Instance.new("TextLabel")
redName.Text = "RED"
redName.Font = Enum.Font.GothamBlack
redName.TextScaled = true
redName.TextColor3 = GOLD_TEXT
redName.BackgroundTransparency = 1
redName.Size = UDim2.new(1, -16, 0.45, 0)
redName.Position = UDim2.new(0, 8, 0, 2)
redName.Parent = redPanel
local redNameStroke = Instance.new("UIStroke")
redNameStroke.Color = Color3.fromRGB(80, 60, 0)
redNameStroke.Thickness = 1
redNameStroke.Transparency = 0.3
redNameStroke.Parent = redName

local redCountLabel = Instance.new("TextLabel")
redCountLabel.Text = tostring(redScore)
redCountLabel.Font = Enum.Font.GothamBlack
redCountLabel.TextScaled = true
redCountLabel.TextColor3 = RED_ACCENT
redCountLabel.BackgroundTransparency = 1
redCountLabel.Size = UDim2.new(1, -16, 0.55, -4)
redCountLabel.Position = UDim2.new(0, 8, 0.45, 2)
redCountLabel.Parent = redPanel
local redCountStroke = Instance.new("UIStroke")
redCountStroke.Color = Color3.fromRGB(100, 20, 20)
redCountStroke.Thickness = 1.2
redCountStroke.Transparency = 0.2
redCountStroke.Parent = redCountLabel

-- Center timer
local timerLabel = Instance.new("TextLabel")
timerLabel.Text = "20:00"
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextScaled = true
timerLabel.TextColor3 = GOLD_TEXT
timerLabel.BackgroundTransparency = 1
timerLabel.Size = UDim2.new(1, -16, 1, 0)
timerLabel.Position = UDim2.new(0, 8, 0, 0)
timerLabel.Parent = centerPanel
local timerStroke = Instance.new("UIStroke")
timerStroke.Color = Color3.fromRGB(100, 80, 10)
timerStroke.Thickness = 1.2
timerStroke.Transparency = 0.2
timerStroke.Parent = timerLabel

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

-- play the ticking sound from ReplicatedStorage.Sounds.Game.ClockTick
local function playTickSound()
    local sounds = ReplicatedStorage:FindFirstChild("Sounds")
    if not sounds then return end
    local gameFolder = sounds:FindFirstChild("Game")
    if not gameFolder then return end
    local tick = gameFolder:FindFirstChild("ClockTick")
    if not tick or not tick:IsA("Sound") then return end
    local ok, cam = pcall(function() return workspace.CurrentCamera end)
    local parent = (ok and cam) or playerGui
    local snd = tick:Clone()
    snd.Parent = parent
    snd:Play()
    task.delay((snd.TimeLength or 0.6) + 0.2, function()
        if snd and snd.Parent then snd:Destroy() end
    end)
end

-- Timer loop: compute remaining from server start tick to avoid client-side drift
spawn(function()
    while true do
        if running and matchStartTick and matchDuration then
            local now = workspace:GetServerTimeNow()
            local elapsed = now - matchStartTick
            -- use floor (not rounding) so integer decreases happen exactly when a full second elapses
            local newRemaining = math.max(0, math.floor(matchDuration - elapsed))
            -- play tick once when the integer remaining strictly decreases
            if newRemaining > 0 and newRemaining <= 9 then
                if lastIntegerRemaining ~= nil and newRemaining < lastIntegerRemaining then
                    pcall(playTickSound)
                end
            end
            remaining = newRemaining
            lastIntegerRemaining = newRemaining
            if remaining <= 0 then running = false end
            refresh()
        end
        wait(0.05)
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
    ev.OnClientEvent:Connect(function(durationSeconds, startTick)
        if type(durationSeconds) == "number" then
            matchDuration = durationSeconds
        else
            matchDuration = START_TIME_SECONDS
        end
        if type(startTick) == "number" then
            matchStartTick = startTick
        else
            matchStartTick = workspace:GetServerTimeNow()
        end
        -- initialize state
        blueScore = 0
        redScore = 0
        running = true
        lastIntegerRemaining = nil
        lastTickSoundTime = 0

        -- clear all carried-flag HUD indicators
        setCarriedFlag("Blue", "Blue", false)
        setCarriedFlag("Blue", "Red", false)
        setCarriedFlag("Red", "Blue", false)
        setCarriedFlag("Red", "Red", false)

        refresh()
    end)
end

local function wireMatchEnd(ev)
    ev.OnClientEvent:Connect(function(resultType, winner)
        -- stop the local timer so it doesn't keep counting down
        running = false
        if resultType == "sudden" then
            timerLabel.Text = "SUDDEN"
        elseif resultType == "win" then
            timerLabel.Text = "00:00"
        end
    end)
end

-- Connect if events already exist, or wait for them to be created
local scoreEv = ReplicatedStorage:FindFirstChild("ScoreUpdate")
if scoreEv and scoreEv:IsA("RemoteEvent") then wireScoreEvent(scoreEv) end
local matchEv = ReplicatedStorage:FindFirstChild("MatchStart")
if matchEv and matchEv:IsA("RemoteEvent") then wireMatchStart(matchEv) end
local matchEndEv = ReplicatedStorage:FindFirstChild("MatchEnd")
if matchEndEv and matchEndEv:IsA("RemoteEvent") then wireMatchEnd(matchEndEv) end

ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "ScoreUpdate" and child:IsA("RemoteEvent") then
        wireScoreEvent(child)
    elseif child.Name == "MatchStart" and child:IsA("RemoteEvent") then
        wireMatchStart(child)
    elseif child.Name == "MatchEnd" and child:IsA("RemoteEvent") then
        wireMatchEnd(child)
    end
end)

-- initial refresh
refresh()

-- Attempt to resync with server in case we missed the MatchStart event
spawn(function()
    local ok, fn = pcall(function() return ReplicatedStorage:WaitForChild("GetMatchState", 5) end)
    if not ok or not fn then return end
    if not fn:IsA("RemoteFunction") then return end
    local ok2, info = pcall(function() return fn:InvokeServer() end)
    if not ok2 or type(info) ~= "table" then return end
    if info.state == "Game" and type(info.matchStartTick) == "number" and type(info.matchDuration) == "number" then
        matchDuration = info.matchDuration
        matchStartTick = info.matchStartTick
        running = true
        lastIntegerRemaining = nil
        -- also sync scores if provided
        if info.teamScores and type(info.teamScores) == "table" then
            blueScore = info.teamScores.Blue or 0
            redScore = info.teamScores.Red or 0
        end
        refresh()
    end
end)

-- Listen to flag status announcements to update HUD carried-flag squares
if FlagStatus and FlagStatus:IsA("RemoteEvent") then
    FlagStatus.OnClientEvent:Connect(function(eventType, playerName, playerTeamName, flagTeamName)
        if eventType == "pickup" then
            if playerTeamName and flagTeamName then setCarriedFlag(playerTeamName, flagTeamName, true) end
        elseif eventType == "returned" then
            if flagTeamName then
                local other = (flagTeamName == "Blue") and "Red" or "Blue"
                setCarriedFlag(other, flagTeamName, false)
            end
        elseif eventType == "captured" then
            if playerTeamName and flagTeamName then setCarriedFlag(playerTeamName, flagTeamName, false) end
        end
    end)
end
