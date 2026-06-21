--------------------------------------------------------------------------------
-- DailyRewardsUI.lua  –  Controller for your pre-built Studio UI
--------------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

local DailyRewardsUI = {}

local screenGui = nil          -- The ScreenGui (DailyRewardsGui)
local window = nil             -- DailyRewardsWindow
local dayCards = {}
local claimFrame = nil
local claimButton = nil
local streakNumberLabel = nil
local daysLabel = nil
local isOpen = false

local function tweenProp(inst, props, info)
    info = info or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tw = TweenService:Create(inst, info, props)
    tw:Play()
    return tw
end

function DailyRewardsUI.Create(passedScreenGui, initialState)
    if not passedScreenGui then
        warn("[DailyRewardsUI] No ScreenGui passed!")
        return
    end

    screenGui = passedScreenGui
    window = screenGui:FindFirstChild("DailyRewardsWindow")

    if not window then
        warn("[DailyRewardsUI] ERROR: Could not find 'DailyRewardsWindow'!")
        return
    end

    print("[DailyRewardsUI] Found DailyRewardsWindow successfully")

    -- Find streak elements
    streakNumberLabel = window:FindFirstChild("Streak#")
    daysLabel = window:FindFirstChild("Days")

    -- Claim area
    claimFrame = window:FindFirstChild("ClaimButton")
    if claimFrame then
        claimButton = claimFrame:FindFirstChild("Claim")
    end

    -- Day cards
    local container = window:FindFirstChild("CardsContainer")
    if container then
        dayCards = {}
        for i = 1, 7 do
            local card = container:FindFirstChild("Day" .. i)
            if card then
                dayCards[i] = {
                    frame = card,
                    rewardLabel = card:FindFirstChild("RewardLabel"),
                    amountLabel = card:FindFirstChild("AmountLabel"),
                    statusClaimed = card:FindFirstChild("StatusLabelClaimed"),
                    statusToday = card:FindFirstChild("StatusLabelToday"),
                }
            end
        end
    end

    if claimButton then
        claimButton.Activated:Connect(function()
            if DailyRewardsUI.onClaim then DailyRewardsUI.onClaim() end
        end)
    end

    if initialState then
        DailyRewardsUI.Refresh(initialState)
    end

    return DailyRewardsUI
end

function DailyRewardsUI.Refresh(state)
    if not state or not window then return end

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
            if card.statusClaimed then card.statusClaimed.Visible = false end
            if card.statusToday then card.statusToday.Visible = false end

            if status == "claimed" and card.statusClaimed then
                card.statusClaimed.Visible = true
            elseif status == "claimable" and card.statusToday then
                card.statusToday.Visible = true
            end
        end
    end

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