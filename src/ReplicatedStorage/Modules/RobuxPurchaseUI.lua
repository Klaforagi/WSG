local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes"))

local RobuxPurchaseUI = {}

RobuxPurchaseUI.Colors = {
    Gold = Color3.fromRGB(255, 220, 92),
    GoldSoft = Color3.fromRGB(255, 239, 156),
    Black = Color3.fromRGB(0, 0, 0),
    CardBackground = Color3.fromRGB(34, 39, 52),
    CardBackgroundHover = Color3.fromRGB(46, 51, 68),
    ModalBackground = Color3.fromRGB(18, 20, 28),
    CancelBackground = Color3.fromRGB(56, 48, 24),
}

local function ensureCorner(guiObject, radius)
    local corner = guiObject:FindFirstChild("Corner")
    if corner and not corner:IsA("UICorner") then
        corner:Destroy()
        corner = nil
    end
    if not corner then
        corner = Instance.new("UICorner")
        corner.Name = "Corner"
        corner.Parent = guiObject
    end
    corner.CornerRadius = UDim.new(0, radius)
    return corner
end

local function getRobuxImage()
    if AssetCodes and type(AssetCodes.Get) == "function" then
        return AssetCodes.Get("Robux")
    end
    return nil
end

function RobuxPurchaseUI.ApplyOutlinedText(textObject, color)
    if not textObject then
        return
    end

    textObject.TextColor3 = color or RobuxPurchaseUI.Colors.Gold
    textObject.TextStrokeColor3 = RobuxPurchaseUI.Colors.Black
    textObject.TextStrokeTransparency = 0
end

function RobuxPurchaseUI.StyleModalCard(card, strokeColor)
    if not card then
        return
    end

    card.BackgroundColor3 = RobuxPurchaseUI.Colors.ModalBackground
    card.BorderSizePixel = 0
    ensureCorner(card, 14)

    local stroke = card:FindFirstChild("Stroke")
    if stroke and not stroke:IsA("UIStroke") then
        stroke:Destroy()
        stroke = nil
    end
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Name = "Stroke"
        stroke.Parent = card
    end
    stroke.Color = strokeColor or RobuxPurchaseUI.Colors.Black
    stroke.Thickness = 2
    stroke.Transparency = 0

    local accent = card:FindFirstChild("Accent")
    if accent and not accent:IsA("Frame") then
        accent:Destroy()
        accent = nil
    end
    if not accent then
        accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.BorderSizePixel = 0
        accent.Parent = card
        ensureCorner(accent, 10)
    end
    accent.BackgroundColor3 = RobuxPurchaseUI.Colors.Gold
    accent.Size = UDim2.new(1, -30, 0, 4)
    accent.Position = UDim2.new(0, 15, 0, 12)
end

function RobuxPurchaseUI.StyleCancelButton(button)
    if not button then
        return
    end

    button.BackgroundColor3 = RobuxPurchaseUI.Colors.CancelBackground
    button.BorderSizePixel = 0
    RobuxPurchaseUI.ApplyOutlinedText(button, RobuxPurchaseUI.Colors.GoldSoft)
    ensureCorner(button, 10)

    local stroke = button:FindFirstChild("Stroke")
    if stroke and not stroke:IsA("UIStroke") then
        stroke:Destroy()
        stroke = nil
    end
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Name = "Stroke"
        stroke.Parent = button
    end
    stroke.Color = RobuxPurchaseUI.Colors.Black
    stroke.Thickness = 2
    stroke.Transparency = 0
end

function RobuxPurchaseUI.CreateRobuxIcon(parent, size)
    local image = getRobuxImage()
    if image then
        local icon = Instance.new("ImageLabel")
        icon.Name = "RobuxIcon"
        icon.BackgroundTransparency = 1
        icon.Size = UDim2.new(0, size, 0, size)
        icon.Image = image
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Parent = parent
        return icon
    end

    local label = Instance.new("TextLabel")
    label.Name = "RobuxFallback"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0, size + 8, 0, size)
    label.Font = Enum.Font.GothamBlack
    label.Text = "R$"
    label.TextSize = math.max(10, math.floor(size * 0.8))
    label.Parent = parent
    RobuxPurchaseUI.ApplyOutlinedText(label, RobuxPurchaseUI.Colors.Gold)
    return label
end

function RobuxPurchaseUI.CreatePackCard(parent, options)
    options = options or {}

    local button = Instance.new("TextButton")
    button.Name = options.name or "PackCard"
    button.BackgroundColor3 = RobuxPurchaseUI.Colors.CardBackground
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Size = options.size or UDim2.new(1, 0, 0, 56)
    button.LayoutOrder = tonumber(options.layoutOrder) or 0
    button.Text = ""
    button.Parent = parent
    ensureCorner(button, 10)

    local stroke = Instance.new("UIStroke")
    stroke.Name = "Stroke"
    stroke.Color = RobuxPurchaseUI.Colors.Black
    stroke.Thickness = 2
    stroke.Transparency = 0
    stroke.Parent = button

    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.BackgroundColor3 = RobuxPurchaseUI.Colors.Gold
    accent.BorderSizePixel = 0
    accent.Size = UDim2.new(0, 4, 1, -12)
    accent.Position = UDim2.new(0, 8, 0, 6)
    accent.Parent = button
    ensureCorner(accent, 4)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 22, 0, 8)
    titleLabel.Size = UDim2.new(0.62, -22, 0, 22)
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.Text = tostring(options.title or "")
    titleLabel.TextSize = tonumber(options.titleSize) or 18
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = button
    RobuxPurchaseUI.ApplyOutlinedText(titleLabel, options.titleColor or RobuxPurchaseUI.Colors.Gold)

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Name = "Subtitle"
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Position = UDim2.new(0, 22, 0, 31)
    subtitleLabel.Size = UDim2.new(0.62, -22, 0, 16)
    subtitleLabel.Font = Enum.Font.GothamBold
    subtitleLabel.Text = tostring(options.subtitle or "")
    subtitleLabel.TextSize = tonumber(options.subtitleSize) or 13
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.TextTransparency = (options.subtitle and options.subtitle ~= "") and 0 or 1
    subtitleLabel.Parent = button
    RobuxPurchaseUI.ApplyOutlinedText(subtitleLabel, options.subtitleColor or RobuxPurchaseUI.Colors.GoldSoft)

    local priceRow = Instance.new("Frame")
    priceRow.Name = "PriceRow"
    priceRow.BackgroundTransparency = 1
    priceRow.AnchorPoint = Vector2.new(1, 0.5)
    priceRow.Position = UDim2.new(1, -14, 0.5, 0)
    priceRow.Size = UDim2.new(0, 126, 0, 28)
    priceRow.Parent = button

    local priceIcon = RobuxPurchaseUI.CreateRobuxIcon(priceRow, 18)
    priceIcon.AnchorPoint = Vector2.new(0, 0.5)
    priceIcon.Position = UDim2.new(0, 0, 0.5, 0)

    local priceLabel = Instance.new("TextLabel")
    priceLabel.Name = "Price"
    priceLabel.BackgroundTransparency = 1
    priceLabel.Position = UDim2.new(0, 24, 0, 0)
    priceLabel.Size = UDim2.new(1, -24, 1, 0)
    priceLabel.Font = Enum.Font.GothamBlack
    priceLabel.Text = tostring(options.price or 0)
    priceLabel.TextSize = tonumber(options.priceSize) or 20
    priceLabel.TextXAlignment = Enum.TextXAlignment.Left
    priceLabel.Parent = priceRow
    RobuxPurchaseUI.ApplyOutlinedText(priceLabel, options.priceColor or RobuxPurchaseUI.Colors.Gold)

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = RobuxPurchaseUI.Colors.CardBackgroundHover,
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = RobuxPurchaseUI.Colors.CardBackground,
        }):Play()
    end)

    return button
end

return RobuxPurchaseUI