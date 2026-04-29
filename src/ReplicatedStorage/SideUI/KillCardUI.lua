--------------------------------------------------------------------------------
-- KillCardUI.lua  –  Right-side "Defeated By" combat card.
--
-- Public API:
--   KillCardUI.Mount(parentScreenGui)  -> controller
--   controller:Show(payload, onRevenge)
--   controller:Hide()
--
-- Robustness notes:
--   * Show/Hide are idempotent and safe to interleave. A monotonically
--     increasing `seq` token is captured by every async callback (tween
--     Completed handlers, thumbnail fetches, ViewportFrame builds) and any
--     callback whose token is stale becomes a no-op. This eliminates the
--     classic "every-other-death" failure where a Hide tween's Completed
--     handler fires after a new Show set Visible=true and silently re-hid the
--     card.
--   * Portrait fully rebuilds each Show: ImageLabel image cleared, viewport
--     children destroyed, fallback hidden. No stale state can leak between
--     deaths.
--
-- Portrait modes:
--   Player  -> ImageLabel with Roblox HeadShot thumbnail (skull only on fail)
--   NPC     -> ViewportFrame with cloned NPC model (skull only when no model)
--   Unknown -> Skull glyph
--------------------------------------------------------------------------------

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local KillCardUI = {}

local function px(base)
    local cam = workspace.CurrentCamera
    local h = (cam and cam.ViewportSize.Y) or 1080
    if h < 200 then h = 1080 end
    return math.max(1, math.floor(base * (h / 1080) + 0.5))
end

local function createStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or UITheme.GOLD_DIM
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function createCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function badgeColorFor(kind)
    if kind == "Player" then return Color3.fromRGB(80, 130, 220) end
    if kind == "NPC"    then return Color3.fromRGB(180, 70, 70)  end
    return Color3.fromRGB(110, 110, 130)
end

local function badgeTextFor(kind, category)
    if kind == "Player" then return "PLAYER" end
    if kind == "NPC" then
        if category and category ~= "" then return string.upper(category) end
        return "MONSTER"
    end
    return "UNKNOWN"
end

local function safeThumbnail(userId)
    if not userId then return nil end
    local ok, content = pcall(function()
        return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
    end)
    if ok and content and content ~= "" then return content end
    return nil
end

--------------------------------------------------------------------------------
-- Build a ViewportFrame preview of an NPC model. Returns true on success.
-- Clones the model client-side, strips scripts, frames it from the front.
--------------------------------------------------------------------------------
local function buildNpcViewport(viewport, npcModel)
    -- Clear any previous contents first.
    for _, child in ipairs(viewport:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera") then
            child:Destroy()
        end
    end

    if not npcModel or typeof(npcModel) ~= "Instance" or not npcModel:IsA("Model") or not npcModel.Parent then
        return false
    end

    -- Roblox requires Archivable=true to clone. Many replicated models default true,
    -- but we restore whatever it was.
    local prevArchivable = npcModel.Archivable
    if not prevArchivable then
        local ok = pcall(function() npcModel.Archivable = true end)
        if not ok then return false end
    end

    local cloneOk, clone = pcall(function() return npcModel:Clone() end)
    if not prevArchivable then pcall(function() npcModel.Archivable = false end) end
    if not cloneOk or not clone then return false end

    -- Strip scripts so nothing tries to run inside the viewport.
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
        end
    end

    -- Compute bounding box for camera framing.
    local cf, size = clone:GetBoundingBox()
    local maxExtent = math.max(size.X, size.Y, size.Z)
    if maxExtent <= 0 then maxExtent = 4 end

    clone.Parent = viewport

    local cam = Instance.new("Camera")
    cam.FieldOfView = 60
    -- Frame the upper body from slightly above eye-level, looking at head height.
    local lookTarget = cf.Position + Vector3.new(0, size.Y * 0.15, 0)
    local distance = maxExtent * 1.6
    local camPos = lookTarget + Vector3.new(0, size.Y * 0.05, distance)
    cam.CFrame = CFrame.lookAt(camPos, lookTarget)
    cam.Parent = viewport
    viewport.CurrentCamera = cam

    return true
end

--------------------------------------------------------------------------------
function KillCardUI.Mount(parentScreenGui)
    assert(parentScreenGui and parentScreenGui:IsA("ScreenGui"), "KillCardUI.Mount needs a ScreenGui parent")

    local CARD_W = px(280)
    local CARD_H = px(360)

    local root = Instance.new("Frame")
    root.Name = "KillCard"
    root.AnchorPoint = Vector2.new(1, 0.5)
    root.Position = UDim2.new(1, px(40), 0.5, 0)
    root.Size = UDim2.fromOffset(CARD_W, CARD_H)
    root.BackgroundColor3 = UITheme.NAVY
    root.BackgroundTransparency = 0
    root.BorderSizePixel = 0
    root.Visible = false
    root.ZIndex = 50
    root.Parent = parentScreenGui

    createCorner(root, 8)
    createStroke(root, UITheme.GOLD_DIM, 2)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(UITheme.NAVY_LIGHT, UITheme.NAVY)
    grad.Rotation = 90
    grad.Parent = root

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, px(10))
    pad.PaddingBottom = UDim.new(0, px(10))
    pad.PaddingLeft   = UDim.new(0, px(10))
    pad.PaddingRight  = UDim.new(0, px(10))
    pad.Parent = root

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, px(22))
    header.BackgroundTransparency = 1
    header.Text = "DEFEATED BY"
    header.Font = Enum.Font.GothamBold
    header.TextColor3 = UITheme.GOLD
    header.TextSize = px(16)
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.ZIndex = 51
    header.Parent = root

    -- Portrait container (fixed slot)
    local portraitSlot = Instance.new("Frame")
    portraitSlot.Name = "PortraitSlot"
    portraitSlot.AnchorPoint = Vector2.new(0.5, 0)
    portraitSlot.Position = UDim2.new(0.5, 0, 0, px(30))
    portraitSlot.Size = UDim2.fromOffset(px(120), px(120))
    portraitSlot.BackgroundColor3 = UITheme.ICON_BG
    portraitSlot.BorderSizePixel = 0
    portraitSlot.ZIndex = 51
    portraitSlot.Parent = root
    createCorner(portraitSlot, 8)
    createStroke(portraitSlot, UITheme.CARD_STROKE, 2)

    -- Mode A: ImageLabel for Player avatar + Unknown skull + NPC fallback
    local portraitImage = Instance.new("ImageLabel")
    portraitImage.Name = "PortraitImage"
    portraitImage.Size = UDim2.fromScale(1, 1)
    portraitImage.BackgroundTransparency = 1
    portraitImage.Image = ""
    portraitImage.ScaleType = Enum.ScaleType.Fit
    portraitImage.Visible = false
    portraitImage.ZIndex = 52
    portraitImage.Parent = portraitSlot
    createCorner(portraitImage, 8)

    -- Mode B: ViewportFrame for NPC model preview
    local portraitViewport = Instance.new("ViewportFrame")
    portraitViewport.Name = "PortraitViewport"
    portraitViewport.Size = UDim2.fromScale(1, 1)
    portraitViewport.BackgroundTransparency = 1
    portraitViewport.Visible = false
    portraitViewport.ZIndex = 52
    portraitViewport.Parent = portraitSlot
    createCorner(portraitViewport, 8)

    -- Fallback glyph (only when nothing else available)
    local portraitFallback = Instance.new("TextLabel")
    portraitFallback.Name = "PortraitFallback"
    portraitFallback.Size = UDim2.fromScale(1, 1)
    portraitFallback.BackgroundTransparency = 1
    portraitFallback.Text = "\u{2620}"
    portraitFallback.Font = Enum.Font.GothamBlack
    portraitFallback.TextColor3 = UITheme.DIM_TEXT
    portraitFallback.TextScaled = true
    portraitFallback.Visible = false
    portraitFallback.ZIndex = 53
    portraitFallback.Parent = portraitSlot

    -- Killer name
    local nameLbl = Instance.new("TextLabel")
    nameLbl.AnchorPoint = Vector2.new(0.5, 0)
    nameLbl.Position = UDim2.new(0.5, 0, 0, px(160))
    nameLbl.Size = UDim2.new(1, 0, 0, px(24))
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = ""
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextColor3 = UITheme.WHITE
    nameLbl.TextSize = px(20)
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.ZIndex = 51
    nameLbl.Parent = root

    -- Badge
    local badge = Instance.new("Frame")
    badge.AnchorPoint = Vector2.new(0.5, 0)
    badge.Position = UDim2.new(0.5, 0, 0, px(188))
    badge.Size = UDim2.fromOffset(px(110), px(20))
    badge.BackgroundColor3 = badgeColorFor("Unknown")
    badge.BorderSizePixel = 0
    badge.ZIndex = 51
    badge.Parent = root
    createCorner(badge, 4)
    createStroke(badge, Color3.fromRGB(0, 0, 0), 1)

    local badgeLbl = Instance.new("TextLabel")
    badgeLbl.Size = UDim2.fromScale(1, 1)
    badgeLbl.BackgroundTransparency = 1
    badgeLbl.Text = ""
    badgeLbl.Font = Enum.Font.GothamBold
    badgeLbl.TextColor3 = UITheme.WHITE
    badgeLbl.TextSize = px(12)
    badgeLbl.ZIndex = 52
    badgeLbl.Parent = badge

    -- Stats list
    local stats = Instance.new("Frame")
    stats.AnchorPoint = Vector2.new(0.5, 0)
    stats.Position = UDim2.new(0.5, 0, 0, px(216))
    stats.Size = UDim2.new(1, 0, 0, px(70))
    stats.BackgroundTransparency = 1
    stats.ZIndex = 51
    stats.Parent = root

    local statList = Instance.new("UIListLayout")
    statList.SortOrder = Enum.SortOrder.LayoutOrder
    statList.Padding = UDim.new(0, px(2))
    statList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    statList.Parent = stats

    local function makeStatLine(order)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, px(16))
        lbl.BackgroundTransparency = 1
        lbl.Text = ""
        lbl.Font = Enum.Font.Gotham
        lbl.TextColor3 = UITheme.DIM_TEXT
        lbl.TextSize = px(13)
        lbl.LayoutOrder = order
        lbl.ZIndex = 52
        lbl.Parent = stats
        return lbl
    end
    local statLevel  = makeStatLine(1)
    local statStreak = makeStatLine(2)
    local statCount  = makeStatLine(3)
    local statWeapon = makeStatLine(4)

    -- Revenge button
    local revengeBtn = Instance.new("TextButton")
    revengeBtn.AnchorPoint = Vector2.new(0.5, 1)
    revengeBtn.Position = UDim2.new(0.5, 0, 1, -px(20))
    revengeBtn.Size = UDim2.new(1, -px(8), 0, px(36))
    revengeBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 50)
    revengeBtn.BorderSizePixel = 0
    revengeBtn.Text = "REVENGE"
    revengeBtn.Font = Enum.Font.GothamBold
    revengeBtn.TextColor3 = UITheme.WHITE
    revengeBtn.TextSize = px(16)
    revengeBtn.AutoButtonColor = true
    revengeBtn.ZIndex = 51
    revengeBtn.Parent = root
    createCorner(revengeBtn, 6)
    createStroke(revengeBtn, Color3.fromRGB(120, 30, 30), 1)

    local revengeSub = Instance.new("TextLabel")
    revengeSub.AnchorPoint = Vector2.new(0.5, 1)
    revengeSub.Position = UDim2.new(0.5, 0, 1, -px(4))
    revengeSub.Size = UDim2.new(1, 0, 0, px(12))
    revengeSub.BackgroundTransparency = 1
    revengeSub.Text = "Coming soon  •  Robux"
    revengeSub.Font = Enum.Font.Gotham
    revengeSub.TextColor3 = UITheme.DIM_TEXT
    revengeSub.TextSize = px(10)
    revengeSub.ZIndex = 51
    revengeSub.Parent = root

    --------------------------------------------------------------------------
    -- Controller
    --------------------------------------------------------------------------
    local controller = {}
    local seq = 0
    local activeShowTween, activeHideTween
    local revengeConn

    local ON_SCREEN_X  = UDim2.new(1, -px(20), 0.5, 0)
    local OFF_SCREEN_X = UDim2.new(1, px(40),  0.5, 0)

    -- Wipe portrait state to a known-clean baseline.
    local function resetPortrait()
        portraitImage.Visible = false
        portraitImage.Image = ""
        portraitImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
        portraitViewport.Visible = false
        for _, child in ipairs(portraitViewport:GetChildren()) do
            if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera") then
                child:Destroy()
            end
        end
        portraitViewport.CurrentCamera = nil
        portraitFallback.Visible = false
        portraitFallback.Text = "\u{2620}"
    end

    local function showFallbackSkull()
        portraitImage.Visible = false
        portraitViewport.Visible = false
        portraitFallback.Visible = true
        portraitFallback.Text = "\u{2620}"
    end

    local function showImage(url)
        portraitViewport.Visible = false
        portraitFallback.Visible = false
        portraitImage.Image = url or ""
        portraitImage.Visible = true
    end

    function controller:Show(payload, onRevenge)
        seq = seq + 1
        local mySeq = seq

        -- Cancel any in-flight tweens; their Completed handlers will check seq
        -- and become no-ops if a newer Show has begun.
        if activeShowTween then pcall(function() activeShowTween:Cancel() end); activeShowTween = nil end
        if activeHideTween then pcall(function() activeHideTween:Cancel() end); activeHideTween = nil end

        local kind     = payload.killerKind or "Unknown"
        local nameStr  = payload.killerDisplayName or payload.killerName or "Unknown"
        local count    = tonumber(payload.killedByThisKillerCount) or 0

        nameLbl.Text   = nameStr
        badge.BackgroundColor3 = badgeColorFor(kind)
        badgeLbl.Text  = badgeTextFor(kind, payload.killerCategory)

        -- Always start from a clean portrait so prior killer's image can't bleed through.
        resetPortrait()

        if kind == "Player" and payload.killerUserId then
            -- Show fallback while async thumbnail loads.
            showFallbackSkull()
            task.spawn(function()
                local img = safeThumbnail(payload.killerUserId)
                if mySeq ~= seq then return end  -- stale: a newer Show happened
                if img then
                    showImage(img)
                else
                    -- Keep skull fallback if thumbnail fetch fails.
                    showFallbackSkull()
                end
            end)
        elseif kind == "NPC" then
            -- Try to render the actual NPC model in a viewport.
            local ok = buildNpcViewport(portraitViewport, payload.killerModel)
            if ok then
                portraitViewport.Visible = true
                portraitImage.Visible = false
                portraitFallback.Visible = false
            else
                -- No model available -> NPC fallback skull.
                showFallbackSkull()
            end
        else
            -- Unknown / environment death.
            showFallbackSkull()
        end

        -- Stats
        if kind == "Player" then
            statLevel.Text  = payload.killerLevel and ("Level " .. tostring(payload.killerLevel)) or ""
            statStreak.Text = (payload.killerStreak and payload.killerStreak > 0)
                and ("Kill streak: " .. tostring(payload.killerStreak)) or ""
        elseif kind == "NPC" then
            statLevel.Text  = payload.killerCategory or ""
            statStreak.Text = ""
        else
            statLevel.Text, statStreak.Text = "", ""
        end

        if count > 0 then
            statCount.Text = string.format("Killed you %d time%s", count, count == 1 and "" or "s")
        else
            statCount.Text = ""
        end
        statWeapon.Text = payload.killerWeaponName and ("Weapon: " .. tostring(payload.killerWeaponName)) or ""

        -- Re-bind revenge button each Show.
        if revengeConn then revengeConn:Disconnect(); revengeConn = nil end
        revengeBtn.Visible = (kind ~= "Unknown")
        revengeSub.Visible = revengeBtn.Visible
        if revengeBtn.Visible then
            revengeConn = revengeBtn.MouseButton1Click:Connect(function()
                if onRevenge then pcall(onRevenge, payload) end
            end)
        end

        -- Slide / fade in. Force a clean baseline so a prior Hide can't leave us hidden.
        root.Position = OFF_SCREEN_X
        root.BackgroundTransparency = 1
        root.Visible = true

        local tw = TweenService:Create(root,
            TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Position = ON_SCREEN_X, BackgroundTransparency = 0 })
        activeShowTween = tw
        tw.Completed:Connect(function()
            if mySeq ~= seq then return end
            if activeShowTween == tw then activeShowTween = nil end
        end)
        tw:Play()
    end

    function controller:Hide()
        if not root.Visible then return end
        seq = seq + 1
        local mySeq = seq

        if revengeConn then revengeConn:Disconnect(); revengeConn = nil end
        if activeShowTween then pcall(function() activeShowTween:Cancel() end); activeShowTween = nil end
        if activeHideTween then pcall(function() activeHideTween:Cancel() end); activeHideTween = nil end

        local tw = TweenService:Create(root,
            TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            { Position = OFF_SCREEN_X, BackgroundTransparency = 1 })
        activeHideTween = tw
        tw.Completed:Connect(function()
            -- CRITICAL: only hide if our seq is still current. A new Show that
            -- ran after this Hide will have bumped seq, and we must not
            -- override its Visible=true.
            if mySeq ~= seq then return end
            root.Visible = false
            if activeHideTween == tw then activeHideTween = nil end
        end)
        tw:Play()
    end

    return controller
end

return KillCardUI
