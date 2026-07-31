--------------------------------------------------------------------------------
-- ShopUI.lua  –  Simplified Shop side menu
--
-- The Shop side menu has been stripped down. All item categories (weapons,
-- skins, effects, emotes, potions, boosts, salvage crates, etc.) have been
-- migrated to their own physical stalls (Cosmetics, Potion, Forge, etc.) and
-- should NOT be managed from this menu anymore.
--
-- Current layout:
--   • Left vertical strip  – Robux currency purchase cards (Coin + Key packs),
--                            styled like the Forge shard-purchase column.
--   • Right content area   – single scrollable, currently empty with a subtle
--                            "Currency purchases coming soon." placeholder.
--
-- Physical stall UIs (ForgeStallUI, PotionStallUI, CosmeticsStallUI, etc.) are
-- NOT touched by this module and should continue working normally.
--------------------------------------------------------------------------------

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local MarketplaceService  = game:GetService("MarketplaceService")
local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local Workspace           = game:GetService("Workspace")

local UITheme = require(script.Parent.UITheme)

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------
local function getViewportSize()
    local cam = Workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

local function px(base)
    local screenY = getViewportSize().Y
    return math.max(1, math.round(base * screenY / 1080))
end

local function safeRequire(parent, name, timeout)
    local mod = parent and parent:FindFirstChild(name)
    if not mod then
        mod = parent and parent:WaitForChild(name, timeout or 2)
    end
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then return result end
        warn("[ShopUI] Failed to require " .. tostring(name) .. ": " .. tostring(result))
    end
    return nil
end

local CoinProducts = safeRequire(ReplicatedStorage, "CoinProducts", 5)
local KeyProducts  = safeRequire(ReplicatedStorage, "KeyProducts", 5)
local AssetCodes   = safeRequire(ReplicatedStorage, "AssetCodes", 5)
local ShopCatalog  = safeRequire(ReplicatedStorage, "ShopCatalog", 5)

local function getAsset(key)
    if AssetCodes and type(AssetCodes.Get) == "function" then
        local id = AssetCodes.Get(key)
        if type(id) == "string" and #id > 0 then return id end
    end
    return nil
end

local function formatNumber(value)
    local n = math.floor(tonumber(value) or 0)
    local text = tostring(n)
    while true do
        local replaced
        text, replaced = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return text
end

--------------------------------------------------------------------------------
-- Palette (sourced from ForgeStallUI for visual parity with the shard column)
--------------------------------------------------------------------------------
local PANEL_BG       = Color3.fromRGB(6, 12, 26)
local PANEL_BG_LIGHT = Color3.fromRGB(8, 16, 34)
local CARD_BG        = Color3.fromRGB(12, 22, 46)
local CARD_BG_HOVER  = Color3.fromRGB(17, 30, 58)
local TOAST_BG       = Color3.fromRGB(10, 18, 38)
local ORANGE         = Color3.fromRGB(255, 145, 20)
local ORANGE_BRIGHT  = Color3.fromRGB(255, 191, 72)
local WHITE          = UITheme.WHITE
local DIM_TEXT       = UITheme.DIM_TEXT
local RED            = Color3.fromRGB(194, 62, 46)

local QUICK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function applyCorners(instance, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = instance
    return c
end

local function applyStroke(instance, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = instance
    return s
end

--------------------------------------------------------------------------------
-- ShopUI module
--------------------------------------------------------------------------------
local ShopUI = {}
local currentShopTab = "gamepasses"
local activeTabSetter = nil

local function showToast(parent, message, color, duration)
    local toast = Instance.new("TextLabel")
    toast.AnchorPoint = Vector2.new(0.5, 1)
    toast.Position = UDim2.new(0.5, 0, 0.97, 0)
    toast.Size = UDim2.new(0.36, 0, 0.08, 0)
    toast.BackgroundColor3 = TOAST_BG
    toast.BackgroundTransparency = 0.05
    toast.BorderSizePixel = 0
    toast.Font = Enum.Font.GothamBold
    toast.Text = message
    toast.TextColor3 = color or WHITE
    toast.TextScaled = true
    toast.TextWrapped = true
    toast.ZIndex = 260
    toast.Parent = parent
    applyCorners(toast, px(8))
    applyStroke(toast, ORANGE, 1, 0.4)
    local toastConstraint = Instance.new("UITextSizeConstraint")
    toastConstraint.MinTextSize = 10
    toastConstraint.MaxTextSize = px(16)
    toastConstraint.Parent = toast
    task.delay(duration or 2.2, function()
        if toast and toast.Parent then
            pcall(function() toast:Destroy() end)
        end
    end)
end

local function buildCurrencyCard(parent, layoutOrder, opts)
    -- opts: { iconKey, iconGlyph, amount, packName, productId, price, isBest }
    local card = Instance.new("TextButton")
    card.Name = "CurrencyPack_" .. tostring(layoutOrder)
    card.Size = UDim2.new(1, 0, 0, px(108))
    card.BackgroundColor3 = CARD_BG
    card.BorderSizePixel = 0
    card.AutoButtonColor = false
    card.Text = ""
    card.LayoutOrder = layoutOrder
    card.ClipsDescendants = false
    card.Parent = parent
    applyCorners(card, px(14))
    local cardStroke = applyStroke(card, ORANGE, 1.6, 0.02)

    -- Icon bubble (left)
    local iconBubble = Instance.new("Frame")
    iconBubble.AnchorPoint = Vector2.new(0, 0.5)
    iconBubble.Position = UDim2.new(0, px(8), 0.5, 0)
    iconBubble.Size = UDim2.new(0, px(78), 0, px(78))
    iconBubble.BackgroundTransparency = 1
    iconBubble.BorderSizePixel = 0
    iconBubble.Parent = card

    local iconImage = getAsset(opts.iconKey)
    if iconImage then
        local img = Instance.new("ImageLabel")
        img.Size = UDim2.fromScale(1, 1)
        img.BackgroundTransparency = 1
        img.Image = iconImage
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = iconBubble
    else
        local glyph = Instance.new("TextLabel")
        glyph.Size = UDim2.fromScale(1, 1)
        glyph.BackgroundTransparency = 1
        glyph.Font = Enum.Font.GothamBlack
        glyph.Text = opts.iconGlyph or "$"
        glyph.TextColor3 = ORANGE_BRIGHT
        glyph.TextScaled = true
        glyph.Parent = iconBubble
    end

    -- Amount (top right of icon)
    local amountLabel = Instance.new("TextLabel")
    amountLabel.BackgroundTransparency = 1
    amountLabel.Position = UDim2.new(0, px(94), 0, px(14))
    amountLabel.Size = UDim2.new(1, -px(100), 0, px(28))
    amountLabel.Font = Enum.Font.GothamBlack
    amountLabel.Text = formatNumber(opts.amount)
    amountLabel.TextColor3 = WHITE
    amountLabel.TextXAlignment = Enum.TextXAlignment.Left
    amountLabel.TextYAlignment = Enum.TextYAlignment.Center
    amountLabel.TextScaled = true
    amountLabel.Parent = card

    -- Pack name (under amount)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, px(94), 0, px(44))
    nameLabel.Size = UDim2.new(1, -px(100), 0, px(18))
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.Text = opts.packName or ""
    nameLabel.TextColor3 = DIM_TEXT
    nameLabel.TextSize = px(13)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card

    -- Price row (robux + price)
    local priceRow = Instance.new("Frame")
    priceRow.BackgroundTransparency = 1
    priceRow.Position = UDim2.new(0, px(94), 0, px(68))
    priceRow.Size = UDim2.new(1, -px(100), 0, px(24))
    priceRow.Parent = card

    local robuxImage = getAsset("Robux")
    local priceOffset = 0
    if robuxImage then
        local robuxIcon = Instance.new("ImageLabel")
        robuxIcon.Size = UDim2.new(0, px(18), 0, px(18))
        robuxIcon.Position = UDim2.new(0, 0, 0.5, -px(9))
        robuxIcon.BackgroundTransparency = 1
        robuxIcon.Image = robuxImage
        robuxIcon.ScaleType = Enum.ScaleType.Fit
        robuxIcon.Parent = priceRow
        priceOffset = px(22)
    end

    local priceLabel = Instance.new("TextLabel")
    priceLabel.BackgroundTransparency = 1
    priceLabel.Position = UDim2.new(0, priceOffset, 0, 0)
    priceLabel.Size = UDim2.new(1, -priceOffset, 1, 0)
    priceLabel.Font = Enum.Font.GothamBlack
    priceLabel.Text = tostring(opts.price or 0)
    priceLabel.TextColor3 = ORANGE_BRIGHT
    priceLabel.TextXAlignment = Enum.TextXAlignment.Left
    priceLabel.TextYAlignment = Enum.TextYAlignment.Center
    priceLabel.TextScaled = true
    priceLabel.Parent = priceRow

    -- BEST VALUE tag (bottom-right corner)
    if opts.isBest then
        local bestLabel = Instance.new("TextLabel")
        bestLabel.AnchorPoint = Vector2.new(1, 1)
        bestLabel.BackgroundTransparency = 1
        bestLabel.Position = UDim2.new(1, -px(8), 1, -px(6))
        bestLabel.Size = UDim2.new(0, px(86), 0, px(16))
        bestLabel.Font = Enum.Font.GothamBlack
        bestLabel.Text = "BEST VALUE"
        bestLabel.TextColor3 = ORANGE_BRIGHT
        bestLabel.TextSize = px(10)
        bestLabel.TextXAlignment = Enum.TextXAlignment.Right
        bestLabel.Parent = card
    end

    -- Hover effects
    card.MouseEnter:Connect(function()
        TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG_HOVER }):Play()
        cardStroke.Color = ORANGE_BRIGHT
    end)
    card.MouseLeave:Connect(function()
        TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG }):Play()
        cardStroke.Color = ORANGE
    end)

    -- Purchase prompt (preserves existing dev-product purchase routing)
    local debounce = false
    card.Activated:Connect(function()
        if debounce then return end
        if not opts.productId or opts.productId <= 0 then
            showToast(parent.Parent, "Product ID not set for " .. tostring(opts.packName), RED, 2.7)
            return
        end
        debounce = true
        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, opts.productId)
        end)
        if not ok then
            warn("[ShopUI] PromptProductPurchase failed:", tostring(err))
            showToast(parent.Parent, "Could not open the purchase prompt.", RED, 2.5)
        end
        task.delay(1.5, function()
            debounce = false
        end)
    end)

    return card
end

--------------------------------------------------------------------------------
-- Build the currency strip from CoinProducts + KeyProducts.
-- The strip itself is a transparent vertical layout — each card has its own
-- orange-bordered dark background, matching the Forge shard column where the
-- cards float outside the main panel.
--------------------------------------------------------------------------------
local function buildCurrencyStrip(parent)
    local strip = Instance.new("Frame")
    strip.Name = "ShopCurrencyStrip"
    strip.Size = UDim2.new(0, px(150), 1, 0)
    strip.BackgroundTransparency = 1
    strip.BorderSizePixel = 0
    strip.ClipsDescendants = false
    strip.ZIndex = 270
    strip.Parent = parent

    local stripLayout = Instance.new("UIListLayout")
    stripLayout.Padding = UDim.new(0, px(12))
    stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
    stripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    stripLayout.Parent = strip

    local cardCount = 0
    local order = 0

    -- Coin packs
    if CoinProducts and type(CoinProducts.Packs) == "table" and #CoinProducts.Packs > 0 then
        local bestIdx, bestRatio = nil, -math.huge
        for i, pack in ipairs(CoinProducts.Packs) do
            if type(pack.Price) == "number" and pack.Price > 0 then
                local ratio = (tonumber(pack.Coins) or 0) / pack.Price
                if ratio > bestRatio then
                    bestRatio = ratio
                    bestIdx = i
                end
            end
        end
        for i, pack in ipairs(CoinProducts.Packs) do
            order += 1
            buildCurrencyCard(strip, order, {
                iconKey   = "Coin",
                iconGlyph = "\u{1FA99}",
                amount    = pack.Coins,
                packName  = pack.Name,
                productId = pack.ProductId,
                price     = pack.Price,
                isBest    = (i == bestIdx),
            })
            cardCount += 1
        end
    end

    -- Key packs
    if KeyProducts and type(KeyProducts.Packs) == "table" and #KeyProducts.Packs > 0 then
        local bestIdx, bestRatio = nil, -math.huge
        for i, pack in ipairs(KeyProducts.Packs) do
            if type(pack.Price) == "number" and pack.Price > 0 then
                local ratio = (tonumber(pack.Keys) or 0) / pack.Price
                if ratio > bestRatio then
                    bestRatio = ratio
                    bestIdx = i
                end
            end
        end
        for i, pack in ipairs(KeyProducts.Packs) do
            order += 1
            buildCurrencyCard(strip, order, {
                iconKey   = "Key",
                iconGlyph = "\u{1F511}",
                amount    = pack.Keys,
                packName  = pack.Name,
                productId = pack.ProductId,
                price     = pack.Price,
                isBest    = (i == bestIdx),
            })
            cardCount += 1
        end
    end

    return strip, cardCount
end

local function getShopItems()
    if ShopCatalog and type(ShopCatalog.GetItems) == "function" then
        return ShopCatalog.GetItems()
    end
    return {}
end

local function getItemOwnedAttribute(item)
    if type(item) ~= "table" then
        return nil
    end
    if type(item.OwnedAttribute) == "string" and item.OwnedAttribute ~= "" then
        return item.OwnedAttribute
    end
    return nil
end

local function promptPurchaseForItem(item)
    if type(item) ~= "table" then
        return false, "invalid item"
    end

    if item.Kind == "GamePass" then
        local gamePassId = math.floor(tonumber(item.GamePassId) or 0)
        if gamePassId <= 0 then
            return false, "gamepass id not set"
        end
        MarketplaceService:PromptGamePassPurchase(player, gamePassId)
        return true
    end

    if item.Kind == "Product" then
        local productId = math.floor(tonumber(item.ProductId) or 0)
        if productId <= 0 then
            return false, "product id not set"
        end
        MarketplaceService:PromptProductPurchase(player, productId)
        return true
    end

    return false, "unsupported purchase type"
end

local function buildShopCard(parent, item, host)
    local accent = item.AccentColor or ORANGE
    local card = Instance.new("Frame")
    card.Name = tostring(item.Id or "ShopItem") .. "Card"
    card.LayoutOrder = math.floor(tonumber(item.SortOrder) or 0)
    card.BackgroundColor3 = CARD_BG
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = parent
    applyCorners(card, px(16))
    local cardStroke = applyStroke(card, accent, 1.4, 0.08)

    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.BackgroundColor3 = accent
    topBar.BackgroundTransparency = 0.12
    topBar.BorderSizePixel = 0
    topBar.Size = UDim2.new(1, 0, 0.035, 0)
    topBar.Parent = card

    local badge = Instance.new("TextLabel")
    badge.Name = "Badge"
    badge.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.2)
    badge.BorderSizePixel = 0
    badge.Position = UDim2.new(0.04, 0, 0.07, 0)
    badge.Size = UDim2.new(0.24, 0, 0.13, 0)
    badge.Font = Enum.Font.GothamBlack
    badge.Text = tostring(item.BadgeText or item.Kind or "SHOP")
    badge.TextColor3 = WHITE
    badge.TextScaled = true
    badge.ZIndex = 2
    badge.Parent = card
    applyCorners(badge, px(10))
    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = accent
    badgeStroke.Transparency = 0.25
    badgeStroke.Thickness = 1
    badgeStroke.Parent = badge
    local badgeConstraint = Instance.new("UITextSizeConstraint")
    badgeConstraint.MinTextSize = 10
    badgeConstraint.MaxTextSize = px(18)
    badgeConstraint.Parent = badge

    local pricePill = Instance.new("Frame")
    pricePill.Name = "PricePill"
    pricePill.AnchorPoint = Vector2.new(1, 0)
    pricePill.Position = UDim2.new(0.96, 0, 0.07, 0)
    pricePill.Size = UDim2.new(0.22, 0, 0.13, 0)
    pricePill.BackgroundColor3 = PANEL_BG
    pricePill.BorderSizePixel = 0
    pricePill.Parent = card
    applyCorners(pricePill, px(10))
    local priceStroke = applyStroke(pricePill, accent, 1, 0.3)

    local robuxImage = getAsset("Robux")
    if robuxImage then
        local robuxIcon = Instance.new("ImageLabel")
        robuxIcon.Name = "RobuxIcon"
        robuxIcon.BackgroundTransparency = 1
        robuxIcon.AnchorPoint = Vector2.new(0, 0.5)
        robuxIcon.Position = UDim2.new(0.08, 0, 0.5, 0)
        robuxIcon.Size = UDim2.new(0.18, 0, 0.62, 0)
        robuxIcon.ScaleType = Enum.ScaleType.Fit
        robuxIcon.Image = robuxImage
        robuxIcon.Parent = pricePill
    end

    local priceLabel = Instance.new("TextLabel")
    priceLabel.Name = "Price"
    priceLabel.BackgroundTransparency = 1
    priceLabel.Position = UDim2.new(0.32, 0, 0, 0)
    priceLabel.Size = UDim2.new(0.66, 0, 1, 0)
    priceLabel.Font = Enum.Font.GothamBlack
    priceLabel.Text = tostring(math.floor(tonumber(item.PriceRobux) or 0))
    priceLabel.TextColor3 = ORANGE_BRIGHT
    priceLabel.TextScaled = true
    priceLabel.TextXAlignment = Enum.TextXAlignment.Left
    priceLabel.TextYAlignment = Enum.TextYAlignment.Center
    priceLabel.Parent = pricePill
    local priceConstraint = Instance.new("UITextSizeConstraint")
    priceConstraint.MinTextSize = 10
    priceConstraint.MaxTextSize = px(18)
    priceConstraint.Parent = priceLabel

    local iconBubble = Instance.new("Frame")
    iconBubble.Name = "IconBubble"
    iconBubble.BackgroundColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.16)
    iconBubble.BorderSizePixel = 0
    iconBubble.Position = UDim2.new(0.04, 0, 0.25, 0)
    iconBubble.Size = UDim2.new(0.20, 0, 0.36, 0)
    iconBubble.Parent = card
    applyCorners(iconBubble, px(18))
    local iconStroke = applyStroke(iconBubble, accent, 1, 0.25)

    local iconAsset = item.IconKey and getAsset(item.IconKey) or nil
    if iconAsset then
        local iconImage = Instance.new("ImageLabel")
        iconImage.Name = "IconImage"
        iconImage.BackgroundTransparency = 1
        iconImage.Size = UDim2.new(0.72, 0, 0.72, 0)
        iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
        iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        iconImage.ScaleType = Enum.ScaleType.Fit
        iconImage.Image = iconAsset
        iconImage.Parent = iconBubble
    else
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Name = "IconText"
        iconLabel.BackgroundTransparency = 1
        iconLabel.Size = UDim2.new(1, 0, 1, 0)
        iconLabel.Font = Enum.Font.GothamBlack
        iconLabel.Text = tostring(item.IconText or string.upper(string.sub(item.DisplayName or item.Id or "", 1, 3)))
        iconLabel.TextColor3 = PANEL_BG
        iconLabel.TextScaled = true
        iconLabel.Parent = iconBubble
        local iconConstraint = Instance.new("UITextSizeConstraint")
        iconConstraint.MinTextSize = 18
        iconConstraint.MaxTextSize = px(38)
        iconConstraint.Parent = iconLabel
    end

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0.28, 0, 0.24, 0)
    title.Size = UDim2.new(0.67, 0, 0.14, 0)
    title.Font = Enum.Font.GothamBlack
    title.Text = tostring(item.DisplayName or item.Id or "Shop Item")
    title.TextColor3 = WHITE
    title.TextScaled = true
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Center
    title.Parent = card
    local titleConstraint = Instance.new("UITextSizeConstraint")
    titleConstraint.MinTextSize = 11
    titleConstraint.MaxTextSize = px(22)
    titleConstraint.Parent = title

    local description = Instance.new("TextLabel")
    description.Name = "Description"
    description.BackgroundTransparency = 1
    description.Position = UDim2.new(0.28, 0, 0.41, 0)
    description.Size = UDim2.new(0.67, 0, 0.21, 0)
    description.Font = Enum.Font.Gotham
    description.Text = tostring(item.Description or "")
    description.TextColor3 = DIM_TEXT
    description.TextScaled = true
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.Parent = card
    local descConstraint = Instance.new("UITextSizeConstraint")
    descConstraint.MinTextSize = 9
    descConstraint.MaxTextSize = px(14)
    descConstraint.Parent = description

    local buyButton = Instance.new("TextButton")
    buyButton.Name = "BuyButton"
    buyButton.AnchorPoint = Vector2.new(1, 1)
    buyButton.Position = UDim2.new(0.96, 0, 0.93, 0)
    buyButton.Size = UDim2.new(0.34, 0, 0.16, 0)
    buyButton.AutoButtonColor = false
    buyButton.BorderSizePixel = 0
    buyButton.Font = Enum.Font.GothamBlack
    buyButton.TextColor3 = WHITE
    buyButton.TextScaled = true
    buyButton.Parent = card
    applyCorners(buyButton, px(10))
    local buyStroke = applyStroke(buyButton, accent, 1, 0.15)
    local buyConstraint = Instance.new("UITextSizeConstraint")
    buyConstraint.MinTextSize = 10
    buyConstraint.MaxTextSize = px(18)
    buyConstraint.Parent = buyButton

    if item.BestValue or item.isBest then
        local bestLabel = Instance.new("TextLabel")
        bestLabel.Name = "BestValue"
        bestLabel.AnchorPoint = Vector2.new(1, 1)
        bestLabel.BackgroundTransparency = 1
        bestLabel.Position = UDim2.new(0.96, 0, 0.86, 0)
        bestLabel.Size = UDim2.new(0.24, 0, 0.08, 0)
        bestLabel.Font = Enum.Font.GothamBlack
        bestLabel.Text = "BEST VALUE"
        bestLabel.TextColor3 = ORANGE_BRIGHT
        bestLabel.TextScaled = true
        bestLabel.TextXAlignment = Enum.TextXAlignment.Right
        bestLabel.Parent = card
        local bestConstraint = Instance.new("UITextSizeConstraint")
        bestConstraint.MinTextSize = 9
        bestConstraint.MaxTextSize = px(14)
        bestConstraint.Parent = bestLabel
    end

    local owned = false
    local busy = false
    local ownedAttr = getItemOwnedAttribute(item)

    local function refreshVisuals()
        if item.Kind == "GamePass" and ownedAttr then
            owned = player:GetAttribute(ownedAttr) == true
        else
            owned = false
        end

        local buttonText = "BUY"
        local buttonColor = accent
        local textColor = WHITE
        local strokeColor = accent

        if owned then
            buttonText = "OWNED"
            buttonColor = Color3.fromRGB(34, 42, 68)
            textColor = DIM_TEXT
            strokeColor = Color3.fromRGB(120, 126, 145)
        end

        buyButton.Text = buttonText
        buyButton.BackgroundColor3 = buttonColor
        buyButton.TextColor3 = textColor
        cardStroke.Color = strokeColor
        badgeStroke.Color = strokeColor
        priceStroke.Color = strokeColor
        iconStroke.Color = strokeColor
        buyStroke.Color = strokeColor
    end

    local function openPurchase()
        if busy then
            return
        end
        if item.Kind == "GamePass" and owned then
            showToast(host or card, tostring(item.DisplayName or item.Id or "Item") .. " already owned.", ORANGE_BRIGHT, 2)
            return
        end

        local success, err = promptPurchaseForItem(item)
        if not success then
            showToast(host or card, tostring(item.DisplayName or item.Id or "Item") .. " is not configured yet.", RED, 2.5)
            warn("[ShopUI] Purchase blocked for", tostring(item.Id), ":", tostring(err))
            return
        end

        busy = true
        task.delay(1.5, function()
            busy = false
        end)
    end

    card.MouseEnter:Connect(function()
        TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG_HOVER }):Play()
    end)
    card.MouseLeave:Connect(function()
        TweenService:Create(card, QUICK_TWEEN, { BackgroundColor3 = CARD_BG }):Play()
    end)

    buyButton.Activated:Connect(openPurchase)

    if item.Kind == "GamePass" and ownedAttr then
        player:GetAttributeChangedSignal(ownedAttr):Connect(refreshVisuals)
    end

    refreshVisuals()
    return card
end

local function getGamepassTabItems()
    local items = {}
    if ShopCatalog and type(ShopCatalog.GetItems) == "function" then
        for _, item in ipairs(ShopCatalog.GetItems()) do
            if item.Id == "starter_pack" or item.Kind == "GamePass" then
                table.insert(items, item)
            end
        end
    end
    return items
end

local function getPackTabItems(source, kindLabel, iconKey, accentColor, nounLabel)
    local items = {}
    if not (source and type(source.Packs) == "table") then
        return items
    end

    for index, pack in ipairs(source.Packs) do
        local amount = math.floor(tonumber(pack.Coins or pack.Keys) or 0)
        local price = math.floor(tonumber(pack.Price) or 0)
        local nounText = amount == 1 and nounLabel or (nounLabel .. "s")
        table.insert(items, {
            Id = string.lower(kindLabel) .. "_pack_" .. tostring(index),
            SortOrder = index,
            Kind = "Product",
            DisplayName = tostring(pack.Name or (formatNumber(amount) .. " " .. nounLabel .. " Pack")),
            BadgeText = kindLabel,
            Description = string.format("%s %s for %d Robux.", formatNumber(amount), nounText, price),
            PriceRobux = price,
            ProductId = pack.ProductId,
            AccentColor = accentColor,
            IconKey = iconKey,
            IconText = nounLabel:sub(1, 3):upper(),
            BestValue = pack.BestValue == true or index == #source.Packs,
        })
    end

    return items
end

local function buildCatalogPage(parent, items, host)
    local catalogItems = (type(items) == "table") and items or {}
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ShopScroll"
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.CanvasSize = UDim2.fromScale(0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
    scroll.ScrollBarThickness = math.max(6, px(8))
    scroll.ScrollBarImageColor3 = UITheme.GOLD
    scroll.ScrollBarImageTransparency = 0.15
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.Parent = parent

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0.02, 0)
    padding.PaddingBottom = UDim.new(0.09, 0)
    padding.PaddingLeft = UDim.new(0.02, 0)
    padding.PaddingRight = UDim.new(0.02, 0)
    padding.Parent = scroll

    local grid = Instance.new("UIGridLayout")
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 2
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.CellPadding = UDim2.fromScale(0.02, 0.02)
    grid.CellSize = UDim2.fromScale(0.47, 0.44)
    grid.Parent = scroll

    for _, item in ipairs(catalogItems) do
        buildShopCard(scroll, item, host)
    end

    local rowCount = math.max(1, math.ceil(#catalogItems / 2))
    local contentHeight = 0.02 + (rowCount * 0.44) + math.max(0, rowCount - 1) * 0.02 + 0.22
    scroll.CanvasSize = UDim2.fromScale(0, contentHeight)

    return scroll
end

--------------------------------------------------------------------------------
-- Walk up the ancestor chain to find the modal window (ModalWindow) so the
-- currency strip can be parented as a sibling and floated to its left edge.
--------------------------------------------------------------------------------
local function findModalWindow(inst)
    local cur = inst
    while cur do
        if cur.Name == "ModalWindow" then return cur end
        cur = cur.Parent
    end
    return nil
end

--------------------------------------------------------------------------------
-- Public: ShopUI.Create(parent, coinApi, inventoryApi)
--   Builds the simplified Shop menu inside `parent`.
--   coinApi / inventoryApi are accepted for API compatibility and are unused
--   in the simplified shop (currency display is handled by SideUI's header).
--------------------------------------------------------------------------------
function ShopUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return nil end

    -- Clear any previous content from this parent
    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
            pcall(function() c:Destroy() end)
        end
    end

    local root = Instance.new("Frame")
    root.Name = "ShopRoot"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 1, 0)
    root.ZIndex = 240
    root.LayoutOrder = 1
    root.ClipsDescendants = false
    root.Parent = parent

    local shell = Instance.new("Frame")
    shell.Name = "ShopShell"
    shell.BackgroundColor3 = UITheme.NAVY
    shell.BorderSizePixel = 0
    shell.AnchorPoint = Vector2.new(0.5, 0.5)
    shell.Position = UDim2.new(0.5, 0, 0.5, 0)
    shell.Size = UDim2.new(0.985, 0, 0.985, 0)
    shell.Parent = root
    applyCorners(shell, px(18))
    applyStroke(shell, UITheme.GOLD_DIM, 1, 0.88)

    local shellGradient = Instance.new("UIGradient")
    shellGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 11, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 20, 42)),
    })
    shellGradient.Rotation = 90
    shellGradient.Parent = shell

    local sidebar = Instance.new("Frame")
    sidebar.Name = "ShopTabs"
    sidebar.BackgroundColor3 = UITheme.SIDEBAR_BG
    sidebar.BorderSizePixel = 0
    sidebar.Position = UDim2.new(0.015, 0, 0.02, 0)
    sidebar.Size = UDim2.new(0.14, 0, 0.96, 0)
    sidebar.ZIndex = 5
    sidebar.Parent = shell
    applyCorners(sidebar, px(16))
    applyStroke(sidebar, UITheme.CARD_STROKE, 1, 0.82)

    local sidebarPadding = Instance.new("UIPadding")
    sidebarPadding.PaddingTop = UDim.new(0.04, 0)
    sidebarPadding.PaddingBottom = UDim.new(0.04, 0)
    sidebarPadding.PaddingLeft = UDim.new(0.05, 0)
    sidebarPadding.PaddingRight = UDim.new(0.05, 0)
    sidebarPadding.Parent = sidebar

    local sidebarLayout = Instance.new("UIListLayout")
    sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sidebarLayout.Padding = UDim.new(0.03, 0)
    sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sidebarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    sidebarLayout.Parent = sidebar

    local contentArea = Instance.new("Frame")
    contentArea.Name = "ShopPages"
    contentArea.BackgroundColor3 = UITheme.NAVY_MID
    contentArea.BorderSizePixel = 0
    contentArea.Position = UDim2.new(0.17, 0, 0.02, 0)
    contentArea.Size = UDim2.new(0.815, 0, 0.96, 0)
    contentArea.ZIndex = 2
    contentArea.Parent = shell
    applyCorners(contentArea, px(16))
    applyStroke(contentArea, UITheme.CARD_STROKE, 1, 0.9)

    local contentGradient = Instance.new("UIGradient")
    contentGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 16, 34)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 26, 52)),
    })
    contentGradient.Rotation = 90
    contentGradient.Parent = contentArea

    local tabPages = {}
    tabPages.gamepasses = buildCatalogPage(contentArea, getGamepassTabItems(), root)
    tabPages.coins = buildCatalogPage(contentArea, getPackTabItems(CoinProducts, "COINS", "Coin", ORANGE, "Coin"), root)
    tabPages.keys = buildCatalogPage(contentArea, getPackTabItems(KeyProducts, "KEYS", "Key", UITheme.GOLD, "Key"), root)

    for _, page in pairs(tabPages) do
        page.Visible = false
        page.Parent = contentArea
    end

    local tabButtons = {}

    local function setActiveTab(tabId)
        if tabId == "currency" then
            tabId = "coins"
        end
        if not tabPages[tabId] then
            tabId = "gamepasses"
        end

        currentShopTab = tabId

        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and UITheme.TAB_ACTIVE or UITheme.SIDEBAR_BG

            local label = btn:FindFirstChild("Label")
            if label then
                label.TextColor3 = active and WHITE or DIM_TEXT
            end

            local indicator = btn:FindFirstChild("ActiveBar")
            if indicator then
                indicator.BackgroundTransparency = active and 0 or 1
            end

            local stroke = btn:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = active and UITheme.GOLD_WARM or UITheme.CARD_STROKE
                stroke.Transparency = active and 0.08 or 0.25
            end
        end

        for id, page in pairs(tabPages) do
            page.Visible = (id == tabId)
        end
    end

    local function makeTabButton(tabId, labelText, order)
        local btn = Instance.new("TextButton")
        btn.Name = labelText .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = UITheme.SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.ZIndex = 6
        btn.Size = UDim2.fromScale(0.92, 0.26)
        btn.LayoutOrder = order
        btn.Text = ""
        btn.Parent = sidebar
        applyCorners(btn, px(12))
        applyStroke(btn, UITheme.CARD_STROKE, 1, 0.25)

        local activeBar = Instance.new("Frame")
        activeBar.Name = "ActiveBar"
        activeBar.BackgroundColor3 = UITheme.GOLD_WARM
        activeBar.BorderSizePixel = 0
        activeBar.BackgroundTransparency = 1
        activeBar.Position = UDim2.new(0.05, 0, 0.18, 0)
        activeBar.Size = UDim2.new(0.03, 0, 0.64, 0)
        activeBar.ZIndex = 7
        activeBar.Parent = btn
        applyCorners(activeBar, px(8))

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromScale(0.08, 0.08)
        label.Size = UDim2.fromScale(0.84, 0.84)
        label.Font = Enum.Font.GothamBlack
        label.Text = labelText
        label.TextColor3 = DIM_TEXT
        label.TextScaled = true
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.ZIndex = 7
        label.Parent = btn

        btn.MouseEnter:Connect(function()
            if currentShopTab ~= tabId then
                TweenService:Create(btn, QUICK_TWEEN, { BackgroundColor3 = UITheme.TAB_HOVER }):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if currentShopTab ~= tabId then
                TweenService:Create(btn, QUICK_TWEEN, { BackgroundColor3 = UITheme.SIDEBAR_BG }):Play()
            end
        end)
        btn.Activated:Connect(function()
            setActiveTab(tabId)
        end)
        btn.MouseButton1Click:Connect(function()
            setActiveTab(tabId)
        end)

        tabButtons[tabId] = btn
        return btn
    end

    makeTabButton("gamepasses", "Passes", 1)
    makeTabButton("coins", "Coins", 2)
    makeTabButton("keys", "Keys", 3)

    activeTabSetter = setActiveTab
    setActiveTab(currentShopTab)

    print(string.format("[ShopUI] Opened shop catalog with %d items", #getGamepassTabItems() + #getPackTabItems(CoinProducts, "COINS", "Coin", ORANGE, "Coin") + #getPackTabItems(KeyProducts, "KEYS", "Key", UITheme.GOLD, "Key")))

    return root
end

-- Default tab API (overwritten on Create as well, but exposed so callers
-- requiring this module before the menu is built can still introspect safely).
ShopUI.getActiveTab = function()
    return currentShopTab == "coins" and "currency" or currentShopTab
end
ShopUI.setActiveTab = function(tabId)
    if tabId == "currency" then
        tabId = "coins"
    end
    if type(tabId) ~= "string" or tabId == "" then
        tabId = "gamepasses"
    end
    currentShopTab = tabId
    if activeTabSetter then
        activeTabSetter(tabId)
    end
end

return ShopUI
