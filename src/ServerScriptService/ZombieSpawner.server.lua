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

local DETECTION_RADIUS   = 30
local ZOMBIE_WALK_SPEED  = 10
local ZOMBIE_TAG         = "ZombieNPC"

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

    -------------------------------------------------------------------
    -- Movement helpers
    -------------------------------------------------------------------
    local moving = false

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
        stopWalking()
    end)

    -------------------------------------------------------------------
    -- AI loop
    -------------------------------------------------------------------
    local lastWander    = 0
    local wanderCooldown = math.random(3, 7)
    local areaCenter = areaPart and areaPart:IsA("BasePart") and areaPart.Position or nil
    local areaSize   = areaPart and areaPart:IsA("BasePart") and areaPart.Size or nil

    local aiConn
    aiConn = RunService.Heartbeat:Connect(function()
        if not z or not z.Parent or not humanoid or humanoid.Health <= 0 then
            if aiConn then aiConn:Disconnect() end
            stopWalking()
            return
        end
        local zroot = getRootPart(z)
        if not zroot then return end

        -- chase nearby player
        local _, targetRoot, dist = nearestPlayer(zroot.Position)
        if targetRoot and dist and dist > 2 then
            startWalking(targetRoot.Position)
            return
        end

        -- wander occasionally; 30 % chance to just idle in place
        if tick() - lastWander >= wanderCooldown then
            lastWander    = tick()
            wanderCooldown = math.random(3, 7)
            if math.random() < 0.3 then return end

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
    end)

    -- cleanup on death
    humanoid.Died:Connect(function()
        if aiConn then aiConn:Disconnect() end
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
