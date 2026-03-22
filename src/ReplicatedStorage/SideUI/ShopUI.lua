--------------------------------------------------------------------------------
-- ShopUI.lua  –  Sectioned shop UI (fixed header handled by SideUI)
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local UITheme = require(script.Parent.UITheme)

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- palette (sourced from shared UITheme – Team menu visual language)
local CARD_BG      = UITheme.CARD_BG
local CARD_OWNED   = UITheme.CARD_OWNED
local CARD_STROKE  = UITheme.CARD_STROKE
local ICON_BG      = UITheme.ICON_BG
local GOLD         = UITheme.GOLD
local WHITE        = UITheme.WHITE
local DIM_TEXT     = UITheme.DIM_TEXT
local BTN_BUY      = UITheme.BTN_BG
local BTN_STROKE_C = UITheme.BTN_STROKE
local GREEN_BTN    = UITheme.GREEN_BTN
local GREEN_GLOW   = UITheme.GREEN_GLOW
local RED_TEXT     = UITheme.RED_TEXT
local DISABLED_BG  = UITheme.DISABLED_BG

-- Tab-specific colors
local SIDEBAR_BG    = UITheme.SIDEBAR_BG
local TAB_ACTIVE_BG = UITheme.TAB_ACTIVE

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ShopUI = {}

local CrateConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
    if mod and mod:IsA("ModuleScript") then
        CrateConfig = require(mod)
    end
end)

local BoostConfig = nil
local AssetCodes = nil
local boostRemotes = nil

local function safeRequireBoostConfig()
    local ok, mod = pcall(function() return ReplicatedStorage:FindFirstChild("BoostConfig") end)
    if ok and mod and mod:IsA("ModuleScript") then
        local suc, result = pcall(function() return require(mod) end)
        if suc and type(result) == "table" then return result end
    end
    return nil
end

local function safeRequireAssetCodes()
    local ok, mod = pcall(function() return ReplicatedStorage:FindFirstChild("AssetCodes") end)
    if ok and mod and mod:IsA("ModuleScript") then
        local suc, result = pcall(function() return require(mod) end)
        if suc and type(result) == "table" then return result end
    end
    return nil
end

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

-- Wave emote preview data (reusable anywhere emote previews appear)
-- NOTE: rbxassetid://4720094407 failed to load (blank), so we use a
-- guaranteed-rendering text glyph as the primary visual.
local WAVE_PREVIEW = {
    glyph = "\u{1F44B}",  -- waving hand emoji (always renders)
    size  = UDim2.new(0.82, 0, 0.82, 0),
}

local function ensureBoostRemotes()
    if boostRemotes then return boostRemotes end

    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return nil end

    local boostFolder = remotesFolder:FindFirstChild("Boosts") or remotesFolder:WaitForChild("Boosts", 5)
    if not boostFolder then return nil end

    local purchaseRF = boostFolder:FindFirstChild("PurchaseBoost") or boostFolder:FindFirstChild("RequestBuyOrUseBoost")
    local getStatesRF = boostFolder:FindFirstChild("GetBoostStates")
    local stateUpdatedRE = remotesFolder:FindFirstChild("BoostStateUpdated")
    if not purchaseRF or not getStatesRF or not stateUpdatedRE then
        return nil
    end

    boostRemotes = {
        purchase = purchaseRF,
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

-- Helper: create a titled section with an inner grid for item cards
local function makeSection(parent, sectionId, label)
    local section = Instance.new("Frame")
    section.Name = sectionId .. "_Section"
    section.BackgroundTransparency = 1
    section.Size = UDim2.new(1, 0, 0, 0)
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.Parent = parent

    -- ensure section stacks header + grid vertically
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

    -- Header wrapper with accent bar (matches Boosts/Quests header style)
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
    grid.Name = sectionId .. "_Grid"
    grid.BackgroundTransparency = 1
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.Parent = section

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.30, 0, 0, px(160))
    gridLayout.CellPadding = UDim2.new(0.025, 0, 0, px(12))
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.FillDirectionMaxCells = 3
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    grid.LayoutOrder = 2

    return section, grid
end

-- NOTE: safeRequireAssetCodes is already defined above (line ~52).
-- A duplicate declaration + `local AssetCodes = ...` here previously
-- shadowed the module-level AssetCodes that getBoostIconImage captures,
-- causing boost icons to always fall back to glyphs in Shop.
-- Removed to keep a single AssetCodes variable for the whole module.

--------------------------------------------------------------------------------
-- Tab definitions (mirrors DailyQuestsUI TAB_DEFS pattern)
--------------------------------------------------------------------------------
local TAB_DEFS = {
    { id = "weapons", icon = "\u{2694}", label = "Weapons", order = 1 },
    { id = "boosts",  icon = "\u{26A1}", label = "Boosts",  order = 2 },
    { id = "skins",   icon = "\u{2726}", label = "Skins",   order = 3 },
    { id = "emotes",  icon = "\u{263A}", label = "Emotes",  order = 4 },
    { id = "effects", icon = "\u{2738}", label = "Effects", order = 5 },
    { id = "coins",   icon = "\u{1FA99}", label = "Coins",   order = 6 },
}

-- Debug: final Shop categories after Trails removal
do
    local ids = {}
    for _, def in ipairs(TAB_DEFS) do
        table.insert(ids, def.id)
    end
    local joined = table.concat(ids, ",")
    print("[CategoryDebug][Shop] final categories:", joined)
    print("[CategoryDebug][Shop] trails present:", tostring(string.find(joined, "trails", 1, true) ~= nil))
end

local function markIconPart(part)
    part:SetAttribute("TabIconPart", true)
    return part
end

local function setTabIconTint(iconRoot, color)
    if not iconRoot then return end
    if iconRoot:GetAttribute("TabIconPart") then
        if iconRoot:IsA("Frame") then
            iconRoot.BackgroundColor3 = color
        elseif iconRoot:IsA("TextLabel") then
            iconRoot.TextColor3 = color
        elseif iconRoot:IsA("ImageLabel") then
            iconRoot.ImageColor3 = color
        elseif iconRoot:IsA("UIStroke") then
            iconRoot.Color = color
        end
    end
    for _, d in ipairs(iconRoot:GetDescendants()) do
        if d:GetAttribute("TabIconPart") then
            if d:IsA("Frame") then
                d.BackgroundColor3 = color
            elseif d:IsA("TextLabel") then
                d.TextColor3 = color
            elseif d:IsA("ImageLabel") then
                d.ImageColor3 = color
            elseif d:IsA("UIStroke") then
                d.Color = color
            end
        end
    end
end

local CUSTOM_TAB_ICON_COLORS = {
    skins  = { active = Color3.fromRGB(178, 146, 220), inactive = Color3.fromRGB(114, 99, 140) },
    emotes = { active = Color3.fromRGB(223, 176, 96), inactive = Color3.fromRGB(145, 116, 74) },
    effects = { active = Color3.fromRGB(214, 138, 206), inactive = Color3.fromRGB(136, 90, 131) },
    coins  = { active = Color3.fromRGB(255, 215, 80), inactive = Color3.fromRGB(160, 140, 60) },
}

local function getCustomTabIconColor(tabId, active)
    local palette = CUSTOM_TAB_ICON_COLORS[tabId]
    if not palette then
        return active and GOLD or DIM_TEXT
    end
    return active and palette.active or palette.inactive
end

local function buildCustomTabIcon(parentBtn, tabId)
    local root = Instance.new("Frame")
    root.Name = "IconCustom"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(0, px(26), 0, px(24))
    root.AnchorPoint = Vector2.new(0.5, 0)
    root.Position = UDim2.new(0.5, 0, 0, px(8))
    root.Parent = parentBtn

    if tabId == "skins" then
        local shoulders = markIconPart(Instance.new("Frame"))
        shoulders.BackgroundTransparency = 0
        shoulders.BorderSizePixel = 0
        shoulders.Size = UDim2.new(0, px(18), 0, px(7))
        shoulders.Position = UDim2.new(0.5, 0, 0, px(14))
        shoulders.AnchorPoint = Vector2.new(0.5, 0)
        shoulders.Parent = root
        local shouldersCorner = Instance.new("UICorner")
        shouldersCorner.CornerRadius = UDim.new(0, px(3))
        shouldersCorner.Parent = shoulders

        local torso = markIconPart(Instance.new("Frame"))
        torso.BackgroundTransparency = 0
        torso.BorderSizePixel = 0
        torso.Size = UDim2.new(0, px(12), 0, px(8))
        torso.Position = UDim2.new(0.5, 0, 0, px(10))
        torso.AnchorPoint = Vector2.new(0.5, 0)
        torso.Parent = root
        local torsoCorner = Instance.new("UICorner")
        torsoCorner.CornerRadius = UDim.new(0, px(3))
        torsoCorner.Parent = torso

        local head = markIconPart(Instance.new("Frame"))
        head.BackgroundTransparency = 0
        head.BorderSizePixel = 0
        head.Size = UDim2.new(0, px(8), 0, px(8))
        head.Position = UDim2.new(0.5, 0, 0, px(2))
        head.AnchorPoint = Vector2.new(0.5, 0)
        head.Parent = root
        local headCorner = Instance.new("UICorner")
        headCorner.CornerRadius = UDim.new(1, 0)
        headCorner.Parent = head
    elseif tabId == "emotes" then
        local face = Instance.new("Frame")
        face.Name = "FaceOutline"
        face.BackgroundTransparency = 1
        face.BorderSizePixel = 0
        face.Size = UDim2.new(0, px(20), 0, px(20))
        face.Position = UDim2.new(0.5, 0, 0, px(2))
        face.AnchorPoint = Vector2.new(0.5, 0)
        face.Parent = root

        local faceStroke = markIconPart(Instance.new("UIStroke"))
        faceStroke.Thickness = math.max(1, math.floor(px(2)))
        faceStroke.Parent = face

        local faceCorner = Instance.new("UICorner")
        faceCorner.CornerRadius = UDim.new(1, 0)
        faceCorner.Parent = face

        local eyeL = markIconPart(Instance.new("Frame"))
        eyeL.BackgroundTransparency = 0
        eyeL.BorderSizePixel = 0
        eyeL.Size = UDim2.new(0, px(3), 0, px(3))
        eyeL.Position = UDim2.new(0, px(6), 0, px(8))
        eyeL.Parent = root
        local eyeLCorner = Instance.new("UICorner")
        eyeLCorner.CornerRadius = UDim.new(1, 0)
        eyeLCorner.Parent = eyeL

        local eyeR = markIconPart(Instance.new("Frame"))
        eyeR.BackgroundTransparency = 0
        eyeR.BorderSizePixel = 0
        eyeR.Size = UDim2.new(0, px(3), 0, px(3))
        eyeR.Position = UDim2.new(0, px(17), 0, px(8))
        eyeR.Parent = root
        local eyeRCorner = Instance.new("UICorner")
        eyeRCorner.CornerRadius = UDim.new(1, 0)
        eyeRCorner.Parent = eyeR

        local smile = markIconPart(Instance.new("Frame"))
        smile.BackgroundTransparency = 0
        smile.BorderSizePixel = 0
        smile.Size = UDim2.new(0, px(10), 0, px(3))
        smile.Position = UDim2.new(0.5, 0, 0, px(14))
        smile.AnchorPoint = Vector2.new(0.5, 0)
        smile.Parent = root
        local smileCorner = Instance.new("UICorner")
        smileCorner.CornerRadius = UDim.new(1, 0)
        smileCorner.Parent = smile
    elseif tabId == "effects" then
        local sparkleV = markIconPart(Instance.new("Frame"))
        sparkleV.BackgroundTransparency = 0
        sparkleV.BorderSizePixel = 0
        sparkleV.Size = UDim2.new(0, px(3), 0, px(14))
        sparkleV.Position = UDim2.new(0.5, 0, 0, px(4))
        sparkleV.AnchorPoint = Vector2.new(0.5, 0)
        sparkleV.Parent = root
        local sparkleVCorner = Instance.new("UICorner")
        sparkleVCorner.CornerRadius = UDim.new(1, 0)
        sparkleVCorner.Parent = sparkleV

        local sparkleH = markIconPart(Instance.new("Frame"))
        sparkleH.BackgroundTransparency = 0
        sparkleH.BorderSizePixel = 0
        sparkleH.Size = UDim2.new(0, px(14), 0, px(3))
        sparkleH.Position = UDim2.new(0.5, 0, 0, px(10))
        sparkleH.AnchorPoint = Vector2.new(0.5, 0)
        sparkleH.Parent = root
        local sparkleHCorner = Instance.new("UICorner")
        sparkleHCorner.CornerRadius = UDim.new(1, 0)
        sparkleHCorner.Parent = sparkleH

        local miniA = markIconPart(Instance.new("Frame"))
        miniA.BackgroundTransparency = 0
        miniA.BorderSizePixel = 0
        miniA.Size = UDim2.new(0, px(2), 0, px(7))
        miniA.Position = UDim2.new(0, px(4), 0, px(2))
        miniA.Parent = root
        local miniACorner = Instance.new("UICorner")
        miniACorner.CornerRadius = UDim.new(1, 0)
        miniACorner.Parent = miniA

        local miniB = markIconPart(Instance.new("Frame"))
        miniB.BackgroundTransparency = 0
        miniB.BorderSizePixel = 0
        miniB.Size = UDim2.new(0, px(7), 0, px(2))
        miniB.Position = UDim2.new(0, px(2), 0, px(4))
        miniB.Parent = root
        local miniBCorner = Instance.new("UICorner")
        miniBCorner.CornerRadius = UDim.new(1, 0)
        miniBCorner.Parent = miniB

        local miniDot = markIconPart(Instance.new("Frame"))
        miniDot.BackgroundTransparency = 0
        miniDot.BorderSizePixel = 0
        miniDot.Size = UDim2.new(0, px(3), 0, px(3))
        miniDot.Position = UDim2.new(0, px(20), 0, px(3))
        miniDot.Parent = root
        local miniDotCorner = Instance.new("UICorner")
        miniDotCorner.CornerRadius = UDim.new(1, 0)
        miniDotCorner.Parent = miniDot
    elseif tabId == "coins" then
        -- Coin circle icon
        local coinOuter = markIconPart(Instance.new("Frame"))
        coinOuter.BackgroundTransparency = 0
        coinOuter.BorderSizePixel = 0
        coinOuter.Size = UDim2.new(0, px(18), 0, px(18))
        coinOuter.Position = UDim2.new(0.5, 0, 0, px(3))
        coinOuter.AnchorPoint = Vector2.new(0.5, 0)
        coinOuter.Parent = root
        local coinOuterCorner = Instance.new("UICorner")
        coinOuterCorner.CornerRadius = UDim.new(1, 0)
        coinOuterCorner.Parent = coinOuter

        -- Inner dollar sign text
        local coinSign = markIconPart(Instance.new("TextLabel"))
        coinSign.BackgroundTransparency = 1
        coinSign.Font = Enum.Font.GothamBlack
        coinSign.Text = "$"
        coinSign.TextSize = math.max(10, math.floor(px(12)))
        coinSign.Size = UDim2.new(1, 0, 1, 0)
        coinSign.TextXAlignment = Enum.TextXAlignment.Center
        coinSign.TextYAlignment = Enum.TextYAlignment.Center
        coinSign.Parent = coinOuter
    end

    return root
end

local function makeItem(gridParent, id, displayName, price, iconKey, coinApi, inventoryApi, category)
    category = category or "Ranged"
    local card = Instance.new("Frame")
    card.Name = "Item_" .. tostring(id)
    card.BackgroundColor3 = CARD_BG
    card.Size = UDim2.new(1, 0, 1, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.ZIndex = 250
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

    -- LEFT half: weapon image
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
            local key = iconKey or tostring(id)
            local img = AssetCodes.Get(key)
            if img and #img > 0 then thumb.Image = img end
        end
    end)

    -- RIGHT half: price row, name, buy button
    local rightBox = Instance.new("Frame")
    rightBox.Name = "RightBox"
    rightBox.Size = UDim2.new(0.52, 0, 1, 0)
    rightBox.Position = UDim2.new(0.48, 0, 0, 0)
    rightBox.BackgroundTransparency = 1
    rightBox.ZIndex = 251
    rightBox.Parent = card

    -- Price badge (framed, matches Quests reward badge style)
    local priceBadge = Instance.new("Frame")
    priceBadge.Name = "PriceBadge"
    priceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
    priceBadge.BackgroundTransparency = 0.3
    priceBadge.Size = UDim2.new(0.85, 0, 0, px(24))
    priceBadge.AnchorPoint = Vector2.new(0.5, 0)
    priceBadge.Position = UDim2.new(0.5, 0, 0.04, 0)
    priceBadge.ZIndex = 252
    priceBadge.Parent = rightBox
    local badgeCr = Instance.new("UICorner")
    badgeCr.CornerRadius = UDim.new(0, px(8))
    badgeCr.Parent = priceBadge
    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Color3.fromRGB(255, 200, 40)
    badgeStroke.Thickness = 1
    badgeStroke.Transparency = 0.55
    badgeStroke.Parent = priceBadge

    local priceLabel = Instance.new("TextLabel")
    priceLabel.Name = "Price"
    priceLabel.Size = UDim2.new(0.58, 0, 1, 0)
    priceLabel.Position = UDim2.new(0, 0, 0, 0)
    priceLabel.BackgroundTransparency = 1
    priceLabel.Font = Enum.Font.GothamBold
    priceLabel.TextScaled = true
    priceLabel.TextColor3 = GOLD
    priceLabel.TextXAlignment = Enum.TextXAlignment.Right
    priceLabel.Text = (price > 0) and tostring(price) or "FREE"
    priceLabel.ZIndex = 253
    priceLabel.Parent = priceBadge

    local coinIcon = Instance.new("ImageLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.Size = UDim2.new(0.26, 0, 0.80, 0)
    coinIcon.Position = UDim2.new(0.64, 0, 0.5, 0)
    coinIcon.AnchorPoint = Vector2.new(0, 0.5)
    coinIcon.BackgroundTransparency = 1
    coinIcon.ScaleType = Enum.ScaleType.Fit
    coinIcon.ZIndex = 253
    coinIcon.Parent = priceBadge
    coinIcon.Visible = (price > 0)
    pcall(function()
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local ci = AssetCodes.Get("Coin")
            if ci and #ci > 0 then coinIcon.Image = ci end
        end
    end)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "ItemName"
    nameLabel.Size = UDim2.new(1, 0, 0.22, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.34, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true
    nameLabel.TextColor3 = WHITE
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Text = displayName
    nameLabel.ZIndex = 252
    nameLabel.Parent = rightBox

    local buyBtn = Instance.new("TextButton")
    buyBtn.Name = "BuyBtn"
    buyBtn.Size = UDim2.new(0.85, 0, 0.24, 0)
    buyBtn.AnchorPoint = Vector2.new(0.5, 1)
    buyBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
    buyBtn.BackgroundColor3 = BTN_BUY
    buyBtn.Font = Enum.Font.GothamBold
    buyBtn.TextScaled = true
    buyBtn.TextColor3 = WHITE
    buyBtn.AutoButtonColor = false
    buyBtn.ZIndex = 253
    buyBtn.Parent = rightBox
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, px(10))
    btnCorner.Parent = buyBtn
    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = BTN_STROKE_C
    btnStroke.Thickness = 1.4
    btnStroke.Transparency = 0.25
    btnStroke.Parent = buyBtn

    local function refresh()
        local owned = false
        if inventoryApi and inventoryApi.HasItem then
            pcall(function() owned = inventoryApi:HasItem(id) end)
        end
        if owned then
            buyBtn.Text = "\u{2714} OWNED"
            buyBtn.Active = false
            buyBtn.BackgroundColor3 = DISABLED_BG
            buyBtn.TextColor3 = GREEN_GLOW
            btnStroke.Color = GREEN_GLOW
            btnStroke.Transparency = 0.45
            -- Update card visual for owned state
            card.BackgroundColor3 = CARD_OWNED
            stroke.Color = GREEN_GLOW
            stroke.Thickness = 1.6
            stroke.Transparency = 0.35
        else
            buyBtn.Text = "BUY"
            buyBtn.Active = true
            buyBtn.BackgroundColor3 = BTN_BUY
            buyBtn.TextColor3 = WHITE
            btnStroke.Color = BTN_STROKE_C
            btnStroke.Transparency = 0.25
            -- Reset card visual for purchasable state
            card.BackgroundColor3 = CARD_BG
            stroke.Color = CARD_STROKE
            stroke.Thickness = 1.2
            stroke.Transparency = 0.35
        end
    end
    refresh()

    -- hover: highlight on hover when actionable (matches Boosts/Quests style)
    buyBtn.MouseEnter:Connect(function()
        if buyBtn.Active then
            pcall(function()
                TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end)
        end
    end)
    buyBtn.MouseLeave:Connect(function()
        if buyBtn.Active then
            pcall(function()
                TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BUY}):Play()
            end)
        end
    end)

    buyBtn.MouseButton1Click:Connect(function()
        if not buyBtn.Active then return end
        local owned = false
        if inventoryApi and inventoryApi.HasItem then
            pcall(function() owned = inventoryApi:HasItem(id) end)
        end
        if owned then return end

        -- Price-zero items: just grant immediately, no coin check needed
        if price <= 0 then
            if inventoryApi and inventoryApi.AddItem then
                inventoryApi:AddItem(id)
            end
            local req = ReplicatedStorage:FindFirstChild("RequestToolCopy")
            if req and req:IsA("RemoteFunction") then
                pcall(function() req:InvokeServer(category, id) end)
            end
            refresh()
            return
        end

        -- Server-authoritative purchase: validates price & deducts coins on the server
        local purchaseFn = ReplicatedStorage:FindFirstChild("PurchaseTool")
        if purchaseFn and purchaseFn:IsA("RemoteFunction") then
            local ok, success, newBalance = pcall(function()
                return purchaseFn:InvokeServer(category, id)
            end)
            if ok and success then
                -- Server accepted the purchase; update local state
                if coinApi and coinApi.SetCoins then
                    pcall(function() coinApi.SetCoins(newBalance) end)
                end
                if inventoryApi and inventoryApi.AddItem then
                    inventoryApi:AddItem(id)
                end
                pcall(function()
                    if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                end)
                refresh()
                -- play local purchase sound if available
                pcall(function()
                    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
                    if soundsFolder then
                        local s = soundsFolder:FindFirstChild("Buy") or (soundsFolder:FindFirstChild("UI") and soundsFolder.UI:FindFirstChild("Buy"))
                        if s and s:IsA("Sound") then
                            local clone = s:Clone()
                            clone.Parent = buyBtn
                            clone:Play()
                            task.delay(clone.TimeLength + 0.1, function()
                                pcall(function() clone:Destroy() end)
                            end)
                        end
                    end
                end)
            else
                -- Not enough coins or server error
                buyBtn.Text = "NOT ENOUGH"
                buyBtn.TextColor3 = RED_TEXT
                btnStroke.Color = RED_TEXT
                btnStroke.Transparency = 0.3
                task.delay(1.2, function()
                    buyBtn.TextColor3 = WHITE
                    btnStroke.Color = BTN_STROKE_C
                    btnStroke.Transparency = 0.25
                    refresh()
                end)
            end
        else
            warn("[ShopUI] PurchaseTool remote not found")
        end
    end)

    return card
end

function ShopUI.Create(parent, coinApi, inventoryApi)
    if not parent then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") then
            pcall(function() c:Destroy() end)
        end
    end

    -- Ensure we have AssetCodes cached (safe)
    AssetCodes = AssetCodes or safeRequireAssetCodes()
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

    ---------------------------------------------------------------------------
    -- Layout constants (sidebar dimensions matching DailyQuestsUI)
    ---------------------------------------------------------------------------
    local TAB_W   = px(130)
    local TAB_GAP = px(10)

    ---------------------------------------------------------------------------
    -- Root container (absolute positioning for sidebar + content, like Quests)
    ---------------------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name                = "ShopRoot"
    root.BackgroundTransparency = 1
    root.Size                = UDim2.new(1, 0, 0, px(600))
    root.ZIndex              = 240
    root.LayoutOrder         = 1
    root.ClipsDescendants    = false
    root.Parent              = parent

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop    = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(6))
    rootPad.Parent        = root

    ---------------------------------------------------------------------------
    -- Left sidebar (vertical tab rail, mirrors DailyQuestsUI TabSidebar)
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
    sideCorner.CornerRadius = UDim.new(0, px(10))
    sideCorner.Parent = sidebar

    local sideStroke = Instance.new("UIStroke")
    sideStroke.Color        = CARD_STROKE
    sideStroke.Thickness    = 1.2
    sideStroke.Transparency = 0.3
    sideStroke.Parent       = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    sideLayout.Padding             = UDim.new(0, px(3))
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent              = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop    = UDim.new(0, px(10))
    sidePad.PaddingBottom = UDim.new(0, px(10))
    sidePad.PaddingLeft   = UDim.new(0, px(6))
    sidePad.PaddingRight  = UDim.new(0, px(6))
    sidePad.Parent        = sidebar

    ---------------------------------------------------------------------------
    -- Build tab buttons (vertical, mirrors DailyQuestsUI makeTabButton)
    ---------------------------------------------------------------------------
    local tabButtons   = {}  -- [id] -> TextButton
    local contentPages = {}  -- [id] -> Frame
    local currentTab   = "weapons"

    local function makeTabButton(def)
        local btn = Instance.new("TextButton")
        btn.Name            = def.label .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size            = UDim2.new(1, -px(2), 0, px(62))
        btn.LayoutOrder     = def.order
        btn.Text            = ""
        btn.Parent          = sidebar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent       = btn

        -- Active indicator bar (left edge, hidden by default)
        local bar = Instance.new("Frame")
        bar.Name                   = "ActiveBar"
        bar.BackgroundColor3       = GOLD
        bar.BorderSizePixel        = 0
        bar.Size                   = UDim2.new(0, px(3), 0.6, 0)
        bar.AnchorPoint            = Vector2.new(0, 0.5)
        bar.Position               = UDim2.new(0, 0, 0.5, 0)
        bar.BackgroundTransparency = 1
        local barCr = Instance.new("UICorner")
        barCr.CornerRadius = UDim.new(0.5, 0)
        barCr.Parent = bar
        bar.Parent = btn

        -- Keep original glyph rendering for Weapons/Boosts only.
        -- Other tabs get custom vector-style icons for clarity at small size.
        if def.id == "weapons" or def.id == "boosts" then
            local iconLbl = Instance.new("TextLabel")
            iconLbl.Name                = "Icon"
            iconLbl.BackgroundTransparency = 1
            iconLbl.Font                = Enum.Font.GothamBold
            iconLbl.Text                = def.icon
            iconLbl.TextColor3          = DIM_TEXT
            iconLbl.TextSize            = math.max(16, math.floor(px(18)))
            iconLbl.Size                = UDim2.new(1, 0, 0, px(24))
            iconLbl.Position            = UDim2.new(0, 0, 0, px(8))
            iconLbl.TextXAlignment      = Enum.TextXAlignment.Center
            iconLbl.Parent              = btn
        else
            local custom = buildCustomTabIcon(btn, def.id)
            setTabIconTint(custom, getCustomTabIconColor(def.id, false))
        end

        -- Text label
        local textLbl = Instance.new("TextLabel")
        textLbl.Name                = "Label"
        textLbl.BackgroundTransparency = 1
        textLbl.Font                = Enum.Font.GothamBold
        textLbl.Text                = def.label
        textLbl.TextColor3          = DIM_TEXT
        textLbl.TextSize            = math.max(11, math.floor(px(12)))
        textLbl.Size                = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position            = UDim2.new(0, px(3), 0, px(34))
        textLbl.TextXAlignment      = Enum.TextXAlignment.Center
        textLbl.TextTruncate        = Enum.TextTruncate.None
        textLbl.Parent              = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color        = CARD_STROKE
        btnStroke.Thickness    = 1.2
        btnStroke.Transparency = 0.6
        btnStroke.Parent       = btn

        return btn
    end

    for _, def in ipairs(TAB_DEFS) do
        tabButtons[def.id] = makeTabButton(def)
    end

    local function attachEmptyStateCategoryIcon(card, tabId, fallbackGlyph)
        local iconPlate = Instance.new("Frame")
        iconPlate.Name = "PlaceholderIconPlate"
        iconPlate.BackgroundColor3 = ICON_BG
        iconPlate.BackgroundTransparency = 0.15
        iconPlate.BorderSizePixel = 0
        iconPlate.Size = UDim2.new(0, px(74), 0, px(74))
        iconPlate.AnchorPoint = Vector2.new(0.5, 0)
        iconPlate.Position = UDim2.new(0.5, 0, 0, px(12))
        iconPlate.Parent = card

        local plateCorner = Instance.new("UICorner")
        plateCorner.CornerRadius = UDim.new(0, px(14))
        plateCorner.Parent = iconPlate

        local plateStroke = Instance.new("UIStroke")
        plateStroke.Color = CARD_STROKE
        plateStroke.Thickness = 1.1
        plateStroke.Transparency = 0.45
        plateStroke.Parent = iconPlate

        local sourceBtn = tabButtons[tabId]
        local sourceCustom = sourceBtn and sourceBtn:FindFirstChild("IconCustom")
        local sourceGlyph = sourceBtn and sourceBtn:FindFirstChild("Icon")

        local iconRef = "none"
        local iconVisual = nil

        if sourceCustom and sourceCustom:IsA("Frame") then
            iconVisual = sourceCustom:Clone()
            iconVisual.Name = "PlaceholderIconVisual"
            iconVisual.AnchorPoint = Vector2.new(0.5, 0.5)
            iconVisual.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconVisual.Size = UDim2.fromOffset(px(26), px(24))
            iconVisual.BackgroundTransparency = 1
            iconVisual.Parent = iconPlate

            local iconScale = Instance.new("UIScale")
            iconScale.Scale = 2.3
            iconScale.Parent = iconVisual

            setTabIconTint(iconVisual, getCustomTabIconColor(tabId, true))
            iconRef = "tab:IconCustom"
        else
            local glyph = fallbackGlyph
            if sourceGlyph and sourceGlyph:IsA("TextLabel") and sourceGlyph.Text ~= "" then
                glyph = sourceGlyph.Text
            end

            local iconGlyph = Instance.new("TextLabel")
            iconGlyph.Name = "PlaceholderIconVisual"
            iconGlyph.BackgroundTransparency = 1
            iconGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
            iconGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconGlyph.Size = UDim2.new(1, -px(12), 1, -px(12))
            iconGlyph.Font = Enum.Font.GothamBold
            iconGlyph.Text = glyph or "?"
            iconGlyph.TextSize = math.max(24, math.floor(px(34)))
            iconGlyph.TextColor3 = getCustomTabIconColor(tabId, true)
            iconGlyph.TextXAlignment = Enum.TextXAlignment.Center
            iconGlyph.TextYAlignment = Enum.TextYAlignment.Center
            iconGlyph.Parent = iconPlate

            iconVisual = iconGlyph
            iconRef = "tab:IconGlyph"
        end

        print(string.format("[EmptyStateIconDebug][Shop] category=%s iconRef=%s exists=%s", tostring(tabId), iconRef, tostring(iconVisual ~= nil)))
        task.defer(function()
            if not iconVisual or not iconVisual.Parent then
                print(string.format("[EmptyStateIconDebug][Shop] category=%s finalSize=n/a visible=false", tostring(tabId)))
                return
            end
            local size = iconVisual.AbsoluteSize
            print(string.format("[EmptyStateIconDebug][Shop] category=%s finalSize=%dx%d visible=%s", tostring(tabId), size.X, size.Y, tostring(iconVisual.Visible)))
        end)

        return iconVisual
    end

    ---------------------------------------------------------------------------
    -- Active-tab state management (mirrors DailyQuestsUI setActiveTab)
    ---------------------------------------------------------------------------
    local function setActiveTab(tabId)
        currentTab = tabId
        print(string.format("[EmptyStateIconDebug][Shop] selectedCategory=%s", tostring(tabId)))
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar    = btn:FindFirstChild("ActiveBar")
            local icon   = btn:FindFirstChild("Icon")
            local iconCustom = btn:FindFirstChild("IconCustom")
            local label  = btn:FindFirstChild("Label")
            local stroke = btn:FindFirstChildOfClass("UIStroke")

            if bar    then bar.BackgroundTransparency = active and 0    or 1    end
            if icon   then icon.TextColor3            = active and GOLD or DIM_TEXT end
            if iconCustom then setTabIconTint(iconCustom, getCustomTabIconColor(id, active)) end
            if label  then label.TextColor3           = active and WHITE or DIM_TEXT end
            if stroke then stroke.Transparency        = active and 0.2  or 0.6  end
        end
        for id, page in pairs(contentPages) do
            page.Visible = (id == tabId)
        end
    end

    ---------------------------------------------------------------------------
    -- Wire tab button clicks + hover feedback (mirrors DailyQuestsUI)
    ---------------------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        local id  = def.id
        local btn = tabButtons[id]

        btn.MouseButton1Click:Connect(function()
            print(string.format("[CategoryDebug][Shop] tab clicked=%s", tostring(id)))
            setActiveTab(id)
        end)
        btn.MouseEnter:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(28, 26, 18)}):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = SIDEBAR_BG}):Play()
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Content area (right of sidebar, mirrors DailyQuestsUI ContentArea)
    ---------------------------------------------------------------------------
    local contentContainer = Instance.new("Frame")
    contentContainer.Name                = "ContentArea"
    contentContainer.BackgroundTransparency = 1
    contentContainer.Size                = UDim2.new(1, -(TAB_W + TAB_GAP), 0, 0)
    contentContainer.Position            = UDim2.new(0, TAB_W + TAB_GAP, 0, 0)
    contentContainer.AutomaticSize       = Enum.AutomaticSize.Y
    contentContainer.ClipsDescendants    = false
    contentContainer.Parent              = root

    ---------------------------------------------------------------------------
    -- WEAPONS content page → CRATE CARDS
    ---------------------------------------------------------------------------
    local weaponsPage = Instance.new("Frame")
    weaponsPage.Name                = "WeaponsContent"
    weaponsPage.BackgroundTransparency = 1
    weaponsPage.Size                = UDim2.new(1, 0, 0, 0)
    weaponsPage.AutomaticSize       = Enum.AutomaticSize.Y
    weaponsPage.Visible             = true
    weaponsPage.Parent              = contentContainer

    local wpLayout = Instance.new("UIListLayout")
    wpLayout.SortOrder = Enum.SortOrder.LayoutOrder
    wpLayout.Padding   = UDim.new(0, px(16))
    wpLayout.Parent    = weaponsPage

    local wpPad = Instance.new("UIPadding")
    wpPad.PaddingTop    = UDim.new(0, px(6))
    wpPad.PaddingBottom = UDim.new(0, px(12))
    wpPad.PaddingLeft   = UDim.new(0, px(8))
    wpPad.PaddingRight  = UDim.new(0, px(8))
    wpPad.Parent        = weaponsPage

    -- Header
    local crateHeader = Instance.new("Frame")
    crateHeader.Name = "CrateHeader"
    crateHeader.BackgroundTransparency = 1
    crateHeader.Size = UDim2.new(1, 0, 0, px(54))
    crateHeader.LayoutOrder = 0
    crateHeader.Parent = weaponsPage

    local crateTitle = Instance.new("TextLabel")
    crateTitle.BackgroundTransparency = 1
    crateTitle.Font = Enum.Font.GothamBold
    crateTitle.Text = "WEAPON CRATES"
    crateTitle.TextColor3 = GOLD
    crateTitle.TextSize = math.max(20, math.floor(px(24)))
    crateTitle.TextXAlignment = Enum.TextXAlignment.Left
    crateTitle.Size = UDim2.new(1, 0, 0, px(30))
    crateTitle.Parent = crateHeader

    local crateSubtitle = Instance.new("TextLabel")
    crateSubtitle.BackgroundTransparency = 1
    crateSubtitle.Font = Enum.Font.GothamMedium
    crateSubtitle.Text = "Open crates to get random weapons. You can own duplicates!"
    crateSubtitle.TextColor3 = DIM_TEXT
    crateSubtitle.TextSize = math.max(11, math.floor(px(12)))
    crateSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    crateSubtitle.Size = UDim2.new(1, 0, 0, px(16))
    crateSubtitle.Position = UDim2.new(0, 0, 0, px(30))
    crateSubtitle.Parent = crateHeader

    local crateAccent = Instance.new("Frame")
    crateAccent.BackgroundColor3 = GOLD
    crateAccent.BackgroundTransparency = 0.3
    crateAccent.BorderSizePixel = 0
    crateAccent.Size = UDim2.new(1, 0, 0, px(2))
    crateAccent.Position = UDim2.new(0, 0, 1, -px(2))
    crateAccent.Parent = crateHeader

    -- Build crate cards from CrateConfig
    local crateOrder = (CrateConfig and CrateConfig.CrateOrder) or {}
    local crateOpenDebounce = false

    for idx, crateId in ipairs(crateOrder) do
        local crateDef = CrateConfig and CrateConfig.Crates[crateId]
        if not crateDef then continue end

        local card = Instance.new("Frame")
        card.Name = "Crate_" .. crateId
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(1, 0, 0, px(180))
        card.LayoutOrder = idx
        card.Parent = weaponsPage

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, px(14))
        cCorner.Parent = card

        local cStroke = Instance.new("UIStroke")
        cStroke.Color = CARD_STROKE
        cStroke.Thickness = 1.4
        cStroke.Transparency = 0.25
        cStroke.Parent = card

        local cPad = Instance.new("UIPadding")
        cPad.PaddingTop    = UDim.new(0, px(14))
        cPad.PaddingBottom = UDim.new(0, px(14))
        cPad.PaddingLeft   = UDim.new(0, px(14))
        cPad.PaddingRight  = UDim.new(0, px(14))
        cPad.Parent        = card

        -- Left: icon plate
        local iconPlate = Instance.new("Frame")
        iconPlate.Name = "IconPlate"
        iconPlate.BackgroundColor3 = ICON_BG
        iconPlate.Size = UDim2.new(0, px(100), 0, px(100))
        iconPlate.Position = UDim2.new(0, 0, 0.5, 0)
        iconPlate.AnchorPoint = Vector2.new(0, 0.5)
        iconPlate.Parent = card

        local ipCorner = Instance.new("UICorner")
        ipCorner.CornerRadius = UDim.new(0, px(12))
        ipCorner.Parent = iconPlate

        local ipStroke = Instance.new("UIStroke")
        ipStroke.Color = CARD_STROKE
        ipStroke.Thickness = 1
        ipStroke.Transparency = 0.4
        ipStroke.Parent = iconPlate

        local iconLabel = Instance.new("TextLabel")
        iconLabel.BackgroundTransparency = 1
        iconLabel.Font = Enum.Font.GothamBold
        iconLabel.Text = crateDef.iconGlyph or "?"
        iconLabel.TextSize = math.max(36, math.floor(px(42)))
        iconLabel.TextColor3 = GOLD
        iconLabel.Size = UDim2.new(1, 0, 1, 0)
        iconLabel.TextXAlignment = Enum.TextXAlignment.Center
        iconLabel.TextYAlignment = Enum.TextYAlignment.Center
        iconLabel.Parent = iconPlate

        -- Right: name, description, price, rarity chances, open button
        local rightX = px(100) + px(14)
        local rightW = UDim2.new(1, -(rightX), 1, 0)

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "CrateName"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = crateDef.displayName
        nameLabel.TextColor3 = WHITE
        nameLabel.TextSize = math.max(16, math.floor(px(18)))
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Size = UDim2.new(1, -rightX, 0, px(22))
        nameLabel.Position = UDim2.new(0, rightX, 0, 0)
        nameLabel.Parent = card

        local descLabel = Instance.new("TextLabel")
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.GothamMedium
        descLabel.Text = crateDef.description or ""
        descLabel.TextColor3 = DIM_TEXT
        descLabel.TextSize = math.max(11, math.floor(px(12)))
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextWrapped = true
        descLabel.Size = UDim2.new(1, -rightX, 0, px(16))
        descLabel.Position = UDim2.new(0, rightX, 0, px(24))
        descLabel.Parent = card

        -- Rarity chances row
        local rarityRow = Instance.new("Frame")
        rarityRow.Name = "RarityRow"
        rarityRow.BackgroundTransparency = 1
        rarityRow.Size = UDim2.new(1, -rightX, 0, px(18))
        rarityRow.Position = UDim2.new(0, rightX, 0, px(44))
        rarityRow.Parent = card

        local rrLayout = Instance.new("UIListLayout")
        rrLayout.FillDirection = Enum.FillDirection.Horizontal
        rrLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rrLayout.Padding = UDim.new(0, px(10))
        rrLayout.Parent = rarityRow

        -- Show rarity %s for this crate's pool
        if CrateConfig and CrateConfig.Rarities then
            -- Compute total weight for this pool
            local totalW = 0
            for _, entry in ipairs(crateDef.pool or {}) do
                local rd = CrateConfig.Rarities[entry.rarity]
                totalW = totalW + ((rd and rd.weight) or 0)
            end
            -- Aggregate by rarity
            local rarityTotals = {}
            for _, entry in ipairs(crateDef.pool or {}) do
                local rd = CrateConfig.Rarities[entry.rarity]
                local w = (rd and rd.weight) or 0
                rarityTotals[entry.rarity] = (rarityTotals[entry.rarity] or 0) + w
            end
            local order = 0
            for _, rarName in ipairs(CrateConfig.RarityOrder) do
                local w = rarityTotals[rarName]
                if w and w > 0 then
                    local pct = (totalW > 0) and (w / totalW * 100) or 0
                    local rd = CrateConfig.Rarities[rarName]
                    local tag = Instance.new("TextLabel")
                    tag.BackgroundTransparency = 1
                    tag.Font = Enum.Font.GothamBold
                    tag.TextSize = math.max(10, math.floor(px(11)))
                    tag.Text = string.format("%s %.0f%%", rd.label, pct)
                    tag.TextColor3 = rd.color
                    tag.Size = UDim2.new(0, px(80), 1, 0)
                    tag.TextXAlignment = Enum.TextXAlignment.Left
                    tag.LayoutOrder = order
                    tag.Parent = rarityRow
                    order = order + 1
                end
            end
        end

        -- Price badge
        local priceBadge = Instance.new("Frame")
        priceBadge.Name = "PriceBadge"
        priceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
        priceBadge.BackgroundTransparency = 0.3
        priceBadge.Size = UDim2.new(0, px(100), 0, px(28))
        priceBadge.Position = UDim2.new(0, rightX, 0, px(68))
        priceBadge.Parent = card

        local pbCorner = Instance.new("UICorner")
        pbCorner.CornerRadius = UDim.new(0, px(8))
        pbCorner.Parent = priceBadge

        local pbStroke = Instance.new("UIStroke")
        pbStroke.Color = Color3.fromRGB(255, 200, 40)
        pbStroke.Thickness = 1
        pbStroke.Transparency = 0.55
        pbStroke.Parent = priceBadge

        local priceLabel = Instance.new("TextLabel")
        priceLabel.BackgroundTransparency = 1
        priceLabel.Font = Enum.Font.GothamBold
        priceLabel.TextScaled = true
        priceLabel.TextColor3 = GOLD
        priceLabel.Text = tostring(crateDef.price or 0)
        priceLabel.Size = UDim2.new(0.55, 0, 1, 0)
        priceLabel.TextXAlignment = Enum.TextXAlignment.Right
        priceLabel.Parent = priceBadge

        local coinIcon = Instance.new("ImageLabel")
        coinIcon.BackgroundTransparency = 1
        coinIcon.Size = UDim2.new(0.26, 0, 0.80, 0)
        coinIcon.Position = UDim2.new(0.62, 0, 0.5, 0)
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.ScaleType = Enum.ScaleType.Fit
        coinIcon.Parent = priceBadge
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local ci = AssetCodes.Get("Coin")
                if ci and #ci > 0 then coinIcon.Image = ci end
            end
        end)

        -- Open button
        local openBtn = Instance.new("TextButton")
        openBtn.Name = "OpenBtn"
        openBtn.Size = UDim2.new(0, px(120), 0, px(36))
        openBtn.AnchorPoint = Vector2.new(0, 1)
        openBtn.Position = UDim2.new(0, rightX, 1, 0)
        openBtn.BackgroundColor3 = GREEN_BTN
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextScaled = true
        openBtn.TextColor3 = WHITE
        openBtn.Text = "OPEN CRATE"
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 253
        openBtn.Parent = card

        local obCorner = Instance.new("UICorner")
        obCorner.CornerRadius = UDim.new(0, px(10))
        obCorner.Parent = openBtn

        local obStroke = Instance.new("UIStroke")
        obStroke.Color = Color3.fromRGB(30, 200, 80)
        obStroke.Thickness = 1.4
        obStroke.Transparency = 0.25
        obStroke.Parent = openBtn

        -- Hover
        openBtn.MouseEnter:Connect(function()
            pcall(function()
                TweenService:Create(openBtn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(40, 210, 90)}):Play()
            end)
        end)
        openBtn.MouseLeave:Connect(function()
            pcall(function()
                TweenService:Create(openBtn, TWEEN_QUICK,
                    {BackgroundColor3 = GREEN_BTN}):Play()
            end)
        end)

        -- Click: fire crate open
        openBtn.MouseButton1Click:Connect(function()
            if crateOpenDebounce then return end
            crateOpenDebounce = true

            -- Fire the crate opening event via global callback
            -- The CrateOpeningUI will handle the animation and server call
            if _G.OpenCrateRequested then
                _G.OpenCrateRequested(crateId)
            else
                -- Fallback: direct server call without animation
                local openCrateRF = ReplicatedStorage:FindFirstChild("OpenCrate")
                if openCrateRF and openCrateRF:IsA("RemoteFunction") then
                    local ok, success, result = pcall(function()
                        return openCrateRF:InvokeServer(crateId)
                    end)
                    if ok and success and type(result) == "table" then
                        if coinApi and coinApi.SetCoins then
                            pcall(function() coinApi.SetCoins(result.newBalance) end)
                        end
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        showToast(weaponsPage,
                            string.format("Got %s (%s)!", result.weaponName, result.rarity),
                            CrateConfig and CrateConfig.Rarities[result.rarity] and CrateConfig.Rarities[result.rarity].color or GOLD,
                            3)
                    elseif ok and not success then
                        showToast(weaponsPage,
                            type(result) == "string" and result or "Purchase failed",
                            RED_TEXT, 2)
                    end
                end
            end

            task.delay(1.5, function()
                crateOpenDebounce = false
            end)
        end)
    end

    contentPages["weapons"] = weaponsPage

    ---------------------------------------------------------------------------
    -- BOOSTS content page (purchase adds to owned inventory only)
    ---------------------------------------------------------------------------
    local boostsPage = Instance.new("Frame")
    boostsPage.Name = "BoostsContent"
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
    boostsSubtitle.Text = "Buy boosts here, then activate them later from Inventory > Boosts."
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
    helperNote.Text = "Purchases add to your inventory only. Active effects still use the existing timer system."
    helperNote.TextColor3 = DIM_TEXT
    helperNote.TextSize = math.max(10, math.floor(px(11)))
    helperNote.TextXAlignment = Enum.TextXAlignment.Left
    helperNote.Size = UDim2.new(1, 0, 0, px(14))
    helperNote.LayoutOrder = 2
    helperNote.Parent = boostsPage

    local boostStates = {}
    local boostCards = {}
    local shopBoostDefs = {}

    if BoostConfig and BoostConfig.Boosts then
        for _, def in ipairs(BoostConfig.Boosts) do
            if not def.InstantUse then
                table.insert(shopBoostDefs, def)
            end
        end
        table.sort(shopBoostDefs, function(a, b)
            return (a.SortOrder or 0) < (b.SortOrder or 0)
        end)
    end

    local remotes = ensureBoostRemotes()
    if remotes and remotes.getStates then
        pcall(function()
            local states = remotes.getStates:InvokeServer()
            if type(states) == "table" then
                boostStates = states
            end
        end)
    end

    local function formatDuration(seconds)
        seconds = math.max(0, math.floor(tonumber(seconds) or 0))
        local mins = math.floor(seconds / 60)
        if mins > 0 then
            return string.format("%d min", mins)
        end
        return string.format("%d sec", seconds)
    end

    local function refreshBoostCards(states)
        if type(states) == "table" then
            boostStates = states
        end
        for _, def in ipairs(shopBoostDefs) do
            local refs = boostCards[def.Id]
            local state = boostStates[def.Id] or {}
            if refs then
                local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
                refs.owned.Text = string.format("Owned: %d", owned)
                refs.status.Text = state.active and "Active now" or "Inactive"
                refs.status.TextColor3 = state.active and GREEN_GLOW or DIM_TEXT
            end
        end
    end

    if #shopBoostDefs == 0 or not remotes then
        local unavailable = Instance.new("TextLabel")
        unavailable.BackgroundTransparency = 1
        unavailable.Font = Enum.Font.GothamMedium
        unavailable.Text = "Boost purchases are currently unavailable."
        unavailable.TextColor3 = DIM_TEXT
        unavailable.TextSize = math.max(14, math.floor(px(15)))
        unavailable.Size = UDim2.new(1, 0, 0, px(50))
        unavailable.LayoutOrder = 10
        unavailable.Parent = boostsPage
    else
        for index, def in ipairs(shopBoostDefs) do
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

            local iconColor = GOLD
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
            print(string.format("[BoostIconDebug][Shop] %s -> %s  (visible=%s)",
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

            local price = Instance.new("TextLabel")
            price.BackgroundTransparency = 1
            price.Font = Enum.Font.GothamBold
            price.Text = string.format("Cost: %d Coins", def.PriceCoins or 0)
            price.TextColor3 = GOLD
            price.TextSize = math.max(12, math.floor(px(13)))
            price.TextXAlignment = Enum.TextXAlignment.Left
            price.Size = UDim2.new(0.45, -px(74), 0, px(18))
            price.Position = UDim2.new(0, px(74), 1, -px(22))
            price.Parent = card

            local duration = Instance.new("TextLabel")
            duration.BackgroundTransparency = 1
            duration.Font = Enum.Font.GothamMedium
            duration.Text = string.format("Duration: %s", formatDuration(def.DurationSeconds))
            duration.TextColor3 = DIM_TEXT
            duration.TextSize = math.max(10, math.floor(px(11)))
            duration.TextXAlignment = Enum.TextXAlignment.Left
            duration.Size = UDim2.new(0.45, -px(74), 0, px(16))
            duration.Position = UDim2.new(0, px(74), 1, -px(40))
            duration.Parent = card

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
            status.Text = "Inactive"
            status.TextColor3 = DIM_TEXT
            status.TextSize = math.max(10, math.floor(px(11)))
            status.TextXAlignment = Enum.TextXAlignment.Right
            status.Size = UDim2.new(0.34, 0, 0, px(16))
            status.Position = UDim2.new(0.66, 0, 0, px(34))
            status.Parent = card

            local buyBtn = Instance.new("TextButton")
            buyBtn.Name = "BuyBtn"
            buyBtn.AutoButtonColor = false
            buyBtn.BackgroundColor3 = BTN_BUY
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.Text = "BUY"
            buyBtn.TextColor3 = WHITE
            buyBtn.TextSize = math.max(12, math.floor(px(13)))
            buyBtn.Size = UDim2.new(0, px(120), 0, px(36))
            buyBtn.AnchorPoint = Vector2.new(1, 1)
            buyBtn.Position = UDim2.new(1, 0, 1, 0)
            buyBtn.Parent = card

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, px(10))
            btnCorner.Parent = buyBtn

            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = BTN_STROKE_C
            btnStroke.Thickness = 1.3
            btnStroke.Transparency = 0.25
            btnStroke.Parent = buyBtn

            buyBtn.MouseEnter:Connect(function()
                TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end)
            buyBtn.MouseLeave:Connect(function()
                TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BUY}):Play()
            end)

            buyBtn.MouseButton1Click:Connect(function()
                local ok, success, message, states = pcall(function()
                    return remotes.purchase:InvokeServer(def.Id)
                end)
                if ok and success then
                    refreshBoostCards(states)
                    pcall(function()
                        if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                    end)
                    buyBtn.Text = "BOUGHT"
                    showToast(boostsPage, (message or "Purchased") .. " - stored in Inventory > Boosts.", GREEN_GLOW, 2.4)
                    task.delay(0.9, function()
                        if buyBtn and buyBtn.Parent then
                            buyBtn.Text = "BUY"
                        end
                    end)
                else
                    local reason = ok and message or "Purchase failed"
                    buyBtn.Text = "ERROR"
                    showToast(boostsPage, tostring(reason), RED_TEXT, 2.4)
                    task.delay(0.9, function()
                        if buyBtn and buyBtn.Parent then
                            buyBtn.Text = "BUY"
                        end
                    end)
                end
            end)

            boostCards[def.Id] = {
                owned = owned,
                status = status,
            }
        end

        refreshBoostCards(boostStates)

        trackConn(remotes.stateUpdated.OnClientEvent:Connect(function(states)
            refreshBoostCards(states)
        end))
    end

    contentPages["boosts"] = boostsPage

    ---------------------------------------------------------------------------
    -- Placeholder content pages (Skins, Effects). Trails are now grouped under Effects.
    ---------------------------------------------------------------------------
    local function makePlaceholderPage(name, tabId, placeholderIcon, message)
        local page = Instance.new("Frame")
        page.Name                = name
        page.BackgroundTransparency = 1
        page.Size                = UDim2.new(1, 0, 0, px(300))
        page.Visible             = false
        page.Parent              = contentContainer

        -- Centered placeholder card
        local card = Instance.new("Frame")
        card.Name            = "PlaceholderCard"
        card.BackgroundColor3 = CARD_BG
        card.Size            = UDim2.new(0.6, 0, 0, px(180))
        card.AnchorPoint     = Vector2.new(0.5, 0.5)
        card.Position        = UDim2.new(0.5, 0, 0.5, 0)
        card.Parent          = page

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, px(16))
        cardCorner.Parent       = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color        = CARD_STROKE
        cardStroke.Thickness    = 1.4
        cardStroke.Transparency = 0.25
        cardStroke.Parent       = card

        attachEmptyStateCategoryIcon(card, tabId, placeholderIcon)

        -- "Coming Soon" heading
        local msgLbl = Instance.new("TextLabel")
        msgLbl.Name                = "PlaceholderMsg"
        msgLbl.BackgroundTransparency = 1
        msgLbl.Font                = Enum.Font.GothamBold
        msgLbl.Text                = message
        msgLbl.TextColor3          = GOLD
        msgLbl.TextSize            = math.max(16, math.floor(px(18)))
        msgLbl.Size                = UDim2.new(1, 0, 0, px(28))
        msgLbl.Position            = UDim2.new(0, 0, 0.48, 0)
        msgLbl.TextXAlignment      = Enum.TextXAlignment.Center
        msgLbl.Parent              = card

        -- Subtext
        local subLbl = Instance.new("TextLabel")
        subLbl.Name                = "PlaceholderSub"
        subLbl.BackgroundTransparency = 1
        subLbl.Font                = Enum.Font.GothamMedium
        subLbl.Text                = "Check back soon for new items!"
        subLbl.TextColor3          = DIM_TEXT
        subLbl.TextSize            = math.max(12, math.floor(px(13)))
        subLbl.Size                = UDim2.new(1, 0, 0, px(20))
        subLbl.Position            = UDim2.new(0, 0, 0.66, 0)
        subLbl.TextXAlignment      = Enum.TextXAlignment.Center
        subLbl.Parent              = card

        contentPages[tabId] = page
        return page
    end

    makePlaceholderPage("SkinsContent",   "skins",   "\u{2726}", "Skins coming soon")

    ---------------------------------------------------------------------------
    -- EFFECTS content page (real shop page, reads from EffectDefs)
    ---------------------------------------------------------------------------
    do
        local EffectDefs = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
            if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
        end)

        local effectRemotes = nil
        local function ensureEffectRemotes()
            if effectRemotes then return effectRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local ef = rf:FindFirstChild("Effects") or rf:WaitForChild("Effects", 5)
            if not ef then return nil end
            effectRemotes = {
                purchase = ef:FindFirstChild("PurchaseEffect"),
                getOwned = ef:FindFirstChild("GetOwnedEffects"),
            }
            return effectRemotes
        end

        -- Only show purchasable effects (exclude free defaults), sorted by price
        local allEffects = {}
        if EffectDefs then
            for _, def in ipairs(EffectDefs.GetAll()) do
                if not def.IsFree then
                    table.insert(allEffects, def)
                end
            end
            table.sort(allEffects, function(a, b)
                local pa = a.CoinCost or 0
                local pb = b.CoinCost or 0
                if pa ~= pb then return pa < pb end
                return (a.DisplayName or a.Id) < (b.DisplayName or b.Id)
            end)
            print("[Shop] Applied effect sort by price")
        end

        if #allEffects > 0 then
            local effectsPage = Instance.new("Frame")
            effectsPage.Name                = "EffectsContent"
            effectsPage.BackgroundTransparency = 1
            effectsPage.Size                = UDim2.new(1, 0, 0, 0)
            effectsPage.AutomaticSize       = Enum.AutomaticSize.Y
            effectsPage.Visible             = false
            effectsPage.Parent              = contentContainer

            local epLayout = Instance.new("UIListLayout")
            epLayout.SortOrder = Enum.SortOrder.LayoutOrder
            epLayout.Padding   = UDim.new(0, px(16))
            epLayout.Parent    = effectsPage

            local effectSection, effectGrid = makeSection(effectsPage, "DashTrails", "Dash Trails")
            effectSection.LayoutOrder = 1

            -- Fetch owned effects from the server once
            local ownedSet = {}
            local effectRefreshFns = {}
            task.spawn(function()
                local remotes = ensureEffectRemotes()
                if remotes and remotes.getOwned and remotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return remotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then
                        for _, id in ipairs(list) do ownedSet[id] = true end
                        for _, fn in ipairs(effectRefreshFns) do
                            pcall(fn)
                        end
                    end
                end
            end)

            for i_effect, def in ipairs(allEffects) do
                local effectId    = def.Id
                local displayName = def.DisplayName or effectId
                local price       = def.CoinCost or 0
                local description = def.Description or ""
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)

                local card = Instance.new("Frame")
                card.Name = "Effect_" .. effectId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.AutomaticSize = Enum.AutomaticSize.Y
                card.LayoutOrder = i_effect
                card.ZIndex = 250
                card.Parent = effectGrid

                local crn = Instance.new("UICorner")
                crn.CornerRadius = UDim.new(0, px(12))
                crn.Parent = card
                local isEpic = (def.Rarity == "Epic")
                local stk = Instance.new("UIStroke")
                stk.Color = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                stk.Thickness = isEpic and 1.6 or 1.2
                stk.Transparency = isEpic and 0.2 or 0.35
                stk.Parent = card
                local cPad = Instance.new("UIPadding")
                cPad.PaddingTop    = UDim.new(0, px(8))
                cPad.PaddingBottom = UDim.new(0, px(8))
                cPad.PaddingLeft   = UDim.new(0, px(8))
                cPad.PaddingRight  = UDim.new(0, px(8))
                cPad.Parent = card

                -- LEFT: color swatch preview
                local leftBox = Instance.new("Frame")
                leftBox.Name = "LeftBox"
                leftBox.Size = UDim2.new(0.45, 0, 1, 0)
                leftBox.BackgroundColor3 = ICON_BG
                leftBox.ZIndex = 251
                leftBox.Parent = card
                local lCrn = Instance.new("UICorner")
                lCrn.CornerRadius = UDim.new(0, px(10))
                lCrn.Parent = leftBox
                local lStk = Instance.new("UIStroke")
                lStk.Color = CARD_STROKE; lStk.Thickness = 1; lStk.Transparency = 0.5
                lStk.Parent = leftBox

                -- Trail color swatch (colored streak icon)
                local isRainbow = def.IsRainbow == true
                local swatch = Instance.new("Frame")
                swatch.Name = "ColorSwatch"
                swatch.Size = UDim2.new(0.6, 0, 0.15, 0)
                swatch.AnchorPoint = Vector2.new(0.5, 0.5)
                swatch.Position = UDim2.new(0.5, 0, 0.4, 0)
                swatch.BackgroundColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                swatch.BorderSizePixel = 0
                swatch.ZIndex = 252
                swatch.Parent = leftBox
                local swatchCorner = Instance.new("UICorner")
                swatchCorner.CornerRadius = UDim.new(0.5, 0)
                swatchCorner.Parent = swatch
                -- Rainbow gradient on the swatch
                if isRainbow and def.TrailColorSequence then
                    local grad = Instance.new("UIGradient")
                    grad.Color = def.TrailColorSequence
                    grad.Parent = swatch
                end
                -- Glow effect on the swatch
                local swatchStroke = Instance.new("UIStroke")
                swatchStroke.Color = isRainbow and Color3.fromRGB(200, 160, 255) or effectColor
                swatchStroke.Thickness = px(2)
                swatchStroke.Transparency = 0.3
                swatchStroke.Parent = swatch

                -- "TRAIL" label beneath swatch
                local trailLabel = Instance.new("TextLabel")
                trailLabel.Name = "TrailLabel"
                trailLabel.Text = "\u{2550}\u{2550}\u{2550}"
                trailLabel.Font = Enum.Font.GothamBold
                trailLabel.TextColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                trailLabel.TextScaled = true
                trailLabel.BackgroundTransparency = 1
                trailLabel.Size = UDim2.new(0.8, 0, 0.2, 0)
                trailLabel.AnchorPoint = Vector2.new(0.5, 0)
                trailLabel.Position = UDim2.new(0.5, 0, 0.6, 0)
                trailLabel.ZIndex = 252
                trailLabel.Parent = leftBox
                if isRainbow and def.TrailColorSequence then
                    local glyphGrad = Instance.new("UIGradient")
                    glyphGrad.Color = def.TrailColorSequence
                    glyphGrad.Parent = trailLabel
                end

                -- RIGHT: name, description, price, buy button
                local rightBox = Instance.new("Frame")
                rightBox.Name = "RightBox"
                rightBox.Size = UDim2.new(0.52, 0, 1, 0)
                rightBox.Position = UDim2.new(0.48, 0, 0, 0)
                rightBox.BackgroundTransparency = 1
                rightBox.ZIndex = 251
                rightBox.Parent = card

                -- Price badge (matching emote card coin icon style)
                local priceBadge = Instance.new("Frame")
                priceBadge.Name = "PriceBadge"
                priceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
                priceBadge.BackgroundTransparency = 0.3
                priceBadge.Size = UDim2.new(0.85, 0, 0, px(24))
                priceBadge.AnchorPoint = Vector2.new(0.5, 0)
                priceBadge.Position = UDim2.new(0.5, 0, 0.04, 0)
                priceBadge.ZIndex = 252
                priceBadge.Parent = rightBox
                local pbCrn = Instance.new("UICorner")
                pbCrn.CornerRadius = UDim.new(0, px(8))
                pbCrn.Parent = priceBadge
                local pbStk = Instance.new("UIStroke")
                pbStk.Color = Color3.fromRGB(255, 200, 40); pbStk.Thickness = 1; pbStk.Transparency = 0.55
                pbStk.Parent = priceBadge

                local pbLbl = Instance.new("TextLabel")
                pbLbl.Name = "PriceText"
                pbLbl.BackgroundTransparency = 1
                pbLbl.Font = Enum.Font.GothamBold
                pbLbl.Text = (price > 0) and tostring(price) or "FREE"
                pbLbl.TextColor3 = GOLD
                pbLbl.TextScaled = true
                pbLbl.Size = UDim2.new(0.58, 0, 1, 0)
                pbLbl.Position = UDim2.new(0, 0, 0, 0)
                pbLbl.TextXAlignment = Enum.TextXAlignment.Right
                pbLbl.ZIndex = 253
                pbLbl.Parent = priceBadge

                local trailCoinIcon = Instance.new("ImageLabel")
                trailCoinIcon.Name = "CoinIcon"
                trailCoinIcon.Size = UDim2.new(0.26, 0, 0.80, 0)
                trailCoinIcon.Position = UDim2.new(0.64, 0, 0.5, 0)
                trailCoinIcon.AnchorPoint = Vector2.new(0, 0.5)
                trailCoinIcon.BackgroundTransparency = 1
                trailCoinIcon.ScaleType = Enum.ScaleType.Fit
                trailCoinIcon.ZIndex = 253
                trailCoinIcon.Visible = (price > 0)
                trailCoinIcon.Parent = priceBadge
                pcall(function()
                    if AssetCodes and type(AssetCodes.Get) == "function" then
                        local ci = AssetCodes.Get("Coin")
                        if ci and #ci > 0 then trailCoinIcon.Image = ci end
                    end
                end)

                print(string.format("[Shop] Rendering effect item: %s price=%d", displayName, price))

                -- Name label
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "ItemName"
                nameLabel.Size = UDim2.new(0.95, 0, 0.22, 0)
                nameLabel.Position = UDim2.new(0.04, 0, 0.26, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.Text = displayName
                nameLabel.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                nameLabel.TextSize = math.max(13, math.floor(px(15)))
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.ZIndex = 252
                nameLabel.Parent = rightBox

                -- Description label
                local descLabel = Instance.new("TextLabel")
                descLabel.Name = "Desc"
                descLabel.Size = UDim2.new(0.95, 0, 0.18, 0)
                descLabel.Position = UDim2.new(0.04, 0, 0.48, 0)
                descLabel.BackgroundTransparency = 1
                descLabel.Font = Enum.Font.GothamMedium
                descLabel.Text = description
                descLabel.TextColor3 = DIM_TEXT
                descLabel.TextSize = math.max(10, math.floor(px(11)))
                descLabel.TextXAlignment = Enum.TextXAlignment.Left
                descLabel.TextWrapped = true
                descLabel.ZIndex = 252
                descLabel.Parent = rightBox

                -- Buy button
                local buyBtn = Instance.new("TextButton")
                buyBtn.Name = "BuyBtn"
                buyBtn.Size = UDim2.new(0.85, 0, 0.24, 0)
                buyBtn.AnchorPoint = Vector2.new(0.5, 1)
                buyBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
                buyBtn.BackgroundColor3 = BTN_BUY
                buyBtn.BorderSizePixel = 0
                buyBtn.AutoButtonColor = false
                buyBtn.Font = Enum.Font.GothamBold
                buyBtn.Text = "BUY"
                buyBtn.TextColor3 = WHITE
                buyBtn.TextSize = math.max(13, math.floor(px(14)))
                buyBtn.ZIndex = 253
                buyBtn.Parent = rightBox
                local bCrn = Instance.new("UICorner")
                bCrn.CornerRadius = UDim.new(0, px(8))
                bCrn.Parent = buyBtn
                local bStk = Instance.new("UIStroke")
                bStk.Color = BTN_STROKE_C
                bStk.Thickness = 1.2
                bStk.Transparency = 0.25
                bStk.Parent = buyBtn

                -- Refresh display based on ownership
                local function refreshEffectCard()
                    local owned = ownedSet[effectId] == true
                    if owned then
                        buyBtn.Text = "\u{2714} OWNED"
                        buyBtn.Active = false
                        buyBtn.BackgroundColor3 = DISABLED_BG
                        buyBtn.TextColor3 = GREEN_GLOW
                        bStk.Color = GREEN_GLOW; bStk.Transparency = 0.45
                        card.BackgroundColor3 = CARD_OWNED
                        stk.Color = GREEN_GLOW; stk.Thickness = 1.6; stk.Transparency = 0.35
                    else
                        buyBtn.Text = "BUY"
                        buyBtn.Active = true
                        buyBtn.BackgroundColor3 = BTN_BUY
                        buyBtn.TextColor3 = WHITE
                        bStk.Color = BTN_STROKE_C; bStk.Transparency = 0.25
                        card.BackgroundColor3 = CARD_BG
                        stk.Color = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                        stk.Thickness = isEpic and 1.6 or 1.2
                        stk.Transparency = isEpic and 0.2 or 0.35
                    end
                end
                refreshEffectCard()
                table.insert(effectRefreshFns, refreshEffectCard)

                -- Hover effects
                if not game:GetService("UserInputService").TouchEnabled then
                    buyBtn.MouseEnter:Connect(function()
                        if buyBtn.Active then
                            TweenService:Create(buyBtn, TWEEN_QUICK, { BackgroundColor3 = GREEN_BTN }):Play()
                        end
                    end)
                    buyBtn.MouseLeave:Connect(function()
                        if buyBtn.Active then
                            TweenService:Create(buyBtn, TWEEN_QUICK, { BackgroundColor3 = BTN_BUY }):Play()
                        end
                    end)
                end

                -- Purchase click handler
                buyBtn.MouseButton1Click:Connect(function()
                    if not buyBtn.Active then return end
                    if ownedSet[effectId] then return end

                    local remotes = ensureEffectRemotes()
                    if not remotes or not remotes.purchase then
                        warn("[ShopUI] Effects purchase remote not found")
                        return
                    end

                    buyBtn.Active = false
                    buyBtn.Text = "..."

                    local ok, success, newBalance, msg = pcall(function()
                        return remotes.purchase:InvokeServer(effectId)
                    end)

                    if ok and success then
                        ownedSet[effectId] = true
                        if coinApi and coinApi.SetCoins then
                            coinApi:SetCoins(newBalance)
                        end
                        print("[ShopUI] Purchased", displayName)
                        refreshEffectCard()
                    else
                        buyBtn.Text = "NOT ENOUGH"
                        buyBtn.TextColor3 = RED_TEXT
                        print("[ShopUI] effect purchase rejected:", effectId, msg)
                        task.delay(1.2, function()
                            if not ownedSet[effectId] then
                                refreshEffectCard()
                            end
                        end)
                    end
                end)
            end -- end for each effect

            contentPages["effects"] = effectsPage
        else
            makePlaceholderPage("EffectsContent", "effects", "\u{2738}", "Effects coming soon")
        end
    end

    ---------------------------------------------------------------------------
    -- EMOTES content page (real shop page, reads from EmoteConfig)
    ---------------------------------------------------------------------------
    do
        local EmoteConfig = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EmoteConfig")
            if mod and mod:IsA("ModuleScript") then EmoteConfig = require(mod) end
        end)

        local emoteRemotes = nil
        local function ensureEmoteRemotes()
            if emoteRemotes then return emoteRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local ef = rf:FindFirstChild("Emotes") or rf:WaitForChild("Emotes", 5)
            if not ef then return nil end
            emoteRemotes = {
                purchase  = ef:FindFirstChild("PurchaseEmote"),
                getOwned  = ef:FindFirstChild("GetOwnedEmotes"),
            }
            return emoteRemotes
        end

        local allEmotes = EmoteConfig and EmoteConfig.GetAll() or {}

        if #allEmotes > 0 then
            local emotesPage = Instance.new("Frame")
            emotesPage.Name                = "EmotesContent"
            emotesPage.BackgroundTransparency = 1
            emotesPage.Size                = UDim2.new(1, 0, 0, 0)
            emotesPage.AutomaticSize       = Enum.AutomaticSize.Y
            emotesPage.Visible             = false
            emotesPage.Parent              = contentContainer

            local epLayout = Instance.new("UIListLayout")
            epLayout.SortOrder = Enum.SortOrder.LayoutOrder
            epLayout.Padding   = UDim.new(0, px(16))
            epLayout.Parent    = emotesPage

            local emoteSection, emoteGrid = makeSection(emotesPage, "Emotes", "Emotes")
            emoteSection.LayoutOrder = 1

            -- Fetch owned emotes from the server once
            local ownedSet = {}
            -- Build a card for each emote
            local emoteRefreshFns = {}
            task.spawn(function()
                local remotes = ensureEmoteRemotes()
                if remotes and remotes.getOwned and remotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return remotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then
                        for _, id in ipairs(list) do ownedSet[id] = true end
                        -- Refresh all emote cards now that owned data arrived
                        for _, fn in ipairs(emoteRefreshFns) do
                            pcall(fn)
                        end
                    end
                end
            end)

            for _, def in ipairs(allEmotes) do
                local emoteId     = def.Id
                local displayName = def.DisplayName or emoteId
                local price       = def.CoinCost or 0
                local iconKey     = def.IconKey
                local description = def.Description or ""

                local card = Instance.new("Frame")
                card.Name = "Emote_" .. emoteId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.AutomaticSize = Enum.AutomaticSize.Y
                card.ZIndex = 250
                card.Parent = emoteGrid

                local crn = Instance.new("UICorner")
                crn.CornerRadius = UDim.new(0, px(12))
                crn.Parent = card
                local stk = Instance.new("UIStroke")
                stk.Color = CARD_STROKE
                stk.Thickness = 1.2
                stk.Transparency = 0.35
                stk.Parent = card
                local cPad = Instance.new("UIPadding")
                cPad.PaddingTop    = UDim.new(0, px(8))
                cPad.PaddingBottom = UDim.new(0, px(8))
                cPad.PaddingLeft   = UDim.new(0, px(8))
                cPad.PaddingRight  = UDim.new(0, px(8))
                cPad.Parent = card

                -- LEFT: icon
                local leftBox = Instance.new("Frame")
                leftBox.Name = "LeftBox"
                leftBox.Size = UDim2.new(0.45, 0, 1, 0)
                leftBox.BackgroundColor3 = ICON_BG
                leftBox.ZIndex = 251
                leftBox.Parent = card
                local lCrn = Instance.new("UICorner")
                lCrn.CornerRadius = UDim.new(0, px(10))
                lCrn.Parent = leftBox
                local lStk = Instance.new("UIStroke")
                lStk.Color = CARD_STROKE; lStk.Thickness = 1; lStk.Transparency = 0.5
                lStk.Parent = leftBox

                local thumb = Instance.new("ImageLabel")
                thumb.Name = "Thumb"
                thumb.Size = UDim2.new(0.75, 0, 0.75, 0)
                thumb.AnchorPoint = Vector2.new(0.5, 0.5)
                thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
                thumb.BackgroundTransparency = 1
                thumb.ScaleType = Enum.ScaleType.Fit
                thumb.ZIndex = 252
                thumb.Parent = leftBox
                pcall(function()
                    if AssetCodes and iconKey then
                        local img = AssetCodes.Get(iconKey)
                        if img and #img > 0 then thumb.Image = img end
                    end
                end)

                -- Wave-specific shop preview: guaranteed-visible static glyph
                if emoteId == "wave" then
                    -- Hide the ImageLabel (asset was blank); use a TextLabel instead
                    thumb.Visible = false

                    local waveIcon = Instance.new("TextLabel")
                    waveIcon.Name = "WaveGlyph"
                    waveIcon.Text = WAVE_PREVIEW.glyph
                    waveIcon.Size = WAVE_PREVIEW.size
                    waveIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                    waveIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
                    waveIcon.BackgroundTransparency = 1
                    waveIcon.TextScaled = true
                    waveIcon.Font = Enum.Font.GothamBold
                    waveIcon.TextColor3 = GOLD
                    waveIcon.ZIndex = 252
                    waveIcon.Parent = leftBox

                    -- Debug prints (remove once confirmed working)
                    print("[ShopUI][WavePreview] preview source: TextLabel glyph")
                    print("[ShopUI][WavePreview] class:", waveIcon.ClassName)
                    print("[ShopUI][WavePreview] visible:", waveIcon.Visible)
                    print("[ShopUI][WavePreview] size:", tostring(waveIcon.Size))
                    print("[ShopUI][WavePreview] position:", tostring(waveIcon.Position))
                    print("[ShopUI][WavePreview] text (empty?):", waveIcon.Text == "" and "YES" or "NO", "text:", waveIcon.Text)
                end

                -- RIGHT: name, description, price, buy button
                local rightBox = Instance.new("Frame")
                rightBox.Name = "RightBox"
                rightBox.Size = UDim2.new(0.52, 0, 1, 0)
                rightBox.Position = UDim2.new(0.48, 0, 0, 0)
                rightBox.BackgroundTransparency = 1
                rightBox.ZIndex = 251
                rightBox.Parent = card

                -- Price badge (match standard shop item card style)
                local priceBadge = Instance.new("Frame")
                priceBadge.Name = "PriceBadge"
                priceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
                priceBadge.BackgroundTransparency = 0.3
                priceBadge.Size = UDim2.new(0.85, 0, 0, px(24))
                priceBadge.AnchorPoint = Vector2.new(0.5, 0)
                priceBadge.Position = UDim2.new(0.5, 0, 0.04, 0)
                priceBadge.ZIndex = 252
                priceBadge.Parent = rightBox
                local pbCrn = Instance.new("UICorner")
                pbCrn.CornerRadius = UDim.new(0, px(8))
                pbCrn.Parent = priceBadge
                local pbStk = Instance.new("UIStroke")
                pbStk.Color = Color3.fromRGB(255, 200, 40)
                pbStk.Thickness = 1
                pbStk.Transparency = 0.55
                pbStk.Parent = priceBadge

                local pbLbl = Instance.new("TextLabel")
                pbLbl.Name = "Price"
                pbLbl.BackgroundTransparency = 1
                pbLbl.Size = UDim2.new(0.58, 0, 1, 0)
                pbLbl.Position = UDim2.new(0, 0, 0, 0)
                pbLbl.Font = Enum.Font.GothamBold
                pbLbl.Text = (price > 0) and tostring(price) or "FREE"
                pbLbl.TextColor3 = GOLD
                pbLbl.TextScaled = true
                pbLbl.TextXAlignment = Enum.TextXAlignment.Right
                pbLbl.ZIndex = 253
                pbLbl.Parent = priceBadge

                local emoteCoinIcon = Instance.new("ImageLabel")
                emoteCoinIcon.Name = "CoinIcon"
                emoteCoinIcon.Size = UDim2.new(0.26, 0, 0.80, 0)
                emoteCoinIcon.Position = UDim2.new(0.64, 0, 0.5, 0)
                emoteCoinIcon.AnchorPoint = Vector2.new(0, 0.5)
                emoteCoinIcon.BackgroundTransparency = 1
                emoteCoinIcon.ScaleType = Enum.ScaleType.Fit
                emoteCoinIcon.ZIndex = 253
                emoteCoinIcon.Visible = (price > 0)
                emoteCoinIcon.Parent = priceBadge

                local emoteCoinAsset = ""
                pcall(function()
                    if AssetCodes and type(AssetCodes.Get) == "function" then
                        local ci = AssetCodes.Get("Coin")
                        if ci and #ci > 0 then
                            emoteCoinIcon.Image = ci
                            emoteCoinAsset = ci
                        end
                    end
                end)

                -- Debug prints (temporary): validate emote price render path + coin icon + badge state
                print(string.format("[ShopUI][EmotePrice] card=%s path=EmotesCustomCard->WeaponStylePriceBadge", tostring(emoteId)))
                print(string.format("[ShopUI][EmotePrice] card=%s coinAsset=%s", tostring(emoteId), tostring(emoteCoinAsset)))
                print(string.format(
                    "[ShopUI][EmotePrice] card=%s badgeVisible=%s badgeSize=%s coinVisible=%s",
                    tostring(emoteId),
                    tostring(priceBadge.Visible),
                    tostring(priceBadge.Size),
                    tostring(emoteCoinIcon.Visible)
                ))

                -- Name
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "ItemName"
                nameLabel.BackgroundTransparency = 1
                nameLabel.Size = UDim2.new(0.95, 0, 0.22, 0)
                nameLabel.Position = UDim2.new(0.04, 0, 0.26, 0)
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.Text = displayName
                nameLabel.TextColor3 = WHITE
                nameLabel.TextScaled = true
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.ZIndex = 253
                nameLabel.Parent = rightBox

                -- Description
                local descLabel = Instance.new("TextLabel")
                descLabel.Name = "Desc"
                descLabel.BackgroundTransparency = 1
                descLabel.Size = UDim2.new(0.95, 0, 0.18, 0)
                descLabel.Position = UDim2.new(0.04, 0, 0.48, 0)
                descLabel.Font = Enum.Font.Gotham
                descLabel.Text = description
                descLabel.TextColor3 = DIM_TEXT
                descLabel.TextScaled = true
                descLabel.TextXAlignment = Enum.TextXAlignment.Left
                descLabel.ZIndex = 253
                descLabel.Parent = rightBox

                -- Buy button
                local buyBtn = Instance.new("TextButton")
                buyBtn.Name = "BuyBtn"
                buyBtn.Size = UDim2.new(0.85, 0, 0.24, 0)
                buyBtn.AnchorPoint = Vector2.new(0.5, 1)
                buyBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
                buyBtn.BackgroundColor3 = BTN_BUY
                buyBtn.Font = Enum.Font.GothamBold
                buyBtn.TextScaled = true
                buyBtn.TextColor3 = WHITE
                buyBtn.AutoButtonColor = false
                buyBtn.ZIndex = 253
                buyBtn.Parent = rightBox
                local bCrn = Instance.new("UICorner")
                bCrn.CornerRadius = UDim.new(0, px(10))
                bCrn.Parent = buyBtn
                local bStk = Instance.new("UIStroke")
                bStk.Color = BTN_STROKE_C; bStk.Thickness = 1.4; bStk.Transparency = 0.25
                bStk.Parent = buyBtn

                local function refreshEmoteCard()
                    local owned = ownedSet[emoteId] == true
                    if owned then
                        buyBtn.Text = "\u{2714} OWNED"
                        buyBtn.Active = false
                        buyBtn.BackgroundColor3 = DISABLED_BG
                        buyBtn.TextColor3 = GREEN_GLOW
                        bStk.Color = GREEN_GLOW
                        bStk.Transparency = 0.45
                        card.BackgroundColor3 = CARD_OWNED
                        stk.Color = GREEN_GLOW
                        stk.Thickness = 1.6
                        stk.Transparency = 0.35
                    else
                        buyBtn.Text = "BUY"
                        buyBtn.Active = true
                        buyBtn.BackgroundColor3 = BTN_BUY
                        buyBtn.TextColor3 = WHITE
                        bStk.Color = BTN_STROKE_C
                        bStk.Transparency = 0.25
                        card.BackgroundColor3 = CARD_BG
                        stk.Color = CARD_STROKE
                        stk.Thickness = 1.2
                        stk.Transparency = 0.35
                    end
                end
                refreshEmoteCard()
                table.insert(emoteRefreshFns, refreshEmoteCard)

                -- Hover
                buyBtn.MouseEnter:Connect(function()
                    if buyBtn.Active then
                        pcall(function() TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play() end)
                    end
                end)
                buyBtn.MouseLeave:Connect(function()
                    if buyBtn.Active then
                        pcall(function() TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BUY}):Play() end)
                    end
                end)

                -- Purchase click
                buyBtn.MouseButton1Click:Connect(function()
                    if not buyBtn.Active then return end
                    if ownedSet[emoteId] then return end

                    local remotes = ensureEmoteRemotes()
                    if not remotes or not remotes.purchase or not remotes.purchase:IsA("RemoteFunction") then
                        warn("[ShopUI] PurchaseEmote remote not found")
                        return
                    end

                    print("[ShopUI] emote purchase requested:", emoteId)
                    local ok, success, newBalance, msg = pcall(function()
                        return remotes.purchase:InvokeServer(emoteId)
                    end)
                    if ok and success then
                        ownedSet[emoteId] = true
                        if coinApi and coinApi.SetCoins then
                            pcall(function() coinApi.SetCoins(newBalance) end)
                        end
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        print("[ShopUI] emote purchase accepted:", emoteId)
                        refreshEmoteCard()
                    else
                        buyBtn.Text = "NOT ENOUGH"
                        buyBtn.TextColor3 = RED_TEXT
                        bStk.Color = RED_TEXT
                        bStk.Transparency = 0.3
                        task.delay(1.2, function()
                            buyBtn.TextColor3 = WHITE
                            bStk.Color = BTN_STROKE_C
                            bStk.Transparency = 0.25
                            refreshEmoteCard()
                        end)
                        print("[ShopUI] emote purchase rejected:", emoteId, msg)
                    end
                end)
            end -- end for each emote

            contentPages["emotes"] = emotesPage
        else
            -- No emotes defined yet: show placeholder
            makePlaceholderPage("EmotesContent",  "emotes",  "\u{263A}", "Emotes coming soon")
        end
    end

    ---------------------------------------------------------------------------
    -- COINS content page (Robux coin packs via Developer Products)
    ---------------------------------------------------------------------------
    do
        local CoinProducts = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("CoinProducts")
            if mod and mod:IsA("ModuleScript") then
                CoinProducts = require(mod)
            end
        end)

        local coinsPage = Instance.new("Frame")
        coinsPage.Name = "CoinsContent"
        coinsPage.BackgroundTransparency = 1
        coinsPage.Size = UDim2.new(1, 0, 0, 0)
        coinsPage.AutomaticSize = Enum.AutomaticSize.Y
        coinsPage.Visible = false
        coinsPage.Parent = contentContainer

        local coinsLayout = Instance.new("UIListLayout")
        coinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        coinsLayout.Padding = UDim.new(0, px(14))
        coinsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        coinsLayout.Parent = coinsPage

        -- Section header
        local coinsHeader = Instance.new("TextLabel")
        coinsHeader.Name = "CoinsHeader"
        coinsHeader.BackgroundTransparency = 1
        coinsHeader.Font = Enum.Font.GothamBlack
        coinsHeader.Text = "Coin Packs"
        coinsHeader.TextColor3 = GOLD
        coinsHeader.TextSize = math.max(16, math.floor(px(20)))
        coinsHeader.Size = UDim2.new(1, 0, 0, px(30))
        coinsHeader.TextXAlignment = Enum.TextXAlignment.Left
        coinsHeader.LayoutOrder = 0
        coinsHeader.Parent = coinsPage

        local coinsAccent = Instance.new("Frame")
        coinsAccent.Name = "AccentBar"
        coinsAccent.BackgroundColor3 = GOLD
        coinsAccent.BackgroundTransparency = 0.3
        coinsAccent.Size = UDim2.new(1, 0, 0, px(2))
        coinsAccent.BorderSizePixel = 0
        coinsAccent.LayoutOrder = 1
        coinsAccent.Parent = coinsPage

        local coinPromptDebounce = false

        if CoinProducts and CoinProducts.Packs then
            local coinAsset = nil
            if AssetCodes and type(AssetCodes.Get) == "function" then
                pcall(function() coinAsset = AssetCodes.Get("Coin") end)
            end

            for i, pack in ipairs(CoinProducts.Packs) do
                local card = Instance.new("Frame")
                card.Name = "CoinPack_" .. tostring(i)
                card.Size = UDim2.new(1, -px(4), 0, px(115))
                card.BackgroundColor3 = CARD_BG
                card.BorderSizePixel = 0
                card.LayoutOrder = 1 + i
                card.ZIndex = 250
                card.ClipsDescendants = true
                card.Parent = coinsPage

                local cardCorner = Instance.new("UICorner")
                cardCorner.CornerRadius = UDim.new(0, px(10))
                cardCorner.Parent = card

                local cardStroke = Instance.new("UIStroke")
                cardStroke.Color = CARD_STROKE
                cardStroke.Thickness = 1.2
                cardStroke.Transparency = 0.35
                cardStroke.Parent = card

                local cardPad = Instance.new("UIPadding")
                cardPad.PaddingLeft = UDim.new(0, px(20))
                cardPad.PaddingRight = UDim.new(0, px(18))
                cardPad.Parent = card

                -- Coin icon (image or fallback circle)
                local coinIconSize = px(54)
                if coinAsset and type(coinAsset) == "string" then
                    local coinIcon = Instance.new("ImageLabel")
                    coinIcon.Name = "CoinIcon"
                    coinIcon.Size = UDim2.new(0, coinIconSize, 0, coinIconSize)
                    coinIcon.AnchorPoint = Vector2.new(0, 0.5)
                    coinIcon.Position = UDim2.new(0, 0, 0.5, 0)
                    coinIcon.BackgroundTransparency = 1
                    coinIcon.Image = coinAsset
                    coinIcon.ScaleType = Enum.ScaleType.Fit
                    coinIcon.ZIndex = 252
                    coinIcon.Parent = card
                else
                    local coinCircle = Instance.new("Frame")
                    coinCircle.Name = "CoinIcon"
                    coinCircle.Size = UDim2.new(0, coinIconSize, 0, coinIconSize)
                    coinCircle.AnchorPoint = Vector2.new(0, 0.5)
                    coinCircle.Position = UDim2.new(0, 0, 0.5, 0)
                    coinCircle.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
                    coinCircle.BorderSizePixel = 0
                    coinCircle.ZIndex = 252
                    coinCircle.Parent = card
                    local cc = Instance.new("UICorner")
                    cc.CornerRadius = UDim.new(0.5, 0)
                    cc.Parent = coinCircle
                end

                -- Coin amount label
                local coinLabel = Instance.new("TextLabel")
                coinLabel.Name = "CoinAmount"
                coinLabel.Size = UDim2.new(0.50, -coinIconSize, 0.50, 0)
                coinLabel.Position = UDim2.new(0, coinIconSize + px(16), 0, px(10))
                coinLabel.BackgroundTransparency = 1
                coinLabel.Font = Enum.Font.GothamBlack
                coinLabel.Text = tostring(pack.Coins) .. " Coins"
                coinLabel.TextColor3 = GOLD
                coinLabel.TextSize = math.max(18, math.floor(px(22)))
                coinLabel.TextXAlignment = Enum.TextXAlignment.Left
                coinLabel.ZIndex = 252
                coinLabel.Parent = card

                -- Pack name subtitle
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "PackName"
                nameLabel.Size = UDim2.new(0.50, -coinIconSize, 0.35, 0)
                nameLabel.Position = UDim2.new(0, coinIconSize + px(16), 0.50, px(4))
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.Text = pack.Name
                nameLabel.TextColor3 = DIM_TEXT
                nameLabel.TextSize = math.max(13, math.floor(px(15)))
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.ZIndex = 252
                nameLabel.Parent = card

                -- Buy button (right side)
                local buyBtn = Instance.new("TextButton")
                buyBtn.Name = "BuyBtn"
                buyBtn.Size = UDim2.new(0, px(140), 0, px(48))
                buyBtn.AnchorPoint = Vector2.new(1, 0.5)
                buyBtn.Position = UDim2.new(1, 0, 0.5, 0)
                buyBtn.BackgroundColor3 = GREEN_BTN
                buyBtn.BorderSizePixel = 0
                buyBtn.Font = Enum.Font.GothamBold
                buyBtn.Text = "R$ " .. tostring(pack.Price or "??")
                buyBtn.TextColor3 = WHITE
                buyBtn.TextSize = math.max(15, math.floor(px(18)))
                buyBtn.AutoButtonColor = false
                buyBtn.ZIndex = 253
                buyBtn.Parent = card

                local buyCorner = Instance.new("UICorner")
                buyCorner.CornerRadius = UDim.new(0, px(8))
                buyCorner.Parent = buyBtn

                local buyStroke = Instance.new("UIStroke")
                buyStroke.Color = Color3.fromRGB(25, 140, 50)
                buyStroke.Thickness = 1.2
                buyStroke.Parent = buyBtn

                -- Hover feedback
                buyBtn.MouseEnter:Connect(function()
                    TweenService:Create(buyBtn, TWEEN_QUICK, {
                        BackgroundColor3 = Color3.fromRGB(50, 220, 90),
                    }):Play()
                end)
                buyBtn.MouseLeave:Connect(function()
                    TweenService:Create(buyBtn, TWEEN_QUICK, {
                        BackgroundColor3 = GREEN_BTN,
                    }):Play()
                end)

                -- Purchase click handler
                buyBtn.MouseButton1Click:Connect(function()
                    if coinPromptDebounce then return end

                    local productId = pack.ProductId
                    if not productId or productId == 0 then
                        warn("[ShopUI][Coins] Product ID not set for '" .. pack.Name .. "'. Set it in CoinProducts.lua")
                        return
                    end

                    coinPromptDebounce = true
                    print("[ShopUI][Coins] Prompting purchase:", pack.Name, "ProductId:", productId)

                    local ok, err = pcall(function()
                        MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
                    end)
                    if not ok then
                        warn("[ShopUI][Coins] PromptProductPurchase failed:", tostring(err))
                    end

                    task.delay(2, function()
                        coinPromptDebounce = false
                    end)
                end)
            end
        end

        contentPages["coins"] = coinsPage
    end

    ---------------------------------------------------------------------------
    -- Set initial state: Weapons tab active by default
    ---------------------------------------------------------------------------
    setActiveTab("weapons")

    -- Expose so external code (e.g. EmoteUI shop button) can switch tabs
    ShopUI.setActiveTab = setActiveTab
    ShopUI.getActiveTab = function() return currentTab end

    ---------------------------------------------------------------------------
    -- Dynamic root height: keep root tall enough for content (sidebar fills it)
    ---------------------------------------------------------------------------
    local function updateRootHeight()
        local h = contentContainer.AbsoluteSize.Y
        local minH = px(400)
        root.Size = UDim2.new(1, 0, 0, math.max(h, minH))
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

return ShopUI
