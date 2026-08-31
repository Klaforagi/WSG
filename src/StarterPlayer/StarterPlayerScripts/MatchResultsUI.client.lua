local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NAVY = Color3.fromRGB(10, 12, 26)
local NAVY_PANEL = Color3.fromRGB(16, 18, 34)
local NAVY_ROW = Color3.fromRGB(8, 10, 22)
local NAVY_ROW_ALT = Color3.fromRGB(12, 14, 28)
local GOLD = Color3.fromRGB(255, 214, 70)
local GOLD_DIM = Color3.fromRGB(196, 164, 72)
local BLUE_BAR = Color3.fromRGB(28, 46, 102)
local RED_BAR = Color3.fromRGB(92, 22, 26)
local WHITE = Color3.fromRGB(236, 236, 242)

local COLS = {
	{ key = "level", header = "Lvl", width = 0.08, align = Enum.TextXAlignment.Center },
	{ key = "avatar", header = "", width = 0.07, align = Enum.TextXAlignment.Center },
	{ key = "name", header = "Name", width = 0.25, align = Enum.TextXAlignment.Left },
	{ key = "score", header = "Score", width = 0.12, align = Enum.TextXAlignment.Center, gold = true },
	{ key = "eliminations", header = "Elims", width = 0.12, align = Enum.TextXAlignment.Center },
	{ key = "deaths", header = "Deaths", width = 0.12, align = Enum.TextXAlignment.Center },
	{ key = "captures", header = "Caps", width = 0.12, align = Enum.TextXAlignment.Center },
	{ key = "returns", header = "Rets", width = 0.12, align = Enum.TextXAlignment.Center },
}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, trans)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = props.font or Enum.Font.GothamBold
	l.Text = props.text or ""
	l.TextColor3 = props.color or WHITE
	l.TextSize = props.textSize or 16
	l.TextScaled = props.scaled == true
	l.TextXAlignment = props.xAlign or Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Size = props.size or UDim2.new(1, 0, 1, 0)
	l.Position = props.pos or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = props.anchor or Vector2.new(0, 0)
	l.Parent = parent
	return l
end

local function hairline(parent, y, widthScale)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, y)
	line.Size = UDim2.new(widthScale or 0.42, 0, 0, 1)
	line.BackgroundColor3 = GOLD
	line.BackgroundTransparency = 0.45
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

local function diamond(parent, pos)
	local d = label(parent, {
		text = "◆",
		textSize = 10,
		color = GOLD,
		pos = pos,
		anchor = Vector2.new(0.5, 0.5),
		size = UDim2.fromOffset(16, 16),
	})
	d.TextTransparency = 0.15
	return d
end

local function fillAvatar(image, userId, thumbSize)
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				thumbSize or Enum.ThumbnailSize.Size48x48
			)
		end)
		if ok and url and image and image.Parent then
			image.Image = url
		end
	end)
end

local function teamName(key)
	if TeamDisplayNames and TeamDisplayNames.GetUpper then
		return TeamDisplayNames.GetUpper(key)
	end
	return key == "Red" and "BARBARIANS" or "KNIGHTS"
end

local function clearExisting()
	local old = playerGui:FindFirstChild("MatchResultsUI")
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
end

local function buildHeaderRow(parent)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 22)
	row.Position = UDim2.new(0, 4, 0, 0)
	row.Parent = parent

	local x = 0
	for _, col in ipairs(COLS) do
		if col.header ~= "" then
			local l = label(row, {
				text = col.header,
				textSize = 12,
				color = GOLD_DIM,
				xAlign = col.align,
				size = UDim2.new(col.width, 0, 1, 0),
				pos = UDim2.new(x, 0, 0, 0),
			})
			l.Font = Enum.Font.GothamMedium
			l.TextTruncate = Enum.TextTruncate.None
			l.TextScaled = true
			local constraint = Instance.new("UITextSizeConstraint")
			constraint.MinTextSize = 10
			constraint.MaxTextSize = 12
			constraint.Parent = l
		end
		x += col.width
	end
	return row
end

local function buildPlayerRow(entry, isLocal, index)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = isLocal and Color3.fromRGB(78, 62, 16)
		or (index % 2 == 0 and NAVY_ROW_ALT or NAVY_ROW)
	row.BorderSizePixel = 0
	corner(row, 6)
	if isLocal then
		stroke(row, GOLD, 1.5)
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = row

	local x = 0
	for _, col in ipairs(COLS) do
		if col.key == "avatar" then
			local av = Instance.new("ImageLabel")
			av.BackgroundTransparency = 1
			av.Size = UDim2.fromOffset(28, 28)
			av.AnchorPoint = Vector2.new(0.5, 0.5)
			av.Position = UDim2.new(x + col.width * 0.5, 0, 0.5, 0)
			av.Parent = row
			corner(av, 14)
			stroke(av, isLocal and GOLD or Color3.fromRGB(40, 44, 64), 1)
			fillAvatar(av, entry.userId, Enum.ThumbnailSize.Size48x48)
		else
			local text
			if col.key == "name" then
				text = entry.displayName or entry.name or ""
			else
				text = tostring(entry[col.key] or 0)
			end
			label(row, {
				text = text,
				textSize = 14,
				color = col.gold and GOLD or WHITE,
				xAlign = col.align,
				size = UDim2.new(col.width, 0, 1, 0),
				pos = UDim2.new(x, 0, 0, 0),
			})
		end
		x += col.width
	end

	return row
end

local function buildTeamColumn(parent, teamKey, headerColor, entries, localUserId)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.492, 0, 1, 0)
	panel.BackgroundTransparency = 1
	panel.Parent = parent

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 34)
	header.BackgroundColor3 = headerColor
	header.BorderSizePixel = 0
	header.Parent = panel
	corner(header, 6)
	stroke(header, GOLD, 1, 0.72)

	label(header, {
		text = teamName(teamKey),
		font = Enum.Font.GothamBlack,
		textSize = 16,
		color = WHITE,
		xAlign = Enum.TextXAlignment.Center,
		size = UDim2.new(1, 0, 1, 0),
	})

	local headerRowHolder = Instance.new("Frame")
	headerRowHolder.BackgroundTransparency = 1
	headerRowHolder.Size = UDim2.new(1, 0, 0, 22)
	headerRowHolder.Position = UDim2.new(0, 0, 0, 38)
	headerRowHolder.Parent = panel
	buildHeaderRow(headerRowHolder)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 0, 0, 62)
	scroll.Size = UDim2.new(1, 0, 1, -62)
	scroll.ScrollBarThickness = #entries > 6 and 6 or 0
	scroll.ScrollBarImageColor3 = GOLD_DIM
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingEnabled = #entries > 6
	scroll.Active = true
	scroll.Parent = panel

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = scroll

	for i, entry in ipairs(entries) do
		local row = buildPlayerRow(entry, entry.userId == localUserId, i)
		row.LayoutOrder = i
		row.Parent = scroll
	end

	return panel
end

local function showMatchResults(payload)
	if typeof(payload) ~= "table" then
		return
	end

	clearExisting()

	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchResultsUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Selectable = false
	dim.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.62, 0.58)
	card.BackgroundColor3 = NAVY
	card.BorderSizePixel = 0
	card.Active = true
	card.Parent = gui
	corner(card, 12)
	stroke(card, GOLD, 2)

	local limiter = Instance.new("UISizeConstraint")
	limiter.MinSize = Vector2.new(720, 420)
	limiter.MaxSize = Vector2.new(1100, 680)
	limiter.Parent = card

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.72
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = card

	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(0.52, 0.48)
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(0.62, 0.58),
	}):Play()

	local winnerKey = payload.winner or "Blue"
	label(card, {
		text = teamName(winnerKey) .. " VICTORY",
		font = Enum.Font.GothamBlack,
		textSize = 30,
		color = GOLD,
		pos = UDim2.new(0.5, 0, 0, 16),
		anchor = Vector2.new(0.5, 0),
		size = UDim2.new(0.8, 0, 0, 34),
	})

	local blueScore = (payload.score and payload.score.Blue) or 0
	local redScore = (payload.score and payload.score.Red) or 0
	label(card, {
		text = string.format("%d   —   %d", blueScore, redScore),
		font = Enum.Font.GothamBlack,
		textSize = 20,
		color = GOLD,
		pos = UDim2.new(0.5, 0, 0, 50),
		anchor = Vector2.new(0.5, 0),
		size = UDim2.new(0.5, 0, 0, 24),
	})

	hairline(card, 80, 0.28)
	diamond(card, UDim2.new(0.5, 0, 0, 80))

	-- MVP chip
	local mvpChip = Instance.new("Frame")
	mvpChip.AnchorPoint = Vector2.new(0.5, 0)
	mvpChip.Position = UDim2.new(0.5, 0, 0, 92)
	mvpChip.Size = UDim2.fromOffset(340, 52)
	mvpChip.BackgroundColor3 = NAVY_PANEL
	mvpChip.Parent = card
	corner(mvpChip, 8)
	stroke(mvpChip, GOLD, 1.4, 0.25)

	local mvpAvWrap = Instance.new("Frame")
	mvpAvWrap.BackgroundColor3 = Color3.fromRGB(24, 22, 12)
	mvpAvWrap.Size = UDim2.fromOffset(40, 40)
	mvpAvWrap.Position = UDim2.new(0, 10, 0.5, 0)
	mvpAvWrap.AnchorPoint = Vector2.new(0, 0.5)
	mvpAvWrap.Parent = mvpChip
	corner(mvpAvWrap, 20)
	stroke(mvpAvWrap, GOLD, 1.2)

	local mvpAv = Instance.new("ImageLabel")
	mvpAv.BackgroundTransparency = 1
	mvpAv.Size = UDim2.fromScale(1, 1)
	mvpAv.Parent = mvpAvWrap
	corner(mvpAv, 20)

	local mvpName = label(mvpChip, {
		text = "—",
		font = Enum.Font.GothamBlack,
		textSize = 18,
		color = GOLD,
		xAlign = Enum.TextXAlignment.Left,
		pos = UDim2.new(0, 62, 0, 0),
		size = UDim2.new(0.48, 0, 1, 0),
	})

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -10, 0.5, 0)
	badge.Size = UDim2.fromOffset(86, 28)
	badge.BackgroundColor3 = Color3.fromRGB(48, 38, 10)
	badge.Parent = mvpChip
	corner(badge, 6)
	stroke(badge, GOLD, 1)

	label(badge, {
		text = "◆  MVP",
		font = Enum.Font.GothamBlack,
		textSize = 13,
		color = GOLD,
	})

	if payload.mvpUserId then
		for _, p in ipairs(payload.players or {}) do
			if p.userId == payload.mvpUserId then
				mvpName.Text = p.displayName or p.name or "MVP"
				fillAvatar(mvpAv, p.userId, Enum.ThumbnailSize.Size48x48)
				break
			end
		end
	end

	local cols = Instance.new("Frame")
	cols.BackgroundTransparency = 1
	cols.Position = UDim2.new(0, 18, 0, 158)
	cols.Size = UDim2.new(1, -36, 1, -176)
	cols.Parent = card

	local leftEntries, rightEntries = {}, {}
	for _, p in ipairs(payload.players or {}) do
		if p.team == "Blue" and #leftEntries < 8 then
			table.insert(leftEntries, p)
		elseif p.team == "Red" and #rightEntries < 8 then
			table.insert(rightEntries, p)
		end
	end

	local left = buildTeamColumn(cols, "Blue", BLUE_BAR, leftEntries, player.UserId)
	left.Position = UDim2.fromScale(0, 0)

	local right = buildTeamColumn(cols, "Red", RED_BAR, rightEntries, player.UserId)
	right.Position = UDim2.fromScale(0.508, 0)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.Position = UDim2.new(1, -14, 0, 14)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = GOLD
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = card
	corner(closeBtn, 8)
	stroke(closeBtn, GOLD, 1.2)

	closeBtn.Activated:Connect(function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

local function bindRemote()
	local rem = ReplicatedStorage:FindFirstChild("MatchResults")
	if rem and rem:IsA("RemoteEvent") then
		rem.OnClientEvent:Connect(function(payload)
			pcall(showMatchResults, payload)
		end)
		return true
	end
	return false
end

if not bindRemote() then
	task.spawn(function()
		local rem = ReplicatedStorage:WaitForChild("MatchResults", 8)
		if rem and rem:IsA("RemoteEvent") then
			rem.OnClientEvent:Connect(function(payload)
				pcall(showMatchResults, payload)
			end)
		end
	end)
end