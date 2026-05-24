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
local PANEL_BG       = Color3.fromRGB(8, 8, 9)
local PANEL_BG_LIGHT = Color3.fromRGB(13, 13, 15)
local CARD_BG        = Color3.fromRGB(16, 16, 18)
local CARD_BG_HOVER  = Color3.fromRGB(22, 22, 24)
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

local function showToast(parent, message, color, duration)
    local toast = Instance.new("TextLabel")
    toast.AnchorPoint = Vector2.new(0.5, 1)
    toast.Position = UDim2.new(0.5, 0, 1, -px(20))
    toast.Size = UDim2.new(0, px(360), 0, px(44))
    toast.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
    toast.BackgroundTransparency = 0.05
    toast.BorderSizePixel = 0
    toast.Font = Enum.Font.GothamBold
    toast.Text = message
    toast.TextColor3 = color or WHITE
    toast.TextSize = px(16)
    toast.TextWrapped = true
    toast.ZIndex = 260
    toast.Parent = parent
    applyCorners(toast, px(8))
    applyStroke(toast, ORANGE, 1, 0.4)
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
    amountLabel.TextSize = px(22)
    amountLabel.TextXAlignment = Enum.TextXAlignment.Left
    amountLabel.TextYAlignment = Enum.TextYAlignment.Center
    amountLabel.TextScaled = true
    amountLabel.Parent = card
    local amountConstraint = Instance.new("UITextSizeConstraint")
    amountConstraint.MinTextSize = 12
    amountConstraint.MaxTextSize = px(22)
    amountConstraint.Parent = amountLabel

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
    priceLabel.TextSize = px(16)
    priceLabel.TextXAlignment = Enum.TextXAlignment.Left
    priceLabel.TextYAlignment = Enum.TextYAlignment.Center
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

    -- Root container lives inside the modal's content frame (kept simple — the
    -- right side of the window is intentionally empty aside from a subtle
    -- placeholder). The currency strip itself is parented OUTSIDE the window
    -- (see below) so the cards float to the left of the panel like the Forge
    -- shard column.
    local root = Instance.new("Frame")
    root.Name                   = "ShopRoot"
    root.BackgroundTransparency = 1
    root.Size                   = UDim2.new(1, 0, 1, 0)
    root.ZIndex                 = 240
    root.LayoutOrder            = 1
    root.ClipsDescendants       = false
    root.Parent                 = parent

    -- Subtle centered placeholder inside the main window
    local placeholder = Instance.new("TextLabel")
    placeholder.Name = "Placeholder"
    placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
    placeholder.Position = UDim2.new(0.5, 0, 0.5, 0)
    placeholder.Size = UDim2.new(1, -px(40), 0, px(40))
    placeholder.BackgroundTransparency = 1
    placeholder.Font = Enum.Font.Gotham
    placeholder.Text = "Currency purchases coming soon."
    placeholder.TextColor3 = DIM_TEXT
    placeholder.TextSize = px(18)
    placeholder.TextTransparency = 0.25
    placeholder.TextXAlignment = Enum.TextXAlignment.Center
    placeholder.TextYAlignment = Enum.TextYAlignment.Center
    placeholder.Parent = root

    -- ──────────────────────────────────────────────────────────────────────
    -- Currency strip: float OUTSIDE the modal window on the left, mirroring
    -- ForgeStallUI's shard column. Parent the strip to the modal window itself
    -- so it inherits show/hide with the window. Position it with a negative X
    -- offset so it sits to the left of the window's outer edge.
    -- ──────────────────────────────────────────────────────────────────────
    local STRIP_W   = px(150)
    local STRIP_GAP = px(12)
    local cardCount = 0

    local modalWindow = findModalWindow(parent)
    local stripHost = modalWindow or root

    -- Account for the modal window's UIPadding so the strip floats outside
    -- the window's true outer edge (not the padded content area).
    local hostPadLeft = 0
    if modalWindow then
        local pad = modalWindow:FindFirstChildOfClass("UIPadding")
        if pad and pad.PaddingLeft then
            hostPadLeft = pad.PaddingLeft.Offset
        end
    end

    local stripContainer = Instance.new("Frame")
    stripContainer.Name = "ShopCurrencyStripContainer"
    stripContainer.BackgroundTransparency = 1
    stripContainer.BorderSizePixel = 0
    stripContainer.AnchorPoint = Vector2.new(1, 0.5)
    stripContainer.Position = UDim2.new(0, -(hostPadLeft + STRIP_GAP), 0.5, 0)
    stripContainer.Size = UDim2.new(0, STRIP_W, 1, 0)
    stripContainer.ZIndex = 270
    stripContainer.ClipsDescendants = false
    stripContainer.Parent = stripHost

    local _strip
    _strip, cardCount = buildCurrencyStrip(stripContainer)
    print(string.format("[ShopUI] Rendered %d currency purchase cards", cardCount))

    -- The shop's content host is reparented between the active content frame
    -- (ModalContent) and an offscreen prewarm container (also a descendant of
    -- ModalWindow) when other modal menus take focus. Bind the floating
    -- strip's visibility to whether the shop root is currently a descendant
    -- of ModalContent so the coin/key packs only appear while the Shop is
    -- the active page.
    if modalWindow then
        local function isInActiveContent()
            local cur = root.Parent
            while cur and cur ~= modalWindow do
                if cur.Name == "ModalContent" then
                    return true
                end
                cur = cur.Parent
            end
            return false
        end
        local function syncStripVisibility()
            if not stripContainer or not stripContainer.Parent then return end
            stripContainer.Visible = isInActiveContent()
        end
        syncStripVisibility()
        root.AncestryChanged:Connect(syncStripVisibility)
        if root.Parent then
            root.Parent.AncestryChanged:Connect(syncStripVisibility)
        end
    end

    -- Clean up the strip when the shop root is destroyed entirely.
    root.Destroying:Connect(function()
        if stripContainer and stripContainer.Parent then
            pcall(function() stripContainer:Destroy() end)
        end
    end)

    print("[ShopUI] Opened simplified shop menu")

    -- Public tab API: kept for backwards compatibility with CoinDisplay's
    -- "+" coin button. In simplified mode there are no tabs; we always report
    -- "currency" so the existing toggle behavior on the coin "+" button works.
    ShopUI.getActiveTab = function() return "currency" end
    ShopUI.setActiveTab = function(tabId)
        if tabId and tabId ~= "currency" then
            warn("[ShopUI] Old shop tab creation skipped in simplified shop mode (requested: " .. tostring(tabId) .. ")")
        end
        -- no-op: there is only one page
    end

    return root
end

-- Default tab API (overwritten on Create as well, but exposed so callers
-- requiring this module before the menu is built can still introspect safely).
ShopUI.getActiveTab = function() return "currency" end
ShopUI.setActiveTab = function(tabId)
    if tabId and tabId ~= "currency" then
        warn("[ShopUI] Old shop tab creation skipped in simplified shop mode (requested: " .. tostring(tabId) .. ")")
    end
end

return ShopUI
