local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Lock camera to the menu view
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.new(-86.447, 171.093, 128.36)
	* CFrame.Angles(math.rad(-51.001), math.rad(0.243), math.rad(0))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeamPickerGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

---------------------------------------------------------------------------
-- Title
---------------------------------------------------------------------------
local title = Instance.new("TextLabel")
title.Text = "CHOOSE YOUR SIDE"
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextStrokeTransparency = 0.6
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.8, 0, 0.06, 0)
title.Position = UDim2.new(0.1, 0, 0.15, 0)
title.Parent = screenGui

---------------------------------------------------------------------------
-- Container that holds both team cards side-by-side
---------------------------------------------------------------------------
local container = Instance.new("Frame")
container.Size = UDim2.new(0.7, 0, 0.45, 0)
container.Position = UDim2.new(0.5, 0, 0.52, 0)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.BackgroundTransparency = 1
container.Parent = screenGui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Padding = UDim.new(0.03, 0)
listLayout.Parent = container

---------------------------------------------------------------------------
-- Helper: create a team card button
---------------------------------------------------------------------------
local function makeCard(teamName, accentColor, hoverColor, iconText)
	local card = Instance.new("TextButton")
	card.Name = teamName .. "Card"
	card.Text = ""
	card.AutoButtonColor = false
	card.Size = UDim2.new(0.45, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	card.BorderSizePixel = 0
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = accentColor
	stroke.Thickness = 2.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	-- Accent bar at the top
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.Position = UDim2.new(0, 0, 0, 0)
	bar.BackgroundColor3 = accentColor
	bar.BorderSizePixel = 0
	bar.Parent = card
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 16)
	barCorner.Parent = bar

	-- Icon / emoji
	local icon = Instance.new("TextLabel")
	icon.Text = iconText
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.TextColor3 = accentColor
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0.25, 0)
	icon.Position = UDim2.new(0, 0, 0.12, 0)
	icon.Parent = card

	-- Team name label
	local label = Instance.new("TextLabel")
	label.Text = "JOIN " .. string.upper(teamName)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.8, 0, 0.12, 0)
	label.Position = UDim2.new(0.1, 0, 0.45, 0)
	label.Parent = card


	-- Small "CLICK TO JOIN" prompt
	local prompt = Instance.new("TextLabel")
	prompt.Text = "CLICK TO JOIN"
	prompt.Font = Enum.Font.GothamBold
	prompt.TextScaled = true
	prompt.TextColor3 = accentColor
	prompt.BackgroundTransparency = 1
	prompt.Size = UDim2.new(0.6, 0, 0.07, 0)
	prompt.Position = UDim2.new(0.2, 0, 0.85, 0)
	prompt.Parent = card

	-- Hover effects
	card.MouseEnter:Connect(function()
		card.BackgroundColor3 = hoverColor
		stroke.Thickness = 3.5
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		stroke.Thickness = 2.5
	end)

	return card
end

---------------------------------------------------------------------------
-- Blue on the LEFT, Red on the RIGHT
---------------------------------------------------------------------------
local blueCard = makeCard("Blue", Color3.fromRGB(60, 140, 255), Color3.fromRGB(35, 40, 60), "🛡️")
local redCard  = makeCard("Red",  Color3.fromRGB(255, 60, 60),  Color3.fromRGB(55, 30, 35), "⚔️")

---------------------------------------------------------------------------
-- Team choice logic
---------------------------------------------------------------------------
local chooseEvent = ReplicatedStorage:WaitForChild("ChooseTeamEvent")

local function chooseSide(teamName)
	chooseEvent:FireServer(teamName)
	screenGui:Destroy()
	camera.CameraType = Enum.CameraType.Custom
end

blueCard.MouseButton1Click:Connect(function()
	chooseSide("Blue")
end)

redCard.MouseButton1Click:Connect(function()
	chooseSide("Red")
end)
