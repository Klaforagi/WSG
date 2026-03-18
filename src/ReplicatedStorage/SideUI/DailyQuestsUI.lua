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
local TextService       = game:GetService("TextService")

local UITheme = require(script.Parent.UITheme)

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
-- Palette (sourced from shared UITheme – Team menu visual language)
--------------------------------------------------------------------------------
local ROW_BG           = UITheme.CARD_BG
local ROW_CLAIMABLE_BG = UITheme.CARD_HIGHLIGHT
local ROW_CLAIMED_BG   = UITheme.CARD_OWNED
local SIDEBAR_BG       = UITheme.SIDEBAR_BG
local TAB_ACTIVE_BG    = UITheme.TAB_ACTIVE
local CARD_STROKE      = UITheme.CARD_STROKE
local GOLD             = UITheme.GOLD
local WHITE            = UITheme.WHITE
local DIM_TEXT         = UITheme.DIM_TEXT
local BAR_BG           = UITheme.BAR_BG
local BAR_FILL         = UITheme.GOLD
local BTN_CLAIM        = UITheme.GREEN_BTN
local BTN_CLAIMED      = UITheme.DISABLED_BG
local BTN_LOCKED       = UITheme.BTN_BG
local BTN_STROKE       = UITheme.BTN_STROKE
local GREEN_GLOW       = UITheme.GREEN_GLOW
local CLAIM_GOLD_GLOW  = UITheme.GOLD_WARM

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEBUG_QUEST_UI = false
local DEBUG_QUEST_SORT = true
local DEBUG_REROLL_TOOLTIP = true

local function debugLog(prefix, message)
    if DEBUG_QUEST_UI then
        print(string.format("[%s] %s", prefix, message))
    end
end

local function getQuestCompletionTarget(quest)
    if type(quest) ~= "table" then
        return 0
    end
    return tonumber(quest.goal) or tonumber(quest.target) or 0
end

local function isQuestCompletedForDisplay(quest)
    if type(quest) ~= "table" then
        return false
    end
    if quest.completed == true then
        return true
    end

    local target = getQuestCompletionTarget(quest)
    local progress = tonumber(quest.progress) or 0
    return target > 0 and progress >= target
end

local function getQuestSortPriority(quest)
    if type(quest) ~= "table" then
        return 4
    end
    if quest.claimed == true then
        return 3
    end
    if isQuestCompletedForDisplay(quest) then
        return 2
    end
    return 1
end

local function getQuestDebugLabel(quest, fallbackIndex)
    if type(quest) ~= "table" then
        return string.format("quest_%d", fallbackIndex)
    end
    return tostring(quest.title or quest.id or quest.index or ("quest_" .. tostring(fallbackIndex)))
end

local function logQuestSortOrder(tabId, phase, entries)
    if not DEBUG_QUEST_SORT then
        return
    end

    local parts = {}
    for _, entry in ipairs(entries) do
        local quest = entry.quest
        table.insert(parts, string.format(
            "%d:%s(priority=%d, claimed=%s, completed=%s)",
            entry.originalIndex,
            getQuestDebugLabel(quest, entry.originalIndex),
            entry.priority,
            tostring(quest and quest.claimed == true),
            tostring(isQuestCompletedForDisplay(quest))
        ))
    end

    print(string.format("[QuestSort] tab=%s phase=%s order=%s", tostring(tabId), tostring(phase), table.concat(parts, " | ")))
end

local function sortQuestsForDisplay(tabId, quests)
    local sortable = {}

    for originalIndex, quest in ipairs(quests) do
        table.insert(sortable, {
            quest = quest,
            originalIndex = originalIndex,
            priority = getQuestSortPriority(quest),
        })
    end

    logQuestSortOrder(tabId, "original", sortable)

    table.sort(sortable, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.originalIndex < b.originalIndex
    end)

    logQuestSortOrder(tabId, "sorted", sortable)

    local sorted = {}
    for _, entry in ipairs(sortable) do
        table.insert(sorted, entry.quest)
        if DEBUG_QUEST_SORT then
            print(string.format(
                "[QuestSort] tab=%s quest=%s priority=%d originalIndex=%d",
                tostring(tabId),
                getQuestDebugLabel(entry.quest, entry.originalIndex),
                entry.priority,
                entry.originalIndex
            ))
        end
    end

    return sorted
end

local function applySortedCardLayoutOrders(tabId, quests, getCardForQuest)
    local sorted = sortQuestsForDisplay(tabId, quests)
    for displayIndex, quest in ipairs(sorted) do
        local card = getCardForQuest(quest)
        if card and card.Parent then
            card.LayoutOrder = 10 + displayIndex
        end
    end
end

local MONTH_ABBR = {
    [1] = "Jan", [2] = "Feb", [3] = "Mar", [4] = "Apr", [5] = "May", [6] = "Jun",
    [7] = "Jul", [8] = "Aug", [9] = "Sep", [10] = "Oct", [11] = "Nov", [12] = "Dec",
}

local function formatAchievedOn(ts)
    local unix = tonumber(ts)
    if not unix or unix <= 0 then
        return nil
    end

    local ok, dateTable = pcall(function()
        return os.date("!*t", math.floor(unix))
    end)
    if not ok or type(dateTable) ~= "table" then
        return nil
    end

    local month = MONTH_ABBR[dateTable.month]
    local day = tonumber(dateTable.day)
    local year = tonumber(dateTable.year)
    if not month or not day or not year then
        return nil
    end

    return string.format("%s %d, %d", month, day, year)
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
local getRerollCooldownsRF

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
    getRerollCooldownsRF = questRemotesFolder:WaitForChild("GetRerollCooldowns", 5)

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
    if rerollDailyRF and rerollWeeklyRF and getRerollCooldownsRF then return end
    if not questRemotesFolder then return end
    if not rerollDailyRF then
        rerollDailyRF = questRemotesFolder:FindFirstChild("RequestRerollDailyQuest")
    end
    if not rerollWeeklyRF then
        rerollWeeklyRF = questRemotesFolder:FindFirstChild("RequestRerollWeeklyQuest")
    end
    if not getRerollCooldownsRF then
        getRerollCooldownsRF = questRemotesFolder:FindFirstChild("GetRerollCooldowns")
    end
end

--------------------------------------------------------------------------------
-- Connection cleanup
--------------------------------------------------------------------------------
local activeConnections = {}
local questsScreenGui = nil    -- screen-level host for quest modals
local activeRerollPopup = nil  -- compatibility alias to current modal layer
local activeRerollLayer = nil
local activeRerollOverlay = nil
local activeRerollModal = nil
local activeRerollHostGui = nil
local previousHostZIndexBehavior = nil
local rerollModalOpen = false
local rerollModalSelection = nil
local rerollTooltipLayer = nil
local rerollTooltipPanel = nil
local rerollTooltipLabel = nil
local hideRerollTooltip = function() end
local activeCountdownThread = nil   -- coroutine handle for live countdown

local function trackConn(conn)
    table.insert(activeConnections, conn)
end

local function cleanupConnections()
    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}
    hideRerollTooltip()
    -- Close any open reroll confirmation popup
    if activeRerollPopup then
        print("[QuestReroll] Popup destroyed/hidden (cleanup)")
        closeRerollPopup("cleanup-connections")
    end
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
-- Reroll constants & helpers  –  Per-row reroll button + confirmation popup
--------------------------------------------------------------------------------
local REROLL_ACCENT  = Color3.fromRGB(170, 110, 255)
local REROLL_BTN_BG  = Color3.fromRGB(80, 55, 120)
local CANCEL_BTN_BG  = Color3.fromRGB(120, 40, 40)
local DISABLED_REROLL_BG = Color3.fromRGB(50, 45, 60)

--------------------------------------------------------------------------------
-- Client-side cooldown cache (mirrors server authoritative cooldowns)
-- Updated on popup open and after successful reroll
--------------------------------------------------------------------------------
local clientCooldowns = { daily = 0, weekly = 0 }   -- os.clock()-based expiry

local function fetchServerCooldowns()
    ensureRerollRemotes()
    if not getRerollCooldownsRF then return end
    local ok, result = pcall(function()
        return getRerollCooldownsRF:InvokeServer()
    end)
    if ok and type(result) == "table" then
        local now = os.clock()
        clientCooldowns.daily  = now + (tonumber(result.daily)  or 0)
        clientCooldowns.weekly = now + (tonumber(result.weekly) or 0)
        print(string.format("[QuestReroll] Cooldowns fetched: daily=%ds weekly=%ds",
            math.max(0, math.ceil(tonumber(result.daily) or 0)),
            math.max(0, math.ceil(tonumber(result.weekly) or 0))))
    end
end

local function getClientCooldownRemaining(category)
    local expiresAt = clientCooldowns[category] or 0
    return math.max(0, expiresAt - os.clock())
end

local function setClientCooldown(category, seconds)
    clientCooldowns[category] = os.clock() + seconds
end

local function getTooltipHostGui()
    if questsScreenGui and questsScreenGui.Parent then
        return questsScreenGui
    end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil
    end
    return playerGui:FindFirstChild("SideUIModal") or playerGui:FindFirstChildOfClass("ScreenGui")
end

local function ensureRerollTooltip()
    local hostGui = getTooltipHostGui()
    if not hostGui then
        return false
    end

    if rerollTooltipLayer and rerollTooltipLayer.Parent ~= hostGui then
        rerollTooltipLayer:Destroy()
        rerollTooltipLayer = nil
        rerollTooltipPanel = nil
        rerollTooltipLabel = nil
    end

    if rerollTooltipLayer and rerollTooltipPanel and rerollTooltipLabel then
        return true
    end

    local layer = Instance.new("Frame")
    layer.Name = "RerollTooltipLayer"
    layer.BackgroundTransparency = 1
    layer.Size = UDim2.new(1, 0, 1, 0)
    layer.Position = UDim2.new(0, 0, 0, 0)
    layer.Active = false
    layer.Visible = false
    layer.ZIndex = 899
    layer.ClipsDescendants = false
    layer.Parent = hostGui

    local panel = Instance.new("Frame")
    panel.Name = "RerollTooltip"
    panel.BackgroundColor3 = Color3.fromRGB(16, 22, 38)
    panel.BackgroundTransparency = 0.12
    panel.BorderSizePixel = 0
    panel.Size = UDim2.new(0, px(170), 0, px(30))
    panel.Position = UDim2.new(0, 0, 0, 0)
    panel.Active = false
    panel.Visible = false
    panel.ZIndex = 900
    panel.Parent = layer

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, px(8))
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = CARD_STROKE
    panelStroke.Thickness = 1.1
    panelStroke.Transparency = 0.2
    panelStroke.Parent = panel

    local panelPad = Instance.new("UIPadding")
    panelPad.PaddingLeft = UDim.new(0, px(10))
    panelPad.PaddingRight = UDim.new(0, px(10))
    panelPad.PaddingTop = UDim.new(0, px(6))
    panelPad.PaddingBottom = UDim.new(0, px(6))
    panelPad.Parent = panel

    local text = Instance.new("TextLabel")
    text.Name = "TooltipText"
    text.BackgroundTransparency = 1
    text.Font = Enum.Font.GothamBold
    text.Text = "Reroll Quest"
    text.TextColor3 = GOLD
    text.TextSize = math.max(11, math.floor(px(12)))
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextYAlignment = Enum.TextYAlignment.Center
    text.Size = UDim2.new(1, 0, 1, 0)
    text.ZIndex = 901
    text.Parent = panel

    rerollTooltipLayer = layer
    rerollTooltipPanel = panel
    rerollTooltipLabel = text
    return true
end

hideRerollTooltip = function()
    if rerollTooltipPanel then
        rerollTooltipPanel.Visible = false
    end
    if rerollTooltipLayer then
        rerollTooltipLayer.Visible = false
    end
end

local function showRerollTooltipForButton(button, tooltipText)
    if not button or not button.Parent then
        return
    end
    if not ensureRerollTooltip() then
        return
    end

    local text = tooltipText and tostring(tooltipText) or "Reroll Quest"
    rerollTooltipLabel.Text = text

    local textSize = TextService:GetTextSize(
        text,
        rerollTooltipLabel.TextSize,
        rerollTooltipLabel.Font,
        Vector2.new(2000, 2000)
    )

    local tooltipW = math.max(px(120), textSize.X + px(20))
    local tooltipH = math.max(px(30), textSize.Y + px(12))

    local layerAbsPos = rerollTooltipLayer.AbsolutePosition
    local layerAbsSize = rerollTooltipLayer.AbsoluteSize
    local btnAbsPos = button.AbsolutePosition
    local btnAbsSize = button.AbsoluteSize
    local margin = px(8)
    local verticalPad = px(6)

    -- Position from the hovered button center in screen space, then convert to tooltip-layer space.
    local screenX = btnAbsPos.X + math.floor((btnAbsSize.X - tooltipW) / 2)
    local screenY = btnAbsPos.Y - tooltipH - verticalPad

    local x = screenX - layerAbsPos.X
    local y = screenY - layerAbsPos.Y

    if x + tooltipW > layerAbsSize.X - margin then
        x = layerAbsSize.X - tooltipW - margin
    end
    if x < margin then
        x = margin
    end

    -- Prefer above the button; if there isn't room, flip below while preserving bounds.
    if y < margin then
        y = (btnAbsPos.Y + btnAbsSize.Y + verticalPad) - layerAbsPos.Y
    end
    if y + tooltipH > layerAbsSize.Y - margin then
        y = layerAbsSize.Y - tooltipH - margin
    end
    if y < margin then
        y = margin
    end

    rerollTooltipPanel.Size = UDim2.new(0, tooltipW, 0, tooltipH)
    rerollTooltipPanel.Position = UDim2.new(0, x, 0, y)
    rerollTooltipLayer.Visible = true
    rerollTooltipPanel.Visible = true

    if DEBUG_REROLL_TOOLTIP then
        print(string.format("[QuestRerollTooltip] button AbsolutePosition=(%d, %d)", btnAbsPos.X, btnAbsPos.Y))
        print(string.format("[QuestRerollTooltip] button AbsoluteSize=(%d, %d)", btnAbsSize.X, btnAbsSize.Y))
        print(string.format("[QuestRerollTooltip] tooltip parent=%s", tostring(rerollTooltipPanel.Parent and rerollTooltipPanel.Parent:GetFullName() or "nil")))
        print(string.format("[QuestRerollTooltip] positioned from button coords (not mouse)"))
        print(string.format("[QuestRerollTooltip] tooltip final Position=%s", tostring(rerollTooltipPanel.Position)))
        print(string.format("[QuestRerollTooltip] tooltip AbsolutePosition=(%d, %d)", rerollTooltipPanel.AbsolutePosition.X, rerollTooltipPanel.AbsolutePosition.Y))
    end
end

local function destroyAllRerollModalArtifacts(reason)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    local staleNames = {
        RerollConfirmLayer = true,
        RerollConfirmOverlay = true,
    }

    for _, inst in ipairs(playerGui:GetDescendants()) do
        if staleNames[inst.Name] and inst:IsA("GuiObject") then
            print(string.format("[QuestReroll] Destroying stale modal artifact (%s): %s", tostring(reason or "unknown"), inst:GetFullName()))
            pcall(function()
                inst.Visible = false
                if inst:IsA("TextButton") or inst:IsA("ImageButton") then
                    inst.Active = false
                end
                inst:Destroy()
            end)
        end
    end
end

local function closeRerollPopup(reason)
    print(string.format("[QuestReroll] CloseRerollPopup called (%s)", tostring(reason or "unspecified")))
    hideRerollTooltip()
    if activeRerollOverlay then
        print(string.format("[QuestReroll] Overlay before cleanup | visible=%s | active=%s", tostring(activeRerollOverlay.Visible), tostring(activeRerollOverlay.Active)))
    end
    if activeRerollModal then
        print(string.format("[QuestReroll] Popup before cleanup | visible=%s", tostring(activeRerollModal.Visible)))
    end

    pcall(function()
        if activeRerollOverlay then
            activeRerollOverlay.Active = false
            activeRerollOverlay.Visible = false
            print("[QuestReroll] Overlay hidden and input capture disabled")
        end
        if activeRerollModal then
            activeRerollModal.Visible = false
            print("[QuestReroll] Popup hidden")
        end
        if activeRerollLayer then
            activeRerollLayer.Visible = false
            activeRerollLayer:Destroy()
            print("[QuestReroll] Modal layer destroyed")
        elseif activeRerollPopup then
            activeRerollPopup:Destroy()
            print("[QuestReroll] Popup container destroyed")
        end
    end)

    if activeRerollHostGui and previousHostZIndexBehavior then
        pcall(function()
            activeRerollHostGui.ZIndexBehavior = previousHostZIndexBehavior
        end)
    end

    activeRerollPopup = nil
    activeRerollLayer = nil
    activeRerollOverlay = nil
    activeRerollModal = nil
    activeRerollHostGui = nil
    previousHostZIndexBehavior = nil
    rerollModalOpen = false
    rerollModalSelection = nil
    print("[QuestReroll] Modal state reset")

    destroyAllRerollModalArtifacts(reason or "close")
end

local function resolveModalHostGui()
    if questsScreenGui and questsScreenGui.Parent then
        return questsScreenGui
    end
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil
    end
    return playerGui:FindFirstChild("SideUIModal") or playerGui:FindFirstChildOfClass("ScreenGui")
end

-- Read reroll cost from BoostConfig (fallback 20)
local function getRerollCost()
    local cost = 20
    local conf = getBoostConfigQUI()
    if conf and conf.GetById then
        local def = conf.GetById("quest_reroll")
        if def then cost = def.PriceCoins end
    end
    return cost
end

--------------------------------------------------------------------------------
-- submitReroll  –  Fire the appropriate remote for daily/weekly reroll
--------------------------------------------------------------------------------
local function submitReroll(tabId, serverIdx)
    ensureRerollRemotes()
    local remote = tabId == "daily" and rerollDailyRF or rerollWeeklyRF
    local remoteName = tabId == "daily" and "RequestRerollDailyQuest" or "RequestRerollWeeklyQuest"
    if not remote then
        warn(string.format("[QuestReroll] %s is nil – remote not found", remoteName))
        return false, "Remote missing"
    end
    print(string.format("[QuestReroll] Sending reroll request: %s quest index %d", tabId, serverIdx))
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

--------------------------------------------------------------------------------
-- showRerollConfirmation  –  Modal popup with multiple visual states
-- tabId: "daily" | "weekly"
-- serverIdx: the 1-based quest index to reroll
-- questName: display name of the quest being rerolled
-- popupState: "ready" | "cooldown" | "completedBlocked" | "claimedBlocked"
-- onConfirm: function(success, msg) called after server response
--------------------------------------------------------------------------------
local function showRerollConfirmation(tabId, serverIdx, questName, popupState, onConfirm)
    -- Close any existing popup first
    closeRerollPopup("before-open")

    popupState = popupState or "ready"
    print(string.format("[QuestReroll] Opening popup state=%s for %s quest index %d (%s)", popupState, tabId, serverIdx, questName))

    local rerollCost = getRerollCost()
    local hostGui = resolveModalHostGui()
    if not hostGui then
        warn("[QuestReroll] Unable to resolve modal host ScreenGui")
        return
    end

    -- Dedicated modal layer under root ScreenGui (never under scrolling/card containers)
    local modalLayer = Instance.new("Frame")
    modalLayer.Name = "RerollConfirmLayer"
    modalLayer.BackgroundTransparency = 1
    modalLayer.Size = UDim2.new(1, 0, 1, 0)
    modalLayer.Position = UDim2.new(0, 0, 0, 0)
    modalLayer.ClipsDescendants = false
    modalLayer.ZIndex = 900
    modalLayer.Parent = hostGui
    activeRerollPopup = modalLayer
    activeRerollLayer = modalLayer
    activeRerollHostGui = hostGui
    rerollModalOpen = true
    rerollModalSelection = {
        tabId = tabId,
        serverIdx = serverIdx,
        questName = questName,
    }
    print(string.format("[QuestReroll] Overlay created | parent=%s", modalLayer.Parent:GetFullName()))

    -- Ensure child z-index values are honored globally
    pcall(function()
        previousHostZIndexBehavior = hostGui.ZIndexBehavior
        hostGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    end)

    -- Dimmed background
    local dimBg = Instance.new("TextButton")
    dimBg.Name = "DimBg"
    dimBg.Size = UDim2.new(1, 0, 1, 0)
    dimBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dimBg.BackgroundTransparency = 0.55
    dimBg.BorderSizePixel = 0
    dimBg.Text = ""
    dimBg.AutoButtonColor = false
    dimBg.ZIndex = 901
    dimBg.Parent = modalLayer
    activeRerollOverlay = dimBg
    print(string.format("[QuestReroll] Overlay shown | parent=%s | zindex=%d", dimBg.Parent:GetFullName(), dimBg.ZIndex))

    -- Modal card (slightly larger to accommodate status text)
    local modalW, modalH = px(440), px(340)
    local modal = Instance.new("Frame")
    modal.Name = "RerollModal"
    modal.BackgroundColor3 = Color3.fromRGB(18, 16, 28)
    modal.Size = UDim2.new(0, modalW, 0, modalH)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Position = UDim2.new(0.5, 0, 0.5, 0)
    modal.BorderSizePixel = 0
    modal.Visible = true
    modal.ZIndex = 910
    modal.Parent = modalLayer
    activeRerollModal = modal
    print(string.format("[QuestReroll] Popup frame created | parent=%s", modal.Parent:GetFullName()))
    print(string.format("[QuestReroll] Popup size=%s | position=%s | visible=%s | zindex=%d | overlayZ=%d",
        tostring(modal.Size), tostring(modal.Position), tostring(modal.Visible), modal.ZIndex, dimBg.ZIndex))

    modal.AncestryChanged:Connect(function(_, newParent)
        if newParent == nil then
            print("[QuestReroll] Popup destroyed/hidden (ancestry removed)")
            rerollModalOpen = false
            rerollModalSelection = nil
            if activeCountdownThread then
                pcall(function() task.cancel(activeCountdownThread) end)
                activeCountdownThread = nil
            end
            print("[QuestReroll] Modal state reset (ancestry removed)")
        end
    end)

    local modalCr = Instance.new("UICorner")
    modalCr.CornerRadius = UDim.new(0, px(16))
    modalCr.Parent = modal

    local modalStr = Instance.new("UIStroke")
    modalStr.Color = REROLL_ACCENT
    modalStr.Thickness = 1.8
    modalStr.Transparency = 0.3
    modalStr.Parent = modal

    local modalPad = Instance.new("UIPadding")
    modalPad.PaddingLeft   = UDim.new(0, px(24))
    modalPad.PaddingRight  = UDim.new(0, px(24))
    modalPad.PaddingTop    = UDim.new(0, px(22))
    modalPad.PaddingBottom = UDim.new(0, px(20))
    modalPad.Parent = modal

    -- Title
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "ModalTitle"
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.Text = "Reroll Quest?"
    titleLbl.TextColor3 = REROLL_ACCENT
    titleLbl.TextSize = math.max(18, math.floor(px(22)))
    titleLbl.TextXAlignment = Enum.TextXAlignment.Center
    titleLbl.Size = UDim2.new(1, 0, 0, px(30))
    titleLbl.Position = UDim2.new(0, 0, 0, 0)
    titleLbl.ZIndex = 911
    titleLbl.Parent = modal

    -- Quest name
    local questLbl = Instance.new("TextLabel")
    questLbl.Name = "QuestName"
    questLbl.BackgroundTransparency = 1
    questLbl.Font = Enum.Font.GothamBold
    questLbl.Text = questName
    questLbl.TextColor3 = WHITE
    questLbl.TextSize = math.max(15, math.floor(px(18)))
    questLbl.TextXAlignment = Enum.TextXAlignment.Center
    questLbl.TextTruncate = Enum.TextTruncate.AtEnd
    questLbl.Size = UDim2.new(1, 0, 0, px(28))
    questLbl.Position = UDim2.new(0, 0, 0, px(40))
    questLbl.ZIndex = 911
    questLbl.Parent = modal

    -- Body description (state-dependent)
    local bodyText
    if popupState == "cooldown" then
        bodyText = "Reroll is temporarily unavailable.\nPlease wait for the cooldown to expire."
    elseif popupState == "completedBlocked" then
        bodyText = "This quest is already completed.\nCompleted quests cannot be rerolled."
    elseif popupState == "claimedBlocked" then
        bodyText = "This quest has already been claimed.\nClaimed quests cannot be rerolled."
    else
        bodyText = "This will replace the quest above with a new random quest."
    end

    local bodyLbl = Instance.new("TextLabel")
    bodyLbl.Name = "BodyText"
    bodyLbl.BackgroundTransparency = 1
    bodyLbl.Font = Enum.Font.GothamMedium
    bodyLbl.Text = bodyText
    bodyLbl.TextColor3 = DIM_TEXT
    bodyLbl.TextSize = math.max(13, math.floor(px(15)))
    bodyLbl.TextWrapped = true
    bodyLbl.TextXAlignment = Enum.TextXAlignment.Center
    bodyLbl.Size = UDim2.new(1, 0, 0, px(50))
    bodyLbl.Position = UDim2.new(0, 0, 0, px(76))
    bodyLbl.ZIndex = 911
    bodyLbl.Parent = modal

    -- Cost badge (only shown in ready state)
    local costBadge = Instance.new("Frame")
    costBadge.Name = "CostBadge"
    costBadge.BackgroundColor3 = Color3.fromRGB(36, 33, 18)
    costBadge.BackgroundTransparency = 0.3
    costBadge.Size = UDim2.new(0, px(130), 0, px(34))
    costBadge.AnchorPoint = Vector2.new(0.5, 0)
    costBadge.Position = UDim2.new(0.5, 0, 0, px(136))
    costBadge.ZIndex = 911
    costBadge.Visible = (popupState == "ready")
    costBadge.Parent = modal

    local cbCr = Instance.new("UICorner")
    cbCr.CornerRadius = UDim.new(0, px(10))
    cbCr.Parent = costBadge

    local cbStr = Instance.new("UIStroke")
    cbStr.Color = CLAIM_GOLD_GLOW
    cbStr.Thickness = 1
    cbStr.Transparency = 0.5
    cbStr.Parent = costBadge

    local costLbl = Instance.new("TextLabel")
    costLbl.BackgroundTransparency = 1
    costLbl.Font = Enum.Font.GothamBold
    costLbl.Text = "Cost: " .. tostring(rerollCost)
    costLbl.TextColor3 = GOLD
    costLbl.TextSize = math.max(13, math.floor(px(15)))
    costLbl.TextXAlignment = Enum.TextXAlignment.Center
    costLbl.Size = UDim2.new(1, -px(34), 1, 0)
    costLbl.Position = UDim2.new(0, 0, 0, 0)
    costLbl.ZIndex = 912
    costLbl.Parent = costBadge

    local costCoin = makeCoinIcon(costBadge, px(20))
    costCoin.AnchorPoint = Vector2.new(1, 0.5)
    costCoin.Position = UDim2.new(1, -px(6), 0.5, 0)
    costCoin.ZIndex = 912

    -- Error / status label (above buttons)
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Name = "StatusLbl"
    statusLbl.BackgroundTransparency = 1
    statusLbl.Font = Enum.Font.GothamMedium
    statusLbl.Text = ""
    statusLbl.TextColor3 = Color3.fromRGB(255, 80, 80)
    statusLbl.TextSize = math.max(12, math.floor(px(14)))
    statusLbl.TextXAlignment = Enum.TextXAlignment.Center
    statusLbl.Size = UDim2.new(1, 0, 0, px(22))
    statusLbl.Position = UDim2.new(0, 0, 0, px(178))
    statusLbl.ZIndex = 911
    statusLbl.Parent = modal

    -- Button row
    local btnRowY = px(206)
    local btnW = px(140)
    local btnH = px(42)

    -- Cancel button (always active)
    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Name = "CancelBtn"
    cancelBtn.AutoButtonColor = false
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.Text = "CANCEL"
    cancelBtn.TextColor3 = WHITE
    cancelBtn.TextSize = math.max(14, math.floor(px(16)))
    cancelBtn.BackgroundColor3 = CANCEL_BTN_BG
    cancelBtn.Size = UDim2.new(0, btnW, 0, btnH)
    cancelBtn.AnchorPoint = Vector2.new(1, 0)
    cancelBtn.Position = UDim2.new(0.5, -px(6), 0, btnRowY)
    cancelBtn.ZIndex = 911
    cancelBtn.Parent = modal

    local ccCr = Instance.new("UICorner")
    ccCr.CornerRadius = UDim.new(0, px(12))
    ccCr.Parent = cancelBtn

    local ccStr = Instance.new("UIStroke")
    ccStr.Color = Color3.fromRGB(180, 60, 60)
    ccStr.Thickness = 1.4
    ccStr.Transparency = 0.3
    ccStr.Parent = cancelBtn

    -- Reroll (confirm) button
    local isDisabled = (popupState ~= "ready")
    local confirmBtn = Instance.new("TextButton")
    confirmBtn.Name = "ConfirmBtn"
    confirmBtn.AutoButtonColor = false
    confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.Text = "\u{1F504} REROLL"
    confirmBtn.TextSize = math.max(14, math.floor(px(16)))
    confirmBtn.Size = UDim2.new(0, btnW, 0, btnH)
    confirmBtn.AnchorPoint = Vector2.new(0, 0)
    confirmBtn.Position = UDim2.new(0.5, px(6), 0, btnRowY)
    confirmBtn.ZIndex = 911
    confirmBtn.Parent = modal

    -- Set confirm button appearance based on state
    if isDisabled then
        confirmBtn.BackgroundColor3 = DISABLED_REROLL_BG
        confirmBtn.TextColor3 = DIM_TEXT
        confirmBtn.Active = false
    else
        confirmBtn.BackgroundColor3 = REROLL_BTN_BG
        confirmBtn.TextColor3 = WHITE
        confirmBtn.Active = true
    end

    local cfCr = Instance.new("UICorner")
    cfCr.CornerRadius = UDim.new(0, px(12))
    cfCr.Parent = confirmBtn

    local cfStr = Instance.new("UIStroke")
    if isDisabled then
        cfStr.Color = CARD_STROKE
        cfStr.Transparency = 0.6
    else
        cfStr.Color = REROLL_ACCENT
        cfStr.Transparency = 0.25
    end
    cfStr.Thickness = 1.4
    cfStr.Parent = confirmBtn

    -- Status text line beneath buttons (for cooldown / blocked reason)
    local footerLbl = Instance.new("TextLabel")
    footerLbl.Name = "FooterStatus"
    footerLbl.BackgroundTransparency = 1
    footerLbl.Font = Enum.Font.GothamBold
    footerLbl.TextColor3 = Color3.fromRGB(255, 130, 70)
    footerLbl.TextSize = math.max(12, math.floor(px(14)))
    footerLbl.TextXAlignment = Enum.TextXAlignment.Center
    footerLbl.Size = UDim2.new(1, 0, 0, px(22))
    footerLbl.Position = UDim2.new(0, 0, 0, btnRowY + btnH + px(10))
    footerLbl.ZIndex = 911
    footerLbl.Parent = modal

    -- Set footer text by state
    if popupState == "completedBlocked" then
        footerLbl.Text = "Completed quests cannot be rerolled"
        footerLbl.TextColor3 = Color3.fromRGB(255, 130, 70)
    elseif popupState == "claimedBlocked" then
        footerLbl.Text = "Claimed quests cannot be rerolled"
        footerLbl.TextColor3 = Color3.fromRGB(255, 130, 70)
    elseif popupState == "cooldown" then
        local remaining = math.ceil(getClientCooldownRemaining(tabId))
        footerLbl.Text = string.format("Reroll Cooldown: %ds", remaining)
        footerLbl.TextColor3 = Color3.fromRGB(255, 180, 60)

        -- Live countdown update loop
        activeCountdownThread = task.spawn(function()
            while true do
                task.wait(1)
                if not modal or not modal.Parent then break end
                if not rerollModalOpen then break end
                local rem = math.ceil(getClientCooldownRemaining(tabId))
                if rem <= 0 then
                    -- Cooldown expired while popup is open — upgrade to ready state
                    footerLbl.Text = ""
                    confirmBtn.BackgroundColor3 = REROLL_BTN_BG
                    confirmBtn.TextColor3 = WHITE
                    confirmBtn.Active = true
                    cfStr.Color = REROLL_ACCENT
                    cfStr.Transparency = 0.25
                    bodyLbl.Text = "This will replace the quest above with a new random quest."
                    costBadge.Visible = true
                    statusLbl.Text = ""
                    popupState = "ready"
                    print("[QuestReroll] Cooldown expired while popup open — now ready")
                    break
                end
                footerLbl.Text = string.format("Reroll Cooldown: %ds", rem)
            end
            activeCountdownThread = nil
        end)
    else
        footerLbl.Text = ""
    end

    local inFlight = false

    -- Cancel: close popup
    cancelBtn.MouseButton1Click:Connect(function()
        print("[QuestReroll] Cancel clicked")
        closeRerollPopup("cancel-button")
    end)
    dimBg.MouseButton1Click:Connect(function()
        print("[QuestReroll] Cancel clicked (overlay)")
        closeRerollPopup("overlay-click")
    end)

    -- Hover feedback
    cancelBtn.MouseEnter:Connect(function()
        TweenService:Create(cancelBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(160, 50, 50)}):Play()
    end)
    cancelBtn.MouseLeave:Connect(function()
        TweenService:Create(cancelBtn, TWEEN_QUICK, {BackgroundColor3 = CANCEL_BTN_BG}):Play()
    end)
    confirmBtn.MouseEnter:Connect(function()
        if not inFlight and confirmBtn.Active then
            TweenService:Create(confirmBtn, TWEEN_QUICK, {BackgroundColor3 = REROLL_ACCENT}):Play()
        end
    end)
    confirmBtn.MouseLeave:Connect(function()
        if not inFlight and confirmBtn.Active then
            TweenService:Create(confirmBtn, TWEEN_QUICK, {BackgroundColor3 = REROLL_BTN_BG}):Play()
        end
    end)

    -- Confirm: send reroll (only works in ready state)
    confirmBtn.MouseButton1Click:Connect(function()
        if inFlight then return end
        if not confirmBtn.Active then return end
        print("[QuestReroll] Confirm clicked")
        inFlight = true
        confirmBtn.Text = "..."
        confirmBtn.Active = false
        cancelBtn.Active = false
        statusLbl.Text = ""

        print(string.format("[QuestReroll] Confirm clicked: %s quest index %d", tabId, serverIdx))

        local success, msg = submitReroll(tabId, serverIdx)

        if success then
            print("[QuestReroll] Reroll success; refreshing quest list")
            -- Set client-side cooldown immediately
            local cdDuration = (tabId == "weekly") and 90 or 45
            setClientCooldown(tabId, cdDuration)
            print(string.format("[QuestReroll] Client cooldown set: %s = %ds", tabId, cdDuration))

            closeRerollPopup("confirm-success")
            pcall(function()
                if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
            end)
            if onConfirm then onConfirm(true, msg) end
        else
            print(string.format("[QuestReroll] Reroll failed: %s", tostring(msg)))
            local errText = tostring(msg or "Reroll failed")
            if errText:find("Insufficient") or errText:find("coins") then
                errText = "Not enough coins!"
            elseif errText:find("cooldown") then
                -- Server rejected due to cooldown — refresh cached cooldowns
                fetchServerCooldowns()
                errText = "Reroll on cooldown!"
            end
            statusLbl.Text = errText
            confirmBtn.Text = "\u{1F504} REROLL"
            confirmBtn.Active = true
            cancelBtn.Active = true
            inFlight = false
            closeRerollPopup("confirm-failed")
            if onConfirm then onConfirm(false, msg) end
        end
    end)
end

--------------------------------------------------------------------------------
-- makeRerollButton  –  Small inline reroll icon on each quest card
-- Returns the button instance so caller can update visibility.
-- tabId: "daily" | "weekly"
-- serverIdx: 1-based quest index for the server
-- questTitle: display name of the quest (for confirmation popup)
-- isClaimed: whether the quest is already claimed
-- isComplete: whether quest progress >= goal
-- refreshQuests: function(tabId) to rebuild UI after reroll
--------------------------------------------------------------------------------
local function makeRerollButton(card, tabId, serverIdx, questTitle, isClaimed, isComplete, refreshQuests)
    local rerollState = {
        claimed = isClaimed == true,
        complete = isComplete == true,
    }

    local btnSize = px(36)
    local claimBtnW = px(108)
    local rerollBtn = Instance.new("TextButton")
    rerollBtn.Name = "RerollBtn"
    rerollBtn.AutoButtonColor = false
    rerollBtn.Font = Enum.Font.GothamBold
    rerollBtn.Text = "\u{1F504}"
    rerollBtn.TextSize = math.max(14, math.floor(btnSize * 0.56))
    rerollBtn.TextColor3 = REROLL_ACCENT
    rerollBtn.BackgroundColor3 = Color3.fromRGB(30, 26, 48)
    rerollBtn.Size = UDim2.new(0, btnSize, 0, btnSize)
    rerollBtn.AnchorPoint = Vector2.new(1, 0)
    -- Place to the left of the claim button, vertically aligned with it
    -- Claim button: size px(108) x px(34), at y = px(52) - px(2) = px(50)
    local barYRef = px(52)
    local claimBtnH = px(34)
    rerollBtn.Position = UDim2.new(1, -(claimBtnW + px(12)), 0, barYRef - px(2) + math.floor((claimBtnH - btnSize) / 2))
    rerollBtn.ZIndex = 5
    rerollBtn.Parent = card

    local rbCr = Instance.new("UICorner")
    rbCr.CornerRadius = UDim.new(0, px(10))
    rbCr.Parent = rerollBtn

    local rbStr = Instance.new("UIStroke")
    rbStr.Name = "RerollStroke"
    rbStr.Color = REROLL_ACCENT
    rbStr.Thickness = 1.4
    rbStr.Transparency = 0.4
    rbStr.Parent = rerollBtn

    -- Visual state for the reroll button (dimmed for completed/claimed, normal otherwise)
    local function setRerollVisuals(enabled)
        if enabled then
            rerollBtn.TextColor3 = REROLL_ACCENT
            rerollBtn.BackgroundColor3 = Color3.fromRGB(30, 26, 48)
            rbStr.Color = REROLL_ACCENT
            rbStr.Transparency = 0.4
            rerollBtn.BackgroundTransparency = 0
        else
            rerollBtn.TextColor3 = DIM_TEXT
            rerollBtn.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
            rbStr.Color = CARD_STROKE
            rbStr.Transparency = 0.6
            rerollBtn.BackgroundTransparency = 0.4
        end
    end

    -- Dim the button visually for completed/claimed quests
    setRerollVisuals(not rerollState.claimed and not rerollState.complete)

    -- Button is always Active so clicks are captured for popup state routing
    rerollBtn.Active = true

    local function getTooltipText()
        if rerollState.complete then
            return "Cannot reroll (completed)"
        end
        if rerollState.claimed then
            return "Cannot reroll (claimed)"
        end
        return string.format("Reroll Quest (%d coins)", getRerollCost())
    end

    local function setQuestRerollState(claimed, complete)
        rerollState.claimed = claimed == true
        rerollState.complete = complete == true
        setRerollVisuals(not rerollState.claimed and not rerollState.complete)
    end

    -- Hover
    trackConn(rerollBtn.MouseEnter:Connect(function()
        showRerollTooltipForButton(rerollBtn, getTooltipText())
        if not rerollState.claimed and not rerollState.complete then
            TweenService:Create(rerollBtn, TWEEN_QUICK, {BackgroundColor3 = REROLL_ACCENT, TextColor3 = WHITE}):Play()
            rbStr.Transparency = 0
        end
    end))
    trackConn(rerollBtn.MouseLeave:Connect(function()
        hideRerollTooltip()
        if not rerollState.claimed and not rerollState.complete then
            TweenService:Create(rerollBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(30, 26, 48), TextColor3 = REROLL_ACCENT}):Play()
            rbStr.Transparency = 0.4
        end
    end))

    -- Click: determine popup state and open confirmation popup
    trackConn(rerollBtn.MouseButton1Click:Connect(function()
        hideRerollTooltip()

        -- Determine the popup state
        local popupState = "ready"
        if rerollState.claimed then
            popupState = "claimedBlocked"
            print(string.format("[QuestReroll] Reroll icon clicked: %s quest index %d (%s) — CLAIMED BLOCKED", tabId, serverIdx, questTitle))
        elseif rerollState.complete then
            popupState = "completedBlocked"
            print(string.format("[QuestReroll] Reroll icon clicked: %s quest index %d (%s) — COMPLETED BLOCKED", tabId, serverIdx, questTitle))
        else
            -- Check cooldown
            local cdRemaining = getClientCooldownRemaining(tabId)
            if cdRemaining > 0 then
                popupState = "cooldown"
                print(string.format("[QuestReroll] Reroll icon clicked: %s quest index %d (%s) — COOLDOWN (%ds)", tabId, serverIdx, questTitle, math.ceil(cdRemaining)))
            else
                print(string.format("[QuestReroll] Reroll icon clicked: %s quest index %d (%s) — READY", tabId, serverIdx, questTitle))
            end
        end

        showRerollConfirmation(tabId, serverIdx, questTitle, popupState, function(success, _msg)
            if success and refreshQuests then
                refreshQuests(tabId)
            end
        end)
    end))

    return rerollBtn, setQuestRerollState
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local DailyQuestsUI = {}

function DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, initialTabId)
    if not parent then return nil end

    questsScreenGui = parent:FindFirstAncestorOfClass("ScreenGui")
    if questsScreenGui then
        debugLog("QuestReroll", "Resolved modal host: " .. questsScreenGui:GetFullName())
    end

    local preferredTab = (initialTabId == "weekly" or initialTabId == "achiev") and initialTabId or "daily"

    -- Cleanup from previous open
    cleanupConnections()
    closeRerollPopup("create-rebuild")

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

    -- Fetch reroll cooldown state from server on UI open
    task.spawn(fetchServerCooldowns)

    -- Fetch quest data from server
    local quests = {}
    pcall(function()
        quests = getQuestsRF:InvokeServer()
    end)
    if type(quests) ~= "table" then quests = {} end

    local dailyQuestServerIndexById = {}
    local dailyQuestDataById = {}
    for index, quest in ipairs(quests) do
        dailyQuestServerIndexById[quest.id] = index
        dailyQuestDataById[quest.id] = quest
    end

    ---------------------------------------------------------------------------
    -- Layout constants
    ---------------------------------------------------------------------------
    local TAB_W   = px(160)
    local TAB_GAP = px(10)
    local CARD_H  = px(142)   -- includes space for achievement date line under progress bar
    local HDR_H   = px(66)    -- header + subheader + accent bar

    local function pageHeightForCount(count)
        return HDR_H + math.max(1, count) * CARD_H + px(24)
    end

    local dailyH = pageHeightForCount(#quests)
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

    trackConn(root.AncestryChanged:Connect(function(_, newParent)
        if newParent == nil or not root:IsDescendantOf(game) then
            closeRerollPopup("quests-root-removed")
        end
    end))

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

    local contentPad = Instance.new("UIPadding")
    contentPad.PaddingRight = UDim.new(0, px(6))
    contentPad.Parent = contentArea

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

    -- Parent is the modal ScrollingFrame in SideUI; tune style per active tab.
    local parentScroll = if parent and parent:IsA("ScrollingFrame") then parent else nil
    local defaultScrollThickness = parentScroll and parentScroll.ScrollBarThickness or 0
    local defaultScrollColor = parentScroll and parentScroll.ScrollBarImageColor3 or Color3.new(1, 1, 1)
    local defaultScrollTransparency = parentScroll and parentScroll.ScrollBarImageTransparency or 0

    local function applyAchievementsScrollStyle(isAchievTab)
        if not parentScroll then return end
        if isAchievTab then
            parentScroll.ScrollBarThickness = px(3)
            parentScroll.ScrollBarImageColor3 = GOLD
            parentScroll.ScrollBarImageTransparency = 0.08
            parentScroll.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right
        else
            parentScroll.ScrollBarThickness = defaultScrollThickness
            parentScroll.ScrollBarImageColor3 = defaultScrollColor
            parentScroll.ScrollBarImageTransparency = defaultScrollTransparency
        end
    end

    local function updateRootHeight(minRows)
        local targetHeight = math.max(pageHeightForCount(minRows), px(220))
        if targetHeight <= rootH then return end
        rootH = targetHeight
        root.Size = UDim2.new(1, 0, 0, rootH)
        for _, page in pairs(contentPages) do
            page.Size = UDim2.new(1, 0, 0, rootH)
        end
    end

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

    local function setActiveTab(tabId)
        currentTab = tabId
        hideRerollTooltip()

        -- Close any open reroll confirmation popup when switching tabs
        closeRerollPopup("tab-switch")

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
        applyAchievementsScrollStyle(tabId == "achiev")
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
    local dailyRerollStateUpdaters = {}

    ---------------------------------------------------------------------------
    -- Quest cards (Daily)
    ---------------------------------------------------------------------------
    local questCardStrokes = {}   -- [questId] = UIStroke (for state glow)
    local questCards       = {}   -- [questId] = Frame
    local dailyDisplayQuests = sortQuestsForDisplay("daily", quests)

    for i, quest in ipairs(dailyDisplayQuests) do
        questGoals[quest.id]   = quest.goal
        questClaimed[quest.id] = quest.claimed

        local card = Instance.new("Frame")
        card.Name             = "Quest_" .. quest.id
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, -px(6), 0, px(120))
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
        local btnW2 = px(108)
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
                if dailyQuestDataById[quest.id] then
                    dailyQuestDataById[quest.id].claimed = true
                    dailyQuestDataById[quest.id].progress = quest.goal
                end
                if dailyRerollStateUpdaters[quest.id] then
                    dailyRerollStateUpdaters[quest.id](true, true)
                end
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
                applySortedCardLayoutOrders("daily", quests, function(displayQuest)
                    return questCards[displayQuest.id]
                end)
            else
                updateButtonState(quest.progress, quest.goal, false)
            end
        end))

        -- Inline reroll button for this quest
        local _rerollBtn, setDailyRerollState = makeRerollButton(
            card, "daily", dailyQuestServerIndexById[quest.id] or i, quest.title,
            quest.claimed, quest.progress >= quest.goal,
            function(selectedTab)
                task.defer(function()
                    DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, selectedTab)
                end)
            end
        )
        dailyRerollStateUpdaters[quest.id] = setDailyRerollState
    end



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
    updateRootHeight(#weeklyQuests)

    local weeklyQuestDataByIndex = {}
    for _, weeklyQuest in ipairs(weeklyQuests) do
        local weeklyIndex = tonumber(weeklyQuest.index)
        if weeklyIndex then
            weeklyQuestDataByIndex[weeklyIndex] = weeklyQuest
        end
    end

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
    local weeklyRerollStateUpdaters = {}
    local weeklyDisplayQuests = sortQuestsForDisplay("weekly", weeklyQuests)

    for i, wq in ipairs(weeklyDisplayQuests) do
        local questIdx       = wq.index or i
        wkGoals[questIdx]    = wq.goal
        wkClaimed[questIdx]  = wq.claimed

        local card = Instance.new("Frame")
        card.Name             = "WeeklyQuest_" .. questIdx
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, -px(6), 0, px(120))
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
        local btnW2 = px(108)
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
                if weeklyQuestDataByIndex[questIdx] then
                    weeklyQuestDataByIndex[questIdx].claimed = true
                    weeklyQuestDataByIndex[questIdx].progress = wq.goal
                end
                if weeklyRerollStateUpdaters[questIdx] then
                    weeklyRerollStateUpdaters[questIdx](true, true)
                end
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
                applySortedCardLayoutOrders("weekly", weeklyQuests, function(displayQuest)
                    return wkCards[displayQuest.index]
                end)
            else
                updateWkBtnState(wq.progress, wq.goal, false)
            end
        end))

        -- Inline reroll button for this weekly quest
        local _wkRerollBtn, setWeeklyRerollState = makeRerollButton(
            card, "weekly", questIdx, wq.title,
            wq.claimed, wq.progress >= wq.goal,
            function(selectedTab)
                task.defer(function()
                    DailyQuestsUI.Create(parent, _coinApi, _inventoryApi, selectedTab)
                end)
            end
        )
        weeklyRerollStateUpdaters[questIdx] = setWeeklyRerollState
    end



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
    updateRootHeight(#achievements)

    local achievementDataById = {}
    for _, achievement in ipairs(achievements) do
        achievementDataById[achievement.id] = achievement
    end

    -- Lookup tables for live updates
    local achProgressBars  = {} -- [id] -> fill Frame
    local achProgressTexts = {} -- [id] -> TextLabel
    local achClaimButtons  = {} -- [id] -> TextButton
    local achGoals         = {} -- [id] -> number
    local achClaimed       = {} -- [id] -> bool
    local achCards         = {} -- [id] -> Frame
    local achCardStrokes   = {} -- [id] -> UIStroke
    local achAchievedOnLabels = {} -- [id] -> TextLabel

    if #achievements == 0 then
        makePlaceholder("Loading achievements...", 3, achievPage)
    end

    local achievementDisplayList = sortQuestsForDisplay("achiev", achievements)

    for i, ach in ipairs(achievementDisplayList) do
        achGoals[ach.id]   = ach.target
        achClaimed[ach.id] = ach.claimed

        local card = Instance.new("Frame")
        card.Name             = "Ach_" .. ach.id
        card.BackgroundColor3 = ROW_BG
        card.Size             = UDim2.new(1, -px(6), 0, px(136))
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

        local achievedOnLbl = Instance.new("TextLabel")
        achievedOnLbl.Name                = "AchievedOn"
        achievedOnLbl.BackgroundTransparency = 1
        achievedOnLbl.Font                = Enum.Font.Gotham
        achievedOnLbl.Text                = ""
        achievedOnLbl.TextColor3          = DIM_TEXT
        achievedOnLbl.TextSize            = math.max(10, math.floor(px(11)))
        achievedOnLbl.TextXAlignment      = Enum.TextXAlignment.Left
        achievedOnLbl.TextTransparency    = 0.1
        achievedOnLbl.Visible             = false
        achievedOnLbl.Size                = UDim2.new(0.62, 0, 0, px(14))
        achievedOnLbl.Position            = UDim2.new(0, 0, 0, barY + barH + px(6))
        achievedOnLbl.Parent              = card
        achAchievedOnLabels[ach.id]       = achievedOnLbl

        local function updateAchievedOnLabel(completed, achievedOn)
            local formattedDate = formatAchievedOn(achievedOn)
            if completed and formattedDate then
                achievedOnLbl.Text = "Achieved On: " .. formattedDate
                achievedOnLbl.Visible = true
            else
                achievedOnLbl.Text = ""
                achievedOnLbl.Visible = false
            end
        end

        -- Claim / status button
        local btnW2 = px(108)
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
        updateAchievedOnLabel(ach.completed == true, ach.achievedOn)

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
                if achievementDataById[ach.id] then
                    achievementDataById[ach.id].claimed = true
                    achievementDataById[ach.id].completed = true
                    achievementDataById[ach.id].progress = ach.target
                end
                updateAchBtnState(ach.target, ach.target, true)
                local latest = achievementDataById[ach.id]
                updateAchievedOnLabel(true, latest and latest.achievedOn)
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
                applySortedCardLayoutOrders("achiev", achievements, function(displayAchievement)
                    return achCards[displayAchievement.id]
                end)
            else
                updateAchBtnState(ach.progress, ach.target, false)
            end
        end))
    end

    ---------------------------------------------------------------------------
    -- Live achievement progress updates
    ---------------------------------------------------------------------------
    if achievProgressRE then
        trackConn(achievProgressRE.OnClientEvent:Connect(function(achId, newProgress, completed, achievedOn, claimedFromServer)
            if type(achId) ~= "string" then return end

            -- Full refresh: re-fetch and rebuild
            if achId == "__full_refresh" then
                if getAchievRF then
                    local newData = {}
                    pcall(function() newData = getAchievRF:InvokeServer() end)
                    if type(newData) == "table" then
                        for _, a in ipairs(newData) do
                            local achievementData = achievementDataById[a.id]
                            if achievementData then
                                achievementData.progress = a.progress
                                achievementData.target = a.target
                                achievementData.claimed = a.claimed
                                achievementData.completed = a.completed
                                achievementData.achievedOn = a.achievedOn
                            end
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
                            local achievedOnLabel = achAchievedOnLabels[a.id]
                            if achievedOnLabel and achievedOnLabel.Parent then
                                local achievedDate = formatAchievedOn(a.achievedOn)
                                if a.completed and achievedDate then
                                    achievedOnLabel.Text = "Achieved On: " .. achievedDate
                                    achievedOnLabel.Visible = true
                                else
                                    achievedOnLabel.Text = ""
                                    achievedOnLabel.Visible = false
                                end
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
                        applySortedCardLayoutOrders("achiev", achievements, function(displayAchievement)
                            return achCards[displayAchievement.id]
                        end)
                    end
                end
                return
            end

            -- Single achievement update
            newProgress = tonumber(newProgress) or 0
            local goal = achGoals[achId]
            if not goal then return end
            if achClaimed[achId] then return end

            local achievementData = achievementDataById[achId]
            if achievementData then
                achievementData.progress = math.min(newProgress, goal)
                achievementData.completed = completed == true or achievementData.completed == true or newProgress >= goal
                if achievementData.completed then
                    if achievementData.achievedOn == nil then
                        achievementData.achievedOn = tonumber(achievedOn)
                    end
                else
                    achievementData.achievedOn = nil
                end
                if claimedFromServer ~= nil then
                    achievementData.claimed = claimedFromServer == true
                end
            end

            if claimedFromServer ~= nil then
                achClaimed[achId] = claimedFromServer == true
            end

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

            local achievedOnLabel = achAchievedOnLabels[achId]
            if achievedOnLabel and achievedOnLabel.Parent then
                local localData = achievementDataById[achId]
                local achievedDate = localData and formatAchievedOn(localData.achievedOn)
                local isComplete = (localData and localData.completed == true) or newProgress >= goal
                if isComplete and achievedDate then
                    achievedOnLabel.Text = "Achieved On: " .. achievedDate
                    achievedOnLabel.Visible = true
                else
                    achievedOnLabel.Text = ""
                    achievedOnLabel.Visible = false
                end
            end

            local claimBtn2 = achClaimButtons[achId]
            if claimBtn2 and claimBtn2.Parent then
                local bStroke = claimBtn2:FindFirstChildOfClass("UIStroke")
                if achClaimed[achId] then
                    claimBtn2.Text             = "\u{2714} CLAIMED"
                    claimBtn2.BackgroundColor3 = BTN_CLAIMED
                    claimBtn2.TextColor3       = GREEN_GLOW
                    claimBtn2.Active           = false
                    if bStroke then bStroke.Color = GREEN_GLOW; bStroke.Transparency = 0.5 end
                elseif newProgress >= goal then
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
                if achClaimed[achId] then
                    cardFrame.BackgroundColor3 = ROW_CLAIMED_BG
                    if cardStroke then cardStroke.Color = GREEN_GLOW; cardStroke.Thickness = 1.8; cardStroke.Transparency = 0.3 end
                    if accent then accent.BackgroundColor3 = GREEN_GLOW; accent.BackgroundTransparency = 0.2 end
                elseif newProgress >= goal then
                    cardFrame.BackgroundColor3 = ROW_CLAIMABLE_BG
                    if cardStroke then cardStroke.Color = CLAIM_GOLD_GLOW; cardStroke.Thickness = 2; cardStroke.Transparency = 0.15 end
                    if accent then accent.BackgroundColor3 = CLAIM_GOLD_GLOW; accent.BackgroundTransparency = 0 end
                end
            end

            applySortedCardLayoutOrders("achiev", achievements, function(displayAchievement)
                return achCards[displayAchievement.id]
            end)

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

            local weeklyQuestData = weeklyQuestDataByIndex[questIdx]
            if weeklyQuestData then
                weeklyQuestData.progress = math.min(newProgress, goal)
            end
            if weeklyRerollStateUpdaters[questIdx] then
                weeklyRerollStateUpdaters[questIdx](false, newProgress >= goal)
            end

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

            applySortedCardLayoutOrders("weekly", weeklyQuests, function(displayQuest)
                return wkCards[displayQuest.index]
            end)
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

            local questData = dailyQuestDataById[questId]
            if questData then
                questData.progress = math.min(newProgress, goal)
            end
            if dailyRerollStateUpdaters[questId] then
                dailyRerollStateUpdaters[questId](false, newProgress >= goal)
            end

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

            applySortedCardLayoutOrders("daily", quests, function(displayQuest)
                return questCards[displayQuest.id]
            end)
        end))
    end

    return parent
end

return DailyQuestsUI
