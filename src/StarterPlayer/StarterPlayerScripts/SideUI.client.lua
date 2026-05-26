-- SideUI.client.lua
-- Main hub menu UI. Coin display is handled by the CoinDisplay module in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")


local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
print("[SideUI] initializing for", player and player.Name)

-- In Team Test the camera ViewportSize can be (0,0) until the first frame
-- renders. Since 0 is truthy in Lua, the old `or 1080` fallback never fired,
-- causing every px() call to return 1 and making all UI elements invisible.
-- Wait briefly so all sizing uses the real resolution.
do
	local cam = workspace.CurrentCamera
	if not cam then
		cam = workspace:WaitForChild("Camera", 5)
	end
	if cam then
		local t = 0
		while cam.ViewportSize.Y < 2 and t < 3 do
			t = t + task.wait()
		end
	end
end

-- Scale pixel values proportionally to viewport height (reference: 1080p)
local function px(base)
	local cam = workspace.CurrentCamera
	-- Guard: if ViewportSize.Y is 0, fall back to 1080 so UI is correctly
	-- proportioned instead of collapsing to 1px (the Team Test root cause).
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

local function safeClamp(value, minValue, maxValue)
    local minv = tonumber(minValue) or 0
    local maxv = tonumber(maxValue) or minv
    if maxv < minv then
        minv, maxv = maxv, minv
    end
    return math.clamp(value, minv, maxv)
end

local function getViewportSize()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize.X, cam.ViewportSize.Y
    end
    local fallbackCamera = workspace:FindFirstChildWhichIsA("Camera")
    if fallbackCamera and fallbackCamera.ViewportSize.X > 0 and fallbackCamera.ViewportSize.Y > 0 then
        return fallbackCamera.ViewportSize.X, fallbackCamera.ViewportSize.Y
    end
    return 1920, 1080
end

-- Load AssetCodes with WaitForChild so it is available in Team Test where
-- ReplicatedStorage contents may not have replicated when this script starts.
local AssetCodes = nil
do
    local mod = ReplicatedStorage:WaitForChild("AssetCodes", 5)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            AssetCodes = result
        else
            warn("[SideUI] AssetCodes failed to load:", tostring(result))
        end
    else
        warn("[SideUI] AssetCodes not found after 5s – button icons may be missing")
    end
end

local function getShardCurrencyImage()
    if AssetCodes and type(AssetCodes.Get) == "function" then
        local image = AssetCodes.Get("Shards") or AssetCodes.Get("Shard")
        if type(image) == "string" and #image > 0 then
            return image
        end
    end
    return nil
end

local function getKeyCurrencyImage()
    if AssetCodes and type(AssetCodes.Get) == "function" then
        local image = AssetCodes.Get("Key") or AssetCodes.Get("Keys")
        if type(image) == "string" and #image > 0 then
            return image
        end
    end
    return nil
end

local function formatCompactCurrency(value)
    local amount = math.max(0, math.floor(tonumber(value) or 0))
    if amount < 10000 then
        return tostring(amount)
    end

    local suffixes = {
        { value = 1000000000000, suffix = "t" },
        { value = 1000000000, suffix = "b" },
        { value = 1000000, suffix = "m" },
        { value = 1000, suffix = "k" },
    }

    for _, entry in ipairs(suffixes) do
        if amount >= entry.value then
            return tostring(math.floor(amount / entry.value)) .. entry.suffix
        end
    end

    return tostring(amount)
end

-- Config / constants
-- Panel sizing: narrower on desktop (8%), wider on mobile (16%)
local PANEL_WIDTH_SCALE = UserInputService.TouchEnabled and 0.16 or 0.11
local PANEL_WIDTH = UDim2.new(PANEL_WIDTH_SCALE, 0, 0, 0) -- width only; height is AutomaticSize
local PANEL_ANCHOR = Vector2.new(0, 0.5) -- left side, vertically centered
local PANEL_POS = UDim2.new(0, px(8), 0.5, 0) -- left side, centered vertically

-- Device text scale (smaller on desktop)
local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75
local function tpx(base)
    return math.max(1, math.round(px(base) * deviceTextScale))
end

local COLORS = {
    panelBg = Color3.fromRGB(12, 14, 28),
    gold = Color3.fromRGB(255, 215, 80),
    brown = Color3.fromRGB(122, 85, 46),
    white = Color3.fromRGB(245, 245, 245),
    buttonBg = Color3.fromRGB(18, 20, 36),
    badgeBg = Color3.fromRGB(220, 40, 40),
}

-- Team gradient helpers
local function getTeamGradientSequence()
    local ok, base = pcall(function()
        local team = player and player.Team
        if team and team.TeamColor and team.Name ~= "Neutral" then
            if team.Name == "Blue" then
                return Color3.fromRGB(12, 51, 168) -- royal blue (match MatchHUD BLUE_ACCENT)
            elseif team.Name == "Red" then
                return Color3.fromRGB(202, 24, 24) -- match MatchHUD RED_ACCENT
            end
            return team.TeamColor.Color
        end
        return nil
    end)
    if not ok or not base then
        base = Color3.fromRGB(18, 22, 48) -- default: dark navy (match Team menu)
    else
        -- slightly darken team colors (blue/red) for stronger contrast
        base = base:Lerp(Color3.new(0, 0, 0), 0.12)
    end
    local dark = base:Lerp(Color3.fromRGB(4, 4, 6), 0.72)
    local bright = base:Lerp(Color3.new(1, 1, 1), 0.12)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, dark),
        ColorSequenceKeypoint.new(1, bright),
    })
end

local function makeButtonGradient(parent)
    local g = Instance.new("UIGradient")
    g.Rotation = 135
    g.Color = getTeamGradientSequence()
    g.Parent = parent
    -- Each gradient listens for team changes directly (reliable)
    player:GetPropertyChangedSignal("Team"):Connect(function()
        pcall(function()
            g.Color = getTeamGradientSequence()
        end)
    end)
    return g
end

local MENU_DEFS = {
    {
        id = "Shop",
        label = "Shop",
        iconKey = "SideShop",
        fallback = "SHOP",
        accent = Color3.fromRGB(255, 210, 70),
        aliases = { "SHOP" },
    },
    {
        id = "Inventory",
        label = "Inventory",
        iconKey = "SideInventory",
        fallback = "INV",
        accent = Color3.fromRGB(75, 210, 255),
        aliases = { "INVENTORY" },
    },
    {
        id = "Missions",
        label = "Achieves",
        iconKey = "SideAchieves",
        fallback = "ACH",
        accent = Color3.fromRGB(255, 205, 45),
        aliases = { "Achieves", "Achievement", "Achievements", "Quests" },
    },
    {
        id = "Team",
        label = "Team",
        iconKey = "Team",
        fallback = "TEAM",
        accent = Color3.fromRGB(235, 70, 70),
        aliases = { "TEAM" },
    },
}

-- Internal state tables to expose
local buttonsById = {}
local badgesById = {}
-- Local handlers table (defined early so click handlers can safely reference it)
local scriptHandlers = {}

-- Helper tween
local function tweenInstance(inst, props, info)
    info = info or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local suc, t = pcall(function() return TweenService:Create(inst, info, props) end)
    if suc and t then t:Play() end
end

-- UI creation helpers
local function getAssetImage(iconKey)
    if iconKey and AssetCodes and type(AssetCodes.Get) == "function" then
        local ok, id = pcall(function() return AssetCodes.Get(iconKey) end)
        if ok and type(id) == "string" and #id > 0 then
            return id
        end
    end
    return nil
end

local function activateLauncherButton(def)
    if not def then return end

    if def.id == "Shop" then
        if _G and _G.SideUI and type(_G.SideUI.OnShop) == "function" then
            pcall(_G.SideUI.OnShop)
        elseif type(scriptHandlers.OnShop) == "function" then
            pcall(scriptHandlers.OnShop)
        end
        return
    end

    if def.id == "Inventory" then
        if _G and _G.SideUI and type(_G.SideUI.OnInventory) == "function" then
            pcall(_G.SideUI.OnInventory)
        elseif type(scriptHandlers.OnInventory) == "function" then
            pcall(scriptHandlers.OnInventory)
        end
        return
    end

    if _G and _G.SideUI and type(_G.SideUI.OnMenuButton) == "function" then
        pcall(_G.SideUI.OnMenuButton, def.id)
    elseif type(scriptHandlers.OnMenuButton) == "function" then
        pcall(scriptHandlers.OnMenuButton, def.id)
    end
end

local function addCardGradient(parent, accent)
    accent = accent or COLORS.gold
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accent:Lerp(Color3.new(1, 1, 1), 0.18)),
        ColorSequenceKeypoint.new(0.16, Color3.fromRGB(32, 34, 55)),
        ColorSequenceKeypoint.new(0.58, Color3.fromRGB(12, 14, 28)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 6, 14)),
    })
    gradient.Parent = parent
    return gradient
end

local function buildCrossedFlagIcon(parent, zIndex)
    local iconRoot = Instance.new("Frame")
    iconRoot.Name = "TeamCrossedFlagsIcon"
    iconRoot.BackgroundTransparency = 1
    iconRoot.Size = UDim2.new(0.84, 0, 0.66, 0)
    iconRoot.AnchorPoint = Vector2.new(0.5, 0.5)
    iconRoot.Position = UDim2.new(0.5, 0, 0.43, 0)
    iconRoot.ZIndex = zIndex or 254
    iconRoot.Parent = parent

    local function makeFlag(name, angle, direction, poleColor, clothColor, clothShade)
        local flag = Instance.new("Frame")
        flag.Name = name
        flag.BackgroundTransparency = 1
        flag.Size = UDim2.new(0.78, 0, 0.92, 0)
        flag.AnchorPoint = Vector2.new(0.5, 0.5)
        flag.Position = UDim2.new(0.5, 0, 0.54, 0)
        flag.Rotation = angle
        flag.ZIndex = iconRoot.ZIndex
        flag.Parent = iconRoot

        local poleX = direction == 1 and 0.40 or 0.60
        local outward = direction == 1 and -1 or 1

        local pole = Instance.new("Frame")
        pole.Name = "Pole"
        pole.BorderSizePixel = 0
        pole.BackgroundColor3 = poleColor
        pole.Size = UDim2.new(0.09, 0, 0.96, 0)
        pole.AnchorPoint = Vector2.new(0.5, 0)
        pole.Position = UDim2.new(poleX, 0, 0.02, 0)
        pole.ZIndex = iconRoot.ZIndex
        pole.Parent = flag
        local poleCorner = Instance.new("UICorner")
        poleCorner.CornerRadius = UDim.new(1, 0)
        poleCorner.Parent = pole

        local clothMain = Instance.new("Frame")
        clothMain.Name = "ClothMain"
        clothMain.BorderSizePixel = 0
        clothMain.BackgroundColor3 = clothColor
        clothMain.Size = UDim2.new(0.52, 0, 0.32, 0)
        clothMain.AnchorPoint = Vector2.new(outward == 1 and 0 or 1, 0)
        clothMain.Position = UDim2.new(poleX + outward * 0.03, 0, 0.15, 0)
        clothMain.ZIndex = iconRoot.ZIndex + 1
        clothMain.Parent = flag
        local clothMainCorner = Instance.new("UICorner")
        clothMainCorner.CornerRadius = UDim.new(0, px(4))
        clothMainCorner.Parent = clothMain

        local clothTip = Instance.new("Frame")
        clothTip.Name = "ClothTip"
        clothTip.BorderSizePixel = 0
        clothTip.BackgroundColor3 = clothColor
        clothTip.Size = UDim2.new(0.15, 0, 0.15, 0)
        clothTip.AnchorPoint = Vector2.new(0.5, 0.5)
        clothTip.Position = UDim2.new(
            clothMain.Position.X.Scale + outward * clothMain.Size.X.Scale,
            0,
            clothMain.Position.Y.Scale + clothMain.Size.Y.Scale * 0.55,
            0
        )
        clothTip.Rotation = outward == 1 and 45 or -45
        clothTip.ZIndex = iconRoot.ZIndex + 1
        clothTip.Parent = flag

        local clothStripe = Instance.new("Frame")
        clothStripe.Name = "ClothStripe"
        clothStripe.BorderSizePixel = 0
        clothStripe.BackgroundColor3 = clothShade
        clothStripe.Size = UDim2.new(0.22, 0, 0.06, 0)
        clothStripe.AnchorPoint = Vector2.new(outward == 1 and 0 or 1, 0.5)
        clothStripe.Position = UDim2.new(poleX + outward * 0.06, 0, 0.23, 0)
        clothStripe.ZIndex = iconRoot.ZIndex + 2
        clothStripe.Parent = flag

        local clothStroke = Instance.new("UIStroke")
        clothStroke.Color = clothColor:Lerp(Color3.new(1, 1, 1), 0.25)
        clothStroke.Thickness = 1.5
        clothStroke.Transparency = 0.25
        clothStroke.Parent = clothMain
    end

    makeFlag("RedFlag", -40, 1, Color3.fromRGB(172, 132, 88), Color3.fromRGB(212, 38, 45), Color3.fromRGB(255, 116, 124))
    makeFlag("BlueFlag", 40, -1, Color3.fromRGB(150, 118, 82), Color3.fromRGB(56, 120, 220), Color3.fromRGB(122, 188, 255))
end

local function createLauncherButton(def)
    local accent = def.accent or COLORS.gold
    local btn = Instance.new("TextButton")
    btn.Name = (def.id == "Missions" and "Achieves" or def.id) .. "Button"
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.new(1, 1, 1)
    btn.BackgroundTransparency = 0
    btn.BorderSizePixel = 0
    btn.ClipsDescendants = false
    btn.Text = ""
    btn.ZIndex = 252

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(12))
    corner.Parent = btn

    addCardGradient(btn, accent)

    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = px(3)
    stroke.Transparency = 0.02
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Round
    stroke.Parent = btn

    local shine = Instance.new("Frame")
    shine.Name = "TopShine"
    shine.BackgroundColor3 = Color3.new(1, 1, 1)
    shine.BackgroundTransparency = 0.88
    shine.BorderSizePixel = 0
    shine.Size = UDim2.new(1, -px(10), 0.22, 0)
    shine.Position = UDim2.new(0, px(5), 0, px(5))
    shine.ZIndex = 253
    shine.Parent = btn
    local shineCorner = Instance.new("UICorner")
    shineCorner.CornerRadius = UDim.new(0, px(9))
    shineCorner.Parent = shine

    local iconImage = getAssetImage(def.iconKey)
    if iconImage then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.BackgroundTransparency = 1
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.new(0.5, 0, 0.42, 0)
        icon.Size = UDim2.new(0.74, 0, 0.66, 0)
        icon.Image = iconImage
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ZIndex = 254
        icon.Parent = btn
    else
        local fallback = Instance.new("TextLabel")
        fallback.Name = "IconFallback"
        fallback.BackgroundTransparency = 1
        fallback.AnchorPoint = Vector2.new(0.5, 0.5)
        fallback.Position = UDim2.new(0.5, 0, 0.42, 0)
        fallback.Size = UDim2.new(0.84, 0, 0.56, 0)
        fallback.Font = Enum.Font.GothamBlack
        fallback.Text = def.fallback or def.label or def.id
        fallback.TextColor3 = accent
        fallback.TextScaled = true
        fallback.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        fallback.TextStrokeTransparency = 0.1
        fallback.ZIndex = 254
        fallback.Parent = btn
        local fallbackConstraint = Instance.new("UITextSizeConstraint")
        fallbackConstraint.MinTextSize = 18
        fallbackConstraint.MaxTextSize = 34
        fallbackConstraint.Parent = fallback
    end

    local labelShadow = Instance.new("TextLabel")
    labelShadow.Name = "LabelShadow"
    labelShadow.BackgroundTransparency = 1
    labelShadow.AnchorPoint = Vector2.new(0.5, 1)
    labelShadow.Position = UDim2.new(0.5, px(2), 1, px(5))
    labelShadow.Size = UDim2.new(1.2, 0, 0.28, 0)
    labelShadow.Font = Enum.Font.GothamBlack
    labelShadow.Text = def.label or def.id
    labelShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    labelShadow.TextScaled = true
    labelShadow.TextWrapped = false
    labelShadow.TextXAlignment = Enum.TextXAlignment.Center
    labelShadow.TextYAlignment = Enum.TextYAlignment.Center
    labelShadow.ZIndex = 255
    labelShadow.Parent = btn

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 1, px(3))
    nameLabel.Size = UDim2.new(1.2, 0, 0.28, 0)
    nameLabel.Font = Enum.Font.GothamBlack
    nameLabel.Text = def.label or def.id
    nameLabel.TextColor3 = COLORS.white
    nameLabel.TextScaled = true
    nameLabel.TextWrapped = false
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.ZIndex = 256
    nameLabel.Parent = btn

    local labelConstraint = Instance.new("UITextSizeConstraint")
    labelConstraint.MinTextSize = 15
    labelConstraint.MaxTextSize = 28
    labelConstraint.Parent = nameLabel

    local shadowConstraint = Instance.new("UITextSizeConstraint")
    shadowConstraint.MinTextSize = 15
    shadowConstraint.MaxTextSize = 28
    shadowConstraint.Parent = labelShadow

    local badge = Instance.new("TextLabel")
    badge.Name = "Badge"
    badge.AnchorPoint = Vector2.new(0.5, 0.5)
    badge.Position = UDim2.new(1, -px(4), 0, px(3))
    badge.Size = UDim2.new(0, px(34), 0, px(34))
    badge.BackgroundColor3 = COLORS.badgeBg
    badge.BorderSizePixel = 0
    badge.Font = Enum.Font.GothamBlack
    badge.Text = "!"
    badge.TextColor3 = Color3.new(1, 1, 1)
    badge.TextScaled = true
    badge.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    badge.TextStrokeTransparency = 0.15
    badge.Visible = false
    badge.ZIndex = 259
    badge.Parent = btn
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = badge
    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Color3.new(1, 1, 1)
    badgeStroke.Thickness = 1.5
    badgeStroke.Transparency = 0.1
    badgeStroke.Parent = badge
    local badgeConstraint = Instance.new("UITextSizeConstraint")
    badgeConstraint.MinTextSize = 16
    badgeConstraint.MaxTextSize = 30
    badgeConstraint.Parent = badge

    local buttonScale = Instance.new("UIScale")
    buttonScale.Scale = 1
    buttonScale.Parent = btn

    local hovering = false
    btn.MouseEnter:Connect(function()
        hovering = true
        tweenInstance(buttonScale, { Scale = 1.045 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(stroke, { Transparency = 0, Thickness = px(4) }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    btn.MouseLeave:Connect(function()
        hovering = false
        tweenInstance(buttonScale, { Scale = 1 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(stroke, { Transparency = 0.02, Thickness = px(3) }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    btn.MouseButton1Down:Connect(function()
        tweenInstance(buttonScale, { Scale = 0.94 }, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    btn.MouseButton1Up:Connect(function()
        tweenInstance(buttonScale, { Scale = hovering and 1.045 or 1 }, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    btn.Activated:Connect(function()
        tweenInstance(buttonScale, { Scale = 0.96 }, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        task.delay(0.06, function()
            if buttonScale and buttonScale.Parent then
                tweenInstance(buttonScale, { Scale = hovering and 1.045 or 1 }, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
            end
        end)
        activateLauncherButton(def)
    end)

    local function updateTextLimits()
        local h = btn.AbsoluteSize.Y > 0 and btn.AbsoluteSize.Y or px(100)
        local maxLabel = math.max(18, math.floor(h * 0.26))
        local minLabel = math.max(13, math.floor(h * 0.15))
        labelConstraint.MinTextSize = minLabel
        labelConstraint.MaxTextSize = maxLabel
        shadowConstraint.MinTextSize = minLabel
        shadowConstraint.MaxTextSize = maxLabel
        badge.Size = UDim2.new(0, math.max(24, math.floor(h * 0.33)), 0, math.max(24, math.floor(h * 0.33)))
        badgeConstraint.MaxTextSize = math.max(22, math.floor(h * 0.27))
    end
    btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTextLimits)
    task.defer(updateTextLimits)

    return btn, badge
end

local function CreateSideLauncher(screenGui)
    local launcher = Instance.new("Frame")
    launcher.Name = "SideLauncher"
    launcher.BackgroundTransparency = 1
    launcher.BorderSizePixel = 0
    launcher.Size = UDim2.new(1, 0, 1, 0)
    launcher.Position = UDim2.new(0, 0, 0, 0)
    launcher.ClipsDescendants = false
    launcher.ZIndex = 250
    launcher.Parent = screenGui

    local stack = Instance.new("Frame")
    stack.Name = "SideButtonStack"
    stack.AnchorPoint = Vector2.new(0, 0.5)
    stack.BackgroundTransparency = 1
    stack.BorderSizePixel = 0
    stack.ClipsDescendants = false
    stack.ZIndex = 251
    stack.Parent = launcher

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = stack

    for index, def in ipairs(MENU_DEFS) do
        local btn, badge = createLauncherButton(def)
        btn.LayoutOrder = index
        btn.Parent = stack
        buttonsById[def.id] = btn
        badgesById[def.id] = badge
        if type(def.aliases) == "table" then
            for _, alias in ipairs(def.aliases) do
                buttonsById[alias] = btn
                badgesById[alias] = badge
            end
        end
    end

    local toggle = Instance.new("TextButton")
    toggle.Name = "CollapseToggleButton"
    toggle.AnchorPoint = Vector2.new(0, 0.5)
    toggle.AutoButtonColor = false
    toggle.BackgroundTransparency = 1
    toggle.BorderSizePixel = 0
    toggle.Font = Enum.Font.GothamBlack
    toggle.Text = "<"
    toggle.TextColor3 = COLORS.gold
    toggle.TextScaled = true
    toggle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    toggle.TextStrokeTransparency = 0.32
    toggle.ZIndex = 258
    toggle.Parent = launcher
    local toggleConstraint = Instance.new("UITextSizeConstraint")
    toggleConstraint.MinTextSize = 10
    toggleConstraint.MaxTextSize = 22
    toggleConstraint.Parent = toggle
    local toggleScale = Instance.new("UIScale")
    toggleScale.Scale = 1
    toggleScale.Parent = toggle

    local isCollapsed = false
    local isTweening = false
    local layoutMetrics = nil

    local function getLauncherMetrics()
        local viewportX, viewportY = getViewportSize()
        local cardSize = safeClamp(viewportY * (UserInputService.TouchEnabled and 0.105 or 0.102), UserInputService.TouchEnabled and 62 or 78, UserInputService.TouchEnabled and 94 or 118)
        local spacing = safeClamp(cardSize * 0.18, 10, 18)
        local collapsedX = -cardSize - safeClamp(cardSize * 0.28, 18, 32)
        local toggleW = safeClamp(cardSize * 0.30, 28, 36)
        local toggleH = safeClamp(cardSize * 0.34, 28, 36)
        local handleGap = safeClamp(cardSize * 0.018, 1, 3)
        local toggleCenterX = safeClamp(viewportX * 0.003, 5, 7)
        local toggleExpandedX = toggleCenterX - (toggleW * 0.5)
        local stackExpandedX = toggleExpandedX + toggleW + handleGap
        local toggleCollapsedX = toggleExpandedX
        local totalHeight = (cardSize * #MENU_DEFS) + (spacing * math.max(0, #MENU_DEFS - 1))
        return {
            cardSize = math.floor(cardSize + 0.5),
            spacing = math.floor(spacing + 0.5),
            stackExpandedX = math.floor(stackExpandedX + 0.5),
            collapsedX = math.floor(collapsedX + 0.5),
            toggleW = math.floor(toggleW + 0.5),
            toggleH = math.floor(toggleH + 0.5),
            toggleExpandedX = math.floor(toggleExpandedX + 0.5),
            toggleCollapsedX = math.floor(toggleCollapsedX + 0.5),
            totalHeight = math.floor(totalHeight + 0.5),
        }
    end

    local function applyLauncherLayout(animated)
        layoutMetrics = getLauncherMetrics()
        layout.Padding = UDim.new(0, layoutMetrics.spacing)
        stack.Size = UDim2.new(0, layoutMetrics.cardSize, 0, layoutMetrics.totalHeight)
        for _, def in ipairs(MENU_DEFS) do
            local btn = buttonsById[def.id]
            if btn then
                btn.Size = UDim2.new(0, layoutMetrics.cardSize, 0, layoutMetrics.cardSize)
            end
        end

        toggle.Size = UDim2.new(0, layoutMetrics.toggleW, 0, layoutMetrics.toggleH)
    toggleConstraint.MaxTextSize = safeClamp(math.floor(layoutMetrics.toggleH * 0.72), 18, 24)
        local stackPos = UDim2.new(0, isCollapsed and layoutMetrics.collapsedX or layoutMetrics.stackExpandedX, 0.5, 0)
        local togglePos = UDim2.new(0, isCollapsed and layoutMetrics.toggleCollapsedX or layoutMetrics.toggleExpandedX, 0.5, 0)

        if animated then
            tweenInstance(stack, { Position = stackPos }, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
            tweenInstance(toggle, { Position = togglePos }, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        else
            stack.Position = stackPos
            toggle.Position = togglePos
        end
        toggle.Text = isCollapsed and ">" or "<"
    end

    toggle.MouseEnter:Connect(function()
        tweenInstance(toggleScale, { Scale = 1.12 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(toggle, { TextColor3 = COLORS.white, TextStrokeTransparency = 0.12 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    toggle.MouseLeave:Connect(function()
        tweenInstance(toggleScale, { Scale = 1 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(toggle, { TextColor3 = COLORS.gold, TextStrokeTransparency = 0.32 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    toggle.MouseButton1Down:Connect(function()
        tweenInstance(toggleScale, { Scale = 0.94 }, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    toggle.MouseButton1Up:Connect(function()
        tweenInstance(toggleScale, { Scale = 1.02 }, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)
    toggle.Activated:Connect(function()
        if isTweening then return end
        isTweening = true
        isCollapsed = not isCollapsed
        layoutMetrics = getLauncherMetrics()
        toggle.Text = isCollapsed and ">" or "<"
        local stackPos = UDim2.new(0, isCollapsed and layoutMetrics.collapsedX or layoutMetrics.stackExpandedX, 0.5, 0)
        local togglePos = UDim2.new(0, isCollapsed and layoutMetrics.toggleCollapsedX or layoutMetrics.toggleExpandedX, 0.5, 0)
        local tweenInfo = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local ok, stackTween = pcall(function() return TweenService:Create(stack, tweenInfo, { Position = stackPos }) end)
        pcall(function() TweenService:Create(toggle, tweenInfo, { Position = togglePos }):Play() end)
        if ok and stackTween then
            stackTween:Play()
            stackTween.Completed:Connect(function()
                isTweening = false
                applyLauncherLayout(false)
            end)
        else
            stack.Position = stackPos
            toggle.Position = togglePos
            isTweening = false
        end
    end)

    local launcherCameraViewportConn = nil
    local launcherCameraChangedConn = nil
    local function bindCameraViewport()
        if launcherCameraViewportConn then
            pcall(function() launcherCameraViewportConn:Disconnect() end)
            launcherCameraViewportConn = nil
        end
        local cam = workspace.CurrentCamera
        if cam then
            launcherCameraViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                applyLauncherLayout(false)
            end)
        end
    end
    bindCameraViewport()
    launcherCameraChangedConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
    launcher.Destroying:Connect(function()
        if launcherCameraViewportConn then
            pcall(function() launcherCameraViewportConn:Disconnect() end)
            launcherCameraViewportConn = nil
        end
        if launcherCameraChangedConn then
            pcall(function() launcherCameraChangedConn:Disconnect() end)
            launcherCameraChangedConn = nil
        end
    end)
    task.defer(function() applyLauncherLayout(false) end)

    return launcher, stack, toggle
end

-- PREMIUM CRATE / KEY SYSTEM  – KeyDisplay module (mirrors CoinDisplay)
local KeyDisplayModule = nil
do
    local mod = ReplicatedStorage:WaitForChild("KeyDisplay", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            KeyDisplayModule = result
        else
            warn("[SideUI] KeyDisplay failed to load:", tostring(result))
        end
    else
        warn("[SideUI] KeyDisplay not found – key row will be unavailable")
    end
end

-- SALVAGE SYSTEM  – SalvageDisplay module (mirrors KeyDisplay)
local SalvageDisplayModule = nil
do
    local mod = ReplicatedStorage:WaitForChild("SalvageDisplay", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            SalvageDisplayModule = result
        else
            warn("[SideUI] SalvageDisplay failed to load:", tostring(result))
        end
    else
        warn("[SideUI] SalvageDisplay not found – salvage row will be unavailable")
    end
end

local function CreateLegacyLauncherGridUnused(parent)
    local gridContainer = Instance.new("Frame")
    gridContainer.Name = "LegacyLauncherGridUnused"
    gridContainer.LayoutOrder = 3
    gridContainer.Size = UDim2.new(1, 0, 0, 0)
    gridContainer.BackgroundTransparency = 1
    gridContainer.Parent = parent

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, px(54), 0, px(54))
    grid.CellPadding = UDim2.new(0, px(6), 0, px(6))
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 3
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = gridContainer

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, px(2))
    padding.PaddingBottom = UDim.new(0, px(6))
    padding.PaddingLeft = UDim.new(0, 0)
    padding.PaddingRight = UDim.new(0, 0)
    padding.Parent = gridContainer

    local function updateContainerHeight()
        local contentHeight = grid.AbsoluteContentSize.Y
        local paddedHeight = contentHeight + padding.PaddingTop.Offset + padding.PaddingBottom.Offset
        gridContainer.Size = UDim2.new(1, 0, 0, paddedHeight)
    end

    -- Legacy helper kept only as dormant code during the launcher transition.
    local legacyWidthSource = parent:FindFirstChild("LegacyLauncherWidthSource")
    local function updateCellSize()
        local cols = grid.FillDirectionMaxCells or 3
        local cellPad = (grid and grid.CellPadding and grid.CellPadding.X) and grid.CellPadding.X.Offset or 6

        local sourceW = 0
        if legacyWidthSource and legacyWidthSource.AbsoluteSize and legacyWidthSource.AbsoluteSize.X > 0 then
            sourceW = legacyWidthSource.AbsoluteSize.X
        else
            sourceW = gridContainer.AbsoluteSize.X
        end

        if sourceW <= 0 then return end
        local cellW = math.max(20, math.floor((sourceW - (cellPad * (cols - 1))) / cols))
        grid.CellSize = UDim2.new(0, cellW, 0, cellW)
        updateContainerHeight()
    end

    if legacyWidthSource then
        legacyWidthSource:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    end
    gridContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    if gridContainer.Parent then
        gridContainer.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    end
    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateContainerHeight)
    task.defer(updateCellSize)

    return gridContainer
end

local function CreateLegacyLauncherButtonUnused(def)
    local btn = Instance.new("TextButton")
    btn.Name = "Btn_" .. tostring(def.id)
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.new(1, 1, 1) -- white so UIGradient colour shows through
    btn.BackgroundTransparency = 0
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.Text = "" -- we use a separate small label for the name
    btn.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(8))
    corner.Parent = btn

    makeButtonGradient(btn)

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = btn

    local function buildCrossedFlagIcon(parent)
        local iconRoot = Instance.new("Frame")
        iconRoot.Name = "TeamCrossedFlagsIcon"
        iconRoot.BackgroundTransparency = 1
        iconRoot.Size = UDim2.new(0.82, 0, 0.68, 0)
        iconRoot.AnchorPoint = Vector2.new(0.5, 0.5)
        iconRoot.Position = UDim2.new(0.5, 0, 0.40, 0)
        iconRoot.Parent = parent

        local function makeFlag(name, angle, direction, poleColor, clothColor, clothShade)
            local flag = Instance.new("Frame")
            flag.Name = name
            flag.BackgroundTransparency = 1
            flag.Size = UDim2.new(0.78, 0, 0.92, 0)
            flag.AnchorPoint = Vector2.new(0.5, 0.5)
            flag.Position = UDim2.new(0.5, 0, 0.54, 0)
            flag.Rotation = angle
            flag.Parent = iconRoot

            local poleX = direction == 1 and 0.40 or 0.60
            local outward = direction == 1 and -1 or 1

            local pole = Instance.new("Frame")
            pole.Name = "Pole"
            pole.BorderSizePixel = 0
            pole.BackgroundColor3 = poleColor
            pole.Size = UDim2.new(0.09, 0, 0.96, 0)
            pole.AnchorPoint = Vector2.new(0.5, 0)
            pole.Position = UDim2.new(poleX, 0, 0.02, 0)
            pole.Parent = flag

            local poleCorner = Instance.new("UICorner")
            poleCorner.CornerRadius = UDim.new(1, 0)
            poleCorner.Parent = pole

            local finial = Instance.new("Frame")
            finial.Name = "Finial"
            finial.BorderSizePixel = 0
            finial.BackgroundColor3 = poleColor:Lerp(Color3.new(1, 1, 1), 0.18)
            finial.Size = UDim2.new(0, px(5), 0, px(5))
            finial.AnchorPoint = Vector2.new(0.5, 0.5)
            finial.Position = UDim2.new(poleX, 0, 0.02, 0)
            finial.Parent = flag

            local finialCorner = Instance.new("UICorner")
            finialCorner.CornerRadius = UDim.new(1, 0)
            finialCorner.Parent = finial

            local clothMain = Instance.new("Frame")
            clothMain.Name = "ClothMain"
            clothMain.BorderSizePixel = 0
            clothMain.BackgroundColor3 = clothColor
            clothMain.Size = UDim2.new(0.48, 0, 0.30, 0)
            clothMain.AnchorPoint = Vector2.new(outward == 1 and 0 or 1, 0)
            clothMain.Position = UDim2.new(poleX + outward * 0.03, 0, 0.15, 0)
            clothMain.Parent = flag

            local clothMainCorner = Instance.new("UICorner")
            clothMainCorner.CornerRadius = UDim.new(0, px(3))
            clothMainCorner.Parent = clothMain

            local clothTip = Instance.new("Frame")
            clothTip.Name = "ClothTip"
            clothTip.BorderSizePixel = 0
            clothTip.BackgroundColor3 = clothColor
            clothTip.Size = UDim2.new(0.14, 0, 0.14, 0)
            clothTip.AnchorPoint = Vector2.new(0.5, 0.5)
            clothTip.Position = UDim2.new(
                clothMain.Position.X.Scale + outward * clothMain.Size.X.Scale,
                0,
                clothMain.Position.Y.Scale + clothMain.Size.Y.Scale * 0.55,
                0
            )
            clothTip.Rotation = outward == 1 and 45 or -45
            clothTip.Parent = flag

            local clothStripe = Instance.new("Frame")
            clothStripe.Name = "ClothStripe"
            clothStripe.BorderSizePixel = 0
            clothStripe.BackgroundColor3 = clothShade
            clothStripe.Size = UDim2.new(0.20, 0, 0.06, 0)
            clothStripe.AnchorPoint = Vector2.new(outward == 1 and 0 or 1, 0.5)
            clothStripe.Position = UDim2.new(poleX + outward * 0.06, 0, 0.23, 0)
            clothStripe.Parent = flag

            local clothStroke = Instance.new("UIStroke")
            clothStroke.Color = clothColor:Lerp(Color3.new(1, 1, 1), 0.2)
            clothStroke.Thickness = 1
            clothStroke.Transparency = 0.35
            clothStroke.Parent = clothMain

            return flag
        end

        makeFlag(
            "RedFlag",
            -40,
            1,
            Color3.fromRGB(172, 132, 88),
            Color3.fromRGB(196, 44, 50),
            Color3.fromRGB(235, 118, 124)
        )

        makeFlag(
            "BlueFlag",
            40,
            -1,
            Color3.fromRGB(150, 118, 82),
            Color3.fromRGB(56, 100, 188),
            Color3.fromRGB(122, 166, 240)
        )
    end

    -- Background image (fills the button)
    local iconImage = getAssetImage(def.iconKey)
    if iconImage then
        local bgImg = Instance.new("ImageLabel")
        bgImg.Name = "BgIcon"
        bgImg.BackgroundTransparency = 1
        bgImg.Size = UDim2.new(0.7, 0, 0.6, 0)
        bgImg.AnchorPoint = Vector2.new(0.5, 0.4)
        bgImg.Position = UDim2.new(0.5, 0, 0.38, 0)
        bgImg.Image = iconImage
        bgImg.ScaleType = Enum.ScaleType.Fit
        bgImg.Parent = btn
    end

    -- Small text label at the bottom of the button
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 1, def.id == "Team" and -px(2) or -px(3))
    nameLabel.Size = UDim2.new(0.95, 0, 0, def.id == "Team" and px(12) or px(11))
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = def.label or def.id
    nameLabel.TextColor3 = COLORS.gold
    nameLabel.TextSize = tpx(def.id == "Team" and 28 or 24)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = btn
    local nameStroke = Instance.new("UIStroke")
    nameStroke.Color = Color3.fromRGB(0, 0, 0)
    nameStroke.Thickness = 0.6
    nameStroke.Transparency = 0.3
    nameStroke.Parent = nameLabel

    -- badge (hidden by default)
    local badge = Instance.new("TextLabel")
    badge.Name = "Badge"
    badge.Size = UDim2.new(0, px(16), 0, px(16))
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -px(2), 0, -px(2))
    badge.BackgroundColor3 = COLORS.badgeBg
    badge.Text = "!"
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = tpx(24)
    badge.TextColor3 = Color3.new(1, 1, 1)
    badge.Visible = false
    badge.Parent = btn
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = badge

    -- hover & click feedback (more pronounced: background + stroke tweak)
    btn.MouseEnter:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.12)) end
        -- brighten label text on hover
        pcall(function()
            tweenInstance(nameLabel, {TextColor3 = Color3.new(1,1,1)}, TweenInfo.new(0.12))
        end)
    end)
    btn.MouseLeave:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        pcall(function()
            tweenInstance(nameLabel, {TextColor3 = COLORS.gold}, TweenInfo.new(0.12))
        end)
    end)
    btn.Activated:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.04))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.04)) end
        task.delay(0.06, function()
            tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12))
            if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        end)
        if _G and _G.SideUI and type(_G.SideUI.OnMenuButton) == "function" then
            pcall(_G.SideUI.OnMenuButton, def.id)
        elseif type(scriptHandlers.OnMenuButton) == "function" then
            pcall(scriptHandlers.OnMenuButton, def.id)
        else
            print("Menu button clicked:", def.id)
        end
    end)

    return btn, badge
end

-- Create a compact, top-right utility button for opening Options.
-- DailyRewardsClient positions its button immediately to the left of this slot.
local function getHudUtilityButtonMetrics()
    local viewportX, viewportY = getViewportSize()
    local shortSide = math.min(viewportX, viewportY)
    local buttonSize = UserInputService.TouchEnabled
        and safeClamp(shortSide * 0.07, 50, 72)
        or safeClamp(shortSide * 0.045, 42, 58)
    local insetX = safeClamp(buttonSize * 0.28, 12, 18)
    local insetY = safeClamp(buttonSize * 0.24, 10, 16)

    return {
        buttonSize = math.floor(buttonSize + 0.5),
        insetX = math.floor(insetX + 0.5),
        insetY = math.floor(insetY + 0.5),
    }
end

local function CreateHudOptionsButton(onActivated)
    local existingHudGui = playerGui:FindFirstChild("OptionsHudGui")
    if existingHudGui then
        existingHudGui:Destroy()
    end

    local hudGui = Instance.new("ScreenGui")
    hudGui.Name = "OptionsHudGui"
    hudGui.ResetOnSpawn = false
    hudGui.IgnoreGuiInset = true
    hudGui.DisplayOrder = 1000
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = playerGui

    local container = Instance.new("Frame")
    container.Name = "HudControls"
    container.AnchorPoint = Vector2.new(1, 0)
    container.BackgroundTransparency = 1
    container.Parent = hudGui

    local button = Instance.new("ImageButton")
    button.Name = "OptionsButton"
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.fromScale(0.5, 0.5)
    button.Size = UDim2.fromScale(1, 1)
    button.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    button.BackgroundTransparency = 0.3
    button.AutoButtonColor = false
    button.Active = true
    button.BorderSizePixel = 0
    button.Image = ""
    button.ZIndex = 505
    button.Parent = container

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, px(9))
    buttonCorner.Parent = button

    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = Color3.fromRGB(255, 255, 255)
    buttonStroke.Thickness = 1
    buttonStroke.Transparency = 0.84
    buttonStroke.Parent = button

    local buttonScale = Instance.new("UIScale")
    buttonScale.Parent = button

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.fromScale(0.5, 0.5)
    icon.Size = UDim2.fromScale(0.58, 0.58)
    icon.BackgroundTransparency = 1
    icon.Image = (AssetCodes and type(AssetCodes.Get) == "function" and AssetCodes.Get("Options")) or ""
    icon.ImageColor3 = Color3.fromRGB(242, 245, 250)
    icon.ScaleType = Enum.ScaleType.Fit
    icon.ZIndex = 506
    icon.Parent = button

    local iconFallback = Instance.new("TextLabel")
    iconFallback.Name = "Fallback"
    iconFallback.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFallback.Position = UDim2.fromScale(0.5, 0.5)
    iconFallback.Size = UDim2.fromScale(0.72, 0.72)
    iconFallback.BackgroundTransparency = 1
    iconFallback.Font = Enum.Font.GothamBold
    iconFallback.Text = "SET"
    iconFallback.TextScaled = true
    iconFallback.TextColor3 = Color3.fromRGB(242, 245, 250)
    iconFallback.ZIndex = 507
    iconFallback.Visible = false
    iconFallback.Parent = button

    local fallbackConstraint = Instance.new("UITextSizeConstraint")
    fallbackConstraint.MinTextSize = 8
    fallbackConstraint.MaxTextSize = 16
    fallbackConstraint.Parent = iconFallback

    local idleBgTransparency = 0.3
    local hoverBgTransparency = 0.18
    local pressedBgTransparency = 0.08
    local idleIconColor = Color3.fromRGB(232, 236, 244)
    local activeIconColor = Color3.fromRGB(255, 255, 255)
    local isHovering = false

    local function tweenButtonVisuals(backgroundTransparency, imageColor, scaleValue)
        tweenInstance(button, { BackgroundTransparency = backgroundTransparency }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(icon, { ImageColor3 = imageColor }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        tweenInstance(buttonScale, { Scale = scaleValue }, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end

    local function updateLayout()
        local metrics = getHudUtilityButtonMetrics()
        local buttonSize = metrics.buttonSize

        container.Size = UDim2.new(0, buttonSize, 0, buttonSize)
        container.Position = UDim2.new(1, -metrics.insetX, 0, metrics.insetY)
        buttonCorner.CornerRadius = UDim.new(0, math.max(8, math.floor(buttonSize * 0.24)))
        fallbackConstraint.MaxTextSize = math.max(12, math.floor(buttonSize * 0.35))
    end

    local cameraViewportConn
    local cameraChangedConn

    local function bindViewportListener()
        if cameraViewportConn then
            cameraViewportConn:Disconnect()
            cameraViewportConn = nil
        end

        local camera = workspace.CurrentCamera
        if camera then
            cameraViewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
        end
    end

    cameraChangedConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        bindViewportListener()
        task.defer(updateLayout)
    end)

    button.MouseEnter:Connect(function()
        isHovering = true
        tweenButtonVisuals(hoverBgTransparency, activeIconColor, 1)
    end)

    button.MouseLeave:Connect(function()
        isHovering = false
        tweenButtonVisuals(idleBgTransparency, idleIconColor, 1)
    end)

    button.MouseButton1Down:Connect(function()
        tweenButtonVisuals(pressedBgTransparency, activeIconColor, 0.94)
    end)

    button.MouseButton1Up:Connect(function()
        if isHovering then
            tweenButtonVisuals(hoverBgTransparency, activeIconColor, 1)
        else
            tweenButtonVisuals(idleBgTransparency, idleIconColor, 1)
        end
    end)

    button.Activated:Connect(function()
        if type(onActivated) == "function" then
            onActivated()
        end
    end)

    hudGui.Destroying:Connect(function()
        if cameraViewportConn then
            cameraViewportConn:Disconnect()
            cameraViewportConn = nil
        end
        if cameraChangedConn then
            cameraChangedConn:Disconnect()
            cameraChangedConn = nil
        end
    end)

    bindViewportListener()
    iconFallback.Visible = (icon.Image == nil or icon.Image == "")
    tweenButtonVisuals(idleBgTransparency, idleIconColor, 1)
    task.defer(updateLayout)

    return hudGui, button
end

-- Build UI (create ScreenGui if script not already parented to one)
local screenGui = nil
if script.Parent and script.Parent:IsA("ScreenGui") then
    screenGui = script.Parent
else
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MainUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui
    -- move the script into this ScreenGui so that script.Parent references remain intuitive
    pcall(function() script.Parent = screenGui end)
end
pcall(function() screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
-- Ensure shop ScreenGui renders above other UI (hotbar, HUD). Adjust as needed.
pcall(function() screenGui.DisplayOrder = 250 end)
print("[SideUI] screenGui ready; parent =", tostring(screenGui.Parent))

for _, existingName in ipairs({ "SideLauncher", "MainUICard" }) do
    local existing = screenGui:FindFirstChild(existingName)
    if existing then
        existing:Destroy()
    end
end

local panel, sideButtonStack, collapseToggleButton = CreateSideLauncher(screenGui)
local shopBtn = buttonsById.Shop
local invBtn = buttonsById.Inventory
print("[SideUI] side launcher created; shopBtn =", tostring(shopBtn), "invBtn =", tostring(invBtn))

-- Simple client-side inventory API
local Inventory = {}
do
    local items = {}
    local equipped = { Melee = nil, Ranged = nil, Special = nil }
    function Inventory:AddItem(id)
        if not id then return end
        for _, v in ipairs(items) do if v == id then return end end
        table.insert(items, id)
    end
    function Inventory:HasItem(id)
        for _, v in ipairs(items) do if v == id then return true end end
        return false
    end
    function Inventory:GetItems()
        return table.clone(items)
    end
    function Inventory:SetEquipped(category, id)
        if type(category) ~= "string" then return end
        local k = tostring(category):gsub("%s+", "")
        if not equipped[k] then equipped[k] = nil end
        equipped[k] = id
    end
    function Inventory:GetEquipped(category)
        if type(category) ~= "string" then return nil end
        local k = tostring(category):gsub("%s+", "")
        return equipped[k]
    end
end

-- Starter weapons are granted as instances with IDs by the server (CrateServiceInit),
-- so no need to preload plain items here.

-- Fetch saved loadout from server so inventory shows the correct equipped state
do
    local savedMelee = "Starter Sword"
    local savedRanged = "Starter Slingshot"
    pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local rf = rs:WaitForChild("GetLoadout", 5)
        if rf and rf:IsA("RemoteFunction") then
            local data = rf:InvokeServer()
            if type(data) == "table" then
                if type(data.melee) == "string" and #data.melee > 0 then
                    savedMelee = data.melee
                end
                if type(data.ranged) == "string" and #data.ranged > 0 then
                    savedRanged = data.ranged
                end
            end
        end
    end)
    pcall(function() Inventory:SetEquipped("Melee", savedMelee) end)
    pcall(function() Inventory:SetEquipped("Ranged", savedRanged) end)
end
-- Create centered modal window (hidden by default)
local modalOverlay = Instance.new("Frame")
modalOverlay.Name = "ModalOverlay"
modalOverlay.Size = UDim2.new(1,0,1,0)
modalOverlay.Position = UDim2.new(0,0,0,0)
modalOverlay.BackgroundTransparency = 0.5
modalOverlay.BackgroundColor3 = Color3.fromRGB(10,10,10)
modalOverlay.Visible = false
modalOverlay.Parent = screenGui

-- ── Modal window ──────────────────────────────────────────────────────────
local window = Instance.new("Frame")
window.Name = "ModalWindow"
window.Size = UDim2.new(0.65, 0, 0.72, 0)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.new(0.5, 0, 0.5, 0)
-- Deep navy background matching Team menu
window.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
window.BackgroundTransparency = 0.04
window.Parent = modalOverlay
window.ZIndex = 260
local winCorner = Instance.new("UICorner")
winCorner.CornerRadius = UDim.new(0, px(14))
winCorner.Parent = window
local winStroke = Instance.new("UIStroke")
winStroke.Color = Color3.fromRGB(180, 150, 50)
winStroke.Thickness = 1.5
winStroke.Transparency = 0.15
winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
winStroke.Parent = window
-- Subtle vertical gradient matching Team menu panel
local winGradient = Instance.new("UIGradient")
winGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
})
winGradient.Rotation = 90
winGradient.Parent = window
local winPad = Instance.new("UIPadding")
winPad.PaddingTop = UDim.new(0, px(10))
winPad.PaddingBottom = UDim.new(0, px(10))
winPad.PaddingLeft = UDim.new(0, px(14))
winPad.PaddingRight = UDim.new(0, px(14))
winPad.Parent = window

-- ── Header bar (title + coin display + close X) ──────────────────────────
local HEADER_H = 0.10 -- fraction of window height
local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, HEADER_H, 0)
headerBar.BackgroundTransparency = 1
headerBar.ZIndex = 10
headerBar.Parent = window
headerBar.ZIndex = 270

-- Title pill (matches Team menu title bar)
local titlePill = Instance.new("Frame")
titlePill.Name = "TitlePill"
titlePill.Size = UDim2.new(0.30, 0, 0.80, 0)
titlePill.AnchorPoint = Vector2.new(0.5, 0.5)
titlePill.Position = UDim2.new(0.5, 0, 0.5, 0)
titlePill.BackgroundColor3 = Color3.fromRGB(22, 26, 48)
titlePill.ZIndex = 10
titlePill.Parent = headerBar
local titlePillCorner = Instance.new("UICorner")
titlePillCorner.CornerRadius = UDim.new(0, px(8))
titlePillCorner.Parent = titlePill
local titlePillStroke = Instance.new("UIStroke")
titlePillStroke.Color = Color3.fromRGB(180, 150, 50)
titlePillStroke.Thickness = 1.5
titlePillStroke.Transparency = 0.25
titlePillStroke.Parent = titlePill

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
titleLabel.Text = "SHOP"
titleLabel.ZIndex = 11
titleLabel.Parent = titlePill
titleLabel.ZIndex = 275

-- Right-side currency row (Coins + Keys + Salvage)
    local currencyRow = Instance.new("Frame")
    currencyRow.Name = "CurrencyRow"
    currencyRow.BackgroundTransparency = 1
    currencyRow.Size = UDim2.new(0.52, 0, 0, px(34))
    currencyRow.AnchorPoint = Vector2.new(1, 0.5)
    currencyRow.Position = UDim2.new(0.935, 0, 0.5, 0)
    currencyRow.ZIndex = 275
    currencyRow.Parent = headerBar

    local currencyLayout = Instance.new("UIListLayout")
    currencyLayout.FillDirection = Enum.FillDirection.Horizontal
    currencyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    currencyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    currencyLayout.Padding = UDim.new(0, px(8))
    currencyLayout.Parent = currencyRow

    local function styleCurrencyChip(frame, accentColor, width)
        frame.Size = UDim2.new(0, px(width), 0, px(31))
        frame.BackgroundColor3 = Color3.fromRGB(17, 20, 34)
        frame.BackgroundTransparency = 0.04
        frame.BorderSizePixel = 0

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(9))
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = accentColor
        stroke.Thickness = 1.1
        stroke.Transparency = 0.38
        stroke.Parent = frame

        local gradient = Instance.new("UIGradient")
        gradient.Rotation = 90
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 28, 46)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 13, 24)),
        })
        gradient.Parent = frame
    end

    local function addHeaderTextConstraint(label, maxSize)
        label.TextScaled = true
        local constraint = Instance.new("UITextSizeConstraint")
        constraint.MinTextSize = 9
        constraint.MaxTextSize = math.max(10, math.floor(px(maxSize)))
        constraint.Parent = label
        return constraint
    end

    -- Coin display (right side, LayoutOrder 1 = appears first from the left)
    local headerCoinFrame = Instance.new("Frame")
    headerCoinFrame.Name = "HeaderCoin"
    headerCoinFrame.ZIndex = 275
    headerCoinFrame.LayoutOrder = 1
    headerCoinFrame.Parent = currencyRow
    styleCurrencyChip(headerCoinFrame, Color3.fromRGB(255, 215, 80), 96)

    local headerCoinIcon = Instance.new("ImageLabel")
    headerCoinIcon.Name = "CoinIcon"
    headerCoinIcon.Size = UDim2.new(0, px(22), 0, px(22))
    headerCoinIcon.Position = UDim2.new(0, px(9), 0.5, 0)
    headerCoinIcon.AnchorPoint = Vector2.new(0, 0.5)
    headerCoinIcon.BackgroundTransparency = 1
    headerCoinIcon.ScaleType = Enum.ScaleType.Fit
    headerCoinIcon.ZIndex = 277
    headerCoinIcon.Parent = headerCoinFrame
    pcall(function()
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local ci = AssetCodes.Get("Coin")
            if ci and #ci > 0 then headerCoinIcon.Image = ci end
        end
    end)

    local headerCoinLabel = Instance.new("TextLabel")
    headerCoinLabel.Name = "CoinLabel"
    headerCoinLabel.Size = UDim2.new(1, -px(40), 1, -px(4))
    headerCoinLabel.Position = UDim2.new(0, px(34), 0, px(2))
    headerCoinLabel.BackgroundTransparency = 1
    headerCoinLabel.Font = Enum.Font.GothamBold
    headerCoinLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
    headerCoinLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerCoinLabel.Text = "0"
    headerCoinLabel.ZIndex = 277
    headerCoinLabel.Parent = headerCoinFrame
    local headerCoinLabelConstraint = addHeaderTextConstraint(headerCoinLabel, 15)

    -- Keys display (right side, LayoutOrder 2 = appears after coins)
    local headerKeyFrame = Instance.new("Frame")
    headerKeyFrame.Name = "HeaderKey"
    headerKeyFrame.ZIndex = 275
    headerKeyFrame.LayoutOrder = 2
    headerKeyFrame.Parent = currencyRow
    styleCurrencyChip(headerKeyFrame, Color3.fromRGB(170, 100, 255), 72)

    local headerKeyIcon = nil
    local headerKeyIconConstraint = nil
    local keyImage = getKeyCurrencyImage()
    if keyImage then
        headerKeyIcon = Instance.new("ImageLabel")
        headerKeyIcon.Name = "KeyIcon"
        headerKeyIcon.Size = UDim2.new(0, px(22), 0, px(22))
        headerKeyIcon.Position = UDim2.new(0, px(8), 0.5, 0)
        headerKeyIcon.AnchorPoint = Vector2.new(0, 0.5)
        headerKeyIcon.BackgroundTransparency = 1
        headerKeyIcon.Image = keyImage
        headerKeyIcon.ScaleType = Enum.ScaleType.Fit
        headerKeyIcon.ZIndex = 277
        headerKeyIcon.Parent = headerKeyFrame
    else
        headerKeyIcon = Instance.new("TextLabel")
        headerKeyIcon.Name = "KeyIcon"
        headerKeyIcon.Size = UDim2.new(0, px(22), 0, px(22))
        headerKeyIcon.Position = UDim2.new(0, px(8), 0.5, 0)
        headerKeyIcon.AnchorPoint = Vector2.new(0, 0.5)
        headerKeyIcon.BackgroundTransparency = 1
        headerKeyIcon.Font = Enum.Font.GothamBold
        headerKeyIcon.Text = "\u{1F511}"
        headerKeyIcon.TextColor3 = Color3.fromRGB(170, 100, 255)
        headerKeyIcon.ZIndex = 277
        headerKeyIcon.Parent = headerKeyFrame
        headerKeyIconConstraint = addHeaderTextConstraint(headerKeyIcon, 18)
    end

    local headerKeyLabel = Instance.new("TextLabel")
    headerKeyLabel.Name = "KeyLabel"
    headerKeyLabel.Size = UDim2.new(1, -px(36), 1, -px(4))
    headerKeyLabel.Position = UDim2.new(0, px(33), 0, px(2))
    headerKeyLabel.BackgroundTransparency = 1
    headerKeyLabel.Font = Enum.Font.GothamBold
    headerKeyLabel.TextColor3 = Color3.fromRGB(170, 100, 255)
    headerKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerKeyLabel.Text = "0"
    headerKeyLabel.ZIndex = 277
    headerKeyLabel.Parent = headerKeyFrame
    local headerKeyLabelConstraint = addHeaderTextConstraint(headerKeyLabel, 15)

    -- Salvage display (header currency row, LayoutOrder 3 = after keys)
    local SHARD_ACCENT = Color3.fromRGB(255, 158, 74)

    local headerSalvageFrame = Instance.new("Frame")
    headerSalvageFrame.Name = "HeaderSalvage"
    headerSalvageFrame.ZIndex = 275
    headerSalvageFrame.LayoutOrder = 3
    headerSalvageFrame.Parent = currencyRow
    styleCurrencyChip(headerSalvageFrame, SHARD_ACCENT, 98)
    headerSalvageFrame.BackgroundColor3 = Color3.fromRGB(57, 33, 12)
    local headerSalvageGradient = headerSalvageFrame:FindFirstChildOfClass("UIGradient")
    if headerSalvageGradient then
        headerSalvageGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(82, 48, 18)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(31, 18, 8)),
        })
    end

    local shardImage = getShardCurrencyImage()
    local headerSalvageIcon = nil
    local headerSalvageIconConstraint = nil
    if shardImage then
        headerSalvageIcon = Instance.new("ImageLabel")
        headerSalvageIcon.Name = "SalvageIcon"
        headerSalvageIcon.Size = UDim2.new(0, px(22), 0, px(22))
        headerSalvageIcon.Position = UDim2.new(0, px(8), 0.5, 0)
        headerSalvageIcon.AnchorPoint = Vector2.new(0, 0.5)
        headerSalvageIcon.BackgroundTransparency = 1
        headerSalvageIcon.Image = shardImage
        headerSalvageIcon.ScaleType = Enum.ScaleType.Fit
        headerSalvageIcon.ZIndex = 277
        headerSalvageIcon.Parent = headerSalvageFrame
    else
        headerSalvageIcon = Instance.new("TextLabel")
        headerSalvageIcon.Name = "SalvageIcon"
        headerSalvageIcon.Size = UDim2.new(0, px(22), 0, px(22))
        headerSalvageIcon.Position = UDim2.new(0, px(8), 0.5, 0)
        headerSalvageIcon.AnchorPoint = Vector2.new(0, 0.5)
        headerSalvageIcon.BackgroundTransparency = 1
        headerSalvageIcon.Font = Enum.Font.GothamBold
        headerSalvageIcon.Text = "\u{25C6}"
        headerSalvageIcon.TextColor3 = SHARD_ACCENT
        headerSalvageIcon.ZIndex = 277
        headerSalvageIcon.Parent = headerSalvageFrame
        headerSalvageIconConstraint = addHeaderTextConstraint(headerSalvageIcon, 18)
    end

    local headerSalvageLabel = Instance.new("TextLabel")
    headerSalvageLabel.Name = "SalvageLabel"
    headerSalvageLabel.Size = UDim2.new(1, -px(36), 1, -px(4))
    headerSalvageLabel.Position = UDim2.new(0, px(33), 0, px(2))
    headerSalvageLabel.BackgroundTransparency = 1
    headerSalvageLabel.Font = Enum.Font.GothamBold
    headerSalvageLabel.TextColor3 = SHARD_ACCENT
    headerSalvageLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerSalvageLabel.Text = "0"
    headerSalvageLabel.ZIndex = 277
    headerSalvageLabel.Parent = headerSalvageFrame
    local headerSalvageLabelConstraint = addHeaderTextConstraint(headerSalvageLabel, 15)

-- Close X (top-right corner of window) — dark + gold style
local CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
local CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)
local CLOSE_PRESS   = Color3.fromRGB(18, 20, 32)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextScaled = true
closeBtn.Size = UDim2.new(0.05, 0, HEADER_H * 0.85, 0)
closeBtn.SizeConstraint = Enum.SizeConstraint.RelativeYY
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.BackgroundColor3 = CLOSE_DEFAULT
closeBtn.TextColor3 = COLORS.gold
closeBtn.AutoButtonColor = false
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 300
closeBtn.Parent = window

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, px(8))
closeBtnCorner.Parent = closeBtn

local closeBtnStroke = Instance.new("UIStroke")
closeBtnStroke.Color = COLORS.gold
closeBtnStroke.Thickness = 1.2
closeBtnStroke.Transparency = 0.4
closeBtnStroke.Parent = closeBtn

local contentFrame, modalStatusOverlay, prewarmContainer

local function updateHeaderCurrencyLayout()
    local windowWidth = window.AbsoluteSize.X
    local headerHeight = headerBar.AbsoluteSize.Y
    if windowWidth <= 0 or headerHeight <= 0 then return end

    local chipHeight = math.max(22, math.floor(headerHeight * 0.62))
    local chipGap = math.max(4, math.floor(chipHeight * 0.22))
    local iconSize = math.max(14, math.floor(chipHeight * 0.7))
    local iconInset = math.max(4, math.floor(chipHeight * 0.24))
    local labelInset = iconInset + iconSize + math.max(4, math.floor(chipHeight * 0.18))
    local labelTop = math.max(1, math.floor(chipHeight * 0.08))
    local labelHeightInset = math.max(2, math.floor(chipHeight * 0.12))
    local closeInset = closeBtn.AbsoluteSize.X > 0 and closeBtn.AbsoluteSize.X or math.floor(headerHeight * 0.85)
    local rightInset = closeInset + math.max(10, math.floor(headerHeight * 0.24))

    local maxRowWidth = math.max(162, math.floor(windowWidth * 0.255))
    local chipWidth = math.max(50, math.floor((maxRowWidth - (chipGap * 2)) / 3))
    local totalWidth = (chipWidth * 3) + (chipGap * 2)

    currencyRow.Size = UDim2.new(0, totalWidth, 0, chipHeight)
    currencyRow.Position = UDim2.new(1, -rightInset, 0.5, 0)
    currencyLayout.Padding = UDim.new(0, chipGap)

    local titleHeight = math.max(28, math.floor(headerHeight * 0.8))
    local leftInset = math.max(12, math.floor(headerHeight * 0.28))
    local rightReserved = rightInset + totalWidth + math.max(8, math.floor(headerHeight * 0.24))
    local titleWidth = math.max(96, math.min(math.floor(windowWidth * 0.34), windowWidth - rightReserved - leftInset))
    local titleCenter = math.max(leftInset + math.floor(titleWidth * 0.5), math.min(math.floor(windowWidth * 0.5), windowWidth - rightReserved - math.floor(titleWidth * 0.5)))

    titlePill.Size = UDim2.new(0, titleWidth, 0, titleHeight)
    titlePill.Position = UDim2.new(0, titleCenter, 0.5, 0)

    local function sizeChip(frame, width)
        frame.Size = UDim2.new(0, width, 0, chipHeight)
    end

    sizeChip(headerCoinFrame, chipWidth)
    sizeChip(headerKeyFrame, chipWidth)
    sizeChip(headerSalvageFrame, chipWidth)

    local function positionIcon(icon, scale)
        if not icon then return end
        local actualScale = scale or 1
        local actualIconSize = math.max(14, math.floor(iconSize * actualScale))
        icon.Size = UDim2.new(0, actualIconSize, 0, actualIconSize)
        icon.Position = UDim2.new(0, iconInset, 0.5, 0)
    end

    local function positionLabel(label)
        if not label then return end
        label.Size = UDim2.new(1, -(labelInset + iconInset), 1, -labelHeightInset)
        label.Position = UDim2.new(0, labelInset, 0, labelTop)
    end

    positionIcon(headerCoinIcon)
    positionIcon(headerKeyIcon)
    positionIcon(headerSalvageIcon, 1.25)
    positionLabel(headerCoinLabel)
    positionLabel(headerKeyLabel)
    positionLabel(headerSalvageLabel)

    local maxLabelSize = math.max(11, math.floor(chipHeight * 0.5))
    if headerCoinLabelConstraint then headerCoinLabelConstraint.MaxTextSize = maxLabelSize end
    if headerKeyLabelConstraint then headerKeyLabelConstraint.MaxTextSize = maxLabelSize end
    if headerSalvageLabelConstraint then headerSalvageLabelConstraint.MaxTextSize = maxLabelSize end
    if headerKeyIconConstraint then headerKeyIconConstraint.MaxTextSize = math.max(12, math.floor(chipHeight * 0.62)) end
    if headerSalvageIconConstraint then headerSalvageIconConstraint.MaxTextSize = math.max(12, math.floor(chipHeight * 0.62)) end
end

local function updateModalWindowLayout()
    local viewportX, viewportY = getViewportSize()
    if viewportX <= 0 or viewportY <= 0 then return end

    local widthTarget = math.floor(viewportX * (viewportX < viewportY and 0.82 or 0.65))
    local widthMin = math.min(math.floor(viewportX * 0.92), 540)
    local widthMax = math.floor(viewportX * 0.86)

    local lowerBound = math.max(320, widthMin)
    local upperBound = math.max(widthMax, lowerBound)
    local windowWidth = safeClamp(widthTarget, lowerBound, upperBound)

    local heightTarget = math.floor(viewportY * 0.72)
    local heightLimit = viewportX < viewportY and math.floor(windowWidth * 1.1) or math.floor(viewportY * 0.8)
    local desiredHeight = math.min(heightTarget, heightLimit)
    local minHeight = math.max(220, math.floor(viewportY * 0.46))
    local maxHeight = math.max(math.floor(viewportY * 0.84), minHeight)
    local windowHeight = safeClamp(desiredHeight, minHeight, maxHeight)
    local headerHeight = safeClamp(math.floor(windowHeight * 0.1), 44, 76)
    local contentTop = headerHeight + math.max(6, math.floor(windowHeight * 0.015))
    local closeSize = math.max(36, math.floor(headerHeight * 0.84))

    window.Size = UDim2.new(0, windowWidth, 0, windowHeight)
    headerBar.Size = UDim2.new(1, 0, 0, headerHeight)
    closeBtn.SizeConstraint = Enum.SizeConstraint.RelativeXY
    closeBtn.Size = UDim2.new(0, closeSize, 0, closeSize)

    if contentFrame then
        contentFrame.Position = UDim2.new(0, 0, 0, contentTop)
        contentFrame.Size = UDim2.new(1, 0, 1, -contentTop)
    end
    if modalStatusOverlay and contentFrame then
        modalStatusOverlay.Position = contentFrame.Position
        modalStatusOverlay.Size = contentFrame.Size
    end
    if prewarmContainer and contentFrame then
        prewarmContainer.Position = contentFrame.Position
        prewarmContainer.Size = contentFrame.Size
    end

    updateHeaderCurrencyLayout()
end

task.defer(updateModalWindowLayout)
window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHeaderCurrencyLayout)
headerBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHeaderCurrencyLayout)
modalOverlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateModalWindowLayout)
do
    local cameraViewportConn = nil
    local function bindModalCamera()
        if cameraViewportConn then
            pcall(function() cameraViewportConn:Disconnect() end)
            cameraViewportConn = nil
        end
        local camera = workspace.CurrentCamera
        if camera then
            cameraViewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateModalWindowLayout)
        end
    end
    bindModalCamera()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        bindModalCamera()
        updateModalWindowLayout()
    end)
end

-- Hover / press feedback
local closeFeedbackInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeBtn, closeFeedbackInfo, {BackgroundColor3 = CLOSE_HOVER}):Play()
    TweenService:Create(closeBtn, closeFeedbackInfo, {TextColor3 = Color3.new(1, 1, 1)}):Play()
end)
closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeBtn, closeFeedbackInfo, {BackgroundColor3 = CLOSE_DEFAULT}):Play()
    TweenService:Create(closeBtn, closeFeedbackInfo, {TextColor3 = COLORS.gold}):Play()
end)
closeBtn.MouseButton1Down:Connect(function()
    TweenService:Create(closeBtn, closeFeedbackInfo, {BackgroundColor3 = CLOSE_PRESS}):Play()
end)
closeBtn.MouseButton1Up:Connect(function()
    TweenService:Create(closeBtn, closeFeedbackInfo, {BackgroundColor3 = CLOSE_HOVER}):Play()
end)

-- ── Content area (below header) ───────────────────────────────────────────
contentFrame = Instance.new("ScrollingFrame")
contentFrame.Name = "ModalContent"
contentFrame.BackgroundTransparency = 1
contentFrame.Size = UDim2.new(1, 0, 1 - HEADER_H - 0.02, 0)
contentFrame.Position = UDim2.new(0, 0, HEADER_H + 0.01, 0)
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.ScrollBarThickness = px(4)
contentFrame.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
contentFrame.BorderSizePixel = 0
contentFrame.ZIndex = 1
contentFrame.Parent = window

local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, px(8))
contentLayout.Parent = contentFrame

-- add top padding so first row of cards is not clipped by fixed header
local contentPadding = Instance.new("UIPadding")
contentPadding.PaddingTop = UDim.new(0, px(14))
contentPadding.PaddingLeft = UDim.new(0, px(10))
contentPadding.PaddingRight = UDim.new(0, px(10))
contentPadding.Parent = contentFrame

-- ensure content sits above other UI but behind header elements
contentFrame.ZIndex = 260

modalStatusOverlay = Instance.new("Frame")
modalStatusOverlay.Name = "ModalStatusOverlay"
modalStatusOverlay.BackgroundTransparency = 1
modalStatusOverlay.Size = contentFrame.Size
modalStatusOverlay.Position = contentFrame.Position
modalStatusOverlay.Visible = false
modalStatusOverlay.ZIndex = 285
modalStatusOverlay.Parent = window

updateModalWindowLayout()

local modalStatusCard = Instance.new("Frame")
modalStatusCard.Name = "StatusCard"
modalStatusCard.BackgroundColor3 = Color3.fromRGB(17, 20, 34)
modalStatusCard.BackgroundTransparency = 0.04
modalStatusCard.Size = UDim2.new(0, px(310), 0, px(96))
modalStatusCard.AnchorPoint = Vector2.new(0.5, 0.5)
modalStatusCard.Position = UDim2.new(0.5, 0, 0.45, 0)
modalStatusCard.BorderSizePixel = 0
modalStatusCard.ZIndex = 286
modalStatusCard.Parent = modalStatusOverlay
Instance.new("UICorner", modalStatusCard).CornerRadius = UDim.new(0, px(10))

local modalStatusStroke = Instance.new("UIStroke")
modalStatusStroke.Color = COLORS.gold
modalStatusStroke.Thickness = 1.2
modalStatusStroke.Transparency = 0.35
modalStatusStroke.Parent = modalStatusCard

local modalStatusTitle = Instance.new("TextLabel")
modalStatusTitle.Name = "StatusTitle"
modalStatusTitle.BackgroundTransparency = 1
modalStatusTitle.Font = Enum.Font.GothamBold
modalStatusTitle.TextColor3 = COLORS.gold
modalStatusTitle.TextSize = math.max(15, math.floor(px(17)))
modalStatusTitle.TextXAlignment = Enum.TextXAlignment.Center
modalStatusTitle.Size = UDim2.new(1, -px(28), 0, px(28))
modalStatusTitle.Position = UDim2.new(0, px(14), 0, px(18))
modalStatusTitle.ZIndex = 287
modalStatusTitle.Parent = modalStatusCard

local modalStatusDetail = Instance.new("TextLabel")
modalStatusDetail.Name = "StatusDetail"
modalStatusDetail.BackgroundTransparency = 1
modalStatusDetail.Font = Enum.Font.GothamMedium
modalStatusDetail.TextColor3 = Color3.fromRGB(190, 195, 215)
modalStatusDetail.TextSize = math.max(12, math.floor(px(13)))
modalStatusDetail.TextWrapped = true
modalStatusDetail.TextXAlignment = Enum.TextXAlignment.Center
modalStatusDetail.Size = UDim2.new(1, -px(32), 0, px(34))
modalStatusDetail.Position = UDim2.new(0, px(16), 0, px(48))
modalStatusDetail.ZIndex = 287
modalStatusDetail.Parent = modalStatusCard

local function setModalStatus(title, detail, accentColor)
    local accent = accentColor or COLORS.gold
    modalStatusTitle.Text = title or "Loading..."
    modalStatusTitle.TextColor3 = accent
    modalStatusDetail.Text = detail or ""
    modalStatusStroke.Color = accent
    modalStatusOverlay.Visible = true
end

local function hideModalStatus()
    modalStatusOverlay.Visible = false
end

-- Forward-declare coinApi so closures below can reference it
local coinApi = nil
-- PREMIUM CRATE / KEY SYSTEM  – forward-declare keyApi
local keyApi = nil
local activePreloadedMenuName = nil

local function ensurePrewarmContainer()
    if prewarmContainer and prewarmContainer.Parent then
        return prewarmContainer
    end

    prewarmContainer = Instance.new("Frame")
    prewarmContainer.Name = "MenuPrewarmContainer"
    prewarmContainer.BackgroundTransparency = 1
    prewarmContainer.Size = contentFrame and contentFrame.Size or UDim2.new(1, 0, 1, 0)
    prewarmContainer.Position = contentFrame and contentFrame.Position or UDim2.new(0, 0, 0, 0)
    prewarmContainer.Visible = false
    prewarmContainer.ZIndex = 259
    prewarmContainer.ClipsDescendants = true
    prewarmContainer.Parent = window
    updateModalWindowLayout()
    return prewarmContainer
end

local function detachPreloadedHost(host)
    if not host or not host:GetAttribute("MenuPreloadedHost") then
        return false
    end
    host.Visible = false
    host.Parent = ensurePrewarmContainer()
    return true
end

local function clearContent()
    for _, c in ipairs(contentFrame:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
            if not detachPreloadedHost(c) then
                pcall(function() c:Destroy() end)
            end
        end
    end
    activePreloadedMenuName = nil
    -- Clean up AP display (parented to headerBar, outside contentFrame)
    local apDisp = headerBar:FindFirstChild("APDisplay")
    if apDisp then apDisp:Destroy() end
end

local function createContentHost(parentOverride, menuName)
    -- Fill the visible content area so child menus that read parent.AbsoluteSize.Y
    -- (e.g. InventoryUI's adaptive root height) get a non-zero height.
    local host = Instance.new("Frame")
    host.Name = menuName and (menuName .. "ContentHost") or "ModalContentHost"
    host.BackgroundTransparency = 1
    host.Size = UDim2.new(1, 0, 1, 0)
    host.LayoutOrder = 1
    host.ZIndex = 260
    if menuName then
        host:SetAttribute("MenuPreloadedHost", menuName)
    end
    host.Parent = parentOverride or contentFrame

    local hostLayout = Instance.new("UIListLayout")
    hostLayout.SortOrder = Enum.SortOrder.LayoutOrder
    hostLayout.Padding = UDim.new(0, px(8))
    hostLayout.Parent = host

    return host
end

local currentModule = nil
local modalBuildToken = 0
local isAnimating = false
local TWEEN_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function clearAndHide()
    modalBuildToken += 1
    currentModule = nil
    modalOverlay.Visible = false
    hideModalStatus()
    clearContent()
end

local function tweenWindowIn(done)
    if isAnimating then return end
    isAnimating = true
    modalOverlay.Visible = true
    -- start above the viewport and tween to center
    window.Position = UDim2.new(0.5, 0, -0.35, 0)
    local suc, t = pcall(function() return TweenService:Create(window, TWEEN_IN_INFO, {Position = UDim2.new(0.5, 0, 0.5, 0)}) end)
    if suc and t then
        t:Play()
        t.Completed:Connect(function()
            isAnimating = false
            if type(done) == "function" then pcall(done) end
        end)
    else
        -- fallback: immediate
        window.Position = UDim2.new(0.5, 0, 0.5, 0)
        isAnimating = false
        if type(done) == "function" then pcall(done) end
    end
end

local function tweenWindowOut(done)
    if isAnimating then return end
    isAnimating = true
    -- tween window up offscreen, then hide overlay and clear
    local suc, t = pcall(function() return TweenService:Create(window, TWEEN_OUT_INFO, {Position = UDim2.new(0.5, 0, -0.35, 0)}) end)
    if suc and t then
        t:Play()
        t.Completed:Connect(function()
            clearAndHide()
            isAnimating = false
            if type(done) == "function" then pcall(done) end
        end)
    else
        -- fallback: immediate
        clearAndHide()
        isAnimating = false
        if type(done) == "function" then pcall(done) end
    end
end

local MenuController = nil
local MenuPreloader = nil
local DEBUG_MENU_PRELOAD = false
local salvageApi = nil

closeBtn.Activated:Connect(function()
    if MenuController then
        MenuController.CloseAllMenus()
    elseif modalOverlay.Visible then
        tweenWindowOut()
    end
end)

-- WaitForChild for the folder AND its children: in Team Test the folder may
-- replicate before its child ModuleScripts are available.
local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI", 10)
local shopModule = sideUIFolder and sideUIFolder:WaitForChild("ShopUI", 5)
local invModule = sideUIFolder and sideUIFolder:WaitForChild("InventoryUI", 5)
local optionsModule = sideUIFolder and sideUIFolder:WaitForChild("OptionsUI", 5)
local questsModule = sideUIFolder and sideUIFolder:WaitForChild("DailyQuestsUI", 5)
local boostsModule = sideUIFolder and sideUIFolder:WaitForChild("BoostsUI", 5)
local crateOpeningModule = sideUIFolder and sideUIFolder:WaitForChild("CrateOpeningUI", 5)
if not sideUIFolder then
    warn("[SideUI] SideUI folder not found in ReplicatedStorage – modals unavailable")
end

-- MenuController: centralized menu management (shared by all menus including Team)
do
    local mcMod = sideUIFolder and sideUIFolder:WaitForChild("MenuController", 5)
    if mcMod and mcMod:IsA("ModuleScript") then
        local ok, result = pcall(require, mcMod)
        if ok then
            MenuController = result
            print("[SideUI] MenuController loaded")
        else
            warn("[SideUI] MenuController failed to load:", tostring(result))
        end
    else
        warn("[SideUI] MenuController not found – falling back to standalone menu logic")
    end
end

do
    local preloaderMod = sideUIFolder and sideUIFolder:WaitForChild("MenuPreloader", 5)
    if preloaderMod and preloaderMod:IsA("ModuleScript") then
        local ok, result = pcall(require, preloaderMod)
        if ok then
            MenuPreloader = result
            if MenuPreloader and MenuPreloader.SetDebug then
                MenuPreloader.SetDebug(DEBUG_MENU_PRELOAD)
            end
        else
            warn("[SideUI] MenuPreloader failed to load:", tostring(result))
        end
    else
        warn("[SideUI] MenuPreloader not found – menu warmup disabled")
    end
end

local function updateHeaderCoins()
    local coins = 0
    -- Try coinApi first (tracks live value without rendering a launcher coin row)
    if coinApi and coinApi.GetCoins then
        local ok, val = pcall(function() return coinApi.GetCoins() end)
        if ok and type(val) == "number" then coins = val end
    end
    if coins > 0 then
        headerCoinLabel.Text = formatCompactCurrency(coins)
    else
        -- Defer server call to avoid yielding during menu transitions
        headerCoinLabel.Text = formatCompactCurrency(0)
        task.spawn(function()
            pcall(function()
                local getCoinsFn = ReplicatedStorage:FindFirstChild("GetCoins")
                if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
                    local res = getCoinsFn:InvokeServer()
                    if type(res) == "number" then
                        if coinApi and coinApi.SetCoins then
                            coinApi.SetCoins(res)
                        else
                            headerCoinLabel.Text = formatCompactCurrency(res)
                        end
                    end
                end
            end)
        end)
    end
end
-- Expose so ShopUI can trigger a refresh after purchase
_G.UpdateShopHeaderCoins = updateHeaderCoins

local function updateHeaderKeys()
    local keys = 0
    if coinApi and coinApi.GetKeys then
        local ok, val = pcall(function() return coinApi.GetKeys() end)
        if ok and type(val) == "number" then keys = val end
    end
    if keys > 0 then
        headerKeyLabel.Text = formatCompactCurrency(keys)
    else
        headerKeyLabel.Text = formatCompactCurrency(0)
        task.spawn(function()
            pcall(function()
                local getKeysFn = ReplicatedStorage:FindFirstChild("GetKeys")
                if getKeysFn and getKeysFn:IsA("RemoteFunction") then
                    local res = getKeysFn:InvokeServer()
                    if type(res) == "number" then
                        headerKeyLabel.Text = formatCompactCurrency(res)
                    end
                end
            end)
        end)
    end
end
_G.UpdateShopHeaderKeys = updateHeaderKeys

local function updateHeaderSalvage()
    local salvage = 0
    if salvageApi and salvageApi.GetSalvage then
        local ok, val = pcall(function() return salvageApi.GetSalvage() end)
        if ok and type(val) == "number" then salvage = val end
    end
    if salvage > 0 then
        headerSalvageLabel.Text = formatCompactCurrency(salvage)
    else
        headerSalvageLabel.Text = formatCompactCurrency(0)
        task.spawn(function()
            pcall(function()
                local getSalvageFn = ReplicatedStorage:FindFirstChild("GetSalvage")
                if getSalvageFn and getSalvageFn:IsA("RemoteFunction") then
                    local res = getSalvageFn:InvokeServer()
                    if type(res) == "number" then
                        headerSalvageLabel.Text = formatCompactCurrency(res)
                    end
                end
            end)
        end)
    end
end
_G.UpdateShopHeaderSalvage = updateHeaderSalvage

local MENU_OPEN_WAIT_TIMEOUT = 0.75

local function configureModalHeader(label)
    titleLabel.Text = label or "SHOP"
    -- Currency row visibility rules:
    -- Shop: show Coins + Keys + Salvage
    -- Inventory: show Coins + Keys + Salvage
    local isShop = (label == "SHOP" or label == "BOOSTS")
    local isInventory = (label == "INVENTORY")
    local showCurrency = isShop or isInventory
    currencyRow.Visible = showCurrency
    headerCoinFrame.Visible = showCurrency
    headerKeyFrame.Visible = showCurrency
    headerSalvageFrame.Visible = showCurrency
    if showCurrency then
        updateHeaderCoins()
        updateHeaderKeys()
        updateHeaderSalvage()
    end
end

local function contentHostHasGuiContent(contentHost)
    for _, child in ipairs(contentHost:GetChildren()) do
        if child:IsA("GuiObject") then
            return true
        end
    end
    return false
end

local function destroyPreloadedRecord(record)
    if type(record) == "table" and record.host then
        pcall(function() record.host:Destroy() end)
    end
end

local function buildPreloadedMenu(menuName, mod, label, createOptions)
    if not mod then
        error("Missing menu module")
    end

    local contentHost = createContentHost(ensurePrewarmContainer(), menuName)
    contentHost.Visible = false

    local ok, result = xpcall(function()
        local requireOk, loaded = pcall(require, mod)
        if not requireOk then
            error("Require failed: " .. tostring(loaded))
        end
        if type(loaded) ~= "table" or type(loaded.Create) ~= "function" then
            error("Menu module has no Create(parent, coinApi, inventoryApi) function")
        end

        loaded.Create(contentHost, coinApi, Inventory, createOptions)
        if not contentHostHasGuiContent(contentHost) then
            error("Menu did not create any visible content")
        end

        return {
            name = menuName,
            label = label,
            moduleScript = mod,
            module = loaded,
            host = contentHost,
            createOptions = createOptions,
        }
    end, function(buildErr)
        return tostring(buildErr)
    end)

    if ok then
        return result
    end

    pcall(function() contentHost:Destroy() end)
    error(result)
end

local function activatePreloadedMenu(menuName, mod, label)
    if not MenuPreloader then return false end
    local record = MenuPreloader.GetResult(menuName)
    if type(record) ~= "table" or not record.host or not record.host.Parent then
        return false
    end

    modalBuildToken += 1
    configureModalHeader(label)
    clearContent()
    hideModalStatus()

    currentModule = mod
    activePreloadedMenuName = menuName
    record.host.LayoutOrder = 1
    record.host.Visible = true
    record.host.Parent = contentFrame
    return true
end

local function populateModalContentDirect(mod, label, createOptions)
    if not mod then return end
    modalBuildToken += 1
    local token = modalBuildToken
    configureModalHeader(label)
    clearContent()

    local contentHost = createContentHost()
    currentModule = mod
    setModalStatus("Loading " .. string.lower(label or "menu") .. "...", "Getting the menu ready.", COLORS.gold)

    task.defer(function()
        local ok, err = xpcall(function()
            local requireOk, loaded = pcall(require, mod)
            if not requireOk then
                error("Require failed: " .. tostring(loaded))
            end
            if type(loaded) ~= "table" or type(loaded.Create) ~= "function" then
                error("Menu module has no Create(parent, coinApi, inventoryApi) function")
            end
            if token ~= modalBuildToken or not contentHost.Parent then return end

            loaded.Create(contentHost, coinApi, Inventory, createOptions)

            if token ~= modalBuildToken or not contentHost.Parent then return end
            local hasContent = false
            for _, child in ipairs(contentHost:GetChildren()) do
                if child:IsA("GuiObject") then
                    hasContent = true
                    break
                end
            end
            if not hasContent then
                error("Menu did not create any visible content")
            end
        end, function(buildErr)
            return tostring(buildErr)
        end)

        if token ~= modalBuildToken then
            pcall(function() contentHost:Destroy() end)
            return
        end

        if ok then
            hideModalStatus()
        else
            warn("[SideUI] Failed to build " .. tostring(label or "menu") .. ": " .. tostring(err))
            clearContent()
            setModalStatus("Could not load " .. string.lower(label or "menu"), "Close this menu and try opening it again.", Color3.fromRGB(255, 105, 105))
        end
    end)
end

-- Populate modal content without animation (used by MenuController open callbacks)
local function populateModalContent(menuName, mod, label, createOptions)
    if not mod then return end

    if MenuPreloader and type(menuName) == "string" then
        local state = MenuPreloader.GetState(menuName)
        if state == MenuPreloader.State.Failed then
            MenuPreloader.ResetMenu(menuName)
            state = MenuPreloader.GetState(menuName)
        end

        if state ~= MenuPreloader.State.Ready then
            MenuPreloader.StartPreload(menuName)
            local record = MenuPreloader.WaitForMenu(menuName, MENU_OPEN_WAIT_TIMEOUT)
            if record and activatePreloadedMenu(menuName, mod, label) then
                return
            end

            modalBuildToken += 1
            local token = modalBuildToken
            configureModalHeader(label)
            clearContent()
            currentModule = mod
            setModalStatus("Loading " .. string.lower(label or "menu") .. "...", "Getting the menu ready.", COLORS.gold)

            task.spawn(function()
                local loadedRecord, err = MenuPreloader.PreloadMenu(menuName)
                if token ~= modalBuildToken then
                    return
                end
                if loadedRecord and activatePreloadedMenu(menuName, mod, label) then
                    return
                end

                warn("[SideUI] Failed to preload " .. tostring(label or "menu") .. ": " .. tostring(err))
                clearContent()
                currentModule = mod
                setModalStatus("Could not load " .. string.lower(label or "menu"), "Close this menu and try opening it again.", Color3.fromRGB(255, 105, 105))
            end)
            return
        end

        if activatePreloadedMenu(menuName, mod, label) then
            return
        end

        MenuPreloader.ResetMenu(menuName)
    end

    populateModalContentDirect(mod, label, createOptions)
end
-- Instant-close the modal (no animation). Used when switching menus.
-- sameGroup: when true, keeps overlay visible for seamless same-group transition.
local function modalCloseInstant(sameGroup)
    isAnimating = false
    modalBuildToken += 1
    currentModule = nil
    if sameGroup then
        -- Same-group switch: keep overlay visible, only swap content
        clearContent()
        hideModalStatus()
        print("[SideUI] modalCloseInstant: sameGroup=true, overlay stays visible")
    else
        clearAndHide()
        print("[SideUI] modalCloseInstant: sameGroup=false, overlay hidden")
    end
end

-- Register a modal-based menu (Shop, Inventory, etc.) with the MenuController.
-- All modal menus share the same overlay/window; they form a "modal" group so
-- switching between them swaps content in-place without a full close/open cycle.
local function registerModalMenu(name, mod, label, createOptions)
    if not MenuController then return end
    MenuController.RegisterMenu(name, {
        group = "modal",
        open = function(sameGroup)
            populateModalContent(mod, label, createOptions)
            isAnimating = false
            if sameGroup then
                -- Switching within the modal group: overlay already visible, just swap content
                modalOverlay.Visible = true
                window.Position = UDim2.new(0.5, 0, 0.5, 0)
            else
                tweenWindowIn()
            end
        end,
        close = function()
            tweenWindowOut()
        end,
        closeInstant = function(sameGroup)
            modalCloseInstant(sameGroup)
        end,
        isOpen = function()
            return modalOverlay.Visible and currentModule == mod
        end,
    })
    -- Also register with authoritative MenuState (tracks real GUI visibility)
    local msMod = sideUIFolder and sideUIFolder:FindFirstChild("MenuState")
    if msMod and msMod:IsA("ModuleScript") then
        local ok, ms = pcall(require, msMod)
        if ok and ms and ms.RegisterMenu then
            ms.RegisterMenu(name, { gui = modalOverlay, isOpen = function()
                return modalOverlay.Visible and currentModule == mod
            end })
        end
    end
end

local HIGH_PRIORITY_MENU_PRELOAD_ORDER = { "Shop", "Inventory", "Quests", "Options" }
local MENU_ASSET_PRELOAD_KEYS = {
    "Shop", "Inventory", "Quests", "Options", "Team",
    "Coin", "Key", "Keys", "Shards", "Shard", "Robux",
    "Boosts", "Upgrade", "DailyReward", "Bandage",
    "Melee", "Ranged",
}
local REPLICATED_MENU_ASSET_MODULES = {
    "BoostConfig",
    "PotionConfig",
    "HealthPotionConfig",
    "BandageConfig",
    "ItemIconRegistry",
    "SkinDefinitions",
    "CrateConfig",
    "SalvageShopConfig",
    "CosmeticsCatalog",
}
local SIDE_UI_MENU_ASSET_MODULES = {
    "EffectDefs",
    "EmoteConfig",
}
local menuAssetPreloadStarted = false

local function addAssetId(assetIds, assetId)
    if type(assetId) ~= "string" or assetId == "" then
        return
    end
    if assetId:match("^%d+$") then
        assetId = "rbxassetid://" .. assetId
    end
    if not (assetId:match("^rbxassetid://") or assetId:match("^rbxthumb://") or assetId:match("^https?://")) then
        return
    end
    assetIds[assetId] = true
end

local function shouldCollectAssetField(key)
    local keyText = tostring(key or ""):lower()
    return keyText:find("icon", 1, true)
        or keyText:find("image", 1, true)
        or keyText:find("asset", 1, true)
        or keyText:find("thumbnail", 1, true)
        or keyText:find("preview", 1, true)
        or keyText:find("glow", 1, true)
end

local function collectAssetIdsFromTable(value, assetIds, seen, depth)
    if type(value) ~= "table" or depth > 5 or seen[value] then
        return
    end
    seen[value] = true

    for key, child in pairs(value) do
        if type(child) == "string" then
            if shouldCollectAssetField(key) or child:match("^rbxassetid://") or child:match("^rbxthumb://") then
                addAssetId(assetIds, child)
            end
        elseif type(child) == "number" then
            if shouldCollectAssetField(key) then
                addAssetId(assetIds, tostring(child))
            end
        elseif type(child) == "table" then
            collectAssetIdsFromTable(child, assetIds, seen, depth + 1)
        end
    end
end

local function safeRequireAssetModule(parent, moduleName)
    local module = parent and parent:FindFirstChild(moduleName)
    if not (module and module:IsA("ModuleScript")) then
        return nil
    end
    local ok, result = pcall(require, module)
    if ok then
        return result
    end
    warn("[MenuPreloader] Asset config failed to load: " .. tostring(moduleName) .. " - " .. tostring(result))
    return nil
end

local function preloadMenuAssets()
    if menuAssetPreloadStarted then return end
    menuAssetPreloadStarted = true

    local assetIds = {}
    if AssetCodes and type(AssetCodes.Get) == "function" then
        for _, key in ipairs(MENU_ASSET_PRELOAD_KEYS) do
            local ok, assetId = pcall(function() return AssetCodes.Get(key) end)
            if ok then addAssetId(assetIds, assetId) end
        end
    end
    if AssetCodes and type(AssetCodes.List) == "function" then
        local ok, images = pcall(function() return AssetCodes.List() end)
        if ok and type(images) == "table" then
            for _, assetId in pairs(images) do
                addAssetId(assetIds, assetId)
            end
        end
    end

    for _, moduleName in ipairs(REPLICATED_MENU_ASSET_MODULES) do
        local config = safeRequireAssetModule(ReplicatedStorage, moduleName)
        if config then
            collectAssetIdsFromTable(config, assetIds, {}, 0)
        end
    end
    for _, moduleName in ipairs(SIDE_UI_MENU_ASSET_MODULES) do
        local config = safeRequireAssetModule(sideUIFolder, moduleName)
        if config then
            collectAssetIdsFromTable(config, assetIds, {}, 0)
        end
    end

    local preloadList = {}
    for assetId in pairs(assetIds) do
        table.insert(preloadList, assetId)
    end
    if #preloadList == 0 then
        return
    end

    if MenuPreloader and MenuPreloader.DEBUG_MENU_PRELOAD then
        print("[MenuPreloader] Starting asset preload:", #preloadList)
    end

    local batchSize = 24
    for index = 1, #preloadList, batchSize do
        local batch = {}
        for batchIndex = index, math.min(index + batchSize - 1, #preloadList) do
            table.insert(batch, preloadList[batchIndex])
        end
        local ok, err = pcall(function()
            ContentProvider:PreloadAsync(batch)
        end)
        if not ok then
            warn("[MenuPreloader] Asset preload failed: " .. tostring(err))
        end
        task.wait(0.05)
    end
end

local function startMenuWarmup()
    if not MenuPreloader then return end
    if MenuPreloader.GetEntry and not MenuPreloader.GetEntry("Shop") then return end
    task.defer(function()
        task.wait()
        MenuPreloader.PreloadMenus(HIGH_PRIORITY_MENU_PRELOAD_ORDER, 0.08)
        task.defer(preloadMenuAssets)
    end)
end

local function registerPrewarmedModalMenu(name, mod, label, createOptions)
    if not MenuController then return end
    if MenuPreloader then
        MenuPreloader.RegisterMenu(name, {
            preload = function(menuName)
                return buildPreloadedMenu(menuName, mod, label, createOptions)
            end,
            onReset = destroyPreloadedRecord,
        })
    end

    MenuController.RegisterMenu(name, {
        group = "modal",
        open = function(sameGroup)
            populateModalContent(name, mod, label, createOptions)
            isAnimating = false
            if sameGroup then
                modalOverlay.Visible = true
                window.Position = UDim2.new(0.5, 0, 0.5, 0)
            else
                tweenWindowIn()
            end
        end,
        close = function()
            tweenWindowOut()
        end,
        closeInstant = function(sameGroup)
            modalCloseInstant(sameGroup)
        end,
        isOpen = function()
            return modalOverlay.Visible and currentModule == mod
        end,
    })
end

-- Register every modal page
if shopModule then registerModalMenu("Shop", shopModule, "SHOP") end
if invModule then registerModalMenu("Inventory", invModule, "INVENTORY") end
if optionsModule then registerModalMenu("Options", optionsModule, "OPTIONS") end
if questsModule then registerModalMenu("Quests", questsModule, "Achievements", { achievementsOnly = true, initialTabId = "achiev" }) end
if shopModule then registerPrewarmedModalMenu("Shop", shopModule, "SHOP") end
if invModule then registerPrewarmedModalMenu("Inventory", invModule, "INVENTORY") end
if optionsModule then registerPrewarmedModalMenu("Options", optionsModule, "OPTIONS") end
if questsModule then registerPrewarmedModalMenu("Quests", questsModule, "Achievements", { achievementsOnly = true, initialTabId = "achiev" }) end
startMenuWarmup()
-- Legacy helper kept for any external code that may still reference it
local function requestShowModule(mod, label)
    if not mod then return end
    -- Map module ref → MenuController name and delegate
    local nameMap = {
        [shopModule]     = "Shop",
        [invModule]      = "Inventory",
        [optionsModule]  = "Options",
        [questsModule]   = "Quests",
    }
    local menuName = nameMap[mod]
    if MenuController and menuName then
        MenuController.ToggleMenu(menuName)
    end
end

-- Launcher card activation is wired in createLauncherButton and routed through
-- scriptHandlers below so all four side buttons share the same open path.

-- Options HUD button (must be placed AFTER menu registration)
local function toggleOptionsMenu()
    if MenuController then MenuController.ToggleMenu("Options") else requestShowModule(optionsModule, "OPTIONS") end
end

local optionsHudGui, optionsHudButton = CreateHudOptionsButton(toggleOptionsMenu)

local function ensureOptionsHudButton()
    if not optionsHudGui or not optionsHudGui.Parent or not optionsHudButton or not optionsHudButton.Parent then
        optionsHudGui, optionsHudButton = CreateHudOptionsButton(toggleOptionsMenu)
    end
end

task.delay(1, ensureOptionsHudButton)
task.delay(3, ensureOptionsHudButton)
playerGui.ChildRemoved:Connect(function(child)
    if child and child.Name == "OptionsHudGui" then
        task.defer(ensureOptionsHudButton)
    end
end)

-- Side launcher no longer renders a coin row; coinApi remains headless for
-- Shop/Inventory headers, reward refreshes, and crate-opening integrations.
print("[SideUI] headless coin API initialized; no launcher coin row created")
pcall(function() updateHeaderCoins() end)

-- PREMIUM CRATE / KEY SYSTEM  – Key API (no HUD row; displayed in Shop header only)
if KeyDisplayModule and KeyDisplayModule.Create then
    -- Create off-screen to initialize the key API without showing the row in the HUD
    local hiddenHost = Instance.new("Frame")
    hiddenHost.Name = "KeyApiHost"
    hiddenHost.Visible = false
    hiddenHost.Size = UDim2.new(0, 0, 0, 0)
    hiddenHost.Parent = panel
    local _keyRow
    _keyRow, keyApi = KeyDisplayModule.Create(hiddenHost, 1)
    if coinApi and keyApi then
        coinApi.SetKeys = keyApi.SetKeys
        coinApi.GetKeys = keyApi.GetKeys
    end
    print("[SideUI] KeyDisplay API initialized (no HUD row)")
end

-- SALVAGE SYSTEM  – Salvage API (no HUD row; displayed in Inventory/Shop only)
if SalvageDisplayModule and SalvageDisplayModule.Create then
    local hiddenHost = Instance.new("Frame")
    hiddenHost.Name = "SalvageApiHost"
    hiddenHost.Visible = false
    hiddenHost.Size = UDim2.new(0, 0, 0, 0)
    hiddenHost.Parent = panel
    local _salvageRow
    _salvageRow, salvageApi = SalvageDisplayModule.Create(hiddenHost, 1)
    print("[SideUI] SalvageDisplay API initialized (no HUD row)")
end

-- Initialize CrateOpeningUI (roulette animation overlay)
if crateOpeningModule and crateOpeningModule:IsA("ModuleScript") then
    pcall(function()
        local CrateOpeningUI = require(crateOpeningModule)
        if CrateOpeningUI and CrateOpeningUI.Init then
            CrateOpeningUI.Init(playerGui)
            _G.CrateOpeningCoinApi = coinApi
            print("[SideUI] CrateOpeningUI initialized")
        end
    end)
end

-- Listen for server coin updates. Uses task.spawn + WaitForChild so the remote
-- is found reliably in Team Test without blocking the rest of UI init.
task.spawn(function()
    local coinsEvent = ReplicatedStorage:WaitForChild("CoinsUpdated", 10)
    if coinsEvent and coinsEvent:IsA("RemoteEvent") then
        coinsEvent.OnClientEvent:Connect(function(amount)
            if coinApi and coinApi.SetCoins then
                coinApi.SetCoins(amount)
            else
                headerCoinLabel.Text = formatCompactCurrency(amount)
            end
        end)
        pcall(updateHeaderCoins)
    else
        warn("[SideUI] CoinsUpdated remote not found – coin header won't auto-update")
    end
end)

-- PREMIUM CRATE / KEY SYSTEM  – Listen for server key updates
task.spawn(function()
    local keysEvent = ReplicatedStorage:WaitForChild("KeysUpdated", 10)
    if keysEvent and keysEvent:IsA("RemoteEvent") then
        keysEvent.OnClientEvent:Connect(function(amount)
            if keyApi and keyApi.SetKeys then
                pcall(function() keyApi.SetKeys(amount) end)
            end
            headerKeyLabel.Text = formatCompactCurrency(amount)
        end)
    else
        warn("[SideUI] KeysUpdated remote not found – key display won't auto-update")
    end
end)

-- SALVAGE SYSTEM  – Listen for server salvage updates (header label + API)
task.spawn(function()
    local salvageEvent = ReplicatedStorage:WaitForChild("SalvageUpdated", 10)
    if salvageEvent and salvageEvent:IsA("RemoteEvent") then
        salvageEvent.OnClientEvent:Connect(function(amount)
            headerSalvageLabel.Text = formatCompactCurrency(amount)
        end)
    else
        warn("[SideUI] SalvageUpdated remote not found – salvage header won't auto-update")
    end
end)

-- Deferred retry to catch slow DataStore loads (same schedule as CoinDisplay)
task.spawn(function()
    local delays = {1, 2, 3, 5}
    for _, d in ipairs(delays) do
        task.wait(d)
        pcall(updateHeaderCoins)
    end
end)

for _, child in ipairs(panel:GetChildren()) do
    if child.Name == "ActiveBoostIcons" then
        pcall(function() child:Destroy() end)
    end
end

-- Launcher buttons are created inside SideButtonStack during CreateSideLauncher.

-- Exposed API
local function SetCoins(amount)
    if coinApi and coinApi.SetCoins then
        coinApi.SetCoins(amount)
    end
end

local function SetBadge(id, enabled)
    local badge = badgesById[id]
    if badge then
        badge.Visible = enabled and true or false
    end
end

local achievementBadgeDataById = {}

local function isAchievementClaimable(entry)
    if type(entry) ~= "table" then return false end
    if entry.claimed == true or entry.maxedOut == true then return false end
    local isComplete = entry.completed == true
    local goal = tonumber(entry.target) or 0
    local progress = tonumber(entry.progress) or 0
    return isComplete or (goal > 0 and progress >= goal)
end

local function updateAchievementLauncherBadge()
    local hasClaimable = false
    for _, entry in pairs(achievementBadgeDataById) do
        if isAchievementClaimable(entry) then
            hasClaimable = true
            break
        end
    end
    SetBadge("Missions", hasClaimable)
end

local function refreshAchievementLauncherBadge(getAchievementsRF)
    if not getAchievementsRF or not getAchievementsRF:IsA("RemoteFunction") then return end
    task.spawn(function()
        local ok, result = pcall(function()
            return getAchievementsRF:InvokeServer()
        end)
        if not ok or type(result) ~= "table" then return end
        achievementBadgeDataById = {}
        for _, entry in ipairs(result) do
            if type(entry) == "table" and type(entry.id) == "string" then
                achievementBadgeDataById[entry.id] = entry
            end
        end
        updateAchievementLauncherBadge()
    end)
end

local function wireAchievementLauncherBadge()
    task.spawn(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then return end
        local getAchievementsRF = remotes:WaitForChild("GetAchievements", 10)
        local achievProgressRE = remotes:WaitForChild("AchievementProgress", 10)

        if getAchievementsRF and getAchievementsRF:IsA("RemoteFunction") then
            refreshAchievementLauncherBadge(getAchievementsRF)
        end

        if achievProgressRE and achievProgressRE:IsA("RemoteEvent") then
            achievProgressRE.OnClientEvent:Connect(function(achId, progress, completed, achievedOn, claimed, stageIndex)
                if achId == "__full_refresh" then
                    refreshAchievementLauncherBadge(getAchievementsRF)
                    return
                end
                if type(achId) ~= "string" then return end

                local entry = achievementBadgeDataById[achId] or { id = achId }
                entry.progress = tonumber(progress) or entry.progress or 0
                entry.completed = completed == true
                entry.achievedOn = achievedOn
                entry.claimed = claimed == true
                if stageIndex ~= nil then
                    entry.stageIndex = stageIndex
                end
                achievementBadgeDataById[achId] = entry
                updateAchievementLauncherBadge()
            end)
        end
    end)
end

local function OpenPage(id)
    -- Route all menu opens through MenuController for unified one-click switching
    if MenuController then
        local idToMenu = {
            Shop     = "Shop",
            Inventory = "Inventory",
            Options  = "Options",
            Missions = "Quests",
            Achieves = "Quests",
            Achievement = "Quests",
            Achievements = "Quests",
            Quests   = "Quests",
            Team     = "Team",
        }
        local menuName = idToMenu[id]
        if menuName then
            MenuController.ToggleMenu(menuName)
            return
        end
    else
        -- Fallback if MenuController failed to load
        if id == "Shop" then requestShowModule(shopModule, "SHOP"); return end
        if id == "Inventory" then requestShowModule(invModule, "INVENTORY"); return end
        if id == "Options" then toggleOptionsMenu(); return end
        if id == "Missions" or id == "Achieves" or id == "Achievement" or id == "Achievements" or id == "Quests" then
            requestShowModule(questsModule, "Achievements")
            return
        end
        if id == "Team" then
            if type(_G.TeamStatsToggle) == "function" then pcall(_G.TeamStatsToggle) end
            return
        end
    end
    print("OpenPage:", id)
end

-- Expose simple handlers via a small global table so other local scripts can call them
-- (using _G avoids assigning arbitrary members on the Instance which can error)
_G.SideUI = _G.SideUI or {}
_G.SideUI.SetCoins = SetCoins
_G.SideUI.SetBadge = SetBadge
_G.SideUI.OpenPage = OpenPage
_G.SideUI.OpenOptions = toggleOptionsMenu
_G.SideUI.SetTitle = function(text) titleLabel.Text = text end
_G.SideUI.MenuController = MenuController  -- expose for other scripts

-- default handlers (can be overridden by assigning to script.OnShop/script.OnMenuButton)
-- Assign to the forward-declared scriptHandlers table (line ~106) so click closures above see these
scriptHandlers.OnShop = function()
    if MenuController then MenuController.ToggleMenu("Shop") else requestShowModule(shopModule, "SHOP") end
end
scriptHandlers.OnInventory = function()
    if MenuController then MenuController.ToggleMenu("Inventory") else requestShowModule(invModule, "INVENTORY") end
end
scriptHandlers.OnMenuButton = function(id)
    OpenPage(id)
end

-- Initial default state for the headless coin API and launcher badges.
if not coinApi then
    SetCoins(0)
end
for id,_ in pairs(badgesById) do SetBadge(id, false) end
wireAchievementLauncherBadge()


-- OPTIONAL: small convenience to return refs (not required, but handy during dev)
pcall(function() script.buttonsById = buttonsById end)
pcall(function() script.badgesById = badgesById end)

-- finished building UI
return nil