--------------------------------------------------------------------------------
-- BoostsUI.lua  –  Client-side Boosts panel
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / DailyQuestsUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Shows purchasable boosts, active timers, and handles reroll/bonus-claim
-- quest selection sub-panels.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

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
local CARD_BG       = Color3.fromRGB(26, 30, 48)
local CARD_ACTIVE_BG= Color3.fromRGB(22, 38, 34)
local CARD_STROKE   = Color3.fromRGB(55, 62, 95)
local ICON_BG       = Color3.fromRGB(16, 18, 30)
local GOLD          = Color3.fromRGB(255, 215, 60)
local WHITE         = Color3.fromRGB(245, 245, 252)
local DIM_TEXT      = Color3.fromRGB(145, 150, 175)
local BTN_BG        = Color3.fromRGB(48, 55, 82)
local BTN_STROKE_C  = Color3.fromRGB(90, 100, 140)
local GREEN_BTN     = Color3.fromRGB(35, 190, 75)
local RED_TEXT      = Color3.fromRGB(255, 80, 80)
local ACTIVE_GLOW   = Color3.fromRGB(50, 230, 110)
local DISABLED_BG   = Color3.fromRGB(35, 38, 52)
local POPUP_BG      = Color3.fromRGB(20, 22, 38)

local ACCENT_COLORS = {
    coins_2x     = Color3.fromRGB(255, 200, 40),
    quest_2x     = Color3.fromRGB(80, 165, 255),
    quest_reroll = Color3.fromRGB(170, 110, 255),
    bonus_claim  = Color3.fromRGB(255, 120, 65),
}

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- BoostConfig (shared)
--------------------------------------------------------------------------------
local BoostConfig
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("BoostConfig", 10)
    if mod and mod:IsA("ModuleScript") then
        BoostConfig = require(mod)
    end
end)

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local remotesFolder
local boostFolder
local buyBoostRF
local rerollRF
local bonusClaimRF
local getStatesRF
local stateUpdatedRE
local getQuestsRF

local function ensureRemotes()
    if boostFolder then return true end
    remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return false end
    boostFolder     = remotesFolder:WaitForChild("Boosts", 5)
    stateUpdatedRE  = remotesFolder:WaitForChild("BoostStateUpdated", 5)
    getQuestsRF     = remotesFolder:FindFirstChild("GetQuests")
    if not boostFolder then return false end
    buyBoostRF      = boostFolder:WaitForChild("RequestBuyOrUseBoost", 5)
    rerollRF        = boostFolder:WaitForChild("RequestRerollQuest", 5)
    bonusClaimRF    = boostFolder:WaitForChild("RequestBonusClaim", 5)
    getStatesRF     = boostFolder:WaitForChild("GetBoostStates", 5)
    return buyBoostRF ~= nil
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
-- Notification toast (lightweight reusable)
--------------------------------------------------------------------------------
local function showToast(parent, message, color, duration)
    color = color or GOLD
    duration = duration or 2.5
    local toast = Instance.new("TextLabel")
    toast.Name                = "Toast"
    toast.BackgroundColor3    = Color3.fromRGB(18, 20, 36)
    toast.BackgroundTransparency = 0.08
    toast.Size                = UDim2.new(0.85, 0, 0, px(40))
    toast.AnchorPoint         = Vector2.new(0.5, 0)
    toast.Position            = UDim2.new(0.5, 0, 0, px(6))
    toast.Font                = Enum.Font.GothamBold
    toast.TextSize            = math.max(13, math.floor(px(14)))
    toast.TextColor3          = color
    toast.Text                = message
    toast.TextWrapped         = true
    toast.ZIndex              = 400
    toast.Parent              = parent

    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0, px(10))
    cr.Parent = toast

    local st = Instance.new("UIStroke")
    st.Color = color
    st.Thickness = 1.2
    st.Transparency = 0.35
    st.Parent = toast

    -- Animate in
    toast.BackgroundTransparency = 1
    toast.TextTransparency = 1
    TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency = 0.15, TextTransparency = 0}):Play()

    task.delay(duration, function()
        if toast and toast.Parent then
            local t = TweenService:Create(toast, TweenInfo.new(0.3), {BackgroundTransparency = 1, TextTransparency = 1})
            t:Play()
            t.Completed:Connect(function()
                pcall(function() toast:Destroy() end)
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Coin icon widget (matches DailyQuestsUI pattern — pure frame, no asset needed)
--------------------------------------------------------------------------------
local function makeCoinIcon(parentFrame, size)
    local coin = Instance.new("Frame")
    coin.Name            = "CoinIcon"
    coin.Size            = UDim2.new(0, size, 0, size)
    coin.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
    coin.BorderSizePixel = 0
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)
    cr.Parent = coin
    local stroke = Instance.new("UIStroke")
    stroke.Color           = Color3.fromRGB(172, 125, 10)
    stroke.Thickness       = math.max(1, math.floor(size * 0.1))
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent          = coin
    local hl = Instance.new("Frame")
    hl.Size                  = UDim2.new(0, math.max(2, math.floor(size * 0.28)), 0, math.max(2, math.floor(size * 0.28)))
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
-- Boost icon placeholder (colored circle with emoji-style glyph)
--------------------------------------------------------------------------------
local BOOST_GLYPHS = {
    coins_2x      = "\u{1F4B0}",  -- 💰
    quest_2x      = "\u{26A1}",   -- ⚡
    quest_reroll  = "\u{1F504}",  -- 🔄
    bonus_claim   = "\u{1F381}",  -- 🎁
}
-- Fallback colors for icon circles
local BOOST_ICON_COLORS = {
    coins_2x     = Color3.fromRGB(255, 200, 40),
    quest_2x     = Color3.fromRGB(80, 165, 255),
    quest_reroll = Color3.fromRGB(170, 110, 255),
    bonus_claim  = Color3.fromRGB(255, 120, 65),
}

local function makeBoostIcon(parent, boostId, size)
    local frame = Instance.new("Frame")
    frame.Name = "BoostIcon"
    frame.Size = UDim2.new(0, size, 0, size)
    frame.BackgroundColor3 = BOOST_ICON_COLORS[boostId] or Color3.fromRGB(80, 80, 90)
    frame.BorderSizePixel = 0
    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0, px(14))
    cr.Parent = frame
    local iconStroke = Instance.new("UIStroke")
    iconStroke.Color = Color3.fromRGB(255, 255, 255)
    iconStroke.Thickness = 1.5
    iconStroke.Transparency = 0.7
    iconStroke.Parent = frame
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = BOOST_GLYPHS[boostId] or "?"
    lbl.TextSize = math.max(18, math.floor(size * 0.52))
    lbl.TextColor3 = WHITE
    lbl.Parent = frame
    frame.Parent = parent
    return frame
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local BoostsUI = {}

function BoostsUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return nil end

    cleanupConnections()

    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
            and not c:IsA("UIPadding") then
            pcall(function() c:Destroy() end)
        end
    end

    if not BoostConfig then
        local errLabel = Instance.new("TextLabel")
        errLabel.BackgroundTransparency = 1
        errLabel.Font      = Enum.Font.GothamMedium
        errLabel.Text      = "Boosts unavailable – config not found."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize  = px(16)
        errLabel.Size      = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent    = parent
        return nil
    end

    if not ensureRemotes() then
        local errLabel = Instance.new("TextLabel")
        errLabel.BackgroundTransparency = 1
        errLabel.Font      = Enum.Font.GothamMedium
        errLabel.Text      = "Boosts unavailable – remotes not found."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize  = px(16)
        errLabel.Size      = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent    = parent
        return nil
    end

    -- Fetch initial state from server
    local boostStates = {}
    pcall(function()
        boostStates = getStatesRF:InvokeServer()
    end)
    if type(boostStates) ~= "table" then boostStates = {} end
    local serverTime = boostStates._serverTime or os.time()
    local timeDelta = os.time() - serverTime  -- offset to translate server times to local

    ---------------------------------------------------------------------------
    -- Root container
    ---------------------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name = "BoostsRoot"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 0, 0)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.LayoutOrder = 1
    root.Parent = parent

    local rootLayout = Instance.new("UIListLayout")
    rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rootLayout.Padding = UDim.new(0, px(10))
    rootLayout.Parent = root

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(16))
    rootPad.PaddingLeft = UDim.new(0, px(8))
    rootPad.PaddingRight = UDim.new(0, px(8))
    rootPad.Parent = root

    ---------------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------------
    local headerWrap = Instance.new("Frame")
    headerWrap.Name = "HeaderWrap"
    headerWrap.BackgroundTransparency = 1
    headerWrap.Size = UDim2.new(1, 0, 0, px(54))
    headerWrap.LayoutOrder = 1
    headerWrap.Parent = root

    local header = Instance.new("TextLabel")
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.Text = "\u{26A1} BOOSTS"
    header.TextColor3 = GOLD
    header.TextSize = math.max(20, math.floor(px(24)))
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Size = UDim2.new(1, 0, 0, px(30))
    header.Position = UDim2.new(0, 0, 0, 0)
    header.Parent = headerWrap

    local subHeader = Instance.new("TextLabel")
    subHeader.Name = "SubHeader"
    subHeader.BackgroundTransparency = 1
    subHeader.Font = Enum.Font.GothamMedium
    subHeader.Text = "Activate temporary advantages and utility boosts."
    subHeader.TextColor3 = DIM_TEXT
    subHeader.TextSize = math.max(11, math.floor(px(12)))
    subHeader.TextXAlignment = Enum.TextXAlignment.Left
    subHeader.Size = UDim2.new(1, 0, 0, px(16))
    subHeader.Position = UDim2.new(0, 0, 0, px(30))
    subHeader.Parent = headerWrap

    -- Gold accent bar under header
    local accentBar = Instance.new("Frame")
    accentBar.Name = "AccentBar"
    accentBar.BackgroundColor3 = GOLD
    accentBar.BackgroundTransparency = 0.3
    accentBar.Size = UDim2.new(1, 0, 0, px(2))
    accentBar.Position = UDim2.new(0, 0, 1, -px(2))
    accentBar.BorderSizePixel = 0
    accentBar.Parent = headerWrap

    local helperNote = Instance.new("TextLabel")
    helperNote.Name = "HelperNote"
    helperNote.BackgroundTransparency = 1
    helperNote.Font = Enum.Font.GothamMedium
    helperNote.RichText = true
    helperNote.Text = '<font color="#9096af">Timed boosts activate immediately and do not stack.</font>'
    helperNote.TextColor3 = DIM_TEXT
    helperNote.TextSize = math.max(10, math.floor(px(11)))
    helperNote.TextXAlignment = Enum.TextXAlignment.Left
    helperNote.Size = UDim2.new(1, 0, 0, px(14))
    helperNote.LayoutOrder = 2
    helperNote.Parent = root

    ---------------------------------------------------------------------------
    -- Boost cards
    ---------------------------------------------------------------------------
    local timerLabels = {}   -- [boostId] = { label, expiresAt }
    local cardButtons = {}   -- [boostId] = TextButton
    local cardStatusLabels = {} -- [boostId] = TextLabel
    local cardBorders = {}   -- [boostId] = UIStroke (for active glow)

    -- Sort boosts by SortOrder
    local sortedBoosts = {}
    for _, def in ipairs(BoostConfig.Boosts) do
        table.insert(sortedBoosts, def)
    end
    table.sort(sortedBoosts, function(a, b) return a.SortOrder < b.SortOrder end)

    for i, def in ipairs(sortedBoosts) do
        local bState = boostStates[def.Id] or {}
        local isActive = bState.active == true
        local expiresAt = (bState.expiresAt or 0) + timeDelta  -- convert to local time

        local card = Instance.new("Frame")
        card.Name = "Boost_" .. def.Id
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(1, 0, 0, px(120))
        card.LayoutOrder = 10 + i
        card.Parent = root

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color = isActive and ACTIVE_GLOW or CARD_STROKE
        stroke.Thickness = isActive and 2.5 or 1.2
        stroke.Transparency = isActive and 0.1 or 0.35
        stroke.Parent = card
        cardBorders[def.Id] = stroke

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(14))
        pad.PaddingRight  = UDim.new(0, px(14))
        pad.PaddingTop    = UDim.new(0, px(12))
        pad.PaddingBottom = UDim.new(0, px(12))
        pad.Parent = card

        -- Subtle accent glow behind icon area
        local iconSize = px(60)
        local iconGlow = Instance.new("Frame")
        iconGlow.Name = "IconGlow"
        iconGlow.Size = UDim2.new(0, iconSize + px(10), 0, iconSize + px(10))
        iconGlow.AnchorPoint = Vector2.new(0, 0.5)
        iconGlow.Position = UDim2.new(0, -px(5), 0.5, 0)
        iconGlow.BackgroundColor3 = ACCENT_COLORS[def.Id] or CARD_STROKE
        iconGlow.BackgroundTransparency = 0.82
        iconGlow.BorderSizePixel = 0
        local glowCr = Instance.new("UICorner")
        glowCr.CornerRadius = UDim.new(0, px(18))
        glowCr.Parent = iconGlow
        iconGlow.Parent = card

        -- Left: icon
        local iconFrame = makeBoostIcon(card, def.Id, iconSize)
        iconFrame.Position = UDim2.new(0, 0, 0.5, 0)
        iconFrame.AnchorPoint = Vector2.new(0, 0.5)

        -- Middle-top: name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = def.DisplayName
        nameLabel.TextColor3 = WHITE
        nameLabel.TextSize = math.max(15, math.floor(px(17)))
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Size = UDim2.new(0.50, 0, 0, px(22))
        nameLabel.Position = UDim2.new(0, iconSize + px(14), 0, 0)
        nameLabel.Parent = card

        -- Middle: description
        local descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.GothamMedium
        descLabel.Text = def.Description
        descLabel.TextColor3 = DIM_TEXT
        descLabel.TextSize = math.max(11, math.floor(px(12)))
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextWrapped = true
        descLabel.Size = UDim2.new(0.50, 0, 0, px(28))
        descLabel.Position = UDim2.new(0, iconSize + px(14), 0, px(23))
        descLabel.Parent = card

        -- Duration label (for timed boosts)
        if def.Type == BoostConfig.Type.Timed then
            local durationLabel = Instance.new("TextLabel")
            durationLabel.Name = "Duration"
            durationLabel.BackgroundTransparency = 1
            durationLabel.Font = Enum.Font.GothamMedium
            durationLabel.RichText = true
            durationLabel.Text = '<font color="#9096af">\u{23F1}</font>  ' .. math.floor(def.DurationSeconds / 60) .. " min"
            durationLabel.TextColor3 = DIM_TEXT
            durationLabel.TextSize = math.max(10, math.floor(px(11)))
            durationLabel.TextXAlignment = Enum.TextXAlignment.Left
            durationLabel.Size = UDim2.new(0.50, 0, 0, px(16))
            durationLabel.Position = UDim2.new(0, iconSize + px(14), 0, px(53))
            durationLabel.Parent = card
        end

        -- Right side: price row + button + status
        local rightX = 0.72

        -- Price row
        local priceRow = Instance.new("Frame")
        priceRow.Name = "PriceRow"
        priceRow.BackgroundTransparency = 1
        priceRow.Size = UDim2.new(0.28, 0, 0, px(22))
        priceRow.AnchorPoint = Vector2.new(1, 0)
        priceRow.Position = UDim2.new(1, 0, 0, 0)
        priceRow.Parent = card

        local priceLabel = Instance.new("TextLabel")
        priceLabel.Name = "Price"
        priceLabel.BackgroundTransparency = 1
        priceLabel.Font = Enum.Font.GothamBold
        priceLabel.TextScaled = true
        priceLabel.TextColor3 = GOLD
        priceLabel.TextXAlignment = Enum.TextXAlignment.Right
        priceLabel.Text = tostring(def.PriceCoins)
        priceLabel.Size = UDim2.new(0.60, 0, 1, 0)
        priceLabel.Parent = priceRow

        local coinIconSize = px(18)
        local cIcon = makeCoinIcon(priceRow, coinIconSize)
        cIcon.AnchorPoint = Vector2.new(0, 0.5)
        cIcon.Position = UDim2.new(0.66, 0, 0.5, 0)

        -- Action button
        local btn = Instance.new("TextButton")
        btn.Name = "ActionBtn"
        btn.AutoButtonColor = false
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = math.max(13, math.floor(px(14)))
        btn.TextColor3 = WHITE
        btn.Size = UDim2.new(0.28, 0, 0, px(36))
        btn.AnchorPoint = Vector2.new(1, 0)
        btn.Position = UDim2.new(1, 0, 0, px(28))
        btn.BackgroundColor3 = BTN_BG
        btn.Parent = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = BTN_STROKE_C
        btnStroke.Thickness = 1.4
        btnStroke.Transparency = 0.25
        btnStroke.Parent = btn

        cardButtons[def.Id] = btn

        -- Status / timer label below button
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Name = "Status"
        statusLabel.BackgroundTransparency = 1
        statusLabel.Font = Enum.Font.GothamBold
        statusLabel.TextSize = math.max(11, math.floor(px(12)))
        statusLabel.TextColor3 = DIM_TEXT
        statusLabel.TextXAlignment = Enum.TextXAlignment.Center
        statusLabel.Size = UDim2.new(0.28, 0, 0, px(18))
        statusLabel.AnchorPoint = Vector2.new(1, 0)
        statusLabel.Position = UDim2.new(1, 0, 0, px(67))
        statusLabel.Parent = card
        cardStatusLabels[def.Id] = statusLabel

        -- Set initial button / status state
        local function updateCardState(active, expAt)
            if def.Type == BoostConfig.Type.Timed then
                if active then
                    btn.Text = "ACTIVE"
                    btn.BackgroundColor3 = DISABLED_BG
                    btn.Active = false
                    statusLabel.TextColor3 = ACTIVE_GLOW
                    stroke.Color = ACTIVE_GLOW
                    stroke.Thickness = 2.5
                    stroke.Transparency = 0.1
                    card.BackgroundColor3 = CARD_ACTIVE_BG

                    -- Store timer info
                    timerLabels[def.Id] = { label = statusLabel, expiresAt = expAt }
                else
                    btn.Text = "BUY"
                    btn.BackgroundColor3 = BTN_BG
                    btn.Active = true
                    statusLabel.Text = "Ready"
                    statusLabel.TextColor3 = DIM_TEXT
                    stroke.Color = CARD_STROKE
                    stroke.Thickness = 1.2
                    stroke.Transparency = 0.35
                    card.BackgroundColor3 = CARD_BG
                    timerLabels[def.Id] = nil
                end
            else
                -- Instant use boosts
                if def.Id == "quest_reroll" then
                    btn.Text = "USE"
                    btn.BackgroundColor3 = BTN_BG
                    btn.Active = true
                    statusLabel.Text = "Select Quest"
                    statusLabel.TextColor3 = DIM_TEXT
                elseif def.Id == "bonus_claim" then
                    btn.Text = "USE"
                    btn.BackgroundColor3 = BTN_BG
                    btn.Active = true
                    statusLabel.Text = "Select Quest"
                    statusLabel.TextColor3 = DIM_TEXT
                end
            end
        end

        updateCardState(isActive, expiresAt)

        -- Hover feedback
        trackConn(btn.MouseEnter:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if btn.Active then
                local bgColor = BTN_BG
                TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = bgColor}):Play()
            end
        end))

        -- Click handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if not btn.Active then return end

            if def.Type == BoostConfig.Type.Timed then
                -- Purchase timed boost
                btn.Active = false
                btn.Text = "..."

                local success, msg = false, "Error"
                pcall(function()
                    success, msg = buyBoostRF:InvokeServer(def.Id)
                end)

                if success then
                    showToast(root, def.DisplayName .. " activated!", GREEN_BTN, 2)
                    local newExpires = os.time() + def.DurationSeconds
                    updateCardState(true, newExpires)
                    -- Refresh header coins
                    pcall(function()
                        if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                    end)
                else
                    local toastMsg = msg or "Purchase failed"
                    local toastColor = RED_TEXT
                    if tostring(msg):find("Insufficient") then
                        toastMsg = "Not enough coins!"
                    elseif tostring(msg):find("Already") then
                        toastMsg = "Boost is already active!"
                    end
                    showToast(root, toastMsg, toastColor, 2.5)
                    updateCardState(false, 0)
                end

            elseif def.Id == "quest_reroll" then
                showQuestSelector(root, parent, "reroll", def, updateCardState)

            elseif def.Id == "bonus_claim" then
                showQuestSelector(root, parent, "bonus", def, updateCardState)
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Timer tick: update countdowns every second
    ---------------------------------------------------------------------------
    local timerConnection
    timerConnection = RunService.Heartbeat:Connect(function()
        local now = os.time()
        for boostId, info in pairs(timerLabels) do
            if info.label and info.label.Parent then
                local remaining = info.expiresAt - now
                if remaining > 0 then
                    local mins = math.floor(remaining / 60)
                    local secs = remaining % 60
                    info.label.Text = string.format("%02d:%02d", mins, secs)
                else
                    -- Expired
                    info.label.Text = "Ready"
                    info.label.TextColor3 = DIM_TEXT
                    timerLabels[boostId] = nil

                    -- Reset card state
                    local btn2 = cardButtons[boostId]
                    if btn2 then
                        btn2.Text = "BUY"
                        btn2.BackgroundColor3 = BTN_BG
                        btn2.Active = true
                    end
                    local border = cardBorders[boostId]
                    if border then
                        border.Color = CARD_STROKE
                        border.Thickness = 1.2
                        border.Transparency = 0.35
                    end
                end
            end
        end
    end)
    trackConn(timerConnection)

    ---------------------------------------------------------------------------
    -- Listen for server push updates
    ---------------------------------------------------------------------------
    if stateUpdatedRE then
        trackConn(stateUpdatedRE.OnClientEvent:Connect(function(states)
            if type(states) ~= "table" then return end
            local srvTime = states._serverTime or os.time()
            local delta = os.time() - srvTime

            for _, def in ipairs(BoostConfig.Boosts) do
                local st = states[def.Id]
                if st then
                    local active = st.active == true
                    local expAt = (st.expiresAt or 0) + delta

                    if def.Type == BoostConfig.Type.Timed then
                        local btn2 = cardButtons[def.Id]
                        local statusLbl = cardStatusLabels[def.Id]
                        local border = cardBorders[def.Id]

                        if active then
                            if btn2 then
                                btn2.Text = "ACTIVE"
                                btn2.BackgroundColor3 = DISABLED_BG
                                btn2.Active = false
                            end
                            if statusLbl then
                                statusLbl.TextColor3 = ACTIVE_GLOW
                            end
                            if border then
                                border.Color = ACTIVE_GLOW
                                border.Thickness = 2.5
                                border.Transparency = 0.1
                            end
                            timerLabels[def.Id] = { label = statusLbl, expiresAt = expAt }
                        else
                            if btn2 then
                                btn2.Text = "BUY"
                                btn2.BackgroundColor3 = BTN_BG
                                btn2.Active = true
                            end
                            if statusLbl then
                                statusLbl.Text = "Ready"
                                statusLbl.TextColor3 = DIM_TEXT
                            end
                            if border then
                                border.Color = CARD_STROKE
                                border.Thickness = 1.2
                                border.Transparency = 0.35
                            end
                            timerLabels[def.Id] = nil
                        end
                    end
                end
            end
        end))
    end

    return root
end

--------------------------------------------------------------------------------
-- Quest selector sub-panel (used by Reroll and Bonus Claim)
--------------------------------------------------------------------------------
function showQuestSelector(boostsRoot, modalParent, mode, boostDef, updateCardState)
    -- Remove any existing selector
    local existing = boostsRoot:FindFirstChild("QuestSelector")
    if existing then existing:Destroy() end

    -- Fetch current quests
    local quests = {}
    pcall(function()
        if getQuestsRF then
            quests = getQuestsRF:InvokeServer()
        end
    end)
    if type(quests) ~= "table" or #quests == 0 then
        showToast(boostsRoot, "No quests available.", RED_TEXT, 2)
        return
    end

    -- Fetch bonus claimed data
    local boostStates = {}
    pcall(function()
        if getStatesRF then
            boostStates = getStatesRF:InvokeServer()
        end
    end)
    local bonusClaimed = (type(boostStates) == "table" and boostStates._bonusClaimed) or {}

    -- Build overlay
    local selector = Instance.new("Frame")
    selector.Name = "QuestSelector"
    selector.BackgroundColor3 = POPUP_BG
    selector.BackgroundTransparency = 0.02
    selector.Size = UDim2.new(1, 0, 0, 0)
    selector.AutomaticSize = Enum.AutomaticSize.Y
    selector.LayoutOrder = 999
    selector.ZIndex = 350
    selector.Parent = boostsRoot

    local selCorner = Instance.new("UICorner")
    selCorner.CornerRadius = UDim.new(0, px(12))
    selCorner.Parent = selector

    local selStroke = Instance.new("UIStroke")
    selStroke.Color = GOLD
    selStroke.Thickness = 1.8
    selStroke.Transparency = 0.2
    selStroke.Parent = selector

    local selPad = Instance.new("UIPadding")
    selPad.PaddingTop    = UDim.new(0, px(14))
    selPad.PaddingBottom = UDim.new(0, px(14))
    selPad.PaddingLeft   = UDim.new(0, px(14))
    selPad.PaddingRight  = UDim.new(0, px(14))
    selPad.Parent = selector

    local selLayout = Instance.new("UIListLayout")
    selLayout.SortOrder = Enum.SortOrder.LayoutOrder
    selLayout.Padding = UDim.new(0, px(8))
    selLayout.Parent = selector

    -- Title
    local titleText = mode == "reroll" and "Select a quest to reroll:" or "Select a completed quest for bonus reward:"
    local selTitle = Instance.new("TextLabel")
    selTitle.BackgroundTransparency = 1
    selTitle.Font = Enum.Font.GothamBold
    selTitle.Text = titleText
    selTitle.TextColor3 = GOLD
    selTitle.TextSize = math.max(14, math.floor(px(16)))
    selTitle.TextXAlignment = Enum.TextXAlignment.Left
    selTitle.TextWrapped = true
    selTitle.Size = UDim2.new(1, 0, 0, px(26))
    selTitle.LayoutOrder = 1
    selTitle.ZIndex = 351
    selTitle.Parent = selector

    -- Quest rows
    local anyEligible = false
    for idx, quest in ipairs(quests) do
        local eligible = false
        local reason = ""

        if mode == "reroll" then
            if quest.claimed then
                reason = "Claimed"
            else
                eligible = true
            end
        elseif mode == "bonus" then
            if quest.progress < quest.goal then
                reason = "Not completed"
            elseif bonusClaimed[quest.id] then
                reason = "Bonus used"
            else
                eligible = true
            end
        end

        if eligible then anyEligible = true end

        local row = Instance.new("Frame")
        row.Name = "QuestRow_" .. idx
        row.BackgroundColor3 = eligible and CARD_BG or DISABLED_BG
        row.Size = UDim2.new(1, 0, 0, px(56))
        row.LayoutOrder = 10 + idx
        row.ZIndex = 352
        row.Parent = selector

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, px(10))
        rowCorner.Parent = row

        local rowStroke = Instance.new("UIStroke")
        rowStroke.Color = eligible and CARD_STROKE or DISABLED_BG
        rowStroke.Thickness = 1
        rowStroke.Transparency = 0.5
        rowStroke.Parent = row

        local rowPad = Instance.new("UIPadding")
        rowPad.PaddingLeft = UDim.new(0, px(12))
        rowPad.PaddingRight = UDim.new(0, px(10))
        rowPad.Parent = row

        local questTitle = Instance.new("TextLabel")
        questTitle.BackgroundTransparency = 1
        questTitle.Font = Enum.Font.GothamBold
        questTitle.Text = quest.title
        questTitle.TextColor3 = eligible and WHITE or DIM_TEXT
        questTitle.TextSize = math.max(12, math.floor(px(13)))
        questTitle.TextXAlignment = Enum.TextXAlignment.Left
        questTitle.Size = UDim2.new(0.5, 0, 0, px(18))
        questTitle.Position = UDim2.new(0, 0, 0, px(6))
        questTitle.ZIndex = 353
        questTitle.Parent = row

        local questDesc = Instance.new("TextLabel")
        questDesc.BackgroundTransparency = 1
        questDesc.Font = Enum.Font.GothamMedium
        questDesc.Text = quest.desc .. "  (" .. quest.progress .. "/" .. quest.goal .. ")"
        questDesc.TextColor3 = DIM_TEXT
        questDesc.TextSize = math.max(10, math.floor(px(10)))
        questDesc.TextXAlignment = Enum.TextXAlignment.Left
        questDesc.Size = UDim2.new(0.5, 0, 0, px(14))
        questDesc.Position = UDim2.new(0, 0, 0, px(26))
        questDesc.ZIndex = 353
        questDesc.Parent = row

        if eligible then
            local selectBtn = Instance.new("TextButton")
            selectBtn.Name = "SelectBtn"
            selectBtn.AutoButtonColor = false
            selectBtn.Font = Enum.Font.GothamBold
            selectBtn.TextSize = math.max(12, math.floor(px(13)))
            selectBtn.Text = "CONFIRM"
            selectBtn.TextColor3 = WHITE
            selectBtn.BackgroundColor3 = BTN_BG
            selectBtn.Size = UDim2.new(0.28, 0, 0, px(32))
            selectBtn.AnchorPoint = Vector2.new(1, 0.5)
            selectBtn.Position = UDim2.new(1, 0, 0.5, 0)
            selectBtn.ZIndex = 354
            selectBtn.Parent = row

            local selBtnCorner = Instance.new("UICorner")
            selBtnCorner.CornerRadius = UDim.new(0, px(8))
            selBtnCorner.Parent = selectBtn

            local selBtnStroke = Instance.new("UIStroke")
            selBtnStroke.Color = BTN_STROKE_C
            selBtnStroke.Thickness = 1.2
            selBtnStroke.Transparency = 0.25
            selBtnStroke.Parent = selectBtn

            -- Hover
            trackConn(selectBtn.MouseEnter:Connect(function()
                TweenService:Create(selectBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end))
            trackConn(selectBtn.MouseLeave:Connect(function()
                TweenService:Create(selectBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
            end))

            -- Click
            trackConn(selectBtn.MouseButton1Click:Connect(function()
                selectBtn.Active = false
                selectBtn.Text = "..."

                local success, msg = false, "Error"
                if mode == "reroll" then
                    pcall(function()
                        success, msg = rerollRF:InvokeServer(idx)
                    end)
                elseif mode == "bonus" then
                    pcall(function()
                        success, msg = bonusClaimRF:InvokeServer(quest.id)
                    end)
                end

                if success then
                    local toastMsg = mode == "reroll"
                        and "Quest rerolled!"
                        or ("Bonus reward claimed! +" .. quest.reward .. " coins")
                    showToast(boostsRoot, toastMsg, GREEN_BTN, 2.5)
                    -- Refresh coins header
                    pcall(function()
                        if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                    end)
                else
                    local toastMsg = msg or "Action failed"
                    if tostring(msg):find("Insufficient") then
                        toastMsg = "Not enough coins!"
                    end
                    showToast(boostsRoot, toastMsg, RED_TEXT, 2.5)
                end

                -- Close selector
                pcall(function() selector:Destroy() end)
            end))
        else
            local reasonLabel = Instance.new("TextLabel")
            reasonLabel.BackgroundTransparency = 1
            reasonLabel.Font = Enum.Font.GothamMedium
            reasonLabel.Text = reason
            reasonLabel.TextColor3 = RED_TEXT
            reasonLabel.TextSize = math.max(10, math.floor(px(11)))
            reasonLabel.TextXAlignment = Enum.TextXAlignment.Right
            reasonLabel.Size = UDim2.new(0.3, 0, 1, 0)
            reasonLabel.AnchorPoint = Vector2.new(1, 0)
            reasonLabel.Position = UDim2.new(1, 0, 0, 0)
            reasonLabel.ZIndex = 353
            reasonLabel.Parent = row
        end
    end

    if not anyEligible then
        local noMsg = mode == "reroll"
            and "No quests available to reroll."
            or "No completed quests eligible for bonus."
        showToast(boostsRoot, noMsg, RED_TEXT, 2.5)
    end

    -- Cancel button
    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Name = "CancelBtn"
    cancelBtn.AutoButtonColor = false
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.TextSize = math.max(13, math.floor(px(14)))
    cancelBtn.Text = "CANCEL"
    cancelBtn.TextColor3 = WHITE
    cancelBtn.BackgroundColor3 = Color3.fromRGB(140, 45, 45)
    cancelBtn.Size = UDim2.new(0.45, 0, 0, px(34))
    cancelBtn.LayoutOrder = 100
    cancelBtn.ZIndex = 352
    cancelBtn.Parent = selector

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, px(8))
    cancelCorner.Parent = cancelBtn

    local cancelStroke = Instance.new("UIStroke")
    cancelStroke.Color = Color3.fromRGB(180, 60, 60)
    cancelStroke.Thickness = 1.2
    cancelStroke.Transparency = 0.3
    cancelStroke.Parent = cancelBtn

    trackConn(cancelBtn.MouseButton1Click:Connect(function()
        pcall(function() selector:Destroy() end)
    end))
end

return BoostsUI
