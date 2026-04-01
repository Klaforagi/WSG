--------------------------------------------------------------------------------
-- WeaponPerkService.lua  –  Server module: perk visual application & hit FX
--
-- Responsible for:
--   • Setting perk attributes on Tool instances
--   • Creating / removing aura ParticleEmitters on the weapon
--   • Recoloring the existing SwordTrail
--   • Spawning short hit-burst particles at confirmed hit locations
--
-- All perk-created instances are named with a "Perk" prefix so cleanup
-- can distinguish them from normal weapon children.
--
-- USAGE (server only):
--   local PerkService = require(path.to.WeaponPerkService)
--   PerkService.RollAndAssignPerk(tool, instanceData)
--   PerkService.ApplyPerkVisuals(tool)
--   PerkService.ClearPerkVisuals(tool)
--   PerkService.SpawnHitEffect(hitPosition, perkName)
--   PerkService.GetPerkDataFromTool(tool)
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local WeaponPerkConfig = require(ReplicatedStorage:WaitForChild("WeaponPerkConfig"))

local WeaponPerkService = {}

-- Names used for perk-created instances (cleanup searches for these)
local PERK_AURA_NAME    = "PerkAuraEmitter"
local PERK_SPARK_NAME   = "PerkSparkEmitter"
local PERK_GLOW_NAME    = "PerkGlowEmitter"
local PERK_ATTACH_NAME  = "PerkAttachment"
local PERK_LIGHT_NAME   = "PerkPointLight"

-- Roblox built-in soft-glow particle texture (a round feathered circle)
local SOFT_GLOW_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local STAR_TEXTURE      = "rbxasset://textures/particles/fire_main.dds"

--------------------------------------------------------------------------------
-- INTERNAL: find the best BasePart to attach visuals to
--------------------------------------------------------------------------------
local function findAttachPart(tool)
    if not tool then return nil end
    -- Prefer Handle (standard Tool convention)
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end
    -- Fallback: any BasePart directly under the tool
    for _, child in ipairs(tool:GetChildren()) do
        if child:IsA("BasePart") then return child end
    end
    -- Deep search
    return tool:FindFirstChildWhichIsA("BasePart", true)
end

--------------------------------------------------------------------------------
-- CLEAR PERK VISUALS
-- Removes all perk-owned instances from a tool. Safe to call even if the
-- tool has no perk.  Does NOT remove non-perk children.
--------------------------------------------------------------------------------
function WeaponPerkService.ClearPerkVisuals(tool)
    if not tool then return end
    for _, desc in ipairs(tool:GetDescendants()) do
        if desc and desc.Name == PERK_AURA_NAME
            or desc.Name == PERK_SPARK_NAME
            or desc.Name == PERK_GLOW_NAME
            or desc.Name == PERK_ATTACH_NAME
            or desc.Name == PERK_LIGHT_NAME then
            pcall(function() desc:Destroy() end)
        end
    end
    -- Restore SwordTrail to default white/gray if it exists
    local trail = tool:FindFirstChild("SwordTrail", true)
    if trail and trail:IsA("Trail") then
        pcall(function()
            trail.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 240, 240)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
            })
        end)
    end
end

--------------------------------------------------------------------------------
-- APPLY PERK VISUALS
-- Reads HasPerk / PerkName attributes from the tool and creates:
--   1. A colored aura ParticleEmitter on the weapon handle
--   2. A subtle spark emitter for extra flair
--   3. A dim PointLight for glow ambiance
--   4. Recolors the existing SwordTrail
-- Removes prior perk visuals first to prevent stacking.
--------------------------------------------------------------------------------
function WeaponPerkService.ApplyPerkVisuals(tool)
    if not tool then return end

    local hasPerk  = tool:GetAttribute("HasPerk")
    local perkName = tool:GetAttribute("PerkName")
    if not hasPerk or not perkName or perkName == "" then return end

    local perkData = WeaponPerkConfig.GetPerkData(perkName)
    if not perkData then
        warn("[WeaponPerkService] Unknown perk '" .. tostring(perkName) .. "', skipping visuals")
        return
    end

    local attachPart = findAttachPart(tool)
    if not attachPart then
        warn("[WeaponPerkService] No BasePart found on tool '" .. tool.Name .. "', skipping visuals")
        return
    end

    -- Clean up any prior perk visuals
    WeaponPerkService.ClearPerkVisuals(tool)

    local color = perkData.color

    -- Derive a brighter variant for accent highlights
    local h, s, v = Color3.toHSV(color)
    local brightColor = Color3.fromHSV(h, math.clamp(s * 0.6, 0, 1), math.clamp(v * 1.3, 0, 1))

    -- Read weapon size scale for adaptive emitter tuning. Bigger weapons get
    -- slightly more particles to keep the aura proportional.
    local sizePct = tool:GetAttribute("SizePercent") or 100
    local scaleMult = math.clamp(sizePct / 100, 0.7, 2.0)

    ----------------------------------------------------------------------------
    -- 1) CORE AURA EMITTER — constant medium-density energy hugging the weapon
    --    Creates the "infused weapon" baseline look.
    ----------------------------------------------------------------------------
    local aura = Instance.new("ParticleEmitter")
    aura.Name = PERK_AURA_NAME
    aura.Texture = SOFT_GLOW_TEXTURE

    aura.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, brightColor),
        ColorSequenceKeypoint.new(0.5, color),
        ColorSequenceKeypoint.new(1, color),
    })
    aura.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.08 * scaleMult),
        NumberSequenceKeypoint.new(0.3, 0.28 * scaleMult),
        NumberSequenceKeypoint.new(0.7, 0.22 * scaleMult),
        NumberSequenceKeypoint.new(1, 0),
    })
    aura.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(0.3, 0.35),
        NumberSequenceKeypoint.new(0.7, 0.55),
        NumberSequenceKeypoint.new(1, 1),
    })
    aura.LightEmission = 0.85
    aura.LightInfluence = 0

    aura.Rate = math.floor(18 * scaleMult)
    aura.Lifetime = NumberRange.new(0.35, 0.7)
    aura.Speed = NumberRange.new(0.15, 0.6)
    aura.SpreadAngle = Vector2.new(180, 180)

    aura.Drag = 3
    aura.LockedToPart = false
    aura.RotSpeed = NumberRange.new(-60, 60)
    aura.Rotation = NumberRange.new(0, 360)
    aura.ZOffset = -0.1

    aura.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 2) ACCENT SPARK EMITTER — brighter, faster little motes for energy feel
    --    Adds motion and sparkle so the weapon doesn't look static.
    ----------------------------------------------------------------------------
    local spark = Instance.new("ParticleEmitter")
    spark.Name = PERK_SPARK_NAME
    spark.Texture = STAR_TEXTURE

    spark.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, brightColor),
        ColorSequenceKeypoint.new(1, color),
    })
    spark.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.12 * scaleMult),
        NumberSequenceKeypoint.new(0.5, 0.06 * scaleMult),
        NumberSequenceKeypoint.new(1, 0),
    })
    spark.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.4, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    spark.LightEmission = 1
    spark.LightInfluence = 0

    spark.Rate = math.floor(10 * scaleMult)
    spark.Lifetime = NumberRange.new(0.2, 0.45)
    spark.Speed = NumberRange.new(0.6, 2.0)
    spark.SpreadAngle = Vector2.new(180, 180)
    spark.Drag = 5
    spark.LockedToPart = false
    spark.RotSpeed = NumberRange.new(-120, 120)
    spark.Rotation = NumberRange.new(0, 360)
    spark.ZOffset = 0.05

    spark.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 3) GLOW PULSE EMITTER — few larger soft particles for aura fullness
    --    Very low count, makes the overall effect feel richer and more magical.
    ----------------------------------------------------------------------------
    local glow = Instance.new("ParticleEmitter")
    glow.Name = PERK_GLOW_NAME
    glow.Texture = SOFT_GLOW_TEXTURE

    glow.Color = ColorSequence.new(color)
    glow.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15 * scaleMult),
        NumberSequenceKeypoint.new(0.5, 0.55 * scaleMult),
        NumberSequenceKeypoint.new(1, 0.3 * scaleMult),
    })
    glow.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(0.4, 0.45),
        NumberSequenceKeypoint.new(1, 1),
    })
    glow.LightEmission = 0.7
    glow.LightInfluence = 0

    glow.Rate = math.floor(4 * scaleMult)
    glow.Lifetime = NumberRange.new(0.5, 0.9)
    glow.Speed = NumberRange.new(0.05, 0.2)
    glow.SpreadAngle = Vector2.new(180, 180)
    glow.Drag = 1
    glow.LockedToPart = true
    glow.RotSpeed = NumberRange.new(-20, 20)
    glow.Rotation = NumberRange.new(0, 360)
    glow.ZOffset = -0.2

    glow.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 4) POINT LIGHT — stronger glow on nearby surfaces
    ----------------------------------------------------------------------------
    local light = Instance.new("PointLight")
    light.Name = PERK_LIGHT_NAME
    light.Color = color
    light.Brightness = 0.8
    light.Range = 6
    light.Shadows = false
    light.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 5) SWORD TRAIL RECOLOR — more vivid, less transparent
    ----------------------------------------------------------------------------
    local trail = tool:FindFirstChild("SwordTrail", true)
    if trail and trail:IsA("Trail") then
        pcall(function()
            trail.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, brightColor),
                ColorSequenceKeypoint.new(0.4, color),
                ColorSequenceKeypoint.new(1, color),
            })
            trail.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.15),
                NumberSequenceKeypoint.new(0.5, 0.4),
                NumberSequenceKeypoint.new(1, 0.9),
            })
            trail.LightEmission = 0.8
            trail.LightInfluence = 0
        end)
    end
end

--------------------------------------------------------------------------------
-- ROLL AND ASSIGN PERK
-- Performs the 20% perk roll and writes attributes onto the tool.
-- `instanceData` is optional; if provided, perkName is also written to it
-- so it persists in the DataStore.
-- Returns perkName (string or nil).
--------------------------------------------------------------------------------
function WeaponPerkService.RollAndAssignPerk(tool, instanceData)
    if not tool then return nil end

    local perkName = WeaponPerkConfig.RollPerk()

    if perkName then
        tool:SetAttribute("HasPerk", true)
        tool:SetAttribute("PerkName", perkName)

        local perkData = WeaponPerkConfig.GetPerkData(perkName)
        if perkData then
            -- Store hex color for easy UI reading later
            local c = perkData.color
            tool:SetAttribute("PerkColorHex", string.format("#%02X%02X%02X",
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5)))
        end
    else
        tool:SetAttribute("HasPerk", false)
        tool:SetAttribute("PerkName", "")
    end

    -- Persist to instance data if provided
    if instanceData then
        instanceData.perkName = perkName or ""
    end

    return perkName
end

--------------------------------------------------------------------------------
-- APPLY PERK FROM INSTANCE DATA
-- Sets attributes on a tool clone based on stored instance data, then applies
-- visuals.  Used by Loadout.server when granting a tool that already has a
-- perk rolled from the crate.
-- instanceData = { ..., perkName = "Fiery" }
--------------------------------------------------------------------------------
function WeaponPerkService.ApplyPerkFromInstance(tool, instanceData)
    if not tool or not instanceData then return end

    local perkName = instanceData.perkName
    if type(perkName) ~= "string" or perkName == "" then
        tool:SetAttribute("HasPerk", false)
        tool:SetAttribute("PerkName", "")
        return
    end

    local perkData = WeaponPerkConfig.GetPerkData(perkName)
    if not perkData then
        tool:SetAttribute("HasPerk", false)
        tool:SetAttribute("PerkName", "")
        return
    end

    tool:SetAttribute("HasPerk", true)
    tool:SetAttribute("PerkName", perkName)

    local c = perkData.color
    tool:SetAttribute("PerkColorHex", string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5)))

    WeaponPerkService.ApplyPerkVisuals(tool)
end

--------------------------------------------------------------------------------
-- GET PERK DATA FROM TOOL
-- Reads perk attributes and returns { hasPerk, perkName, perkData } or nil.
--------------------------------------------------------------------------------
function WeaponPerkService.GetPerkDataFromTool(tool)
    if not tool then return nil end
    local hasPerk  = tool:GetAttribute("HasPerk")
    local perkName = tool:GetAttribute("PerkName")
    if not hasPerk or not perkName or perkName == "" then
        return { hasPerk = false, perkName = nil, perkData = nil }
    end
    return {
        hasPerk  = true,
        perkName = perkName,
        perkData = WeaponPerkConfig.GetPerkData(perkName),
    }
end

--------------------------------------------------------------------------------
-- SPAWN HIT EFFECT
-- Creates a brief burst of colored particles at the hit position.
-- Cleans up automatically via Debris. Safe to call from server.
--
-- hitPosition : Vector3 – world position of the hit
-- perkName    : string  – which perk to color the burst
-- hitPart     : BasePart (optional) – if provided, attach to it instead
--------------------------------------------------------------------------------
function WeaponPerkService.SpawnHitEffect(hitPosition, perkName, hitPart)
    if not hitPosition or typeof(hitPosition) ~= "Vector3" then return end

    local perkData = WeaponPerkConfig.GetPerkData(perkName)
    if not perkData then return end

    local color = perkData.color
    local h, s, v = Color3.toHSV(color)
    local brightColor = Color3.fromHSV(h, math.clamp(s * 0.5, 0, 1), math.clamp(v * 1.3, 0, 1))

    -- Create a tiny invisible anchored part at the hit location
    local anchor = Instance.new("Part")
    anchor.Name = "_PerkHitFX"
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.CFrame = CFrame.new(hitPosition)
    anchor.Parent = workspace

    -- Primary impact burst — bright fast outward flash
    local burst = Instance.new("ParticleEmitter")
    burst.Name = "PerkHitBurst"
    burst.Texture = SOFT_GLOW_TEXTURE

    burst.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, brightColor),
        ColorSequenceKeypoint.new(0.5, color),
        ColorSequenceKeypoint.new(1, color),
    })
    burst.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.3, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    burst.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.3, 0.2),
        NumberSequenceKeypoint.new(0.7, 0.6),
        NumberSequenceKeypoint.new(1, 1),
    })
    burst.LightEmission = 1
    burst.LightInfluence = 0

    burst.Lifetime = NumberRange.new(0.15, 0.35)
    burst.Speed = NumberRange.new(5, 14)
    burst.SpreadAngle = Vector2.new(180, 180)
    burst.Drag = 6
    burst.Rate = 0

    burst.RotSpeed = NumberRange.new(-180, 180)
    burst.Rotation = NumberRange.new(0, 360)

    burst.Parent = anchor
    burst:Emit(18)

    -- Secondary flash — a few larger soft particles for impact fullness
    local flash = Instance.new("ParticleEmitter")
    flash.Name = "PerkHitFlash"
    flash.Texture = SOFT_GLOW_TEXTURE

    flash.Color = ColorSequence.new(brightColor)
    flash.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(1, 0.1),
    })
    flash.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    flash.LightEmission = 1
    flash.LightInfluence = 0

    flash.Lifetime = NumberRange.new(0.1, 0.2)
    flash.Speed = NumberRange.new(1, 4)
    flash.SpreadAngle = Vector2.new(180, 180)
    flash.Drag = 3
    flash.Rate = 0

    flash.Parent = anchor
    flash:Emit(5)

    -- Clean up after particles have fully died
    Debris:AddItem(anchor, 0.8)
end

return WeaponPerkService
