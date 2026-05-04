local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobCombat = {}

local function defaultGetRootPart(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function nearestPlayer(pos, detectionRadius)
    local best, bestDist, bestRoot
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        if not ch then continue end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local root = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
        if not root then continue end

        local d = (root.Position - pos).Magnitude
        if d <= detectionRadius and (not bestDist or d < bestDist) then
            best, bestDist, bestRoot = p, d, root
        end
    end
    return best, bestRoot, bestDist
end

local function randomPointInArea(areaPart)
    local c, s = areaPart.Position, areaPart.Size
    return Vector3.new(
        c.X + (math.random() - 0.5) * s.X,
        c.Y,
        c.Z + (math.random() - 0.5) * s.Z
    )
end

local function buildForwardBoxCFrame(root, offset)
    -- Treat positive Z as forward in world space from the mob's current look.
    local right = root.CFrame.RightVector
    local up = root.CFrame.UpVector
    local forward = root.CFrame.LookVector
    local worldPos = root.Position + right * offset.X + up * offset.Y + forward * offset.Z
    return CFrame.lookAt(worldPos, worldPos + forward, up)
end

local function applyVictimKnockback(victimRoot, attackerRoot, knockback, knockbackY)
    if not victimRoot or not attackerRoot then return end
    if not victimRoot:IsA("BasePart") or victimRoot.Anchored then return end

    local horizontal = Vector3.new(
        victimRoot.Position.X - attackerRoot.Position.X,
        0,
        victimRoot.Position.Z - attackerRoot.Position.Z
    )
    if horizontal.Magnitude < 0.01 then
        local fwd = attackerRoot.CFrame.LookVector
        horizontal = Vector3.new(fwd.X, 0, fwd.Z)
    end
    if horizontal.Magnitude < 0.01 then return end

    local dir = horizontal.Unit
    -- Directly overwrite AssemblyLinearVelocity instead of ApplyImpulse.
    -- ApplyImpulse is countered by the Humanoid controller every frame;
    -- setting velocity directly produces a reliable, visible knockback.
    local lateralSpeed = knockback or 50
    local vertSpeed = knockbackY or 12
    victimRoot.AssemblyLinearVelocity = dir * lateralSpeed + Vector3.new(0, vertSpeed, 0)
end

local function playDamageFlash(character)
    if not character or not character:IsA("Model") then return end

    local flash = character:FindFirstChild("_MobDamageFlash")
    if not (flash and flash:IsA("Highlight")) then
        flash = Instance.new("Highlight")
        flash.Name = "_MobDamageFlash"
        flash.Adornee = character
        flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        flash.FillColor = Color3.fromRGB(255, 255, 255)
        flash.OutlineColor = Color3.fromRGB(255, 80, 80)
        flash.Parent = character
    end

    flash.Enabled = true
    flash.FillTransparency = 0.22
    flash.OutlineTransparency = 0.38

    local tween = TweenService:Create(
        flash,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { FillTransparency = 1, OutlineTransparency = 1 }
    )
    tween:Play()
    Debris:AddItem(flash, 0.2)
end

function MobCombat.StartMob(mobModel, mobConfig, context)
    if not mobModel or not mobModel.Parent then return end

    context = context or {}
    local getRootPart = context.getRootPart or defaultGetRootPart
    local defaultWalkAnimId = context.defaultWalkAnimId or "rbxassetid://180426354"
    local zombieKillEvent = context.zombieKillEvent
    local mobTag = context.mobTag
    local spawnPos = context.spawnPos or mobModel:GetPivot().Position
    local areaPart = context.areaPart
    local destroyDelay = context.destroyDelay or 10

    local cfgMove = (mobConfig and mobConfig.Movement) or {}
    local cfgAtk = (mobConfig and mobConfig.Attack) or {}
    local cfgAnim = (mobConfig and mobConfig.Animation) or {}
    local cfgDbg = (mobConfig and mobConfig.Debug) or {}

    local humanoid = mobModel:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[MobCombat] Mob has no Humanoid:", mobModel.Name)
        return
    end

    local WALK_SPEED = cfgMove.WalkSpeed or 10
    local CHASE_SPEED = cfgMove.ChaseSpeed or 14
    local ENRAGED_SPEED = cfgMove.EnragedSpeed or CHASE_SPEED
    local USE_ENRAGED = (cfgMove.UseEnraged == true)
    local DETECTION_RADIUS = cfgMove.DetectionRadius or 20
    local AGGRO_DURATION = cfgMove.AggroDuration or 8

    local ATTACK_DAMAGE = cfgAtk.Damage or 12
    local ATTACK_COOLDOWN = cfgAtk.Cooldown or 1
    local ATTACK_RANGE = cfgAtk.Range or 6
    local ATTACK_WINDUP = cfgAtk.Windup or 0.45
    local HITBOX_SIZE = cfgAtk.HitboxSize or Vector3.new(5, 6, 5)
    local HITBOX_OFFSET = cfgAtk.HitboxOffset or Vector3.new(0, 0, 3)
    local HIT_KNOCKBACK = cfgAtk.Knockback or 50
    local HIT_KNOCKBACK_Y = cfgAtk.KnockbackY or 12
    local MIN_SPACING = cfgAtk.MinimumSpacingDistance or 3.5
    local ORC_NOISE_CHANCE = 0.25
    local ORC_NOISE_COOLDOWN = 3
    local isOrc = (mobModel.Name == "Orc")
    local GOBLIN_NOISE_CHANCE = 0.25
    local GOBLIN_NOISE_COOLDOWN = 3
    local isGoblin = (mobModel.Name == "Goblin")

    local SHOW_HITBOX = (cfgDbg.ShowHitbox == true)
    local HITBOX_COLOR = cfgDbg.HitboxColor or Color3.fromRGB(255, 50, 50)

    local isEnraged = false
    local isAttacking = false
    local lastSwingEnd = 0
    local aggroPlayer = nil
    local aggroExpiry = 0
    local chasing = false
    local moving = false
    local stationaryTicks = 0
    local aiRunning = true

    local lastMoveTarget = nil
    local lastMoveCommandAt = 0
    local REPATH_INTERVAL = 0.20
    local REPATH_DISTANCE = 1.5
    local lastOrcNoiseProcAt = os.clock() -- start at now so full cooldown must expire before first noise (prevents spawn-time audio pop)
    local lastGoblinNoiseProcAt = os.clock() -- shared cooldown for both GoblinNoise and GoblinDeath
    local STUCK_MISS_THRESHOLD = 2
    local STUCK_SPEED_THRESHOLD = 0.6
    local STUCK_RETREAT_TIME = 0.2
    local stuckMissesWhileStationary = 0
    local forcedRetreatUntil = 0

    humanoid.WalkSpeed = WALK_SPEED
    humanoid.AutoRotate = true

    local function setMobSpeed(speed)
        local icySlow = humanoid:GetAttribute("IcySlowPercent")
        if icySlow and type(icySlow) == "number" and icySlow > 0 then
            speed = math.max(speed * (1 - icySlow), 1)
        end
        humanoid.WalkSpeed = speed
    end

    local function updateSpeedByState()
        if isEnraged then
            setMobSpeed(ENRAGED_SPEED)
        elseif chasing then
            setMobSpeed(CHASE_SPEED)
        else
            setMobSpeed(WALK_SPEED)
        end
    end

    -- Remove template Animate scripts to avoid animation conflicts.
    for _, desc in ipairs(mobModel:GetDescendants()) do
        if (desc:IsA("Script") or desc:IsA("LocalScript")) and desc.Name == "Animate" then
            desc:Destroy()
        end
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end)

    local walkAnimId = (cfgAnim.Walk and cfgAnim.Walk ~= "") and cfgAnim.Walk or defaultWalkAnimId
    local runAnimId = (cfgAnim.Run and cfgAnim.Run ~= "") and cfgAnim.Run or walkAnimId

    local walkAnimObj = Instance.new("Animation")
    walkAnimObj.Name = "Walk_Mob"
    walkAnimObj.AnimationId = walkAnimId
    walkAnimObj.Parent = mobModel

    local runAnimObj = Instance.new("Animation")
    runAnimObj.Name = "Run_Mob"
    runAnimObj.AnimationId = runAnimId
    runAnimObj.Parent = mobModel

    local walkTrack, runTrack
    pcall(function()
        walkTrack = animator:LoadAnimation(walkAnimObj)
        walkTrack.Priority = Enum.AnimationPriority.Movement
        walkTrack.Looped = true

        runTrack = animator:LoadAnimation(runAnimObj)
        runTrack.Priority = Enum.AnimationPriority.Movement
        runTrack.Looped = true
    end)

    local idleTrack
    if cfgAnim.Idle and cfgAnim.Idle ~= "" then
        local idleAnimObj = Instance.new("Animation")
        idleAnimObj.Name = "Idle_Mob"
        idleAnimObj.AnimationId = cfgAnim.Idle
        idleAnimObj.Parent = mobModel
        pcall(function()
            idleTrack = animator:LoadAnimation(idleAnimObj)
            idleTrack.Priority = Enum.AnimationPriority.Idle
            idleTrack.Looped = true
            idleTrack:Play(0.2)
        end)
    end

    local attackTrack
    if cfgAnim.Attack and cfgAnim.Attack ~= "" then
        local atkAnimObj = Instance.new("Animation")
        atkAnimObj.Name = "Attack_Mob"
        atkAnimObj.AnimationId = cfgAnim.Attack
        atkAnimObj.Parent = mobModel
        pcall(function()
            attackTrack = animator:LoadAnimation(atkAnimObj)
            attackTrack.Priority = Enum.AnimationPriority.Action
            attackTrack.Looped = false
        end)
    end

    local activeTrack
    local function playMoveAnim(useRun)
        local desired = useRun and runTrack or walkTrack
        if not desired then return end
        if activeTrack == desired and desired.IsPlaying then return end

        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track ~= desired and track ~= attackTrack then
                    track:Stop(0.15)
                end
            end
        end)

        pcall(function() desired:Play(0.15) end)
        activeTrack = desired
    end

    local function playIdleAnim()
        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track ~= idleTrack and track ~= attackTrack then
                    track:Stop(0.2)
                end
            end
        end)

        activeTrack = nil
        if idleTrack and not idleTrack.IsPlaying then
            pcall(function() idleTrack:Play(0.2) end)
        end
    end

    local function enforceAnim()
        if isAttacking then return end
        local root = getRootPart(mobModel)
        if not root or not root:IsA("BasePart") then return end

        local vel = root.AssemblyLinearVelocity or root.Velocity
        local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        if hSpeed > 0.75 then
            playMoveAnim(chasing)
        else
            playIdleAnim()
        end
    end

    local function startWalking(dest, useRun)
        humanoid:MoveTo(dest)
        moving = true
        stationaryTicks = 0
        lastMoveTarget = dest
        lastMoveCommandAt = os.clock()
        playMoveAnim(useRun)
    end

    local function startWalkingSmart(dest, useRun)
        local now = os.clock()
        local shouldIssue = false

        if not lastMoveTarget then
            shouldIssue = true
        elseif (dest - lastMoveTarget).Magnitude >= REPATH_DISTANCE then
            shouldIssue = true
        elseif (now - lastMoveCommandAt) >= REPATH_INTERVAL then
            shouldIssue = true
        end

        if shouldIssue then
            startWalking(dest, useRun)
        end
    end

    local function stopWalking()
        moving = false
        stationaryTicks = 0
        local root = getRootPart(mobModel)
        if root then
            humanoid:MoveTo(root.Position)
        end
        lastMoveTarget = nil
        playIdleAnim()
    end

    humanoid.Running:Connect(function(speed)
        if isAttacking then return end
        if speed > 0.5 then
            playMoveAnim(chasing)
        else
            playIdleAnim()
        end
    end)

    humanoid.StateChanged:Connect(function(_, newState)
        if isAttacking then return end
        if newState == Enum.HumanoidStateType.Running or newState == Enum.HumanoidStateType.RunningNoPhysics then
            enforceAnim()
        end
    end)

    humanoid.MoveToFinished:Connect(function()
        if chasing then return end
        local root = getRootPart(mobModel)
        if root and root:IsA("BasePart") then
            local vel = root.AssemblyLinearVelocity or root.Velocity
            local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if hSpeed > 0.75 then return end
        end
        stopWalking()
    end)

    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local mobSoundsFolder = soundsFolder and soundsFolder:FindFirstChild("Mobs")
    local mobSwingTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild("MobSwing")
    local mobHitTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild("MobHit")
    local orcNoiseTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild("OrcNoise")
    local goblinNoiseTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild("GoblinNoise")
    local goblinDeathTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild("GoblinDeath")

    local function playTemplateSound(template, parentPart)
        if not template or not template:IsA("Sound") then return end
        local parentObj = parentPart or getRootPart(mobModel) or mobModel
        if not parentObj then return end
        local s = template:Clone()
        s.Parent = parentObj
        s:Play()
        Debris:AddItem(s, 4)
    end

    local function playOrcNoise()
        if not isOrc then return end
        local now = os.clock()
        if (now - lastOrcNoiseProcAt) < ORC_NOISE_COOLDOWN then return end
        if math.random() < ORC_NOISE_CHANCE then
            lastOrcNoiseProcAt = now
            playTemplateSound(orcNoiseTemplate, getRootPart(mobModel) or mobModel)
        end
    end

    -- Goblin: GoblinNoise plays on attack or aggro (shared cooldown with GoblinDeath)
    local function playGoblinNoise()
        if not isGoblin then return end
        local now = os.clock()
        if (now - lastGoblinNoiseProcAt) < GOBLIN_NOISE_COOLDOWN then return end
        if math.random() < GOBLIN_NOISE_CHANCE then
            lastGoblinNoiseProcAt = now
            playTemplateSound(goblinNoiseTemplate, getRootPart(mobModel) or mobModel)
        end
    end

    -- Goblin: GoblinDeath plays randomly when the goblin takes damage (shared cooldown with GoblinNoise)
    local function playGoblinDeath()
        if not isGoblin then return end
        local now = os.clock()
        if (now - lastGoblinNoiseProcAt) < GOBLIN_NOISE_COOLDOWN then return end
        if math.random() < GOBLIN_NOISE_CHANCE then
            lastGoblinNoiseProcAt = now
            playTemplateSound(goblinDeathTemplate, getRootPart(mobModel) or mobModel)
        end
    end

    local function performAttack(targetRoot)
        if isAttacking then return end
        if not mobModel.Parent or humanoid.Health <= 0 then return end

        local now = os.clock()
        if now < forcedRetreatUntil then return end
        if now - lastSwingEnd < ATTACK_COOLDOWN then return end

        isAttacking = true

        -- Every mob attack swing plays MobSwing.
        playTemplateSound(mobSwingTemplate, getRootPart(mobModel) or mobModel)
        -- Orc-specific flavor: 25% chance to play OrcNoise on attack (3s proc cooldown).
        playOrcNoise()
        -- Goblin-specific flavor: 25% chance to play GoblinNoise on attack (3s shared cooldown).
        playGoblinNoise()

        if attackTrack then
            pcall(function()
                local len = attackTrack.Length
                if len > 0 and ATTACK_WINDUP > 0 then
                    attackTrack:AdjustSpeed(len / ATTACK_WINDUP)
                end
                attackTrack:Play(0.08)
            end)
        end

        task.wait(ATTACK_WINDUP)

        if not mobModel.Parent or humanoid.Health <= 0 then
            isAttacking = false
            return
        end

        local root = getRootPart(mobModel)
        local didHit = false
        if root then
            local boxCF = buildForwardBoxCFrame(root, HITBOX_OFFSET)

            if SHOW_HITBOX then
                local dbg = Instance.new("Part")
                dbg.Name = "_MobHitboxDebug"
                dbg.Anchored = true
                dbg.CanCollide = false
                dbg.CanTouch = false
                dbg.CanQuery = false
                dbg.Size = HITBOX_SIZE
                dbg.CFrame = boxCF
                dbg.Transparency = 0.5
                dbg.Color = HITBOX_COLOR
                dbg.Material = Enum.Material.Neon
                dbg.Parent = Workspace
                local tween = TweenService:Create(dbg, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 })
                tween:Play()
                Debris:AddItem(dbg, 0.6)
            end

            local parts = Workspace:GetPartBoundsInBox(boxCF, HITBOX_SIZE)
            local hitHumanoids = {}
            if parts then
                for _, part in ipairs(parts) do
                    if not part or not part:IsA("BasePart") then continue end
                    local model = part:FindFirstAncestorOfClass("Model")
                    if not model or model == mobModel then continue end
                    local victimHum = model:FindFirstChildOfClass("Humanoid")
                    if not victimHum or victimHum.Health <= 0 then continue end
                    local ply = Players:GetPlayerFromCharacter(model)
                    if not ply then continue end
                    if hitHumanoids[victimHum] then continue end
                    hitHumanoids[victimHum] = ply
                end
            end

            for victimHum, ply in pairs(hitHumanoids) do
                didHit = true

                -- Tag the player victim with this NPC as the attacker so that
                -- KillTracker can show a kill card crediting the monster on death.
                if _G.RegisterMobCombatHit then
                    pcall(function() _G.RegisterMobCombatHit(victimHum, mobModel) end)
                end

                victimHum:TakeDamage(ATTACK_DAMAGE)

                local victimChar = victimHum.Parent
                -- Quick whole-character flash so players can clearly read incoming damage.
                playDamageFlash(victimChar)
                local victimRoot = victimChar and (victimChar:FindFirstChild("HumanoidRootPart") or victimChar:FindFirstChild("Torso"))
                if victimRoot then
                    pcall(function()
                        applyVictimKnockback(victimRoot, root, HIT_KNOCKBACK, HIT_KNOCKBACK_Y)
                    end)
                end

                if victimHum.Health <= 0 and zombieKillEvent then
                    pcall(function() zombieKillEvent:FireClient(ply) end)
                end

                -- If a player gets hit by a mob, play MobHit on the victim.
                local parentForSound = (victimChar and (victimChar:FindFirstChild("HumanoidRootPart") or victimChar:FindFirstChildWhichIsA("BasePart"))) or mobModel
                playTemplateSound(mobHitTemplate, parentForSound)
            end

            local vel = root.AssemblyLinearVelocity or root.Velocity
            local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if (hSpeed < STUCK_SPEED_THRESHOLD) and (not didHit) then
                stuckMissesWhileStationary = stuckMissesWhileStationary + 1
                if stuckMissesWhileStationary >= STUCK_MISS_THRESHOLD then
                    forcedRetreatUntil = os.clock() + STUCK_RETREAT_TIME
                    stuckMissesWhileStationary = 0
                end
            else
                stuckMissesWhileStationary = 0
            end
        end

        lastSwingEnd = os.clock()
        isAttacking = false
    end

    local prevHealth = humanoid.Health
    updateSpeedByState()
    humanoid.HealthChanged:Connect(function(newHealth)
        if newHealth < prevHealth then
            if USE_ENRAGED then
                isEnraged = true
            end

            -- Orc-specific flavor: 25% chance to play OrcNoise when damaged (3s proc cooldown).
            playOrcNoise()
            -- Goblin-specific flavor: 25% chance to play GoblinDeath when damaged (3s shared cooldown).
            playGoblinDeath()

            local attackerId = humanoid:GetAttribute("lastDamagerUserId")
            if attackerId then
                local attacker = Players:GetPlayerByUserId(attackerId)
                if attacker and attacker.Character then
                    local aHum = attacker.Character:FindFirstChildOfClass("Humanoid")
                    if aHum and aHum.Health > 0 then
                        aggroPlayer = attacker
                        aggroExpiry = os.clock() + AGGRO_DURATION
                    end
                end
            end
        end

        updateSpeedByState()
        prevHealth = newHealth
    end)

    local areaCenter = areaPart and areaPart:IsA("BasePart") and areaPart.Position or nil
    local areaSize = areaPart and areaPart:IsA("BasePart") and areaPart.Size or nil
    local lastWander = 0
    local wanderCooldown = math.random(3, 7)

    task.spawn(function()
        while aiRunning and mobModel and mobModel.Parent and humanoid and humanoid.Health > 0 do
            local root = getRootPart(mobModel)
            if not root then break end

            local targetRoot, dist
            if aggroPlayer and os.clock() < aggroExpiry then
                local ch = aggroPlayer.Character
                if ch then
                    local aHum = ch:FindFirstChildOfClass("Humanoid")
                    local aRoot = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
                    if aHum and aHum.Health > 0 and aRoot then
                        targetRoot = aRoot
                        dist = (aRoot.Position - root.Position).Magnitude
                    else
                        aggroPlayer = nil
                    end
                else
                    aggroPlayer = nil
                end
            end

            if not targetRoot then
                local _, nr, nd = nearestPlayer(root.Position, DETECTION_RADIUS)
                targetRoot = nr
                dist = nd
            end

            if targetRoot and dist then
                local wasChasing = chasing
                chasing = true
                -- Orc-specific flavor: 25% chance to play OrcNoise when first aggroed (3s proc cooldown).
                if (not wasChasing) and isOrc then
                    playOrcNoise()
                end
                -- Goblin-specific flavor: 25% chance to play GoblinNoise when first aggroed (3s shared cooldown).
                if (not wasChasing) and isGoblin then
                    playGoblinNoise()
                end
                updateSpeedByState()

                local targetPos = targetRoot.Position
                local horizontalDelta = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
                local horizontalDist = horizontalDelta.Magnitude
                local retreating = os.clock() < forcedRetreatUntil

                if retreating and horizontalDist > 0.05 then
                    local awayDir = -horizontalDelta.Unit
                    local retreatPos = root.Position + awayDir * (MIN_SPACING * 2)
                    startWalkingSmart(Vector3.new(retreatPos.X, root.Position.Y, retreatPos.Z), true)
                else
                    if horizontalDist > MIN_SPACING then
                        if not humanoid.AutoRotate then
                            humanoid.AutoRotate = true
                        end
                        local dir = horizontalDelta.Unit
                        -- Overshoot past the target so the humanoid never decelerates before entering attack range.
                        local movePos = targetPos + dir * MIN_SPACING
                        startWalkingSmart(Vector3.new(movePos.X, root.Position.Y, movePos.Z), true)
                    else
                        stopWalking()
                    end
                end

                if (not retreating) and dist <= ATTACK_RANGE then
                    task.spawn(performAttack, targetRoot)
                end
            else
                if chasing then
                    chasing = false
                    -- Restore auto-rotate now that we are no longer locked onto a target.
                    humanoid.AutoRotate = true
                    updateSpeedByState()

                    local dest
                    if areaCenter and areaSize then
                        dest = randomPointInArea(areaPart)
                    else
                        local a = math.random() * math.pi * 2
                        local r = math.random(3, 12)
                        dest = spawnPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                    end
                    startWalking(dest, false)
                    lastWander = tick()
                    wanderCooldown = math.random(3, 7)
                end

                updateSpeedByState()
                if tick() - lastWander >= wanderCooldown then
                    lastWander = tick()
                    wanderCooldown = math.random(3, 7)

                    if math.random() < 0.3 then
                        stopWalking()
                    else
                        local dest
                        if areaCenter and areaSize then
                            dest = randomPointInArea(areaPart)
                        else
                            local a = math.random() * math.pi * 2
                            local r = math.random(3, 12)
                            dest = spawnPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                        end
                        startWalking(dest, false)
                    end
                else
                    if moving and root:IsA("BasePart") then
                        local vel = root.AssemblyLinearVelocity or root.Velocity
                        local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
                        if hSpeed < 0.3 then
                            stationaryTicks = stationaryTicks + 1
                            if stationaryTicks >= 5 then
                                stopWalking()
                            end
                        else
                            stationaryTicks = 0
                        end
                    end
                end
            end

            if not isAttacking then
                enforceAnim()
            end

            task.wait(0.2)
        end

        aiRunning = false
    end)

    humanoid.Died:Connect(function()
        aiRunning = false
        stopWalking()

        if mobTag then
            pcall(function() CollectionService:RemoveTag(mobModel, mobTag) end)
        end

        task.delay(destroyDelay, function()
            if mobModel and mobModel.Parent then
                mobModel:Destroy()
            end
        end)
    end)

    return {
        Stop = function()
            aiRunning = false
        end,
    }
end

return MobCombat
