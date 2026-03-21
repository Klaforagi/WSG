--------------------------------------------------------------------------------
-- BandageClient.client.lua
-- Client-side bandage utility: input handling, progress bar, cooldown visuals,
-- interruption detection, and hotbar slot 3 integration.
--
-- StarterPlayerScripts — persists across respawns (ResetOnSpawn = false).
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- LOAD CONFIG
--------------------------------------------------------------------------------
local BandageConfig
do
    local mod = ReplicatedStorage:WaitForChild("BandageConfig", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then BandageConfig = result end
    end
end
if not BandageConfig then
    warn("[BandageClient] BandageConfig not found – using defaults")
    BandageConfig = {
        CastDuration = 6, TickInterval = 1.5, HealPerTick = 10,
        MaxTotalHeal = 40, Cooldown = 20, MoveThreshold = 1.5,
    }
end

--------------------------------------------------------------------------------
-- WAIT FOR REMOTES
--------------------------------------------------------------------------------
local requestBandage  = ReplicatedStorage:WaitForChild("RequestBandage", 10)
local cancelBandage   = ReplicatedStorage:WaitForChild("CancelBandage", 10)
local bandageStarted  = ReplicatedStorage:WaitForChild("BandageStarted", 10)
local bandageHealTick = ReplicatedStorage:WaitForChild("BandageHealTick", 10)
local bandageEnded    = ReplicatedStorage:WaitForChild("BandageEnded", 10)
local bandageCooldown = ReplicatedStorage:WaitForChild("BandageCooldown", 10)

if not requestBandage or not bandageStarted then
    warn("[BandageClient] Bandage remotes not found – bandage disabled")
    return
end

--------------------------------------------------------------------------------
-- PALETTE (consistent with KingsGround navy + gold theme)
--------------------------------------------------------------------------------
local NAVY       = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT = Color3.fromRGB(22, 26, 48)
local GOLD       = Color3.fromRGB(255, 215, 80)
local GOLD_DIM   = Color3.fromRGB(180, 150, 50)
local GREEN      = Color3.fromRGB(35, 190, 75)
local RED        = Color3.fromRGB(255, 80, 80)
local BLUE_FILL  = Color3.fromRGB(65, 130, 255)
local WHITE      = Color3.fromRGB(255, 255, 255)

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local isBandaging   = false
local isCoolingDown = false
local cooldownEnd   = 0
local startPosition = nil
local castStartTime = 0
local renderConn    = nil  -- RenderStepped connection for progress bar
local interruptConns = {}  -- connections to disconnect on stop

-- Expose bandaging state globally so other scripts can check
_G.IsBandaging = false

--------------------------------------------------------------------------------
-- RESPONSIVE SCALING
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 100 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- PROCEDURAL BANDAGE ANIMATION CONTROLLER
-- Manipulates Motor6D.Transform on shoulder joints to create a visible
-- "wrapping / rubbing hands" pose without needing an uploaded Animation asset.
-- Works on R15 rigs.  R6 is handled gracefully (no-ops).
--
-- IMPORTANT: Uses BindToRenderStep at priority AFTER Roblox's Animator
-- (Enum.RenderPriority.Character.Value + 1) so our transforms are NOT
-- overwritten by the default idle/walk animation system.
--------------------------------------------------------------------------------

-- ══════════════════════════════════════════════════════════════════════════════
-- TUNING CONSTANTS (adjust these to taste once the anim is confirmed working)
-- ══════════════════════════════════════════════════════════════════════════════
local BASE_SHOULDER_INWARD_ANGLE  = 55   -- degrees – how far arms rotate inward
local BASE_SHOULDER_FORWARD_ANGLE = 70   -- degrees – how far arms pitch forward
local BASE_ELBOW_BEND             = 75   -- degrees – forearm bend
local BASE_WAIST_LEAN             = 12   -- degrees – torso forward lean
local LOOP_AMPLITUDE              = 15   -- degrees – oscillation range on top of base
local LOOP_SPEED                  = 3.5  -- Hz – primary oscillation frequency
local LOOP_SECONDARY_SPEED        = 7.0  -- Hz – secondary wobble frequency
local LOOP_SECONDARY_SCALE        = 0.35 -- multiplier for secondary wave
local RENDER_STEP_NAME            = "BandageProceduralAnim"
local RENDER_STEP_PRIORITY        = Enum.RenderPriority.Character.Value + 1

local bandageAnimActive = false  -- true while the procedural loop is bound
local bandageAnimTime   = 0     -- accumulated time for sinusoidal motion
local bandageAnimJoints = {}    -- {RightShoulder, LeftShoulder, RightElbow, LeftElbow, Waist}

-- Robustly finds Motor6D descendants by name anywhere inside the character.
-- Uses FindFirstChild with recursive=true so it works regardless of hierarchy.
local function findR15Joints(char)
    local joints = {}
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("Motor6D") then
            local n = desc.Name
            if n == "RightShoulder" then joints.RightShoulder = desc
            elseif n == "LeftShoulder" then joints.LeftShoulder = desc
            elseif n == "RightElbow" then joints.RightElbow = desc
            elseif n == "LeftElbow" then joints.LeftElbow = desc
            elseif n == "Waist" then joints.Waist = desc
            end
        end
    end
    -- Debug: report what we found
    print("[BandageAnim] findR15Joints results:")
    print("  RightShoulder:", joints.RightShoulder and joints.RightShoulder:GetFullName() or "NOT FOUND")
    print("  LeftShoulder: ", joints.LeftShoulder and joints.LeftShoulder:GetFullName() or "NOT FOUND")
    print("  RightElbow:   ", joints.RightElbow and joints.RightElbow:GetFullName() or "NOT FOUND")
    print("  LeftElbow:    ", joints.LeftElbow and joints.LeftElbow:GetFullName() or "NOT FOUND")
    print("  Waist:        ", joints.Waist and joints.Waist:GetFullName() or "NOT FOUND")
    return joints
end

local function resetJointTransforms()
    for name, motor in pairs(bandageAnimJoints) do
        if motor and motor.Parent then
            motor.Transform = CFrame.new()
            print("[BandageAnim] reset Transform on", name)
        end
    end
    bandageAnimJoints = {}
end

local function startBandageProceduralAnim()
    print("[BandageAnim] start requested")

    -- Prevent duplicate loops
    if bandageAnimActive then
        print("[BandageAnim] already active, skipping duplicate start")
        return
    end

    local char = player.Character
    if not char then
        warn("[BandageAnim] no Character – anim skipped")
        return
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then
        warn("[BandageAnim] no Humanoid – anim skipped")
        return
    end

    -- Detect rig type
    local rigType = hum.RigType
    print("[BandageAnim] rig type:", tostring(rigType))
    if rigType ~= Enum.HumanoidRigType.R15 then
        warn("[BandageAnim] unsupported rig / not R15 – procedural anim skipped")
        return
    end

    local joints = findR15Joints(char)
    if not joints.RightShoulder or not joints.LeftShoulder then
        warn("[BandageAnim] R15 shoulder joints not found – procedural anim skipped")
        return
    end
    print("[BandageAnim] found R15 shoulders ✓")
    bandageAnimJoints = joints
    bandageAnimTime = 0
    bandageAnimActive = true

    -- BindToRenderStep at priority AFTER the Animator so our transforms stick.
    -- This is the critical fix: RenderStepped:Connect runs at default priority
    -- which the Animator can overwrite. BindToRenderStep with priority
    -- Character+1 runs AFTER the Animator finishes writing transforms.
    print("[BandageAnim] BindToRenderStep connected (priority", RENDER_STEP_PRIORITY, ")")
    RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_STEP_PRIORITY, function(dt)
        -- Safety: bail if joints became invalid (respawn, etc.)
        if not bandageAnimActive then return end
        if not joints.RightShoulder or not joints.RightShoulder.Parent then
            print("[BandageAnim] joints lost mid-loop, stopping")
            stopBandageProceduralAnim()
            return
        end

        bandageAnimTime = bandageAnimTime + dt
        local t = bandageAnimTime

        -- ── Oscillation wave components ──────────────────────────────────
        local wave1 = math.sin(t * LOOP_SPEED)
        local wave2 = math.sin(t * LOOP_SECONDARY_SPEED) * LOOP_SECONDARY_SCALE
        local combined = wave1 + wave2  -- range roughly -1.35 .. 1.35

        -- ── RIGHT SHOULDER (bring arm inward + forward) ─────────────────
        local rPitch = math.rad(-BASE_SHOULDER_FORWARD_ANGLE + combined * LOOP_AMPLITUDE)
        local rYaw   = math.rad(-BASE_SHOULDER_INWARD_ANGLE + combined * (LOOP_AMPLITUDE * 0.6))
        local rRoll  = math.rad(15)
        if joints.RightShoulder and joints.RightShoulder.Parent then
            joints.RightShoulder.Transform = CFrame.Angles(rPitch, rYaw, rRoll)
        end

        -- ── LEFT SHOULDER (mirror, offset phase so arms alternate) ──────
        local lWave1 = math.sin(t * LOOP_SPEED + 1.0)
        local lWave2 = math.sin(t * LOOP_SECONDARY_SPEED + 1.0) * LOOP_SECONDARY_SCALE
        local lCombined = lWave1 + lWave2

        local lPitch = math.rad(-BASE_SHOULDER_FORWARD_ANGLE + lCombined * LOOP_AMPLITUDE)
        local lYaw   = math.rad(BASE_SHOULDER_INWARD_ANGLE - lCombined * (LOOP_AMPLITUDE * 0.6))
        local lRoll  = math.rad(-15)
        if joints.LeftShoulder and joints.LeftShoulder.Parent then
            joints.LeftShoulder.Transform = CFrame.Angles(lPitch, lYaw, lRoll)
        end

        -- ── Elbows (bend forearms inward) ────────────────────────────────
        if joints.RightElbow and joints.RightElbow.Parent then
            joints.RightElbow.Transform = CFrame.Angles(math.rad(-BASE_ELBOW_BEND + combined * (LOOP_AMPLITUDE * 0.7)), 0, 0)
        end
        if joints.LeftElbow and joints.LeftElbow.Parent then
            joints.LeftElbow.Transform = CFrame.Angles(math.rad(-BASE_ELBOW_BEND + lCombined * (LOOP_AMPLITUDE * 0.7)), 0, 0)
        end

        -- ── Waist (forward lean) ─────────────────────────────────────────
        if joints.Waist and joints.Waist.Parent then
            joints.Waist.Transform = CFrame.Angles(math.rad(-BASE_WAIST_LEAN + math.sin(t * 2.0) * 3), 0, 0)
        end
    end)
    print("[BandageAnim] procedural anim STARTED – applying transforms")
end

local function stopBandageProceduralAnim()
    print("[BandageAnim] stop requested (was active:", bandageAnimActive, ")")
    if bandageAnimActive then
        -- Unbind the render step callback
        pcall(function() RunService:UnbindFromRenderStep(RENDER_STEP_NAME) end)
        print("[BandageAnim] UnbindFromRenderStep done")
    end
    bandageAnimActive = false
    resetJointTransforms()
    bandageAnimTime = 0
    print("[BandageAnim] procedural anim STOPPED and transforms reset")
end

-- Convenience aliases matching old naming so hook sites stay clean
local playBandageAnimation = startBandageProceduralAnim
local stopBandageAnimation = stopBandageProceduralAnim

--------------------------------------------------------------------------------
-- PROGRESS BAR UI
--------------------------------------------------------------------------------
local progressGui = Instance.new("ScreenGui")
progressGui.Name           = "BandageProgressUI"
progressGui.ResetOnSpawn   = false
progressGui.IgnoreGuiInset = true
progressGui.DisplayOrder   = 15
progressGui.Enabled        = false
progressGui.Parent         = playerGui

-- ── Cast bar sizing constants ─────────────────────────────────────────────
local BAR_WIDTH       = 0.20          -- fraction of screen width
local BAR_HEIGHT_BASE = 24            -- base px height (scaled via px())
local BAR_INSET_BASE  = 3             -- internal padding for fill
local BAR_CORNER_BASE = 6             -- rounded corners
local BAR_Y           = 0.81          -- vertical anchor (above hotbar)

-- Resolved pixel sizes (recalculated every time the bar is shown)
local barHeight  = px(BAR_HEIGHT_BASE)
local barInset   = px(BAR_INSET_BASE)
local barCornerR = px(BAR_CORNER_BASE)

-- Container frame
local barContainer = Instance.new("Frame")
barContainer.Name                   = "BarContainer"
barContainer.AnchorPoint            = Vector2.new(0.5, 1)
barContainer.Position               = UDim2.new(0.5, 0, BAR_Y, 0)
barContainer.Size                   = UDim2.new(BAR_WIDTH, 0, 0, barHeight)
barContainer.BackgroundColor3       = NAVY
barContainer.BackgroundTransparency = 0.08
barContainer.BorderSizePixel        = 0
barContainer.Parent                 = progressGui

local barCorner = Instance.new("UICorner", barContainer)
barCorner.CornerRadius = UDim.new(0, barCornerR)

local barStroke = Instance.new("UIStroke", barContainer)
barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
barStroke.Color           = GOLD
barStroke.Thickness       = px(2)

-- Fill bar (inset inside the container)
local fillBar = Instance.new("Frame")
fillBar.Name                   = "Fill"
fillBar.AnchorPoint            = Vector2.new(0, 0.5)
fillBar.Position               = UDim2.new(0, barInset, 0.5, 0)
fillBar.Size                   = UDim2.new(0, 0, 0, barHeight - barInset * 2)
fillBar.BackgroundColor3       = BLUE_FILL
fillBar.BackgroundTransparency = 0
fillBar.BorderSizePixel        = 0
fillBar.Parent                 = barContainer

local fillCorner = Instance.new("UICorner", fillBar)
fillCorner.CornerRadius = UDim.new(0, math.max(1, barCornerR - 2))

-- A subtle inner gradient on the fill to give it depth
local fillGradient = Instance.new("UIGradient", fillBar)
fillGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 155, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 100, 220)),
})
fillGradient.Rotation = 90

-- "Bandaging..." label – sits on top of the fill, always readable
local castLabel = Instance.new("TextLabel")
castLabel.Name                   = "CastLabel"
castLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
castLabel.Position               = UDim2.fromScale(0.5, 0.5)
castLabel.Size                   = UDim2.new(0.92, 0, 0, barHeight - barInset * 2)
castLabel.BackgroundTransparency = 1
castLabel.Text                   = "Bandaging..."
castLabel.Font                   = Enum.Font.GothamBold
castLabel.TextScaled             = true
castLabel.TextColor3             = WHITE
castLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
castLabel.TextStrokeTransparency = 0.45
castLabel.ZIndex                 = 2
castLabel.Parent                 = barContainer

-- Status text (shows briefly on interrupt/complete) – positioned above the bar
local statusLabel = Instance.new("TextLabel")
statusLabel.Name                   = "StatusLabel"
statusLabel.AnchorPoint            = Vector2.new(0.5, 1)
statusLabel.Position               = UDim2.new(0.5, 0, BAR_Y, -barHeight - px(4))
statusLabel.Size                   = UDim2.new(BAR_WIDTH, 0, 0, px(20))
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = ""
statusLabel.Font                   = Enum.Font.GothamBold
statusLabel.TextScaled             = true
statusLabel.TextColor3             = RED
statusLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Parent                 = progressGui
statusLabel.Visible                = false

--------------------------------------------------------------------------------
-- HEAL POPUP
--------------------------------------------------------------------------------
local function showHealPopup(amount)
    local gui = Instance.new("ScreenGui")
    gui.Name           = "HealPopup"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 20
    gui.Parent         = playerGui

    local label = Instance.new("TextLabel")
    label.AnchorPoint            = Vector2.new(0.5, 0.5)
    label.Position               = UDim2.new(0.5, math.random(-30, 30), 0.45, 0)
    label.Size                   = UDim2.new(0, px(80), 0, px(24))
    label.BackgroundTransparency = 1
    label.Text                   = "+" .. tostring(math.floor(amount)) .. " HP"
    label.Font                   = Enum.Font.GothamBold
    label.TextScaled             = true
    label.TextColor3             = GREEN
    label.TextStrokeColor3       = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.5
    label.Parent                 = gui

    -- Float upward and fade out
    local tween = TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = label.Position + UDim2.new(0, 0, -0.04, 0),
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })
    tween:Play()
    tween.Completed:Connect(function()
        gui:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- STATUS MESSAGE (brief flash)
--------------------------------------------------------------------------------
local function showStatusMessage(text, color)
    statusLabel.Text       = text
    statusLabel.TextColor3 = color or RED
    statusLabel.Visible    = true
    task.delay(1.5, function()
        statusLabel.Visible = false
    end)
end

--------------------------------------------------------------------------------
-- PROGRESS BAR CONTROL
--------------------------------------------------------------------------------
-- Recalculate bar pixel sizes (handles late camera initialization)
local function recalcBarSizes()
    barHeight  = px(BAR_HEIGHT_BASE)
    barInset   = px(BAR_INSET_BASE)
    barCornerR = px(BAR_CORNER_BASE)

    barContainer.Size             = UDim2.new(BAR_WIDTH, 0, 0, barHeight)
    barCorner.CornerRadius        = UDim.new(0, barCornerR)
    barStroke.Thickness           = px(2)
    fillBar.Position              = UDim2.new(0, barInset, 0.5, 0)
    fillCorner.CornerRadius       = UDim.new(0, math.max(1, barCornerR - 2))
    castLabel.Size                = UDim2.new(0.92, 0, 0, barHeight - barInset * 2)
    statusLabel.Position          = UDim2.new(0.5, 0, BAR_Y, -barHeight - px(4))
    statusLabel.Size              = UDim2.new(BAR_WIDTH, 0, 0, px(20))
    -- DEBUG: uncomment to verify bar dimensions at runtime
    -- print("[BandageBar] recalc  barHeight =", barHeight, "AbsoluteSize =", barContainer.AbsoluteSize)
end

local function showProgressBar()
    recalcBarSizes()
    castLabel.Text = "Bandaging..."
    fillBar.Size = UDim2.new(0, 0, 0, barHeight - barInset * 2)
    progressGui.Enabled = true
    castStartTime = tick()

    -- Smooth fill via RenderStepped
    if renderConn then renderConn:Disconnect() end
    renderConn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - castStartTime
        local pct = math.clamp(elapsed / BandageConfig.CastDuration, 0, 1)
        local maxWidth = barContainer.AbsoluteSize.X - barInset * 2
        fillBar.Size = UDim2.new(0, maxWidth * pct, 0, barHeight - barInset * 2)
        -- Update label with remaining time
        local remaining = math.max(0, BandageConfig.CastDuration - elapsed)
        castLabel.Text = string.format("Bandaging...  %.1fs", remaining)
    end)
end

local function hideProgressBar()
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    progressGui.Enabled = false
    fillBar.Size = UDim2.new(0, 0, 0, 0)
end

--------------------------------------------------------------------------------
-- INTERRUPT DETECTION (client-side for responsiveness)
--------------------------------------------------------------------------------
local function disconnectInterruptListeners()
    for _, conn in ipairs(interruptConns) do
        pcall(function() conn:Disconnect() end)
    end
    interruptConns = {}
end

local function cancelBandaging(reason)
    if not isBandaging then return end
    print("[BandageAnim] cancelBandaging called, reason:", reason)
    isBandaging = false
    _G.IsBandaging = false

    stopBandageAnimation()
    hideProgressBar()
    disconnectInterruptListeners()

    -- Tell server
    if cancelBandage then
        cancelBandage:FireServer()
    end

    if reason == "interrupted" then
        showStatusMessage("Bandage Interrupted", RED)
    elseif reason == "full_hp" then
        showStatusMessage("Health Full", GREEN)
    end
end

local function setupInterruptListeners()
    disconnectInterruptListeners()

    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    startPosition = hrp.Position

    -- Movement detection (check every frame)
    table.insert(interruptConns, RunService.Heartbeat:Connect(function()
        if not isBandaging then return end
        if not hrp or not hrp.Parent then
            cancelBandaging("interrupted")
            return
        end
        -- Check position drift
        local dist = (hrp.Position - startPosition).Magnitude
        if dist > BandageConfig.MoveThreshold then
            cancelBandaging("interrupted")
            return
        end
        -- Check MoveDirection (WASD)
        if hum.MoveDirection.Magnitude > 0.1 then
            cancelBandaging("interrupted")
            return
        end
    end))

    -- Jump detection
    table.insert(interruptConns, hum:GetPropertyChangedSignal("Jump"):Connect(function()
        if hum.Jump and isBandaging then
            cancelBandaging("interrupted")
        end
    end))

    -- Also detect FloorMaterial going to Air (jump/fall)
    table.insert(interruptConns, hum.StateChanged:Connect(function(_, newState)
        if not isBandaging then return end
        if newState == Enum.HumanoidStateType.Jumping
            or newState == Enum.HumanoidStateType.Freefall then
            cancelBandaging("interrupted")
        end
    end))

    -- Damage detection (health going down)
    local prevHealth = hum.Health
    table.insert(interruptConns, hum.HealthChanged:Connect(function(newHealth)
        if not isBandaging then return end
        if newHealth < prevHealth - 0.1 then
            -- Took damage (not from our healing)
            cancelBandaging("interrupted")
        end
        prevHealth = math.max(newHealth, prevHealth) -- ratchet up for heal ticks
    end))

    -- Death
    table.insert(interruptConns, hum.Died:Connect(function()
        cancelBandaging("died")
    end))

    -- Tool equipping (weapon switch)
    table.insert(interruptConns, char.ChildAdded:Connect(function(child)
        if not isBandaging then return end
        if child:IsA("Tool") then
            cancelBandaging("interrupted")
        end
    end))

    -- Input detection for attacks / dash / weapon switch
    table.insert(interruptConns, UserInputService.InputBegan:Connect(function(input, processed)
        if not isBandaging then return end
        if processed then return end
        local kc = input.KeyCode
        -- Keys 1, 2 = weapon switch
        if kc == Enum.KeyCode.One or kc == Enum.KeyCode.Two then
            cancelBandaging("interrupted")
            return
        end
        -- LeftShift = dash
        if kc == Enum.KeyCode.LeftShift then
            cancelBandaging("interrupted")
            return
        end
        -- Mouse click = attack attempt
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            cancelBandaging("interrupted")
            return
        end
    end))
end

--------------------------------------------------------------------------------
-- COOLDOWN HANDLING
--------------------------------------------------------------------------------
local function startClientCooldown(duration)
    isCoolingDown = true
    cooldownEnd = tick() + duration

    -- Use the hotbar cooldown overlay system for slot 3
    if _G.HotbarCooldown and _G.HotbarCooldown.start then
        _G.HotbarCooldown.start(3, duration)
    end

    -- Also start the numeric countdown on slot 3
    if _G.HotbarCooldown and _G.HotbarCooldown.startCountdown then
        _G.HotbarCooldown.startCountdown(3, duration)
    end

    task.delay(duration, function()
        if tick() >= cooldownEnd - 0.1 then
            isCoolingDown = false
        end
    end)
end

--------------------------------------------------------------------------------
-- ACTIVATE BANDAGE (called by hotbar slot 3 click or key 3)
--------------------------------------------------------------------------------
local function activateBandage()
    print("[BandageAnim] activateBandage called")
    if isBandaging then print("[BandageAnim] already bandaging, returning") return end
    if isCoolingDown then print("[BandageAnim] on cooldown, returning") return end

    local char = player.Character
    if not char then print("[BandageAnim] no character, returning") return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then print("[BandageAnim] no humanoid or dead, returning") return end

    -- Full health check
    if hum.Health >= hum.MaxHealth then
        print("[BandageAnim] health full, returning")
        showStatusMessage("Health Full", GREEN)
        return
    end

    print("[BandageAnim] requesting bandage from server")
    -- Unequip any held weapon first
    pcall(function() hum:UnequipTools() end)

    -- Request from server
    requestBandage:FireServer()
end

-- Expose activation function globally so Hotbar can call it
_G.ActivateBandage = activateBandage
-- Expose cancel function so other scripts (Hotbar weapon switch) can interrupt
_G.CancelBandage = function() cancelBandaging("interrupted") end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------
if bandageStarted then
    bandageStarted.OnClientEvent:Connect(function()
        print("[BandageAnim] ══ BandageStarted event received from server ══")
        isBandaging = true
        _G.IsBandaging = true
        playBandageAnimation()
        showProgressBar()
        setupInterruptListeners()
        print("[BandageAnim] bandage start sequence complete")
    end)
end

if bandageHealTick then
    bandageHealTick.OnClientEvent:Connect(function(newHealth, healAmount)
        if healAmount and healAmount > 0 then
            showHealPopup(healAmount)
        end
        -- Update the prev health ratchet for damage detection
        -- (handled internally via the HealthChanged connection)
    end)
end

if bandageEnded then
    bandageEnded.OnClientEvent:Connect(function(reason)
        print("[BandageAnim] ══ BandageEnded event received, reason:", reason, "══")
        local wasBandaging = isBandaging
        isBandaging = false
        _G.IsBandaging = false

        stopBandageAnimation()
        hideProgressBar()
        disconnectInterruptListeners()

        if wasBandaging then
            if reason == "interrupted" then
                showStatusMessage("Bandage Interrupted", RED)
            elseif reason == "full_hp" then
                showStatusMessage("Health Full", GREEN)
            elseif reason == "complete" then
                showStatusMessage("Bandage Complete", GREEN)
            end
        end
    end)
end

if bandageCooldown then
    bandageCooldown.OnClientEvent:Connect(function(duration)
        startClientCooldown(duration)
    end)
end

--------------------------------------------------------------------------------
-- RESPAWN CLEANUP
--------------------------------------------------------------------------------
player.CharacterAdded:Connect(function(newChar)
    print("[BandageAnim] CharacterAdded – cleaning up previous bandage state")
    -- Force-kill any procedural animation from previous life
    stopBandageProceduralAnim()

    isBandaging = false
    _G.IsBandaging = false
    isCoolingDown = false
    cooldownEnd = 0
    hideProgressBar()
    disconnectInterruptListeners()
    statusLabel.Visible = false

    -- Pre-validate joints on the new character so we know early if they exist
    task.defer(function()
        if newChar and newChar.Parent then
            local hum = newChar:FindFirstChildOfClass("Humanoid")
            if hum then
                print("[BandageAnim] new character rig type:", tostring(hum.RigType))
            end
            local testJoints = findR15Joints(newChar)
            if testJoints.RightShoulder and testJoints.LeftShoulder then
                print("[BandageAnim] new character has valid R15 shoulders ✓")
            else
                warn("[BandageAnim] new character MISSING R15 shoulders – anim will not work")
            end
        end
    end)
end)
