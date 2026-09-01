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

local GOLD_CHIP = Color3.fromRGB(24, 22, 12)
local GOLD_BADGE = Color3.fromRGB(48, 38, 10)

local THEMES = {
	Blue = {
		cardBg = Color3.fromRGB(8, 14, 38),
		cardStroke = Color3.fromRGB(72, 128, 230),
		accent = Color3.fromRGB(90, 148, 255),
		closeBg = Color3.fromRGB(16, 26, 58),
	},
	Red = {
		cardBg = Color3.fromRGB(43, 0, 0),
		cardStroke = Color3.fromRGB(210, 72, 72),
		accent = Color3.fromRGB(230, 86, 86),
		closeBg = Color3.fromRGB(50, 16, 20),
	},
}

-- Designed at this width; height follows content. Uniformly scaled to fit the viewport.
local DESIGN_WIDTH = 1100
local FIT_SCALE = 0.75
local PLAYER_ROW_HEIGHT = 42
local PLAYER_ROW_GAP = 6

local MAP_DISPLAY_NAMES = {
	thepit = "The Pit",
	forest = "Forest",
	wintergate = "Frozen Lake",
	frozenlake = "Frozen Lake",
}

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

local function hairline(parent, y, widthScale, color)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, y)
	line.Size = UDim2.new(widthScale or 0.42, 0, 0, 1)
	line.BackgroundColor3 = color or GOLD
	line.BackgroundTransparency = 0.35
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

local function diamond(parent, pos, color)
	local d = label(parent, {
		text = "◆",
		textSize = 10,
		color = color or GOLD,
		pos = pos,
		anchor = Vector2.new(0.5, 0.5),
		size = UDim2.fromOffset(16, 16),
	})
	d.TextTransparency = 0.1
	return d
end

local function themeFor(winnerKey)
	return THEMES[winnerKey] or THEMES.Blue
end

local function badgeColorForTeam(teamKey)
	if teamKey == "Red" then
		return RED_BAR
	end
	if teamKey == "Blue" then
		return BLUE_BAR
	end
	return GOLD_BADGE
end

local function buildScorePill(parent, value, teamColor, posScale, widthScale)
	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = teamColor
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(widthScale or 0.22, 0, 1, 0)
	pill.Position = UDim2.fromScale(posScale, 0)
	pill.Parent = parent
	corner(pill, 8)
	stroke(pill, Color3.fromRGB(255, 255, 255), 1.15, 0.72)

	local valueLabel = label(pill, {
		text = tostring(value),
		font = Enum.Font.GothamBlack,
		textSize = 22,
		color = WHITE,
		scaled = true,
	})
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 14
	constraint.MaxTextSize = 22
	constraint.Parent = valueLabel
	return pill
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

local function pickStatLeader(players, key)
	local ties = {}
	local best = nil
	for _, entry in ipairs(players or {}) do
		local value = tonumber(entry[key]) or 0
		if best == nil or value > best then
			best = value
			ties = { entry }
		elseif value == best then
			table.insert(ties, entry)
		end
	end
	if #ties == 0 then
		return nil, 0
	end
	if #ties > 1 then
		return ties[math.random(1, #ties)], best or 0
	end
	return ties[1], best or 0
end

local function buildAwardChip(parent, badgeText, entry)
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = GOLD_CHIP
	chip.BorderSizePixel = 0
	chip.Size = UDim2.new(0.485, 0, 1, 0)
	chip.Parent = parent
	corner(chip, 8)
	stroke(chip, GOLD, 1.4, 0.25)

	local avWrap = Instance.new("Frame")
	avWrap.BackgroundColor3 = GOLD_CHIP
	avWrap.Size = UDim2.fromOffset(40, 40)
	avWrap.Position = UDim2.new(0, 10, 0.5, 0)
	avWrap.AnchorPoint = Vector2.new(0, 0.5)
	avWrap.Parent = chip
	corner(avWrap, 20)
	stroke(avWrap, GOLD, 1.2)

	local av = Instance.new("ImageLabel")
	av.BackgroundTransparency = 1
	av.Size = UDim2.fromScale(1, 1)
	av.Parent = avWrap
	corner(av, 20)

	local nameLabel = label(chip, {
		text = "—",
		font = Enum.Font.GothamBlack,
		textSize = 16,
		color = GOLD,
		xAlign = Enum.TextXAlignment.Left,
		pos = UDim2.new(0, 58, 0, 0),
		size = UDim2.new(1, -180, 1, 0),
	})

	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -10, 0.5, 0)
	badge.Size = UDim2.fromOffset(112, 28)
	badge.BackgroundColor3 = badgeColorForTeam(entry and entry.team)
	badge.Parent = chip
	corner(badge, 6)
	stroke(badge, GOLD, 1)

	label(badge, {
		text = badgeText,
		font = Enum.Font.GothamBlack,
		textSize = 11,
		color = WHITE,
	})

	if entry then
		nameLabel.Text = entry.displayName or entry.name or "—"
		if entry.userId then
			fillAvatar(av, entry.userId, Enum.ThumbnailSize.Size48x48)
		end
	end

	return chip
end

local function teamName(key)
	if TeamDisplayNames and TeamDisplayNames.GetUpper then
		return TeamDisplayNames.GetUpper(key)
	end
	return key == "Red" and "BARBARIANS" or "KNIGHTS"
end

local function formatMapName(raw)
	if type(raw) ~= "string" then
		return "Unknown Map"
	end
	local trimmed = raw:match("^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return "Unknown Map"
	end

	local compact = string.lower(trimmed):gsub("[%s_%-]", "")
	if MAP_DISPLAY_NAMES[compact] then
		return MAP_DISPLAY_NAMES[compact]
	end

	local spaced = trimmed:gsub("(%l)(%u)", "%1 %2"):gsub("[_%-]+", " ")
	spaced = spaced:gsub("(%S)(%S*)", function(first, rest)
		return string.upper(first) .. string.lower(rest)
	end)
	return spaced
end

local function getViewportSize()
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 1 and cam.ViewportSize.Y > 1 then
		return cam.ViewportSize.X, cam.ViewportSize.Y
	end
	return 1920, 1080
end

local function getFitScale(contentHeight)
	local vw, vh = getViewportSize()
	local height = tonumber(contentHeight) or 0
	if height < 1 then
		height = 400
	end
	local scale = math.min((vw * 0.94) / DESIGN_WIDTH, (vh * 0.88) / height, FIT_SCALE)
	if scale ~= scale then
		scale = FIT_SCALE
	end
	return math.clamp(scale, 0.22, FIT_SCALE)
end

local function listContentHeight(count)
	if count <= 0 then
		return 0
	end
	return count * PLAYER_ROW_HEIGHT + math.max(0, count - 1) * PLAYER_ROW_GAP
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

local function buildPlayerRow(entry, isLocal, index, teamColor)
	-- Outer wrapper stays transparent so the gold outline can sit fully inside
	-- the row bounds instead of being clipped by the ScrollingFrame.
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 42)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundColor3 = teamColor or NAVY_ROW
	inner.BorderSizePixel = 0
	inner.Size = UDim2.new(1, -4, 1, -4)
	inner.Position = UDim2.new(0, 2, 0, 2)
	inner.Parent = row
	corner(inner, 6)
	if isLocal then
		stroke(inner, GOLD, 1.6)
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = inner

	local x = 0
	for _, col in ipairs(COLS) do
		if col.key == "avatar" then
			local av = Instance.new("ImageLabel")
			av.BackgroundTransparency = 1
			av.Size = UDim2.fromOffset(28, 28)
			av.AnchorPoint = Vector2.new(0.5, 0.5)
			av.Position = UDim2.new(x + col.width * 0.5, 0, 0.5, 0)
			av.Parent = inner
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
			label(inner, {
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
	panel.Size = UDim2.new(0.492, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.Parent = parent

	local colLayout = Instance.new("UIListLayout")
	colLayout.FillDirection = Enum.FillDirection.Vertical
	colLayout.SortOrder = Enum.SortOrder.LayoutOrder
	colLayout.Padding = UDim.new(0, 4)
	colLayout.Parent = panel

	local header = Instance.new("Frame")
	header.LayoutOrder = 1
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
	headerRowHolder.LayoutOrder = 2
	headerRowHolder.BackgroundTransparency = 1
	headerRowHolder.Size = UDim2.new(1, 0, 0, 22)
	headerRowHolder.Parent = panel
	buildHeaderRow(headerRowHolder)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.LayoutOrder = 3
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 0, 0)
	scroll.AutomaticSize = Enum.AutomaticSize.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GOLD_DIM
	scroll.ScrollingEnabled = false
	scroll.Active = true
	scroll.Parent = panel

	local listConstraint = Instance.new("UISizeConstraint")
	listConstraint.Name = "ListMax"
	listConstraint.MaxSize = Vector2.new(math.huge, 4096)
	listConstraint.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, PLAYER_ROW_GAP)
	list.Parent = scroll

	if #entries > 0 then
		local scrollPad = Instance.new("UIPadding")
		scrollPad.PaddingTop = UDim.new(0, 2)
		scrollPad.PaddingBottom = UDim.new(0, 2)
		scrollPad.PaddingLeft = UDim.new(0, 3)
		scrollPad.PaddingRight = UDim.new(0, 8)
		scrollPad.Parent = scroll

		for i, entry in ipairs(entries) do
			local row = buildPlayerRow(entry, entry.userId == localUserId, i, headerColor)
			row.LayoutOrder = i
			row.Parent = scroll
		end
	end

	local function applyListHeight(maxHeight)
		local contentH = listContentHeight(#entries)
		if #entries > 0 then
			contentH += 4
		end
		local cap = tonumber(maxHeight) or contentH
		if cap < 0 then
			cap = contentH
		end
		local visibleH = math.min(contentH, cap)
		scroll.Size = UDim2.new(1, 0, 0, visibleH)
		scroll.CanvasSize = UDim2.new(0, 0, 0, contentH)
		scroll.ScrollingEnabled = contentH > visibleH + 0.5
		listConstraint.MaxSize = Vector2.new(math.huge, math.max(visibleH, 0))
	end

	applyListHeight(4096)

	return panel, applyListHeight
end

local function showMatchResults(payload)
	if typeof(payload) ~= "table" then
		return
	end

	clearExisting()

	local winnerKey = payload.winner or "Blue"
	local theme = themeFor(winnerKey)

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
	card.Size = UDim2.fromOffset(DESIGN_WIDTH, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = theme.cardBg
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Active = false
	card.Selectable = false
	card.Parent = gui
	corner(card, 12)
	stroke(card, theme.cardStroke, 2)

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 18)
	cardPad.PaddingRight = UDim.new(0, 18)
	cardPad.PaddingBottom = UDim.new(0, 16)
	cardPad.Parent = card

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Parent = card

	local contentList = Instance.new("UIListLayout")
	contentList.FillDirection = Enum.FillDirection.Vertical
	contentList.SortOrder = Enum.SortOrder.LayoutOrder
	contentList.Padding = UDim.new(0, 8)
	contentList.Parent = content

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "FitScale"
	uiScale.Parent = card

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 0)
	header.AutomaticSize = Enum.AutomaticSize.Y
	header.Parent = content

	local headerList = Instance.new("UIListLayout")
	headerList.FillDirection = Enum.FillDirection.Vertical
	headerList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	headerList.SortOrder = Enum.SortOrder.LayoutOrder
	headerList.Padding = UDim.new(0, 4)
	headerList.Parent = header

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingTop = UDim.new(0, 14)
	headerPad.PaddingBottom = UDim.new(0, 2)
	headerPad.Parent = header

	local victory = label(header, {
		text = teamName(winnerKey) .. " VICTORY",
		font = Enum.Font.GothamBlack,
		textSize = 44,
		color = GOLD,
		size = UDim2.new(0.9, 0, 0, 52),
		scaled = true,
	})
	victory.LayoutOrder = 1
	local victorySize = Instance.new("UITextSizeConstraint")
	victorySize.MinTextSize = 22
	victorySize.MaxTextSize = 44
	victorySize.Parent = victory

	local knightsScore = (payload.score and payload.score.Blue) or 0
	local barbariansScore = (payload.score and payload.score.Red) or 0

	local topDivider = Instance.new("Frame")
	topDivider.Name = "TopDivider"
	topDivider.BackgroundTransparency = 1
	topDivider.Size = UDim2.new(1, 0, 0, 16)
	topDivider.LayoutOrder = 2
	topDivider.Parent = header
	hairline(topDivider, 8, 0.28, GOLD)
	diamond(topDivider, UDim2.new(0.5, 0, 0.5, 0), GOLD)

	local scoreRow = Instance.new("Frame")
	scoreRow.Name = "ScoreRow"
	scoreRow.BackgroundTransparency = 1
	scoreRow.Size = UDim2.new(0.48, 0, 0, 40)
	scoreRow.LayoutOrder = 3
	scoreRow.Parent = header

	buildScorePill(scoreRow, knightsScore, BLUE_BAR, 0, 0.24)
	local mapLabel = label(scoreRow, {
		text = formatMapName(payload.mapName),
		font = Enum.Font.GothamBold,
		textSize = 22,
		color = GOLD,
		size = UDim2.new(0.42, 0, 1, 0),
		pos = UDim2.fromScale(0.29, 0),
		scaled = true,
	})
	mapLabel.TextTruncate = Enum.TextTruncate.None
	local mapSize = Instance.new("UITextSizeConstraint")
	mapSize.MinTextSize = 12
	mapSize.MaxTextSize = 22
	mapSize.Parent = mapLabel
	buildScorePill(scoreRow, barbariansScore, RED_BAR, 0.76, 0.24)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundTransparency = 1
	divider.Size = UDim2.new(1, 0, 0, 16)
	divider.LayoutOrder = 4
	divider.Parent = header
	hairline(divider, 8, 0.28, GOLD)
	diamond(divider, UDim2.new(0.5, 0, 0.5, 0), GOLD)

	local mvpChip = Instance.new("Frame")
	mvpChip.Name = "MVPChip"
	mvpChip.Size = UDim2.fromOffset(340, 52)
	mvpChip.BackgroundColor3 = GOLD_CHIP
	mvpChip.LayoutOrder = 5
	mvpChip.Parent = header
	corner(mvpChip, 8)
	stroke(mvpChip, GOLD, 1.4, 0.25)

	local mvpAvWrap = Instance.new("Frame")
	mvpAvWrap.BackgroundColor3 = GOLD_CHIP
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
	badge.BackgroundColor3 = GOLD_BADGE
	badge.Parent = mvpChip
	corner(badge, 6)
	stroke(badge, GOLD, 1)

	label(badge, {
		text = "◆  MVP",
		font = Enum.Font.GothamBlack,
		textSize = 13,
		color = WHITE,
	})

	if payload.mvpUserId then
		for _, p in ipairs(payload.players or {}) do
			if p.userId == payload.mvpUserId then
				mvpName.Text = p.displayName or p.name or "MVP"
				fillAvatar(mvpAv, p.userId, Enum.ThumbnailSize.Size48x48)
				badge.BackgroundColor3 = badgeColorForTeam(p.team)
				break
			end
		end
	end

	local awardsGap = Instance.new("Frame")
	awardsGap.Name = "AwardsGap"
	awardsGap.BackgroundTransparency = 1
	awardsGap.Size = UDim2.new(1, 0, 0, 8)
	awardsGap.LayoutOrder = 6
	awardsGap.Parent = header

	local awardsRow = Instance.new("Frame")
	awardsRow.Name = "AwardsRow"
	awardsRow.BackgroundTransparency = 1
	awardsRow.Size = UDim2.new(0.72, 0, 0, 52)
	awardsRow.LayoutOrder = 7
	awardsRow.Parent = header

	local awardsList = Instance.new("UIListLayout")
	awardsList.FillDirection = Enum.FillDirection.Horizontal
	awardsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	awardsList.VerticalAlignment = Enum.VerticalAlignment.Center
	awardsList.Padding = UDim.new(0.03, 0)
	awardsList.SortOrder = Enum.SortOrder.LayoutOrder
	awardsList.Parent = awardsRow

	local elimsLeader = pickStatLeader(payload.players, "eliminations")
	local capsLeader = pickStatLeader(payload.players, "captures")
	local elimsChip = buildAwardChip(awardsRow, "MOST ELIMS", elimsLeader)
	elimsChip.LayoutOrder = 1
	local capsChip = buildAwardChip(awardsRow, "MOST CAPS", capsLeader)
	capsChip.LayoutOrder = 2

	local cols = Instance.new("Frame")
	cols.Name = "Teams"
	cols.LayoutOrder = 2
	cols.BackgroundTransparency = 1
	cols.Size = UDim2.new(1, 0, 0, 0)
	cols.AutomaticSize = Enum.AutomaticSize.Y
	cols.Parent = content

	local leftEntries, rightEntries = {}, {}
	for _, p in ipairs(payload.players or {}) do
		if p.team == "Blue" then
			table.insert(leftEntries, p)
		elseif p.team == "Red" then
			table.insert(rightEntries, p)
		end
	end

	local left, applyLeftHeight = buildTeamColumn(cols, "Blue", BLUE_BAR, leftEntries, player.UserId)
	left.Position = UDim2.fromScale(0, 0)

	local right, applyRightHeight = buildTeamColumn(cols, "Red", RED_BAR, rightEntries, player.UserId)
	right.Position = UDim2.fromScale(0.508, 0)

	local function rawHeight(guiObject)
		local scale = math.max(uiScale.Scale, 0.01)
		return (guiObject.AbsoluteSize.Y) / scale
	end

	local function applyListCaps()
		local vw, vh = getViewportSize()
		local widthScale = math.min((vw * 0.94) / DESIGN_WIDTH, FIT_SCALE)
		local maxContentH = (vh * 0.88) / math.max(widthScale, 0.22)
		local headerH = rawHeight(header)
		local chrome = 28
		local maxListH = math.max(PLAYER_ROW_HEIGHT, math.floor(maxContentH - headerH - chrome))
		applyLeftHeight(maxListH)
		applyRightHeight(maxListH)
	end

	local function refreshScale()
		applyListCaps()
		uiScale.Scale = getFitScale(rawHeight(card))
	end

	local viewportConn
	local function bindViewport(cam)
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
		end
		refreshScale()
	end
	bindViewport(workspace.CurrentCamera)
	local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewport(workspace.CurrentCamera)
	end)
	gui.Destroying:Connect(function()
		if viewportConn then
			viewportConn:Disconnect()
		end
		if cameraConn then
			cameraConn:Disconnect()
		end
	end)

	uiScale.Scale = FIT_SCALE
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.15,
	}):Play()
	task.defer(function()
		applyListCaps()
		local openScale = getFitScale(rawHeight(card))
		uiScale.Scale = openScale * 0.88
		TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = openScale,
		}):Play()
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.Position = UDim2.new(1, -14, 0, 14)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = theme.closeBg
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = WHITE
	closeBtn.AutoButtonColor = true
	closeBtn.ZIndex = 3
	closeBtn.Parent = card
	corner(closeBtn, 8)
	stroke(closeBtn, theme.accent, 1.2)

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