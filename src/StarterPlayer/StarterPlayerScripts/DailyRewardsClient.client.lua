--------------------------------------------------------------------------------
-- DailyRewardsClient.client.lua
-- StarterPlayerScripts – Manages the top-right Daily Rewards HUD button
-- and auto-popup logic. Communicates with DailyRewardServiceInit on the server.
--
-- This script:
--  1. Creates a small top-right Daily Rewards HUD button (next to Options)
--  2. Auto-opens the Daily Rewards popup on first eligible join
--  3. Handles claim flow and refreshes UI state
--  4. Shows an attention badge when a claim is available
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for viewport to be ready (same pattern as SideUI)
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

--------------------------------------------------------------------------------
-- Scaling helpers (match SideUI conventions)
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

--------------------------------------------------------------------------------
-- Load shared modules
--------------------------------------------------------------------------------
local AssetCodes
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("AssetCodes", 5)
    if mod and mod:IsA("ModuleScript") then AssetCodes = require(mod) end
end)

local DailyRewardsUI
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    if sideUI then
        local mod = sideUI:WaitForChild("DailyRewardsUI", 5)
        if mod and mod:IsA("ModuleScript") then DailyRewardsUI = require(mod) end
    end
end)

if not DailyRewardsUI then
    warn("[DailyRewardsClient] DailyRewardsUI module not found – aborting")
    return
end

-- MenuController integration: register DailyRewards as a managed menu so
-- the global menu-lock system knows when this popup is open.
local MenuController = nil
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    if sideUI then
        local mc = sideUI:FindFirstChild("MenuController")
        if mc then MenuController = require(mc) end
    end
end)
if MenuController then
    MenuController.RegisterMenu("DailyRewards", {
        open = function() end, -- opened by DailyRewardsUI.Open() directly
        close = function()
            if DailyRewardsUI.IsOpen() then DailyRewardsUI.Close() end
        end,
        closeInstant = function()
            if DailyRewardsUI.IsOpen() then DailyRewardsUI.Close() end
        end,
        isOpen = function()
            return DailyRewardsUI.IsOpen()
        end,
    })
end

--------------------------------------------------------------------------------
-- Tween helper
--------------------------------------------------------------------------------
local function tweenProp(inst, props, info)
    info = info or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local ok, tw = pcall(function() return TweenService:Create(inst, info, props) end)
    if ok and tw then tw:Play() return tw end
    return nil
end

--------------------------------------------------------------------------------
-- Remote references
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 15)
local drFolder      = remotesFolder and remotesFolder:WaitForChild("DailyRewards", 10)
local getStateRF    = drFolder and drFolder:FindFirstChild("GetDailyRewardState")
local claimRF       = drFolder and drFolder:FindFirstChild("ClaimDailyReward")
local stateUpdatedRE = drFolder and drFolder:FindFirstChild("DailyRewardStateUpdated")

if not drFolder then
    warn("[DailyRewardsClient] DailyRewards remotes folder not found – aborting")
    return
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local currentState       = nil
local popupCreated       = false
local autoPopupDone      = false
local screenGui          = nil  -- ScreenGui for both button and popup

--------------------------------------------------------------------------------
-- ScreenGui setup
--------------------------------------------------------------------------------
local existingGui = playerGui:FindFirstChild("DailyRewardsGui")
if existingGui then existingGui:Destroy() end

screenGui = Instance.new("ScreenGui")
screenGui.Name = "DailyRewardsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 310
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Register with MenuState so menu visibility is authoritative
do
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    if sideUI then
        local ms = sideUI:FindFirstChild("MenuState")
        if ms then
            pcall(function()
                local menuState = require(ms)
                if menuState and menuState.RegisterMenu then
                    menuState.RegisterMenu("DailyRewards", { gui = screenGui, isOpen = function() return DailyRewardsUI.IsOpen() end })
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- HUD Button (top-right, beside Options button)
-- Positioned to the LEFT of the Options button which sits at (1, -px(12), 0, px(10))
--------------------------------------------------------------------------------
local buttonSize = isMobile
    and math.clamp(px(40), 38, 46)
    or math.clamp(px(34), 32, 38)

-- Container (matches Options HUD button style)
local btnContainer = Instance.new("Frame")
btnContainer.Name = "DailyRewardsBtnContainer"
btnContainer.AnchorPoint = Vector2.new(1, 0)
btnContainer.Size = UDim2.new(0, buttonSize, 0, buttonSize)
-- Position to the left of the Options button with a small gap
btnContainer.Position = UDim2.new(1, -px(12) - buttonSize - px(8), 0, px(10))
btnContainer.BackgroundTransparency = 1
btnContainer.Parent = screenGui

local button = Instance.new("ImageButton")
button.Name = "DailyRewardsButton"
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Position = UDim2.fromScale(0.5, 0.5)
button.Size = UDim2.fromScale(1, 1)
button.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
button.BackgroundTransparency = 0.3
button.AutoButtonColor = false
button.Active = true
button.BorderSizePixel = 0
button.Image = ""
button.ZIndex = 305
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

-- Constructed gift-box icon (layered frames) – always renders reliably
-- Do NOT use an ImageLabel from AssetCodes here; the asset may be missing/invalid
-- and produce a blank button. The constructed icon is guaranteed visible.
do
    local iconSize = math.floor(buttonSize * 0.65)
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconGlyph"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFrame.Position = UDim2.fromScale(0.5, 0.52)
    iconFrame.Size = UDim2.new(0, iconSize, 0, iconSize)
    iconFrame.BackgroundTransparency = 1
    iconFrame.ZIndex = 306
    iconFrame.Parent = button

    -- Box body
    local boxBody = Instance.new("Frame")
    boxBody.Name = "Body"
    boxBody.Size = UDim2.fromScale(0.88, 0.50)
    boxBody.Position = UDim2.fromScale(0.06, 0.48)
    boxBody.BackgroundColor3 = Color3.fromRGB(255, 215, 80)
    boxBody.BorderSizePixel = 0
    boxBody.ZIndex = 307
    boxBody.Parent = iconFrame
    Instance.new("UICorner", boxBody).CornerRadius = UDim.new(0.12, 0)

    -- Box lid
    local boxLid = Instance.new("Frame")
    boxLid.Name = "Lid"
    boxLid.Size = UDim2.fromScale(0.98, 0.24)
    boxLid.Position = UDim2.fromScale(0.01, 0.26)
    boxLid.BackgroundColor3 = Color3.fromRGB(255, 230, 110)
    boxLid.BorderSizePixel = 0
    boxLid.ZIndex = 308
    boxLid.Parent = iconFrame
    Instance.new("UICorner", boxLid).CornerRadius = UDim.new(0.15, 0)

    -- Vertical ribbon
    local vRib = Instance.new("Frame")
    vRib.Name = "VRibbon"
    vRib.AnchorPoint = Vector2.new(0.5, 0)
    vRib.Size = UDim2.fromScale(0.16, 0.72)
    vRib.Position = UDim2.fromScale(0.5, 0.26)
    vRib.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    vRib.BorderSizePixel = 0
    vRib.ZIndex = 309
    vRib.Parent = iconFrame

    -- Horizontal ribbon
    local hRib = Instance.new("Frame")
    hRib.Name = "HRibbon"
    hRib.AnchorPoint = Vector2.new(0, 0.5)
    hRib.Size = UDim2.fromScale(0.88, 0.13)
    hRib.Position = UDim2.fromScale(0.06, 0.66)
    hRib.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    hRib.BorderSizePixel = 0
    hRib.ZIndex = 309
    hRib.Parent = iconFrame

    -- Bow knot
    local bow = Instance.new("Frame")
    bow.Name = "Bow"
    bow.AnchorPoint = Vector2.new(0.5, 1)
    bow.Size = UDim2.fromScale(0.30, 0.22)
    bow.Position = UDim2.fromScale(0.5, 0.30)
    bow.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    bow.BorderSizePixel = 0
    bow.ZIndex = 310
    bow.Parent = iconFrame
    Instance.new("UICorner", bow).CornerRadius = UDim.new(1, 0)
end

-- Attention badge dot (shown when claim available)
local badgeDot = Instance.new("Frame")
badgeDot.Name = "BadgeDot"
badgeDot.Size = UDim2.new(0, px(10), 0, px(10))
badgeDot.AnchorPoint = Vector2.new(1, 0)
badgeDot.Position = UDim2.new(1, px(2), 0, -px(2))
badgeDot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
badgeDot.Visible = false
badgeDot.ZIndex = 308
badgeDot.Parent = button
Instance.new("UICorner", badgeDot).CornerRadius = UDim.new(1, 0)
local badgeStroke = Instance.new("UIStroke")
badgeStroke.Color = Color3.fromRGB(12, 14, 28)
badgeStroke.Thickness = 1.5
badgeStroke.Parent = badgeDot

-- Badge pulse animation
local badgePulseConn = nil
local function startBadgePulse()
    if badgePulseConn then return end
    badgeDot.Visible = true
    local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local tw = TweenService:Create(badgeDot, pulseInfo, {
        BackgroundTransparency = 0.4
    })
    tw:Play()
    badgePulseConn = tw
end

local function stopBadgePulse()
    if badgePulseConn then
        pcall(function() badgePulseConn:Cancel() end)
        badgePulseConn = nil
    end
    badgeDot.Visible = false
    badgeDot.BackgroundTransparency = 0
end

-- Button hover/press styling (match Options button style)
local idleBgTransparency = 0.3
local hoverBgTransparency = 0.18
local isHovering = false

button.MouseEnter:Connect(function()
    isHovering = true
    tweenProp(button, { BackgroundTransparency = hoverBgTransparency })
    tweenProp(btnScale, { Scale = 1 })
end)
button.MouseLeave:Connect(function()
    isHovering = false
    tweenProp(button, { BackgroundTransparency = idleBgTransparency })
    tweenProp(btnScale, { Scale = 1 })
end)
button.MouseButton1Down:Connect(function()
    tweenProp(btnScale, { Scale = 0.94 }, TweenInfo.new(0.08))
end)
button.MouseButton1Up:Connect(function()
    tweenProp(btnScale, { Scale = 1 })
end)

-- Responsive layout (match Options button sizing logic)
local function updateLayout()
    local bs = isMobile
        and math.clamp(px(40), 38, 46)
        or math.clamp(px(34), 32, 38)
    btnContainer.Size = UDim2.new(0, bs, 0, bs)
    btnContainer.Position = UDim2.new(1, -px(12) - bs - px(8), 0, px(10))
    btnCorner.CornerRadius = UDim.new(0, math.max(8, math.floor(bs * 0.24)))
end

local camViewConn
local function bindViewport()
    if camViewConn then camViewConn:Disconnect(); camViewConn = nil end
    local cam = workspace.CurrentCamera
    if cam then
        camViewConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
    end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindViewport()
    task.defer(updateLayout)
end)
bindViewport()
task.defer(updateLayout)

--------------------------------------------------------------------------------
-- Popup management
--------------------------------------------------------------------------------
local updateBadgeState  -- forward declaration

local function ensurePopup()
    if popupCreated then return end
    popupCreated = true

    DailyRewardsUI.Create(screenGui, currentState or {}, {
        onClaim = function()
            -- Request claim from server (returns success, message, updatedState)
            if not claimRF then return end
            local ok, success, message, updatedState = pcall(function()
                return claimRF:InvokeServer()
            end)
            if not ok then return end

            -- Use the updatedState from the claim response if available
            if type(updatedState) == "table" then
                currentState = updatedState
            elseif getStateRF then
                -- Fallback: fetch fresh state if server didn't include it
                local stOk, st = pcall(function() return getStateRF:InvokeServer() end)
                if stOk and type(st) == "table" then
                    currentState = st
                end
            end

            if currentState then
                DailyRewardsUI.Refresh(currentState)
                -- Play claim animation on the just-claimed day
                if success and currentState.currentDay and currentState.currentDay > 0 then
                    DailyRewardsUI.PlayClaimAnimation(currentState.currentDay)
                    pcall(function()
                        local cs = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClaimSound"))
                        cs.Play()
                    end)
                end
            end
            updateBadgeState()
        end,
        onClose = function()
            updateBadgeState()
        end,
    })
end

local function openPopup()
    if DailyRewardsUI.IsOpen() then return end

    -- Close any open SideUI menus first
    if _G.SideUI and _G.SideUI.MenuController then
        pcall(function() _G.SideUI.MenuController.CloseAllMenus() end)
    end

    -- Fetch fresh state before showing
    if getStateRF then
        local ok, state = pcall(function() return getStateRF:InvokeServer() end)
        if ok and type(state) == "table" then
            currentState = state
        end
    end

    ensurePopup()
    DailyRewardsUI.Refresh(currentState or {})
    DailyRewardsUI.Open()
end

-- Badge state update
updateBadgeState = function()
    if currentState and currentState.canClaimToday and not currentState.alreadyClaimed then
        startBadgePulse()
    else
        stopBadgePulse()
    end
end

-- Button click → toggle popup
button.Activated:Connect(function()
    if DailyRewardsUI.IsOpen() then
        DailyRewardsUI.Close()
    else
        openPopup()
    end
end)

--------------------------------------------------------------------------------
-- Server state push listener (auto-popup on first eligible join)
--------------------------------------------------------------------------------
if stateUpdatedRE then
    stateUpdatedRE.OnClientEvent:Connect(function(state)
        if type(state) ~= "table" then return end
        currentState = state

        -- Auto-popup on first eligible join (server signals with autoPopup=true)
        if state.canClaimToday and state.autoPopup and not autoPopupDone then
            autoPopupDone = true
            -- Small delay so player sees the world first
            task.delay(1.5, function()
                if not DailyRewardsUI.IsOpen() then
                    openPopup()
                end
            end)
        end

        -- Refresh UI if popup is open
        if DailyRewardsUI.IsOpen() then
            DailyRewardsUI.Refresh(currentState)
        end

        updateBadgeState()
    end)
end

--------------------------------------------------------------------------------
-- Initial state fetch (fallback if server push didn't arrive yet)
--------------------------------------------------------------------------------
task.spawn(function()
    task.wait(4)
    if not currentState and getStateRF then
        local ok, state = pcall(function() return getStateRF:InvokeServer() end)
        if ok and type(state) == "table" then
            currentState = state
            updateBadgeState()

            -- Auto-popup if eligible and not yet shown
            if state.canClaimToday and not state.alreadyClaimed and not autoPopupDone then
                autoPopupDone = true
                task.delay(0.5, function()
                    if not DailyRewardsUI.IsOpen() then
                        openPopup()
                    end
                end)
            end
        end
    end
end)

print("[DailyRewardsClient] Daily Rewards HUD initialized")
