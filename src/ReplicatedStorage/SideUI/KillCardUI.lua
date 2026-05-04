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
--   Player  -> ViewportFrame with generated avatar rig (thumbnail only on fail)
--   NPC     -> ViewportFrame with cloned NPC model (skull only when no model)
--   Unknown -> Skull glyph
--------------------------------------------------------------------------------

local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService  = game:GetService("TweenService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local EmoteConfig
pcall(function()
    local mod = script.Parent:FindFirstChild("EmoteConfig")
    if mod and mod:IsA("ModuleScript") then
        EmoteConfig = require(mod)
    end
end)

local KillCardUI = {}

local DEFAULT_PLAYER_PORTRAIT_EMOTE_ID = "wave"

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
-- Look up a canonical mob template (clean clone source) in
-- ReplicatedStorage.MobTemplates. Server publishes this folder at startup.
-- Falls back to nil; caller decides what to do.
--------------------------------------------------------------------------------
local function getMobTemplate(templateName)
    if not templateName or templateName == "" then return nil end
    local folder = ReplicatedStorage:FindFirstChild("MobTemplates")
    if not folder then return nil end
    local m = folder:FindFirstChild(templateName)
    if m and m:IsA("Model") then return m end
    return nil
end

--------------------------------------------------------------------------------
-- Sanitize a cloned character/NPC model for use inside a ViewportFrame /
-- WorldModel. Strips scripts, anchors parts, disables collisions/queries.
-- Returns the same model for chaining.
--------------------------------------------------------------------------------
local function sanitizeForViewport(clone, anchorParts)
    if not clone then return clone end
    if anchorParts == nil then anchorParts = true end
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("ModuleScript")
            or d:IsA("BillboardGui") or d:IsA("ForceField") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = anchorParts
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
        end
    end
    return clone
end

local function prepareAnimatedAvatarForViewport(rig)
    sanitizeForViewport(rig, false)

    local root = rig and rig:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        root.Anchored = true
    end

    local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        if not humanoid:FindFirstChildOfClass("Animator") then
            Instance.new("Animator").Parent = humanoid
        end
    end

    return rig
end

--------------------------------------------------------------------------------
-- Find the head/torso of a humanoid-shaped Model so we can frame the camera
-- consistently regardless of rig type (R6 / R15 / custom NPC).
--------------------------------------------------------------------------------
local function getFramingPivot(model)
    local root = model:FindFirstChild("HumanoidRootPart")
              or model:FindFirstChild("Torso")
              or model:FindFirstChild("UpperTorso")
              or model.PrimaryPart
              or model:FindFirstChildWhichIsA("BasePart")
    if not root then
        return model:GetPivot(), Vector3.new(4, 5, 2)
    end
    return root.CFrame, model:GetExtentsSize()
end

--------------------------------------------------------------------------------
-- Build a clean front-facing preview of `model` inside `viewport`.
-- Uses a WorldModel so animations / Motor6Ds remain functional for future
-- emote support. Roblox characters face toward local -Z, so the camera sits
-- on the -Z side and looks back at the chest/head area.
--------------------------------------------------------------------------------
local function buildModelViewport(viewport, model, options)
    options = options or {}

    -- Clear any previous contents.
    for _, child in ipairs(viewport:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera")
            or child:IsA("WorldModel") then
            child:Destroy()
        end
    end

    if not model or typeof(model) ~= "Instance" or not model:IsA("Model") then
        return false
    end

    -- WorldModel inside the ViewportFrame allows animators / future emotes.
    local world = Instance.new("WorldModel")
    world.Parent = viewport

    -- Re-pivot the model to origin facing -Z.
    -- This guarantees a clean front-facing pose no matter what orientation
    -- the source model had in workspace/ReplicatedStorage.
    local _, extents = getFramingPivot(model)
    -- Pivot at origin, facing forward (-Z is "front" in Roblox character convention)
    pcall(function() model:PivotTo(CFrame.new(0, 0, 0)) end)

    model.Parent = world

    -- Recompute extents now that model is parented.
    local size = model:GetExtentsSize()
    local maxExtent = math.max(size.X, size.Y, size.Z)
    if maxExtent <= 0 then maxExtent = 5 end

    -- Camera setup — front view, centered on torso/head area.
    local cam = Instance.new("Camera")
    cam.FieldOfView = options.fieldOfView or 50
    -- Look at a point slightly above the geometric center (head area).
    local lookAt = Vector3.new(0, size.Y * (options.lookAtHeightScale or 0.15), 0)
    -- Distance scaled to the model's largest extent so big and small
    -- mobs are framed identically.
    local distance = maxExtent * (options.distanceScale or 1.85)
    -- Camera in FRONT of the model (negative Z because model faces -Z).
    local camPos = lookAt + Vector3.new(0, size.Y * 0.05, -distance)
    cam.CFrame = CFrame.lookAt(camPos, lookAt)
    cam.Parent = viewport
    viewport.CurrentCamera = cam

    return true
end

--------------------------------------------------------------------------------
-- Player preview: build a fresh avatar rig from HumanoidDescription instead
-- of cloning the live character. That keeps the card from becoming a frozen
-- death-moment body/tool snapshot and gives us a clean Animator path.
--------------------------------------------------------------------------------
local function buildPlayerAvatarRig(userId)
    if not userId then return nil end

    local desc
    local player = Players:GetPlayerByUserId(userId)
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            desc = hum:GetAppliedDescription()
        end)
    end

    if not desc then
        pcall(function()
            desc = Players:GetHumanoidDescriptionFromUserId(userId)
        end)
    end
    if not desc then return nil end

    local rig
    pcall(function()
        rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not rig then return nil end

    rig.Name = "KillCardAvatar_" .. tostring(userId)
    return prepareAnimatedAvatarForViewport(rig)
end

local function resolvePlayerPortraitAnimationId(payload)
    local explicitId = payload and (payload.portraitAnimationId
        or payload.killCardAnimationId
        or payload.killerAnimationId)
    if type(explicitId) == "string" and explicitId ~= "" then
        return explicitId
    end

    if EmoteConfig and type(EmoteConfig.GetById) == "function" then
        local def = EmoteConfig.GetById(DEFAULT_PLAYER_PORTRAIT_EMOTE_ID)
        if def and type(def.AnimationId) == "string" and def.AnimationId ~= "" then
            return def.AnimationId
        end
    end

    return nil
end

local function playPortraitAnimation(rig, animationId)
    if not rig or type(animationId) ~= "string" or animationId == "" then
        return nil
    end

    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId
    local track
    local ok, err = pcall(function()
        track = animator:LoadAnimation(animation)
    end)
    animation:Destroy()

    if not ok or not track then
        warn("[KillCardUI] Failed to load portrait animation:", err)
        return nil
    end

    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    pcall(function() track:Play(0.2) end)
    return track
end

--------------------------------------------------------------------------------
-- NPC preview: prefer the canonical model from ReplicatedStorage.MobTemplates
-- (set up by MobSpawner). Never clones from workspace per design note.
--------------------------------------------------------------------------------
local function buildNpcViewport(viewport, payload)
    -- Prefer the templated source published by the server.
    local templateName = payload and (payload.npcTemplateName or payload.killerName)
    local template = getMobTemplate(templateName)
    if template then
        local prevArchivable = template.Archivable
        if not prevArchivable then pcall(function() template.Archivable = true end) end
        local ok, clone = pcall(function() return template:Clone() end)
        if not prevArchivable then pcall(function() template.Archivable = false end) end
        if ok and clone then
            sanitizeForViewport(clone)
            return buildModelViewport(viewport, clone)
        end
    end
    return false
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

    -- Mode A: ImageLabel fallback for player avatar load failures
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

    -- Mode B: ViewportFrame for player avatar and NPC model previews
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
    local activePortraitTrack
    local revengeConn

    local ON_SCREEN_X  = UDim2.new(1, -px(20), 0.5, 0)
    local OFF_SCREEN_X = UDim2.new(1, px(40),  0.5, 0)

    -- Wipe portrait state to a known-clean baseline.
    local function stopPortraitAnimation()
        if activePortraitTrack then
            pcall(function() activePortraitTrack:Stop(0) end)
            pcall(function() activePortraitTrack:Destroy() end)
            activePortraitTrack = nil
        end
    end

    local function resetPortrait()
        stopPortraitAnimation()
        portraitImage.Visible = false
        portraitImage.Image = ""
        portraitImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
        portraitViewport.Visible = false
        for _, child in ipairs(portraitViewport:GetChildren()) do
            if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Camera")
                or child:IsA("WorldModel") then
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
            showFallbackSkull()
            local animationId = resolvePlayerPortraitAnimationId(payload)
            task.spawn(function()
                local rig = buildPlayerAvatarRig(payload.killerUserId)
                if mySeq ~= seq then
                    if rig then pcall(function() rig:Destroy() end) end
                    return
                end

                if rig then
                    local rendered3D = buildModelViewport(portraitViewport, rig, {
                        fieldOfView = 42,
                        distanceScale = 1.65,
                        lookAtHeightScale = 0.22,
                    })
                    if rendered3D then
                        activePortraitTrack = playPortraitAnimation(rig, animationId)
                        portraitViewport.Visible = true
                        portraitImage.Visible = false
                        portraitFallback.Visible = false
                        return
                    end
                    pcall(function() rig:Destroy() end)
                end

                local img = safeThumbnail(payload.killerUserId)
                if mySeq ~= seq then return end
                if img then
                    showImage(img)
                else
                    showFallbackSkull()
                end
            end)
        elseif kind == "NPC" then
            -- Use ReplicatedStorage.MobTemplates (server-published) — never
            -- the workspace mob clone.
            local ok = buildNpcViewport(portraitViewport, payload)
            if ok then
                portraitViewport.Visible = true
                portraitImage.Visible = false
                portraitFallback.Visible = false
            else
                -- No template available -> NPC fallback skull.
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
            resetPortrait()
            if activeHideTween == tw then activeHideTween = nil end
        end)
        tw:Play()
    end

    return controller
end

return KillCardUI
