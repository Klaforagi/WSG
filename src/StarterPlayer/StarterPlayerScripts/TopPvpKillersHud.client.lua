-- TopPvpKillersHud.client.lua
-- Top PvP killers HUD with animated reordering, responsive sizing, styled frames.
-- Only players with kills > 0 are shown.  Hidden when nobody has any kills.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------
local MAX_SLOTS = 5
local PORTRAIT_TYPE = Enum.ThumbnailType.HeadShot
local PORTRAIT_SIZE = Enum.ThumbnailSize.Size100x100
local SLOT_GAP = 10
local TWEEN_MOVE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Team-based border colors (red / blue team)
local TEAM_STROKE_COLORS = {
    Red  = Color3.fromRGB(220, 50, 50),
    Blue = Color3.fromRGB(50, 100, 220),
}
local DEFAULT_STROKE = Color3.fromRGB(180, 180, 190)

local function getStrokeColorForPlayer(player)
    if player and player.Team and player.Team.Name then
        return TEAM_STROKE_COLORS[player.Team.Name] or DEFAULT_STROKE
    end
    return DEFAULT_STROKE
end

------------------------------------------------------------------------
-- ScreenGui + Root container (top-center, invisible background)
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TopPvpKillersHud"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 5
screenGui.Parent = PlayerGui

local rootFrame = Instance.new("Frame")
rootFrame.Name = "Root"
rootFrame.BackgroundTransparency = 1
rootFrame.AnchorPoint = Vector2.new(0.5, 0)
rootFrame.Position = UDim2.new(0.5, 0, 0, 4)
rootFrame.Size = UDim2.new(0, 400, 0, 80)
rootFrame.Visible = false -- hidden until someone has kills
rootFrame.Parent = screenGui

------------------------------------------------------------------------
-- Responsive sizing helpers
------------------------------------------------------------------------
local function getViewportWidth()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize then
        return cam.ViewportSize.X
    end
    return 1280
end

-- Scale factor: reduce overall UI to ~60% (40% smaller)
local UI_SCALE = 0.6
local function computeSlotPx()
    local vw = getViewportWidth()
    local px = math.floor(vw * 0.05 * UI_SCALE)
    return math.clamp(px, 24, 80 * UI_SCALE)
end

local function updateRootSize(slotPx, visibleCount)
    local count = math.max(visibleCount, 1)
    local totalW = count * slotPx + (count - 1) * SLOT_GAP
    local topMargin = math.floor(slotPx * 0.4) -- space above slots for crown
    rootFrame.Size = UDim2.new(0, totalW, 0, slotPx + topMargin)
end

------------------------------------------------------------------------
-- Build slot UI elements (all start hidden — NO flash of empty boxes)
------------------------------------------------------------------------
local slots = {}
for i = 1, MAX_SLOTS do
    local slot = Instance.new("Frame")
    slot.Name = "Slot" .. i
    slot.Size = UDim2.new(0, 56, 0, 56)
    slot.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    slot.BackgroundTransparency = 0.2
    slot.BorderSizePixel = 0
    slot.AnchorPoint = Vector2.new(0, 0)
    slot.ClipsDescendants = false
    slot.Visible = false
    slot.Parent = rootFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = slot

    local stroke = Instance.new("UIStroke")
    stroke.Color = DEFAULT_STROKE
    stroke.Thickness = 2
    stroke.Transparency = 0.2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = slot

    local portrait = Instance.new("ImageLabel")
    portrait.Name = "Portrait"
    portrait.Size = UDim2.new(1, -4, 1, -4)
    portrait.Position = UDim2.new(0, 2, 0, 2)
    portrait.BackgroundTransparency = 1
    portrait.BorderSizePixel = 0
    portrait.ScaleType = Enum.ScaleType.Crop
    portrait.Image = ""
    portrait.Parent = slot

    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 5)
    pCorner.Parent = portrait

    local countBg = Instance.new("Frame")
    countBg.Name = "CountBg"
    countBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    countBg.BackgroundTransparency = 0.35
    countBg.BorderSizePixel = 0
    countBg.Parent = slot

    local cbCorner = Instance.new("UICorner")
    cbCorner.CornerRadius = UDim.new(0, 4)
    cbCorner.Parent = countBg

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "Count"
    countLabel.Size = UDim2.new(1, 0, 1, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.TextColor3 = Color3.new(1, 1, 1)
    countLabel.TextStrokeTransparency = 0.4
    countLabel.Font = Enum.Font.GothamBold
    countLabel.Text = ""
    countLabel.Parent = countBg

    local crown = Instance.new("TextLabel")
    crown.Name = "Crown"
    crown.BackgroundTransparency = 1
    crown.Text = "👑"
    crown.TextScaled = true
    crown.Font = Enum.Font.GothamBold
    crown.TextColor3 = Color3.fromRGB(255, 215, 0)
    crown.Visible = false
    crown.ZIndex = 3
    crown.AnchorPoint = Vector2.new(0.5, 1)
    crown.Parent = slot

    slots[i] = {
        frame     = slot,
        portrait  = portrait,
        countBg   = countBg,
        countLabel = countLabel,
        crown     = crown,
        stroke    = stroke,
    }
end

-- Apply pixel-based sizes to one slot and its children
local function applySizeToSlot(s, px)
    s.frame.Size = UDim2.new(0, px, 0, px)
    s.portrait.Size = UDim2.new(1, -4, 1, -4)
    s.portrait.Position = UDim2.new(0, 2, 0, 2)
    local countH = math.max(14, math.floor(px * 0.26))
    s.countBg.Size = UDim2.new(1, -4, 0, countH)
    s.countBg.Position = UDim2.new(0, 2, 1, -countH - 2)
    s.countLabel.TextSize = math.max(10, math.floor(countH * 0.75))
    local crownPx = math.floor(px * 0.5)
    s.crown.Size = UDim2.new(0, crownPx, 0, crownPx)
    -- place crown above the slot: AnchorPoint is (0.5, 1) so Y=0 offset -4 puts it just above the top edge
    s.crown.Position = UDim2.new(0.5, 0, 0, -4)
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
-- PlayerKills helper
------------------------------------------------------------------------
local function getPlayerKills(player)
    local v = player:GetAttribute("PlayerKills")
    if type(v) == "number" then return v end
    return 0
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
    local topMargin = math.floor(slotPx * 0.4)

    -- 1) Build sorted list of players with kills > 0
    local entries = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local k = getPlayerKills(p)
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
                slots[idx].frame.BackgroundTransparency = 0.2
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

    -- 4) Resize root container and show it
    updateRootSize(slotPx, visibleCount)
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
        local targetPos = UDim2.new(0, (i - 1) * (slotPx + SLOT_GAP), 0, topMargin)
        local si = usedSlots[uid]

        if si then
            -- Player already owns a slot → update data and tween to new position
            local s = slots[si]
            applySizeToSlot(s, slotPx)
            s.countLabel.Text = tostring(entry.kills)
            s.crown.Visible = (i == 1)
            local targetColor = getStrokeColorForPlayer(entry.player)
            TweenService:Create(s.stroke, TWEEN_FADE, { Color = targetColor }):Play()
            TweenService:Create(s.frame, TWEEN_MOVE, { Position = targetPos }):Play()
        else
            -- New player — grab a free slot, place at target, fade in
            si = findFreeSlot()
            if not si then continue end
            usedSlots[uid] = si
            slotOwner[si] = uid

            local s = slots[si]
            applySizeToSlot(s, slotPx)
            s.portrait.Image = getThumbnail(uid)
            s.countLabel.Text = tostring(entry.kills)
            s.crown.Visible = (i == 1)

            s.stroke.Color = getStrokeColorForPlayer(entry.player)

            -- Snap to correct position, then fade in from transparent
            s.frame.Position = targetPos
            s.frame.BackgroundTransparency = 1
            s.frame.Visible = true
            TweenService:Create(s.frame, TWEEN_FADE, { BackgroundTransparency = 0.2 }):Play()
        end
    end
end

------------------------------------------------------------------------
-- Watch PlayerKills changes per player
------------------------------------------------------------------------
local playerConns = {}

local function watchPlayer(player)
    -- avoid duplicate connections
    if playerConns[player] then
        playerConns[player]:Disconnect()
        playerConns[player] = nil
    end
    -- listen for attribute changes to PlayerKills
    if player.GetAttributeChangedSignal then
        playerConns[player] = player:GetAttributeChangedSignal("PlayerKills"):Connect(function()
            updateHud()
        end)
    else
        -- fallback: poll periodically (very unlikely on modern clients)
        playerConns[player] = nil
    end
    -- refresh immediately so we pick up the current value
    updateHud()
end

local function unwatchPlayer(player)
    if playerConns[player] then
        playerConns[player]:Disconnect()
        playerConns[player] = nil
    end
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
    updateHud()
end)

-- Watch all players currently in the game (blocking so we pick up their stats)
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(watchPlayer, p)
end

-- Recompute on viewport change
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        updateHud()
    end)
end

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
