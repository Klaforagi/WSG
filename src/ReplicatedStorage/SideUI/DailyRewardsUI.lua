--------------------------------------------------------------------------------
-- DailyRewardsUI.lua  –  Code-built daily login modal (navy + gold)
-- Featured today's reward + compact 7-day track. Does not use the Studio GUI.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UITheme = require(script.Parent.UITheme)
local TimeHelper
pcall(function()
	TimeHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeHelper"))
end)

local AssetCodes
pcall(function()
	AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes", 5))
end)

local DailyRewardsUI = {}

local screenGui
local overlay
local window
local windowScale
local claimButton
local featuredIcon
local featuredDayLabel
local featuredName
local featuredStatus
local streakValue
local timerLabel
local dayNodes = {}
local isOpen = false
local currentState
local selectedDay = 1
local onClaimCb
local timerToken = 0
local syncWindowLayout

local NAVY = UITheme.NAVY
local NAVY_LIGHT = UITheme.NAVY_LIGHT
local GOLD = UITheme.GOLD
local GOLD_DIM = UITheme.GOLD_DIM
local WHITE = UITheme.WHITE
local DIM = UITheme.DIM_TEXT
local GREEN = UITheme.GREEN_BTN
local CARD = UITheme.CARD_BG
local STROKE = UITheme.CARD_STROKE

local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

local function constrainText(label, minSize, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize
	c.MaxTextSize = maxSize
	c.Parent = label
	return c
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.2
	s.Transparency = transparency or 0.25
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function inferType(reward)
	if type(reward) ~= "table" then
		return "Coins"
	end
	local t = reward.rewardType or reward.type
	if type(t) == "string" and t ~= "" then
		return t
	end
	local name = string.lower(tostring(reward.displayName or ""))
	if string.find(name, "shard", 1, true) then
		return "Shards"
	end
	if string.find(name, "key", 1, true) then
		return "Key"
	end
	return "Coins"
end

local function iconForType(rewardType)
	if not (AssetCodes and AssetCodes.Get) then
		return ""
	end
	if rewardType == "Shards" then
		return AssetCodes.Get("Shards") or ""
	end
	if rewardType == "Key" then
		return AssetCodes.Get("Key") or ""
	end
	return AssetCodes.Get("Coin") or ""
end

local function hideLegacyStudioGui(playerGui)
	local legacy = playerGui:FindFirstChild("DailyRewardsGui")
	if legacy and legacy:IsA("ScreenGui") and legacy ~= screenGui then
		legacy.Enabled = false
		local win = legacy:FindFirstChild("DailyRewardsWindow")
		if win then
			win.Visible = false
		end
	end
end

local FALLBACK_REWARDS = {
	{ day = 1, displayName = "100 Coins", amount = 100, rewardType = "Coins" },
	{ day = 2, displayName = "50 Shards", amount = 50, rewardType = "Shards" },
	{ day = 3, displayName = "200 Coins", amount = 200, rewardType = "Coins" },
	{ day = 4, displayName = "100 Shards", amount = 100, rewardType = "Shards" },
	{ day = 5, displayName = "300 Coins", amount = 300, rewardType = "Coins" },
	{ day = 6, displayName = "150 Shards", amount = 150, rewardType = "Shards" },
	{ day = 7, displayName = "1 Golden Key", amount = 1, rewardType = "Key" },
}

local function getReward(day)
	local rewards = currentState and currentState.rewards
	if type(rewards) == "table" then
		for _, reward in ipairs(rewards) do
			if type(reward) == "table" and tonumber(reward.day) == day then
				return reward
			end
		end
		if type(rewards[day]) == "table" then
			return rewards[day]
		end
	end
	return FALLBACK_REWARDS[day]
end

local function hasRealClaim(state)
	local lastClaimTime = tonumber(state and state.lastClaimTime)
	local currentDay = tonumber(state and state.currentDay) or 0
	return lastClaimTime ~= nil and lastClaimTime > 1600000000 and currentDay > 0
end

local function computeDayStatus(dayIndex, state)
	if type(state) ~= "table" or not hasRealClaim(state) then
		return dayIndex == 1 and "claimable" or "future"
	end
	local currentDay = tonumber(state.currentDay) or 0
	if state.alreadyClaimed == true then
		return dayIndex <= currentDay and "claimed" or "future"
	end
	if dayIndex <= currentDay then
		return "claimed"
	end
	if dayIndex == currentDay + 1 then
		return "claimable"
	end
	return "future"
end

local function statusColor(status)
	if status == "claimed" then
		return Color3.fromRGB(28, 58, 40), Color3.fromRGB(70, 210, 110)
	end
	if status == "claimable" then
		return Color3.fromRGB(42, 36, 16), GOLD
	end
	return CARD, STROKE
end

local function secondsUntilNextDay()
	if TimeHelper and TimeHelper.SecondsUntilNextDailyReset then
		return math.max(0, tonumber(TimeHelper.SecondsUntilNextDailyReset()) or 0)
	end
	local utc = os.date("!*t", os.time())
	local elapsed = (utc.hour * 3600) + (utc.min * 60) + utc.sec
	return math.max(0, 86400 - elapsed)
end

local function formatHMS(total)
	total = math.max(0, math.floor(tonumber(total) or 0))
	local h = math.floor(total / 3600)
	local m = math.floor((total % 3600) / 60)
	local s = total % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function updateTimerLabel()
	if not timerLabel then
		return
	end
	timerLabel.Text = formatHMS(secondsUntilNextDay())
end

local function refreshFeatured()
	local reward = getReward(selectedDay)
	if not reward then
		return
	end
	local status = computeDayStatus(selectedDay, currentState)
	local rewardType = inferType(reward)
	featuredIcon.Image = iconForType(rewardType)
	featuredDayLabel.Text = "DAY " .. tostring(selectedDay)
	featuredName.Text = reward.displayName or ("Day " .. tostring(selectedDay))

	local canClaim = currentState and currentState.canClaimToday and not currentState.alreadyClaimed
	if status == "claimable" then
		featuredStatus.Text = "READY TO CLAIM"
		featuredStatus.TextColor3 = GOLD
	elseif status == "claimed" then
		featuredStatus.Text = "CLAIMED"
		featuredStatus.TextColor3 = Color3.fromRGB(90, 220, 130)
	else
		featuredStatus.Text = "LOCKED"
		featuredStatus.TextColor3 = DIM
	end

	if canClaim then
		claimButton.Text = "CLAIM REWARD"
		claimButton.BackgroundColor3 = GREEN
		claimButton.TextColor3 = WHITE
		claimButton.Active = true
	elseif currentState and currentState.alreadyClaimed then
		claimButton.Text = "CLAIMED TODAY"
		claimButton.BackgroundColor3 = Color3.fromRGB(32, 48, 40)
		claimButton.TextColor3 = DIM
		claimButton.Active = false
	else
		claimButton.Text = "KEEP YOUR STREAK"
		claimButton.BackgroundColor3 = Color3.fromRGB(32, 36, 52)
		claimButton.TextColor3 = DIM
		claimButton.Active = false
	end
end

local function refreshTrack()
	for i, node in ipairs(dayNodes) do
		local reward = getReward(i)
		local status = computeDayStatus(i, currentState)
		local bg, border = statusColor(status)
		node.frame.BackgroundColor3 = bg
		node.stroke.Color = border
		if status == "claimed" or status == "claimable" then
			node.stroke.Thickness = 2
			node.stroke.Transparency = 0.05
		else
			node.stroke.Thickness = 1.2
			node.stroke.Transparency = 0.35
		end
		if status == "claimed" then
			node.dayLabel.TextColor3 = Color3.fromRGB(90, 220, 130)
		elseif status == "claimable" then
			node.dayLabel.TextColor3 = GOLD
		else
			node.dayLabel.TextColor3 = DIM
		end
		node.icon.Image = iconForType(inferType(reward or {}))
		node.icon.ImageTransparency = status == "future" and 0.35 or 0
		node.check.Visible = status == "claimed"
		node.scale.Scale = 1
	end
end

function DailyRewardsUI.Refresh(state)
	if type(state) ~= "table" then
		return
	end
    state = table.clone(state)
    currentState = state
    -- A reset streak must not retain a previous cycle's claimed-day visuals.
    if tonumber(state.currentStreak) == 0 then
        state.currentDay = 0
    end
    if not hasRealClaim(state) then
        state.currentStreak = tonumber(state.currentStreak) or 0
		state.currentDay = 0
		state.alreadyClaimed = false
		state.canClaimToday = true
		state.lastClaimTime = 0
	end
	if streakValue then
		streakValue.Text = tostring(state.currentStreak or 0)
	end

	selectedDay = 1
	for i = 1, 7 do
		if computeDayStatus(i, state) == "claimable" then
			selectedDay = i
			break
		end
	end
	if state.alreadyClaimed == true and hasRealClaim(state) then
		selectedDay = math.clamp(tonumber(state.currentDay) or 1, 1, 7)
	end

	refreshTrack()
	refreshFeatured()
end

function DailyRewardsUI.Create(parent, initialState, callbacks)
	onClaimCb = callbacks and callbacks.onClaim or nil
	local player = Players.LocalPlayer
	local playerGui = player and (player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui"))
	if typeof(parent) == "Instance" and parent:IsA("PlayerGui") then
		playerGui = parent
	elseif typeof(parent) == "Instance" and parent:IsA("ScreenGui") then
		playerGui = parent.Parent
	end
	if not playerGui then
		warn("[DailyRewardsUI] PlayerGui missing")
		return
	end

	hideLegacyStudioGui(playerGui)

	local existing = playerGui:FindFirstChild("DailyRewardsMenu")
	if existing then
		existing:Destroy()
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DailyRewardsMenu"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 540
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1.1, 0, 1.1, 0)
	overlay.Position = UDim2.new(0.5, 0, 0.5, 0)
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.5, 0.72)
	window.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
	window.BackgroundTransparency = 0.04
	window.BorderSizePixel = 0
	window.Active = true
	window.ZIndex = 2
	window.Parent = screenGui
	corner(window, px(14))
	stroke(window, Color3.fromRGB(180, 150, 50), 1.5, 0.15)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 195))
	gradient.Rotation = 90
	gradient.Parent = window

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.4
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = window

	-- Match SideUI's Shop/Achievements/Team modal sizing, not the stall panels.
	local thisWindow = window
	local thisGui = screenGui
	local viewportConnection
	local function layoutWindow()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewportX, viewportY = camera.ViewportSize.X, camera.ViewportSize.Y
		if viewportX <= 0 or viewportY <= 0 then return end
		local portrait = viewportX < viewportY
		local widthMin = math.min(math.floor(viewportX * 0.92), 540)
		local lower = math.max(320, widthMin)
		local width = math.clamp(math.floor(viewportX * (portrait and 0.82 or 0.65)),
			lower, math.max(math.floor(viewportX * 0.86), lower))
		local heightLimit = portrait and math.floor(width * 1.1) or math.floor(viewportY * 0.8)
		local minHeight = math.max(220, math.floor(viewportY * 0.46))
		local height = math.clamp(math.min(math.floor(viewportY * 0.72), heightLimit),
			minHeight, math.max(math.floor(viewportY * 0.84), minHeight))
		-- SideUI narrows Shop/Achievements/Team by 25% after computing the base size.
		thisWindow.Position = UDim2.fromScale(0.5, 0.5)
		thisWindow.Size = UDim2.fromScale(math.max(200, math.floor(width * 0.75)) / viewportX, height / viewportY)
		-- Mirror the actual shared window: its parent is 110% screen size and
		-- Inventory uses different sizing from Shop. Don't approximate either.
		local sideUI = _G.SideUI
		local windowCorner = thisWindow:FindFirstChildOfClass("UICorner")
		if windowCorner then
			windowCorner.CornerRadius = sideUI and sideUI.GetSharedModalCornerRadius
				and sideUI.GetSharedModalCornerRadius() or UDim.new(0, px(14))
		end
		local sharedSize = sideUI and sideUI.GetSharedModalSize and sideUI.GetSharedModalSize()
		if sharedSize and sharedSize.X > 0 and sharedSize.Y > 0 then
			-- Already resolved by the shared window's aspect constraint. Applying
			-- another constraint here can shrink the copied dimensions again.
			aspect.Parent = nil
			thisWindow.Size = UDim2.fromOffset(sharedSize.X, sharedSize.Y)
		else
			aspect.Parent = thisWindow
			-- Match the shared overlay scale while SideUI is still initializing.
			thisWindow.Size = UDim2.fromScale(thisWindow.Size.X.Scale * 1.1, thisWindow.Size.Y.Scale * 1.1)
		end
		local close = thisWindow:FindFirstChild("Close")
		if close then
			local headerHeight = math.clamp(math.floor(height * 0.1), 44, 76)
			local closeSize = math.max(26, math.floor(headerHeight * 0.60))
			close.Size = UDim2.fromOffset(closeSize, closeSize)
			local closeCorner = close:FindFirstChildOfClass("UICorner")
			if sideUI and sideUI.GetSharedCloseStyle then
				local size, radius = sideUI.GetSharedCloseStyle()
				if size.X > 0 and size.Y > 0 then close.Size = UDim2.fromOffset(size.X, size.Y) end
				if closeCorner then closeCorner.CornerRadius = radius end
			elseif closeCorner then
				closeCorner.CornerRadius = UDim.new(0, px(8))
			end
		end
		local padding = thisWindow:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingTop = UDim.new(0, px(10))
			padding.PaddingBottom = UDim.new(0, px(10))
			padding.PaddingLeft = UDim.new(0, px(14))
			padding.PaddingRight = UDim.new(0, px(14))
		end
	end
	local function bindCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		viewportConnection = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutWindow)
		layoutWindow()
	end
	local cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	syncWindowLayout = layoutWindow
	local sizeConnection = RunService.RenderStepped:Connect(function()
		if thisGui.Enabled then layoutWindow() end
	end)
	thisGui.Destroying:Connect(function()
		aspect:Destroy()
		cameraConnection:Disconnect()
		sizeConnection:Disconnect()
		if viewportConnection then viewportConnection:Disconnect() end
	end)
	bindCamera()

	windowScale = Instance.new("UIScale")
	windowScale.Scale = 1
	windowScale.Parent = window

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px(10))
	pad.PaddingBottom = UDim.new(0, px(10))
	pad.PaddingLeft = UDim.new(0, px(14))
	pad.PaddingRight = UDim.new(0, px(14))
	pad.Parent = window

	local header = Instance.new("Frame")
	header.Name = "HeaderBar"
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromScale(1, 0.1)
	header.ZIndex = 3
	header.Parent = window

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(0, 0.1)
	content.Size = UDim2.fromScale(1, 0.9)
	content.ZIndex = 3
	content.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.42, 1)
	title.Position = UDim2.fromScale(0.06, 0)
	title.Font = Enum.Font.GothamBlack
	title.Text = "DAILY LOGIN"
	title.TextColor3 = GOLD
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	constrainText(title, 18, 34)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.fromScale(1, 0)
	closeBtn.Size = UDim2.fromScale(0.08, 1)
	closeBtn.BackgroundColor3 = UITheme.CLOSE_DEFAULT
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.Text = "X"
	closeBtn.TextColor3 = GOLD
	closeBtn.TextScaled = true
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 4
	closeBtn.Parent = window
	corner(closeBtn, px(8))
	stroke(closeBtn, GOLD, 1.2, 0.4)
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.Parent = closeBtn
	layoutWindow()
	constrainText(closeBtn, 14, 26)
	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = UITheme.CLOSE_HOVER
		closeBtn.TextColor3 = WHITE
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = UITheme.CLOSE_DEFAULT
		closeBtn.TextColor3 = GOLD
	end)
	closeBtn.Activated:Connect(function()
		local mc = _G.SideUI and _G.SideUI.MenuController
		if mc and mc.CloseMenu then
			mc.CloseMenu("DailyRewards")
		else
			DailyRewardsUI.Close(false)
		end
	end)

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "NextDayTimer"
	timerLabel.BackgroundTransparency = 1
	-- Keep the countdown with the claim action instead of competing with the title.
	timerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	timerLabel.Position = UDim2.fromScale(0.5, 0.965)
	timerLabel.Size = UDim2.fromScale(0.42, 0.06)
	timerLabel.FontFace = Font.new(
		"rbxasset://fonts/families/SourceSansPro.json",
		Enum.FontWeight.Bold,
		Enum.FontStyle.Normal
	)
	timerLabel.Text = "00:00:00"
	timerLabel.TextColor3 = GOLD
	timerLabel.TextScaled = true
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.ZIndex = 3
	timerLabel.Parent = content
	constrainText(timerLabel, 16, 26)
	updateTimerLabel()
	timerToken += 1
	local thisTimer = timerToken
	task.spawn(function()
		while thisTimer == timerToken and timerLabel and timerLabel.Parent do
			updateTimerLabel()
			task.wait(1)
		end
	end)

	local streakChip = Instance.new("Frame")
	streakChip.Name = "StreakChip"
	streakChip.BackgroundColor3 = Color3.fromRGB(32, 28, 14)
	streakChip.Size = UDim2.fromScale(0.34, 0.08)
	streakChip.Position = UDim2.fromScale(0, 0)
	streakChip.ZIndex = 3
	streakChip.Parent = content
	corner(streakChip, px(8))
	stroke(streakChip, GOLD_DIM, 1.2, 0.35)

	local streakCaption = Instance.new("TextLabel")
	streakCaption.BackgroundTransparency = 1
	streakCaption.Size = UDim2.fromScale(0.58, 1)
	streakCaption.Position = UDim2.fromScale(0.06, 0)
	streakCaption.Font = Enum.Font.GothamBold
	streakCaption.Text = "STREAK"
	streakCaption.TextColor3 = GOLD
	streakCaption.TextScaled = true
	streakCaption.TextXAlignment = Enum.TextXAlignment.Left
	streakCaption.ZIndex = 4
	streakCaption.Parent = streakChip
	constrainText(streakCaption, 10, 16)

	streakValue = Instance.new("TextLabel")
	streakValue.Name = "StreakValue"
	streakValue.BackgroundTransparency = 1
	streakValue.AnchorPoint = Vector2.new(1, 0)
	streakValue.Position = UDim2.fromScale(0.94, 0)
	streakValue.Size = UDim2.fromScale(0.34, 1)
	streakValue.Font = Enum.Font.GothamBlack
	streakValue.Text = "0"
	streakValue.TextColor3 = WHITE
	streakValue.TextScaled = true
	streakValue.TextXAlignment = Enum.TextXAlignment.Right
	streakValue.ZIndex = 4
	streakValue.Parent = streakChip
	constrainText(streakValue, 12, 22)

	local featured = Instance.new("Frame")
	featured.Name = "Featured"
	featured.BackgroundColor3 = NAVY_LIGHT
	featured.Size = UDim2.fromScale(1, 0.43)
	featured.Position = UDim2.fromScale(0, 0.1)
	featured.ZIndex = 3
	featured.Parent = content
	corner(featured, px(14))
	stroke(featured, GOLD_DIM, 1.4, 0.45)

	local featuredPad = Instance.new("UIPadding")
	featuredPad.PaddingTop = UDim.new(0.08, 0)
	featuredPad.PaddingBottom = UDim.new(0.08, 0)
	featuredPad.PaddingLeft = UDim.new(0.04, 0)
	featuredPad.PaddingRight = UDim.new(0.04, 0)
	featuredPad.Parent = featured

	local iconWell = Instance.new("Frame")
	iconWell.Name = "IconWell"
	iconWell.BackgroundColor3 = Color3.fromRGB(14, 16, 28)
	iconWell.Size = UDim2.fromScale(0.26, 0.84)
	iconWell.Position = UDim2.fromScale(0.02, 0.08)
	iconWell.ZIndex = 4
	iconWell.Parent = featured
	corner(iconWell, px(12))
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.Parent = iconWell

	featuredIcon = Instance.new("ImageLabel")
	featuredIcon.Name = "Icon"
	featuredIcon.BackgroundTransparency = 1
	featuredIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	featuredIcon.Position = UDim2.fromScale(0.5, 0.5)
	featuredIcon.Size = UDim2.fromScale(0.72, 0.72)
	featuredIcon.ScaleType = Enum.ScaleType.Fit
	featuredIcon.ZIndex = 5
	featuredIcon.Parent = iconWell

	featuredDayLabel = Instance.new("TextLabel")
	featuredDayLabel.Name = "DayLabel"
	featuredDayLabel.BackgroundTransparency = 1
	featuredDayLabel.Position = UDim2.fromScale(0.34, 0.04)
	featuredDayLabel.Size = UDim2.new(0.64, 0, 0.18, 0)
	featuredDayLabel.Font = Enum.Font.GothamBold
	featuredDayLabel.Text = "DAY 1"
	featuredDayLabel.TextColor3 = GOLD
	featuredDayLabel.TextScaled = true
	featuredDayLabel.TextXAlignment = Enum.TextXAlignment.Left
	featuredDayLabel.ZIndex = 5
	featuredDayLabel.Parent = featured
	constrainText(featuredDayLabel, 12, 20)

	featuredStatus = Instance.new("TextLabel")
	featuredStatus.Name = "Status"
	featuredStatus.BackgroundTransparency = 1
	featuredStatus.Position = UDim2.fromScale(0.34, 0.22)
	featuredStatus.Size = UDim2.new(0.64, 0, 0.14, 0)
	featuredStatus.Font = Enum.Font.GothamBold
	featuredStatus.Text = "LOCKED"
	featuredStatus.TextColor3 = DIM
	featuredStatus.TextScaled = true
	featuredStatus.TextXAlignment = Enum.TextXAlignment.Left
	featuredStatus.ZIndex = 5
	featuredStatus.Parent = featured
	constrainText(featuredStatus, 10, 16)

	featuredName = Instance.new("TextLabel")
	featuredName.Name = "RewardName"
	featuredName.BackgroundTransparency = 1
	featuredName.Position = UDim2.fromScale(0.34, 0.38)
	featuredName.Size = UDim2.new(0.64, 0, 0.52, 0)
	featuredName.Font = Enum.Font.GothamBlack
	featuredName.Text = "100 Coins"
	featuredName.TextColor3 = WHITE
	featuredName.TextScaled = true
	featuredName.TextXAlignment = Enum.TextXAlignment.Left
	featuredName.TextYAlignment = Enum.TextYAlignment.Top
	featuredName.ZIndex = 5
	featuredName.Parent = featured
	constrainText(featuredName, 16, 30)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.Size = UDim2.fromScale(1, 0.23)
	track.Position = UDim2.fromScale(0, 0.56)
	track.ZIndex = 3
	track.Parent = content

	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	trackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trackLayout.Padding = UDim.new(0.012, 0)
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Parent = track

	dayNodes = {}
	for i = 1, 7 do
		local cell = Instance.new("TextButton")
		cell.Name = "Day" .. i
		cell.AutoButtonColor = false
		cell.Text = ""
		cell.BackgroundColor3 = CARD
		cell.BorderSizePixel = 0
		cell.Size = UDim2.fromScale(0.125, 0.92)
		cell.LayoutOrder = i
		cell.ZIndex = 4
		cell.Parent = track
		corner(cell, px(10))
		local cellStroke = stroke(cell, STROKE, 1.2, 0.35)
		local cellScale = Instance.new("UIScale")
		cellScale.Parent = cell

		local dayLabel = Instance.new("TextLabel")
		dayLabel.BackgroundTransparency = 1
		dayLabel.Size = UDim2.new(1, 0, 0.28, 0)
		dayLabel.Position = UDim2.fromScale(0, 0.06)
		dayLabel.Font = Enum.Font.GothamBold
		dayLabel.Text = tostring(i)
		dayLabel.TextColor3 = GOLD
		dayLabel.TextScaled = true
		dayLabel.ZIndex = 5
		dayLabel.Parent = cell
		constrainText(dayLabel, 9, 16)

		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, 0.34)
		icon.Size = UDim2.fromScale(0.5, 0.42)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 5
		icon.Parent = cell

		local check = Instance.new("TextLabel")
		check.Name = "Check"
		check.BackgroundTransparency = 1
		check.Size = UDim2.new(1, 0, 0.22, 0)
		check.Position = UDim2.fromScale(0, 0.74)
		check.Font = Enum.Font.GothamBlack
		check.Text = "✓"
		check.TextColor3 = Color3.fromRGB(90, 220, 130)
		check.TextScaled = true
		check.Visible = false
		check.ZIndex = 6
		check.Parent = cell
		constrainText(check, 8, 14)

		dayNodes[i] = {
			frame = cell,
			stroke = cellStroke,
			scale = cellScale,
			dayLabel = dayLabel,
			icon = icon,
			check = check,
		}

		cell.Activated:Connect(function()
			selectedDay = i
			refreshTrack()
			refreshFeatured()
		end)
	end

	claimButton = Instance.new("TextButton")
	claimButton.Name = "ClaimButton"
	claimButton.AutoButtonColor = false
	claimButton.Size = UDim2.fromScale(1, 0.11)
	claimButton.Position = UDim2.fromScale(0, 0.81)
	claimButton.BackgroundColor3 = GREEN
	claimButton.BorderSizePixel = 0
	claimButton.Font = Enum.Font.GothamBlack
	claimButton.Text = "CLAIM REWARD"
	claimButton.TextColor3 = WHITE
	claimButton.TextScaled = true
	claimButton.ZIndex = 4
	claimButton.Parent = content
	corner(claimButton, px(12))
	constrainText(claimButton, 14, 24)
	claimButton.Activated:Connect(function()
		if not (currentState and currentState.canClaimToday and not currentState.alreadyClaimed) then
			return
		end
		if onClaimCb then
			onClaimCb()
		end
	end)

	DailyRewardsUI.Refresh({
		currentDay = 0,
		currentStreak = 0,
		lastClaimTime = 0,
		alreadyClaimed = false,
		canClaimToday = true,
		rewards = {},
	})
	if initialState then
		DailyRewardsUI.Refresh(initialState)
	end

	return DailyRewardsUI
end

local function showSharedOverlay()
	local sideUI = _G.SideUI
	if sideUI and sideUI.SetSharedModalOverlay then
		sideUI.SetSharedModalOverlay(true, true)
	end
end

local function hideSharedOverlay()
	local sideUI = _G.SideUI
	if sideUI and sideUI.SetSharedModalOverlay then
		sideUI.SetSharedModalOverlay(false)
	end
end

local function restoreSharedWindow()
	local sideUI = _G.SideUI
	if sideUI and sideUI.RestoreSharedModalWindow then
		sideUI.RestoreSharedModalWindow()
	end
end

function DailyRewardsUI.Open(sameGroup)
	if not screenGui or not window then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	if playerGui then
		hideLegacyStudioGui(playerGui)
	end
	isOpen = true
	if syncWindowLayout then syncWindowLayout() end
	screenGui.Enabled = true
	if overlay then
		overlay.Visible = false
	end
	showSharedOverlay()
	if sameGroup then
		windowScale.Scale = 1
	else
		windowScale.Scale = 0.94
		TweenService:Create(windowScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

function DailyRewardsUI.Close(sameGroup)
	if not screenGui then
		return
	end
	isOpen = false
	screenGui.Enabled = false
	if overlay then
		overlay.Visible = false
	end
	if sameGroup then
		restoreSharedWindow()
	else
		hideSharedOverlay()
	end
end

function DailyRewardsUI.IsOpen()
	return isOpen == true
end

function DailyRewardsUI.PlayClaimAnimation(dayIndex)
	local node = dayNodes[dayIndex]
	if not node then
		return
	end
	TweenService:Create(node.scale, TweenInfo.new(0.12), { Scale = 1.16 }):Play()
	task.delay(0.16, function()
		if node.scale then
			TweenService:Create(node.scale, TweenInfo.new(0.2), { Scale = (selectedDay == dayIndex) and 1.08 or 1 }):Play()
		end
	end)
end

return DailyRewardsUI
