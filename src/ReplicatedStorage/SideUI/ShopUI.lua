--------------------------------------------------------------------------------
-- ShopUI.lua  –  Sectioned shop UI (fixed header handled by SideUI)
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- palette (matches BoostsUI / QuestsUI deep-blue / gold theme)
local CARD_BG      = Color3.fromRGB(26, 30, 48)
local CARD_OWNED   = Color3.fromRGB(22, 38, 34)
local CARD_STROKE  = Color3.fromRGB(55, 62, 95)
local ICON_BG      = Color3.fromRGB(16, 18, 30)
local GOLD         = Color3.fromRGB(255, 215, 60)
local WHITE        = Color3.fromRGB(245, 245, 252)
local DIM_TEXT     = Color3.fromRGB(145, 150, 175)
local BTN_BUY      = Color3.fromRGB(48, 55, 82)
local BTN_STROKE_C = Color3.fromRGB(90, 100, 140)
local GREEN_BTN    = Color3.fromRGB(35, 190, 75)
local GREEN_GLOW   = Color3.fromRGB(50, 230, 110)
local RED_TEXT     = Color3.fromRGB(255, 80, 80)
local DISABLED_BG  = Color3.fromRGB(35, 38, 52)

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ShopUI = {}

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

local function safeRequireAssetCodes()
    local ok, mod = pcall(function() return ReplicatedStorage:FindFirstChild("AssetCodes") end)
    if ok and mod and mod:IsA("ModuleScript") then
        local suc, t = pcall(function() return require(mod) end)
        if suc and type(t) == "table" then return t end
    end
    return nil
end

local AssetCodes = safeRequireAssetCodes()

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

    local root = Instance.new("Frame")
    root.Name = "ShopUI"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 0, 0)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.ZIndex = 240
    root.Parent = parent

    -- stack sections vertically with spacing
    local rootLayout = Instance.new("UIListLayout")
    rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rootLayout.Padding = UDim.new(0, px(16))
    rootLayout.Parent = root

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(16))
    rootPad.PaddingLeft = UDim.new(0, px(8))
    rootPad.PaddingRight = UDim.new(0, px(8))
    rootPad.Parent = root

    -- Ensure we have AssetCodes cached (safe)
    AssetCodes = AssetCodes or safeRequireAssetCodes()

    -- Build sections (these live inside the modal's scrolling content provided by SideUI)
    local rangedSection, rangedGrid = makeSection(root, "Ranged", "Ranged Weapons")
    local meleeSection, meleeGrid = makeSection(root, "Melee", "Melee Weapons")
    local specialSection, specialGrid = makeSection(root, "Special", "Special Weapons")
    local coinsSection, coinsGrid = makeSection(root, "Coins", "Coins")

    -- explicit stacking order for sections (Melee first, Ranged second)
    meleeSection.LayoutOrder = 1
    rangedSection.LayoutOrder = 2
    specialSection.LayoutOrder = 3
    coinsSection.LayoutOrder = 4

    -- Populate melee weapons section (Stick is the free starter)
    makeItem(meleeGrid, "Stick", "Stick", 0, "Stick", coinApi, inventoryApi, "Melee")
    makeItem(meleeGrid, "Dagger", "Dagger", 30, "Dagger", coinApi, inventoryApi, "Melee")
    makeItem(meleeGrid, "Sword", "Sword", 30, "Sword", coinApi, inventoryApi, "Melee")
    makeItem(meleeGrid, "Spear", "Spear", 30, "Spear", coinApi, inventoryApi, "Melee")

    -- Populate ranged weapons section (Slingshot is the free starter)
    makeItem(rangedGrid, "Slingshot", "Slingshot", 0, "Slingshot", coinApi, inventoryApi, "Ranged")
    makeItem(rangedGrid, "Shortbow", "Shortbow", 20, "Shortbow", coinApi, inventoryApi, "Ranged")
    makeItem(rangedGrid, "Longbow", "Longbow", 30, "Longbow", coinApi, inventoryApi, "Ranged")
    makeItem(rangedGrid, "Xbow", "Xbow", 40, "Xbow", coinApi, inventoryApi, "Ranged")

    -- Special/Coin sections can be populated similarly by calling makeItem on those grids

    return root
end

return ShopUI
