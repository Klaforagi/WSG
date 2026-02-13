--------------------------------------------------------------------------------
-- ToolMeleeSetup.server.lua  –  server-side melee weapon handler
-- Mirrors ToolGunSetup.server.lua: creates RemoteEvents, validates incoming
-- swing requests, performs a short-range cone/sphere check, applies damage,
-- handles kill feed and score.
--------------------------------------------------------------------------------
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")
local Workspace          = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris             = game:GetService("Debris")
local CollectionService  = game:GetService("CollectionService")

-- Melee settings module
local MeleeCfg
if ReplicatedStorage:FindFirstChild("ToolMeleeSettings") then
    MeleeCfg = require(ReplicatedStorage:WaitForChild("ToolMeleeSettings"))
end

---------------------------------------------------------------------------
-- Remote events
---------------------------------------------------------------------------
local function ensureEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end

local swingEvent  = ensureEvent("MeleeSwing")   -- client → server
local meleeHit    = ensureEvent("MeleeHit")      -- server → client (damage popup)
local KillFeedEvent = ensureEvent("KillFeed")
local HeadshotEvent = ensureEvent("Headshot")

-- Score bindable (shared with ToolGunSetup / GameManager)
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

local KILL_POINTS = 10

---------------------------------------------------------------------------
-- Resolve per-tool config from presets
---------------------------------------------------------------------------
local function getServerMeleeCfg(toolName)
    local cfg = {}
    if MeleeCfg and MeleeCfg.presets then
        local suffix = toolName and tostring(toolName):match("^Tool(.+)")
        local key = suffix and suffix:lower()
        if key and MeleeCfg.presets[key] then
            for k, v in pairs(MeleeCfg.presets[key]) do cfg[k] = v end
        end
    end
    return cfg
end

---------------------------------------------------------------------------
-- Damage helper (same tag pattern as the gun system so KillTracker works)
---------------------------------------------------------------------------
local function applyMeleeDamage(player, humanoid, victimModel, damage, hitPart, hitPos)
    pcall(function()
        humanoid:SetAttribute("lastDamagerUserId", player.UserId)
        humanoid:SetAttribute("lastDamagerName", player.Name)
        humanoid:SetAttribute("lastDamageTime", tick())
    end)
    humanoid:TakeDamage(damage)
    -- send hit feedback to the attacker
    pcall(function()
        meleeHit:FireClient(player, damage, false, hitPart, hitPos)
    end)
    if humanoid.Health <= 0 then
        humanoid:SetAttribute("_killCredited", true)
        local victimName = (victimModel and victimModel.Name) or "Unknown"
        local vp = Players:GetPlayerFromCharacter(victimModel)
        if vp then victimName = vp.Name end
        if player.Name ~= victimName then
            pcall(function() KillFeedEvent:FireAllClients(player.Name, victimName) end)
            if player.Team then
                pcall(function() AddScore:Fire(player.Team.Name, KILL_POINTS) end)
            end
        end
        -- ragdoll dummies on melee kill
        if victimModel and victimModel:IsA("Model") and victimModel.Name == "Dummy" then
            pcall(function() humanoid:SetAttribute("_dummyRagdolled", true) end)
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)
            for _, desc in ipairs(victimModel:GetDescendants()) do
                if desc:IsA("BasePart") then desc.Anchored = false; desc.CanCollide = true end
            end
            task.wait(0.05)
            pcall(function() victimModel:BreakJoints() end)
            task.delay(5, function()
                if victimModel and victimModel.Parent then pcall(function() victimModel:Destroy() end) end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Headshot detection (reused from ToolGunSetup logic)
---------------------------------------------------------------------------
local function checkHeadshot(inst, victimModel, hitPos)
    local headPart = victimModel:FindFirstChild("Head")
    if not headPart then return false end
    if inst == headPart then return true end
    if inst.Name and tostring(inst.Name):lower():find("head") then return true end
    if inst:IsDescendantOf(headPart) then return true end
    if inst:FindFirstAncestorWhichIsA("Accessory") then
        local acc = inst:FindFirstAncestorWhichIsA("Accessory")
        local handle = acc:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") and (handle.Position - headPart.Position).Magnitude <= 3 then
            return true
        end
    end
    if hitPos and (hitPos - headPart.Position).Magnitude <= 2 then return true end
    return false
end

---------------------------------------------------------------------------
-- Knockback helper
---------------------------------------------------------------------------
local function applyKnockback(victimRoot, direction, force)
    if not victimRoot or not victimRoot:IsA("BasePart") then return end
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity = direction.Unit * force + Vector3.new(0, force * 0.3, 0) -- slight upward pop
    bv.Parent = victimRoot
    Debris:AddItem(bv, 0.2)
end

---------------------------------------------------------------------------
-- Cone hit detection: find all damageable targets in a cone in front of
-- the player.  Returns array of {humanoid, model, hitPart, hitPos, dist}.
---------------------------------------------------------------------------
local function getTargetsInCone(playerChar, origin, lookDir, range, arcDeg)
    local results = {}
    local halfArc = math.rad(arcDeg / 2)
    local lookFlat = Vector3.new(lookDir.X, 0, lookDir.Z)
    if lookFlat.Magnitude < 0.001 then lookFlat = Vector3.new(0, 0, -1) end
    lookFlat = lookFlat.Unit

    -- gather candidate models: players + dummies + zombies
    local candidates = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and p.Character ~= playerChar then
            table.insert(candidates, p.Character)
        end
    end
    -- dummies
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name == "Dummy" then
            table.insert(candidates, obj)
        end
    end
    -- zombies
    for _, z in ipairs(CollectionService:GetTagged("ZombieNPC")) do
        if z:IsA("Model") then table.insert(candidates, z) end
    end

    for _, model in ipairs(candidates) do
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local root = model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChildWhichIsA("BasePart")
        if not root then continue end

        local toTarget = root.Position - origin
        local dist = toTarget.Magnitude
        if dist > range then continue end

        -- angle check (flatten to XZ)
        local toFlat = Vector3.new(toTarget.X, 0, toTarget.Z)
        if toFlat.Magnitude < 0.001 then
            -- basically on top of us – always hits
            table.insert(results, { humanoid = hum, model = model, hitPart = root, hitPos = root.Position, dist = dist })
            continue
        end
        toFlat = toFlat.Unit
        local angle = math.acos(math.clamp(lookFlat:Dot(toFlat), -1, 1))
        if angle <= halfArc then
            -- optional: quick raycast to make sure there's no wall between
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = { playerChar }
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            local ray = Workspace:Raycast(origin, (root.Position - origin), params)
            if ray and ray.Instance then
                -- did we hit something belonging to the target model?
                if ray.Instance:IsDescendantOf(model) or ray.Instance == root then
                    table.insert(results, {
                        humanoid = hum,
                        model    = model,
                        hitPart  = ray.Instance,
                        hitPos   = ray.Position,
                        dist     = dist,
                    })
                end
                -- else a wall is in the way – skip
            end
        end
    end

    -- sort by distance so closest gets hit first
    table.sort(results, function(a, b) return a.dist < b.dist end)
    return results
end

---------------------------------------------------------------------------
-- Rate limiting
---------------------------------------------------------------------------
local lastSwing = {} -- [player] = { [toolName] = tick() }

---------------------------------------------------------------------------
-- Handle incoming swing
---------------------------------------------------------------------------
swingEvent.OnServerEvent:Connect(function(player, toolName, lookDir)
    -- basic validation
    if type(toolName) ~= "string" then return end
    if typeof(lookDir) ~= "Vector3" then return end
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    -- verify the player actually has this tool equipped
    local tool = player.Character:FindFirstChild(toolName)
    if not tool or not tool:IsA("Tool") then return end

    -- resolve config
    local cfg = getServerMeleeCfg(toolName)
    local damage    = cfg.damage or 30
    local cd        = cfg.cd or 0.5
    local range     = cfg.range or 7
    local arc       = cfg.arc or 90
    local knockback = cfg.knockback or 0

    -- rate limit
    local now = tick()
    if not lastSwing[player] then lastSwing[player] = {} end
    local last = lastSwing[player][toolName] or 0
    if now - last < cd * 0.9 then return end -- 0.9 to be lenient with latency
    lastSwing[player][toolName] = now

    -- use the server-side look direction (from HRP) for safety, blended with the client's
    -- to prevent spoofing while still feeling responsive
    local serverLook = hrp.CFrame.LookVector
    local blended = (serverLook + lookDir.Unit).Unit
    if blended.Magnitude < 0.001 then blended = serverLook end

    -- find targets
    local origin = hrp.Position + Vector3.new(0, 0.5, 0) -- slightly above feet
    local targets = getTargetsInCone(player.Character, origin, blended, range, arc)

    -- play hit sound at the weapon for everyone nearby
    if #targets > 0 then
        local hitSoundKey = cfg.hit_sound
        if hitSoundKey and hitSoundKey ~= "" then
            local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
            if soundsFolder then
                local meleeFolder = soundsFolder:FindFirstChild("ToolMelee")
                if meleeFolder then
                    local template = meleeFolder:FindFirstChild(hitSoundKey)
                    if template and template:IsA("Sound") then
                        local s = template:Clone()
                        s.Parent = hrp
                        s:Play()
                        Debris:AddItem(s, 3)
                    end
                end
            end
        end
    end

    -- apply damage to all targets in the swing cone
    for _, hit in ipairs(targets) do
        applyMeleeDamage(player, hit.humanoid, hit.model, damage, hit.hitPart, hit.hitPos)

        -- knockback
        if knockback > 0 then
            local victimRoot = hit.model:FindFirstChild("HumanoidRootPart")
                or hit.model:FindFirstChild("Torso")
            if victimRoot then
                local dir = (victimRoot.Position - origin)
                if dir.Magnitude < 0.01 then dir = blended end
                applyKnockback(victimRoot, dir, knockback)
            end
        end
    end
end)

-- clean up on leave
Players.PlayerRemoving:Connect(function(player)
    lastSwing[player] = nil
end)

print("[ToolMeleeSetup] server ready")
