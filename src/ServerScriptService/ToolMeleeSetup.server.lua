--------------------------------------------------------------------------------
-- ToolMeleeSetup.server.lua  –  server-side melee weapon handler
-- Mirrors ToolGunSetup.server.lua: creates RemoteEvents, validates incoming
-- swing requests, performs a short-range cone/sphere check, applies damage,
-- handles kill feed and score.
--
-- SCALING SYSTEM:
--   All timing / damage / knockback values from ToolMeleeSettings are baselines
--   at 100% weapon size.  At runtime they are scaled by:
--     • Size multiplier  (sizePercent / 100)  — bigger = more damage, slower swing
--     • Combo multiplier (per-step from comboConfig) — attack 3 is the finisher
--------------------------------------------------------------------------------
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris              = game:GetService("Debris")
local CollectionService   = game:GetService("CollectionService")
local TweenService        = game:GetService("TweenService")

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

-- StatService: damage tracking for quests
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

-- Melee settings module
local MeleeCfg
if ReplicatedStorage:FindFirstChild("ToolMeleeSettings") then
    MeleeCfg = require(ReplicatedStorage:WaitForChild("ToolMeleeSettings"))
end

-- ENCHANT SYSTEM: lazy-load enchant service for hit-burst visuals
local WeaponEnchantService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponEnchantService")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantService = require(mod)
    end
end)

-- Shared weapon switch lock
local WeaponLockService = require(ServerScriptService:WaitForChild("WeaponLockService"))

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

local swingEvent    = ensureEvent("MeleeSwing")   -- client → server
local meleeHit      = ensureEvent("MeleeHit")      -- server → client (damage popup)
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
-- Resolve per-tool config from presets (uses getPreset which merges
-- rarity defaults + weapon overrides)
---------------------------------------------------------------------------
local function getServerMeleeCfg(toolName)
    if not MeleeCfg or not MeleeCfg.getPreset then return {} end
    local suffix = toolName and (tostring(toolName):match("^Tool(.+)") or tostring(toolName):match("^(.+)$"))
    local key = suffix and suffix:lower()
    if not key then return {} end
    return MeleeCfg.getPreset(key) or {}
end

---------------------------------------------------------------------------
-- SIZE + COMBO SCALING HELPERS
--
-- All config values (damage, cd, knockback, hitboxDelay, hitboxActive,
-- trail_start, trail_end) are baselines authored at 100% weapon size.
--
-- sizePercent is read from tool attributes (set by WeaponScaleService
-- via Loadout.server at equip time).
--
-- Size multiplier = sizePercent / 100
--   100% → 1.0x   (normal baseline)
--   200% → 2.0x   (King: double damage, double swing time)
--    80% → 0.8x   (Tiny: less damage, faster swing)
---------------------------------------------------------------------------

--- Read weapon size from tool attributes. Defaults to 100.
local _sizeWarnedTools = {}
local function getToolSizePercent(tool)
    if not tool then return 100 end
    local sp = tool:GetAttribute("SizePercent")
        or tool:GetAttribute("WeaponSizePercent")
        or tool:GetAttribute("ScalePercent")
        or tool:GetAttribute("WeaponScale")
    if type(sp) == "number" and sp > 0 then return sp end
    -- warn once per tool instance
    if not _sizeWarnedTools[tool] then
        _sizeWarnedTools[tool] = true
        warn("[MeleeScaling] No size attribute found on tool:", tool.Name, "defaulting to 100")
    end
    return 100
end

--- Damage scales at half rate above 100%: 200% size = 1.5x damage.
local function getSizeDamageMultiplier(sizePercent)
    if sizePercent <= 100 then
        return math.clamp(sizePercent / 100, 0.5, 1.0)
    end
    return math.clamp(1.0 + (sizePercent - 100) / 200, 1.0, 1.5)
end

--- Speed scaling: 100% = 1.0x. 200% = 1.5x (half-rate above 100%).
--- Below 100% is linear (tiny weapons swing faster).
local function getSizeSpeedMultiplier(sizePercent)
    if sizePercent <= 100 then
        return math.clamp(sizePercent / 100, 0.5, 1.0)
    end
    return math.clamp(1.0 + (sizePercent - 100) / 200, 1.0, 2.0)
end

--- Return the scaled swing duration for a given base cooldown.
local function getScaledSwingDuration(baseDuration, sizePercent)
    return baseDuration * getSizeSpeedMultiplier(sizePercent)
end

--- Return scaled hitbox timing (delay, active) preserving the proportional
--- hit-point within the swing animation (~80% into the swing).
local function getScaledHitboxTiming(baseDelay, baseActive, sizePercent)
    local sm = getSizeSpeedMultiplier(sizePercent)
    return baseDelay * sm, baseActive * sm
end

--- Combo damage multiplier for a given step (1-indexed).
--- Falls back to 1.0 for attacks 1-2 and legacy ATTACK3_DAMAGE_MULTIPLIER for attack 3.
local function getComboDamageMultiplier(comboCfg, step)
    if comboCfg.ATTACK_DAMAGE_MULTIPLIERS and type(comboCfg.ATTACK_DAMAGE_MULTIPLIERS) == "table" then
        local m = comboCfg.ATTACK_DAMAGE_MULTIPLIERS[step]
        if type(m) == "number" then return m end
    end
    -- Legacy fallback
    if step == 3 then
        return comboCfg.ATTACK3_DAMAGE_MULTIPLIER or 1.25
    end
    return 1.0
end

--- Combo knockback multiplier for a given step.
--- Attacks 1-2 are minimal; attack 3 is the big finisher.
local function getComboKnockbackMultiplier(comboCfg, step)
    if comboCfg.ATTACK_KNOCKBACK_MULTIPLIERS and type(comboCfg.ATTACK_KNOCKBACK_MULTIPLIERS) == "table" then
        local m = comboCfg.ATTACK_KNOCKBACK_MULTIPLIERS[step]
        if type(m) == "number" then return m end
    end
    -- Default fallback: attacks 1-2 light, attack 3 heavy
    local defaults = { 1.0, 1.25, 10.0 }
    return defaults[step] or 1.0
end

local function getMaxCleaveTargets(sizePercent)
    if sizePercent >= 190 then
        return 3
    end
    if sizePercent >= 150 then
        return 2
    end
    return 1
end

---------------------------------------------------------------------------
-- Damage helper (same tag pattern as the gun system so KillTracker works)
---------------------------------------------------------------------------
local function applyMeleeDamage(player, humanoid, victimModel, damage, hitPart, hitPos, weaponInstanceId, weaponName)
    -- prevent friendly fire: if the victim is a player on the same Team, skip damage
    local victimPlayer = nil
    if victimModel and Players then
        victimPlayer = Players:GetPlayerFromCharacter(victimModel)
    end
    if victimPlayer and player and player.Team and victimPlayer.Team and player.Team == victimPlayer.Team then
        return
    end
    -- Apply melee upgrade multiplier (PvP-capped / PvE-uncapped)
    if _G.GetMeleeDamageMultiplier then
        local isPvP = (victimPlayer ~= nil)
        local mult = _G.GetMeleeDamageMultiplier(player, isPvP)
        if mult > 1 then
            damage = damage * mult
        end
    end
    -- Round to nearest whole number
    damage = math.round(damage)
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
    -- Track damage dealt for quest progress
    if StatService and StatService.RegisterDamageDealt then
        pcall(function() StatService:RegisterDamageDealt(player, damage) end)
    end
    if WeaponMasteryService and type(weaponInstanceId) == "string" and weaponInstanceId ~= "" then
        pcall(function() WeaponMasteryService:RegisterDamage(player, weaponInstanceId, damage) end)
    end
    -- send hit feedback to the attacker
    pcall(function()
        meleeHit:FireClient(player, damage, false, hitPart, hitPos)
    end)
    -- Kill credit (StatService events, coins, XP, KillFeed, AddScore, enchant
    -- cleanup, dummy ragdoll) is handled centrally by KillTracker.server.lua
    -- via the Humanoid.Died hook. Weapons only need to TAG the humanoid
    -- (already done above via lastDamager* attributes).
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
    -- Respect knockback immunity (e.g. mobs mid-attack)
    local model = victimRoot:FindFirstAncestorOfClass("Model")
    if model then
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum:GetAttribute("knockbackImmune") then return end
    end
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

    local candidates = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and p.Character ~= playerChar then
            table.insert(candidates, p.Character)
        end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name == "Dummy" then
            table.insert(candidates, obj)
        end
    end
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

        local toFlat = Vector3.new(toTarget.X, 0, toTarget.Z)
        if toFlat.Magnitude < 0.001 then
            table.insert(results, { humanoid = hum, model = model, hitPart = root, hitPos = root.Position, dist = dist })
            continue
        end
        toFlat = toFlat.Unit
        local angle = math.acos(math.clamp(lookFlat:Dot(toFlat), -1, 1))
        if angle <= halfArc then
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = { playerChar }
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true
            local ray = Workspace:Raycast(origin, (root.Position - origin), params)
            if ray == nil then
                table.insert(results, { humanoid = hum, model = model, hitPart = root, hitPos = root.Position, dist = dist })
            elseif ray.Instance then
                if ray.Instance:IsDescendantOf(model) or ray.Instance == root then
                    table.insert(results, {
                        humanoid = hum,
                        model    = model,
                        hitPart  = ray.Instance,
                        hitPos   = ray.Position,
                        dist     = dist,
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.dist < b.dist end)
    return results
end

---------------------------------------------------------------------------
-- Box overlap hit detection
---------------------------------------------------------------------------
local function getTargetsInBox(playerChar, boxCFrame, halfSize)
    local results = {}
    local seenHum = {}

    local parts = Workspace:GetPartBoundsInBox(boxCFrame, halfSize * 2)
    if parts and #parts > 0 then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { playerChar }
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        for _, part in ipairs(parts) do
            if not part or not part:IsA("BasePart") then continue end
            local model = part:FindFirstAncestorOfClass("Model")
            if not model then continue end
            if model == playerChar then continue end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            if seenHum[hum] then continue end

            local dir = part.Position - boxCFrame.Position
            if dir.Magnitude <= 0.001 then
                local dist = (part.Position - boxCFrame.Position).Magnitude
                table.insert(results, { humanoid = hum, model = model, hitPart = part, hitPos = part.Position, dist = dist })
                seenHum[hum] = true
            else
                local ray = Workspace:Raycast(boxCFrame.Position, dir, params)
                if ray == nil then
                    local dist = (part.Position - boxCFrame.Position).Magnitude
                    table.insert(results, { humanoid = hum, model = model, hitPart = part, hitPos = part.Position, dist = dist })
                    seenHum[hum] = true
                elseif ray.Instance and (ray.Instance:IsDescendantOf(model) or ray.Instance == part) then
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
-- Rate limiting & combo state
---------------------------------------------------------------------------
local lastSwing  = {} -- [player] = { [toolName] = tick() }
local slowState  = {} -- [player] = { count = n, base = number, factors = {..} }
local comboState = {} -- [player] = { step = 1, lastTime = 0, toolName = "" }

-- Combo config from shared module
local comboCfg = MeleeCfg and MeleeCfg.comboConfig or {}
local COMBO_WINDOW   = comboCfg.COMBO_WINDOW or 0.2
local ATTACK3_EXTRA  = comboCfg.ATTACK3_EXTRA_CD or 0.4

---------------------------------------------------------------------------
-- Handle incoming swing
---------------------------------------------------------------------------
swingEvent.OnServerEvent:Connect(function(player, toolName, lookDir, clientComboStep)
    -- basic validation
    if type(toolName) ~= "string" then return end
    if typeof(lookDir) ~= "Vector3" then return end
    if not player or not player.Character then return end
    -- Losing-team tool lockout: server-authoritative block on weapon use.
    if player:GetAttribute("ToolsLocked") == true then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    -- verify the player actually has this tool equipped
    local tool = player.Character:FindFirstChild(toolName)
    if not tool or not tool:IsA("Tool") then return end

    -- WEAPON LOCK CHECK: reject swings from a different weapon while locked
    if WeaponLockService.IsLocked(player) then
        local lockedTool = WeaponLockService.GetLockedTool(player)
        if lockedTool ~= toolName then return end
    end

    -- resolve config (rarity defaults merged with weapon overrides)
    local cfg = getServerMeleeCfg(toolName)

    -- ── SIZE SCALING ──────────────────────────────────────────────────
    local sizePercent     = getToolSizePercent(tool)
    local sizeDamageMult  = getSizeDamageMultiplier(sizePercent)
    local sizeSpeedMult   = getSizeSpeedMultiplier(sizePercent)

    -- Base stats from config (at 100% size)
    local baseDamage   = cfg.damage or 5
    local baseKnockback = cfg.knockback or 2

    -- ── COMBO VALIDATION ──────────────────────────────────────────────
    local hasCombo = cfg.swing_anim_ids and type(cfg.swing_anim_ids) == "table"
        and #cfg.swing_anim_ids >= 3

    local now = tick()
    if not comboState[player] then
        comboState[player] = { step = 1, lastTime = 0, toolName = "" }
    end
    local cs = comboState[player]

    local validStep = 1
    if hasCombo then
        -- Reset if weapon changed or combo window expired
        local prevBaseCd = (cfg.cd or 0.5) + (cs.step == 3 and ATTACK3_EXTRA or 0)
        local prevScaledCd = prevBaseCd * sizeSpeedMult
        local comboDeadline = cs.lastTime + prevScaledCd + COMBO_WINDOW
        if cs.toolName ~= toolName or now > comboDeadline then
            cs.step = 1
        end

        if type(clientComboStep) == "number" then
            clientComboStep = math.clamp(math.floor(clientComboStep), 1, 3)
        else
            clientComboStep = 1
        end

        validStep = cs.step
    end

    -- ── SCALED COOLDOWN ───────────────────────────────────────────────
    -- cfg.cd = exact cooldown per attack in seconds (steps 1 & 2).
    -- Step 3 adds ATTACK3_EXTRA on top.
    local baseCd     = cfg.cd or 0.5
    local baseStepCd = hasCombo and (baseCd + (validStep == 3 and ATTACK3_EXTRA or 0))
                                or  baseCd
    local cd = baseStepCd * sizeSpeedMult

    -- ── SCALED DAMAGE ─────────────────────────────────────────────────
    -- finalDamage = baseDamage * sizeMult * comboMult * random(0.8–1.0), rounded up
    local comboDmgMult = getComboDamageMultiplier(comboCfg, validStep)
    local rawDamage = baseDamage * sizeDamageMult * comboDmgMult
    local damageRoll = 0.8 + math.random() * 0.2   -- 80-100% of full value
    local damage = math.ceil(rawDamage * damageRoll)

    -- ── SCALED KNOCKBACK ──────────────────────────────────────────────
    -- finalKnockback = baseKnockback * comboKnockbackMult * sizeMult
    local comboKbMult = getComboKnockbackMultiplier(comboCfg, validStep)
    local finalKnockback = baseKnockback * comboKbMult * sizeDamageMult
    local maxTargets = getMaxCleaveTargets(sizePercent)
    local cleaveDamageMultipliers = { 1.0, 0.55, 0.35 }
    local cleaveKnockbackMultipliers = { 1.0, 0.4, 0.4 }

    -- ── DEBUG: size scaling verification ───────────────────────────────
    print(string.format(
        "[MeleeScaling] %s | size=%d%% | baseDmg=%.1f | finalDmg=%d | baseCd=%.2f | scaledCd=%.2f | step=%d",
        toolName, sizePercent, baseDamage, damage, baseStepCd, cd, validStep
    ))

    -- ── SWORD TRAIL (size-scaled timing) ──────────────────────────────
    do
        local ok, trail = pcall(function() return tool:FindFirstChild("SwordTrail", true) end)
        if ok and trail and trail:IsA("Trail") then
            pcall(function() trail.Enabled = false end)
            -- Anchor trail to hitbox: start 0.12s before impact, end at hitbox clear
            local hd         = (cfg.hitboxDelay  or 0.35) * sizeSpeedMult
            local ha         = (cfg.hitboxActive or 0.1)  * sizeSpeedMult
            local startDelay = math.max(0, hd - 0.12)
            local endTime    = hd + ha
            local activeDur  = math.max(0.01, endTime - startDelay)
            task.spawn(function()
                task.wait(startDelay)
                pcall(function() trail.Enabled = true end)
                task.wait(activeDur)
                pcall(function() trail.Enabled = false end)
            end)
        end
    end

    -- ── RATE LIMITING ─────────────────────────────────────────────────
    if not lastSwing[player] then lastSwing[player] = {} end
    local last       = lastSwing[player][toolName] or 0
    local prevStepCd = lastSwing[player][toolName .. "_cd"] or cd
    if now - last < prevStepCd * 0.85 then return end
    if last > 0 and (now - last) < prevStepCd * 1.5 then
        lastSwing[player][toolName] = last + prevStepCd
    else
        lastSwing[player][toolName] = now
    end
    lastSwing[player][toolName .. "_cd"] = cd

    -- Lock weapon switching for the duration of this swing's cooldown.
    WeaponLockService.ApplyWeaponLock(player, tool, cd)

    -- Advance server combo state AFTER rate-limit passes
    if hasCombo then
        cs.lastTime = now
        cs.toolName = toolName
        if validStep >= 3 then
            cs.step = 1
        else
            cs.step = validStep + 1
        end
    end

    -- ── SLOWDOWN (size-scaled duration) ───────────────────────────────
    do
        local slowFactor = 0.75
        if cfg.slow_factor and type(cfg.slow_factor) == "number" then
            slowFactor = math.clamp(cfg.slow_factor, 0.1, 1)
        end
        local slowDuration = math.max(cd * 0.95, 0.01)

        if not slowState[player] then
            slowState[player] = { count = 0, base = nil, factors = {} }
        end
        local st = slowState[player]
        if st.count == 0 then
            st.base = hum and hum.WalkSpeed or 16
        end
        st.count = st.count + 1
        table.insert(st.factors, slowFactor)

        local minFactor = 1
        for _, f in ipairs(st.factors) do minFactor = math.min(minFactor, f) end
        if hum and hum.Parent then
            pcall(function() hum.WalkSpeed = math.max((st.base or 16) * minFactor, 0.1) end)
        end

        task.delay(slowDuration, function()
            local s = slowState[player]
            if not s then return end
            s.count = math.max(s.count - 1, 0)
            for i, v in ipairs(s.factors) do
                if v == slowFactor then
                    table.remove(s.factors, i)
                    break
                end
            end
            if s.count <= 0 then
                if s.base and hum and hum.Parent then
                    pcall(function() hum.WalkSpeed = s.base end)
                end
                slowState[player] = nil
            else
                local mf = 1
                for _, f in ipairs(s.factors) do mf = math.min(mf, f) end
                if hum and hum.Parent then
                    pcall(function() hum.WalkSpeed = math.max((s.base or 16) * mf, 0.1) end)
                end
            end
        end)
    end

    -- ── LOOK DIRECTION (server-blended) ───────────────────────────────
    local serverLook = hrp.CFrame.LookVector
    local blended = (serverLook + lookDir.Unit).Unit
    if blended.Magnitude < 0.001 then blended = serverLook end

    -- ── SERVER AUDIOVISUALS ───────────────────────────────────────────
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
                            -- At larger sizes the swing takes longer, so delay the whoosh
                            -- and slow it down so it hits at the same point in the animation.
                            s.PlaybackSpeed = math.clamp(1.0 / sizeSpeedMult, 0.25, 1.5)
                            s.Parent = hrp
                            -- Fire at 0.08s into the swing (scaled with size)
                            local soundDelay = 0.08 * sizeSpeedMult
                            task.delay(soundDelay, function()
                                if s and s.Parent then s:Play() end
                            end)
                            Debris:AddItem(s, soundDelay + 3)
                        end
                    end
                end
            end)
        end

        -- Resolve animation id: use combo step for combo weapons, else cycle
        local resolvedAnimId = nil
        if cfg.swing_anim_ids and type(cfg.swing_anim_ids) == "table" and #cfg.swing_anim_ids > 0 then
            local validIds = {}
            for _, id in ipairs(cfg.swing_anim_ids) do
                if id and tostring(id) ~= "" then table.insert(validIds, tostring(id)) end
            end
            if #validIds > 0 then
                if hasCombo then
                    resolvedAnimId = validIds[((validStep - 1) % #validIds) + 1]
                else
                    if not lastSwing[player] then lastSwing[player] = {} end
                    local cycleKey = toolName .. "_animIdx"
                    local idx = lastSwing[player][cycleKey] or 1
                    resolvedAnimId = validIds[((idx - 1) % #validIds) + 1]
                    lastSwing[player][cycleKey] = idx + 1
                end
            end
        end
        if (not resolvedAnimId or resolvedAnimId == "") and cfg.swing_anim_id and cfg.swing_anim_id ~= "" then
            resolvedAnimId = tostring(cfg.swing_anim_id)
        end

        local animObj = nil
        if resolvedAnimId and resolvedAnimId ~= "" then
            local a = Instance.new("Animation")
            local animId = resolvedAnimId
            if not animId:match("^rbxassetid://") then
                if tonumber(animId) then
                    animId = "rbxassetid://" .. animId
                end
            end
            a.AnimationId = animId
            animObj = a
        end

        -- find the right-arm Motor6D so we can restore it after animation/tween
        local motor = nil
        do
            local char = player.Character
            if char then
                local torso = char:FindFirstChild("Torso")
                if torso then motor = torso:FindFirstChild("Right Shoulder") end
                if not motor then
                    local rua = char:FindFirstChild("RightUpperArm")
                    if rua then motor = rua:FindFirstChild("RightShoulder") end
                end
                if motor and not motor:IsA("Motor6D") then motor = nil end
            end
        end

        local originalC1 = motor and motor.C1 or nil

        if animObj then
            pcall(function()
                local animator = hum:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator")
                    animator.Parent = hum
                end

                local okLoad, track = pcall(function() return animator:LoadAnimation(animObj) end)
                if not okLoad or not track then return end
                track.Priority = Enum.AnimationPriority.Action

                -- Scale animation speed by size only: baseStepCd/cd = 1/sizeSpeedMult
                -- so bigger weapons play the animation proportionally slower.
                local fallbackSpeed = math.clamp(baseStepCd / cd, 0.25, 4.0)

                track.Stopped:Connect(function()
                    if originalC1 and motor and motor.Parent then
                        pcall(function() motor.C1 = originalC1 end)
                    end
                end)

                -- Pass speed as 3rd arg to Play() — omitting it defaults to 1.0
                -- which silently overrides any prior AdjustSpeed call.
                pcall(function() track:Play(0.1, 1, fallbackSpeed) end)

                -- Belt-and-suspenders AdjustSpeed after Play
                pcall(function() track:AdjustSpeed(fallbackSpeed) end)

                -- Once track.Length resolves, refine with exact value
                task.spawn(function()
                    task.wait(0.1)
                    local realLength = 0
                    pcall(function() realLength = track.Length end)
                    if realLength > 0 and cd > 0 then
                        local preciseSpeed = math.clamp(realLength / cd, 0.25, 4.0)
                        if math.abs(preciseSpeed - fallbackSpeed) > 0.05 then
                            pcall(function() track:AdjustSpeed(preciseSpeed) end)
                        end
                    end
                end)

                local stopDelay = math.max(cd * 1.05, 0.15)
                task.delay(stopDelay, function()
                    if track then pcall(function() track:Stop() end) end
                    if animObj and animObj:IsA("Animation") and animObj.Parent == nil then
                        pcall(function() animObj:Destroy() end)
                    end
                    if originalC1 and motor and motor.Parent then
                        pcall(function() motor.C1 = originalC1 end)
                    end
                end)
            end)
        else
            -- Procedural swing fallback: tween Motor6D on the right arm
            pcall(function()
                local char = player.Character
                if not char then return end
                if not motor then return end

                local raiseGoal = originalC1 * CFrame.Angles(math.rad(-90), 0, 0)
                local slashGoal = originalC1 * CFrame.Angles(math.rad(90), 0, 0)

                -- Scale procedural timings to match size-scaled cooldown
                local DEFAULT_PROC_TOTAL = 0.48
                local scale = 1
                if cd > 0 then scale = cd / DEFAULT_PROC_TOTAL end

                local raiseTI  = TweenInfo.new(0.12 * scale, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local slashTI  = TweenInfo.new(0.14 * scale, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                local returnTI = TweenInfo.new(0.22 * scale, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

                local raiseTween = TweenService:Create(motor, raiseTI, { C1 = raiseGoal })
                raiseTween:Play()
                raiseTween.Completed:Once(function()
                    local slashTween = TweenService:Create(motor, slashTI, { C1 = slashGoal })
                    slashTween:Play()
                    slashTween.Completed:Once(function()
                        local returnTween = TweenService:Create(motor, returnTI, { C1 = originalC1 })
                        returnTween:Play()
                        returnTween.Completed:Once(function()
                            if originalC1 and motor and motor.Parent then
                                pcall(function() motor.C1 = originalC1 end)
                            end
                        end)
                    end)
                end)

                task.delay(math.max(cd * 1.2, 0.5), function()
                    if originalC1 and motor and motor.Parent then
                        pcall(function() motor.C1 = originalC1 end)
                    end
                end)
            end)
        end
    end

    -- ── HITBOX (size-scaled timing + size-scaled spatial dimensions) ──
    local baseHitboxDelay  = cfg.hitboxDelay or 0.35
    local baseHitboxActive = cfg.hitboxActive or 0.1
    local scaledDelay, scaledActive = getScaledHitboxTiming(baseHitboxDelay, baseHitboxActive, sizePercent)

    -- Scale hitbox with weapon size: up to +50% at 200% size, never shrink below base
    local hitboxScale = 1
    if sizePercent > 100 then
        hitboxScale = 1 + math.clamp((sizePercent - 100) / 100, 0, 1) * 0.5
    end

    task.spawn(function()
        task.wait(scaledDelay)
        local hitAlready = {}
        local primaryHitDone = false
        local endTime = tick() + scaledActive
        while (not primaryHitDone) and tick() < endTime and player and player.Character and hum and hum.Health > 0 do
            local curHrp = player.Character:FindFirstChild("HumanoidRootPart")
            if not curHrp then break end

            local baseBoxSize = cfg.hitboxSize or Vector3.new(4, 3, 7)
            local boxSize = baseBoxSize * hitboxScale
            local offset  = cfg.hitboxOffset or Vector3.new(0, 1, boxSize.Z * 0.5)

            local rightV = curHrp.CFrame.RightVector
            local upV    = curHrp.CFrame.UpVector
            local lookV  = curHrp.CFrame.LookVector

            local centerZ = offset.Z
            local spread  = boxSize.Z * 0.35
            local sampleDepths = { centerZ - spread, centerZ, centerZ + spread }
            local candidateHits = {}

            for _, depth in ipairs(sampleDepths) do
                local pos = curHrp.Position + rightV * offset.X + upV * offset.Y + lookV * depth
                local boxCFrame = CFrame.new(pos, pos + lookV)
                local halfSize  = boxSize / 2

                -- Debug: show hitbox part (only when cfg.showHitbox == true)
                if cfg.showHitbox == true then
                    local dbg = Instance.new("Part")
                    dbg.Name = "_HitboxDebug"
                    dbg.Size = boxSize
                    dbg.CFrame = boxCFrame
                    dbg.Anchored = true
                    dbg.CanCollide = false
                    dbg.CanTouch = false
                    dbg.CanQuery = false
                    dbg.Transparency = 0.7
                    dbg.Color = cfg.hitboxColor or Color3.fromRGB(255, 0, 0)
                    dbg.Material = Enum.Material.Neon
                    dbg.Parent = workspace
                    Debris:AddItem(dbg, scaledActive + 0.05)
                end

                local targetsNow = getTargetsInBox(player.Character, boxCFrame, halfSize)
                for _, hit in ipairs(targetsNow) do
                    if not hitAlready[hit.humanoid] then
                        local victimRoot = hit.model:FindFirstChild("HumanoidRootPart") or hit.model:FindFirstChild("Torso")
                        local victimPos = (victimRoot and victimRoot.Position) or hit.hitPos
                        if victimPos then
                            local distToAttacker = (victimPos - curHrp.Position).Magnitude
                            local existing = candidateHits[hit.humanoid]
                            if (not existing) or distToAttacker < existing.dist then
                                candidateHits[hit.humanoid] = {
                                    hit = hit,
                                    boxCFrame = boxCFrame,
                                    victimRoot = victimRoot,
                                    dist = distToAttacker,
                                }
                            end
                        end
                    end
                end
            end

            local selectedHits = {}
            for _, entry in pairs(candidateHits) do
                table.insert(selectedHits, entry)
            end
            table.sort(selectedHits, function(a, b)
                return a.dist < b.dist
            end)

            while #selectedHits > maxTargets do
                table.remove(selectedHits)
            end

            if #selectedHits > 0 then
                primaryHitDone = true

                local pn = nil
                local canTryEnchant = WeaponEnchantService and tool and tool:GetAttribute("HasEnchant")
                if canTryEnchant then
                    pn = tool:GetAttribute("EnchantName")
                    canTryEnchant = pn and pn ~= ""
                end
                local enchantProcced = false

                for index, entry in ipairs(selectedHits) do
                    local hit = entry.hit
                    hitAlready[hit.humanoid] = true

                    local damageMultiplier = cleaveDamageMultipliers[index] or cleaveDamageMultipliers[#cleaveDamageMultipliers]
                    local knockbackMultiplier = cleaveKnockbackMultipliers[index] or cleaveKnockbackMultipliers[#cleaveKnockbackMultipliers]
                    applyMeleeDamage(
                        player,
                        hit.humanoid,
                        hit.model,
                        damage * damageMultiplier,
                        hit.hitPart,
                        hit.hitPos,
                        tool:GetAttribute("WeaponInstanceId"),
                        tool:GetAttribute("WeaponName") or toolName
                    )

                    if canTryEnchant and (not enchantProcced) then
                        local procSucceeded = false
                        pcall(function()
                            procSucceeded = WeaponEnchantService.TryProcEnchant(
                                player, hum,
                                hit.model, hit.humanoid,
                                pn, hit.hitPos
                            ) == true
                        end)
                        if procSucceeded then
                            enchantProcced = true
                            if hit.hitPos then
                                pcall(function()
                                    WeaponEnchantService.SpawnHitEffect(hit.hitPos, pn, hit.hitPart)
                                end)
                            end
                        end
                    end

                    -- knockback (skip for same-team players)
                    if finalKnockback > 0 and entry.victimRoot then
                        local vp = Players:GetPlayerFromCharacter(hit.model)
                        local isSameTeam = vp and player and player.Team and vp.Team and player.Team == vp.Team
                        if not isSameTeam then
                            local dir = (entry.victimRoot.Position - entry.boxCFrame.Position)
                            if dir.Magnitude < 0.01 then dir = entry.boxCFrame.LookVector end
                            applyKnockback(entry.victimRoot, dir, finalKnockback * knockbackMultiplier)
                        end
                    end
                end

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
            end

            task.wait(0.01)
        end
    end)
end)

-- clean up on leave
Players.PlayerRemoving:Connect(function(player)
    lastSwing[player] = nil
    comboState[player] = nil
    if slowState[player] then
        local st = slowState[player]
        local char = player.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and st.base then
                pcall(function() hum.WalkSpeed = st.base end)
            end
        end
        slowState[player] = nil
    end
    WeaponLockService.cleanupPlayer(player)
end)

print("[ToolMeleeSetup] server ready")
