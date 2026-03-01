local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local label = Instance.new("TextLabel")
label.Name = "CoinsLabel"
label.AnchorPoint = Vector2.new(0, 0.5)
label.Position = UDim2.new(0, 12, 0.5, 0)
label.Size = UDim2.new(0.6, 0, 0.8, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamSemibold
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(255, 215, 80)
label.Text = "Coins"
label.Parent = bg

local valueLabel = Instance.new("TextLabel")
valueLabel.Name = "CoinsValue"
valueLabel.AnchorPoint = Vector2.new(1, 0.5)
valueLabel.Position = UDim2.new(0.98, 0, 0.5, 0)
valueLabel.Size = UDim2.new(0.35, -12, 0.8, 0)
valueLabel.BackgroundTransparency = 1
valueLabel.Font = Enum.Font.GothamBlack
valueLabel.TextScaled = true
valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
valueLabel.Text = "0"
valueLabel.TextXAlignment = Enum.TextXAlignment.Right
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
