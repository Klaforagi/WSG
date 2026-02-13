local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Lock camera to the menu view
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.new(-72.447, 171.093, 128.36)
	* CFrame.Angles(math.rad(-51), math.rad(0.386), math.rad(-0.3))

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

	-- Player count label (updates dynamically)
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Text = "0"
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextScaled = true
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	countLabel.BackgroundTransparency = 1
	countLabel.Size = UDim2.new(0.3, 0, 0.08, 0)
	countLabel.Position = UDim2.new(0.35, 0, 0.7, 0)
	countLabel.Parent = card

	-- Disabled attribute (client-side visual/guard)
	card:SetAttribute("Disabled", false)

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

local chooseResponse = ReplicatedStorage:WaitForChild("ChooseTeamResponse")

local function showError(msg)
	local existing = screenGui:FindFirstChild("TeamError")
	if existing then existing:Destroy() end
	local err = Instance.new("TextLabel")
	err.Name = "TeamError"
	err.Text = msg
	err.Font = Enum.Font.GothamBold
	err.TextScaled = true
	err.TextColor3 = Color3.fromRGB(255, 120, 120)
	err.BackgroundTransparency = 1
	err.Size = UDim2.new(0.6, 0, 0.06, 0)
	err.Position = UDim2.new(0.2, 0, 0.28, 0)
	err.Parent = screenGui
	delay(2, function()
		if err then err:Destroy() end
	end)
end

local function chooseSide(teamName)
	-- guard client-side disabled flag (visual)
	local card = (teamName == "Blue") and blueCard or redCard
	if card and card:GetAttribute("Disabled") then
		showError("That team has more players — pick the other side")
		return
	end

	chooseEvent:FireServer(teamName)
end

-- handle server response (success => close UI, failure => show message)
chooseResponse.OnClientEvent:Connect(function(success, message)
	if success then
		screenGui:Destroy()
		camera.CameraType = Enum.CameraType.Custom
	else
		showError(message or "Could not join team")
	end
end)

blueCard.MouseButton1Click:Connect(function()
	chooseSide("Blue")
end)

-- Player count updating
local Teams = game:GetService("Teams")

local function updateCounts()
	local blueCount = 0
	local redCount = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local tname
		if p.Team then
			tname = p.Team.Name
		else
			tname = p:GetAttribute("Team")
		end
		if tname == "Blue" then
			blueCount = blueCount + 1
		elseif tname == "Red" then
			redCount = redCount + 1
		end
	end

	local bc = blueCard:FindFirstChild("CountLabel")
	local rc = redCard:FindFirstChild("CountLabel")
	if bc then bc.Text = tostring(blueCount) end
	if rc then rc.Text = tostring(redCount) end
    
	-- Disable the side only when it's 2 or more players larger than the other
	if blueCount >= redCount + 2 then
		blueCard:SetAttribute("Disabled", true)
		blueCard.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	else
		blueCard:SetAttribute("Disabled", false)
		blueCard.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	end

	if redCount >= blueCount + 2 then
		redCard:SetAttribute("Disabled", true)
		redCard.BackgroundColor3 = Color3.fromRGB(26, 20, 20)
	else
		redCard:SetAttribute("Disabled", false)
		redCard.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	end
end

-- Wire up events
updateCounts()
for _, p in ipairs(Players:GetPlayers()) do
	p:GetPropertyChangedSignal("Team"):Connect(updateCounts)
end
Players.PlayerAdded:Connect(function(p)
	p:GetPropertyChangedSignal("Team"):Connect(updateCounts)
	updateCounts()
end)
Players.PlayerRemoving:Connect(updateCounts)

redCard.MouseButton1Click:Connect(function()
	chooseSide("Red")
end)
