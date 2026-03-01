-- CoinDisplay ModuleScript
-- Provides a reusable coin-row UI element wired to CurrencyService remotes.
-- Usage from a client LocalScript:
--   local CoinDisplay = require(ReplicatedStorage:WaitForChild("CoinDisplay"))
--   local row, api = CoinDisplay.Create(parentFrame, layoutOrder)
--   -- api.SetCoins(123)   (manual override, but auto-updates from server)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Try to load AssetCodes safely
local AssetCodes = nil
do
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        pcall(function() AssetCodes = require(mod) end)
    end
end

local COLORS = {
    gold = Color3.fromRGB(255, 215, 80),
    white = Color3.fromRGB(245, 245, 245),
    rowBg = Color3.fromRGB(22, 24, 42),
}

local CoinDisplay = {}

--- Creates the coin-row Frame, wires it to server remotes, and returns (frame, api).
--- @param parent Instance  The parent GUI object to place the row inside.
--- @param layoutOrder number  Optional LayoutOrder for the row frame.
--- @return Frame, table  The row frame and an api table with SetCoins(amount).
function CoinDisplay.Create(parent, layoutOrder)
    -- Row wrapper
    local row = Instance.new("Frame")
    row.Name = "CoinRow"
    row.LayoutOrder = layoutOrder or 2
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.Parent = parent

    -- Inner background (holds coin icon + value, leaves room for + button)
    local inner = Instance.new("Frame")
    inner.Name = "CoinInner"
    inner.Size = UDim2.new(1, -40, 1, 0) -- leave 40px on right for + button
    inner.BackgroundTransparency = 0
    inner.BackgroundColor3 = COLORS.rowBg
    inner.BorderSizePixel = 0
    inner.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = inner

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1
    stroke.Transparency = 0.85
    stroke.Parent = inner

    -- Coin icon (image or fallback text) — positioned absolutely on the left
    local coinAsset = nil
    if AssetCodes and type(AssetCodes.Get) == "function" then
        pcall(function() coinAsset = AssetCodes.Get("Coin") end)
    end
    if coinAsset and type(coinAsset) == "string" then
        local coinIcon = Instance.new("ImageLabel")
        coinIcon.Name = "CoinIcon"
        coinIcon.BackgroundTransparency = 1
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position = UDim2.new(0, 6, 0.5, 0)
        coinIcon.Size = UDim2.new(0, 24, 0, 24)
        coinIcon.Image = coinAsset
        coinIcon.ScaleType = Enum.ScaleType.Fit
        coinIcon.Parent = inner
    else
        local coinIcon = Instance.new("TextLabel")
        coinIcon.Name = "CoinTextIcon"
        coinIcon.BackgroundTransparency = 1
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position = UDim2.new(0, 6, 0.5, 0)
        coinIcon.Size = UDim2.new(0, 40, 0, 22)
        coinIcon.Font = Enum.Font.GothamBold
        coinIcon.Text = "Coins"
        coinIcon.TextColor3 = COLORS.gold
        coinIcon.TextScaled = true
        coinIcon.TextXAlignment = Enum.TextXAlignment.Left
        coinIcon.Parent = inner
    end

    -- Coin value label — centered in the inner frame
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "CoinsValue"
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBlack
    valueLabel.TextScaled = true
    valueLabel.TextColor3 = COLORS.white
    valueLabel.Text = "0"
    valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    valueLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    valueLabel.Size = UDim2.new(0.5, 0, 0.7, 0)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.Parent = inner

    -- "+" button on the right
    local plusBtn = Instance.new("TextButton")
    plusBtn.Name = "BuyCoinsBtn"
    plusBtn.AnchorPoint = Vector2.new(1, 0)
    plusBtn.Position = UDim2.new(1, 0, 0, 0)
    plusBtn.Size = UDim2.new(0, 36, 1, 0)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 60)
    plusBtn.BackgroundTransparency = 0.08
    plusBtn.BorderSizePixel = 0
    plusBtn.Font = Enum.Font.GothamBlack
    plusBtn.Text = "+"
    plusBtn.TextColor3 = Color3.new(1, 1, 1)
    plusBtn.TextSize = 20
    plusBtn.AutoButtonColor = false
    plusBtn.Parent = row
    local plusCorner = Instance.new("UICorner")
    plusCorner.CornerRadius = UDim.new(0, 6)
    plusCorner.Parent = plusBtn
    local plusStroke = Instance.new("UIStroke")
    plusStroke.Color = Color3.fromRGB(40, 200, 80)
    plusStroke.Thickness = 1
    plusStroke.Transparency = 0.5
    plusStroke.Parent = plusBtn
    plusBtn.MouseButton1Click:Connect(function()
        print("BuyCoins+ clicked")
    end)

    -- API
    local api = {}

    function api.SetCoins(amount)
        amount = math.max(0, tonumber(amount) or 0)
        valueLabel.Text = tostring(math.floor(amount))
    end

    -- Wire to server CurrencyService remotes
    local coinsEvent = ReplicatedStorage:FindFirstChild("CoinsUpdated")
    local getCoinsFn = ReplicatedStorage:FindFirstChild("GetCoins")
    if not coinsEvent then
        pcall(function() coinsEvent = ReplicatedStorage:WaitForChild("CoinsUpdated", 6) end)
    end
    if not getCoinsFn then
        pcall(function() getCoinsFn = ReplicatedStorage:WaitForChild("GetCoins", 6) end)
    end

    -- Listen for server pushes
    if coinsEvent and coinsEvent:IsA("RemoteEvent") then
        coinsEvent.OnClientEvent:Connect(function(amount)
            pcall(function() api.SetCoins(amount) end)
        end)
    end

    -- Fetch initial value
    if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
        local ok, result = pcall(function() return getCoinsFn:InvokeServer() end)
        if ok and type(result) == "number" then
            pcall(function() api.SetCoins(result) end)
        end
    end

    return row, api
end

return CoinDisplay
