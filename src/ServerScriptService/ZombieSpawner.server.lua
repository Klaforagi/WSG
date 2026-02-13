local Workspace         = game:GetService("Workspace")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
local TEMPLATE_NAME      = "Zombie_R6"
local PORTAL_GROUP_NAMES = { "DarkPortal1", "DarkPortal2" }
local PORTAL_PART_NAME   = "PortalPlane"
local MOB_AREA_PREFIX    = "MobArea"

local SPAWN_INTERVAL     = 30
local SPAWN_BATCH        = 4
local MAX_PER_PORTAL     = 8
local MAX_TOTAL          = 8

local DETECTION_RADIUS   = 60 -- increased aggro range (double)
local ZOMBIE_WALK_SPEED  = 16
local ZOMBIE_TAG         = "ZombieNPC"
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local function findTemplate()
    local mobs = ServerStorage:FindFirstChild("Mobs")
    if mobs then
        local t = mobs:FindFirstChild(TEMPLATE_NAME)
        if t then print("[ZombieSpawner] Template found in ServerStorage.Mobs") return t end
    end
    local t = ServerStorage:FindFirstChild(TEMPLATE_NAME)
    if t then print("[ZombieSpawner] Template found in ServerStorage") return t end
    warn("[ZombieSpawner] No template '" .. TEMPLATE_NAME .. "' found!")
    return nil
end

local template = findTemplate()

---------------------------------------------------------------------------
-- Portal discovery → { {portal, area, groupName}, … }
---------------------------------------------------------------------------
local function findPortals()
    local out = {}
    for idx, groupName in ipairs(PORTAL_GROUP_NAMES) do
        local group = Workspace:FindFirstChild(groupName)
        if not group then warn("[ZombieSpawner] Missing group: " .. groupName) continue end
        local areaName = MOB_AREA_PREFIX .. tostring(idx)
        local areaPart = Workspace:FindFirstChild(areaName)
        if not areaPart then warn("[ZombieSpawner] Missing area: " .. areaName) end
        for _, v in ipairs(group:GetDescendants()) do
            if v:IsA("BasePart") and v.Name == PORTAL_PART_NAME then
                table.insert(out, { portal = v, area = areaPart, groupName = groupName })
            end
        end
    end
    print("[ZombieSpawner] Discovered " .. #out .. " portal(s)")
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

local function nearestPlayer(pos)
    local best, bestDist, bestRoot
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        if not ch then continue end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local root = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
        if not root then continue end
        local d = (root.Position - pos).Magnitude
        if d <= DETECTION_RADIUS and (not bestDist or d < bestDist) then
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
-- Spawn one zombie
---------------------------------------------------------------------------
local function spawnZombie(portalPart, areaPart)
    if not template then return nil end

    local z = template:Clone()
    z.Name = "Zombie"
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

    CollectionService:AddTag(z, ZOMBIE_TAG)

    -- unanchor so physics / humanoid work
    for _, d in ipairs(z:GetDescendants()) do
        if d:IsA("BasePart") then d.Anchored = false; d.CanCollide = true end
    end

    local humanoid = z:FindFirstChildOfClass("Humanoid")
    if not humanoid then warn("[ZombieSpawner] Zombie has no Humanoid!") return z end
    humanoid.WalkSpeed  = ZOMBIE_WALK_SPEED
    humanoid.AutoRotate = true

    -- attack setup
    local ATTACK_DAMAGE = 60
    local ATTACK_COOLDOWN = 1 -- seconds per target
    local lastAttackTimes = {}
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local attackSoundTemplate
    if soundsFolder then
        attackSoundTemplate = soundsFolder:FindFirstChild("ZombieAttack") or soundsFolder:FindFirstChild("Zombie_Attack")
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
        walkAnimObj = Instance.new("Animation")
        walkAnimObj.Name        = "Walk_Fallback"
        walkAnimObj.AnimationId = DEFAULT_WALK_ANIM_ID
        walkAnimObj.Parent      = z
    end

    local walkTrack
    local ok, err = pcall(function()
        walkTrack        = animator:LoadAnimation(walkAnimObj)
        walkTrack.Priority = Enum.AnimationPriority.Movement
        walkTrack.Looped   = true
    end)
    if not ok then warn("[ZombieSpawner] Walk anim failed: " .. tostring(err)); walkTrack = nil end

    -- adjust speed based on health: if health less than max, set to 25, otherwise default
    local function updateSpeedByHealth(h)
        local maxH = humanoid.MaxHealth or 100
        if h < maxH then
            humanoid.WalkSpeed = 25
        else
            humanoid.WalkSpeed = ZOMBIE_WALK_SPEED
        end
    end

    -------------------------------------------------------------------
    -- Damage-based aggro: whoever shot us becomes the priority target
    -------------------------------------------------------------------
    local aggroPlayer = nil   -- Player who last damaged this zombie
    local aggroExpiry = 0     -- os.clock() when aggro expires
    local AGGRO_DURATION = 12 -- seconds to chase attacker

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
                        aggroExpiry = os.clock() + AGGRO_DURATION
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
                local _, nr, nd = nearestPlayer(zroot.Position)
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
                -- proximity attack (6 studs so it lands even while both are moving)
                if dist <= 6 then
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
        pcall(function() CollectionService:RemoveTag(z, ZOMBIE_TAG) end)
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
        local alive   = #CollectionService:GetTagged(ZOMBIE_TAG)
        if template and #portals > 0 then
            for i = 1, SPAWN_BATCH do
                if alive >= MAX_TOTAL then break end
                local entry = portals[math.random(1, #portals)]
                local z = spawnZombie(entry.portal, entry.area)
                if z then alive = alive + 1 end
            end
        end
        task.wait(SPAWN_INTERVAL)
    end
end)

print("[ZombieSpawner] started")
