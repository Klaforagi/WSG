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
local TOOLCFG = {}

-- Default: tracers are disabled unless a preset explicitly enables them
local SHOW_TRACER = false

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
local HeadshotEvent = ensureEvent("Headshot")
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

-- Base defaults when no preset supplies values
local DAMAGE = 25
local RANGE = 300
local COOLDOWN_SERVER = 0.5

-- Projectile settings defaults
local PROJECTILE_SPEED = 100 -- studs per second
local PROJECTILE_LIFETIME = 5 -- seconds
local PROJECTILE_SIZE = Vector3.new(0.2, 0.2, 0.2)
local BULLET_DROP = 9.8

-- Raycast helper that skips Accessory parts so bullets pass through hats/attachments.
local function raycastSkippingAccessories(origin, direction, rayParams)
    local maxIter = 10
    local start = origin
    local remaining = direction
    for i = 1, maxIter do
        if not remaining or remaining.Magnitude <= 0.001 then break end
        local result = Workspace:Raycast(start, remaining, rayParams)
        if not result or not result.Instance then
            return result
        end
        local inst = result.Instance
        local acc = nil
        if inst and inst.FindFirstAncestorWhichIsA then
            acc = inst:FindFirstAncestorWhichIsA("Accessory")
        end
        if acc then
            -- skip accessory: continue raycast just past the hit position
            local hitPos = result.Position
            local dirUnit = remaining.Unit
            local traveled = (hitPos - start).Magnitude
            local remainingLen = math.max(0, remaining.Magnitude - traveled)
            start = hitPos + dirUnit * 0.02
            remaining = dirUnit * remainingLen
            -- try again
        else
            return result
        end
    end
    return nil
end

-- Unified damage helper: tags humanoid, deals damage, fires hitmarker,
-- and fires kill credit immediately if the target dies.
local function applyDamage(player, humanoid, victimModel, damage, isHeadshot, hitPart, hitPos)
    -- prevent friendly fire: if the victim is a player on the same Team, skip damage
    local victimPlayer = nil
    if victimModel and Players then
        victimPlayer = Players:GetPlayerFromCharacter(victimModel)
    end
    if victimPlayer and player and player.Team and victimPlayer.Team and player.Team == victimPlayer.Team then
        return
    end
    pcall(function()
        humanoid:SetAttribute("lastDamagerUserId", player.UserId)
        humanoid:SetAttribute("lastDamagerName", player.Name)
        humanoid:SetAttribute("lastDamageTime", tick())
    end)
    -- apply damage (server may already have multiplied for headshots)
    humanoid:TakeDamage(damage)
    pcall(function()
        if fireHit then fireHit:FireClient(player, damage, isHeadshot == true, hitPart, hitPos) end
    end)
    -- if this was a headshot, increment a simple per-player headshot counter and notify the shooter
    if isHeadshot then
        pcall(function()
            if player and player.SetAttribute then
                local n = player:GetAttribute("headshotCount") or 0
                player:SetAttribute("headshotCount", n + 1)
            end
            if HeadshotEvent then
                HeadshotEvent:FireClient(player, victimModel and victimModel.Name or "Unknown")
            end
        end)
    end
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

local function spawnProjectile(player, origin, initialVelocity, projCfg, toolName)
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
    visual.Color = getTracerColor(player)
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
                    local isHeadshot = false
                    -- robust headshot detection that handles accessories (hats/hair):
                    local headPart = parent:FindFirstChild("Head")
                    if headPart then
                        -- 1) direct hit on the Head part
                        if inst == headPart then
                            isHeadshot = true
                        -- 2) hit part name contains 'head' (e.g. HeadMesh)
                        elseif inst.Name and tostring(inst.Name):lower():find("head") then
                            isHeadshot = true
                        -- 3) hit part is a descendant of Head (face decals etc.)
                        elseif inst:IsDescendantOf(headPart) then
                            isHeadshot = true
                        -- 4) hit part belongs to an Accessory attached near the Head
                        elseif inst:FindFirstAncestorWhichIsA("Accessory") then
                            local acc = inst:FindFirstAncestorWhichIsA("Accessory")
                            local handle = acc:FindFirstChild("Handle")
                            if handle and handle:IsA("BasePart") then
                                if (handle.Position - headPart.Position).Magnitude <= 3 then
                                    isHeadshot = true
                                end
                            end
                        end
                        -- 5) fallback: hit position within generous radius of Head center
                        if not isHeadshot then
                            local hitPos = rayResult.Position
                            if hitPos and headPart.Position then
                                if (hitPos - headPart.Position).Magnitude <= 2 then
                                    isHeadshot = true
                                end
                            end
                        end
                    end
                    local finalDamage = pDamage
                    if isHeadshot then
                        local mult = (projCfg and projCfg.headshot_multiplier) or 1
                        finalDamage = pDamage * mult
                    end
                    applyDamage(player, humanoid, parent, finalDamage, isHeadshot, inst, rayResult.Position)
                    -- play sniper headshot sound at victim head when appropriate
                    if isHeadshot then
                        local ok, _ = pcall(function()
                            -- determine if this was a sniper by toolName or preset key
                            local isSniper = false
                            if toolName and tostring(toolName):lower():find("sniper") then
                                isSniper = true
                            else
                                -- try to detect from projCfg name hints
                                if projCfg and projCfg.bulletspeed and projCfg.bulletspeed > 1500 then
                                    isSniper = true
                                end
                            end
                            if isSniper then
                                local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
                                if soundsFolder then
                                    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
                                    if toolgunFolder then
                                        local template = toolgunFolder:FindFirstChild("Sniper_headshot") or toolgunFolder:FindFirstChild("Sniper_Headshot")
                                        if template and template:IsA("Sound") then
                                            local s = template:Clone()
                                            -- parent to the hit part if possible so it originates from the head
                                            if inst and inst:IsA("BasePart") then
                                                s.Parent = inst
                                            else
                                                s.Parent = Workspace
                                            end
                                            s:Play()
                                            game:GetService("Debris"):AddItem(s, 4)
                                        end
                                    end
                                end
                            end
                        end)
                    end
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
    -- Uses 90% of cooldown as the check threshold so network jitter can't
    -- silently drop shots.  Stamps lastFire to the cadence beat (last + cd)
    -- rather than wall-clock receipt time, preventing cumulative drift that
    -- causes hiccup/burst patterns at any cooldown value.
    local now = tick()
    local toolKey = toolName or "_default"
    if not lastFire[player] then lastFire[player] = {} end
    local last = lastFire[player][toolKey]
    if last and now - last < tCOOLDOWN * 0.9 then return end
    -- snap to expected cadence beat; reset fresh if player hasn't fired recently
    if last and (now - last) < tCOOLDOWN * 1.5 then
        lastFire[player][toolKey] = last + tCOOLDOWN
    else
        lastFire[player][toolKey] = now
    end

    -- basic proximity checks (allow some leeway for camera offsets)
    if (gunOrigin - hrp.Position).Magnitude > 60 then return end
    if (camOrigin - hrp.Position).Magnitude > 120 then return end

    -- perform a server-side hitscan from the camera ray first so shots go where the player's cursor is
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local rayDir = camDirection.Unit
    local rayResult = raycastSkippingAccessories(camOrigin, rayDir * tRANGE, params)
    if rayResult and rayResult.Instance then
        -- camera ray hit something; ensure there's no obstruction between gun muzzle and that hit
        local camHitPos = rayResult.Position
        local toCamHit = camHitPos - gunOrigin
        local gunBlock = raycastSkippingAccessories(gunOrigin, toCamHit, params)
        local finalHit = rayResult
        if gunBlock and gunBlock.Instance then
            -- there is something between the gun and the camera hit; prefer the closer gun-side hit
            finalHit = gunBlock
        end
        -- instead of applying damage immediately, spawn a server projectile toward the final hit
        local hitPos = finalHit.Position
        local showTracerForTool = (tCfg and tCfg.showTracer ~= nil) and tCfg.showTracer or SHOW_TRACER
        if showTracerForTool then
            coroutine.wrap(function()
                local gunPos = gunOrigin or camOrigin
                local dir = (hitPos - gunPos)
                local len = dir.Magnitude
                local beam = Instance.new("Part")
                beam.Name = "ToolGunServerTracer"
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

        -- compute initial velocity toward the hit position using per-tool cfg
        local tBULLETSPEED = tCfg.bulletspeed or PROJECTILE_SPEED
        local tBULLETDROP = tCfg.bulletdrop or BULLET_DROP
        local displacement = hitPos - gunOrigin
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

        spawnProjectile(player, gunOrigin, initVel, tCfg, toolName)

        pcall(function()
            if fireAck then
                fireAck:FireClient(player, gunOrigin, hitPos, toolName)
            end
        end)
        return
    end

    -- if the camera ray missed, check if there's an obstruction between the gun and the camera aim direction
    local aimPos = camOrigin + rayDir * tRANGE
    local gunObstruction = raycastSkippingAccessories(gunOrigin, rayDir * tRANGE, params)
    if gunObstruction and gunObstruction.Instance then
        -- gun is immediately obstructed; spawn server tracer to obstruction and notify client
        local showTracerForTool = (tCfg and tCfg.showTracer ~= nil) and tCfg.showTracer or SHOW_TRACER
        if showTracerForTool then
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
                fireAck:FireClient(player, gunOrigin, gunObstruction.Position, toolName)
            end
        end)
        -- instead of applying damage immediately, spawn projectile toward the obstruction
        local hitPos = gunObstruction.Position
        local tBULLETSPEED = tCfg.bulletspeed or PROJECTILE_SPEED
        local tBULLETDROP = tCfg.bulletdrop or BULLET_DROP
        local displacement = hitPos - gunOrigin
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
        spawnProjectile(player, gunOrigin, initVel, tCfg, toolName)
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
    spawnProjectile(player, gunOrigin, initVel, tCfg, toolName)
    -- notify client with the gun origin and aimed position so the client can spawn a local tracer
    pcall(function()
        if fireAck then
            local aimPos = aimPos or (camOrigin + rayDir * tRANGE)
            fireAck:FireClient(player, gunOrigin, aimPos, toolName)
        end
    end)
end)

-- clean up rate-limit table when players leave
Players.PlayerRemoving:Connect(function(player)
    lastFire[player] = nil
end)
