local Workspace = game:GetService("Workspace")
local Map = Workspace:WaitForChild("WSG")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local MobCombat = require(script.Parent:WaitForChild("MobCombat"))
local MobSkinService = require(script.Parent:WaitForChild("MobSkinService"))

---------------------------------------------------------------------------
-- Collision group: mobs don't collide with each other
---------------------------------------------------------------------------
local MOB_COLLISION_GROUP = "Mobs"
pcall(function() PhysicsService:RegisterCollisionGroup(MOB_COLLISION_GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(MOB_COLLISION_GROUP, MOB_COLLISION_GROUP, false) end)

---------------------------------------------------------------------------
-- Spawner configuration
---------------------------------------------------------------------------
local TEMPLATE_NAMES = { "Zombie", "Zack", "Orc", "Ogre", "Goblin" }
local PORTAL_GROUP_NAMES = { "DarkPortal1", "DarkPortal2" }
local PORTAL_PART_NAME = "PortalPlane"
local MOB_AREA_PREFIX = "MobArea"

local SPAWN_INTERVAL = 5
local SPAWN_BATCH = 1
local MAX_PER_PORTAL = 4
local MAX_TOTAL = 8
local DEFAULT_MOB_TAG = "ZombieNPC"
local DEFAULT_WALK_ANIM_ID = "rbxassetid://180426354"

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

local function isMatchActive()
    local matchState = script.Parent:GetAttribute("MatchState")
    return matchState == "Game" or matchState == "SuddenDeath"
end

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
local function getRootPart(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function setModelCollisionGroup(model, groupName)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            d.CanCollide = true
            d.CollisionGroup = groupName
        end
    end
end

-- Keep existing Orc Axe collision cleanup behavior
-- Weapon names to disable collision on, per mob
local MOB_WEAPON_NAMES = {
    Orc    = { "Axe" },
    Goblin = { "Dagger" },
    Ogre   = { "Hammer" },
}

local function disableWeaponCollision(part)
    pcall(function()
        part.CanCollide = false
        part.CanTouch   = false
        part.CanQuery   = false
        part.Massless   = true
    end)
end

local function applyMobPartCollisionOverrides(mobModel)
    if mobModel.Name ~= "Ogre" then return end

    for _, d in ipairs(mobModel:GetDescendants()) do
        if d:IsA("BasePart") and d.Name == "Helmet" then
            pcall(function()
                d.CanCollide = false
                d.Massless = true
            end)
        end
    end
end

local function applyOrcAxeCollisionFix(mobModel)
    local weaponNames = MOB_WEAPON_NAMES[mobModel.Name]
    if not weaponNames then return end

    local nameSet = {}
    for _, n in ipairs(weaponNames) do nameSet[n] = true end

    for _, d in ipairs(mobModel:GetDescendants()) do
        -- Direct BasePart with a weapon name
        if d:IsA("BasePart") and nameSet[d.Name] then
            disableWeaponCollision(d)
        end
        -- Tool or Model container with a weapon name (disable all BaseParts inside)
        if (d:IsA("Tool") or d:IsA("Model")) and nameSet[d.Name] then
            for _, p in ipairs(d:GetDescendants()) do
                if p:IsA("BasePart") then
                    disableWeaponCollision(p)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Template discovery and weighted pool
---------------------------------------------------------------------------
local function findTemplates()
    local out = {}
    local mobsFolder = ServerStorage:FindFirstChild("Mobs")

    for _, name in ipairs(TEMPLATE_NAMES) do
        local template
        if mobsFolder then
            template = mobsFolder:FindFirstChild(name)
            if template then
                table.insert(out, template)
                print("[MobSpawner] Template '" .. name .. "' found in ServerStorage.Mobs")
                continue
            end
        end

        template = ServerStorage:FindFirstChild(name)
        if template then
            table.insert(out, template)
            print("[MobSpawner] Template '" .. name .. "' found in ServerStorage")
        else
            warn("[MobSpawner] Template '" .. name .. "' not found in ServerStorage or ServerStorage.Mobs")
        end
    end

    return out
end

local templates = findTemplates()
local weightedPool = {}

---------------------------------------------------------------------------
-- Replicate sanitized mob templates to ReplicatedStorage so client UI
-- (e.g. KillCardUI viewport preview) can clone the canonical model without
-- touching workspace mobs. Scripts are stripped, parts anchored, no
-- collisions. Folder is rebuilt every server start so it stays fresh.
---------------------------------------------------------------------------
local function publishClientTemplates()
    local existing = ReplicatedStorage:FindFirstChild("MobTemplates")
    if existing then existing:Destroy() end
    local folder = Instance.new("Folder")
    folder.Name = "MobTemplates"
    folder.Parent = ReplicatedStorage

    for _, src in ipairs(templates) do
        if src and src:IsA("Model") then
            local ok, copy = pcall(function()
                src.Archivable = true
                return src:Clone()
            end)
            if ok and copy then
                -- Strip scripts so nothing tries to run on the client.
                for _, d in ipairs(copy:GetDescendants()) do
                    if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                        d:Destroy()
                    elseif d:IsA("BasePart") then
                        d.Anchored = true
                        d.CanCollide = false
                        d.CanQuery = false
                        d.CanTouch = false
                    end
                end
                copy.Parent = folder
            end
        end
    end
    print("[MobSpawner] Published " .. #folder:GetChildren() .. " mob templates to ReplicatedStorage.MobTemplates")
end
pcall(publishClientTemplates)

local function rebuildWeightedPool()
    table.clear(weightedPool)
    local disabledCount = 0

    for _, tpl in ipairs(templates) do
        local cfg = MobSettings and MobSettings.Get(tpl.Name) or nil
        local weight = math.floor((cfg and cfg.Spawn and cfg.Spawn.Weight) or 1)
        if weight > 0 then
            for _ = 1, weight do
                table.insert(weightedPool, tpl)
            end
        else
            disabledCount = disabledCount + 1
            print("[MobSpawner] Template '" .. tostring(tpl.Name) .. "' disabled (Spawn.Weight=0)")
        end
    end

    print("[MobSpawner] Weighted pool size: " .. #weightedPool .. " entries across " .. #templates .. " template(s)" .. (disabledCount > 0 and (" (" .. disabledCount .. " disabled)") or ""))
end

local function pickWeightedTemplate()
    if #weightedPool == 0 then return nil end
    return weightedPool[math.random(1, #weightedPool)]
end

rebuildWeightedPool()

---------------------------------------------------------------------------
-- Portal discovery and cap helpers
---------------------------------------------------------------------------
local function findPortals()
    local out = {}
    for idx, groupName in ipairs(PORTAL_GROUP_NAMES) do
        local group = Map:FindFirstChild(groupName)
        if not group then
            warn("[MobSpawner] Missing group: " .. groupName)
            continue
        end

        local areaName = MOB_AREA_PREFIX .. tostring(idx)
        local areaPart = Map:FindFirstChild(areaName)
        if not areaPart then
            warn("[MobSpawner] Missing area: " .. areaName)
        end

        for _, v in ipairs(group:GetDescendants()) do
            if v:IsA("BasePart") and v.Name == PORTAL_PART_NAME then
                table.insert(out, {
                    portal = v,
                    area = areaPart,
                    groupName = groupName,
                })
            end
        end
    end

    print("[MobSpawner] Discovered " .. #out .. " portal(s)")
    return out
end

local function countAliveMobs()
    local count = 0
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("IsSpawnedMob") == true then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function countAliveInPortalGroup(groupName)
    local count = 0
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("IsSpawnedMob") == true then
            if model:GetAttribute("SpawnPortalGroup") == groupName then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    count = count + 1
                end
            end
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Spawn one mob and hand off combat to MobCombat
---------------------------------------------------------------------------
local function spawnMobFromTemplate(entry, template)
    local tpl = template or (templates and templates[1])
    if not tpl or not entry or not entry.portal then return nil end

    local mobCfg = MobSettings and MobSettings.Get(tpl.Name) or nil
    local spawnCfg = (mobCfg and mobCfg.Spawn) or {}
    local appearanceCfg = (mobCfg and mobCfg.Appearance) or {}
    local mobTag = (spawnCfg.Tag and spawnCfg.Tag ~= "") and spawnCfg.Tag or DEFAULT_MOB_TAG

    local mob = tpl:Clone()
    mob.Name = tpl.Name
    mob.Parent = Workspace

    if type(appearanceCfg.SkinPalette) == "table" and #appearanceCfg.SkinPalette > 0 then
        MobSkinService.applyMobSkin(mob, appearanceCfg.SkinPalette, appearanceCfg.SkinVariation)
    elseif typeof(appearanceCfg.BaseSkinColor) == "Color3" then
        MobSkinService.applyMobSkin(mob, appearanceCfg.BaseSkinColor, appearanceCfg.SkinVariation)
    end

    local root = getRootPart(mob)
    local rootHalfY = (root and root:IsA("BasePart")) and (root.Size.Y / 2 + 0.5) or 2
    local spawnHeightOffset = (type(spawnCfg.SpawnHeightOffset) == "number") and spawnCfg.SpawnHeightOffset or 0
    local spawnPos = entry.portal.Position - Vector3.new(0, entry.portal.Size.Y / 2 + rootHalfY - spawnHeightOffset, 0)

    pcall(function()
        if not mob.PrimaryPart and root then
            mob.PrimaryPart = root
        end
        if mob.PrimaryPart then
            mob:SetPrimaryPartCFrame(CFrame.new(spawnPos))
        elseif root then
            root.CFrame = CFrame.new(spawnPos)
        end
    end)

    mob:SetAttribute("IsSpawnedMob", true)
    mob:SetAttribute("SpawnPortalGroup", entry.groupName)
    mob:SetAttribute("TemplateName", tpl.Name)

    CollectionService:AddTag(mob, mobTag)
    setModelCollisionGroup(mob, MOB_COLLISION_GROUP)
    applyMobPartCollisionOverrides(mob)
    applyOrcAxeCollisionFix(mob)

    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[MobSpawner] Template '" .. tpl.Name .. "' has no Humanoid")
        return mob
    end

    MobCombat.StartMob(mob, mobCfg, {
        zombieKillEvent = zombieKillEvent,
        mobTag = mobTag,
        defaultWalkAnimId = DEFAULT_WALK_ANIM_ID,
        getRootPart = getRootPart,
        spawnPos = spawnPos,
        areaPart = entry.area,
        mobCollisionGroup = MOB_COLLISION_GROUP,
    })

    return mob
end

---------------------------------------------------------------------------
-- Main spawn loop
---------------------------------------------------------------------------
task.spawn(function()
    while true do
        if isMatchActive() then
            local portals = findPortals()
            local aliveTotal = countAliveMobs()

            if #templates > 0 and #portals > 0 and #weightedPool > 0 then
                for _ = 1, SPAWN_BATCH do
                    if aliveTotal >= MAX_TOTAL then
                        break
                    end

                    local candidatePortals = {}
                    for _, entry in ipairs(portals) do
                        if countAliveInPortalGroup(entry.groupName) < MAX_PER_PORTAL then
                            table.insert(candidatePortals, entry)
                        end
                    end

                    if #candidatePortals == 0 then
                        break
                    end

                    local entry = candidatePortals[math.random(1, #candidatePortals)]
                    local chosen = pickWeightedTemplate()
                    if not chosen then
                        warn("[MobSpawner] No enabled templates in weighted pool; skipping spawn")
                        break
                    end

                    local mob = spawnMobFromTemplate(entry, chosen)
                    if mob then
                        aliveTotal = aliveTotal + 1
                    end
                end
            end
        end

        task.wait(SPAWN_INTERVAL)
    end
end)

print("[MobSpawner] started")
