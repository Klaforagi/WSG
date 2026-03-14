--------------------------------------------------------------------------------
-- DailyQuestsUI.lua  –  Client-side Quests panel (Daily / Weekly / Achievements)
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / InventoryUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Fetches quest data from server via Remotes.GetQuests RemoteFunction.
-- Listens for live progress updates via Remotes.QuestProgress RemoteEvent.
-- Claims rewards via Remotes.ClaimQuest RemoteFunction.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / ShopUI / OptionsUI)
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- Palette (matches SideUI neutral-gray / gold theme)
--------------------------------------------------------------------------------
local ROW_BG        = Color3.fromRGB(28, 28, 33)
local SIDEBAR_BG    = Color3.fromRGB(20, 20, 24)
local TAB_ACTIVE_BG = Color3.fromRGB(36, 33, 18)   -- subtle warm tint for selected tab
local CARD_STROKE   = Color3.fromRGB(60, 60, 64)
local GOLD          = Color3.fromRGB(255, 215, 80)
local WHITE         = Color3.fromRGB(240, 240, 240)
local DIM_TEXT      = Color3.fromRGB(160, 160, 165)
local BAR_BG        = Color3.fromRGB(50, 50, 55)
local BAR_FILL      = GOLD
local BTN_CLAIM     = Color3.fromRGB(50, 180, 80)
local BTN_CLAIMED   = Color3.fromRGB(80, 80, 85)
local BTN_LOCKED    = Color3.fromRGB(64, 64, 68)

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- Remotes (resolved lazily with WaitForChild)
--------------------------------------------------------------------------------
local remotesFolder
local getQuestsRF
local claimQuestRF
local questProgressRE

local function ensureRemotes()
    if remotesFolder then return true end
    remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return false end
    getQuestsRF     = remotesFolder:WaitForChild("GetQuests", 5)
    claimQuestRF    = remotesFolder:WaitForChild("ClaimQuest", 5)
    questProgressRE = remotesFolder:WaitForChild("QuestProgress", 5)
    return getQuestsRF ~= nil
end

--------------------------------------------------------------------------------
-- Connection cleanup
--------------------------------------------------------------------------------
local activeConnections = {}

local function trackConn(conn)
    table.insert(activeConnections, conn)
end

local function cleanupConnections()
    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}
end

--------------------------------------------------------------------------------
-- Coin icon widget – gold circular coin built from Frames (no asset id needed)
--------------------------------------------------------------------------------
local function makeCoinIcon(parentFrame, size)
    local coin = Instance.new("Frame")
    coin.Name            = "CoinIcon"
    coin.Size            = UDim2.new(0, size, 0, size)
    coin.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
    coin.BorderSizePixel = 0

    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)   -- perfect circle
    cr.Parent = coin

    local stroke = Instance.new("UIStroke")
    stroke.Color             = Color3.fromRGB(172, 125, 10)
    stroke.Thickness         = math.max(1, math.floor(size * 0.1))
    stroke.ApplyStrokeMode   = Enum.ApplyStrokeMode.Border
    stroke.Parent            = coin

    -- Specular highlight (small bright dot, top-left)
    local hl = Instance.new("Frame")
    hl.Name                  = "Highlight"
    local hlS                = math.max(2, math.floor(size * 0.28))
    hl.Size                  = UDim2.new(0, hlS, 0, hlS)
    hl.Position              = UDim2.new(0, math.floor(size * 0.22), 0, math.floor(size * 0.16))
    hl.BackgroundColor3      = Color3.fromRGB(255, 245, 185)
    hl.BackgroundTransparency = 0.3
    hl.BorderSizePixel       = 0
    local hlcr = Instance.new("UICorner")
    hlcr.CornerRadius = UDim.new(0.5, 0)
    hlcr.Parent = hl
    hl.Parent = coin

    coin.Parent = parentFrame
    return coin
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local DailyQuestsUI = {}

function DailyQuestsUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return nil end

    -- Cleanup from previous open
    cleanupConnections()

    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
            and not c:IsA("UIPadding") then
            pcall(function() c:Destroy() end)
        end
    end

    -- Ensure remotes are available
    if not ensureRemotes() then
        local errLabel = Instance.new("TextLabel")
        errLabel.BackgroundTransparency = 1
        errLabel.Font      = Enum.Font.GothamMedium
        errLabel.Text      = "Quests unavailable – please try again."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize  = px(16)
        errLabel.Size      = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent    = parent
        return nil
    end

    -- Fetch quest data from server
    local quests = {}
    pcall(function()
        quests = getQuestsRF:InvokeServer()
    end)
    if type(quests) ~= "table" then quests = {} end

    ---------------------------------------------------------------------------
    -- Layout constants
    ---------------------------------------------------------------------------
    local TAB_W   = px(160)   -- accommodates "Achievements" with comfortable side padding
    local TAB_GAP = px(10)
    local CARD_H  = px(106)   -- card height + spacing gap
    local HDR_H   = px(58)    -- header + subheader region

    local dailyH = HDR_H + math.max(1, #quests) * CARD_H + px(24)
    local rootH  = math.max(dailyH, px(220))

    ---------------------------------------------------------------------------
    -- Root container (single direct child of the ScrollingFrame parent)
    ---------------------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name                = "QuestsRoot"
    root.BackgroundTransparency = 1
    root.Size                = UDim2.new(1, 0, 0, rootH)
    root.LayoutOrder         = 1
    root.ClipsDescendants    = false
    root.Parent              = parent

    ---------------------------------------------------------------------------
    -- Left sidebar
    ---------------------------------------------------------------------------
    local sidebar = Instance.new("Frame")
    sidebar.Name             = "TabSidebar"
    sidebar.BackgroundColor3 = SIDEBAR_BG
    sidebar.BorderSizePixel  = 0
    sidebar.Size             = UDim2.new(0, TAB_W, 1, 0)
    sidebar.Position         = UDim2.new(0, 0, 0, 0)
    sidebar.ClipsDescendants = false
    sidebar.Parent           = root

    local sideCorner = Instance.new("UICorner")
    sideCorner.CornerRadius = UDim.new(0, px(6))
    sideCorner.Parent = sidebar

    local sideStroke = Instance.new("UIStroke")
    sideStroke.Color        = CARD_STROKE
    sideStroke.Thickness    = 1
    sideStroke.Transparency = 0.4
    sideStroke.Parent       = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    sideLayout.Padding             = UDim.new(0, px(3))
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent              = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop    = UDim.new(0, px(8))
    sidePad.PaddingBottom = UDim.new(0, px(8))
    sidePad.PaddingLeft   = UDim.new(0, px(4))
    sidePad.PaddingRight  = UDim.new(0, px(4))
    sidePad.Parent        = sidebar

    ---------------------------------------------------------------------------
    -- Content area (right of sidebar)
    ---------------------------------------------------------------------------
    local contentArea = Instance.new("Frame")
    contentArea.Name                = "ContentArea"
    contentArea.BackgroundTransparency = 1
    contentArea.Size                = UDim2.new(1, -(TAB_W + TAB_GAP), 1, 0)
    contentArea.Position            = UDim2.new(0, TAB_W + TAB_GAP, 0, 0)
    contentArea.ClipsDescendants    = false
    contentArea.Parent              = root

    ---------------------------------------------------------------------------
    -- Tab definitions
    ---------------------------------------------------------------------------
    local TAB_DEFS = {
        { id = "daily",  icon = "\u{25C6}", label = "Daily",        order = 1 },   -- ◆
        { id = "weekly", icon = "\u{25C8}", label = "Weekly",       order = 2 },   -- ◈
        { id = "achiev", icon = "\u{2605}", label = "Achievements", order = 3 },   -- ★
    }

    local tabButtons   = {}  -- [id] -> TextButton
    local contentPages = {}  -- [id] -> Frame

    ---------------------------------------------------------------------------
    -- Helper: build one sidebar tab button
    ---------------------------------------------------------------------------
    local function makeTabButton(iconChar, labelText, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Name            = labelText .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size            = UDim2.new(1, -px(2), 0, px(58))
        btn.LayoutOrder     = layoutOrder
        btn.Text            = ""
        btn.Parent          = sidebar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(5))
        btnCorner.Parent = btn

        -- Active indicator bar (left edge, hidden by default)
        local bar = Instance.new("Frame")
        bar.Name                 = "ActiveBar"
        bar.BackgroundColor3     = GOLD
        bar.BorderSizePixel      = 0
        bar.Size                 = UDim2.new(0, px(3), 0.65, 0)
        bar.AnchorPoint          = Vector2.new(0, 0.5)
        bar.Position             = UDim2.new(0, 0, 0.5, 0)
        bar.BackgroundTransparency = 1
        local barCr = Instance.new("UICorner")
        barCr.CornerRadius = UDim.new(0.5, 0)
        barCr.Parent = bar
        bar.Parent = btn

        -- Icon glyph
        local iconLbl = Instance.new("TextLabel")
        iconLbl.Name                = "Icon"
        iconLbl.BackgroundTransparency = 1
        iconLbl.Font                = Enum.Font.GothamBold
        iconLbl.Text                = iconChar
        iconLbl.TextColor3          = DIM_TEXT
        iconLbl.TextSize            = math.max(14, math.floor(px(16)))
        iconLbl.Size                = UDim2.new(1, 0, 0, px(22))
        iconLbl.Position            = UDim2.new(0, 0, 0, px(7))
        iconLbl.TextXAlignment      = Enum.TextXAlignment.Center
        iconLbl.Parent              = btn

        -- Text label
        local textLbl = Instance.new("TextLabel")
        textLbl.Name                = "Label"
        textLbl.BackgroundTransparency = 1
        textLbl.Font                = Enum.Font.GothamBold
        textLbl.Text                = labelText
        textLbl.TextColor3          = DIM_TEXT
        textLbl.TextSize            = math.max(10, math.floor(px(12)))
        textLbl.Size                = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position            = UDim2.new(0, px(3), 0, px(30))
        textLbl.TextXAlignment      = Enum.TextXAlignment.Center
        textLbl.TextTruncate        = Enum.TextTruncate.None
        textLbl.Parent              = btn

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1
        stroke.Transparency = 0.7
        stroke.Parent       = btn

        return btn
    end

    ---------------------------------------------------------------------------
    -- Create tab buttons
    ---------------------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        tabButtons[def.id] = makeTabButton(def.icon, def.label, def.order)
    end

    ---------------------------------------------------------------------------
    -- Active-tab state management
    ---------------------------------------------------------------------------
    local currentTab = "daily"

    local function setActiveTab(tabId)
        currentTab = tabId
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)

            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar   = btn:FindFirstChild("ActiveBar")
            local icon  = btn:FindFirstChild("Icon")
            local label = btn:FindFirstChild("Label")
            local stroke = btn:FindFirstChildOfClass("UIStroke")

            if bar    then bar.BackgroundTransparency   = active and 0    or 1    end
            if icon   then icon.TextColor3              = active and GOLD  or DIM_TEXT end
            if label  then label.TextColor3             = active and WHITE or DIM_TEXT end
            if stroke then stroke.Transparency          = active and 0.35 or 0.7  end
        end
        for id, page in pairs(contentPages) do
            page.Visible = (id == tabId)
        end
    end

    ---------------------------------------------------------------------------
    -- Wire tab button clicks + hover feedback
    ---------------------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        local id  = def.id
        local btn = tabButtons[id]

        trackConn(btn.MouseButton1Click:Connect(function()
            setActiveTab(id)
        end))
        trackConn(btn.MouseEnter:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(30, 28, 18)}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = SIDEBAR_BG}):Play()
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Helper: create a content page Frame (with UIListLayout)
    ---------------------------------------------------------------------------
    local function makePage(name, visible)
        local page = Instance.new("Frame")
        page.Name               = name
        page.BackgroundTransparency = 1
        page.Size               = UDim2.new(1, 0, 0, rootH)
        page.Visible            = visible
        page.ClipsDescendants   = false

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding   = UDim.new(0, px(6))
        layout.Parent    = page

        page.Parent = contentArea
        return page
    end

    ---------------------------------------------------------------------------
    -- Helper: make a gold section header
    ---------------------------------------------------------------------------
    local function makeHeader(text, subText, parentFrame)
        local hdr = Instance.new("TextLabel")
        hdr.Name                = "SectionHeader"
        hdr.BackgroundTransparency = 1
        hdr.Font                = Enum.Font.GothamBold
        hdr.Text                = text
        hdr.TextColor3          = GOLD
        hdr.TextSize            = math.max(16, math.floor(px(18)))
        hdr.TextXAlignment      = Enum.TextXAlignment.Left
        hdr.Size                = UDim2.new(1, 0, 0, px(28))
        hdr.LayoutOrder         = 1
        hdr.Parent              = parentFrame

        local sub = Instance.new("TextLabel")
        sub.Name                = "SubHeader"
        sub.BackgroundTransparency = 1
        sub.Font                = Enum.Font.GothamMedium
        sub.Text                = subText
        sub.TextColor3          = DIM_TEXT
        sub.TextSize            = math.max(11, math.floor(px(12)))
        sub.TextXAlignment      = Enum.TextXAlignment.Left
        sub.Size                = UDim2.new(1, 0, 0, px(20))
        sub.LayoutOrder         = 2
        sub.Parent              = parentFrame
    end

    ---------------------------------------------------------------------------
    -- Helper: placeholder block (for Weekly / Achievements)
    ---------------------------------------------------------------------------
    local function makePlaceholder(message, layoutOrder, parentFrame)
        local block = Instance.new("Frame")
        block.Name              = "Placeholder"
        block.BackgroundColor3  = ROW_BG
        block.Size              = UDim2.new(1, 0, 0, px(110))
        block.LayoutOrder       = layoutOrder
        block.Parent            = parentFrame

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, px(8))
        bc.Parent = block

        local bs = Instance.new("UIStroke")
        bs.Color        = CARD_STROKE
        bs.Thickness    = 1
        bs.Transparency = 0.4
        bs.Parent       = block

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Font            = Enum.Font.GothamMedium
        lbl.Text            = message
        lbl.TextColor3      = DIM_TEXT
        lbl.TextSize        = math.max(13, math.floor(px(14)))
        lbl.Size            = UDim2.new(1, 0, 1, 0)
        lbl.TextXAlignment  = Enum.TextXAlignment.Center
        lbl.Parent          = block
    end

    ---------------------------------------------------------------------------
    -- DAILY page
    ---------------------------------------------------------------------------
    local dailyPage = makePage("DailyPage", true)
    contentPages["daily"] = dailyPage

    makeHeader("DAILY QUESTS", "Complete quests to earn coin rewards. Resets daily!", dailyPage)

    if #quests == 0 then
        makePlaceholder("No quests available today.", 3, dailyPage)
    end

    ---------------------------------------------------------------------------
    -- Lookup tables for live updates
    ---------------------------------------------------------------------------
    local progressBars  = {}
    local progressTexts = {}
    local claimButtons  = {}
    local questGoals    = {}
    local questClaimed  = {}

    ---------------------------------------------------------------------------
    -- Quest cards (Daily)
    ---------------------------------------------------------------------------
    for i, quest in ipairs(quests) do
        questGoals[quest.id]   = quest.goal
        questClaimed[quest.id] = quest.claimed

        local card = Instance.new("Frame")
        card.Name             = "Quest_" .. quest.id
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, 0, 0, px(100))
        card.LayoutOrder      = 10 + i
        card.Parent           = dailyPage

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(8))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1
        stroke.Transparency = 0.4
        stroke.Parent       = card

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(12))
        pad.PaddingRight  = UDim.new(0, px(12))
        pad.PaddingTop    = UDim.new(0, px(10))
        pad.PaddingBottom = UDim.new(0, px(10))
        pad.Parent        = card

        -- Title
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name               = "Title"
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font               = Enum.Font.GothamBold
        titleLbl.Text               = quest.title
        titleLbl.TextColor3         = WHITE
        titleLbl.TextSize           = math.max(14, math.floor(px(15)))
        titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
        titleLbl.Size               = UDim2.new(0.62, 0, 0, px(20))
        titleLbl.Position           = UDim2.new(0, 0, 0, 0)
        titleLbl.Parent             = card

        -- Reward row (right of title): coin icon + amount
        local rewardRow = Instance.new("Frame")
        rewardRow.Name              = "RewardRow"
        rewardRow.BackgroundTransparency = 1
        rewardRow.Size              = UDim2.new(0.38, 0, 0, px(20))
        rewardRow.Position          = UDim2.new(0.62, 0, 0, 0)
        rewardRow.Parent            = card

        local coinSize = px(16)
        local amtW     = px(50)

        -- Coin icon (anchored to right side, just left of amount)
        local coinIcon = makeCoinIcon(rewardRow, coinSize)
        coinIcon.AnchorPoint = Vector2.new(1, 0.5)
        coinIcon.Position    = UDim2.new(1, -(amtW + px(3)), 0.5, 0)

        -- Amount label
        local amtLbl = Instance.new("TextLabel")
        amtLbl.Name                = "Amount"
        amtLbl.BackgroundTransparency = 1
        amtLbl.Font                = Enum.Font.GothamBold
        amtLbl.Text                = tostring(quest.reward)
        amtLbl.TextColor3          = GOLD
        amtLbl.TextSize            = math.max(13, math.floor(px(14)))
        amtLbl.TextXAlignment      = Enum.TextXAlignment.Right
        amtLbl.Size                = UDim2.new(0, amtW, 1, 0)
        amtLbl.AnchorPoint         = Vector2.new(1, 0)
        amtLbl.Position            = UDim2.new(1, 0, 0, 0)
        amtLbl.Parent              = rewardRow

        -- Description
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "Desc"
        descLbl.BackgroundTransparency = 1
        descLbl.Font               = Enum.Font.GothamMedium
        descLbl.Text               = quest.desc
        descLbl.TextColor3         = DIM_TEXT
        descLbl.TextSize           = math.max(11, math.floor(px(12)))
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.Size               = UDim2.new(1, 0, 0, px(16))
        descLbl.Position           = UDim2.new(0, 0, 0, px(22))
        descLbl.Parent             = card

        -- Progress bar track
        local barY = px(44)
        local barH = px(14)
        local track = Instance.new("Frame")
        track.Name             = "BarTrack"
        track.BackgroundColor3 = BAR_BG
        track.Size             = UDim2.new(0.65, 0, 0, barH)
        track.Position         = UDim2.new(0, 0, 0, barY)
        track.Parent           = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, px(4))
        trackCorner.Parent = track

        -- Progress bar fill
        local pct = (quest.goal > 0) and math.clamp(quest.progress / quest.goal, 0, 1) or 0
        local fill = Instance.new("Frame")
        fill.Name             = "BarFill"
        fill.BackgroundColor3 = BAR_FILL
        fill.Size             = UDim2.new(pct, 0, 1, 0)
        fill.Parent           = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, px(4))
        fillCorner.Parent = fill

        progressBars[quest.id] = fill

        -- Progress text (e.g., "3/5")
        local progText = Instance.new("TextLabel")
        progText.Name               = "ProgressText"
        progText.BackgroundTransparency = 1
        progText.Font               = Enum.Font.GothamBold
        progText.Text               = tostring(quest.progress) .. "/" .. tostring(quest.goal)
        progText.TextColor3         = WHITE
        progText.TextSize           = math.max(11, math.floor(px(12)))
        progText.Size               = UDim2.new(1, 0, 1, 0)
        progText.Parent             = track

        progressTexts[quest.id] = progText

        -- Claim button
        local btnW2 = px(90)
        local btnH  = px(30)
        local btn = Instance.new("TextButton")
        btn.Name            = "ClaimBtn"
        btn.AutoButtonColor = false
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = math.max(12, math.floor(px(13)))
        btn.Size            = UDim2.new(0, btnW2, 0, btnH)
        btn.AnchorPoint     = Vector2.new(1, 0)
        btn.Position        = UDim2.new(1, 0, 0, barY - px(2))
        btn.Parent          = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(6))
        btnCorner.Parent = btn

        claimButtons[quest.id] = btn

        -- Button state helper
        local function updateButtonState(progress, goal, claimed)
            if claimed then
                btn.Text             = "CLAIMED"
                btn.BackgroundColor3 = BTN_CLAIMED
                btn.TextColor3       = DIM_TEXT
                btn.Active           = false
            elseif progress >= goal then
                btn.Text             = "CLAIM"
                btn.BackgroundColor3 = BTN_CLAIM
                btn.TextColor3       = WHITE
                btn.Active           = true
            else
                btn.Text             = tostring(progress) .. "/" .. tostring(goal)
                btn.BackgroundColor3 = BTN_LOCKED
                btn.TextColor3       = DIM_TEXT
                btn.Active           = false
            end
        end

        updateButtonState(quest.progress, quest.goal, quest.claimed)

        -- Claim handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if questClaimed[quest.id] then return end
            if not btn.Active then return end

            btn.Active = false
            btn.Text   = "..."

            local success = false
            pcall(function()
                success = claimQuestRF:InvokeServer(quest.id)
            end)

            if success then
                questClaimed[quest.id] = true
                updateButtonState(quest.goal, quest.goal, true)
                -- Flash gold
                local origColor = card.BackgroundColor3
                TweenService:Create(card, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(60, 55, 25)}):Play()
                task.delay(0.3, function()
                    if card and card.Parent then
                        TweenService:Create(card, TWEEN_QUICK,
                            {BackgroundColor3 = origColor}):Play()
                    end
                end)
                if _G.UpdateShopHeaderCoins then
                    pcall(_G.UpdateShopHeaderCoins)
                end
            else
                updateButtonState(quest.progress, quest.goal, false)
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- WEEKLY page (placeholder – ready for full data when implemented)
    ---------------------------------------------------------------------------
    local weeklyPage = makePage("WeeklyPage", false)
    contentPages["weekly"] = weeklyPage

    makeHeader("WEEKLY QUESTS", "Larger challenges – resets every Monday!", weeklyPage)
    makePlaceholder("Weekly quests coming soon.", 3, weeklyPage)

    ---------------------------------------------------------------------------
    -- ACHIEVEMENTS page (placeholder)
    ---------------------------------------------------------------------------
    local achievPage = makePage("AchievPage", false)
    contentPages["achiev"] = achievPage

    makeHeader("ACHIEVEMENTS", "Track your progress and milestones.", achievPage)
    makePlaceholder("Achievements coming soon.", 3, achievPage)

    ---------------------------------------------------------------------------
    -- Activate default tab
    ---------------------------------------------------------------------------
    setActiveTab("daily")

    ---------------------------------------------------------------------------
    -- Live progress updates from server
    ---------------------------------------------------------------------------
    if questProgressRE then
        trackConn(questProgressRE.OnClientEvent:Connect(function(questId, newProgress)
            if type(questId) ~= "string" then return end
            newProgress = tonumber(newProgress) or 0
            local goal = questGoals[questId]
            if not goal then return end
            if questClaimed[questId] then return end

            local pct2 = math.clamp(newProgress / goal, 0, 1)

            local fillBar = progressBars[questId]
            if fillBar and fillBar.Parent then
                TweenService:Create(fillBar, TWEEN_QUICK,
                    {Size = UDim2.new(pct2, 0, 1, 0)}):Play()
            end

            local txt = progressTexts[questId]
            if txt and txt.Parent then
                txt.Text = tostring(math.min(newProgress, goal)) .. "/" .. tostring(goal)
            end

            local claimBtn = claimButtons[questId]
            if claimBtn and claimBtn.Parent then
                if newProgress >= goal then
                    claimBtn.Text             = "CLAIM"
                    claimBtn.BackgroundColor3 = BTN_CLAIM
                    claimBtn.TextColor3       = WHITE
                    claimBtn.Active           = true
                else
                    claimBtn.Text             = tostring(newProgress) .. "/" .. tostring(goal)
                    claimBtn.BackgroundColor3 = BTN_LOCKED
                    claimBtn.TextColor3       = DIM_TEXT
                    claimBtn.Active           = false
                end
            end
        end))
    end

    return parent
end

return DailyQuestsUI
