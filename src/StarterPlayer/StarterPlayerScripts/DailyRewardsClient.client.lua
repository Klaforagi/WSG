--------------------------------------------------------------------------------
-- DailyRewardsClient.client.lua (Final Fixed Version)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for viewport
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

--------------------------------------------------------------------------------
-- Load DailyRewardsUI module
--------------------------------------------------------------------------------
local DailyRewardsUI
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    if sideUI then
        local mod = sideUI:WaitForChild("DailyRewardsUI", 5)
        if mod and mod:IsA("ModuleScript") then
            DailyRewardsUI = require(mod)
        end
    end
end)

if not DailyRewardsUI then
    warn("[DailyRewardsClient] DailyRewardsUI module not found!")
    return
end

--------------------------------------------------------------------------------
-- Find your pre-built popup GUI
--------------------------------------------------------------------------------
local popupGui = playerGui:FindFirstChild("DailyRewardsGui")

if not popupGui then
    warn("DailyRewardsGui not found in PlayerGui!")
    return
end

--------------------------------------------------------------------------------
-- Create a SEPARATE ScreenGui just for the HUD button (always visible)
--------------------------------------------------------------------------------
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "DailyRewardsHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder = 500
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui

--------------------------------------------------------------------------------
-- Get Remotes
--------------------------------------------------------------------------------
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local drFolder = remotes:FindFirstChild("DailyRewards")
local getStateRF = drFolder and drFolder:FindFirstChild("GetDailyRewardState")
local claimRF = drFolder and drFolder:FindFirstChild("ClaimDailyReward")

--------------------------------------------------------------------------------
-- Initialize the popup UI (with claim callback)
--------------------------------------------------------------------------------
DailyRewardsUI.Create(popupGui, nil, {
    onClaim = function()
        if not claimRF then return end

        local success, message = claimRF:InvokeServer()

        if success then
            if getStateRF then
                local newState = getStateRF:InvokeServer()
                DailyRewardsUI.Refresh(newState)
            end
        else
            warn("[DailyRewardsClient] Claim failed:", message)
        end
    end
})

--------------------------------------------------------------------------------
-- Top Right Gift Box Button (on its own ScreenGui - always visible)
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local isMobile = UserInputService.TouchEnabled

local function getHudUtilityButtonMetrics()
    local shortSide = math.min(workspace.CurrentCamera.ViewportSize.X, workspace.CurrentCamera.ViewportSize.Y)
    local buttonSize = isMobile and math.clamp(shortSide * 0.072, 52, 78) or math.clamp(shortSide * 0.048, 44, 62)
    local insetX = math.clamp(buttonSize * 0.26, 12, 20)
    local insetY = math.clamp(buttonSize * 0.22, 10, 16)
    local gap = math.clamp(buttonSize * 0.16, 6, 12)
    
    return {
        buttonSize = math.floor(buttonSize + 0.5),
        insetX = math.floor(insetX + 0.5),
        insetY = math.floor(insetY + 0.5),
        gap = math.floor(gap + 0.5),
    }
end

local hudMetrics = getHudUtilityButtonMetrics()
local buttonSize = hudMetrics.buttonSize

local btnContainer = Instance.new("Frame")
btnContainer.Name = "DailyRewardsBtnContainer"
btnContainer.AnchorPoint = Vector2.new(1, 0)
btnContainer.Size = UDim2.new(0, buttonSize, 0, buttonSize)
btnContainer.Position = UDim2.new(1, -hudMetrics.insetX - buttonSize - hudMetrics.gap, 0, hudMetrics.insetY)
btnContainer.BackgroundTransparency = 1
btnContainer.Parent = hudGui   -- ← Button is on its own ScreenGui now

local button = Instance.new("ImageButton")
button.Name = "DailyRewardsButton"
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Position = UDim2.fromScale(0.5, 0.5)
button.Size = UDim2.fromScale(1, 1)
button.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
button.BackgroundTransparency = 0.3
button.AutoButtonColor = false
button.BorderSizePixel = 0
button.ZIndex = 600
button.Parent = btnContainer

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, math.max(8, math.floor(buttonSize * 0.24)))
btnCorner.Parent = button

local btnStroke = Instance.new("UIStroke")
btnStroke.Color = Color3.fromRGB(255, 255, 255)
btnStroke.Thickness = 1
btnStroke.Transparency = 0.84
btnStroke.Parent = button

local btnScale = Instance.new("UIScale")
btnScale.Parent = button

-- Gift Box Icon
do
    local iconSize = math.floor(buttonSize * 0.65)
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconGlyph"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFrame.Position = UDim2.fromScale(0.5, 0.52)
    iconFrame.Size = UDim2.new(0, iconSize, 0, iconSize)
    iconFrame.BackgroundTransparency = 1
    iconFrame.ZIndex = 610
    iconFrame.Parent = button

    local boxBody = Instance.new("Frame")
    boxBody.Name = "Body"
    boxBody.Size = UDim2.fromScale(0.88, 0.50)
    boxBody.Position = UDim2.fromScale(0.06, 0.48)
    boxBody.BackgroundColor3 = Color3.fromRGB(255, 215, 80)
    boxBody.BorderSizePixel = 0
    boxBody.ZIndex = 611
    boxBody.Parent = iconFrame
    Instance.new("UICorner", boxBody).CornerRadius = UDim.new(0.12, 0)

    local boxLid = Instance.new("Frame")
    boxLid.Name = "Lid"
    boxLid.Size = UDim2.fromScale(0.98, 0.24)
    boxLid.Position = UDim2.fromScale(0.01, 0.26)
    boxLid.BackgroundColor3 = Color3.fromRGB(255, 230, 110)
    boxLid.BorderSizePixel = 0
    boxLid.ZIndex = 612
    boxLid.Parent = iconFrame
    Instance.new("UICorner", boxLid).CornerRadius = UDim.new(0.15, 0)

    local vRib = Instance.new("Frame")
    vRib.Name = "VRibbon"
    vRib.AnchorPoint = Vector2.new(0.5, 0)
    vRib.Size = UDim2.fromScale(0.16, 0.72)
    vRib.Position = UDim2.fromScale(0.5, 0.26)
    vRib.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    vRib.BorderSizePixel = 0
    vRib.ZIndex = 613
    vRib.Parent = iconFrame

    local hRib = Instance.new("Frame")
    hRib.Name = "HRibbon"
    hRib.AnchorPoint = Vector2.new(0, 0.5)
    hRib.Size = UDim2.fromScale(0.88, 0.13)
    hRib.Position = UDim2.fromScale(0.06, 0.66)
    hRib.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    hRib.BorderSizePixel = 0
    hRib.ZIndex = 613
    hRib.Parent = iconFrame

    local bow = Instance.new("Frame")
    bow.Name = "Bow"
    bow.AnchorPoint = Vector2.new(0.5, 1)
    bow.Size = UDim2.fromScale(0.30, 0.22)
    bow.Position = UDim2.fromScale(0.5, 0.30)
    bow.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    bow.BorderSizePixel = 0
    bow.ZIndex = 614
    bow.Parent = iconFrame
    Instance.new("UICorner", bow).CornerRadius = UDim.new(1, 0)
end

-- Hover Effects
button.MouseEnter:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.1), {BackgroundTransparency = 0.18}):Play()
    TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
end)

button.MouseLeave:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.1), {BackgroundTransparency = 0.3}):Play()
    TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1}):Play()
end)

button.MouseButton1Down:Connect(function()
    TweenService:Create(btnScale, TweenInfo.new(0.08), {Scale = 0.94}):Play()
end)

button.MouseButton1Up:Connect(function()
    TweenService:Create(btnScale, TweenInfo.new(0.1), {Scale = 1}):Play()
end)

-- Button Click → Open/Close popup
button.Activated:Connect(function()
    if DailyRewardsUI.IsOpen() then
        DailyRewardsUI.Close()
    else
        if getStateRF then
            local state = getStateRF:InvokeServer()
            DailyRewardsUI.Refresh(state)
        end
        DailyRewardsUI.Open()
    end
end)

print("[DailyRewardsClient] Button is now always visible (separate HUD ScreenGui)")