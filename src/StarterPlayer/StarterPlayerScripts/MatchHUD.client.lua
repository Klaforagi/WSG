local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local START_TIME_SECONDS = 1 * 60

-- Polished PvP scoreboard palette
local NAVY         = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT   = Color3.fromRGB(22, 26, 48)
local NAVY_MID     = Color3.fromRGB(18, 20, 40)
local GOLD_TEXT    = Color3.fromRGB(255, 215, 80)
local GOLD_DIM     = Color3.fromRGB(180, 150, 50)
local GOLD_BORDER  = Color3.fromRGB(200, 170, 40)
local BLUE_ACCENT  = Color3.fromRGB(65, 105, 225)
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

--------------------------------------------------------------------------------
-- CREATE SCOREBOARD HUD
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

-- Root positioning frame (transparent, allows center panel to extend beyond)
local root = Instance.new("Frame")
root.Name = "ScoreboardRoot"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0.006, 0)
root.Size = UDim2.new(0.46, 0, 0.072, 0)
root.BackgroundTransparency = 1
root.ClipsDescendants = false
root.Parent = screenGui

local rootConstraint = Instance.new("UISizeConstraint")
rootConstraint.MinSize = Vector2.new(440, 44)
rootConstraint.MaxSize = Vector2.new(math.huge, 82)
rootConstraint.Parent = root

-- Soft drop-shadow behind the entire scoreboard
local barShadow = Instance.new("Frame")
barShadow.Name = "BarShadow"
barShadow.AnchorPoint = Vector2.new(0.5, 0.5)
barShadow.Position = UDim2.new(0.5, 0, 0.55, 2)
barShadow.Size = UDim2.new(1.01, 6, 1, 6)
barShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
barShadow.BackgroundTransparency = 0.72
barShadow.BorderSizePixel = 0
barShadow.ZIndex = 0
barShadow.Parent = root
Instance.new("UICorner", barShadow).CornerRadius = UDim.new(0, 12)

-- Main dark bar (unified backdrop behind all sections)
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
backdrop.Position = UDim2.new(0.5, 0, 0.5, 0)
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = NAVY
backdrop.BackgroundTransparency = 0.06
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = root
Instance.new("UICorner", backdrop).CornerRadius = UDim.new(0, 10)

do -- backdrop stroke + gradient
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(45, 45, 70)
    s.Thickness = 1
    s.Transparency = 0.45
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = backdrop

    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 190)),
    })
    g.Rotation = 90
    g.Parent = backdrop
end

-- Thin highlight along the top edge for a glass feel
do
    local hl = Instance.new("Frame")
    hl.Name = "TopHighlight"
    hl.AnchorPoint = Vector2.new(0.5, 0)
    hl.Position = UDim2.new(0.5, 0, 0, 1)
    hl.Size = UDim2.new(0.96, 0, 0, 1)
    hl.BackgroundColor3 = Color3.fromRGB(100, 100, 140)
    hl.BackgroundTransparency = 0.55
    hl.BorderSizePixel = 0
    hl.ZIndex = 2
    hl.Parent = backdrop
end

--------------------------------------------------------------------------------
-- HELPER: build a team panel
--------------------------------------------------------------------------------
local function makeTeamPanel(name, glowColor, anchorX, posX)
    local panel = Instance.new("Frame")
    panel.Name = name
    panel.AnchorPoint = Vector2.new(anchorX, 0.5)
    panel.Position = UDim2.new(posX, 0, 0.5, 0)
    panel.Size = UDim2.new(0.345, 0, 0.80, 0)
    panel.BackgroundColor3 = NAVY_MID
    panel.BackgroundTransparency = 0.18
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.ZIndex = 2
    panel.Parent = root

    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 7)

    local stroke = Instance.new("UIStroke")
    stroke.Color = glowColor
    stroke.Thickness = 1.6
    stroke.Transparency = 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = panel

    -- subtle depth gradient (top-to-bottom)
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 215, 230)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 180, 205)),
    })
    grad.Rotation = 90
    grad.Parent = panel

    -- top inner-shadow for recessed depth
    local innerShadow = Instance.new("Frame")
    innerShadow.Name = "InnerShadow"
    innerShadow.Size = UDim2.new(1, 0, 0.18, 0)
    innerShadow.Position = UDim2.new(0, 0, 0, 0)
    innerShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    innerShadow.BackgroundTransparency = 0.88
    innerShadow.BorderSizePixel = 0
    innerShadow.ZIndex = 3
    innerShadow.Parent = panel

    return panel
end

--------------------------------------------------------------------------------
-- BLUE PANEL
--------------------------------------------------------------------------------
local bluePanel = makeTeamPanel("BluePanel", BLUE_GLOW, 0, 0.01)

-- Colored accent bar on the inner edge (right side, facing timer)
do
    local bar = Instance.new("Frame")
    bar.Name = "AccentBar"
    bar.AnchorPoint = Vector2.new(1, 0.5)
    bar.Position = UDim2.new(1, 0, 0.5, 0)
    bar.Size = UDim2.new(0, 3, 0.6, 0)
    bar.BackgroundColor3 = BLUE_ACCENT
    bar.BackgroundTransparency = 0.25
    bar.BorderSizePixel = 0
    bar.ZIndex = 3
    bar.Parent = bluePanel
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
end

-- Diamond team badge removed (decorative element)
print("[MatchHUD] Removed blue diamond badge for cleaner scoreboard")

-- Team name label
local blueName = Instance.new("TextLabel")
blueName.Name = "TeamName"
blueName.Text = "BLUE"
blueName.Font = Enum.Font.GothamBlack
blueName.TextScaled = true
blueName.TextColor3 = GOLD_TEXT
blueName.BackgroundTransparency = 1
    blueName.Size = UDim2.new(0.62, 0, 0.34, 0)
    blueName.Position = UDim2.new(0.12, 0, 0.02, 0)
blueName.TextXAlignment = Enum.TextXAlignment.Center
blueName.ZIndex = 3
blueName.Parent = bluePanel
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(60, 45, 0)
    s.Thickness = 1
    s.Transparency = 0.25
    s.Parent = blueName
end

-- Score number (large & prominent)
local blueCountLabel = Instance.new("TextLabel")
blueCountLabel.Name = "ScoreCount"
blueCountLabel.Text = tostring(blueScore)
blueCountLabel.Font = Enum.Font.GothamBlack
blueCountLabel.TextScaled = true
blueCountLabel.TextColor3 = BLUE_ACCENT
blueCountLabel.BackgroundTransparency = 1
blueCountLabel.Size = UDim2.new(0.82, 0, 0.58, 0)
blueCountLabel.Position = UDim2.new(0.09, 0, 0.38, 0)
blueCountLabel.ZIndex = 3
blueCountLabel.Parent = bluePanel
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(15, 30, 80)
    s.Thickness = 1.5
    s.Transparency = 0.15
    s.Parent = blueCountLabel
end

--------------------------------------------------------------------------------
-- RED PANEL
--------------------------------------------------------------------------------
local redPanel = makeTeamPanel("RedPanel", RED_GLOW, 1, 0.99)

-- Colored accent bar on the inner edge (left side, facing timer)
do
    local bar = Instance.new("Frame")
    bar.Name = "AccentBar"
    bar.AnchorPoint = Vector2.new(0, 0.5)
    bar.Position = UDim2.new(0, 0, 0.5, 0)
    bar.Size = UDim2.new(0, 3, 0.6, 0)
    bar.BackgroundColor3 = RED_ACCENT
    bar.BackgroundTransparency = 0.25
    bar.BorderSizePixel = 0
    bar.ZIndex = 3
    bar.Parent = redPanel
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
end

-- Diamond team badge removed (decorative element)
print("[MatchHUD] Removed red diamond badge for cleaner scoreboard")

-- Team name label
local redName = Instance.new("TextLabel")
redName.Name = "TeamName"
redName.Text = "RED"
redName.Font = Enum.Font.GothamBlack
redName.TextScaled = true
redName.TextColor3 = GOLD_TEXT
redName.BackgroundTransparency = 1
    redName.Size = UDim2.new(0.62, 0, 0.34, 0)
    redName.Position = UDim2.new(0.20, 0, 0.02, 0)
redName.TextXAlignment = Enum.TextXAlignment.Center
redName.ZIndex = 3
redName.Parent = redPanel
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(60, 45, 0)
    s.Thickness = 1
    s.Transparency = 0.25
    s.Parent = redName
end

-- Score number (large & prominent)
local redCountLabel = Instance.new("TextLabel")
redCountLabel.Name = "ScoreCount"
redCountLabel.Text = tostring(redScore)
redCountLabel.Font = Enum.Font.GothamBlack
redCountLabel.TextScaled = true
redCountLabel.TextColor3 = RED_ACCENT
redCountLabel.BackgroundTransparency = 1
redCountLabel.Size = UDim2.new(0.82, 0, 0.58, 0)
redCountLabel.Position = UDim2.new(0.09, 0, 0.38, 0)
redCountLabel.ZIndex = 3
redCountLabel.Parent = redPanel
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(80, 15, 15)
    s.Thickness = 1.5
    s.Transparency = 0.15
    s.Parent = redCountLabel
end

--------------------------------------------------------------------------------
-- CENTER TIMER PANEL (focal point — slightly taller than side panels)
--------------------------------------------------------------------------------

-- Subtle gold glow behind center panel
local centerGlow = Instance.new("Frame")
centerGlow.Name = "CenterGlow"
centerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
centerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
centerGlow.Size = UDim2.new(0.24, 0, 1.2, 0)
centerGlow.BackgroundColor3 = GOLD_DIM
centerGlow.BackgroundTransparency = 0.88
centerGlow.BorderSizePixel = 0
centerGlow.ZIndex = 2
centerGlow.Parent = root
Instance.new("UICorner", centerGlow).CornerRadius = UDim.new(0, 10)

local centerPanel = Instance.new("Frame")
centerPanel.Name = "CenterPanel"
centerPanel.AnchorPoint = Vector2.new(0.5, 0.5)
centerPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
centerPanel.Size = UDim2.new(0.22, 0, 1.12, 0)
centerPanel.BackgroundColor3 = NAVY
centerPanel.BackgroundTransparency = 0.02
centerPanel.BorderSizePixel = 0
centerPanel.ZIndex = 3
centerPanel.Parent = root
Instance.new("UICorner", centerPanel).CornerRadius = UDim.new(0, 8)

do -- center panel stroke + gradient
    local s = Instance.new("UIStroke")
    s.Color = GOLD_BORDER
    s.Thickness = 2
    s.Transparency = 0.2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = centerPanel

    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 235, 220)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 190, 175)),
    })
    g.Rotation = 90
    g.Parent = centerPanel
end

-- Timer text (the visual centerpiece)
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerText"
timerLabel.Text = "01:00"
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.TextScaled = true
timerLabel.TextColor3 = GOLD_TEXT
timerLabel.BackgroundTransparency = 1
timerLabel.Size = UDim2.new(0.88, 0, 0.56, 0)
timerLabel.Position = UDim2.new(0.06, 0, 0.04, 0)
timerLabel.ZIndex = 4
timerLabel.Parent = centerPanel
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(120, 95, 10)
    s.Thickness = 1.5
    s.Transparency = 0.15
    s.Parent = timerLabel
end

-- Helpers (must be declared before dev buttons reference them)
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

-- Time adjustment pill-shaped tags (dev/creator testing)
local btnContainer = Instance.new("Frame")
btnContainer.Name = "TimeAdjust"
btnContainer.AnchorPoint = Vector2.new(0.5, 0)
btnContainer.Size = UDim2.new(0.92, 0, 0.30, 0)
btnContainer.Position = UDim2.new(0.5, 0, 0.64, 0)
btnContainer.BackgroundTransparency = 1
btnContainer.ZIndex = 4
btnContainer.Parent = centerPanel

local function makePillBtn(text, anchorX, posX)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.44, 0, 0.88, 0)
    btn.AnchorPoint = Vector2.new(anchorX, 0.5)
    btn.Position = UDim2.new(posX, 0, 0.5, 0)
    btn.Font = Enum.Font.GothamBold
    btn.Text = text
    btn.TextScaled = true
    btn.BackgroundColor3 = NAVY_LIGHT
    btn.BackgroundTransparency = 0.12
    btn.TextColor3 = GOLD_TEXT
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.ZIndex = 5
    btn.Parent = btnContainer

    Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0) -- full pill shape

    local pillStroke = Instance.new("UIStroke")
    pillStroke.Color = GOLD_DIM
    pillStroke.Thickness = 1
    pillStroke.Transparency = 0.5
    pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    pillStroke.Parent = btn

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0.08, 0)
    pad.PaddingRight = UDim.new(0.08, 0)
    pad.Parent = btn

    return btn
end

local minusBtn = makePillBtn("-10s", 0, 0.02)
local plusBtn  = makePillBtn("+10s", 1, 0.98)

--------------------------------------------------------------------------------
-- REMOTE REFERENCES
--------------------------------------------------------------------------------
local FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
local AdjustMatchTime = ReplicatedStorage:WaitForChild("AdjustMatchTime", 10)

minusBtn.MouseButton1Click:Connect(function()
    if AdjustMatchTime then
        AdjustMatchTime:FireServer(-10)
    end
end)
plusBtn.MouseButton1Click:Connect(function()
    if AdjustMatchTime then
        AdjustMatchTime:FireServer(10)
    end
end)

--------------------------------------------------------------------------------
-- FLAG CARRIER INDICATORS (stylized flag icons)
--------------------------------------------------------------------------------

-- buildFlagIcon: creates a stylized flag shape from UI elements inside a container
-- Returns the container Frame (set .Visible to show/hide)
local function buildFlagIcon(parent, flagColor, glowColor)
    local container = Instance.new("Frame")
    container.Name = "FlagIcon"
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.ZIndex = 5
    container.Visible = false
    container.Parent = parent

    -- Pole (vertical bar on the left side of the icon)
    local pole = Instance.new("Frame")
    pole.Name = "Pole"
    pole.AnchorPoint = Vector2.new(0, 0)
    pole.Position = UDim2.new(0.08, 0, 0.05, 0)
    pole.Size = UDim2.new(0.1, 0, 0.9, 0)
    pole.BackgroundColor3 = Color3.fromRGB(180, 175, 160)
    pole.BackgroundTransparency = 0
    pole.BorderSizePixel = 0
    pole.ZIndex = 6
    pole.Parent = container
    Instance.new("UICorner", pole).CornerRadius = UDim.new(0.5, 0)

    -- Pole finial (small circle at the top)
    local finial = Instance.new("Frame")
    finial.Name = "Finial"
    finial.AnchorPoint = Vector2.new(0.5, 1)
    finial.Position = UDim2.new(0.5, 0, 0.08, 0)
    finial.Size = UDim2.new(2.2, 0, 0, 0)
    finial.BackgroundColor3 = GOLD_DIM
    finial.BackgroundTransparency = 0
    finial.BorderSizePixel = 0
    finial.ZIndex = 7
    finial.Parent = pole
    Instance.new("UICorner", finial).CornerRadius = UDim.new(1, 0)
    Instance.new("UIAspectRatioConstraint", finial).AspectRatio = 1

    -- Banner (the flag cloth, attached to the right of the pole)
    local banner = Instance.new("Frame")
    banner.Name = "Banner"
    banner.AnchorPoint = Vector2.new(0, 0)
    banner.Position = UDim2.new(0.18, 0, 0.08, 0)
    banner.Size = UDim2.new(0.72, 0, 0.55, 0)
    banner.BackgroundColor3 = flagColor
    banner.BackgroundTransparency = 0
    banner.BorderSizePixel = 0
    banner.ZIndex = 6
    banner.Parent = container
    Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 3)

    -- Banner glow stroke
    local bannerStroke = Instance.new("UIStroke")
    bannerStroke.Color = glowColor
    bannerStroke.Thickness = 1.2
    bannerStroke.Transparency = 0.25
    bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    bannerStroke.Parent = banner

    -- Banner depth gradient (top lighter, bottom slightly darker)
    local bannerGrad = Instance.new("UIGradient")
    bannerGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 190)),
    })
    bannerGrad.Rotation = 90
    bannerGrad.Parent = banner

    return container
end

-- makeFlagSlot: creates two flag icons for a team panel and positions them responsively
local function makeFlagSlot(panel, alignRight)
    local slot = Instance.new("Frame")
    slot.Name = "FlagSlot"
    slot.Size = UDim2.new(1, 0, 1, 0)
    slot.BackgroundTransparency = 1
    slot.ZIndex = 4
    slot.Parent = panel

    local blueCarried = buildFlagIcon(slot, BLUE_ACCENT, BLUE_GLOW)
    blueCarried.Name = "BlueFlagIcon"
    local redCarried = buildFlagIcon(slot, RED_ACCENT, RED_GLOW)
    redCarried.Name = "RedFlagIcon"

    local function updateSizes()
        local abs = slot.AbsoluteSize
        if abs.X == 0 or abs.Y == 0 then return end
        -- icon is taller than wide (flag shape); height-based sizing
        local iconH = math.clamp(math.floor(abs.Y * 0.72), 14, 52)
        local iconW = math.clamp(math.floor(iconH * 0.8), 12, 44)
        local spacing = math.max(4, math.floor(iconW * 0.2))
        local y = math.floor((abs.Y - iconH) / 2)

        if alignRight then
            local rightPadding = 6
            local rightOffset = -rightPadding - iconW
            local leftOffset = rightOffset - spacing - iconW
            if blueCarried.Visible and redCarried.Visible then
                blueCarried.Position = UDim2.new(1, leftOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            elseif redCarried.Visible then
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
                blueCarried.Position = UDim2.new(1, rightOffset, 0, y)
            elseif blueCarried.Visible then
                blueCarried.Position = UDim2.new(1, rightOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            else
                blueCarried.Position = UDim2.new(1, leftOffset, 0, y)
                redCarried.Position = UDim2.new(1, rightOffset, 0, y)
            end
        else
            local leftPadding = 6
            local leftX = leftPadding
            local rightX = leftX + iconW + spacing
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
        blueCarried.Size = UDim2.new(0, iconW, 0, iconH)
        redCarried.Size = UDim2.new(0, iconW, 0, iconH)
    end

    slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSizes)
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSizes)
    blueCarried:GetPropertyChangedSignal("Visible"):Connect(updateSizes)
    redCarried:GetPropertyChangedSignal("Visible"):Connect(updateSizes)
    spawn(function()
        wait()
        updateSizes()
    end)

    return {slot = slot, blue = blueCarried, red = redCarried}
end

local blueFlagSlot = makeFlagSlot(bluePanel, true)
local redFlagSlot = makeFlagSlot(redPanel, false)

local function setCarriedFlag(teamName, flagTeamName, present)
    local slot = (teamName == "Blue") and blueFlagSlot or redFlagSlot
    if flagTeamName == "Blue" then
        slot.blue.Visible = present
    elseif flagTeamName == "Red" then
        slot.red.Visible = present
    end
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
            -- clamp at 1 while match is running; server decides at 1s whether to go to 0 (winner) or sudden death
            local newRemaining = math.max(1, math.floor(matchDuration - elapsed))
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

-- Listen for server time adjustments (dev buttons) — only updates the tick, no score reset
if AdjustMatchTime and AdjustMatchTime:IsA("RemoteEvent") then
    AdjustMatchTime.OnClientEvent:Connect(function(newStartTick)
        if type(newStartTick) == "number" then
            matchStartTick = newStartTick
        end
    end)
end

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
