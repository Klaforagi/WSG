local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local FastCast = require(ReplicatedStorage:WaitForChild("Dependencies"):WaitForChild("FastCastRedux"))
local RangedCast = require(ReplicatedStorage:WaitForChild("RangedCast"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local fireEvent = ReplicatedStorage:WaitForChild("ToolGunFire")
local fireAck = ReplicatedStorage:WaitForChild("ToolGunFireAck")
local fireHit = ReplicatedStorage:FindFirstChild("ToolGunHit")
local projectileVisualEvent = ReplicatedStorage:WaitForChild("ToolGunProjectileVisual")

-- Config (from original crosshair)
local BASE_GAP = 6
local MAX_RECOIL_SPREAD = 14
local LINE_THICKNESS = 3
local LINE_LENGTH = 10
local GAP_RETURN_TIME = 0.18
local DEFAULT_RECOIL_AMOUNT = 8

-- Projectile trails and the aiming reticle stay neutral across teams.
local DEFAULT_TRACER_COLOR = Color3.fromRGB(255, 200, 100)
local function getTracerColor()
    return DEFAULT_TRACER_COLOR
end

local Debris = game:GetService("Debris")

-- Load tool config module early so playFireSound can use preset shoot_sound
local TOOLCFG_MODULE
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    TOOLCFG_MODULE = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
end

local WeaponEnchantConfig
local enchantConfigModule = ReplicatedStorage:FindFirstChild("WeaponEnchantConfig")
if enchantConfigModule then
    WeaponEnchantConfig = require(enchantConfigModule)
end

local function projectilePrimary(visual)
    if visual:IsA("BasePart") then return visual end
    if visual:IsA("Model") then
        if visual.PrimaryPart then return visual.PrimaryPart end
        local part = visual:FindFirstChildWhichIsA("BasePart", true)
        if part then visual.PrimaryPart = part end
        return part
    end
    return nil
end

local function setProjectileCFrame(visual, primary, cf)
    if visual:IsA("Model") then
        visual:PivotTo((cf * primary.CFrame:Inverse()) * visual:GetPivot())
    else
        visual.CFrame = cf
    end
end

local activeClientProjectiles = {}
local function projectileKey(shooterUserId, shotId)
    return tostring(shooterUserId) .. ":" .. tostring(shotId)
end

local cosmeticCasters = {}
local function getCosmeticCaster(toolName)
    local caster = cosmeticCasters[toolName]
    if caster then return caster end
    caster = FastCast.new()
    caster.LengthChanged:Connect(function(cast, origin, direction, length, velocity)
        local state = cast.UserData
        if state.visual.Parent then
            local moveDirection = velocity.Magnitude > 0.001 and velocity.Unit or direction
            state.place(origin + direction * length, moveDirection)
        end
    end)
    caster.CastTerminating:Connect(function(cast)
        local state = cast.UserData
        if state.cast == cast then state.cast = nil end
        -- A cosmetic cast reaching its range must not invent an impact. Keep the
        -- last pose until the server's finish message (or cleanup timeout).
    end)
    cosmeticCasters[toolName] = caster
    return caster
end

local function startCosmeticCast(state, origin, direction, flight, age)
    if state.cast then state.cast:Terminate() end
    local acceleration = Vector3.new(0, -flight.drop, 0)
    local initialVelocity = direction.Unit * flight.speed
    local startPosition = origin + initialVelocity * age + acceleration * (0.5 * age * age)
    local velocity = initialVelocity + acceleration * age
    local params = RaycastParams.new()
    -- Client casts only animate. Collision/termination comes from server RayHit.
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {}
    local behavior = FastCast.newBehavior()
    behavior.RaycastParams = params
    behavior.Acceleration = acceleration
    behavior.MaxDistance = flight.range
    state.place(startPosition, velocity.Magnitude > 0.001 and velocity.Unit or direction)
    local cast = getCosmeticCaster(state.toolName):Fire(startPosition, direction, velocity, behavior)
    cast.UserData = state
    state.cast = cast
    state.flightVersion = (state.flightVersion or 0) + 1
    local version = state.flightVersion
    task.delay(math.max(0, flight.lifetime - age), function()
        if state.cast == cast then cast:Terminate() end
    end)
    -- Clean up rejected requests and missing finish messages without a leaked
    -- arrow/cast. Accepted shots normally end through the server event.
    task.delay(math.max(0, flight.lifetime - age) + 2, function()
        if state.flightVersion == version and state.visual.Parent then state.visual:Destroy() end
    end)
end

local function spawnClientProjectile(toolName, origin, direction, enchantName, visualScale, shooterUserId, shotId, flight)
    if not TOOLCFG_MODULE or not TOOLCFG_MODULE.getPreset then return end
    local presetName = tostring(toolName):match("^Tool(.+)") or tostring(toolName)
    local preset = TOOLCFG_MODULE.getPreset(presetName:lower())
    local templates = ReplicatedStorage:FindFirstChild("ClientProjectileVisuals")
    local template = preset and templates and templates:FindFirstChild(tostring(preset.projectile_name))
    if not template then return end

    local visual = template:Clone()
    visual.Name = "_LocalPredictedProjectile"
    visual:SetAttribute("_LocalPredictedProjectile", true)
    local primary = projectilePrimary(visual)
    if not primary then visual:Destroy() return end

    visualScale = tonumber(visualScale) or 1
    if visual:IsA("Model") and math.abs(visualScale - 1) > 0.001 then
        pcall(function() visual:ScaleTo(visual:GetScale() * visualScale) end)
    elseif visual:IsA("BasePart") and math.abs(visualScale - 1) > 0.001 then
        visual.Size *= visualScale
        for _, item in ipairs(visual:GetDescendants()) do
            if item:IsA("Attachment") then item.Position *= visualScale end
        end
    end

    local predictedTrails = {}
    for _, item in ipairs(visual:GetDescendants()) do
        if item:IsA("BasePart") then
            item.Anchored = true
            item.CanCollide = false
            item.CanTouch = false
            item.CanQuery = false
        elseif item:IsA("Trail") then
            table.insert(predictedTrails, item)
            item.Enabled = false
        end
    end
    if visual:IsA("BasePart") then
        visual.Anchored = true
        visual.CanCollide = false
        visual.CanTouch = false
        visual.CanQuery = false
    end

    if direction.Magnitude <= 0.001 then visual:Destroy() return end
    direction = direction.Unit

    local correction = nil
    local configuredRotation = preset.visual_rotation or preset.visual_rotation_degrees
    if typeof(configuredRotation) == "Vector3" then
        correction = CFrame.Angles(
            math.rad(configuredRotation.X),
            math.rad(configuredRotation.Y),
            math.rad(configuredRotation.Z)
        )
    elseif type(configuredRotation) == "table" then
        correction = CFrame.Angles(
            math.rad(tonumber(configuredRotation[1] or configuredRotation.X) or 0),
            math.rad(tonumber(configuredRotation[2] or configuredRotation.Y) or 0),
            math.rad(tonumber(configuredRotation[3] or configuredRotation.Z) or 0)
        )
    end
    correction = correction or RangedCast.GetShaftLookCorrection(visual, primary)
    local tip = visual:FindFirstChild("Tip", true)
    local tipLocal = Vector3.zero
    if tip and tip:IsA("Attachment") then
        tipLocal = primary.CFrame:PointToObjectSpace(tip.WorldPosition)
    end

    -- Server-created trails are not part of the stored template. Mirror the
    -- projectile trail locally so it begins on the same frame as the arrow.
    if #predictedTrails == 0 and tip and tip:IsA("Attachment") and tip.Parent and tip.Parent:IsA("BasePart") then
        local secondAttachment = Instance.new("Attachment")
        secondAttachment.Name = "_PredictedProjectileTrail1"
        secondAttachment.CFrame = tip.CFrame * CFrame.new(0, 0.18, 0)
        secondAttachment.Parent = tip.Parent

        local trail = Instance.new("Trail")
        trail.Name = "AmmoTrail"
        trail.Attachment0 = tip
        trail.Attachment1 = secondAttachment
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, DEFAULT_TRACER_COLOR),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
        })
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.6, 0.55),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.WidthScale = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1.2075),
            NumberSequenceKeypoint.new(0.65, 0.6325),
            NumberSequenceKeypoint.new(1, 0.092),
        })
        trail.Lifetime = math.clamp((preset.projectile_lifetime or 4) * 0.08, 0.18, 0.35)
        trail.MinLength = 0
        trail.FaceCamera = true
        trail.LightEmission = 0.45
        trail.Enabled = false
        trail.Parent = tip.Parent
        table.insert(predictedTrails, trail)
    end

    for _, trail in ipairs(predictedTrails) do
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, DEFAULT_TRACER_COLOR),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
        })
    end

    local enchantTrailColor = WeaponEnchantConfig
        and WeaponEnchantConfig.GetTrailColorSequenceForEnchant
        and WeaponEnchantConfig.GetTrailColorSequenceForEnchant(enchantName)
    if enchantTrailColor then
        for _, trail in ipairs(predictedTrails) do trail.Color = enchantTrailColor end
    end

    local displayName = tostring(toolName):match("^Tool(.+)") or tostring(toolName)
    if displayName:lower():find("ethereal", 1, true) and WeaponEnchantConfig
        and WeaponEnchantConfig.GetEtherealPartColor then
        local bodyColor = WeaponEnchantConfig.GetEtherealPartColor(enchantName)
        if bodyColor then
            local function tint(item)
                if item:IsA("BasePart") and item.Name ~= "EnchantBlock" then item.Color = bodyColor end
            end
            tint(visual)
            for _, item in ipairs(visual:GetDescendants()) do tint(item) end
        end
    end

    local function flightCFrame(atPosition, moveDirection)
        local targetDirection = preset.visual_flip and -moveDirection or moveDirection
        return CFrame.lookAt(atPosition, atPosition + targetDirection) * correction * CFrame.new(-tipLocal)
    end
    local key = projectileKey(shooterUserId, shotId)
    local previous = activeClientProjectiles[key]
    if previous then previous.visual:Destroy() end
    local state = {
        visual = visual,
        primary = primary,
        toolName = toolName,
        trails = predictedTrails,
        place = function(position, moveDirection)
            setProjectileCFrame(visual, primary, flightCFrame(position, moveDirection))
        end,
    }
    activeClientProjectiles[key] = state
    visual.Destroying:Connect(function()
        if activeClientProjectiles[key] == state then activeClientProjectiles[key] = nil end
        if state.cast then state.cast:Terminate() end
        if state.followConnection then state.followConnection:Disconnect() end
    end)
    local settings = flight or {
        speed = preset.bulletspeed or 150,
        drop = preset.bulletdrop or 55,
        range = preset.range or 450,
        lifetime = preset.projectile_lifetime or 4,
    }
    local age = flight and math.max(0, workspace:GetServerTimeNow() - flight.startedAt) or 0
    startCosmeticCast(state, origin, direction, settings, age)
    visual.Parent = workspace
    for _, trail in ipairs(predictedTrails) do trail.Enabled = true end
end

-- Size-scaling helpers (mirrors server logic in ToolGunSetup)
local function getClientSizePercent(tool)
    if not tool then return 100 end
    local sp = tool:GetAttribute("SizePercent")
        or tool:GetAttribute("WeaponSizePercent")
        or tool:GetAttribute("ScalePercent")
        or tool:GetAttribute("WeaponScale")
    if type(sp) == "number" and sp > 0 then return sp end
    return 100
end
local function getClientSizeSpeedMult(sp)
    if sp <= 100 then return math.clamp(sp / 100, 0.5, 1.0) end
    return math.clamp(1.0 + (sp - 100) / 200, 1.0, 2.0)
end
local function getClientScaledCooldown(baseCd, sizePercent)
    return baseCd * getClientSizeSpeedMult(sizePercent)
end

local function playFireSound(toolName)
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end

    local template = nil

    -- 1) Try preset shoot_sound from Toolgunsettings
    if TOOLCFG_MODULE and TOOLCFG_MODULE.getPreset and toolName then
        local suffix = tostring(toolName):match("^Tool(.+)") or tostring(toolName)
        local preset = TOOLCFG_MODULE.getPreset(suffix:lower())
        if preset and preset.shoot_sound then
            -- try exact name first, then case-insensitive scan
            template = toolgunFolder:FindFirstChild(preset.shoot_sound)
            if not template then
                local target = preset.shoot_sound:lower()
                for _, child in ipairs(toolgunFolder:GetChildren()) do
                    if child:IsA("Sound") and child.Name:lower() == target then
                        template = child
                        break
                    end
                end
            end
        end
    end

    -- 2) Fallback: name-based heuristics
    if not template and toolName then
        local lower = tostring(toolName):lower()
        if lower:find("sniper") then
            template = toolgunFolder:FindFirstChild("Sniper_shoot") or toolgunFolder:FindFirstChild("Sniper_Shoot")
        elseif lower:find("pistol") then
            template = toolgunFolder:FindFirstChild("Pistol_shoot") or toolgunFolder:FindFirstChild("Pistol_Shoot")
        elseif lower:find("slingshot") then
            template = toolgunFolder:FindFirstChild("Slingshot_Shoot") or toolgunFolder:FindFirstChild("Slingshot_shoot")
        elseif lower:find("bow") then
            template = toolgunFolder:FindFirstChild("BowShoot")
                or toolgunFolder:FindFirstChild("Bow_shoot")
                or toolgunFolder:FindFirstChild("Bow_Shoot")
                or toolgunFolder:FindFirstChild("Shortbow_shoot")
                or toolgunFolder:FindFirstChild("Shortbow_Shoot")
        end
    end

    -- 3) Last resort
    if not template then
        template = toolgunFolder:FindFirstChild("Gun_shoot")
    end

    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

local function playHitSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end
    local template = toolgunFolder:FindFirstChild("Gun_hitmarker")
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

-- Build HUD ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ToolGunHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui
screenGui.Enabled = false

local function makeLine(name, size, anchor, pos)
    local f = Instance.new("Frame")
    f.Name = name
    f.Size = size
    f.AnchorPoint = anchor
    f.BackgroundColor3 = getTracerColor()
    f.BorderSizePixel = 0
    f.Position = pos
    f.Parent = screenGui
    return f
end

local centerUD = UDim2.new(0.5, 0, 0.5, 0)
local up = makeLine("Cross_Up",
    UDim2.new(0, LINE_THICKNESS, 0, LINE_LENGTH),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))
)
local down = makeLine("Cross_Down",
    UDim2.new(0, LINE_THICKNESS, 0, LINE_LENGTH),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, 0, 0, (BASE_GAP + LINE_LENGTH/2))
)
local left = makeLine("Cross_Left",
    UDim2.new(0, LINE_LENGTH, 0, LINE_THICKNESS),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)
)
local right = makeLine("Cross_Right",
    UDim2.new(0, LINE_LENGTH, 0, LINE_THICKNESS),
    Vector2.new(0.5, 0.5),
    centerUD + UDim2.new(0, (BASE_GAP + LINE_LENGTH/2), 0, 0)
)

local function updatePositions(gap)
    up.Position    = centerUD + UDim2.new(0, 0, 0, -(gap + LINE_LENGTH/2))
    down.Position  = centerUD + UDim2.new(0, 0, 0,  (gap + LINE_LENGTH/2))
    left.Position  = centerUD + UDim2.new(0, -(gap + LINE_LENGTH/2), 0, 0)
    right.Position = centerUD + UDim2.new(0,  (gap + LINE_LENGTH/2), 0, 0)
end

-- Hitmarker (center X)
local hitLabel = Instance.new("TextLabel")
hitLabel.Name = "HitMarker"
hitLabel.Size = UDim2.new(0, 12, 0, 12)
hitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hitLabel.BackgroundTransparency = 1
hitLabel.Text = "X"
hitLabel.Font = Enum.Font.GothamBold
hitLabel.TextScaled = false
hitLabel.TextSize = 14
hitLabel.TextColor3 = Color3.fromRGB(0,0,0)
hitLabel.TextTransparency = 0
hitLabel.TextStrokeTransparency = 0.5
hitLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
hitLabel.Visible = false
hitLabel.Position = centerUD
hitLabel.Parent = screenGui

-- Crosshair animation state
local currentGap = BASE_GAP
local returnTween = nil
local tweenInfo = TweenInfo.new(GAP_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function resetCrosshair()
    if returnTween then
        pcall(function() returnTween:Cancel() end)
        returnTween = nil
    end
    local goal = {}
    goal[up]    = {Position = centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))}
    goal[down]  = {Position = centerUD + UDim2.new(0, 0, 0,  (BASE_GAP + LINE_LENGTH/2))}
    goal[left]  = {Position = centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)}
    goal[right] = {Position = centerUD + UDim2.new(0,  (BASE_GAP + LINE_LENGTH/2), 0, 0)}

    local tweens = {}
    for part, props in pairs(goal) do
        local t = TweenService:Create(part, tweenInfo, props)
        t:Play()
        table.insert(tweens, t)
    end
    currentGap = BASE_GAP
    returnTween = tweens[1]
    returnTween.Completed:Connect(function()
        returnTween = nil
    end)
end

local function expandCrosshair(amount)
    local add = amount or DEFAULT_RECOIL_AMOUNT
    local newGap = math.min((currentGap or BASE_GAP) + add, MAX_RECOIL_SPREAD)
    currentGap = newGap

    if returnTween then
        pcall(function() returnTween:Cancel() end)
        returnTween = nil
    end

    updatePositions(currentGap)

    local goal = {}
    goal[up]    = {Position = centerUD + UDim2.new(0, 0, 0, -(BASE_GAP + LINE_LENGTH/2))}
    goal[down]  = {Position = centerUD + UDim2.new(0, 0, 0,  (BASE_GAP + LINE_LENGTH/2))}
    goal[left]  = {Position = centerUD + UDim2.new(0, -(BASE_GAP + LINE_LENGTH/2), 0, 0)}
    goal[right] = {Position = centerUD + UDim2.new(0,  (BASE_GAP + LINE_LENGTH/2), 0, 0)}

    local tweens = {}
    for part, props in pairs(goal) do
        local t = TweenService:Create(part, tweenInfo, props)
        t:Play()
        table.insert(tweens, t)
    end
    returnTween = tweens[1]
    returnTween.Completed:Connect(function()
        currentGap = BASE_GAP
        returnTween = nil
    end)
end

-- Hold-to-fire state (server-paced via ACK; no client-side timer drift)
local COOLDOWN = 0.5
local isHoldingFire = false
local shotInFlight = false
local nextAllowedFireAt = 0
local fireToken = 0
local nextClientShotId = 0
local locallyRenderedShots = {}
local currentFiringTool = nil

projectileVisualEvent.OnClientEvent:Connect(function(action, shooterUserId, shotId, toolName, origin, direction, enchantName, visualScale, flight)
    local state = activeClientProjectiles[projectileKey(shooterUserId, shotId)]
    if action == "finish" then
        local impact = toolName -- finish payload
        if not state then return end
        if state.cast then state.cast:Terminate() end
        state.flightVersion = (state.flightVersion or 0) + 1
        if typeof(impact) == "table" and typeof(impact.position) == "Vector3" then
            local velocity = impact.velocity
            if typeof(velocity) == "Vector3" and velocity.Magnitude > 0.001 then
                state.place(impact.position, velocity.Unit)
            end
            for _, trail in ipairs(state.trails) do trail.Enabled = false end
            if impact.leaveProjectile then
                local hitPart = impact.hitPart
                if hitPart and hitPart:IsA("BasePart") then
                    local offset = hitPart.CFrame:ToObjectSpace(state.primary.CFrame)
                    state.followConnection = RunService.RenderStepped:Connect(function()
                        if not hitPart.Parent then
                            state.visual:Destroy()
                            return
                        end
                        setProjectileCFrame(state.visual, state.primary, hitPart.CFrame * offset)
                    end)
                end
                Debris:AddItem(state.visual, impact.stickLifetime or 2)
                return
            end
        end
        state.visual:Destroy()
        return
    end
    if action ~= "spawn" then return end
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
    if shooterUserId == player.UserId and locallyRenderedShots[shotId] then
        locallyRenderedShots[shotId] = nil
        if state and flight then
            -- Retain the immediate muzzle visual, but reconcile its trajectory to
            -- the server's camera target, settings and launch time.
            for _, trail in ipairs(state.trails) do trail:Clear() end
            startCosmeticCast(state, origin, direction, flight,
                math.max(0, workspace:GetServerTimeNow() - flight.startedAt))
            return
        end
    end
    spawnClientProjectile(toolName, origin, direction, enchantName, visualScale, shooterUserId, shotId, flight)
end)
local toolCooldowns = {} -- toolName → base cd (set by attachTool, used in ACK handler)

local function tryFire(tool)
    if not isHoldingFire then return end
    if shotInFlight then return end
    if os.clock() < nextAllowedFireAt then return end
    if not tool or not tool.Parent then return end
    local char = player.Character
    if not char or not char:FindFirstChild(tool.Name) then return end
    if _G.IsBandaging then return end

    shotInFlight = true
    local activeCamera = workspace.CurrentCamera or camera
    if not activeCamera then
        shotInFlight = false
        return
    end

    local origin
    if TOOLCFG_MODULE and type(TOOLCFG_MODULE.getFireOrigin) == "function" then
        origin = TOOLCFG_MODULE.getFireOrigin(tool, nil)
    end
    if typeof(origin) ~= "Vector3" then
        local handle = tool:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            origin = handle.Position
        else
            origin = activeCamera.CFrame.Position
        end
    end

	local rayOrigin
	    local rayDirection

	if UserInputService.TouchEnabled then
		-- Touch aiming stays at the crosshair even if a keyboard/mouse becomes
		-- available during a held burst (including Studio's phone emulator).
		-- Mobile: fire through the same point the crosshair uses (screen center)
		local viewport = activeCamera.ViewportSize
		local centerRay = activeCamera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
		rayOrigin = centerRay.Origin
		rayDirection = centerRay.Direction.Unit
	else
		local mouse = player:GetMouse()
		local mx, my
		if mouse and mouse.X and mouse.Y then
			mx = mouse.X
			my = mouse.Y
		else
			local mpos = UserInputService:GetMouseLocation()
			mx = mpos.X
			my = mpos.Y
		end
		local mouseRay = activeCamera:ScreenPointToRay(mx, my)
		rayOrigin = mouseRay.Origin
		rayDirection = mouseRay.Direction.Unit
	end
    local presetName = tostring(tool.Name):match("^Tool(.+)") or tostring(tool.Name)
    local preset = TOOLCFG_MODULE and TOOLCFG_MODULE.getPreset and TOOLCFG_MODULE.getPreset(presetName:lower())
    local range = (preset and preset.range) or 450
    local aimParams = RaycastParams.new()
    aimParams.FilterType = Enum.RaycastFilterType.Exclude
    aimParams.FilterDescendantsInstances = { char }
    aimParams.IgnoreWater = true
    local aimHit = RangedCast.RaycastAim(workspace, rayOrigin, rayDirection * range, aimParams, player)
    local aimPoint = aimHit and aimHit.Position or (rayOrigin + rayDirection * range)
    local localDirection = aimPoint - origin
    if localDirection.Magnitude <= 0.001 then localDirection = rayDirection end

    nextClientShotId += 1
    local shotId = nextClientShotId
    locallyRenderedShots[shotId] = true
    local sizePercent = getClientSizePercent(tool)
    local visualScale = math.clamp(sizePercent / 100, 0.1, 5)
    spawnClientProjectile(
        tool.Name,
        origin,
        localDirection.Unit,
        tool:GetAttribute("EnchantName"),
        visualScale,
        player.UserId,
        shotId
    )
    fireEvent:FireServer(rayOrigin, rayDirection, origin, tool.Name, shotId)
    task.delay(5, function() locallyRenderedShots[shotId] = nil end)
    -- Failsafe: if no ACK within 0.35s, clear the in-flight flag so the gun does not get stuck
    local myToken = fireToken
    task.delay(0.35, function()
        if fireToken == myToken and shotInFlight then
            shotInFlight = false
        end
    end)
end

fireAck.OnClientEvent:Connect(function(gunOrigin, targetPos, toolName)
    expandCrosshair(DEFAULT_RECOIL_AMOUNT)
    playFireSound(toolName)

    -- Resolve the equipped tool to compute size-scaled cooldown
    local equippedTool = nil
    local char = player.Character
    if char and toolName then equippedTool = char:FindFirstChild(toolName) end
    local baseCd = toolCooldowns[toolName] or COOLDOWN
    local sizePercent = getClientSizePercent(equippedTool)
    local scaledCd = getClientScaledCooldown(baseCd, sizePercent)

    -- Hotbar cooldown overlay with the correct size-scaled duration
    if _G.HotbarCooldown then
        _G.HotbarCooldown.start(2, scaledCd)
    end

    -- Unblock the next shot and schedule tryFire if player is still holding
    shotInFlight = false
    nextAllowedFireAt = os.clock() + scaledCd

    if isHoldingFire then
        local myToken = fireToken
        task.delay(scaledCd, function()
            if fireToken == myToken and isHoldingFire then
                tryFire(currentFiringTool)
            end
        end)
    end
end)

-- Hit event handling: reuse logic from ToolGun.client.lua
if fireHit and fireHit:IsA("RemoteEvent") then
    fireHit.OnClientEvent:Connect(function(damage, hitPart, hitPos)
        playHitSound()
        local color = Color3.fromRGB(243, 255, 16)
        if screenGui.Enabled then
            hitLabel.TextColor3 = color
            local hitSize = 16
            hitLabel.TextSize = hitSize
            hitLabel.TextStrokeTransparency = 0
            hitLabel.Visible = true
            task.delay(0.25, function()
                hitLabel.Visible = false
                hitLabel.TextSize = 14
                hitLabel.TextStrokeTransparency = 0.5
            end)
        else
            -- temporary center hit indicator if HUD not shown
            local tempGui = Instance.new("ScreenGui")
            tempGui.IgnoreGuiInset = true
            tempGui.ResetOnSpawn = false
            tempGui.Parent = playerGui
            local temp = Instance.new("TextLabel")
            temp.Size = UDim2.new(0,12,0,12)
            temp.Position = centerUD
            temp.AnchorPoint = Vector2.new(0.5,0.5)
            temp.BackgroundTransparency = 1
            temp.Text = "X"
            temp.Font = Enum.Font.GothamBold
            local tempSize = 16
            temp.TextSize = tempSize
            temp.TextColor3 = color
            temp.TextTransparency = 0
            temp.TextStrokeTransparency = 0
            temp.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            temp.Parent = tempGui
            task.delay(0.25, function()
                tempGui:Destroy()
            end)
        end

        -- floating damage number at hit location/part (unchanged)
        spawn(function()
            local TweenService = game:GetService("TweenService")
            local parentPart = nil
            local createdAnchor = nil
            if hitPart and typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
                parentPart = hitPart
            elseif hitPos and typeof(hitPos) == "Vector3" then
                createdAnchor = Instance.new("Part")
                createdAnchor.Name = "_DamageAnchor"
                createdAnchor.Size = Vector3.new(0.2,0.2,0.2)
                createdAnchor.Transparency = 1
                createdAnchor.Anchored = true
                createdAnchor.CanCollide = false
                createdAnchor.CFrame = CFrame.new(hitPos)
                createdAnchor.Parent = workspace
                parentPart = createdAnchor
            end
            if not parentPart then return end

            local gui = Instance.new("BillboardGui")
            gui.Name = "DamagePopup"
            gui.Size = UDim2.new(0,100,0,40)
            gui.Adornee = parentPart
            gui.AlwaysOnTop = true
            gui.StudsOffset = Vector3.new(0, 2, 0)
            gui.Parent = parentPart

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1,0,1,0)
            label.BackgroundTransparency = 1
            label.Text = tostring(math.floor(damage))
            label.Font = Enum.Font.GothamBold
            label.TextSize = 24
            label.TextColor3 = Color3.fromRGB(255,255,255)
            label.TextStrokeTransparency = 0.5
            label.Parent = gui

            local goal = {StudsOffset = gui.StudsOffset + Vector3.new(0,1.2,0)}
            local tween = TweenService:Create(gui, TweenInfo.new(1.5, Enum.EasingStyle.Quad), goal)
            tween:Play()
            for i = 0, 1, 0.06 do
                label.TextTransparency = i
                task.wait(0.09)
            end
            tween:Cancel()
            gui:Destroy()
            if createdAnchor and createdAnchor.Parent then createdAnchor:Destroy() end
        end)
    end)
end

-- Tool detection logic (merge of both scripts)
-- (TOOLCFG_MODULE already required above)

local function isToolGun(tool)
    if not tool then return false end
    if tool:GetAttribute("IsToolGun") then return true end
    local name = tostring(tool.Name)
    if name == "ToolPistol" or name == "ToolSniper" then return true end
    local suffix = name:match("^Tool(.+)") or name:match("^(.+)$")
    if suffix then
        local key = suffix:lower()
        if TOOLCFG_MODULE and TOOLCFG_MODULE.presets and TOOLCFG_MODULE.presets[key] then
            return true
        end
    end
    return false
end

-- Show/hide HUD based on equipped ToolGun
local equippedCount = 0
local toolConns = {}

local function onEquippedTool()
    equippedCount = equippedCount + 1
    screenGui.Enabled = true
end
local function onUnequippedTool()
    equippedCount = math.max(0, equippedCount - 1)
    if equippedCount == 0 then
        screenGui.Enabled = false
    end
end

-- Firing logic copied from original ToolGun.client.lua
local attachedTools = {} -- Lua table registry to prevent duplicate connections on clones

local function getToolCfgForTool(tool)
    local cfg = {}
    local toolType = tool:GetAttribute("ToolType")
    if not toolType then
        local name = tostring(tool.Name)
        local suffix = name:match("^Tool(.+)") or name:match("^(.+)$")
        if suffix then toolType = suffix:lower() end
    end
    if TOOLCFG_MODULE and TOOLCFG_MODULE.getPreset and toolType then
        local preset = TOOLCFG_MODULE.getPreset(toolType)
        if preset then
            for k, v in pairs(preset) do cfg[k] = v end
        end
    end
    local attrs = {"cd","bulletspeed","damage","range","projectile_lifetime","projectile_size","bulletdrop","showTracer"}
    for _, a in ipairs(attrs) do
        local val = tool:GetAttribute(a)
        if val ~= nil then cfg[a] = val end
    end
    return cfg
end

local function attachTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if not isToolGun(tool) then return end
    if attachedTools[tool] then return end
    attachedTools[tool] = true

    local toolCfg = getToolCfgForTool(tool)
    local toolCooldown = (toolCfg and toolCfg.cd) or COOLDOWN
    toolCooldowns[tool.Name] = toolCooldown   -- base cd stored for ACK handler size-scaling

    local mouse = player:GetMouse()
    local function startFiring()
        if _G.IsBandaging then return end
        isHoldingFire = true
        currentFiringTool = tool
        tryFire(tool)
    end

    local function stopFiring()
        isHoldingFire = false
        fireToken = fireToken + 1
        shotInFlight = false
    end

	local mouseConns = {}
        local fireTouchId = nil

        local function clearMouseConns()
            for _, c in ipairs(mouseConns) do
                c:Disconnect()
            end
            mouseConns = {}
            fireTouchId = nil
        end

        local function isRightSideTouch(input)
            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
            return input.Position.X >= (viewport.X * 0.5)
        end

        tool.Equipped:Connect(function()
            clearMouseConns()

            if UserInputService.TouchEnabled then
                table.insert(mouseConns, UserInputService.InputBegan:Connect(function(input, gameProcessed)
                    if input.UserInputType ~= Enum.UserInputType.Touch then
                        return
                    end
                    if fireTouchId ~= nil then
                        return
                    end
                    if not isRightSideTouch(input) then
                        return
                    end
                    fireTouchId = input
                    startFiring()
                end))

                table.insert(mouseConns, UserInputService.InputEnded:Connect(function(input)
                    if input ~= fireTouchId then
                        return
                    end
                    fireTouchId = nil
                    stopFiring()
                end))
            else
                table.insert(mouseConns, mouse.Button1Down:Connect(startFiring))
                table.insert(mouseConns, mouse.Button1Up:Connect(stopFiring))
            end

            onEquippedTool()
        end)

        tool.Unequipped:Connect(function()
            clearMouseConns()
            stopFiring()
            onUnequippedTool()
        end)

    end

local scannedContainers = {} -- prevent duplicate ChildAdded on same container
local function scanContainer(container)
    if not container then return end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            attachTool(child)
        end
    end
    if not scannedContainers[container] then
        scannedContainers[container] = true
        container.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                attachTool(child)
            end
        end)
    end
end

-- initial scan & connections
scanContainer(player.Backpack)
if player.Character then scanContainer(player.Character) end
player.CharacterAdded:Connect(function(char)
    scanContainer(char)
end)

-- also scan StarterPack for tools (they get copied to Backpack)
for _, child in ipairs(StarterPack:GetChildren()) do
    if child:IsA("Tool") and isToolGun(child) then
        -- no-op; attach happens when copied to Backpack
    end
end

-- initial crosshair layout
updatePositions(BASE_GAP)

return nil
