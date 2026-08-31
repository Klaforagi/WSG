--------------------------------------------------------------------------------
-- TeamUI.lua
-- Modal-based Team / Career Stats panel for SideUI modal host.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))

local TeamUI = {}

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- Color palette
local NAVY         = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT   = Color3.fromRGB(22, 26, 48)
local GOLD         = Color3.fromRGB(255, 215, 80)
local GOLD_DIM     = Color3.fromRGB(180, 150, 50)
local BLUE_ACCENT  = Color3.fromRGB(65, 105, 225)
local BLUE_BG      = Color3.fromRGB(16, 24, 56)
local RED_ACCENT   = Color3.fromRGB(255, 75, 75)
local RED_BG       = Color3.fromRGB(56, 16, 20)
local WHITE        = Color3.fromRGB(235, 235, 240)
local GRAY         = Color3.fromRGB(140, 140, 155)

local COLUMNS = {
    { key = "Level",        label = "Lvl",          width = 0.07 },
    { key = "Avatar",       label = "",               width = 0.08 },
    { key = "Name",         label = "Player",         width = 0.20 },
    { key = "Score",        label = "Score",          width = 0.10 },
    { key = "Eliminations", label = "Elims",   width = 0.14 },
    { key = "Deaths",       label = "Deaths",         width = 0.10 },
    { key = "FlagCaptures", label = "Captures",  width = 0.16 },
    { key = "FlagReturns",  label = "Returns",   width = 0.15 },
}

local HEADER_TEXT_SIZE = 14
local STAT_TEXT_SIZE = 16
local AVATAR_SIZE        = 46
local ROW_HEIGHT         = 56
local TEAM_HEADER_HEIGHT = 46

local function formatStatNumber(value)
    value = tonumber(value) or 0
    if math.abs(value) >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    elseif math.abs(value) >= 1000 then
        return string.format("%.1fk", value / 1000)
    end
    return tostring(math.floor(value + 0.5))
end

local function formatPlaytime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local mins = math.floor(seconds / 60)
    local hours = math.floor(mins / 60)
    local days = math.floor(hours / 24)
    if days > 0 then
        return tostring(days) .. "d"
    elseif hours > 0 then
        return tostring(hours) .. "h"
    elseif mins > 0 then
        return tostring(mins) .. "m"
    end
    return tostring(seconds) .. "s"
end

-- Build the panel content (host is the contentFrame provided by SideUI)
function TeamUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return end

    local host = Instance.new("Frame")
    host.Name = "TeamRoot"
    host.Size = UDim2.new(1, 0, 1, 0)
    host.BackgroundTransparency = 1
    host.LayoutOrder = 1
    host.Parent = parent

    -- Panel (fills host)
    local panel = Instance.new("Frame")
    panel.Name = "TeamStatsPanel"
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundColor3 = NAVY
    panel.BackgroundTransparency = 0.04
    panel.ClipsDescendants = true
    panel.Parent = host

    local panelPad = Instance.new("UIPadding")
    panelPad.PaddingTop    = UDim.new(0, px(14))
    panelPad.PaddingBottom = UDim.new(0, px(12))
    panelPad.PaddingLeft   = UDim.new(0, px(18))
    panelPad.PaddingRight  = UDim.new(0, px(18))
    panelPad.Parent = panel

    -- (Removed internal STATS header to allow SideUI's external TEAMS header to show)

    -- Tab bar
    local TAB_BAR_H = px(42)
    local TAB_GAP   = px(8)
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, 0, 0, TAB_BAR_H)
    tabBar.Position = UDim2.new(0, 0, 0, px(12))
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = panel

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabLayout.Padding = UDim.new(0, TAB_GAP)
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Parent = tabBar

    local activeTab = "TeamStats"
    local selectedCareerTarget = nil
    local activePopup = nil
    local activePopupRow = nil
    local popupJustOpened = false
    local openPlayerActionPopup
    local closePlayerActionPopup
    local populateCareerTab
    local updateTabVisuals
    local selectTab

    local function createTabButton(name, label, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Name = name .. "Tab"
        btn.Size = UDim2.new(0.5, -TAB_GAP / 2, 1, 0)
        btn.BackgroundColor3 = NAVY_LIGHT
        btn.BackgroundTransparency = 0.05
        btn.Font = Enum.Font.GothamBold
        btn.Text = label
        btn.TextScaled = true
        btn.TextSize = 16
        btn.TextColor3 = GRAY
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.LayoutOrder = layoutOrder
        btn.Parent = tabBar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, px(8))
        return btn
    end

    local teamStatsTabBtn = createTabButton("TeamStats", "TEAM STATS", 1)
    local careerTabBtn    = createTabButton("Career",    "CAREER",     2)

    -- Content containers
    local CONTENT_AREA_TOP = px(12) + TAB_BAR_H + px(8)

    local teamStatsContainer = Instance.new("Frame")
    teamStatsContainer.Name = "TeamStatsContainer"
    teamStatsContainer.Size = UDim2.new(1, 0, 1, -CONTENT_AREA_TOP)
    teamStatsContainer.Position = UDim2.new(0, 0, 0, CONTENT_AREA_TOP)
    teamStatsContainer.BackgroundTransparency = 1
    teamStatsContainer.Parent = panel

    local careerContainer = Instance.new("ScrollingFrame")
    careerContainer.Name = "CareerContainer"
    careerContainer.Size = UDim2.new(1, 0, 1, -CONTENT_AREA_TOP)
    careerContainer.Position = UDim2.new(0, 0, 0, CONTENT_AREA_TOP)
    careerContainer.BackgroundTransparency = 1
    careerContainer.ScrollBarThickness = px(6)
    careerContainer.ScrollBarImageColor3 = GOLD_DIM
    careerContainer.ScrollBarImageTransparency = 0.3
    careerContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    careerContainer.Visible = false
    careerContainer.Parent = panel

    local careerLayout = Instance.new("UIListLayout")
    careerLayout.SortOrder = Enum.SortOrder.LayoutOrder
    careerLayout.Padding = UDim.new(0, px(10))
    careerLayout.Parent = careerContainer

    local careerPad = Instance.new("UIPadding")
    careerPad.PaddingTop = UDim.new(0, px(4))
    careerPad.PaddingBottom = UDim.new(0, px(14))
    careerPad.PaddingLeft = UDim.new(0, px(2))
    careerPad.PaddingRight = UDim.new(0, px(2))
    careerPad.Parent = careerContainer

    -- Column headers
    local COL_H_Y = px(4)
    local COL_H_H = px(38)
    local colHeaderRow = Instance.new("Frame")
    colHeaderRow.Name = "ColumnHeaders"
    colHeaderRow.Size = UDim2.new(1, 0, 0, COL_H_H)
    colHeaderRow.Position = UDim2.new(0, 0, 0, COL_H_Y)
    colHeaderRow.BackgroundTransparency = 1
    colHeaderRow.Parent = teamStatsContainer

    for i, col in ipairs(COLUMNS) do
        local xOff = 0
        for j = 1, i - 1 do
            xOff = xOff + COLUMNS[j].width
        end

        local lbl = Instance.new("TextLabel")
        lbl.Name = "ColH_" .. col.key
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = false
        lbl.TextSize = 14
        lbl.TextWrapped = true
        lbl.TextColor3 = GRAY
        lbl.Text = col.label
        lbl.TextXAlignment = (col.key == "Name") and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
        lbl.Position = UDim2.new(xOff, 0, 0, 0)
        lbl.Size = UDim2.new(col.width, 0, 1, 0)
        lbl.Parent = colHeaderRow
    end

    -- Content scroll
    local CONTENT_TOP = COL_H_Y + COL_H_H + px(6)
    local contentScroll = Instance.new("ScrollingFrame")
    contentScroll.Name = "Content"
    contentScroll.Position = UDim2.new(0, 0, 0, CONTENT_TOP)
    contentScroll.Size = UDim2.new(1, 0, 1, -CONTENT_TOP - px(80))
    contentScroll.BackgroundTransparency = 1
    contentScroll.ScrollBarThickness = px(6)
    contentScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    contentScroll.Parent = teamStatsContainer

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, px(10))
    contentLayout.Parent = contentScroll

    -- Footer
    local footer = Instance.new("Frame")
    footer.Name = "ChangeTeamFooter"
    footer.Size = UDim2.new(1, 0, 0, px(80))
    footer.Position = UDim2.new(0, 0, 1, -px(80))
    footer.BackgroundTransparency = 1
    footer.Parent = teamStatsContainer

    local lobbyBtn = Instance.new("TextButton")
    lobbyBtn.Name = "LobbyBtn"
    lobbyBtn.Size = UDim2.new(0, px(220), 0, px(44))
    lobbyBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    lobbyBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    lobbyBtn.BackgroundColor3 = NAVY_LIGHT
    lobbyBtn.BackgroundTransparency = 0.05
    lobbyBtn.Font = Enum.Font.GothamBold
    lobbyBtn.Text = "GO TO LOBBY"
    lobbyBtn.TextScaled = false
    lobbyBtn.TextSize = 16
    lobbyBtn.TextColor3 = GOLD
    lobbyBtn.Parent = footer
    Instance.new("UICorner", lobbyBtn).CornerRadius = UDim.new(0, px(8))

    lobbyBtn.MouseButton1Click:Connect(function()
        local remotes = ReplicatedStorage
        local returnReq = remotes:FindFirstChild("ReturnToLobbyRequest")
        if not returnReq then
            pcall(function()
                returnReq = remotes:WaitForChild("ReturnToLobbyRequest", 5)
            end)
        end
        if returnReq and returnReq.FireServer then
            pcall(function()
                returnReq:FireServer()
            end)
        end
    end)

    -- Data / rows
    local playerRows = {}

    local function getScoreboardTeamName(plr)
        local teamName = plr.Team and plr.Team.Name
        if teamName == "Blue" or teamName == "Red" then
            return teamName
        end
        return "Neutral"
    end

    local function fetchAvatar(userId, callback)
        task.spawn(function()
            local ok, url = pcall(function()
                return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            end)
            if ok and url then callback(url) end
        end)
    end

    local function getPlayerStat(plr, key)
        if key == "Level" then
            local ls = plr:FindFirstChild("leaderstats")
            if ls then
                local lv = ls:FindFirstChild("Level")
                if lv then return lv.Value end
            end
            return plr:GetAttribute("Level") or 1
        end
        return plr:GetAttribute(key) or 0
    end

    local careerStatsRemote
    local publicCareerStatsRemote

    local function getCareerStatsRemote()
        if careerStatsRemote then return careerStatsRemote end
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
        if remotes then
            careerStatsRemote = remotes:WaitForChild("GetCareerStats", 5)
        end
        return careerStatsRemote
    end

    local function getPublicCareerStatsRemote()
        if publicCareerStatsRemote then return publicCareerStatsRemote end
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
        if remotes then
            publicCareerStatsRemote = remotes:WaitForChild("GetPublicCareerStats", 5)
        end
        return publicCareerStatsRemote
    end

    local function createPlayerRow(plr, teamName, order)
        local isLocal = (plr == Players.LocalPlayer)
        local row = Instance.new("Frame")
        row.Name = "Row_" .. plr.Name
        row.Size = UDim2.new(1, 0, 0, px(ROW_HEIGHT))
        row.LayoutOrder = order or 999
        if teamName == "Blue" then
            row.BackgroundColor3 = Color3.fromRGB(22, 17, 74)
        elseif teamName == "Red" then
            row.BackgroundColor3 = Color3.fromRGB(57, 0, 1)
        else
            row.BackgroundColor3 = Color3.fromRGB(45, 44, 53)
        end
        row.BackgroundTransparency = (isLocal and 0.05) or 0.30
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(6))

        local rowPad = Instance.new("UIPadding")
        rowPad.PaddingLeft  = UDim.new(0, px(8))
        rowPad.PaddingRight = UDim.new(0, px(8))
        rowPad.Parent = row

        local cells = {}
        for i, col in ipairs(COLUMNS) do
            local xOff = 0
            for j = 1, i - 1 do xOff = xOff + COLUMNS[j].width end
        if col.key == "Avatar" then
            local avatarImg = Instance.new("ImageLabel")
            avatarImg.Name = "Avatar"
            avatarImg.Size = UDim2.new(0, px(AVATAR_SIZE), 0, px(AVATAR_SIZE))
            avatarImg.Position = UDim2.new(xOff + col.width * 0.5, 0, 0.5, 0)
            avatarImg.AnchorPoint = Vector2.new(0.5, 0.5)
            avatarImg.BackgroundTransparency = 0.25
            avatarImg.Parent = row
            Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)
            fetchAvatar(plr.UserId, function(url)
                if avatarImg and avatarImg.Parent then
                    avatarImg.Image = url
                end
            end)
            cells["Avatar"] = avatarImg

        elseif col.key == "Name" then
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "CellName"
            nameLabel.BackgroundTransparency = 1
            nameLabel.Position = UDim2.new(xOff, px(4), 0, 0)
            nameLabel.Size = UDim2.new(col.width, -px(8), 1, 0)
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextScaled = false
            nameLabel.TextSize = 16
            nameLabel.TextColor3 = isLocal and GOLD or WHITE
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextYAlignment = Enum.TextYAlignment.Center
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Text = plr.DisplayName
            nameLabel.Parent = row
            cells["Name"] = nameLabel

        else
            local cell = Instance.new("TextLabel")
            cell.Name = "Cell_" .. col.key
            cell.BackgroundTransparency = 1
            cell.Position = UDim2.new(xOff, 0, 0, 0)
            cell.Size = UDim2.new(col.width, 0, 1, 0)
            cell.Font = (col.key == "Score") and Enum.Font.GothamBlack or Enum.Font.GothamBold
            cell.TextScaled = false
            cell.TextSize = 16
            cell.TextColor3 = (col.key == "Score") and GOLD or WHITE
            cell.TextXAlignment = Enum.TextXAlignment.Center
            cell.TextYAlignment = Enum.TextYAlignment.Center
            cell.Text = tostring(getPlayerStat(plr, col.key))
            cell.Parent = row
            cells[col.key] = cell
        end
    end

        -- Click overlay
        local clickOverlay = Instance.new("TextButton")
        clickOverlay.Name = "ClickOverlay"
        clickOverlay.Size = UDim2.new(1, 0, 1, 0)
        clickOverlay.BackgroundTransparency = 1
        clickOverlay.Text = ""
        clickOverlay.AutoButtonColor = false
        clickOverlay.BorderSizePixel = 0
        clickOverlay.ZIndex = 5
        clickOverlay.Parent = row
        -- Track exact input position for precise popup placement (mouse & touch)
        local lastInputPos = nil
        clickOverlay.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                lastInputPos = input.Position
            end
        end)

        clickOverlay.MouseButton1Click:Connect(function()
            local mousePos = lastInputPos
            if not mousePos then
                pcall(function()
                    local m = Players.LocalPlayer and Players.LocalPlayer:GetMouse()
                    if m then mousePos = Vector2.new(m.X or 0, m.Y or 0) end
                end)
            end
            if not mousePos then
                mousePos = UserInputService:GetMouseLocation()
            end
            openPlayerActionPopup(plr, row, mousePos)
        end)

        return row, cells
    end

    local playerRows = {}

    local function makeSection(name, accentColor)
        local sec = Instance.new("Frame")
        sec.Name = name .. "Section"
        sec.Size = UDim2.new(1, 0, 0, 0)
        sec.AutomaticSize = Enum.AutomaticSize.Y
        sec.LayoutOrder = (name == "Blue" and 1) or (name == "Red" and 2) or 3
        if name == "Blue" then
            sec.BackgroundColor3 = Color3.fromRGB(20, 24, 255)
        elseif name == "Red" then
            sec.BackgroundColor3 = Color3.fromRGB(255, 0, 4)
        else
            sec.BackgroundColor3 = Color3.fromRGB(255, 204, 1)
        end
        sec.BackgroundTransparency = 0.8
        sec.Parent = contentScroll

        local hdr = Instance.new("Frame")
        hdr.Name = "TeamHeader"
        hdr.Size = UDim2.new(1, 0, 0, px(28))
        hdr.BackgroundTransparency = 0.9
        hdr.Parent = sec

        local hdrLabel = Instance.new("TextLabel")
        hdrLabel.Name = "TeamLabel"
        hdrLabel.Size = UDim2.new(1, -px(12), 1, 0)
        hdrLabel.Position = UDim2.new(0, px(6), 0, 0)
        hdrLabel.BackgroundTransparency = 1
        hdrLabel.Font = Enum.Font.GothamBold
        hdrLabel.TextScaled = true
        hdrLabel.TextSize = 14
        hdrLabel.TextColor3 = accentColor or GOLD
        hdrLabel.TextXAlignment = Enum.TextXAlignment.Left
        hdrLabel.Text = tostring(name)
        hdrLabel.Parent = hdr

        local list = Instance.new("UIListLayout")
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, px(6))
        list.Parent = sec

        return sec, hdrLabel
    end

    local blueSection, blueLabel = makeSection("Blue", BLUE_ACCENT)
    local redSection, redLabel = makeSection("Red", RED_ACCENT)
    local neutralSection, neutralLabel = makeSection("Neutral", GOLD)

    closePlayerActionPopup = function()
        if activePopup then
            pcall(function() activePopup:Destroy() end)
            activePopup = nil
        end
        if activePopupRow then
            local hs = activePopupRow:FindFirstChild("PopupHighlight")
            if hs then hs:Destroy() end
            activePopupRow = nil
        end
    end

    openPlayerActionPopup = function(targetPlayer, anchorRow, clickPos)
        closePlayerActionPopup()
        if not targetPlayer or not anchorRow or not anchorRow.Parent then return end

        activePopupRow = anchorRow

        local highlight = Instance.new("Frame")
        highlight.Name = "PopupHighlight"
        highlight.Size = UDim2.new(1, 0, 1, 0)
        highlight.BackgroundColor3 = GOLD
        highlight.BackgroundTransparency = 0.88
        highlight.BorderSizePixel = 0
        highlight.ZIndex = 0
        highlight.Parent = anchorRow
        Instance.new("UICorner", highlight).CornerRadius = UDim.new(0, px(6))

        local popup = Instance.new("Frame")
        popup.Name = "PlayerActionPopup"
        popup.Size = UDim2.new(0, px(210), 0, px(100))
        popup.BackgroundColor3 = NAVY
        popup.BackgroundTransparency = 0.02
        popup.BorderSizePixel = 0
        popup.ZIndex = 50
        popup.ClipsDescendants = true
        popup.Parent = host
        Instance.new("UICorner", popup).CornerRadius = UDim.new(0, px(10))

        local stroke = Instance.new("UIStroke")
        stroke.Color = GOLD_DIM
        stroke.Thickness = 1.5
        stroke.Transparency = 0.15
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = popup

        local popupLayout = Instance.new("UIListLayout")
        popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
        popupLayout.Padding = UDim.new(0, px(4))
        popupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        popupLayout.Parent = popup

        local popupPad = Instance.new("UIPadding")
        popupPad.PaddingTop = UDim.new(0, px(8))
        popupPad.PaddingBottom = UDim.new(0, px(8))
        popupPad.PaddingLeft = UDim.new(0, px(8))
        popupPad.PaddingRight = UDim.new(0, px(8))
        popupPad.Parent = popup

        local BTN_DEFAULT = Color3.fromRGB(26, 30, 48)
        local BTN_HOVER = Color3.fromRGB(42, 38, 22)
        local fi = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        local function makePopupButton(text, order, callback)
            local btn = Instance.new("TextButton")
            btn.Name = text .. "Btn"
            btn.Size = UDim2.new(1, 0, 0, px(36))
            btn.BackgroundColor3 = BTN_DEFAULT
            btn.BackgroundTransparency = 0.05
            btn.Font = Enum.Font.GothamBold
            btn.TextScaled = true
            btn.TextSize = 18
            btn.Text = text
            btn.TextColor3 = WHITE
            btn.AutoButtonColor = false
            btn.BorderSizePixel = 0
            btn.LayoutOrder = order
            btn.ZIndex = 51
            btn.Parent = popup
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, px(6))

            btn.MouseEnter:Connect(function()
                TweenService:Create(btn, fi, {BackgroundColor3 = BTN_HOVER, TextColor3 = GOLD}):Play()
            end)
            btn.MouseLeave:Connect(function()
                TweenService:Create(btn, fi, {BackgroundColor3 = BTN_DEFAULT, TextColor3 = WHITE}):Play()
            end)
            btn.MouseButton1Click:Connect(function()
                closePlayerActionPopup()
                if callback then callback() end
            end)
            return btn
        end

        makePopupButton("View Career Page", 1, function()
            selectedCareerTarget = targetPlayer
            selectTab("Career")
        end)

        makePopupButton("Add Friend", 2, function()
            if targetPlayer == Players.LocalPlayer then return end
            pcall(function()
                StarterGui:SetCore("PromptSendFriendRequest", targetPlayer)
            end)
        end)

        local function positionPopup()
            local popW = popup.AbsoluteSize.X
            local popH = popup.AbsoluteSize.Y
            local panelPos = panel.AbsolutePosition
            local panelSize = panel.AbsoluteSize
            local panelL = panelPos.X
            local panelT = panelPos.Y
            local panelR = panelL + panelSize.X
            local panelB = panelT + panelSize.Y

            local cx, cy
            if clickPos then
                cx = clickPos.X
                cy = clickPos.Y
            else
                local rp = anchorRow.AbsolutePosition
                local rs = anchorRow.AbsoluteSize
                cx = rp.X + rs.X * 0.25
                cy = rp.Y + rs.Y / 2
            end

            local posX = cx - popW / 2
            local posY = cy - popH - px(8)
            if posY < panelT + px(4) then
                posY = cy + px(8)
            end

            posX = math.clamp(posX, panelL + px(4), panelR - popW - px(4))
            posY = math.clamp(posY, panelT + px(4), panelB - popH - px(4))
            -- Convert absolute screen coords to host-local coords (popup's parent is `host`)
            local hostPos = host.AbsolutePosition
            local localX = math.floor(posX - hostPos.X + 0)
            local localY = math.floor(posY - hostPos.Y + 0)
            popup.Position = UDim2.new(0, localX, 0, localY)
        end

        task.defer(positionPopup)

        activePopup = popup
        popupJustOpened = true
    end

    UserInputService.InputEnded:Connect(function(input)
        if not activePopup then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if popupJustOpened then
            popupJustOpened = false
            return
        end
        local pos = input.Position
        if activePopup and activePopup.Parent then
            local apPos = activePopup.AbsolutePosition
            local apSize = activePopup.AbsoluteSize
            if pos.X >= apPos.X and pos.X <= apPos.X + apSize.X and pos.Y >= apPos.Y and pos.Y <= apPos.Y + apSize.Y then
                return
            end
        end
        closePlayerActionPopup()
    end)

    local function clearCareerContainer()
        for _, child in ipairs(careerContainer:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
    end

    local function makeCareerRow(section, label, valueText)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, px(42))
        row.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
        row.BackgroundTransparency = 0.2
        row.Parent = section
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(6))

        local rowPad = Instance.new("UIPadding")
        rowPad.PaddingLeft = UDim.new(0, px(10))
        rowPad.PaddingRight = UDim.new(0, px(10))
        rowPad.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0.65, 0, 1, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextScaled = true
        lbl.TextSize = 18
        lbl.TextColor3 = WHITE
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = label
        lbl.Parent = row

        local val = Instance.new("TextLabel")
        val.BackgroundTransparency = 1
        val.Position = UDim2.new(0.65, 0, 0, 0)
        val.Size = UDim2.new(0.35, 0, 1, 0)
        val.Font = Enum.Font.GothamBlack
        val.TextScaled = true
        val.TextSize = 20
        val.TextColor3 = GOLD
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.Text = valueText
        val.Parent = row
    end

    local function buildCareerSection(parent, title, stats, profileData)
        local section = Instance.new("Frame")
        section.Name = title .. "Section"
        section.BackgroundColor3 = NAVY_LIGHT
        section.BackgroundTransparency = 0.2
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.Size = UDim2.new(1, 0, 0, 0)
        section.Parent = parent
        Instance.new("UICorner", section).CornerRadius = UDim.new(0, px(10))

        local sectionStroke = Instance.new("UIStroke")
        sectionStroke.Color = Color3.fromRGB(55, 62, 95)
        sectionStroke.Thickness = 1
        sectionStroke.Transparency = 0.4
        sectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        sectionStroke.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingLeft = UDim.new(0, px(16))
        sectionPad.PaddingRight = UDim.new(0, px(16))
        sectionPad.PaddingTop = UDim.new(0, px(12))
        sectionPad.PaddingBottom = UDim.new(0, px(12))
        sectionPad.Parent = section

        local sectionLayout = Instance.new("UIListLayout")
        sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
        sectionLayout.Padding = UDim.new(0, px(6))
        sectionLayout.Parent = section

        local header = Instance.new("TextLabel")
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, 0, 0, px(28))
        header.Font = Enum.Font.GothamBlack
        header.TextScaled = true
        header.TextSize = 22
        header.TextColor3 = GOLD
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Text = string.upper(title)
        header.LayoutOrder = 1
        header.Parent = section

        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, 0, 0, 1)
        sep.BackgroundColor3 = GOLD_DIM
        sep.BackgroundTransparency = 0.65
        sep.BorderSizePixel = 0
        sep.LayoutOrder = 2
        sep.Parent = section

        for i, stat in ipairs(stats) do
            local rawValue = profileData[stat.key] or 0
            local valueText = stat.formatter and stat.formatter(rawValue) or formatStatNumber(rawValue)
            local row = Instance.new("Frame")
            row.Name = stat.key
            row.Size = UDim2.new(1, 0, 0, px(40))
            row.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(18, 20, 38) or Color3.fromRGB(24, 28, 52)
            row.BackgroundTransparency = (i % 2 == 0) and 0.2 or 0.45
            row.LayoutOrder = i + 2
            row.Parent = section
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(4))

            local rowPad = Instance.new("UIPadding")
            rowPad.PaddingLeft = UDim.new(0, px(10))
            rowPad.PaddingRight = UDim.new(0, px(10))
            rowPad.Parent = row

            local nameLbl = Instance.new("TextLabel")
            nameLbl.BackgroundTransparency = 1
            nameLbl.Size = UDim2.new(0.65, 0, 1, 0)
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextScaled = true
            nameLbl.TextSize = 18
            nameLbl.TextColor3 = WHITE
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.Text = stat.label
            nameLbl.Parent = row

            local valLbl = Instance.new("TextLabel")
            valLbl.BackgroundTransparency = 1
            valLbl.Position = UDim2.new(0.65, 0, 0, 0)
            valLbl.Size = UDim2.new(0.35, 0, 1, 0)
            valLbl.Font = Enum.Font.GothamBlack
            valLbl.TextScaled = true
            valLbl.TextSize = 20
            valLbl.TextColor3 = GOLD
            valLbl.TextXAlignment = Enum.TextXAlignment.Right
            valLbl.Text = valueText
            valLbl.Parent = row
        end

        return section
    end

    populateCareerTab = function()
        local targetPlayer = selectedCareerTarget or Players.LocalPlayer
        local isViewingSelf = (targetPlayer == Players.LocalPlayer)

        local ok, profileData
        if isViewingSelf then
            local remote = getCareerStatsRemote()
            if not remote then
                warn("[TeamUI] GetCareerStats remote not found")
                return
            end
            ok, profileData = pcall(function()
                return remote:InvokeServer()
            end)
        else
            local remote = getPublicCareerStatsRemote()
            if not remote then
                warn("[TeamUI] GetPublicCareerStats remote not found")
                return
            end
            ok, profileData = pcall(function()
                return remote:InvokeServer(targetPlayer.UserId)
            end)
        end

        if not ok or type(profileData) ~= "table" then
            if not isViewingSelf then
                selectedCareerTarget = nil
                return populateCareerTab()
            end
            warn("[TeamUI] Failed to fetch career stats:", tostring(profileData))
            return
        end

        clearCareerContainer()

        local layoutOrder = 0
        local function nextOrder()
            layoutOrder += 1
            return layoutOrder
        end

        local profileFrame = Instance.new("Frame")
        profileFrame.Name = "ProfileHeader"
        profileFrame.Size = UDim2.new(1, 0, 0, px(150))
        profileFrame.BackgroundColor3 = NAVY_LIGHT
        profileFrame.BackgroundTransparency = 0.15
        profileFrame.LayoutOrder = nextOrder()
        profileFrame.Parent = careerContainer
        Instance.new("UICorner", profileFrame).CornerRadius = UDim.new(0, px(10))

        local profileStroke = Instance.new("UIStroke")
        profileStroke.Color = GOLD_DIM
        profileStroke.Thickness = 1.2
        profileStroke.Transparency = 0.35
        profileStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        profileStroke.Parent = profileFrame

        local profPad = Instance.new("UIPadding")
        profPad.PaddingLeft = UDim.new(0, px(20))
        profPad.PaddingRight = UDim.new(0, px(20))
        profPad.PaddingTop = UDim.new(0, px(14))
        profPad.PaddingBottom = UDim.new(0, px(14))
        profPad.Parent = profileFrame

        local avatarSize = px(96)
        local avatarFrame = Instance.new("ImageLabel")
        avatarFrame.Size = UDim2.new(0, avatarSize, 0, avatarSize)
        avatarFrame.Position = UDim2.new(0, 0, 0.5, 0)
        avatarFrame.AnchorPoint = Vector2.new(0, 0.5)
        avatarFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
        avatarFrame.BackgroundTransparency = 0.2
        avatarFrame.Parent = profileFrame
        Instance.new("UICorner", avatarFrame).CornerRadius = UDim.new(0, px(12))

        local avatarStroke = Instance.new("UIStroke")
        avatarStroke.Color = GOLD_DIM
        avatarStroke.Thickness = 1.5
        avatarStroke.Transparency = 0.3
        avatarStroke.Parent = avatarFrame

        task.spawn(function()
            local okA, url = pcall(function()
                return Players:GetUserThumbnailAsync(targetPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
            end)
            if okA and url and avatarFrame and avatarFrame.Parent then
                avatarFrame.Image = url
            end
        end)

        local infoX = avatarSize + px(16)

        local displayNameLabel = Instance.new("TextLabel")
        displayNameLabel.Size = UDim2.new(1, -infoX, 0, px(34))
        displayNameLabel.Position = UDim2.new(0, infoX, 0, px(4))
        displayNameLabel.BackgroundTransparency = 1
        displayNameLabel.Font = Enum.Font.GothamBlack
        displayNameLabel.TextScaled = true
        displayNameLabel.TextSize = 30
        displayNameLabel.TextColor3 = GOLD
        displayNameLabel.TextXAlignment = Enum.TextXAlignment.Left
        displayNameLabel.Text = profileData._DisplayName or targetPlayer.DisplayName
        displayNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        displayNameLabel.Parent = profileFrame

        local usernameLabel = Instance.new("TextLabel")
        usernameLabel.Size = UDim2.new(1, -infoX, 0, px(22))
        usernameLabel.Position = UDim2.new(0, infoX, 0, px(36))
        usernameLabel.BackgroundTransparency = 1
        usernameLabel.Font = Enum.Font.Gotham
        usernameLabel.TextScaled = true
        usernameLabel.TextSize = 18
        usernameLabel.TextColor3 = GRAY
        usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
        usernameLabel.Text = "@" .. (profileData._Username or targetPlayer.Name)
        usernameLabel.Parent = profileFrame

        local playerLevel = profileData._Level or 1
        local playerXP = profileData._XP or 0
        local xpToNext = profileData._XPToNext or 100
        local totalXP = profileData._TotalXP or profileData.TotalXP or 0

        local levelLabel = Instance.new("TextLabel")
        levelLabel.Size = UDim2.new(0.5, -infoX / 2, 0, px(26))
        levelLabel.Position = UDim2.new(0, infoX, 0, px(62))
        levelLabel.BackgroundTransparency = 1
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextScaled = true
        levelLabel.TextSize = 20
        levelLabel.TextColor3 = WHITE
        levelLabel.TextXAlignment = Enum.TextXAlignment.Left
        levelLabel.Text = "Level " .. tostring(playerLevel)
        levelLabel.Parent = profileFrame

        local xpLabel = Instance.new("TextLabel")
        xpLabel.Size = UDim2.new(0.5, 0, 0, px(22))
        xpLabel.Position = UDim2.new(0.5, 0, 0, px(64))
        xpLabel.BackgroundTransparency = 1
        xpLabel.Font = Enum.Font.GothamBold
        xpLabel.TextScaled = true
        xpLabel.TextSize = 16
        xpLabel.TextColor3 = GRAY
        xpLabel.TextXAlignment = Enum.TextXAlignment.Right
        xpLabel.Text = formatStatNumber(playerXP) .. " / " .. formatStatNumber(xpToNext) .. " XP"
        xpLabel.Parent = profileFrame

        local barBG = Instance.new("Frame")
        barBG.Size = UDim2.new(1, -infoX, 0, px(14))
        barBG.Position = UDim2.new(0, infoX, 0, px(92))
        barBG.BackgroundColor3 = Color3.fromRGB(35, 38, 58)
        barBG.Parent = profileFrame
        Instance.new("UICorner", barBG).CornerRadius = UDim.new(1, 0)

        local fillPct = (xpToNext > 0) and math.clamp(playerXP / xpToNext, 0, 1) or 0
        local barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(fillPct, 0, 1, 0)
        barFill.BackgroundColor3 = GOLD
        barFill.Parent = barBG
        Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

        local wins = profileData.Wins or 0
        local matches = profileData.MatchesPlayed or 0
        local winRate = (matches > 0) and math.floor((wins / matches) * 100 + 0.5) or 0

        local winRateLabel = Instance.new("TextLabel")
        winRateLabel.Size = UDim2.new(0, px(160), 0, px(30))
        winRateLabel.Position = UDim2.new(1, -px(160), 0, px(4))
        winRateLabel.BackgroundColor3 = Color3.fromRGB(22, 38, 34)
        winRateLabel.BackgroundTransparency = 0.3
        winRateLabel.Font = Enum.Font.GothamBold
        winRateLabel.TextScaled = true
        winRateLabel.TextSize = 18
        winRateLabel.TextColor3 = Color3.fromRGB(35, 190, 75)
        winRateLabel.Text = winRate .. "% WIN RATE"
        winRateLabel.Parent = profileFrame
        Instance.new("UICorner", winRateLabel).CornerRadius = UDim.new(0, px(6))

        if not isViewingSelf then
            local viewingBar = Instance.new("Frame")
            viewingBar.Size = UDim2.new(1, 0, 0, px(40))
            viewingBar.BackgroundColor3 = Color3.fromRGB(28, 22, 14)
            viewingBar.BackgroundTransparency = 0.15
            viewingBar.LayoutOrder = nextOrder()
            viewingBar.Parent = careerContainer
            Instance.new("UICorner", viewingBar).CornerRadius = UDim.new(0, px(8))

            local viewingBarPad = Instance.new("UIPadding")
            viewingBarPad.PaddingLeft = UDim.new(0, px(14))
            viewingBarPad.PaddingRight = UDim.new(0, px(8))
            viewingBarPad.Parent = viewingBar

            local viewingLabel = Instance.new("TextLabel")
            viewingLabel.Size = UDim2.new(1, -px(140), 1, 0)
            viewingLabel.BackgroundTransparency = 1
            viewingLabel.Font = Enum.Font.GothamBold
            viewingLabel.TextScaled = true
            viewingLabel.TextSize = 16
            viewingLabel.TextColor3 = GOLD
            viewingLabel.TextXAlignment = Enum.TextXAlignment.Left
            viewingLabel.TextTruncate = Enum.TextTruncate.AtEnd
            viewingLabel.Text = "Viewing: " .. (profileData._DisplayName or targetPlayer.DisplayName)
            viewingLabel.Parent = viewingBar

            local backBtn = Instance.new("TextButton")
            backBtn.Size = UDim2.new(0, px(130), 0, px(28))
            backBtn.Position = UDim2.new(1, -px(130), 0.5, 0)
            backBtn.AnchorPoint = Vector2.new(0, 0.5)
            backBtn.BackgroundColor3 = Color3.fromRGB(40, 18, 18)
            backBtn.BackgroundTransparency = 0.1
            backBtn.Font = Enum.Font.GothamBold
            backBtn.TextScaled = true
            backBtn.TextSize = 14
            backBtn.Text = "Back to My Stats"
            backBtn.TextColor3 = WHITE
            backBtn.AutoButtonColor = false
            backBtn.BorderSizePixel = 0
            backBtn.Parent = viewingBar
            Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, px(6))
            backBtn.MouseButton1Click:Connect(function()
                selectedCareerTarget = nil
                populateCareerTab()
            end)
        end

        local combatSection = buildCareerSection(careerContainer, "Combat", {
            { key = "PlayersEliminated", label = "Players Eliminated" },
            { key = "MonstersEliminated", label = "Monsters Eliminated" },
            { key = "GoblinsEliminated", label = "Goblins Eliminated" },
            { key = "OrcsEliminated", label = "Orcs Eliminated" },
            { key = "OgresEliminated", label = "Ogres Eliminated" },
            { key = "Deaths", label = "Deaths" },
            { key = "TotalDamageDone", label = "Total Damage Done" },
            { key = "HighestEliminationStreak", label = "Highest Elimination Streak" },
        }, profileData)
        combatSection.LayoutOrder = nextOrder()

        local objectiveSection = buildCareerSection(careerContainer, "Objective", {
            { key = "FlagCaptures", label = "Flag Captures" },
            { key = "FlagReturns", label = "Flag Returns" },
        }, profileData)
        objectiveSection.LayoutOrder = nextOrder()

        local progressionSection = buildCareerSection(careerContainer, "Progression", {
            { key = "MatchesPlayed", label = "Matches Played" },
            { key = "Wins", label = "Wins" },
            { key = "MVPs", label = "MVPs" },
            { key = "TotalXP", label = "Total XP" },
            { key = "TotalCoinsEarned", label = "Total Coins Earned" },
            { key = "AchievementPoints", label = "Achievement Points" },
            { key = "QuestsCompleted", label = "Quests Completed" },
        }, profileData)
        progressionSection.LayoutOrder = nextOrder()

        local timeSection = buildCareerSection(careerContainer, "Time", {
            { key = "TotalPlaytimeSeconds", label = "Total Playtime", formatter = formatPlaytime },
        }, profileData)
        timeSection.LayoutOrder = nextOrder()
    end

    local function updateSectionCounts()
        local bCount, rCount, nCount = 0, 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            local tn = getScoreboardTeamName(plr)
            if tn == "Blue" then bCount = bCount + 1 elseif tn == "Red" then rCount = rCount + 1 else nCount = nCount + 1 end
        end
        if TeamDisplayNames and type(TeamDisplayNames.GetUpper) == "function" then
            blueLabel.Text = TeamDisplayNames.GetUpper("Blue") .. " (" .. tostring(bCount) .. ")"
            redLabel.Text = TeamDisplayNames.GetUpper("Red") .. " (" .. tostring(rCount) .. ")"
            neutralLabel.Text = TeamDisplayNames.GetUpper("Neutral") .. " (" .. tostring(nCount) .. ")"
        else
            blueLabel.Text = "Blue (" .. tostring(bCount) .. ")"
            redLabel.Text = "Red (" .. tostring(rCount) .. ")"
            neutralLabel.Text = "Neutral (" .. tostring(nCount) .. ")"
        end
    end

    local function updateRow(plr)
        local info = playerRows[plr]
        if not info then return end
        for _, col in ipairs(COLUMNS) do
            if col.key ~= "Name" and col.key ~= "Avatar" and info.cells[col.key] then
	            info.cells[col.key].Text = tostring(getPlayerStat(plr, col.key))
            end
        end
        updateSectionCounts()
    end

    local function sortTeamSection(section, teamName)
        local teamPlayers = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if getScoreboardTeamName(plr) == teamName and playerRows[plr] then
                table.insert(teamPlayers, plr)
            end
        end
        table.sort(teamPlayers, function(a, b)
            local sa, sb = getPlayerStat(a, "Score"), getPlayerStat(b, "Score")
            if sa ~= sb then return sa > sb end
            return getPlayerStat(a, "Eliminations") > getPlayerStat(b, "Eliminations")
        end)
        for i, plr in ipairs(teamPlayers) do
            playerRows[plr].row.LayoutOrder = i
        end
    end

    local function cleanupPlayerRow(plr)
        local info = playerRows[plr]
        if not info then return end
        if info.row then pcall(function() info.row:Destroy() end) end
        for _, conn in ipairs(info.connections or {}) do pcall(function() conn:Disconnect() end) end
        playerRows[plr] = nil
        updateSectionCounts()
    end

    local function addPlayerRow(plr)
        if playerRows[plr] then return end
        local teamName = getScoreboardTeamName(plr)
        local section = neutralSection
        if teamName == "Blue" then section = blueSection elseif teamName == "Red" then section = redSection end
        local row, cells = createPlayerRow(plr, teamName, 999)
        row.Parent = section
        local connections = {}
        for _, key in ipairs({"Score", "Eliminations", "Deaths", "FlagCaptures", "FlagReturns", "Level"}) do
            table.insert(connections, plr:GetAttributeChangedSignal(key):Connect(function()
                updateRow(plr)
                sortTeamSection(section, teamName)
            end))
        end
        playerRows[plr] = { row = row, cells = cells, connections = connections }
        sortTeamSection(section, teamName)
        updateSectionCounts()
    end

    local function rebuildAll()
        for plr, _ in pairs(playerRows) do cleanupPlayerRow(plr) end
        for _, plr in ipairs(Players:GetPlayers()) do addPlayerRow(plr) end
        updateSectionCounts()
    end

    -- Watch players
    local teamConns = {}
    local function watchPlayer(plr)
        if teamConns[plr] then pcall(function() teamConns[plr]:Disconnect() end) end
        teamConns[plr] = plr:GetPropertyChangedSignal("Team"):Connect(function()
            cleanupPlayerRow(plr)
            addPlayerRow(plr)
        end)
        if host and host.Parent then addPlayerRow(plr) end
    end
    local function unwatchPlayer(plr)
        if teamConns[plr] then pcall(function() teamConns[plr]:Disconnect() end) end
        teamConns[plr] = nil
        cleanupPlayerRow(plr)
    end
    for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
    Players.PlayerAdded:Connect(watchPlayer)
    Players.PlayerRemoving:Connect(unwatchPlayer)

    -- Tab switching
    local function updateTabVisuals()
        if activeTab == "TeamStats" then
            teamStatsTabBtn.BackgroundColor3 = Color3.fromRGB(32, 30, 18)
            teamStatsTabBtn.TextColor3 = GOLD
            careerTabBtn.BackgroundColor3 = NAVY_LIGHT
            careerTabBtn.TextColor3 = GRAY
            teamStatsContainer.Visible = true
            careerContainer.Visible = false
            closePlayerActionPopup()
        else
            careerTabBtn.BackgroundColor3 = Color3.fromRGB(32, 30, 18)
            careerTabBtn.TextColor3 = GOLD
            teamStatsTabBtn.BackgroundColor3 = NAVY_LIGHT
            teamStatsTabBtn.TextColor3 = GRAY
            teamStatsContainer.Visible = false
            careerContainer.Visible = true
            populateCareerTab()
        end
    end

    selectTab = function(tabName)
        activeTab = tabName
        updateTabVisuals()
    end
    updateTabVisuals()

    teamStatsTabBtn.MouseButton1Click:Connect(function() selectTab("TeamStats") end)
    careerTabBtn.MouseButton1Click:Connect(function() selectTab("Career") end)

    -- Initial build
    rebuildAll()

    return host
end

return TeamUI
