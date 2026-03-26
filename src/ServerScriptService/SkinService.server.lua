--------------------------------------------------------------------------------
-- SkinService.server.lua
-- Server-side logic for the cosmetic Skin system: purchase, equip, persist,
-- and apply skins to player characters on spawn/respawn.
--
-- SAFETY: Skins are purely cosmetic overlays. They NEVER destroy, remove, or
-- replace any original character parts (accessories, shirts, pants, face, body
-- parts). All cosmetic parts are tagged and can be cleanly removed.
--
-- Remotes (under ReplicatedStorage.Remotes.Skins):
--   PurchaseSkin          (RF client→server)  buy a skin with coins
--   GetOwnedSkins        (RF client→server)  fetch list of owned skin ids
--   EquipSkin             (RE client→server)  equip an owned skin
--   GetEquippedSkin       (RF client→server)  fetch currently equipped skin id
--   EquippedSkinChanged   (RE server→client)  pushed after equip changes
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local DEBUG = true
local function dprint(...)
    if DEBUG then print("[SkinService]", ...) end
end

dprint("initializing")

-- ── Shared config ──────────────────────────────────────────────────────────
local SkinDefs = nil
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("SkinDefinitions", 10)
    if mod and mod:IsA("ModuleScript") then SkinDefs = require(mod) end
end)
if not SkinDefs then
    warn("[SkinService] SkinDefinitions not found – skin system disabled")
    return
end

-- ── CurrencyService ────────────────────────────────────────────────────────
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then CurrencyService = require(mod) end
end)

-- ── DataStore ──────────────────────────────────────────────────────────────
local DATASTORE_NAME = "Skins_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5
local ds = nil
pcall(function() ds = DataStoreService:GetDataStore(DATASTORE_NAME) end)

-- ── Helper ─────────────────────────────────────────────────────────────────
local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA(className) then return existing end
        existing:Destroy()
    end
    local inst = Instance.new(className)
    inst.Name = name
    inst.Parent = parent
    return inst
end

-- ── Remote setup ───────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local skinsFolder = ensureInstance(remotesFolder, "Folder", "Skins")

local purchaseSkinRF     = ensureInstance(skinsFolder, "RemoteFunction", "PurchaseSkin")
local getOwnedRF         = ensureInstance(skinsFolder, "RemoteFunction", "GetOwnedSkins")
local equipSkinRE        = ensureInstance(skinsFolder, "RemoteEvent",    "EquipSkin")
local getEquippedRF      = ensureInstance(skinsFolder, "RemoteFunction", "GetEquippedSkin")
local equippedChangedRE  = ensureInstance(skinsFolder, "RemoteEvent",    "EquippedSkinChanged")

dprint("Remotes created")

-- ── Per-player state ───────────────────────────────────────────────────────
-- playerData[player] = { owned = { [skinId] = true }, equipped = skinId }
local playerData = {}

-- ── Persistence helpers ────────────────────────────────────────────────────
local function dsKey(player)
    return "User_" .. tostring(player.UserId)
end

local function loadData(player)
    if not ds then return { owned = {}, equipped = "Default" } end
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function() return ds:GetAsync(dsKey(player)) end)
        if success then break end
        warn("[SkinService] GetAsync fail attempt", i, result)
        task.wait(RETRY_DELAY * i)
    end
    if success and type(result) == "table" then
        local owned = {}
        if type(result.owned) == "table" then
            for k, v in pairs(result.owned) do
                if type(k) == "number" and type(v) == "string" then
                    owned[v] = true
                elseif type(v) == "boolean" then
                    owned[k] = v
                end
            end
        end
        local equipped = "Default"
        if type(result.equipped) == "string" and #result.equipped > 0 then
            -- Validate equipped skin exists
            local def = SkinDefs.GetById(result.equipped)
            if def then
                equipped = result.equipped
            end
        end
        -- Always grant default
        owned["Default"] = true
        return { owned = owned, equipped = equipped }
    end
    return { owned = { Default = true }, equipped = "Default" }
end

local function saveData(player)
    if not ds then return end
    local data = playerData[player]
    if not data then return end
    local ownedArr = {}
    for id, v in pairs(data.owned) do
        if v and id ~= "Default" then -- no need to save Default
            table.insert(ownedArr, id)
        end
    end
    local payload = { owned = ownedArr, equipped = data.equipped or "Default" }
    for i = 1, RETRIES do
        local ok, err = pcall(function() ds:SetAsync(dsKey(player), payload) end)
        if ok then
            dprint("saved data for", player.Name)
            return
        end
        warn("[SkinService] SetAsync fail attempt", i, err)
        task.wait(RETRY_DELAY * i)
    end
end

local function getOrCreateData(player)
    if not playerData[player] then
        playerData[player] = loadData(player)
    end
    return playerData[player]
end

-- ── Owned / Equipped helpers ───────────────────────────────────────────────
local function isOwned(player, skinId)
    if skinId == "Default" then return true end
    local data = getOrCreateData(player)
    return data.owned[skinId] == true
end

local function getOwnedList(player)
    local data = getOrCreateData(player)
    local list = {}
    for id, v in pairs(data.owned) do
        if v then table.insert(list, id) end
    end
    -- Ensure Default is always included
    local hasDefault = false
    for _, id in ipairs(list) do
        if id == "Default" then hasDefault = true; break end
    end
    if not hasDefault then table.insert(list, 1, "Default") end
    return list
end

local function getEquipped(player)
    local data = getOrCreateData(player)
    return data.equipped or "Default"
end

local function pushEquippedToClient(player)
    local equipped = getEquipped(player)
    pcall(function() equippedChangedRE:FireClient(player, equipped) end)
end

--------------------------------------------------------------------------------
-- SKIN APPLICATION  (COSMETIC-ONLY – never destroys original character parts)
--------------------------------------------------------------------------------

-- Tag name used to identify skin-applied cosmetic parts
local SKIN_TAG = "_SkinCosmetic"

-- Re-entry guard: prevents double-application
local applyingLock = {}

-- Remove all previously applied cosmetic skin parts from a character
local function clearSkinCosmetics(character)
    if not character then return end
    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute(SKIN_TAG) then
            child:Destroy()
        end
    end
    dprint("cleared cosmetic overlays from", character.Name)
end

-- Save original body colors as attributes on the BodyColors instance
local function saveOriginalBodyColors(character)
    local bc = character:FindFirstChildOfClass("BodyColors")
    if not bc then return end
    if bc:GetAttribute("_OrigBodyColorsSaved") then return end -- only save once
    bc:SetAttribute("_OrigBodyColorsSaved", true)
    bc:SetAttribute("_OrigHeadColor3",     bc.HeadColor3)
    bc:SetAttribute("_OrigTorsoColor3",    bc.TorsoColor3)
    bc:SetAttribute("_OrigLeftArmColor3",  bc.LeftArmColor3)
    bc:SetAttribute("_OrigRightArmColor3", bc.RightArmColor3)
    bc:SetAttribute("_OrigLeftLegColor3",  bc.LeftLegColor3)
    bc:SetAttribute("_OrigRightLegColor3", bc.RightLegColor3)
end

-- Restore original body colors from saved attributes
local function restoreOriginalBodyColors(character)
    local bc = character:FindFirstChildOfClass("BodyColors")
    if not bc or not bc:GetAttribute("_OrigBodyColorsSaved") then return end
    local h  = bc:GetAttribute("_OrigHeadColor3")
    local t  = bc:GetAttribute("_OrigTorsoColor3")
    local la = bc:GetAttribute("_OrigLeftArmColor3")
    local ra = bc:GetAttribute("_OrigRightArmColor3")
    local ll = bc:GetAttribute("_OrigLeftLegColor3")
    local rl = bc:GetAttribute("_OrigRightLegColor3")
    if h  then bc.HeadColor3     = h  end
    if t  then bc.TorsoColor3    = t  end
    if la then bc.LeftArmColor3  = la end
    if ra then bc.RightArmColor3 = ra end
    if ll then bc.LeftLegColor3  = ll end
    if rl then bc.RightLegColor3 = rl end
    dprint("restored original body colors")
end

-- Restore accessory visibility after a skin hid them
local function restoreAccessories(character)
    for _, acc in ipairs(character:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local orig = handle:GetAttribute("_OrigTransparency")
                if orig ~= nil then
                    handle.Transparency = orig
                    handle:SetAttribute("_OrigTransparency", nil)
                end
            end
        end
    end
end

-- Apply Default skin: simply remove cosmetic overlays and restore originals
local function applyDefaultSkin(player, character)
    dprint(player.Name, "applying Default skin")
    clearSkinCosmetics(character)
    restoreOriginalBodyColors(character)
    restoreAccessories(character)
    dprint(player.Name, "Default skin applied successfully")
end

-- Safe helper: create a cosmetic Part, position it, weld it, then parent it.
-- CFrame is set BEFORE parenting to avoid physics-glitch frame at world origin.
local function createArmorPiece(character, limbPart, name, size, offset, color, shape)
    if not limbPart or not limbPart:IsA("BasePart") then return nil end

    local armor = Instance.new("Part")
    armor.Name = name
    armor.Size = size
    armor.Color = color
    armor.Material = Enum.Material.SmoothPlastic
    armor.CanCollide = false
    armor.Massless = true
    armor.Anchored = false
    if shape then
        armor.Shape = shape
    end
    armor:SetAttribute(SKIN_TAG, true)

    -- Position BEFORE parenting so the part never appears at origin
    armor.CFrame = limbPart.CFrame * offset

    -- Create weld before parenting so it activates immediately
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = limbPart
    weld.Part1 = armor
    weld.Parent = armor

    -- Parent LAST – part enters workspace at correct position with weld active
    armor.Parent = character
    return armor
end

-- Apply Knight skin: COSMETIC OVERLAY ONLY
-- • Hides accessories (transparency) instead of destroying them
-- • Saves + overrides body colors (reversible)
-- • Welds tagged armor parts on top of existing body
-- • NEVER destroys any original character object
local function applyKnightSkin(player, character)
    dprint(player.Name, "applying Knight skin")
    clearSkinCosmetics(character)

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        dprint(player.Name, "WARN: no Humanoid found – aborting Knight skin")
        return
    end

    local def = SkinDefs.GetById("Knight")
    if not def then
        dprint(player.Name, "WARN: Knight definition not found")
        return
    end

    local armorColor  = def.ArmorColor  or Color3.fromRGB(160, 165, 175)
    local accentColor = def.AccentColor or Color3.fromRGB(200, 170, 50)
    local helmetColor = def.HelmetColor or Color3.fromRGB(140, 145, 155)
    local visorColor  = def.VisorColor  or Color3.fromRGB(30, 30, 35)

    -- ── Step 1: Save + override body colors (reversible) ─────────────────
    saveOriginalBodyColors(character)
    local bodyColors = character:FindFirstChildOfClass("BodyColors")
    if bodyColors then
        local undersuitColor = BrickColor.new(Color3.fromRGB(50, 50, 55))
        bodyColors.HeadColor      = undersuitColor
        bodyColors.TorsoColor     = undersuitColor
        bodyColors.LeftArmColor   = undersuitColor
        bodyColors.RightArmColor  = undersuitColor
        bodyColors.LeftLegColor   = undersuitColor
        bodyColors.RightLegColor  = undersuitColor
    end

    -- ── Step 2: Hide accessories (transparency, NOT destroy) ─────────────
    for _, acc in ipairs(character:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                if not handle:GetAttribute("_OrigTransparency") then
                    handle:SetAttribute("_OrigTransparency", handle.Transparency)
                end
                handle.Transparency = 1
            end
        end
    end

    -- ── Step 3: Weld cosmetic armor pieces ───────────────────────────────
    local head = character:FindFirstChild("Head")

    -- Helmet
    if head and head:IsA("BasePart") then
        local helmet = createArmorPiece(
            character, head, "KnightHelmet",
            Vector3.new(1.4, 1.4, 1.4),
            CFrame.new(0, 0.05, 0),
            helmetColor, Enum.PartType.Block
        )

        if helmet then
            -- Visor strip
            createArmorPiece(
                character, helmet, "KnightVisor",
                Vector3.new(1.1, 0.2, 0.2),
                CFrame.new(0, 0.05, -0.62),
                visorColor
            )
            -- Helmet crest (top ridge)
            createArmorPiece(
                character, helmet, "KnightCrest",
                Vector3.new(0.25, 0.35, 1.2),
                CFrame.new(0, 0.65, 0),
                accentColor
            )
        end
    end

    -- Chestplate
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        local chest = createArmorPiece(
            character, torso, "KnightChestplate",
            Vector3.new(2.2, 2.1, 1.2),
            CFrame.new(0, 0, -0.1),
            armorColor
        )
        if chest then
            -- Gold trim band
            createArmorPiece(
                character, chest, "KnightChestTrim",
                Vector3.new(2.25, 0.15, 1.25),
                CFrame.new(0, 0.4, 0),
                accentColor
            )
        end
    end

    -- Shoulder pads
    local function makeShoulderPad(armName, xMirror)
        local arm = character:FindFirstChild(armName)
        if not arm or not arm:IsA("BasePart") then return end

        local pad = createArmorPiece(
            character, arm, "KnightShoulder_" .. armName,
            Vector3.new(1.3, 0.5, 1.3),
            CFrame.new(xMirror * 0.1, 0.55, 0),
            armorColor
        )
        if pad then
            createArmorPiece(
                character, pad, "KnightShoulderEdge_" .. armName,
                Vector3.new(1.35, 0.1, 1.35),
                CFrame.new(0, -0.25, 0),
                accentColor
            )
        end
    end

    -- R15 rig
    makeShoulderPad("RightUpperArm", 1)
    makeShoulderPad("LeftUpperArm", -1)
    -- R6 fallback
    makeShoulderPad("Right Arm", 1)
    makeShoulderPad("Left Arm", -1)

    -- ── Gauntlets / forearm armor ────────────────────────────────────────
    local function makeGauntlet(lowerArmName, handName)
        local lowerArm = character:FindFirstChild(lowerArmName)
        if not lowerArm or not lowerArm:IsA("BasePart") then return end

        -- Main forearm plate – wraps around the lower arm
        local bracer = createArmorPiece(
            character, lowerArm, "KnightBracer_" .. lowerArmName,
            Vector3.new(1.15, 0.85, 1.15),
            CFrame.new(0, 0, 0),
            armorColor
        )
        if bracer then
            -- Gold trim ring at the elbow end of the bracer
            createArmorPiece(
                character, bracer, "KnightBracerTrim_" .. lowerArmName,
                Vector3.new(1.2, 0.08, 1.2),
                CFrame.new(0, 0.4, 0),
                accentColor
            )
        end

        -- Hand guard – small plate over the back of the hand
        local hand = character:FindFirstChild(handName)
        if hand and hand:IsA("BasePart") then
            createArmorPiece(
                character, hand, "KnightHandGuard_" .. handName,
                Vector3.new(1.05, 0.55, 0.5),
                CFrame.new(0, 0.05, -0.2),
                armorColor
            )
        end
    end

    -- R15 rig (LowerArm + Hand)
    makeGauntlet("RightLowerArm", "RightHand")
    makeGauntlet("LeftLowerArm", "LeftHand")

    -- R6 fallback: arms are a single part, place bracer on lower half
    local function makeR6Gauntlet(armName, xMirror)
        local arm = character:FindFirstChild(armName)
        if not arm or not arm:IsA("BasePart") then return end
        -- Only add if the R15 parts weren't found (avoid doubling up)
        if character:FindFirstChild("RightLowerArm") or character:FindFirstChild("LeftLowerArm") then return end

        createArmorPiece(
            character, arm, "KnightBracer_" .. armName,
            Vector3.new(1.15, 0.8, 1.15),
            CFrame.new(0, -0.35, 0),
            armorColor
        )
        createArmorPiece(
            character, arm, "KnightBracerTrim_" .. armName,
            Vector3.new(1.2, 0.08, 1.2),
            CFrame.new(0, 0.05, 0),
            accentColor
        )
    end

    makeR6Gauntlet("Right Arm", 1)
    makeR6Gauntlet("Left Arm", -1)

    -- Belt / waist armor
    local lowerTorso = character:FindFirstChild("LowerTorso") or torso
    if lowerTorso and lowerTorso:IsA("BasePart") then
        createArmorPiece(
            character, lowerTorso, "KnightBelt",
            Vector3.new(2.1, 0.3, 1.15),
            CFrame.new(0, 0.3, -0.05),
            accentColor
        )
    end

    -- ── Full leg armor ───────────────────────────────────────────────────
    -- R15 rigs have UpperLeg, LowerLeg, Foot per side.
    -- R6 rigs have a single "Right Leg" / "Left Leg".
    local darkerArmor = Color3.fromRGB(145, 150, 160) -- slightly darker for legs

    local function makeFullLegArmor_R15(side) -- side = "Right" or "Left"
        -- Thigh armor (UpperLeg)
        local upperLeg = character:FindFirstChild(side .. "UpperLeg")
        if upperLeg and upperLeg:IsA("BasePart") then
            createArmorPiece(
                character, upperLeg, "KnightThigh_" .. side,
                Vector3.new(1.15, 1.0, 1.15),
                CFrame.new(0, 0, 0),
                darkerArmor
            )
            -- Gold stripe at the top of the thigh plate
            createArmorPiece(
                character, upperLeg, "KnightThighTrim_" .. side,
                Vector3.new(1.2, 0.08, 1.2),
                CFrame.new(0, 0.48, 0),
                accentColor
            )
        end

        -- Knee cap (joint between upper and lower leg)
        local lowerLeg = character:FindFirstChild(side .. "LowerLeg")
        if lowerLeg and lowerLeg:IsA("BasePart") then
            -- Knee guard – sits at the top of the lower leg
            createArmorPiece(
                character, lowerLeg, "KnightKnee_" .. side,
                Vector3.new(1.15, 0.4, 1.25),
                CFrame.new(0, 0.45, -0.05),
                armorColor
            )

            -- Shin plate – covers the front/sides of the lower leg
            createArmorPiece(
                character, lowerLeg, "KnightShin_" .. side,
                Vector3.new(1.1, 0.9, 1.15),
                CFrame.new(0, -0.15, -0.05),
                armorColor
            )
        end

        -- Foot / sabatons
        local foot = character:FindFirstChild(side .. "Foot")
        if foot and foot:IsA("BasePart") then
            createArmorPiece(
                character, foot, "KnightSabaton_" .. side,
                Vector3.new(1.1, 0.45, 1.2),
                CFrame.new(0, 0.05, -0.05),
                darkerArmor
            )
        end
    end

    local function makeFullLegArmor_R6(legName)
        local leg = character:FindFirstChild(legName)
        if not leg or not leg:IsA("BasePart") then return end
        -- Only use R6 path if R15 parts aren't present
        if character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("LeftUpperLeg") then return end

        -- Upper thigh plate
        createArmorPiece(
            character, leg, "KnightThigh_" .. legName,
            Vector3.new(1.15, 0.7, 1.15),
            CFrame.new(0, 0.35, 0),
            darkerArmor
        )
        -- Knee guard
        createArmorPiece(
            character, leg, "KnightKnee_" .. legName,
            Vector3.new(1.15, 0.35, 1.2),
            CFrame.new(0, 0.0, -0.05),
            armorColor
        )
        -- Shin plate (lower portion)
        createArmorPiece(
            character, leg, "KnightShin_" .. legName,
            Vector3.new(1.1, 0.7, 1.15),
            CFrame.new(0, -0.45, -0.05),
            armorColor
        )
        -- Gold trim at top of thigh
        createArmorPiece(
            character, leg, "KnightThighTrim_" .. legName,
            Vector3.new(1.2, 0.08, 1.2),
            CFrame.new(0, 0.7, 0),
            accentColor
        )
    end

    -- R15
    makeFullLegArmor_R15("Right")
    makeFullLegArmor_R15("Left")
    -- R6
    makeFullLegArmor_R6("Right Leg")
    makeFullLegArmor_R6("Left Leg")

    -- ── Back armor & cape (rear silhouette) ──────────────────────────────
    -- Back plate: a raised armored panel on the rear of the torso so the back
    -- reads as armored instead of plain black undersuit.
    if torso and torso:IsA("BasePart") then
        -- Main back plate – sits on the rear surface of the torso
        local backPlate = createArmorPiece(
            character, torso, "KnightBackPlate",
            Vector3.new(1.8, 1.6, 0.25),
            CFrame.new(0, 0.1, 0.55),
            armorColor
        )
        if backPlate then
            -- Vertical spine ridge for visual depth
            createArmorPiece(
                character, backPlate, "KnightSpineRidge",
                Vector3.new(0.2, 1.4, 0.15),
                CFrame.new(0, 0, 0.15),
                Color3.fromRGB(130, 135, 145) -- slightly darker than main armor
            )
            -- Gold trim border at the top edge of the back plate
            createArmorPiece(
                character, backPlate, "KnightBackTrim",
                Vector3.new(1.85, 0.12, 0.3),
                CFrame.new(0, 0.75, 0),
                accentColor
            )
        end

        -- Short cape – hangs from upper-back, stops above the knees.
        -- Deep royal blue with a gold bottom hem.
        local capeColor = Color3.fromRGB(25, 35, 85) -- dark royal blue
        local cape = createArmorPiece(
            character, torso, "KnightCape",
            Vector3.new(1.5, 2.2, 0.08),
            CFrame.new(0, -1.2, 0.6),
            capeColor
        )
        if cape then
            -- Gold hem at the bottom edge of the cape
            createArmorPiece(
                character, cape, "KnightCapeHem",
                Vector3.new(1.55, 0.1, 0.12),
                CFrame.new(0, -1.05, 0),
                accentColor
            )
            -- Cape clasp at the top – small gold piece connecting cape to armor
            createArmorPiece(
                character, torso, "KnightCapeClasp",
                Vector3.new(0.5, 0.2, 0.18),
                CFrame.new(0, 0.85, 0.58),
                accentColor
            )
        end
    end

    dprint(player.Name, "Knight skin applied successfully –", #character:GetChildren(), "total children")
end

-- Master apply function: protected call with death-revert failsafe
local function applySkin(player, character)
    if not character then
        dprint(player.Name, "WARN: no character for applySkin")
        return
    end

    -- Re-entry guard
    if applyingLock[player] then
        dprint(player.Name, "WARN: skin application already in progress – skipping")
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        dprint(player.Name, "WARN: humanoid dead or missing – skipping skin apply")
        return
    end

    applyingLock[player] = true
    local equipped = getEquipped(player)
    dprint(player.Name, "applySkin – equipped:", equipped)

    -- Protected call: catch ANY error during skin application
    local ok, err = pcall(function()
        local def = SkinDefs.GetById(equipped)
        if not def or def.IsDefault then
            applyDefaultSkin(player, character)
        elseif equipped == "Knight" then
            applyKnightSkin(player, character)
        else
            dprint(player.Name, "unknown skin '" .. tostring(equipped) .. "' – falling back to Default")
            applyDefaultSkin(player, character)
        end
    end)

    applyingLock[player] = nil

    if not ok then
        warn("[SkinService] ERROR applying skin '" .. tostring(equipped) .. "' to " .. player.Name .. ": " .. tostring(err))
        -- Emergency revert to Default
        local data = getOrCreateData(player)
        data.equipped = "Default"
        pcall(function()
            clearSkinCosmetics(character)
            restoreOriginalBodyColors(character)
            restoreAccessories(character)
        end)
        pushEquippedToClient(player)
        dprint(player.Name, "FAILSAFE: reverted to Default due to application error")
        return
    end

    -- Death failsafe: if the player dies within 3 seconds of a non-Default skin
    -- being applied, auto-revert to Default to break potential death loops
    if equipped ~= "Default" then
        task.spawn(function()
            local deathConn
            local reverted = false

            deathConn = humanoid.Died:Connect(function()
                if reverted then return end
                reverted = true
                warn("[SkinService] FAILSAFE: " .. player.Name .. " died within 3s of skin '" .. equipped .. "' – reverting to Default")
                local data = getOrCreateData(player)
                data.equipped = "Default"
                task.spawn(function() saveData(player) end)
                pushEquippedToClient(player)
            end)

            task.wait(3)
            if deathConn then
                deathConn:Disconnect()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------

local function onPlayerAdded(player)
    local data = getOrCreateData(player)
    data.owned["Default"] = true

    -- Validate equipped skin is still owned
    if data.equipped ~= "Default" and not data.owned[data.equipped] then
        data.equipped = "Default"
    end

    dprint(player.Name, "joined – equipped:", data.equipped)

    -- Apply skin on every character spawn (including respawns)
    player.CharacterAdded:Connect(function(character)
        -- Wait for the character to fully load
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            dprint(player.Name, "WARN: Humanoid not found after 10s")
            return
        end

        -- Wait for appearance to load before applying
        if not player:HasAppearanceLoaded() then
            player.CharacterAppearanceLoaded:Wait()
        end

        -- Yield to let character fully settle
        task.wait(0.5)

        -- Verify character is still alive after the wait
        if humanoid.Health <= 0 then
            dprint(player.Name, "WARN: humanoid dead after wait – skipping skin apply")
            return
        end

        applySkin(player, character)
    end)

    -- If already spawned, apply immediately
    if player.Character then
        task.spawn(function()
            task.wait(0.5)
            applySkin(player, player.Character)
        end)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
    saveData(player)
    playerData[player] = nil
    applyingLock[player] = nil
end)

-- Handle late-join players
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(p)
    end)
end

game:BindToClose(function()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function() saveData(p) end)
    end
    task.wait(2)
end)

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

getOwnedRF.OnServerInvoke = function(player)
    return getOwnedList(player)
end

getEquippedRF.OnServerInvoke = function(player)
    return getEquipped(player)
end

purchaseSkinRF.OnServerInvoke = function(player, skinId)
    if type(skinId) ~= "string" or #skinId == 0 then return false, 0, "invalid_id" end

    local def = SkinDefs.GetById(skinId)
    if not def then return false, 0, "unknown_skin" end

    -- Cannot purchase default or non-shop skins
    if def.IsDefault then return false, 0, "cannot_purchase_default" end
    if not def.ShopVisible then return false, 0, "not_purchasable" end

    if isOwned(player, skinId) then
        local bal = CurrencyService and CurrencyService:GetCoins(player) or 0
        return false, bal, "already_owned"
    end

    local price = def.Price or 0
    if price > 0 then
        if not CurrencyService then return false, 0, "no_currency" end
        local balance = CurrencyService:GetCoins(player)
        if balance < price then return false, balance, "not_enough_coins" end
        CurrencyService:SetCoins(player, balance - price)
    end

    local data = getOrCreateData(player)
    data.owned[skinId] = true
    dprint("Purchased", def.DisplayName, "for", player.Name)

    task.spawn(function() saveData(player) end)

    local newBal = CurrencyService and CurrencyService:GetCoins(player) or 0
    return true, newBal, "ok"
end

equipSkinRE.OnServerEvent:Connect(function(player, skinId)
    if type(skinId) ~= "string" or #skinId == 0 then return end

    local def = SkinDefs.GetById(skinId)
    if not def then return end

    -- Must own the skin (Default is always owned)
    if not isOwned(player, skinId) then return end

    local data = getOrCreateData(player)

    -- Already equipped? Do nothing
    if data.equipped == skinId then return end

    data.equipped = skinId
    dprint("Equipped skin:", skinId, "for", player.Name)

    -- Apply to current character immediately
    if player.Character then
        task.spawn(function()
            applySkin(player, player.Character)
        end)
    end

    task.spawn(function() saveData(player) end)
    pushEquippedToClient(player)
end)

--------------------------------------------------------------------------------
-- BINDABLE API  (server-to-server, used by SalvageShopService)
--------------------------------------------------------------------------------
do
    local ServerScriptService = game:GetService("ServerScriptService")

    -- CheckSkinOwnership(player, skinId) -> bool
    local checkBF = Instance.new("BindableFunction")
    checkBF.Name = "CheckSkinOwnership"
    checkBF.Parent = ServerScriptService
    checkBF.OnInvoke = function(player, skinId)
        if not player or type(skinId) ~= "string" then return false end
        return isOwned(player, skinId)
    end

    -- GrantSkin(player, skinId) -> bool
    local grantBF = Instance.new("BindableFunction")
    grantBF.Name = "GrantSkin"
    grantBF.Parent = ServerScriptService
    grantBF.OnInvoke = function(player, skinId)
        if not player or type(skinId) ~= "string" then return false end
        if isOwned(player, skinId) then return true end -- already owned, success
        local def = SkinDefs.GetById(skinId)
        if not def then
            warn("[SkinService] GrantSkin: unknown skinId:", skinId)
            return false
        end
        local data = getOrCreateData(player)
        data.owned[skinId] = true
        dprint("Granted skin", skinId, "to", player.Name, "(via BindableFunction)")
        task.spawn(function() saveData(player) end)
        return true
    end

    dprint("BindableFunction API registered (CheckSkinOwnership, GrantSkin)")
end

dprint("fully initialized")
