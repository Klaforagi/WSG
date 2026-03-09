--------------------------------------------------------------------------------
-- ShopUI.lua  –  Sectioned shop UI (fixed header handled by SideUI)
--------------------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 1080
    return math.max(1, math.round(base * screenY / 1080))
end

-- palette (matches SideUI navy/gold theme)
local CARD_BG      = Color3.fromRGB(18, 24, 52)
local CARD_STROKE  = Color3.fromRGB(50, 80, 160)
local ICON_BG      = Color3.fromRGB(14, 18, 40)
local GOLD         = Color3.fromRGB(255, 215, 80)
local WHITE        = Color3.fromRGB(240, 240, 240)
local BLUE_BTN     = Color3.fromRGB(30, 70, 160)
local BLUE_BTN_STR = Color3.fromRGB(80, 140, 220)
local GREEN_BTN    = Color3.fromRGB(30, 130, 60)
local RED_TEXT     = Color3.fromRGB(255, 90, 90)

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
    sectionLayout.Padding = UDim.new(0, px(6))
    sectionLayout.Parent = section

    local sectionPad = Instance.new("UIPadding")
    sectionPad.PaddingTop = UDim.new(0, px(6))
    sectionPad.PaddingBottom = UDim.new(0, px(10))
    sectionPad.PaddingLeft = UDim.new(0, px(8))
    sectionPad.PaddingRight = UDim.new(0, px(8))
    sectionPad.Parent = section

    local header = Instance.new("TextLabel")
    header.Name = "SectionHeader"
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.Text = label
    header.TextColor3 = GOLD
    header.TextSize = math.max(18, math.floor(px(18)))
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Size = UDim2.new(1, 0, 0, px(28))
    header.LayoutOrder = 1
    header.Parent = section

    local grid = Instance.new("Frame")
    grid.Name = sectionId .. "_Grid"
    grid.BackgroundTransparency = 1
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.Parent = section

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.28, 0, 0, px(140)) -- slightly narrower cards
    gridLayout.CellPadding = UDim2.new(0.02, 0, 0, px(10))
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

local function makeItem(gridParent, id, displayName, price, iconKey, coinApi, inventoryApi)
    local card = Instance.new("Frame")
    card.Name = "Item_" .. tostring(id)
    card.BackgroundColor3 = CARD_BG
    card.Size = UDim2.new(1, 0, 1, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.ZIndex = 250
    card.Parent = gridParent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(10))
    corner.Parent = card
    local stroke = Instance.new("UIStroke")
    stroke.Color = CARD_STROKE
    stroke.Thickness = 1.5
    stroke.Transparency = 0.25
    stroke.Parent = card
    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingTop = UDim.new(0, px(6))
    cardPad.PaddingBottom = UDim.new(0, px(6))
    cardPad.PaddingLeft = UDim.new(0, px(6))
    cardPad.PaddingRight = UDim.new(0, px(6))
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
    lCorner.CornerRadius = UDim.new(0, px(8))
    lCorner.Parent = leftBox

    local thumb = Instance.new("ImageLabel")
    thumb.Name = "Thumb"
    thumb.Size = UDim2.new(0.9, 0, 0.9, 0)
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

    local priceRow = Instance.new("Frame")
    priceRow.Name = "PriceRow"
    priceRow.Size = UDim2.new(1, 0, 0.28, 0)
    priceRow.Position = UDim2.new(0, 0, 0.04, 0)
    priceRow.BackgroundTransparency = 1
    priceRow.Parent = rightBox

    local priceLabel = Instance.new("TextLabel")
    priceLabel.Name = "Price"
    priceLabel.Size = UDim2.new(0.62, 0, 1, 0)
    priceLabel.Position = UDim2.new(0, 0, 0, 0)
    priceLabel.BackgroundTransparency = 1
    priceLabel.Font = Enum.Font.GothamBold
    priceLabel.TextScaled = true
    priceLabel.TextColor3 = GOLD
    priceLabel.TextXAlignment = Enum.TextXAlignment.Right
    priceLabel.Text = tostring(price)
    priceLabel.ZIndex = 252
    priceLabel.Parent = priceRow

    local coinIcon = Instance.new("ImageLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.Size = UDim2.new(0.28, 0, 0.80, 0)
    coinIcon.Position = UDim2.new(0.66, 0, 0.5, 0)
    coinIcon.AnchorPoint = Vector2.new(0, 0.5)
    coinIcon.BackgroundTransparency = 1
    coinIcon.ScaleType = Enum.ScaleType.Fit
    coinIcon.ZIndex = 252
    coinIcon.Parent = priceRow
    pcall(function()
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local ci = AssetCodes.Get("Coin")
            if ci and #ci > 0 then coinIcon.Image = ci end
        end
    end)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "ItemName"
    nameLabel.Size = UDim2.new(1, 0, 0.22, 0)
    nameLabel.Position = UDim2.new(0, 0, 0.36, 0)
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
    buyBtn.Size = UDim2.new(0.80, 0, 0.24, 0)
    buyBtn.AnchorPoint = Vector2.new(0.5, 1)
    buyBtn.Position = UDim2.new(0.5, 0, 1, 0)
    buyBtn.BackgroundColor3 = BLUE_BTN
    buyBtn.Font = Enum.Font.GothamBold
    buyBtn.TextScaled = true
    buyBtn.TextColor3 = WHITE
    buyBtn.AutoButtonColor = false
    buyBtn.ZIndex = 253
    buyBtn.Parent = rightBox
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, px(6))
    btnCorner.Parent = buyBtn
    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = BLUE_BTN_STR
    btnStroke.Thickness = 1.2
    btnStroke.Transparency = 0.3
    btnStroke.Parent = buyBtn

    local function refresh()
        local owned = false
        if inventoryApi and inventoryApi.HasItem then
            pcall(function() owned = inventoryApi:HasItem(id) end)
        end
        if owned then
            buyBtn.Text = "OWNED"
            buyBtn.Active = false
            buyBtn.BackgroundColor3 = GREEN_BTN
        else
            buyBtn.Text = "BUY"
            buyBtn.Active = true
            buyBtn.BackgroundColor3 = BLUE_BTN
        end
    end
    refresh()

    buyBtn.MouseButton1Click:Connect(function()
        if not buyBtn.Active then return end
        local owned = false
        if inventoryApi and inventoryApi.HasItem then
            pcall(function() owned = inventoryApi:HasItem(id) end)
        end
        if owned then return end

        local getCoinsFn = ReplicatedStorage:FindFirstChild("GetCoins")
        local coins = nil
        if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
            local ok, res = pcall(function() return getCoinsFn:InvokeServer() end)
            if ok and type(res) == "number" then coins = res end
        end
        if coins == nil and coinApi and coinApi.GetCoins then
            pcall(function() coins = coinApi.GetCoins() end)
        end
        coins = coins or 0

        if coins < price then
            buyBtn.Text = "NOT ENOUGH"
            buyBtn.TextColor3 = RED_TEXT
            task.delay(1.2, function()
                buyBtn.TextColor3 = WHITE
                refresh()
            end)
            return
        end

        if coinApi and coinApi.SetCoins then
            pcall(function() coinApi.SetCoins(math.max(0, math.floor(coins - price))) end)
        end
        if inventoryApi and inventoryApi.AddItem then
            inventoryApi:AddItem(id)
        end
        local req = ReplicatedStorage:FindFirstChild("RequestToolCopy")
        if req and req:IsA("RemoteFunction") then
            pcall(function() req:InvokeServer("Ranged", id) end)
        end
        -- Update header coin display
        pcall(function()
            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
        end)
        refresh()
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

    -- Ensure we have AssetCodes cached (safe)
    AssetCodes = AssetCodes or safeRequireAssetCodes()

    -- Build sections (these live inside the modal's scrolling content provided by SideUI)
    local rangedSection, rangedGrid = makeSection(root, "Ranged", "Ranged Weapons")
    local meleeSection, meleeGrid = makeSection(root, "Melee", "Melee Weapons")
    local specialSection, specialGrid = makeSection(root, "Special", "Special Weapons")
    local coinsSection, coinsGrid = makeSection(root, "Coins", "Coins")

    -- Populate ranged weapons section (Slingshot first since player starts with it)
    makeItem(rangedGrid, "Slingshot", "Slingshot", 0, "Slingshot", coinApi, inventoryApi)
    makeItem(rangedGrid, "Shortbow", "Shortbow", 20, "Shortbow", coinApi, inventoryApi)
    makeItem(rangedGrid, "Longbow", "Longbow", 30, "Longbow", coinApi, inventoryApi)
    makeItem(rangedGrid, "Xbow", "Xbow", 40, "Xbow", coinApi, inventoryApi)

    -- Melee/Special/Coin sections can be populated similarly by calling makeItem on those grids

    return root
end

return ShopUI
