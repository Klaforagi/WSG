--------------------------------------------------------------------------------
-- DailyQuestsUI.lua  –  Client-side Daily Quests panel
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / InventoryUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Fetches quest data from server via Remotes.GetQuests RemoteFunction.
-- Listens for live progress updates via Remotes.QuestProgress RemoteEvent.
-- Claims rewards via Remotes.ClaimQuest RemoteFunction.
--------------------------------------------------------------------------------

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / ShopUI / OptionsUI)
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
-- Palette (matches SideUI neutral-gray / gold theme)
--------------------------------------------------------------------------------
local ROW_BG       = Color3.fromRGB(28, 28, 33)
local CARD_STROKE  = Color3.fromRGB(60, 60, 64)
local GOLD         = Color3.fromRGB(255, 215, 80)
local WHITE        = Color3.fromRGB(240, 240, 240)
local DIM_TEXT     = Color3.fromRGB(160, 160, 165)
local BAR_BG      = Color3.fromRGB(50, 50, 55)
local BAR_FILL    = GOLD
local BTN_CLAIM   = Color3.fromRGB(50, 180, 80)
local BTN_CLAIMED = Color3.fromRGB(80, 80, 85)
local BTN_LOCKED  = Color3.fromRGB(64, 64, 68)
local COIN_ICON   = "\u{1FA99}"   -- coin emoji fallback

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- Remotes (resolved lazily with WaitForChild)
--------------------------------------------------------------------------------
local remotesFolder
local getQuestsRF
local claimQuestRF
local questProgressRE

local function ensureRemotes()
    if remotesFolder then return true end
    remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return false end
    getQuestsRF   = remotesFolder:WaitForChild("GetQuests", 5)
    claimQuestRF  = remotesFolder:WaitForChild("ClaimQuest", 5)
    questProgressRE = remotesFolder:WaitForChild("QuestProgress", 5)
    return getQuestsRF ~= nil
end

--------------------------------------------------------------------------------
-- Connection cleanup
--------------------------------------------------------------------------------
local activeConnections = {}

local function trackConn(conn)
    table.insert(activeConnections, conn)
end

local function cleanupConnections()
    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local DailyQuestsUI = {}

function DailyQuestsUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return nil end

    -- Cleanup from previous open
    cleanupConnections()

    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout")
            and not c:IsA("UIPadding") then
            pcall(function() c:Destroy() end)
        end
    end

    -- Ensure remotes are available
    if not ensureRemotes() then
        local errLabel = Instance.new("TextLabel")
        errLabel.BackgroundTransparency = 1
        errLabel.Font = Enum.Font.GothamMedium
        errLabel.Text = "Quests unavailable – please try again."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize = px(16)
        errLabel.Size = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent = parent
        return nil
    end

    -- Fetch quest data from server
    local quests = {}
    pcall(function()
        quests = getQuestsRF:InvokeServer()
    end)
    if type(quests) ~= "table" or #quests == 0 then
        local errLabel = Instance.new("TextLabel")
        errLabel.BackgroundTransparency = 1
        errLabel.Font = Enum.Font.GothamMedium
        errLabel.Text = "No quests available today."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize = px(16)
        errLabel.Size = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent = parent
        return nil
    end

    ---------------------------------------------------------------------------
    -- Lookup tables for live updates
    ---------------------------------------------------------------------------
    local progressBars  = {}   -- [questId] = fill Frame
    local progressTexts = {}   -- [questId] = TextLabel "3/5"
    local claimButtons  = {}   -- [questId] = TextButton
    local questGoals    = {}   -- [questId] = goal number
    local questClaimed  = {}   -- [questId] = bool

    ---------------------------------------------------------------------------
    -- Section header
    ---------------------------------------------------------------------------
    local header = Instance.new("TextLabel")
    header.Name = "QuestsHeader"
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.Text = "DAILY QUESTS"
    header.TextColor3 = GOLD
    header.TextSize = math.max(16, math.floor(px(18)))
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Size = UDim2.new(1, 0, 0, px(28))
    header.LayoutOrder = 1
    header.Parent = parent

    local subHeader = Instance.new("TextLabel")
    subHeader.Name = "QuestsSubHeader"
    subHeader.BackgroundTransparency = 1
    subHeader.Font = Enum.Font.GothamMedium
    subHeader.Text = "Complete quests to earn coin rewards. Resets daily!"
    subHeader.TextColor3 = DIM_TEXT
    subHeader.TextSize = math.max(11, math.floor(px(12)))
    subHeader.TextXAlignment = Enum.TextXAlignment.Left
    subHeader.Size = UDim2.new(1, 0, 0, px(20))
    subHeader.LayoutOrder = 2
    subHeader.Parent = parent

    ---------------------------------------------------------------------------
    -- Build a card for each quest
    ---------------------------------------------------------------------------
    for i, quest in ipairs(quests) do
        questGoals[quest.id]   = quest.goal
        questClaimed[quest.id] = quest.claimed

        local card = Instance.new("Frame")
        card.Name = "Quest_" .. quest.id
        card.BackgroundColor3 = ROW_BG
        card.Size = UDim2.new(1, 0, 0, px(100))
        card.LayoutOrder = 10 + i
        card.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(8))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color = CARD_STROKE
        stroke.Thickness = 1
        stroke.Transparency = 0.4
        stroke.Parent = card

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(12))
        pad.PaddingRight  = UDim.new(0, px(12))
        pad.PaddingTop    = UDim.new(0, px(10))
        pad.PaddingBottom = UDim.new(0, px(10))
        pad.Parent = card

        -- Title row
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name = "Title"
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = quest.title
        titleLbl.TextColor3 = WHITE
        titleLbl.TextSize = math.max(14, math.floor(px(15)))
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Size = UDim2.new(0.65, 0, 0, px(20))
        titleLbl.Position = UDim2.new(0, 0, 0, 0)
        titleLbl.Parent = card

        -- Reward label (right side of title row)
        local rewardLbl = Instance.new("TextLabel")
        rewardLbl.Name = "Reward"
        rewardLbl.BackgroundTransparency = 1
        rewardLbl.Font = Enum.Font.GothamBold
        rewardLbl.Text = COIN_ICON .. " " .. tostring(quest.reward)
        rewardLbl.TextColor3 = GOLD
        rewardLbl.TextSize = math.max(13, math.floor(px(14)))
        rewardLbl.TextXAlignment = Enum.TextXAlignment.Right
        rewardLbl.Size = UDim2.new(0.35, 0, 0, px(20))
        rewardLbl.Position = UDim2.new(0.65, 0, 0, 0)
        rewardLbl.Parent = card

        -- Description
        local descLbl = Instance.new("TextLabel")
        descLbl.Name = "Desc"
        descLbl.BackgroundTransparency = 1
        descLbl.Font = Enum.Font.GothamMedium
        descLbl.Text = quest.desc
        descLbl.TextColor3 = DIM_TEXT
        descLbl.TextSize = math.max(11, math.floor(px(12)))
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.Size = UDim2.new(1, 0, 0, px(16))
        descLbl.Position = UDim2.new(0, 0, 0, px(22))
        descLbl.Parent = card

        -- Progress bar track
        local barY = px(44)
        local barH = px(14)
        local track = Instance.new("Frame")
        track.Name = "BarTrack"
        track.BackgroundColor3 = BAR_BG
        track.Size = UDim2.new(0.65, 0, 0, barH)
        track.Position = UDim2.new(0, 0, 0, barY)
        track.Parent = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, px(4))
        trackCorner.Parent = track

        -- Progress bar fill
        local pct = (quest.goal > 0) and math.clamp(quest.progress / quest.goal, 0, 1) or 0
        local fill = Instance.new("Frame")
        fill.Name = "BarFill"
        fill.BackgroundColor3 = BAR_FILL
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, px(4))
        fillCorner.Parent = fill

        progressBars[quest.id] = fill

        -- Progress text  (e.g., "3/5")
        local progText = Instance.new("TextLabel")
        progText.Name = "ProgressText"
        progText.BackgroundTransparency = 1
        progText.Font = Enum.Font.GothamBold
        progText.Text = tostring(quest.progress) .. "/" .. tostring(quest.goal)
        progText.TextColor3 = WHITE
        progText.TextSize = math.max(11, math.floor(px(12)))
        progText.Size = UDim2.new(1, 0, 1, 0)
        progText.Parent = track

        progressTexts[quest.id] = progText

        -- Claim button
        local btnW = px(90)
        local btnH = px(30)
        local btn = Instance.new("TextButton")
        btn.Name = "ClaimBtn"
        btn.AutoButtonColor = false
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = math.max(12, math.floor(px(13)))
        btn.Size = UDim2.new(0, btnW, 0, btnH)
        btn.AnchorPoint = Vector2.new(1, 0)
        btn.Position = UDim2.new(1, 0, 0, barY - px(2))
        btn.Parent = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(6))
        btnCorner.Parent = btn

        claimButtons[quest.id] = btn

        -- Set initial button state
        local function updateButtonState(progress, goal, claimed)
            if claimed then
                btn.Text = "CLAIMED"
                btn.BackgroundColor3 = BTN_CLAIMED
                btn.TextColor3 = DIM_TEXT
                btn.Active = false
            elseif progress >= goal then
                btn.Text = "CLAIM"
                btn.BackgroundColor3 = BTN_CLAIM
                btn.TextColor3 = WHITE
                btn.Active = true
            else
                btn.Text = tostring(progress) .. "/" .. tostring(goal)
                btn.BackgroundColor3 = BTN_LOCKED
                btn.TextColor3 = DIM_TEXT
                btn.Active = false
            end
        end

        updateButtonState(quest.progress, quest.goal, quest.claimed)

        -- Claim handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if questClaimed[quest.id] then return end
            if not btn.Active then return end

            -- Disable immediately to prevent double-clicks
            btn.Active = false
            btn.Text = "..."

            local success = false
            pcall(function()
                success = claimQuestRF:InvokeServer(quest.id)
            end)

            if success then
                questClaimed[quest.id] = true
                updateButtonState(quest.goal, quest.goal, true)
                -- Flash gold
                local origColor = card.BackgroundColor3
                TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(60, 55, 25)}):Play()
                task.delay(0.3, function()
                    if card and card.Parent then
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = origColor}):Play()
                    end
                end)
                -- Refresh coin header if available
                if _G.UpdateShopHeaderCoins then
                    pcall(_G.UpdateShopHeaderCoins)
                end
            else
                -- re-enable
                updateButtonState(quest.progress, quest.goal, false)
            end
        end))

        -- Store update function for live progress
        card:SetAttribute("_questId", quest.id)
        card:SetAttribute("_updateFunc", "")  -- placeholder; we'll use the lookup tables
    end

    ---------------------------------------------------------------------------
    -- Live progress updates from server
    ---------------------------------------------------------------------------
    if questProgressRE then
        trackConn(questProgressRE.OnClientEvent:Connect(function(questId, newProgress)
            if type(questId) ~= "string" then return end
            newProgress = tonumber(newProgress) or 0
            local goal = questGoals[questId]
            if not goal then return end
            if questClaimed[questId] then return end

            local pct = math.clamp(newProgress / goal, 0, 1)

            -- Animate progress bar
            local fill = progressBars[questId]
            if fill and fill.Parent then
                TweenService:Create(fill, TWEEN_QUICK, {Size = UDim2.new(pct, 0, 1, 0)}):Play()
            end

            -- Update text
            local txt = progressTexts[questId]
            if txt and txt.Parent then
                txt.Text = tostring(math.min(newProgress, goal)) .. "/" .. tostring(goal)
            end

            -- Update button
            local btn = claimButtons[questId]
            if btn and btn.Parent then
                if newProgress >= goal then
                    btn.Text = "CLAIM"
                    btn.BackgroundColor3 = BTN_CLAIM
                    btn.TextColor3 = WHITE
                    btn.Active = true
                else
                    btn.Text = tostring(newProgress) .. "/" .. tostring(goal)
                    btn.BackgroundColor3 = BTN_LOCKED
                    btn.TextColor3 = DIM_TEXT
                    btn.Active = false
                end
            end
        end))
    end

    return parent
end

return DailyQuestsUI
