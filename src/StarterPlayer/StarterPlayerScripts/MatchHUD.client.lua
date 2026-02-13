local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local START_TIME_SECONDS = 1 * 60 -- 20 minutes

-- State
local blueScore = 0
local redScore = 0
local remaining = START_TIME_SECONDS
local running = true
local matchStartTick = nil
local matchDuration = START_TIME_SECONDS
local lastIntegerRemaining = nil

-- Create HUD
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0.01, 0)
root.Size = UDim2.new(0.85, 0, 0.055, 0)
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
            local elapsed = tick() - matchStartTick
            local newRemaining = math.max(0, math.floor(matchDuration - elapsed + 0.5))
            remaining = newRemaining
            -- play tick when hitting the last 10 seconds (10..1)
            if remaining <= 10 and remaining > 0 then
                if lastIntegerRemaining == nil or lastIntegerRemaining ~= remaining then
                    pcall(playTickSound)
                end
            end
            lastIntegerRemaining = remaining
            if remaining <= 0 then running = false end
            refresh()
        end
        wait(0.25)
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
            matchStartTick = tick()
        end
        -- initialize state
        blueScore = 0
        redScore = 0
        running = true
        lastIntegerRemaining = nil

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
    local ok, fn = pcall(function() return ReplicatedStorage:WaitForChild("GetMatchState", 2) end)
    if not ok or not fn or not fn.IsA or not fn:IsA(fn, "RemoteFunction") then
        return
    end
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
