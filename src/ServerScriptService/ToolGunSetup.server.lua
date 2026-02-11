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

local function spawnProjectile(player, origin, direction)
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
    local velocity = direction * PROJECTILE_SPEED
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
                    humanoid:TakeDamage(DAMAGE)
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

fireEvent.OnServerEvent:Connect(function(player, origin, direction)
    print("[ToolGun.server] OnServerEvent from", player and player.Name)
    -- basic validation
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- rate limit
    local now = tick()
    local last = lastFire[player]
    if last and now - last < COOLDOWN_SERVER then return end
    lastFire[player] = now

    -- validate origin near player's camera/character (prevent spoof)
    if (origin - hrp.Position).Magnitude > 20 then return end

    -- spawn a server-authoritative projectile that moves over time and raycasts each frame
    spawnProjectile(player, origin, direction)
    -- notify client to play fire sound/feedback
    pcall(function()
        fireAck:FireClient(player)
    end)
end)
