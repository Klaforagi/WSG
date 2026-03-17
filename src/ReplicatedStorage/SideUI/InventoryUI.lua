--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Sectioned inventory (Melee · Ranged · Special)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- Palette (sourced from shared UITheme – Team menu visual language)
local CARD_BG       = UITheme.CARD_BG
local CARD_EQUIPPED = UITheme.CARD_OWNED
local CARD_STROKE   = UITheme.CARD_STROKE
local ICON_BG       = UITheme.ICON_BG
local GOLD          = UITheme.GOLD
local WHITE         = UITheme.WHITE
local DIM_TEXT      = UITheme.DIM_TEXT
local BTN_BG        = UITheme.BTN_BG
local BTN_STROKE_C  = UITheme.BTN_STROKE
local GREEN_GLOW    = UITheme.GREEN_GLOW
local DISABLED_BG   = UITheme.DISABLED_BG
local SIDEBAR_BG    = UITheme.SIDEBAR_BG
local TAB_ACTIVE_BG = UITheme.TAB_ACTIVE

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local TAB_DEFS = {
    { id = "weapons", icon = "\u{2694}", label = "Weapons", order = 1 },
    { id = "boosts",  icon = "\u{26A1}", label = "Boosts",  order = 2 },
}

local InventoryUI = {}

local BoostConfig = nil
local AssetCodes = nil
local boostRemotes = nil

local function safeRequireBoostConfig()
    local mod = ReplicatedStorage:FindFirstChild("BoostConfig")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then
            return result
        end
    end
    return nil
end

local function safeRequireAssetCodes()
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then
            return result
        end
    end
    return nil
end

local BOOST_ACCENT_COLORS = {
    coins_2x = Color3.fromRGB(255, 200, 40),
    quest_2x = Color3.fromRGB(80, 165, 255),
}

local function getBoostIconImage(def)
    if type(def) ~= "table" then return nil end
    if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then
        return def.IconAssetId
    end
    local key = def.IconKey
    if AssetCodes and type(AssetCodes.Get) == "function" and key then
        local image = AssetCodes.Get(key)
        if type(image) == "string" and #image > 0 then
            return image
        end
    end
    return nil
end

local function ensureBoostRemotes()
    if boostRemotes then return boostRemotes end

    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return nil end

    local boostsFolder = remotesFolder:FindFirstChild("Boosts") or remotesFolder:WaitForChild("Boosts", 5)
    if not boostsFolder then return nil end

    local activateRF = boostsFolder:FindFirstChild("ActivateInventoryBoost")
    local getStatesRF = boostsFolder:FindFirstChild("GetBoostStates")
    local stateUpdatedRE = remotesFolder:FindFirstChild("BoostStateUpdated")
    if not activateRF or not getStatesRF or not stateUpdatedRE then
        return nil
    end

    boostRemotes = {
        activate = activateRF,
        getStates = getStatesRF,
        stateUpdated = stateUpdatedRE,
    }
    return boostRemotes
end

local function showToast(parent, message, color, duration)
    local toast = Instance.new("TextLabel")
    toast.Name = "Toast"
    toast.BackgroundColor3 = Color3.fromRGB(18, 20, 36)
    toast.BackgroundTransparency = 0.08
    toast.Size = UDim2.new(0.85, 0, 0, px(40))
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, px(6))
    toast.Font = Enum.Font.GothamBold
    toast.TextSize = math.max(13, math.floor(px(14)))
    toast.TextColor3 = color or GOLD
    toast.Text = message
    toast.TextWrapped = true
    toast.ZIndex = 400
    toast.Parent = parent

    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0, px(10))
    cr.Parent = toast

    local st = Instance.new("UIStroke")
    st.Color = color or GOLD
    st.Thickness = 1.2
    st.Transparency = 0.35
    st.Parent = toast

    toast.BackgroundTransparency = 1
    toast.TextTransparency = 1
    TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency = 0.15, TextTransparency = 0}):Play()

    task.delay(duration or 2.2, function()
        if toast and toast.Parent then
            local tween = TweenService:Create(toast, TweenInfo.new(0.25), {BackgroundTransparency = 1, TextTransparency = 1})
            tween:Play()
            tween.Completed:Connect(function()
                pcall(function() toast:Destroy() end)
            end)
        end
    end)
end

function InventoryUI.Create(parent, coinApi, inventoryApi)
    if not parent then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") then
            pcall(function() c:Destroy() end)
        end
    end

    local TAB_W = px(130)
    local TAB_GAP = px(10)
    BoostConfig = BoostConfig or safeRequireBoostConfig()
    AssetCodes = AssetCodes or safeRequireAssetCodes()

    local cleanupConnections = {}
    local function trackConn(conn)
        table.insert(cleanupConnections, conn)
    end
    local function cleanup()
        for _, conn in ipairs(cleanupConnections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(cleanupConnections)
    end

    local root = Instance.new("Frame")
    root.Name = "InventoryUI"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 0, px(400))
    root.ZIndex = 240
    root.LayoutOrder = 1
    root.ClipsDescendants = false
    root.Parent = parent

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(6))
    rootPad.Parent = root

    local sidebar = Instance.new("Frame")
    sidebar.Name = "TabSidebar"
    sidebar.BackgroundColor3 = SIDEBAR_BG
    sidebar.BorderSizePixel = 0
    sidebar.Size = UDim2.new(0, TAB_W, 1, 0)
    sidebar.Position = UDim2.new(0, 0, 0, 0)
    sidebar.ClipsDescendants = false
    sidebar.Parent = root

    local sideCorner = Instance.new("UICorner")
    sideCorner.CornerRadius = UDim.new(0, px(10))
    sideCorner.Parent = sidebar

    local sideStroke = Instance.new("UIStroke")
    sideStroke.Color = CARD_STROKE
    sideStroke.Thickness = 1.2
    sideStroke.Transparency = 0.3
    sideStroke.Parent = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sideLayout.Padding = UDim.new(0, px(3))
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop = UDim.new(0, px(10))
    sidePad.PaddingBottom = UDim.new(0, px(10))
    sidePad.PaddingLeft = UDim.new(0, px(6))
    sidePad.PaddingRight = UDim.new(0, px(6))
    sidePad.Parent = sidebar

    local tabButtons = {}
    local contentPages = {}
    local currentTab = "weapons"

    local function makeTabButton(def)
        local btn = Instance.new("TextButton")
        btn.Name = def.label .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size = UDim2.new(1, -px(2), 0, px(62))
        btn.LayoutOrder = def.order
        btn.Text = ""
        btn.Parent = sidebar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        local bar = Instance.new("Frame")
        bar.Name = "ActiveBar"
        bar.BackgroundColor3 = GOLD
        bar.BorderSizePixel = 0
        bar.Size = UDim2.new(0, px(3), 0.6, 0)
        bar.AnchorPoint = Vector2.new(0, 0.5)
        bar.Position = UDim2.new(0, 0, 0.5, 0)
        bar.BackgroundTransparency = 1
        bar.Parent = btn

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0.5, 0)
        barCorner.Parent = bar

        local iconLbl = Instance.new("TextLabel")
        iconLbl.Name = "Icon"
        iconLbl.BackgroundTransparency = 1
        iconLbl.Font = Enum.Font.GothamBold
        iconLbl.Text = def.icon
        iconLbl.TextColor3 = DIM_TEXT
        iconLbl.TextSize = math.max(16, math.floor(px(18)))
        iconLbl.Size = UDim2.new(1, 0, 0, px(24))
        iconLbl.Position = UDim2.new(0, 0, 0, px(8))
        iconLbl.TextXAlignment = Enum.TextXAlignment.Center
        iconLbl.Parent = btn

        local textLbl = Instance.new("TextLabel")
        textLbl.Name = "Label"
        textLbl.BackgroundTransparency = 1
        textLbl.Font = Enum.Font.GothamBold
        textLbl.Text = def.label
        textLbl.TextColor3 = DIM_TEXT
        textLbl.TextSize = math.max(11, math.floor(px(12)))
        textLbl.Size = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position = UDim2.new(0, px(3), 0, px(34))
        textLbl.TextXAlignment = Enum.TextXAlignment.Center
        textLbl.TextTruncate = Enum.TextTruncate.None
        textLbl.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = CARD_STROKE
        btnStroke.Thickness = 1.2
        btnStroke.Transparency = 0.6
        btnStroke.Parent = btn

        return btn
    end

    for _, def in ipairs(TAB_DEFS) do
        tabButtons[def.id] = makeTabButton(def)
    end

    local contentContainer = Instance.new("Frame")
    contentContainer.Name = "ContentArea"
    contentContainer.BackgroundTransparency = 1
    contentContainer.Size = UDim2.new(1, -(TAB_W + TAB_GAP), 0, 0)
    contentContainer.Position = UDim2.new(0, TAB_W + TAB_GAP, 0, 0)
    contentContainer.AutomaticSize = Enum.AutomaticSize.Y
    contentContainer.ClipsDescendants = false
    contentContainer.Parent = root

    local function setActiveTab(tabId)
        currentTab = tabId
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar = btn:FindFirstChild("ActiveBar")
            local icon = btn:FindFirstChild("Icon")
            local label = btn:FindFirstChild("Label")
            local stroke = btn:FindFirstChildOfClass("UIStroke")

            if bar then bar.BackgroundTransparency = active and 0 or 1 end
            if icon then icon.TextColor3 = active and GOLD or DIM_TEXT end
            if label then label.TextColor3 = active and WHITE or DIM_TEXT end
            if stroke then stroke.Transparency = active and 0.2 or 0.6 end
        end

        for id, page in pairs(contentPages) do
            page.Visible = (id == tabId)
        end
    end

    for _, def in ipairs(TAB_DEFS) do
        local id = def.id
        local btn = tabButtons[id]

        btn.MouseButton1Click:Connect(function()
            setActiveTab(id)
        end)
        btn.MouseEnter:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = Color3.fromRGB(28, 26, 18) }):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK, { BackgroundColor3 = SIDEBAR_BG }):Play()
            end
        end)
    end

    local weaponsPage = Instance.new("Frame")
    weaponsPage.Name = "WeaponsPage"
    weaponsPage.BackgroundTransparency = 1
    weaponsPage.Size = UDim2.new(1, 0, 0, 0)
    weaponsPage.AutomaticSize = Enum.AutomaticSize.Y
    weaponsPage.Visible = true
    weaponsPage.Parent = contentContainer

    local weaponsLayout = Instance.new("UIListLayout")
    weaponsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    weaponsLayout.Padding = UDim.new(0, px(16))
    weaponsLayout.Parent = weaponsPage

    local items = inventoryApi and inventoryApi:GetItems() or {}
    -- Normalize legacy item IDs to current names so UI shows correct labels
    if items and type(items) == "table" then
        local normalized = {}
        for _, id in ipairs(items) do
            if type(id) == "string" and tostring(id):lower() == "stick" then
                table.insert(normalized, "Wooden Sword")
            else
                table.insert(normalized, id)
            end
        end
        items = normalized
    end

    -- Assets & presets for classification
    local AssetCodes = nil
    pcall(function()
        local ac = game:GetService("ReplicatedStorage"):FindFirstChild("AssetCodes")
        if ac and ac:IsA("ModuleScript") then AssetCodes = require(ac) end
    end)

    local meleePresets = nil
    pcall(function()
        local mm = game:GetService("ReplicatedStorage"):FindFirstChild("ToolMeleeSettings")
        if mm and mm:IsA("ModuleScript") then
            local ok, mod = pcall(function() return require(mm) end)
            if ok and type(mod) == "table" then meleePresets = mod.presets end
        end
    end)
    local rangedPresets = nil
    pcall(function()
        local rm = game:GetService("ReplicatedStorage"):FindFirstChild("Toolgunsettings")
        if rm and rm:IsA("ModuleScript") then
            local ok, mod = pcall(function() return require(rm) end)
            if ok and type(mod) == "table" and mod.presets then rangedPresets = mod.presets end
        end
    end)

    local function classifyItem(name)
        if not name then return "Ranged" end
        local key = tostring(name):lower()
        -- legacy alias mapping: treat certain historical IDs as melee
        local aliasMap = {
            ["stick"] = "Melee",
        }
        if aliasMap[key] then return aliasMap[key] end
        if meleePresets and meleePresets[key] then return "Melee" end
        if rangedPresets and rangedPresets[key] then return "Ranged" end
        return "Ranged"
    end

    -- Helper: create a section with header + grid
    local function makeSection(parent, id, label)
        local section = Instance.new("Frame")
        section.Name = id .. "_Section"
        section.BackgroundTransparency = 1
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.Parent = parent

        -- stack header + grid vertically, mirror ShopUI spacing
        local sectionLayout = Instance.new("UIListLayout")
        sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
        sectionLayout.Padding = UDim.new(0, px(10))
        sectionLayout.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingTop = UDim.new(0, px(4))
        sectionPad.PaddingBottom = UDim.new(0, px(10))
        sectionPad.PaddingLeft = UDim.new(0, px(8))
        sectionPad.PaddingRight = UDim.new(0, px(8))
        sectionPad.Parent = section

        -- Header wrapper with accent bar (matches Boosts/Quests/Shop header style)
        local headerWrap = Instance.new("Frame")
        headerWrap.Name = "HeaderWrap"
        headerWrap.BackgroundTransparency = 1
        headerWrap.Size = UDim2.new(1, 0, 0, px(40))
        headerWrap.LayoutOrder = 1
        headerWrap.Parent = section

        local header = Instance.new("TextLabel")
        header.Name = "SectionHeader"
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = label
        header.TextColor3 = GOLD
        header.TextSize = math.max(18, math.floor(px(20)))
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Size = UDim2.new(1, 0, 0, px(28))
        header.Position = UDim2.new(0, 0, 0, 0)
        header.Parent = headerWrap

        -- Gold accent bar under header
        local accentBar = Instance.new("Frame")
        accentBar.Name = "AccentBar"
        accentBar.BackgroundColor3 = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.Size = UDim2.new(1, 0, 0, px(2))
        accentBar.Position = UDim2.new(0, 0, 1, -px(2))
        accentBar.BorderSizePixel = 0
        accentBar.Parent = headerWrap

        local grid = Instance.new("Frame")
        grid.Name = id .. "_Grid"
        grid.BackgroundTransparency = 1
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.LayoutOrder = 2
        grid.Parent = section

        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0.30, 0, 0, px(160))
        gridLayout.CellPadding = UDim2.new(0.025, 0, 0, px(12))
        gridLayout.FillDirection = Enum.FillDirection.Horizontal
        gridLayout.FillDirectionMaxCells = 3
        gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gridLayout.Parent = grid

        return section, grid
    end

    -- Create sections stacked vertically
    local meleeSection, meleeGrid = makeSection(weaponsPage, "Melee", "Melee Weapons")
    local rangedSection, rangedGrid = makeSection(weaponsPage, "Ranged", "Ranged Weapons")
    local specialSection, specialGrid = makeSection(weaponsPage, "Special", "Special Weapons")
    meleeSection.LayoutOrder = 1
    rangedSection.LayoutOrder = 2
    specialSection.LayoutOrder = 3

    contentPages.weapons = weaponsPage

    local boostsPage = Instance.new("Frame")
    boostsPage.Name = "BoostsPage"
    boostsPage.BackgroundTransparency = 1
    boostsPage.Size = UDim2.new(1, 0, 0, 0)
    boostsPage.AutomaticSize = Enum.AutomaticSize.Y
    boostsPage.Visible = false
    boostsPage.Parent = contentContainer

    local boostsLayout = Instance.new("UIListLayout")
    boostsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    boostsLayout.Padding = UDim.new(0, px(12))
    boostsLayout.Parent = boostsPage

    local boostsPad = Instance.new("UIPadding")
    boostsPad.PaddingTop = UDim.new(0, px(6))
    boostsPad.PaddingBottom = UDim.new(0, px(12))
    boostsPad.PaddingLeft = UDim.new(0, px(8))
    boostsPad.PaddingRight = UDim.new(0, px(8))
    boostsPad.Parent = boostsPage

    local boostsHeader = Instance.new("Frame")
    boostsHeader.Name = "BoostsHeader"
    boostsHeader.BackgroundTransparency = 1
    boostsHeader.Size = UDim2.new(1, 0, 0, px(54))
    boostsHeader.LayoutOrder = 1
    boostsHeader.Parent = boostsPage

    local boostsTitle = Instance.new("TextLabel")
    boostsTitle.BackgroundTransparency = 1
    boostsTitle.Font = Enum.Font.GothamBold
    boostsTitle.Text = "BOOSTS"
    boostsTitle.TextColor3 = GOLD
    boostsTitle.TextSize = math.max(20, math.floor(px(24)))
    boostsTitle.TextXAlignment = Enum.TextXAlignment.Left
    boostsTitle.Size = UDim2.new(1, 0, 0, px(30))
    boostsTitle.Parent = boostsHeader

    local boostsSubtitle = Instance.new("TextLabel")
    boostsSubtitle.BackgroundTransparency = 1
    boostsSubtitle.Font = Enum.Font.GothamMedium
    boostsSubtitle.Text = "Activate owned boosts when you need them. Activation consumes one stored boost."
    boostsSubtitle.TextColor3 = DIM_TEXT
    boostsSubtitle.TextSize = math.max(11, math.floor(px(12)))
    boostsSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    boostsSubtitle.Size = UDim2.new(1, 0, 0, px(16))
    boostsSubtitle.Position = UDim2.new(0, 0, 0, px(30))
    boostsSubtitle.Parent = boostsHeader

    local boostsAccent = Instance.new("Frame")
    boostsAccent.BackgroundColor3 = GOLD
    boostsAccent.BackgroundTransparency = 0.3
    boostsAccent.BorderSizePixel = 0
    boostsAccent.Size = UDim2.new(1, 0, 0, px(2))
    boostsAccent.Position = UDim2.new(0, 0, 1, -px(2))
    boostsAccent.Parent = boostsHeader

    local helperNote = Instance.new("TextLabel")
    helperNote.BackgroundTransparency = 1
    helperNote.Font = Enum.Font.GothamMedium
    helperNote.Text = "Active boosts continue to drive coin and quest multipliers. Owning a boost does nothing until you activate it here."
    helperNote.TextColor3 = DIM_TEXT
    helperNote.TextSize = math.max(10, math.floor(px(11)))
    helperNote.TextXAlignment = Enum.TextXAlignment.Left
    helperNote.Size = UDim2.new(1, 0, 0, px(14))
    helperNote.LayoutOrder = 2
    helperNote.Parent = boostsPage

    local boostDefs = {}
    if BoostConfig and BoostConfig.Boosts then
        for _, def in ipairs(BoostConfig.Boosts) do
            if not def.InstantUse then
                table.insert(boostDefs, def)
            end
        end
        table.sort(boostDefs, function(a, b)
            return (a.SortOrder or 0) < (b.SortOrder or 0)
        end)
    end

    local remotes = ensureBoostRemotes()
    local boostStates = {}
    local timeDelta = 0
    local boostCards = {}

    local function ingestStates(states)
        if type(states) ~= "table" then return end
        boostStates = states
        timeDelta = os.time() - (states._serverTime or os.time())
    end

    if remotes and remotes.getStates then
        pcall(function()
            ingestStates(remotes.getStates:InvokeServer())
        end)
    end

    local function refreshBoostCards()
        for _, def in ipairs(boostDefs) do
            local refs = boostCards[def.Id]
            local state = boostStates[def.Id] or {}
            if refs then
                local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
                local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + timeDelta
                local active = expiresAt > os.time()

                refs.card.BackgroundColor3 = active and CARD_EQUIPPED or CARD_BG
                refs.cardStroke.Color = active and GREEN_GLOW or CARD_STROKE
                refs.cardStroke.Thickness = active and 1.8 or 1.2
                refs.cardStroke.Transparency = active and 0.3 or 0.35

                refs.owned.Text = string.format("Owned: %d", owned)

                if active then
                    local remaining = math.max(0, expiresAt - os.time())
                    refs.status.Text = string.format("Time Remaining: %02d:%02d", math.floor(remaining / 60), remaining % 60)
                    refs.status.TextColor3 = GREEN_GLOW
                    refs.button.Text = "ACTIVE"
                    refs.button.Active = false
                    refs.button.BackgroundColor3 = DISABLED_BG
                    refs.button.TextColor3 = GREEN_GLOW
                    refs.buttonStroke.Color = GREEN_GLOW
                elseif owned > 0 then
                    refs.status.Text = "Ready to activate"
                    refs.status.TextColor3 = DIM_TEXT
                    refs.button.Text = "ACTIVATE"
                    refs.button.Active = true
                    refs.button.BackgroundColor3 = BTN_BG
                    refs.button.TextColor3 = WHITE
                    refs.buttonStroke.Color = BTN_STROKE_C
                else
                    refs.status.Text = "Not owned"
                    refs.status.TextColor3 = DIM_TEXT
                    refs.button.Text = "UNAVAILABLE"
                    refs.button.Active = false
                    refs.button.BackgroundColor3 = DISABLED_BG
                    refs.button.TextColor3 = DIM_TEXT
                    refs.buttonStroke.Color = CARD_STROKE
                end
            end
        end
    end

    if #boostDefs == 0 or not remotes then
        local unavailable = Instance.new("TextLabel")
        unavailable.BackgroundTransparency = 1
        unavailable.Font = Enum.Font.GothamMedium
        unavailable.Text = "Boost inventory is currently unavailable."
        unavailable.TextColor3 = DIM_TEXT
        unavailable.TextSize = math.max(14, math.floor(px(15)))
        unavailable.Size = UDim2.new(1, 0, 0, px(50))
        unavailable.LayoutOrder = 10
        unavailable.Parent = boostsPage
    else
        for index, def in ipairs(boostDefs) do
            local card = Instance.new("Frame")
            card.Name = "Boost_" .. def.Id
            card.BackgroundColor3 = CARD_BG
            card.Size = UDim2.new(1, 0, 0, px(122))
            card.LayoutOrder = 10 + index
            card.Parent = boostsPage

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, px(12))
            corner.Parent = card

            local stroke = Instance.new("UIStroke")
            stroke.Color = CARD_STROKE
            stroke.Thickness = 1.2
            stroke.Transparency = 0.35
            stroke.Parent = card

            local pad = Instance.new("UIPadding")
            pad.PaddingTop = UDim.new(0, px(12))
            pad.PaddingBottom = UDim.new(0, px(12))
            pad.PaddingLeft = UDim.new(0, px(14))
            pad.PaddingRight = UDim.new(0, px(14))
            pad.Parent = card

            local iconColor = BOOST_ACCENT_COLORS[def.Id] or GOLD
            if type(def.IconColor) == "table" and #def.IconColor >= 3 then
                iconColor = Color3.fromRGB(def.IconColor[1], def.IconColor[2], def.IconColor[3])
            end

            local iconFrame = Instance.new("Frame")
            iconFrame.Name = "BoostIcon"
            iconFrame.Size = UDim2.new(0, px(60), 0, px(60))
            iconFrame.Position = UDim2.new(0, 0, 0.5, 0)
            iconFrame.AnchorPoint = Vector2.new(0, 0.5)
            iconFrame.BackgroundColor3 = iconColor
            iconFrame.BorderSizePixel = 0
            iconFrame.Parent = card

            local iconCorner = Instance.new("UICorner")
            iconCorner.CornerRadius = UDim.new(0, px(8))
            iconCorner.Parent = iconFrame

            local iconStroke = Instance.new("UIStroke")
            iconStroke.Color = WHITE
            iconStroke.Thickness = 1.2
            iconStroke.Transparency = 0.75
            iconStroke.Parent = iconFrame

            local iconImage = Instance.new("ImageLabel")
            iconImage.Name = "BoostIconImage"
            iconImage.BackgroundTransparency = 1
            iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
            iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconImage.Size = UDim2.new(0.72, 0, 0.72, 0)
            iconImage.ScaleType = Enum.ScaleType.Fit
            iconImage.Image = getBoostIconImage(def) or ""
            iconImage.Visible = iconImage.Image ~= ""
            iconImage.Parent = iconFrame

            -- [BoostIconDebug] Verify icon asset matches between Shop and Inventory
            print(string.format("[BoostIconDebug][Inventory] %s -> %s  (visible=%s)",
                tostring(def.Id), tostring(iconImage.Image), tostring(iconImage.Visible)))

            local iconGlyph = Instance.new("TextLabel")
            iconGlyph.Name = "BoostIconGlyph"
            iconGlyph.BackgroundTransparency = 1
            iconGlyph.Size = UDim2.new(1, 0, 1, 0)
            iconGlyph.Font = Enum.Font.GothamBold
            iconGlyph.Text = def.IconGlyph or "?"
            iconGlyph.TextSize = math.max(16, math.floor(px(33)))
            iconGlyph.TextColor3 = WHITE
            iconGlyph.Visible = not iconImage.Visible
            iconGlyph.Parent = iconFrame

            local title = Instance.new("TextLabel")
            title.BackgroundTransparency = 1
            title.Font = Enum.Font.GothamBold
            title.Text = def.DisplayName
            title.TextColor3 = WHITE
            title.TextSize = math.max(16, math.floor(px(18)))
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Size = UDim2.new(0.58, -px(74), 0, px(24))
            title.Position = UDim2.new(0, px(74), 0, 0)
            title.Parent = card

            local desc = Instance.new("TextLabel")
            desc.BackgroundTransparency = 1
            desc.Font = Enum.Font.GothamMedium
            desc.Text = def.Description
            desc.TextColor3 = DIM_TEXT
            desc.TextSize = math.max(11, math.floor(px(12)))
            desc.TextWrapped = true
            desc.TextXAlignment = Enum.TextXAlignment.Left
            desc.TextYAlignment = Enum.TextYAlignment.Top
            desc.Size = UDim2.new(0.58, -px(74), 0, px(42))
            desc.Position = UDim2.new(0, px(74), 0, px(28))
            desc.Parent = card

            local owned = Instance.new("TextLabel")
            owned.BackgroundTransparency = 1
            owned.Font = Enum.Font.GothamBold
            owned.Text = "Owned: 0"
            owned.TextColor3 = WHITE
            owned.TextSize = math.max(11, math.floor(px(12)))
            owned.TextXAlignment = Enum.TextXAlignment.Right
            owned.Size = UDim2.new(0.34, 0, 0, px(18))
            owned.Position = UDim2.new(0.66, 0, 0, px(12))
            owned.Parent = card

            local status = Instance.new("TextLabel")
            status.BackgroundTransparency = 1
            status.Font = Enum.Font.GothamMedium
            status.Text = "Not owned"
            status.TextColor3 = DIM_TEXT
            status.TextSize = math.max(10, math.floor(px(11)))
            status.TextXAlignment = Enum.TextXAlignment.Right
            status.Size = UDim2.new(0.34, 0, 0, px(16))
            status.Position = UDim2.new(0.66, 0, 0, px(34))
            status.Parent = card

            local activateBtn = Instance.new("TextButton")
            activateBtn.Name = "ActivateBtn"
            activateBtn.AutoButtonColor = false
            activateBtn.BackgroundColor3 = BTN_BG
            activateBtn.Font = Enum.Font.GothamBold
            activateBtn.Text = "ACTIVATE"
            activateBtn.TextColor3 = WHITE
            activateBtn.TextSize = math.max(12, math.floor(px(13)))
            activateBtn.Size = UDim2.new(0, px(132), 0, px(36))
            activateBtn.AnchorPoint = Vector2.new(1, 1)
            activateBtn.Position = UDim2.new(1, 0, 1, 0)
            activateBtn.Parent = card

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, px(10))
            btnCorner.Parent = activateBtn

            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = BTN_STROKE_C
            btnStroke.Thickness = 1.3
            btnStroke.Transparency = 0.25
            btnStroke.Parent = activateBtn

            activateBtn.MouseEnter:Connect(function()
                if activateBtn.Active then
                    TweenService:Create(activateBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                end
            end)
            activateBtn.MouseLeave:Connect(function()
                if activateBtn.Active then
                    TweenService:Create(activateBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                end
            end)

            activateBtn.MouseButton1Click:Connect(function()
                local ok, success, message, states = pcall(function()
                    return remotes.activate:InvokeServer(def.Id)
                end)
                if ok and success then
                    ingestStates(states)
                    refreshBoostCards()
                    showToast(boostsPage, "Boost activated.", GREEN_GLOW, 2.2)
                else
                    if ok and type(states) == "table" then
                        ingestStates(states)
                    end
                    refreshBoostCards()
                    if ok and message == "Already active" then
                        local refs = boostCards[def.Id]
                        if refs then
                            refs.status.Text = "Already Active"
                            refs.status.TextColor3 = GOLD
                            task.delay(1.2, function()
                                if refs.card and refs.card.Parent then
                                    refreshBoostCards()
                                end
                            end)
                        end
                    end
                    showToast(boostsPage, tostring((ok and message) or "Activation failed"), RED_TEXT, 2.2)
                end
            end)

            boostCards[def.Id] = {
                card = card,
                cardStroke = stroke,
                owned = owned,
                status = status,
                button = activateBtn,
                buttonStroke = btnStroke,
            }
        end

        refreshBoostCards()

        trackConn(remotes.stateUpdated.OnClientEvent:Connect(function(states)
            ingestStates(states)
            refreshBoostCards()
        end))

        local lastTick = 0
        trackConn(RunService.Heartbeat:Connect(function()
            local now = os.time()
            if now == lastTick then return end
            lastTick = now
            refreshBoostCards()
        end))
    end

    contentPages.boosts = boostsPage

    local GREEN_BTN = Color3.fromRGB(35, 190, 75)
    local GREEN_BTN_STR = Color3.fromRGB(50, 230, 110)
    -- Restore equipped state from inventory API if available (per-category)
    local equippedState = { Melee = nil, Ranged = nil, Special = nil }
    if inventoryApi and inventoryApi.GetEquipped then
        pcall(function()
            equippedState.Melee = inventoryApi:GetEquipped("Melee")
            equippedState.Ranged = inventoryApi:GetEquipped("Ranged")
            equippedState.Special = inventoryApi:GetEquipped("Special")
            -- normalize legacy equipped references
            if type(equippedState.Melee) == "string" and equippedState.Melee:lower() == "stick" then
                equippedState.Melee = "Wooden Sword"
            end
            if type(equippedState.Ranged) == "string" and equippedState.Ranged:lower() == "stick" then
                equippedState.Ranged = "Wooden Sword"
            end
            if type(equippedState.Special) == "string" and equippedState.Special:lower() == "stick" then
                equippedState.Special = "Wooden Sword"
            end
        end)
    end
    local allEquipBtns = {} -- id -> {btn, stroke, category, card, cardStroke}

    local function refreshAllEquipButtons()
        for itemId, info in pairs(allEquipBtns) do
            local cat = info.category or classifyItem(itemId)
            if equippedState[cat] == itemId then
                info.btn.Text = "\u{2714} EQUIPPED"
                info.btn.BackgroundColor3 = DISABLED_BG
                info.btn.TextColor3 = GREEN_GLOW
                info.stroke.Color = GREEN_GLOW
                info.stroke.Transparency = 0.45
                -- Update card visual for equipped state
                if info.card then
                    info.card.BackgroundColor3 = CARD_EQUIPPED
                end
                if info.cardStroke then
                    info.cardStroke.Color = GREEN_GLOW
                    info.cardStroke.Thickness = 1.8
                    info.cardStroke.Transparency = 0.3
                end
            else
                info.btn.Text = "EQUIP"
                info.btn.BackgroundColor3 = BTN_BG
                info.btn.TextColor3 = WHITE
                info.stroke.Color = BTN_STROKE_C
                info.stroke.Transparency = 0.25
                -- Reset card visual
                if info.card then
                    info.card.BackgroundColor3 = CARD_BG
                end
                if info.cardStroke then
                    info.cardStroke.Color = CARD_STROKE
                    info.cardStroke.Thickness = 1.2
                    info.cardStroke.Transparency = 0.35
                end
            end
        end
    end

    -- Helper to create item card inside a specific grid
    local function createCard(gridParent, id)
        local card = Instance.new("Frame")
        card.Name = "ItemCard_" .. tostring(id)
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(1, 0, 1, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.Parent = gridParent
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Color = CARD_STROKE
        stroke.Thickness = 1.2
        stroke.Transparency = 0.35
        stroke.Parent = card
        local cardPad = Instance.new("UIPadding")
        cardPad.PaddingTop = UDim.new(0, px(8))
        cardPad.PaddingBottom = UDim.new(0, px(8))
        cardPad.PaddingLeft = UDim.new(0, px(8))
        cardPad.PaddingRight = UDim.new(0, px(8))
        cardPad.Parent = card

        local leftBox = Instance.new("Frame")
        leftBox.Name = "LeftBox"
        leftBox.Size = UDim2.new(0.45, 0, 1, 0)
        leftBox.Position = UDim2.new(0, 0, 0, 0)
        leftBox.BackgroundColor3 = ICON_BG
        leftBox.ZIndex = 251
        leftBox.Parent = card
        local lCorner = Instance.new("UICorner")
        lCorner.CornerRadius = UDim.new(0, px(10))
        lCorner.Parent = leftBox

        -- Subtle highlight in icon area for depth
        local iconHighlight = Instance.new("Frame")
        iconHighlight.Name = "IconHighlight"
        iconHighlight.Size = UDim2.new(1, 0, 0.35, 0)
        iconHighlight.Position = UDim2.new(0, 0, 0, 0)
        iconHighlight.BackgroundColor3 = Color3.fromRGB(30, 35, 55)
        iconHighlight.BackgroundTransparency = 0.5
        iconHighlight.BorderSizePixel = 0
        iconHighlight.ZIndex = 251
        iconHighlight.Parent = leftBox
        local hlCr = Instance.new("UICorner")
        hlCr.CornerRadius = UDim.new(0, px(10))
        hlCr.Parent = iconHighlight

        -- Subtle stroke on icon area
        local iconStroke = Instance.new("UIStroke")
        iconStroke.Color = CARD_STROKE
        iconStroke.Thickness = 1
        iconStroke.Transparency = 0.5
        iconStroke.Parent = leftBox

        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0.85, 0, 0.85, 0)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.BackgroundTransparency = 1
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.ZIndex = 252
        thumb.Parent = leftBox
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(id))
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        local rightBox = Instance.new("Frame")
        rightBox.Name = "RightBox"
        rightBox.Size = UDim2.new(0.52, 0, 1, 0)
        rightBox.Position = UDim2.new(0.48, 0, 0, 0)
        rightBox.BackgroundTransparency = 1
        rightBox.ZIndex = 251
        rightBox.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "ItemName"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextScaled = true
        nameLabel.TextColor3 = WHITE
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Text = tostring(id)
        nameLabel.Size = UDim2.new(1, 0, 0, px(28))
        nameLabel.Position = UDim2.new(0, 0, 0.34, 0)
        nameLabel.Parent = rightBox

        local equipBtn = Instance.new("TextButton")
        equipBtn.Name = "EquipBtn"
        equipBtn.Size = UDim2.new(0.85, 0, 0.24, 0)
        equipBtn.AnchorPoint = Vector2.new(0.5, 1)
        equipBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
        equipBtn.BackgroundColor3 = BTN_BG
        equipBtn.Font = Enum.Font.GothamBold
        equipBtn.TextScaled = true
        equipBtn.TextColor3 = WHITE
        equipBtn.Text = "EQUIP"
        equipBtn.AutoButtonColor = false
        equipBtn.Parent = rightBox
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = equipBtn
        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = BTN_STROKE_C
        btnStroke.Thickness = 1.4
        btnStroke.Transparency = 0.25
        btnStroke.Parent = equipBtn

        local cat = classifyItem(id)
        allEquipBtns[id] = { btn = equipBtn, stroke = btnStroke, category = cat, card = card, cardStroke = stroke }

        equipBtn.MouseButton1Click:Connect(function()
            local rs = game:GetService("ReplicatedStorage")
            local toolName = tostring(id)
            local category = classifyItem(toolName)
            if category == "Ranged" then
                local setRanged = rs:FindFirstChild("SetRangedTool")
                if setRanged and setRanged:IsA("RemoteEvent") then
                    pcall(function() setRanged:FireServer(toolName) end)
                else
                    local fe = rs:FindFirstChild("ForceEquipTool")
                    if fe and fe:IsA("RemoteEvent") then
                        pcall(function() fe:FireServer("Ranged", toolName) end)
                    end
                end
            else
                local setMelee = rs:FindFirstChild("SetMeleeTool")
                if setMelee and setMelee:IsA("RemoteEvent") then
                    pcall(function() setMelee:FireServer(toolName) end)
                else
                    local fe = rs:FindFirstChild("ForceEquipTool")
                    if fe and fe:IsA("RemoteEvent") then
                        pcall(function() fe:FireServer("Melee", toolName) end)
                    end
                end
            end

            equippedState[category] = id
            if inventoryApi and inventoryApi.SetEquipped then
                pcall(function() inventoryApi:SetEquipped(category, id) end)
            end
            refreshAllEquipButtons()
            -- play local equip sound if available
            pcall(function()
                local soundsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Sounds")
                if soundsFolder then
                    local s = soundsFolder:FindFirstChild("Equip") or (soundsFolder:FindFirstChild("UI") and soundsFolder.UI:FindFirstChild("Equip"))
                    if s and s:IsA("Sound") then
                        local clone = s:Clone()
                        clone.Parent = equipBtn
                        clone:Play()
                        task.delay(clone.TimeLength + 0.1, function()
                            pcall(function() clone:Destroy() end)
                        end)
                    end
                end
            end)
        end)

        -- hover: highlight on hover (matches Boosts/Quests/Shop style)
        equipBtn.MouseEnter:Connect(function()
            local info = allEquipBtns[id]
            local isEquipped = info and equippedState[info.category] == id
            if not isEquipped then
                pcall(function()
                    TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                end)
            end
        end)
        equipBtn.MouseLeave:Connect(function()
            local info = allEquipBtns[id]
            local isEquipped = info and equippedState[info.category] == id
            if not isEquipped then
                pcall(function()
                    TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                end)
            end
        end)

        return card
    end

    -- Populate sections with owned items
    for _, id in ipairs(items) do
        local cat = classifyItem(id)
        if cat == "Melee" then
            createCard(meleeGrid, id)
        elseif cat == "Ranged" then
            createCard(rangedGrid, id)
        else
            createCard(specialGrid, id)
        end
    end

    -- If no items, show friendly message in root
    if #items == 0 then
        local emptyCard = Instance.new("Frame")
        emptyCard.Name = "EmptyState"
        emptyCard.BackgroundColor3 = CARD_BG
        emptyCard.Size = UDim2.new(1, 0, 0, px(110))
        emptyCard.Parent = weaponsPage
        local emptyCr = Instance.new("UICorner")
        emptyCr.CornerRadius = UDim.new(0, px(12))
        emptyCr.Parent = emptyCard
        local emptyStroke = Instance.new("UIStroke")
        emptyStroke.Color = CARD_STROKE
        emptyStroke.Thickness = 1.2
        emptyStroke.Transparency = 0.35
        emptyStroke.Parent = emptyCard
        local lbl = Instance.new("TextLabel")
        lbl.Text = "No items owned"
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = px(16)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = DIM_TEXT
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.Parent = emptyCard
    end

    -- Apply initial equipped state visually
    refreshAllEquipButtons()

    setActiveTab("weapons")

    local function updateRootHeight()
        local height = contentContainer.AbsoluteSize.Y
        local minHeight = px(400)
        root.Size = UDim2.new(1, 0, 0, math.max(height, minHeight))
    end

    contentContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRootHeight)
    task.defer(updateRootHeight)

    root.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            cleanup()
        end
    end)

    return root
end

return InventoryUI
