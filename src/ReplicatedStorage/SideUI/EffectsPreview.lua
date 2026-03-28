--------------------------------------------------------------------------------
-- EffectsPreview.lua  –  Client-side dash trail preview for Inventory Effects tab
--
-- Builds a preview rig posed mid-dash, then spawns coloured ribbon-parts
-- behind it as it oscillates to simulate the trail visually.
--
-- NOTE: Roblox Trail instances do NOT render inside ViewportFrames.
-- This module uses a part-based ribbon fallback that closely matches
-- the real trail's colour / transparency / fade behaviour.
--
-- Usage:  EffectsPreview.Update(viewportFrame, effectId)
--         EffectsPreview.Stop()
--------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DashConfig = require(ReplicatedStorage:WaitForChild("DashConfig"))

local EffectDefs
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
    if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
end)

local EffectsPreview = {}

local function dprint(...)
    print("[EffectsPreview]", ...)
end

--------------------------------------------------------------------------------
-- ACTIVE STATE
--------------------------------------------------------------------------------
local _activeConn   = nil   -- RenderStepped connection
local _activeWM     = nil   -- WorldModel reference
local _ribbonParts  = {}    -- { {part, spawnTime}, ... }
local _elapsed      = 0     -- clock tracked inside RenderStepped

--------------------------------------------------------------------------------
-- RIBBON CONFIGURATION  (preview-only — does NOT affect live gameplay)
--------------------------------------------------------------------------------
local RIBBON_LIFETIME    = 1.3     -- seconds each ribbon segment persists
local RIBBON_SPACING     = 0.10    -- studs of movement between spawns
local RIBBON_HEIGHT      = 2.3     -- matches attachment span  (0.8 to -1.5)
local RIBBON_THICKNESS   = 0.06    -- thin slab (depth toward camera)
local RIBBON_WIDTH       = 0.35    -- width perpendicular to camera view
local MAX_RIBBONS        = 60      -- safety cap

--------------------------------------------------------------------------------
-- MOTION / CAMERA CONFIGURATION
--------------------------------------------------------------------------------
-- Movement direction aligned with rig facing (160° Y rotation)
local MOVE_DIR   = Vector3.new(-0.781, 0, 0.625)
local BASE_POS   = Vector3.new(0, 3, 0)
local RIG_Y_ROT  = math.rad(160)
local DASH_DURATION = 1.0  -- seconds for one forward dash
local RESET_DELAY   = 0.5  -- pause at start before next dash
local CYCLE_TIME    = DASH_DURATION + RESET_DELAY
local SLIDE_DIST    = 3.0  -- studs total dash distance

local CAM_POS    = Vector3.new(2, 5, 7)
local CAM_TARGET = Vector3.new(0, 2.5, 0)
local CAM_FOV    = 50

-- Rainbow colours (from real TrailColorSequence keypoints)
local RAINBOW_COLORS = {
    Color3.fromRGB(255,  60,  60),   -- red
    Color3.fromRGB(255, 160,  40),   -- orange
    Color3.fromRGB(255, 230,  60),   -- yellow
    Color3.fromRGB( 40, 220,  80),   -- green
    Color3.fromRGB( 40, 210, 255),   -- cyan
    Color3.fromRGB( 60,  80, 255),   -- blue
    Color3.fromRGB(200,  60, 255),   -- magenta
}

--------------------------------------------------------------------------------
-- BUILD PREVIEW RIG  (reuses SkinPreview pattern)
--------------------------------------------------------------------------------
local function buildRig()
    local player = Players.LocalPlayer
    local character = player and player.Character

    -- Try HumanoidDescription first for a clean model
    if character then
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then
            local desc
            pcall(function() desc = hum:GetAppliedDescription() end)
            if desc then
                local ok, rig = pcall(function()
                    return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
                end)
                if ok and rig then
                    for _, d in ipairs(rig:GetDescendants()) do
                        if d:IsA("BaseScript") then d:Destroy() end
                    end
                    dprint("Built preview rig from HumanoidDescription")
                    return rig
                end
            end
        end
    end

    -- Fallback: clone character
    if character then
        local rig = character:Clone()
        for _, d in ipairs(rig:GetDescendants()) do
            if d:IsA("BaseScript") or d:IsA("BillboardGui") or d:IsA("ForceField") then
                d:Destroy()
            end
        end
        dprint("Built preview rig from character clone")
        return rig
    end

    dprint("No character available for preview")
    return nil
end

--------------------------------------------------------------------------------
-- POSE RIG IN DASH-LEAN
--------------------------------------------------------------------------------
local function poseDashLean(rig)
    local hrp = rig:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local function setJointAngle(jointName, partName, cf)
        local part = rig:FindFirstChild(partName)
        if not part then return end
        local joint = part:FindFirstChild(jointName) or part:FindFirstChildWhichIsA("Motor6D")
        if joint and joint:IsA("Motor6D") then
            joint.C0 = joint.C0 * cf
        end
    end

    setJointAngle("Root", "LowerTorso", CFrame.Angles(math.rad(18), 0, 0))
    setJointAngle("RightShoulder", "RightUpperArm", CFrame.Angles(math.rad(35), 0, 0))
    setJointAngle("LeftShoulder", "LeftUpperArm", CFrame.Angles(math.rad(-25), 0, 0))
    setJointAngle("RightHip", "RightUpperLeg", CFrame.Angles(math.rad(20), 0, 0))
    setJointAngle("LeftHip", "LeftUpperLeg", CFrame.Angles(math.rad(-15), 0, 0))
end

--------------------------------------------------------------------------------
-- RESOLVE TRAIL VISUAL CONFIG  (replaces createTrailOnRig)
--------------------------------------------------------------------------------
local function resolveTrailConfig(effectId)
    local def = EffectDefs and EffectDefs.GetById(effectId or "DefaultTrail")
    if not def then
        def = EffectDefs and EffectDefs.GetById("DefaultTrail")
    end
    if not def then
        dprint("WARN: No effect def found, using white fallback")
        return {
            color = Color3.fromRGB(255, 255, 255),
            isRainbow = false,
            isDark = false,
            baseTransparency = 0.25,
        }
    end

    local isRainbow = def.IsRainbow == true
    local solidColor = def.Color or DashConfig.DefaultEffectColor
    local isDark = (not isRainbow) and solidColor
        and (solidColor.R + solidColor.G + solidColor.B) < 0.75

    -- Preview-only: slightly more opaque than live for readability
    local baseTransp = isRainbow and 0.15 or (isDark and 0.05 or 0.25)

    dprint("Resolved trail config:", effectId,
        "| rainbow=", isRainbow, "| dark=", isDark, "| baseTransp=", baseTransp)

    return {
        color = solidColor,
        isRainbow = isRainbow,
        isDark = isDark,
        baseTransparency = baseTransp,
        rainbowColors = isRainbow and RAINBOW_COLORS or nil,
    }
end

--------------------------------------------------------------------------------
-- RIBBON MANAGEMENT
--------------------------------------------------------------------------------
local function cleanupAllRibbons()
    for _, entry in ipairs(_ribbonParts) do
        if entry.part and entry.part.Parent then
            entry.part:Destroy()
        end
    end
    _ribbonParts = {}
end

local function spawnRibbon(worldModel, ribbonPos, config, colorIndex)
    -- Determine colour
    local color
    if config.isRainbow and config.rainbowColors then
        local idx = ((colorIndex - 1) % #config.rainbowColors) + 1
        color = config.rainbowColors[idx]
    else
        color = config.color
    end

    -- Orient ribbon to face the camera (billboard-style vertical slab)
    local dirToCam = CAM_POS - ribbonPos
    local flatDir = Vector3.new(dirToCam.X, 0, dirToCam.Z)
    if flatDir.Magnitude < 0.001 then flatDir = Vector3.new(0, 0, 1) end
    flatDir = flatDir.Unit

    local ribbonCF = CFrame.lookAt(ribbonPos, ribbonPos + flatDir)

    local part = Instance.new("Part")
    part.Name = "_RibbonSeg"
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Size = Vector3.new(RIBBON_WIDTH, RIBBON_HEIGHT, RIBBON_THICKNESS)
    part.CFrame = ribbonCF
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Transparency = config.baseTransparency
    part.Parent = worldModel

    table.insert(_ribbonParts, {
        part = part,
        spawnTime = _elapsed,
        baseTransparency = config.baseTransparency,
    })

    -- Enforce cap
    while #_ribbonParts > MAX_RIBBONS do
        local oldest = table.remove(_ribbonParts, 1)
        if oldest.part and oldest.part.Parent then
            oldest.part:Destroy()
        end
    end
end

local function updateRibbonFade()
    local i = 1
    while i <= #_ribbonParts do
        local entry = _ribbonParts[i]
        local age = _elapsed - entry.spawnTime
        if age >= RIBBON_LIFETIME then
            if entry.part and entry.part.Parent then
                entry.part:Destroy()
            end
            table.remove(_ribbonParts, i)
        else
            local frac = age / RIBBON_LIFETIME
            -- Ease-in fade: slow at start, faster toward end
            local fadeFrac = frac * frac
            entry.part.Transparency = entry.baseTransparency + (1 - entry.baseTransparency) * fadeFrac
            i = i + 1
        end
    end
end

--------------------------------------------------------------------------------
-- STOP  –  Disconnect loop, cleanup
--------------------------------------------------------------------------------
function EffectsPreview.Stop()
    if _activeConn then
        _activeConn:Disconnect()
        _activeConn = nil
    end
    cleanupAllRibbons()
    if _activeWM then
        _activeWM:Destroy()
        _activeWM = nil
    end
    _elapsed = 0
    dprint("Cleaned previous trail preview")
end

--------------------------------------------------------------------------------
-- UPDATE  –  Build rig, set up ribbon trail, start oscillating loop
--------------------------------------------------------------------------------
function EffectsPreview.Update(viewportFrame, effectId)
    if not viewportFrame then return end

    -- Clean previous
    EffectsPreview.Stop()

    for _, child in ipairs(viewportFrame:GetChildren()) do
        if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
            child:Destroy()
        end
    end

    dprint("Selected trail:", tostring(effectId))

    local rig = buildRig()
    if not rig then return end

    -- Strip existing skin cosmetic parts
    local toRemove = {}
    for _, child in ipairs(rig:GetChildren()) do
        if child:GetAttribute("_SkinCosmetic") then
            table.insert(toRemove, child)
        end
    end
    for _, child in ipairs(toRemove) do child:Destroy() end

    -- Anchor all parts
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end

    -- Pose the rig for a mid-dash look
    poseDashLean(rig)

    -- Initial rig position
    local baseRot = CFrame.Angles(0, RIG_Y_ROT, 0)
    local baseCF = CFrame.new(BASE_POS) * baseRot
    rig:PivotTo(baseCF)

    -- Resolve trail visual config (colour, transparency, rainbow)
    local trailConfig = resolveTrailConfig(effectId)
    dprint("Trail config resolved — using ribbon fallback (Trail cannot render in ViewportFrame)")

    -- Parent into WorldModel
    local worldModel = Instance.new("WorldModel")
    _activeWM = worldModel
    rig.Parent = worldModel
    worldModel.Parent = viewportFrame

    -- Camera: positioned to see horizontal trail path
    local camera = Instance.new("Camera")
    camera.FieldOfView = CAM_FOV
    camera.CFrame = CFrame.lookAt(CAM_POS, CAM_TARGET)
    camera.Parent = viewportFrame
    viewportFrame.CurrentCamera = camera

    -- Lighting
    local keyLightPart = Instance.new("Part")
    keyLightPart.Anchored = true; keyLightPart.Transparency = 1
    keyLightPart.CanCollide = false; keyLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    keyLightPart.CFrame = CFrame.new(5, 7, 5); keyLightPart.Parent = worldModel
    local keyLight = Instance.new("PointLight")
    keyLight.Color = Color3.fromRGB(220, 220, 230); keyLight.Brightness = 1.8
    keyLight.Range = 22; keyLight.Parent = keyLightPart

    local fillLightPart = Instance.new("Part")
    fillLightPart.Anchored = true; fillLightPart.Transparency = 1
    fillLightPart.CanCollide = false; fillLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    fillLightPart.CFrame = CFrame.new(-4, 4, 3); fillLightPart.Parent = worldModel
    local fillLight = Instance.new("PointLight")
    fillLight.Color = Color3.fromRGB(150, 160, 200); fillLight.Brightness = 0.8
    fillLight.Range = 18; fillLight.Parent = fillLightPart

    -- Repeating one-way dash loop with ribbon spawning
    _elapsed = 0
    local lastSpawnPos = nil
    local ribbonColorIdx = 0
    local startPos = BASE_POS - MOVE_DIR * (SLIDE_DIST * 0.5)
    local endPos   = BASE_POS + MOVE_DIR * (SLIDE_DIST * 0.5)

    -- Place rig at dash start
    rig:PivotTo(CFrame.new(startPos) * baseRot)

    _activeConn = RunService.RenderStepped:Connect(function(dt)
        if not worldModel or not worldModel.Parent then
            if _activeConn then _activeConn:Disconnect(); _activeConn = nil end
            return
        end

        _elapsed = _elapsed + dt

        local phase = _elapsed % CYCLE_TIME
        local isDashing = phase < DASH_DURATION

        if isDashing then
            -- Forward dash: ease-out for natural deceleration
            local t = phase / DASH_DURATION
            local eased = 1 - (1 - t) * (1 - t)
            local worldPos = startPos:Lerp(endPos, eased)
            rig:PivotTo(CFrame.new(worldPos) * baseRot)

            -- Spawn ribbon segments behind the rig
            local hrp = rig:FindFirstChild("HumanoidRootPart")
            if hrp then
                local currentPos = hrp.Position
                local ribbonPos = Vector3.new(currentPos.X, currentPos.Y - 0.35, currentPos.Z)

                if lastSpawnPos == nil or (currentPos - lastSpawnPos).Magnitude >= RIBBON_SPACING then
                    ribbonColorIdx = ribbonColorIdx + 1
                    spawnRibbon(worldModel, ribbonPos, trailConfig, ribbonColorIdx)
                    lastSpawnPos = currentPos
                end
            end
        else
            -- Reset phase: clear leftover ribbons then reposition rig
            cleanupAllRibbons()
            rig:PivotTo(CFrame.new(startPos) * baseRot)
            lastSpawnPos = nil
            ribbonColorIdx = 0
        end

        -- Fade existing ribbons during dash
        if isDashing then
            updateRibbonFade()
        end
    end)

    dprint("Preview started — one-way dash ribbon trail active")
end

return EffectsPreview
