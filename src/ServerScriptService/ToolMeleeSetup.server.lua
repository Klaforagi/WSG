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
local TweenService       = game:GetService("TweenService")

-- XP integration
local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

-- CurrencyService: award coins on mob kills
local CurrencyService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

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
            -- determine coin award for this kill and award it before firing the feed
            local coinAward = 0
            if not vp and CurrencyService and CurrencyService.AddCoins then
                pcall(function() CurrencyService:AddCoins(player, 1) end)
                coinAward = 1
            end

            pcall(function() KillFeedEvent:FireAllClients(player.Name, victimName, coinAward) end)
            if player.Team then
                pcall(function() AddScore:Fire(player.Team.Name, KILL_POINTS) end)
            end
            -- Award XP
            if XPModule and XPModule.AwardXP then
                if vp then
                    pcall(function() XPModule.AwardXP(player, "PlayerKill") end)
                else
                    local mobName = victimModel and victimModel.Name or "Unknown"
                    local mobXP = 3
                    pcall(function()
                        if XPModule.GetMobXP then mobXP = XPModule.GetMobXP(mobName) end
                    end)
                    pcall(function() XPModule.AwardXP(player, "MobKill", mobXP) end)
                end
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
-- Box overlap hit detection: find targets whose root is inside an oriented box
-- `boxCFrame` is the world CFrame of the box center; `halfSize` is half extents Vector3
---------------------------------------------------------------------------
local function getTargetsInBox(playerChar, boxCFrame, halfSize)
    local results = {}
    local seenHum = {}

    -- Use GetPartBoundsInBox to detect any parts inside the oriented box.
    local parts = Workspace:GetPartBoundsInBox(boxCFrame, halfSize * 2)
    if parts and #parts > 0 then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { playerChar }
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        for _, part in ipairs(parts) do
            if not part or not part:IsA("BasePart") then continue end
            -- find ancestor model that has a Humanoid
            local model = part:FindFirstAncestorOfClass("Model")
            if not model then continue end
            if model == playerChar then continue end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            if seenHum[hum] then continue end

            -- ensure there's line-of-sight to the hit part (box center → part)
            local dir = part.Position - boxCFrame.Position
            if dir.Magnitude <= 0.001 then
                -- extremely close, accept hit
                local dist = (part.Position - boxCFrame.Position).Magnitude
                table.insert(results, { humanoid = hum, model = model, hitPart = part, hitPos = part.Position, dist = dist })
                seenHum[hum] = true
            else
                local ray = Workspace:Raycast(boxCFrame.Position, dir, params)
                if ray and ray.Instance and (ray.Instance:IsDescendantOf(model) or ray.Instance == part) then
                    local dist = (part.Position - boxCFrame.Position).Magnitude
                    table.insert(results, { humanoid = hum, model = model, hitPart = ray.Instance, hitPos = ray.Position, dist = dist })
                    seenHum[hum] = true
                end
            end
        end
    end

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
    local knockback = cfg.knockback or 0

    -- rate limit (small tolerance so network jitter doesn't silently drop held swings)
    -- Snaps lastSwing to the cadence beat (last + cd) rather than wall-clock
    -- receipt time, preventing cumulative drift at any cooldown value.
    local now = tick()
    if not lastSwing[player] then lastSwing[player] = {} end
    local last = lastSwing[player][toolName] or 0
    if now - last < cd * 0.85 then return end
    -- snap to expected cadence beat; reset fresh if player hasn't swung recently
    if last > 0 and (now - last) < cd * 1.5 then
        lastSwing[player][toolName] = last + cd
    else
        lastSwing[player][toolName] = now
    end

    -- use the server-side look direction (from HRP) for safety, blended with the client's
    -- to prevent spoofing while still feeling responsive
    local serverLook = hrp.CFrame.LookVector
    local blended = (serverLook + lookDir.Unit).Unit
    if blended.Magnitude < 0.001 then blended = serverLook end

    -- server-side audiovisuals: play swing sound and server animation from the character
    do
        -- play swing sound at HRP
        local swingSoundKey = cfg.swing_sound
        if swingSoundKey and swingSoundKey ~= "" then
            pcall(function()
                local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
                if soundsFolder then
                    local meleeFolder = soundsFolder:FindFirstChild("ToolMelee")
                    if meleeFolder then
                        local template = meleeFolder:FindFirstChild(swingSoundKey)
                        if template and template:IsA("Sound") then
                            local s = template:Clone()
                            s.Parent = hrp
                            s:Play()
                            Debris:AddItem(s, 3)
                        end
                    end
                end
            end)
        end

        -- play swing animation on the server humanoid
        -- 1) try a custom Animation inside the tool
        local animObj = nil
        if tool then
            for _, d in ipairs(tool:GetDescendants()) do
                if d:IsA("Animation") and tostring(d.Name):lower():find("swing") then
                    animObj = d
                    break
                end
            end
        end
        if not animObj and cfg.swing_anim_id and cfg.swing_anim_id ~= "" then
            local a = Instance.new("Animation")
            a.AnimationId = cfg.swing_anim_id
            animObj = a
        end
        if animObj then
            pcall(function()
                local animator = hum:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator")
                    animator.Parent = hum
                end
                local track = animator:LoadAnimation(animObj)
                track.Priority = Enum.AnimationPriority.Action
                track:Play()
                task.delay(2, function()
                    pcall(function() track:Stop() end)
                    if animObj and animObj:IsA("Animation") and animObj.Parent == nil then
                        pcall(function() animObj:Destroy() end)
                    end
                end)
            end)
        else
            -- 2) procedural swing: tween Motor6D on the right arm (replicates to all clients)
            pcall(function()
                local char = player.Character
                if not char then return end
                local motor = nil
                local torso = char:FindFirstChild("Torso")
                if torso then motor = torso:FindFirstChild("Right Shoulder") end
                if not motor then
                    local rua = char:FindFirstChild("RightUpperArm")
                    if rua then motor = rua:FindFirstChild("RightShoulder") end
                end
                if not motor or not motor:IsA("Motor6D") then return end

                local originalC1 = motor.C1
                local raiseGoal = originalC1 * CFrame.Angles(math.rad(-90), 0, 0)
                local slashGoal = originalC1 * CFrame.Angles(math.rad(90), 0, 0)

                local raiseTI  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local slashTI  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                local returnTI = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

                local raiseTween = TweenService:Create(motor, raiseTI, { C1 = raiseGoal })
                raiseTween:Play()
                raiseTween.Completed:Once(function()
                    local slashTween = TweenService:Create(motor, slashTI, { C1 = slashGoal })
                    slashTween:Play()
                    slashTween.Completed:Once(function()
                        local returnTween = TweenService:Create(motor, returnTI, { C1 = originalC1 })
                        returnTween:Play()
                    end)
                end)
            end)
        end
    end

    -- delayed/persistent hitbox: wait `hitboxDelay`, then for `hitboxActive` seconds
    -- repeatedly check the cone and apply damage once per target per swing.
    local hitboxDelay = cfg.hitboxDelay or 0.1
    local hitboxActive = cfg.hitboxActive or 0.2
    task.spawn(function()
        task.wait(hitboxDelay)
        local hitAlready = {}
        local endTime = tick() + hitboxActive
        while tick() < endTime and player and player.Character and hum and hum.Health > 0 do
            local curHrp = player.Character:FindFirstChild("HumanoidRootPart")
            if not curHrp then break end
            -- compute oriented box CFrame and half extents
            local boxSize = cfg.hitboxSize or Vector3.new(4, 3, 7)
            local offset = cfg.hitboxOffset or Vector3.new(0, 1, boxSize.Z * 0.5)
            -- compute world position using HRP local axes so +Z in offset means "in front"
            local pos = curHrp.Position
                + curHrp.CFrame.RightVector * offset.X
                + curHrp.CFrame.UpVector * offset.Y
                + curHrp.CFrame.LookVector * offset.Z
            local boxCFrame = CFrame.new(pos, pos + curHrp.CFrame.LookVector)
            local halfSize = boxSize / 2
            local targetsNow = getTargetsInBox(player.Character, boxCFrame, halfSize)
            for _, hit in ipairs(targetsNow) do
                if not hitAlready[hit.humanoid] then
                    hitAlready[hit.humanoid] = true
                    -- apply damage
                    applyMeleeDamage(player, hit.humanoid, hit.model, damage, hit.hitPart, hit.hitPos)
                    -- hit sound at attacker
                    local hitSoundKey = cfg.hit_sound
                    if hitSoundKey and hitSoundKey ~= "" then
                        local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
                        if soundsFolder then
                            local meleeFolder = soundsFolder:FindFirstChild("ToolMelee")
                            if meleeFolder then
                                local template = meleeFolder:FindFirstChild(hitSoundKey)
                                if template and template:IsA("Sound") then
                                    local s = template:Clone()
                                    s.Parent = curHrp
                                    s:Play()
                                    Debris:AddItem(s, 3)
                                end
                            end
                        end
                    end
                    -- knockback
                    -- knockback (skip for same-team players)
                    if knockback > 0 then
                        local victimRoot = hit.model:FindFirstChild("HumanoidRootPart")
                            or hit.model:FindFirstChild("Torso")
                        if victimRoot then
                            local vp = Players:GetPlayerFromCharacter(hit.model)
                            local isSameTeam = vp and player and player.Team and vp.Team and player.Team == vp.Team
                            if not isSameTeam then
                                local dir = (victimRoot.Position - boxCFrame.Position)
                                if dir.Magnitude < 0.01 then dir = boxCFrame.LookVector end
                                applyKnockback(victimRoot, dir, knockback)
                            end
                        end
                    end
                end
            end
            task.wait(0.06)
        end
    end)
end)

-- clean up on leave
Players.PlayerRemoving:Connect(function(player)
    lastSwing[player] = nil
end)

print("[ToolMeleeSetup] server ready")
