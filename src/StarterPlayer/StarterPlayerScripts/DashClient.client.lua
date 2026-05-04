--------------------------------------------------------------------------------
-- DashClient.client.lua
-- Client-side dash ability: UI button, keyboard input, cooldown display,
-- visual effects (trail + speed particles + afterimage).
--
-- StarterPlayerScripts  –  persists across respawns (ResetOnSpawn = false).
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local player   = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DEBUG = false
local DEBUG_LAYOUT = true -- temporary diagnostics for button positioning
local function log(...) if DEBUG then print("[DashClient]", ...) end end
local function logLayout(...)
    if DEBUG_LAYOUT then
        print("[DashClient:Layout]", ...)
    end
end

--------------------------------------------------------------------------------
-- Wait for viewport to stabilise (same pattern as HealthBar / SideUI)
--------------------------------------------------------------------------------
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

--------------------------------------------------------------------------------
-- Responsive scaling (reference 1080p – matches project convention)
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
-- Load DashConfig
--------------------------------------------------------------------------------
local DashConfig
do
    local mod = ReplicatedStorage:WaitForChild("DashConfig", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then DashConfig = result end
    end
end
if not DashConfig then
    warn("[DashClient] DashConfig not found – using defaults")
    DashConfig = { Cooldown = 12, Duration = 0.18, Distance = 22,
                   EffectEnabled = true, AnimationId = "",
                   TrailLifetime = 0.25, ParticleCount = 18,
                   GhostTransparency = 0.7, GhostFadeDuration = 0.35,
                   DefaultEffectColor = Color3.fromRGB(180, 220, 255) }
end

--------------------------------------------------------------------------------
-- Load EffectDefs (for resolving trail colors by effectId)
--------------------------------------------------------------------------------
local EffectDefs = nil
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
    if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
end)

--------------------------------------------------------------------------------
-- Wait for Remotes
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 15)
local dashFolder    = remotesFolder and remotesFolder:WaitForChild("Dash", 15)
local requestDash   = dashFolder and dashFolder:WaitForChild("RequestDash", 10)
local dashApproved  = dashFolder and dashFolder:WaitForChild("DashApproved", 10)
local dashRejected  = dashFolder and dashFolder:WaitForChild("DashRejected", 10)
local playDashVFX   = dashFolder and dashFolder:WaitForChild("PlayDashVFX", 10)

if not requestDash or not dashApproved then
    warn("[DashClient] Dash remotes not found – dash disabled")
    return
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local isCoolingDown  = false
local cooldownEnd    = 0
local isDashing      = false
local currentTeamColor = nil

--------------------------------------------------------------------------------
-- PALETTE (consistent with navy + gold game theme)
--------------------------------------------------------------------------------
local NAVY        = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT  = Color3.fromRGB(22, 26, 48)
local GOLD        = Color3.fromRGB(255, 215, 80)
local GOLD_DIM    = Color3.fromRGB(180, 150, 50)
local WHITE       = Color3.fromRGB(245, 245, 252)
local DIM_TEXT    = Color3.fromRGB(145, 150, 175)
local DISABLED_BG = Color3.fromRGB(35, 38, 52)

local function teamColorOrNil(team)
    if not team then return nil end
    local name = tostring(team.Name):lower()
    if string.find(name, "neutral") then return nil end
    if team.TeamColor then return team.TeamColor.Color end
    return nil
end

local function getTeamTintFill(teamColor)
    if not teamColor then
        return NAVY_LIGHT
    end
    -- Mirror Hotbar style: darkened team tint for base readability.
    return teamColor:Lerp(Color3.new(0, 0, 0), 0.55)
end

local function getTeamTintHoverFill(teamColor)
    if not teamColor then
        return Color3.fromRGB(30, 34, 60)
    end
    -- Slightly lighter than ready fill, still legible with gold stroke/text.
    local base = getTeamTintFill(teamColor)
    return base:Lerp(Color3.new(1, 1, 1), 0.08)
end

local function getTeamTintPressedFill(teamColor)
    if not teamColor then
        return Color3.fromRGB(35, 40, 65)
    end
    -- Press state: a bit deeper than hover for click feedback.
    local base = getTeamTintFill(teamColor)
    return base:Lerp(Color3.new(0, 0, 0), 0.08)
end

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local oldDashGui = playerGui:FindFirstChild("DashGui")
if oldDashGui then
    -- Keep one runtime source of truth; remove stale instances on script reload.
    oldDashGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DashGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 7
screenGui.Parent = playerGui

--------------------------------------------------------------------------------
-- DASH BUTTON - sits on the same baseline as the 1-4 hotbar slots.
-- Its right edge lines up with the XP bar's right edge.
--------------------------------------------------------------------------------
local BUTTON_SIZE          = 108   -- base px at 1080p; matches Hotbar SLOT_SCALE
local HOTBAR_BOTTOM_OFFSET = 0.012 + 0.058
local XP_BAR_WIDTH_SCALE   = 0.34
local XP_LEVEL_LABEL_SIZE  = 22
local XP_BAR_EXTRA_WIDTH   = XP_LEVEL_LABEL_SIZE * 2 + 24

local btnFrame = Instance.new("Frame")
btnFrame.Name = "DashButtonFrame"
btnFrame.AnchorPoint = Vector2.new(1, 1)
btnFrame.Size = UDim2.fromOffset(px(BUTTON_SIZE), px(BUTTON_SIZE))
btnFrame.BackgroundTransparency = 1
btnFrame.Parent = screenGui

local applyingLayout = false
local function applyButtonLayout()
    applyingLayout = true
    btnFrame.Position = UDim2.new(
        0.5 + (XP_BAR_WIDTH_SCALE / 2), XP_BAR_EXTRA_WIDTH / 2,
        1 - HOTBAR_BOTTOM_OFFSET, 0
    )
    btnFrame.Size = UDim2.fromOffset(px(BUTTON_SIZE), px(BUTTON_SIZE))
    applyingLayout = false
end

local function printButtonDebug(tag)
    local ap = btnFrame.AbsolutePosition
    local as = btnFrame.AbsoluteSize
    logLayout(tag,
        "path=PlayerGui/" .. screenGui.Name .. "/" .. btnFrame.Name,
        "parent=" .. (btnFrame.Parent and btnFrame.Parent.Name or "nil"),
        "position=" .. tostring(btnFrame.Position),
        "size=" .. tostring(btnFrame.Size),
        "anchor=" .. tostring(btnFrame.AnchorPoint),
        "absPos=" .. tostring(ap),
        "absSize=" .. tostring(as)
    )

    local current = btnFrame.Parent
    while current and current ~= playerGui do
        for _, child in ipairs(current:GetChildren()) do
            if child:IsA("UIListLayout")
                or child:IsA("UIGridLayout")
                or child:IsA("UITableLayout")
                or child:IsA("UIPageLayout") then
                logLayout("layout-controller-found:", child.ClassName, "on", current:GetFullName())
            end
        end
        current = current.Parent
    end
end

btnFrame:GetPropertyChangedSignal("Position"):Connect(function()
    if not applyingLayout then
        logLayout("position changed externally ->", tostring(btnFrame.Position))
    end
end)

applyButtonLayout()

local camForLayout = workspace.CurrentCamera
if camForLayout then
    camForLayout:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        applyButtonLayout()
    end)
end

task.defer(function()
    printButtonDebug("post-create")
end)

task.delay(1.0, function()
    printButtonDebug("after-1s")
end)

task.delay(3.0, function()
    printButtonDebug("after-3s")
end)

-- Drop shadow (matches other HUD elements)
local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.fromScale(0.5, 0.5)
shadow.Size = UDim2.new(1, px(6), 1, px(6))
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.65
shadow.BorderSizePixel = 0
shadow.ZIndex = 0
shadow.Parent = btnFrame
do
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, px(14))
    sc.Parent = shadow
end

-- Main button
local btn = Instance.new("TextButton")
btn.Name = "DashBtn"
btn.Size = UDim2.fromScale(1, 1)
btn.BackgroundColor3 = NAVY_LIGHT
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Text = ""
btn.ZIndex = 1
btn.Parent = btnFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, px(14))
btnCorner.Parent = btn

local btnStroke = Instance.new("UIStroke")
btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
btnStroke.Thickness = px(2)
btnStroke.Color = GOLD_DIM
btnStroke.Parent = btn

-- Inner gradient tint (subtle depth, matching Side UI panels)
local btnGradient = Instance.new("UIGradient")
btnGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 200)),
})
btnGradient.Rotation = 90
btnGradient.Parent = btn

-- Speed icon – prominent glyph centred in upper portion
local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "Icon"
iconLabel.AnchorPoint = Vector2.new(0.5, 0)
iconLabel.Size = UDim2.fromScale(0.92, 0.56)
iconLabel.Position = UDim2.fromScale(0.5, 0.03)
iconLabel.BackgroundTransparency = 1
iconLabel.Text = "»"
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextColor3 = GOLD
iconLabel.TextScaled = true
iconLabel.ZIndex = 1
iconLabel.Parent = btn

-- "DASH" label – clear, centred text
local dashLabel = Instance.new("TextLabel")
dashLabel.Name = "DashLabel"
dashLabel.AnchorPoint = Vector2.new(0.5, 0)
dashLabel.Size = UDim2.fromScale(0.9, 0.2)
dashLabel.Position = UDim2.fromScale(0.5, 0.58)
dashLabel.BackgroundTransparency = 1
dashLabel.Text = "DASH"
dashLabel.Font = Enum.Font.GothamBold
dashLabel.TextColor3 = WHITE
dashLabel.TextScaled = true
dashLabel.ZIndex = 1
dashLabel.Parent = btn

-- Keybind hint – small footer
local keybindLabel = Instance.new("TextLabel")
keybindLabel.Name = "Keybind"
keybindLabel.AnchorPoint = Vector2.new(0.5, 1)
keybindLabel.Size = UDim2.fromScale(0.8, 0.16)
keybindLabel.Position = UDim2.fromScale(0.5, 0.965)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "[SHIFT]"
keybindLabel.Font = Enum.Font.Gotham
keybindLabel.TextColor3 = DIM_TEXT
keybindLabel.TextScaled = true
keybindLabel.ZIndex = 1
keybindLabel.Parent = btn

-- ── Cooldown overlay (dark tint that sweeps down from top) ──
local cdOverlay = Instance.new("Frame")
cdOverlay.Name = "CooldownOverlay"
cdOverlay.Size = UDim2.fromScale(1, 0) -- 0 = ready, 1 = full cooldown
cdOverlay.Position = UDim2.fromScale(0, 0)
cdOverlay.AnchorPoint = Vector2.new(0, 0)
cdOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cdOverlay.BackgroundTransparency = 0.4
cdOverlay.BorderSizePixel = 0
cdOverlay.ZIndex = 2
cdOverlay.Parent = btn

local cdOverlayCorner = Instance.new("UICorner")
cdOverlayCorner.CornerRadius = UDim.new(0, px(14))
cdOverlayCorner.Parent = cdOverlay

-- Cooldown number – large, centred over entire button
local cdText = Instance.new("TextLabel")
cdText.Name = "CooldownText"
cdText.AnchorPoint = Vector2.new(0.5, 0.5)
cdText.Size = UDim2.fromScale(0.78, 0.5)
cdText.Position = UDim2.fromScale(0.5, 0.47)
cdText.BackgroundTransparency = 1
cdText.Text = ""
cdText.Font = Enum.Font.GothamBold
cdText.TextColor3 = WHITE
cdText.TextScaled = true
cdText.TextTransparency = 1
cdText.ZIndex = 3
cdText.Parent = btn

--------------------------------------------------------------------------------
-- BUTTON VISUAL FEEDBACK
--------------------------------------------------------------------------------
local function setButtonReady()
    btn.BackgroundColor3 = getTeamTintFill(currentTeamColor)
    btnStroke.Color = GOLD_DIM
    iconLabel.TextColor3 = GOLD
    dashLabel.TextColor3 = WHITE
end

local function setButtonCooldown()
    btn.BackgroundColor3 = DISABLED_BG
    btnStroke.Color = Color3.fromRGB(60, 62, 80)
    iconLabel.TextColor3 = DIM_TEXT
    dashLabel.TextColor3 = DIM_TEXT
end

local function setButtonPressed()
    btn.BackgroundColor3 = getTeamTintPressedFill(currentTeamColor)
end

-- Hover (desktop only)
if not UserInputService.TouchEnabled then
    btn.MouseEnter:Connect(function()
        if not isCoolingDown then
            TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = getTeamTintHoverFill(currentTeamColor) }):Play()
            TweenService:Create(btnStroke, TweenInfo.new(0.12), { Color = GOLD }):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if not isCoolingDown then
            TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = getTeamTintFill(currentTeamColor) }):Play()
            TweenService:Create(btnStroke, TweenInfo.new(0.12), { Color = GOLD_DIM }):Play()
        end
    end)
end

--------------------------------------------------------------------------------
-- COOLDOWN DISPLAY
--------------------------------------------------------------------------------
local cooldownConn = nil

local function startCooldownUI()
    isCoolingDown = true
    cooldownEnd = tick() + DashConfig.Cooldown
    setButtonCooldown()

    cdOverlay.Size = UDim2.fromScale(1, 1)
    cdText.TextTransparency = 0
    cdText.Text = tostring(math.ceil(DashConfig.Cooldown))

    -- Disconnect old connection if somehow still active
    if cooldownConn then cooldownConn:Disconnect() end

    cooldownConn = RunService.Heartbeat:Connect(function()
        local remaining = cooldownEnd - tick()
        if remaining <= 0 then
            isCoolingDown = false
            cdOverlay.Size = UDim2.fromScale(1, 0)
            cdText.TextTransparency = 1
            cdText.Text = ""
            setButtonReady()
            if cooldownConn then cooldownConn:Disconnect(); cooldownConn = nil end
            return
        end

        -- Overlay shrinks from full to 0 as cooldown expires
        local frac = remaining / DashConfig.Cooldown
        cdOverlay.Size = UDim2.fromScale(1, math.clamp(frac, 0, 1))
        cdText.Text = tostring(math.ceil(remaining))
    end)
end

local function resetCooldownUI()
    isCoolingDown = false
    cooldownEnd = 0
    cdOverlay.Size = UDim2.fromScale(1, 0)
    cdText.TextTransparency = 1
    cdText.Text = ""
    setButtonReady()
    if cooldownConn then cooldownConn:Disconnect(); cooldownConn = nil end
end

--------------------------------------------------------------------------------
-- VISUAL EFFECTS
--------------------------------------------------------------------------------
local function getEffectColorForPlayer(_targetPlayer)
    -- Always return the default white trail color; team color no longer affects dash trails.
    -- Equipped cosmetic color is provided by the server via PlayDashVFX RGB args.
    return DashConfig.DefaultEffectColor  -- white (255,255,255)
end

local function playDashEffects(targetPlayer, effectId)
    if not DashConfig.EffectEnabled then return end
    if not targetPlayer or not targetPlayer:IsA("Player") then return end
    local char = targetPlayer.Character
    if not char then return end
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Resolve effect definition from EffectDefs
    local def = EffectDefs and EffectDefs.GetById(effectId or "DefaultTrail")
    if not def then
        def = EffectDefs and EffectDefs.GetById("DefaultTrail")
    end

    -- Determine trail color or color sequence
    local isRainbow = def and def.IsRainbow
    local trailColorSeq
    local solidColor
    if isRainbow and def.TrailColorSequence then
        trailColorSeq = def.TrailColorSequence
        solidColor = def.Color or Color3.fromRGB(180, 120, 255)
        log("[Dash] Using Rainbow Trail sequence")
    else
        solidColor = (def and def.Color) or DashConfig.DefaultEffectColor
        trailColorSeq = ColorSequence.new(solidColor, solidColor)
        log("[Dash] Using", (def and def.DisplayName or "Default Trail"), "visuals")
    end
    local duration = DashConfig.Duration

    -- Cleanup stale transient dash VFX before spawning fresh ones.
    for _, child in ipairs(rootPart:GetChildren()) do
        if child.Name == "_DashTrailA0"
            or child.Name == "_DashTrailA1"
            or child.Name == "_DashTrail"
            or child.Name == "_DashParticleAttach"
            or child.Name == "_DashStreaks" then
            pcall(function() child:Destroy() end)
        end
    end

    -------------------------------------------------------
    -- 1) Trail effect
    -------------------------------------------------------
    local trailAttach0 = Instance.new("Attachment")
    trailAttach0.Name = "_DashTrailA0"
    trailAttach0.Position = Vector3.new(0, 0.8, 0)
    trailAttach0.Parent = rootPart

    local trailAttach1 = Instance.new("Attachment")
    trailAttach1.Name = "_DashTrailA1"
    trailAttach1.Position = Vector3.new(0, -1.5, 0)
    trailAttach1.Parent = rootPart

    local trail = Instance.new("Trail")
    trail.Name = "_DashTrail"
    trail.Attachment0 = trailAttach0
    trail.Attachment1 = trailAttach1
    trail.Color = trailColorSeq

    -- Dark trails (e.g. Black Trail) need lower LightEmission and less
    -- starting transparency so the dark color reads clearly in gameplay.
    local isDarkTrail = (not isRainbow) and solidColor
        and (solidColor.R + solidColor.G + solidColor.B) < 0.75

    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, isRainbow and 0.2 or (isDarkTrail and 0.1 or 0.3)),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = isRainbow and (DashConfig.TrailLifetime * 1.15) or DashConfig.TrailLifetime
    trail.MinLength = 0.05
    trail.FaceCamera = true
    trail.LightEmission = isRainbow and 0.7 or (isDarkTrail and 0.08 or 0.6)
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, isRainbow and 0.4 or 0.3),
    })
    trail.Parent = rootPart

    Debris:AddItem(trail, duration + DashConfig.TrailLifetime + 0.1)
    Debris:AddItem(trailAttach0, duration + DashConfig.TrailLifetime + 0.15)
    Debris:AddItem(trailAttach1, duration + DashConfig.TrailLifetime + 0.15)

    -------------------------------------------------------
    -- 2) Speed-streak particles
    -------------------------------------------------------
    local particleAttach = Instance.new("Attachment")
    particleAttach.Name = "_DashParticleAttach"
    particleAttach.Parent = rootPart

    local particles = Instance.new("ParticleEmitter")
    particles.Name = "_DashStreaks"
    particles.Color = isRainbow and trailColorSeq or ColorSequence.new(solidColor)
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 0),
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, isRainbow and 0.15 or 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    particles.Lifetime = NumberRange.new(0.15, 0.3)
    particles.Speed = NumberRange.new(8, 15)
    particles.SpreadAngle = Vector2.new(15, 15)
    particles.Rate = 0 -- controlled by Emit()
    particles.LightEmission = 0.5
    particles.LockedToPart = false
    -- Emit backwards from movement direction
    local lookDir = rootPart.CFrame.LookVector
    particles.EmissionDirection = Enum.NormalId.Back
    particles.Parent = particleAttach

    particles:Emit(DashConfig.ParticleCount)

    Debris:AddItem(particles, 1)
    Debris:AddItem(particleAttach, 1.05)

    -------------------------------------------------------
    -- 3) Afterimage ghost
    -------------------------------------------------------
    task.spawn(function()
        local ghostModel = Instance.new("Model")
        ghostModel.Name = "_DashGhost_" .. tostring(targetPlayer.UserId)

        -- For rainbow, cycle ghost part colors through the palette
        local ghostColors = (isRainbow and def.GhostColors) or nil
        local ghostIdx = 0

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local ghost = part:Clone()
                -- Strip scripts, welds, attachments to keep it clean
                for _, child in ipairs(ghost:GetChildren()) do
                    if not child:IsA("SpecialMesh") and not child:IsA("MeshPart")
                       and not child:IsA("DataModelMesh") then
                        pcall(function() child:Destroy() end)
                    end
                end
                ghost.Anchored = true
                ghost.CanCollide = false
                ghost.CanQuery = false
                ghost.CanTouch = false
                ghost.CastShadow = false
                ghost.Transparency = isRainbow and (DashConfig.GhostTransparency - 0.05) or DashConfig.GhostTransparency
                ghost.Material = Enum.Material.Neon
                if ghostColors then
                    ghostIdx = ghostIdx + 1
                    ghost.Color = ghostColors[((ghostIdx - 1) % #ghostColors) + 1]
                else
                    ghost.Color = solidColor
                end
                ghost.Parent = ghostModel
            end
        end

        ghostModel.Parent = workspace
        Debris:AddItem(ghostModel, DashConfig.GhostFadeDuration + 0.1)

        -- Fade out
        local fadeInfo = TweenInfo.new(DashConfig.GhostFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        for _, part in ipairs(ghostModel:GetDescendants()) do
            if part:IsA("BasePart") then
                TweenService:Create(part, fadeInfo, { Transparency = 1 }):Play()
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- DASH ANIMATION
--------------------------------------------------------------------------------
local loadedAnim = nil
local animTrack  = nil

local function playDashAnimation()
    if not DashConfig.AnimationId or DashConfig.AnimationId == "" then return end
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        if not loadedAnim then
            loadedAnim = Instance.new("Animation")
            loadedAnim.AnimationId = DashConfig.AnimationId
        end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            animTrack = animator:LoadAnimation(loadedAnim)
            animTrack.Priority = Enum.AnimationPriority.Action
            animTrack:Play(0.05)
            -- Auto-stop after dash duration
            task.delay(DashConfig.Duration + 0.05, function()
                if animTrack and animTrack.IsPlaying then
                    animTrack:Stop(0.1)
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- CORE DASH REQUEST
--------------------------------------------------------------------------------
local function requestDashAction()
    if isCoolingDown then return end
    if isDashing then return end
    -- Cancel bandage if player tries to dash
    if _G.IsBandaging then return end

    -- Quick client-side sanity
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    isDashing = true

    -- Optimistic: start cooldown UI immediately for responsiveness
    startCooldownUI()

    -- Fire to server
    requestDash:FireServer()
    log("dash requested")
end

--------------------------------------------------------------------------------
-- SERVER RESPONSES
--------------------------------------------------------------------------------
dashApproved.OnClientEvent:Connect(function()
    log("dash approved")
    isDashing = false
    -- VFX now comes from PlayDashVFX broadcast so all clients see the same dash.
    playDashAnimation()
    -- Flash button briefly to give feedback
    task.spawn(function()
        setButtonPressed()
        task.wait(0.1)
        if isCoolingDown then
            setButtonCooldown()
        end
    end)
end)

if playDashVFX then
    playDashVFX.OnClientEvent:Connect(function(dashingPlayer, effectId)
        if not dashingPlayer or not dashingPlayer:IsA("Player") then return end
        print("[DashClient] received dash VFX for", dashingPlayer.Name,
            "trail:", effectId or "DefaultTrail")
        playDashEffects(dashingPlayer, effectId)
    end)
else
    warn("[DashClient] PlayDashVFX remote missing; dash VFX visibility may be local-only")
end

if dashRejected then
    dashRejected.OnClientEvent:Connect(function(reason)
        log("dash rejected:", reason)
        isDashing = false
        -- If server rejected, reset the optimistic cooldown
        if reason ~= "cooldown" then
            resetCooldownUI()
        end
    end)
end

-- Keep dash button fill synced to current team at runtime (no respawn needed)
currentTeamColor = teamColorOrNil(player.Team)
setButtonReady()
player:GetPropertyChangedSignal("Team"):Connect(function()
    currentTeamColor = teamColorOrNil(player.Team)
    if isCoolingDown then
        setButtonCooldown()
    else
        setButtonReady()
    end
end)

--------------------------------------------------------------------------------
-- INPUT: BUTTON CLICK
--------------------------------------------------------------------------------
btn.MouseButton1Click:Connect(function()
    requestDashAction()
end)

-- Also support touch
btn.TouchTap:Connect(function()
    requestDashAction()
end)

--------------------------------------------------------------------------------
-- INPUT: LEFT SHIFT KEY
--------------------------------------------------------------------------------
local shiftHeld = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Don't fire while typing in chat / textboxes
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.LeftShift then
        if shiftHeld then return end -- prevent repeat-fire while held
        shiftHeld = true
        requestDashAction()
    end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        shiftHeld = false
    end
end)

--------------------------------------------------------------------------------
-- RESPAWN HANDLING
-- Animation cache should be cleared when character respawns
--------------------------------------------------------------------------------
player.CharacterAdded:Connect(function()
    isDashing = false
    loadedAnim = nil
    animTrack = nil
end)

log("ready")
