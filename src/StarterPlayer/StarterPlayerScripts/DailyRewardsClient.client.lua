--------------------------------------------------------------------------------
-- DailyRewardsClient.client.lua
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

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
-- Create the top-left Daily Login button (Roblox unibar chip style)
--------------------------------------------------------------------------------
local CORE_HUD_BTN_SIZE = 44
local CORE_HUD_BTN_GAP = 8
local CORE_HUD_UNIBAR_GAP = 8
local CORE_HUD_Y_NUDGE = 4

local function layoutTopHudButtonsFrame(frame)
    if not frame then return end
    local x = 176
    local y = 8 + CORE_HUD_Y_NUDGE
    local ok, inset = pcall(function()
        return GuiService.TopbarInset
    end)
    if ok and inset and typeof(inset) == "Rect" and inset.Width > 0 and inset.Width < 400 then
        x = inset.Min.X + inset.Width + CORE_HUD_UNIBAR_GAP
        y = inset.Min.Y + math.max(0, (inset.Height - CORE_HUD_BTN_SIZE) * 0.5) + CORE_HUD_Y_NUDGE
    end
    frame.AnchorPoint = Vector2.new(0, 0)
    frame.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
    frame.Size = UDim2.fromOffset(CORE_HUD_BTN_SIZE * 2 + CORE_HUD_BTN_GAP, CORE_HUD_BTN_SIZE)
end

local function ensureTopRightButtonsFrame()
    local topGui = playerGui:FindFirstChild("TopRightButtonsGui")
    if not topGui then
        topGui = Instance.new("ScreenGui")
        topGui.Name = "TopRightButtonsGui"
        topGui.ResetOnSpawn = false
        topGui.IgnoreGuiInset = true
        topGui.DisplayOrder = 1200
        topGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        topGui.Parent = playerGui
    end
    local frame = topGui:FindFirstChild("TopRightButtonsFrame")
    if not frame then
        frame = Instance.new("Frame")
        frame.Name = "TopRightButtonsFrame"
        frame.BackgroundTransparency = 1
        frame.Parent = topGui
    end
    local layout = frame:FindFirstChildOfClass("UIListLayout")
    if not layout then
        layout = Instance.new("UIListLayout")
        layout.Parent = frame
    end
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, CORE_HUD_BTN_GAP)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    local aspect = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
    if aspect then
        aspect:Destroy()
    end
    layoutTopHudButtonsFrame(frame)
    if not frame:GetAttribute("TopbarInsetBound") then
        frame:SetAttribute("TopbarInsetBound", true)
        pcall(function()
            GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
                layoutTopHudButtonsFrame(frame)
            end)
        end)
    end
    return frame
end

local topFrame = ensureTopRightButtonsFrame()

local btnContainer = Instance.new("Frame")
btnContainer.Name = "DailyRewardsBtnContainer"
btnContainer.BackgroundTransparency = 1
btnContainer.Size = UDim2.fromOffset(CORE_HUD_BTN_SIZE, CORE_HUD_BTN_SIZE)
btnContainer.LayoutOrder = 2
btnContainer.Parent = topFrame

local button = Instance.new("ImageButton")
button.Name = "DailyRewardsButton"
button.AnchorPoint = Vector2.new(0.5, 0.5)
button.Position = UDim2.fromScale(0.5, 0.5)
button.Size = UDim2.fromScale(1, 1)
button.BackgroundColor3 = Color3.fromRGB(23, 23, 23)
button.BackgroundTransparency = 0.1
button.AutoButtonColor = false
button.BorderSizePixel = 0
button.ZIndex = 600
button.Parent = btnContainer

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(1, 0)
btnCorner.Parent = button

local btnScale = Instance.new("UIScale")
btnScale.Parent = button

-- Gift box: white outline, sharp box/lid, simple two-loop bow
do
    local WHITE = Color3.fromRGB(255, 255, 255)

    local function outlineShape(parent, name, size, pos, zIndex, corner)
        local frame = Instance.new("Frame")
        frame.Name = name
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Size = size
        frame.Position = pos
        frame.AnchorPoint = Vector2.new(0.5, 0.5)
        frame.ZIndex = zIndex
        frame.Parent = parent
        if corner and corner > 0 then
            local cornerInst = Instance.new("UICorner")
            cornerInst.CornerRadius = UDim.new(corner, 0)
            cornerInst.Parent = frame
        end
        local stroke = Instance.new("UIStroke")
        stroke.Color = WHITE
        stroke.Thickness = 1.6
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = frame
        return frame
    end

    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconGlyph"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFrame.Position = UDim2.fromScale(0.5, 0.52)
    iconFrame.Size = UDim2.new(0.56, 0, 0.56, 0)
    iconFrame.BackgroundTransparency = 1
    iconFrame.ZIndex = 610
    iconFrame.Parent = button

    outlineShape(iconFrame, "BowLeft", UDim2.fromScale(0.30, 0.28), UDim2.fromScale(0.36, 0.24), 614, 1)
    outlineShape(iconFrame, "BowRight", UDim2.fromScale(0.30, 0.28), UDim2.fromScale(0.64, 0.24), 614, 1)
    outlineShape(iconFrame, "BowKnot", UDim2.fromScale(0.11, 0.11), UDim2.fromScale(0.50, 0.26), 615, 1)

    outlineShape(iconFrame, "LidLeft", UDim2.fromScale(0.44, 0.13), UDim2.fromScale(0.25, 0.44), 612, 0)
    outlineShape(iconFrame, "LidRight", UDim2.fromScale(0.44, 0.13), UDim2.fromScale(0.75, 0.44), 612, 0)
    outlineShape(iconFrame, "BodyLeft", UDim2.fromScale(0.40, 0.38), UDim2.fromScale(0.26, 0.77), 611, 0)
    outlineShape(iconFrame, "BodyRight", UDim2.fromScale(0.40, 0.38), UDim2.fromScale(0.74, 0.77), 611, 0)
end

-- Hover Effects
button.MouseEnter:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.1), {BackgroundTransparency = 0.02}):Play()
end)

button.MouseLeave:Connect(function()
    TweenService:Create(button, TweenInfo.new(0.1), {BackgroundTransparency = 0.1}):Play()
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
