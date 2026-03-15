-- HealthBar.client.lua
-- Custom always-visible health bar anchored to the bottom-left corner.
-- Disables the default Roblox health UI and rebuilds it from scratch.
-- Sized as a prominent main HUD element, matching the navy+gold game theme.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- DISABLE DEFAULT HEALTH BAR
--------------------------------------------------------------------------------
local function disableDefaultHealth()
	local ok, err
	for _ = 1, 10 do
		ok, err = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then break end
		task.wait(0.5)
	end
	if not ok then
		warn("[HealthBar] Could not disable default health UI:", err)
	end
end
disableDefaultHealth()

--------------------------------------------------------------------------------
-- SCALE HELPER (reference: 1080p – matches SideUI/MatchHUD)
--------------------------------------------------------------------------------
do
	local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
	if cam then
		local t = 0
		while cam.ViewportSize.Y < 2 and t < 3 do
			t = t + task.wait()
		end
	end
end

local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- PALETTE (consistent with MatchHUD / SideUI navy + gold theme)
--------------------------------------------------------------------------------
local NAVY        = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT  = Color3.fromRGB(22, 26, 48)
local GOLD        = Color3.fromRGB(255, 215, 80)
local GREEN_FILL  = Color3.fromRGB(75, 200, 80)
local YELLOW_FILL = Color3.fromRGB(230, 195, 50)
local RED_FILL    = Color3.fromRGB(220, 50, 50)
local WHITE       = Color3.fromRGB(245, 245, 245)

--------------------------------------------------------------------------------
-- CREATE SCREEN GUI
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomHealthBar"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 6
screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- BUILD UI ELEMENTS (prominent bottom-left HUD bar)
--------------------------------------------------------------------------------

-- Outer container – pinned to bottom-left with generous padding from edges.
-- Width ~340px and height ~52px at 1080p makes this a true main-HUD element.
local BAR_WIDTH  = px(340)
local BAR_HEIGHT = px(52)
local EDGE_PAD   = px(24)

local container = Instance.new("Frame")
container.Name = "HealthContainer"
container.AnchorPoint = Vector2.new(0, 1)
container.Position = UDim2.new(0, EDGE_PAD, 1, -EDGE_PAD)
container.Size = UDim2.new(0, BAR_WIDTH, 0, BAR_HEIGHT)
container.BackgroundColor3 = NAVY
container.BackgroundTransparency = 0.06
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, px(12))
containerCorner.Parent = container

-- Gold outline so the bar pops against any background
local containerStroke = Instance.new("UIStroke")
containerStroke.Color = GOLD
containerStroke.Thickness = px(2)
containerStroke.Transparency = 0.35
containerStroke.Parent = container

-- Drop shadow for depth
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 0, 0.55, 3)
shadow.Size = UDim2.new(1, 10, 1, 10)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.65
shadow.BorderSizePixel = 0
shadow.ZIndex = 0
shadow.Parent = container
Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, px(14))

-- Inner padding keeps children off the container edges
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, px(8))
padding.PaddingBottom = UDim.new(0, px(8))
padding.PaddingLeft = UDim.new(0, px(10))
padding.PaddingRight = UDim.new(0, px(10))
padding.Parent = container

-- Heart icon – large enough to be instantly recognisable
local ICON_SIZE = px(34)
local heartIcon = Instance.new("TextLabel")
heartIcon.Name = "HeartIcon"
heartIcon.AnchorPoint = Vector2.new(0, 0.5)
heartIcon.Position = UDim2.new(0, 0, 0.5, 0)
heartIcon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
heartIcon.BackgroundTransparency = 1
heartIcon.Text = "❤"
heartIcon.Font = Enum.Font.GothamBold
heartIcon.TextColor3 = RED_FILL
heartIcon.TextScaled = true
heartIcon.ZIndex = 3
heartIcon.Parent = container

-- Bar background (dark track behind the coloured fill)
local BAR_OFFSET = ICON_SIZE + px(8) -- start bar to the right of the heart
local barBg = Instance.new("Frame")
barBg.Name = "BarBackground"
barBg.AnchorPoint = Vector2.new(0, 0.5)
barBg.Position = UDim2.new(0, BAR_OFFSET, 0.5, 0)
barBg.Size = UDim2.new(1, -BAR_OFFSET, 1, 0)
barBg.BackgroundColor3 = NAVY_LIGHT
barBg.BorderSizePixel = 0
barBg.ClipsDescendants = true
barBg.ZIndex = 1
barBg.Parent = container
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, px(8))

-- Subtle inner border on the bar track
local barStroke = Instance.new("UIStroke")
barStroke.Color = GOLD
barStroke.Thickness = 1
barStroke.Transparency = 0.75
barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
barStroke.Parent = barBg

-- Fill bar (coloured portion that shrinks / grows via tween)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = GREEN_FILL
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = barBg
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, px(8))

-- Fill gradient for subtle polish
local fillGradient = Instance.new("UIGradient")
fillGradient.Rotation = 90
fillGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0.25),
})
fillGradient.Parent = fill

-- Health text ("85 / 100") – centred on the bar, large and easy to read
local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthText"
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.BackgroundTransparency = 1
healthLabel.Text = "100 / 100"
healthLabel.Font = Enum.Font.GothamBold
healthLabel.TextColor3 = WHITE
healthLabel.TextScaled = true
healthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
healthLabel.TextStrokeTransparency = 0.4
healthLabel.ZIndex = 3
healthLabel.Parent = barBg

-- Text size constraint – allows much larger text now (up to 26px at 1080p)
local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MaxTextSize = px(26)
textConstraint.Parent = healthLabel

--------------------------------------------------------------------------------
-- TWEEN / UPDATE LOGIC
--------------------------------------------------------------------------------
local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentTween: Tween? = nil

local function getBarColor(ratio: number): Color3
	if ratio > 0.5 then
		return GREEN_FILL
	elseif ratio > 0.25 then
		return YELLOW_FILL
	else
		return RED_FILL
	end
end

local function updateBar(health: number, maxHealth: number)
	local ratio = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
	local displayHealth = math.floor(health)
	local displayMax = math.floor(maxHealth)

	healthLabel.Text = displayHealth .. " / " .. displayMax
	fill.BackgroundColor3 = getBarColor(ratio)

	-- Cancel any running tween before starting a new one
	if currentTween then
		currentTween:Cancel()
	end
	currentTween = TweenService:Create(fill, TWEEN_INFO, {
		Size = UDim2.new(ratio, 0, 1, 0),
	})
	currentTween:Play()
end

--------------------------------------------------------------------------------
-- CHARACTER / HUMANOID CONNECTION (respawn-safe)
--------------------------------------------------------------------------------
local healthConn: RBXScriptConnection? = nil
local maxHealthConn: RBXScriptConnection? = nil

local function connectToCharacter(character)
	-- Disconnect previous connections
	if healthConn then healthConn:Disconnect() end
	if maxHealthConn then maxHealthConn:Disconnect() end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		warn("[HealthBar] Humanoid not found in character")
		return
	end

	-- Initial update
	updateBar(humanoid.Health, humanoid.MaxHealth)

	-- Listen for health changes
	healthConn = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		updateBar(humanoid.Health, humanoid.MaxHealth)
	end)

	-- Listen for max health changes (e.g. upgrades, buffs)
	maxHealthConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateBar(humanoid.Health, humanoid.MaxHealth)
	end)
end

-- Connect to current character if it already exists
if player.Character then
	task.spawn(connectToCharacter, player.Character)
end

-- Reconnect on every respawn
player.CharacterAdded:Connect(function(character)
	connectToCharacter(character)
end)
