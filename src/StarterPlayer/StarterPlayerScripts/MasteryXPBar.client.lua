-- MasteryXPBar.client.lua
-- Shows a small mastery XP progress bar at bottom-right when any mastery XP is gained.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local masteryRemote = ReplicatedStorage:WaitForChild("WeaponMasteryUpdated", 10)
if not masteryRemote or not masteryRemote:IsA("RemoteEvent") then
    return
end

-- Configuration
-- Toggle during testing: when true the bar stays visible always
local ALWAYS_SHOW = false

local DISPLAY_SECONDS = 3
local FADE_OUT_TIME = 0.4
-- Scale-based sizing (fraction of viewport)
local SCALE_W = 0.24
local SCALE_H = 0.06
local PAD_X = 0.03
local PAD_Y = 0.03

-- Build UI
local gui = Instance.new("ScreenGui")
gui.Name = "MasteryXPBarGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

audio = nil

local container = Instance.new("Frame")
container.Name = "MasteryXPContainer"
container.AnchorPoint = Vector2.new(1, 1)
container.Position = UDim2.new(0.93, 0, 0.99, 0)
container.Size = UDim2.new(0.15, 0, 0.04, 0)
container.BackgroundTransparency = 1
container.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
container.BorderSizePixel = 0
container.ZIndex = 50
container.Visible = ALWAYS_SHOW or false
container.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = container

local barBack = Instance.new("Frame")
barBack.Name = "BarBack"
barBack.AnchorPoint = Vector2.new(0, 0.5)
barBack.Position = UDim2.new(0.02, 0, 0.5, 0)
barBack.Size = UDim2.new(0.96, 0, 0.5, 0)
barBack.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
barBack.BackgroundTransparency = 0.2
barBack.BorderSizePixel = 0
barBack.Parent = container

local backCorner = Instance.new("UICorner")
backCorner.CornerRadius = UDim.new(0, 6)
backCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(210, 168, 0)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = barFill

local txt = Instance.new("TextLabel")
txt.Name = "Label"
txt.AnchorPoint = Vector2.new(0, 0)
txt.Position = UDim2.new(0.03, 0, 0, 0)
txt.Size = UDim2.new(0.6, 0, 0.5, 0)
txt.BackgroundTransparency = 1
txt.Font = Enum.Font.GothamBold
txt.TextScaled = true
txt.TextColor3 = Color3.fromRGB(240, 240, 240)
txt.TextXAlignment = Enum.TextXAlignment.Left
txt.Text = "Mastery"
txt.Parent = container
local txtConstraint = Instance.new("UITextSizeConstraint")
txtConstraint.MaxTextSize = 22
txtConstraint.MinTextSize = 10
txtConstraint.Parent = txt

local xpText = Instance.new("TextLabel")
xpText.Name = "XPText"
xpText.AnchorPoint = Vector2.new(1, 0)
xpText.Position = UDim2.new(0.97, 0, 0, 0)
xpText.Size = UDim2.new(0.45, 0, 0.5, 0)
xpText.BackgroundTransparency = 1
xpText.Font = Enum.Font.Gotham
xpText.TextScaled = true
xpText.TextColor3 = Color3.fromRGB(200, 200, 200)
xpText.TextXAlignment = Enum.TextXAlignment.Right
xpText.Text = "+0 XP"
xpText.Parent = container
local xpConstraint = Instance.new("UITextSizeConstraint")
xpConstraint.MaxTextSize = 18
xpConstraint.MinTextSize = 10
xpConstraint.Parent = xpText

-- Simple show/fade logic
local hideTask = nil
local visible = false

local function cancelHide()
    hideTask = nil
end

local function startHideCountdown()
    if ALWAYS_SHOW then
        return
    end
    -- cancel existing
    if hideTask then
        hideTask.cancel = true
    end
    local token = { cancel = false }
    hideTask = token
    task.spawn(function()
        local waited = 0
        local interval = 0.1
        while waited < DISPLAY_SECONDS do
            task.wait(interval)
            if token.cancel then return end
            waited = waited + interval
        end
        if token.cancel then return end
        -- fade out
        local fadeInfo = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(container, fadeInfo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(barBack, fadeInfo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(barFill, fadeInfo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(txt, fadeInfo, {TextTransparency = 1}):Play()
        TweenService:Create(xpText, fadeInfo, {TextTransparency = 1}):Play()
        task.wait(FADE_OUT_TIME + 0.05)
        if token.cancel then return end
        container.Visible = false
        -- reset transparencies for next show
        container.BackgroundTransparency = 0.12
        barBack.BackgroundTransparency = 0
        barFill.BackgroundTransparency = 0
        txt.TextTransparency = 0
        xpText.TextTransparency = 0
        hideTask = nil
    end)
end

local function showForXP(payload, meta)
    if type(payload) ~= "table" then return end
    local delta = (type(meta) == "table" and tonumber(meta.deltaXP) or 0) or 0
    if not (delta and delta > 0) then return end

    local progress = tonumber(payload.progress) or 0
    local level = tonumber(payload.level) or 0
    local weaponName = tostring(payload.weaponName or "Mastery")

    -- update texts
    txt.Text = weaponName
    local displayXP = string.format("+%s XP", tostring(delta))
    xpText.Text = displayXP

    -- ensure visible
    if not container.Visible then
        container.Visible = true
        -- keep container background fully transparent per request
        container.BackgroundTransparency = 1
        barBack.BackgroundTransparency = 0
        barFill.BackgroundTransparency = 0
        txt.TextTransparency = 0
        xpText.TextTransparency = 0
    end

    -- tween fill to progress fraction
    local fillInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local targetSize = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
    TweenService:Create(barFill, fillInfo, {Size = targetSize}):Play()

    -- restart hide countdown
    startHideCountdown()
end

masteryRemote.OnClientEvent:Connect(function(instanceId, payload, meta)
    -- payload is mastery payload (see server GetMasteryPayloadForWeaponName) and meta includes deltaXP
    pcall(showForXP, payload, meta)
end)
