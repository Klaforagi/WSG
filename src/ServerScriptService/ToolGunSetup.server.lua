local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local FastCast = require(ReplicatedStorage:WaitForChild("Dependencies"):WaitForChild("FastCastRedux"))
local RangedCast = require(ReplicatedStorage:WaitForChild("RangedCast"))

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

-- Centralized stat/event tracking (single source of truth for quests/achievements/scoreboard)
local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

local WeaponMasteryService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponMasteryService")
    if mod and mod:IsA("ModuleScript") then
        WeaponMasteryService = require(mod)
    end
end)

local WeaponEnchantService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponEnchantService")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantService = require(mod)
    end
end)

local WeaponEnchantConfig
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("WeaponEnchantConfig")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantConfig = require(mod)
    end
end)

local PotionService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("HealthPotionService")
    if mod and mod:IsA("ModuleScript") then
        PotionService = require(mod)
    end
end)

-- Toolgun settings module (defaults + optional Studio overrides)
local ToolgunModule
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    ToolgunModule = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
end
local TOOLCFG = {}

-- Shared weapon switch lock (also used by ToolMeleeSetup)
local WeaponLockService = require(ServerScriptService:WaitForChild("WeaponLockService"))
local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))
local FULL_BODY_SKIN_MODEL_ATTRIBUTE = "_FullBodySkinModel"
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local RANGED_ATTACK_SPEED_MODIFIER_ID = "ranged_attack_slow"
local CombatUtils = require(ServerScriptService:WaitForChild("CombatUtils"))

local WeaponTrailService = nil
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponTrailService")
    if mod and mod:IsA("ModuleScript") then
        WeaponTrailService = require(mod)
    end
end)

local function shouldIgnoreHumanoidTarget(model, humanoid)
    if not humanoid then return true end
    if humanoid:GetAttribute("IgnoreCombatTargeting") then return true end
    if CombatUtils and CombatUtils.isPodiumAvatar(model) then return true end
    if model and (model:GetAttribute(FULL_BODY_SKIN_MODEL_ATTRIBUTE) or model.Name == "AppliedCharacterSkin") then
        return true
    end
    return false
end

-- Default: tracers are disabled unless a preset explicitly enables them
local SHOW_TRACER = false
local DEFAULT_TRACER_COLOR = Color3.fromRGB(255, 200, 100)

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

local PROJECTILE_VISUAL_EVENT_NAME = "ToolGunProjectileVisual"
local projectileVisualEvent = ReplicatedStorage:FindFirstChild(PROJECTILE_VISUAL_EVENT_NAME)
if not projectileVisualEvent then
    projectileVisualEvent = Instance.new("RemoteEvent")
    projectileVisualEvent.Name = PROJECTILE_VISUAL_EVENT_NAME
    projectileVisualEvent.Parent = ReplicatedStorage
end

-- Read-only copies let the firing client render the projectile immediately.
-- Collision and damage still use the separate server-authoritative projectile.
local clientProjectileVisuals = ReplicatedStorage:FindFirstChild("ClientProjectileVisuals")
if not clientProjectileVisuals then
    clientProjectileVisuals = Instance.new("Folder")
    clientProjectileVisuals.Name = "ClientProjectileVisuals"
    clientProjectileVisuals.Parent = ReplicatedStorage
end
local storedProjectiles = ServerStorage:FindFirstChild("Projectiles")
if storedProjectiles then
    for _, template in ipairs(storedProjectiles:GetChildren()) do
        if not clientProjectileVisuals:FindFirstChild(template.Name) then
            template:Clone().Parent = clientProjectileVisuals
        end
    end
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
    if ToolgunModule then
        local suffix = toolName and (tostring(toolName):match("^Tool(.+)") or tostring(toolName):match("^(.+)$"))
        local presetKey = suffix and suffix:lower()
        local preset = presetKey and (
            (ToolgunModule.getPreset and ToolgunModule.getPreset(presetKey))
            or (ToolgunModule.presets and ToolgunModule.presets[presetKey])
        )
        if preset then
            for k, v in pairs(preset) do cfg[k] = v end
        end
    end
    return cfg
end

-- Server-side handling + validation (projectile-based)
local lastFire = {} -- [player] = { [toolName] = tick() }

local function clearRangedFireSlow(player)
    pcall(function()
        HumanoidStatService:RemoveModifier(player, MOVEMENT_SPEED_STAT, RANGED_ATTACK_SPEED_MODIFIER_ID)
    end)
end

-- Base defaults when no preset supplies values
local DAMAGE = 25
local RANGE = 300
local COOLDOWN_SERVER = 0.5

-- Projectile settings defaults
local PROJECTILE_SPEED = 100 -- studs per second
local PROJECTILE_LIFETIME = 5 -- seconds
local PROJECTILE_SIZE = Vector3.new(0.2, 0.2, 0.2)
local BULLET_DROP = 9.8

---------------------------------------------------------------------------
-- RANGED SIZE SCALING HELPERS
-- Mirrors the melee scaling system in ToolMeleeSetup.
-- sizePercent is read from the equipped Tool's attributes set by WeaponScaleService.
---------------------------------------------------------------------------

local _rangedSizeWarnedTools = {}
local function getToolSizePercent(tool)
    if not tool then return 100 end
    local sp = tool:GetAttribute("SizePercent")
        or tool:GetAttribute("WeaponSizePercent")
        or tool:GetAttribute("ScalePercent")
        or tool:GetAttribute("WeaponScale")
    if type(sp) == "number" and sp > 0 then return sp end
    if not _rangedSizeWarnedTools[tool] then
        _rangedSizeWarnedTools[tool] = true
        warn("[RangedScaling] No size attribute on tool:", tool.Name, "defaulting to 100")
    end
    return 100
end

--- Damage: linear 1:1 with size. 150% = 1.5x, 80% = 0.8x.
local function getSizeDamageMultiplier(sizePercent)
    return math.clamp(sizePercent / 100, 0.5, 3.0)
end

--- Cooldown speed: same curve as melee.
--- 80%=0.8x, 100%=1.0x, 150%=1.25x, 200%=1.5x
local function getSizeSpeedMultiplier(sizePercent)
    if sizePercent <= 100 then
        return math.clamp(sizePercent / 100, 0.5, 1.0)
    end
    return math.clamp(1.0 + (sizePercent - 100) / 200, 1.0, 2.0)
end

--- Returns baseCooldown scaled by weapon size.
local function getScaledCooldown(baseCooldown, sizePercent)
    return baseCooldown * getSizeSpeedMultiplier(sizePercent)
end

--- Projectile visual scale factor = sizePercent / 100 (linear).
local function getProjectileVisualScale(sizePercent)
    return math.clamp(sizePercent / 100, 0.1, 5.0)
end

--- Scale a Vector3 by a uniform factor.
local function scaleVec3(v, factor)
    return Vector3.new(v.X * factor, v.Y * factor, v.Z * factor)
end

local function scaleCFrameTranslation(cf, factor)
    local rot = CFrame.new(cf.Position):Inverse() * cf
    return CFrame.new(cf.Position * factor) * rot
end

local function convertWeldConstraints(root)
    if not root or not root.GetDescendants then return end
    for _, wc in ipairs(root:GetDescendants()) do
        if wc and wc:IsA("WeldConstraint") then
            local p0 = wc.Part0
            local p1 = wc.Part1
            if p0 and p1 then
                local weld = Instance.new("Weld")
                weld.Name = wc.Name ~= "" and wc.Name or "Weld_from_WeldConstraint"
                weld.Part0 = p0
                weld.Part1 = p1
                local ok, c0 = pcall(function()
                    return p0.CFrame:ToObjectSpace(p1.CFrame)
                end)
                weld.C0 = (ok and c0) or CFrame.new()
                weld.C1 = CFrame.new()
                weld.Parent = p0
            end
            wc:Destroy()
        end
    end
end

local function applyProjectilePhysicsFlags(root)
    local function flagPart(part)
        part.CanCollide = false
        part.Anchored = true
        pcall(function() part.CanTouch = false end)
        pcall(function() part.CanQuery = false end)
        pcall(function() part.Massless = true end)
    end

    if root:IsA("BasePart") then
        flagPart(root)
    end
    if not root.GetDescendants then return end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            flagPart(descendant)
        end
    end
end

local function getVisualPrimary(visual)
    if not visual then return nil end
    if visual:IsA("BasePart") then
        return visual
    end
    if visual:IsA("Model") then
        local primary = visual.PrimaryPart
        if primary and primary:IsA("BasePart") then
            return primary
        end
        for _, descendant in ipairs(visual:GetDescendants()) do
            if descendant:IsA("BasePart") then
                visual.PrimaryPart = descendant
                return descendant
            end
        end
    end
    return nil
end

local function findNamedAttachment(root, name)
    if ToolgunModule and type(ToolgunModule.findNamedAttachment) == "function" then
        return ToolgunModule.findNamedAttachment(root, name)
    end
    if not root or type(name) ~= "string" then return nil end
    local direct = root:FindFirstChild(name)
    if direct and direct:IsA("Attachment") then
        return direct
    end
    if root.GetDescendants then
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("Attachment") and descendant.Name == name then
                return descendant
            end
        end
    end
    return nil
end

-- Tip POSITION in primary-part space. Rotation is ignored so a rotated Tip
-- attachment cannot swing the whole projectile off to the side of Fire.
local function getTipLocalPosition(visual, primary)
    local tip = findNamedAttachment(visual, "Tip")
    if not tip or not primary or not primary:IsA("BasePart") then
        return Vector3.zero
    end
    if tip.Parent == primary then
        return tip.Position
    end
    if tip.WorldPosition then
        return primary.CFrame:PointToObjectSpace(tip.WorldPosition)
    end
    return Vector3.zero
end

local function getVisualRotationCFrame(projCfg)
    local r = projCfg and (projCfg.visual_rotation or projCfg.visual_rotation_degrees)
    if typeof(r) == "Vector3" then
        return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
    end
    if type(r) == "table" then
        return CFrame.Angles(
            math.rad(tonumber(r[1] or r.X) or 0),
            math.rad(tonumber(r[2] or r.Y) or 0),
            math.rad(tonumber(r[3] or r.Z) or 0)
        )
    end
    return nil
end

-- Shared with client cosmetics so multipart arrows use the same shaft axis.
local getShaftLookCorrection = RangedCast.GetShaftLookCorrection

local function getLookCFrame(position, direction, visualFlip)
    if not direction or direction.Magnitude <= 0.001 then
        return CFrame.new(position)
    end
    if visualFlip then
        return CFrame.lookAt(position, position - direction.Unit)
    end
    return CFrame.lookAt(position, position + direction.Unit)
end

-- Place Tip at `position` and aim along `direction`. Optional extra rotation
-- is applied in look-space (visual_rotation degrees on the weapon preset).
local function getAlignedPrimaryCFrame(position, direction, visualFlip, tipLocalPos, extraRotation)
    local lookCFrame = getLookCFrame(position, direction, visualFlip)
    if extraRotation then
        lookCFrame = lookCFrame * extraRotation
    end
    local localPos = tipLocalPos or Vector3.zero
    return lookCFrame * CFrame.new(-localPos)
end

local function setVisualPrimaryCFrame(visual, usingModel, cf)
    local primary = nil
    if usingModel and visual and visual:IsA("Model") then
        primary = visual.PrimaryPart
    elseif visual and visual:IsA("BasePart") then
        primary = visual
    end
    if not primary or not primary:IsA("BasePart") then
        return
    end

    if visual:IsA("Model") then
        visual:PivotTo((cf * primary.CFrame:Inverse()) * visual:GetPivot())
    else
        visual.CFrame = cf
    end
end

--- Scale all BasePart sizes, attachment offsets, and weld translations
--- on a cloned projectile. Must be called BEFORE parenting / positioning.
local function scaleProjectileInstance(visual, factor)
    if not visual or math.abs(factor - 1.0) < 0.001 then return end
    convertWeldConstraints(visual)

    local function scaleDescendant(descendant)
        if descendant:IsA("BasePart") then
            pcall(function() descendant.Size = scaleVec3(descendant.Size, factor) end)
        elseif descendant:IsA("Attachment") then
            pcall(function() descendant.Position = descendant.Position * factor end)
        elseif descendant:IsA("Weld") or descendant:IsA("ManualWeld") or descendant:IsA("Motor6D") then
            pcall(function() descendant.C0 = scaleCFrameTranslation(descendant.C0, factor) end)
            pcall(function() descendant.C1 = scaleCFrameTranslation(descendant.C1, factor) end)
        elseif descendant:IsA("SpecialMesh") then
            pcall(function() descendant.Scale = descendant.Scale * factor end)
        end
    end

    if visual:IsA("BasePart") then
        pcall(function() visual.Size = scaleVec3(visual.Size, factor) end)
    end
    if visual.GetDescendants then
        for _, descendant in ipairs(visual:GetDescendants()) do
            scaleDescendant(descendant)
        end
    end

    local primary = getVisualPrimary(visual)
    if primary and visual.GetDescendants then
        for _, descendant in ipairs(visual:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant ~= primary then
                local rel = primary.CFrame:ToObjectSpace(descendant.CFrame)
                pcall(function()
                    descendant.CFrame = primary.CFrame * scaleCFrameTranslation(rel, factor)
                end)
            end
        end
    end
end

local function getToolDisplayName(toolName)
    if type(toolName) ~= "string" then return toolName end
    return toolName:match("^Tool(.+)") or toolName
end

local function applyEtherealProjectileColor(visual, toolName, enchantName)
    if not visual or type(enchantName) ~= "string" or enchantName == "" then
        return
    end

    local weaponName = getToolDisplayName(toolName)
    local isEthereal = type(weaponName) == "string" and string.find(string.lower(weaponName), "ethereal", 1, true) ~= nil
    if not isEthereal then
        return
    end

    local color = nil
    if WeaponEnchantConfig and type(WeaponEnchantConfig.GetEtherealPartColor) == "function" then
        color = WeaponEnchantConfig.GetEtherealPartColor(enchantName)
    end
    if not color then
        return
    end

    local function paint(part)
        if part and part:IsA("BasePart") and part.Name ~= "EnchantBlock" then
            pcall(function() part.Color = color end)
        end
    end

    paint(visual)
    if visual.GetDescendants then
        for _, descendant in ipairs(visual:GetDescendants()) do
            paint(descendant)
        end
    end
end

local function applyOutgoingDamageModifiers(player, damage, context)
    if PotionService and type(PotionService.ApplyOutgoingDamageModifiers) == "function" then
        local ok, modifiedDamage = pcall(function()
            return PotionService:ApplyOutgoingDamageModifiers(player, damage, context)
        end)
        if ok and type(modifiedDamage) == "number" then
            return modifiedDamage
        end
    end
    return damage
end

local shouldPierceProjectile = RangedCast.ShouldPierce
local function raycastSkippingAccessories(origin, direction, rayParams, attackerPlayer)
    return RangedCast.RaycastAim(Workspace, origin, direction, rayParams, attackerPlayer)
end

-- Same integer roll melee uses on attacks 1-2: ceil(base * 0.7) through ceil(base * 1.0).
local RANGED_DAMAGE_ROLL_MIN = 0.7
local RANGED_DAMAGE_ROLL_MAX = 1.0

local function rollUniformIntegerDamage(baseDamage, minRoll, maxRoll)
    local minDamage = math.ceil(baseDamage * minRoll)
    local maxDamage = math.ceil(baseDamage * maxRoll)
    if maxDamage < minDamage then
        maxDamage = minDamage
    end
    return math.random(minDamage, maxDamage)
end

-- Unified damage helper: tags humanoid, deals damage, fires hitmarker,
-- and fires kill credit immediately if the target dies.
local function applyDamage(player, humanoid, victimModel, damage, hitPart, hitPos, weaponInstanceId, weaponName, enchantName)
    -- Podium avatars are fully immune to damage and should be ignored by combat
    if CombatUtils and (CombatUtils.isPodiumAvatar(victimModel) or CombatUtils.isPodiumPart(hitPart)) then
        if _G.DEBUG_COMBAT then
            print("[Combat] Ignored podium avatar target:", victimModel and victimModel.Name or tostring(hitPart))
        end
        return
    end
    -- prevent friendly fire: if the victim is a player on the same Team, skip damage
    local victimPlayer = nil
    if victimModel and Players then
        victimPlayer = Players:GetPlayerFromCharacter(victimModel)
    end
    if victimPlayer and player and player.Team and victimPlayer.Team and player.Team == victimPlayer.Team then
        return
    end
    -- Apply ranged upgrade multiplier (PvP-capped / PvE-uncapped)
    if _G.GetRangedDamageMultiplier then
        local isPvP = (victimPlayer ~= nil)
        local mult = _G.GetRangedDamageMultiplier(player, isPvP)
        if type(mult) == "number" and mult > 0 and mult ~= 1 then
            damage = damage * mult
        end
    end
    damage = rollUniformIntegerDamage(damage, RANGED_DAMAGE_ROLL_MIN, RANGED_DAMAGE_ROLL_MAX)
    damage = applyOutgoingDamageModifiers(player, damage, {
        source = "ranged",
        weaponName = weaponName,
        weaponInstanceId = weaponInstanceId,
        victimModel = victimModel,
    })
    damage = math.max(0, math.round(damage))
    pcall(function()
        humanoid:SetAttribute("lastDamagerUserId", player.UserId)
        humanoid:SetAttribute("lastDamagerName", player.Name)
        humanoid:SetAttribute("lastDamageTime", tick())
        if type(weaponInstanceId) == "string" and weaponInstanceId ~= "" then
            humanoid:SetAttribute("lastDamagerWeaponInstanceId", weaponInstanceId)
        else
            humanoid:SetAttribute("lastDamagerWeaponInstanceId", nil)
        end
        if type(weaponName) == "string" and weaponName ~= "" then
            humanoid:SetAttribute("lastDamagerWeapon", weaponName)
        else
            humanoid:SetAttribute("lastDamagerWeapon", nil)
        end
    end)
    humanoid:TakeDamage(damage)

    if WeaponEnchantService and type(enchantName) == "string" and enchantName ~= "" then
        local attackerHumanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local procSucceeded = false
        pcall(function()
            procSucceeded = WeaponEnchantService.TryProcEnchant(
                player,
                attackerHumanoid,
                victimModel,
                humanoid,
                enchantName,
                hitPos,
                { damageType = "ranged" }
            ) == true
        end)
        if procSucceeded and hitPos then
            pcall(function()
                WeaponEnchantService.SpawnHitEffect(hitPos, enchantName, hitPart)
            end)
        end
    end

    -- Track damage dealt for quest progress
    if StatService and StatService.RegisterDamageDealt then
        pcall(function() StatService:RegisterDamageDealt(player, damage, { damageType = "ranged" }) end)
    end
    if WeaponMasteryService and type(weaponInstanceId) == "string" and weaponInstanceId ~= "" then
        pcall(function() WeaponMasteryService:RegisterDamage(player, weaponInstanceId, damage) end)
    end
    pcall(function()
        if fireHit then fireHit:FireClient(player, damage, hitPart, hitPos) end
    end)
    -- Kill credit (StatService events, coins, XP, KillFeed, AddScore) is handled
    -- centrally by KillTracker.server.lua via the Humanoid.Died hook. Weapons only
    -- need to TAG the humanoid (already done above via lastDamager* attributes).
end

-- One caster per equipped tool, reused across shots. Per-shot state lives on
-- ActiveCast.UserData so simultaneous players/shots cannot share damage context.
local projectileCasters = setmetatable({}, { __mode = "k" })
local function getProjectileCaster(tool)
    local caster = projectileCasters[tool]
    if caster then return caster end
    caster = FastCast.new()
    caster.LengthChanged:Connect(function(cast, origin, direction, length, velocity)
        cast.UserData.OnLengthChanged(origin, direction, length, velocity)
    end)
    caster.RayHit:Connect(function(cast, result, velocity)
        cast.UserData.OnRayHit(result, velocity)
    end)
    caster.CastTerminating:Connect(function(cast)
        cast.UserData.OnTerminating()
    end)
    projectileCasters[tool] = caster
    return caster
end

local function spawnProjectile(player, origin, initialVelocity, projCfg, toolName, clientShotId, equippedTool)
    -- projCfg contains per-tool overrides: damage, range, bulletdrop, projectile_size, projectile_lifetime
    local pDamage = (projCfg and projCfg.damage) or DAMAGE
    -- Ranged upgrade multiplier is applied at hit time in applyDamage
    -- so PvP vs PvE targets get the correct (capped vs uncapped) scaling.
    local pRange = (projCfg and projCfg.range) or RANGE
    local pDrop = (projCfg and projCfg.bulletdrop) or BULLET_DROP
    local pLifetime = (projCfg and projCfg.projectile_lifetime) or PROJECTILE_LIFETIME
    local leaveProjectile = (projCfg and (projCfg.LeaveProjectile == true or projCfg.leaveProjectile == true))
    local stickLifetime = (projCfg and (projCfg.projectile_stick_lifetime or projCfg.stick_lifetime)) or 2
    -- Visual scale already baked into projCfg.projectile_size by the caller;
    -- _projVisualScale is used here only for Model scaling.
    local modelVisualScale = (projCfg and projCfg._projVisualScale) or 1.0
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
    local presetKey = nil
    if toolName then
        local s = tostring(toolName):match("^Tool(.+)") or tostring(toolName):match("^(.+)$")
        if s then presetKey = s:lower() end
    end
    if ToolgunModule and ToolgunModule.getProjectileForPreset and presetKey then
        local ok, proj = pcall(function() return ToolgunModule.getProjectileForPreset(presetKey) end)
        if ok and proj then
            visual = proj
        end
    end

    -- Fallback to simple part if no template provided
    if not visual then
        visual = Instance.new("Part")
        visual.Name = "Bullet"
        visual.Size = pSize
        visual.Material = Enum.Material.SmoothPlastic
        visual.Color = Color3.fromRGB(180, 180, 180)
    elseif visual:IsA("Model") then
        usingModel = true
        scaleProjectileInstance(visual, modelVisualScale)
        getVisualPrimary(visual)
    elseif visual:IsA("BasePart") then
        scaleProjectileInstance(visual, modelVisualScale)
    else
        local part = Instance.new("Part")
        part.Name = "Bullet"
        part.Size = pSize
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.fromRGB(180, 180, 180)
        visual = part
        usingModel = false
    end

    applyProjectilePhysicsFlags(visual)
    params.FilterDescendantsInstances = {player.Character, visual}

    local enchantName = projCfg and projCfg._enchantName
    if type(enchantName) == "string" then
        enchantName = enchantName:match("^%s*(.-)%s*$")
        if enchantName == "" or string.lower(enchantName) == "none" then
            enchantName = nil
        end
    else
        enchantName = nil
    end
    if WeaponEnchantService and enchantName then
        local applied = false
        local applyOk, applyResult = pcall(function()
            return WeaponEnchantService.ApplyEnchantVisualsToProjectile(visual, enchantName)
        end)
        applied = applyOk and applyResult == true
        if not applyOk then
            warn("[ToolGun] Failed to apply projectile enchant visuals:", applyResult)
        elseif not applied then
            warn("[ToolGun] Projectile enchant visuals did not apply for", tostring(enchantName), "on", tostring(visual and visual.Name))
        end
    end
    applyEtherealProjectileColor(visual, (projCfg and projCfg._weaponName) or toolName, enchantName)

    local visualFlip = (projCfg and projCfg.visual_flip) and true or false
    local extraRotation = getVisualRotationCFrame(projCfg)
    local aimUnit = (initialVelocity and initialVelocity.Magnitude > 0.001) and initialVelocity.Unit or Vector3.new(0, 0, -1)
    local primary = getVisualPrimary(visual)
    if extraRotation == nil then
        extraRotation = getShaftLookCorrection(visual, primary)
    end
    local tipLocalPos = getTipLocalPosition(visual, primary)
    pcall(function()
        setVisualPrimaryCFrame(visual, usingModel, getAlignedPrimaryCFrame(origin, aimUnit, visualFlip, tipLocalPos, extraRotation))
    end)

    if WeaponTrailService and visual then
        local trailColor = DEFAULT_TRACER_COLOR
        if visual:IsA("BasePart") then
            trailColor = visual.Color
        elseif visual:IsA("Model") and visual.PrimaryPart then
            trailColor = visual.PrimaryPart.Color
        end
        if type(enchantName) == "string" and enchantName ~= "" then
            pcall(function()
                visual:SetAttribute("HasEnchant", true)
                visual:SetAttribute("EnchantName", enchantName)
            end)
        end
        pcall(function()
            WeaponTrailService.ApplyToProjectile(visual, {
                Color = trailColor,
                Lifetime = math.clamp(pLifetime * 0.08, 0.18, 0.35),
                EnchantName = enchantName,
                Scale = modelVisualScale,
            })
        end)
    end

    -- Do not parent the clone until its muzzle-aligned transform and effects are
    -- ready. Parenting first can replicate the template's saved Studio position
    -- for a frame, which looks like the projectile spawned far in front of the bow.
    -- This instance is simulation-only. Every client renders the broadcast visual,
    -- avoiding replication-delay jumps while the server retains hit authority.
    local function hideServerVisual(item)
        if item:IsA("BasePart") then
            item.Transparency = 1
            item.CastShadow = false
        elseif item:IsA("Trail") or item:IsA("Beam") or item:IsA("ParticleEmitter") then
            item.Enabled = false
        end
    end
    hideServerVisual(visual)
    for _, item in ipairs(visual:GetDescendants()) do hideServerVisual(item) end
    visual:SetAttribute("_ServerProjectileSimulation", true)
    visual.Parent = Workspace

    local lastPos = origin
    local hitHumanoids = {}
    local impactResult = nil
    local impactVelocity = initialVelocity
    local caster = getProjectileCaster(equippedTool)
    local behavior = FastCast.newBehavior()
    behavior.RaycastParams = params
    behavior.MaxDistance = pRange
    behavior.Acceleration = Vector3.new(0, -pDrop, 0)
    behavior.CanPierceFunction = function(_, result)
        return shouldPierceProjectile(result.Instance, player)
    end

    -- Cosmetics may be Models with Tip attachments, so we manage them through
    -- UserData instead of FastCast's BasePart-only CosmeticBulletTemplate.
    projectileVisualEvent:FireAllClients(
        "spawn", player.UserId, clientShotId, toolName, origin, aimUnit,
        projCfg._enchantName, modelVisualScale, {
            speed = initialVelocity.Magnitude,
            drop = pDrop,
            range = pRange,
            lifetime = pLifetime,
            startedAt = Workspace:GetServerTimeNow(),
        }
    )
    local cast = caster:Fire(origin, initialVelocity.Unit, initialVelocity, behavior)
    cast.UserData.OnLengthChanged = function(segmentOrigin, segmentDirection, length, velocity)
        lastPos = segmentOrigin + segmentDirection * length
        local moveDir = velocity.Magnitude > 0.001 and velocity.Unit or aimUnit
        setVisualPrimaryCFrame(visual, usingModel, getAlignedPrimaryCFrame(
            lastPos, moveDir, visualFlip, tipLocalPos, extraRotation
        ))
    end
    cast.UserData.OnRayHit = function(rayResult, velocity)
        impactResult = rayResult
        impactVelocity = velocity
        local inst = rayResult.Instance
        local parent = inst
        while parent and parent ~= Workspace do
            local humanoid = parent:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                if shouldIgnoreHumanoidTarget(parent, humanoid) then
                    parent = parent.Parent
                    continue
                end
                if hitHumanoids[humanoid] then
                    parent = parent.Parent
                    continue
                end
                applyDamage(
                    player,
                    humanoid,
                    parent,
                    pDamage,
                    inst,
                    rayResult.Position,
                    projCfg and projCfg._weaponInstanceId,
                    (projCfg and projCfg._weaponName) or toolName,
                    projCfg and projCfg._enchantName
                )
                hitHumanoids[humanoid] = true
                break
            end
            parent = parent.Parent
        end

        -- Retain the original landing sound when this preset leaves arrows behind.
        if leaveProjectile then
            local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
            local toolgunFolder = soundsFolder and soundsFolder:FindFirstChild("Toolgun")
            local template = toolgunFolder and toolgunFolder:FindFirstChild("Projectile_land")
            if template and template:IsA("Sound") then
                local host = Instance.new("Part")
                host.Name = "_ProjectileSound"
                host.Size = Vector3.new(0.2, 0.2, 0.2)
                host.Transparency = 1
                host.Anchored = true
                host.CanCollide = false
                host.CanTouch = false
                host.CanQuery = false
                host.CFrame = CFrame.new(rayResult.Position)
                host.Parent = Workspace
                local sound = template:Clone()
                sound.Parent = host
                sound:Play()
                game:GetService("Debris"):AddItem(host, 4)
            end
        end
    end
    cast.UserData.OnTerminating = function()
        projectileVisualEvent:FireAllClients("finish", player.UserId, clientShotId, {
            position = impactResult and impactResult.Position or lastPos,
            velocity = impactVelocity,
            hitPart = impactResult and impactResult.Instance,
            leaveProjectile = impactResult ~= nil and leaveProjectile,
            stickLifetime = stickLifetime,
        })
        visual:Destroy()
    end
    -- FastCast owns stepping and MaxDistance; preserve the preset's lifetime too.
    task.delay(pLifetime, function()
        if cast.StateInfo then cast:Terminate() end
    end)
end

local function isFiniteVector3(value)
    return typeof(value) == "Vector3"
        and value.X == value.X and value.Y == value.Y and value.Z == value.Z
        and math.abs(value.X) < math.huge
        and math.abs(value.Y) < math.huge
        and math.abs(value.Z) < math.huge
end

fireEvent.OnServerEvent:Connect(function(player, camOrigin, camDirection, gunOrigin, toolName, clientShotId)
    -- basic validation of types
    if not isFiniteVector3(camOrigin) or not isFiniteVector3(camDirection) or not isFiniteVector3(gunOrigin) then return end
    if camDirection.Magnitude <= 0.001 or type(toolName) ~= "string" then return end
    if type(clientShotId) ~= "number" or clientShotId ~= clientShotId
        or math.abs(clientShotId) == math.huge then return end
    if not player or not player.Character then return end
    -- Losing-team tool lockout: server-authoritative block on weapon use.
    if player:GetAttribute("ToolsLocked") == true then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- resolve per-tool config
    local tCfg = getServerToolCfg(toolName)
    local tDAMAGE = tCfg.damage or DAMAGE
    local tRANGE = tCfg.range or RANGE
    local tCOOLDOWN = tCfg.cd or COOLDOWN_SERVER

    -- Validate the tool is actually equipped in the character (not just named by client).
    local equippedTool = player.Character:FindFirstChild(toolName)
    if not equippedTool or not equippedTool:IsA("Tool") then return end

    -- WEAPON LOCK CHECK: reject shots from a different weapon while locked.
    if WeaponLockService.IsLocked(player) then
        local lockedTool = WeaponLockService.GetLockedTool(player)
        if lockedTool ~= toolName then return end
    end

    -- ── SIZE SCALING ──────────────────────────────────────────────────
    local sizePercent     = getToolSizePercent(equippedTool)
    local sizeDamageMult  = getSizeDamageMultiplier(sizePercent)
    local scaledCooldown  = getScaledCooldown(tCOOLDOWN, sizePercent)
    local projVisualScale = getProjectileVisualScale(sizePercent)

    local weaponInstanceId = equippedTool:GetAttribute("WeaponInstanceId")
    if WeaponMasteryService and type(weaponInstanceId) == "string" and weaponInstanceId ~= "" then
        local ok, masteryDamage = pcall(function()
            return WeaponMasteryService:GetMasteryBaseDamage(player, weaponInstanceId)
        end)
        if ok and type(masteryDamage) == "number" and masteryDamage > 0 then
            tDAMAGE = masteryDamage
        end
    end

    -- Scaled damage is baked into the projectile config so applyDamage
    -- sees it as the base damage (upgrade multipliers still apply there).
    local scaledDamage = tDAMAGE * sizeDamageMult

    -- Compute scaled projectile size.
    local baseSize = PROJECTILE_SIZE
    if tCfg.projectile_size then
        local ps = tCfg.projectile_size
        if typeof(ps) == "Vector3" then
            baseSize = ps
        elseif type(ps) == "table" then
            baseSize = Vector3.new(ps[1] or 0.2, ps[2] or 0.2, ps[3] or 0.2)
        end
    end
    local scaledSize = scaleVec3(baseSize, projVisualScale)

    -- Strict one-shot cooldown: no cadence snapping, no catch-up, no burst.
    local now = tick()
    local toolKey = toolName or "_default"
    if not lastFire[player] then lastFire[player] = {} end
    local last = lastFire[player][toolKey] or 0
    if now - last < scaledCooldown then
        print("[RangedCooldown] blocked", player.Name, toolName, "remaining", scaledCooldown - (now - last))
        return
    end
    lastFire[player][toolKey] = now

    print(string.format(
        "[RangedScaling] %s | size=%d%% | baseDmg=%.1f | finalDmg=%.1f | baseCd=%.2f | scaledCd=%.2f | projectileScale=%.2f",
        toolName, sizePercent, tDAMAGE, scaledDamage, tCOOLDOWN, scaledCooldown, projVisualScale
    ))

    -- Override cfg fields with computed scaled values before passing to spawnProjectile.
    -- We copy so we never mutate the shared config table.
    local scaledCfg = {}
    for k, v in pairs(tCfg) do scaledCfg[k] = v end
    scaledCfg.damage          = scaledDamage
    scaledCfg.projectile_size = scaledSize
    -- Store the visual scale so spawnProjectile can scale Model projectiles.
    scaledCfg._projVisualScale = projVisualScale
    scaledCfg._weaponInstanceId = equippedTool:GetAttribute("WeaponInstanceId")
    scaledCfg._weaponName = equippedTool:GetAttribute("WeaponName") or toolName
    scaledCfg._enchantName = equippedTool:GetAttribute("EnchantName")

    -- The firing client owns its character assembly, so its attachment position is
    -- newer than the server's replicated copy while the player is moving. Keep the
    -- client muzzle after tightly validating it against the character and the
    -- server-observed attachment. Replacing it with the latter made projectiles
    -- visibly spawn behind/to the side of a moving bow by roughly one network RTT.
    if (gunOrigin - hrp.Position).Magnitude > 16 then return end
    if (camOrigin - hrp.Position).Magnitude > 120 then return end

    local serverFireOrigin = nil
    if ToolgunModule and type(ToolgunModule.getFireOrigin) == "function" then
        serverFireOrigin = ToolgunModule.getFireOrigin(equippedTool, nil)
    else
        local fireAttachment = findNamedAttachment(equippedTool, "Fire")
        if fireAttachment then
            serverFireOrigin = fireAttachment.WorldPosition
        end
    end

    -- Allow replication delay, but reject a forged muzzle that is nowhere near the
    -- equipped weapon. The actual visual/simulation origin remains the fresh client
    -- attachment position so it stays glued to Fire even during strafes and dashes.
    if isFiniteVector3(serverFireOrigin) and (gunOrigin - serverFireOrigin).Magnitude > 16 then
        return
    end
    local fireOrigin = gunOrigin

    -- perform a server-side hitscan from the camera ray first so shots go where the player's cursor is
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {player.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true

    local rayDir = camDirection.Unit
    local tBULLETSPEED = tCfg.bulletspeed or PROJECTILE_SPEED

    -- Compute an aim point on the camera ray (server-side) so projectiles from the muzzle converge on the crosshair
    local camHit = raycastSkippingAccessories(camOrigin, rayDir * tRANGE, params, player)
    local aimPoint
    if camHit and camHit.Instance and camHit.Position then
        aimPoint = camHit.Position
    else
        aimPoint = camOrigin + rayDir * tRANGE
    end

    -- Aim direction from muzzle to the aimPoint (fixes parallax)
    local aimDir = (aimPoint - fireOrigin)
    if aimDir.Magnitude <= 0.001 then
        aimDir = hrp.CFrame.LookVector
    else
        aimDir = aimDir.Unit
    end

    -- muzzle obstruction check along the computed aimDir from Fire
    local gunObstruction = raycastSkippingAccessories(fireOrigin, aimDir * tRANGE, params, player)
    if gunObstruction and gunObstruction.Instance then
        local showTracerForTool = (tCfg and tCfg.showTracer ~= nil) and tCfg.showTracer or SHOW_TRACER
        if showTracerForTool then
            coroutine.wrap(function()
                local hitPos = gunObstruction.Position
                local beam = Instance.new("Part")
                beam.Name = "ToolGunServerTracer"
                local dir = (hitPos - fireOrigin)
                local len = dir.Magnitude
                beam.Size = Vector3.new(0.15, 0.15, math.max(len, 0.1))
                beam.CFrame = CFrame.new(fireOrigin + dir/2, hitPos)
                beam.Anchored = true
                beam.CanCollide = false
                beam.Material = Enum.Material.Neon
                beam.Color = DEFAULT_TRACER_COLOR
                beam.Parent = Workspace
                game:GetService("Debris"):AddItem(beam, 0.22)
            end)()
        end
        -- (fireAck is fired early in this handler, before spawnProjectile — no duplicate here)
    end

    -- Notify the client immediately so hold-to-fire pacing is driven by ACK, not a local timer.
    pcall(function()
        if fireAck then fireAck:FireClient(player, fireOrigin, aimPoint, toolName) end
    end)

    -- FastCast uses the existing weapon speed and bulletdrop configuration.
    local initVel = aimDir * tBULLETSPEED
    spawnProjectile(player, fireOrigin, initVel, scaledCfg, toolName, clientShotId, equippedTool)

    -- Apply a brief movement slow while firing ranged weapons.
    do
        local speedPenalty = tonumber(tCfg.movement_speed_penalty) or -4
        local slowDuration = math.max(scaledCooldown * 0.95, 0.01)
        HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, RANGED_ATTACK_SPEED_MODIFIER_ID, {
            additive = speedPenalty,
            duration = slowDuration,
            source = toolName,
        })
    end

    -- Lock weapon switching for the duration of this weapon's scaled cooldown.
    WeaponLockService.ApplyWeaponLock(player, equippedTool, scaledCooldown)

    -- play a minimal server-side recoil animation on the shooter's right arm
    spawn(function()
        pcall(function() playServerRecoil(player) end)
    end)
end)

-- Restore WalkSpeed and weapon lock on character removal (respawn clears old Humanoid/Backpack).
local function onCharacterRemoving(player)
    clearRangedFireSlow(player)
    -- Roblox resets the backpack on respawn; just destroy the holder so tools re-grant cleanly.
    WeaponLockService.cleanupCharacter(player)
end

local function setupPlayerCleanup(player)
    player.CharacterRemoving:Connect(function()
        onCharacterRemoving(player)
    end)
end

-- Hook existing players (if script runs after players joined).
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayerCleanup(player)
end

Players.PlayerAdded:Connect(function(player)
    setupPlayerCleanup(player)
end)

-- clean up rate-limit table when players leave
Players.PlayerRemoving:Connect(function(player)
    lastFire[player] = nil
    clearRangedFireSlow(player)
    WeaponLockService.cleanupPlayer(player)
end)
