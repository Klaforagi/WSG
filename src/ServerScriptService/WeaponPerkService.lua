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
local PERK_ATTACH_NAME  = "PerkAttachment"
local PERK_LIGHT_NAME   = "PerkPointLight"

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

    ----------------------------------------------------------------------------
    -- 1) AURA EMITTER — soft colored glow around the weapon
    ----------------------------------------------------------------------------
    local aura = Instance.new("ParticleEmitter")
    aura.Name = PERK_AURA_NAME

    -- Appearance
    aura.Color = ColorSequence.new(color)
    aura.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(0.5, 0.35),
        NumberSequenceKeypoint.new(1, 0.05),
    })
    aura.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.4, 0.65),
        NumberSequenceKeypoint.new(1, 1),
    })
    aura.LightEmission = 0.6
    aura.LightInfluence = 0

    -- Emission
    aura.Rate = 6
    aura.Lifetime = NumberRange.new(0.4, 0.8)
    aura.Speed = NumberRange.new(0.2, 0.5)
    aura.SpreadAngle = Vector2.new(180, 180)  -- emit in all directions (aura)

    -- Behaviour
    aura.Drag = 2
    aura.LockedToPart = false
    aura.RotSpeed = NumberRange.new(-30, 30)
    aura.Rotation = NumberRange.new(0, 360)

    -- Use default Roblox particle texture (no custom asset needed)
    -- The default texture is a soft circle which works well for glow.

    aura.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 2) SPARK EMITTER — occasional tiny bright flecks
    ----------------------------------------------------------------------------
    local spark = Instance.new("ParticleEmitter")
    spark.Name = PERK_SPARK_NAME

    spark.Color = ColorSequence.new(color)
    spark.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 0),
    })
    spark.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    spark.LightEmission = 1
    spark.LightInfluence = 0

    spark.Rate = 2
    spark.Lifetime = NumberRange.new(0.2, 0.5)
    spark.Speed = NumberRange.new(0.5, 1.5)
    spark.SpreadAngle = Vector2.new(180, 180)
    spark.Drag = 3
    spark.LockedToPart = false

    spark.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 3) POINT LIGHT — subtle glow on nearby surfaces
    ----------------------------------------------------------------------------
    local light = Instance.new("PointLight")
    light.Name = PERK_LIGHT_NAME
    light.Color = color
    light.Brightness = 0.4
    light.Range = 4
    light.Shadows = false
    light.Parent = attachPart

    ----------------------------------------------------------------------------
    -- 4) SWORD TRAIL RECOLOR
    ----------------------------------------------------------------------------
    local trail = tool:FindFirstChild("SwordTrail", true)
    if trail and trail:IsA("Trail") then
        -- Slightly brighten the start, fade toward perk color
        local brightened = Color3.new(
            math.min(color.R * 1.2, 1),
            math.min(color.G * 1.2, 1),
            math.min(color.B * 1.2, 1)
        )
        pcall(function()
            trail.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, brightened),
                ColorSequenceKeypoint.new(1, color),
            })
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

    -- Burst emitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "PerkHitBurst"

    emitter.Color = ColorSequence.new(color)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.LightEmission = 0.8
    emitter.LightInfluence = 0

    emitter.Lifetime = NumberRange.new(0.15, 0.35)
    emitter.Speed = NumberRange.new(3, 8)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Drag = 4
    emitter.Rate = 0  -- we use :Emit() for a one-shot burst

    emitter.RotSpeed = NumberRange.new(-90, 90)
    emitter.Rotation = NumberRange.new(0, 360)

    emitter.Parent = anchor

    -- Emit a short burst
    emitter:Emit(10)

    -- Clean up after particles have died
    Debris:AddItem(anchor, 0.6)
end

return WeaponPerkService
