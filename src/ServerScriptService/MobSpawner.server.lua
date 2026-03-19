local Workspace         = game:GetService("Workspace")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local PhysicsService    = game:GetService("PhysicsService")

---------------------------------------------------------------------------
-- Collision group: mobs don't collide with each other
---------------------------------------------------------------------------
local MOB_COLLISION_GROUP = "Mobs"
pcall(function() PhysicsService:RegisterCollisionGroup(MOB_COLLISION_GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(MOB_COLLISION_GROUP, MOB_COLLISION_GROUP, false) end)

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
-- list of template names (ServerStorage.Mobs or ServerStorage)
local TEMPLATE_NAMES     = { "Zombie", "Zack", "Orc", "Ogre" }
local PORTAL_GROUP_NAMES = { "DarkPortal1", "DarkPortal2" }
local PORTAL_PART_NAME   = "PortalPlane"
local MOB_AREA_PREFIX    = "MobArea"

local SPAWN_INTERVAL     = 5
local SPAWN_BATCH        = 1
local MAX_PER_PORTAL     = 4
local MAX_TOTAL          = 8

-- defaults (overridden per-mob via MobSettings)
local DEFAULT_DETECTION_RADIUS = 40
local DEFAULT_WALK_SPEED      = 16
local DEFAULT_CHASE_SPEED     = 25
local DEFAULT_ATTACK_RANGE    = 6
local DEFAULT_AGGRO_DURATION  = 12
local MOB_TAG                 = "ZombieNPC"
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- optional per-mob settings module (put presets keyed by template Name)
local MobSettings
if ReplicatedStorage:FindFirstChild("MobSettings") then
    MobSettings = require(ReplicatedStorage:WaitForChild("MobSettings"))
end

-- Create ZombieKill remote up front so the client can connect immediately
local zombieKillEvent = ReplicatedStorage:FindFirstChild("ZombieKill")
if not zombieKillEvent then
    zombieKillEvent = Instance.new("RemoteEvent")
    zombieKillEvent.Name = "ZombieKill"
    zombieKillEvent.Parent = ReplicatedStorage
end

-- Default R6 walk animation (used when template has no Walk animation)
local DEFAULT_WALK_ANIM_ID = "rbxassetid://180426354"

---------------------------------------------------------------------------
-- Find template
---------------------------------------------------------------------------
local function findTemplates()
    local out = {}
    local mobsFolder = ServerStorage:FindFirstChild("Mobs")
    for _, name in ipairs(TEMPLATE_NAMES) do
        local t = nil
        if mobsFolder then
            t = mobsFolder:FindFirstChild(name)
            if t then
                table.insert(out, t)
                print("[MobSpawner] Template '" .. name .. "' found in ServerStorage.Mobs")
                continue
            end
        end
        t = ServerStorage:FindFirstChild(name)
        if t then
            table.insert(out, t)
            print("[MobSpawner] Template '" .. name .. "' found in ServerStorage")
        else
            warn("[MobSpawner] Template '" .. name .. "' not found in ServerStorage or ServerStorage.Mobs")
        end
    end
    return out
end

local templates = findTemplates()

---------------------------------------------------------------------------
-- Weighted random selection
---------------------------------------------------------------------------
-- Build a flat pool where each template appears N times based on its
-- spawn_chance value from MobSettings (default 1).  Picking a random
-- entry from this pool gives exact weighted probability.
local weightedPool = {}

local function rebuildWeightedPool()
    table.clear(weightedPool)
    local disabledCount = 0
    for _, tpl in ipairs(templates) do
        local cfg = (MobSettings and MobSettings.presets and MobSettings.presets[tpl.Name]) or {}
        local weight = math.floor(tonumber(cfg.spawn_chance) or 1)
        if weight > 0 then
            for _ = 1, weight do
                table.insert(weightedPool, tpl)
            end
        else
            disabledCount = disabledCount + 1
            print("[MobSpawner] Template '" .. tostring(tpl.Name) .. "' disabled (spawn_chance=" .. tostring(cfg.spawn_chance) .. ")")
        end
    end
    print("[MobSpawner] Weighted pool size: " .. #weightedPool .. " entries across " .. #templates .. " template(s)" .. (disabledCount > 0 and (" (" .. disabledCount .. " disabled)") or ""))
end

rebuildWeightedPool()

local function pickWeightedTemplate()
    if #weightedPool == 0 then return nil end
    return weightedPool[math.random(1, #weightedPool)]
end

---------------------------------------------------------------------------
-- Portal discovery → { {portal, area, groupName}, … }
---------------------------------------------------------------------------
local function findPortals()
    local out = {}
    for idx, groupName in ipairs(PORTAL_GROUP_NAMES) do
        local group = Workspace:FindFirstChild(groupName)
        if not group then warn("[MobSpawner] Missing group: " .. groupName) continue end
        local areaName = MOB_AREA_PREFIX .. tostring(idx)
        local areaPart = Workspace:FindFirstChild(areaName)
        if not areaPart then warn("[MobSpawner] Missing area: " .. areaName) end
        for _, v in ipairs(group:GetDescendants()) do
            if v:IsA("BasePart") and v.Name == PORTAL_PART_NAME then
                table.insert(out, { portal = v, area = areaPart, groupName = groupName })
            end
        end
    end
    print("[MobSpawner] Discovered " .. #out .. " portal(s)")
    return out
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function getRootPart(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function nearestPlayer(pos, detectionRadius)
    local radius = detectionRadius or DEFAULT_DETECTION_RADIUS
    local best, bestDist, bestRoot
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        if not ch then continue end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local root = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
        if not root then continue end
        local d = (root.Position - pos).Magnitude
        if d <= radius and (not bestDist or d < bestDist) then
            best, bestDist, bestRoot = p, d, root
        end
    end
    return best, bestRoot, bestDist
end

local function randomPointInArea(areaPart)
    local c, s = areaPart.Position, areaPart.Size
    return Vector3.new(c.X + (math.random() - 0.5) * s.X, c.Y, c.Z + (math.random() - 0.5) * s.Z)
end

---------------------------------------------------------------------------
-- Spawn one mob
---------------------------------------------------------------------------
local function spawnZombie(portalPart, areaPart, tpl)
    local tplToUse = tpl or templates and templates[1]
    if not tplToUse then return nil end

    -- resolve per-template config early
    local tplName = tplToUse and tplToUse.Name or "Unknown"
    local mobCfg = (MobSettings and MobSettings.presets and MobSettings.presets[tplName]) or {}

    local z = tplToUse:Clone()
    -- name the spawned instance after its template so it matches the source
    if tplToUse and tplToUse.Name then
        z.Name = tplToUse.Name
    end
    z.Parent = Workspace

    -- position at bottom of portal
    local root = getRootPart(z)
    local rootHalfY = (root and root:IsA("BasePart")) and (root.Size.Y / 2 + 0.5) or 2
    local spawnPos  = portalPart.Position - Vector3.new(0, portalPart.Size.Y / 2 + rootHalfY, 0)
    pcall(function()
        if not z.PrimaryPart and root then z.PrimaryPart = root end
        if z.PrimaryPart then
            z:SetPrimaryPartCFrame(CFrame.new(spawnPos))
        elseif root then
            root.CFrame = CFrame.new(spawnPos)
        end
    end)

    local mobTag = (mobCfg.tag and type(mobCfg.tag) == "string" and mobCfg.tag ~= "") and mobCfg.tag or MOB_TAG
    CollectionService:AddTag(z, mobTag)

    -- unanchor so physics / humanoid work; assign mob collision group
    for _, d in ipairs(z:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            d.CanCollide = true
            d.CollisionGroup = MOB_COLLISION_GROUP
        end
    end

    -- Special-case: ensure Orcs' Axe weapon parts don't collide or fire Touched events
    if z.Name == "Orc" then
        for _, d in ipairs(z:GetDescendants()) do
            if d and d:IsA("BasePart") and d.Name == "Axe" then
                pcall(function()
                    d.CanCollide = false
                    d.CanTouch = false
                    d.CanQuery = false
                    d.Massless = true
                end)
            end
            if d and d:IsA("Tool") and d.Name == "Axe" then
                for _, p in ipairs(d:GetDescendants()) do
                    if p and p:IsA("BasePart") then
                        pcall(function()
                            p.CanCollide = false
                            p.CanTouch = false
                            p.CanQuery = false
                            p.Massless = true
                        end)
                    end
                end
            end
        end
    end

    local humanoid = z:FindFirstChildOfClass("Humanoid")
    if not humanoid then warn("[MobSpawner] Template '" .. (tplToUse and tplToUse.Name or "Unknown") .. "' has no Humanoid!") return z end
    local MOB_WALK_SPEED = mobCfg.walk_speed or DEFAULT_WALK_SPEED
    local MOB_CHASE_SPEED = mobCfg.chase_speed or DEFAULT_CHASE_SPEED
    local MOB_ENRAGED_SPEED = mobCfg.enraged_speed or MOB_CHASE_SPEED
    local ENRAGED_ENABLED = (mobCfg.enraged == true)
    local isEnraged = false  -- permanently set once damaged (if enraged enabled)
    local MOB_ATTACK_RANGE = mobCfg.attack_range or DEFAULT_ATTACK_RANGE
    local MOB_DETECTION_RADIUS = mobCfg.detection_radius or DEFAULT_DETECTION_RADIUS
    local MOB_AGGRO_DURATION = mobCfg.aggro_duration or DEFAULT_AGGRO_DURATION
    humanoid.WalkSpeed  = MOB_WALK_SPEED
    humanoid.AutoRotate = true
    -- attack setup (resolve per-template values if provided)
    local ATTACK_DAMAGE   = mobCfg.attack_damage   or 60
    local ATTACK_COOLDOWN = mobCfg.attack_cooldown  or 1   -- minimum seconds between swings
    local ATTACK_WINDUP   = mobCfg.attack_windup    or 1   -- seconds locked in place before hitbox fires
    local HITBOX_SIZE     = mobCfg.hitbox_size       or Vector3.new(4, 6, 4)
    local HITBOX_OFFSET   = mobCfg.hitbox_offset     or Vector3.new(0, 0, 3)
    local SHOW_HITBOX     = (mobCfg.show_hitbox == true)
    local HITBOX_COLOR    = mobCfg.hitbox_color       or Color3.fromRGB(255, 50, 50)

    local isAttacking     = false   -- true while in the attack wind-up/swing
    local lastSwingEnd    = 0       -- os.clock() when last swing finished (for cooldown)

    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local attackSoundTemplate
    if soundsFolder then
        local key = mobCfg.attack_sound or "ZombieAttack"
        attackSoundTemplate = soundsFolder:FindFirstChild(key) or soundsFolder:FindFirstChild("Zombie_Attack")
    end

    -------------------------------------------------------------------
    -- Animator + walk/run tracks
    -------------------------------------------------------------------
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- Build walk animation object
    local walkAnimId = (mobCfg.walk_anim_id and mobCfg.walk_anim_id ~= "") and mobCfg.walk_anim_id or DEFAULT_WALK_ANIM_ID
    local walkAnimObj = Instance.new("Animation")
    walkAnimObj.Name        = "Walk_Mob"
    walkAnimObj.AnimationId = walkAnimId
    walkAnimObj.Parent      = z

    -- Build run animation object (falls back to walk if not set)
    local runAnimId = (mobCfg.run_anim_id and mobCfg.run_anim_id ~= "") and mobCfg.run_anim_id or walkAnimId
    local runAnimObj = Instance.new("Animation")
    runAnimObj.Name        = "Run_Mob"
    runAnimObj.AnimationId = runAnimId
    runAnimObj.Parent      = z

    -- Build idle animation object (optional)
    local idleTrack = nil
    if mobCfg.idle_anim_id and mobCfg.idle_anim_id ~= "" then
        local idleAnimObj = Instance.new("Animation")
        idleAnimObj.Name        = "Idle_Mob"
        idleAnimObj.AnimationId = mobCfg.idle_anim_id
        idleAnimObj.Parent      = z
        pcall(function()
            idleTrack          = animator:LoadAnimation(idleAnimObj)
            idleTrack.Priority = Enum.AnimationPriority.Idle
            idleTrack.Looped   = true
        end)
    end

    local walkTrack, runTrack
    local ok, err = pcall(function()
        walkTrack          = animator:LoadAnimation(walkAnimObj)
        walkTrack.Priority = Enum.AnimationPriority.Movement
        walkTrack.Looped   = true
        runTrack           = animator:LoadAnimation(runAnimObj)
        runTrack.Priority  = Enum.AnimationPriority.Movement
        runTrack.Looped    = true
    end)
    if not ok then warn("[MobSpawner] Anim load failed: " .. tostring(err)); walkTrack = nil; runTrack = nil end

    -- Build attack animation (optional – plays during wind-up)
    local attackTrack = nil
    if mobCfg.attack_anim_id and mobCfg.attack_anim_id ~= "" then
        local atkAnimObj = Instance.new("Animation")
        atkAnimObj.Name        = "Attack_Mob"
        atkAnimObj.AnimationId = mobCfg.attack_anim_id
        atkAnimObj.Parent      = z
        pcall(function()
            attackTrack          = animator:LoadAnimation(atkAnimObj)
            attackTrack.Priority = Enum.AnimationPriority.Action
            attackTrack.Looped   = false
        end)
    end

    -- play idle on spawn so the mob isn't T-posing
    if idleTrack then
        pcall(function() idleTrack:Play() end)
    end

    -- activeTrack points to whichever track is currently playing
    local activeTrack = nil

    -------------------------------------------------------------------
    -- Forward declarations for cross-referencing state
    -------------------------------------------------------------------
    local aggroPlayer = nil   -- Player who last damaged this mob
    local aggroExpiry = 0     -- os.clock() when aggro expires
    local moving = false
    local chasing = false     -- true while actively chasing a player
    local stationaryTicks = 0 -- consecutive AI ticks with near-zero velocity

    -- adjust speed based on enraged/aggro state
    local function updateSpeedByHealth(h)
        local maxH = humanoid.MaxHealth or 100
        if ENRAGED_ENABLED and h < maxH then
            isEnraged = true
            humanoid.WalkSpeed = MOB_ENRAGED_SPEED
        elseif aggroPlayer then
            humanoid.WalkSpeed = MOB_CHASE_SPEED
        else
            humanoid.WalkSpeed = MOB_WALK_SPEED
        end
    end

    -------------------------------------------------------------------
    -- Damage-based aggro: whoever shot us becomes the priority target
    -------------------------------------------------------------------

    local prevHealth = humanoid.Health
    -- apply immediately in case template spawns damaged
    updateSpeedByHealth(humanoid.Health)
    humanoid.HealthChanged:Connect(function(newHealth)
        -- detect damage (health went down)
        if newHealth < prevHealth then
            -- mark enraged permanently if enabled
            if ENRAGED_ENABLED then
                isEnraged = true
            end
            local attackerId = humanoid:GetAttribute("lastDamagerUserId")
            if attackerId then
                local attacker = Players:GetPlayerByUserId(attackerId)
                if attacker and attacker.Character then
                    local aHum = attacker.Character:FindFirstChildOfClass("Humanoid")
                    if aHum and aHum.Health > 0 then
                        aggroPlayer = attacker
                        aggroExpiry = os.clock() + MOB_AGGRO_DURATION
                    end
                end
            end
        end
        updateSpeedByHealth(newHealth)
        prevHealth = newHealth
    end)

    -------------------------------------------------------------------
    -- Hitbox-based melee attack
    -- When called, the mob locks in place for ATTACK_WINDUP seconds,
    -- then a GetPartBoundsInBox hitbox fires at the mob's front.
    -- Any player characters inside take ATTACK_DAMAGE.
    -------------------------------------------------------------------
    local function performAttack()
        if isAttacking then return end
        if not z or not z.Parent then return end
        if not humanoid or humanoid.Health <= 0 then return end
        local now = os.clock()
        if now - lastSwingEnd < ATTACK_COOLDOWN then return end

        isAttacking = true
        local zroot = getRootPart(z)
        if not zroot then isAttacking = false return end

        -- 1) Lock the mob: stop movement, lock orientation, disable knockback, freeze speed
        humanoid.WalkSpeed  = 0
        humanoid.AutoRotate = false
        humanoid:SetAttribute("knockbackImmune", true)

        -- Stop movement animations, play attack anim if available
        if activeTrack and activeTrack.IsPlaying then
            pcall(function() activeTrack:Stop(0.1) end)
        end
        if idleTrack and idleTrack.IsPlaying then
            pcall(function() idleTrack:Stop(0.1) end)
        end
        if attackTrack then
            pcall(function()
                attackTrack:AdjustSpeed(attackTrack.Length / ATTACK_WINDUP)
                attackTrack:Play(0.1)
            end)
        end

        -- 2) Wait for the wind-up duration
        task.wait(ATTACK_WINDUP)

        -- Mob may have died during wind-up
        if not z or not z.Parent or not humanoid or humanoid.Health <= 0 then
            isAttacking = false
            return
        end

        -- 3) Fire the hitbox: oriented box in front of the mob
        zroot = getRootPart(z) -- refresh reference
        if zroot then
            local boxCF = zroot.CFrame * CFrame.new(HITBOX_OFFSET)

            -- Debug: show hitbox part
            if SHOW_HITBOX then
                local dbg = Instance.new("Part")
                dbg.Name         = "_MobHitboxDebug"
                dbg.Anchored     = true
                dbg.CanCollide   = false
                dbg.CanTouch     = false
                dbg.CanQuery     = false
                dbg.Size         = HITBOX_SIZE
                dbg.CFrame       = boxCF
                dbg.Transparency = 0.5
                dbg.Color        = HITBOX_COLOR
                dbg.Material     = Enum.Material.Neon
                dbg.Parent       = Workspace
                -- Fade out and destroy after 0.5s
                local tween = TweenService:Create(dbg, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 })
                tween:Play()
                Debris:AddItem(dbg, 0.6)
            end

            local parts  = Workspace:GetPartBoundsInBox(boxCF, HITBOX_SIZE)
            local hitHumanoids = {}
            if parts then
                for _, part in ipairs(parts) do
                    if not part or not part:IsA("BasePart") then continue end
                    local model = part:FindFirstAncestorOfClass("Model")
                    if not model or model == z then continue end
                    local victimHum = model:FindFirstChildOfClass("Humanoid")
                    if not victimHum or victimHum.Health <= 0 then continue end
                    local ply = Players:GetPlayerFromCharacter(model)
                    if not ply then continue end  -- only damage players
                    if hitHumanoids[victimHum] then continue end
                    hitHumanoids[victimHum] = ply
                end
            end

            -- Apply damage & sound to each hit player
            for victimHum, ply in pairs(hitHumanoids) do
                victimHum:TakeDamage(ATTACK_DAMAGE)
                if victimHum.Health <= 0 then
                    pcall(function() zombieKillEvent:FireClient(ply) end)
                end
                -- play attack sound
                local victimChar = victimHum.Parent
                local parentForSound = (victimChar and (victimChar:FindFirstChild("HumanoidRootPart") or victimChar:FindFirstChildWhichIsA("BasePart"))) or z
                if attackSoundTemplate and attackSoundTemplate:IsA("Sound") then
                    local s = attackSoundTemplate:Clone()
                    s.Parent = parentForSound
                    s:Play()
                    Debris:AddItem(s, 4)
                end
            end
        end

        -- 4) Unlock the mob: restore speed, re-enable rotation & knockback
        lastSwingEnd = os.clock()
        humanoid:SetAttribute("knockbackImmune", false)
        humanoid.AutoRotate = true
        -- Restore speed based on current state
        if isEnraged then
            humanoid.WalkSpeed = MOB_ENRAGED_SPEED
        elseif chasing then
            humanoid.WalkSpeed = MOB_CHASE_SPEED
        else
            humanoid.WalkSpeed = MOB_WALK_SPEED
        end
        isAttacking = false
    end

    -------------------------------------------------------------------
    -- Movement helpers
    -------------------------------------------------------------------

    -- Switch to the correct animation track based on chasing state
    local function switchTrack(wantRun)
        local desired = wantRun and runTrack or walkTrack
        if not desired then return end
        -- always restart if track stopped unexpectedly
        if activeTrack == desired and desired.IsPlaying then return end
        -- stop previous track
        if activeTrack and activeTrack ~= desired and activeTrack.IsPlaying then
            pcall(function() activeTrack:Stop(0.15) end)
        end
        -- stop idle if playing
        if idleTrack and idleTrack.IsPlaying then
            pcall(function() idleTrack:Stop(0.15) end)
        end
        pcall(function() desired:Play(0.15) end)
        activeTrack = desired
    end

    local function startWalking(dest, useRun)
        humanoid:MoveTo(dest)
        switchTrack(useRun)
        moving = true
        stationaryTicks = 0
    end

    local function stopWalking()
        if activeTrack and activeTrack.IsPlaying then
            pcall(function() activeTrack:Stop() end)
        end
        activeTrack = nil
        moving = false
        stationaryTicks = 0
        -- play idle animation if available
        if idleTrack and not idleTrack.IsPlaying then
            pcall(function() idleTrack:Play(0.2) end)
        end
    end

    humanoid.MoveToFinished:Connect(function()
        -- don't stop walking while chasing; the AI loop will issue a new MoveTo
        if not chasing then
            stopWalking()
        end
    end)

    -------------------------------------------------------------------
    -- AI loop
    -------------------------------------------------------------------
    local lastWander    = 0
    local wanderCooldown = math.random(3, 7)
    local areaCenter = areaPart and areaPart:IsA("BasePart") and areaPart.Position or nil
    local areaSize   = areaPart and areaPart:IsA("BasePart") and areaPart.Size or nil

    -- lightweight AI loop (runs every 0.2s) to reduce server overhead
    local aiRunning = true
    task.spawn(function()
        while aiRunning and z and z.Parent and humanoid and humanoid.Health > 0 do
            local zroot = getRootPart(z)
            if not zroot then break end

            -- resolve aggro target: prioritise the player who shot us
            local targetRoot, dist
            if aggroPlayer and os.clock() < aggroExpiry then
                local ch = aggroPlayer.Character
                if ch then
                    local aHum = ch:FindFirstChildOfClass("Humanoid")
                    local aRoot = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
                    if aHum and aHum.Health > 0 and aRoot then
                        targetRoot = aRoot
                        dist = (aRoot.Position - zroot.Position).Magnitude
                    else
                        aggroPlayer = nil -- target dead / invalid
                    end
                else
                    aggroPlayer = nil
                end
            end
            -- fall back to nearest player within detection radius
            if not targetRoot then
                local _, nr, nd = nearestPlayer(zroot.Position, MOB_DETECTION_RADIUS)
                targetRoot = nr
                dist = nd
            end

            if targetRoot and dist then
                chasing = true

                -- If currently mid-attack, skip movement/attack logic this tick
                if isAttacking then
                    -- do nothing; performAttack coroutine handles unlock
                else
                    -- In range → begin attack (non-blocking: runs in its own coroutine)
                    if dist <= MOB_ATTACK_RANGE then
                        task.spawn(performAttack)
                    else
                        -- set appropriate speed: enraged > chase
                        if isEnraged then
                            humanoid.WalkSpeed = MOB_ENRAGED_SPEED
                        else
                            humanoid.WalkSpeed = MOB_CHASE_SPEED
                        end
                        -- overshoot: move to a point 10 studs PAST the player so the
                        -- humanoid never decelerates near them
                        local dir = (targetRoot.Position - zroot.Position).Unit
                        local overshoot = targetRoot.Position + dir * 10
                        startWalking(overshoot, true)  -- true = use run animation
                    end
                end
            else
                -- was chasing but lost target → immediately transition to wander
                if chasing then
                    chasing = false
                    -- force an immediate wander so there's no animation gap
                    local dest
                    if areaCenter and areaSize then
                        dest = randomPointInArea(areaPart)
                    else
                        local a = math.random() * math.pi * 2
                        local r = math.random(3, 12)
                        dest = spawnPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                    end
                    startWalking(dest, false)  -- walk animation kicks in immediately
                    lastWander = tick()
                    wanderCooldown = math.random(3, 7)
                end
                -- set idle/walk speed (unless enraged)
                if isEnraged then
                    humanoid.WalkSpeed = MOB_ENRAGED_SPEED
                else
                    humanoid.WalkSpeed = MOB_WALK_SPEED
                end
                -- wander occasionally; 30% chance to idle
                if tick() - lastWander >= wanderCooldown then
                    lastWander = tick()
                    wanderCooldown = math.random(3, 7)
                    if math.random() < 0.3 then
                        stopWalking() -- explicitly stop in case still animating
                    else
                        local dest
                        if areaCenter and areaSize then
                            dest = randomPointInArea(areaPart)
                        else
                            local a = math.random() * math.pi * 2
                            local r = math.random(3, 12)
                            dest = spawnPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                        end
                        startWalking(dest, false)  -- false = use walk animation
                    end
                else
                    -- safety: if stationary for several consecutive ticks, stop anim
                    if moving and zroot:IsA("BasePart") then
                        local vel = zroot.AssemblyLinearVelocity or zroot.Velocity
                        local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
                        if hSpeed < 0.3 then
                            stationaryTicks = stationaryTicks + 1
                            if stationaryTicks >= 5 then -- ~1s stationary before stopping
                                stopWalking()
                            end
                        else
                            stationaryTicks = 0
                            -- ensure animation is playing while actually moving
                            if activeTrack and not activeTrack.IsPlaying then
                                pcall(function() activeTrack:Play(0.1) end)
                            end
                        end
                    end
                end
            end

            task.wait(0.2)
        end
        aiRunning = false
    end)

    -- cleanup on death
    humanoid.Died:Connect(function()
        aiRunning = false
        stopWalking()
        pcall(function() CollectionService:RemoveTag(z, mobTag) end)
        task.delay(10, function() if z and z.Parent then z:Destroy() end end)
    end)

    return z
end

---------------------------------------------------------------------------
-- Main spawn loop
---------------------------------------------------------------------------
task.spawn(function()
    while true do
        local portals = findPortals()
        local alive   = #CollectionService:GetTagged(MOB_TAG)
        if templates and #templates > 0 and #portals > 0 then
            for i = 1, SPAWN_BATCH do
                if alive >= MAX_TOTAL then break end
                local entry = portals[math.random(1, #portals)]
                local chosen = pickWeightedTemplate()
                if not chosen then
                    warn("[MobSpawner] No enabled templates in weighted pool; skipping spawn")
                    continue
                end
                local z = spawnZombie(entry.portal, entry.area, chosen)
                if z then alive = alive + 1 end
            end
        end
        task.wait(SPAWN_INTERVAL)
    end
end)

print("[MobSpawner] started")
