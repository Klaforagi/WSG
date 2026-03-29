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

-- Rarity colour palettes (shared with Inventory)
local RARITY_COLORS = {
    Common    = Color3.fromRGB(150, 150, 155),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(180, 60, 255),
    Legendary = Color3.fromRGB(255, 180, 30),
}
local RARITY_BG_COLORS = {
    Common    = Color3.fromRGB(42, 44, 55),
    Rare      = Color3.fromRGB(22, 38, 68),
    Epic      = Color3.fromRGB(46, 22, 65),
    Legendary = Color3.fromRGB(58, 46, 18),
}

-- Preview modules (shared with Inventory)
local SkinPreview = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("SkinPreview")
    if mod and mod:IsA("ModuleScript") then SkinPreview = require(mod) end
end)

local EffectsPreviewModule = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("EffectsPreview")
    if mod and mod:IsA("ModuleScript") then EffectsPreviewModule = require(mod) end
end)

-- Ownership sort helper: pushes owned items to the bottom of their grid/list
-- cardEntries = { { card = GuiObject, originalOrder = int, id = string }, ... }
-- isOwnedFn(id) → bool
local function reorderByOwnership(cardEntries, isOwnedFn)
    for _, entry in ipairs(cardEntries) do
        if entry.card and entry.card.Parent then
            local owned = isOwnedFn(entry.id)
            entry.card.LayoutOrder = owned and (1000 + entry.originalOrder) or entry.originalOrder
        end
    end
end

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
    { id = "salvage", icon = "\u{2699}", label = "Salvage", order = 6 },
    { id = "currency", icon = "\u{1FA99}", label = "Currency", order = 7 },
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
    currency = { active = Color3.fromRGB(255, 215, 80), inactive = Color3.fromRGB(160, 140, 60) },
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
    elseif tabId == "currency" then
        -- Currency circle icon
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
    root.Size                = UDim2.new(1, 0, 0, px(680))
    root.ZIndex              = 240
    root.LayoutOrder         = 1
    root.ClipsDescendants    = false
    root.Parent              = parent

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop    = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(6))
    rootPad.Parent        = root

    print("[ShopLayout] ShopRoot height:", px(680), "px | ContentArea fills parent")

    ---------------------------------------------------------------------------
    -- Left sidebar (vertical tab rail, mirrors DailyQuestsUI TabSidebar)
    ---------------------------------------------------------------------------
    local sidebar = Instance.new("Frame")
    sidebar.Name             = "TabSidebar"
    sidebar.BackgroundColor3 = SIDEBAR_BG
    sidebar.BorderSizePixel  = 0
    sidebar.Size             = UDim2.new(0, TAB_W, 0, 0)
    sidebar.AutomaticSize    = Enum.AutomaticSize.Y
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
        if def.id == "weapons" or def.id == "boosts" or def.id == "salvage" then
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
    local _stopShopEffectsPreview = nil  -- set by effects tab, called on tab switch
    local _stopShopEmotePreview   = nil  -- set by emotes tab, called on tab switch

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
        -- Stop effects preview animation when leaving effects tab
        if tabId ~= "effects" and _stopShopEffectsPreview then
            _stopShopEffectsPreview()
        end
        -- Stop emote preview animation when leaving emotes tab
        if tabId ~= "emotes" and _stopShopEmotePreview then
            _stopShopEmotePreview()
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
    contentContainer.Size                = UDim2.new(1, -(TAB_W + TAB_GAP), 1, 0)
    contentContainer.Position            = UDim2.new(0, TAB_W + TAB_GAP, 0, 0)
    contentContainer.ClipsDescendants    = false
    contentContainer.Parent              = root

    ---------------------------------------------------------------------------
    -- WEAPONS content page → 2×2 CRATE GRID
    ---------------------------------------------------------------------------
    local weaponsPage = Instance.new("Frame")
    weaponsPage.Name                = "WeaponsContent"
    weaponsPage.BackgroundTransparency = 1
    weaponsPage.Size                = UDim2.new(1, 0, 0, px(570))
    weaponsPage.Visible             = true
    weaponsPage.Parent              = contentContainer

    -- No UIListLayout – header + grid are absolutely positioned for
    -- reliable 2×2 sizing inside the ScrollingFrame canvas.

    local wpPad = Instance.new("UIPadding")
    wpPad.PaddingTop    = UDim.new(0, px(6))
    wpPad.PaddingBottom = UDim.new(0, px(6))
    wpPad.PaddingLeft   = UDim.new(0, px(8))
    wpPad.PaddingRight  = UDim.new(0, px(8))
    wpPad.Parent        = weaponsPage

    -- Header (absolutely positioned at top of content area)
    local CRATE_HEADER_H = px(54)
    local crateHeader = Instance.new("Frame")
    crateHeader.Name = "CrateHeader"
    crateHeader.BackgroundTransparency = 1
    crateHeader.Size = UDim2.new(1, 0, 0, CRATE_HEADER_H)
    crateHeader.Position = UDim2.new(0, 0, 0, 0)
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

    ---------------------------------------------------------------------------
    -- 2×2 Grid container for crate cards
    --
    -- The grid is absolutely positioned below the header and fills the
    -- remaining height of weaponsPage.  CellSize is computed dynamically
    -- from the grid's actual rendered pixel dimensions so that two columns
    -- always fit regardless of ScrollingFrame canvas-size quirks.
    --
    -- >>> To tweak spacing, edit GRID_GAP below.
    -- >>> Cell size is auto-computed – see recomputeGridCells().
    ---------------------------------------------------------------------------
    local GRID_GAP     = px(12)   -- gap between cards (horizontal & vertical)
    local GRID_TOP_OFF = CRATE_HEADER_H + px(10)  -- header + gap

    local crateGrid = Instance.new("Frame")
    crateGrid.Name = "CrateGrid"
    crateGrid.BackgroundTransparency = 1
    crateGrid.Size     = UDim2.new(1, 0, 1, -GRID_TOP_OFF)
    crateGrid.Position = UDim2.new(0, 0, 0, GRID_TOP_OFF)
    crateGrid.ClipsDescendants = false
    crateGrid.Parent = weaponsPage

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellPadding            = UDim2.new(0, GRID_GAP, 0, GRID_GAP)
    gridLayout.CellSize               = UDim2.fromOffset(px(200), px(220)) -- fallback
    gridLayout.FillDirection           = Enum.FillDirection.Horizontal
    gridLayout.FillDirectionMaxCells   = 2
    gridLayout.HorizontalAlignment    = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment       = Enum.VerticalAlignment.Center
    gridLayout.SortOrder               = Enum.SortOrder.LayoutOrder
    gridLayout.Parent                  = crateGrid

    -- Dynamically compute CellSize from the grid's actual rendered size
    -- so two columns always fit regardless of parent chain sizing.
    local function recomputeGridCells()
        local w = crateGrid.AbsoluteSize.X
        local h = crateGrid.AbsoluteSize.Y
        if w > 20 and h > 20 then
            local cellW = math.floor((w - GRID_GAP) / 2)
            local cellH = math.floor((h - GRID_GAP) / 2)
            gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
        end
    end
    crateGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(recomputeGridCells)
    task.defer(recomputeGridCells)

    -- Build crate cards from CrateConfig (fills 2×2 grid)
    local crateOrder = (CrateConfig and CrateConfig.CrateOrder) or {}
    local crateOpenDebounce = false

    for idx, crateId in ipairs(crateOrder) do
        local crateDef = CrateConfig and CrateConfig.Crates[crateId]
        if not crateDef then continue end

        local crateCurrency = crateDef.currency or "Coins"
        local cratePrice = crateDef.cost or crateDef.price or 0
        local isKeyCrate = (crateCurrency == "Keys")

        -- Premium accent colours
        local PREM_STROKE = Color3.fromRGB(170, 100, 255)
        local PREM_BG     = Color3.fromRGB(24, 16, 44)
        local NORM_BG     = CARD_BG

        -------------------------------------------------------------------
        -- Card frame
        -------------------------------------------------------------------
        local card = Instance.new("Frame")
        card.Name = "Crate_" .. crateId
        card.BackgroundColor3 = isKeyCrate and PREM_BG or NORM_BG
        card.LayoutOrder = idx
        card.Parent = crateGrid

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, px(14))
        cCorner.Parent = card

        local cStroke = Instance.new("UIStroke")
        cStroke.Color = isKeyCrate and PREM_STROKE or CARD_STROKE
        cStroke.Thickness = isKeyCrate and 2 or 1.4
        cStroke.Transparency = isKeyCrate and 0.10 or 0.25
        cStroke.Parent = card

        -- Inner vertical layout
        local innerLayout = Instance.new("UIListLayout")
        innerLayout.SortOrder      = Enum.SortOrder.LayoutOrder
        innerLayout.FillDirection   = Enum.FillDirection.Vertical
        innerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        innerLayout.Padding        = UDim.new(0, px(3))
        innerLayout.Parent         = card

        local innerPad = Instance.new("UIPadding")
        innerPad.PaddingTop    = UDim.new(0, px(8))
        innerPad.PaddingBottom = UDim.new(0, px(8))
        innerPad.PaddingLeft   = UDim.new(0, px(8))
        innerPad.PaddingRight  = UDim.new(0, px(8))
        innerPad.Parent        = card

        -------------------------------------------------------------------
        -- 1. Icon plate (centered near top)
        -------------------------------------------------------------------
        local iconPlate = Instance.new("Frame")
        iconPlate.Name = "IconPlate"
        iconPlate.BackgroundColor3 = isKeyCrate and Color3.fromRGB(28, 20, 54) or ICON_BG
        iconPlate.Size = UDim2.new(0, px(52), 0, px(52))
        iconPlate.LayoutOrder = 1
        iconPlate.Parent = card

        local ipCorner = Instance.new("UICorner")
        ipCorner.CornerRadius = UDim.new(0, px(12))
        ipCorner.Parent = iconPlate

        local ipStroke = Instance.new("UIStroke")
        ipStroke.Color = isKeyCrate and PREM_STROKE or CARD_STROKE
        ipStroke.Thickness = 1
        ipStroke.Transparency = isKeyCrate and 0.2 or 0.4
        ipStroke.Parent = iconPlate

        local iconLabel = Instance.new("TextLabel")
        iconLabel.BackgroundTransparency = 1
        iconLabel.Font = Enum.Font.GothamBold
        iconLabel.Text = crateDef.iconGlyph or "?"
        iconLabel.TextSize = math.max(22, math.floor(px(26)))
        iconLabel.TextColor3 = isKeyCrate and PREM_STROKE or GOLD
        iconLabel.Size = UDim2.new(1, 0, 1, 0)
        iconLabel.TextXAlignment = Enum.TextXAlignment.Center
        iconLabel.TextYAlignment = Enum.TextYAlignment.Center
        iconLabel.Parent = iconPlate

        -- Hover-detection button over icon plate for tooltip
        local iconHoverBtn = Instance.new("TextButton")
        iconHoverBtn.Name = "IconHoverBtn"
        iconHoverBtn.Text = ""
        iconHoverBtn.BackgroundTransparency = 1
        iconHoverBtn.Size = UDim2.new(1, 0, 1, 0)
        iconHoverBtn.ZIndex = iconLabel.ZIndex + 1
        iconHoverBtn.Parent = iconPlate

        -- Tooltip frame (hidden by default, shown on icon hover)
        local tooltip = Instance.new("Frame")
        tooltip.Name = "RarityTooltip"
        tooltip.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
        tooltip.BackgroundTransparency = 0.05
        tooltip.Size = UDim2.new(0, px(130), 0, 0)
        tooltip.AutomaticSize = Enum.AutomaticSize.Y
        tooltip.AnchorPoint = Vector2.new(0.5, 1)
        tooltip.Position = UDim2.new(0.5, 0, 0, -px(4))
        tooltip.Visible = false
        tooltip.ZIndex = 310
        tooltip.ClipsDescendants = false
        tooltip.Parent = iconPlate

        local ttCorner = Instance.new("UICorner")
        ttCorner.CornerRadius = UDim.new(0, px(8))
        ttCorner.Parent = tooltip

        local ttStroke = Instance.new("UIStroke")
        ttStroke.Color = isKeyCrate and PREM_STROKE or GOLD
        ttStroke.Thickness = 1
        ttStroke.Transparency = 0.3
        ttStroke.Parent = tooltip

        local ttPad = Instance.new("UIPadding")
        ttPad.PaddingTop = UDim.new(0, px(6))
        ttPad.PaddingBottom = UDim.new(0, px(6))
        ttPad.PaddingLeft = UDim.new(0, px(8))
        ttPad.PaddingRight = UDim.new(0, px(8))
        ttPad.Parent = tooltip

        local ttLayout = Instance.new("UIListLayout")
        ttLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ttLayout.Padding = UDim.new(0, px(2))
        ttLayout.Parent = tooltip

        -- Populate tooltip from crate rarity data
        if CrateConfig and CrateConfig.Rarities and CrateConfig.RarityOrder then
            local hasCrateRarities = (type(crateDef.rarities) == "table")
            local totalW = 0
            if hasCrateRarities then
                for _, w in pairs(crateDef.rarities) do totalW = totalW + w end
            end
            local ttOrder = 0
            local hasCommon = hasCrateRarities and crateDef.rarities["Common"]
            for _, rarName in ipairs(CrateConfig.RarityOrder) do
                local w = hasCrateRarities and crateDef.rarities[rarName]
                if w and w > 0 then
                    local pct = (totalW > 0) and (w / totalW * 100) or 0
                    local rd = CrateConfig.Rarities[rarName]
                    local row = Instance.new("TextLabel")
                    row.BackgroundTransparency = 1
                    row.Font = Enum.Font.GothamBold
                    row.TextSize = math.max(9, math.floor(px(10)))
                    row.Text = string.format("%s %.0f%%", rd.label, pct)
                    row.TextColor3 = rd.color
                    row.Size = UDim2.new(1, 0, 0, px(13))
                    row.TextXAlignment = Enum.TextXAlignment.Left
                    row.LayoutOrder = ttOrder
                    row.ZIndex = 311
                    row.Parent = tooltip
                    ttOrder = ttOrder + 1
                end
            end
            if not hasCommon and isKeyCrate then
                local noCommon = Instance.new("TextLabel")
                noCommon.BackgroundTransparency = 1
                noCommon.Font = Enum.Font.GothamBold
                noCommon.TextSize = math.max(9, math.floor(px(10)))
                noCommon.Text = "No Commons"
                noCommon.TextColor3 = Color3.fromRGB(180, 180, 180)
                noCommon.Size = UDim2.new(1, 0, 0, px(13))
                noCommon.TextXAlignment = Enum.TextXAlignment.Left
                noCommon.LayoutOrder = ttOrder
                noCommon.ZIndex = 311
                noCommon.Parent = tooltip
            end
        end

        iconHoverBtn.MouseEnter:Connect(function()
            tooltip.Visible = true
        end)
        iconHoverBtn.MouseLeave:Connect(function()
            tooltip.Visible = false
        end)

        -------------------------------------------------------------------
        -- 2. Crate name
        -------------------------------------------------------------------
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "CrateName"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = crateDef.displayName
        nameLabel.TextColor3 = isKeyCrate and PREM_STROKE or WHITE
        nameLabel.TextSize = math.max(13, math.floor(px(15)))
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Size = UDim2.new(1, 0, 0, px(18))
        nameLabel.LayoutOrder = 2
        nameLabel.Parent = card

        -------------------------------------------------------------------
        -- 3. Short description
        -------------------------------------------------------------------
        local descLabel = Instance.new("TextLabel")
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.GothamMedium
        descLabel.Text = crateDef.description or ""
        descLabel.TextColor3 = DIM_TEXT
        descLabel.TextSize = math.max(9, math.floor(px(10)))
        descLabel.TextXAlignment = Enum.TextXAlignment.Center
        descLabel.TextWrapped = true
        descLabel.Size = UDim2.new(1, 0, 0, px(14))
        descLabel.LayoutOrder = 3
        descLabel.Parent = card

        -------------------------------------------------------------------
        -- 4. (Rarity odds removed from card – shown via icon tooltip)
        -------------------------------------------------------------------

        -------------------------------------------------------------------
        -- 5. Price badge
        -------------------------------------------------------------------
        local priceBadge = Instance.new("Frame")
        priceBadge.Name = "PriceBadge"
        priceBadge.BackgroundColor3 = isKeyCrate and Color3.fromRGB(28, 18, 36) or Color3.fromRGB(36, 33, 18)
        priceBadge.BackgroundTransparency = 0.3
        priceBadge.Size = UDim2.new(0.80, 0, 0, px(26))
        priceBadge.LayoutOrder = 6
        priceBadge.Parent = card

        local pbCorner = Instance.new("UICorner")
        pbCorner.CornerRadius = UDim.new(0, px(8))
        pbCorner.Parent = priceBadge

        local pbStroke = Instance.new("UIStroke")
        pbStroke.Color = isKeyCrate and PREM_STROKE or Color3.fromRGB(255, 200, 40)
        pbStroke.Thickness = 1
        pbStroke.Transparency = 0.55
        pbStroke.Parent = priceBadge

        -- Centered amount + icon group inside the badge
        local costGroup = Instance.new("Frame")
        costGroup.Name = "CostGroup"
        costGroup.BackgroundTransparency = 1
        costGroup.Size = UDim2.new(0, 0, 1, 0)
        costGroup.AutomaticSize = Enum.AutomaticSize.X
        costGroup.AnchorPoint = Vector2.new(0.5, 0)
        costGroup.Position = UDim2.new(0.5, 0, 0, 0)
        costGroup.Parent = priceBadge

        local costLayout = Instance.new("UIListLayout")
        costLayout.FillDirection = Enum.FillDirection.Horizontal
        costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        costLayout.SortOrder = Enum.SortOrder.LayoutOrder
        costLayout.Padding = UDim.new(0, px(4))
        costLayout.Parent = costGroup

        local priceLabel = Instance.new("TextLabel")
        priceLabel.BackgroundTransparency = 1
        priceLabel.Font = Enum.Font.GothamBold
        priceLabel.TextSize = math.max(12, math.floor(px(14)))
        priceLabel.TextColor3 = isKeyCrate and PREM_STROKE or GOLD
        priceLabel.Text = tostring(cratePrice)
        priceLabel.Size = UDim2.new(0, 0, 1, 0)
        priceLabel.AutomaticSize = Enum.AutomaticSize.X
        priceLabel.LayoutOrder = 1
        priceLabel.Parent = costGroup

        if isKeyCrate then
            local keyGlyph = Instance.new("TextLabel")
            keyGlyph.BackgroundTransparency = 1
            keyGlyph.Font = Enum.Font.GothamBold
            keyGlyph.Text = "\u{1F511}"
            keyGlyph.TextSize = math.max(12, math.floor(px(14)))
            keyGlyph.TextColor3 = PREM_STROKE
            keyGlyph.Size = UDim2.new(0, px(18), 0, px(18))
            keyGlyph.LayoutOrder = 2
            keyGlyph.Parent = costGroup
        else
            local coinIcon = Instance.new("ImageLabel")
            coinIcon.BackgroundTransparency = 1
            coinIcon.Size = UDim2.new(0, px(18), 0, px(18))
            coinIcon.ScaleType = Enum.ScaleType.Fit
            coinIcon.LayoutOrder = 2
            coinIcon.Parent = costGroup
            pcall(function()
                if AssetCodes and type(AssetCodes.Get) == "function" then
                    local ci = AssetCodes.Get("Coin")
                    if ci and #ci > 0 then coinIcon.Image = ci end
                end
            end)
        end

        -------------------------------------------------------------------
        -- 6. Open Crate button
        -------------------------------------------------------------------
        local openBtn = Instance.new("TextButton")
        openBtn.Name = "OpenBtn"
        openBtn.Size = UDim2.new(0.80, 0, 0, px(32))
        openBtn.BackgroundColor3 = GREEN_BTN
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextScaled = true
        openBtn.TextColor3 = WHITE
        openBtn.Text = "OPEN CRATE"
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 253
        openBtn.LayoutOrder = 7
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

        -- Click: fire crate open (with client-side balance pre-check)
        openBtn.MouseButton1Click:Connect(function()
            if crateOpenDebounce then return end
            crateOpenDebounce = true

            -- Client-side balance check: flash button red if insufficient
            local hasEnough = true
            if isKeyCrate then
                local keys = 0
                if coinApi and coinApi.GetKeys then
                    pcall(function() keys = coinApi.GetKeys() or 0 end)
                end
                hasEnough = (keys >= cratePrice)
            else
                local coins = 0
                if coinApi and coinApi.GetCoins then
                    pcall(function() coins = coinApi.GetCoins() or 0 end)
                end
                hasEnough = (coins >= cratePrice)
            end

            if not hasEnough then
                local msg = isKeyCrate and "NOT ENOUGH KEYS" or "NOT ENOUGH COINS"
                openBtn.Text = msg
                openBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
                obStroke.Color = Color3.fromRGB(200, 40, 40)
                task.delay(1, function()
                    if openBtn and openBtn.Parent then
                        openBtn.Text = "OPEN CRATE"
                        openBtn.BackgroundColor3 = GREEN_BTN
                        obStroke.Color = Color3.fromRGB(30, 200, 80)
                    end
                    crateOpenDebounce = false
                end)
                return
            end

            if _G.OpenCrateRequested then
                _G.OpenCrateRequested(crateId)
            else
                local openCrateRF = ReplicatedStorage:FindFirstChild("OpenCrate")
                if openCrateRF and openCrateRF:IsA("RemoteFunction") then
                    local ok, success, result = pcall(function()
                        return openCrateRF:InvokeServer(crateId)
                    end)
                    if ok and success and type(result) == "table" then
                        if coinApi and coinApi.SetCoins then
                            pcall(function() coinApi.SetCoins(result.newBalance) end)
                        end
                        if coinApi and coinApi.SetKeys and result.newKeyBalance then
                            pcall(function() coinApi.SetKeys(result.newKeyBalance) end)
                        end
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        if _G.UpdateShopHeaderKeys then
                            pcall(function() _G.UpdateShopHeaderKeys() end)
                        end
                        showToast(weaponsPage,
                            string.format("Got %s (%s)!", result.weaponName, result.rarity),
                            CrateConfig and CrateConfig.Rarities[result.rarity] and CrateConfig.Rarities[result.rarity].color or GOLD,
                            3)
                    elseif ok and not success then
                        -- Server rejected: flash button red
                        local msg = isKeyCrate and "NOT ENOUGH KEYS" or "NOT ENOUGH COINS"
                        openBtn.Text = msg
                        openBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
                        obStroke.Color = Color3.fromRGB(200, 40, 40)
                        task.delay(1, function()
                            if openBtn and openBtn.Parent then
                                openBtn.Text = "OPEN CRATE"
                                openBtn.BackgroundColor3 = GREEN_BTN
                                obStroke.Color = Color3.fromRGB(30, 200, 80)
                            end
                        end)
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

    ---------------------------------------------------------------------------
    -- SKINS content page (card grid + right detail panel, mirrors Inventory)
    ---------------------------------------------------------------------------
    do
        local SkinDefs = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("SkinDefinitions")
            if mod and mod:IsA("ModuleScript") then SkinDefs = require(mod) end
        end)

        local skinRemotes = nil
        local function ensureSkinRemotes()
            if skinRemotes then return skinRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local sf = rf:FindFirstChild("Skins") or rf:WaitForChild("Skins", 5)
            if not sf then return nil end
            skinRemotes = {
                purchase   = sf:FindFirstChild("PurchaseSkin"),
                getOwned   = sf:FindFirstChild("GetOwnedSkins"),
                equip      = sf:FindFirstChild("EquipSkin"),
                getEquipped = sf:FindFirstChild("GetEquippedSkin"),
                changed    = sf:FindFirstChild("EquippedSkinChanged"),
            }
            return skinRemotes
        end

        local shopSkins = SkinDefs and SkinDefs.GetShopSkins() or {}

        if #shopSkins > 0 then
            local SHOP_SKIN_DETAIL_W = px(380)
            local SHOP_SKIN_GRID_GAP = px(14)

            local skinsPage = Instance.new("Frame")
            skinsPage.Name                = "SkinsContent"
            skinsPage.BackgroundTransparency = 1
            skinsPage.Size                = UDim2.new(1, 0, 0, px(660))
            skinsPage.Visible             = false
            skinsPage.Parent              = contentContainer

            -- ── State ───────────────────────────────────────────────────
            local ownedSkinSet    = {}
            local equippedSkinId  = nil
            local selectedSkinId  = nil
            local skinCards       = {} -- [skinId] = { card, cardStroke, ... }

            -- ── Grid (left side) ────────────────────────────────────────
            local skinGridScroll = Instance.new("ScrollingFrame")
            skinGridScroll.Name = "SkinGridScroll"
            skinGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
            skinGridScroll.BackgroundTransparency = 0.5
            skinGridScroll.Size = UDim2.new(1, -(SHOP_SKIN_DETAIL_W + SHOP_SKIN_GRID_GAP), 1, 0)
            skinGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            skinGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            skinGridScroll.ScrollBarThickness = px(4)
            skinGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
            skinGridScroll.BorderSizePixel = 0
            skinGridScroll.Parent = skinsPage
            Instance.new("UICorner", skinGridScroll).CornerRadius = UDim.new(0, px(10))

            local skinGridLayout = Instance.new("UIGridLayout", skinGridScroll)
            skinGridLayout.CellSize = UDim2.new(0, px(180), 0, px(215))
            skinGridLayout.CellPadding = UDim2.new(0, px(14), 0, px(14))
            skinGridLayout.FillDirection = Enum.FillDirection.Horizontal
            skinGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            skinGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

            local skinGridPad = Instance.new("UIPadding", skinGridScroll)
            skinGridPad.PaddingTop    = UDim.new(0, px(12))
            skinGridPad.PaddingLeft   = UDim.new(0, px(12))
            skinGridPad.PaddingRight  = UDim.new(0, px(12))
            skinGridPad.PaddingBottom = UDim.new(0, px(12))

            -- ── Details panel (right side) ──────────────────────────────
            local skinDetailsPanel = Instance.new("Frame")
            skinDetailsPanel.Name = "SkinDetailsPanel"
            skinDetailsPanel.BackgroundColor3 = CARD_BG
            skinDetailsPanel.Size = UDim2.new(0, SHOP_SKIN_DETAIL_W, 1, 0)
            skinDetailsPanel.AnchorPoint = Vector2.new(1, 0)
            skinDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
            skinDetailsPanel.Parent = skinsPage
            Instance.new("UICorner", skinDetailsPanel).CornerRadius = UDim.new(0, px(12))
            local sdpStroke = Instance.new("UIStroke", skinDetailsPanel)
            sdpStroke.Color = CARD_STROKE; sdpStroke.Thickness = 1.4; sdpStroke.Transparency = 0.2

            -- Placeholder
            local skinDetailPlaceholder = Instance.new("TextLabel", skinDetailsPanel)
            skinDetailPlaceholder.Name = "Placeholder"
            skinDetailPlaceholder.BackgroundTransparency = 1
            skinDetailPlaceholder.Font = Enum.Font.GothamMedium
            skinDetailPlaceholder.Text = "Select a skin"
            skinDetailPlaceholder.TextColor3 = DIM_TEXT
            skinDetailPlaceholder.TextSize = px(22)
            skinDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
            skinDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
            skinDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

            -- Detail content
            local skinDetailContent = Instance.new("Frame", skinDetailsPanel)
            skinDetailContent.Name = "DetailContent"
            skinDetailContent.BackgroundTransparency = 1
            skinDetailContent.Size = UDim2.new(1, 0, 1, 0)
            skinDetailContent.Visible = false

            local sdPad = Instance.new("UIPadding", skinDetailContent)
            sdPad.PaddingTop  = UDim.new(0, px(16)); sdPad.PaddingBottom = UDim.new(0, px(16))
            sdPad.PaddingLeft = UDim.new(0, px(16)); sdPad.PaddingRight  = UDim.new(0, px(16))

            -- 3D preview area
            local skinPreviewVP = Instance.new("ViewportFrame", skinDetailContent)
            skinPreviewVP.Name = "PreviewViewport"
            skinPreviewVP.BackgroundColor3 = RARITY_BG_COLORS.Common
            skinPreviewVP.Size = UDim2.new(1, 0, 0, px(250))
            skinPreviewVP.Ambient = Color3.fromRGB(100, 100, 120)
            Instance.new("UICorner", skinPreviewVP).CornerRadius = UDim.new(0, px(10))
            local skinIconStroke = Instance.new("UIStroke", skinPreviewVP)
            skinIconStroke.Color = RARITY_COLORS.Common; skinIconStroke.Thickness = 1.5; skinIconStroke.Transparency = 0.3

            -- Skin name
            local skinDetailName = Instance.new("TextLabel", skinDetailContent)
            skinDetailName.Name = "SkinName"
            skinDetailName.BackgroundTransparency = 1
            skinDetailName.Font = Enum.Font.GothamBold
            skinDetailName.TextColor3 = WHITE
            skinDetailName.TextSize = px(26)
            skinDetailName.TextXAlignment = Enum.TextXAlignment.Center
            skinDetailName.Size = UDim2.new(1, 0, 0, px(36))
            skinDetailName.Position = UDim2.new(0, 0, 0, px(260))
            skinDetailName.TextTruncate = Enum.TextTruncate.AtEnd

            -- Rarity label
            local skinDetailRarity = Instance.new("TextLabel", skinDetailContent)
            skinDetailRarity.Name = "Rarity"
            skinDetailRarity.BackgroundTransparency = 1
            skinDetailRarity.Font = Enum.Font.GothamBold
            skinDetailRarity.TextColor3 = RARITY_COLORS.Common
            skinDetailRarity.TextSize = px(19)
            skinDetailRarity.TextXAlignment = Enum.TextXAlignment.Center
            skinDetailRarity.Size = UDim2.new(1, 0, 0, px(28))
            skinDetailRarity.Position = UDim2.new(0, 0, 0, px(298))

            -- Description
            local skinDetailDesc = Instance.new("TextLabel", skinDetailContent)
            skinDetailDesc.Name = "Description"
            skinDetailDesc.BackgroundTransparency = 1
            skinDetailDesc.Font = Enum.Font.GothamBold
            skinDetailDesc.TextColor3 = DIM_TEXT
            skinDetailDesc.TextSize = px(17)
            skinDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
            skinDetailDesc.TextWrapped = true
            skinDetailDesc.Size = UDim2.new(1, 0, 0, px(48))
            skinDetailDesc.Position = UDim2.new(0, 0, 0, px(330))
            local skinDescStroke = Instance.new("UIStroke", skinDetailDesc)
            skinDescStroke.Color = Color3.fromRGB(0, 0, 0)
            skinDescStroke.Thickness = 1.5
            skinDescStroke.Transparency = 0.15

            -- Price row (between desc and button)
            local skinPriceRow = Instance.new("Frame", skinDetailContent)
            skinPriceRow.Name = "PriceRow"
            skinPriceRow.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
            skinPriceRow.BackgroundTransparency = 0.3
            skinPriceRow.Size = UDim2.new(0.6, 0, 0, px(34))
            skinPriceRow.AnchorPoint = Vector2.new(0.5, 0)
            skinPriceRow.Position = UDim2.new(0.5, 0, 0, px(390))
            Instance.new("UICorner", skinPriceRow).CornerRadius = UDim.new(0, px(8))
            local spStk = Instance.new("UIStroke", skinPriceRow)
            spStk.Color = Color3.fromRGB(255, 200, 40); spStk.Thickness = 1; spStk.Transparency = 0.55

            local skinPriceLbl = Instance.new("TextLabel", skinPriceRow)
            skinPriceLbl.Name = "PriceText"
            skinPriceLbl.BackgroundTransparency = 1
            skinPriceLbl.Font = Enum.Font.GothamBold
            skinPriceLbl.TextColor3 = GOLD
            skinPriceLbl.TextScaled = true
            skinPriceLbl.Size = UDim2.new(0.58, 0, 1, 0)
            skinPriceLbl.TextXAlignment = Enum.TextXAlignment.Right

            local skinPriceCoin = Instance.new("ImageLabel", skinPriceRow)
            skinPriceCoin.Name = "CoinIcon"
            skinPriceCoin.Size = UDim2.new(0.26, 0, 0.80, 0)
            skinPriceCoin.Position = UDim2.new(0.64, 0, 0.5, 0)
            skinPriceCoin.AnchorPoint = Vector2.new(0, 0.5)
            skinPriceCoin.BackgroundTransparency = 1
            skinPriceCoin.ScaleType = Enum.ScaleType.Fit
            pcall(function()
                if AssetCodes and type(AssetCodes.Get) == "function" then
                    local ci = AssetCodes.Get("Coin")
                    if ci and #ci > 0 then skinPriceCoin.Image = ci end
                end
            end)

            -- ShowHelm toggle row
            local TOGGLE_ON_C  = Color3.fromRGB(35, 190, 75)
            local TOGGLE_OFF_C = Color3.fromRGB(45, 48, 65)

            local helmRow = Instance.new("Frame", skinDetailContent)
            helmRow.Name = "HelmToggleRow"
            helmRow.BackgroundTransparency = 1
            helmRow.Size = UDim2.new(1, 0, 0, px(34))
            helmRow.Position = UDim2.new(0, 0, 0, px(434))

            local helmLabel = Instance.new("TextLabel", helmRow)
            helmLabel.BackgroundTransparency = 1
            helmLabel.Font = Enum.Font.GothamBold
            helmLabel.Text = "Show Helm"
            helmLabel.TextColor3 = DIM_TEXT
            helmLabel.TextSize = px(17)
            helmLabel.TextXAlignment = Enum.TextXAlignment.Left
            helmLabel.Size = UDim2.new(0.6, 0, 1, 0)
            local helmLabelStroke = Instance.new("UIStroke", helmLabel)
            helmLabelStroke.Color = Color3.fromRGB(0, 0, 0)
            helmLabelStroke.Thickness = 1.5
            helmLabelStroke.Transparency = 0.15

            local helmToggleBg = Instance.new("TextButton", helmRow)
            helmToggleBg.Name = "ToggleBg"
            helmToggleBg.Text = ""
            helmToggleBg.AutoButtonColor = false
            helmToggleBg.Size = UDim2.new(0, px(44), 0, px(24))
            helmToggleBg.AnchorPoint = Vector2.new(1, 0.5)
            helmToggleBg.Position = UDim2.new(1, 0, 0.5, 0)
            helmToggleBg.BorderSizePixel = 0
            Instance.new("UICorner", helmToggleBg).CornerRadius = UDim.new(1, 0)

            local helmKnob = Instance.new("Frame", helmToggleBg)
            helmKnob.Name = "Knob"
            helmKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            helmKnob.Size = UDim2.new(0, px(18), 0, px(18))
            helmKnob.AnchorPoint = Vector2.new(0, 0.5)
            helmKnob.BorderSizePixel = 0
            Instance.new("UICorner", helmKnob).CornerRadius = UDim.new(1, 0)

            local function syncHelmToggle()
                local on = _G.PlayerSettings and _G.PlayerSettings.ShowHelm
                if on == nil then on = true end
                helmToggleBg.BackgroundColor3 = on and TOGGLE_ON_C or TOGGLE_OFF_C
                helmKnob.Position = on and UDim2.new(1, -px(21), 0.5, 0) or UDim2.new(0, px(3), 0.5, 0)
            end
            syncHelmToggle()

            helmToggleBg.MouseButton1Click:Connect(function()
                if not _G.PlayerSettings then return end
                local newVal = not (_G.PlayerSettings.ShowHelm ~= false)
                _G.PlayerSettings.ShowHelm = newVal
                syncHelmToggle()
                local updateEV = ReplicatedStorage:FindFirstChild("UpdatePlayerSetting")
                if updateEV and updateEV:IsA("RemoteEvent") then
                    updateEV:FireServer("ShowHelm", newVal)
                end
                if _G.ApplySettings then
                    pcall(_G.ApplySettings, _G.PlayerSettings)
                end
                if SkinPreview and selectedSkinId then
                    SkinPreview.Update(skinPreviewVP, selectedSkinId, newVal)
                end
            end)

            -- Action button (BUY / OWNED / EQUIP / EQUIPPED)
            local skinActionBtn = Instance.new("TextButton", skinDetailContent)
            skinActionBtn.Name = "ActionBtn"
            skinActionBtn.AutoButtonColor = false
            skinActionBtn.BackgroundColor3 = BTN_BUY
            skinActionBtn.Font = Enum.Font.GothamBold
            skinActionBtn.Text = "BUY"
            skinActionBtn.TextColor3 = WHITE
            skinActionBtn.TextSize = px(24)
            skinActionBtn.Size = UDim2.new(0.92, 0, 0, px(56))
            skinActionBtn.AnchorPoint = Vector2.new(0.5, 1)
            skinActionBtn.Position = UDim2.new(0.5, 0, 1, 0)
            Instance.new("UICorner", skinActionBtn).CornerRadius = UDim.new(0, px(10))
            local skinActionStroke = Instance.new("UIStroke", skinActionBtn)
            skinActionStroke.Color = BTN_STROKE_C; skinActionStroke.Thickness = 1.4; skinActionStroke.Transparency = 0.25

            -- ── Helper: update action button state ──────────────────────
            local function updateSkinActionButton()
                if not selectedSkinId then return end
                local def = SkinDefs and SkinDefs.GetById(selectedSkinId)
                if not def then return end
                local owned = ownedSkinSet[selectedSkinId] == true
                local isEquipped = (equippedSkinId == selectedSkinId)
                local price = def.Price or 0

                if owned and isEquipped then
                    skinActionBtn.Text = "\u{2714} EQUIPPED"
                    skinActionBtn.BackgroundColor3 = DISABLED_BG
                    skinActionBtn.TextColor3 = GREEN_GLOW
                    skinActionStroke.Color = GREEN_GLOW; skinActionStroke.Transparency = 0.45
                    skinPriceRow.Visible = false
                elseif owned then
                    skinActionBtn.Text = "EQUIP"
                    skinActionBtn.BackgroundColor3 = BTN_BUY
                    skinActionBtn.TextColor3 = WHITE
                    skinActionStroke.Color = BTN_STROKE_C; skinActionStroke.Transparency = 0.25
                    skinPriceRow.Visible = false
                else
                    skinActionBtn.Text = "BUY"
                    skinActionBtn.BackgroundColor3 = BTN_BUY
                    skinActionBtn.TextColor3 = WHITE
                    skinActionStroke.Color = BTN_STROKE_C; skinActionStroke.Transparency = 0.25
                    skinPriceLbl.Text = tostring(price)
                    skinPriceRow.Visible = (price > 0)
                    skinPriceCoin.Visible = (price > 0)
                end
            end

            -- ── Helper: refresh card highlights ─────────────────────────
            local function refreshSkinCards()
                for sid, info in pairs(skinCards) do
                    local isSelected = (selectedSkinId == sid)
                    local owned = ownedSkinSet[sid] == true
                    local isEquippedCard = (equippedSkinId == sid)

                    if isSelected then
                        info.cardStroke.Color = GOLD
                        info.cardStroke.Thickness = 2.0
                        info.cardStroke.Transparency = 0
                    elseif owned and isEquippedCard then
                        info.cardStroke.Color = GREEN_GLOW
                        info.cardStroke.Thickness = 1.8
                        info.cardStroke.Transparency = 0.3
                        info.card.BackgroundColor3 = CARD_OWNED
                    elseif owned then
                        info.cardStroke.Color = GREEN_GLOW
                        info.cardStroke.Thickness = 1.6
                        info.cardStroke.Transparency = 0.35
                        info.card.BackgroundColor3 = CARD_OWNED
                    else
                        info.cardStroke.Color = info.baseStrokeColor
                        info.cardStroke.Thickness = info.baseStrokeThickness
                        info.cardStroke.Transparency = info.baseStrokeTransparency
                        info.card.BackgroundColor3 = CARD_BG
                    end

                    -- Equipped bar at bottom of card
                    local eqBar = info.card:FindFirstChild("EquippedBar")
                    if eqBar then eqBar.Visible = isEquippedCard end

                    -- Owned badge on card
                    local ownedBadge = info.card:FindFirstChild("OwnedBadge")
                    if ownedBadge then ownedBadge.Visible = owned end
                end
            end

            -- ── Helper: select a skin ───────────────────────────────────
            local function setSelectedSkin(skinId)
                selectedSkinId = skinId
                if not skinId then
                    skinDetailPlaceholder.Visible = true
                    skinDetailContent.Visible = false
                    refreshSkinCards()
                    return
                end
                skinDetailPlaceholder.Visible = false
                skinDetailContent.Visible = true

                local def = SkinDefs and SkinDefs.GetById(skinId)
                if not def then return end

                local rarity = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local rarityBg = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common

                skinDetailName.Text = def.DisplayName or skinId
                skinDetailName.TextColor3 = (rarity == "Epic") and Color3.fromRGB(210, 170, 255) or WHITE
                skinDetailRarity.Text = rarity
                skinDetailRarity.TextColor3 = rarityColor
                skinDetailDesc.Text = def.Description or ""
                skinPreviewVP.BackgroundColor3 = rarityBg
                skinIconStroke.Color = rarityColor

                -- Update 3D preview
                local previewShowHelm = _G.PlayerSettings and _G.PlayerSettings.ShowHelm
                if previewShowHelm == nil then previewShowHelm = true end
                if SkinPreview then
                    SkinPreview.Update(skinPreviewVP, skinId, previewShowHelm)
                end

                updateSkinActionButton()
                syncHelmToggle()
                refreshSkinCards()
                print("[ShopSkins] Selected item:", skinId)
            end

            -- ── Action button click ─────────────────────────────────────
            skinActionBtn.MouseButton1Click:Connect(function()
                if not selectedSkinId then return end
                local def = SkinDefs and SkinDefs.GetById(selectedSkinId)
                if not def then return end
                local owned = ownedSkinSet[selectedSkinId] == true
                local isEquipped = (equippedSkinId == selectedSkinId)

                if owned and isEquipped then
                    -- Already equipped, do nothing
                    return
                elseif owned then
                    -- Equip it
                    local sRemotes = ensureSkinRemotes()
                    if sRemotes and sRemotes.equip and sRemotes.equip:IsA("RemoteEvent") then
                        pcall(function() sRemotes.equip:FireServer(selectedSkinId) end)
                    end
                    equippedSkinId = selectedSkinId
                    updateSkinActionButton()
                    refreshSkinCards()
                else
                    -- Purchase
                    local remotes = ensureSkinRemotes()
                    if not remotes or not remotes.purchase then
                        warn("[ShopUI] Skins purchase remote not found")
                        return
                    end

                    skinActionBtn.Text = "..."
                    local ok, success, newBalance, msg = pcall(function()
                        return remotes.purchase:InvokeServer(selectedSkinId)
                    end)

                    if ok and success then
                        ownedSkinSet[selectedSkinId] = true
                        if coinApi and coinApi.SetCoins then
                            pcall(function() coinApi.SetCoins(newBalance) end)
                        end
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        updateSkinActionButton()
                        refreshSkinCards()
                        print("[ShopPurchase] Skin purchased:", selectedSkinId)
                    else
                        skinActionBtn.Text = "NOT ENOUGH"
                        skinActionBtn.TextColor3 = RED_TEXT
                        task.delay(1.2, function()
                            updateSkinActionButton()
                        end)
                    end
                end
            end)

            -- Action button hover
            if not game:GetService("UserInputService").TouchEnabled then
                skinActionBtn.MouseEnter:Connect(function()
                    local owned = selectedSkinId and ownedSkinSet[selectedSkinId]
                    local isEquipped = (equippedSkinId == selectedSkinId)
                    if not (owned and isEquipped) then
                        TweenService:Create(skinActionBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                    end
                end)
                skinActionBtn.MouseLeave:Connect(function()
                    updateSkinActionButton()
                end)
            end

            -- ── Create skin cards ───────────────────────────────────────
            for i_sk, def in ipairs(shopSkins) do
                local skinId      = def.Id
                local displayName = def.DisplayName or skinId
                local isEpic      = (def.Rarity == "Epic")
                local skinColor   = def.ArmorColor or Color3.fromRGB(150, 150, 155)
                local rarity      = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local price       = def.Price or 0

                local card = Instance.new("TextButton")
                card.Name = "SkinCard_" .. skinId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.Text = ""
                card.AutoButtonColor = false
                card.BorderSizePixel = 0
                card.LayoutOrder = i_sk
                card.Parent = skinGridScroll
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(10))

                local baseStrokeColor = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                local baseStrokeThickness = isEpic and 1.6 or 1.2
                local baseStrokeTransparency = isEpic and 0.2 or 0.35
                local sCS = Instance.new("UIStroke", card)
                sCS.Color = baseStrokeColor
                sCS.Thickness = baseStrokeThickness
                sCS.Transparency = baseStrokeTransparency

                -- Icon area (top)
                local iconArea = Instance.new("Frame", card)
                iconArea.Name = "IconArea"
                iconArea.BackgroundColor3 = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common
                iconArea.Size = UDim2.new(1, -px(10), 0, px(125))
                iconArea.Position = UDim2.new(0, px(5), 0, px(5))
                iconArea.BorderSizePixel = 0
                Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, px(8))

                local cardIcon = Instance.new("TextLabel", iconArea)
                cardIcon.Name = "Icon"
                cardIcon.BackgroundTransparency = 1
                cardIcon.Font = Enum.Font.GothamBold
                cardIcon.Text = "\u{1F6E1}"
                cardIcon.TextScaled = true
                cardIcon.TextColor3 = skinColor
                cardIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
                cardIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                cardIcon.Position = UDim2.new(0.5, 0, 0.5, 0)

                -- Name label (bottom)
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = displayName
                cardName.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                cardName.TextSize = math.max(13, math.floor(px(14)))
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, px(24))
                cardName.Position = UDim2.new(0, px(5), 0, px(136))

                -- Rarity label
                local cardRarity = Instance.new("TextLabel", card)
                cardRarity.Name = "RarityLabel"
                cardRarity.BackgroundTransparency = 1
                cardRarity.Font = Enum.Font.GothamBold
                cardRarity.Text = rarity
                cardRarity.TextColor3 = rarityColor
                cardRarity.TextSize = math.max(11, math.floor(px(12)))
                cardRarity.TextXAlignment = Enum.TextXAlignment.Center
                cardRarity.Size = UDim2.new(1, -px(10), 0, px(20))
                cardRarity.Position = UDim2.new(0, px(5), 0, px(163))

                -- Price badge on card
                local cardPriceBadge = Instance.new("Frame", card)
                cardPriceBadge.Name = "CardPriceBadge"
                cardPriceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
                cardPriceBadge.BackgroundTransparency = 0.3
                cardPriceBadge.Size = UDim2.new(0.65, 0, 0, px(22))
                cardPriceBadge.AnchorPoint = Vector2.new(0.5, 0)
                cardPriceBadge.Position = UDim2.new(0.5, 0, 0, px(186))
                Instance.new("UICorner", cardPriceBadge).CornerRadius = UDim.new(0, px(6))
                local cpLbl = Instance.new("TextLabel", cardPriceBadge)
                cpLbl.BackgroundTransparency = 1
                cpLbl.Font = Enum.Font.GothamBold
                cpLbl.Text = tostring(price)
                cpLbl.TextColor3 = GOLD
                cpLbl.TextScaled = true
                cpLbl.Size = UDim2.new(1, 0, 1, 0)
                cpLbl.TextXAlignment = Enum.TextXAlignment.Center

                -- Owned badge (top-right corner)
                local ownedBadge = Instance.new("TextLabel", card)
                ownedBadge.Name = "OwnedBadge"
                ownedBadge.BackgroundTransparency = 1
                ownedBadge.Font = Enum.Font.GothamBold
                ownedBadge.Text = "\u{2714}"
                ownedBadge.TextColor3 = GREEN_GLOW
                ownedBadge.TextSize = math.max(14, math.floor(px(16)))
                ownedBadge.Size = UDim2.new(0, px(20), 0, px(20))
                ownedBadge.AnchorPoint = Vector2.new(1, 0)
                ownedBadge.Position = UDim2.new(1, -px(6), 0, px(6))
                ownedBadge.ZIndex = 5
                ownedBadge.Visible = false

                -- Equipped bar at bottom
                local eqBar = Instance.new("Frame", card)
                eqBar.Name = "EquippedBar"
                eqBar.BackgroundColor3 = GREEN_GLOW
                eqBar.Size = UDim2.new(0.7, 0, 0, px(3))
                eqBar.AnchorPoint = Vector2.new(0.5, 1)
                eqBar.Position = UDim2.new(0.5, 0, 1, -px(4))
                eqBar.BorderSizePixel = 0
                eqBar.Visible = false
                Instance.new("UICorner", eqBar).CornerRadius = UDim.new(0, px(2))

                skinCards[skinId] = {
                    card = card,
                    cardStroke = sCS,
                    baseStrokeColor = baseStrokeColor,
                    baseStrokeThickness = baseStrokeThickness,
                    baseStrokeTransparency = baseStrokeTransparency,
                }

                -- Click to select
                card.MouseButton1Click:Connect(function()
                    setSelectedSkin(skinId)
                end)

                -- Hover effect
                if not game:GetService("UserInputService").TouchEnabled then
                    card.MouseEnter:Connect(function()
                        if selectedSkinId ~= skinId then
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(38, 40, 58)}):Play()
                        end
                    end)
                    card.MouseLeave:Connect(function()
                        if selectedSkinId ~= skinId then
                            local isOwn = ownedSkinSet[skinId] == true
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = isOwn and CARD_OWNED or CARD_BG}):Play()
                        end
                    end)
                end
            end

            -- ── Fetch data from server ──────────────────────────────────
            task.spawn(function()
                local sRemotes = ensureSkinRemotes()
                if not sRemotes then return end
                -- Owned skins
                if sRemotes.getOwned and sRemotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return sRemotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then
                        for _, id in ipairs(list) do ownedSkinSet[id] = true end
                    end
                end
                -- Equipped skin
                if sRemotes.getEquipped and sRemotes.getEquipped:IsA("RemoteFunction") then
                    local ok, equipped = pcall(function() return sRemotes.getEquipped:InvokeServer() end)
                    if ok and type(equipped) == "string" then equippedSkinId = equipped end
                end
                refreshSkinCards()
                -- Listen for equip changes
                if sRemotes.changed and sRemotes.changed:IsA("RemoteEvent") then
                    sRemotes.changed.OnClientEvent:Connect(function(newEquipped)
                        if type(newEquipped) == "string" then
                            equippedSkinId = newEquipped
                            updateSkinActionButton()
                            refreshSkinCards()
                        end
                    end)
                end
            end)

            contentPages["skins"] = skinsPage
            print("[ShopLayout] Skins content bounds:", px(660), "px | Detail panel:", px(380), "px | Card grid available width:", skinGridScroll.Size)
        else
            makePlaceholderPage("SkinsContent", "skins", "\u{2726}", "Skins coming soon")
        end
    end

    ---------------------------------------------------------------------------
    -- EFFECTS content page (card grid + right detail panel, mirrors Inventory)
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
                purchase    = ef:FindFirstChild("PurchaseEffect"),
                getOwned    = ef:FindFirstChild("GetOwnedEffects"),
                equip       = ef:FindFirstChild("EquipEffect"),
                getEquipped = ef:FindFirstChild("GetEquippedEffects"),
                changed     = ef:FindFirstChild("EquippedEffectsChanged"),
            }
            return effectRemotes
        end

        -- Only show purchasable effects (exclude free defaults), sorted by price
        local allEffects = {}
        if EffectDefs then
            for _, def in ipairs(EffectDefs.GetAll()) do
                if not def.IsFree and def.ShopVisible ~= false then
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
            local SHOP_EFX_DETAIL_W = px(380)
            local SHOP_EFX_GRID_GAP = px(14)

            local effectsPage = Instance.new("Frame")
            effectsPage.Name                = "EffectsContent"
            effectsPage.BackgroundTransparency = 1
            effectsPage.Size                = UDim2.new(1, 0, 0, px(660))
            effectsPage.Visible             = false
            effectsPage.Parent              = contentContainer

            -- ── State ───────────────────────────────────────────────────
            local ownedEffectSet    = {}
            local equippedEffectId  = nil
            local selectedEffectId  = nil
            local effectCards       = {} -- [effectId] = { card, cardStroke, ... }

            -- ── Grid (left side) ────────────────────────────────────────
            local efxGridScroll = Instance.new("ScrollingFrame")
            efxGridScroll.Name = "EffectGridScroll"
            efxGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
            efxGridScroll.BackgroundTransparency = 0.5
            efxGridScroll.Size = UDim2.new(1, -(SHOP_EFX_DETAIL_W + SHOP_EFX_GRID_GAP), 1, 0)
            efxGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            efxGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            efxGridScroll.ScrollBarThickness = px(4)
            efxGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
            efxGridScroll.BorderSizePixel = 0
            efxGridScroll.Parent = effectsPage
            Instance.new("UICorner", efxGridScroll).CornerRadius = UDim.new(0, px(10))

            local efxGridLayout = Instance.new("UIGridLayout", efxGridScroll)
            efxGridLayout.CellSize = UDim2.new(0, px(180), 0, px(170))
            efxGridLayout.CellPadding = UDim2.new(0, px(14), 0, px(14))
            efxGridLayout.FillDirection = Enum.FillDirection.Horizontal
            efxGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            efxGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

            local efxGridPad = Instance.new("UIPadding", efxGridScroll)
            efxGridPad.PaddingTop    = UDim.new(0, px(12))
            efxGridPad.PaddingLeft   = UDim.new(0, px(12))
            efxGridPad.PaddingRight  = UDim.new(0, px(12))
            efxGridPad.PaddingBottom = UDim.new(0, px(12))

            -- ── Details panel (right side) ──────────────────────────────
            local efxDetailsPanel = Instance.new("Frame")
            efxDetailsPanel.Name = "EffectDetailsPanel"
            efxDetailsPanel.BackgroundColor3 = CARD_BG
            efxDetailsPanel.Size = UDim2.new(0, SHOP_EFX_DETAIL_W, 1, 0)
            efxDetailsPanel.AnchorPoint = Vector2.new(1, 0)
            efxDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
            efxDetailsPanel.Parent = effectsPage
            Instance.new("UICorner", efxDetailsPanel).CornerRadius = UDim.new(0, px(12))
            local edpStroke = Instance.new("UIStroke", efxDetailsPanel)
            edpStroke.Color = CARD_STROKE; edpStroke.Thickness = 1.4; edpStroke.Transparency = 0.2

            -- Placeholder
            local efxDetailPlaceholder = Instance.new("TextLabel", efxDetailsPanel)
            efxDetailPlaceholder.Name = "Placeholder"
            efxDetailPlaceholder.BackgroundTransparency = 1
            efxDetailPlaceholder.Font = Enum.Font.GothamMedium
            efxDetailPlaceholder.Text = "Select an effect"
            efxDetailPlaceholder.TextColor3 = DIM_TEXT
            efxDetailPlaceholder.TextSize = px(22)
            efxDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
            efxDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
            efxDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

            -- Detail content
            local efxDetailContent = Instance.new("Frame", efxDetailsPanel)
            efxDetailContent.Name = "DetailContent"
            efxDetailContent.BackgroundTransparency = 1
            efxDetailContent.Size = UDim2.new(1, 0, 1, 0)
            efxDetailContent.Visible = false

            local edPad = Instance.new("UIPadding", efxDetailContent)
            edPad.PaddingTop  = UDim.new(0, px(16)); edPad.PaddingBottom = UDim.new(0, px(16))
            edPad.PaddingLeft = UDim.new(0, px(16)); edPad.PaddingRight  = UDim.new(0, px(16))

            -- 3D trail preview area
            local efxPreviewVP = Instance.new("ViewportFrame", efxDetailContent)
            efxPreviewVP.Name = "PreviewViewport"
            efxPreviewVP.BackgroundColor3 = RARITY_BG_COLORS.Common
            efxPreviewVP.Size = UDim2.new(1, 0, 0, px(260))
            efxPreviewVP.Ambient = Color3.fromRGB(100, 100, 120)
            Instance.new("UICorner", efxPreviewVP).CornerRadius = UDim.new(0, px(10))
            local efxIconStroke = Instance.new("UIStroke", efxPreviewVP)
            efxIconStroke.Color = RARITY_COLORS.Common; efxIconStroke.Thickness = 1.5; efxIconStroke.Transparency = 0.3

            -- Effect name
            local efxDetailName = Instance.new("TextLabel", efxDetailContent)
            efxDetailName.Name = "EffectName"
            efxDetailName.BackgroundTransparency = 1
            efxDetailName.Font = Enum.Font.GothamBold
            efxDetailName.TextColor3 = WHITE
            efxDetailName.TextSize = px(26)
            efxDetailName.TextXAlignment = Enum.TextXAlignment.Center
            efxDetailName.Size = UDim2.new(1, 0, 0, px(36))
            efxDetailName.Position = UDim2.new(0, 0, 0, px(272))
            efxDetailName.TextTruncate = Enum.TextTruncate.AtEnd

            -- Rarity label
            local efxDetailRarity = Instance.new("TextLabel", efxDetailContent)
            efxDetailRarity.Name = "Rarity"
            efxDetailRarity.BackgroundTransparency = 1
            efxDetailRarity.Font = Enum.Font.GothamBold
            efxDetailRarity.TextColor3 = RARITY_COLORS.Common
            efxDetailRarity.TextSize = px(19)
            efxDetailRarity.TextXAlignment = Enum.TextXAlignment.Center
            efxDetailRarity.Size = UDim2.new(1, 0, 0, px(28))
            efxDetailRarity.Position = UDim2.new(0, 0, 0, px(310))

            -- Description
            local efxDetailDesc = Instance.new("TextLabel", efxDetailContent)
            efxDetailDesc.Name = "Description"
            efxDetailDesc.BackgroundTransparency = 1
            efxDetailDesc.Font = Enum.Font.GothamBold
            efxDetailDesc.TextColor3 = DIM_TEXT
            efxDetailDesc.TextSize = px(17)
            efxDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
            efxDetailDesc.TextWrapped = true
            efxDetailDesc.Size = UDim2.new(1, 0, 0, px(48))
            efxDetailDesc.Position = UDim2.new(0, 0, 0, px(342))
            local efxDescStroke = Instance.new("UIStroke", efxDetailDesc)
            efxDescStroke.Color = Color3.fromRGB(0, 0, 0)
            efxDescStroke.Thickness = 1.5
            efxDescStroke.Transparency = 0.15

            -- Price row
            local efxPriceRow = Instance.new("Frame", efxDetailContent)
            efxPriceRow.Name = "PriceRow"
            efxPriceRow.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
            efxPriceRow.BackgroundTransparency = 0.3
            efxPriceRow.Size = UDim2.new(0.6, 0, 0, px(34))
            efxPriceRow.AnchorPoint = Vector2.new(0.5, 0)
            efxPriceRow.Position = UDim2.new(0.5, 0, 0, px(400))
            Instance.new("UICorner", efxPriceRow).CornerRadius = UDim.new(0, px(8))
            local epStk = Instance.new("UIStroke", efxPriceRow)
            epStk.Color = Color3.fromRGB(255, 200, 40); epStk.Thickness = 1; epStk.Transparency = 0.55

            local efxPriceLbl = Instance.new("TextLabel", efxPriceRow)
            efxPriceLbl.Name = "PriceText"
            efxPriceLbl.BackgroundTransparency = 1
            efxPriceLbl.Font = Enum.Font.GothamBold
            efxPriceLbl.TextColor3 = GOLD
            efxPriceLbl.TextScaled = true
            efxPriceLbl.Size = UDim2.new(0.58, 0, 1, 0)
            efxPriceLbl.TextXAlignment = Enum.TextXAlignment.Right

            local efxPriceCoin = Instance.new("ImageLabel", efxPriceRow)
            efxPriceCoin.Name = "CoinIcon"
            efxPriceCoin.Size = UDim2.new(0.26, 0, 0.80, 0)
            efxPriceCoin.Position = UDim2.new(0.64, 0, 0.5, 0)
            efxPriceCoin.AnchorPoint = Vector2.new(0, 0.5)
            efxPriceCoin.BackgroundTransparency = 1
            efxPriceCoin.ScaleType = Enum.ScaleType.Fit
            pcall(function()
                if AssetCodes and type(AssetCodes.Get) == "function" then
                    local ci = AssetCodes.Get("Coin")
                    if ci and #ci > 0 then efxPriceCoin.Image = ci end
                end
            end)

            -- Action button (BUY / OWNED / EQUIP / EQUIPPED)
            local efxActionBtn = Instance.new("TextButton", efxDetailContent)
            efxActionBtn.Name = "ActionBtn"
            efxActionBtn.AutoButtonColor = false
            efxActionBtn.BackgroundColor3 = BTN_BUY
            efxActionBtn.Font = Enum.Font.GothamBold
            efxActionBtn.Text = "BUY"
            efxActionBtn.TextColor3 = WHITE
            efxActionBtn.TextSize = px(24)
            efxActionBtn.Size = UDim2.new(0.92, 0, 0, px(56))
            efxActionBtn.AnchorPoint = Vector2.new(0.5, 1)
            efxActionBtn.Position = UDim2.new(0.5, 0, 1, 0)
            Instance.new("UICorner", efxActionBtn).CornerRadius = UDim.new(0, px(10))
            local efxActionStroke = Instance.new("UIStroke", efxActionBtn)
            efxActionStroke.Color = BTN_STROKE_C; efxActionStroke.Thickness = 1.4; efxActionStroke.Transparency = 0.25

            -- ── Helper: update action button state ──────────────────────
            local function updateEffectActionButton()
                if not selectedEffectId then return end
                local def = nil
                if EffectDefs then
                    for _, d in ipairs(EffectDefs.GetAll()) do
                        if d.Id == selectedEffectId then def = d; break end
                    end
                end
                if not def then return end
                local owned = ownedEffectSet[selectedEffectId] == true
                local isEquipped = (equippedEffectId == selectedEffectId)
                local price = def.CoinCost or 0

                if owned and isEquipped then
                    efxActionBtn.Text = "\u{2714} EQUIPPED"
                    efxActionBtn.BackgroundColor3 = DISABLED_BG
                    efxActionBtn.TextColor3 = GREEN_GLOW
                    efxActionStroke.Color = GREEN_GLOW; efxActionStroke.Transparency = 0.45
                    efxPriceRow.Visible = false
                elseif owned then
                    efxActionBtn.Text = "EQUIP"
                    efxActionBtn.BackgroundColor3 = BTN_BUY
                    efxActionBtn.TextColor3 = WHITE
                    efxActionStroke.Color = BTN_STROKE_C; efxActionStroke.Transparency = 0.25
                    efxPriceRow.Visible = false
                else
                    efxActionBtn.Text = "BUY"
                    efxActionBtn.BackgroundColor3 = BTN_BUY
                    efxActionBtn.TextColor3 = WHITE
                    efxActionStroke.Color = BTN_STROKE_C; efxActionStroke.Transparency = 0.25
                    efxPriceLbl.Text = tostring(price)
                    efxPriceRow.Visible = (price > 0)
                    efxPriceCoin.Visible = (price > 0)
                end
            end

            -- ── Helper: refresh card highlights ─────────────────────────
            local function refreshEffectCards()
                for eid, info in pairs(effectCards) do
                    local isSelected = (selectedEffectId == eid)
                    local owned = ownedEffectSet[eid] == true
                    local isEquippedCard = (equippedEffectId == eid)

                    if isSelected then
                        info.cardStroke.Color = GOLD
                        info.cardStroke.Thickness = 2.0
                        info.cardStroke.Transparency = 0
                    elseif owned and isEquippedCard then
                        info.cardStroke.Color = GREEN_GLOW
                        info.cardStroke.Thickness = 1.8
                        info.cardStroke.Transparency = 0.3
                        info.card.BackgroundColor3 = CARD_OWNED
                    elseif owned then
                        info.cardStroke.Color = GREEN_GLOW
                        info.cardStroke.Thickness = 1.6
                        info.cardStroke.Transparency = 0.35
                        info.card.BackgroundColor3 = CARD_OWNED
                    else
                        info.cardStroke.Color = info.baseStrokeColor
                        info.cardStroke.Thickness = info.baseStrokeThickness
                        info.cardStroke.Transparency = info.baseStrokeTransparency
                        info.card.BackgroundColor3 = CARD_BG
                    end

                    local eqBar = info.card:FindFirstChild("EquippedBar")
                    if eqBar then eqBar.Visible = isEquippedCard end

                    local ownedBadge = info.card:FindFirstChild("OwnedBadge")
                    if ownedBadge then ownedBadge.Visible = owned end
                end
            end

            -- ── Helper: select an effect ────────────────────────────────
            local function setSelectedEffect(effectId)
                selectedEffectId = effectId
                if not effectId then
                    efxDetailPlaceholder.Visible = true
                    efxDetailContent.Visible = false
                    -- Stop preview
                    if EffectsPreviewModule then pcall(EffectsPreviewModule.Stop) end
                    refreshEffectCards()
                    return
                end
                efxDetailPlaceholder.Visible = false
                efxDetailContent.Visible = true

                local def = nil
                if EffectDefs then
                    for _, d in ipairs(EffectDefs.GetAll()) do
                        if d.Id == effectId then def = d; break end
                    end
                end
                if not def then return end

                local rarity = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local rarityBg = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common

                efxDetailName.Text = def.DisplayName or effectId
                local isEpic = (rarity == "Epic")
                efxDetailName.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                efxDetailRarity.Text = rarity
                efxDetailRarity.TextColor3 = rarityColor
                efxDetailDesc.Text = def.Description or ""
                efxPreviewVP.BackgroundColor3 = rarityBg
                efxIconStroke.Color = rarityColor

                -- Update 3D trail preview
                if EffectsPreviewModule then
                    EffectsPreviewModule.Update(efxPreviewVP, effectId)
                end

                -- Register the stop function so setActiveTab can clean up
                _stopShopEffectsPreview = function()
                    if EffectsPreviewModule then pcall(EffectsPreviewModule.Stop) end
                end

                updateEffectActionButton()
                refreshEffectCards()
                print("[ShopEffects] Selected item:", effectId)
            end

            -- ── Action button click ─────────────────────────────────────
            efxActionBtn.MouseButton1Click:Connect(function()
                if not selectedEffectId then return end
                local def = nil
                if EffectDefs then
                    for _, d in ipairs(EffectDefs.GetAll()) do
                        if d.Id == selectedEffectId then def = d; break end
                    end
                end
                if not def then return end
                local owned = ownedEffectSet[selectedEffectId] == true
                local isEquipped = (equippedEffectId == selectedEffectId)

                if owned and isEquipped then
                    return
                elseif owned then
                    -- Equip it
                    local eRemotes = ensureEffectRemotes()
                    if eRemotes and eRemotes.equip and eRemotes.equip:IsA("RemoteEvent") then
                        pcall(function() eRemotes.equip:FireServer(selectedEffectId) end)
                    end
                    equippedEffectId = selectedEffectId
                    updateEffectActionButton()
                    refreshEffectCards()
                else
                    -- Purchase
                    local remotes = ensureEffectRemotes()
                    if not remotes or not remotes.purchase then
                        warn("[ShopUI] Effects purchase remote not found")
                        return
                    end

                    efxActionBtn.Text = "..."
                    local ok, success, newBalance, msg = pcall(function()
                        return remotes.purchase:InvokeServer(selectedEffectId)
                    end)

                    if ok and success then
                        ownedEffectSet[selectedEffectId] = true
                        if coinApi and coinApi.SetCoins then
                            pcall(function() coinApi.SetCoins(newBalance) end)
                        end
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        updateEffectActionButton()
                        refreshEffectCards()
                        print("[ShopPurchase] Effect purchased:", selectedEffectId)
                    else
                        efxActionBtn.Text = "NOT ENOUGH"
                        efxActionBtn.TextColor3 = RED_TEXT
                        task.delay(1.2, function()
                            updateEffectActionButton()
                        end)
                    end
                end
            end)

            -- Action button hover
            if not game:GetService("UserInputService").TouchEnabled then
                efxActionBtn.MouseEnter:Connect(function()
                    local owned = selectedEffectId and ownedEffectSet[selectedEffectId]
                    local isEquipped = (equippedEffectId == selectedEffectId)
                    if not (owned and isEquipped) then
                        TweenService:Create(efxActionBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                    end
                end)
                efxActionBtn.MouseLeave:Connect(function()
                    updateEffectActionButton()
                end)
            end

            -- ── Create effect cards ─────────────────────────────────────
            for i_effect, def in ipairs(allEffects) do
                local effectId    = def.Id
                local displayName = def.DisplayName or effectId
                local isRainbow   = def.IsRainbow == true
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)
                local isEpic      = (def.Rarity == "Epic")
                local rarity      = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local price       = def.CoinCost or 0

                local card = Instance.new("TextButton")
                card.Name = "EffectCard_" .. effectId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.Text = ""
                card.AutoButtonColor = false
                card.BorderSizePixel = 0
                card.LayoutOrder = i_effect
                card.Parent = efxGridScroll
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(10))

                local baseStrokeColor = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                local baseStrokeThickness = isEpic and 1.6 or 1.2
                local baseStrokeTransparency = isEpic and 0.2 or 0.35
                local eCS = Instance.new("UIStroke", card)
                eCS.Color = baseStrokeColor
                eCS.Thickness = baseStrokeThickness
                eCS.Transparency = baseStrokeTransparency

                -- Color swatch icon area (top)
                local swatchArea = Instance.new("Frame", card)
                swatchArea.Name = "SwatchArea"
                swatchArea.BackgroundColor3 = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common
                swatchArea.Size = UDim2.new(1, -px(10), 0, px(80))
                swatchArea.Position = UDim2.new(0, px(5), 0, px(5))
                swatchArea.BorderSizePixel = 0
                Instance.new("UICorner", swatchArea).CornerRadius = UDim.new(0, px(8))

                -- Trail swatch
                local swatch = Instance.new("Frame", swatchArea)
                swatch.Name = "ColorSwatch"
                swatch.Size = UDim2.new(0.6, 0, 0, px(10))
                swatch.AnchorPoint = Vector2.new(0.5, 0.5)
                swatch.Position = UDim2.new(0.5, 0, 0.35, 0)
                swatch.BackgroundColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                swatch.BorderSizePixel = 0
                Instance.new("UICorner", swatch).CornerRadius = UDim.new(0.5, 0)
                if isRainbow and def.TrailColorSequence then
                    local grad = Instance.new("UIGradient", swatch)
                    grad.Color = def.TrailColorSequence
                end
                local swStk = Instance.new("UIStroke", swatch)
                swStk.Color = isRainbow and Color3.fromRGB(200, 160, 255) or effectColor
                swStk.Thickness = px(2); swStk.Transparency = 0.3

                -- Trail glyph
                local trailGlyph = Instance.new("TextLabel", swatchArea)
                trailGlyph.Name = "TrailGlyph"
                trailGlyph.Text = "\u{2550}\u{2550}\u{2550}"
                trailGlyph.Font = Enum.Font.GothamBold
                trailGlyph.TextColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                trailGlyph.TextScaled = true
                trailGlyph.BackgroundTransparency = 1
                trailGlyph.Size = UDim2.new(0.8, 0, 0.3, 0)
                trailGlyph.AnchorPoint = Vector2.new(0.5, 0)
                trailGlyph.Position = UDim2.new(0.5, 0, 0.6, 0)
                if isRainbow and def.TrailColorSequence then
                    local gg = Instance.new("UIGradient", trailGlyph)
                    gg.Color = def.TrailColorSequence
                end

                -- Name label
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = displayName
                cardName.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                cardName.TextSize = math.max(13, math.floor(px(14)))
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, px(24))
                cardName.Position = UDim2.new(0, px(5), 0, px(90))

                -- Rarity label
                local cardRarity = Instance.new("TextLabel", card)
                cardRarity.Name = "RarityLabel"
                cardRarity.BackgroundTransparency = 1
                cardRarity.Font = Enum.Font.GothamBold
                cardRarity.Text = rarity
                cardRarity.TextColor3 = rarityColor
                cardRarity.TextSize = math.max(11, math.floor(px(12)))
                cardRarity.TextXAlignment = Enum.TextXAlignment.Center
                cardRarity.Size = UDim2.new(1, -px(10), 0, px(18))
                cardRarity.Position = UDim2.new(0, px(5), 0, px(116))

                -- Price badge on card
                local cardPriceBadge = Instance.new("Frame", card)
                cardPriceBadge.Name = "CardPriceBadge"
                cardPriceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
                cardPriceBadge.BackgroundTransparency = 0.3
                cardPriceBadge.Size = UDim2.new(0.65, 0, 0, px(20))
                cardPriceBadge.AnchorPoint = Vector2.new(0.5, 0)
                cardPriceBadge.Position = UDim2.new(0.5, 0, 0, px(138))
                Instance.new("UICorner", cardPriceBadge).CornerRadius = UDim.new(0, px(6))
                local cpLbl = Instance.new("TextLabel", cardPriceBadge)
                cpLbl.BackgroundTransparency = 1
                cpLbl.Font = Enum.Font.GothamBold
                cpLbl.Text = tostring(price)
                cpLbl.TextColor3 = GOLD
                cpLbl.TextScaled = true
                cpLbl.Size = UDim2.new(1, 0, 1, 0)
                cpLbl.TextXAlignment = Enum.TextXAlignment.Center

                -- Owned badge (top-right)
                local ownedBadge = Instance.new("TextLabel", card)
                ownedBadge.Name = "OwnedBadge"
                ownedBadge.BackgroundTransparency = 1
                ownedBadge.Font = Enum.Font.GothamBold
                ownedBadge.Text = "\u{2714}"
                ownedBadge.TextColor3 = GREEN_GLOW
                ownedBadge.TextSize = math.max(14, math.floor(px(16)))
                ownedBadge.Size = UDim2.new(0, px(20), 0, px(20))
                ownedBadge.AnchorPoint = Vector2.new(1, 0)
                ownedBadge.Position = UDim2.new(1, -px(6), 0, px(6))
                ownedBadge.ZIndex = 5
                ownedBadge.Visible = false

                -- Equipped bar
                local eqBar = Instance.new("Frame", card)
                eqBar.Name = "EquippedBar"
                eqBar.BackgroundColor3 = GREEN_GLOW
                eqBar.Size = UDim2.new(0.7, 0, 0, px(3))
                eqBar.AnchorPoint = Vector2.new(0.5, 1)
                eqBar.Position = UDim2.new(0.5, 0, 1, -px(4))
                eqBar.BorderSizePixel = 0
                eqBar.Visible = false
                Instance.new("UICorner", eqBar).CornerRadius = UDim.new(0, px(2))

                effectCards[effectId] = {
                    card = card,
                    cardStroke = eCS,
                    baseStrokeColor = baseStrokeColor,
                    baseStrokeThickness = baseStrokeThickness,
                    baseStrokeTransparency = baseStrokeTransparency,
                }

                -- Click to select
                card.MouseButton1Click:Connect(function()
                    setSelectedEffect(effectId)
                end)

                -- Hover effect
                if not game:GetService("UserInputService").TouchEnabled then
                    card.MouseEnter:Connect(function()
                        if selectedEffectId ~= effectId then
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(38, 40, 58)}):Play()
                        end
                    end)
                    card.MouseLeave:Connect(function()
                        if selectedEffectId ~= effectId then
                            local isOwn = ownedEffectSet[effectId] == true
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = isOwn and CARD_OWNED or CARD_BG}):Play()
                        end
                    end)
                end
            end

            -- ── Fetch data from server ──────────────────────────────────
            task.spawn(function()
                local eRemotes = ensureEffectRemotes()
                if not eRemotes then return end
                -- Owned effects
                if eRemotes.getOwned and eRemotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return eRemotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then
                        for _, id in ipairs(list) do ownedEffectSet[id] = true end
                    end
                end
                -- Equipped effect
                if eRemotes.getEquipped and eRemotes.getEquipped:IsA("RemoteFunction") then
                    local ok, equipped = pcall(function() return eRemotes.getEquipped:InvokeServer() end)
                    if ok and type(equipped) == "string" then equippedEffectId = equipped end
                end
                refreshEffectCards()
                -- Listen for equip changes
                if eRemotes.changed and eRemotes.changed:IsA("RemoteEvent") then
                    eRemotes.changed.OnClientEvent:Connect(function(newEquipped)
                        if type(newEquipped) == "string" then
                            equippedEffectId = newEquipped
                            updateEffectActionButton()
                            refreshEffectCards()
                        end
                    end)
                end
            end)

            contentPages["effects"] = effectsPage
            print("[ShopLayout] Effects content bounds:", px(660), "px | Detail panel:", px(380), "px | Card grid available width:", efxGridScroll.Size)
        else
            makePlaceholderPage("EffectsContent", "effects", "\u{2738}", "Effects coming soon")
        end
    end

    ---------------------------------------------------------------------------
    -- EMOTES content page (card grid + right-side detail panel, matches Skins/Effects)
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
            -- ── State ───────────────────────────────────────────────
            local ownedEmoteSet    = {}
            local selectedEmoteId  = nil
            local emoteCards       = {} -- [emoteId] = { card, cardStroke, ... }

            local SHOP_EMOTE_DETAIL_W = px(380)
            local SHOP_EMOTE_GRID_GAP = px(14)

            -- ── Page container ──────────────────────────────────────
            local emotesPage = Instance.new("Frame")
            emotesPage.Name                = "EmotesContent"
            emotesPage.BackgroundTransparency = 1
            emotesPage.Size                = UDim2.new(1, 0, 0, px(660))
            emotesPage.Visible             = false
            emotesPage.Parent              = contentContainer

            -- ── Left: card grid scroll ──────────────────────────────
            local emoteGridScroll = Instance.new("ScrollingFrame")
            emoteGridScroll.Name = "EmoteGridScroll"
            emoteGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
            emoteGridScroll.BackgroundTransparency = 0.5
            emoteGridScroll.Size = UDim2.new(1, -(SHOP_EMOTE_DETAIL_W + SHOP_EMOTE_GRID_GAP), 1, 0)
            emoteGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            emoteGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            emoteGridScroll.ScrollBarThickness = px(4)
            emoteGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
            emoteGridScroll.BorderSizePixel = 0
            emoteGridScroll.Parent = emotesPage
            Instance.new("UICorner", emoteGridScroll).CornerRadius = UDim.new(0, px(10))

            local emoteGridLayout = Instance.new("UIGridLayout", emoteGridScroll)
            emoteGridLayout.CellSize = UDim2.new(0, px(180), 0, px(215))
            emoteGridLayout.CellPadding = UDim2.new(0, px(14), 0, px(14))
            emoteGridLayout.FillDirection = Enum.FillDirection.Horizontal
            emoteGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            emoteGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

            local emoteGridPad = Instance.new("UIPadding", emoteGridScroll)
            emoteGridPad.PaddingTop    = UDim.new(0, px(12))
            emoteGridPad.PaddingLeft   = UDim.new(0, px(12))
            emoteGridPad.PaddingRight  = UDim.new(0, px(12))
            emoteGridPad.PaddingBottom = UDim.new(0, px(12))

            -- ── Right: detail panel ─────────────────────────────────
            local emoteDetailsPanel = Instance.new("Frame")
            emoteDetailsPanel.Name = "EmoteDetailsPanel"
            emoteDetailsPanel.BackgroundColor3 = CARD_BG
            emoteDetailsPanel.Size = UDim2.new(0, SHOP_EMOTE_DETAIL_W, 1, 0)
            emoteDetailsPanel.AnchorPoint = Vector2.new(1, 0)
            emoteDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
            emoteDetailsPanel.Parent = emotesPage
            Instance.new("UICorner", emoteDetailsPanel).CornerRadius = UDim.new(0, px(12))
            local edpStroke = Instance.new("UIStroke", emoteDetailsPanel)
            edpStroke.Color = CARD_STROKE; edpStroke.Thickness = 1.4; edpStroke.Transparency = 0.2

            -- Placeholder (shown when no emote selected)
            local emoteDetailPlaceholder = Instance.new("TextLabel", emoteDetailsPanel)
            emoteDetailPlaceholder.Name = "Placeholder"
            emoteDetailPlaceholder.BackgroundTransparency = 1
            emoteDetailPlaceholder.Font = Enum.Font.GothamMedium
            emoteDetailPlaceholder.Text = "Select an emote"
            emoteDetailPlaceholder.TextColor3 = DIM_TEXT
            emoteDetailPlaceholder.TextSize = px(22)
            emoteDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
            emoteDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
            emoteDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

            -- Detail content (hidden until an emote is selected)
            local emoteDetailContent = Instance.new("Frame", emoteDetailsPanel)
            emoteDetailContent.Name = "DetailContent"
            emoteDetailContent.BackgroundTransparency = 1
            emoteDetailContent.Size = UDim2.new(1, 0, 1, 0)
            emoteDetailContent.Visible = false

            local edPad = Instance.new("UIPadding", emoteDetailContent)
            edPad.PaddingTop  = UDim.new(0, px(16)); edPad.PaddingBottom = UDim.new(0, px(16))
            edPad.PaddingLeft = UDim.new(0, px(16)); edPad.PaddingRight  = UDim.new(0, px(16))

            -- Preview viewport (shows animated mannequin)
            local emotePreviewVP = Instance.new("ViewportFrame", emoteDetailContent)
            emotePreviewVP.Name = "PreviewViewport"
            emotePreviewVP.BackgroundColor3 = Color3.fromRGB(42, 44, 55)
            emotePreviewVP.Size = UDim2.new(1, 0, 0, px(300))
            emotePreviewVP.Ambient = Color3.fromRGB(100, 100, 120)
            Instance.new("UICorner", emotePreviewVP).CornerRadius = UDim.new(0, px(10))
            local emoteVPStroke = Instance.new("UIStroke", emotePreviewVP)
            emoteVPStroke.Color = GOLD; emoteVPStroke.Thickness = 1.5; emoteVPStroke.Transparency = 0.3

            -- Emote name label
            local emoteDetailName = Instance.new("TextLabel", emoteDetailContent)
            emoteDetailName.Name = "EmoteName"
            emoteDetailName.BackgroundTransparency = 1
            emoteDetailName.Font = Enum.Font.GothamBold
            emoteDetailName.TextColor3 = WHITE
            emoteDetailName.TextSize = px(26)
            emoteDetailName.TextXAlignment = Enum.TextXAlignment.Center
            emoteDetailName.Size = UDim2.new(1, 0, 0, px(36))
            emoteDetailName.Position = UDim2.new(0, 0, 0, px(310))
            emoteDetailName.TextTruncate = Enum.TextTruncate.AtEnd

            -- Type label (shows "Emote" as category)
            local emoteDetailType = Instance.new("TextLabel", emoteDetailContent)
            emoteDetailType.Name = "EmoteType"
            emoteDetailType.BackgroundTransparency = 1
            emoteDetailType.Font = Enum.Font.GothamBold
            emoteDetailType.TextColor3 = GOLD
            emoteDetailType.TextSize = px(19)
            emoteDetailType.TextXAlignment = Enum.TextXAlignment.Center
            emoteDetailType.Size = UDim2.new(1, 0, 0, px(28))
            emoteDetailType.Position = UDim2.new(0, 0, 0, px(348))
            emoteDetailType.Text = "Emote"

            -- Description
            local emoteDetailDesc = Instance.new("TextLabel", emoteDetailContent)
            emoteDetailDesc.Name = "Description"
            emoteDetailDesc.BackgroundTransparency = 1
            emoteDetailDesc.Font = Enum.Font.GothamBold
            emoteDetailDesc.TextColor3 = DIM_TEXT
            emoteDetailDesc.TextSize = px(17)
            emoteDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
            emoteDetailDesc.TextWrapped = true
            emoteDetailDesc.Size = UDim2.new(1, 0, 0, px(48))
            emoteDetailDesc.Position = UDim2.new(0, 0, 0, px(380))
            local emoteDescStroke = Instance.new("UIStroke", emoteDetailDesc)
            emoteDescStroke.Color = Color3.fromRGB(0, 0, 0)
            emoteDescStroke.Thickness = 1.5
            emoteDescStroke.Transparency = 0.15

            -- Price row
            local emotePriceRow = Instance.new("Frame", emoteDetailContent)
            emotePriceRow.Name = "PriceRow"
            emotePriceRow.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
            emotePriceRow.BackgroundTransparency = 0.3
            emotePriceRow.Size = UDim2.new(0.6, 0, 0, px(34))
            emotePriceRow.AnchorPoint = Vector2.new(0.5, 0)
            emotePriceRow.Position = UDim2.new(0.5, 0, 0, px(440))
            Instance.new("UICorner", emotePriceRow).CornerRadius = UDim.new(0, px(8))
            local epStk = Instance.new("UIStroke", emotePriceRow)
            epStk.Color = Color3.fromRGB(255, 200, 40); epStk.Thickness = 1; epStk.Transparency = 0.55

            local emotePriceLbl = Instance.new("TextLabel", emotePriceRow)
            emotePriceLbl.Name = "PriceText"
            emotePriceLbl.BackgroundTransparency = 1
            emotePriceLbl.Font = Enum.Font.GothamBold
            emotePriceLbl.TextColor3 = GOLD
            emotePriceLbl.TextScaled = true
            emotePriceLbl.Size = UDim2.new(0.58, 0, 1, 0)
            emotePriceLbl.TextXAlignment = Enum.TextXAlignment.Right

            local emotePriceCoin = Instance.new("ImageLabel", emotePriceRow)
            emotePriceCoin.Name = "CoinIcon"
            emotePriceCoin.Size = UDim2.new(0.26, 0, 0.80, 0)
            emotePriceCoin.Position = UDim2.new(0.64, 0, 0.5, 0)
            emotePriceCoin.AnchorPoint = Vector2.new(0, 0.5)
            emotePriceCoin.BackgroundTransparency = 1
            emotePriceCoin.ScaleType = Enum.ScaleType.Fit
            pcall(function()
                if AssetCodes and type(AssetCodes.Get) == "function" then
                    local ci = AssetCodes.Get("Coin")
                    if ci and #ci > 0 then emotePriceCoin.Image = ci end
                end
            end)

            -- Action button (BUY / OWNED)
            local emoteActionBtn = Instance.new("TextButton", emoteDetailContent)
            emoteActionBtn.Name = "ActionBtn"
            emoteActionBtn.AutoButtonColor = false
            emoteActionBtn.BackgroundColor3 = BTN_BUY
            emoteActionBtn.Font = Enum.Font.GothamBold
            emoteActionBtn.Text = "BUY"
            emoteActionBtn.TextColor3 = WHITE
            emoteActionBtn.TextSize = px(24)
            emoteActionBtn.Size = UDim2.new(0.92, 0, 0, px(56))
            emoteActionBtn.AnchorPoint = Vector2.new(0.5, 1)
            emoteActionBtn.Position = UDim2.new(0.5, 0, 1, 0)
            Instance.new("UICorner", emoteActionBtn).CornerRadius = UDim.new(0, px(10))
            local emoteActionStroke = Instance.new("UIStroke", emoteActionBtn)
            emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
            emoteActionStroke.Thickness = 1.5
            emoteActionStroke.Transparency = 0.15

            -- ── Emote preview rig management ────────────────────────
            local _emotePreviewRig   = nil
            local _emotePreviewTrack = nil
            local _emotePreviewWM    = nil

            local function cleanupEmotePreview()
                if _emotePreviewTrack then
                    pcall(function() _emotePreviewTrack:Stop(0) end)
                    pcall(function() _emotePreviewTrack:Destroy() end)
                    _emotePreviewTrack = nil
                end
                if _emotePreviewWM then
                    pcall(function() _emotePreviewWM:Destroy() end)
                    _emotePreviewWM = nil
                end
                _emotePreviewRig = nil
                -- Clear viewport children
                for _, child in ipairs(emotePreviewVP:GetChildren()) do
                    if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
                        child:Destroy()
                    end
                end
            end

            local function buildEmotePreviewRig()
                cleanupEmotePreview()

                local player = game:GetService("Players").LocalPlayer
                if not player then return nil end
                local desc = nil
                pcall(function()
                    desc = game:GetService("Players"):GetHumanoidDescriptionFromUserId(player.UserId)
                end)

                local rig = nil
                pcall(function()
                    rig = game:GetService("Players"):CreateHumanoidModelFromDescription(desc or Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
                end)
                if not rig then return nil end

                -- Strip scripts and effects
                for _, child in ipairs(rig:GetDescendants()) do
                    if child:IsA("BaseScript") or child:IsA("BillboardGui") or child:IsA("ForceField") then
                        child:Destroy()
                    end
                end

                local worldModel = Instance.new("WorldModel")
                worldModel.Parent = emotePreviewVP
                rig.Parent = worldModel
                _emotePreviewWM = worldModel

                -- Position rig
                local hrp = rig:FindFirstChild("HumanoidRootPart")
                if hrp then
                    rig:PivotTo(CFrame.new(0, 0, 0))
                end

                -- Camera: front-facing, slightly above center
                local cam = Instance.new("Camera")
                cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.5, 8), Vector3.new(0, 2, 0))
                cam.FieldOfView = 40
                cam.Parent = emotePreviewVP
                emotePreviewVP.CurrentCamera = cam

                -- Lighting
                local lightPart = Instance.new("Part")
                lightPart.Anchored = true; lightPart.Transparency = 1
                lightPart.CanCollide = false; lightPart.Size = Vector3.new(0.1, 0.1, 0.1)
                lightPart.CFrame = CFrame.new(3, 6, 5); lightPart.Parent = worldModel
                local light = Instance.new("PointLight")
                light.Color = Color3.fromRGB(255, 245, 230); light.Brightness = 1.2
                light.Range = 22; light.Parent = lightPart

                local fillPart = Instance.new("Part")
                fillPart.Anchored = true; fillPart.Transparency = 1
                fillPart.CanCollide = false; fillPart.Size = Vector3.new(0.1, 0.1, 0.1)
                fillPart.CFrame = CFrame.new(-4, 4, 3); fillPart.Parent = worldModel
                local fill = Instance.new("PointLight")
                fill.Color = Color3.fromRGB(150, 160, 200); fill.Brightness = 0.8
                fill.Range = 18; fill.Parent = fillPart

                _emotePreviewRig = rig
                return rig
            end

            local function playEmoteOnPreviewRig(animationId)
                if not _emotePreviewRig then return end

                -- Stop previous track
                if _emotePreviewTrack then
                    pcall(function() _emotePreviewTrack:Stop(0) end)
                    pcall(function() _emotePreviewTrack:Destroy() end)
                    _emotePreviewTrack = nil
                end

                local humanoid = _emotePreviewRig:FindFirstChildOfClass("Humanoid")
                if not humanoid then return end

                local animator = humanoid:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator")
                    animator.Parent = humanoid
                end

                local anim = Instance.new("Animation")
                anim.AnimationId = animationId
                local track
                local ok, err = pcall(function()
                    track = animator:LoadAnimation(anim)
                end)
                anim:Destroy()
                if not ok or not track then
                    warn("[ShopEmotes] Failed to load emote animation:", err)
                    return
                end

                track.Priority = Enum.AnimationPriority.Action
                track.Looped = true
                pcall(function() track:Play(0.25) end)
                _emotePreviewTrack = track
                print("[ShopEmotes] Playing preview animation for:", animationId)
            end

            -- Register cleanup for tab switch
            _stopShopEmotePreview = function()
                cleanupEmotePreview()
            end

            -- ── Action button state management ──────────────────────
            local function updateEmoteActionButton()
                if not selectedEmoteId then return end
                local owned = ownedEmoteSet[selectedEmoteId] == true
                local def = EmoteConfig and EmoteConfig.GetById(selectedEmoteId)
                local price = def and def.CoinCost or 0

                if owned then
                    emoteActionBtn.Text = "\u{2714} OWNED"
                    emoteActionBtn.BackgroundColor3 = DISABLED_BG
                    emoteActionBtn.TextColor3 = GREEN_GLOW
                    emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
                    emoteActionStroke.Transparency = 0.15
                    emotePriceRow.Visible = false
                else
                    emoteActionBtn.Text = "BUY"
                    emoteActionBtn.BackgroundColor3 = BTN_BUY
                    emoteActionBtn.TextColor3 = WHITE
                    emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
                    emoteActionStroke.Transparency = 0.15
                    emotePriceLbl.Text = tostring(price)
                    emotePriceRow.Visible = (price > 0)
                    emotePriceCoin.Visible = (price > 0)
                end
            end

            -- ── Card highlight refresh ──────────────────────────────
            local function refreshEmoteCards()
                for eid, info in pairs(emoteCards) do
                    local isSelected = (selectedEmoteId == eid)
                    local owned = ownedEmoteSet[eid] == true

                    if isSelected then
                        info.cardStroke.Color = GOLD
                        info.cardStroke.Thickness = 2.0
                        info.cardStroke.Transparency = 0
                    elseif owned then
                        info.cardStroke.Color = GREEN_GLOW
                        info.cardStroke.Thickness = 1.6
                        info.cardStroke.Transparency = 0.35
                        info.card.BackgroundColor3 = CARD_OWNED
                    else
                        info.cardStroke.Color = info.baseStrokeColor
                        info.cardStroke.Thickness = info.baseStrokeThickness
                        info.cardStroke.Transparency = info.baseStrokeTransparency
                        info.card.BackgroundColor3 = CARD_BG
                    end

                    -- Owned badge on card
                    local ownedBadge = info.card:FindFirstChild("OwnedBadge")
                    if ownedBadge then ownedBadge.Visible = owned end
                end
            end

            -- ── Set selected emote (update detail panel) ────────────
            local function setSelectedEmote(emoteId)
                selectedEmoteId = emoteId
                if not emoteId then
                    emoteDetailPlaceholder.Visible = true
                    emoteDetailContent.Visible = false
                    cleanupEmotePreview()
                    refreshEmoteCards()
                    return
                end
                emoteDetailPlaceholder.Visible = false
                emoteDetailContent.Visible = true

                local def = EmoteConfig and EmoteConfig.GetById(emoteId)
                if not def then return end

                emoteDetailName.Text = def.DisplayName or emoteId
                emoteDetailDesc.Text = def.Description or ""

                -- Build preview rig and play animation
                local rig = buildEmotePreviewRig()
                if rig and def.AnimationId then
                    playEmoteOnPreviewRig(def.AnimationId)
                end

                updateEmoteActionButton()
                refreshEmoteCards()
                print("[ShopEmotes] Selected emote:", emoteId)
            end

            -- ── Action button click ─────────────────────────────────
            emoteActionBtn.MouseButton1Click:Connect(function()
                if not selectedEmoteId then return end
                local owned = ownedEmoteSet[selectedEmoteId] == true
                if owned then return end -- already owned, nothing to do

                -- Purchase
                local remotes = ensureEmoteRemotes()
                if not remotes or not remotes.purchase or not remotes.purchase:IsA("RemoteFunction") then
                    warn("[ShopEmotes] PurchaseEmote remote not found")
                    return
                end

                emoteActionBtn.Text = "..."
                local ok, success, newBalance, msg = pcall(function()
                    return remotes.purchase:InvokeServer(selectedEmoteId)
                end)

                if ok and success then
                    ownedEmoteSet[selectedEmoteId] = true
                    if coinApi and coinApi.SetCoins then
                        pcall(function() coinApi.SetCoins(newBalance) end)
                    end
                    pcall(function()
                        if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                    end)
                    updateEmoteActionButton()
                    refreshEmoteCards()
                    print("[ShopEmotes] Purchase accepted:", selectedEmoteId)
                else
                    emoteActionBtn.Text = "NOT ENOUGH"
                    emoteActionBtn.TextColor3 = RED_TEXT
                    task.delay(1.2, function()
                        updateEmoteActionButton()
                    end)
                    print("[ShopEmotes] Purchase rejected:", selectedEmoteId, msg)
                end
            end)

            -- Action button hover
            emoteActionBtn.MouseEnter:Connect(function()
                local owned = selectedEmoteId and ownedEmoteSet[selectedEmoteId]
                if not owned then
                    pcall(function() TweenService:Create(emoteActionBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play() end)
                end
            end)
            emoteActionBtn.MouseLeave:Connect(function()
                local owned = selectedEmoteId and ownedEmoteSet[selectedEmoteId]
                if not owned then
                    pcall(function() TweenService:Create(emoteActionBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BUY}):Play() end)
                end
            end)

            -- ── Fetch owned emotes from server ──────────────────────
            local emoteCardEntries = {}
            task.spawn(function()
                local remotes = ensureEmoteRemotes()
                if remotes and remotes.getOwned and remotes.getOwned:IsA("RemoteFunction") then
                    local ok2, list = pcall(function() return remotes.getOwned:InvokeServer() end)
                    if ok2 and type(list) == "table" then
                        for _, id in ipairs(list) do ownedEmoteSet[id] = true end
                        refreshEmoteCards()
                        if selectedEmoteId then updateEmoteActionButton() end
                        reorderByOwnership(emoteCardEntries, function(id) return ownedEmoteSet[id] == true end)
                    end
                end
            end)

            -- ── Build emote cards ───────────────────────────────────
            for i_emote, def in ipairs(allEmotes) do
                local emoteId     = def.Id
                local displayName = def.DisplayName or emoteId
                local price       = def.CoinCost or 0
                local iconKey     = def.IconKey
                local description = def.Description or ""

                -- Main card button
                local card = Instance.new("TextButton")
                card.Name = "EmoteCard_" .. emoteId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.Text = ""
                card.AutoButtonColor = false
                card.BorderSizePixel = 0
                card.LayoutOrder = i_emote
                card.Parent = emoteGridScroll
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(10))

                local baseStrokeColor = CARD_STROKE
                local baseStrokeThickness = 1.2
                local baseStrokeTransparency = 0.35
                local cStk = Instance.new("UIStroke", card)
                cStk.Color = baseStrokeColor
                cStk.Thickness = baseStrokeThickness
                cStk.Transparency = baseStrokeTransparency

                table.insert(emoteCardEntries, { card = card, originalOrder = i_emote, id = emoteId })
                emoteCards[emoteId] = {
                    card = card,
                    cardStroke = cStk,
                    baseStrokeColor = baseStrokeColor,
                    baseStrokeThickness = baseStrokeThickness,
                    baseStrokeTransparency = baseStrokeTransparency,
                }

                -- Icon area (top section) — warm-tinted background
                local iconArea = Instance.new("Frame", card)
                iconArea.Name = "IconArea"
                iconArea.BackgroundColor3 = Color3.fromRGB(38, 36, 52)
                iconArea.Size = UDim2.new(1, -px(10), 0, px(125))
                iconArea.Position = UDim2.new(0, px(5), 0, px(5))
                iconArea.BorderSizePixel = 0
                Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, px(8))
                local iconAreaStroke = Instance.new("UIStroke", iconArea)
                iconAreaStroke.Color = Color3.fromRGB(70, 65, 45)
                iconAreaStroke.Thickness = 1
                iconAreaStroke.Transparency = 0.55

                -- PRIMARY: TextLabel emoji icon (always visible, matches Skins card pattern)
                local EMOTE_GLYPHS = {
                    wave   = "\u{1F44B}",  -- 👋
                    dance  = "\u{1F57A}",  -- 🕺
                    cheer  = "\u{1F389}",  -- 🎉
                    salute = "\u{270B}",   -- ✋
                    laugh  = "\u{1F602}",  -- 😂
                    cry    = "\u{1F622}",  -- 😢
                    flex   = "\u{1F4AA}",  -- 💪
                    point  = "\u{1F449}",  -- 👉
                }
                local EMOTE_GLYPH_COLORS = {
                    wave   = Color3.fromRGB(255, 210, 80),
                    dance  = Color3.fromRGB(180, 120, 255),
                    cheer  = Color3.fromRGB(255, 180, 50),
                    salute = Color3.fromRGB(200, 200, 220),
                }
                local glyphText = EMOTE_GLYPHS[emoteId] or "\u{1F3AD}" -- 🎭 generic
                local glyphColor = EMOTE_GLYPH_COLORS[emoteId] or GOLD

                local cardGlyph = Instance.new("TextLabel", iconArea)
                cardGlyph.Name = "EmoteGlyph"
                cardGlyph.BackgroundTransparency = 1
                cardGlyph.Text = glyphText
                cardGlyph.TextScaled = true
                cardGlyph.Font = Enum.Font.GothamBold
                cardGlyph.TextColor3 = glyphColor
                cardGlyph.Size = UDim2.new(0.55, 0, 0.55, 0)
                cardGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
                cardGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
                cardGlyph.ZIndex = 2
                print("[ShopEmotes] Building card for emote:", emoteId, "glyph:", glyphText, "visible:", cardGlyph.Visible, "ZIndex:", cardGlyph.ZIndex)

                -- OPTIONAL OVERLAY: if a real image asset loads, show it on top of the glyph
                pcall(function()
                    local imgId = nil
                    if AssetCodes and iconKey then
                        local img = AssetCodes.Get(iconKey)
                        if img and #img > 0 then imgId = img end
                    end
                    if not imgId and def.IconAssetId and type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then
                        imgId = def.IconAssetId
                    end
                    if imgId then
                        local cardImg = Instance.new("ImageLabel", iconArea)
                        cardImg.Name = "IconImage"
                        cardImg.BackgroundTransparency = 1
                        cardImg.ScaleType = Enum.ScaleType.Fit
                        cardImg.Size = UDim2.new(0.65, 0, 0.65, 0)
                        cardImg.AnchorPoint = Vector2.new(0.5, 0.5)
                        cardImg.Position = UDim2.new(0.5, 0, 0.5, 0)
                        cardImg.ZIndex = 3
                        cardImg.Image = imgId
                        print("[ShopEmotes] Image overlay assigned for emote:", emoteId, "asset:", imgId)
                    end
                end)

                -- Name label
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = displayName
                cardName.TextColor3 = WHITE
                cardName.TextSize = math.max(13, math.floor(px(14)))
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, px(24))
                cardName.Position = UDim2.new(0, px(5), 0, px(136))

                -- Type label
                local cardType = Instance.new("TextLabel", card)
                cardType.Name = "TypeLabel"
                cardType.BackgroundTransparency = 1
                cardType.Font = Enum.Font.GothamBold
                cardType.Text = "Emote"
                cardType.TextColor3 = GOLD
                cardType.TextSize = math.max(11, math.floor(px(12)))
                cardType.TextXAlignment = Enum.TextXAlignment.Center
                cardType.Size = UDim2.new(1, -px(10), 0, px(20))
                cardType.Position = UDim2.new(0, px(5), 0, px(163))

                -- Price badge
                local cardPriceBadge = Instance.new("Frame", card)
                cardPriceBadge.Name = "CardPriceBadge"
                cardPriceBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
                cardPriceBadge.BackgroundTransparency = 0.3
                cardPriceBadge.Size = UDim2.new(0.65, 0, 0, px(22))
                cardPriceBadge.AnchorPoint = Vector2.new(0.5, 0)
                cardPriceBadge.Position = UDim2.new(0.5, 0, 0, px(186))
                Instance.new("UICorner", cardPriceBadge).CornerRadius = UDim.new(0, px(6))
                local cpLbl = Instance.new("TextLabel", cardPriceBadge)
                cpLbl.BackgroundTransparency = 1
                cpLbl.Font = Enum.Font.GothamBold
                cpLbl.Text = (price > 0) and tostring(price) or "FREE"
                cpLbl.TextColor3 = GOLD
                cpLbl.TextScaled = true
                cpLbl.Size = UDim2.new(1, 0, 1, 0)
                cpLbl.TextXAlignment = Enum.TextXAlignment.Center

                -- Owned badge (top-right checkmark)
                local ownedBadge = Instance.new("TextLabel", card)
                ownedBadge.Name = "OwnedBadge"
                ownedBadge.BackgroundTransparency = 1
                ownedBadge.Font = Enum.Font.GothamBold
                ownedBadge.Text = "\u{2714}"
                ownedBadge.TextColor3 = GREEN_GLOW
                ownedBadge.TextSize = math.max(16, math.floor(px(18)))
                ownedBadge.Size = UDim2.new(0, px(28), 0, px(28))
                ownedBadge.AnchorPoint = Vector2.new(1, 0)
                ownedBadge.Position = UDim2.new(1, -px(5), 0, px(5))
                ownedBadge.Visible = false

                -- Card click handler
                card.MouseButton1Click:Connect(function()
                    setSelectedEmote(emoteId)
                end)

                -- Card hover
                card.MouseEnter:Connect(function()
                    if selectedEmoteId ~= emoteId then
                        pcall(function() TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(42, 48, 70)}):Play() end)
                    end
                end)
                card.MouseLeave:Connect(function()
                    if selectedEmoteId ~= emoteId then
                        local owned = ownedEmoteSet[emoteId] == true
                        pcall(function() TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = owned and CARD_OWNED or CARD_BG}):Play() end)
                    end
                end)
            end -- end for each emote

            contentPages["emotes"] = emotesPage
            print("[ShopEmotes] Emotes tab built with", #allEmotes, "emotes — card grid + detail panel layout")
        else
            -- No emotes defined yet: show placeholder
            makePlaceholderPage("EmotesContent",  "emotes",  "\u{263A}", "Emotes coming soon")
        end
    end

    ---------------------------------------------------------------------------
    -- SALVAGE SHOP content page
    ---------------------------------------------------------------------------
    do
        local SalvageShopConfig = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("SalvageShopConfig")
            if mod and mod:IsA("ModuleScript") then
                SalvageShopConfig = require(mod)
            end
        end)

        local SALVAGE_GREEN = Color3.fromRGB(35, 190, 75)
        local SALVAGE_BG    = Color3.fromRGB(24, 56, 32)

        local salvagePage = Instance.new("ScrollingFrame")
        salvagePage.Name = "SalvageContent"
        salvagePage.BackgroundTransparency = 1
        salvagePage.Size = UDim2.new(1, 0, 1, 0)
        salvagePage.CanvasSize = UDim2.new(0, 0, 0, 0)
        salvagePage.AutomaticCanvasSize = Enum.AutomaticSize.Y
        salvagePage.ScrollBarThickness = px(4)
        salvagePage.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
        salvagePage.BorderSizePixel = 0
        salvagePage.Visible = false
        salvagePage.Parent = contentContainer

        local salvageLayout = Instance.new("UIListLayout")
        salvageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        salvageLayout.Padding = UDim.new(0, px(12))
        salvageLayout.Parent = salvagePage

        local salvagePad = Instance.new("UIPadding")
        salvagePad.PaddingTop = UDim.new(0, px(6))
        salvagePad.PaddingBottom = UDim.new(0, px(12))
        salvagePad.PaddingLeft = UDim.new(0, px(8))
        salvagePad.PaddingRight = UDim.new(0, px(8))
        salvagePad.Parent = salvagePage

        -- Header
        local salvageHeader = Instance.new("Frame")
        salvageHeader.Name = "SalvageHeader"
        salvageHeader.BackgroundTransparency = 1
        salvageHeader.Size = UDim2.new(1, 0, 0, px(54))
        salvageHeader.LayoutOrder = 1
        salvageHeader.Parent = salvagePage

        local salvageTitle = Instance.new("TextLabel")
        salvageTitle.BackgroundTransparency = 1
        salvageTitle.Font = Enum.Font.GothamBold
        salvageTitle.Text = "SALVAGE SHOP"
        salvageTitle.TextColor3 = SALVAGE_GREEN
        salvageTitle.TextSize = math.max(20, math.floor(px(24)))
        salvageTitle.TextXAlignment = Enum.TextXAlignment.Left
        salvageTitle.Size = UDim2.new(1, 0, 0, px(30))
        salvageTitle.Parent = salvageHeader

        local salvageSubtitle = Instance.new("TextLabel")
        salvageSubtitle.BackgroundTransparency = 1
        salvageSubtitle.Font = Enum.Font.GothamMedium
        salvageSubtitle.Text = "Spend Salvage earned from recycling weapons."
        salvageSubtitle.TextColor3 = DIM_TEXT
        salvageSubtitle.TextSize = math.max(11, math.floor(px(12)))
        salvageSubtitle.TextXAlignment = Enum.TextXAlignment.Left
        salvageSubtitle.Size = UDim2.new(1, 0, 0, px(16))
        salvageSubtitle.Position = UDim2.new(0, 0, 0, px(30))
        salvageSubtitle.Parent = salvageHeader

        local salvageAccent = Instance.new("Frame")
        salvageAccent.BackgroundColor3 = SALVAGE_GREEN
        salvageAccent.BackgroundTransparency = 0.3
        salvageAccent.BorderSizePixel = 0
        salvageAccent.Size = UDim2.new(1, 0, 0, px(2))
        salvageAccent.Position = UDim2.new(0, 0, 1, -px(2))
        salvageAccent.Parent = salvageHeader

        -- Rarity colors for card styling
        local SALVAGE_RARITY_COLORS = {
            Common    = Color3.fromRGB(180, 180, 180),
            Uncommon  = Color3.fromRGB(120, 200, 120),
            Rare      = Color3.fromRGB(60, 140, 255),
            Epic      = Color3.fromRGB(180, 60, 255),
            Legendary = Color3.fromRGB(255, 180, 30),
        }

        -- Fetch ownership state from server
        local ownedItems = {}
        pcall(function()
            local ownershipRF = ReplicatedStorage:FindFirstChild("GetSalvageShopOwnership")
            if not ownershipRF then
                ownershipRF = ReplicatedStorage:WaitForChild("GetSalvageShopOwnership", 6)
            end
            if ownershipRF and ownershipRF:IsA("RemoteFunction") then
                local result = ownershipRF:InvokeServer()
                if type(result) == "table" then
                    ownedItems = result
                end
            end
        end)

        -- Fetch current salvage balance for button state
        local currentSalvage = 0
        pcall(function()
            local getSalvageFn = ReplicatedStorage:FindFirstChild("GetSalvage")
            if getSalvageFn and getSalvageFn:IsA("RemoteFunction") then
                local result = getSalvageFn:InvokeServer()
                if type(result) == "number" then
                    currentSalvage = result
                end
            end
        end)

        -- Listen for live salvage balance updates
        pcall(function()
            local salvageEvent = ReplicatedStorage:FindFirstChild("SalvageUpdated")
            if salvageEvent and salvageEvent:IsA("RemoteEvent") then
                trackConn(salvageEvent.OnClientEvent:Connect(function(amount)
                    if type(amount) == "number" then
                        currentSalvage = amount
                    end
                end))
            end
        end)

        local purchaseDebounce = false
        local salvageCardRefs = {} -- [itemId] = { buyBtn, ownedLabel, priceLabel }

        local function updateSalvageCardStates()
            for itemId, refs in pairs(salvageCardRefs) do
                local isOwned = ownedItems[itemId] == true
                -- Sort owned unique items to the bottom
                if refs.card and refs.card.Parent and refs.originalOrder then
                    refs.card.LayoutOrder = (isOwned and refs.unique)
                        and (1000 + refs.originalOrder)
                        or refs.originalOrder
                end
                if isOwned and refs.unique then
                    refs.buyBtn.Visible = false
                    refs.ownedLabel.Visible = true
                    refs.card.BackgroundColor3 = CARD_OWNED or Color3.fromRGB(20, 38, 24)
                    refs.stroke.Color = GREEN_GLOW
                else
                    refs.buyBtn.Visible = true
                    refs.ownedLabel.Visible = false
                    refs.card.BackgroundColor3 = CARD_BG
                    refs.stroke.Color = CARD_STROKE
                    -- Update affordability
                    if currentSalvage >= refs.price then
                        refs.buyBtn.BackgroundColor3 = Color3.fromRGB(30, 48, 36)
                        refs.buyBtn.TextColor3 = Color3.fromRGB(180, 230, 190)
                        refs.buyBtn.Text = refs.priceText
                    else
                        refs.buyBtn.BackgroundColor3 = DISABLED_BG
                        refs.buyBtn.TextColor3 = DIM_TEXT
                        refs.buyBtn.Text = refs.priceText
                    end
                end
            end
        end

        if SalvageShopConfig then
            local enabledItems = SalvageShopConfig.GetEnabled()

            if #enabledItems == 0 then
                local empty = Instance.new("TextLabel")
                empty.BackgroundTransparency = 1
                empty.Font = Enum.Font.GothamMedium
                empty.Text = "No items available in the Salvage Shop yet."
                empty.TextColor3 = DIM_TEXT
                empty.TextSize = math.max(14, math.floor(px(15)))
                empty.Size = UDim2.new(1, 0, 0, px(50))
                empty.LayoutOrder = 10
                empty.Parent = salvagePage
            else
                for index, item in ipairs(enabledItems) do
                    local rarColor = SALVAGE_RARITY_COLORS[item.Rarity] or SALVAGE_RARITY_COLORS.Common
                    local isOwned = item.Unique and ownedItems[item.Id] == true

                    local card = Instance.new("Frame")
                    card.Name = "Salvage_" .. item.Id
                    card.BackgroundColor3 = isOwned and (CARD_OWNED or Color3.fromRGB(20, 38, 24)) or CARD_BG
                    card.Size = UDim2.new(1, 0, 0, px(110))
                    card.LayoutOrder = 10 + index
                    card.Parent = salvagePage

                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UDim.new(0, px(12))
                    corner.Parent = card

                    local cardStroke = Instance.new("UIStroke")
                    cardStroke.Color = isOwned and GREEN_GLOW or CARD_STROKE
                    cardStroke.Thickness = 1.2
                    cardStroke.Transparency = 0.35
                    cardStroke.Parent = card

                    local pad = Instance.new("UIPadding")
                    pad.PaddingTop = UDim.new(0, px(10))
                    pad.PaddingBottom = UDim.new(0, px(10))
                    pad.PaddingLeft = UDim.new(0, px(14))
                    pad.PaddingRight = UDim.new(0, px(14))
                    pad.Parent = card

                    -- Icon plate (left side)
                    local iconFrame = Instance.new("Frame")
                    iconFrame.Name = "ItemIcon"
                    iconFrame.Size = UDim2.new(0, px(56), 0, px(56))
                    iconFrame.Position = UDim2.new(0, 0, 0.5, 0)
                    iconFrame.AnchorPoint = Vector2.new(0, 0.5)
                    iconFrame.BackgroundColor3 = rarColor
                    iconFrame.BackgroundTransparency = 0.7
                    iconFrame.BorderSizePixel = 0
                    iconFrame.Parent = card

                    local iconCorner = Instance.new("UICorner")
                    iconCorner.CornerRadius = UDim.new(0, px(8))
                    iconCorner.Parent = iconFrame

                    local iconStroke = Instance.new("UIStroke")
                    iconStroke.Color = rarColor
                    iconStroke.Thickness = 1.2
                    iconStroke.Transparency = 0.4
                    iconStroke.Parent = iconFrame

                    local iconGlyph = Instance.new("TextLabel")
                    iconGlyph.Name = "Glyph"
                    iconGlyph.BackgroundTransparency = 1
                    iconGlyph.Size = UDim2.new(1, 0, 1, 0)
                    iconGlyph.Font = Enum.Font.GothamBold
                    iconGlyph.Text = item.IconGlyph or "\u{2699}"
                    iconGlyph.TextSize = math.max(16, math.floor(px(28)))
                    iconGlyph.TextColor3 = WHITE
                    iconGlyph.Parent = iconFrame

                    -- Item name
                    local nameLabel = Instance.new("TextLabel")
                    nameLabel.BackgroundTransparency = 1
                    nameLabel.Font = Enum.Font.GothamBold
                    nameLabel.Text = item.DisplayName
                    nameLabel.TextColor3 = WHITE
                    nameLabel.TextSize = math.max(15, math.floor(px(17)))
                    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                    nameLabel.Size = UDim2.new(0.55, -px(70), 0, px(22))
                    nameLabel.Position = UDim2.new(0, px(70), 0, 0)
                    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                    nameLabel.Parent = card

                    -- Rarity tag
                    local rarTag = Instance.new("TextLabel")
                    rarTag.BackgroundTransparency = 1
                    rarTag.Font = Enum.Font.GothamBold
                    rarTag.Text = item.Rarity or ""
                    rarTag.TextColor3 = rarColor
                    rarTag.TextSize = math.max(10, math.floor(px(11)))
                    rarTag.TextXAlignment = Enum.TextXAlignment.Left
                    rarTag.Size = UDim2.new(0.3, 0, 0, px(16))
                    rarTag.Position = UDim2.new(0, px(70), 0, px(22))
                    rarTag.Parent = card

                    -- Description
                    local desc = Instance.new("TextLabel")
                    desc.BackgroundTransparency = 1
                    desc.Font = Enum.Font.GothamMedium
                    desc.Text = item.Description
                    desc.TextColor3 = DIM_TEXT
                    desc.TextSize = math.max(11, math.floor(px(12)))
                    desc.TextWrapped = true
                    desc.TextXAlignment = Enum.TextXAlignment.Left
                    desc.TextYAlignment = Enum.TextYAlignment.Top
                    desc.Size = UDim2.new(0.55, -px(70), 0, px(36))
                    desc.Position = UDim2.new(0, px(70), 0, px(40))
                    desc.Parent = card

                    -- Price label
                    local priceText = tostring(item.SalvagePrice) .. " \u{2699}"
                    local priceLabel = Instance.new("TextLabel")
                    priceLabel.BackgroundTransparency = 1
                    priceLabel.Font = Enum.Font.GothamBold
                    priceLabel.Text = priceText
                    priceLabel.TextColor3 = Color3.fromRGB(140, 210, 160)
                    priceLabel.TextSize = math.max(13, math.floor(px(14)))
                    priceLabel.TextXAlignment = Enum.TextXAlignment.Left
                    priceLabel.Size = UDim2.new(0.3, -px(70), 0, px(18))
                    priceLabel.Position = UDim2.new(0, px(70), 1, -px(18))
                    priceLabel.Parent = card

                    -- Buy button (right side)
                    local buyBtn = Instance.new("TextButton")
                    buyBtn.Name = "BuyBtn"
                    buyBtn.AutoButtonColor = false
                    buyBtn.Font = Enum.Font.GothamBold
                    buyBtn.TextSize = math.max(14, math.floor(px(15)))
                    buyBtn.Size = UDim2.new(0, px(140), 0, px(38))
                    buyBtn.AnchorPoint = Vector2.new(1, 1)
                    buyBtn.Position = UDim2.new(1, -px(4), 1, -px(4))
                    buyBtn.Parent = card
                    buyBtn.Visible = not isOwned

                    if currentSalvage >= item.SalvagePrice then
                        buyBtn.BackgroundColor3 = Color3.fromRGB(30, 48, 36)
                        buyBtn.TextColor3 = Color3.fromRGB(180, 230, 190)
                        buyBtn.Text = priceText
                    else
                        buyBtn.BackgroundColor3 = DISABLED_BG
                        buyBtn.TextColor3 = DIM_TEXT
                        buyBtn.Text = priceText
                    end

                    local btnCorner = Instance.new("UICorner")
                    btnCorner.CornerRadius = UDim.new(0, px(10))
                    btnCorner.Parent = buyBtn

                    local btnStroke = Instance.new("UIStroke")
                    btnStroke.Color = Color3.fromRGB(80, 130, 90)
                    btnStroke.Thickness = 1.2
                    btnStroke.Transparency = 0.5
                    btnStroke.Parent = buyBtn

                    local btnPad = Instance.new("UIPadding")
                    btnPad.PaddingLeft = UDim.new(0, px(6))
                    btnPad.PaddingRight = UDim.new(0, px(6))
                    btnPad.Parent = buyBtn

                    -- Owned indicator (hidden unless unique + owned)
                    local ownedLabel = Instance.new("TextLabel")
                    ownedLabel.Name = "OwnedBadge"
                    ownedLabel.BackgroundTransparency = 1
                    ownedLabel.Font = Enum.Font.GothamBold
                    ownedLabel.Text = "\u{2714} OWNED"
                    ownedLabel.TextColor3 = GREEN_GLOW
                    ownedLabel.TextSize = math.max(13, math.floor(px(14)))
                    ownedLabel.TextXAlignment = Enum.TextXAlignment.Right
                    ownedLabel.Size = UDim2.new(0.35, 0, 0, px(24))
                    ownedLabel.AnchorPoint = Vector2.new(1, 1)
                    ownedLabel.Position = UDim2.new(1, 0, 1, 0)
                    ownedLabel.Visible = isOwned
                    ownedLabel.Parent = card

                    -- Hover feedback
                    buyBtn.MouseEnter:Connect(function()
                        if currentSalvage >= item.SalvagePrice then
                            TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(38, 60, 44)}):Play()
                        end
                    end)
                    buyBtn.MouseLeave:Connect(function()
                        local bg = (currentSalvage >= item.SalvagePrice) and Color3.fromRGB(30, 48, 36) or DISABLED_BG
                        TweenService:Create(buyBtn, TWEEN_QUICK, {BackgroundColor3 = bg}):Play()
                    end)

                    -- Purchase click handler
                    buyBtn.MouseButton1Click:Connect(function()
                        if purchaseDebounce then return end
                        if currentSalvage < item.SalvagePrice then
                            showToast(salvagePage, "Not enough Salvage!", RED_TEXT, 2)
                            return
                        end

                        purchaseDebounce = true

                        local purchaseRF = ReplicatedStorage:FindFirstChild("PurchaseSalvageItem")
                        if not purchaseRF or not purchaseRF:IsA("RemoteFunction") then
                            showToast(salvagePage, "Purchase unavailable", RED_TEXT, 2)
                            purchaseDebounce = false
                            return
                        end

                        buyBtn.Text = "..."
                        local ok, success, result = pcall(function()
                            return purchaseRF:InvokeServer(item.Id)
                        end)

                        if ok and success then
                            -- Update balance
                            if type(result) == "table" and result.newBalance then
                                currentSalvage = result.newBalance
                            end

                            -- Mark owned if unique
                            if item.Unique then
                                ownedItems[item.Id] = true
                            end

                            -- Refresh all card states
                            updateSalvageCardStates()

                            -- Update header
                            pcall(function()
                                if _G.UpdateShopHeaderSalvage then _G.UpdateShopHeaderSalvage() end
                            end)

                            -- Trigger crate opening animation for crate purchases
                            if item.RewardType == "Crate" and type(result) == "table"
                                and result.rewardData and result.rewardData.weaponName
                                and _G.PlayCrateAnimation then
                                local rd = result.rewardData
                                _G.PlayCrateAnimation(item.RewardId, {
                                    weaponName   = rd.weaponName,
                                    rarity       = rd.rarity,
                                    sizePercent  = rd.sizePercent,
                                    sizeTier     = rd.sizeTier,
                                    salvageValue = rd.salvageValue,
                                    isPending    = rd.isPending,
                                    crateType    = rd.crateType or item.RewardId,
                                })
                                print("[SalvageCrate] Routing to shared reward popup")
                            else
                                local displayName = (type(result) == "table" and result.displayName) or item.DisplayName
                                showToast(salvagePage, "Purchased " .. displayName .. "!", GREEN_GLOW, 2.5)
                            end

                            print("[SalvageShop] Purchase success:", item.Id)
                        else
                            local reason = "Purchase failed"
                            if type(result) == "table" and result.reason then
                                reason = result.reason
                            elseif type(result) == "string" then
                                reason = result
                            end
                            showToast(salvagePage, reason, RED_TEXT, 3)
                            print("[SalvageShop] Purchase denied:", item.Id, reason)
                        end

                        buyBtn.Text = priceText
                        task.delay(1.0, function()
                            purchaseDebounce = false
                        end)
                    end)

                    -- Store refs for state updates
                    salvageCardRefs[item.Id] = {
                        card = card,
                        buyBtn = buyBtn,
                        ownedLabel = ownedLabel,
                        priceLabel = priceLabel,
                        stroke = cardStroke,
                        price = item.SalvagePrice,
                        priceText = priceText,
                        unique = item.Unique == true,
                        originalOrder = 10 + index,
                    }
                end

                -- Initial card state update
                updateSalvageCardStates()
            end
        else
            local empty = Instance.new("TextLabel")
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.GothamMedium
            empty.Text = "Salvage Shop coming soon."
            empty.TextColor3 = DIM_TEXT
            empty.TextSize = math.max(14, math.floor(px(15)))
            empty.Size = UDim2.new(1, 0, 0, px(50))
            empty.LayoutOrder = 10
            empty.Parent = salvagePage
        end

        contentPages["salvage"] = salvagePage
    end

    ---------------------------------------------------------------------------
    -- CURRENCY content page (Robux coin packs + key packs via Developer Products)
    ---------------------------------------------------------------------------
    do
        local CoinProducts = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("CoinProducts")
            if mod and mod:IsA("ModuleScript") then
                CoinProducts = require(mod)
            end
        end)

        local KeyProducts = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("KeyProducts")
            if mod and mod:IsA("ModuleScript") then
                KeyProducts = require(mod)
            end
        end)

        local coinsPage = Instance.new("ScrollingFrame")
        coinsPage.Name = "CurrencyContent"
        coinsPage.BackgroundTransparency = 1
        coinsPage.Size = UDim2.new(1, 0, 1, 0)
        coinsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
        coinsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
        coinsPage.ScrollBarThickness = px(4)
        coinsPage.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
        coinsPage.BorderSizePixel = 0
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

        -----------------------------------------------------------------------
        -- KEY PACKS section (within the same Currency tab)
        -----------------------------------------------------------------------
        local KEY_BLUE = Color3.fromRGB(100, 200, 255)

        -- Spacer between coin packs and key packs
        local keySpacer = Instance.new("Frame")
        keySpacer.Name = "KeySpacer"
        keySpacer.BackgroundTransparency = 1
        keySpacer.Size = UDim2.new(1, 0, 0, px(6))
        keySpacer.LayoutOrder = 100
        keySpacer.Parent = coinsPage

        -- Key packs header
        local keysHeader = Instance.new("TextLabel")
        keysHeader.Name = "KeysHeader"
        keysHeader.BackgroundTransparency = 1
        keysHeader.Font = Enum.Font.GothamBlack
        keysHeader.Text = "Key Packs"
        keysHeader.TextColor3 = KEY_BLUE
        keysHeader.TextSize = math.max(16, math.floor(px(20)))
        keysHeader.Size = UDim2.new(1, 0, 0, px(30))
        keysHeader.TextXAlignment = Enum.TextXAlignment.Left
        keysHeader.LayoutOrder = 101
        keysHeader.Parent = coinsPage

        local keysAccent = Instance.new("Frame")
        keysAccent.Name = "KeyAccentBar"
        keysAccent.BackgroundColor3 = KEY_BLUE
        keysAccent.BackgroundTransparency = 0.3
        keysAccent.Size = UDim2.new(1, 0, 0, px(2))
        keysAccent.BorderSizePixel = 0
        keysAccent.LayoutOrder = 102
        keysAccent.Parent = coinsPage

        local keyPromptDebounce = false

        if KeyProducts and KeyProducts.Packs then
            for i, pack in ipairs(KeyProducts.Packs) do
                local card = Instance.new("Frame")
                card.Name = "KeyPack_" .. tostring(i)
                card.Size = UDim2.new(1, -px(4), 0, px(115))
                card.BackgroundColor3 = CARD_BG
                card.BorderSizePixel = 0
                card.LayoutOrder = 102 + i
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

                -- Key icon (diamond/key glyph circle)
                local keyIconSize = px(54)
                local keyCircle = Instance.new("Frame")
                keyCircle.Name = "KeyIcon"
                keyCircle.Size = UDim2.new(0, keyIconSize, 0, keyIconSize)
                keyCircle.AnchorPoint = Vector2.new(0, 0.5)
                keyCircle.Position = UDim2.new(0, 0, 0.5, 0)
                keyCircle.BackgroundColor3 = KEY_BLUE
                keyCircle.BackgroundTransparency = 0.15
                keyCircle.BorderSizePixel = 0
                keyCircle.ZIndex = 252
                keyCircle.Parent = card
                local kcc = Instance.new("UICorner")
                kcc.CornerRadius = UDim.new(0.5, 0)
                kcc.Parent = keyCircle

                local keyGlyph = Instance.new("TextLabel")
                keyGlyph.Name = "KeyGlyph"
                keyGlyph.BackgroundTransparency = 1
                keyGlyph.Font = Enum.Font.GothamBold
                keyGlyph.Text = "\u{1F511}"
                keyGlyph.TextSize = math.max(18, math.floor(px(24)))
                keyGlyph.TextColor3 = WHITE
                keyGlyph.Size = UDim2.new(1, 0, 1, 0)
                keyGlyph.ZIndex = 253
                keyGlyph.Parent = keyCircle

                -- Key amount label
                local keyLabel = Instance.new("TextLabel")
                keyLabel.Name = "KeyAmount"
                keyLabel.Size = UDim2.new(0.50, -keyIconSize, 0.50, 0)
                keyLabel.Position = UDim2.new(0, keyIconSize + px(16), 0, px(10))
                keyLabel.BackgroundTransparency = 1
                keyLabel.Font = Enum.Font.GothamBlack
                keyLabel.Text = tostring(pack.Keys) .. " Keys"
                keyLabel.TextColor3 = KEY_BLUE
                keyLabel.TextSize = math.max(18, math.floor(px(22)))
                keyLabel.TextXAlignment = Enum.TextXAlignment.Left
                keyLabel.ZIndex = 252
                keyLabel.Parent = card

                -- Pack name subtitle
                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "PackName"
                nameLabel.Size = UDim2.new(0.50, -keyIconSize, 0.35, 0)
                nameLabel.Position = UDim2.new(0, keyIconSize + px(16), 0.50, px(4))
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
                    if keyPromptDebounce then return end

                    local productId = pack.ProductId
                    if not productId or productId == 0 then
                        warn("[ShopUI][Keys] Product ID not set for '" .. pack.Name .. "'. Set it in KeyProducts.lua")
                        return
                    end

                    keyPromptDebounce = true
                    print("[ShopUI][Keys] Prompting purchase:", pack.Name, "ProductId:", productId)

                    local ok, err = pcall(function()
                        MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
                    end)
                    if not ok then
                        warn("[ShopUI][Keys] PromptProductPurchase failed:", tostring(err))
                    end

                    task.delay(2, function()
                        keyPromptDebounce = false
                    end)
                end)
            end
        end

        contentPages["currency"] = coinsPage
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
        local contentH = contentContainer.AbsoluteSize.Y
        local sidebarH = sidebar.AbsoluteSize.Y
        local minH = px(400)
        root.Size = UDim2.new(1, 0, 0, math.max(contentH, sidebarH, minH))
    end
    contentContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRootHeight)
    sidebar:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRootHeight)
    task.defer(updateRootHeight)

    root.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            cleanup()
        end
    end)

    return root
end

return ShopUI
