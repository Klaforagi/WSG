--------------------------------------------------------------------------------
-- WeaponEnchantService.lua  –  Server module: enchant visual application & hit FX
--
-- Responsible for:
--   • Setting enchant attributes on Tool instances
--   • Cloning manual enchant visual assets from ReplicatedStorage.Enchants
--     and parenting them under Handle.EnchantBlock (melee) or projectile
--     EnchantBlock (ranged)
--   • Recoloring the existing SwordTrail / projectile AmmoTrail
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
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponEnchantConfig = require(ReplicatedStorage:WaitForChild("WeaponEnchantConfig"))

local AssetCodes
pcall(function()
    local module = ReplicatedStorage:FindFirstChild("AssetCodes")
    if module and module:IsA("ModuleScript") then
        AssetCodes = require(module)
    end
end)

local function applyWeaponIcon(tool, enchantName)
    if not tool or not AssetCodes or type(AssetCodes.GetWeaponIcon) ~= "function" then
        return
    end
    local weaponName = tool:GetAttribute("WeaponName") or tool.Name
    local icon = AssetCodes.GetWeaponIcon(weaponName, enchantName)
    if type(icon) ~= "string" or icon == "" then
        return
    end
    pcall(function()
        tool.TextureId = icon
        tool:SetAttribute("Icon", icon)
    end)
end

local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)
local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))
local CombatUtils = require(ServerScriptService:WaitForChild("CombatUtils"))

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

-- Folder containing manually built enchant visual assets. Resolved at use-time
-- so a late-created ReplicatedStorage.Enchants folder still works.
local function getEnchantsFolder()
    local folder = ReplicatedStorage:FindFirstChild("Enchants")
    if folder then
        return folder
    end
    warn("[WeaponEnchantService] ReplicatedStorage.Enchants folder not found — enchant visuals will not apply")
    return nil
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

local function isRangedWeapon(tool)
    if not tool then return false end
    if tool:GetAttribute("IsRanged") == true then
        return true
    end

    local category = tool:GetAttribute("WeaponCategory") or tool:GetAttribute("HotbarCategory")
    if type(category) == "string" and string.lower(category) == "ranged" then
        return true
    end

    return false
end

local function isEnchantBlockName(name)
    return type(name) == "string" and string.lower(name) == "enchantblock"
end

local function asEnchantHost(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Attachment") and instance.Parent and instance.Parent:IsA("BasePart") then
        return instance.Parent
    end
    if instance.FindFirstChildWhichIsA then
        local part = instance:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part
        end
    end
    return nil
end

local function findEnchantBlocks(root)
    local blocks = {}
    local seen = {}
    local function add(instance)
        local host = asEnchantHost(instance)
        if host and not seen[host] then
            seen[host] = true
            table.insert(blocks, host)
        end
    end

    if not root then return blocks end

    if isEnchantBlockName(root.Name) then
        add(root)
    end

    local handle = root:FindFirstChild("Handle")
    if handle then
        local handleBlock = handle:FindFirstChild("EnchantBlock")
        if handleBlock then
            add(handleBlock)
        end
    end

    if root.GetDescendants then
        for _, descendant in ipairs(root:GetDescendants()) do
            if isEnchantBlockName(descendant.Name) then
                add(descendant)
            end
        end
    end

    return blocks
end

local function getProjectileHostPart(projectile)
    if not projectile then return nil end
    if projectile:IsA("BasePart") then
        return projectile
    end
    if projectile:IsA("Model") then
        if projectile.PrimaryPart and projectile.PrimaryPart:IsA("BasePart") then
            return projectile.PrimaryPart
        end
        local named = projectile:FindFirstChild(projectile.Name)
        if named and named:IsA("BasePart") then
            return named
        end
        return projectile:FindFirstChildWhichIsA("BasePart", true)
    end
    return projectile:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureProjectileEnchantBlocks(projectile)
    local blocks = findEnchantBlocks(projectile)
    if #blocks > 0 then
        return blocks
    end

    local host = getProjectileHostPart(projectile)
    if not host then
        return {}
    end

    local block = Instance.new("Part")
    block.Name = "EnchantBlock"
    block.Size = Vector3.new(0.25, 0.25, 0.25)
    block.Transparency = 1
    block.CanCollide = false
    block.Massless = true
    block.Anchored = host.Anchored
    block.CastShadow = false
    pcall(function() block.CanTouch = false end)
    pcall(function() block.CanQuery = false end)

    local tip = host:FindFirstChild("Tip")
    if not (tip and tip:IsA("Attachment")) and projectile.FindFirstChild then
        tip = projectile:FindFirstChild("Tip", true)
        if tip and not tip:IsA("Attachment") then
            tip = nil
        end
    end
    if tip and tip:IsA("Attachment") then
        block.CFrame = tip.WorldCFrame
    else
        block.CFrame = host.CFrame
    end

    if projectile:IsA("Model") then
        block.Parent = projectile
    else
        block.Parent = host.Parent or projectile
    end

    local weld = Instance.new("Weld")
    weld.Name = "EnchantBlockWeld"
    weld.Part0 = host
    weld.Part1 = block
    weld.C0 = host.CFrame:ToObjectSpace(block.CFrame)
    weld.C1 = CFrame.new()
    weld.Parent = host

    return { block }
end

local function clearEnchantClonesFromBlock(enchantBlock)
    if not enchantBlock then return end
    for _, child in ipairs(enchantBlock:GetChildren()) do
        if child.Name:sub(1, #ENCHANT_EFFECT_PREFIX) == ENCHANT_EFFECT_PREFIX then
            pcall(function() child:Destroy() end)
        end
    end
end

local PROJECTILE_ENCHANT_EMITTER_RATE = 20

local function configureProjectileEnchantEffects(root, rate)
    if not root then return end

    local function apply(instance)
        if instance:IsA("ParticleEmitter") then
            pcall(function()
                instance.Enabled = true
                instance.LockedToPart = true
                if type(rate) == "number" then
                    instance.Rate = rate
                end
            end)
        elseif instance:IsA("Beam") or instance:IsA("Trail") then
            pcall(function()
                instance.Enabled = true
            end)
        elseif instance:IsA("PointLight") or instance:IsA("SurfaceLight") or instance:IsA("SpotLight") then
            pcall(function()
                instance.Enabled = true
            end)
        end
    end

    apply(root)
    if root.GetDescendants then
        for _, descendant in ipairs(root:GetDescendants()) do
            apply(descendant)
        end
    end
end

-- Particle emitters only render when they have a BasePart ancestor. Melee
-- assets are often an Attachment; folders/models must be unpacked onto the block.
local function parentEnchantCloneToBlock(clone, enchantBlock)
    if not clone or not enchantBlock then
        return
    end

    if clone:IsA("BasePart")
        or clone:IsA("Attachment")
        or clone:IsA("ParticleEmitter")
        or clone:IsA("Beam")
        or clone:IsA("Trail")
        or clone:IsA("PointLight")
        or clone:IsA("SurfaceLight")
        or clone:IsA("SpotLight")
    then
        clone.Parent = enchantBlock
        return
    end

    for _, child in ipairs(clone:GetChildren()) do
        child.Parent = enchantBlock
    end
    clone:Destroy()
end

local function cloneEnchantAssetsIntoBlock(enchantBlock, enchantName, emitterRate)
    local enchantsFolder = getEnchantsFolder()
    if not enchantBlock or not enchantsFolder then return 0 end

    local clonedCount = 0
    local assetNames = getAssetNames(enchantName)
    for _, assetName in ipairs(assetNames) do
        local assetTemplate = enchantsFolder:FindFirstChild(assetName)
        if not assetTemplate then
            for _, child in ipairs(enchantsFolder:GetChildren()) do
                if string.lower(child.Name) == string.lower(assetName) then
                    assetTemplate = child
                    break
                end
            end
        end
        if assetTemplate then
            local clone = assetTemplate:Clone()
            clone.Name = ENCHANT_EFFECT_PREFIX .. assetName
            if type(emitterRate) == "number" then
                parentEnchantCloneToBlock(clone, enchantBlock)
                configureProjectileEnchantEffects(enchantBlock, emitterRate)
            else
                clone.Parent = enchantBlock
            end
            clonedCount += 1
        else
            warn("[WeaponEnchantService] Asset '" .. assetName .. "' not found in ReplicatedStorage.Enchants")
        end
    end
    return clonedCount
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

    -- Clean up active enchant effect clones from EnchantBlock(s)
    for _, enchantBlock in ipairs(findEnchantBlocks(tool)) do
        clearEnchantClonesFromBlock(enchantBlock)
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

    -- Ranged weapons keep enchant attributes for shot projectiles, but do not
    -- show melee-style Handle.EnchantBlock effects on the held weapon.
    if isRangedWeapon(tool) then
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

    local enchantBlocks = findEnchantBlocks(tool)
    if #enchantBlocks == 0 then
        warn("[WeaponEnchantService] Handle.EnchantBlock not found on tool '" .. tool.Name .. "', skipping visuals")
        return
    end

    if not getEnchantsFolder() then
        warn("[WeaponEnchantService] ReplicatedStorage.Enchants folder missing, cannot apply visuals")
        return
    end

    -- Clean up any prior enchant visuals
    WeaponEnchantService.ClearEnchantVisuals(tool)

    -- Clone the correct asset(s) into EnchantBlock
    for _, enchantBlock in ipairs(enchantBlocks) do
        cloneEnchantAssetsIntoBlock(enchantBlock, enchantName)
    end

    local trailColorSequence = WeaponEnchantConfig.GetTrailColorSequenceForEnchant(enchantName)

    local trail = tool:FindFirstChild("SwordTrail", true)
    if trail and trail:IsA("Trail") and trailColorSequence then
        pcall(function()
            trail.Color = trailColorSequence
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

    local enchantName = WeaponEnchantConfig.RollEnchant(instanceData)

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
        applyWeaponIcon(tool, enchantName)
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

    local weaponName = instanceData.weaponName or tool:GetAttribute("WeaponName") or tool.Name
    if WeaponEnchantConfig and type(WeaponEnchantConfig.EnsureEnchantName) == "function" then
        local ensured = WeaponEnchantConfig.EnsureEnchantName(weaponName, instanceData.enchantName)
        if ensured and ensured ~= instanceData.enchantName then
            instanceData.enchantName = ensured
        end
    end

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

    applyWeaponIcon(tool, enchantName)
    WeaponEnchantService.ApplyEnchantVisuals(tool)
end

--------------------------------------------------------------------------------
-- APPLY ENCHANT VISUALS TO PROJECTILE
-- Ranged weapons show their enchant on each shot's EnchantBlock instead of
-- the held weapon. Safe to call on a Part or Model.
--------------------------------------------------------------------------------
function WeaponEnchantService.ApplyEnchantVisualsToProjectile(projectile, enchantName)
    if not projectile then return false end
    if type(enchantName) == "string" then
        enchantName = enchantName:match("^%s*(.-)%s*$")
    end
    if type(enchantName) ~= "string" or enchantName == "" or string.lower(enchantName) == "none" then
        return false
    end

    local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not enchantData then
        warn("[WeaponEnchantService] Unknown enchant '" .. tostring(enchantName) .. "' on projectile, skipping visuals")
        return false
    end

    if not getEnchantsFolder() then
        warn("[WeaponEnchantService] ReplicatedStorage.Enchants folder missing, cannot apply projectile visuals")
        return false
    end

    local enchantBlocks = ensureProjectileEnchantBlocks(projectile)
    if #enchantBlocks == 0 then
        warn("[WeaponEnchantService] EnchantBlock not found on projectile '" .. tostring(projectile.Name) .. "', skipping visuals")
        return false
    end

    local cloned = 0
    for _, enchantBlock in ipairs(enchantBlocks) do
        clearEnchantClonesFromBlock(enchantBlock)
        cloned += cloneEnchantAssetsIntoBlock(enchantBlock, enchantName, PROJECTILE_ENCHANT_EMITTER_RATE)
        configureProjectileEnchantEffects(enchantBlock, PROJECTILE_ENCHANT_EMITTER_RATE)
    end

    if cloned <= 0 then
        warn("[WeaponEnchantService] No enchant assets cloned onto projectile '" .. tostring(projectile.Name) .. "'")
        return false
    end

    pcall(function()
        projectile:SetAttribute("HasEnchant", true)
        projectile:SetAttribute("EnchantName", enchantName)
    end)

    return true
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
local EnchantHitVFX

function WeaponEnchantService.SpawnHitEffect(hitPosition, enchantName, hitPart)
    if not hitPosition or typeof(hitPosition) ~= "Vector3" then return end

    local enchantData = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not enchantData then return end

    pcall(function()
        EnchantHitVFX:FireAllClients(hitPosition, enchantName)
    end)
end

--------------------------------------------------------------------------------
-- ══════════════════════════════════════════════════════════════════════════════
-- ENCHANT PROC SYSTEM  –  Flat damage / effects triggered on confirmed hits
-- ══════════════════════════════════════════════════════════════════════════════
--
-- TryProcEnchant(attackerPlayer, attackerHumanoid, targetModel, targetHumanoid,
--                enchantName, hitPos)
--
-- Called from ToolMeleeSetup after every confirmed melee hit on a target that
-- has an enchanted weapon.  Rolls proc chance internally.  All damage is FLAT
-- and does NOT scale from weapon damage, size, rarity, upgrades, or combo.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local ICY_MOVEMENT_MODIFIER_ID = "icy_debuff"

local ProcConfig = WeaponEnchantConfig.ProcConfig or {}
local DOT_DAMAGE_OPTIONS = { SkipLastDamagerTag = true }
local PRACTICE_DUMMY_TAG = "PracticeDummy"

local function isPracticeDummyModel(model)
    return model
        and model:IsA("Model")
        and (model:GetAttribute("IsPracticeDummy") == true or CollectionService:HasTag(model, PRACTICE_DUMMY_TAG))
end

local STANDARD_BODY_PARTS = {
    head = true,
    torso = true,
    uppertorso = true,
    lowertorso = true,
    leftarm = true,
    rightarm = true,
    leftleg = true,
    rightleg = true,
    leftupperarm = true,
    leftlowerarm = true,
    lefthand = true,
    rightupperarm = true,
    rightlowerarm = true,
    righthand = true,
    leftupperleg = true,
    leftlowerleg = true,
    leftfoot = true,
    rightupperleg = true,
    rightlowerleg = true,
    rightfoot = true,
}

-- Remote event for enchant proc damage popups (server → attacker client)
local EnchantProcHit = ReplicatedStorage:FindFirstChild("EnchantProcHit")
if not EnchantProcHit then
    EnchantProcHit = Instance.new("RemoteEvent")
    EnchantProcHit.Name = "EnchantProcHit"
    EnchantProcHit.Parent = ReplicatedStorage
end

EnchantHitVFX = ReplicatedStorage:FindFirstChild("EnchantHitVFX")
if not EnchantHitVFX then
    EnchantHitVFX = Instance.new("RemoteEvent")
    EnchantHitVFX.Name = "EnchantHitVFX"
    EnchantHitVFX.Parent = ReplicatedStorage
end

-- Remote event for shock chain lightning VFX (server → all clients)
local ShockChainVFX = ReplicatedStorage:FindFirstChild("ShockChainVFX")
if not ShockChainVFX then
    ShockChainVFX = Instance.new("RemoteEvent")
    ShockChainVFX.Name = "ShockChainVFX"
    ShockChainVFX.Parent = ReplicatedStorage
end

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------

-- Safe get HumanoidRootPart (or Torso fallback)
local function getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("Head")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

-- Safe get Humanoid
local function getHumanoid(model)
    if not model then return nil end
    return model:FindFirstChildOfClass("Humanoid")
end

local function isStandardBodyPart(part)
    if not part or not part:IsA("BasePart") then return false end
    local normalizedName = string.lower((part.Name or ""):gsub("%s+", ""))
    return STANDARD_BODY_PARTS[normalizedName] == true
end

local function applyBodyTint(model, tintColor)
    if not model then return {} end

    local originals = {}
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") and child.Transparency < 1 and isStandardBodyPart(child) then
            originals[child] = child.Color
            pcall(function() child.Color = tintColor end)
        end
    end

    return originals
end

-- Play a proc sound at a position (via the target's root if available)
-- Clones the Sound from ReplicatedStorage.Sounds.ToolMelee.<enchantName>
local toolMeleeSounds = ReplicatedStorage:FindFirstChild("Sounds")
    and ReplicatedStorage.Sounds:FindFirstChild("ToolMelee")

local function playProcSound(enchantName, targetRoot)
    if not enchantName or enchantName == "" then return end
    if not targetRoot or not targetRoot:IsA("BasePart") then return end
    if not toolMeleeSounds then return end
    local template = toolMeleeSounds:FindFirstChild(enchantName)
    if not template or not template:IsA("Sound") then return end
    pcall(function()
        local s = template:Clone()
        s.Parent = targetRoot
        s:Play()
        Debris:AddItem(s, s.TimeLength + 1)
    end)
end

-- Send enchant proc damage popup to the attacker's client
-- Find the torso part of a model (Torso for R6, UpperTorso for R15, fallback to root)
local function getTorso(model)
    if not model then return nil end
    return model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("HumanoidRootPart")
end

local function sendProcPopup(attackerPlayer, damage, enchantName, targetRoot, targetPosition)
    if not attackerPlayer or not attackerPlayer.Parent then return end
    local popupPosition = targetPosition
    if not popupPosition and targetRoot and targetRoot:IsA("BasePart") then
        popupPosition = targetRoot.Position
    end
    pcall(function()
        EnchantProcHit:FireClient(attackerPlayer, damage, enchantName, targetRoot, popupPosition)
    end)
end

local function rollEnchantDamage(baseDamage)
    if type(baseDamage) ~= "number" or baseDamage <= 0 then
        return 0
    end
    return baseDamage * (math.random(80, 120) / 100)
end

local function applyDamageOutputModifiers(attackerPlayer, damage)
    if not attackerPlayer or not _G.GetRevengeCurseDamageMultiplier then
        return damage
    end
    local ok, multiplier = pcall(function()
        return _G.GetRevengeCurseDamageMultiplier(attackerPlayer)
    end)
    if ok and type(multiplier) == "number" and multiplier > 0 then
        return damage * multiplier
    end
    return damage
end

local function inferWeaponDamageType(attackerPlayer, options)
    if type(options) == "table" then
        local explicit = options.damageType
        if explicit == "melee" or explicit == "ranged" then
            return explicit
        end
    end
    local character = attackerPlayer and attackerPlayer.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    local category = tool and (tool:GetAttribute("WeaponCategory") or tool:GetAttribute("HotbarCategory"))
    if type(category) == "string" then
        local lowered = string.lower(category)
        if lowered == "melee" then
            return "melee"
        end
        if lowered == "ranged" then
            return "ranged"
        end
    end
    return nil
end

-- Apply flat enchant damage to a humanoid.
-- Does not scale from melee or ranged upgrades.
-- Also sends a proc popup to the attacker's client.
local function applyFlatDamage(targetHumanoid, damage, attackerPlayer, enchantName, options)
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    if damage <= 0 then return end
    local skipLastDamagerTag = type(options) == "table" and options.SkipLastDamagerTag == true
    damage = applyDamageOutputModifiers(attackerPlayer, damage)
    damage = math.round(damage)
    pcall(function()
        local model = targetHumanoid.Parent
        if CombatUtils and (CombatUtils.isPodiumAvatar(model) or CombatUtils.isPodiumPart(options and options.PopupPart)) then
            if _G.DEBUG_COMBAT then print("[Combat] Ignored podium avatar enchant damage:", model and model.Name) end
            return
        end
        if attackerPlayer then
            targetHumanoid:SetAttribute("lastDamagerUserId", attackerPlayer.UserId)
            targetHumanoid:SetAttribute("lastDamagerName", attackerPlayer.Name)
            targetHumanoid:SetAttribute("lastDamageTime", tick())
        end
        if skipLastDamagerTag then
            targetHumanoid:SetAttribute("SuppressMobAggroUntil", os.clock() + 0.25)
        end
        targetHumanoid:TakeDamage(damage)
    end)
    if StatService and StatService.RegisterDamageDealt and attackerPlayer then
        pcall(function()
            StatService:RegisterDamageDealt(attackerPlayer, damage, {
                damageType = inferWeaponDamageType(attackerPlayer, options),
            })
        end)
    end
    -- Send popup to attacker
    if enchantName and attackerPlayer then
        local model = targetHumanoid and targetHumanoid.Parent
        local popupPart = type(options) == "table" and options.PopupPart or nil
        local popupPosition = type(options) == "table" and options.PopupPosition or nil
        if not (popupPart and popupPart:IsA("BasePart")) then
            popupPart = model and (getTorso(model) or getRoot(model)) or nil
        end
        sendProcPopup(attackerPlayer, damage, enchantName, popupPart, popupPosition)
    end
end

-- Check that target is alive and not the attacker
local function isValidTarget(attackerPlayer, targetModel, targetHumanoid)
    if not targetModel or not targetHumanoid then return false end
    if targetHumanoid.Health <= 0 then return false end
    -- Don't proc on self
    if attackerPlayer and attackerPlayer.Character == targetModel then return false end
    -- Don't proc on same-team players
    local vp = Players:GetPlayerFromCharacter(targetModel)
    if vp and attackerPlayer and attackerPlayer.Team and vp.Team
        and attackerPlayer.Team == vp.Team then
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- ICY STATE  –  One slow + damage-tick tracker per target humanoid
-- Applies the slow through HumanoidStatService so players and mobs both use
-- the same movement speed formula.
-- Ticks damage immediately on application, then once per interval.
-- Re-procs refresh the timer and restart ticks.
-- Tints body parts icy blue and spawns snowflake particles for the duration.
---------------------------------------------------------------------------
local icyState = {} -- [Humanoid] = { subject, expireThread, tickThread, remaining, originalColors, particles }

local ICY_COLOR = Color3.fromRGB(95, 220, 255)
local ICY_SNOWFLAKE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Tint all visible body parts to icy blue and store originals
local function applyIcyBodyTint(model)
    return applyBodyTint(model, ICY_COLOR)
end

-- Restore original body part colors
local function removeIcyBodyTint(originals)
    if not originals then return end
    for part, color in pairs(originals) do
        if part and part.Parent then
            pcall(function() part.Color = color end)
        end
    end
end

-- Create snowflake particle emitter attached to the target's root
local function createIcyParticles(model)
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso"))
    if not root then return nil end

    local attachment = Instance.new("Attachment")
    attachment.Name = "_IcyFrostAttachment"
    attachment.Parent = root

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "_IcyFrostEmitter"
    emitter.Texture = ICY_SNOWFLAKE_TEXTURE
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 240, 255)),
        ColorSequenceKeypoint.new(1, ICY_COLOR),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.LightEmission = 0.6
    emitter.LightInfluence = 0.2
    emitter.Lifetime = NumberRange.new(0.5, 1.2)
    emitter.Speed = NumberRange.new(1, 4)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Drag = 2
    emitter.Rate = 15
    emitter.RotSpeed = NumberRange.new(-120, 120)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.Parent = attachment

    return attachment -- destroying this also destroys the emitter
end

-- Remove icy particles
local function removeIcyParticles(attachment)
    if attachment and attachment.Parent then
        pcall(function() attachment:Destroy() end)
    end
end

local function resolveMovementSubjectFromHumanoid(targetHumanoid)
    if not targetHumanoid then
        return nil
    end

    local model = targetHumanoid.Parent
    local player = model and Players:GetPlayerFromCharacter(model)
    return player or targetHumanoid
end

local function applyIcySlow(targetHumanoid, slowPercent, duration, tickDamage, tickInterval, attackerPlayer)
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    tickDamage   = tickDamage   or 2
    tickInterval = tickInterval or 1

    local model = targetHumanoid.Parent
    local subject = resolveMovementSubjectFromHumanoid(targetHumanoid)
    local existing = icyState[targetHumanoid]

    if not existing then
        local origColors = applyIcyBodyTint(model)
        local particleAttach = createIcyParticles(model)
        icyState[targetHumanoid] = {
            subject = subject,
            expireThread = nil,
            tickThread = nil,
            remaining = duration,
            originalColors = origColors,
            particles = particleAttach,
        }
    else
        existing.remaining = duration
        existing.subject = subject
    end

    local state = icyState[targetHumanoid]
    local speedMultiplier = math.max(0, 1 - (tonumber(slowPercent) or 0))
    HumanoidStatService:SetModifier(subject, MOVEMENT_SPEED_STAT, ICY_MOVEMENT_MODIFIER_ID, {
        multiplier = speedMultiplier,
        duration = duration,
        source = "Icy",
    })

    if state.expireThread then
        pcall(function() task.cancel(state.expireThread) end)
        state.expireThread = nil
    end

    if state.tickThread then
        pcall(function() task.cancel(state.tickThread) end)
        state.tickThread = nil
    end

    state.remaining = duration

    applyFlatDamage(targetHumanoid, rollEnchantDamage(tickDamage), attackerPlayer, "Icy", DOT_DAMAGE_OPTIONS)

    state.tickThread = task.spawn(function()
        while state.remaining >= tickInterval do
            task.wait(tickInterval)
            if not icyState[targetHumanoid] then break end
            if not targetHumanoid or not targetHumanoid.Parent or targetHumanoid.Health <= 0 then break end
            state.remaining = state.remaining - tickInterval
            applyFlatDamage(targetHumanoid, rollEnchantDamage(tickDamage), attackerPlayer, "Icy", DOT_DAMAGE_OPTIONS)
        end
    end)

    state.expireThread = task.delay(duration, function()
        local s = icyState[targetHumanoid]
        if s then
            if s.tickThread then
                pcall(function() task.cancel(s.tickThread) end)
            end
            removeIcyBodyTint(s.originalColors)
            removeIcyParticles(s.particles)
            if s.subject then
                pcall(function()
                    HumanoidStatService:RemoveModifier(s.subject, MOVEMENT_SPEED_STAT, ICY_MOVEMENT_MODIFIER_ID)
                end)
            end
            icyState[targetHumanoid] = nil
        end
    end)
end

-- Clean up icy state if humanoid dies or is destroyed
local function cleanIcyOnDeath(targetHumanoid)
    if not icyState[targetHumanoid] then return end
    local s = icyState[targetHumanoid]
    if s.expireThread then
        pcall(function() task.cancel(s.expireThread) end)
    end
    if s.tickThread then
        pcall(function() task.cancel(s.tickThread) end)
    end
    removeIcyBodyTint(s.originalColors)
    removeIcyParticles(s.particles)
    if s.subject then
        pcall(function()
            HumanoidStatService:RemoveModifier(s.subject, MOVEMENT_SPEED_STAT, ICY_MOVEMENT_MODIFIER_ID)
        end)
    end
    icyState[targetHumanoid] = nil
end

---------------------------------------------------------------------------
-- SHOCK CHAIN  –  Anti-spam cooldown per attacker
---------------------------------------------------------------------------
local shockLastChain = {} -- [Player] = tick()

-- Find the single nearest valid chain target from a given position.
-- Returns { model, humanoid, root, dist } or nil.
local function findNextChainTarget(attackerPlayer, currentPos, chainRange, seen)
    local best = nil
    local bestDist = chainRange + 1

    -- Gather all candidate models
    local candidates = {}
    local function addCandidate(model)
        if model and not seen[model] then
            table.insert(candidates, model)
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and not seen[p.Character] then
            addCandidate(p.Character)
        end
    end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name == "Dummy" and not seen[obj] then
            addCandidate(obj)
        end
    end
    for _, obj in ipairs(CollectionService:GetTagged(PRACTICE_DUMMY_TAG)) do
        if obj:IsA("Model") then
            addCandidate(obj)
        end
    end
    for _, z in ipairs(CollectionService:GetTagged("ZombieNPC")) do
        if z:IsA("Model") then
            addCandidate(z)
        end
    end

    for _, model in ipairs(candidates) do
        local hum = getHumanoid(model)
        if not hum or hum.Health <= 0 then continue end
        local root = getRoot(model)
        if not root then continue end
        -- Team check
        local vp = Players:GetPlayerFromCharacter(model)
        if vp and attackerPlayer and attackerPlayer.Team and vp.Team
            and attackerPlayer.Team == vp.Team then
            continue
        end
        local dist = (root.Position - currentPos).Magnitude
        if dist <= chainRange and dist < bestDist then
            best = { model = model, humanoid = hum, root = root, dist = dist }
            bestDist = dist
        end
    end

    return best
end

---------------------------------------------------------------------------
-- TOXIC STATE  –  One poison runner per target; re-procs extend duration
---------------------------------------------------------------------------
local toxicState = {} -- [Humanoid] = { remaining, running, originalColors, particles }

local POISON_COLOR = Color3.fromRGB(80, 200, 80)

local function applyPoisonBodyTint(model)
    return applyBodyTint(model, POISON_COLOR)
end

local function removePoisonBodyTint(originals)
    if not originals then return end
    for part, color in pairs(originals) do
        if part and part.Parent then
            pcall(function() part.Color = color end)
        end
    end
end

local function createPoisonParticles(model)
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso"))
    if not root then return nil end

    local attachment = Instance.new("Attachment")
    attachment.Name = "_PoisonGasAttachment"
    attachment.Parent = root

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "_PoisonGasEmitter"
    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 220, 80)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 180, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 120, 40)),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.4, 0.5),
        NumberSequenceKeypoint.new(1, 0.05),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.LightEmission = 0.2
    emitter.LightInfluence = 0.6
    emitter.Lifetime = NumberRange.new(0.6, 1.4)
    emitter.Speed = NumberRange.new(1, 3)
    emitter.SpreadAngle = Vector2.new(60, 60)
    emitter.Drag = 3
    emitter.Rate = 20
    emitter.RotSpeed = NumberRange.new(-60, 60)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.Parent = attachment

    return attachment
end

local function removePoisonParticles(attachment)
    if attachment and attachment.Parent then
        pcall(function() attachment:Destroy() end)
    end
end

local function applyToxicDoT(attackerPlayer, targetHumanoid, cfg)
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    local tickDmg       = cfg.TickDamage      or 7
    local tickInterval  = cfg.TickInterval     or 2
    local addDuration   = cfg.DurationPerProc  or 6
    local maxDuration   = cfg.MaxDuration      or 18

    local existing = toxicState[targetHumanoid]
    if existing then
        -- Extend remaining time up to cap
        existing.remaining = math.min(existing.remaining + addDuration, maxDuration)
        return -- runner is already going, it will pick up the extended time
    end

    -- Create new toxic state and runner
    local state = { remaining = math.min(addDuration, maxDuration), running = true }
    toxicState[targetHumanoid] = state

    -- Apply visuals
    local model = targetHumanoid.Parent
    state.originalColors = applyPoisonBodyTint(model)
    state.particles      = createPoisonParticles(model)

    task.spawn(function()
        while state.running and state.remaining > 0 do
            task.wait(tickInterval)
            -- Re-check after wait
            if not state.running then break end
            if not targetHumanoid or not targetHumanoid.Parent or targetHumanoid.Health <= 0 then
                break
            end
            state.remaining = state.remaining - tickInterval
            applyFlatDamage(targetHumanoid, rollEnchantDamage(tickDmg), attackerPlayer, "Toxic", DOT_DAMAGE_OPTIONS)
        end
        -- Cleanup visuals then state
        state.running = false
        removePoisonBodyTint(state.originalColors)
        removePoisonParticles(state.particles)
        if toxicState[targetHumanoid] == state then
            toxicState[targetHumanoid] = nil
        end
    end)
end

---------------------------------------------------------------------------
-- MAIN PROC ENTRY POINT
---------------------------------------------------------------------------
function WeaponEnchantService.TryProcEnchant(attackerPlayer, attackerHumanoid,
                                              targetModel, targetHumanoid,
                                              enchantName, hitPos)
    if not enchantName or enchantName == "" then return false end
    if not isValidTarget(attackerPlayer, targetModel, targetHumanoid) then return false end

    local cfg = ProcConfig[enchantName]
    if not cfg then return false end

    -- Roll proc chance
    local chance = cfg.ProcChance or 0
    if math.random() > chance then return false end

    local targetRoot = getRoot(targetModel)
    local primaryDamageOptions = hitPos and { PopupPosition = hitPos } or nil

    -- Play proc sound
    playProcSound(enchantName, targetRoot)

    ---------- FIERY ----------
    if enchantName == "Fiery" then
        applyFlatDamage(targetHumanoid, rollEnchantDamage(cfg.ProcDamage or 20), attackerPlayer, enchantName, primaryDamageOptions)

    ---------- ICY ----------
    elseif enchantName == "Icy" then
        -- No instant damage; slow + tick damage over the slow duration
        applyIcySlow(
            targetHumanoid,
            cfg.SlowPercent or 0.50,
            cfg.SlowDuration or 4,
            cfg.TickDamage or 2,
            cfg.TickInterval or 1,
            attackerPlayer
        )

    ---------- SHOCK ----------
    elseif enchantName == "Shock" then
        applyFlatDamage(targetHumanoid, rollEnchantDamage(cfg.ProcDamage or 10), attackerPlayer, enchantName, primaryDamageOptions)

        -- Always show impact sparks on the original target
        ShockChainVFX:FireAllClients(targetModel, nil)

        -- Anti-spam: one chain per attacker per cooldown window
        local now = tick()
        local lastChain = shockLastChain[attackerPlayer] or 0
        if now - lastChain < (cfg.ChainCooldown or 0.5) then return end
        shockLastChain[attackerPlayer] = now

        local chainRange = cfg.ChainRange or 12
        local maxChains  = cfg.MaxChains  or 2

        -- Sequential chain: A -> B -> C (not branching)
        local seen = {}
        seen[targetModel] = true
        if attackerPlayer and attackerPlayer.Character then
            seen[attackerPlayer.Character] = true
        end

        local currentModel = targetModel
        local currentPos   = targetRoot and targetRoot.Position or hitPos
        if not currentPos then return end

        for _ = 1, maxChains do
            local next = findNextChainTarget(attackerPlayer, currentPos, chainRange, seen)
            if not next then break end

            applyFlatDamage(next.humanoid, cfg.ChainDamage or 8, attackerPlayer, enchantName)
            playProcSound(enchantName, next.root)
            ShockChainVFX:FireAllClients(currentModel, next.model)

            seen[next.model] = true
            currentModel = next.model
            currentPos   = next.root.Position
        end

    ---------- TOXIC ----------
    elseif enchantName == "Toxic" then
        applyToxicDoT(attackerPlayer, targetHumanoid, cfg)

    ---------- LIFESTEAL ----------
    elseif enchantName == "Lifesteal" then
        applyFlatDamage(targetHumanoid, rollEnchantDamage(cfg.ProcDamage or 6), attackerPlayer, enchantName, primaryDamageOptions)
        -- Heal attacker
        if attackerHumanoid and attackerHumanoid.Parent and attackerHumanoid.Health > 0 then
            pcall(function()
                local heal = cfg.HealAmount or 6
                attackerHumanoid.Health = math.min(attackerHumanoid.Health + heal, attackerHumanoid.MaxHealth)
            end)
        end

    ---------- VOID ----------
    elseif enchantName == "Void" then
        applyFlatDamage(targetHumanoid, rollEnchantDamage(cfg.ProcDamage or 30), attackerPlayer, enchantName, primaryDamageOptions)
        -- Knockback blast
        if targetRoot and targetRoot:IsA("BasePart") then
            local attackerRoot = attackerPlayer and attackerPlayer.Character
                and getRoot(attackerPlayer.Character)
            if attackerRoot then
                local dir = (targetRoot.Position - attackerRoot.Position)
                if dir.Magnitude < 0.01 then
                    dir = attackerRoot.CFrame.LookVector
                end
                dir = dir.Unit
                pcall(function()
                    local bv = Instance.new("BodyVelocity")
                    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                    bv.Velocity = dir * (cfg.KnockbackForce or 85)
                        + Vector3.new(0, cfg.KnockbackUpwardForce or 18, 0)
                    bv.Parent = targetRoot
                    Debris:AddItem(bv, 0.25)
                end)
            end
        end
    end

    return true
end

---------------------------------------------------------------------------
-- CLEANUP: remove icy / toxic state when humanoids die or are destroyed
-- Called from ToolMeleeSetup on kill, but also safe as a periodic sweep.
---------------------------------------------------------------------------
function WeaponEnchantService.CleanupTarget(targetHumanoid)
    cleanIcyOnDeath(targetHumanoid)
    local ts = toxicState[targetHumanoid]
    if ts then
        ts.running = false
        toxicState[targetHumanoid] = nil
    end
end

-- Auto-cleanup shock cooldowns when players leave
Players.PlayerRemoving:Connect(function(player)
    shockLastChain[player] = nil
end)

return WeaponEnchantService
