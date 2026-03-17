--------------------------------------------------------------------------------
-- DevRocketService.lua  –  Server-authoritative rocket launcher logic
-- ModuleScript in ServerScriptService.
--
-- Handles: tool template creation, projectile spawning, explosion VFX,
-- AoE damage, kill attribution, and cooldown enforcement.
-- Integrates with the existing StatService / KillTracker pipeline.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local Debris              = game:GetService("Debris")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local DevWeaponConfig = require(ReplicatedStorage:WaitForChild("DevWeaponConfig"))

-- Lazy-load integrations (same pattern as ToolGunSetup)
local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

local CurrencyService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

-- BindableEvent for score awards (listened to by GameManager)
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

-- Kill feed remote
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

local DevRocketService = {}

--------------------------------------------------------------------------------
-- COOLDOWN STATE
--------------------------------------------------------------------------------
local lastFireTime = {} -- [Player] = tick()

function DevRocketService.IsOnCooldown(player)
    local last = lastFireTime[player]
    if not last then return false end
    return (tick() - last) < DevWeaponConfig.ROCKET_COOLDOWN
end

function DevRocketService.MarkFired(player)
    lastFireTime[player] = tick()
end

function DevRocketService.ClearPlayer(player)
    lastFireTime[player] = nil
end

--------------------------------------------------------------------------------
-- TOOL TEMPLATE BUILDER
-- Creates a Tool instance programmatically (no .rbxl dependency).
--------------------------------------------------------------------------------
function DevRocketService.CreateToolTemplate()
    local tool = Instance.new("Tool")
    tool.Name = DevWeaponConfig.TOOL_NAME
    tool.CanBeDropped = false
    tool.RequiresHandle = true

    -- Handle: the physical part the player holds
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1, 1, 3.5)
    handle.Color = Color3.fromRGB(60, 60, 60)
    handle.Material = Enum.Material.Metal
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool

    -- Barrel tip (visual muzzle reference)
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(0.6, 0.6, 1.2)
    barrel.Color = Color3.fromRGB(90, 20, 20)
    barrel.Material = Enum.Material.Metal
    barrel.CanCollide = false
    barrel.Massless = true
    barrel.Parent = tool

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle
    weld.Part1 = barrel
    weld.Parent = barrel

    -- Offset barrel to the front of the handle
    barrel.CFrame = handle.CFrame * CFrame.new(0, 0, -2.3)

    -- Muzzle attachment (used as spawn point for rockets)
    local muzzle = Instance.new("Attachment")
    muzzle.Name = "MuzzlePoint"
    muzzle.Position = Vector3.new(0, 0, -0.6)
    muzzle.Parent = barrel

    -- Grip offset so it looks reasonable when held
    tool.GripPos = Vector3.new(0, -0.3, -0.5)
    tool.GripForward = Vector3.new(0, 0, -1)
    tool.GripRight = Vector3.new(1, 0, 0)
    tool.GripUp = Vector3.new(0, 1, 0)

    -- Tag it so other systems can identify it
    tool:SetAttribute("IsDevWeapon", true)
    tool:SetAttribute("HotbarCategory", "DevWeapon")

    return tool
end

--------------------------------------------------------------------------------
-- FIRE VALIDATION
-- Returns (ok: bool, reason: string)
--------------------------------------------------------------------------------
function DevRocketService.ValidateFireRequest(player)
    if not DevWeaponConfig.IsAuthorizedDevPlayer(player) then
        return false, "Not authorized"
    end

    local allowed, reason = DevWeaponConfig.IsDevRocketAllowedInThisServer()
    if not allowed then
        return false, reason
    end

    if DevRocketService.IsOnCooldown(player) then
        return false, "Cooldown active"
    end

    local char = player.Character
    if not char then return false, "No character" end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false, "Dead or no humanoid"
    end

    -- Verify the tool is actually equipped (in character)
    local tool = char:FindFirstChild(DevWeaponConfig.TOOL_NAME)
    if not tool or not tool:IsA("Tool") then
        return false, "Launcher not equipped"
    end

    return true, "OK"
end

--------------------------------------------------------------------------------
-- PROJECTILE
--------------------------------------------------------------------------------
local function createRocketVisual(origin, direction)
    local rocket = Instance.new("Part")
    rocket.Name = "DevRocket"
    rocket.Size = Vector3.new(0.5, 0.5, 1.8)
    rocket.Color = Color3.fromRGB(200, 50, 30)
    rocket.Material = Enum.Material.Neon
    rocket.CanCollide = false
    rocket.Anchored = true
    rocket.CFrame = CFrame.lookAt(origin, origin + direction)
    rocket.Parent = Workspace

    -- Trail
    local att0 = Instance.new("Attachment")
    att0.Name = "TrailAtt0"
    att0.Position = Vector3.new(0, 0, 0.9)
    att0.Parent = rocket

    local att1 = Instance.new("Attachment")
    att1.Name = "TrailAtt1"
    att1.Position = Vector3.new(0, 0, -0.9)
    att1.Parent = rocket

    local trail = Instance.new("Trail")
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Lifetime = 0.4
    trail.MinLength = 0
    trail.FaceCamera = true
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 50)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 20)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0.2),
    })
    trail.LightEmission = 0.8
    trail.Parent = rocket

    -- Point light for glow
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 120, 30)
    light.Brightness = 2
    light.Range = 8
    light.Parent = rocket

    return rocket
end

local function createExplosionVFX(position)
    -- Visual-only explosion (non-destructive)
    local explosion = Instance.new("Explosion")
    explosion.Position = position
    explosion.BlastRadius = 0         -- no physics force
    explosion.BlastPressure = 0       -- no physics force
    explosion.DestroyJointRadiusPercent = 0 -- non-destructive
    explosion.Parent = Workspace

    -- Extra: bright flash sphere
    local flash = Instance.new("Part")
    flash.Name = "RocketFlash"
    flash.Shape = Enum.PartType.Ball
    flash.Size = Vector3.new(4, 4, 4)
    flash.Color = Color3.fromRGB(255, 180, 50)
    flash.Material = Enum.Material.Neon
    flash.Transparency = 0.3
    flash.Anchored = true
    flash.CanCollide = false
    flash.Position = position
    flash.Parent = Workspace
    Debris:AddItem(flash, 0.5)

    -- Animate flash expansion
    task.spawn(function()
        local steps = 8
        for i = 1, steps do
            local t = i / steps
            pcall(function()
                flash.Size = Vector3.new(4 + 10 * t, 4 + 10 * t, 4 + 10 * t)
                flash.Transparency = 0.3 + 0.7 * t
            end)
            task.wait(0.5 / steps)
        end
    end)

    -- Point light for the flash
    local expLight = Instance.new("PointLight")
    expLight.Color = Color3.fromRGB(255, 160, 40)
    expLight.Brightness = 4
    expLight.Range = 25
    expLight.Parent = flash
end

--------------------------------------------------------------------------------
-- AoE DAMAGE  (server-authoritative)
--------------------------------------------------------------------------------
local function applyAoEDamage(shooter, hitPosition)
    local blastRadius = DevWeaponConfig.ROCKET_BLAST_RADIUS
    local damage = DevWeaponConfig.ROCKET_DAMAGE

    -- Find all humanoids within blast radius
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if not otherPlayer.Character then continue end
        local hum = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        local hrp = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local dist = (hrp.Position - hitPosition).Magnitude
        if dist > blastRadius then continue end

        -- Self-damage check
        if otherPlayer == shooter and not DevWeaponConfig.SELF_DAMAGE then
            continue
        end

        -- Friendly fire check
        if not DevWeaponConfig.FRIENDLY_FIRE then
            if shooter.Team and otherPlayer.Team and shooter.Team == otherPlayer.Team and otherPlayer ~= shooter then
                continue
            end
        end

        -- Tag for kill attribution (same pattern as ToolGunSetup)
        pcall(function()
            hum:SetAttribute("lastDamagerUserId", shooter.UserId)
            hum:SetAttribute("lastDamagerName", shooter.Name)
            hum:SetAttribute("lastDamageTime", tick())
        end)

        -- Apply damage
        hum:TakeDamage(damage)

        -- Immediate kill credit if dead (same pattern as ToolGunSetup)
        if hum.Health <= 0 then
            pcall(function() hum:SetAttribute("_killCredited", true) end)

            local victimName = otherPlayer.Name

            -- Route through StatService
            if StatService then
                StatService:RegisterElimination(shooter, otherPlayer)
            end

            if shooter.Name ~= victimName then
                pcall(function() KillFeedEvent:FireAllClients(shooter.Name, victimName, 0) end)
                if shooter.Team then
                    pcall(function() AddScore:Fire(shooter.Team.Name, KILL_POINTS) end)
                end
                if XPModule and XPModule.AwardXP then
                    pcall(function() XPModule.AwardXP(shooter, "PlayerKill", nil, { coinAward = 0 }) end)
                end
            end
        end
    end

    -- Also check NPC humanoids (mobs, dummies) in workspace
    for _, model in ipairs(Workspace:GetDescendants()) do
        if not model:IsA("Humanoid") then continue end
        if model.Health <= 0 then continue end

        local character = model.Parent
        if not character or not character:IsA("Model") then continue end

        -- Skip players (already handled above)
        if Players:GetPlayerFromCharacter(character) then continue end

        local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
        if not hrp then
            -- try any BasePart
            for _, p in ipairs(character:GetChildren()) do
                if p:IsA("BasePart") then hrp = p; break end
            end
        end
        if not hrp then continue end

        local dist = (hrp.Position - hitPosition).Magnitude
        if dist > blastRadius then continue end

        -- Tag and damage
        pcall(function()
            model:SetAttribute("lastDamagerUserId", shooter.UserId)
            model:SetAttribute("lastDamagerName", shooter.Name)
            model:SetAttribute("lastDamageTime", tick())
        end)

        model:TakeDamage(damage)

        if model.Health <= 0 then
            pcall(function() model:SetAttribute("_killCredited", true) end)

            local victimName = character.Name or "Unknown"

            if StatService then
                StatService:RegisterMobKill(shooter, victimName)
            end

            pcall(function() KillFeedEvent:FireAllClients(shooter.Name, victimName, 0) end)
            if shooter.Team then
                pcall(function() AddScore:Fire(shooter.Team.Name, KILL_POINTS) end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- SPAWN & SIMULATE ROCKET
--------------------------------------------------------------------------------
function DevRocketService.FireRocket(player, aimDirection)
    -- Get muzzle origin from equipped tool
    local char = player.Character
    if not char then return end

    local tool = char:FindFirstChild(DevWeaponConfig.TOOL_NAME)
    if not tool then return end

    -- Find muzzle point or fall back to handle front
    local muzzle = tool:FindFirstChild("MuzzlePoint", true)
    local origin
    if muzzle and muzzle:IsA("Attachment") then
        origin = muzzle.WorldPosition
    else
        local handle = tool:FindFirstChild("Handle")
        if handle then
            origin = (handle.CFrame * CFrame.new(0, 0, -2.5)).Position
        else
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            origin = (hrp.CFrame * CFrame.new(0, 0, -3)).Position
        end
    end

    -- Normalize aim direction; reject garbage
    if typeof(aimDirection) ~= "Vector3" then return end
    if aimDirection.Magnitude < 0.01 then return end
    local dir = aimDirection.Unit

    -- Mark cooldown
    DevRocketService.MarkFired(player)

    -- Create projectile
    local rocket = createRocketVisual(origin, dir)

    -- Simulate movement on the server with stepped frame updates
    local speed = DevWeaponConfig.ROCKET_SPEED
    local lifetime = DevWeaponConfig.ROCKET_LIFETIME
    local elapsed = 0

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { char, rocket }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    local connection
    connection = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if elapsed >= lifetime then
            -- Expired without hitting anything
            if connection then connection:Disconnect() end
            pcall(function() rocket:Destroy() end)
            return
        end

        local step = dir * speed * dt
        local result = Workspace:Raycast(rocket.Position, step, rayParams)

        if result then
            -- Hit something
            if connection then connection:Disconnect() end
            local hitPos = result.Position
            pcall(function() rocket:Destroy() end)

            -- VFX + damage
            createExplosionVFX(hitPos)
            applyAoEDamage(player, hitPos)
            print("[DevRocket] Impact at", hitPos)
        else
            -- Move forward
            pcall(function()
                rocket.CFrame = CFrame.lookAt(rocket.Position + step, rocket.Position + step + dir)
            end)
        end
    end)

    -- Safety cleanup in case the connection leaks
    Debris:AddItem(rocket, lifetime + 1)

    print("[DevRocket]", player.Name, "fired rocket")
end

return DevRocketService
