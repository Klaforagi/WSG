local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

-- Minimal server-side recoil: nudge the character's right arm up then back down
local function playServerRecoil(player)
    if not player or not player.Character then return end
    local char = player.Character
    -- find a sensible shoulder Motor6D (R6 or R15)
    local motor = nil
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("Motor6D") then
            local lname = tostring(v.Name):lower()
            if lname:find("right") and lname:find("shoulder") then
                motor = v
                break
            end
        end
    end
    -- fallback: look for Motor6D whose Part1 name matches common right-arm names
    if not motor then
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("Motor6D") and v.Part1 and v.Part1.Name then
                local p1n = tostring(v.Part1.Name):lower()
                if p1n == "rightupperarm" or p1n == "right arm" or p1n == "righthand" then
                    motor = v
                    break
                end
            end
        end
    end
    if not motor then return end

    local ok, orig = pcall(function() return motor.C1 end)
    if not ok or not orig then return end

    local raiseAngle = math.rad(-8)
    local raised = orig * CFrame.Angles(raiseAngle, 0, 0)

    local suc, _ = pcall(function()
        local upTween = TweenService:Create(motor, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {C1 = raised})
        local downTween = TweenService:Create(motor, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {C1 = orig})
        upTween:Play()
        upTween.Completed:Connect(function()
            if downTween then downTween:Play() end
        end)
    end)
    if not suc then
        pcall(function() motor.C1 = orig end)
    end
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
        local isInvisWall = false
        if inst and inst.FindFirstAncestorWhichIsA then
            acc = inst:FindFirstAncestorWhichIsA("Accessory")
        end
        if inst and inst:IsA("BasePart") and tostring(inst.Name) == "InvisWall" then
            isInvisWall = true
        end
        if acc or isInvisWall then
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
    local leaveProjectile = (projCfg and (projCfg.LeaveProjectile == true or projCfg.leaveProjectile == true))
    local stickLifetime = (projCfg and (projCfg.projectile_stick_lifetime or projCfg.stick_lifetime)) or 2
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

    -- Try to obtain a preset projectile (Part or Model) from Toolgunsettings
    local visual = nil
    local usingModel = false
    if ToolgunModule and ToolgunModule.getProjectileForPreset then
        -- derive preset key from toolName (ToolBow -> bow)
        local presetKey = nil
        if toolName then
            local s = tostring(toolName):match("^Tool(.+)")
            if s then presetKey = s:lower() end
        end
        if presetKey then
            local ok, proj = pcall(function() return ToolgunModule.getProjectileForPreset(presetKey) end)
            if ok and proj then
                visual = proj
            end
        end
    end

    -- Fallback to simple part if no template provided
    if not visual then
        visual = Instance.new("Part")
        visual.Name = "Bullet"
        visual.Size = pSize
        visual.Material = Enum.Material.Neon
        visual.Color = getTracerColor(player)
        -- keep same behavior as previous implementation
        visual.CanCollide = false
        visual.Anchored = true
        visual.CFrame = CFrame.new(origin)
        visual.Parent = Workspace
    else
        -- If the template is a Model, prepare it for script-driven movement
        if visual:IsA("Model") then
            usingModel = true
            -- ensure model has a PrimaryPart; pick first BasePart if not
            local primary = visual.PrimaryPart
            if not primary then
                for _, d in ipairs(visual:GetDescendants()) do
                    if d:IsA("BasePart") then
                        primary = d
                        break
                    end
                end
                if primary then visual.PrimaryPart = primary end
            end
            -- make all parts non-collidable and anchored so we can move the model via CFrame
            for _, d in ipairs(visual:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = false
                    d.Anchored = true
                end
            end
            visual:SetPrimaryPartCFrame(CFrame.new(origin))
            visual.Parent = Workspace
        elseif visual:IsA("BasePart") then
            visual.CanCollide = false
            visual.Anchored = true
            visual.CFrame = CFrame.new(origin)
            visual.Parent = Workspace
        else
            -- unknown type: fallback to simple part
            local part = Instance.new("Part")
            part.Name = "Bullet"
            part.Size = pSize
            part.Material = Enum.Material.Neon
            part.Color = getTracerColor(player)
            part.CanCollide = false
            part.Anchored = true
            part.CFrame = CFrame.new(origin)
            part.Parent = Workspace
            visual = part
        end
    end

    local lastPos = origin
    local velocity = initialVelocity
    local startTime = tick()
    local conn
    local lastCFrame = CFrame.new(origin, origin + initialVelocity.Unit)
    conn = RunService.Heartbeat:Connect(function(dt)
        if not visual.Parent then
            conn:Disconnect()
            return
        end
        -- apply gravity/bullet drop to vertical component of velocity
        velocity = velocity + Vector3.new(0, -pDrop * dt, 0)
        local nextPos = lastPos + velocity * dt
        local rayResult = raycastSkippingAccessories(lastPos, (nextPos - lastPos), params)
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
            -- Impact handling: stop simulation, anchor + orient the visual at hit, play impact sound, then destroy after delay
            local hitPos = rayResult.Position
            local hitNormal = rayResult.Normal or Vector3.new(0, 1, 0)

            -- stop the heartbeat simulation
            if conn then
                conn:Disconnect()
                conn = nil
            end

            -- If this projectile should NOT be left in the world, destroy it immediately and return
            if not leaveProjectile then
                if visual and visual.Parent then
                    pcall(function() visual:Destroy() end)
                end
                return
            end

            -- Determine rotation to keep from last frame
            local rot = nil
            if lastCFrame then
                rot = lastCFrame - lastCFrame.Position
            end

            -- Helper: set safe physics flags on a BasePart
            -- `anchor` controls whether to Anchor (true) or leave unanchored for welding (false)
            local function safePartFlags(part, anchor)
                part.Anchored = (anchor == true)
                part.CanCollide = false
                pcall(function() part.CanTouch = false end)
                pcall(function() part.CanQuery = false end)
            end

            -- Try to find an Attachment named 'Tip' to align precisely
            local function findTipAttachment(obj, primary)
                if not obj then return nil end
                -- Prefer Attachment named 'Tip' under the PrimaryPart
                if primary and primary:IsA("BasePart") then
                    local a = primary:FindFirstChild("Tip")
                    if a and a:IsA("Attachment") then return a end
                end
                -- Otherwise search descendants for Attachment named 'Tip'
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("Attachment") and d.Name == "Tip" then
                        return d
                    end
                end
                return nil
            end

            -- Finalize projectile placement: keep rotation, align Tip to hitPos,
            -- weld to hit BasePart (to follow moving objects) or anchor in world space.
            if usingModel and visual:IsA("Model") then
                -- ensure PrimaryPart exists
                local primary = visual.PrimaryPart
                if not primary then
                    for _, d in ipairs(visual:GetDescendants()) do
                        if d:IsA("BasePart") then
                            primary = d
                            visual.PrimaryPart = primary
                            break
                        end
                    end
                end
                if primary then
                    -- determine the BasePart we struck
                    local hitInstance = rayResult.Instance
                    local hitPart = nil
                    if hitInstance and hitInstance:IsA("BasePart") and not hitInstance:IsA("Terrain") then
                        hitPart = hitInstance
                    end

                    -- Compute tipOffset: the Tip Attachment's CFrame relative to PrimaryPart.
                    -- Works even when the Tip lives on a non-primary descendant part.
                    local tip = findTipAttachment(visual, primary)
                    local tipOffset = nil
                    if tip then
                        if tip.Parent == primary then
                            tipOffset = tip.CFrame
                        else
                            -- tip is on another part; bridge via world CFrames
                            local tipWorld = tip.Parent.CFrame * tip.CFrame
                            tipOffset = primary.CFrame:Inverse() * tipWorld
                        end
                    end

                    -- Position model so Tip.WorldPosition == hitPos, rotation == rot
                    if tipOffset and rot then
                        local newPrimary = CFrame.new(hitPos) * rot * tipOffset:Inverse()
                        visual:SetPrimaryPartCFrame(newPrimary)
                    elseif tipOffset then
                        local newPrimary = CFrame.new(hitPos) * tipOffset:Inverse()
                        visual:SetPrimaryPartCFrame(newPrimary)
                    else
                        if rot then
                            visual:SetPrimaryPartCFrame(CFrame.new(hitPos) * rot)
                        else
                            visual:SetPrimaryPartCFrame(CFrame.new(hitPos))
                        end
                    end

                    -- Weld to hitPart (moves with it) or anchor in world space
                    if hitPart then
                        -- Determine if the hit part belongs to a character Model with a Humanoid
                        local char = hitPart:FindFirstAncestorOfClass("Model")
                        local hum = char and char:FindFirstChildOfClass("Humanoid")

                        -- Attach the projectile to the hit part by following its CFrame every Heartbeat.
                        -- This avoids adding the projectile to the character's physics assembly.
                        local targetPart = hitPart.AssemblyRootPart or hitPart

                        -- Ensure projectile is parented to Workspace (or Projectiles folder)
                        local projFolder = Workspace:FindFirstChild("Projectiles")
                        if not projFolder then
                            projFolder = Instance.new("Folder")
                            projFolder.Name = "Projectiles"
                            projFolder.Parent = Workspace
                        end
                        if visual.Parent ~= projFolder then
                            visual.Parent = projFolder
                        end

                        -- Compute relative offset from the hitPart to the projectile
                        local rel
                        if usingModel and visual.PrimaryPart then
                            rel = targetPart.CFrame:ToObjectSpace(visual.PrimaryPart.CFrame)
                            -- Anchor model primary part so it won't be added to the physics assembly
                            for _, part in ipairs(visual:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.Anchored = true
                                end
                            end
                        else
                            rel = targetPart.CFrame:ToObjectSpace(visual.CFrame)
                            visual.Anchored = true
                        end

                        visual.Massless = true
                        visual.CanCollide = false
                        pcall(function() visual.CanTouch = false end)
                        pcall(function() visual.CanQuery = false end)

                        local followConn
                        followConn = RunService.Heartbeat:Connect(function()
                            if not visual or not visual.Parent or not targetPart or not targetPart.Parent then
                                if followConn then
                                    followConn:Disconnect()
                                    followConn = nil
                                end
                                if visual and visual.Parent then
                                    pcall(function() visual:Destroy() end)
                                end
                                return
                            end

                            if usingModel and visual.PrimaryPart then
                                visual:SetPrimaryPartCFrame(targetPart.CFrame * rel)
                            else
                                visual.CFrame = targetPart.CFrame * rel
                            end
                        end)

                        -- Single destroy timer for this arrow
                            task.spawn(function()
                                task.wait(stickLifetime)
                                if followConn then
                                    followConn:Disconnect()
                                    followConn = nil
                                end
                                if visual and visual.Parent then
                                    pcall(function() visual:Destroy() end)
                                end
                            end)
                    else
                        -- Fallback to anchoring in world space
                        for _, d in ipairs(visual:GetDescendants()) do
                            if d:IsA("BasePart") then
                                d.Anchored = true
                            end
                        end
                    end

                    -- (destroy handled by impact branch above)
                end
            elseif visual and visual:IsA("BasePart") then
                -- determine the BasePart we struck
                local hitInstance = rayResult.Instance
                local hitPart = nil
                if hitInstance and hitInstance:IsA("BasePart") and not hitInstance:IsA("Terrain") then
                    hitPart = hitInstance
                end

                if hitPart then
                    -- Determine if the hit part belongs to a character Model with a Humanoid
                    local char = hitPart:FindFirstAncestorOfClass("Model")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")

                    -- Attach the projectile to the hit part by following its CFrame every Heartbeat.
                    local targetPart = hitPart.AssemblyRootPart or hitPart

                    -- Ensure projectile is parented to Workspace.Projectiles
                    local projFolder = Workspace:FindFirstChild("Projectiles")
                    if not projFolder then
                        projFolder = Instance.new("Folder")
                        projFolder.Name = "Projectiles"
                        projFolder.Parent = Workspace
                    end
                    if visual.Parent ~= projFolder then
                        visual.Parent = projFolder
                    end

                    -- Compute relative offset from hit part to arrow
                    local rel = targetPart.CFrame:ToObjectSpace(visual.CFrame)

                    -- Anchor the arrow so it is kept out of the target's physics assembly
                    visual.Anchored = true
                    visual.Massless = true
                    visual.CanCollide = false
                    pcall(function() visual.CanTouch = false end)
                    pcall(function() visual.CanQuery = false end)

                    local followConn
                    followConn = RunService.Heartbeat:Connect(function()
                        if not visual or not visual.Parent or not targetPart or not targetPart.Parent then
                            if followConn then
                                followConn:Disconnect()
                                followConn = nil
                            end
                            if visual and visual.Parent then
                                pcall(function() visual:Destroy() end)
                            end
                            return
                        end
                        visual.CFrame = targetPart.CFrame * rel
                    end)

                    -- Single destroy timer for this arrow
                        task.spawn(function()
                            task.wait(stickLifetime)
                            if followConn then
                                followConn:Disconnect()
                                followConn = nil
                            end
                            if visual and visual.Parent then
                                pcall(function() visual:Destroy() end)
                            end
                        end)
                end
            end

            -- play projectile land sound at the impact position on server (only if projectile is left)
            if leaveProjectile then
                pcall(function()
                    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
                    if soundsFolder then
                        local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
                        if toolgunFolder then
                            local template = toolgunFolder:FindFirstChild("Projectile_land")
                            if template and template:IsA("Sound") and hitPos then
                                -- create a tiny invisible host part at hitPos so the sound is 3D
                                local host = Instance.new("Part")
                                host.Name = "_ProjectileSound"
                                host.Size = Vector3.new(0.2, 0.2, 0.2)
                                host.Transparency = 1
                                host.Anchored = true
                                host.CanCollide = false
                                pcall(function() host.CanTouch = false end)
                                pcall(function() host.CanQuery = false end)
                                host.CFrame = CFrame.new(hitPos)
                                host.Parent = Workspace

                                local s = template:Clone()
                                s.Parent = host
                                s:Play()
                                game:GetService("Debris"):AddItem(host, 4)
                            end
                        end
                    end
                end)
            end

            -- (destroy handled by impact branch above)

            return
        end

        if usingModel and visual:IsA("Model") and visual.PrimaryPart then
            if lastCFrame then
                local rot = lastCFrame - lastCFrame.Position
                visual:SetPrimaryPartCFrame(CFrame.new(nextPos) * rot)
            else
                visual:SetPrimaryPartCFrame(CFrame.new(nextPos, nextPos + velocity.Unit))
            end
            lastCFrame = visual.PrimaryPart and visual.PrimaryPart.CFrame or lastCFrame
        elseif visual and visual:IsA("BasePart") then
            if lastCFrame then
                local rot = lastCFrame - lastCFrame.Position
                visual.CFrame = CFrame.new(nextPos) * rot
            else
                visual.CFrame = CFrame.new(nextPos, nextPos + velocity.Unit)
            end
            lastCFrame = visual.CFrame
        end
        lastPos = nextPos

        if (lastPos - origin).Magnitude > pRange or tick() - startTime > pLifetime then
                if visual and visual.Parent then
                    visual:Destroy()
                end
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
    local tBULLETSPEED = tCfg.bulletspeed or PROJECTILE_SPEED

    -- Compute an aim point on the camera ray (server-side) so projectiles from the muzzle converge on the crosshair
    local camHit = raycastSkippingAccessories(camOrigin, rayDir * tRANGE, params)
    local aimPoint
    if camHit and camHit.Instance and camHit.Position then
        aimPoint = camHit.Position
    else
        aimPoint = camOrigin + rayDir * tRANGE
    end

    -- Aim direction from muzzle to the aimPoint (fixes parallax)
    local aimDir = (aimPoint - gunOrigin)
    if aimDir.Magnitude <= 0.001 then
        aimDir = hrp.CFrame.LookVector
    else
        aimDir = aimDir.Unit
    end

    -- muzzle obstruction check along the computed aimDir from gunOrigin
    local gunObstruction = raycastSkippingAccessories(gunOrigin, aimDir * tRANGE, params)
    if gunObstruction and gunObstruction.Instance then
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
        pcall(function()
            if fireAck then
                fireAck:FireClient(player, gunOrigin, gunObstruction.Position, toolName)
            end
        end)
    end

    -- Spawn projectile along aimDir; ballistic simulation + raycasts will determine actual impacts
    local initVel = aimDir * tBULLETSPEED
    spawnProjectile(player, gunOrigin, initVel, tCfg, toolName)

    -- play a minimal server-side recoil animation on the shooter's right arm
    spawn(function()
        pcall(function() playServerRecoil(player) end)
    end)

    -- notify client with aimed position so client can spawn a local tracer
    pcall(function()
        if fireAck then
            fireAck:FireClient(player, gunOrigin, aimPoint, toolName)
        end
    end)
end)

-- clean up rate-limit table when players leave
Players.PlayerRemoving:Connect(function(player)
    lastFire[player] = nil
end)
