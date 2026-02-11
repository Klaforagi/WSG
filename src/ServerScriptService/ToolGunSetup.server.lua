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

-- Create the tool template in StarterPack if missing
local TOOL_NAME = "ToolGun"
local existing = StarterPack:FindFirstChild(TOOL_NAME)
if not existing then
    local tool = Instance.new("Tool")
    tool.Name = TOOL_NAME
    tool.CanBeDropped = false

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1,1,2)
    handle.Material = Enum.Material.Metal
    handle.Color = Color3.fromRGB(50,50,60)
    handle.Parent = tool

    tool.Parent = StarterPack
end

-- Server-side handling + validation (projectile-based)
local lastFire = {}

local DAMAGE = TOOLCFG.damage or 25
local RANGE = TOOLCFG.range or 300
local COOLDOWN_SERVER = TOOLCFG.cd or 0.5

-- Projectile settings
local PROJECTILE_SPEED = TOOLCFG.bulletspeed or 100 -- studs per second
local PROJECTILE_LIFETIME = TOOLCFG.projectile_lifetime or 5 -- seconds
local psize = TOOLCFG.projectile_size or {0.2, 0.2, 0.2}
local PROJECTILE_SIZE = Vector3.new(psize[1], psize[2], psize[3])
local BULLET_DROP = TOOLCFG.bulletdrop or 9.8

local function spawnProjectile(player, origin, initialVelocity)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local visual = Instance.new("Part")
    visual.Name = "Bullet"
    visual.Size = PROJECTILE_SIZE
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
        velocity = velocity + Vector3.new(0, -BULLET_DROP * dt, 0)
        local nextPos = lastPos + velocity * dt
        local rayResult = Workspace:Raycast(lastPos, (nextPos - lastPos), params)
        if rayResult and rayResult.Instance then
            -- hit detected
            local inst = rayResult.Instance
            local parent = inst
            while parent and parent ~= Workspace do
                local humanoid = parent:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    -- tag humanoid with who last damaged it
                    pcall(function()
                        humanoid:SetAttribute("lastDamagerUserId", player and player.UserId or nil)
                        humanoid:SetAttribute("lastDamagerName", player and player.Name or nil)
                        humanoid:SetAttribute("lastDamageTime", tick())
                    end)
                    humanoid:TakeDamage(DAMAGE)
                    -- notify shooter client to play hitmarker
                    pcall(function()
                        if fireHit then
                            fireHit:FireClient(player)
                        end
                    end)
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

        if (lastPos - origin).Magnitude > RANGE or tick() - startTime > PROJECTILE_LIFETIME then
            visual:Destroy()
            conn:Disconnect()
            return
        end
    end)
end

fireEvent.OnServerEvent:Connect(function(player, camOrigin, camDirection, gunOrigin)
    print("[ToolGun.server] OnServerEvent from", player and player.Name)
    -- basic validation of types
    if typeof(camOrigin) ~= "Vector3" or typeof(camDirection) ~= "Vector3" or typeof(gunOrigin) ~= "Vector3" then return end
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- rate limit
    local now = tick()
    local last = lastFire[player]
    if last and now - last < COOLDOWN_SERVER then return end
    lastFire[player] = now

    -- basic proximity checks (allow some leeway for camera offsets)
    if (gunOrigin - hrp.Position).Magnitude > 60 then return end
    if (camOrigin - hrp.Position).Magnitude > 120 then return end

    -- perform a server-side hitscan from the camera ray first so shots go where the player's cursor is
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local rayDir = camDirection.Unit
    local rayResult = Workspace:Raycast(camOrigin, rayDir * RANGE, params)
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
                        pcall(function()
                            humanoid:SetAttribute("lastDamagerUserId", player and player.UserId or nil)
                            humanoid:SetAttribute("lastDamagerName", player and player.Name or nil)
                            humanoid:SetAttribute("lastDamageTime", tick())
                        end)
                        humanoid:TakeDamage(DAMAGE)
                        pcall(function()
                            if fireHit then
                                fireHit:FireClient(player)
                            end
                        end)
                        break
                    end
            parent = parent.Parent
        end

        coroutine.wrap(function()
            local hitPos = finalHit.Position
            local gunPos = gunOrigin or camOrigin
            local beam = Instance.new("Part")
            beam.Name = "ToolGunServerTracer"
            local dir = (hitPos - gunPos)
            local len = dir.Magnitude
            beam.Size = Vector3.new(0.08, 0.08, math.max(len, 0.1))
            beam.CFrame = CFrame.new(gunPos + dir/2, hitPos)
            beam.Anchored = true
            beam.CanCollide = false
            beam.Material = Enum.Material.Neon
            beam.Color = Color3.fromRGB(255, 120, 80)
            beam.Parent = Workspace
            game:GetService("Debris"):AddItem(beam, 0.12)
        end)()

        pcall(function()
            if fireAck then
                fireAck:FireClient(player, gunOrigin, finalHit.Position)
            end
        end)
        return
    end

    -- if the camera ray missed, check if there's an obstruction between the gun and the camera aim direction
    local aimPos = camOrigin + rayDir * RANGE
    local gunObstruction = Workspace:Raycast(gunOrigin, rayDir * RANGE, params)
    if gunObstruction and gunObstruction.Instance then
        -- gun is immediately obstructed; spawn server tracer to obstruction and notify client
        coroutine.wrap(function()
            local hitPos = gunObstruction.Position
            local beam = Instance.new("Part")
            beam.Name = "ToolGunServerTracer"
            local dir = (hitPos - gunOrigin)
            local len = dir.Magnitude
            beam.Size = Vector3.new(0.08, 0.08, math.max(len, 0.1))
            beam.CFrame = CFrame.new(gunOrigin + dir/2, hitPos)
            beam.Anchored = true
            beam.CanCollide = false
            beam.Material = Enum.Material.Neon
            beam.Color = Color3.fromRGB(255, 120, 80)
            beam.Parent = Workspace
            game:GetService("Debris"):AddItem(beam, 0.12)
        end)()
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
                pcall(function()
                    humanoid:SetAttribute("lastDamagerUserId", player and player.UserId or nil)
                    humanoid:SetAttribute("lastDamagerName", player and player.Name or nil)
                    humanoid:SetAttribute("lastDamageTime", tick())
                end)
                humanoid:TakeDamage(DAMAGE)
                pcall(function()
                    if fireHit then
                        fireHit:FireClient(player)
                    end
                end)
                break
            end
            parent = parent.Parent
        end
        return
    end
    local displacement = aimPos - gunOrigin
    local distance = displacement.Magnitude
    local initVel
    if distance <= 0.001 then
        initVel = hrp.CFrame.LookVector * PROJECTILE_SPEED
    else
        local t = distance / PROJECTILE_SPEED
        if t <= 0 then t = 0.01 end
        local g = Vector3.new(0, -BULLET_DROP, 0)
        initVel = (displacement / t) - (0.5 * g * t)
    end
    spawnProjectile(player, gunOrigin, initVel)
    -- notify client with the gun origin and aimed position so the client can spawn a local tracer
    pcall(function()
        if fireAck then
            local aimPos = aimPos or (camOrigin + rayDir * RANGE)
            fireAck:FireClient(player, gunOrigin, aimPos)
        end
    end)
end)
