--------------------------------------------------------------------------------
-- DailyQuestsUI.lua  –  Client-side Quests panel (Daily / Weekly / Achievements)
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / InventoryUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Fetches quest data from ReplicatedStorage.Remotes.Quests.GetQuests.
-- Listens for live progress updates via ReplicatedStorage.Remotes.Quests.QuestProgress.
-- Claims rewards via ReplicatedStorage.Remotes.Quests.ClaimQuest.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
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
-- Palette (matches BoostsUI deep-blue / gold theme)
--------------------------------------------------------------------------------
local ROW_BG           = Color3.fromRGB(26, 30, 48)
local ROW_CLAIMABLE_BG = Color3.fromRGB(36, 33, 18)
local ROW_CLAIMED_BG   = Color3.fromRGB(22, 38, 34)
local SIDEBAR_BG       = Color3.fromRGB(18, 20, 34)
local TAB_ACTIVE_BG    = Color3.fromRGB(32, 30, 18)
local CARD_STROKE      = Color3.fromRGB(55, 62, 95)
local GOLD             = Color3.fromRGB(255, 215, 60)
local WHITE            = Color3.fromRGB(245, 245, 252)
local DIM_TEXT         = Color3.fromRGB(145, 150, 175)
local BAR_BG           = Color3.fromRGB(35, 38, 58)
local BAR_FILL         = GOLD
local BTN_CLAIM        = Color3.fromRGB(35, 190, 75)
local BTN_CLAIMED      = Color3.fromRGB(35, 38, 52)
local BTN_LOCKED       = Color3.fromRGB(48, 55, 82)
local BTN_STROKE       = Color3.fromRGB(90, 100, 140)
local GREEN_GLOW       = Color3.fromRGB(50, 230, 110)
local CLAIM_GOLD_GLOW  = Color3.fromRGB(255, 200, 40)

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEBUG_QUEST_UI = false

local function debugLog(prefix, message)
    if DEBUG_QUEST_UI then
        print(string.format("[%s] %s", prefix, message))
    end
end

--------------------------------------------------------------------------------
-- Remotes (resolved lazily with WaitForChild)
--------------------------------------------------------------------------------
local remotesFolder
local questRemotesFolder
local getQuestsRF
local claimQuestRF
local questProgressRE
local getWeeklyRF
local claimWeeklyRF
local weeklyProgressRE
local rerollDailyRF
local rerollWeeklyRF

local function ensureRemotes()
    if questRemotesFolder then return true end
    remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return false end
    questRemotesFolder = remotesFolder:WaitForChild("Quests", 5)
    if not questRemotesFolder then return false end

    debugLog("QuestReroll", "Looking for remotes in ReplicatedStorage.Remotes.Quests")
    getQuestsRF      = questRemotesFolder:WaitForChild("GetQuests", 5)
    claimQuestRF     = questRemotesFolder:WaitForChild("ClaimQuest", 5)
    questProgressRE  = questRemotesFolder:WaitForChild("QuestProgress", 5)
    getWeeklyRF      = questRemotesFolder:FindFirstChild("GetWeeklyQuests")
    claimWeeklyRF    = questRemotesFolder:FindFirstChild("ClaimWeeklyQuest")
    weeklyProgressRE = questRemotesFolder:FindFirstChild("WeeklyQuestProgress")
    rerollDailyRF    = questRemotesFolder:WaitForChild("RequestRerollDailyQuest", 5)
    rerollWeeklyRF   = questRemotesFolder:WaitForChild("RequestRerollWeeklyQuest", 5)

    if rerollDailyRF then
        debugLog("QuestReroll", "Found RequestRerollDailyQuest")
    else
        warn("[QuestReroll] RequestRerollDailyQuest not found after WaitForChild")
    end
    if rerollWeeklyRF then
        debugLog("QuestReroll", "Found RequestRerollWeeklyQuest")
    else
        warn("[QuestReroll] RequestRerollWeeklyQuest not found after WaitForChild")
    end
    return getQuestsRF ~= nil
end

-- Lazy re-resolve reroll remotes (in case they weren't ready on first ensureRemotes call)
local function ensureRerollRemotes()
    if rerollDailyRF and rerollWeeklyRF then return end
    if not questRemotesFolder then return end
    if not rerollDailyRF then
        rerollDailyRF = questRemotesFolder:FindFirstChild("RequestRerollDailyQuest")
    end
    if not rerollWeeklyRF then
        rerollWeeklyRF = questRemotesFolder:FindFirstChild("RequestRerollWeeklyQuest")
    end
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
-- Coin icon widget – gold circular coin built from Frames (no asset id needed)
--------------------------------------------------------------------------------
local function makeCoinIcon(parentFrame, size)
    local coin = Instance.new("Frame")
    coin.Name            = "CoinIcon"
    coin.Size            = UDim2.new(0, size, 0, size)
    coin.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
    coin.BorderSizePixel = 0

    local cr = Instance.new("UICorner")
    cr.CornerRadius = UDim.new(0.5, 0)   -- perfect circle
    cr.Parent = coin

    local stroke = Instance.new("UIStroke")
    stroke.Color             = Color3.fromRGB(172, 125, 10)
    stroke.Thickness         = math.max(1, math.floor(size * 0.1))
    stroke.ApplyStrokeMode   = Enum.ApplyStrokeMode.Border
    stroke.Parent            = coin

    -- Specular highlight (small bright dot, top-left)
    local hl = Instance.new("Frame")
    hl.Name                  = "Highlight"
    local hlS                = math.max(2, math.floor(size * 0.28))
    hl.Size                  = UDim2.new(0, hlS, 0, hlS)
    hl.Position              = UDim2.new(0, math.floor(size * 0.22), 0, math.floor(size * 0.16))
    hl.BackgroundColor3      = Color3.fromRGB(255, 245, 185)
    hl.BackgroundTransparency = 0.3
    hl.BorderSizePixel       = 0
    local hlcr = Instance.new("UICorner")
    hlcr.CornerRadius = UDim.new(0.5, 0)
    hlcr.Parent = hl
    hl.Parent = coin

    coin.Parent = parentFrame
    return coin
end

--------------------------------------------------------------------------------
-- BoostConfig lazy loader (for reroll cost in the reroll panel)
--------------------------------------------------------------------------------
local _boostConfigCacheQUI
local function getBoostConfigQUI()
    if _boostConfigCacheQUI then return _boostConfigCacheQUI end
    pcall(function()
        local m = ReplicatedStorage:FindFirstChild("BoostConfig")
        if m and m:IsA("ModuleScript") then
            local ok, v = pcall(require, m)
            if ok then _boostConfigCacheQUI = v end
        end
    end)
    return _boostConfigCacheQUI
end

--------------------------------------------------------------------------------
-- addRerollPanel  –  Compact Quest Reroll card + inline quest-selection mode
-- Appended to the bottom of the Daily and Weekly tab content pages.
-- tabId: "daily" | "weekly"
-- cardFrames: {[key] = Frame}   – quest card instances (quest.id for daily, questIdx for weekly)
-- claimedMap: {[key] = bool}    – whether each quest has been claimed
-- indexMap:   {[key] = number}  – server index to send for reroll
-- refreshQuests: function(tabId) – rebuilds the quest view after a successful reroll
-- Returns: exitSelectionMode function (for external cleanup, e.g. tab switch)
--------------------------------------------------------------------------------
local function addRerollPanel(page, tabId, cardFrames, claimedMap, indexMap, refreshQuests)
    local REROLL_ACCENT  = Color3.fromRGB(170, 110, 255)
    local REROLL_BTN_BG  = Color3.fromRGB(80, 55, 120)
    local CANCEL_BTN_BG  = Color3.fromRGB(120, 40, 40)
    local GREEN_INT      = Color3.fromRGB(35, 190, 75)

    -- Read reroll cost from BoostConfig (fallback 20)
    local rerollCost = 20
    local conf = getBoostConfigQUI()
    if conf and conf.GetById then
        local def = conf.GetById("quest_reroll")
        if def then rerollCost = def.PriceCoins end
    end

    -- Thin separator line for visual separation
    local sep = Instance.new("Frame")
    sep.Name               = "RerollSep"
    sep.BackgroundColor3   = CARD_STROKE
    sep.BackgroundTransparency = 0.3
    sep.Size               = UDim2.new(1, 0, 0, px(1))
    sep.BorderSizePixel    = 0
    sep.LayoutOrder        = 490
    sep.Parent             = page

    -- Reroll card
    local card = Instance.new("Frame")
    card.Name              = "RerollCard"
    card.BackgroundColor3  = Color3.fromRGB(20, 18, 32)
    card.Size              = UDim2.new(1, 0, 0, px(100))
    card.LayoutOrder       = 491
    card.Parent            = page

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, px(12))
    cardCorner.Parent = card

    local cardStrokeR = Instance.new("UIStroke")
    cardStrokeR.Color        = REROLL_ACCENT
    cardStrokeR.Thickness    = 1.4
    cardStrokeR.Transparency = 0.45
    cardStrokeR.Parent       = card

    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingLeft   = UDim.new(0, px(14))
    cardPad.PaddingRight  = UDim.new(0, px(14))
    cardPad.PaddingTop    = UDim.new(0, px(12))
    cardPad.PaddingBottom = UDim.new(0, px(12))
    cardPad.Parent        = card

    -- Icon glow background
    local iconGlow = Instance.new("Frame")
    iconGlow.Size                  = UDim2.new(0, px(62), 0, px(62))
    iconGlow.AnchorPoint           = Vector2.new(0, 0.5)
    iconGlow.Position              = UDim2.new(0, -px(5), 0.5, 0)
    iconGlow.BackgroundColor3      = REROLL_ACCENT
    iconGlow.BackgroundTransparency = 0.82
    iconGlow.BorderSizePixel       = 0
    local glowCr = Instance.new("UICorner")
    glowCr.CornerRadius = UDim.new(0, px(18))
    glowCr.Parent = iconGlow
    iconGlow.Parent = card

    -- Icon circle (purple with 🔄)
    local iconSize = px(52)
    local iconCircle = Instance.new("Frame")
    iconCircle.Name             = "RerollIcon"
    iconCircle.Size             = UDim2.new(0, iconSize, 0, iconSize)
    iconCircle.AnchorPoint      = Vector2.new(0, 0.5)
    iconCircle.Position         = UDim2.new(0, 0, 0.5, 0)
    iconCircle.BackgroundColor3 = REROLL_ACCENT
    iconCircle.BorderSizePixel  = 0
    local icCr = Instance.new("UICorner")
    icCr.CornerRadius = UDim.new(0, px(14))
    icCr.Parent = iconCircle
    local icStr = Instance.new("UIStroke")
    icStr.Color = WHITE
    icStr.Thickness = 1.5
    icStr.Transparency = 0.7
    icStr.Parent = iconCircle
    local icLbl = Instance.new("TextLabel")
    icLbl.BackgroundTransparency = 1
    icLbl.Size       = UDim2.new(1, 0, 1, 0)
    icLbl.Font       = Enum.Font.GothamBold
    icLbl.Text       = "\u{1F504}"
    icLbl.TextSize   = math.max(20, math.floor(iconSize * 0.52))
    icLbl.TextColor3 = WHITE
    icLbl.Parent     = iconCircle
    iconCircle.Parent = card

    -- Title label
    local nameX = iconSize + px(14)
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name               = "RerollTitle"
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.Text               = "Quest Reroll"
    nameLbl.TextColor3         = WHITE
    nameLbl.TextSize           = math.max(15, math.floor(px(17)))
    nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
    nameLbl.Size               = UDim2.new(1, -(nameX + px(92)), 0, px(22))
    nameLbl.Position           = UDim2.new(0, nameX, 0, 0)
    nameLbl.Parent             = card

    -- Description label (correct wording per tab)
    local descText = tabId == "daily"
        and "Replace one daily quest with a new random quest."
        or  "Replace one weekly quest with a new random quest."
    local descLblR = Instance.new("TextLabel")
    descLblR.Name               = "RerollDesc"
    descLblR.BackgroundTransparency = 1
    descLblR.Font               = Enum.Font.GothamMedium
    descLblR.Text               = descText
    descLblR.TextColor3         = DIM_TEXT
    descLblR.TextSize           = math.max(11, math.floor(px(12)))
    descLblR.TextXAlignment     = Enum.TextXAlignment.Left
    descLblR.TextWrapped        = true
    descLblR.Size               = UDim2.new(1, -(nameX + px(92)), 0, px(30))
    descLblR.Position           = UDim2.new(0, nameX, 0, px(24))
    descLblR.Parent             = card

    -- Price badge (top-right corner of card)
    local priceBadgeR = Instance.new("Frame")
    priceBadgeR.Name              = "PriceBadge"
    priceBadgeR.BackgroundColor3  = Color3.fromRGB(36, 33, 18)
    priceBadgeR.BackgroundTransparency = 0.3
    priceBadgeR.Size              = UDim2.new(0, px(80), 0, px(24))
    priceBadgeR.AnchorPoint       = Vector2.new(1, 0)
    priceBadgeR.Position          = UDim2.new(1, 0, 0, 0)
    priceBadgeR.Parent            = card
    local pbCr = Instance.new("UICorner")
    pbCr.CornerRadius = UDim.new(0, px(8))
    pbCr.Parent = priceBadgeR
    local pbStr = Instance.new("UIStroke")
    pbStr.Color = CLAIM_GOLD_GLOW
    pbStr.Thickness = 1
    pbStr.Transparency = 0.55
    pbStr.Parent = priceBadgeR
    local priceLblR = Instance.new("TextLabel")
    priceLblR.BackgroundTransparency = 1
    priceLblR.Font           = Enum.Font.GothamBold
    priceLblR.TextScaled     = true
    priceLblR.TextColor3     = GOLD
    priceLblR.TextXAlignment = Enum.TextXAlignment.Right
    priceLblR.Text           = tostring(rerollCost)
    priceLblR.Size           = UDim2.new(0.58, 0, 1, 0)
    priceLblR.Parent         = priceBadgeR
    local cIconR = makeCoinIcon(priceBadgeR, px(18))
    cIconR.AnchorPoint = Vector2.new(0, 0.5)
    cIconR.Position    = UDim2.new(0.64, 0, 0.5, 0)

    -- USE / CANCEL button (right side, below price badge)
    local useBtn = Instance.new("TextButton")
    useBtn.Name             = "RerollUseBtn"
    useBtn.AutoButtonColor  = false
    useBtn.Font             = Enum.Font.GothamBold
    useBtn.TextSize         = math.max(13, math.floor(px(14)))
    useBtn.Text             = "USE"
    useBtn.TextColor3       = WHITE
    useBtn.Size             = UDim2.new(0, px(80), 0, px(36))
    useBtn.AnchorPoint      = Vector2.new(1, 0)
    useBtn.Position         = UDim2.new(1, 0, 0, px(30))
    useBtn.BackgroundColor3 = REROLL_BTN_BG
    useBtn.Active           = true
    useBtn.Parent           = card
    local ubCr = Instance.new("UICorner")
    ubCr.CornerRadius = UDim.new(0, px(10))
    ubCr.Parent = useBtn
    local ubStr = Instance.new("UIStroke")
    ubStr.Color = REROLL_ACCENT
    ubStr.Thickness = 1.4
    ubStr.Transparency = 0.25
    ubStr.Parent = useBtn

    -- Hint label below USE button
    local hintLbl = Instance.new("TextLabel")
    hintLbl.BackgroundTransparency = 1
    hintLbl.Font           = Enum.Font.GothamMedium
    hintLbl.Text           = "Select Quest"
    hintLbl.TextColor3     = DIM_TEXT
    hintLbl.TextSize       = math.max(10, math.floor(px(11)))
    hintLbl.TextXAlignment = Enum.TextXAlignment.Center
    hintLbl.Size           = UDim2.new(0, px(80), 0, px(16))
    hintLbl.AnchorPoint    = Vector2.new(1, 0)
    hintLbl.Position       = UDim2.new(1, 0, 0, px(70))
    hintLbl.Parent         = card

    ---------------------------------------------------------------------------
    -- Inline reroll-selection mode state
    ---------------------------------------------------------------------------
    local rerollState = {
        isRerollMode = false,
        selectedRerollType = nil,
        rerollInFlight = false,
        selectionOverlays = {},
    }

    local function showButtonError(message, duration)
        local errText = tostring(message or "Reroll failed")
        if errText:find("Insufficient") then
            errText = "Not enough coins!"
        end
        useBtn.Text = errText:sub(1, 16)
        useBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
        task.delay(duration or 1.8, function()
            if useBtn and useBtn.Parent and not rerollState.isRerollMode then
                useBtn.Text = "USE"
                useBtn.TextColor3 = WHITE
            end
        end)
    end

    local function clearSelectionOverlays()
        for _, obj in ipairs(rerollState.selectionOverlays) do
            pcall(function() obj:Destroy() end)
        end
        rerollState.selectionOverlays = {}
    end

    local function exitSelectionMode()
        if not rerollState.isRerollMode and #rerollState.selectionOverlays == 0 then
            return
        end

        rerollState.isRerollMode = false
        rerollState.selectedRerollType = nil
        rerollState.rerollInFlight = false
        debugLog("QuestReroll", "Exiting reroll mode; restoring UI")

        useBtn.Active = true
        useBtn.Text = "USE"
        useBtn.TextColor3 = WHITE
        useBtn.BackgroundColor3 = REROLL_BTN_BG
        ubStr.Color = REROLL_ACCENT
        hintLbl.Text = "Select Quest"
        hintLbl.TextColor3 = DIM_TEXT
        descLblR.Text = descText
        descLblR.TextColor3 = DIM_TEXT

        clearSelectionOverlays()
    end

    local function submitReroll(serverIdx)
        ensureRerollRemotes()

        local remote = tabId == "daily" and rerollDailyRF or rerollWeeklyRF
        local remoteName = tabId == "daily" and "RequestRerollDailyQuest" or "RequestRerollWeeklyQuest"
        if not remote then
            warn(string.format("[QuestReroll] %s is nil – remote not found", remoteName))
            debugLog("QuestReroll", "Reroll failed: remote missing")
            return false, "Remote missing"
        end

        debugLog("QuestReroll", string.format("Sending reroll request for %s quest %d", rerollState.selectedRerollType or tabId, serverIdx))

        local success, msg = false, "Reroll failed"
        local ok, err = pcall(function()
            success, msg = remote:InvokeServer(serverIdx)
        end)
        if not ok then
            warn(string.format("[QuestReroll] %s invoke error: %s", remoteName, tostring(err)))
            return false, "Request error"
        end

        return success, msg
    end

    local function enterSelectionMode()
        if rerollState.isRerollMode or rerollState.rerollInFlight then
            return
        end

        rerollState.isRerollMode = true
        rerollState.selectedRerollType = tabId == "daily" and "Daily" or "Weekly"
        debugLog("QuestReroll", string.format("Entered reroll mode for %s", rerollState.selectedRerollType))

        useBtn.Text = "CANCEL"
        useBtn.BackgroundColor3 = CANCEL_BTN_BG
        ubStr.Color = Color3.fromRGB(180, 60, 60)
        hintLbl.Text = "Pick a quest"
        hintLbl.TextColor3 = REROLL_ACCENT
        descLblR.Text = tabId == "daily"
            and "Select one daily quest card to reroll."
            or "Select one weekly quest card to reroll."
        descLblR.TextColor3 = REROLL_ACCENT

        local anyEligible = false
        for key, questCard in pairs(cardFrames) do
            if not claimedMap[key] and questCard and questCard.Parent then
                anyEligible = true
                local serverIdx = indexMap[key]

                local clickBtn = Instance.new("TextButton")
                clickBtn.Name = "RerollSelect"
                clickBtn.Size = UDim2.new(1, px(28), 1, px(24))
                clickBtn.Position = UDim2.new(0, -px(14), 0, -px(12))
                clickBtn.BackgroundColor3 = REROLL_ACCENT
                clickBtn.BackgroundTransparency = 0.9
                clickBtn.Text = ""
                clickBtn.AutoButtonColor = false
                clickBtn.ZIndex = 20
                clickBtn.Parent = questCard

                local clickCr = Instance.new("UICorner")
                clickCr.CornerRadius = UDim.new(0, px(12))
                clickCr.Parent = clickBtn

                local clickStr = Instance.new("UIStroke")
                clickStr.Color = REROLL_ACCENT
                clickStr.Thickness = 2
                clickStr.Transparency = 0.18
                clickStr.Parent = clickBtn

                local overlayLabel = Instance.new("TextLabel")
                overlayLabel.Name = "RerollLabel"
                overlayLabel.BackgroundTransparency = 1
                overlayLabel.Font = Enum.Font.GothamBold
                overlayLabel.Text = "CLICK TO REROLL"
                overlayLabel.TextColor3 = WHITE
                overlayLabel.TextSize = math.max(11, math.floor(px(12)))
                overlayLabel.Size = UDim2.new(1, 0, 0, px(18))
                overlayLabel.Position = UDim2.new(0, 0, 0.5, -px(9))
                overlayLabel.ZIndex = 21
                overlayLabel.Parent = clickBtn

                table.insert(rerollState.selectionOverlays, clickBtn)

                trackConn(clickBtn.MouseEnter:Connect(function()
                    if rerollState.isRerollMode and not rerollState.rerollInFlight then
                        TweenService:Create(clickBtn, TWEEN_QUICK, {BackgroundTransparency = 0.76}):Play()
                        clickStr.Color = GOLD
                        clickStr.Transparency = 0
                    end
                end))
                trackConn(clickBtn.MouseLeave:Connect(function()
                    if rerollState.isRerollMode and not rerollState.rerollInFlight then
                        TweenService:Create(clickBtn, TWEEN_QUICK, {BackgroundTransparency = 0.9}):Play()
                        clickStr.Color = REROLL_ACCENT
                        clickStr.Transparency = 0.18
                    end
                end))

                -- Reroll begins here: selecting a quest sends exactly one server request.
                trackConn(clickBtn.MouseButton1Click:Connect(function()
                    if not rerollState.isRerollMode or rerollState.rerollInFlight then
                        return
                    end

                    rerollState.rerollInFlight = true
                    useBtn.Active = false
                    useBtn.Text = "..."
                    debugLog("QuestReroll", string.format("Selected %s quest index %d", rerollState.selectedRerollType or tabId, serverIdx))

                    local success, msg = submitReroll(serverIdx)

                    -- Always restore the selection UI, even on failed remote lookups or request errors.
                    exitSelectionMode()

                    if success then
                        debugLog("QuestReroll", "Reroll success; refreshing quest list")
                        pcall(function()
                            if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
                        end)
                        if refreshQuests then
                            refreshQuests(tabId)
                        end
                    else
                        debugLog("QuestReroll", string.format("Reroll failed: %s", tostring(msg)))
                        showButtonError(msg, 2)
                    end
                end))
            end
        end

        if not anyEligible then
            exitSelectionMode()
            showButtonError("No quests", 1.5)
        end
    end

    -- Hover feedback on USE / CANCEL button
    trackConn(useBtn.MouseEnter:Connect(function()
        if useBtn.Active then
            local hoverColor = rerollState.isRerollMode and Color3.fromRGB(160, 50, 50) or REROLL_ACCENT
            TweenService:Create(useBtn, TWEEN_QUICK, {BackgroundColor3 = hoverColor}):Play()
        end
    end))
    trackConn(useBtn.MouseLeave:Connect(function()
        if useBtn.Active then
            local restColor = rerollState.isRerollMode and CANCEL_BTN_BG or REROLL_BTN_BG
            TweenService:Create(useBtn, TWEEN_QUICK, {BackgroundColor3 = restColor}):Play()
        end
    end))

    -- Reroll mode begins here: USE toggles a single selection state with guards.
    trackConn(useBtn.MouseButton1Click:Connect(function()
        if not useBtn.Active then return end
        if rerollState.rerollInFlight then return end
        if rerollState.isRerollMode then
            exitSelectionMode()
        else
            enterSelectionMode()
        end
    end))

    return exitSelectionMode
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local DailyQuestsUI = {}

function DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, initialTabId)
    if not parent then return nil end

    local preferredTab = (initialTabId == "weekly" or initialTabId == "achiev") and initialTabId or "daily"

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
        errLabel.Font      = Enum.Font.GothamMedium
        errLabel.Text      = "Quests unavailable – please try again."
        errLabel.TextColor3 = DIM_TEXT
        errLabel.TextSize  = px(16)
        errLabel.Size      = UDim2.new(1, 0, 0, px(60))
        errLabel.Parent    = parent
        return nil
    end

    -- Fetch quest data from server
    local quests = {}
    pcall(function()
        quests = getQuestsRF:InvokeServer()
    end)
    if type(quests) ~= "table" then quests = {} end

    ---------------------------------------------------------------------------
    -- Layout constants
    ---------------------------------------------------------------------------
    local TAB_W   = px(160)
    local TAB_GAP = px(10)
    local CARD_H  = px(130)   -- taller cards for more breathing room
    local HDR_H   = px(66)    -- header + subheader + accent bar

    local dailyH = HDR_H + math.max(1, #quests) * CARD_H + px(24)
    local rootH  = math.max(dailyH, px(220))

    ---------------------------------------------------------------------------
    -- Root container (single direct child of the ScrollingFrame parent)
    ---------------------------------------------------------------------------
    local root = Instance.new("Frame")
    root.Name                = "QuestsRoot"
    root.BackgroundTransparency = 1
    root.Size                = UDim2.new(1, 0, 0, rootH)
    root.LayoutOrder         = 1
    root.ClipsDescendants    = false
    root.Parent              = parent

    ---------------------------------------------------------------------------
    -- Left sidebar
    ---------------------------------------------------------------------------
    local sidebar = Instance.new("Frame")
    sidebar.Name             = "TabSidebar"
    sidebar.BackgroundColor3 = SIDEBAR_BG
    sidebar.BorderSizePixel  = 0
    sidebar.Size             = UDim2.new(0, TAB_W, 1, 0)
    sidebar.Position         = UDim2.new(0, 0, 0, 0)
    sidebar.ClipsDescendants = false
    sidebar.Parent           = root

    local sideCorner = Instance.new("UICorner")
    sideCorner.CornerRadius = UDim.new(0, px(10))
    sideCorner.Parent = sidebar

    local sideStroke = Instance.new("UIStroke")
    sideStroke.Color        = CARD_STROKE
    sideStroke.Thickness    = 1.2
    sideStroke.Transparency = 0.3
    sideStroke.Parent       = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    sideLayout.Padding             = UDim.new(0, px(3))
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent              = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop    = UDim.new(0, px(10))
    sidePad.PaddingBottom = UDim.new(0, px(10))
    sidePad.PaddingLeft   = UDim.new(0, px(6))
    sidePad.PaddingRight  = UDim.new(0, px(6))
    sidePad.Parent        = sidebar

    ---------------------------------------------------------------------------
    -- Content area (right of sidebar)
    ---------------------------------------------------------------------------
    local contentArea = Instance.new("Frame")
    contentArea.Name                = "ContentArea"
    contentArea.BackgroundTransparency = 1
    contentArea.Size                = UDim2.new(1, -(TAB_W + TAB_GAP), 1, 0)
    contentArea.Position            = UDim2.new(0, TAB_W + TAB_GAP, 0, 0)
    contentArea.ClipsDescendants    = false
    contentArea.Parent              = root

    ---------------------------------------------------------------------------
    -- Tab definitions
    ---------------------------------------------------------------------------
    local TAB_DEFS = {
        { id = "daily",  icon = "\u{25C6}", label = "Daily",        order = 1 },   -- ◆
        { id = "weekly", icon = "\u{25C8}", label = "Weekly",       order = 2 },   -- ◈
        { id = "achiev", icon = "\u{2605}", label = "Achievements", order = 3 },   -- ★
    }

    local tabButtons   = {}  -- [id] -> TextButton
    local contentPages = {}  -- [id] -> Frame

    ---------------------------------------------------------------------------
    -- Helper: build one sidebar tab button
    ---------------------------------------------------------------------------
    local function makeTabButton(iconChar, labelText, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Name            = labelText .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size            = UDim2.new(1, -px(2), 0, px(62))
        btn.LayoutOrder     = layoutOrder
        btn.Text            = ""
        btn.Parent          = sidebar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        -- Active indicator bar (left edge, hidden by default)
        local bar = Instance.new("Frame")
        bar.Name                 = "ActiveBar"
        bar.BackgroundColor3     = GOLD
        bar.BorderSizePixel      = 0
        bar.Size                 = UDim2.new(0, px(3), 0.6, 0)
        bar.AnchorPoint          = Vector2.new(0, 0.5)
        bar.Position             = UDim2.new(0, 0, 0.5, 0)
        bar.BackgroundTransparency = 1
        local barCr = Instance.new("UICorner")
        barCr.CornerRadius = UDim.new(0.5, 0)
        barCr.Parent = bar
        bar.Parent = btn

        -- Icon glyph
        local iconLbl = Instance.new("TextLabel")
        iconLbl.Name                = "Icon"
        iconLbl.BackgroundTransparency = 1
        iconLbl.Font                = Enum.Font.GothamBold
        iconLbl.Text                = iconChar
        iconLbl.TextColor3          = DIM_TEXT
        iconLbl.TextSize            = math.max(16, math.floor(px(18)))
        iconLbl.Size                = UDim2.new(1, 0, 0, px(24))
        iconLbl.Position            = UDim2.new(0, 0, 0, px(8))
        iconLbl.TextXAlignment      = Enum.TextXAlignment.Center
        iconLbl.Parent              = btn

        -- Text label
        local textLbl = Instance.new("TextLabel")
        textLbl.Name                = "Label"
        textLbl.BackgroundTransparency = 1
        textLbl.Font                = Enum.Font.GothamBold
        textLbl.Text                = labelText
        textLbl.TextColor3          = DIM_TEXT
        textLbl.TextSize            = math.max(11, math.floor(px(12)))
        textLbl.Size                = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position            = UDim2.new(0, px(3), 0, px(34))
        textLbl.TextXAlignment      = Enum.TextXAlignment.Center
        textLbl.TextTruncate        = Enum.TextTruncate.None
        textLbl.Parent              = btn

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1.2
        stroke.Transparency = 0.6
        stroke.Parent       = btn

        return btn
    end

    ---------------------------------------------------------------------------
    -- Create tab buttons
    ---------------------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        tabButtons[def.id] = makeTabButton(def.icon, def.label, def.order)
    end

    ---------------------------------------------------------------------------
    -- Active-tab state management
    ---------------------------------------------------------------------------
    local currentTab = "daily"
    local rerollExitFns = {}   -- populated by addRerollPanel; called on tab switch

    local function setActiveTab(tabId)
        currentTab = tabId

        -- Exit any active reroll selection mode when switching tabs
        for _, exitFn in ipairs(rerollExitFns) do
            pcall(exitFn)
        end

        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)

            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar   = btn:FindFirstChild("ActiveBar")
            local icon  = btn:FindFirstChild("Icon")
            local label = btn:FindFirstChild("Label")
            local stroke = btn:FindFirstChildOfClass("UIStroke")

            if bar    then bar.BackgroundTransparency   = active and 0    or 1    end
            if icon   then icon.TextColor3              = active and GOLD  or DIM_TEXT end
            if label  then label.TextColor3             = active and WHITE or DIM_TEXT end
            if stroke then stroke.Transparency          = active and 0.2  or 0.6  end
        end
        for id, page in pairs(contentPages) do
            page.Visible = (id == tabId)
        end
        -- Update the modal window title to match the active tab
        local TAB_TITLES = {
            daily  = "DAILY QUESTS",
            weekly = "WEEKLY QUESTS",
            achiev = "ACHIEVEMENTS",
        }
        if _G.SideUI and type(_G.SideUI.SetTitle) == "function" then
            _G.SideUI.SetTitle(TAB_TITLES[tabId] or "QUESTS")
        end
    end

    ---------------------------------------------------------------------------
    -- Wire tab button clicks + hover feedback
    ---------------------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        local id  = def.id
        local btn = tabButtons[id]

        trackConn(btn.MouseButton1Click:Connect(function()
            setActiveTab(id)
        end))
        trackConn(btn.MouseEnter:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(28, 26, 18)}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = SIDEBAR_BG}):Play()
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Helper: create a content page Frame (with UIListLayout)
    ---------------------------------------------------------------------------
    local function makePage(name, visible)
        local page = Instance.new("Frame")
        page.Name               = name
        page.BackgroundTransparency = 1
        page.Size               = UDim2.new(1, 0, 0, rootH)
        page.Visible            = visible
        page.ClipsDescendants   = false

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding   = UDim.new(0, px(10))
        layout.Parent    = page

        page.Parent = contentArea
        return page
    end

    ---------------------------------------------------------------------------
    -- Helper: make a gold section header
    ---------------------------------------------------------------------------
    local function makeHeader(text, subText, parentFrame)
        -- Wrapper to hold header + subheader + accent bar
        local hdrWrap = Instance.new("Frame")
        hdrWrap.Name                = "HeaderWrap"
        hdrWrap.BackgroundTransparency = 1
        hdrWrap.Size                = UDim2.new(1, 0, 0, px(58))
        hdrWrap.LayoutOrder         = 1
        hdrWrap.Parent              = parentFrame

        local hdr = Instance.new("TextLabel")
        hdr.Name                = "SectionHeader"
        hdr.BackgroundTransparency = 1
        hdr.Font                = Enum.Font.GothamBold
        hdr.Text                = text
        hdr.TextColor3          = GOLD
        hdr.TextSize            = math.max(18, math.floor(px(22)))
        hdr.TextXAlignment      = Enum.TextXAlignment.Left
        hdr.Size                = UDim2.new(1, 0, 0, px(28))
        hdr.Position            = UDim2.new(0, 0, 0, 0)
        hdr.Parent              = hdrWrap

        local sub = Instance.new("TextLabel")
        sub.Name                = "SubHeader"
        sub.BackgroundTransparency = 1
        sub.Font                = Enum.Font.GothamMedium
        sub.Text                = subText
        sub.TextColor3          = DIM_TEXT
        sub.TextSize            = math.max(11, math.floor(px(12)))
        sub.TextXAlignment      = Enum.TextXAlignment.Left
        sub.Size                = UDim2.new(1, 0, 0, px(18))
        sub.Position            = UDim2.new(0, 0, 0, px(30))
        sub.Parent              = hdrWrap

        -- Gold accent bar under header (matches BoostsUI style)
        local accentBar = Instance.new("Frame")
        accentBar.Name                = "AccentBar"
        accentBar.BackgroundColor3    = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.Size                = UDim2.new(1, 0, 0, px(2))
        accentBar.Position            = UDim2.new(0, 0, 1, -px(2))
        accentBar.BorderSizePixel     = 0
        accentBar.Parent              = hdrWrap
    end

    ---------------------------------------------------------------------------
    -- Helper: placeholder block (for Weekly / Achievements)
    ---------------------------------------------------------------------------
    local function makePlaceholder(message, layoutOrder, parentFrame)
        local block = Instance.new("Frame")
        block.Name              = "Placeholder"
        block.BackgroundColor3  = ROW_BG
        block.Size              = UDim2.new(1, 0, 0, px(110))
        block.LayoutOrder       = layoutOrder
        block.Parent            = parentFrame

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, px(12))
        bc.Parent = block

        local bs = Instance.new("UIStroke")
        bs.Color        = CARD_STROKE
        bs.Thickness    = 1.2
        bs.Transparency = 0.35
        bs.Parent       = block

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Font            = Enum.Font.GothamMedium
        lbl.Text            = message
        lbl.TextColor3      = DIM_TEXT
        lbl.TextSize        = math.max(13, math.floor(px(14)))
        lbl.Size            = UDim2.new(1, 0, 1, 0)
        lbl.TextXAlignment  = Enum.TextXAlignment.Center
        lbl.Parent          = block
    end

    ---------------------------------------------------------------------------
    -- DAILY page
    ---------------------------------------------------------------------------
    local dailyPage = makePage("DailyPage", true)
    contentPages["daily"] = dailyPage

    makeHeader("DAILY QUESTS", "Complete quests to earn coin rewards. Resets daily!", dailyPage)

    if #quests == 0 then
        makePlaceholder("No quests available today.", 3, dailyPage)
    end

    ---------------------------------------------------------------------------
    -- Lookup tables for live updates
    ---------------------------------------------------------------------------
    local progressBars  = {}
    local progressTexts = {}
    local claimButtons  = {}
    local questGoals    = {}
    local questClaimed  = {}

    ---------------------------------------------------------------------------
    -- Quest cards (Daily)
    ---------------------------------------------------------------------------
    local questCardStrokes = {}   -- [questId] = UIStroke (for state glow)
    local questCards       = {}   -- [questId] = Frame

    for i, quest in ipairs(quests) do
        questGoals[quest.id]   = quest.goal
        questClaimed[quest.id] = quest.claimed

        local card = Instance.new("Frame")
        card.Name             = "Quest_" .. quest.id
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, 0, 0, px(120))
        card.LayoutOrder      = 10 + i
        card.Parent           = dailyPage
        questCards[quest.id]  = card

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1.2
        stroke.Transparency = 0.35
        stroke.Parent       = card
        questCardStrokes[quest.id] = stroke

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(14))
        pad.PaddingRight  = UDim.new(0, px(14))
        pad.PaddingTop    = UDim.new(0, px(12))
        pad.PaddingBottom = UDim.new(0, px(12))
        pad.Parent        = card

        -- Left accent bar for visual state
        local accentBar = Instance.new("Frame")
        accentBar.Name                = "StateAccent"
        accentBar.BackgroundColor3    = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.BorderSizePixel     = 0
        accentBar.Size                = UDim2.new(0, px(3), 0.7, 0)
        accentBar.AnchorPoint         = Vector2.new(0, 0.5)
        accentBar.Position            = UDim2.new(0, -px(10), 0.5, 0)
        local accentCr = Instance.new("UICorner")
        accentCr.CornerRadius = UDim.new(0.5, 0)
        accentCr.Parent = accentBar
        accentBar.Parent = card

        -- Title
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name               = "Title"
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font               = Enum.Font.GothamBold
        titleLbl.Text               = quest.title
        titleLbl.TextColor3         = WHITE
        titleLbl.TextSize           = math.max(15, math.floor(px(17)))
        titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
        titleLbl.Size               = UDim2.new(0.58, 0, 0, px(22))
        titleLbl.Position           = UDim2.new(0, 0, 0, 0)
        titleLbl.Parent             = card

        -- Reward badge (right of title): framed coin icon + amount
        local rewardBadge = Instance.new("Frame")
        rewardBadge.Name              = "RewardBadge"
        rewardBadge.BackgroundColor3  = Color3.fromRGB(36, 33, 18)
        rewardBadge.BackgroundTransparency = 0.3
        rewardBadge.Size              = UDim2.new(0, px(100), 0, px(26))
        rewardBadge.AnchorPoint       = Vector2.new(1, 0)
        rewardBadge.Position          = UDim2.new(1, 0, 0, -px(2))
        rewardBadge.Parent            = card

        local badgeCr = Instance.new("UICorner")
        badgeCr.CornerRadius = UDim.new(0, px(8))
        badgeCr.Parent = rewardBadge

        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color       = CLAIM_GOLD_GLOW
        badgeStroke.Thickness   = 1
        badgeStroke.Transparency = 0.55
        badgeStroke.Parent      = rewardBadge

        local coinSize = px(18)
        local coinIcon = makeCoinIcon(rewardBadge, coinSize)
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position    = UDim2.new(0, px(8), 0.5, 0)

        local amtLbl = Instance.new("TextLabel")
        amtLbl.Name                = "Amount"
        amtLbl.BackgroundTransparency = 1
        amtLbl.Font                = Enum.Font.GothamBold
        amtLbl.Text                = tostring(quest.reward)
        amtLbl.TextColor3          = GOLD
        amtLbl.TextSize            = math.max(13, math.floor(px(14)))
        amtLbl.TextXAlignment      = Enum.TextXAlignment.Right
        amtLbl.Size                = UDim2.new(1, -px(30), 1, 0)
        amtLbl.AnchorPoint         = Vector2.new(1, 0)
        amtLbl.Position            = UDim2.new(1, -px(8), 0, 0)
        amtLbl.Parent              = rewardBadge

        -- Description
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "Desc"
        descLbl.BackgroundTransparency = 1
        descLbl.Font               = Enum.Font.GothamMedium
        descLbl.Text               = quest.desc
        descLbl.TextColor3         = DIM_TEXT
        descLbl.TextSize           = math.max(11, math.floor(px(12)))
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.TextWrapped        = true
        descLbl.Size               = UDim2.new(0.7, 0, 0, px(18))
        descLbl.Position           = UDim2.new(0, 0, 0, px(26))
        descLbl.Parent             = card

        -- Progress bar track
        local barY = px(52)
        local barH = px(16)
        local track = Instance.new("Frame")
        track.Name             = "BarTrack"
        track.BackgroundColor3 = BAR_BG
        track.Size             = UDim2.new(0.62, 0, 0, barH)
        track.Position         = UDim2.new(0, 0, 0, barY)
        track.Parent           = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, px(6))
        trackCorner.Parent = track

        local trackStroke = Instance.new("UIStroke")
        trackStroke.Color        = CARD_STROKE
        trackStroke.Thickness    = 1
        trackStroke.Transparency = 0.5
        trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        trackStroke.Parent       = track

        -- Progress bar fill
        local pct = (quest.goal > 0) and math.clamp(quest.progress / quest.goal, 0, 1) or 0
        local fill = Instance.new("Frame")
        fill.Name             = "BarFill"
        fill.BackgroundColor3 = BAR_FILL
        fill.BackgroundTransparency = 0.1
        fill.Size             = UDim2.new(pct, 0, 1, 0)
        fill.Parent           = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, px(6))
        fillCorner.Parent = fill

        -- Subtle inner highlight on fill bar
        local fillHighlight = Instance.new("Frame")
        fillHighlight.Name = "FillHighlight"
        fillHighlight.BackgroundColor3 = Color3.fromRGB(255, 245, 180)
        fillHighlight.BackgroundTransparency = 0.65
        fillHighlight.BorderSizePixel = 0
        fillHighlight.Size = UDim2.new(1, 0, 0.35, 0)
        fillHighlight.Position = UDim2.new(0, 0, 0, 0)
        fillHighlight.Parent = fill

        local fillHlCr = Instance.new("UICorner")
        fillHlCr.CornerRadius = UDim.new(0, px(6))
        fillHlCr.Parent = fillHighlight

        progressBars[quest.id] = fill

        -- Progress text (e.g., "3/5")
        local progText = Instance.new("TextLabel")
        progText.Name               = "ProgressText"
        progText.BackgroundTransparency = 1
        progText.Font               = Enum.Font.GothamBold
        progText.Text               = tostring(quest.progress) .. "/" .. tostring(quest.goal)
        progText.TextColor3         = WHITE
        progText.TextSize           = math.max(11, math.floor(px(12)))
        progText.Size               = UDim2.new(1, 0, 1, 0)
        progText.Parent             = track

        progressTexts[quest.id] = progText

        -- Claim button
        local btnW2 = px(100)
        local btnH  = px(34)
        local btn = Instance.new("TextButton")
        btn.Name            = "ClaimBtn"
        btn.AutoButtonColor = false
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = math.max(13, math.floor(px(14)))
        btn.Size            = UDim2.new(0, btnW2, 0, btnH)
        btn.AnchorPoint     = Vector2.new(1, 0)
        btn.Position        = UDim2.new(1, 0, 0, barY - px(2))
        btn.Parent          = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color       = BTN_STROKE
        btnStroke.Thickness   = 1.4
        btnStroke.Transparency = 0.3
        btnStroke.Parent      = btn

        claimButtons[quest.id] = btn

        -- Card state helper: updates card bg, accent, stroke for visual states
        local function updateCardVisuals(progress, goal, claimed)
            if claimed then
                card.BackgroundColor3 = ROW_CLAIMED_BG
                stroke.Color = GREEN_GLOW
                stroke.Thickness = 1.8
                stroke.Transparency = 0.3
                accentBar.BackgroundColor3 = GREEN_GLOW
                accentBar.BackgroundTransparency = 0.2
            elseif progress >= goal then
                card.BackgroundColor3 = ROW_CLAIMABLE_BG
                stroke.Color = CLAIM_GOLD_GLOW
                stroke.Thickness = 2
                stroke.Transparency = 0.15
                accentBar.BackgroundColor3 = CLAIM_GOLD_GLOW
                accentBar.BackgroundTransparency = 0
            else
                card.BackgroundColor3 = ROW_BG
                stroke.Color = CARD_STROKE
                stroke.Thickness = 1.2
                stroke.Transparency = 0.35
                accentBar.BackgroundColor3 = GOLD
                accentBar.BackgroundTransparency = 0.5
            end
        end

        -- Button state helper
        local function updateButtonState(progress, goal, claimed)
            if claimed then
                btn.Text             = "\u{2714} CLAIMED"
                btn.BackgroundColor3 = BTN_CLAIMED
                btn.TextColor3       = GREEN_GLOW
                btn.Active           = false
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.5
            elseif progress >= goal then
                btn.Text             = "\u{2B50} CLAIM"
                btn.BackgroundColor3 = BTN_CLAIM
                btn.TextColor3       = WHITE
                btn.Active           = true
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.15
            else
                btn.Text             = tostring(progress) .. "/" .. tostring(goal)
                btn.BackgroundColor3 = BTN_LOCKED
                btn.TextColor3       = DIM_TEXT
                btn.Active           = false
                btnStroke.Color      = BTN_STROKE
                btnStroke.Transparency = 0.4
            end
            updateCardVisuals(progress, goal, claimed)
        end

        updateButtonState(quest.progress, quest.goal, quest.claimed)

        -- Button hover feedback (matching BoostsUI style)
        trackConn(btn.MouseEnter:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(45, 210, 90)}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = BTN_CLAIM}):Play()
            end
        end))

        -- Claim handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if questClaimed[quest.id] then return end
            if not btn.Active then return end

            btn.Active = false
            btn.Text   = "..."

            local success = false
            pcall(function()
                success = claimQuestRF:InvokeServer(quest.id)
            end)

            if success then
                questClaimed[quest.id] = true
                updateButtonState(quest.goal, quest.goal, true)
                -- Flash gold
                local origColor = card.BackgroundColor3
                TweenService:Create(card, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(60, 55, 25)}):Play()
                task.delay(0.3, function()
                    if card and card.Parent then
                        TweenService:Create(card, TWEEN_QUICK,
                            {BackgroundColor3 = origColor}):Play()
                    end
                end)
                if _G.UpdateShopHeaderCoins then
                    pcall(_G.UpdateShopHeaderCoins)
                end
            else
                updateButtonState(quest.progress, quest.goal, false)
            end
        end))
    end

    -- Reroll panel at the bottom of the Daily tab
    local dailyIndexMap = {}
    for i, quest in ipairs(quests) do
        dailyIndexMap[quest.id] = i
    end
    local dailyRerollExit = addRerollPanel(dailyPage, "daily", questCards, questClaimed, dailyIndexMap, function(selectedTab)
        task.defer(function()
            DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, selectedTab)
        end)
    end)
    table.insert(rerollExitFns, dailyRerollExit)

    ---------------------------------------------------------------------------
    -- WEEKLY page (fully functional – fetches real weekly quest data)
    ---------------------------------------------------------------------------
    local weeklyPage = makePage("WeeklyPage", false)
    contentPages["weekly"] = weeklyPage

    makeHeader("WEEKLY QUESTS", "Larger challenges \u{2013} resets every Monday!", weeklyPage)

    -- Fetch weekly quest data from server
    local weeklyQuests = {}
    if getWeeklyRF then
        pcall(function()
            weeklyQuests = getWeeklyRF:InvokeServer()
        end)
    end
    if type(weeklyQuests) ~= "table" then weeklyQuests = {} end

    if #weeklyQuests == 0 then
        makePlaceholder("No weekly quests available.", 3, weeklyPage)
    end

    -- Lookup tables for weekly live updates
    local wkProgressBars  = {}
    local wkProgressTexts = {}
    local wkClaimButtons  = {}
    local wkGoals         = {}
    local wkClaimed       = {}
    local wkCards         = {}
    local wkCardStrokes   = {}

    for i, wq in ipairs(weeklyQuests) do
        local questIdx       = wq.index or i
        wkGoals[questIdx]    = wq.goal
        wkClaimed[questIdx]  = wq.claimed

        local card = Instance.new("Frame")
        card.Name             = "WeeklyQuest_" .. questIdx
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, 0, 0, px(120))
        card.LayoutOrder      = 10 + i
        card.Parent           = weeklyPage
        wkCards[questIdx]     = card

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1.2
        stroke.Transparency = 0.35
        stroke.Parent       = card
        wkCardStrokes[questIdx] = stroke

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(14))
        pad.PaddingRight  = UDim.new(0, px(14))
        pad.PaddingTop    = UDim.new(0, px(12))
        pad.PaddingBottom = UDim.new(0, px(12))
        pad.Parent        = card

        -- Left accent bar
        local accentBar = Instance.new("Frame")
        accentBar.Name                = "StateAccent"
        accentBar.BackgroundColor3    = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.BorderSizePixel     = 0
        accentBar.Size                = UDim2.new(0, px(3), 0.7, 0)
        accentBar.AnchorPoint         = Vector2.new(0, 0.5)
        accentBar.Position            = UDim2.new(0, -px(10), 0.5, 0)
        local accentCr = Instance.new("UICorner")
        accentCr.CornerRadius = UDim.new(0.5, 0)
        accentCr.Parent = accentBar
        accentBar.Parent = card

        -- Title
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name               = "Title"
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font               = Enum.Font.GothamBold
        titleLbl.Text               = wq.title
        titleLbl.TextColor3         = WHITE
        titleLbl.TextSize           = math.max(15, math.floor(px(17)))
        titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
        titleLbl.Size               = UDim2.new(0.58, 0, 0, px(22))
        titleLbl.Position           = UDim2.new(0, 0, 0, 0)
        titleLbl.Parent             = card

        -- Reward badge
        local rewardBadge = Instance.new("Frame")
        rewardBadge.Name              = "RewardBadge"
        rewardBadge.BackgroundColor3  = Color3.fromRGB(36, 33, 18)
        rewardBadge.BackgroundTransparency = 0.3
        rewardBadge.Size              = UDim2.new(0, px(100), 0, px(26))
        rewardBadge.AnchorPoint       = Vector2.new(1, 0)
        rewardBadge.Position          = UDim2.new(1, 0, 0, -px(2))
        rewardBadge.Parent            = card

        local badgeCr = Instance.new("UICorner")
        badgeCr.CornerRadius = UDim.new(0, px(8))
        badgeCr.Parent = rewardBadge

        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color       = CLAIM_GOLD_GLOW
        badgeStroke.Thickness   = 1
        badgeStroke.Transparency = 0.55
        badgeStroke.Parent      = rewardBadge

        local coinSize = px(18)
        local coinIcon = makeCoinIcon(rewardBadge, coinSize)
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position    = UDim2.new(0, px(8), 0.5, 0)

        local amtLbl = Instance.new("TextLabel")
        amtLbl.Name                = "Amount"
        amtLbl.BackgroundTransparency = 1
        amtLbl.Font                = Enum.Font.GothamBold
        amtLbl.Text                = tostring(wq.reward)
        amtLbl.TextColor3          = GOLD
        amtLbl.TextSize            = math.max(13, math.floor(px(14)))
        amtLbl.TextXAlignment      = Enum.TextXAlignment.Right
        amtLbl.Size                = UDim2.new(1, -px(30), 1, 0)
        amtLbl.AnchorPoint         = Vector2.new(1, 0)
        amtLbl.Position            = UDim2.new(1, -px(8), 0, 0)
        amtLbl.Parent              = rewardBadge

        -- Description
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "Desc"
        descLbl.BackgroundTransparency = 1
        descLbl.Font               = Enum.Font.GothamMedium
        descLbl.Text               = wq.desc
        descLbl.TextColor3         = DIM_TEXT
        descLbl.TextSize           = math.max(11, math.floor(px(12)))
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.TextWrapped        = true
        descLbl.Size               = UDim2.new(0.7, 0, 0, px(18))
        descLbl.Position           = UDim2.new(0, 0, 0, px(26))
        descLbl.Parent             = card

        -- Progress bar track
        local barY = px(52)
        local barH = px(16)
        local track = Instance.new("Frame")
        track.Name             = "BarTrack"
        track.BackgroundColor3 = BAR_BG
        track.Size             = UDim2.new(0.62, 0, 0, barH)
        track.Position         = UDim2.new(0, 0, 0, barY)
        track.Parent           = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, px(6))
        trackCorner.Parent = track

        local trackStroke = Instance.new("UIStroke")
        trackStroke.Color        = CARD_STROKE
        trackStroke.Thickness    = 1
        trackStroke.Transparency = 0.5
        trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        trackStroke.Parent       = track

        -- Progress bar fill
        local pctW = (wq.goal > 0) and math.clamp(wq.progress / wq.goal, 0, 1) or 0
        local fill = Instance.new("Frame")
        fill.Name             = "BarFill"
        fill.BackgroundColor3 = BAR_FILL
        fill.BackgroundTransparency = 0.1
        fill.Size             = UDim2.new(pctW, 0, 1, 0)
        fill.Parent           = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, px(6))
        fillCorner.Parent = fill

        local fillHighlight = Instance.new("Frame")
        fillHighlight.Name = "FillHighlight"
        fillHighlight.BackgroundColor3 = Color3.fromRGB(255, 245, 180)
        fillHighlight.BackgroundTransparency = 0.65
        fillHighlight.BorderSizePixel = 0
        fillHighlight.Size = UDim2.new(1, 0, 0.35, 0)
        fillHighlight.Position = UDim2.new(0, 0, 0, 0)
        fillHighlight.Parent = fill

        local fillHlCr = Instance.new("UICorner")
        fillHlCr.CornerRadius = UDim.new(0, px(6))
        fillHlCr.Parent = fillHighlight

        wkProgressBars[questIdx] = fill

        -- Progress text
        local progText = Instance.new("TextLabel")
        progText.Name               = "ProgressText"
        progText.BackgroundTransparency = 1
        progText.Font               = Enum.Font.GothamBold
        progText.Text               = tostring(wq.progress) .. "/" .. tostring(wq.goal)
        progText.TextColor3         = WHITE
        progText.TextSize           = math.max(11, math.floor(px(12)))
        progText.Size               = UDim2.new(1, 0, 1, 0)
        progText.Parent             = track

        wkProgressTexts[questIdx] = progText

        -- Claim button
        local btnW2 = px(100)
        local btnH  = px(34)
        local btn = Instance.new("TextButton")
        btn.Name            = "ClaimBtn"
        btn.AutoButtonColor = false
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = math.max(13, math.floor(px(14)))
        btn.Size            = UDim2.new(0, btnW2, 0, btnH)
        btn.AnchorPoint     = Vector2.new(1, 0)
        btn.Position        = UDim2.new(1, 0, 0, barY - px(2))
        btn.Parent          = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color       = BTN_STROKE
        btnStroke.Thickness   = 1.4
        btnStroke.Transparency = 0.3
        btnStroke.Parent      = btn

        wkClaimButtons[questIdx] = btn

        -- Card + button state helpers (identical pattern to daily)
        local function updateWkCardVisuals(progress, goal, claimed)
            if claimed then
                card.BackgroundColor3 = ROW_CLAIMED_BG
                stroke.Color = GREEN_GLOW
                stroke.Thickness = 1.8
                stroke.Transparency = 0.3
                accentBar.BackgroundColor3 = GREEN_GLOW
                accentBar.BackgroundTransparency = 0.2
            elseif progress >= goal then
                card.BackgroundColor3 = ROW_CLAIMABLE_BG
                stroke.Color = CLAIM_GOLD_GLOW
                stroke.Thickness = 2
                stroke.Transparency = 0.15
                accentBar.BackgroundColor3 = CLAIM_GOLD_GLOW
                accentBar.BackgroundTransparency = 0
            else
                card.BackgroundColor3 = ROW_BG
                stroke.Color = CARD_STROKE
                stroke.Thickness = 1.2
                stroke.Transparency = 0.35
                accentBar.BackgroundColor3 = GOLD
                accentBar.BackgroundTransparency = 0.5
            end
        end

        local function updateWkBtnState(progress, goal, claimed)
            if claimed then
                btn.Text             = "\u{2714} CLAIMED"
                btn.BackgroundColor3 = BTN_CLAIMED
                btn.TextColor3       = GREEN_GLOW
                btn.Active           = false
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.5
            elseif progress >= goal then
                btn.Text             = "\u{2B50} CLAIM"
                btn.BackgroundColor3 = BTN_CLAIM
                btn.TextColor3       = WHITE
                btn.Active           = true
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.15
            else
                btn.Text             = tostring(progress) .. "/" .. tostring(goal)
                btn.BackgroundColor3 = BTN_LOCKED
                btn.TextColor3       = DIM_TEXT
                btn.Active           = false
                btnStroke.Color      = BTN_STROKE
                btnStroke.Transparency = 0.4
            end
            updateWkCardVisuals(progress, goal, claimed)
        end

        updateWkBtnState(wq.progress, wq.goal, wq.claimed)

        -- Hover feedback
        trackConn(btn.MouseEnter:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(45, 210, 90)}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = BTN_CLAIM}):Play()
            end
        end))

        -- Claim handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if wkClaimed[questIdx] then return end
            if not btn.Active then return end

            btn.Active = false
            btn.Text   = "..."

            local success = false
            if claimWeeklyRF then
                pcall(function()
                    success = claimWeeklyRF:InvokeServer(questIdx)
                end)
            end

            if success then
                wkClaimed[questIdx] = true
                updateWkBtnState(wq.goal, wq.goal, true)
                -- Flash gold
                local origColor2 = card.BackgroundColor3
                TweenService:Create(card, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(60, 55, 25)}):Play()
                task.delay(0.3, function()
                    if card and card.Parent then
                        TweenService:Create(card, TWEEN_QUICK,
                            {BackgroundColor3 = origColor2}):Play()
                    end
                end)
                if _G.UpdateShopHeaderCoins then
                    pcall(_G.UpdateShopHeaderCoins)
                end
            else
                updateWkBtnState(wq.progress, wq.goal, false)
            end
        end))
    end

    -- Reroll panel at the bottom of the Weekly tab
    local wkIndexMap = {}
    for i, wq in ipairs(weeklyQuests) do
        local idx = wq.index or i
        wkIndexMap[idx] = idx
    end
    local weeklyRerollExit = addRerollPanel(weeklyPage, "weekly", wkCards, wkClaimed, wkIndexMap, function(selectedTab)
        task.defer(function()
            DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, selectedTab)
        end)
    end)
    table.insert(rerollExitFns, weeklyRerollExit)

    ---------------------------------------------------------------------------
    -- ACHIEVEMENTS page  (fully functional)
    ---------------------------------------------------------------------------
    local achievPage = makePage("AchievPage", false)
    contentPages["achiev"] = achievPage

    makeHeader("ACHIEVEMENTS", "Track your progress and earn rewards!", achievPage)

    -- Remotes for achievement system
    local getAchievRF
    local claimAchievRF2
    local achievProgressRE

    pcall(function()
        local rm = ReplicatedStorage:WaitForChild("Remotes", 5)
        if rm then
            getAchievRF     = rm:FindFirstChild("GetAchievements")
            claimAchievRF2  = rm:FindFirstChild("ClaimAchievement")
            achievProgressRE = rm:FindFirstChild("AchievementProgress")
        end
    end)

    -- Fetch achievement data
    local achievements = {}
    if getAchievRF then
        pcall(function()
            achievements = getAchievRF:InvokeServer()
        end)
    end
    if type(achievements) ~= "table" then achievements = {} end

    -- Lookup tables for live updates
    local achProgressBars  = {} -- [id] -> fill Frame
    local achProgressTexts = {} -- [id] -> TextLabel
    local achClaimButtons  = {} -- [id] -> TextButton
    local achGoals         = {} -- [id] -> number
    local achClaimed       = {} -- [id] -> bool
    local achCards         = {} -- [id] -> Frame
    local achCardStrokes   = {} -- [id] -> UIStroke

    if #achievements == 0 then
        makePlaceholder("Loading achievements...", 3, achievPage)
    end

    for i, ach in ipairs(achievements) do
        achGoals[ach.id]   = ach.target
        achClaimed[ach.id] = ach.claimed

        local card = Instance.new("Frame")
        card.Name             = "Ach_" .. ach.id
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, 0, 0, px(120))
        card.LayoutOrder      = 10 + i
        card.Parent           = achievPage
        achCards[ach.id]      = card

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color        = CARD_STROKE
        stroke.Thickness    = 1.2
        stroke.Transparency = 0.35
        stroke.Parent       = card
        achCardStrokes[ach.id] = stroke

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, px(14))
        pad.PaddingRight  = UDim.new(0, px(14))
        pad.PaddingTop    = UDim.new(0, px(12))
        pad.PaddingBottom = UDim.new(0, px(12))
        pad.Parent        = card

        -- Left accent bar
        local accentBar = Instance.new("Frame")
        accentBar.Name                = "StateAccent"
        accentBar.BackgroundColor3    = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.BorderSizePixel     = 0
        accentBar.Size                = UDim2.new(0, px(3), 0.7, 0)
        accentBar.AnchorPoint         = Vector2.new(0, 0.5)
        accentBar.Position            = UDim2.new(0, -px(10), 0.5, 0)
        local accentCr = Instance.new("UICorner")
        accentCr.CornerRadius = UDim.new(0.5, 0)
        accentCr.Parent = accentBar
        accentBar.Parent = card

        -- Icon glyph (left side)
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Name                = "AchIcon"
        iconLabel.BackgroundTransparency = 1
        iconLabel.Font                = Enum.Font.GothamBold
        iconLabel.Text                = ach.icon or "★"
        iconLabel.TextSize            = math.max(20, math.floor(px(24)))
        iconLabel.TextColor3          = GOLD
        iconLabel.Size                = UDim2.new(0, px(32), 0, px(32))
        iconLabel.Position            = UDim2.new(0, 0, 0, 0)
        iconLabel.Parent              = card

        -- Title (right of icon)
        local titleLbl = Instance.new("TextLabel")
        titleLbl.Name               = "Title"
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font               = Enum.Font.GothamBold
        titleLbl.Text               = ach.title
        titleLbl.TextColor3         = WHITE
        titleLbl.TextSize           = math.max(15, math.floor(px(17)))
        titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
        titleLbl.Size               = UDim2.new(0.50, 0, 0, px(22))
        titleLbl.Position           = UDim2.new(0, px(38), 0, 0)
        titleLbl.Parent             = card

        -- Reward badge (right of title)
        local rewardBadge = Instance.new("Frame")
        rewardBadge.Name              = "RewardBadge"
        rewardBadge.BackgroundColor3  = Color3.fromRGB(36, 33, 18)
        rewardBadge.BackgroundTransparency = 0.3
        rewardBadge.Size              = UDim2.new(0, px(100), 0, px(26))
        rewardBadge.AnchorPoint       = Vector2.new(1, 0)
        rewardBadge.Position          = UDim2.new(1, 0, 0, -px(2))
        rewardBadge.Parent            = card

        local badgeCr = Instance.new("UICorner")
        badgeCr.CornerRadius = UDim.new(0, px(8))
        badgeCr.Parent = rewardBadge

        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color       = CLAIM_GOLD_GLOW
        badgeStroke.Thickness   = 1
        badgeStroke.Transparency = 0.55
        badgeStroke.Parent      = rewardBadge

        local coinSize = px(18)
        local coinIcon = makeCoinIcon(rewardBadge, coinSize)
        coinIcon.AnchorPoint = Vector2.new(0, 0.5)
        coinIcon.Position    = UDim2.new(0, px(8), 0.5, 0)

        local amtLbl = Instance.new("TextLabel")
        amtLbl.Name                = "Amount"
        amtLbl.BackgroundTransparency = 1
        amtLbl.Font                = Enum.Font.GothamBold
        amtLbl.Text                = tostring(ach.reward)
        amtLbl.TextColor3          = GOLD
        amtLbl.TextSize            = math.max(13, math.floor(px(14)))
        amtLbl.TextXAlignment      = Enum.TextXAlignment.Right
        amtLbl.Size                = UDim2.new(1, -px(30), 1, 0)
        amtLbl.AnchorPoint         = Vector2.new(1, 0)
        amtLbl.Position            = UDim2.new(1, -px(8), 0, 0)
        amtLbl.Parent              = rewardBadge

        -- Description
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "Desc"
        descLbl.BackgroundTransparency = 1
        descLbl.Font               = Enum.Font.GothamMedium
        descLbl.Text               = ach.desc
        descLbl.TextColor3         = DIM_TEXT
        descLbl.TextSize           = math.max(11, math.floor(px(12)))
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.TextWrapped        = true
        descLbl.Size               = UDim2.new(0.7, 0, 0, px(18))
        descLbl.Position           = UDim2.new(0, px(38), 0, px(26))
        descLbl.Parent             = card

        -- Progress bar track
        local barY = px(52)
        local barH = px(16)
        local track = Instance.new("Frame")
        track.Name             = "BarTrack"
        track.BackgroundColor3 = BAR_BG
        track.Size             = UDim2.new(0.62, 0, 0, barH)
        track.Position         = UDim2.new(0, 0, 0, barY)
        track.Parent           = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, px(6))
        trackCorner.Parent = track

        local trackStroke = Instance.new("UIStroke")
        trackStroke.Color        = CARD_STROKE
        trackStroke.Thickness    = 1
        trackStroke.Transparency = 0.5
        trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        trackStroke.Parent       = track

        -- Progress bar fill
        local pct = (ach.target > 0) and math.clamp(ach.progress / ach.target, 0, 1) or 0
        local fill = Instance.new("Frame")
        fill.Name             = "BarFill"
        fill.BackgroundColor3 = BAR_FILL
        fill.BackgroundTransparency = 0.1
        fill.Size             = UDim2.new(pct, 0, 1, 0)
        fill.Parent           = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, px(6))
        fillCorner.Parent = fill

        -- Subtle inner highlight on fill bar
        local fillHighlight = Instance.new("Frame")
        fillHighlight.Name = "FillHighlight"
        fillHighlight.BackgroundColor3 = Color3.fromRGB(255, 245, 180)
        fillHighlight.BackgroundTransparency = 0.65
        fillHighlight.BorderSizePixel = 0
        fillHighlight.Size = UDim2.new(1, 0, 0.35, 0)
        fillHighlight.Position = UDim2.new(0, 0, 0, 0)
        fillHighlight.Parent = fill

        local fillHlCr = Instance.new("UICorner")
        fillHlCr.CornerRadius = UDim.new(0, px(6))
        fillHlCr.Parent = fillHighlight

        achProgressBars[ach.id] = fill

        -- Progress text
        local progText = Instance.new("TextLabel")
        progText.Name               = "ProgressText"
        progText.BackgroundTransparency = 1
        progText.Font               = Enum.Font.GothamBold
        progText.Text               = tostring(ach.progress) .. "/" .. tostring(ach.target)
        progText.TextColor3         = WHITE
        progText.TextSize           = math.max(11, math.floor(px(12)))
        progText.Size               = UDim2.new(1, 0, 1, 0)
        progText.Parent             = track
        achProgressTexts[ach.id] = progText

        -- Claim / status button
        local btnW2 = px(100)
        local btnH  = px(34)
        local btn = Instance.new("TextButton")
        btn.Name            = "ClaimBtn"
        btn.AutoButtonColor = false
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = math.max(13, math.floor(px(14)))
        btn.Size            = UDim2.new(0, btnW2, 0, btnH)
        btn.AnchorPoint     = Vector2.new(1, 0)
        btn.Position        = UDim2.new(1, 0, 0, barY - px(2))
        btn.Parent          = card

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = btn

        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color       = BTN_STROKE
        btnStroke.Thickness   = 1.4
        btnStroke.Transparency = 0.3
        btnStroke.Parent      = btn

        achClaimButtons[ach.id] = btn

        -- Card visuals helper
        local function updateAchCardVisuals(progress, goal, claimed)
            if claimed then
                card.BackgroundColor3 = ROW_CLAIMED_BG
                stroke.Color = GREEN_GLOW
                stroke.Thickness = 1.8
                stroke.Transparency = 0.3
                accentBar.BackgroundColor3 = GREEN_GLOW
                accentBar.BackgroundTransparency = 0.2
            elseif progress >= goal then
                card.BackgroundColor3 = ROW_CLAIMABLE_BG
                stroke.Color = CLAIM_GOLD_GLOW
                stroke.Thickness = 2
                stroke.Transparency = 0.15
                accentBar.BackgroundColor3 = CLAIM_GOLD_GLOW
                accentBar.BackgroundTransparency = 0
            else
                card.BackgroundColor3 = ROW_BG
                stroke.Color = CARD_STROKE
                stroke.Thickness = 1.2
                stroke.Transparency = 0.35
                accentBar.BackgroundColor3 = GOLD
                accentBar.BackgroundTransparency = 0.5
            end
        end

        -- Button state helper
        local function updateAchBtnState(progress, goal, claimed)
            if claimed then
                btn.Text             = "\u{2714} CLAIMED"
                btn.BackgroundColor3 = BTN_CLAIMED
                btn.TextColor3       = GREEN_GLOW
                btn.Active           = false
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.5
            elseif progress >= goal then
                btn.Text             = "\u{2B50} CLAIM"
                btn.BackgroundColor3 = BTN_CLAIM
                btn.TextColor3       = WHITE
                btn.Active           = true
                btnStroke.Color      = GREEN_GLOW
                btnStroke.Transparency = 0.15
            else
                btn.Text             = tostring(progress) .. "/" .. tostring(goal)
                btn.BackgroundColor3 = BTN_LOCKED
                btn.TextColor3       = DIM_TEXT
                btn.Active           = false
                btnStroke.Color      = BTN_STROKE
                btnStroke.Transparency = 0.4
            end
            updateAchCardVisuals(progress, goal, claimed)
        end

        updateAchBtnState(ach.progress, ach.target, ach.claimed)

        -- Hover
        trackConn(btn.MouseEnter:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(45, 210, 90)}):Play()
            end
        end))
        trackConn(btn.MouseLeave:Connect(function()
            if btn.Active then
                TweenService:Create(btn, TWEEN_QUICK,
                    {BackgroundColor3 = BTN_CLAIM}):Play()
            end
        end))

        -- Claim handler
        trackConn(btn.MouseButton1Click:Connect(function()
            if achClaimed[ach.id] then return end
            if not btn.Active then return end

            btn.Active = false
            btn.Text   = "..."

            local success = false
            if claimAchievRF2 then
                pcall(function()
                    success = claimAchievRF2:InvokeServer(ach.id)
                end)
            end

            if success then
                achClaimed[ach.id] = true
                updateAchBtnState(ach.target, ach.target, true)
                -- Flash gold
                TweenService:Create(card, TWEEN_QUICK,
                    {BackgroundColor3 = Color3.fromRGB(60, 55, 25)}):Play()
                task.delay(0.3, function()
                    if card and card.Parent then
                        TweenService:Create(card, TWEEN_QUICK,
                            {BackgroundColor3 = ROW_CLAIMED_BG}):Play()
                    end
                end)
                if _G.UpdateShopHeaderCoins then
                    pcall(_G.UpdateShopHeaderCoins)
                end
            else
                updateAchBtnState(ach.progress, ach.target, false)
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Live achievement progress updates
    ---------------------------------------------------------------------------
    if achievProgressRE then
        trackConn(achievProgressRE.OnClientEvent:Connect(function(achId, newProgress, completed)
            if type(achId) ~= "string" then return end

            -- Full refresh: re-fetch and rebuild
            if achId == "__full_refresh" then
                if getAchievRF then
                    local newData = {}
                    pcall(function() newData = getAchievRF:InvokeServer() end)
                    if type(newData) == "table" then
                        for _, a in ipairs(newData) do
                            achGoals[a.id]   = a.target
                            achClaimed[a.id] = a.claimed
                            local fillBar = achProgressBars[a.id]
                            if fillBar and fillBar.Parent then
                                local p2 = math.clamp(a.progress / a.target, 0, 1)
                                TweenService:Create(fillBar, TWEEN_QUICK,
                                    {Size = UDim2.new(p2, 0, 1, 0)}):Play()
                            end
                            local txt = achProgressTexts[a.id]
                            if txt and txt.Parent then
                                txt.Text = tostring(a.progress) .. "/" .. tostring(a.target)
                            end
                            local claimBtn2 = achClaimButtons[a.id]
                            if claimBtn2 then
                                local bStroke = claimBtn2:FindFirstChildOfClass("UIStroke")
                                if a.claimed then
                                    claimBtn2.Text = "\u{2714} CLAIMED"
                                    claimBtn2.BackgroundColor3 = BTN_CLAIMED
                                    claimBtn2.TextColor3 = GREEN_GLOW
                                    claimBtn2.Active = false
                                    if bStroke then bStroke.Color = GREEN_GLOW; bStroke.Transparency = 0.5 end
                                elseif a.progress >= a.target then
                                    claimBtn2.Text = "\u{2B50} CLAIM"
                                    claimBtn2.BackgroundColor3 = BTN_CLAIM
                                    claimBtn2.TextColor3 = WHITE
                                    claimBtn2.Active = true
                                    if bStroke then bStroke.Color = GREEN_GLOW; bStroke.Transparency = 0.15 end
                                else
                                    claimBtn2.Text = tostring(a.progress) .. "/" .. tostring(a.target)
                                    claimBtn2.BackgroundColor3 = BTN_LOCKED
                                    claimBtn2.TextColor3 = DIM_TEXT
                                    claimBtn2.Active = false
                                    if bStroke then bStroke.Color = BTN_STROKE; bStroke.Transparency = 0.4 end
                                end
                            end
                            -- Update card visuals
                            local cardFrame = achCards[a.id]
                            local cardStroke = achCardStrokes[a.id]
                            if cardFrame and cardFrame.Parent then
                                local accent = cardFrame:FindFirstChild("StateAccent")
                                if a.claimed then
                                    cardFrame.BackgroundColor3 = ROW_CLAIMED_BG
                                    if cardStroke then cardStroke.Color = GREEN_GLOW; cardStroke.Thickness = 1.8; cardStroke.Transparency = 0.3 end
                                    if accent then accent.BackgroundColor3 = GREEN_GLOW; accent.BackgroundTransparency = 0.2 end
                                elseif a.progress >= a.target then
                                    cardFrame.BackgroundColor3 = ROW_CLAIMABLE_BG
                                    if cardStroke then cardStroke.Color = CLAIM_GOLD_GLOW; cardStroke.Thickness = 2; cardStroke.Transparency = 0.15 end
                                    if accent then accent.BackgroundColor3 = CLAIM_GOLD_GLOW; accent.BackgroundTransparency = 0 end
                                else
                                    cardFrame.BackgroundColor3 = ROW_BG
                                    if cardStroke then cardStroke.Color = CARD_STROKE; cardStroke.Thickness = 1.2; cardStroke.Transparency = 0.35 end
                                    if accent then accent.BackgroundColor3 = GOLD; accent.BackgroundTransparency = 0.5 end
                                end
                            end
                        end
                    end
                end
                return
            end

            -- Single achievement update
            newProgress = tonumber(newProgress) or 0
            local goal = achGoals[achId]
            if not goal then return end
            if achClaimed[achId] then return end

            local pct2 = math.clamp(newProgress / goal, 0, 1)

            local fillBar = achProgressBars[achId]
            if fillBar and fillBar.Parent then
                TweenService:Create(fillBar, TWEEN_QUICK,
                    {Size = UDim2.new(pct2, 0, 1, 0)}):Play()
            end

            local txt = achProgressTexts[achId]
            if txt and txt.Parent then
                txt.Text = tostring(math.min(newProgress, goal)) .. "/" .. tostring(goal)
            end

            local claimBtn2 = achClaimButtons[achId]
            if claimBtn2 and claimBtn2.Parent then
                local bStroke = claimBtn2:FindFirstChildOfClass("UIStroke")
                if newProgress >= goal then
                    claimBtn2.Text             = "\u{2B50} CLAIM"
                    claimBtn2.BackgroundColor3 = BTN_CLAIM
                    claimBtn2.TextColor3       = WHITE
                    claimBtn2.Active           = true
                    if bStroke then bStroke.Color = GREEN_GLOW; bStroke.Transparency = 0.15 end
                end
            end

            -- Update card visuals
            local cardFrame = achCards[achId]
            local cardStroke = achCardStrokes[achId]
            if cardFrame and cardFrame.Parent then
                local accent = cardFrame:FindFirstChild("StateAccent")
                if newProgress >= goal then
                    cardFrame.BackgroundColor3 = ROW_CLAIMABLE_BG
                    if cardStroke then cardStroke.Color = CLAIM_GOLD_GLOW; cardStroke.Thickness = 2; cardStroke.Transparency = 0.15 end
                    if accent then accent.BackgroundColor3 = CLAIM_GOLD_GLOW; accent.BackgroundTransparency = 0 end
                end
            end

            -- Show toast notification when an achievement is newly completed
            if completed and _G.ShowAchievementToast then
                pcall(function() _G.ShowAchievementToast(achId) end)
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Activate default tab
    ---------------------------------------------------------------------------
    setActiveTab(preferredTab)

    ---------------------------------------------------------------------------
    -- Live weekly quest progress updates from server
    ---------------------------------------------------------------------------
    if weeklyProgressRE then
        trackConn(weeklyProgressRE.OnClientEvent:Connect(function(questIdx, newProgress)
            questIdx = tonumber(questIdx)
            if not questIdx then return end
            newProgress = tonumber(newProgress) or 0
            local goal = wkGoals[questIdx]
            if not goal then return end
            if wkClaimed[questIdx] then return end

            local pctW2 = math.clamp(newProgress / goal, 0, 1)

            local fillBar = wkProgressBars[questIdx]
            if fillBar and fillBar.Parent then
                TweenService:Create(fillBar, TWEEN_QUICK,
                    {Size = UDim2.new(pctW2, 0, 1, 0)}):Play()
            end

            local txt = wkProgressTexts[questIdx]
            if txt and txt.Parent then
                txt.Text = tostring(math.min(newProgress, goal)) .. "/" .. tostring(goal)
            end

            local claimBtn3 = wkClaimButtons[questIdx]
            if claimBtn3 and claimBtn3.Parent then
                local bStr = claimBtn3:FindFirstChildOfClass("UIStroke")
                if newProgress >= goal then
                    claimBtn3.Text             = "\u{2B50} CLAIM"
                    claimBtn3.BackgroundColor3 = BTN_CLAIM
                    claimBtn3.TextColor3       = WHITE
                    claimBtn3.Active           = true
                    if bStr then bStr.Color = GREEN_GLOW; bStr.Transparency = 0.15 end
                else
                    claimBtn3.Text             = tostring(newProgress) .. "/" .. tostring(goal)
                    claimBtn3.BackgroundColor3 = BTN_LOCKED
                    claimBtn3.TextColor3       = DIM_TEXT
                    claimBtn3.Active           = false
                    if bStr then bStr.Color = BTN_STROKE; bStr.Transparency = 0.4 end
                end
            end

            -- Update card visuals
            local cardFrame2 = wkCards[questIdx]
            local cardStroke2 = wkCardStrokes[questIdx]
            if cardFrame2 and cardFrame2.Parent then
                local accent2 = cardFrame2:FindFirstChild("StateAccent")
                if newProgress >= goal then
                    cardFrame2.BackgroundColor3 = ROW_CLAIMABLE_BG
                    if cardStroke2 then cardStroke2.Color = CLAIM_GOLD_GLOW; cardStroke2.Thickness = 2; cardStroke2.Transparency = 0.15 end
                    if accent2 then accent2.BackgroundColor3 = CLAIM_GOLD_GLOW; accent2.BackgroundTransparency = 0 end
                else
                    cardFrame2.BackgroundColor3 = ROW_BG
                    if cardStroke2 then cardStroke2.Color = CARD_STROKE; cardStroke2.Thickness = 1.2; cardStroke2.Transparency = 0.35 end
                    if accent2 then accent2.BackgroundColor3 = GOLD; accent2.BackgroundTransparency = 0.5 end
                end
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Live daily quest progress updates from server
    ---------------------------------------------------------------------------
    if questProgressRE then
        trackConn(questProgressRE.OnClientEvent:Connect(function(questId, newProgress)
            if type(questId) ~= "string" then return end
            newProgress = tonumber(newProgress) or 0
            local goal = questGoals[questId]
            if not goal then return end
            if questClaimed[questId] then return end

            local pct2 = math.clamp(newProgress / goal, 0, 1)

            local fillBar = progressBars[questId]
            if fillBar and fillBar.Parent then
                TweenService:Create(fillBar, TWEEN_QUICK,
                    {Size = UDim2.new(pct2, 0, 1, 0)}):Play()
            end

            local txt = progressTexts[questId]
            if txt and txt.Parent then
                txt.Text = tostring(math.min(newProgress, goal)) .. "/" .. tostring(goal)
            end

            local claimBtn = claimButtons[questId]
            if claimBtn and claimBtn.Parent then
                local btnStrokeRef = claimBtn:FindFirstChildOfClass("UIStroke")
                if newProgress >= goal then
                    claimBtn.Text             = "\u{2B50} CLAIM"
                    claimBtn.BackgroundColor3 = BTN_CLAIM
                    claimBtn.TextColor3       = WHITE
                    claimBtn.Active           = true
                    if btnStrokeRef then
                        btnStrokeRef.Color = GREEN_GLOW
                        btnStrokeRef.Transparency = 0.15
                    end
                else
                    claimBtn.Text             = tostring(newProgress) .. "/" .. tostring(goal)
                    claimBtn.BackgroundColor3 = BTN_LOCKED
                    claimBtn.TextColor3       = DIM_TEXT
                    claimBtn.Active           = false
                    if btnStrokeRef then
                        btnStrokeRef.Color = BTN_STROKE
                        btnStrokeRef.Transparency = 0.4
                    end
                end
            end

            -- Update card visuals for state change
            local cardFrame = questCards and questCards[questId]
            local cardStroke = questCardStrokes and questCardStrokes[questId]
            if cardFrame and cardFrame.Parent then
                local accent = cardFrame:FindFirstChild("StateAccent")
                if newProgress >= goal then
                    cardFrame.BackgroundColor3 = ROW_CLAIMABLE_BG
                    if cardStroke then
                        cardStroke.Color = CLAIM_GOLD_GLOW
                        cardStroke.Thickness = 2
                        cardStroke.Transparency = 0.15
                    end
                    if accent then
                        accent.BackgroundColor3 = CLAIM_GOLD_GLOW
                        accent.BackgroundTransparency = 0
                    end
                else
                    cardFrame.BackgroundColor3 = ROW_BG
                    if cardStroke then
                        cardStroke.Color = CARD_STROKE
                        cardStroke.Thickness = 1.2
                        cardStroke.Transparency = 0.35
                    end
                    if accent then
                        accent.BackgroundColor3 = GOLD
                        accent.BackgroundTransparency = 0.5
                    end
                end
            end
        end))
    end

    return parent
end

return DailyQuestsUI
