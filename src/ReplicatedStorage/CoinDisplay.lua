-- CoinDisplay ModuleScript
-- Provides a reusable coin-row UI element wired to CurrencyService remotes.
-- Usage from a client LocalScript:
--   local CoinDisplay = require(ReplicatedStorage:WaitForChild("CoinDisplay"))
--   local row, api = CoinDisplay.Create(parentFrame, layoutOrder)
--   -- api.SetCoins(123)   (manual override, but auto-updates from server)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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

-- Scale pixel values proportionally to viewport height (reference: 1080p)
local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 1080
    return math.max(1, math.round(base * screenY / 1080))
    end

    -- Device text scale (smaller on desktop)
    local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75
    local function tpx(base)
        return math.max(1, math.round(px(base) * deviceTextScale))
    end

    local CoinDisplay = {}

--- Creates the coin-row Frame, wires it to server remotes, and returns (frame, api).
--- @param parent Instance  The parent GUI object to place the row inside.
--- @param layoutOrder number  Optional LayoutOrder for the row frame.
--- @return Frame, table  The row frame and an api table with SetCoins(amount).
function CoinDisplay.Create(parent, layoutOrder)
    -- Row wrapper (responsive height)
    local row = Instance.new("Frame")
    row.Name = "CoinRow"
    row.LayoutOrder = layoutOrder or 2
    row.BackgroundTransparency = 1
    row.Parent = parent

    local function calcRowHeight()
        local screenY = 720
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            screenY = cam.ViewportSize.Y
        end
        return math.max(28, math.floor(screenY * 0.05))
    end
    row.Size = UDim2.new(1, 0, 0, calcRowHeight())

    -- Inner background (full width, coin icon + value)
    local inner = Instance.new("Frame")
    inner.Name = "CoinInner"
    inner.Size = UDim2.new(1, 0, 1, 0) -- full width matching shop button
    inner.BackgroundTransparency = 0
    inner.BackgroundColor3 = Color3.new(1, 1, 1) -- white so UIGradient shows through
    inner.BorderSizePixel = 0
    inner.ClipsDescendants = false
    inner.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(6))
    corner.Parent = inner

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inner

    -- Team-color gradient background
    local function getTeamSeq()
        local lp = Players.LocalPlayer
        local team = lp and lp.Team
        local base
        if team and team.Name ~= "Neutral" then
            if team.Name == "Blue" then
                base = Color3.fromRGB(12, 51, 168) -- royal blue
            elseif team.Name == "Red" then
                base = Color3.fromRGB(202, 24, 24)
            else
                base = team.TeamColor.Color
            end
            -- darken team color slightly for better contrast
            base = base:Lerp(Color3.new(0, 0, 0), 0.12)
        else
            base = Color3.fromRGB(35, 35, 40) -- default: dark gray (toolbar style)
        end
        local dark = base:Lerp(Color3.fromRGB(4, 4, 6), 0.72)
        return ColorSequence.new({
            ColorSequenceKeypoint.new(0, dark),
            ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(1,1,1), 0.12)),
        })
    end
    local coinGradient = Instance.new("UIGradient")
    coinGradient.Rotation = 135
    coinGradient.Color = getTeamSeq()
    coinGradient.Parent = inner
    local lp = Players.LocalPlayer
    if lp then
        lp:GetPropertyChangedSignal("Team"):Connect(function()
            if coinGradient and coinGradient.Parent then
                coinGradient.Color = getTeamSeq()
            end
        end)
    end

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
        coinIcon.Position = UDim2.new(0, px(6), 0.5, 0)
        local function updateCoinIcon()
            local h = row.AbsoluteSize.Y > 0 and row.AbsoluteSize.Y or calcRowHeight()
            local s = math.max(18, math.floor(h * 0.7))
            coinIcon.Size = UDim2.new(0, s, 0, s)
        end
        updateCoinIcon()
        coinIcon.Image = coinAsset
        coinIcon.ScaleType = Enum.ScaleType.Fit
        coinIcon.Parent = inner
        row:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCoinIcon)
    else
        local coinIcon = Instance.new("TextLabel")
        coinIcon.Name = "CoinTextIcon"
        coinIcon.BackgroundTransparency = 1
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position = UDim2.new(0, px(6), 0.5, 0)
        coinIcon.Size = UDim2.new(0, px(40), 0, px(22))
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
    valueLabel.TextColor3 = COLORS.gold
    valueLabel.Text = "0"
    valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    valueLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    valueLabel.Size = UDim2.new(0.5, 0, 0.7, 0)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.Parent = inner

    -- "+" button — small, sits on the right edge of the coin box
    local plusBtn = Instance.new("TextButton")
    plusBtn.Name = "BuyCoinsBtn"
    plusBtn.AnchorPoint = Vector2.new(1, 0)
    local function updatePlus()
        local h = row.AbsoluteSize.Y > 0 and row.AbsoluteSize.Y or calcRowHeight()
        local s = math.max(20, math.floor(h * 0.68))
        plusBtn.Position = UDim2.new(1, math.max(8, math.floor(s * 0.45)), 0, math.max(4, math.floor((h - s) / 2)))
        plusBtn.Size = UDim2.new(0, s, 0, s)
    end
    updatePlus()
    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePlus)
    plusBtn.BackgroundColor3 = Color3.fromRGB(30, 160, 60)
    plusBtn.BackgroundTransparency = 0.00
    plusBtn.BorderSizePixel = 0
    plusBtn.Font = Enum.Font.GothamBlack
    plusBtn.Text = "+"
    plusBtn.TextColor3 = COLORS.gold
    plusBtn.TextSize = tpx(30)
    plusBtn.TextScaled = true
    plusBtn.AutoButtonColor = false
    plusBtn.ZIndex = 3
    plusBtn.Parent = inner
    local plusCorner = Instance.new("UICorner")
    plusCorner.CornerRadius = UDim.new(0, px(5))
    plusCorner.Parent = plusBtn
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

    -- Fetch initial value with a small retry loop to avoid race with server load
    if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
        local function tryFetch()
            local ok, result = pcall(function() return getCoinsFn:InvokeServer() end)
            if ok and type(result) == "number" then
                pcall(function() api.SetCoins(result) end)
                return true
            end
            return false
        end
        -- try immediately, then a couple more times in case server is still loading the player's data
        if not tryFetch() then
            task.delay(0.2, function()
                if not tryFetch() then
                    task.delay(0.5, function() pcall(tryFetch) end)
                end
            end)
        end
    end

    return row, api
end

return CoinDisplay
