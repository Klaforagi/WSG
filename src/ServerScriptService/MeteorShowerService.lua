--[[
    MeteorShowerService.lua  (ServerScriptService – ModuleScript)
    Server-authoritative meteor spawning, movement, and cleanup.

    Public API:
        MeteorShowerService:Start()   – begin the meteor shower loop
        MeteorShowerService:Stop()    – stop spawning and clean up
        MeteorShowerService:IsActive()

    Responsibilities:
        - Target zone sampling     → picks random landing positions from zone parts
        - Meteor construction      → assembles visible meteor with fire/glow effects
        - Movement (TweenService)  → scripted Quad-In fall from sky to ground
        - Impact flash             → simple expanding neon sphere on landing
        - Lifecycle cleanup        → Debris-based removal, force-cleanup safety net

    Extension points for future work:
        - Damage:          add in the impact handler (tween.Completed callback)
        - Collectible drops: spawn items at the impact position
        - Warning circles: spawn a decal/part at targetPos before the tween starts
        - NPC spawning:    spawn enemies at the impact site
        - Advanced VFX:    swap createMeteor / createImpactEffect for richer visuals
        - Terrain craters: deform terrain at the impact position
]]

local Players              = game:GetService("Players")
local TweenService         = game:GetService("TweenService")
local Debris               = game:GetService("Debris")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("MeteorShowerConfig"))

---------------------------------------------------------------------
-- Currency integration (for reward payout)
---------------------------------------------------------------------
local CurrencyService
pcall(function()
    CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)
if not CurrencyService then
    warn("[MeteorShower] CurrencyService not found – rewards will not be granted")
end

---------------------------------------------------------------------
-- Remotes (server → client)
---------------------------------------------------------------------
-- MeteorShardCollected: tells the collecting player to show popup + play sound
local ShardCollectedRemote = ReplicatedStorage:FindFirstChild("MeteorShardCollected")
if not ShardCollectedRemote then
    ShardCollectedRemote = Instance.new("RemoteEvent")
    ShardCollectedRemote.Name = "MeteorShardCollected"
    ShardCollectedRemote.Parent = ReplicatedStorage
end

---------------------------------------------------------------------
-- Module
---------------------------------------------------------------------
local MeteorShowerService = {}

local _active          = false   -- true while shower is running
local _spawnThread     = nil     -- coroutine running the spawn loop
local _currentMeteors  = {}      -- references to in-flight meteor parts
local _generation      = 0       -- bumped on each Start(); prevents stale cleanup
local _activeShards    = {}      -- { part, connection } pairs for cleanup

---------------------------------------------------------------------
-- Target zone helpers
---------------------------------------------------------------------

--- Returns (or creates) the zone folder in Workspace.
-- If no folder exists, a 200×200 fallback zone at the world origin is
-- created so testing works immediately out of the box.
local function getOrCreateZoneFolder()
    local folder = workspace:FindFirstChild(Config.ZONE_FOLDER_NAME)
    if folder then return folder end

    warn("[MeteorShower] Zone folder '" .. Config.ZONE_FOLDER_NAME
        .. "' not found – creating default 200×200 fallback zone.")

    folder = Instance.new("Folder")
    folder.Name = Config.ZONE_FOLDER_NAME
    folder.Parent = workspace

    local centerPart = workspace:FindFirstChild("CenterPoint")
    local centerPos = centerPart and centerPart.Position or Vector3.new(0, 0, 0)

    local zone = Instance.new("Part")
    zone.Name = "DefaultZone"
    zone.Size = Vector3.new(200, 1, 200)
    zone.Position = Vector3.new(centerPos.X, centerPos.Y + 5, centerPos.Z)
    zone.Anchored = true
    zone.CanCollide = false
    zone.CanTouch = false
    zone.CanQuery = false
    zone.Transparency = 1
    zone.Parent = folder

    return folder
end

--- Pick a random landing position from a random zone part.
-- Returns a Vector3 on the top face of the chosen zone, or nil.
local function sampleTargetPosition()
    local folder = getOrCreateZoneFolder()

    local zones = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(zones, child)
        end
    end

    if #zones == 0 then
        warn("[MeteorShower] No BasePart children in zone folder")
        return nil
    end

    local zone = zones[math.random(1, #zones)]
    local cf   = zone.CFrame
    local size = zone.Size

    -- Random point on the top face of the zone part (works with rotated parts)
    local localOffset = Vector3.new(
        (math.random() * 2 - 1) * (size.X / 2),
        size.Y / 2,   -- top face
        (math.random() * 2 - 1) * (size.Z / 2)
    )

    return cf:PointToWorldSpace(localOffset)
end

---------------------------------------------------------------------
-- Meteor construction
---------------------------------------------------------------------

--- Clone and attach the custom VFX meteor model to a root Part.
-- All model BaseParts are welded to root so the tween on root moves everything.
local function attachVFXModel(root, spawnCF)
    local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
    local template  = vfxFolder and vfxFolder:FindFirstChild("Meteor")
    if not template then
        warn("[MeteorShower] ReplicatedStorage.VFX.Meteor not found – using fallback ball")
        return false
    end

    local clone = template:Clone()

    -- Normalise to a consistent pivot before welding
    if clone:IsA("Model") then
        if not clone.PrimaryPart then
            clone.PrimaryPart = clone:FindFirstChildOfClass("BasePart")
        end
        clone:PivotTo(spawnCF * CFrame.Angles(math.rad(90), 0, 0))
    elseif clone:IsA("BasePart") then
        clone.CFrame = spawnCF * CFrame.Angles(math.rad(90), 0, 0)
    end

    -- Parent into workspace tree so WeldConstraints resolve correctly
    clone.Parent = root

    -- Weld every BasePart to root and strip physics/collision
    local parts = clone:IsA("BasePart")
        and { clone }
        or clone:GetDescendants()

    for _, part in ipairs(parts) do
        if part:IsA("BasePart") then
            part.Anchored   = false   -- must be unanchored to follow the weld
            part.CanCollide = false
            part.CanTouch   = false

            local weld  = Instance.new("WeldConstraint")
            weld.Part0  = root
            weld.Part1  = part
            weld.Parent = root
        end
    end

    return true
end

--- Build a meteor anchored to an invisible root Part.
-- The root is the tween target and is returned as "meteor" to the caller.
-- Fire / Smoke / PointLight are direct children of root so the existing
-- impact-cleanup loop (meteor:GetChildren()) finds them without changes.
-- Returns: rootPart, spawnPos, targetPos
local function createMeteor(targetPos)
    -- Spawn position: high above + slight horizontal jitter for diagonal trajectory
    local jitter   = Config.SPAWN_ANGLE_JITTER
    local spawnPos = targetPos + Vector3.new(
        (math.random() * 2 - 1) * jitter,
        Config.SPAWN_HEIGHT,
        (math.random() * 2 - 1) * jitter
    )

    local direction = (targetPos - spawnPos).Unit
    local spawnCF   = CFrame.new(spawnPos, spawnPos + direction)

    -- Invisible anchor part – this is what TweenService moves
    local root = Instance.new("Part")
    root.Name        = "Meteor"
    root.Size        = Vector3.new(1, 1, 1)
    root.Transparency = 1
    root.Anchored    = true
    root.CanCollide  = false
    root.CanTouch    = false
    root.CastShadow  = false
    root.CFrame      = spawnCF
    root.Parent      = workspace   -- parent first so welds resolve in-world

    local usedVFX = attachVFXModel(root, spawnCF)

    if not usedVFX then
        -- Fallback: make the root itself the visible ball
        root.Transparency = 0
        root.Shape    = Enum.PartType.Ball
        root.Size     = Vector3.new(Config.METEOR_DIAMETER, Config.METEOR_DIAMETER, Config.METEOR_DIAMETER)
        root.Material = Enum.Material.Slate
        root.Color    = Config.METEOR_COLOR

        local fire = Instance.new("Fire")
        fire.Size          = Config.METEOR_DIAMETER * 1.5
        fire.Heat          = 15
        fire.Color         = Config.FIRE_COLOR
        fire.SecondaryColor = Config.FIRE_SEC_COLOR
        fire.Parent        = root

        local smoke = Instance.new("Smoke")
        smoke.Size         = 4
        smoke.Opacity      = 0.4
        smoke.Color        = Color3.fromRGB(80, 60, 40)
        smoke.RiseVelocity = 2
        smoke.Parent       = root
    end

    -- Glow always lives on root (direct child) so the impact cleanup
    -- loop (meteor:GetChildren()) can disable it
    local light = Instance.new("PointLight")
    light.Color      = Config.GLOW_COLOR
    light.Brightness = Config.GLOW_BRIGHTNESS
    light.Range      = Config.GLOW_RANGE
    light.Parent     = root

    return root, spawnPos, targetPos
end

---------------------------------------------------------------------
-- Impact effect
---------------------------------------------------------------------

--- Play a random Meteor or Meteor2 sound from the Sounds folder at the given part.
local function playMeteorSound(part)
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end

    local names = { "Meteor", "Meteor2" }
    local source = soundsFolder:FindFirstChild(names[math.random(1, 2)])
    if not source then return end

    local sound = source:Clone()
    sound.PlaybackSpeed = source.PlaybackSpeed + (math.random() * 0.3 - 0.15)
    sound.Parent = part
    sound:Play()
end

--- Quick expanding neon flash at the landing site.
local function createImpactEffect(position)
    local diameter = Config.METEOR_DIAMETER

    local flash = Instance.new("Part")
    flash.Name = "MeteorImpact"
    flash.Shape = Enum.PartType.Ball
    flash.Size = Vector3.new(diameter * 1.5, diameter * 1.5, diameter * 1.5)
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.fromRGB(180, 225, 255)   -- light blue
    flash.Anchored = true
    flash.CanCollide = false
    flash.Transparency = 0.3
    flash.CFrame = CFrame.new(position)
    flash.Parent = workspace

    local impactLight = Instance.new("PointLight")
    impactLight.Color = Color3.fromRGB(200, 235, 255)  -- pale blue-white
    impactLight.Brightness = 4
    impactLight.Range = 50
    impactLight.Parent = flash

    -- Expand + fade out
    local tweenInfo = TweenInfo.new(
        Config.IMPACT_FLASH_DURATION,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )

    local flashTween = TweenService:Create(flash, tweenInfo, {
        Size = Vector3.new(diameter * 3, diameter * 3, diameter * 3),
        Transparency = 1,
    })

    local lightTween = TweenService:Create(impactLight, tweenInfo, {
        Brightness = 0,
    })

    flashTween:Play()
    lightTween:Play()

    -- Debris handles cleanup even if tweens error
    Debris:AddItem(flash, Config.IMPACT_FLASH_DURATION + 0.1)
end

---------------------------------------------------------------------
-- Impact damage (server-authoritative, MaxHealth-based)
---------------------------------------------------------------------

local function applyImpactDamage(impactPos)
    local directR = Config.DIRECT_HIT_RADIUS
    local splashR = Config.SPLASH_RADIUS

    -- Pre-load MobHit sound template
    local soundsFolder  = ReplicatedStorage:FindFirstChild("Sounds")
    local mobsFolder    = soundsFolder and soundsFolder:FindFirstChild("Mobs")
    local mobHitTemplate = mobsFolder and mobsFolder:FindFirstChild("MobHit")

    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local dist = (hrp.Position - impactPos).Magnitude
        local didHit = false

        if dist <= directR then
            hum:TakeDamage(hum.MaxHealth * Config.DIRECT_HIT_DAMAGE_PCT)
            didHit = true
        elseif dist <= splashR then
            hum:TakeDamage(hum.MaxHealth * Config.SPLASH_DAMAGE_PCT)
            didHit = true
        end

        if didHit and mobHitTemplate and mobHitTemplate:IsA("Sound") then
            local s = mobHitTemplate:Clone()
            s.Parent = hrp
            s:Play()
            Debris:AddItem(s, 4)
        end
    end
end

---------------------------------------------------------------------
-- Meteor shard spawning & collection
---------------------------------------------------------------------

local function spawnShard(position)
    if not _active then return end
    if math.random() > Config.SHARD_SPAWN_CHANCE then return end

    local shard = Instance.new("Part")
    shard.Name = "MeteorShard"
    shard.Shape = Enum.PartType.Ball
    shard.Size = Config.SHARD_SIZE
    shard.Material = Enum.Material.Neon
    shard.Color = Config.SHARD_COLOR
    shard.Anchored = true
    shard.CanCollide = false
    shard.CFrame = CFrame.new(position + Vector3.new(0, Config.SHARD_Y_OFFSET, 0))
    shard.Parent = workspace

    local light = Instance.new("PointLight")
    light.Color = Config.SHARD_COLOR
    light.Brightness = Config.SHARD_LIGHT_BRIGHTNESS
    light.Range = Config.SHARD_LIGHT_RANGE
    light.Parent = shard

    local bobInfo = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local bobTween = TweenService:Create(shard, bobInfo, {
        CFrame = shard.CFrame + Vector3.new(0, 1.5, 0),
    })
    bobTween:Play()

    local collected = false

    local conn
    conn = shard.Touched:Connect(function(hit)
        if collected then return end

        local char = hit.Parent
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local plr = Players:GetPlayerFromCharacter(char)
        if not plr then return end

        collected = true

        -- Grant +5 coins
        local rewardAmount = Config.SHARD_REWARD_COINS
        if CurrencyService and CurrencyService.AddCoins then
            pcall(function()
                CurrencyService:AddCoins(plr, rewardAmount, "MeteorShard")
            end)
        end

        -- Tell the client: show popup + play Collect sound
        pcall(function()
            ShardCollectedRemote:FireClient(plr, shard.Position, rewardAmount)
        end)

        pcall(function() conn:Disconnect() end)
        pcall(function() bobTween:Cancel() end)
        pcall(function() shard:Destroy() end)
    end)

    -- Fade out during the last 5 seconds of the shard's lifetime
    local fadeStart = Config.SHARD_LIFETIME - 5
    if fadeStart > 0 then
        task.delay(fadeStart, function()
            if not shard or shard.Parent == nil then return end
            local fadeInfo = TweenInfo.new(5, Enum.EasingStyle.Linear)
            TweenService:Create(shard, fadeInfo, { Transparency = 1 }):Play()
            local shardLight = shard:FindFirstChildOfClass("PointLight")
            if shardLight then
                TweenService:Create(shardLight, fadeInfo, { Brightness = 0 }):Play()
            end
        end)
    end

    Debris:AddItem(shard, Config.SHARD_LIFETIME)
    table.insert(_activeShards, { part = shard, connection = conn, tween = bobTween })
end

local function spawnOneMeteor()
    if not _active then return end

    -- Enforce active-meteor cap
    -- Prune destroyed references first
    for i = #_currentMeteors, 1, -1 do
        if _currentMeteors[i] == nil or _currentMeteors[i].Parent == nil then
            table.remove(_currentMeteors, i)
        end
    end

    if #_currentMeteors >= Config.MAX_ACTIVE_METEORS then
        return  -- skip this cycle; will try again next interval
    end

    local targetPos = sampleTargetPosition()
    if not targetPos then return end

    local meteor, spawnPos, target = createMeteor(targetPos)
    table.insert(_currentMeteors, meteor)

    -- Scripted fall: Quad-In easing simulates gravitational acceleration
    local direction = (target - spawnPos).Unit
    local endCF = CFrame.new(target, target + direction)

    local tweenInfo = TweenInfo.new(
        Config.FALL_DURATION,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.In
    )

    local tween = TweenService:Create(meteor, tweenInfo, { CFrame = endCF })

    tween.Completed:Connect(function()
        -- Impact flash
        createImpactEffect(target)

        -- Deal AoE damage at impact site
        applyImpactDamage(target)

        -- Spawn a collectible shard
        spawnShard(target)

        -- Turn off emitters so they fade naturally before removal
        pcall(function()
            for _, child in ipairs(meteor:GetChildren()) do
                if child:IsA("Fire") or child:IsA("Smoke") or child:IsA("PointLight") then
                    child.Enabled = false
                end
            end
        end)

        -- Schedule removal via Debris (safe against errors)
        Debris:AddItem(meteor, Config.IMPACT_CLEANUP_DELAY)
    end)

    tween:Play()
    playMeteorSound(meteor)
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------

--- Start the meteor shower.  Spawns meteors at random intervals
--- until :Stop() is called.
function MeteorShowerService:Start()
    if _active then return end

    _active = true
    _generation = _generation + 1
    _currentMeteors = {}   -- fresh table for this session

    print("[MeteorShower] Shower STARTED")

    _spawnThread = task.spawn(function()
        while _active do
            spawnOneMeteor()

            -- Randomised interval for natural cadence
            local interval = Config.SPAWN_INTERVAL_MIN
                + math.random() * (Config.SPAWN_INTERVAL_MAX - Config.SPAWN_INTERVAL_MIN)
            task.wait(interval)
        end
    end)
end

--- Stop the meteor shower.  Cancels the spawn loop and schedules
--- cleanup of any remaining in-flight meteors.
function MeteorShowerService:Stop()
    if not _active then return end
    _active = false

    print("[MeteorShower] Shower STOPPED")

    -- Cancel spawn loop
    if _spawnThread then
        pcall(task.cancel, _spawnThread)
        _spawnThread = nil
    end

    -- Leave active shards alive so they time out naturally (with fade).
    -- Clear the tracking table so the next event starts fresh.
    _activeShards = {}
    _currentMeteors = {}
end

--- Returns true while the shower is actively spawning meteors.
function MeteorShowerService:IsActive()
    return _active
end

return MeteorShowerService
