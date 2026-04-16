--------------------------------------------------------------------------------
-- ToolMelee.client.lua  –  client-side melee weapon handler
-- Mirrors the ToolGun.client.lua pattern: auto-detects any Tool whose name
-- starts with "Tool" and whose suffix matches a ToolMeleeSettings preset
-- (e.g. ToolBat, ToolSword).  On click it fires a RemoteEvent so the server
-- can validate and apply damage.
--------------------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local Debris             = game:GetService("Debris")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local camera    = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- read melee settings module
local MeleeCfgModule
if ReplicatedStorage:FindFirstChild("ToolMeleeSettings") then
    MeleeCfgModule = require(ReplicatedStorage:WaitForChild("ToolMeleeSettings"))
end

-- ENCHANT SYSTEM: shared enchant config for trail color lookup
local WeaponEnchantConfig
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("WeaponEnchantConfig")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantConfig = require(mod)
    end
end)

-- remote for swings (server creates this)
local swingEvent = ReplicatedStorage:WaitForChild("MeleeSwing")

-- remote for hit feedback (server → client: damage, isHeadshot, hitPart, hitPos)
local meleeHitEvent = ReplicatedStorage:WaitForChild("MeleeHit")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function isMeleeTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsMelee") then return true end
    local suffix = tostring(tool.Name):match("^Tool(.+)") or tostring(tool.Name):match("^(.+)$")
    if not suffix then return false end
    if MeleeCfgModule and MeleeCfgModule.presets then
        return MeleeCfgModule.presets[suffix:lower()] ~= nil
    end
    return false
end

local function getCfg(tool)
    local cfg = {}
    local suffix = tostring(tool.Name):match("^Tool(.+)") or tostring(tool.Name):match("^(.+)$")
    local key = suffix and suffix:lower()
    if key and MeleeCfgModule then
        if MeleeCfgModule.getPreset then
            local preset = MeleeCfgModule.getPreset(key)
            if preset then
                for k, v in pairs(preset) do cfg[k] = v end
            end
        elseif MeleeCfgModule.presets and MeleeCfgModule.presets[key] then
            for k, v in pairs(MeleeCfgModule.presets[key]) do cfg[k] = v end
        end
    end
    -- per-tool attribute overrides
        for _, a in ipairs({"damage","cd","knockback","hitboxSize","hitboxOffset","hitboxDelay","hitboxActive","showHitbox"}) do
        local val = tool:GetAttribute(a)
        if val ~= nil then cfg[a] = val end
    end
    return cfg
end

--------------------------------------------------------------------------------
-- Size scaling helpers (mirrors server-side ToolMeleeSetup logic)
-- sizePercent / 100:  100% = 1.0x baseline,  200% = 2.0x (slower, stronger)
--------------------------------------------------------------------------------
local _sizeWarnedTools = {}
local function getToolSizePercent(tool)
    if not tool then return 100 end
    local sp = tool:GetAttribute("SizePercent")
        or tool:GetAttribute("WeaponSizePercent")
        or tool:GetAttribute("ScalePercent")
        or tool:GetAttribute("WeaponScale")
    if type(sp) == "number" and sp > 0 then return sp end
    if not _sizeWarnedTools[tool] then
        _sizeWarnedTools[tool] = true
        warn("[MeleeScaling] No size attribute found on tool:", tool.Name, "defaulting to 100")
    end
    return 100
end

--- Speed scaling: below 100% is linear (tiny weapons swing faster for more DPS).
--- Above 100% scales at half rate so max 200% = 1.5x duration, not 2.0x.
local function getSizeSpeedMultiplier(sizePercent)
    if sizePercent <= 100 then
        return math.clamp(sizePercent / 100, 0.5, 1.0)
    end
    return math.clamp(1.0 + (sizePercent - 100) / 200, 1.0, 2.0)
end

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------
local function playMeleeSound(soundKey)
    if not soundKey or soundKey == "" then return end
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local meleeFolder = soundsFolder:FindFirstChild("ToolMelee")
    if not meleeFolder then return end
    local template = meleeFolder:FindFirstChild(soundKey)
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = camera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

--------------------------------------------------------------------------------
-- Hit feedback GUI (floating damage number – same style as ranged)
--------------------------------------------------------------------------------
local function showDamagePopup(damage, isHeadshot, hitPart, hitPos)
    local parentPart, anchor
    if hitPart and typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
        parentPart = hitPart
    elseif hitPos and typeof(hitPos) == "Vector3" then
        anchor = Instance.new("Part")
        anchor.Name = "_MeleeAnchor"
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CFrame = CFrame.new(hitPos)
        anchor.Parent = workspace
        parentPart = anchor
    end
    if not parentPart then return end

    local gui = Instance.new("BillboardGui")
    gui.Name = "MeleeDmgPopup"
    gui.Size = UDim2.new(0, 100, 0, 40)
    gui.Adornee = parentPart
    gui.AlwaysOnTop = true
    gui.StudsOffset = Vector3.new(0, 2, 0)
    gui.Parent = parentPart

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(math.floor(damage))
    label.Font = Enum.Font.GothamBold
    label.TextSize = 24
    label.TextColor3 = isHeadshot and Color3.fromRGB(255, 75, 75) or Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.5
    label.Parent = gui

    local tween = TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
        StudsOffset = gui.StudsOffset + Vector3.new(0, 1.2, 0),
    })
    tween:Play()
    for i = 0, 1, 0.06 do
        label.TextTransparency = i
        task.wait(0.06)
    end
    tween:Cancel()
    gui:Destroy()
    if anchor and anchor.Parent then anchor:Destroy() end
end

--------------------------------------------------------------------------------
-- Debug: show hitbox disk locally for tuning (client-only part)
--------------------------------------------------------------------------------
local function showDebugHitbox(originCFrame, boxSize, offset, duration, color)
    if not originCFrame or not boxSize then return end
    duration = duration or 0.2
    color = color or Color3.fromRGB(255, 50, 50)

    local offset = offset or Vector3.new(0, 0, 0)
    local pos = originCFrame.Position
        + originCFrame.RightVector * offset.X
        + originCFrame.UpVector * offset.Y
        + originCFrame.LookVector * offset.Z
    local boxCFrame = CFrame.new(pos, pos + originCFrame.LookVector)
    local part = Instance.new("Part")
    part.Name = "_MeleeHitboxDebug"
    part.Anchored = true
    part.CanCollide = false
    part.Size = boxSize
    part.Transparency = 0.6
    part.Color = color
    part.Material = Enum.Material.Neon
    part.CFrame = boxCFrame
    part.Parent = workspace
    Debris:AddItem(part, duration)
end

--------------------------------------------------------------------------------
-- Play configured animation locally (returns true on success)
-- Supports swing_anim_ids (ordered array) — cycles 1→2→3→1… per tool.
--------------------------------------------------------------------------------
local currentSwingTrack = nil -- script-level: previous swing track reference
local swingCycleIndex = {}    -- [toolName] → next index into swing_anim_ids

local function playLocalCfgAnimation(cfg, toolName, scaledCd, baseCdOverride)
    -- Resolve which animation id to use this swing
    local animId = nil
    if cfg and cfg.swing_anim_ids and type(cfg.swing_anim_ids) == "table" and #cfg.swing_anim_ids > 0 then
        -- build a filtered list of non-empty ids
        local validIds = {}
        for _, id in ipairs(cfg.swing_anim_ids) do
            if id and tostring(id) ~= "" then table.insert(validIds, tostring(id)) end
        end
        if #validIds > 0 then
            local key = toolName or "_default"
            local idx = swingCycleIndex[key] or 1
            animId = validIds[((idx - 1) % #validIds) + 1]
            swingCycleIndex[key] = idx + 1
        end
    end
    -- fall back to single swing_anim_id
    if (not animId or animId == "") and cfg and cfg.swing_anim_id and cfg.swing_anim_id ~= "" then
        animId = tostring(cfg.swing_anim_id)
    end
    if not animId or animId == "" then return false end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    print("[MeleeAnim] RigType =", tostring(hum.RigType))

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end

    -- Stop any previous swing track to avoid overlap/conflicts
    if currentSwingTrack then
        pcall(function() currentSwingTrack:Stop(0) end)
        currentSwingTrack = nil
    end

    if not animId:match("^rbxassetid://") then
        if tonumber(animId) then animId = "rbxassetid://" .. animId end
    end
    print("[MeleeAnim] Loading animId =", animId)

    local a = Instance.new("Animation")
    a.AnimationId = animId
    local ok, track = pcall(function() return animator:LoadAnimation(a) end)
    if not ok or not track then
        print("[MeleeAnim] LoadAnimation FAILED")
        return false
    end

    -- Use Action4 (highest action priority) so idle/walk/tool anims cannot override
    track.Priority = Enum.AnimationPriority.Action4

    -- Scale speed to match size-scaled swing duration.
    -- Animations are authored at the base cooldown (~0.5s). For bigger weapons
    -- scaledCd is longer, so we slow the animation proportionally.
    -- baseCd/scaledCd gives the correct ratio immediately without needing track.Length.
    local cd = scaledCd or cfg.cd or 0.5
    local baseCd = baseCdOverride or cfg.cd or 0.5
    local fallbackSpeed = math.clamp(baseCd / cd, 0.25, 4.0)

    -- Pass speed as 3rd arg to Play() so Roblox doesn't default it to 1.0.
    -- Play(fadeTime, weight, speed) — omitting speed defaults to 1.0 which
    -- silently overrides any prior AdjustSpeed call.
    local okPlay = pcall(function() track:Play(0, 1, fallbackSpeed) end)
    if not okPlay then
        print("[MeleeAnim] track:Play() FAILED")
        return false
    end

    -- Belt-and-suspenders: also AdjustSpeed after Play in case the engine
    -- ignores the 3rd arg on some platforms/versions.
    pcall(function() track:AdjustSpeed(fallbackSpeed) end)
    print("[MeleeAnim] Speed =", fallbackSpeed, "baseCd =", baseCd, "scaledCd =", cd, "tool =", toolName)

    currentSwingTrack = track
    print("[MeleeAnim] track:Play() called for", animId)

    -- Once track.Length resolves, refine with the exact value for precision
    task.spawn(function()
        task.wait(0.1)
        local realLength = 0
        pcall(function() realLength = track.Length end)
        if realLength > 0 and cd > 0 then
            local preciseSpeed = math.clamp(realLength / cd, 0.25, 4.0)
            if math.abs(preciseSpeed - fallbackSpeed) > 0.05 then
                pcall(function() track:AdjustSpeed(preciseSpeed) end)
                print("[MeleeAnim] Refined speed =", preciseSpeed, "length =", realLength)
            end
        end
    end)

    -- schedule stop/cleanup
    task.delay((cd or 0.6) * 1.2 + 0.05, function()
        if track then pcall(function() track:Stop() end) end
        if currentSwingTrack == track then currentSwingTrack = nil end
        if a and a.Parent == nil then pcall(function() a:Destroy() end) end
    end)
    return true
end

--------------------------------------------------------------------------------
-- Swing animation — procedural CFrame tween on the right arm + tool
-- Works for both R6 (Right Arm) and R15 (RightHand / RightUpperArm).
-- If the tool contains an Animation named "Swing*" it uses that instead.
--------------------------------------------------------------------------------
-- Swing timing: raise → slash down → return to rest
local raiseTweenInfo  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local slashTweenInfo  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local returnTweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local function playSwingVisual(tool)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 1) try a custom Animation inside the tool first
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, a in ipairs(tool:GetDescendants()) do
            if a:IsA("Animation") and a.Name:lower():find("swing") then
                pcall(function()
                    local track = animator:LoadAnimation(a)
                    track.Priority = Enum.AnimationPriority.Action
                    track:Play()
                end)
                return
            end
        end
    end

    -- (moved playLocalCfgAnimation to top-level)

    -- 2) procedural swing: raise arm up 90°, slash down 180°, return to rest
    -- R6: "Right Shoulder" Motor6D in Torso
    -- R15: "RightShoulder" Motor6D in RightUpperArm
    local motor = nil
    local torso = char:FindFirstChild("Torso")
    if torso then
        motor = torso:FindFirstChild("Right Shoulder")
    end
    if not motor then
        local rua = char:FindFirstChild("RightUpperArm")
        if rua then motor = rua:FindFirstChild("RightShoulder") end
    end
    if not motor or not motor:IsA("Motor6D") then return end

    local originalC1 = motor.C1
    -- use slightly less than 90° to avoid ambiguous 180° interpolation that can flip the arm
    local SWING_ANGLE = 85
    -- phase 1: raise arm up (negative rotation to lift)
    local raiseGoal = originalC1 * CFrame.Angles(math.rad(-SWING_ANGLE), 0, 0)
    -- phase 2: slash down (rotate to +SWING_ANGLE relative to default)
    local slashGoal = originalC1 * CFrame.Angles(math.rad(SWING_ANGLE), 0, 0)

    local raiseTween = TweenService:Create(motor, raiseTweenInfo, { C1 = raiseGoal })
    raiseTween:Play()
    raiseTween.Completed:Once(function()
        local slashTween = TweenService:Create(motor, slashTweenInfo, { C1 = slashGoal })
        slashTween:Play()
        slashTween.Completed:Once(function()
            local returnTween = TweenService:Create(motor, returnTweenInfo, { C1 = originalC1 })
            returnTween:Play()
        end)
    end)
end

--------------------------------------------------------------------------------
-- Per-tool setup
--------------------------------------------------------------------------------
local function attachMelee(tool)
    if not tool or not tool:IsA("Tool") then return end
    if not isMeleeTool(tool) then return end
    if tool:GetAttribute("_meleeConnected") then return end
    tool:SetAttribute("_meleeConnected", true)

    -- detect a Trail named "SwordTrail" inside the tool (if present)
    local swordTrail = nil
    local trailRunning = false
    do
        local ok, t = pcall(function() return tool:FindFirstChild("SwordTrail", true) end)
        if ok and t and t:IsA("Trail") then
            swordTrail = t
            pcall(function() swordTrail.Enabled = false end)
        end
    end

    -- schedule the SwordTrail to be enabled only during a specific swing window
    -- defaults target the downswing: 0.22s -> 0.36s (relative to swing start)
    local function triggerSwordTrailWindow(startOffset, endOffset)
        if not swordTrail then return end
        if not startOffset then startOffset = 0.22 end
        if not endOffset then endOffset = 0.36 end
        if endOffset <= startOffset then
            -- fallback short pulse
            startOffset = 0
            endOffset = math.min(0.28, startOffset + 0.28)
        end

        local duration = endOffset - startOffset
        -- ENCHANT SYSTEM: use enchant color for trail if weapon has an enchant
        local trailColorStart = Color3.fromRGB(240, 240, 240)
        local trailColorEnd   = Color3.fromRGB(190, 190, 190)
        if WeaponEnchantConfig and tool:GetAttribute("HasEnchant") then
            local pn = tool:GetAttribute("EnchantName")
            if pn and pn ~= "" then
                local enchantColor = WeaponEnchantConfig.GetTrailColorForEnchant(pn)
                if enchantColor then
                    trailColorStart = Color3.new(
                        math.min(enchantColor.R * 1.2, 1),
                        math.min(enchantColor.G * 1.2, 1),
                        math.min(enchantColor.B * 1.2, 1)
                    )
                    trailColorEnd = enchantColor
                end
            end
        end
        -- configure trail appearance
        pcall(function()
            swordTrail.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, trailColorStart),
                ColorSequenceKeypoint.new(0.4, trailColorEnd),
                ColorSequenceKeypoint.new(1, trailColorEnd),
            })
            -- Enchant trails are much more visible; non-Enchant trails keep a subtler look
            local hasEnchantTrail = WeaponEnchantConfig and tool:GetAttribute("HasEnchant")
            if hasEnchantTrail then
                swordTrail.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.1),
                    NumberSequenceKeypoint.new(0.3, 0.25),
                    NumberSequenceKeypoint.new(0.7, 0.6),
                    NumberSequenceKeypoint.new(1, 1),
                })
                swordTrail.LightEmission = 0.8
                swordTrail.LightInfluence = 0
            else
                swordTrail.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.6),
                    NumberSequenceKeypoint.new(0.5, 0.8),
                    NumberSequenceKeypoint.new(1, 1),
                })
            end
            swordTrail.Lifetime = math.max(0.14, duration)
            swordTrail.MinLength = 0
            swordTrail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.15), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 0.2)})
            swordTrail.FaceCamera = false
        end)

        -- schedule enable/disable relative to swing start
        spawn(function()
            task.wait(startOffset)
            pcall(function() swordTrail.Enabled = true end)
            task.wait(duration)
            pcall(function() swordTrail.Enabled = false end)
        end)
    end

    local cfg = getCfg(tool)

    --------------------------------------------------------------------------
    -- COMBO SYSTEM CONFIG
    -- Pulled from ToolMeleeSettings.comboConfig so tuning is centralized.
    --------------------------------------------------------------------------
    local comboCfg       = MeleeCfgModule and MeleeCfgModule.comboConfig or {}
    local COMBO_WINDOW   = comboCfg.COMBO_WINDOW or 0.2
    local ATTACK_CDS     = comboCfg.ATTACK_COOLDOWNS or { 0.5, 0.5, 0.8 }
    -- Weapons with 3+ swing_anim_ids use the combo chain; others keep flat cd.
    local hasCombo = cfg.swing_anim_ids and type(cfg.swing_anim_ids) == "table"
        and #cfg.swing_anim_ids >= 3

    --------------------------------------------------------------------------
    -- COMBO STATE
    --------------------------------------------------------------------------
    local currentComboStep = 1   -- 1-based (Attack1, Attack2, Attack3)
    local comboExpireTime  = 0   -- tick() deadline; combo resets to 1 after this
    local isSwinging       = false
    local lastAttackTime   = 0
    local lastStepCooldown = 0   -- cooldown of the step that set lastAttackTime
    local bufferedClick    = false

    local function getStepCooldown(step)
        if not hasCombo then return cfg.cd or 0.5 end
        return ATTACK_CDS[step] or ATTACK_CDS[1] or 0.5
    end

    local function resetCombo()
        currentComboStep = 1
        comboExpireTime  = 0
        bufferedClick    = false
        lastStepCooldown = 0
    end

    --------------------------------------------------------------------------
    -- INPUT & SWING  (combo-aware)
    --------------------------------------------------------------------------
    local mouse     = player:GetMouse()
    local mouseConns = {}

    local function executeAttack()
        -- Cancel if bandaging
        if _G.IsBandaging then return end

        -- Buffer click if a swing is already active
        if isSwinging then
            bufferedClick = true
            return
        end

        local now = tick()

        -- Check combo window — if expired, reset to Attack1
        if comboExpireTime > 0 and now > comboExpireTime then
            resetCombo()
        end

        local step        = currentComboStep
        local stepCooldown = getStepCooldown(step)

        -- Size scaling: scale cooldown by weapon size
        local sizePercent   = getToolSizePercent(tool)
        local sizeSpeedMult = getSizeSpeedMultiplier(sizePercent)
        local scaledStepCd  = stepCooldown * sizeSpeedMult

        -- Rate-limit: use the cooldown of the PREVIOUS step (the one that
        -- set lastAttackTime), not the upcoming step.  This prevents
        -- Attack3 (0.8s cd) from blocking a chain that follows Attack2 (0.5s cd).
        local enforcedCd = lastStepCooldown > 0 and lastStepCooldown or scaledStepCd
        if now - lastAttackTime < enforcedCd * 0.85 then return end

        -- Lock swing
        isSwinging     = true
        bufferedClick  = false
        lastAttackTime = now
        lastStepCooldown = scaledStepCd

        -- Force animation index to match combo step
        if hasCombo then
            swingCycleIndex[tool.Name or "_default"] = step
        end

        -- Debug hitbox visual (unchanged logic, per-step cooldown aware)
        local showGlobal = false
        local globalVal = ReplicatedStorage:FindFirstChild("ToolMeleeShowHitbox")
        if globalVal and globalVal:IsA("BoolValue") then showGlobal = globalVal.Value end
        local wantDebug = (cfg.showHitbox == true) or showGlobal
        if wantDebug then
            local hd = (cfg.hitboxDelay or 0.35) * sizeSpeedMult
            local ha = (cfg.hitboxActive or 0.1) * sizeSpeedMult
            local color = cfg.hitboxColor or Color3.fromRGB(255, 50, 50)
            spawn(function()
                task.wait(hd)
                local startTime = tick()
                local boxSize = cfg.hitboxSize or Vector3.new(4, 3, 7)
                local offset = cfg.hitboxOffset or Vector3.new(0, 1, boxSize.Z * 0.5)
                local part = workspace:FindFirstChild("_MeleeHitboxDebug")
                if not part or not part:IsA("BasePart") then
                    part = Instance.new("Part")
                    part.Name = "_MeleeHitboxDebug"
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = 0.6
                    part.Size = boxSize
                    part.Color = color
                    part.Material = Enum.Material.Neon
                    part.Parent = workspace
                end
                local conn
                conn = RunService.Heartbeat:Connect(function()
                    if not part or not part.Parent then
                        if conn then conn:Disconnect() end
                        return
                    end
                    if tick() - startTime > ha then
                        if conn then conn:Disconnect() end
                        if part and part.Parent then part:Destroy() end
                        return
                    end
                    local char = player.Character
                    if not char then return end
                    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                    if not hrp then return end
                    local rightV = hrp.CFrame.RightVector
                    local upV = hrp.CFrame.UpVector
                    local lookV = hrp.CFrame.LookVector
                    local pos = hrp.Position + rightV * offset.X + upV * offset.Y + lookV * offset.Z
                    local boxCFrame = CFrame.new(pos, pos + lookV)
                    if part.Size ~= boxSize then part.Size = boxSize end
                    if part.Color ~= color then part.Color = color end
                    part.CFrame = boxCFrame
                end)
            end)
        end

        -- Trigger sword trail (size-scaled timing)
        -- First attack uses later timing (0.26-0.44) so trail aligns with animation
        local trailStart = cfg.trail_start or 0.22
        local trailEnd   = cfg.trail_end   or 0.36
        if step == 1 then
            trailStart = cfg.trail_start or 0.26
            trailEnd   = cfg.trail_end   or 0.44
        end
        local startOffset = trailStart * sizeSpeedMult
        local endOffset   = trailEnd   * sizeSpeedMult
        pcall(function() triggerSwordTrailWindow(startOffset, endOffset) end)

        -- Tell the server we swung (include combo step for validation/damage)
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                swingEvent:FireServer(tool.Name, hrp.CFrame.LookVector, step)
            end
        end

        -- Play local animation for immediate feedback (size-scaled duration)
        local playedAnim = nil
        pcall(function() playedAnim = playLocalCfgAnimation(cfg, tool.Name, scaledStepCd, stepCooldown) end)
        if not playedAnim then
            playSwingVisual(tool)
        end

        -- Hotbar cooldown overlay (slot 1 = Melee)
        if _G.HotbarCooldown then
            _G.HotbarCooldown.start(1, scaledStepCd)
        end

        -- Advance or reset combo, then schedule cooldown end
        local nextStep = (step >= 3) and 1 or (step + 1)

        task.delay(scaledStepCd, function()
            isSwinging = false

            if step >= 3 then
                -- Attack3 finished: hard reset, no combo chain allowed
                resetCombo()
            else
                -- Open the combo chain window for the next step
                currentComboStep = nextStep
                comboExpireTime  = tick() + COMBO_WINDOW
            end

            -- Process buffered click if still within the combo window
            if bufferedClick then
                bufferedClick = false
                -- Only auto-advance; don't start a new Attack1 from buffer
                -- to stop spam-clicking from bypassing the Attack3 recovery.
                if currentComboStep > 1 and tick() <= comboExpireTime then
                    task.defer(executeAttack)
                end
            end
        end)
    end

    tool.Equipped:Connect(function()
        -- Always start fresh at Attack1 on equip
        resetCombo()
        isSwinging     = false
        lastAttackTime = 0
        table.insert(mouseConns, mouse.Button1Down:Connect(executeAttack))
    end)

    tool.Unequipped:Connect(function()
        -- Full reset on unequip / death / weapon switch
        resetCombo()
        isSwinging     = false
        lastAttackTime = 0
        for _, c in ipairs(mouseConns) do c:Disconnect() end
        mouseConns = {}
    end)
end

--------------------------------------------------------------------------------
-- Hit feedback from server
--------------------------------------------------------------------------------
meleeHitEvent.OnClientEvent:Connect(function(damage, isHeadshot, hitPart, hitPos)
    playMeleeSound("hit") -- generic fallback; server can send tool-specific later
    spawn(function()
        showDamagePopup(damage, isHeadshot, hitPart, hitPos)
    end)
end)

--------------------------------------------------------------------------------
-- ENCHANT PROC DAMAGE POPUP
-- Listens for EnchantProcHit from server. Shows a colored damage number
-- offset above the normal damage numbers so they're visually distinct.
--------------------------------------------------------------------------------
local enchantProcEvent = ReplicatedStorage:FindFirstChild("EnchantProcHit")
if not enchantProcEvent then
    -- Server may not have created it yet; wait briefly
    enchantProcEvent = ReplicatedStorage:WaitForChild("EnchantProcHit", 10)
end

if enchantProcEvent then
    enchantProcEvent.OnClientEvent:Connect(function(damage, enchantName, torsoPart)
        spawn(function()
            if not damage or not enchantName then return end

            -- Resolve enchant color
            local enchantColor = Color3.fromRGB(255, 255, 255)
            if WeaponEnchantConfig then
                local c = WeaponEnchantConfig.GetColorForEnchant(enchantName)
                if c then enchantColor = c end
            end

            -- Adorn to the target's torso part; fall back to anchored part if needed
            local parentPart
            local anchor
            if torsoPart and typeof(torsoPart) == "Instance" and torsoPart:IsA("BasePart") then
                parentPart = torsoPart
            elseif torsoPart and typeof(torsoPart) == "Vector3" then
                -- Legacy fallback: if a position was sent instead of a part
                anchor = Instance.new("Part")
                anchor.Name = "_EnchantProcAnchor"
                anchor.Size = Vector3.new(0.2, 0.2, 0.2)
                anchor.Transparency = 1
                anchor.Anchored = true
                anchor.CanCollide = false
                anchor.CFrame = CFrame.new(torsoPart)
                anchor.Parent = workspace
                parentPart = anchor
            end
            if not parentPart then return end

            local gui = Instance.new("BillboardGui")
            gui.Name = "EnchantProcPopup"
            gui.Size = UDim2.new(0, 120, 0, 40)
            gui.Adornee = parentPart
            gui.AlwaysOnTop = true
            gui.StudsOffset = Vector3.new(0, 3, 0) -- offset above torso

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Text = tostring(math.floor(damage))
            label.Font = Enum.Font.GothamBold
            label.TextSize = 20
            label.TextColor3 = enchantColor
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextStrokeTransparency = 0.4
            label.Parent = gui
            gui.Parent = parentPart

            local tween = TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
                StudsOffset = gui.StudsOffset + Vector3.new(0, 1.5, 0),
            })
            tween:Play()
            for i = 0, 1, 0.06 do
                label.TextTransparency = i
                label.TextStrokeTransparency = 0.4 + i * 0.6
                task.wait(0.06)
            end
            tween:Cancel()
            gui:Destroy()
            if anchor and anchor.Parent then anchor:Destroy() end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Scan & watch for melee tools (same pattern as ToolGun.client)
--------------------------------------------------------------------------------
local function scanAndAttach()
    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do attachMelee(child) end
    end
    if player.Character then
        for _, child in ipairs(player.Character:GetChildren()) do attachMelee(child) end
    end
end

scanAndAttach()

player.Backpack.ChildAdded:Connect(function(child) attachMelee(child) end)
player.CharacterAdded:Connect(function(char)
    scanAndAttach()
    char.ChildAdded:Connect(function(child) attachMelee(child) end)
end)

print("[ToolMelee.client] running for", player and player.Name)
