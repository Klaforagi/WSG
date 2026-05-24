--[[
    GoblinRaidService.lua  (ServerScriptService - ModuleScript)
    Server-authoritative Goblin Raid event. Spawns a capped temporary wave of
    existing Goblin NPCs, uses the shared MobCombat/KillTracker pipeline for
    normal monster kills, and grants a small event bonus once per credited kill.
]]

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ServerStorage       = game:GetService("ServerStorage")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")
local PhysicsService      = game:GetService("PhysicsService")
local TweenService        = game:GetService("TweenService")

local EventConfig    = require(ReplicatedStorage:WaitForChild("EventConfig"))
local MobSettings    = require(ReplicatedStorage:WaitForChild("MobSettings"))
local MobCombat      = require(ServerScriptService:WaitForChild("MobCombat"))
local MobSkinService = require(ServerScriptService:WaitForChild("MobSkinService"))

local CurrencyService
pcall(function()
    CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)

local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

local RewardRemote = ReplicatedStorage:FindFirstChild("GoblinRaidReward")
if not RewardRemote then
    RewardRemote = Instance.new("RemoteEvent")
    RewardRemote.Name = "GoblinRaidReward"
    RewardRemote.Parent = ReplicatedStorage
end

local ZombieKillRemote = ReplicatedStorage:FindFirstChild("ZombieKill")
if not ZombieKillRemote then
    ZombieKillRemote = Instance.new("RemoteEvent")
    ZombieKillRemote.Name = "ZombieKill"
    ZombieKillRemote.Parent = ReplicatedStorage
end

local EVENT_ID = "GoblinRaid"
local TEMPLATE_NAME = "Goblin"
local DEFAULT_MOB_TAG = "ZombieNPC"
local RAID_TAG = "GoblinRaidNPC"
local MOB_COLLISION_GROUP = "Mobs"
local DEFAULT_WALK_ANIM_ID = "rbxassetid://180426354"
local KILL_CREDIT_WINDOW = 15

pcall(function() PhysicsService:RegisterCollisionGroup(MOB_COLLISION_GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(MOB_COLLISION_GROUP, MOB_COLLISION_GROUP, false) end)

local GoblinRaidService = {}

local _active = false
local _spawnThread = nil
local _records = {}
local _totalSpawned = 0
local _defeated = 0
local _generation = 0
local _warnedMissingTemplate = false

local function getDef()
    return EventConfig.EventDefs and EventConfig.EventDefs[EVENT_ID] or {}
end

local function getNumber(key, fallback)
    local value = tonumber(getDef()[key])
    if value == nil then return fallback end
    return value
end

local function getRootPart(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function setModelCollisionGroup(model, groupName)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored = false
            desc.CanCollide = true
            desc.CollisionGroup = groupName
        end
    end
end

local function disableWeaponCollision(part)
    pcall(function()
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
    end)
end

local function applyGoblinWeaponCollisionFix(mobModel)
    for _, desc in ipairs(mobModel:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "Dagger" then
            disableWeaponCollision(desc)
        elseif (desc:IsA("Tool") or desc:IsA("Model")) and desc.Name == "Dagger" then
            for _, part in ipairs(desc:GetDescendants()) do
                if part:IsA("BasePart") then
                    disableWeaponCollision(part)
                end
            end
        end
    end
end

local function findGoblinTemplate()
    local mobsFolder = ServerStorage:FindFirstChild("Mobs")
    local template = mobsFolder and mobsFolder:FindFirstChild(TEMPLATE_NAME)
    if not template then
        template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
    end
    if template and template:IsA("Model") then
        return template
    end
    if not _warnedMissingTemplate then
        _warnedMissingTemplate = true
        warn("[GoblinRaid] Goblin template not found in ServerStorage.Mobs or ServerStorage")
    end
    return nil
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function getRaidMobConfig()
    local cfg = deepCopy(MobSettings.Get(TEMPLATE_NAME))
    cfg.Movement = cfg.Movement or {}
    cfg.Attack = cfg.Attack or {}

    cfg.Movement.WalkSpeed = getNumber("GoblinWalkSpeed", 10)
    cfg.Movement.ChaseSpeed = getNumber("GoblinChaseSpeed", 16)
    cfg.Movement.EnragedSpeed = getNumber("GoblinEnragedSpeed", 18)
    cfg.Movement.DetectionRadius = getNumber("GoblinDetectionRadius", 48)
    cfg.Movement.AggroDuration = getNumber("GoblinAggroDuration", 10)

    cfg.Attack.Damage = getNumber("GoblinDamage", 3)
    cfg.Attack.Cooldown = getNumber("GoblinAttackCooldown", 0.65)
    cfg.Attack.Range = getNumber("GoblinAttackRange", 7)
    cfg.Attack.Windup = getNumber("GoblinAttackWindup", 0.35)

    return cfg
end

local function getRaidFolder()
    local folder = Workspace:FindFirstChild("GoblinRaidMobs")
    if folder then return folder end

    folder = Instance.new("Folder")
    folder.Name = "GoblinRaidMobs"
    folder.Parent = Workspace
    return folder
end

local function addBasePartsFrom(container, output)
    if not container then return end
    if container:IsA("BasePart") then
        table.insert(output, container)
        return
    end
    for _, desc in ipairs(container:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(output, desc)
        end
    end
end

local function getSpawnParts()
    local parts = {}
    local eventSpawns = Workspace:FindFirstChild("EventSpawns")
    if eventSpawns then
        addBasePartsFrom(eventSpawns:FindFirstChild("GoblinRaid"), parts)
    end

    for _, name in ipairs({
        "GoblinRaidSpawns",
        "EventGoblinRaidSpawns",
        "GoblinRaidZones",
        "EventGoblinRaidZones",
        "EventZones",
        "GoldRushZones",
        "EventGoldRushZones",
        "MeteorShowerZones",
    }) do
        addBasePartsFrom(Workspace:FindFirstChild(name), parts)
        if #parts > 0 then
            return parts
        end
    end

    local map = Workspace:FindFirstChild("WSG")
    if map then
        local mapEventSpawns = map:FindFirstChild("EventSpawns")
        if mapEventSpawns then
            addBasePartsFrom(mapEventSpawns:FindFirstChild("GoblinRaid"), parts)
        end
        addBasePartsFrom(map:FindFirstChild("GoblinRaidSpawns"), parts)
        addBasePartsFrom(map:FindFirstChild("EventGoblinRaidSpawns"), parts)
        if #parts > 0 then
            return parts
        end

        for index = 1, 6 do
            addBasePartsFrom(map:FindFirstChild("MobArea" .. tostring(index)), parts)
        end
    end

    return parts
end

local function raycastToGround(position)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getRaidFolder() }

    local result = Workspace:Raycast(position + Vector3.new(0, 220, 0), Vector3.new(0, -520, 0), params)
    if result then
        return result.Position + Vector3.new(0, 2.6, 0)
    end
    return Vector3.new(position.X, math.max(position.Y, 8), position.Z)
end

local function samplePointInPart(part)
    local localOffset = Vector3.new(
        (math.random() * 2 - 1) * part.Size.X * 0.42,
        part.Size.Y * 0.5,
        (math.random() * 2 - 1) * part.Size.Z * 0.42
    )
    return part.CFrame:PointToWorldSpace(localOffset)
end

local function sampleFallbackPosition()
    local center = Vector3.new(-70, 20, 110)
    local radiusX = 85
    local radiusZ = 110

    local map = Workspace:FindFirstChild("WSG")
    if map and map:IsA("Model") then
        local ok, cf, size = pcall(function()
            local boxCf, boxSize = map:GetBoundingBox()
            return boxCf, boxSize
        end)
        if ok and cf and size then
            center = cf.Position
            radiusX = math.max(45, math.min(95, size.X * 0.18))
            radiusZ = math.max(55, math.min(125, size.Z * 0.18))
        end
    end

    local x = center.X + (math.random() * 2 - 1) * radiusX
    local z = center.Z + (math.random() * 2 - 1) * radiusZ
    return raycastToGround(Vector3.new(x, center.Y, z)), nil
end

local function sampleSpawnPosition()
    local parts = getSpawnParts()
    if #parts > 0 then
        local part = parts[math.random(1, #parts)]
        return raycastToGround(samplePointInPart(part)), part
    end
    return sampleFallbackPosition()
end

local function resolveKiller(humanoid)
    if not humanoid then return nil end
    local damageTime = humanoid:GetAttribute("lastDamageTime")
    if not damageTime or (tick() - damageTime) > KILL_CREDIT_WINDOW then
        return nil
    end

    local objVal = humanoid:FindFirstChild("LastDamagedBy")
    if objVal and objVal:IsA("ObjectValue") and objVal.Value and objVal.Value:IsA("Player") and objVal.Value.Parent == Players then
        return objVal.Value
    end

    local userId = humanoid:GetAttribute("lastDamagerUserId")
    if userId then
        local player = Players:GetPlayerByUserId(userId)
        if player then return player end
    end

    local name = humanoid:GetAttribute("lastDamagerName")
    if name then
        return Players:FindFirstChild(name)
    end
    return nil
end

local function fireRewardPopup(player, worldPosition, coins, xp)
    if not player or not player.Parent then return end
    pcall(function()
        RewardRemote:FireClient(player, worldPosition, coins or 0, xp or 0)
    end)
end

local function awardRaidBonus(record)
    if not record or record.bonusAwarded then return end
    record.bonusAwarded = true

    local killer = resolveKiller(record.humanoid)
    if not killer then return end

    local minCoins = math.floor(getNumber("BonusCoinsMin", 10))
    local maxCoins = math.floor(getNumber("BonusCoinsMax", 20))
    if maxCoins < minCoins then
        maxCoins = minCoins
    end
    local coinBonus = math.random(minCoins, maxCoins)
    local grantedCoins = coinBonus

    if CurrencyService and CurrencyService.AddCoins then
        local ok, result = pcall(function()
            return CurrencyService:AddCoins(killer, coinBonus, "GoblinRaidBonus")
        end)
        if ok and type(result) == "number" then
            grantedCoins = result
        end
    end

    local xpBonus = math.max(0, math.floor(getNumber("BonusXP", 3)))
    if xpBonus > 0 and XPModule and XPModule.AwardXP then
        pcall(function()
            XPModule.AwardXP(killer, "GoblinRaid", xpBonus, {
                coinAward = grantedCoins,
                eventName = EVENT_ID,
            })
        end)
    end

    local root = getRootPart(record.model)
    local popupPosition = root and root.Position or record.spawnPosition or Vector3.new()
    fireRewardPopup(killer, popupPosition, grantedCoins, xpBonus)
end

local function forgetRecord(record)
    if not record then return end
    if record.model then
        _records[record.model] = nil
    end
    if record.diedConn then
        pcall(function() record.diedConn:Disconnect() end)
        record.diedConn = nil
    end
    if record.ancestryConn then
        pcall(function() record.ancestryConn:Disconnect() end)
        record.ancestryConn = nil
    end
end

local function fadeAndDestroy(model)
    if not model or not model.Parent then return end

    local fadeInfo = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.CanTouch = false
            desc.CanQuery = false
            desc.CanCollide = false
            desc.Anchored = true
            pcall(function()
                TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
            end)
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            pcall(function()
                TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
            end)
        end
    end

    task.delay(1.1, function()
        if model and model.Parent then
            model:Destroy()
        end
    end)
end

local function cleanupRecord(record)
    if not record then return end
    local model = record.model
    local humanoid = record.humanoid

    if record.combatHandle and record.combatHandle.Stop then
        pcall(function() record.combatHandle.Stop() end)
    end

    forgetRecord(record)

    if model and model.Parent then
        pcall(function() CollectionService:RemoveTag(model, RAID_TAG) end)
        pcall(function() CollectionService:RemoveTag(model, record.mobTag or DEFAULT_MOB_TAG) end)
        if humanoid and humanoid.Health > 0 then
            humanoid:SetAttribute("EliminationProcessed", true)
            humanoid:SetAttribute("_killCredited", true)
            fadeAndDestroy(model)
        end
    end
end

local function countAliveRaidGoblins()
    local count = 0
    for model, record in pairs(_records) do
        local humanoid = record.humanoid
        if model and model.Parent and humanoid and humanoid.Health > 0 then
            count = count + 1
        end
    end
    return count
end

local function spawnEffect(position)
    local burst = Instance.new("Part")
    burst.Name = "GoblinRaidSpawnBurst"
    burst.Shape = Enum.PartType.Ball
    burst.Size = Vector3.new(1.2, 1.2, 1.2)
    burst.Material = Enum.Material.Neon
    burst.Color = Color3.fromRGB(90, 210, 95)
    burst.Anchored = true
    burst.CanCollide = false
    burst.CanTouch = false
    burst.CanQuery = false
    burst.Transparency = 0.25
    burst.CFrame = CFrame.new(position)
    burst.Parent = Workspace

    local tween = TweenService:Create(burst, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(5, 5, 5),
        Transparency = 1,
    })
    tween:Play()
    task.delay(0.45, function()
        if burst and burst.Parent then burst:Destroy() end
    end)
end

local function spawnGoblin()
    if not _active then return nil end
    if _totalSpawned >= getNumber("TotalSpawnCap", 18) then return nil end
    if countAliveRaidGoblins() >= getNumber("MaxActiveGoblins", 9) then return nil end

    local template = findGoblinTemplate()
    if not template then return nil end

    local spawnPosition, areaPart = sampleSpawnPosition()
    local cfg = getRaidMobConfig()
    local spawnCfg = (cfg and cfg.Spawn) or {}
    local appearanceCfg = (cfg and cfg.Appearance) or {}
    local mobTag = (spawnCfg.Tag and spawnCfg.Tag ~= "") and spawnCfg.Tag or DEFAULT_MOB_TAG

    local mob = template:Clone()
    mob.Name = TEMPLATE_NAME
    mob:SetAttribute("IsSpawnedMob", true)
    mob:SetAttribute("IsMob", true)
    mob:SetAttribute("IsEventNPC", true)
    mob:SetAttribute("EventName", EVENT_ID)
    mob:SetAttribute("Source", EVENT_ID)
    mob:SetAttribute("TemplateName", TEMPLATE_NAME)
    mob:SetAttribute("SpawnPortalGroup", EVENT_ID)

    local root = getRootPart(mob)
    if root then
        mob.PrimaryPart = mob.PrimaryPart or root
    end

    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[GoblinRaid] Goblin template has no Humanoid")
        mob:Destroy()
        return nil
    end

    local health = math.max(1, math.floor(getNumber("GoblinHealth", 70)))
    humanoid.MaxHealth = health
    humanoid.Health = health

    if type(appearanceCfg.SkinPalette) == "table" and #appearanceCfg.SkinPalette > 0 then
        MobSkinService.applyMobSkin(mob, appearanceCfg.SkinPalette, appearanceCfg.SkinVariation)
    elseif typeof(appearanceCfg.BaseSkinColor) == "Color3" then
        MobSkinService.applyMobSkin(mob, appearanceCfg.BaseSkinColor, appearanceCfg.SkinVariation)
    end

    pcall(function()
        local yaw = math.random() * math.pi * 2
        mob:PivotTo(CFrame.new(spawnPosition) * CFrame.Angles(0, yaw, 0))
    end)

    CollectionService:AddTag(mob, mobTag)
    CollectionService:AddTag(mob, RAID_TAG)
    setModelCollisionGroup(mob, MOB_COLLISION_GROUP)
    applyGoblinWeaponCollisionFix(mob)

    mob.Parent = getRaidFolder()
    if root and root:IsA("BasePart") then
        pcall(function() root:SetNetworkOwner(nil) end)
    end

    spawnEffect(spawnPosition)

    local record = {
        model = mob,
        humanoid = humanoid,
        mobTag = mobTag,
        spawnPosition = spawnPosition,
        bonusAwarded = false,
    }
    _records[mob] = record
    _totalSpawned = _totalSpawned + 1

    record.diedConn = humanoid.Died:Connect(function()
        _defeated = _defeated + 1
        awardRaidBonus(record)
        forgetRecord(record)
    end)

    record.ancestryConn = mob.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            forgetRecord(record)
        end
    end)

    record.combatHandle = MobCombat.StartMob(mob, cfg, {
        zombieKillEvent = ZombieKillRemote,
        mobTag = mobTag,
        defaultWalkAnimId = DEFAULT_WALK_ANIM_ID,
        getRootPart = getRootPart,
        spawnPos = spawnPosition,
        areaPart = areaPart,
        mobCollisionGroup = MOB_COLLISION_GROUP,
    })

    return mob
end

local function spawnWave(count)
    local spawned = 0
    for _ = 1, count do
        if not _active then break end
        if _totalSpawned >= getNumber("TotalSpawnCap", 18) then break end
        if countAliveRaidGoblins() >= getNumber("MaxActiveGoblins", 9) then break end
        if spawnGoblin() then
            spawned = spawned + 1
        end
    end
    return spawned
end

function GoblinRaidService:Start()
    if _active then return end

    _active = true
    _generation = _generation + 1
    _totalSpawned = 0
    _defeated = 0
    _records = {}

    print("[GoblinRaid] Started")

    local generation = _generation
    _spawnThread = task.spawn(function()
        local initialMin = math.floor(getNumber("InitialWaveMin", 4))
        local initialMax = math.floor(getNumber("InitialWaveMax", 6))
        if initialMax < initialMin then initialMax = initialMin end
        spawnWave(math.random(initialMin, initialMax))

        while _active and _generation == generation and _totalSpawned < getNumber("TotalSpawnCap", 18) do
            local minDelay = getNumber("ReinforcementIntervalMin", 6)
            local maxDelay = getNumber("ReinforcementIntervalMax", 10)
            if maxDelay < minDelay then maxDelay = minDelay end
            task.wait(minDelay + math.random() * (maxDelay - minDelay))
            if not _active or _generation ~= generation then return end

            local addMin = math.floor(getNumber("ReinforcementMin", 1))
            local addMax = math.floor(getNumber("ReinforcementMax", 2))
            if addMax < addMin then addMax = addMin end
            spawnWave(math.random(addMin, addMax))
        end
    end)
end

function GoblinRaidService:Stop()
    if not _active and next(_records) == nil then return end

    _active = false
    _generation = _generation + 1

    if _spawnThread then
        pcall(task.cancel, _spawnThread)
        _spawnThread = nil
    end

    local records = {}
    for _, record in pairs(_records) do
        table.insert(records, record)
    end
    for _, record in ipairs(records) do
        cleanupRecord(record)
    end

    _records = {}
    _totalSpawned = 0
    _defeated = 0

    print("[GoblinRaid] Ended")
end

function GoblinRaidService:IsActive()
    return _active
end

return GoblinRaidService