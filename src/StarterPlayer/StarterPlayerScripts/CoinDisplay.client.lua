local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- try to require AssetCodes from ReplicatedStorage (optional)
local AssetCodes = nil
pcall(function()
    AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes", 5))
end)

-- Create a simple coins display anchored to the left side of the screen
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CoinDisplay"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0, 0.5)
root.Position = UDim2.new(0, 10, 0.5, -20)
root.Size = UDim2.new(0, 160, 0, 40)
root.BackgroundTransparency = 1
root.Parent = screenGui

local bg = Instance.new("Frame")
bg.AnchorPoint = Vector2.new(0, 0)
bg.Position = UDim2.new(0, 0, 0, 0)
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
bg.BackgroundTransparency = 0.08
bg.BorderSizePixel = 0
bg.Parent = root

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = bg

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 215, 80)
stroke.Thickness = 1.2
stroke.Transparency = 0.6
stroke.Parent = bg

-- coin image on the left (falls back to a text label if no asset available)
local coinIcon
local iconSize = 24
local coinAsset = nil
if AssetCodes and type(AssetCodes.Get) == "function" then
    pcall(function() coinAsset = AssetCodes.Get("Coin") end)
end
if coinAsset and type(coinAsset) == "string" then
    coinIcon = Instance.new("ImageLabel")
    coinIcon.Name = "CoinIcon"
    coinIcon.AnchorPoint = Vector2.new(0, 0.5)
    coinIcon.Position = UDim2.new(0, 12, 0.5, 0)
    coinIcon.Size = UDim2.new(0, iconSize, 0, iconSize)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Image = coinAsset
    coinIcon.ScaleType = Enum.ScaleType.Fit
    coinIcon.Parent = bg
else
    coinIcon = Instance.new("TextLabel")
    coinIcon.Name = "CoinsLabel"
    coinIcon.AnchorPoint = Vector2.new(0, 0.5)
    coinIcon.Position = UDim2.new(0, 12, 0.5, 0)
    coinIcon.Size = UDim2.new(0, 60, 0.8, 0)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Font = Enum.Font.GothamSemibold
    coinIcon.TextScaled = true
    coinIcon.TextColor3 = Color3.fromRGB(255, 215, 80)
    coinIcon.Text = "Coins"
    coinIcon.Parent = bg
end

local valueLabel = Instance.new("TextLabel")
valueLabel.Name = "CoinsValue"
valueLabel.AnchorPoint = Vector2.new(0, 0.5)
valueLabel.Position = UDim2.new(0, 12 + iconSize + 8, 0.5, 0)
valueLabel.Size = UDim2.new(0, 88, 0.8, 0)
valueLabel.BackgroundTransparency = 1
valueLabel.Font = Enum.Font.GothamBlack
valueLabel.TextScaled = true
valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
valueLabel.Text = "0"
valueLabel.TextXAlignment = Enum.TextXAlignment.Left
valueLabel.Parent = bg

-- Subscribe to server-provided coin updates via ReplicatedStorage
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local coinsEvent = ReplicatedStorage:FindFirstChild("CoinsUpdated")
local getCoinsFn = ReplicatedStorage:FindFirstChild("GetCoins")

-- wait for the remote objects (short timeout) — if missing, continue gracefully
if not coinsEvent then
    coinsEvent = ReplicatedStorage:WaitForChild("CoinsUpdated", 10)
end
if not getCoinsFn then
    getCoinsFn = ReplicatedStorage:WaitForChild("GetCoins", 10)
end

-- update function
local function setCoinsDisplay(n)
    valueLabel.Text = tostring(n or 0)
end

-- Listen for server pushes
if coinsEvent and coinsEvent:IsA("RemoteEvent") then
    coinsEvent.OnClientEvent:Connect(function(amount)
        setCoinsDisplay(amount)
    end)
end

-- Request initial value from server (if available)
if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
    local ok, result = pcall(function()
        return getCoinsFn:InvokeServer()
    end)
    if ok and type(result) == "number" then
        setCoinsDisplay(result)
    end
end
