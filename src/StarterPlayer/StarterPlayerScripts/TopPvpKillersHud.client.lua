-- TopPvpKillersHud.client.lua
-- Top match killers HUD with animated reordering, responsive sizing, styled frames.
-- Only players with kills > 0 are shown.  Hidden when nobody has any kills.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TopHudStack = require(ReplicatedStorage:WaitForChild("TopHudStack"))
local AlertBannerStyle = require(ReplicatedStorage:WaitForChild("AlertBannerStyle"))

------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------
local MAX_SLOTS = 5
-- Temporary: set false for player-only rankings AND fire-icon streaks.
local INCLUDE_MOB_KILLS = true
local PORTRAIT_TYPE = Enum.ThumbnailType.HeadShot
local PORTRAIT_SIZE = Enum.ThumbnailSize.Size100x100
local SLOT_GAP = TopHudStack.KillersSlotGap
local TWEEN_MOVE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local TEAM_FILL = {
    Red  = AlertBannerStyle.BarbariansColor,
    Blue = AlertBannerStyle.KnightsColor,
}
local DEFAULT_FILL = Color3.fromRGB(90, 90, 105)
local STREAK_MIN = 3
local SLOT_BG_TRANSPARENCY = 0.72

local function getTeamFill(player)
    local teamName = player and player.Team and player.Team.Name
    return TEAM_FILL[teamName] or DEFAULT_FILL
end

local overlayKills = {}
local overlayStreak = {}

local function getPlayerKills(player)
    local attr = tonumber(player and player:GetAttribute("PlayerKills")) or 0
    local over = overlayKills[player.UserId]
    if over ~= nil then
        if attr >= over then
            overlayKills[player.UserId] = nil
            return attr
        end
        return over
    end
    return attr
end

local function getKillStreak(player)
    if INCLUDE_MOB_KILLS then
        -- KillFeed's streak overlay is PvP-only. Use the server's combined
        -- counter, which resets on death and at the start of each match.
        return tonumber(player:GetAttribute("CombinedKillStreak")) or 0
    end
    local attr = tonumber(player and player:GetAttribute("KillStreak")) or 0
    local over = overlayStreak[player.UserId]
    if over ~= nil then
        if attr == over then
            overlayStreak[player.UserId] = nil
        end
        return over
    end
    return attr
end

local function getRankingKills(player)
    local mobKills = INCLUDE_MOB_KILLS and (tonumber(player:GetAttribute("MobKills")) or 0) or 0
    -- The kill-feed overlay contains PvP kills only; add mob kills separately
    -- so a later player kill cannot overwrite the combined total.
    return getPlayerKills(player) + mobKills
end

------------------------------------------------------------------------
-- ScreenGui + Root container (top-center, invisible background)
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TopPvpKillersHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = PlayerGui

local rootFrame = Instance.new("Frame")
rootFrame.Name = "Root"
rootFrame.BackgroundTransparency = 1
rootFrame.AnchorPoint = Vector2.new(0.5, 0)
rootFrame.Position = TopHudStack.GetKillersPosition()
rootFrame.Size = UDim2.new(0.05, 0, 0.1, 0)
rootFrame.Visible = false -- hidden until someone has kills
rootFrame.Parent = screenGui

local function placeRoot()
	rootFrame.Position = TopHudStack.GetKillersPosition()
	TopHudStack.NotifyLayoutChanged()
end

------------------------------------------------------------------------
-- Responsive sizing helpers
------------------------------------------------------------------------
local function computeSlotPx()
    return TopHudStack.GetKillersSlotPx()
end

local function updateRootSize(slotPx, visibleCount)
    local count = math.max(visibleCount, 1)
    local totalW = count * slotPx + (count - 1) * SLOT_GAP
    rootFrame.Size = UDim2.new(0, totalW, 0, slotPx)
end

------------------------------------------------------------------------
-- Build slot UI elements (all start hidden — NO flash of empty boxes)
------------------------------------------------------------------------
local slots = {}
for i = 1, MAX_SLOTS do
    local slot = Instance.new("Frame")
    slot.Name = "Slot" .. i
    slot.Size = UDim2.new(0, 56, 0, 56)
    slot.BackgroundColor3 = DEFAULT_FILL
    slot.BackgroundTransparency = SLOT_BG_TRANSPARENCY
    slot.BorderSizePixel = 0
    slot.AnchorPoint = Vector2.new(0, 0)
    slot.ClipsDescendants = false
    slot.Visible = false
    slot.Parent = rootFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = slot

    local stroke = Instance.new("UIStroke")
    stroke.Color = DEFAULT_FILL
    stroke.Thickness = 1.4
    stroke.Transparency = 0.35
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = slot

    local portrait = Instance.new("ImageLabel")
    portrait.Name = "Portrait"
    portrait.Size = UDim2.fromScale(1, 1)
    portrait.BackgroundTransparency = 1
    portrait.BorderSizePixel = 0
    portrait.ScaleType = Enum.ScaleType.Crop
    portrait.Image = ""
    portrait.ZIndex = 1
    portrait.Parent = slot

    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 8)
    pCorner.Parent = portrait

    local wash = Instance.new("Frame")
    wash.Name = "TeamWash"
    wash.Size = UDim2.fromScale(1, 1)
    wash.BackgroundColor3 = DEFAULT_FILL
    wash.BackgroundTransparency = 0
    wash.BorderSizePixel = 0
    wash.ZIndex = 2
    wash.Parent = slot
    local washCorner = Instance.new("UICorner")
    washCorner.CornerRadius = UDim.new(0, 8)
    washCorner.Parent = wash
    local washGrad = Instance.new("UIGradient")
    washGrad.Rotation = 90
    washGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.42, 0.88),
        NumberSequenceKeypoint.new(1, 0.28),
    })
    washGrad.Parent = wash

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "Count"
    countLabel.AnchorPoint = Vector2.new(1, 1)
    countLabel.Position = UDim2.new(1, -2, 1, 1)
    countLabel.Size = UDim2.fromOffset(28, 22)
    countLabel.BackgroundTransparency = 1
    countLabel.Font = AlertBannerStyle.Font
    countLabel.Text = ""
    countLabel.TextColor3 = AlertBannerStyle.TextColor
    countLabel.TextXAlignment = Enum.TextXAlignment.Right
    countLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    countLabel.ZIndex = 5
    countLabel.Parent = slot
    AlertBannerStyle.ApplyTextStroke(countLabel)

    local streakFrame = Instance.new("Frame")
    streakFrame.Name = "Streak"
    streakFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    streakFrame.Position = UDim2.new(0, 14, 1, -10)
    streakFrame.Size = UDim2.fromOffset(32, 32)
    streakFrame.BackgroundTransparency = 1
    streakFrame.ZIndex = 3
    streakFrame.Visible = false
    streakFrame.Parent = slot

    local fireLabel = Instance.new("TextLabel")
    fireLabel.Name = "Fire"
    fireLabel.Size = UDim2.fromScale(1, 1)
    fireLabel.BackgroundTransparency = 1
    fireLabel.Font = Enum.Font.GothamBold
    fireLabel.Text = "\u{1F525}"
    fireLabel.TextScaled = true
    fireLabel.TextXAlignment = Enum.TextXAlignment.Center
    fireLabel.TextYAlignment = Enum.TextYAlignment.Center
    fireLabel.ZIndex = 3
    fireLabel.Parent = streakFrame
    local fireStroke = Instance.new("UIStroke")
    fireStroke.Color = Color3.fromRGB(0, 0, 0)
    fireStroke.Thickness = 2.4
    fireStroke.Transparency = 0.15
    fireStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    fireStroke.Parent = fireLabel
    fireLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    fireLabel.TextStrokeTransparency = 0.2

    local streakLabel = Instance.new("TextLabel")
    streakLabel.Name = "StreakCount"
    streakLabel.AnchorPoint = Vector2.new(0, 1)
    streakLabel.Position = UDim2.new(0, 2, 1, 1)
    streakLabel.Size = UDim2.fromOffset(28, 22)
    streakLabel.BackgroundTransparency = 1
    streakLabel.Font = AlertBannerStyle.Font
    streakLabel.Text = ""
    streakLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    streakLabel.TextXAlignment = Enum.TextXAlignment.Left
    streakLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    streakLabel.ZIndex = 5
    streakLabel.Visible = false
    streakLabel.Parent = slot
    AlertBannerStyle.ApplyTextStroke(streakLabel)

    slots[i] = {
        frame = slot,
        portrait = portrait,
        wash = wash,
        countLabel = countLabel,
        streakFrame = streakFrame,
        streakLabel = streakLabel,
        fireLabel = fireLabel,
        stroke = stroke,
    }
end

local function applySizeToSlot(s, px)
    s.frame.Size = UDim2.fromOffset(px, px)
    s.portrait.Size = UDim2.fromScale(1, 1)
    s.portrait.Position = UDim2.fromScale(0, 0)
    local killSize = math.max(14, math.floor(px * 0.34))
    local countW = math.floor(px * 0.55)
    local countH = math.floor(px * 0.4)
    s.countLabel.TextSize = killSize
    s.countLabel.Size = UDim2.fromOffset(countW, countH)
    s.countLabel.Position = UDim2.new(1, -2, 1, 1)
    s.streakLabel.TextSize = killSize
    s.streakLabel.Size = UDim2.fromOffset(countW, countH)
    s.streakLabel.Position = UDim2.new(0, 2, 1, 1)
    local firePx = math.max(30, math.floor(px * 0.58))
    s.streakFrame.Size = UDim2.fromOffset(firePx, firePx)
    local digitCenterX = 2 + math.floor(killSize * 0.38)
    local digitCenterY = 1 - math.floor(killSize * 0.42) - 6
    s.streakFrame.Position = UDim2.new(0, digitCenterX, 1, digitCenterY)
end

local function applyTeamLook(s, player)
    local color = getTeamFill(player)
    s.frame.BackgroundColor3 = color
    s.wash.BackgroundColor3 = color
    s.stroke.Color = color
end

local function applyStreak(s, streak)
    if streak >= STREAK_MIN then
        s.streakFrame.Visible = true
        s.streakLabel.Visible = true
        s.streakLabel.Text = tostring(streak)
    else
        s.streakFrame.Visible = false
        s.streakLabel.Visible = false
        s.streakLabel.Text = ""
    end
end

------------------------------------------------------------------------
-- Thumbnail cache
------------------------------------------------------------------------
local thumbnailCache = {}

local function getThumbnail(userId)
    if thumbnailCache[userId] then return thumbnailCache[userId] end
    local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId, PORTRAIT_TYPE, PORTRAIT_SIZE)
    if ok and url then
        thumbnailCache[userId] = url
        return url
    end
    return ""
end

------------------------------------------------------------------------
-- Slot-pool tracking  (userId ↔ slot index)
------------------------------------------------------------------------
local usedSlots = {}   -- [userId] = slotIndex
local slotOwner = {}   -- [slotIndex] = userId

local function findFreeSlot()
    for i = 1, MAX_SLOTS do
        if not slotOwner[i] then return i end
    end
    return nil
end

------------------------------------------------------------------------
-- Main HUD update — animated reorder, fade in/out, zero-kill filter
------------------------------------------------------------------------
local function updateHud()
    local slotPx = computeSlotPx()

    -- 1) Build sorted list of players with kills > 0
    local entries = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local k = getRankingKills(p)
        if k > 0 then
            table.insert(entries, { player = p, kills = k, userId = p.UserId })
        end
    end

    -- 2) If nobody has kills, fade everything out and hide
    if #entries == 0 then
        local toRemove = {}
        for uid, si in pairs(usedSlots) do
            table.insert(toRemove, { uid = uid, si = si })
        end
        for _, r in ipairs(toRemove) do
            local s = slots[r.si]
            local idx = r.si
            local tw = TweenService:Create(s.frame, TWEEN_FADE, { BackgroundTransparency = 1 })
            tw:Play()
            tw.Completed:Connect(function()
                slots[idx].frame.Visible = false
                slots[idx].frame.BackgroundTransparency = SLOT_BG_TRANSPARENCY
            end)
            slotOwner[r.si] = nil
            usedSlots[r.uid] = nil
        end
        rootFrame.Visible = false
        return
    end

    -- 3) Sort: descending kills, tie-break ascending UserId
    table.sort(entries, function(a, b)
        if a.kills == b.kills then return a.userId < b.userId end
        return a.kills > b.kills
    end)

    local visibleCount = math.min(#entries, MAX_SLOTS)

    -- 4) Resize root container, park it under the scoreboard, and show it
    updateRootSize(slotPx, visibleCount)
    placeRoot()
    rootFrame.Visible = true

    -- 5) Build set of userIds that SHOULD be visible
    local newSet = {}
    for i = 1, visibleCount do
        newSet[entries[i].userId] = true
    end

    -- 6) Remove slots for players no longer in the list (collect first to avoid pairs-mutation)
    local toRemove = {}
    for uid, si in pairs(usedSlots) do
        if not newSet[uid] then
            table.insert(toRemove, { uid = uid, si = si })
        end
    end
    for _, r in ipairs(toRemove) do
        local s = slots[r.si]
        local idx = r.si
        local tw = TweenService:Create(s.frame, TWEEN_FADE, { BackgroundTransparency = 1 })
        tw:Play()
        tw.Completed:Connect(function()
            slots[idx].frame.Visible = false
            slots[idx].frame.BackgroundTransparency = 0.2
        end)
        slotOwner[r.si] = nil
        usedSlots[r.uid] = nil
    end

    -- 7) Assign / move slots
    for i = 1, visibleCount do
        local entry = entries[i]
        local uid = entry.userId
        local targetPos = UDim2.new(0, (i - 1) * (slotPx + SLOT_GAP), 0, 0)
        local si = usedSlots[uid]

        if si then
            -- Player already owns a slot → update data and tween to new position
            local s = slots[si]
            applySizeToSlot(s, slotPx)
            applyTeamLook(s, entry.player)
            applyStreak(s, getKillStreak(entry.player))
            s.countLabel.Text = tostring(entry.kills)
            TweenService:Create(s.frame, TWEEN_MOVE, { Position = targetPos }):Play()
        else
            -- New player — grab a free slot, place at target, fade in
            si = findFreeSlot()
            if not si then continue end
            usedSlots[uid] = si
            slotOwner[si] = uid

            local s = slots[si]
            applySizeToSlot(s, slotPx)
            applyTeamLook(s, entry.player)
            applyStreak(s, getKillStreak(entry.player))
            s.portrait.Image = getThumbnail(uid)
            s.countLabel.Text = tostring(entry.kills)

            s.frame.Position = targetPos
            s.frame.BackgroundTransparency = 1
            s.frame.Visible = true
            TweenService:Create(s.frame, TWEEN_FADE, { BackgroundTransparency = SLOT_BG_TRANSPARENCY }):Play()
        end
    end
end

------------------------------------------------------------------------
-- Watch match kill counters per player (both reset through StatService).
------------------------------------------------------------------------
local playerConns = {}

local function unwatchPlayer(player)
    local conns = playerConns[player]
    if not conns then
        return
    end
    for _, conn in ipairs(conns) do
        conn:Disconnect()
    end
    playerConns[player] = nil
end

local function watchPlayer(player)
    unwatchPlayer(player)
    local conns = {}
    table.insert(conns, player:GetAttributeChangedSignal("PlayerKills"):Connect(updateHud))
    if INCLUDE_MOB_KILLS then
        table.insert(conns, player:GetAttributeChangedSignal("MobKills"):Connect(updateHud))
        table.insert(conns, player:GetAttributeChangedSignal("CombinedKillStreak"):Connect(updateHud))
    end
    table.insert(conns, player:GetAttributeChangedSignal("KillStreak"):Connect(updateHud))
    table.insert(conns, player:GetPropertyChangedSignal("Team"):Connect(updateHud))
    playerConns[player] = conns
    updateHud()
end

Players.PlayerAdded:Connect(function(player)
    task.defer(function()
        watchPlayer(player)
        updateHud()
    end)
end)
Players.PlayerRemoving:Connect(function(player)
    unwatchPlayer(player)
    thumbnailCache[player.UserId] = nil
    overlayKills[player.UserId] = nil
    overlayStreak[player.UserId] = nil
    updateHud()
end)

local killFeedEvent = ReplicatedStorage:FindFirstChild("KillFeed") or ReplicatedStorage:WaitForChild("KillFeed", 10)
if killFeedEvent and killFeedEvent:IsA("RemoteEvent") then
    killFeedEvent.OnClientEvent:Connect(function(_killerName, _victimName, _coins, killerUserId, kills, streak, victimUserId)
        if type(killerUserId) == "number" then
            if type(kills) == "number" then
                overlayKills[killerUserId] = kills
            end
            if type(streak) == "number" then
                overlayStreak[killerUserId] = streak
            end
        end
        if type(victimUserId) == "number" then
            overlayStreak[victimUserId] = 0
        end
        updateHud()
    end)
end

-- Watch all players currently in the game (blocking so we pick up their stats)
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(watchPlayer, p)
end

-- Recompute on viewport change
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        updateHud()
        placeRoot()
    end)
end

local function hookScoreboard(root)
    if not root or root:GetAttribute("TopHudStackHooked") then
        return
    end
    root:SetAttribute("TopHudStackHooked", true)
    root:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeRoot)
    root:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeRoot)
    root:GetPropertyChangedSignal("Visible"):Connect(placeRoot)
    placeRoot()
end

local function watchMatchHud(hud)
    if not hud then
        return
    end
    hookScoreboard(hud:FindFirstChild("ScoreboardRoot"))
    hud.ChildAdded:Connect(function(child)
        if child.Name == "ScoreboardRoot" then
            hookScoreboard(child)
        end
    end)
end

local existingHud = PlayerGui:FindFirstChild("MatchHUD")
if existingHud then
    watchMatchHud(existingHud)
end
PlayerGui.ChildAdded:Connect(function(child)
    if child.Name == "MatchHUD" then
        watchMatchHud(child)
    end
end)

-- Initial draw (after a short yield so leaderstats can replicate)
task.defer(function()
    task.wait(1)
    updateHud()
end)

-- Periodic safety refresh: catches any missed replication or late leaderstats
task.spawn(function()
    while true do
        task.wait(3)
        -- re-watch any player we haven't connected to yet
        for _, p in ipairs(Players:GetPlayers()) do
            if not playerConns[p] then
                task.spawn(watchPlayer, p)
            end
        end
        updateHud()
    end
end)
