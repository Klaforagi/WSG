local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))
local AlertBannerStyle = require(ReplicatedStorage:WaitForChild("AlertBannerStyle"))
local TopHudStack = require(ReplicatedStorage:WaitForChild("TopHudStack"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlagStatusGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Parent = playerGui

local FlagStatus = ReplicatedStorage:WaitForChild("FlagStatus")

local messageQueue = {}
local processing = false

local function colorToHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local GOLD_HEX = colorToHex(AlertBannerStyle.TextColor)

local function teamHex(teamName)
	return colorToHex(AlertBannerStyle.TeamColor(teamName))
end

local function escapeRichText(text)
	return tostring(text or "")
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
end

local function playLocalSound(soundName)
	if not soundName then
		return
	end
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	if not sounds then
		return
	end
	local flagFolder = sounds:FindFirstChild("Flag")
	if not flagFolder then
		return
	end
	local s = flagFolder:FindFirstChild(soundName)
	if not s or not s:IsA("Sound") then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local snd = s:Clone()
	snd.Parent = cam
	snd:Play()
	task.delay((snd.TimeLength or 3) + 0.5, function()
		if snd and snd.Parent then
			snd:Destroy()
		end
	end)
end

local function fillAvatar(image, userId)
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48
			)
		end)
		if ok and url and image and image.Parent then
			image.Image = url
		end
	end)
end

local function buildRichText(item)
	if item.eventType == "event" then
		return escapeRichText(item.message or "")
	end

	local pHex = teamHex(item.playerTeamName)
	local fHex = teamHex(item.flagTeamName)
	local teamWord = escapeRichText(TeamDisplayNames.Get(item.flagTeamName))
	local playerName = escapeRichText(item.playerName or "")

	if item.eventType == "pickup" then
		return string.format(
			"<font color='%s'>%s</font><font color='%s'> picked up the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
			pHex, playerName, GOLD_HEX, fHex, teamWord, GOLD_HEX
		)
	elseif item.eventType == "captured" then
		return string.format(
			"<font color='%s'>%s</font><font color='%s'> captured the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
			pHex, playerName, GOLD_HEX, fHex, teamWord, GOLD_HEX
		)
	elseif item.eventType == "returned" then
		if playerName ~= "" then
			return string.format(
				"<font color='%s'>%s</font><font color='%s'> returned the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
				pHex, playerName, GOLD_HEX, fHex, teamWord, GOLD_HEX
			)
		end
		return string.format(
			"<font color='%s'>The </font><font color='%s'>%s</font><font color='%s'> Flag has been returned!</font>",
			GOLD_HEX, fHex, teamWord, GOLD_HEX
		)
	elseif item.eventType == "crowned" then
		return string.format(
			"<font color='%s'>%s</font><font color='%s'> has been crowned King!</font>",
			pHex, playerName, GOLD_HEX
		)
	elseif item.eventType == "slain_king" then
		return string.format(
			"<font color='%s'>%s</font><font color='%s'> has slain the King</font>",
			pHex, playerName, GOLD_HEX
		)
	end
	return playerName
end

local function displayItem(item)
	local isEvent = item.eventType == "event"
	local textSize = isEvent and AlertBannerStyle.EventTextSize or AlertBannerStyle.FlagTextSize
	local avatarSize = AlertBannerStyle.AvatarSize
	local showAvatar = (not isEvent)
		and type(item.userId) == "number"
		and item.userId > 0
		and item.playerName
		and item.playerName ~= ""

	local panel = Instance.new("Frame")
	panel.Name = "FlagMsgPanel"
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = TopHudStack.GetAlertPosition()
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ZIndex = 100
	panel.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = panel

	local avatarImage = nil
	if showAvatar then
		local avWrap = Instance.new("Frame")
		avWrap.Name = "Avatar"
		avWrap.LayoutOrder = 1
		avWrap.Size = UDim2.fromOffset(avatarSize, avatarSize)
		avWrap.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		avWrap.BackgroundTransparency = 0.25
		avWrap.BorderSizePixel = 0
		avWrap.ZIndex = 101
		avWrap.Parent = panel

		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avWrap

		local avStroke = Instance.new("UIStroke")
		avStroke.Color = AlertBannerStyle.TextColor
		avStroke.Thickness = 1.4
		avStroke.Transparency = 0.25
		avStroke.Parent = avWrap

		avatarImage = Instance.new("ImageLabel")
		avatarImage.BackgroundTransparency = 1
		avatarImage.Size = UDim2.fromScale(1, 1)
		avatarImage.ImageTransparency = 1
		avatarImage.ZIndex = 102
		avatarImage.Parent = avWrap

		local imgCorner = Instance.new("UICorner")
		imgCorner.CornerRadius = UDim.new(1, 0)
		imgCorner.Parent = avatarImage

		fillAvatar(avatarImage, item.userId)
	end

	local label = Instance.new("TextLabel")
	label.Name = "FlagMsg"
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.RichText = true
	label.Font = AlertBannerStyle.Font
	label.TextSize = textSize
	label.TextColor3 = AlertBannerStyle.TextColor
	label.TextXAlignment = showAvatar and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 101
	label.Text = buildRichText(item)
	label.TextTransparency = 1
	label.Parent = panel
	local lblStroke = AlertBannerStyle.ApplyTextStroke(label)
	lblStroke.Transparency = 1

	local function snapAlertY()
		if panel and panel.Parent then
			panel.Position = TopHudStack.GetAlertPosition()
		end
	end
	snapAlertY()
	task.defer(snapAlertY)

	TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
	TweenService:Create(lblStroke, TweenInfo.new(0.18), { Transparency = AlertBannerStyle.StrokeTransparency }):Play()
	if avatarImage then
		TweenService:Create(avatarImage, TweenInfo.new(0.18), { ImageTransparency = 0 }):Play()
	end

	task.wait(AlertBannerStyle.HoldSeconds)
	if panel and panel.Parent then
		local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(lblStroke, fadeInfo, { Transparency = 1 }):Play()
		if avatarImage then
			TweenService:Create(avatarImage, fadeInfo, { ImageTransparency = 1 }):Play()
		end
		task.wait(0.4)
		if panel and panel.Parent then
			panel:Destroy()
		end
	end
end

local function processQueue()
	if processing then
		return
	end
	processing = true
	task.spawn(function()
		while #messageQueue > 0 do
			local item = table.remove(messageQueue, 1)
			displayItem(item)
		end
		processing = false
	end)
end

FlagStatus.OnClientEvent:Connect(function(eventType, playerName, playerTeamName, flagTeamName, _accentColor, userId)
	if eventType == "playSound" then
		playLocalSound(playerName)
		return
	end

	if eventType == "pickup" or eventType == "returned" or eventType == "captured"
		or eventType == "crowned" or eventType == "slain_king" then
		table.insert(messageQueue, {
			eventType = eventType,
			playerName = playerName,
			playerTeamName = playerTeamName,
			flagTeamName = flagTeamName,
			userId = userId,
		})
		processQueue()
	elseif eventType == "event" then
		table.insert(messageQueue, {
			eventType = eventType,
			message = playerName,
		})
		processQueue()
	end
end)

TopHudStack.OnLayoutChanged(function()
	for _, child in ipairs(screenGui:GetChildren()) do
		if child.Name == "FlagMsgPanel" then
			child.Position = TopHudStack.GetAlertPosition()
		end
	end
end)
