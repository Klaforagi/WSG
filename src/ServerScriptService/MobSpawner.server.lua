local Workspace         = game:GetService("Workspace")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
-- list of template names (ServerStorage.Mobs or ServerStorage)
local TEMPLATE_NAMES     = { "Zombie", "Zack" }
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
    for _, tpl in ipairs(templates) do
        local cfg = (MobSettings and MobSettings.presets and MobSettings.presets[tpl.Name]) or {}
        local weight = math.max(1, math.floor(tonumber(cfg.spawn_chance) or 1))
        for _ = 1, weight do
            table.insert(weightedPool, tpl)
        end
    end
    print("[MobSpawner] Weighted pool size: " .. #weightedPool .. " entries across " .. #templates .. " template(s)")
end

rebuildWeightedPool()

local function pickWeightedTemplate()
    if #weightedPool == 0 then return templates[1] end
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

    -- unanchor so physics / humanoid work
    for _, d in ipairs(z:GetDescendants()) do
        if d:IsA("BasePart") then d.Anchored = false; d.CanCollide = true end
    end

    local humanoid = z:FindFirstChildOfClass("Humanoid")
    if not humanoid then warn("[MobSpawner] Template '" .. (tplToUse and tplToUse.Name or "Unknown") .. "' has no Humanoid!") return z end
    local MOB_WALK_SPEED = mobCfg.walk_speed or DEFAULT_WALK_SPEED
    local MOB_CHASE_SPEED = mobCfg.chase_speed or DEFAULT_CHASE_SPEED
    local MOB_ATTACK_RANGE = mobCfg.attack_range or DEFAULT_ATTACK_RANGE
    local MOB_DETECTION_RADIUS = mobCfg.detection_radius or DEFAULT_DETECTION_RADIUS
    local MOB_AGGRO_DURATION = mobCfg.aggro_duration or DEFAULT_AGGRO_DURATION
    humanoid.WalkSpeed  = MOB_WALK_SPEED
    humanoid.AutoRotate = true
    -- attack setup (resolve per-template values if provided)
    local ATTACK_DAMAGE = mobCfg.attack_damage or 60
    local ATTACK_COOLDOWN = mobCfg.attack_cooldown or 1 -- seconds per target
    local lastAttackTimes = {}
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local attackSoundTemplate
    if soundsFolder then
        local key = mobCfg.attack_sound or "ZombieAttack"
        attackSoundTemplate = soundsFolder:FindFirstChild(key) or soundsFolder:FindFirstChild("Zombie_Attack")
    end

    -------------------------------------------------------------------
    -- Animator + walk track
    -------------------------------------------------------------------
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- find a walk Animation in the template, or create fallback
    local walkAnimObj
    for _, a in ipairs(z:GetDescendants()) do
        if a:IsA("Animation") and a.Name:lower():find("walk") then walkAnimObj = a break end
    end
    if not walkAnimObj then
        local animId = (mobCfg.walk_anim_id and mobCfg.walk_anim_id ~= "") and mobCfg.walk_anim_id or DEFAULT_WALK_ANIM_ID
        walkAnimObj = Instance.new("Animation")
        walkAnimObj.Name        = "Walk_Fallback"
        walkAnimObj.AnimationId = animId
        walkAnimObj.Parent      = z
    end

    local walkTrack
    local ok, err = pcall(function()
        walkTrack        = animator:LoadAnimation(walkAnimObj)
        walkTrack.Priority = Enum.AnimationPriority.Movement
        walkTrack.Looped   = true
    end)
    if not ok then warn("[MobSpawner] Walk anim failed: " .. tostring(err)); walkTrack = nil end

    -- adjust speed based on health: if health less than max, use chase speed
    local function updateSpeedByHealth(h)
        local maxH = humanoid.MaxHealth or 100
        if h < maxH then
            humanoid.WalkSpeed = MOB_CHASE_SPEED
        else
            humanoid.WalkSpeed = MOB_WALK_SPEED
        end
    end

    -------------------------------------------------------------------
    -- Damage-based aggro: whoever shot us becomes the priority target
    -------------------------------------------------------------------
    local aggroPlayer = nil   -- Player who last damaged this mob
    local aggroExpiry = 0     -- os.clock() when aggro expires

    local prevHealth = humanoid.Health
    -- apply immediately in case template spawns damaged
    updateSpeedByHealth(humanoid.Health)
    humanoid.HealthChanged:Connect(function(newHealth)
        updateSpeedByHealth(newHealth)
        -- detect damage (health went down)
        if newHealth < prevHealth then
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
        prevHealth = newHealth
    end)

    -- damage on touch
    local function tryDamage(otherPart)
        if not otherPart or not otherPart.Parent then return end
        local victimHum = otherPart.Parent:FindFirstChildOfClass("Humanoid")
        if not victimHum or victimHum.Health <= 0 then return end
        local victimChar = victimHum.Parent
        local ply = Players:GetPlayerFromCharacter(victimChar)
        if not ply then return end -- only damage players
        local now = tick()
        local last = lastAttackTimes[victimHum] or 0
        if now - last < ATTACK_COOLDOWN then return end
        lastAttackTimes[victimHum] = now
        -- apply damage
        victimHum:TakeDamage(ATTACK_DAMAGE)
        -- if this killed the player, fire ZombieKill to the victim for DGH popup
        if victimHum.Health <= 0 then
            pcall(function() zombieKillEvent:FireClient(ply) end)
        end
        -- play attack sound at victim root or zombie
        local parentForSound = (victimChar:FindFirstChild("HumanoidRootPart") or victimChar:FindFirstChildWhichIsA("BasePart")) or z
        if attackSoundTemplate and attackSoundTemplate:IsA("Sound") then
            local s = attackSoundTemplate:Clone()
            s.Parent = parentForSound
            s:Play()
            Debris:AddItem(s, 4)
        end
    end
    -- (proximity-based attack is handled in the AI loop below — no Touched events needed)

    -------------------------------------------------------------------
    -- Movement helpers
    -------------------------------------------------------------------
    local moving = false
    local chasing = false  -- true while actively chasing a player

    local function startWalking(dest)
        humanoid:MoveTo(dest)
        if not moving and walkTrack then
            pcall(function() walkTrack:Play() end)
            moving = true
        end
    end

    local function stopWalking()
        if moving and walkTrack then
            pcall(function() walkTrack:Stop() end)
        end
        moving = false
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
                -- overshoot: move to a point 10 studs PAST the player so the
                -- humanoid never decelerates near them
                local dir = (targetRoot.Position - zroot.Position).Unit
                local overshoot = targetRoot.Position + dir * 10
                startWalking(overshoot)
                -- proximity attack
                if dist <= MOB_ATTACK_RANGE then
                    tryDamage(targetRoot)
                end
            else
                chasing = false
                -- wander occasionally; 30% chance to idle
                if tick() - lastWander >= wanderCooldown then
                    lastWander = tick()
                    wanderCooldown = math.random(3, 7)
                    if math.random() < 0.3 then
                        -- stay idle
                    else
                        local dest
                        if areaCenter and areaSize then
                            dest = randomPointInArea(areaPart)
                        else
                            local a = math.random() * math.pi * 2
                            local r = math.random(3, 12)
                            dest = spawnPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                        end
                        startWalking(dest)
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
                local z = spawnZombie(entry.portal, entry.area, chosen)
                if z then alive = alive + 1 end
            end
        end
        task.wait(SPAWN_INTERVAL)
    end
end)

print("[MobSpawner] started")
