--------------------------------------------------------------------------------
-- DailyRewardsUI.lua  –  Controller for your pre-built Studio UI
--------------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local DailyRewardsUI = {}

local screenGui = nil          -- The ScreenGui (DailyRewardsGui)
local window = nil             -- DailyRewardsWindow
local dayCards = {}
local claimFrame = nil
local claimButton = nil
local streakNumberLabel = nil
local daysLabel = nil
local closeBtn = nil
local isOpen = false


local function tweenProp(inst, props, info)
    info = info or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tw = TweenService:Create(inst, info, props)
    tw:Play()
    return tw
end

-- Create: either use passed ScreenGui or find the player's DailyRewardsGui in PlayerGui
function DailyRewardsUI.Create(passedScreenGui, initialState, callbacks)
    local player = Players.LocalPlayer
    if passedScreenGui and passedScreenGui:IsA("ScreenGui") then
        screenGui = passedScreenGui
    else
        if not player then
            warn("[DailyRewardsUI] No LocalPlayer available")
            return
        end
        local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
        screenGui = playerGui:FindFirstChild("DailyRewardsGui") or playerGui:WaitForChild("DailyRewardsGui", 5)
    end

    if not screenGui then
        warn("[DailyRewardsUI] DailyRewardsGui not found in PlayerGui")
        return
    end

    window = screenGui:FindFirstChild("DailyRewardsWindow")
    if not window then
        warn("[DailyRewardsUI] DailyRewardsWindow not found!")
        return
    end

    -- Find commonly used elements
    streakNumberLabel = window:FindFirstChild("Streak#")
    daysLabel = window:FindFirstChild("Days")
    claimFrame = window:FindFirstChild("ClaimButton")
    closeBtn = window:FindFirstChild("CloseBtn")
    if claimFrame then claimButton = claimFrame:FindFirstChild("Claim") end

    -- Day cards
    local container = window:FindFirstChild("CardsContainer")
    dayCards = {}
    if container then
        for i = 1, 7 do
            local card = container:FindFirstChild("Day" .. i)
            if card then
                dayCards[i] = {
                    frame = card,
                    stroke = card:FindFirstChildOfClass("UIStroke"),
                    rewardLabel = card:FindFirstChild("RewardLabel"),
                    amountLabel = card:FindFirstChild("AmountLabel"),
                    statusClaimed = card:FindFirstChild("StatusLabelClaimed"),
                    statusToday = card:FindFirstChild("StatusLabelToday"),
                }
            end
        end
    end

    -- Close button behaviour: keep how it is (top-right trigger should remain unchanged elsewhere)
    if closeBtn then
        closeBtn.Activated:Connect(function()
            DailyRewardsUI.Close()
        end)
    end

    -- Claim button callbacks
    if claimButton and callbacks and callbacks.onClaim then
        claimButton.Activated:Connect(callbacks.onClaim)
    end
    if claimButton then
        claimButton.Activated:Connect(function()
            if DailyRewardsUI.onClaim then DailyRewardsUI.onClaim() end
        end)
    end

    -- Ensure ScreenGui starts disabled by module until explicitly opened
    if screenGui then screenGui.Enabled = screenGui.Enabled or false end

    if initialState then
        DailyRewardsUI.Refresh(initialState)
    end

    return DailyRewardsUI
end

function DailyRewardsUI.Refresh(state)
    if not state or not window then return end

    -- Streak display
    if streakNumberLabel then
        streakNumberLabel.Text = tostring(state.currentStreak or 0)
    end
    if daysLabel then
        daysLabel.Text = ((state.currentStreak or 0) == 1) and "DAY" or "DAYS"
    end

    -- Update day cards
    if streakNumberLabel then
        streakNumberLabel.Text = tostring(state.currentStreak or 0)
    end

    if daysLabel then
        local streak = state.currentStreak or 0
        daysLabel.Text = (streak == 1) and "Day" or "Days"
    end

    local rewards = state.rewards or {}
    for i, card in ipairs(dayCards) do
        local reward = rewards[i]
        if reward and card then
            if card.rewardLabel then card.rewardLabel.Text = reward.displayName or "" end
            if card.amountLabel then card.amountLabel.Text = "x" .. tostring(reward.amount or 0) end

            local status = reward.status or "future"

            -- Reset visibility
            if card.statusClaimed then card.statusClaimed.Visible = false end
            if card.statusToday then card.statusToday.Visible = false end

            -- Apply visuals per status
            if status == "claimable" then
                card.frame.BackgroundColor3 = Color3.fromRGB(255, 217, 0)
                if card.stroke then card.stroke.Color = Color3.fromRGB(255, 200, 0) end
                if card.statusToday then card.statusToday.Visible = true end

            elseif status == "claimed" then
                card.frame.BackgroundColor3 = Color3.fromRGB(38, 240, 16)
                if card.stroke then card.stroke.Color = Color3.fromRGB(24, 184, 12) end
                if card.statusClaimed then card.statusClaimed.Visible = true end

            else
                card.frame.BackgroundColor3 = Color3.fromRGB(26, 30, 48)
                if card.stroke then card.stroke.Color = Color3.fromRGB(55, 62, 95) end
            end
        end
    end

    -- Claim button state
    if claimFrame and claimButton then
        local canClaim = state.canClaimToday and not state.alreadyClaimed
        claimButton.Active = canClaim

        if canClaim then
            claimButton.Text = "CLAIM REWARD"
            claimFrame.BackgroundTransparency = 0
        elseif state.alreadyClaimed then
            claimButton.Text = "✓ CLAIMED TODAY"
            claimFrame.BackgroundTransparency = 0.35
        else
            claimButton.Text = "COME BACK TOMORROW"
            claimFrame.BackgroundTransparency = 0.35
        end
    end
end

function DailyRewardsUI.Open()
    if not screenGui or not window or isOpen then return end
    isOpen = true
    screenGui.Enabled = true
    window.Visible = true
    if not screenGui or not window then
        warn("[DailyRewardsUI] ERROR: screenGui or window is nil")
        return
    end
    if isOpen then return end

    isOpen = true
    screenGui.Enabled = true          -- ← This is the key fix
    window.Visible = true
    print("[DailyRewardsUI] UI Opened (Enabled = true)")
end

function DailyRewardsUI.Close()
    if not screenGui or not window then return end
    isOpen = false
    screenGui.Enabled = false
    window.Visible = false
end

function DailyRewardsUI.IsOpen()
    return isOpen
end

function DailyRewardsUI.PlayClaimAnimation(dayIndex)
    local card = dayCards[dayIndex]
    if not card or not card.frame then return end

    local original = card.frame.BackgroundColor3
    tweenProp(card.frame, { BackgroundColor3 = Color3.fromRGB(255, 215, 80) }, TweenInfo.new(0.12))
    task.delay(0.18, function()
        if card.frame then
            tweenProp(card.frame, { BackgroundColor3 = original }, TweenInfo.new(0.25))
        end
    end)
end

return DailyRewardsUI