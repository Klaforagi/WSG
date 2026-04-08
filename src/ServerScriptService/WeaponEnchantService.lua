--------------------------------------------------------------------------------
-- WeaponEnchantService.lua  –  Server module: enchant visual application & hit FX
--
-- Responsible for:
--   • Setting enchant attributes on Tool instances
--   • Cloning manual enchant visual assets from ReplicatedStorage.Enchants
--     and parenting them under Handle.EnchantBlock
--   • Recoloring the existing SwordTrail
--   • Spawning short hit-burst particles at confirmed hit locations
--
-- Enchant visuals are cloned from ReplicatedStorage.Enchants, NOT generated
-- in code. Each cloned asset is renamed with the prefix "ActiveEnchantEffect_"
-- so cleanup can reliably distinguish them from normal weapon children.
--
-- USAGE (server only):
--   local EnchantService = require(path.to.WeaponEnchantService)
--   EnchantService.RollAndAssignEnchant(tool, instanceData)
--   EnchantService.ApplyEnchantVisuals(tool)
--   EnchantService.ClearEnchantVisuals(tool)
--   EnchantService.SpawnHitEffect(hitPosition, enchantName)
--   EnchantService.GetEnchantDataFromTool(tool)
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local WeaponEnchantConfig = require(ReplicatedStorage:WaitForChild("WeaponEnchantConfig"))

local WeaponEnchantService = {}

-- Prefix applied to all cloned enchant effect instances for safe cleanup
local ENCHANT_EFFECT_PREFIX = "ActiveEnchantEffect_"

-- Legacy names from old code-generated particle system (cleaned up if found)
local LEGACY_NAMES = {
    "EnchantAuraEmitter",
    "EnchantSparkEmitter",
    "EnchantGlowEmitter",
    "EnchantAttachment",
    "EnchantPointLight",
}

-- Folder containing manually built enchant visual assets
local EnchantsFolder = ReplicatedStorage:FindFirstChild("Enchants")
if not EnchantsFolder then
    warn("[WeaponEnchantService] ReplicatedStorage.Enchants folder not found — enchant visuals will not apply")
end

-- Roblox built-in soft-glow particle texture (used only by SpawnHitEffect)
local SOFT_GLOW_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

--------------------------------------------------------------------------------
-- INTERNAL: get the asset name(s) to clone for a given enchant
-- Shock is special: requires both ShockA and ShockB.
-- All others use a single asset matching the enchant name.
--------------------------------------------------------------------------------
local function getAssetNames(enchantName)
    if enchantName == "Shock" then
        return { "ShockA", "ShockB" }
    end
    return { enchantName }
end

--------------------------------------------------------------------------------
-- CLEAR ENCHANT VISUALS
-- Removes all enchant-owned cloned visuals from Handle.EnchantBlock.
-- Also removes any legacy code-generated enchant instances that may still exist.
-- Safe to call even if the tool has no enchant.
-- Does NOT remove SwordTrail, Handle, meshes, welds, or unrelated content.
--------------------------------------------------------------------------------
function WeaponEnchantService.ClearEnchantVisuals(tool)
    if not tool then return end

    local handle = tool:FindFirstChild("Handle")

    -- Clean up active enchant effect clones from EnchantBlock
    if handle then
        local enchantBlock = handle:FindFirstChild("EnchantBlock")
        if enchantBlock then
            for _, child in ipairs(enchantBlock:GetChildren()) do
                if child.Name:sub(1, #ENCHANT_EFFECT_PREFIX) == ENCHANT_EFFECT_PREFIX then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end

    -- Clean up any legacy code-generated enchant instances anywhere in the tool
    for _, desc in ipairs(tool:GetDescendants()) do
        for _, legacyName in ipairs(LEGACY_NAMES) do
            if desc and desc.Name == legacyName then
                pcall(function() desc:Destroy() end)
                break
            end
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
-- APPLY ENCHANT VISUALS
-- Reads HasEnchant / EnchantName attributes from the tool, then:
--   1. Clears any prior enchant visuals
--   2. Clones the correct enchant asset(s) from ReplicatedStorage.Enchants
--   3. Parents them under Handle.EnchantBlock
--   4. Recolors the existing SwordTrail to match the enchant color
-- NO particles are generated in code — all visuals come from manual assets.
--------------------------------------------------------------------------------
function WeaponEnchantService.ApplyEnchantVisuals(tool)
    if not tool then return end

    local hasEnchant  = tool:GetAttribute("HasEnchant")
    local enchantName = tool:GetAttribute("EnchantName")
    if not hasEnchant or not enchantName or enchantName == "" then
        WeaponEnchantService.ClearEnchantVisuals(tool)
        return
    end

    local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not enchantData then
        warn("[WeaponEnchantService] Unknown enchant '" .. tostring(enchantName) .. "', skipping visuals")
        return
    end

    local handle = tool:FindFirstChild("Handle")
    if not handle then
        warn("[WeaponEnchantService] Handle not found on tool '" .. tool.Name .. "', skipping visuals")
        return
    end

    local enchantBlock = handle:FindFirstChild("EnchantBlock")
    if not enchantBlock then
        warn("[WeaponEnchantService] Handle.EnchantBlock not found on tool '" .. tool.Name .. "', skipping visuals")
        return
    end

    if not EnchantsFolder then
        warn("[WeaponEnchantService] ReplicatedStorage.Enchants folder missing, cannot apply visuals")
        return
    end

    -- Clean up any prior enchant visuals
    WeaponEnchantService.ClearEnchantVisuals(tool)

    -- Clone the correct asset(s) into EnchantBlock
    local assetNames = getAssetNames(enchantName)
    for _, assetName in ipairs(assetNames) do
        local assetTemplate = EnchantsFolder:FindFirstChild(assetName)
        if assetTemplate then
            local clone = assetTemplate:Clone()
            clone.Name = ENCHANT_EFFECT_PREFIX .. assetName
            clone.Parent = enchantBlock
        else
            warn("[WeaponEnchantService] Asset '" .. assetName .. "' not found in ReplicatedStorage.Enchants")
        end
    end

    -- Recolor the SwordTrail to match the enchant
    local color = enchantData.color
    local h, s, v = Color3.toHSV(color)
    local brightColor = Color3.fromHSV(h, math.clamp(s * 0.6, 0, 1), math.clamp(v * 1.3, 0, 1))

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
                NumberSequenceKeypoint.new(0.3, 0.3),
                NumberSequenceKeypoint.new(0.7, 0.65),
                NumberSequenceKeypoint.new(1, 1),
            })
            trail.LightEmission = 0.8
            trail.LightInfluence = 0
        end)
    end
end

--------------------------------------------------------------------------------
-- ROLL AND ASSIGN ENCHANT
-- Performs the 20% enchant roll and writes attributes onto the tool.
-- `instanceData` is optional; if provided, enchantName is also written to it
-- so it persists in the DataStore.
-- Returns enchantName (string or nil).
--------------------------------------------------------------------------------
function WeaponEnchantService.RollAndAssignEnchant(tool, instanceData)
    if not tool then return nil end

    local enchantName = WeaponEnchantConfig.RollEnchant()

    if enchantName then
        tool:SetAttribute("HasEnchant", true)
        tool:SetAttribute("EnchantName", enchantName)

        local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
        if enchantData then
            -- Store hex color for easy UI reading later
            local c = enchantData.color
            tool:SetAttribute("EnchantColorHex", string.format("#%02X%02X%02X",
                math.floor(c.R * 255 + 0.5),
                math.floor(c.G * 255 + 0.5),
                math.floor(c.B * 255 + 0.5)))
        end
    else
        tool:SetAttribute("HasEnchant", false)
        tool:SetAttribute("EnchantName", "")
    end

    -- Persist to instance data if provided
    if instanceData then
        instanceData.enchantName = enchantName or ""
    end

    return enchantName
end

--------------------------------------------------------------------------------
-- APPLY ENCHANT FROM INSTANCE DATA
-- Sets attributes on a tool clone based on stored instance data, then applies
-- visuals.  Used by Loadout.server when granting a tool that already has a
-- enchant rolled from the crate.
-- instanceData = { ..., enchantName = "Fiery" }
--------------------------------------------------------------------------------
function WeaponEnchantService.ApplyEnchantFromInstance(tool, instanceData)
    if not tool or not instanceData then return end

    local enchantName = instanceData.enchantName
    if type(enchantName) ~= "string" or enchantName == "" then
        tool:SetAttribute("HasEnchant", false)
        tool:SetAttribute("EnchantName", "")
        return
    end

    local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not enchantData then
        tool:SetAttribute("HasEnchant", false)
        tool:SetAttribute("EnchantName", "")
        return
    end

    tool:SetAttribute("HasEnchant", true)
    tool:SetAttribute("EnchantName", enchantName)

    local c = enchantData.color
    tool:SetAttribute("EnchantColorHex", string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5)))

    WeaponEnchantService.ApplyEnchantVisuals(tool)
end

--------------------------------------------------------------------------------
-- GET ENCHANT DATA FROM TOOL
-- Reads enchant attributes and returns { hasEnchant, enchantName, enchantData } or nil.
--------------------------------------------------------------------------------
function WeaponEnchantService.GetEnchantDataFromTool(tool)
    if not tool then return nil end
    local hasEnchant  = tool:GetAttribute("HasEnchant")
    local enchantName = tool:GetAttribute("EnchantName")
    if not hasEnchant or not enchantName or enchantName == "" then
        return { hasEnchant = false, enchantName = nil, enchantData = nil }
    end
    return {
        hasEnchant  = true,
        enchantName = enchantName,
        enchantData = WeaponEnchantConfig.GetEnchantData(enchantName),
    }
end

--------------------------------------------------------------------------------
-- SPAWN HIT EFFECT
-- Creates a brief burst of colored particles at the hit position.
-- Cleans up automatically via Debris. Safe to call from server.
--
-- hitPosition : Vector3 – world position of the hit
-- enchantName    : string  – which enchant to color the burst
-- hitPart     : BasePart (optional) – if provided, attach to it instead
--------------------------------------------------------------------------------
function WeaponEnchantService.SpawnHitEffect(hitPosition, enchantName, hitPart)
    if not hitPosition or typeof(hitPosition) ~= "Vector3" then return end

    local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not enchantData then return end

    local color = enchantData.color
    local h, s, v = Color3.toHSV(color)
    local brightColor = Color3.fromHSV(h, math.clamp(s * 0.5, 0, 1), math.clamp(v * 1.3, 0, 1))

    -- Create a tiny invisible anchored part at the hit location
    local anchor = Instance.new("Part")
    anchor.Name = "_EnchantHitFX"
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
    burst.Name = "EnchantHitBurst"
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
    flash.Name = "EnchantHitFlash"
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

return WeaponEnchantService
