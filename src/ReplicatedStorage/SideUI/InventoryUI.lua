--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Sectioned inventory (Melee · Ranged)
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
    { id = "skins",   icon = "\u{2726}", label = "Skins",   order = 3 },
    { id = "effects", icon = "\u{2738}", label = "Effects", order = 4 },
}
print("[InventoryUI] Inventory categories loaded: Weapons, Boosts, Skins, Effects (Emotes removed)")

-- Debug: final Inventory categories after Trails removal
do
    local ids = {}
    for _, def in ipairs(TAB_DEFS) do
        table.insert(ids, def.id)
    end
    local joined = table.concat(ids, ",")
    print("[CategoryDebug][Inventory] final categories:", joined)
    print("[CategoryDebug][Inventory] trails present:", tostring(string.find(joined, "trails", 1, true) ~= nil))
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
    effects = { active = Color3.fromRGB(214, 138, 206), inactive = Color3.fromRGB(136, 90, 131) },
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
    end

    return root
end

local InventoryUI = {}

local ShopUIModule = nil
pcall(function()
    ShopUIModule = require(script.Parent.ShopUI)
end)

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

    -- Tab mapping: Inventory tab -> Shop tab
    local INV_TO_SHOP_TAB = {
        weapons = "weapons",
        boosts  = "boosts",
        skins   = "skins",
        effects = "effects",
    }

    ---------------------------------------------------------------------------
    -- Helper: create a "Visit Shop" button at the bottom of a content page
    ---------------------------------------------------------------------------
    local function createShopNavButton(parentPage, layoutOrder)
        -- Wrapper frame: full-width row so the UIListLayout positions it,
        -- with top padding for breathing room below item cards.
        local shopNavWrap = Instance.new("Frame")
        shopNavWrap.Name = "ShopNavWrap"
        shopNavWrap.BackgroundTransparency = 1
        shopNavWrap.Size = UDim2.new(1, 0, 0, px(38) + px(12))
        shopNavWrap.LayoutOrder = layoutOrder or 9999
        shopNavWrap.ZIndex = 260
        shopNavWrap.Parent = parentPage

        local shopNavBtn = Instance.new("TextButton")
        shopNavBtn.Name = "ShopNavBtn"
        shopNavBtn.AutoButtonColor = false
        shopNavBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        shopNavBtn.BorderSizePixel = 0
        shopNavBtn.Font = Enum.Font.GothamBold
        shopNavBtn.Text = "\u{1F6D2}  Browse Shop"
        shopNavBtn.TextColor3 = UITheme.GOLD_DIM
        shopNavBtn.TextSize = math.max(13, math.floor(px(14)))
        shopNavBtn.AutomaticSize = Enum.AutomaticSize.X
        shopNavBtn.Size = UDim2.new(0, 0, 0, px(38))
        shopNavBtn.AnchorPoint = Vector2.new(0.5, 0)
        shopNavBtn.Position = UDim2.new(0.5, 0, 0, px(12))
        shopNavBtn.ZIndex = 260
        shopNavBtn.Parent = shopNavWrap

        local btnPadding = Instance.new("UIPadding")
        btnPadding.PaddingLeft = UDim.new(0, px(20))
        btnPadding.PaddingRight = UDim.new(0, px(20))
        btnPadding.Parent = shopNavBtn

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(8))
        btnCorner.Parent = shopNavBtn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = UITheme.GOLD_DIM
        btnStroke.Thickness = 1.2
        btnStroke.Transparency = 0.45
        btnStroke.Parent = shopNavBtn

        -- Hover effects
        shopNavBtn.MouseEnter:Connect(function()
            TweenService:Create(shopNavBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play()
            TweenService:Create(btnStroke, TWEEN_QUICK, {Transparency = 0.15}):Play()
        end)
        shopNavBtn.MouseLeave:Connect(function()
            TweenService:Create(shopNavBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play()
            TweenService:Create(btnStroke, TWEEN_QUICK, {Transparency = 0.45}):Play()
        end)

        -- Click: open Shop to matching tab
        shopNavBtn.MouseButton1Click:Connect(function()
            local targetTab = INV_TO_SHOP_TAB[currentTab] or "weapons"
            print(string.format("[InventoryUI] Shop button clicked | inventoryTab=%s -> shopTab=%s", tostring(currentTab), tostring(targetTab)))

            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then
                mc.OpenMenu("Shop")
                -- Set the Shop to the matching tab after it opens
                if ShopUIModule and ShopUIModule.setActiveTab then
                    ShopUIModule.setActiveTab(targetTab)
                end
            end
        end)

        return shopNavBtn
    end

    ---------------------------------------------------------------------------
    -- Helper: create an empty-state card for a category (inline in page)
    ---------------------------------------------------------------------------
    local function createEmptyStateInline(parentPage, tabId, layoutOrder)
        local emptyWrap = Instance.new("Frame")
        emptyWrap.Name = "EmptyState"
        emptyWrap.BackgroundTransparency = 1
        emptyWrap.Size = UDim2.new(1, 0, 0, px(160))
        emptyWrap.LayoutOrder = layoutOrder or 500
        emptyWrap.Parent = parentPage

        local card = Instance.new("Frame")
        card.Name = "EmptyCard"
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(0.7, 0, 0, px(130))
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.new(0.5, 0, 0.5, 0)
        card.Parent = emptyWrap

        local cr = Instance.new("UICorner")
        cr.CornerRadius = UDim.new(0, px(14))
        cr.Parent = card

        local st = Instance.new("UIStroke")
        st.Color = CARD_STROKE
        st.Thickness = 1.2
        st.Transparency = 0.3
        st.Parent = card

        local line1 = Instance.new("TextLabel")
        line1.BackgroundTransparency = 1
        line1.Font = Enum.Font.GothamMedium
        line1.Text = "You don't own any items in this category yet."
        line1.TextColor3 = DIM_TEXT
        line1.TextSize = math.max(13, math.floor(px(14)))
        line1.TextWrapped = true
        line1.Size = UDim2.new(0.85, 0, 0, px(40))
        line1.AnchorPoint = Vector2.new(0.5, 0)
        line1.Position = UDim2.new(0.5, 0, 0, px(28))
        line1.TextXAlignment = Enum.TextXAlignment.Center
        line1.Parent = card

        local line2 = Instance.new("TextLabel")
        line2.BackgroundTransparency = 1
        line2.Font = Enum.Font.GothamMedium
        line2.Text = "Visit the shop to unlock more."
        line2.TextColor3 = UITheme.GOLD_DIM
        line2.TextSize = math.max(11, math.floor(px(12)))
        line2.Size = UDim2.new(0.85, 0, 0, px(20))
        line2.AnchorPoint = Vector2.new(0.5, 0)
        line2.Position = UDim2.new(0.5, 0, 0, px(74))
        line2.TextXAlignment = Enum.TextXAlignment.Center
        line2.Parent = card

        return emptyWrap
    end

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

        if def.id == "weapons" or def.id == "boosts" then
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
        else
            local custom = buildCustomTabIcon(btn, def.id)
            setTabIconTint(custom, getCustomTabIconColor(def.id, false))
        end

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

        print(string.format("[EmptyStateIconDebug][Inventory] category=%s iconRef=%s exists=%s", tostring(tabId), iconRef, tostring(iconVisual ~= nil)))
        task.defer(function()
            if not iconVisual or not iconVisual.Parent then
                print(string.format("[EmptyStateIconDebug][Inventory] category=%s finalSize=n/a visible=false", tostring(tabId)))
                return
            end
            local size = iconVisual.AbsoluteSize
            print(string.format("[EmptyStateIconDebug][Inventory] category=%s finalSize=%dx%d visible=%s", tostring(tabId), size.X, size.Y, tostring(iconVisual.Visible)))
        end)

        return iconVisual
    end

    local function setActiveTab(tabId)
        currentTab = tabId
        print(string.format("[InventoryUI] Active tab=%s", tostring(tabId)))
        print(string.format("[EmptyStateIconDebug][Inventory] selectedCategory=%s", tostring(tabId)))
        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar = btn:FindFirstChild("ActiveBar")
            local icon = btn:FindFirstChild("Icon")
            local iconCustom = btn:FindFirstChild("IconCustom")
            local label = btn:FindFirstChild("Label")
            local stroke = btn:FindFirstChildOfClass("UIStroke")

            if bar then bar.BackgroundTransparency = active and 0 or 1 end
            if icon then icon.TextColor3 = active and GOLD or DIM_TEXT end
            if iconCustom then setTabIconTint(iconCustom, getCustomTabIconColor(id, active)) end
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
            print(string.format("[CategoryDebug][Inventory] tab clicked=%s", tostring(id)))
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

    -- Fetch weapon instances from server (crate-obtained weapons)
    local weaponInstances = {}
    pcall(function()
        local getInvRF = ReplicatedStorage:FindFirstChild("GetWeaponInventory")
        if getInvRF and getInvRF:IsA("RemoteFunction") then
            local result = getInvRF:InvokeServer()
            if type(result) == "table" then
                weaponInstances = result
            end
        end
    end)

    -- CrateConfig for rarity colors and developer IDs
    local CrateConfig = nil
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
        if mod and mod:IsA("ModuleScript") then
            CrateConfig = require(mod)
        end
    end)

    local isDeveloper = false
    if CrateConfig and CrateConfig.DeveloperUserIds then
        local localPlayer = Players.LocalPlayer
        if localPlayer then
            for _, uid in ipairs(CrateConfig.DeveloperUserIds) do
                if uid == localPlayer.UserId then
                    isDeveloper = true
                    break
                end
            end
        end
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
    meleeSection.LayoutOrder = 1
    rangedSection.LayoutOrder = 2

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

    -- Empty state label for boosts (created once, visibility toggled)
    local boostsEmptyState = createEmptyStateInline(boostsPage, "boosts", 500)
    boostsEmptyState.Visible = false

    local function refreshBoostCards()
        local visibleCount = 0
        for _, def in ipairs(boostDefs) do
            local refs = boostCards[def.Id]
            local state = boostStates[def.Id] or {}
            if refs then
                local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
                local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + timeDelta
                local active = expiresAt > os.time()

                -- Only show cards for boosts the player owns or has active
                if owned > 0 or active then
                    refs.card.Parent = boostsPage
                    visibleCount = visibleCount + 1
                else
                    refs.card.Parent = nil  -- Remove from layout
                end

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
                end
            end
        end
        -- Show/hide empty state
        boostsEmptyState.Visible = (visibleCount == 0)
        print(string.format("[InventoryUI] Boosts refresh | ownedVisible=%d", visibleCount))
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

    -- Shop button at the bottom of boosts page
    createShopNavButton(boostsPage, 9999)

    contentPages.boosts = boostsPage

    local function makeOwnedPlaceholderPage(name, tabId, iconGlyph, titleText)
        local page = Instance.new("Frame")
        page.Name = name
        page.BackgroundTransparency = 1
        page.Size = UDim2.new(1, 0, 0, px(300))
        page.Visible = false
        page.Parent = contentContainer

        local card = Instance.new("Frame")
        card.Name = "PlaceholderCard"
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(0.6, 0, 0, px(190))
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.new(0.5, 0, 0.5, 0)
        card.Parent = page

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, px(16))
        cardCorner.Parent = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color = CARD_STROKE
        cardStroke.Thickness = 1.4
        cardStroke.Transparency = 0.25
        cardStroke.Parent = card

        attachEmptyStateCategoryIcon(card, tabId, iconGlyph)

        local title = Instance.new("TextLabel")
        title.Name = "PlaceholderTitle"
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.Text = titleText
        title.TextColor3 = GOLD
        title.TextSize = math.max(16, math.floor(px(18)))
        title.Size = UDim2.new(1, 0, 0, px(26))
        title.Position = UDim2.new(0, 0, 0.46, 0)
        title.TextXAlignment = Enum.TextXAlignment.Center
        title.Parent = card

        local subtitle = Instance.new("TextLabel")
        subtitle.Name = "PlaceholderSub"
        subtitle.BackgroundTransparency = 1
        subtitle.Font = Enum.Font.GothamMedium
        subtitle.Text = "You don't own any items in this category yet.\nVisit the shop to unlock more."
        subtitle.TextColor3 = DIM_TEXT
        subtitle.TextSize = math.max(12, math.floor(px(13)))
        subtitle.Size = UDim2.new(1, -px(20), 0, px(36))
        subtitle.Position = UDim2.new(0, px(10), 0.58, 0)
        subtitle.TextWrapped = true
        subtitle.TextXAlignment = Enum.TextXAlignment.Center
        subtitle.Parent = card

        -- Shop button below the placeholder card
        local shopBtnWrap = Instance.new("Frame")
        shopBtnWrap.Name = "ShopBtnWrap"
        shopBtnWrap.BackgroundTransparency = 1
        shopBtnWrap.Size = UDim2.new(1, 0, 0, px(50))
        shopBtnWrap.Position = UDim2.new(0, 0, 1, px(10))
        shopBtnWrap.Parent = page
        createShopNavButton(shopBtnWrap, 1)

        contentPages[tabId] = page
        return page
    end

    makeOwnedPlaceholderPage("SkinsPage", "skins", "\u{2726}", "SKINS")

    ---------------------------------------------------------------------------
    -- EFFECTS inventory page (equippable dash trail effects)
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
                getOwned    = ef:FindFirstChild("GetOwnedEffects"),
                equip       = ef:FindFirstChild("EquipEffect"),
                getEquipped = ef:FindFirstChild("GetEquippedEffects"),
                changed     = ef:FindFirstChild("EquippedEffectsChanged"),
            }
            return effectRemotes
        end

        local allTrailDefs = EffectDefs and EffectDefs.GetBySubType("DashTrail") or {}

        if #allTrailDefs > 0 then
            local effectsPage = Instance.new("Frame")
            effectsPage.Name                = "EffectsPage"
            effectsPage.BackgroundTransparency = 1
            effectsPage.Size                = UDim2.new(1, 0, 0, 0)
            effectsPage.AutomaticSize       = Enum.AutomaticSize.Y
            effectsPage.Visible             = false
            effectsPage.Parent              = contentContainer

            local epLayout = Instance.new("UIListLayout")
            epLayout.SortOrder = Enum.SortOrder.LayoutOrder
            epLayout.Padding   = UDim.new(0, px(16))
            epLayout.Parent    = effectsPage

            local trailSection, trailGrid = makeSection(effectsPage, "DashTrails", "Dash Trails")
            trailSection.LayoutOrder = 1

            -- Track owned and equipped state
            local ownedSet = {}
            local equippedTrailId = nil
            local effectEquipBtns = {} -- effectId -> { btn, stroke, card, cardStroke }
            local effectsEmptyState = nil  -- forward-declare; created after card loop

            local function refreshAllEffectBtns()
                local visibleCount = 0
                for eid, info in pairs(effectEquipBtns) do
                    local isOwned = ownedSet[eid] or info.isFree
                    -- Only show cards for owned effects
                    if isOwned then
                        info.card.Parent = trailGrid
                        visibleCount = visibleCount + 1
                    else
                        info.card.Parent = nil  -- Remove unowned from layout
                    end

                    if equippedTrailId == eid then
                        info.btn.Text = "\u{2714} EQUIPPED"
                        info.btn.BackgroundColor3 = DISABLED_BG
                        info.btn.TextColor3 = GREEN_GLOW
                        info.stroke.Color = GREEN_GLOW
                        info.stroke.Transparency = 0.45
                        if info.card then
                            info.card.BackgroundColor3 = CARD_EQUIPPED
                        end
                        if info.cardStroke then
                            info.cardStroke.Color = GREEN_GLOW
                            info.cardStroke.Thickness = 1.8
                            info.cardStroke.Transparency = 0.3
                        end
                    elseif isOwned then
                        info.btn.Text = "EQUIP"
                        info.btn.BackgroundColor3 = BTN_BG
                        info.btn.TextColor3 = WHITE
                        info.stroke.Color = BTN_STROKE_C
                        info.stroke.Transparency = 0.25
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
                -- Show/hide effects empty state
                if effectsEmptyState then
                    effectsEmptyState.Visible = (visibleCount == 0)
                end
                print(string.format("[InventoryUI] Effects refresh | ownedVisible=%d", visibleCount))
            end

            -- Async fetch owned + equipped
            task.spawn(function()
                local remotes = ensureEffectRemotes()
                if not remotes then return end
                -- Fetch owned
                if remotes.getOwned and remotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return remotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then
                        for _, id in ipairs(list) do ownedSet[id] = true end
                    end
                end
                -- Fetch equipped
                if remotes.getEquipped and remotes.getEquipped:IsA("RemoteFunction") then
                    local ok, equipped = pcall(function() return remotes.getEquipped:InvokeServer() end)
                    if ok and type(equipped) == "table" then
                        equippedTrailId = equipped.DashTrail
                        print("[InventoryUI] loaded equipped DashTrail:", equippedTrailId or "none")
                    end
                end
                refreshAllEffectBtns()

                -- Listen for server-pushed equip changes
                if remotes.changed and remotes.changed:IsA("RemoteEvent") then
                    remotes.changed.OnClientEvent:Connect(function(newEquipped)
                        if type(newEquipped) == "table" then
                            equippedTrailId = newEquipped.DashTrail
                            refreshAllEffectBtns()
                        end
                    end)
                end
            end)

            -- Build cards for each trail effect
            for _, def in ipairs(allTrailDefs) do
                local effectId    = def.Id
                local displayName = def.DisplayName or effectId
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)
                local description = def.Description or ""
                local isFree      = def.IsFree or false
                local isRainbow   = def.IsRainbow == true
                local isEpic      = (def.Rarity == "Epic")

                local card = Instance.new("Frame")
                card.Name = "EffectCard_" .. effectId
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0)
                card.AutomaticSize = Enum.AutomaticSize.Y
                card.Parent = trailGrid
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, px(12))
                corner.Parent = card
                local stroke = Instance.new("UIStroke")
                stroke.Color = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                stroke.Thickness = isEpic and 1.6 or 1.2
                stroke.Transparency = isEpic and 0.2 or 0.35
                stroke.Parent = card
                local cardPad = Instance.new("UIPadding")
                cardPad.PaddingTop    = UDim.new(0, px(8))
                cardPad.PaddingBottom = UDim.new(0, px(8))
                cardPad.PaddingLeft   = UDim.new(0, px(8))
                cardPad.PaddingRight  = UDim.new(0, px(8))
                cardPad.Parent = card

                -- LEFT: color swatch
                local leftBox = Instance.new("Frame")
                leftBox.Name = "LeftBox"
                leftBox.Size = UDim2.new(0.45, 0, 1, 0)
                leftBox.Position = UDim2.new(0, 0, 0, 0)
                leftBox.BackgroundColor3 = ICON_BG
                leftBox.ZIndex = 251
                leftBox.Parent = card
                local lCrn = Instance.new("UICorner")
                lCrn.CornerRadius = UDim.new(0, px(10))
                lCrn.Parent = leftBox
                local lStk = Instance.new("UIStroke")
                lStk.Color = CARD_STROKE; lStk.Thickness = 1; lStk.Transparency = 0.5
                lStk.Parent = leftBox

                -- Color swatch
                local swatch = Instance.new("Frame")
                swatch.Name = "ColorSwatch"
                swatch.Size = UDim2.new(0.6, 0, 0.15, 0)
                swatch.AnchorPoint = Vector2.new(0.5, 0.5)
                swatch.Position = UDim2.new(0.5, 0, 0.4, 0)
                swatch.BackgroundColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                swatch.BorderSizePixel = 0
                swatch.ZIndex = 252
                swatch.Parent = leftBox
                local swCrn = Instance.new("UICorner")
                swCrn.CornerRadius = UDim.new(0.5, 0)
                swCrn.Parent = swatch
                if isRainbow and def.TrailColorSequence then
                    local grad = Instance.new("UIGradient")
                    grad.Color = def.TrailColorSequence
                    grad.Parent = swatch
                end
                local swStk = Instance.new("UIStroke")
                swStk.Color = isRainbow and Color3.fromRGB(200, 160, 255) or effectColor
                swStk.Thickness = px(2); swStk.Transparency = 0.3
                swStk.Parent = swatch

                local trailGlyph = Instance.new("TextLabel")
                trailGlyph.Name = "TrailGlyph"
                trailGlyph.Text = "\u{2550}\u{2550}\u{2550}"
                trailGlyph.Font = Enum.Font.GothamBold
                trailGlyph.TextColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                trailGlyph.TextScaled = true
                trailGlyph.BackgroundTransparency = 1
                trailGlyph.Size = UDim2.new(0.8, 0, 0.2, 0)
                trailGlyph.AnchorPoint = Vector2.new(0.5, 0)
                trailGlyph.Position = UDim2.new(0.5, 0, 0.6, 0)
                trailGlyph.ZIndex = 252
                trailGlyph.Parent = leftBox
                if isRainbow and def.TrailColorSequence then
                    local glyphGrad = Instance.new("UIGradient")
                    glyphGrad.Color = def.TrailColorSequence
                    glyphGrad.Parent = trailGlyph
                end

                -- RIGHT: name + equip button
                local rightBox = Instance.new("Frame")
                rightBox.Name = "RightBox"
                rightBox.Size = UDim2.new(0.52, 0, 1, 0)
                rightBox.Position = UDim2.new(0.48, 0, 0, 0)
                rightBox.BackgroundTransparency = 1
                rightBox.ZIndex = 251
                rightBox.Parent = card

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Name = "ItemName"
                nameLabel.Size = UDim2.new(0.95, 0, 0.28, 0)
                nameLabel.Position = UDim2.new(0.04, 0, 0.08, 0)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Font = Enum.Font.GothamBold
                nameLabel.Text = displayName
                nameLabel.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                nameLabel.TextSize = math.max(13, math.floor(px(15)))
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.ZIndex = 252
                nameLabel.Parent = rightBox

                local descLabel = Instance.new("TextLabel")
                descLabel.Name = "Desc"
                descLabel.Size = UDim2.new(0.95, 0, 0.22, 0)
                descLabel.Position = UDim2.new(0.04, 0, 0.36, 0)
                descLabel.BackgroundTransparency = 1
                descLabel.Font = Enum.Font.GothamMedium
                descLabel.Text = isFree and "Free (default)" or description
                descLabel.TextColor3 = DIM_TEXT
                descLabel.TextSize = math.max(10, math.floor(px(11)))
                descLabel.TextXAlignment = Enum.TextXAlignment.Left
                descLabel.TextWrapped = true
                descLabel.ZIndex = 252
                descLabel.Parent = rightBox

                -- Equip button
                local equipBtn = Instance.new("TextButton")
                equipBtn.Name = "EquipBtn"
                equipBtn.Size = UDim2.new(0.85, 0, 0.26, 0)
                equipBtn.AnchorPoint = Vector2.new(0.5, 1)
                equipBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
                equipBtn.BackgroundColor3 = BTN_BG
                equipBtn.BorderSizePixel = 0
                equipBtn.AutoButtonColor = false
                equipBtn.Font = Enum.Font.GothamBold
                equipBtn.Text = "EQUIP"
                equipBtn.TextColor3 = WHITE
                equipBtn.TextSize = math.max(13, math.floor(px(14)))
                equipBtn.ZIndex = 253
                equipBtn.Parent = rightBox
                local eCrn = Instance.new("UICorner")
                eCrn.CornerRadius = UDim.new(0, px(8))
                eCrn.Parent = equipBtn
                local eStk = Instance.new("UIStroke")
                eStk.Color = BTN_STROKE_C
                eStk.Thickness = 1.2
                eStk.Transparency = 0.25
                eStk.Parent = equipBtn

                effectEquipBtns[effectId] = { btn = equipBtn, stroke = eStk, card = card, cardStroke = stroke, isFree = isFree }

                -- Hover effects
                if not game:GetService("UserInputService").TouchEnabled then
                    equipBtn.MouseEnter:Connect(function()
                        if (ownedSet[effectId] or isFree) and equippedTrailId ~= effectId then
                            TweenService:Create(equipBtn, TWEEN_QUICK, { BackgroundColor3 = Color3.fromRGB(35, 190, 75) }):Play()
                        end
                    end)
                    equipBtn.MouseLeave:Connect(function()
                        if (ownedSet[effectId] or isFree) and equippedTrailId ~= effectId then
                            TweenService:Create(equipBtn, TWEEN_QUICK, { BackgroundColor3 = BTN_BG }):Play()
                        end
                    end)
                end

                -- Equip click handler
                equipBtn.MouseButton1Click:Connect(function()
                    if not ownedSet[effectId] and not isFree then return end
                    if equippedTrailId == effectId then return end

                    local remotes = ensureEffectRemotes()
                    if remotes and remotes.equip and remotes.equip:IsA("RemoteEvent") then
                        pcall(function() remotes.equip:FireServer(effectId, "DashTrail") end)
                    end

                    equippedTrailId = effectId
                    print("[InventoryUI] Equipped DashTrail =", effectId)
                    refreshAllEffectBtns()
                end)
            end -- end for each trail def

            -- Empty state for effects (visibility managed in refreshAllEffectBtns)
            effectsEmptyState = createEmptyStateInline(effectsPage, "effects", 500)
            effectsEmptyState.Visible = false

            -- Shop button at the bottom of effects page
            createShopNavButton(effectsPage, 9999)

            contentPages["effects"] = effectsPage
        else
            makeOwnedPlaceholderPage("EffectsPage", "effects", "\u{2738}", "EFFECTS")
        end
    end

    print("[InventoryUI] all placeholder pages created (Emotes removed)")

    -- [REMOVED] Emotes inventory page -- emotes are now managed via the dedicated E wheel
    print("[InventoryUI] Emotes category removed from Inventory sidebar")

    local GREEN_BTN = Color3.fromRGB(35, 190, 75)
    local GREEN_BTN_STR = Color3.fromRGB(50, 230, 110)
    -- Restore equipped state from inventory API if available (per-category)
    local equippedState = { Melee = nil, Ranged = nil }
    if inventoryApi and inventoryApi.GetEquipped then
        pcall(function()
            equippedState.Melee = inventoryApi:GetEquipped("Melee")
            equippedState.Ranged = inventoryApi:GetEquipped("Ranged")
            -- normalize legacy equipped references
            if type(equippedState.Melee) == "string" and equippedState.Melee:lower() == "stick" then
                equippedState.Melee = "Wooden Sword"
            end
            if type(equippedState.Ranged) == "string" and equippedState.Ranged:lower() == "stick" then
                equippedState.Ranged = "Wooden Sword"
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

    -- Populate sections with owned items (legacy direct-buy items)
    for _, id in ipairs(items) do
        local cat = classifyItem(id)
        if cat == "Melee" then
            createCard(meleeGrid, id)
        else
            createCard(rangedGrid, id)
        end
    end

    -- Populate sections with weapon instances (crate-obtained)
    local function rarityColor(rarity)
        if CrateConfig and CrateConfig.Rarities and CrateConfig.Rarities[rarity] then
            return CrateConfig.Rarities[rarity].color
        end
        return DIM_TEXT
    end

    local instanceCards = {}
    for instanceId, data in pairs(weaponInstances) do
        if type(data) == "table" and data.weaponName then
            local cat = data.category or classifyItem(data.weaponName)
            local targetGrid = (cat == "Melee") and meleeGrid or rangedGrid

            local card = Instance.new("Frame")
            card.Name = "InstanceCard_" .. instanceId
            card.BackgroundColor3 = CARD_BG
            card.Size = UDim2.new(1, 0, 1, 0)
            card.AutomaticSize = Enum.AutomaticSize.Y
            card.Parent = targetGrid

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, px(12))
            corner.Parent = card

            local cStroke = Instance.new("UIStroke")
            cStroke.Color = rarityColor(data.rarity)
            cStroke.Thickness = 1.4
            cStroke.Transparency = 0.3
            cStroke.Parent = card

            local cardPad = Instance.new("UIPadding")
            cardPad.PaddingTop = UDim.new(0, px(8))
            cardPad.PaddingBottom = UDim.new(0, px(8))
            cardPad.PaddingLeft = UDim.new(0, px(8))
            cardPad.PaddingRight = UDim.new(0, px(8))
            cardPad.Parent = card

            -- Rarity bar at top
            local rBar = Instance.new("Frame")
            rBar.BackgroundColor3 = rarityColor(data.rarity)
            rBar.BackgroundTransparency = 0.3
            rBar.Size = UDim2.new(1, 0, 0, px(3))
            rBar.Position = UDim2.new(0, 0, 0, 0)
            rBar.BorderSizePixel = 0
            rBar.ZIndex = 253
            rBar.Parent = card
            local rBarCr = Instance.new("UICorner")
            rBarCr.CornerRadius = UDim.new(0, px(3))
            rBarCr.Parent = rBar

            local leftBox = Instance.new("Frame")
            leftBox.Name = "LeftBox"
            leftBox.Size = UDim2.new(0.45, 0, 1, 0)
            leftBox.BackgroundColor3 = ICON_BG
            leftBox.ZIndex = 251
            leftBox.Parent = card
            local lCorner = Instance.new("UICorner")
            lCorner.CornerRadius = UDim.new(0, px(10))
            lCorner.Parent = leftBox
            local lStroke = Instance.new("UIStroke")
            lStroke.Color = CARD_STROKE
            lStroke.Thickness = 1
            lStroke.Transparency = 0.5
            lStroke.Parent = leftBox

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
                    local img = AssetCodes.Get(tostring(data.weaponName))
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

            -- Rarity label
            local rarityLabel = Instance.new("TextLabel")
            rarityLabel.BackgroundTransparency = 1
            rarityLabel.Font = Enum.Font.GothamBold
            rarityLabel.Text = data.rarity or "Common"
            rarityLabel.TextColor3 = rarityColor(data.rarity)
            rarityLabel.TextSize = math.max(9, math.floor(px(10)))
            rarityLabel.Size = UDim2.new(1, 0, 0, px(14))
            rarityLabel.Position = UDim2.new(0, 0, 0, px(2))
            rarityLabel.TextXAlignment = Enum.TextXAlignment.Center
            rarityLabel.ZIndex = 252
            rarityLabel.Parent = rightBox

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "ItemName"
            nameLabel.BackgroundTransparency = 1
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextScaled = true
            nameLabel.TextColor3 = WHITE
            nameLabel.TextXAlignment = Enum.TextXAlignment.Center
            nameLabel.Text = tostring(data.weaponName)
            nameLabel.Size = UDim2.new(1, 0, 0, px(24))
            nameLabel.Position = UDim2.new(0, 0, 0, px(16))
            nameLabel.ZIndex = 252
            nameLabel.Parent = rightBox

            -- Instance ID (developer only)
            if isDeveloper then
                local idLabel = Instance.new("TextLabel")
                idLabel.BackgroundTransparency = 1
                idLabel.Font = Enum.Font.Code
                idLabel.Text = instanceId
                idLabel.TextColor3 = DIM_TEXT
                idLabel.TextSize = math.max(8, math.floor(px(8)))
                idLabel.Size = UDim2.new(1, 0, 0, px(12))
                idLabel.Position = UDim2.new(0, 0, 0, px(40))
                idLabel.TextXAlignment = Enum.TextXAlignment.Center
                idLabel.ZIndex = 252
                idLabel.Parent = rightBox
            end

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
            equipBtn.ZIndex = 253
            equipBtn.Parent = rightBox

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, px(10))
            btnCorner.Parent = equipBtn
            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = BTN_STROKE_C
            btnStroke.Thickness = 1.4
            btnStroke.Transparency = 0.25
            btnStroke.Parent = equipBtn

            -- Use the weaponName for equipping (same mechanism as legacy)
            local weaponName = data.weaponName
            allEquipBtns[instanceId] = {
                btn = equipBtn,
                stroke = btnStroke,
                category = cat,
                card = card,
                cardStroke = cStroke,
                weaponName = weaponName,
            }

            equipBtn.MouseButton1Click:Connect(function()
                local rs = ReplicatedStorage
                if cat == "Ranged" then
                    local setRanged = rs:FindFirstChild("SetRangedTool")
                    if setRanged and setRanged:IsA("RemoteEvent") then
                        pcall(function() setRanged:FireServer(weaponName) end)
                    end
                else
                    local setMelee = rs:FindFirstChild("SetMeleeTool")
                    if setMelee and setMelee:IsA("RemoteEvent") then
                        pcall(function() setMelee:FireServer(weaponName) end)
                    end
                end
                equippedState[cat] = instanceId
                if inventoryApi and inventoryApi.SetEquipped then
                    pcall(function() inventoryApi:SetEquipped(cat, instanceId) end)
                end
                refreshAllEquipButtons()
            end)

            equipBtn.MouseEnter:Connect(function()
                local info = allEquipBtns[instanceId]
                local isEquipped = info and equippedState[info.category] == instanceId
                if not isEquipped then
                    pcall(function()
                        TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                    end)
                end
            end)
            equipBtn.MouseLeave:Connect(function()
                local info = allEquipBtns[instanceId]
                local isEquipped = info and equippedState[info.category] == instanceId
                if not isEquipped then
                    pcall(function()
                        TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                    end)
                end
            end)

            table.insert(instanceCards, card)
        end
    end

    -- Count total weapons (legacy + instances)
    local instanceCount = 0
    for _ in pairs(weaponInstances) do instanceCount = instanceCount + 1 end
    local totalWeapons = #items + instanceCount

    -- If no items, show friendly empty state
    if totalWeapons == 0 then
        createEmptyStateInline(weaponsPage, "weapons", 500)
    end

    -- Shop button at the bottom of weapons page
    createShopNavButton(weaponsPage, 9999)

    print(string.format("[InventoryUI] Weapons rendered | legacyCount=%d instanceCount=%d total=%d", #items, instanceCount, totalWeapons))

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
