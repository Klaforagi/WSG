--------------------------------------------------------------------------------
-- DailyRewardsClient.client.lua
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create a dedicated high-priority ScreenGui for the HUD button
local hudScreenGui = Instance.new("ScreenGui")
hudScreenGui.Name = "DailyRewardsHUD"
hudScreenGui.ResetOnSpawn = false
hudScreenGui.IgnoreGuiInset = true
hudScreenGui.DisplayOrder = 500
hudScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudScreenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- Load DailyRewardsUI module
--------------------------------------------------------------------------------
local DailyRewardsUI
do
    local ok, sideUI = pcall(function() return ReplicatedStorage:WaitForChild("SideUI", 10) end)
    if not ok or not sideUI then
        warn("[DailyRewardsClient] SideUI folder not found in ReplicatedStorage")
    else
        local mod = sideUI:FindFirstChild("DailyRewardsUI") or sideUI:WaitForChild("DailyRewardsUI", 5)
        if not mod then
            warn("[DailyRewardsClient] DailyRewardsUI ModuleScript not found under SideUI")
        elseif not mod:IsA("ModuleScript") then
            warn("[DailyRewardsClient] DailyRewardsUI exists but is not a ModuleScript (type:", mod.ClassName, ")")
        else
            local okReq, res = pcall(function() return require(mod) end)
            if okReq then
                DailyRewardsUI = res
            else
                warn("[DailyRewardsClient] Failed to require DailyRewardsUI:", res)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Try to find and initialize your pre-built GUI
--------------------------------------------------------------------------------
local realGui = playerGui:FindFirstChild("DailyRewardsGui")
local drRemotes = nil
local getStateRF, claimRF, stateUpdatedRE
local uiInitialized = false

local function doClaim()
    if not claimRF or not claimRF:IsA("RemoteFunction") then return end
    local ok, success, message, updatedState = pcall(function()
        return claimRF:InvokeServer()
    end)
    if not ok then
        warn("[DailyRewardsClient] Claim RPC failed:", success)
        return
    end
    if updatedState and DailyRewardsUI and DailyRewardsUI.Refresh then
        DailyRewardsUI.Refresh(updatedState)
    else
        if getStateRF and getStateRF:IsA("RemoteFunction") then
            local ok2, s2 = pcall(function() return getStateRF:InvokeServer() end)
            if ok2 and type(s2) == "table" and DailyRewardsUI and DailyRewardsUI.Refresh then
                DailyRewardsUI.Refresh(s2)
            end
        end
    end
end

if realGui and DailyRewardsUI then
    pcall(function()
        -- Find remotes (optional, DailyRewardServiceInit creates these)
        local remotesRoot = ReplicatedStorage:FindFirstChild("Remotes")
        if remotesRoot then
            local drFolder = remotesRoot:FindFirstChild("DailyRewards")
            drFolder = drFolder or (remotesRoot:FindFirstChild("DailyRewards") and remotesRoot:FindFirstChild("DailyRewards"))
            if drFolder then
                getStateRF = drFolder:FindFirstChild("GetDailyRewardState")
                claimRF = drFolder:FindFirstChild("ClaimDailyReward")
                stateUpdatedRE = drFolder:FindFirstChild("DailyRewardStateUpdated")
            end
        end

        local initialState = nil
        if getStateRF and getStateRF:IsA("RemoteFunction") then
            local ok, s = pcall(function() return getStateRF:InvokeServer() end)
            if ok and type(s) == "table" then
                initialState = s
            end
        end

        DailyRewardsUI.Create(realGui, initialState, { onClaim = doClaim })
        uiInitialized = true

        -- Listen for server pushes
        if stateUpdatedRE and stateUpdatedRE:IsA("RemoteEvent") then
            stateUpdatedRE.OnClientEvent:Connect(function(state)
                if DailyRewardsUI and DailyRewardsUI.Refresh then
                    DailyRewardsUI.Refresh(state)
                end
                if state and state.autoPopup and state.canClaimToday and DailyRewardsUI and not DailyRewardsUI.IsOpen() then
                    DailyRewardsUI.Open()
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Create the Top-Right Button
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
btnContainer.Parent = hudScreenGui

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

--------------------------------------------------------------------------------
-- Button Click
--------------------------------------------------------------------------------
button.Activated:Connect(function()
    print("[DailyRewardsClient] Button clicked!")

    local realGui = playerGui:FindFirstChild("DailyRewardsGui")

    if not realGui then
        warn("[DailyRewardsClient] ERROR: DailyRewardsGui not found in PlayerGui!")
        return
    end

    if not DailyRewardsUI then
        warn("[DailyRewardsClient] ERROR: DailyRewardsUI module is nil!")
        return
    end

    -- Try to initialize if not already done (ensure callbacks wired)
    if not DailyRewardsUI.IsOpen() then
        if not uiInitialized then
            local success, err = pcall(function()
                local initialState = nil
                if getStateRF and getStateRF:IsA("RemoteFunction") then
                    local ok, s = pcall(function() return getStateRF:InvokeServer() end)
                    if ok and type(s) == "table" then
                        initialState = s
                    end
                end
                DailyRewardsUI.Create(realGui, initialState, { onClaim = doClaim })
            end)
            if not success then
                warn("[DailyRewardsClient] ERROR in DailyRewardsUI.Create:", err)
                return
            end
            uiInitialized = true
        end
    end

    -- Now open or close
    if DailyRewardsUI.IsOpen() then
        DailyRewardsUI.Close()
        print("[DailyRewardsClient] Closed UI")
    else
        DailyRewardsUI.Open()
        print("[DailyRewardsClient] Opened UI")
    end
end)

print("[DailyRewardsClient] Button created successfully")
