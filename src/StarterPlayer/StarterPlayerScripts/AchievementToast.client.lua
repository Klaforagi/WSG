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
-- Layout — vertical offset above the toolbar/hotbar
-- Increase this value to push the popup higher above the toolbar.
--------------------------------------------------------------------------------
local POPUP_ABOVE_TOOLBAR_OFFSET = 194   -- px (at 1080p baseline) of clearance from screen bottom

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

local function showToast(title, icon, reward, ap, achId, category)
    -- Toast frame (TextButton so the whole card is clickable)
    local toast = Instance.new("TextButton")
    toast.Name                = "Toast"
    toast.BackgroundColor3    = DARK_BG
    toast.BackgroundTransparency = 0.05
    toast.AutoButtonColor     = false
    toast.Text                = ""
    toast.Size                = UDim2.new(0, px(340), 0, px(88))
    toast.AnchorPoint         = Vector2.new(0.5, 1)
    toast.Position            = UDim2.new(0.5, 0, 1, px(100)) -- start off-screen below
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

    -- Reward text (coins + AP)
    local rewardParts = {}
    if (reward or 0) > 0 then table.insert(rewardParts, "+" .. tostring(reward) .. " coins") end
    if (ap or 0) > 0 then table.insert(rewardParts, "+" .. tostring(ap) .. " AP") end
    local rewardStr = #rewardParts > 0 and table.concat(rewardParts, "  |  ") or ""

    local rewardLbl = Instance.new("TextLabel")
    rewardLbl.Name               = "Reward"
    rewardLbl.BackgroundTransparency = 1
    rewardLbl.Font               = Enum.Font.GothamMedium
    rewardLbl.Text               = rewardStr
    rewardLbl.TextColor3         = DIM_TEXT
    rewardLbl.TextSize           = math.max(10, math.floor(px(11)))
    rewardLbl.TextXAlignment     = Enum.TextXAlignment.Left
    rewardLbl.Size               = UDim2.new(1, -px(60), 0, px(14))
    rewardLbl.Position           = UDim2.new(0, px(56), 0, px(50))
    rewardLbl.Parent             = toast

    -- "Click to view" hint at the bottom
    local clickLbl = Instance.new("TextLabel")
    clickLbl.Name               = "ClickHint"
    clickLbl.BackgroundTransparency = 1
    clickLbl.Font               = Enum.Font.GothamMedium
    clickLbl.Text               = "Click to view  ▶"
    clickLbl.TextColor3         = Color3.fromRGB(120, 125, 145)
    clickLbl.TextSize           = math.max(9, math.floor(px(10)))
    clickLbl.TextXAlignment     = Enum.TextXAlignment.Right
    clickLbl.Size               = UDim2.new(1, -px(12), 0, px(13))
    clickLbl.AnchorPoint        = Vector2.new(0, 1)
    clickLbl.Position           = UDim2.new(0, px(6), 1, -px(4))
    clickLbl.Parent             = toast

    -- Click handler: navigate to the achievement in the Quests panel
    toast.MouseButton1Click:Connect(function()
        if type(_G.NavigateToAchievement) == "function" then
            pcall(_G.NavigateToAchievement, achId, category)
        end
        -- Dismiss the toast immediately on click
        if toast and toast.Parent then toast:Destroy() end
        isShowing = false
        if #toastQueue > 0 then
            local next = table.remove(toastQueue, 1)
            isShowing = true
            showToast(next.title, next.icon, next.reward, next.ap, next.achId, next.category)
        end
    end)

    -- Animate in
    local TWEEN_IN  = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local TWEEN_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    local targetPos = UDim2.new(0.5, 0, 1, -px(POPUP_ABOVE_TOOLBAR_OFFSET))
    TweenService:Create(toast, TWEEN_IN, {Position = targetPos}):Play()

    -- Hold for 4.5 seconds, then slide out
    task.delay(4.5, function()
        if toast and toast.Parent then
            local outTween = TweenService:Create(toast, TWEEN_OUT,
                {Position = UDim2.new(0.5, 0, 1, px(100))})
            outTween:Play()
            outTween.Completed:Connect(function()
                if toast and toast.Parent then toast:Destroy() end
                -- Process next in queue
                isShowing = false
                if #toastQueue > 0 then
                    local next = table.remove(toastQueue, 1)
                    isShowing = true
                    showToast(next.title, next.icon, next.reward, next.ap, next.achId, next.category)
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Public function (exposed via _G for DailyQuestsUI to call)
--------------------------------------------------------------------------------
_G.ShowAchievementToast = function(achievementId, stageIndex)
    local def
    if AchievementDefs and AchievementDefs.ById then
        -- Resolve old id aliases (e.g. first_blood → first_strike)
        local resolvedId = achievementId
        if AchievementDefs.ResolveId then
            resolvedId = AchievementDefs.ResolveId(achievementId)
        end
        def = AchievementDefs.ById[resolvedId]
    end
    local si = stageIndex or 1
    local title  = achievementId
    local icon   = "★"
    local reward = 0
    local ap     = 0
    local category = nil
    if def then
        icon = def.icon or icon
        category = def.category
        if def.staged then
            title = AchievementDefs.GetStageTitle and AchievementDefs.GetStageTitle(def, si) or (def.titleFormat and string.format(def.titleFormat, "I") or achievementId)
            reward = AchievementDefs.GetStageReward and AchievementDefs.GetStageReward(def, si) or (def.rewards and def.rewards[si] or 0)
            ap = AchievementDefs.GetStageAP and AchievementDefs.GetStageAP(def, si) or 0
        else
            title = def.title or achievementId
            reward = def.reward or 0
            ap = tonumber(def.achievementPoints) or 0
        end
    end

    if isShowing then
        table.insert(toastQueue, { title = title, icon = icon, reward = reward, ap = ap, achId = achievementId, category = category })
    else
        isShowing = true
        showToast(title, icon, reward, ap, achievementId, category)
    end
end

--------------------------------------------------------------------------------
-- Listen for AchievementProgress to show toasts
-- (DailyQuestsUI no longer calls _G.ShowAchievementToast to avoid duplicates)
--------------------------------------------------------------------------------
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then return end
    local achievProgressRE = remotes:WaitForChild("AchievementProgress", 10)
    if not achievProgressRE or not achievProgressRE:IsA("RemoteEvent") then return end

    achievProgressRE.OnClientEvent:Connect(function(achId, _, completed, _, _, stageIndex)
        if achId == "__full_refresh" then return end
        if not completed then return end
        -- Suppress the toast briefly while a CLAIM is in flight. Claiming a
        -- staged achievement whose next stage is already complete-by-stats
        -- causes the server to immediately mark stage N+1 completed and push
        -- progress, which would re-trigger the popup right after the player
        -- clicked Claim. The achievement window already updates the card
        -- visuals to claimable, so the popup is redundant and disruptive.
        local suppressUntil = tonumber(_G._SuppressAchievementToastUntil)
        if suppressUntil and os.clock() < suppressUntil then return end
        if _G.ShowAchievementToast then
            pcall(function() _G.ShowAchievementToast(achId, stageIndex) end)
        end
    end)
end)
