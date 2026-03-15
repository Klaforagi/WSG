--------------------------------------------------------------------------------
-- AchievementToast.client.lua
-- Displays a brief "Achievement Complete!" toast popup on the right side of
-- the screen when the server notifies of a newly completed achievement.
-- Placed in StarterPlayer > StarterPlayerScripts.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Load achievement definitions for titles and icons
local AchievementDefs
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("AchievementDefs", 10)
    if mod and mod:IsA("ModuleScript") then
        AchievementDefs = require(mod)
    end
end)

--------------------------------------------------------------------------------
-- Responsive scaling (matches SideUI)
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------
local GOLD      = Color3.fromRGB(255, 215, 60)
local WHITE     = Color3.fromRGB(245, 245, 252)
local DARK_BG   = Color3.fromRGB(22, 24, 38)
local STROKE_C  = Color3.fromRGB(255, 200, 40)
local DIM_TEXT   = Color3.fromRGB(180, 185, 200)

--------------------------------------------------------------------------------
-- ScreenGui (persistent, above most UI)
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "AchievementToastGui"
screenGui.ResetOnSpawn  = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder  = 300
screenGui.Parent        = playerGui

--------------------------------------------------------------------------------
-- Toast queue (only show one at a time, queue extras)
--------------------------------------------------------------------------------
local toastQueue  = {}
local isShowing   = false

local function showToast(title, icon, reward)
    -- Toast frame
    local toast = Instance.new("Frame")
    toast.Name                = "Toast"
    toast.BackgroundColor3    = DARK_BG
    toast.BackgroundTransparency = 0.05
    toast.Size                = UDim2.new(0, px(320), 0, px(72))
    toast.AnchorPoint         = Vector2.new(1, 0)
    toast.Position            = UDim2.new(1, px(340), 0, px(120)) -- start off-screen right
    toast.Parent              = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(12))
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color       = STROKE_C
    stroke.Thickness   = 1.8
    stroke.Transparency = 0.2
    stroke.Parent      = toast

    -- Gold accent bar (left edge)
    local accentBar = Instance.new("Frame")
    accentBar.Name                = "Accent"
    accentBar.BackgroundColor3    = GOLD
    accentBar.BorderSizePixel     = 0
    accentBar.Size                = UDim2.new(0, px(4), 0.75, 0)
    accentBar.AnchorPoint         = Vector2.new(0, 0.5)
    accentBar.Position            = UDim2.new(0, px(6), 0.5, 0)
    accentBar.Parent              = toast
    local acCr = Instance.new("UICorner")
    acCr.CornerRadius = UDim.new(0.5, 0)
    acCr.Parent = accentBar

    -- Icon glyph
    local iconLbl = Instance.new("TextLabel")
    iconLbl.Name                = "Icon"
    iconLbl.BackgroundTransparency = 1
    iconLbl.Font                = Enum.Font.GothamBold
    iconLbl.Text                = icon or "★"
    iconLbl.TextColor3          = GOLD
    iconLbl.TextSize            = math.max(20, math.floor(px(24)))
    iconLbl.Size                = UDim2.new(0, px(36), 0, px(36))
    iconLbl.AnchorPoint         = Vector2.new(0, 0.5)
    iconLbl.Position            = UDim2.new(0, px(16), 0.5, 0)
    iconLbl.Parent              = toast

    -- "Achievement Complete!" header
    local headerLbl = Instance.new("TextLabel")
    headerLbl.Name               = "Header"
    headerLbl.BackgroundTransparency = 1
    headerLbl.Font               = Enum.Font.GothamBold
    headerLbl.Text               = "ACHIEVEMENT COMPLETE!"
    headerLbl.TextColor3         = GOLD
    headerLbl.TextSize           = math.max(11, math.floor(px(11)))
    headerLbl.TextXAlignment     = Enum.TextXAlignment.Left
    headerLbl.Size               = UDim2.new(1, -px(60), 0, px(16))
    headerLbl.Position           = UDim2.new(0, px(56), 0, px(10))
    headerLbl.Parent             = toast

    -- Achievement title
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name               = "Title"
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font               = Enum.Font.GothamBold
    titleLbl.Text               = title or "Achievement"
    titleLbl.TextColor3         = WHITE
    titleLbl.TextSize           = math.max(14, math.floor(px(16)))
    titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
    titleLbl.Size               = UDim2.new(1, -px(60), 0, px(20))
    titleLbl.Position           = UDim2.new(0, px(56), 0, px(28))
    titleLbl.Parent             = toast

    -- Reward text
    local rewardLbl = Instance.new("TextLabel")
    rewardLbl.Name               = "Reward"
    rewardLbl.BackgroundTransparency = 1
    rewardLbl.Font               = Enum.Font.GothamMedium
    rewardLbl.Text               = "+" .. tostring(reward or 0) .. " coins"
    rewardLbl.TextColor3         = DIM_TEXT
    rewardLbl.TextSize           = math.max(10, math.floor(px(11)))
    rewardLbl.TextXAlignment     = Enum.TextXAlignment.Left
    rewardLbl.Size               = UDim2.new(1, -px(60), 0, px(14))
    rewardLbl.Position           = UDim2.new(0, px(56), 0, px(50))
    rewardLbl.Parent             = toast

    -- Animate in
    local TWEEN_IN  = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TWEEN_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    local targetPos = UDim2.new(1, -px(16), 0, px(120))
    TweenService:Create(toast, TWEEN_IN, {Position = targetPos}):Play()

    -- Hold for 3.5 seconds, then slide out
    task.delay(3.5, function()
        if toast and toast.Parent then
            local outTween = TweenService:Create(toast, TWEEN_OUT,
                {Position = UDim2.new(1, px(340), 0, px(120))})
            outTween:Play()
            outTween.Completed:Connect(function()
                if toast and toast.Parent then toast:Destroy() end
                -- Process next in queue
                isShowing = false
                if #toastQueue > 0 then
                    local next = table.remove(toastQueue, 1)
                    isShowing = true
                    showToast(next.title, next.icon, next.reward)
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Public function (exposed via _G for DailyQuestsUI to call)
--------------------------------------------------------------------------------
_G.ShowAchievementToast = function(achievementId)
    local def
    if AchievementDefs and AchievementDefs.ById then
        def = AchievementDefs.ById[achievementId]
    end
    local title  = def and def.title or achievementId
    local icon   = def and def.icon or "★"
    local reward = def and def.reward or 0

    if isShowing then
        table.insert(toastQueue, { title = title, icon = icon, reward = reward })
    else
        isShowing = true
        showToast(title, icon, reward)
    end
end

--------------------------------------------------------------------------------
-- Also listen directly for AchievementProgress in case the UI is closed
--------------------------------------------------------------------------------
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then return end
    local achievProgressRE = remotes:WaitForChild("AchievementProgress", 10)
    if not achievProgressRE or not achievProgressRE:IsA("RemoteEvent") then return end

    achievProgressRE.OnClientEvent:Connect(function(achId, _, completed)
        if achId == "__full_refresh" then return end
        if completed and _G.ShowAchievementToast then
            pcall(function() _G.ShowAchievementToast(achId) end)
        end
    end)
end)
