-- XPClient.client.lua
-- Polished bottom-screen XP bar with level indicators, popups and level-up banner.
-- Listens to server XP remotes only — never modifies XP locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local XP_Update  = remotes:WaitForChild("XP_Update")
local XP_Popup   = remotes:WaitForChild("XP_Popup")
local XP_LevelUp = remotes:WaitForChild("XP_LevelUp")

--------------------------------------------------------------------------------
-- STYLE CONSTANTS
--------------------------------------------------------------------------------
local BAR_WIDTH_SCALE   = 0.34          -- % of screen width (slightly narrower)
local BAR_HEIGHT        = 14            -- px
local LABEL_SIZE        = 20            -- px – small level numbers
local CORNER_RADIUS     = UDim.new(0, 6) -- subtle rounded corners for a sleek look

local COLOR_BAR_BG      = Color3.fromRGB(12, 14, 28)   -- NAVY base
local COLOR_BAR_STROKE  = Color3.fromRGB(255, 215, 80) -- GOLD stroke
local COLOR_FILL_LEFT   = Color3.fromRGB(255, 215, 80) -- gold -> lighter gold gradient
local COLOR_FILL_RIGHT  = Color3.fromRGB(255, 235, 120)
local COLOR_LABEL       = Color3.fromRGB(255, 215, 80) -- gold labels
local COLOR_POPUP       = Color3.fromRGB(255, 215, 80)
local COLOR_LEVELUP     = Color3.fromRGB(255, 235, 120)

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "XPGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 5
screen.Parent = playerGui

--------------------------------------------------------------------------------
-- CONTAINER  – sits at absolute bottom-center
--------------------------------------------------------------------------------
local container = Instance.new("Frame")
container.Name = "XPContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -4)        -- 4 px from bottom edge
container.Size = UDim2.new(BAR_WIDTH_SCALE, LABEL_SIZE * 2 + 16, 0, LABEL_SIZE)
container.BackgroundTransparency = 1
container.Parent = screen

--------------------------------------------------------------------------------
-- LEVEL LABELS  (outside bar, left = current, right = next)
--------------------------------------------------------------------------------
local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(0, LABEL_SIZE, 0, LABEL_SIZE)
levelLabel.Position = UDim2.new(0, 0, 0.5, 0)
levelLabel.AnchorPoint = Vector2.new(0, 0.5)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextSize = 13
levelLabel.TextColor3 = COLOR_LABEL
levelLabel.Text = "1"
levelLabel.TextXAlignment = Enum.TextXAlignment.Center
levelLabel.Parent = container

local nextLabel = Instance.new("TextLabel")
nextLabel.Name = "NextLevelLabel"
nextLabel.Size = UDim2.new(0, LABEL_SIZE, 0, LABEL_SIZE)
nextLabel.Position = UDim2.new(1, 0, 0.5, 0)
nextLabel.AnchorPoint = Vector2.new(1, 0.5)
nextLabel.BackgroundTransparency = 1
nextLabel.Font = Enum.Font.GothamBold
nextLabel.TextSize = 13
nextLabel.TextColor3 = COLOR_LABEL
nextLabel.Text = "2"
nextLabel.TextXAlignment = Enum.TextXAlignment.Center
nextLabel.Parent = container

--------------------------------------------------------------------------------
-- BAR BACKGROUND  (between the two level labels)
--------------------------------------------------------------------------------
local barBG = Instance.new("Frame")
barBG.Name = "BarBG"
barBG.AnchorPoint = Vector2.new(0.5, 0.5)
barBG.Position = UDim2.new(0.5, 0, 0.5, 0)
barBG.Size = UDim2.new(1, -(LABEL_SIZE * 2 + 12), 0, BAR_HEIGHT)
barBG.BackgroundColor3 = COLOR_BAR_BG
barBG.BorderSizePixel = 0
barBG.ClipsDescendants = true
barBG.Parent = container

local bgCorner = Instance.new("UICorner", barBG)
bgCorner.CornerRadius = CORNER_RADIUS

local bgStroke = Instance.new("UIStroke", barBG)
bgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bgStroke.Thickness = 2
bgStroke.Color = COLOR_BAR_STROKE
bgStroke.Transparency = 0.2

--------------------------------------------------------------------------------
-- FILL BAR  (gradient-filled, pill-shaped)
--------------------------------------------------------------------------------
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.new(0, 0, 0.5, 0)
fill.Size = UDim2.new(0, 0, 1, 0) -- starts empty
fill.BackgroundColor3 = COLOR_FILL_LEFT
fill.BorderSizePixel = 0
fill.Parent = barBG

local fillCorner = Instance.new("UICorner", fill)
fillCorner.CornerRadius = CORNER_RADIUS

local gradient = Instance.new("UIGradient", fill)
gradient.Color = ColorSequence.new(COLOR_FILL_LEFT, COLOR_FILL_RIGHT)
gradient.Rotation = 90

-- segmented notches inside the fill to give the bar depth (only visible where fill exists)
local notchesContainer = Instance.new("Frame")
notchesContainer.Name = "NotchesContainer"
notchesContainer.Size = UDim2.new(1, 0, 1, 0)
notchesContainer.Position = UDim2.new(0, 0, 0, 0)
notchesContainer.BackgroundTransparency = 1
notchesContainer.BorderSizePixel = 0
notchesContainer.Parent = fill

local NOTCH_COUNT = 10
local NOTCH_SPACING = 0.02
for i = 1, NOTCH_COUNT do
    local notch = Instance.new("Frame")
    notch.Name = "Notch" .. tostring(i)
    local x = (i - 1) * (1 / NOTCH_COUNT)
    notch.Position = UDim2.new(x + NOTCH_SPACING * 0.5, 0, 0, 0)
    notch.Size = UDim2.new(1 / NOTCH_COUNT - NOTCH_SPACING, 0, 1, 0)
    notch.BackgroundColor3 = Color3.fromRGB(200, 160, 40)
    notch.BackgroundTransparency = 0.12
    notch.BorderSizePixel = 0
    notch.ZIndex = 2
    notch.Parent = notchesContainer
    local nc = Instance.new("UICorner", notch)
    nc.CornerRadius = UDim.new(0, 3)
end

-- Utility: clamp and lighten a color slightly for gradient
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end
local function lighterColor(c, amt)
    return Color3.new(clamp01(c.R + amt), clamp01(c.G + amt), clamp01(c.B + amt))
end

local function setBarTint(color)
    if not color then color = COLOR_FILL_LEFT end
    -- choose a smaller light amount for strongly red tints so the "light" variant isn't too bright
    local isRed = color.R > color.G and color.R > color.B and color.R > 0.55
    local lightAmt = isRed and 0.06 or 0.12
    local light = lighterColor(color, lightAmt)
    fill.BackgroundColor3 = color
    gradient.Color = ColorSequence.new(color, light)
    levelLabel.TextColor3 = color
    nextLabel.TextColor3 = color
    bgStroke.Color = color
    COLOR_POPUP = color
    -- tint notches (darker variant) and adjust their transparency
    -- by default make notches a bit darker than fill for contrast
    local notchAmt = -0.12
    local notchTrans = 0.12
    -- For red teams, use a slight lighter notch but not too bright
    if isRed then
        notchAmt = 0.06
        notchTrans = 0.08
    end
    local notchColor = lighterColor(color, notchAmt)
    if notchesContainer then
        for _, n in ipairs(notchesContainer:GetChildren()) do
            if n:IsA("Frame") then
                n.BackgroundColor3 = notchColor
                n.BackgroundTransparency = notchTrans
            end
        end
    end
end

-- react when local player's team changes (and set initial tint)
local function teamColorOrNil(team)
    if not team then return nil end
    local name = tostring(team.Name):lower()
    if string.find(name, "neutral") then return nil end
    if team.TeamColor then return team.TeamColor.Color end
    return nil
end

local initial = teamColorOrNil(player.Team)
if initial then
    setBarTint(initial)
else
    setBarTint(COLOR_FILL_LEFT)
end

player:GetPropertyChangedSignal("Team"):Connect(function()
    local tc = teamColorOrNil(player.Team)
    if tc then
        setBarTint(tc)
    else
        setBarTint(COLOR_FILL_LEFT)
    end
end)

--------------------------------------------------------------------------------
-- LEVEL-UP INLINE LABEL  (small text centered on XP bar, no separate overlay)
--------------------------------------------------------------------------------
local levelUpLabel = Instance.new("TextLabel")
levelUpLabel.Name = "LevelUpLabel"
levelUpLabel.AnchorPoint = Vector2.new(0.5, 0.5)
levelUpLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
levelUpLabel.Size = UDim2.new(0.6, 0, 1.6, 0)
levelUpLabel.BackgroundTransparency = 1
levelUpLabel.Font = Enum.Font.GothamBold
levelUpLabel.TextSize = 12
levelUpLabel.TextColor3 = COLOR_LEVELUP
levelUpLabel.TextStrokeTransparency = 0.65
levelUpLabel.TextStrokeColor3 = Color3.fromRGB(80, 60, 0)
levelUpLabel.Text = ""
levelUpLabel.TextTransparency = 1
levelUpLabel.ZIndex = 10
levelUpLabel.Parent = barBG

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function tweenFill(fraction, duration)
    duration = duration or 0.45
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TweenService:Create(fill, info, { Size = UDim2.new(fraction, 0, 1, 0) })
    t:Play()
    return t
end

local function createXPPopup(amount)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 110, 0, 20)
    lbl.AnchorPoint = Vector2.new(0.5, 1)
    -- spawn just above the bar
    lbl.Position = UDim2.new(0.5, 0, 1, -28)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 15
    lbl.TextColor3 = COLOR_POPUP
    lbl.TextStrokeTransparency = 0.75
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.Text = "+" .. tostring(amount) .. " XP"
    lbl.TextTransparency = 0
    lbl.Parent = screen

    task.spawn(function()
        -- rise upward
        local riseGoal = { Position = lbl.Position + UDim2.new(0, 0, -0.04, 0) }
        local t1 = TweenService:Create(lbl, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), riseGoal)
        t1:Play()
        task.wait(0.8 + 0.5)
        -- fade out
        local t2 = TweenService:Create(lbl, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
            Position = lbl.Position + UDim2.new(0, 0, -0.08, 0),
        })
        t2:Play()
        task.wait(0.5)
        pcall(function() lbl:Destroy() end)
    end)
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local currentLevel    = 1
local currentXP       = 0
local currentXPToNext = 100

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------
local function onXPUpdate(payload)
    if not payload then return end

    local newLevel = payload.newLevel or currentLevel
    local xp       = payload.xp or 0
    local xpToNext = payload.xpToNext or 100
    local delta    = payload.delta or 0

    -- cache
    currentXP       = xp
    currentXPToNext = xpToNext

    -- update level labels
    if newLevel ~= currentLevel then
        currentLevel = newLevel
        levelLabel.Text = tostring(currentLevel)
        nextLabel.Text  = tostring(currentLevel + 1)
    end

    -- animate fill
    local fraction = 0
    if xpToNext > 0 then fraction = math.clamp(xp / xpToNext, 0, 1) end
    tweenFill(fraction, 0.45)

    -- popup
    if delta and delta > 0 then
        createXPPopup(delta)
    end
end

local function onPopup(payload)
    if not payload then return end
    if payload.delta and payload.delta > 0 then
        createXPPopup(payload.delta)
    end
end

local function onLevelUp(payload)
    if not payload then return end
    -- only show for the local player
    if payload.playerUserId ~= player.UserId then return end

    -- Immediately update level labels and bar so the player sees the change NOW
    local newLevel = payload.newLevel or (currentLevel + 1)
    currentLevel = newLevel
    levelLabel.Text = tostring(currentLevel)
    nextLabel.Text  = tostring(currentLevel + 1)

    -- Flash fill to full (XP crossed the threshold), then reset to 0.
    -- The subsequent XP_Update will tween to the correct leftover fraction.
    tweenFill(1, 0.2)
    task.delay(0.25, function()
        fill.Size = UDim2.new(0, 0, 1, 0) -- instant reset
    end)

    -- show small "LEVEL UP!" text centered on the XP bar
    levelUpLabel.Text = "LEVEL UP!"
    levelUpLabel.TextTransparency = 0
    levelUpLabel.TextStrokeTransparency = 0.65

    -- fade out after 2 seconds
    task.delay(2, function()
        local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local t = TweenService:Create(levelUpLabel, fadeInfo, {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        })
        t:Play()
    end)
end

--------------------------------------------------------------------------------
-- CONNECT
--------------------------------------------------------------------------------
XP_Update.OnClientEvent:Connect(onXPUpdate)
XP_Popup.OnClientEvent:Connect(onPopup)
XP_LevelUp.OnClientEvent:Connect(onLevelUp)
