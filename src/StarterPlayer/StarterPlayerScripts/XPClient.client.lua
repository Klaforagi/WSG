-- XPClient.client.lua
-- Polished bottom-screen XP bar with level indicators, popups and level-up banner.
-- Listens to server XP remotes only — never modifies XP locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local XP_Update  = remotes:WaitForChild("XP_Update")
local XP_Popup   = remotes:WaitForChild("XP_Popup")
local XP_LevelUp = remotes:WaitForChild("XP_LevelUp")
-- optional asset codes for coin image
local AssetCodes = nil
pcall(function() AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes", 5)) end)

--------------------------------------------------------------------------------
-- STYLE CONSTANTS
--------------------------------------------------------------------------------
local BAR_WIDTH_SCALE   = 0.34          -- % of screen width (slightly narrower)
local TRACK_HEIGHT      = 16            -- inner XP track height
local LABEL_SIZE        = 22            -- level numbers at each side of the track
local CORNER_RADIUS     = UDim.new(0, 7)
local SHELL_CORNER      = UDim.new(0, 11)

local COLOR_SHELL_BG    = Color3.fromRGB(12, 16, 34)   -- outer HUD shell
local COLOR_BAR_BG      = Color3.fromRGB(22, 28, 52)   -- inset dark track frame
local COLOR_TRACK_BASE  = Color3.fromRGB(9, 12, 24)    -- deepest background behind fill
local COLOR_BAR_STROKE  = Color3.fromRGB(255, 215, 80) -- GOLD stroke
local COLOR_FILL_LEFT   = Color3.fromRGB(54, 144, 255) -- blue XP fill
local COLOR_FILL_RIGHT  = Color3.fromRGB(124, 196, 255)
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
-- compute device-aware bar height (smaller on mobile)
local cam = workspace.CurrentCamera
local vpY = 1080
if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
    vpY = cam.ViewportSize.Y
end
local trackH = UserInputService.TouchEnabled and math.max(11, math.floor(vpY * 0.014)) or TRACK_HEIGHT
local shellH = UserInputService.TouchEnabled and math.max(30, math.floor(vpY * 0.031)) or math.max(36, math.floor(vpY * 0.034))

local container = Instance.new("Frame")
container.Name = "XPContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -2)        -- keep near bottom while opening gap above
container.Size = UDim2.new(BAR_WIDTH_SCALE, LABEL_SIZE * 2 + 24, 0, shellH)
container.BackgroundColor3 = COLOR_SHELL_BG
container.BackgroundTransparency = 0.06
container.BorderSizePixel = 0
container.Parent = screen

local shellCorner = Instance.new("UICorner")
shellCorner.CornerRadius = SHELL_CORNER
shellCorner.Parent = container

local shellStroke = Instance.new("UIStroke")
shellStroke.Color = COLOR_BAR_STROKE
shellStroke.Thickness = 2
shellStroke.Transparency = 0.38
shellStroke.Parent = container

local shellShadow = Instance.new("Frame")
shellShadow.Name = "Shadow"
shellShadow.AnchorPoint = Vector2.new(0.5, 0.5)
shellShadow.Position = UDim2.new(0.5, 0, 0.55, 3)
shellShadow.Size = UDim2.new(1, 10, 1, 10)
shellShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shellShadow.BackgroundTransparency = 0.66
shellShadow.BorderSizePixel = 0
shellShadow.ZIndex = 0
shellShadow.Parent = container
Instance.new("UICorner", shellShadow).CornerRadius = UDim.new(0, 14)

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
levelLabel.TextSize = 14
levelLabel.TextColor3 = COLOR_LABEL
levelLabel.Text = "1"
levelLabel.TextXAlignment = Enum.TextXAlignment.Center
levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
levelLabel.TextStrokeTransparency = 0.45
levelLabel.Parent = container

local nextLabel = Instance.new("TextLabel")
nextLabel.Name = "NextLevelLabel"
nextLabel.Size = UDim2.new(0, LABEL_SIZE, 0, LABEL_SIZE)
nextLabel.Position = UDim2.new(1, 0, 0.5, 0)
nextLabel.AnchorPoint = Vector2.new(1, 0.5)
nextLabel.BackgroundTransparency = 1
nextLabel.Font = Enum.Font.GothamBold
nextLabel.TextSize = 14
nextLabel.TextColor3 = COLOR_LABEL
nextLabel.Text = "2"
nextLabel.TextXAlignment = Enum.TextXAlignment.Center
nextLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
nextLabel.TextStrokeTransparency = 0.45
nextLabel.Parent = container

--------------------------------------------------------------------------------
-- BAR BACKGROUND  (between the two level labels)
--------------------------------------------------------------------------------
local barBG = Instance.new("Frame")
barBG.Name = "BarBG"
barBG.AnchorPoint = Vector2.new(0.5, 0.5)
barBG.Position = UDim2.new(0.5, 0, 0.5, 0)
barBG.Size = UDim2.new(1, -(LABEL_SIZE * 2 + 12), 0, trackH)
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
bgStroke.Transparency = 0.6

local fillInset = Instance.new("Frame")
fillInset.Name = "FillInset"
fillInset.AnchorPoint = Vector2.new(0.5, 0.5)
fillInset.Position = UDim2.new(0.5, 0, 0.5, 0)
fillInset.Size = UDim2.new(1, -4, 1, -4)
fillInset.BackgroundColor3 = COLOR_TRACK_BASE
fillInset.BorderSizePixel = 0
fillInset.ClipsDescendants = true
fillInset.ZIndex = 1
fillInset.Parent = barBG
Instance.new("UICorner", fillInset).CornerRadius = UDim.new(0, 5)

local insetStroke = Instance.new("UIStroke")
insetStroke.Color = Color3.fromRGB(255, 255, 255)
insetStroke.Thickness = 1
insetStroke.Transparency = 0.9
insetStroke.Parent = fillInset

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
fill.Parent = fillInset
fill.ZIndex = 2

local fillCorner = Instance.new("UICorner", fill)
fillCorner.CornerRadius = CORNER_RADIUS

local gradient = Instance.new("UIGradient", fill)
gradient.Color = ColorSequence.new(COLOR_FILL_LEFT, COLOR_FILL_RIGHT)
gradient.Rotation = 90

-- notches removed per user request

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
    local activeFillColor = color:Lerp(Color3.new(0,0,0), 0.12)
    local light = lighterColor(color, 0.27)
    fill.BackgroundColor3 = activeFillColor
    gradient.Color = ColorSequence.new(activeFillColor, light)
    -- keep numeric labels and frame in a consistent XP palette
    levelLabel.TextColor3 = COLOR_LABEL
    nextLabel.TextColor3 = COLOR_LABEL
    bgStroke.Color = COLOR_BAR_STROKE
    COLOR_POPUP = COLOR_LABEL
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
-- XP counter label (hidden by default) shows currentXP / currentXPToNext when hovered or held
local xpCountLabel = Instance.new("TextLabel")
xpCountLabel.Name = "XPCountLabel"
xpCountLabel.AnchorPoint = Vector2.new(0.5, 0.5)
xpCountLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
xpCountLabel.Size = UDim2.new(0.6, 0, 1, 0)
xpCountLabel.BackgroundTransparency = 1
xpCountLabel.Font = Enum.Font.Gotham
xpCountLabel.TextSize = 12
xpCountLabel.TextColor3 = COLOR_LABEL
xpCountLabel.Text = ""
xpCountLabel.TextTransparency = 1
xpCountLabel.ZIndex = 11
xpCountLabel.Parent = barBG
local baseFill = Instance.new("Frame")
baseFill.Name = "BaseFill"
baseFill.AnchorPoint = Vector2.new(0, 0.5)
baseFill.Position = UDim2.new(0, 0, 0.5, 0)
baseFill.Size = UDim2.new(1, 0, 1, 0)
baseFill.BackgroundColor3 = COLOR_TRACK_BASE
baseFill.BackgroundTransparency = 0.15
baseFill.BorderSizePixel = 0
baseFill.ZIndex = 1
baseFill.Parent = fillInset

local baseCorner = Instance.new("UICorner", baseFill)
baseCorner.CornerRadius = CORNER_RADIUS

levelUpLabel.Text = ""
levelUpLabel.TextTransparency = 1
levelUpLabel.ZIndex = 10
levelUpLabel.Parent = barBG

-- Helpers to update and show/hide XP counter
local function updateXPCountText()
    local cx = currentXP
    local mx = currentXPToNext
    -- fallback to player Attributes if server hasn't sent an update yet
    if (not cx or cx == 0) and player:GetAttribute("XP") then
        cx = player:GetAttribute("XP")
    end
    if (not mx or mx == 0) and player:GetAttribute("XPToNext") then
        mx = player:GetAttribute("XPToNext")
    end
    cx = cx or 0
    mx = mx or 0
    xpCountLabel.Text = tostring(cx) .. " / " .. tostring(mx)
end

local function showXPCount()
    updateXPCountText()
    xpCountLabel.TextTransparency = 1
    xpCountLabel.Visible = true
    TweenService:Create(xpCountLabel, TweenInfo.new(0.12), { TextTransparency = 0 }):Play()
end

local function hideXPCount()
    local t = TweenService:Create(xpCountLabel, TweenInfo.new(0.12), { TextTransparency = 1 })
    t:Play()
    t.Completed:Connect(function()
        xpCountLabel.Visible = false
    end)
end

-- Desktop: hover to show; Mobile: press-and-hold
local holdThreshold = 0.22
local touchHolding = false
if not UserInputService.TouchEnabled then
    barBG.MouseEnter:Connect(showXPCount)
    barBG.MouseLeave:Connect(hideXPCount)
else
    barBG.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            touchHolding = true
            task.spawn(function()
                local t = 0
                while touchHolding and t < holdThreshold do
                    task.wait(0.05)
                    t = t + 0.05
                end
                if touchHolding then showXPCount() end
            end)
        end
    end)
    barBG.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            touchHolding = false
            hideXPCount()
        end
    end)
end

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

local function createXPPopup(amount, coinAmount)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0, 140, 0, 28)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    -- random position around lower-mid center
    local r = Random.new()
    local fx = r:NextNumber(0.55, 0.65)
    local fy = r:NextNumber(0.4, 0.7)
    container.Position = UDim2.new(fx, 0, fy, 0)
    container.Parent = screen

    local xpLabel = Instance.new("TextLabel")
    xpLabel.BackgroundTransparency = 1
    xpLabel.Font = Enum.Font.GothamBold
    xpLabel.TextSize = 15
    xpLabel.TextColor3 = COLOR_POPUP
    xpLabel.TextStrokeTransparency = 0.75
    xpLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    xpLabel.AnchorPoint = Vector2.new(0.5, 0)
    xpLabel.Size = UDim2.new(1, 0, 0.5, 0)
    xpLabel.Position = UDim2.new(0.5, 0, 0, 0)
    xpLabel.Text = "+" .. tostring(amount) .. " XP"
    xpLabel.TextTransparency = 0
    xpLabel.Parent = container
    -- thicker outline for XP text to match other UI
    local xpStroke = Instance.new("UIStroke")
    xpStroke.Thickness = 1.2
    xpStroke.Color = Color3.fromRGB(0,0,0)
    xpStroke.Transparency = 0.4
    xpStroke.Parent = xpLabel

    if coinAmount and type(coinAmount) == "number" and coinAmount > 0 then
        local coinRow = Instance.new("Frame")
        coinRow.BackgroundTransparency = 1
        coinRow.Size = UDim2.new(1, 0, 0.5, 0)
        coinRow.Position = UDim2.new(0, 0, 0.5, 0)
        coinRow.Parent = container

        local hl = Instance.new("UIListLayout")
        hl.FillDirection = Enum.FillDirection.Horizontal
        hl.HorizontalAlignment = Enum.HorizontalAlignment.Center
        hl.VerticalAlignment = Enum.VerticalAlignment.Center
        hl.SortOrder = Enum.SortOrder.LayoutOrder
        hl.Padding = UDim.new(0, 6)
        hl.Parent = coinRow

        -- coin text (matches XP style) — placed before the image so it reads "+X Coin(s) [icon]"
        local coinWord = (coinAmount == 1) and "Coin" or "Coins"
        local coinText = Instance.new("TextLabel")
        coinText.BackgroundTransparency = 1
        coinText.Font = Enum.Font.GothamBold
        coinText.TextSize = 14
        coinText.TextColor3 = COLOR_POPUP
        coinText.Text = "+" .. tostring(coinAmount) .. " " .. coinWord
        coinText.AutomaticSize = Enum.AutomaticSize.X
        coinText.TextTransparency = 0
        coinText.LayoutOrder = 1
        coinText.Parent = coinRow
        local coinStroke = Instance.new("UIStroke")
        coinStroke.Thickness = 1.2
        coinStroke.Color = Color3.fromRGB(0,0,0)
        coinStroke.Transparency = 0.4
        coinStroke.Parent = coinText

        -- coin image placed after the text
        local coinImg = nil
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local ok, id = pcall(function() return AssetCodes.Get("Coin") end)
            if ok and type(id) == "string" and #id > 0 then
                coinImg = Instance.new("ImageLabel")
                coinImg.BackgroundTransparency = 1
                coinImg.Size = UDim2.new(0, 18, 0, 18)
                coinImg.Image = id
                coinImg.ScaleType = Enum.ScaleType.Fit
                coinImg.LayoutOrder = 2
                coinImg.Parent = coinRow
            end
        end
        if not coinImg then
            local fallback = Instance.new("TextLabel")
            fallback.BackgroundTransparency = 1
            fallback.Font = Enum.Font.GothamBold
            fallback.TextSize = 14
            fallback.Text = "🪙"
            fallback.AutomaticSize = Enum.AutomaticSize.X
            fallback.LayoutOrder = 2
            fallback.Parent = coinRow
        end
    end

    task.spawn(function()
        -- rise upward
        local riseGoal = { Position = container.Position + UDim2.new(0, 0, -0.04, 0) }
        local t1 = TweenService:Create(container, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), riseGoal)
        t1:Play()
        task.wait(0.8 + 1.5)
        -- fade out every text label and image inside the container
        local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        for _, desc in ipairs(container:GetDescendants()) do
            if desc:IsA("TextLabel") then
                TweenService:Create(desc, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
            elseif desc:IsA("ImageLabel") then
                TweenService:Create(desc, fadeInfo, {ImageTransparency = 1}):Play()
            end
        end
        local t2 = TweenService:Create(container, fadeInfo, {
            BackgroundTransparency = 1,
            Position = container.Position + UDim2.new(0, 0, -0.08, 0),
        })
        t2:Play()
        t2.Completed:Wait()
        pcall(function() container:Destroy() end)
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
    -- refresh visible xp count text if the counter is showing
    updateXPCountText()

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

    -- popup: handled via dedicated XP_Popup remote to avoid duplicate popups
end

local function onPopup(payload)
    if not payload then return end
    if payload.delta and payload.delta > 0 then
        print("[XPClient] Popup received — XP:", payload.delta, "Coin:", payload.coin or 0, "Reason:", payload.reason or "?")
        createXPPopup(payload.delta, payload.coin)
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
