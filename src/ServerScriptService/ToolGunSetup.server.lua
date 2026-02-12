local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Toolgun settings module (defaults + optional Studio overrides)
local ToolgunModule
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    ToolgunModule = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
end
local TOOLCFG = ToolgunModule and ToolgunModule.get() or {}

local SHOW_TRACER = true
if type(TOOLCFG.showTracer) == "boolean" then SHOW_TRACER = TOOLCFG.showTracer end

local TEAM_TRACER_COLORS = {
    Blue = Color3.fromRGB(65, 105, 225), -- royal blue
    Red  = Color3.fromRGB(255, 75, 75),
}
local DEFAULT_TRACER_COLOR = Color3.fromRGB(255, 200, 100)
local function getTracerColor(player)
    if player and player.Team then
        return TEAM_TRACER_COLORS[player.Team.Name] or DEFAULT_TRACER_COLOR
    end
    return DEFAULT_TRACER_COLOR
end

-- RemoteEvent for firing
local FIRE_EVENT_NAME = "ToolGunFire"
local fireEvent = ReplicatedStorage:FindFirstChild(FIRE_EVENT_NAME)
if not fireEvent then
    fireEvent = Instance.new("RemoteEvent")
    fireEvent.Name = FIRE_EVENT_NAME
    fireEvent.Parent = ReplicatedStorage
end

local FIRE_ACK_NAME = "ToolGunFireAck"
local fireAck = ReplicatedStorage:FindFirstChild(FIRE_ACK_NAME)
if not fireAck then
    fireAck = Instance.new("RemoteEvent")
    fireAck.Name = FIRE_ACK_NAME
    fireAck.Parent = ReplicatedStorage
end

local HIT_EVENT_NAME = "ToolGunHit"
local fireHit = ReplicatedStorage:FindFirstChild(HIT_EVENT_NAME)
if not fireHit then
    fireHit = Instance.new("RemoteEvent")
    fireHit.Name = HIT_EVENT_NAME
    fireHit.Parent = ReplicatedStorage
end

-- Kill credit events (fire kill feed + score directly from damage code)
local function ensureEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end
local KillFeedEvent = ensureEvent("KillFeed")
local KILL_POINTS = 10

-- BindableEvent for score awards (listened to by GameManager)
local ServerScriptService = game:GetService("ServerScriptService")
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

-- Tools (ToolPistol, ToolSniper, etc.) are placed manually in StarterPack via Studio.
-- No auto-creation here.

-- Resolve per-tool config from presets
local function getServerToolCfg(toolName)
    local cfg = {}
    for k, v in pairs(TOOLCFG) do cfg[k] = v end
    if ToolgunModule and ToolgunModule.presets then
        local suffix = toolName and tostring(toolName):match("^Tool(.+)")
        local presetKey = suffix and suffix:lower()
        if presetKey and ToolgunModule.presets[presetKey] then
            for k, v in pairs(ToolgunModule.presets[presetKey]) do cfg[k] = v end
        end
    end
    return cfg
end

-- Server-side handling + validation (projectile-based)
local lastFire = {} -- [player] = { [toolName] = tick() }

local DAMAGE = TOOLCFG.damage or 25
local RANGE = TOOLCFG.range or 300
local COOLDOWN_SERVER = TOOLCFG.cd or 0.5

-- Projectile settings
local PROJECTILE_SPEED = TOOLCFG.bulletspeed or 100 -- studs per second
local PROJECTILE_LIFETIME = TOOLCFG.projectile_lifetime or 5 -- seconds
local psize = TOOLCFG.projectile_size or {0.2, 0.2, 0.2}
local PROJECTILE_SIZE = Vector3.new(psize[1], psize[2], psize[3])
local BULLET_DROP = TOOLCFG.bulletdrop or 9.8

-- Unified damage helper: tags humanoid, deals damage, fires hitmarker,
-- and fires kill credit immediately if the target dies.
local function applyDamage(player, humanoid, victimModel, damage)
    pcall(function()
        humanoid:SetAttribute("lastDamagerUserId", player.UserId)
        humanoid:SetAttribute("lastDamagerName", player.Name)
        humanoid:SetAttribute("lastDamageTime", tick())
    end)
    humanoid:TakeDamage(damage)
    pcall(function()
        if fireHit then fireHit:FireClient(player) end
    end)
    if humanoid.Health <= 0 then
        humanoid:SetAttribute("_killCredited", true)
        -- immediate kill credit
        local victimName = (victimModel and victimModel.Name) or "Unknown"
        local vp = Players:GetPlayerFromCharacter(victimModel)
        if vp then victimName = vp.Name end
        if player.Name ~= victimName then
            pcall(function() KillFeedEvent:FireAllClients(player.Name, victimName) end)
            if player.Team then
                pcall(function() AddScore:Fire(player.Team.Name, KILL_POINTS) end)
            end
        end
        -- if this was a dummy model, perform ragdoll/cleanup immediately so it visibly falls
        if victimModel and victimModel:IsA("Model") and victimModel.Name == "Dummy" then
            -- mark so DummyDeath doesn't duplicate work
            pcall(function() humanoid:SetAttribute("_dummyRagdolled", true) end)
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Dead)
            end)
            for _, desc in ipairs(victimModel:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.Anchored = false
                    desc.CanCollide = true
                end
            end
            task.wait(0.05)
            pcall(function() victimModel:BreakJoints() end)
            task.delay(5, function()
                if victimModel and victimModel.Parent then
                    pcall(function() victimModel:Destroy() end)
                end
            end)
        end
    end
end

local function spawnProjectile(player, origin, initialVelocity, projCfg)
    -- projCfg contains per-tool overrides: damage, range, bulletdrop, projectile_size, projectile_lifetime
    local pDamage = (projCfg and projCfg.damage) or DAMAGE
    local pRange = (projCfg and projCfg.range) or RANGE
    local pDrop = (projCfg and projCfg.bulletdrop) or BULLET_DROP
    local pLifetime = (projCfg and projCfg.projectile_lifetime) or PROJECTILE_LIFETIME
    local pSize = PROJECTILE_SIZE
    if projCfg and projCfg.projectile_size then
        local ps = projCfg.projectile_size
        if typeof(ps) == "Vector3" then
            pSize = ps
        elseif type(ps) == "table" then
            pSize = Vector3.new(ps[1] or 0.2, ps[2] or 0.2, ps[3] or 0.2)
        end
    end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local visual = Instance.new("Part")
    visual.Name = "Bullet"
    visual.Size = pSize
    visual.CFrame = CFrame.new(origin)
    visual.CanCollide = false
    visual.Anchored = true
    visual.Material = Enum.Material.Neon
    visual.Color = Color3.fromRGB(255, 220, 100)
    visual.Parent = Workspace

    local lastPos = origin
    local velocity = initialVelocity
    local startTime = tick()
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not visual.Parent then
            conn:Disconnect()
            return
        end
        -- apply gravity/bullet drop to vertical component of velocity
        velocity = velocity + Vector3.new(0, -pDrop * dt, 0)
        local nextPos = lastPos + velocity * dt
        local rayResult = Workspace:Raycast(lastPos, (nextPos - lastPos), params)
        if rayResult and rayResult.Instance then
            -- hit detected
            local inst = rayResult.Instance
            local parent = inst
            while parent and parent ~= Workspace do
                local humanoid = parent:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    applyDamage(player, humanoid, parent, pDamage)
                    break
                end
                parent = parent.Parent
            end
            visual:Destroy()
            conn:Disconnect()
            return
        end

        visual.CFrame = CFrame.new(nextPos, nextPos + velocity.Unit)
        lastPos = nextPos

        if (lastPos - origin).Magnitude > pRange or tick() - startTime > pLifetime then
            visual:Destroy()
            conn:Disconnect()
            return
        end
    end)
end

fireEvent.OnServerEvent:Connect(function(player, camOrigin, camDirection, gunOrigin, toolName)
    print("[ToolGun.server] OnServerEvent from", player and player.Name, "tool:", toolName)
    -- basic validation of types
    if typeof(camOrigin) ~= "Vector3" or typeof(camDirection) ~= "Vector3" or typeof(gunOrigin) ~= "Vector3" then return end
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- resolve per-tool config
    local tCfg = getServerToolCfg(toolName)
    local tDAMAGE = tCfg.damage or DAMAGE
    local tRANGE = tCfg.range or RANGE
    local tCOOLDOWN = tCfg.cd or COOLDOWN_SERVER

    -- rate limit (per-tool so switching weapons doesn't block shots)
    local now = tick()
    local toolKey = toolName or "_default"
    if not lastFire[player] then lastFire[player] = {} end
    local last = lastFire[player][toolKey]
    if last and now - last < tCOOLDOWN then return end
    lastFire[player][toolKey] = now

    -- basic proximity checks (allow some leeway for camera offsets)
    if (gunOrigin - hrp.Position).Magnitude > 60 then return end
    if (camOrigin - hrp.Position).Magnitude > 120 then return end

    -- perform a server-side hitscan from the camera ray first so shots go where the player's cursor is
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local rayDir = camDirection.Unit
    local rayResult = Workspace:Raycast(camOrigin, rayDir * tRANGE, params)
    if rayResult and rayResult.Instance then
        -- camera ray hit something; ensure there's no obstruction between gun muzzle and that hit
        local camHitPos = rayResult.Position
        local toCamHit = camHitPos - gunOrigin
        local gunBlock = Workspace:Raycast(gunOrigin, toCamHit, params)
        local finalHit = rayResult
        if gunBlock and gunBlock.Instance then
            -- there is something between the gun and the camera hit; prefer the closer gun-side hit
            finalHit = gunBlock
        end

        -- process finalHit (could be the original camera hit or a closer gun-side obstruction)
                local inst = finalHit.Instance
        local parent = inst
        while parent and parent ~= Workspace do
                    local humanoid = parent:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        applyDamage(player, humanoid, parent, tDAMAGE)
                        break
                    end
            parent = parent.Parent
        end

        if SHOW_TRACER then
            coroutine.wrap(function()
                local hitPos = finalHit.Position
                local gunPos = gunOrigin or camOrigin
                local beam = Instance.new("Part")
                beam.Name = "ToolGunServerTracer"
                local dir = (hitPos - gunPos)
                local len = dir.Magnitude
                beam.Size = Vector3.new(0.15, 0.15, math.max(len, 0.1))
                beam.CFrame = CFrame.new(gunPos + dir/2, hitPos)
                beam.Anchored = true
                beam.CanCollide = false
                beam.Material = Enum.Material.Neon
                beam.Color = getTracerColor(player)
                beam.Parent = Workspace
                game:GetService("Debris"):AddItem(beam, 0.22)
            end)()
        end

        pcall(function()
            if fireAck then
                fireAck:FireClient(player, gunOrigin, finalHit.Position)
            end
        end)
        return
    end

    -- if the camera ray missed, check if there's an obstruction between the gun and the camera aim direction
    local aimPos = camOrigin + rayDir * tRANGE
    local gunObstruction = Workspace:Raycast(gunOrigin, rayDir * tRANGE, params)
    if gunObstruction and gunObstruction.Instance then
        -- gun is immediately obstructed; spawn server tracer to obstruction and notify client
        if SHOW_TRACER then
            coroutine.wrap(function()
                local hitPos = gunObstruction.Position
                local beam = Instance.new("Part")
                beam.Name = "ToolGunServerTracer"
                local dir = (hitPos - gunOrigin)
                local len = dir.Magnitude
                beam.Size = Vector3.new(0.15, 0.15, math.max(len, 0.1))
                beam.CFrame = CFrame.new(gunOrigin + dir/2, hitPos)
                beam.Anchored = true
                beam.CanCollide = false
                beam.Material = Enum.Material.Neon
                beam.Color = getTracerColor(player)
                beam.Parent = Workspace
                game:GetService("Debris"):AddItem(beam, 0.22)
            end)()
        end
        -- notify client of obstruction
        pcall(function()
            if fireAck then
                fireAck:FireClient(player, gunOrigin, gunObstruction.Position)
            end
        end)
        -- attempt to apply damage if it's a humanoid
        local parent = gunObstruction.Instance
        while parent and parent ~= Workspace do
            local humanoid = parent:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                applyDamage(player, humanoid, parent, tDAMAGE)
                break
            end
            parent = parent.Parent
        end
        return
    end
    local tBULLETSPEED = tCfg.bulletspeed or PROJECTILE_SPEED
    local tBULLETDROP = tCfg.bulletdrop or BULLET_DROP
    local displacement = aimPos - gunOrigin
    local distance = displacement.Magnitude
    local initVel
    if distance <= 0.001 then
        initVel = hrp.CFrame.LookVector * tBULLETSPEED
    else
        local t = distance / tBULLETSPEED
        if t <= 0 then t = 0.01 end
        local g = Vector3.new(0, -tBULLETDROP, 0)
        initVel = (displacement / t) - (0.5 * g * t)
    end
    spawnProjectile(player, gunOrigin, initVel, tCfg)
    -- notify client with the gun origin and aimed position so the client can spawn a local tracer
    pcall(function()
        if fireAck then
            local aimPos = aimPos or (camOrigin + rayDir * tRANGE)
            fireAck:FireClient(player, gunOrigin, aimPos)
        end
    end)
end)

-- clean up rate-limit table when players leave
Players.PlayerRemoving:Connect(function(player)
    lastFire[player] = nil
end)
