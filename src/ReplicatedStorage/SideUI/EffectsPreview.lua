--------------------------------------------------------------------------------
-- EffectsPreview.lua  –  Client-side dash trail preview for Inventory Effects tab
--
-- Builds an attachment-aligned avatar and a continuous, tapered ribbon along
-- a repeating dash. Uses live dash timing and effect definitions.
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
    -- Preview logging is intentionally quiet during item selection.
end

--------------------------------------------------------------------------------
-- ACTIVE STATE
--------------------------------------------------------------------------------
local _activeConn   = nil   -- RenderStepped connection
local _activeWM     = nil   -- WorldModel reference
local _ribbonParts  = {}    -- { {part, spawnTime}, ... }
local _elapsed      = 0     -- clock tracked inside RenderStepped
local _generation   = 0     -- invalidate avatar builds that yield during selection changes

--------------------------------------------------------------------------------
-- RIBBON CONFIGURATION  (preview-only — does NOT affect live gameplay)
--------------------------------------------------------------------------------
local RIBBON_LIFETIME    = DashConfig.TrailLifetime or 0.8     -- seconds each ribbon segment persists
local RIBBON_SPACING     = 0.10    -- studs of movement between spawns
local RIBBON_HEIGHT      = 2.3     -- matches attachment span  (0.8 to -1.5)
local RIBBON_THICKNESS   = 0.06    -- thin slab (depth toward camera)
local MAX_RIBBONS        = 160      -- safety cap

--------------------------------------------------------------------------------
-- MOTION / CAMERA CONFIGURATION
--------------------------------------------------------------------------------
-- Movement direction aligned with the avatar facing left.
local MOVE_DIR   = Vector3.new(-1, 0, 0)
local BASE_POS   = Vector3.new(0, 3, 0)
local RIG_Y_ROT  = math.rad(90)
local DASH_DURATION = DashConfig.Duration or 0.2  -- seconds for one forward dash
local RESET_DELAY   = RIBBON_LIFETIME + 0.6  -- pause at start before next dash
local CYCLE_TIME    = DASH_DURATION + RESET_DELAY
local SLIDE_DIST    = 7.0  -- studs total dash distance

local CAM_POS    = Vector3.new(0, 4.5, 13)
local CAM_TARGET = Vector3.new(0, 2.5, 0)
local CAM_FOV    = 50

-- BUILD PREVIEW RIG
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
                    return Players:CreateHumanoidModelFromDescription(desc, hum.RigType)
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
        local archivable = character.Archivable
        character.Archivable = true
        local ok, rig = pcall(function() return character:Clone() end)
        character.Archivable = archivable
        if not ok or not rig then return nil end
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

    -- Match DashClient starting transparency for each effect.
    local baseTransp = isRainbow and 0.2 or (isDark and 0.1 or 0.3)

    dprint("Resolved trail config:", effectId,
        "| rainbow=", isRainbow, "| dark=", isDark, "| baseTransp=", baseTransp)

    return {
        color = solidColor,
        isRainbow = isRainbow,
        isDark = isDark,
        baseTransparency = baseTransp,
        colorSequence = def.TrailColorSequence,
        endWidth = isRainbow and 0.4 or 0.3,
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

local function sampleColor(sequence, t, fallback)
    if not sequence then return fallback end
    local keys = sequence.Keypoints
    for i = 2, #keys do
        if t <= keys[i].Time then
            local left, right = keys[i-1], keys[i]
            return left.Value:Lerp(right.Value, (t-left.Time)/(right.Time-left.Time))
        end
    end
    return keys[#keys].Value
end

local function spawnRibbon(worldModel, from, to, config)
    local delta = to - from
    if delta.Magnitude < 0.001 then return end
    local part = Instance.new("Part")
    part.Name = "TrailRibbon"
    part.Anchored = true
    part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
    part.CastShadow = false
    part.Size = Vector3.new(delta.Magnitude + 0.005, RIBBON_HEIGHT, RIBBON_THICKNESS)
    local right = delta.Unit
    local up = Vector3.yAxis
    part.CFrame = CFrame.fromMatrix((from + to) * 0.5, right, up, right:Cross(up))
    part.Color = config.color
    part.Material = Enum.Material.SmoothPlastic
    part.Transparency = config.baseTransparency
    part.Parent = worldModel
    table.insert(_ribbonParts, {part=part, spawnTime=_elapsed,
        baseTransparency=config.baseTransparency, config=config})
    while #_ribbonParts > MAX_RIBBONS do
        table.remove(_ribbonParts,1).part:Destroy()
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
            -- Match the live linear transparency sequence.
            local fadeFrac = frac
            entry.part.Transparency = entry.baseTransparency + (1 - entry.baseTransparency) * fadeFrac
            entry.part.Size = Vector3.new(entry.part.Size.X,
                RIBBON_HEIGHT * (1 - frac * (1 - (entry.config.endWidth or 0.3))), RIBBON_THICKNESS)
            entry.part.Color = sampleColor(entry.config.colorSequence, frac, entry.config.color)
            i = i + 1
        end
    end
end

--------------------------------------------------------------------------------
-- STOP  –  Disconnect loop, cleanup
--------------------------------------------------------------------------------
function EffectsPreview.Stop()
    _generation += 1
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
    local generation = _generation

    for _, child in ipairs(viewportFrame:GetChildren()) do
        if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
            child:Destroy()
        end
    end

    dprint("Selected trail:", tostring(effectId))

    local rig = buildRig()
    if not rig then return end
    if generation ~= _generation or not viewportFrame.Parent then rig:Destroy(); return end

    -- Strip existing skin cosmetic parts
    local toRemove = {}
    for _, child in ipairs(rig:GetChildren()) do
        if child:GetAttribute("_SkinCosmetic") then
            table.insert(toRemove, child)
        end
    end
    for _, child in ipairs(toRemove) do child:Destroy() end

    -- Keep joints free to position the limbs/accessories; only anchor the root.
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = d.Name == "HumanoidRootPart"
            d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
            d.CastShadow = false
        elseif d:IsA("Tool") or d:IsA("Trail") or d:IsA("ParticleEmitter")
            or d:IsA("BillboardGui") or d:IsA("ForceField") then
            d:Destroy()
        end
    end
    poseDashLean(rig)
    local root = rig:FindFirstChild("HumanoidRootPart")
    if not root then rig:Destroy(); return end
    rig.PrimaryPart = root
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
    -- Resolve the motor hierarchy before the first render, rather than freezing the spawn pose.
    local positioned = {[root]=true}
    for _ = 1, 20 do
        local changed = false
        for _, joint in ipairs(rig:GetDescendants()) do
            if joint:IsA("Motor6D") and joint.Part0 and joint.Part1
                and positioned[joint.Part0] and not positioned[joint.Part1] then
                joint.Part1.CFrame = joint.Part0.CFrame * joint.C0 * joint.Transform * joint.C1:Inverse()
                positioned[joint.Part1] = true
                changed = true
            end
        end
        if not changed then break end
    end
    -- Accessory attachment alignment also handles hats whose weld hasn't settled yet.
    for _, accessory in ipairs(rig:GetChildren()) do
        if accessory:IsA("Accessory") then
            local handle = accessory:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local attachment = handle:FindFirstChildOfClass("Attachment")
                local target
                if attachment then
                    for _, body in ipairs(rig:GetChildren()) do
                        if body:IsA("BasePart") then
                            target = body:FindFirstChild(attachment.Name)
                            if target and target:IsA("Attachment") then break end
                            target = nil
                        end
                    end
                end
                local weld = handle:FindFirstChild("AccessoryWeld")
                if target then
                    handle.CFrame = target.WorldCFrame * attachment.CFrame:Inverse()
                    if weld then weld:Destroy() end
                    weld = Instance.new("Weld")
                    weld.Name = "AccessoryWeld"
                    weld.Part0, weld.Part1 = target.Parent, handle
                    weld.C0, weld.C1 = target.CFrame, attachment.CFrame
                    weld.Parent = handle
                elseif weld and weld:IsA("Weld") and weld.Part0 and weld.Part1 then
                    if weld.Part0 == handle then
                        handle.CFrame = weld.Part1.CFrame * weld.C1 * weld.C0:Inverse()
                    else
                        handle.CFrame = weld.Part0.CFrame * weld.C0 * weld.C1:Inverse()
                    end
                end
            end
        end
    end

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
    viewportFrame.Ambient = Color3.fromRGB(200, 200, 200)
    viewportFrame.LightColor = Color3.new(1, 1, 1)
    local _, rigSize = rig:GetBoundingBox()
    local function fitCamera()
        local size = viewportFrame.AbsoluteSize
        local aspectRatio = size.X / math.max(1, size.Y)
        local halfHeight = math.max(rigSize.Y * 0.6, (rigSize.X + SLIDE_DIST) * 0.55 / math.max(0.2, aspectRatio))
        local distance = halfHeight / math.tan(math.rad(CAM_FOV * 0.5)) + rigSize.Z * 0.5
        camera.CFrame = CFrame.lookAt(CAM_TARGET + Vector3.new(0, distance * 0.12, distance), CAM_TARGET)
    end
    fitCamera()

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
    local lastCycle = -1
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
        fitCamera()

        local cycle = math.floor(_elapsed / CYCLE_TIME)
        if cycle ~= lastCycle then
            cleanupAllRibbons()
            lastSpawnPos = startPos + Vector3.new(0,-0.35,0)
            lastCycle = cycle
        end
        local phase = _elapsed % CYCLE_TIME
        local isDashing = phase < DASH_DURATION

        if isDashing or lastSpawnPos then
            -- Forward dash: ease-out for natural deceleration
            local t = math.min(1, phase / DASH_DURATION)
            local eased = 1 - (1 - t) * (1 - t)
            local worldPos = startPos:Lerp(endPos, eased)
            rig:PivotTo(CFrame.new(worldPos) * baseRot)

            -- Spawn ribbon segments behind the rig
            local hrp = rig:FindFirstChild("HumanoidRootPart")
            if hrp then
                local currentPos = hrp.Position
                local ribbonPos = Vector3.new(currentPos.X, currentPos.Y - 0.35, currentPos.Z)

                if lastSpawnPos then
                    local distance = (ribbonPos-lastSpawnPos).Magnitude
                    local count = math.max(1, math.ceil(distance/RIBBON_SPACING))
                    for i=1,count do
                        spawnRibbon(worldModel, lastSpawnPos:Lerp(ribbonPos,(i-1)/count),
                            lastSpawnPos:Lerp(ribbonPos,i/count),trailConfig)
                    end
                end
                lastSpawnPos = isDashing and ribbonPos or nil
            end
        end
        -- Keep the completed trail visible as it fades; never erase it at dash end.
        updateRibbonFade()
    end)

    dprint("Preview started — one-way dash ribbon trail active")
end

return EffectsPreview
