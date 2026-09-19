local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local CombatUtils = require(ServerScriptService:WaitForChild("CombatUtils"))

local MobCombat = {}

local function defaultGetRootPart(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
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

local function isInsideAreaXZ(worldPos, areaPart, padding)
    if not areaPart or not areaPart:IsA("BasePart") then return false end
    local pad = padding or 0
    local localPos = areaPart.CFrame:PointToObjectSpace(worldPos)
    local half = areaPart.Size * 0.5
    return math.abs(localPos.X) <= (half.X + pad)
        and math.abs(localPos.Z) <= (half.Z + pad)
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

    -- Apply configured MaxHealth if provided in the mob config.
    -- Prefer `MaxHealth` (explicit) but also accept `Health` for compatibility.
    local desiredMaxHealth = nil
    if mobConfig then
        desiredMaxHealth = mobConfig.MaxHealth or mobConfig.Health
    end
    if type(desiredMaxHealth) == "number" then
        local hp = math.max(1, math.floor(desiredMaxHealth))
        pcall(function()
            humanoid.MaxHealth = hp
            humanoid.Health = hp
        end)
    end

    local WALK_SPEED = cfgMove.WalkSpeed or 10
    local CHASE_SPEED = cfgMove.ChaseSpeed or 14
    local ENRAGED_SPEED = cfgMove.EnragedSpeed or CHASE_SPEED
    local USE_ENRAGED = (cfgMove.UseEnraged == true)
    local DETECTION_RADIUS = cfgMove.DetectionRadius or 20
    local AGGRO_DURATION = cfgMove.AggroDuration or 8
    local STUCK_JUMP_DELAY = cfgMove.StuckJumpDelay or 1.25
    local STUCK_JUMP_COOLDOWN = cfgMove.StuckJumpCooldown or 2.5
    local STUCK_JUMP_MAX_TARGET_HEIGHT = cfgMove.StuckJumpMaxTargetHeight or 6

    local ATTACK_DAMAGE = cfgAtk.Damage or 12
    local ATTACK_COOLDOWN = cfgAtk.Cooldown or 1
    local ATTACK_RANGE = cfgAtk.Range or 6
    local ATTACK_WINDUP = cfgAtk.Windup or 0.45
    local ATTACK_SOUND = cfgAtk.Sound or "MobSwing"
    local baseHitboxSize = cfgAtk.HitboxSize or Vector3.new(5, 6, 5)
    local hitboxDepth = baseHitboxSize.Z * (cfgAtk.HitboxDepthMultiplier or 0.8)
    local HITBOX_SIZE = Vector3.new(
        baseHitboxSize.X * (cfgAtk.HitboxWidthMultiplier or 1.2),
        baseHitboxSize.Y,
        hitboxDepth
    )
    local baseHitboxOffset = cfgAtk.HitboxOffset or Vector3.new(0, 0, 3)
    -- Keep the near edge in place; remove reach from the far end of the swing.
    local HITBOX_OFFSET = baseHitboxOffset - Vector3.new(0, 0, (baseHitboxSize.Z - hitboxDepth) * 0.5)
    local HIT_KNOCKBACK = cfgAtk.Knockback or 50
    local HIT_KNOCKBACK_Y = cfgAtk.KnockbackY or 12
    local MIN_SPACING = cfgAtk.MinimumSpacingDistance or 3.5
    local SWING_START_RANGE = math.min(ATTACK_RANGE, HITBOX_OFFSET.Z + HITBOX_SIZE.Z * 0.5)
    -- Leave room for MoveTo's arrival tolerance, especially for short Goblin swings.
    local APPROACH_SPACING = math.min(MIN_SPACING, math.max(0.5, SWING_START_RANGE - 1))
    local ORC_NOISE_CHANCE = 0.25
    local ORC_NOISE_COOLDOWN = 3
    local isOrc = (mobModel.Name == "Orc")
    local isOgre = (mobModel.Name == "Ogre")
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
    local aiRunning = true

    local lastMoveTarget = nil
    local lastMoveCommandAt = 0
    local REPATH_INTERVAL = 0.20
    local REPATH_DISTANCE = 1.5
    local lastOrcNoiseProcAt = os.clock() -- start at now so full cooldown must expire before first noise (prevents spawn-time audio pop)
    local lastGoblinNoiseProcAt = os.clock() -- shared cooldown for both GoblinNoise and GoblinDeath
    local facingTarget = nil
    local attackTarget = nil
    local TURN_RESPONSE = 12

    HumanoidStatService:EnsureHumanoidSubject(humanoid)
    HumanoidStatService:SetBaseStat(humanoid, MOVEMENT_SPEED_STAT, WALK_SPEED)
    humanoid.AutoRotate = true

    local lastBaseSpeed = WALK_SPEED
    local function setMobSpeed(speed)
        if speed == lastBaseSpeed then return end
        lastBaseSpeed = speed
        HumanoidStatService:SetBaseStat(humanoid, MOVEMENT_SPEED_STAT, speed)
    end

    -- Turn through physics when stationary; root CFrame writes can visibly snap
    -- a colliding/animated rig and cancel its current MoveTo command.
    local facingAlign, facingAttachment
    local function disableFacing()
        if facingAlign then facingAlign.Enabled = false end
        humanoid.AutoRotate = true
    end
    local function clearFacing()
        disableFacing()
        if facingAlign then facingAlign:Destroy(); facingAlign = nil end
        if facingAttachment then facingAttachment:Destroy(); facingAttachment = nil end
    end
    local facingConnection
    facingConnection = RunService.Heartbeat:Connect(function()
        if not aiRunning or not mobModel.Parent or humanoid.Health <= 0 then
            facingConnection:Disconnect()
            clearFacing()
            return
        end
        if moving then
            disableFacing()
            return
        end
        local root = getRootPart(mobModel)
        local target = attackTarget or facingTarget
        local targetHumanoid = target and target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
        if not root or not target or not target.Parent or not targetHumanoid or targetHumanoid.Health <= 0 then
            disableFacing()
            return
        end
        humanoid.AutoRotate = false
        local delta = Vector3.new(target.Position.X - root.Position.X, 0, target.Position.Z - root.Position.Z)
        if delta.Magnitude > 0.05 then
            if not facingAlign then
                facingAttachment = Instance.new("Attachment")
                facingAttachment.Name = "_MobFacingAttachment"
                facingAttachment.Parent = root
                facingAlign = Instance.new("AlignOrientation")
                facingAlign.Name = "_MobFacing"
                facingAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
                facingAlign.Attachment0 = facingAttachment
                facingAlign.RigidityEnabled = false
                facingAlign.Responsiveness = TURN_RESPONSE
                facingAlign.MaxTorque = 1e6
                facingAlign.MaxAngularVelocity = math.rad(360)
                facingAlign.Enabled = false
                facingAlign.Parent = root
            end
            facingAlign.CFrame = CFrame.lookAt(Vector3.zero, delta)
            facingAlign.Enabled = true
        end
    end)

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

    local jumpTrack
    local jumpAnimObj = Instance.new("Animation")
    jumpAnimObj.Name = "Jump_Mob"
    jumpAnimObj.AnimationId = cfgAnim.Jump or "rbxassetid://734326930"
    jumpAnimObj.Parent = mobModel
    pcall(function()
        jumpTrack = animator:LoadAnimation(jumpAnimObj)
        jumpTrack.Priority = Enum.AnimationPriority.Action
        jumpTrack.Looped = false
    end)

    local activeTrack
    local function playMoveAnim(useRun)
        local desired = useRun and runTrack or walkTrack
        if not desired then return end
        if activeTrack == desired and desired.IsPlaying then return end

        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track ~= desired and track ~= attackTrack and track ~= jumpTrack then
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
                if track ~= idleTrack and track ~= attackTrack and track ~= jumpTrack then
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
        if not moving and not lastMoveTarget then return end
        moving = false
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
        if newState == Enum.HumanoidStateType.Jumping then
            if jumpTrack then jumpTrack:Play(0.1) end
        elseif newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Dead then
            if jumpTrack then jumpTrack:Stop(0.15) end
        end
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

    local progressPosition = nil
    local progressAt = os.clock()
    local lastRecoveryJump = -math.huge
    local function updateStuckRecovery(root, targetRoot)
        local now = os.clock()
        local position = root.Position
        local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
        local targetTooHigh = targetRoot and targetRoot.Position.Y - position.Y > STUCK_JUMP_MAX_TARGET_HEIGHT
        if not moving or isAttacking or humanoid.WalkSpeed <= 0 or not grounded or targetTooHigh then
            progressPosition, progressAt = position, now
            return
        end
        local progress = progressPosition and Vector3.new(
            position.X - progressPosition.X, 0, position.Z - progressPosition.Z
        ).Magnitude or math.huge
        if progress >= 0.5 then
            progressPosition, progressAt = position, now
            return
        end
        if now - progressAt >= STUCK_JUMP_DELAY and now - lastRecoveryJump >= STUCK_JUMP_COOLDOWN
            and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
            humanoid.Jump = true
            lastRecoveryJump = now
            progressPosition, progressAt = position, now
        end
    end

    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local mobSoundsFolder = soundsFolder and soundsFolder:FindFirstChild("Mobs")
    local attackSwingTemplate = mobSoundsFolder and mobSoundsFolder:FindFirstChild(ATTACK_SOUND)
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
        if not isOrc and not isOgre then return end
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
        if not aiRunning or not mobModel.Parent or humanoid.Health <= 0 then return end
        if not targetRoot or not targetRoot.Parent then return end
        if humanoid.FloorMaterial == Enum.Material.Air then return end

        local now = os.clock()
        if now - lastSwingEnd < ATTACK_COOLDOWN then return end

        isAttacking = true
        attackTarget = targetRoot
        stopWalking()

        playTemplateSound(attackSwingTemplate, getRootPart(mobModel) or mobModel)
        -- Orc-specific flavor: 25% chance to play OrcNoise on attack (3s proc cooldown).
        playOrcNoise()
        -- Goblin-specific flavor: 25% chance to play GoblinNoise on attack (3s shared cooldown).
        playGoblinNoise()

        if attackTrack then
            pcall(function()
                local len = attackTrack.Length
                local speed = (len > 0 and ATTACK_WINDUP > 0) and (len / ATTACK_WINDUP) or 1
                attackTrack:Play(0.08, 1, speed)
            end)
        end

        task.wait(ATTACK_WINDUP)

        if not aiRunning or not mobModel.Parent or humanoid.Health <= 0 then
            isAttacking = false
            attackTarget = nil
            return
        end

        local root = getRootPart(mobModel)
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
                    if CombatUtils and (CombatUtils.isPodiumAvatar(model) or CombatUtils.isPodiumPart(part)) then
                        continue
                    end
                    local victimHum = model:FindFirstChildOfClass("Humanoid")
                    if not victimHum or victimHum.Health <= 0 then continue end
                    local ply = Players:GetPlayerFromCharacter(model)
                    if not ply then continue end
                    if hitHumanoids[victimHum] then continue end
                    hitHumanoids[victimHum] = ply
                end
            end

            for victimHum, ply in pairs(hitHumanoids) do
                local victimChar = victimHum and victimHum.Parent
                if CombatUtils and CombatUtils.isPodiumAvatar(victimChar) then
                    -- Ignore podium avatars
                    if _G.DEBUG_COMBAT then print("[Combat] Ignored podium avatar mob hit:", victimChar and victimChar.Name) end
                    continue
                end

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
        end

        lastSwingEnd = os.clock()
        isAttacking = false
        attackTarget = nil
    end

    local attackSightParams = RaycastParams.new()
    attackSightParams.FilterType = Enum.RaycastFilterType.Exclude
    attackSightParams.FilterDescendantsInstances = { mobModel }
    attackSightParams.IgnoreWater = true
    attackSightParams.RespectCanCollide = true
    local function hasAttackSight(root, targetRoot)
        local result = Workspace:Raycast(root.Position, targetRoot.Position - root.Position, attackSightParams)
        return not result or result.Instance:IsDescendantOf(targetRoot.Parent)
    end

    local areaCenter, areaSize, areaLockActive

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

            local suppressAggroUntil = humanoid:GetAttribute("SuppressMobAggroUntil")
            local attackerId = humanoid:GetAttribute("lastDamagerUserId")
            if type(suppressAggroUntil) == "number" and suppressAggroUntil >= os.clock() then
                attackerId = nil
            end
            if attackerId then
                local attacker = Players:GetPlayerByUserId(attackerId)
                if attacker and attacker.Character then
                    local aHum = attacker.Character:FindFirstChildOfClass("Humanoid")
                    if aHum and aHum.Health > 0 then
                        areaLockActive = false
                        aggroPlayer = attacker
                        aggroExpiry = os.clock() + AGGRO_DURATION
                    end
                end
            end
        end

        updateSpeedByState()
        prevHealth = newHealth
    end)

    areaCenter = areaPart and areaPart:IsA("BasePart") and areaPart.Position or nil
    areaSize = areaPart and areaPart:IsA("BasePart") and areaPart.Size or nil
    areaLockActive = areaPart and areaPart:IsA("BasePart") or false
    local AREA_LOCK_PADDING = 1.5
    local lastWander = 0
    local wanderCooldown = math.random(3, 7)

    task.spawn(function()
        while aiRunning and mobModel and mobModel.Parent and humanoid and humanoid.Health > 0 do
            local root = getRootPart(mobModel)
            if not root then break end

            if areaLockActive and areaCenter then
                if isInsideAreaXZ(root.Position, areaPart, AREA_LOCK_PADDING) then
                    areaLockActive = false
                    stopWalking()
                else
                    -- Force a clean first move into the assigned lane before aggro/wander.
                    chasing = false
                    facingTarget = nil
                    aggroPlayer = nil
                    updateSpeedByState()
                    startWalkingSmart(Vector3.new(areaCenter.X, root.Position.Y, areaCenter.Z), false)
                    updateStuckRecovery(root, nil)
                    if not isAttacking then
                        enforceAnim()
                    end
                    task.wait(0.2)
                    continue
                end
            end

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
                facingTarget = targetRoot
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
                -- Stop on the near side of the target, instead of crossing them
                -- and flipping the travel direction on every AI update.
                local resumeDistance = APPROACH_SPACING + (moving and 0 or 0.5)
                if isAttacking then
                    stopWalking()
                elseif horizontalDist > resumeDistance then
                    local movePos = targetPos - horizontalDelta.Unit * APPROACH_SPACING
                    startWalkingSmart(Vector3.new(movePos.X, root.Position.Y, movePos.Z), true)
                else
                    stopWalking()
                end

                -- A wall-blocked swing would repeatedly reset stuck detection.
                -- Keep trying to approach/recover until the player is reachable.
                if dist <= SWING_START_RANGE and hasAttackSight(root, targetRoot) then
                    task.spawn(performAttack, targetRoot)
                end
            else
                facingTarget = nil
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
                end
            end

            if not isAttacking then
                enforceAnim()
            end
            updateStuckRecovery(root, targetRoot)

            task.wait(0.1)
        end

        aiRunning = false
    end)

    humanoid.Died:Connect(function()
        aiRunning = false
        facingConnection:Disconnect()
        clearFacing()
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
            facingConnection:Disconnect()
            clearFacing()
            stopWalking()
        end,
    }
end

return MobCombat
