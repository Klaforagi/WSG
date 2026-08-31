local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Palette (match Teams UI)
local NAVY = Color3.fromRGB(12, 14, 28)
local NAVY_DARK = Color3.fromRGB(8, 10, 20)
local GOLD = Color3.fromRGB(255, 215, 80)
local GOLD_DIM = Color3.fromRGB(180, 150, 50)
local BLUE = Color3.fromRGB(65, 105, 225)
local RED = Color3.fromRGB(255, 75, 75)
local WHITE = Color3.fromRGB(235, 235, 240)

local function safeText(v)
    return (v == nil) and "" or tostring(v)
end

local function clearExisting()
    local old = playerGui:FindFirstChild("MatchResultsUI")
    if old then pcall(function() old:Destroy() end) end
end

local function makeLabel(parent, props)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = props.bgTrans or 1
    lbl.Size = props.size or UDim2.new(1,0,0,20)
    lbl.Position = props.pos or UDim2.new(0,0,0,0)
    lbl.Font = props.font or Enum.Font.GothamBold
    lbl.TextColor3 = props.color or WHITE
    lbl.Text = props.text or ""
    lbl.TextScaled = props.scaled or false
    lbl.TextSize = props.textSize or 18
    lbl.TextXAlignment = props.xAlign or Enum.TextXAlignment.Center
    lbl.TextYAlignment = props.yAlign or Enum.TextYAlignment.Center
    lbl.Parent = parent
    return lbl
end

local function populateAvatar(imageLabel, userId, size)
    task.spawn(function()
        local ok, url = pcall(function()
            return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, size == 64 and Enum.ThumbnailSize.Size64x64 or Enum.ThumbnailSize.Size48x48)
        end)
        if ok and url and imageLabel and imageLabel.Parent then
            imageLabel.Image = url
        end
    end)
end

    local function buildRow(entry, isLocal)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 42)
    row.BackgroundTransparency = 0
    row.BorderSizePixel = 0
    row.BackgroundColor3 = isLocal and Color3.fromRGB(60,50,10) or NAVY_DARK
    Instance.new("UICorner", row).CornerRadius = UDim.new(0,6)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    pad.Parent = row

    -- Columns: Lvl(7%), Avatar(8%), Name(20%), Score(10%), Elims(14%), Deaths(10%), Captures(16%), Returns(15%)
    local widths = {0.07, 0.08, 0.20, 0.10, 0.14, 0.10, 0.16, 0.15}
    local x = 0

    -- Level
    local lvl = makeLabel(row, { text = tostring(entry.level or 0), textSize = 16, scaled = false })
    lvl.Size = UDim2.new(widths[1], 0, 1, 0)
    lvl.Position = UDim2.new(x, 0, 0, 0)
    lvl.TextXAlignment = Enum.TextXAlignment.Center
    x = x + widths[1]

    -- Avatar
    local av = Instance.new("ImageLabel")
    av.Size = UDim2.new(widths[2], 0, 0.85, 0)
    av.Position = UDim2.new(x + 0.02, 0, 0.5, 0)
    av.AnchorPoint = Vector2.new(0, 0.5)
    av.BackgroundTransparency = 1
    av.Parent = row
    Instance.new("UICorner", av).CornerRadius = UDim.new(1,0)
    populateAvatar(av, entry.userId, 48)
    x = x + widths[2]

    -- Name
    local nameLbl = makeLabel(row, { text = entry.displayName or entry.name or "", textSize = 16, scaled = false })
    nameLbl.Size = UDim2.new(widths[3], 0, 1, 0)
    nameLbl.Position = UDim2.new(x, 0, 0, 0)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    x = x + widths[3]

    -- Score
    local scoreLbl = makeLabel(row, { text = tostring(entry.score or 0), textSize = 16, scaled = false })
    scoreLbl.Size = UDim2.new(widths[4], 0, 1, 0)
    scoreLbl.Position = UDim2.new(x, 0, 0, 0)
    scoreLbl.TextXAlignment = Enum.TextXAlignment.Center
    scoreLbl.TextColor3 = GOLD
    x = x + widths[4]

    -- Elims
    local elimsLbl = makeLabel(row, { text = tostring(entry.eliminations or 0), textSize = 16, scaled = false })
    elimsLbl.Size = UDim2.new(widths[5], 0, 1, 0)
    elimsLbl.Position = UDim2.new(x, 0, 0, 0)
    x = x + widths[5]

    -- Deaths
    local deathsLbl = makeLabel(row, { text = tostring(entry.deaths or 0), textSize = 16, scaled = false })
    deathsLbl.Size = UDim2.new(widths[6], 0, 1, 0)
    deathsLbl.Position = UDim2.new(x, 0, 0, 0)
    x = x + widths[6]

    -- Captures
    local capsLbl = makeLabel(row, { text = tostring(entry.captures or 0), textSize = 16, scaled = false })
    capsLbl.Size = UDim2.new(widths[7], 0, 1, 0)
    capsLbl.Position = UDim2.new(x, 0, 0, 0)
    x = x + widths[7]

    -- Returns
    local retLbl = makeLabel(row, { text = tostring(entry.returns or 0), textSize = 16, scaled = false })
    retLbl.Size = UDim2.new(widths[8], 0, 1, 0)
    retLbl.Position = UDim2.new(x, 0, 0, 0)

    return row
end

local function showMatchResults(payload)
    if not payload or type(payload) ~= "table" then return end

    clearExisting()

    local screen = Instance.new("ScreenGui")
    screen.Name = "MatchResultsUI"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 9999
    screen.Parent = playerGui

    -- Fullscreen solid background
    local root = Instance.new("Frame")
    root.Name = "Root"
    root.Size = UDim2.new(1, 0, 1, 0)
    root.Position = UDim2.new(0, 0, 0, 0)
    root.BackgroundColor3 = NAVY
    root.BackgroundTransparency = 0
    root.BorderSizePixel = 0
    root.Parent = screen

    local stroke = Instance.new("UIStroke")
    stroke.Color = GOLD
    stroke.Thickness = 2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = root

    -- Container (centered)
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position = UDim2.new(0.5, 0, 0.5, 0)
    container.Size = UDim2.new(0.74, 0, 0.66, 0)
    container.BackgroundColor3 = Color3.fromRGB(10,12,24)
    container.BackgroundTransparency = 0
    container.BorderSizePixel = 0
    container.Parent = root
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)

    -- Title + score area
    local title = makeLabel(container, { text = (TeamDisplayNames and TeamDisplayNames.GetUpper and TeamDisplayNames.GetUpper(payload.winner) or tostring(payload.winner)) .. " VICTORY", textSize = 36, scaled = false })
    title.Font = Enum.Font.GothamBlack
    title.Position = UDim2.new(0.5, 0, 0.03, 0)
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.TextColor3 = GOLD

    local leftName = TeamDisplayNames and TeamDisplayNames.GetUpper and TeamDisplayNames.GetUpper("Blue") or "Blue"
    local rightName = TeamDisplayNames and TeamDisplayNames.GetUpper and TeamDisplayNames.GetUpper("Red") or "Red"
    local bscore = (payload.score and payload.score.Blue) or 0
    local rscore = (payload.score and payload.score.Red) or 0
    local scoreText = string.format("%s %d  -  %d %s", leftName, bscore, rscore, rightName)
    local scoreLbl = makeLabel(container, { text = scoreText, textSize = 24, scaled = false })
    scoreLbl.Position = UDim2.new(0.5, 0, 0.09, 0)
    scoreLbl.AnchorPoint = Vector2.new(0.5, 0)
    scoreLbl.TextColor3 = GOLD_DIM

    -- MVP row
    local mvpFrame = Instance.new("Frame")
    mvpFrame.Size = UDim2.new(0.56, 0, 0, 56)
    mvpFrame.Position = UDim2.new(0.5, 0, 0.145, 0)
    mvpFrame.AnchorPoint = Vector2.new(0.5, 0)
    mvpFrame.BackgroundColor3 = Color3.fromRGB(16,18,32)
    mvpFrame.Parent = container
    Instance.new("UICorner", mvpFrame).CornerRadius = UDim.new(0, 8)

    local mvpTag = makeLabel(mvpFrame, { text = "MVP", textSize = 14, scaled = false })
    mvpTag.Position = UDim2.new(0.02, 0, 0.12, 0)
    mvpTag.Size = UDim2.new(0.08, 0, 0.8, 0)
    mvpTag.TextColor3 = GOLD_DIM
    mvpTag.TextXAlignment = Enum.TextXAlignment.Left

    local mvpAvatar = Instance.new("ImageLabel")
    mvpAvatar.Size = UDim2.new(0, 48, 0, 48)
    mvpAvatar.Position = UDim2.new(0.12, 0, 0.5, 0)
    mvpAvatar.AnchorPoint = Vector2.new(0, 0.5)
    mvpAvatar.BackgroundTransparency = 1
    mvpAvatar.Parent = mvpFrame
    Instance.new("UICorner", mvpAvatar).CornerRadius = UDim.new(1, 0)

    local mvpName = makeLabel(mvpFrame, { text = "", textSize = 18, scaled = false })
    mvpName.Position = UDim2.new(0.28, 0, 0.5, 0)
    mvpName.AnchorPoint = Vector2.new(0, 0.5)
    mvpName.Size = UDim2.new(0.6, 0, 0.9, 0)
    mvpName.TextColor3 = GOLD
    mvpName.TextXAlignment = Enum.TextXAlignment.Left

    if payload.mvpUserId then
        for _, p in ipairs(payload.players or {}) do
            if p.userId == payload.mvpUserId then
                mvpName.Text = p.displayName or p.name or ""
                populateAvatar(mvpAvatar, p.userId, 48)
                break
            end
        end
    end

    -- Columns container
    local cols = Instance.new("Frame")
    cols.Size = UDim2.new(0.98, 0, 0.56, 0)
    cols.Position = UDim2.new(0.01, 0, 0.36, 0)
    cols.BackgroundTransparency = 1
    cols.Parent = container

    local leftPanel = Instance.new("Frame")
    leftPanel.Size = UDim2.new(0.48, 0, 1, 0)
    leftPanel.Position = UDim2.new(0, 0, 0, 0)
    leftPanel.BackgroundTransparency = 1
    leftPanel.Parent = cols

    local rightPanel = Instance.new("Frame")
    rightPanel.Size = UDim2.new(0.48, 0, 1, 0)
    rightPanel.Position = UDim2.new(0.52, 0, 0, 0)
    rightPanel.BackgroundTransparency = 1
    rightPanel.Parent = cols

    -- Headers
    local leftHeader = Instance.new("Frame")
    leftHeader.Size = UDim2.new(1, 0, 0, 34)
    leftHeader.Position = UDim2.new(0, 0, 0, 0)
    leftHeader.BackgroundColor3 = Color3.fromRGB(14, 22, 48)
    leftHeader.Parent = leftPanel
    Instance.new("UICorner", leftHeader).CornerRadius = UDim.new(0, 6)
    local lhdrLbl = makeLabel(leftHeader, { text = TeamDisplayNames.GetUpper("Blue"), textSize = 16, scaled = false })
    lhdrLbl.Position = UDim2.new(0.02, 0, 0, 0)
    lhdrLbl.TextXAlignment = Enum.TextXAlignment.Left
    lhdrLbl.TextColor3 = BLUE

    local rightHeader = leftHeader:Clone()
    rightHeader.Parent = rightPanel
    rightHeader.BackgroundColor3 = Color3.fromRGB(95, 18, 18)
    local rhdrLbl = rightHeader:FindFirstChildWhichIsA("TextLabel")
    if rhdrLbl then
        rhdrLbl.Text = TeamDisplayNames.GetUpper("Red")
        rhdrLbl.TextColor3 = WHITE
    end

    -- Scrolling lists
    local leftScroll = Instance.new("ScrollingFrame")
    leftScroll.Size = UDim2.new(1, 0, 0.92, 0)
    leftScroll.Position = UDim2.new(0, 0, 0.08, 0)
    leftScroll.BackgroundTransparency = 1
    leftScroll.ScrollBarThickness = 6
    leftScroll.Parent = leftPanel
    leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local leftLayout = Instance.new("UIListLayout")
    leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
    leftLayout.Padding = UDim.new(0, 6)
    leftLayout.Parent = leftScroll

    local rightScroll = leftScroll:Clone()
    rightScroll.Parent = rightPanel
    local rightLayout = rightScroll:FindFirstChildWhichIsA("UIListLayout")

    -- Column headers (match row order)
    local function createHeaderRow(parent)
        local headerRow = Instance.new("Frame")
        headerRow.Size = UDim2.new(1, 0, 0, 28)
        headerRow.BackgroundTransparency = 1
        headerRow.Parent = parent
        headerRow.LayoutOrder = 0

        local widths = {0.07, 0.08, 0.20, 0.10, 0.14, 0.10, 0.16, 0.15}
        local labels = {"Lvl","Avatar","Name","Score","Elims","Deaths","Captures","Returns"}
        local x = 0
        for i, txt in ipairs(labels) do
            local hl = makeLabel(headerRow, { text = txt, textSize = 14, scaled = false })
            hl.TextColor3 = GOLD_DIM
            hl.Size = UDim2.new(widths[i], 0, 1, 0)
            hl.Position = UDim2.new(x, 0, 0, 0)
            if txt == "Name" then hl.TextXAlignment = Enum.TextXAlignment.Left end
            x = x + widths[i]
        end
    end
    createHeaderRow(leftScroll)
    createHeaderRow(rightScroll)

    -- Build player lists (cap 8 per team)
    local leftCount = 0
    local rightCount = 0
    for _, p in ipairs(payload.players or {}) do
        if p.team == "Blue" and leftCount < 8 then
            leftCount = leftCount + 1
            local isLocal = (p.userId == player.UserId)
            local row = buildRow(p, isLocal)
            row.LayoutOrder = leftCount
            row.Parent = leftScroll
        elseif p.team == "Red" and rightCount < 8 then
            rightCount = rightCount + 1
            local isLocal = (p.userId == player.UserId)
            local row = buildRow(p, isLocal)
            row.LayoutOrder = rightCount
            row.Parent = rightScroll
        end
    end

    -- Hide scroll area if team has no players
    leftScroll.Visible = (leftCount > 0)
    rightScroll.Visible = (rightCount > 0)

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 44, 0, 44)
    closeBtn.Position = UDim2.new(1, -56, 0, 12)
    closeBtn.AnchorPoint = Vector2.new(0, 0)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "X"
    closeBtn.TextSize = 20
    closeBtn.BackgroundTransparency = 0.1
    closeBtn.TextColor3 = GOLD
    closeBtn.Parent = container
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.Activated:Connect(function()
        if screen and screen.Parent then pcall(function() screen:Destroy() end) end
    end)

    -- Auto destroy after 15s
    task.delay(15, function()
        if screen and screen.Parent then pcall(function() screen:Destroy() end) end
    end)
end

-- Listen for MatchResults remote
local rem = ReplicatedStorage:FindFirstChild("MatchResults")
if rem and rem:IsA("RemoteEvent") then
    rem.OnClientEvent:Connect(function(payload)
        pcall(function() showMatchResults(payload) end)
    end)
else
    spawn(function()
        local waited = 0
        while waited < 5 do
            task.wait(0.1)
            waited = waited + 0.1
            rem = ReplicatedStorage:FindFirstChild("MatchResults")
            if rem and rem:IsA("RemoteEvent") then
                rem.OnClientEvent:Connect(function(payload)
                    pcall(function() showMatchResults(payload) end)
                end)
                break
            end
        end
    end)
end
