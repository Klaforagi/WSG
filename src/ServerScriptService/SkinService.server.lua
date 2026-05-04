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
local favoriteSkinRF     = ensureInstance(skinsFolder, "RemoteFunction", "FavoriteSkin")
local getSkinFavoritesRF = ensureInstance(skinsFolder, "RemoteFunction", "GetSkinFavorites")

dprint("Remotes created")

-- ── Per-player state ───────────────────────────────────────────────────────
-- playerData[player] = { owned = { [skinId] = true }, equipped = skinId, favorited = { [skinId] = true } }
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
        -- Load favorited map
        local favorited = {}
        if type(result.favorited) == "table" then
            for k, v in pairs(result.favorited) do
                if type(v) == "boolean" then
                    favorited[k] = v
                end
            end
        end
        return { owned = owned, equipped = equipped, favorited = favorited }
    end
    return { owned = { Default = true }, equipped = "Default", favorited = {} }
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
    local payload = { owned = ownedArr, equipped = data.equipped or "Default", favorited = data.favorited or {} }
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
local HELMET_TAG = "_SkinHelmet"

-- ── PlayerSettingsManager (for ShowHelm) ───────────────────────────────────
local PlayerSettingsManager = require(script.Parent:WaitForChild("PlayerSettingsManager"))

local function getShowHelm(player)
    local settings = PlayerSettingsManager.GetCachedSettings(player)
    if settings and settings.ShowHelm ~= nil then
        dprint("[ShowHelm] Loaded setting for", player.Name, ":", tostring(settings.ShowHelm))
        return settings.ShowHelm
    end
    dprint("[ShowHelm] No saved setting for", player.Name, ", defaulting to true")
    return true -- default ON
end

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

-- ── ShowHelm helpers ───────────────────────────────────────────────────────

-- Names of helmet cosmetic parts (used as fallback if tags are missing)
local HELMET_PART_NAMES = {
    KnightHelmet = true,
    KnightVisor = true,
    KnightCrest = true,
    IronHelmet = true,
    IronVisor = true,
}

-- Remove only helmet cosmetic parts from a character (by tag OR name)
local function clearSkinHelmetParts(character)
    if not character then return end
    local removed = 0
    -- Collect first to avoid mutating during iteration
    local toRemove = {}
    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute(HELMET_TAG) or HELMET_PART_NAMES[child.Name] then
            table.insert(toRemove, child)
        end
    end
    for _, part in ipairs(toRemove) do
        part:Destroy()
        removed = removed + 1
    end
    dprint("[ShowHelm] clearSkinHelmetParts removed", removed, "parts")
end

-- Restore original head body color (when ShowHelm is OFF but skin is equipped)
local function restoreHeadColor(character)
    local bc = character:FindFirstChildOfClass("BodyColors")
    if not bc then
        dprint("[ShowHelm] restoreHeadColor: no BodyColors found")
        return
    end
    local origHead = bc:GetAttribute("_OrigHeadColor3")
    if origHead then
        bc.HeadColor3 = origHead
        dprint("[ShowHelm] restored head color to", tostring(origHead))
    else
        dprint("[ShowHelm] restoreHeadColor: no _OrigHeadColor3 saved")
    end
end

-- Set head body color to undersuit dark (when ShowHelm is ON with a skin)
local function setHeadUndersuitColor(character)
    local bc = character:FindFirstChildOfClass("BodyColors")
    if bc then
        bc.HeadColor = BrickColor.new(Color3.fromRGB(50, 50, 55))
    end
end

-- Head-attachment names used by Roblox for accessories on the head/face
local HEAD_ATTACHMENT_NAMES = {
    HatAttachment = true,
    HairAttachment = true,
    FaceFrontAttachment = true,
    FaceCenterAttachment = true,
}

-- Check if an Accessory attaches to the head area
local function isHeadAccessory(acc)
    local handle = acc:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return false end
    -- Check for attachment points on the handle that correspond to head slots
    for _, child in ipairs(handle:GetChildren()) do
        if child:IsA("Attachment") and HEAD_ATTACHMENT_NAMES[child.Name] then
            return true
        end
    end
    -- Fallback: Roblox classic hat accessories don't always have named attachments
    -- but are welded to the Head part
    local head = acc.Parent and acc.Parent:FindFirstChild("Head")
    if head then
        for _, child in ipairs(handle:GetChildren()) do
            if child:IsA("Weld") or child:IsA("WeldConstraint") then
                if child.Part0 == head or child.Part1 == head then
                    return true
                end
            end
        end
    end
    return false
end

-- Restore visibility of head accessories only (hair, hats, face items)
local function restoreHeadAccessories(character)
    if not character then return end
    for _, acc in ipairs(character:GetChildren()) do
        if acc:IsA("Accessory") and isHeadAccessory(acc) then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local orig = handle:GetAttribute("_OrigTransparency")
                if orig ~= nil then
                    handle.Transparency = orig
                else
                    handle.Transparency = 0
                end
            end
        end
    end
    dprint("[ShowHelm] restored head accessory visibility")
end

-- Hide head accessories (when helmet is ON and covering the head)
local function hideHeadAccessories(character)
    if not character then return end
    for _, acc in ipairs(character:GetChildren()) do
        if acc:IsA("Accessory") and isHeadAccessory(acc) then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                if not handle:GetAttribute("_OrigTransparency") then
                    handle:SetAttribute("_OrigTransparency", handle.Transparency)
                end
                handle.Transparency = 1
            end
        end
    end
    dprint("[ShowHelm] hid head accessories under helmet")
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
    armor.CanTouch = false
    armor.CanQuery = false
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

-- Tag name used to identify team-colored accent parts for live recolor
local ACCENT_TAG = "_SkinAccent"

-- Wrapper: creates an armor piece AND tags it as an accent/trim piece.
local function createAccentPiece(character, limbPart, name, size, offset, color, shape)
    local part = createArmorPiece(character, limbPart, name, size, offset, color, shape)
    if part then
        part:SetAttribute(ACCENT_TAG, true)
    end
    return part
end

-- Resolve team accent color for armor trim.
-- Knights side uses blue trim, Barbarians side uses red trim, else fallback gold.
local TEAM_ACCENT_COLORS = {
    Blue = Color3.fromRGB(40, 90, 220),
    Red  = Color3.fromRGB(220, 45, 45),
}

-- Darker team colors for the cape body.
local TEAM_CAPE_COLORS = {
    Blue = Color3.fromRGB(20, 30, 120),
    Red  = Color3.fromRGB(120, 20, 20),
}

local function getTeamAccentColor(player, fallback)
    local team = player.Team
    if team and TEAM_ACCENT_COLORS[team.Name] then
        return TEAM_ACCENT_COLORS[team.Name]
    end
    return fallback or Color3.fromRGB(200, 170, 50)
end

local function getTeamCapeColor(player, fallback)
    local team = player.Team
    if team and TEAM_CAPE_COLORS[team.Name] then
        return TEAM_CAPE_COLORS[team.Name]
    end
    return fallback or Color3.fromRGB(25, 35, 85)
end

-- Recolor all accent-tagged parts on an existing character.
local CAPE_TAG = "_SkinCape"

local function updateSkinAccentColor(character, accentColor, capeColor)
    if not character then return end
    for _, child in ipairs(character:GetDescendants()) do
        if child:IsA("BasePart") then
            if child:GetAttribute(ACCENT_TAG) then
                child.Color = accentColor
            elseif capeColor and child:GetAttribute(CAPE_TAG) then
                child.Color = capeColor
            end
        end
    end
end

-- Apply only the knight helmet parts to a character (used for live toggle ON)
local function applyKnightHelmetParts(player, character)
    local def = SkinDefs.GetById("Knight")
    if not def then return end

    local helmetColor = def.HelmetColor or Color3.fromRGB(140, 145, 155)
    local visorColor  = def.VisorColor  or Color3.fromRGB(30, 30, 35)
    local accentColor = getTeamAccentColor(player, def.AccentColor or Color3.fromRGB(200, 170, 50))

    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end

    local helmet = createArmorPiece(
        character, head, "KnightHelmet",
        Vector3.new(1.4, 1.4, 1.4),
        CFrame.new(0, 0.05, 0),
        helmetColor, Enum.PartType.Block
    )
    if helmet then
        helmet:SetAttribute(HELMET_TAG, true)
        local visor = createArmorPiece(
            character, helmet, "KnightVisor",
            Vector3.new(1.1, 0.2, 0.2),
            CFrame.new(0, 0.05, -0.62),
            visorColor
        )
        if visor then visor:SetAttribute(HELMET_TAG, true) end
        local crest = createAccentPiece(
            character, helmet, "KnightCrest",
            Vector3.new(0.25, 0.35, 1.2),
            CFrame.new(0, 0.65, 0),
            accentColor
        )
        if crest then crest:SetAttribute(HELMET_TAG, true) end
    end

    setHeadUndersuitColor(character)
    dprint(player.Name, "knight helmet parts applied")
end

-- Apply only the iron knight helmet parts to a character (used for live toggle ON)
local function applyIronKnightHelmetParts(player, character)
    local def = SkinDefs.GetById("IronKnight")
    if not def then return end

    local helmetColor = def.HelmetColor or Color3.fromRGB(80, 85, 90)
    local visorColor  = def.VisorColor  or Color3.fromRGB(20, 22, 25)
    local accentColor = getTeamAccentColor(player, def.AccentColor)

    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end

    local helmet = createArmorPiece(
        character, head, "IronHelmet",
        Vector3.new(1.45, 1.45, 1.45),
        CFrame.new(0, 0.05, 0),
        helmetColor, Enum.PartType.Block
    )
    if helmet then
        helmet.Material = Enum.Material.Metal
        helmet:SetAttribute(HELMET_TAG, true)
        local visor = createArmorPiece(
            character, helmet, "IronVisor",
            Vector3.new(1.0, 0.12, 0.2),
            CFrame.new(0, 0.0, -0.64),
            visorColor
        )
        if visor then visor:SetAttribute(HELMET_TAG, true) end
    end

    local bc = character:FindFirstChildOfClass("BodyColors")
    if bc then
        bc.HeadColor = BrickColor.new(Color3.fromRGB(30, 30, 35))
    end
    dprint(player.Name, "[IronKnight] helmet parts applied (team accent)")
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
    local accentColor = getTeamAccentColor(player, def.AccentColor or Color3.fromRGB(200, 170, 50))
    local helmetColor = def.HelmetColor or Color3.fromRGB(140, 145, 155)
    local visorColor  = def.VisorColor  or Color3.fromRGB(30, 30, 35)

    dprint(player.Name, "accent color:", tostring(accentColor))

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

    -- Helmet (conditional on ShowHelm setting)
    local showHelm = getShowHelm(player)
    dprint(player.Name, "ShowHelm at spawn:", tostring(showHelm))
    if head and head:IsA("BasePart") and showHelm then
        local helmet = createArmorPiece(
            character, head, "KnightHelmet",
            Vector3.new(1.4, 1.4, 1.4),
            CFrame.new(0, 0.05, 0),
            helmetColor, Enum.PartType.Block
        )

        if helmet then
            helmet:SetAttribute(HELMET_TAG, true)
            -- Visor strip
            local visor = createArmorPiece(
                character, helmet, "KnightVisor",
                Vector3.new(1.1, 0.2, 0.2),
                CFrame.new(0, 0.05, -0.62),
                visorColor
            )
            if visor then visor:SetAttribute(HELMET_TAG, true) end
            -- Helmet crest (top ridge)
            local crest = createAccentPiece(
                character, helmet, "KnightCrest",
                Vector3.new(0.25, 0.35, 1.2),
                CFrame.new(0, 0.65, 0),
                accentColor
            )
            if crest then crest:SetAttribute(HELMET_TAG, true) end
        end
    end

    -- If ShowHelm is OFF, restore original head color so the player's face is visible
    if not showHelm then
        restoreHeadColor(character)
        restoreHeadAccessories(character)
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
            -- Team trim band
            createAccentPiece(
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
            createAccentPiece(
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
            -- Team trim ring at the elbow end of the bracer
            createAccentPiece(
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
        createAccentPiece(
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
        createAccentPiece(
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
            -- Team stripe at the top of the thigh plate
            createAccentPiece(
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
        -- Team trim at top of thigh
        createAccentPiece(
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
            -- Team trim border at the top edge of the back plate
            createAccentPiece(
                character, backPlate, "KnightBackTrim",
                Vector3.new(1.85, 0.12, 0.3),
                CFrame.new(0, 0.75, 0),
                accentColor
            )
        end

        -- Short cape – hangs from upper-back, stops above the knees.
        local capeColor = getTeamCapeColor(player)
        local cape = createArmorPiece(
            character, torso, "KnightCape",
            Vector3.new(1.5, 2.3, 0.08),
            CFrame.new(0, -0.8, 0.6),
            capeColor
        )
        if cape then
            cape:SetAttribute(CAPE_TAG, true)
            -- Team hem at the bottom edge of the cape
            createAccentPiece(
                character, cape, "KnightCapeHem",
                Vector3.new(1.55, 0.1, 0.12),
                CFrame.new(0, -1.1, 0),
                accentColor
            )
            -- Cape clasp at the top – small team-colored piece connecting cape to armor
            createAccentPiece(
                character, torso, "KnightCapeClasp",
                Vector3.new(0.5, 0.2, 0.18),
                CFrame.new(0, 0.85, 0.58),
                accentColor
            )
        end
    end

    dprint(player.Name, "Knight skin applied successfully –", #character:GetChildren(), "total children")
end

-- Apply Iron Knight skin: COSMETIC OVERLAY ONLY
-- Dark iron battle-worn armor with team-colored accents.
-- Uses Metal material for a distinct heavy iron feel.
local function applyIronKnightSkin(player, character)
    dprint(player.Name, "[IronKnight] applying skin")
    clearSkinCosmetics(character)

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        dprint(player.Name, "[IronKnight] WARN: no Humanoid – aborting")
        return
    end

    local def = SkinDefs.GetById("IronKnight")
    if not def then
        dprint(player.Name, "[IronKnight] WARN: definition not found")
        return
    end

    local armorColor  = def.ArmorColor  or Color3.fromRGB(90, 95, 100)
    local accentColor = getTeamAccentColor(player, def.AccentColor)
    local helmetColor = def.HelmetColor or Color3.fromRGB(80, 85, 90)
    local visorColor  = def.VisorColor  or Color3.fromRGB(20, 22, 25)
    local darkerArmor = Color3.fromRGB(70, 75, 80)

    dprint(player.Name, "[IronKnight] team accent color:", tostring(accentColor))

    -- Helper to set Metal material on a piece for the battle-worn iron look
    local function setMetal(part)
        if part then part.Material = Enum.Material.Metal end
        return part
    end

    -- ── Step 1: Save + override body colors (very dark undersuit) ────────
    saveOriginalBodyColors(character)
    local bodyColors = character:FindFirstChildOfClass("BodyColors")
    if bodyColors then
        local undersuitColor = BrickColor.new(Color3.fromRGB(30, 30, 35))
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

    -- Helmet (conditional on ShowHelm setting)
    local showHelm = getShowHelm(player)
    dprint(player.Name, "[IronKnight] ShowHelm:", tostring(showHelm))
    if head and head:IsA("BasePart") and showHelm then
        local helmet = createArmorPiece(
            character, head, "IronHelmet",
            Vector3.new(1.45, 1.45, 1.45),
            CFrame.new(0, 0.05, 0),
            helmetColor, Enum.PartType.Block
        )
        if helmet then
            helmet.Material = Enum.Material.Metal
            helmet:SetAttribute(HELMET_TAG, true)
            local visor = createArmorPiece(
                character, helmet, "IronVisor",
                Vector3.new(1.0, 0.12, 0.2),
                CFrame.new(0, 0.0, -0.64),
                visorColor
            )
            if visor then visor:SetAttribute(HELMET_TAG, true) end
        end
    end

    if not showHelm then
        restoreHeadColor(character)
        restoreHeadAccessories(character)
    end

    -- Chestplate – heavy dark iron
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        local chest = setMetal(createArmorPiece(
            character, torso, "IronChestplate",
            Vector3.new(2.3, 2.15, 1.25),
            CFrame.new(0, 0, -0.1),
            armorColor
        ))
        if chest then
            setMetal(createAccentPiece(
                character, chest, "IronChestTrim",
                Vector3.new(2.35, 0.12, 1.3),
                CFrame.new(0, 0.45, 0),
                accentColor
            ))
            setMetal(createArmorPiece(
                character, chest, "IronChestRidge",
                Vector3.new(0.2, 1.6, 0.15),
                CFrame.new(0, 0, -0.1),
                Color3.fromRGB(75, 80, 85)
            ))
        end
    end

    -- Shoulder pads – heavier than Knight
    local function makeIronShoulder(armName, xMirror)
        local arm = character:FindFirstChild(armName)
        if not arm or not arm:IsA("BasePart") then return end

        local pad = setMetal(createArmorPiece(
            character, arm, "IronShoulder_" .. armName,
            Vector3.new(1.4, 0.55, 1.4),
            CFrame.new(xMirror * 0.1, 0.55, 0),
            armorColor
        ))
        if pad then
            setMetal(createAccentPiece(
                character, pad, "IronShoulderEdge_" .. armName,
                Vector3.new(1.45, 0.08, 1.45),
                CFrame.new(0, -0.27, 0),
                accentColor
            ))
            setMetal(createArmorPiece(
                character, pad, "IronShoulderRivet_" .. armName,
                Vector3.new(0.2, 0.15, 0.2),
                CFrame.new(0, 0.25, 0),
                Color3.fromRGB(60, 65, 70), Enum.PartType.Cylinder
            ))
        end
    end

    makeIronShoulder("RightUpperArm", 1)
    makeIronShoulder("LeftUpperArm", -1)
    makeIronShoulder("Right Arm", 1)
    makeIronShoulder("Left Arm", -1)

    -- ── Gauntlets / forearm armor ────────────────────────────────────────
    local function makeIronGauntlet(lowerArmName, handName)
        local lowerArm = character:FindFirstChild(lowerArmName)
        if not lowerArm or not lowerArm:IsA("BasePart") then return end

        local bracer = setMetal(createArmorPiece(
            character, lowerArm, "IronBracer_" .. lowerArmName,
            Vector3.new(1.2, 0.9, 1.2),
            CFrame.new(0, 0, 0),
            armorColor
        ))
        if bracer then
            setMetal(createAccentPiece(
                character, bracer, "IronBracerTrim_" .. lowerArmName,
                Vector3.new(1.25, 0.08, 1.25),
                CFrame.new(0, 0.42, 0),
                accentColor
            ))
        end

        local hand = character:FindFirstChild(handName)
        if hand and hand:IsA("BasePart") then
            setMetal(createArmorPiece(
                character, hand, "IronHandGuard_" .. handName,
                Vector3.new(1.1, 0.55, 0.5),
                CFrame.new(0, 0.05, -0.2),
                armorColor
            ))
        end
    end

    makeIronGauntlet("RightLowerArm", "RightHand")
    makeIronGauntlet("LeftLowerArm", "LeftHand")

    local function makeR6IronGauntlet(armName)
        local arm = character:FindFirstChild(armName)
        if not arm or not arm:IsA("BasePart") then return end
        if character:FindFirstChild("RightLowerArm") or character:FindFirstChild("LeftLowerArm") then return end

        setMetal(createArmorPiece(
            character, arm, "IronBracer_" .. armName,
            Vector3.new(1.2, 0.85, 1.2),
            CFrame.new(0, -0.35, 0),
            armorColor
        ))
        setMetal(createAccentPiece(
            character, arm, "IronBracerTrim_" .. armName,
            Vector3.new(1.25, 0.08, 1.25),
            CFrame.new(0, 0.05, 0),
            accentColor
        ))
    end

    makeR6IronGauntlet("Right Arm")
    makeR6IronGauntlet("Left Arm")

    -- Belt / waist armor
    local lowerTorso = character:FindFirstChild("LowerTorso") or torso
    if lowerTorso and lowerTorso:IsA("BasePart") then
        setMetal(createAccentPiece(
            character, lowerTorso, "IronBelt",
            Vector3.new(2.15, 0.35, 1.2),
            CFrame.new(0, 0.3, -0.05),
            accentColor
        ))
    end

    -- ── Full leg armor ───────────────────────────────────────────────────
    local function makeIronLeg_R15(side)
        local upperLeg = character:FindFirstChild(side .. "UpperLeg")
        if upperLeg and upperLeg:IsA("BasePart") then
            setMetal(createArmorPiece(
                character, upperLeg, "IronThigh_" .. side,
                Vector3.new(1.2, 1.05, 1.2),
                CFrame.new(0, 0, 0),
                darkerArmor
            ))
            setMetal(createAccentPiece(
                character, upperLeg, "IronThighTrim_" .. side,
                Vector3.new(1.25, 0.08, 1.25),
                CFrame.new(0, 0.5, 0),
                accentColor
            ))
        end

        local lowerLeg = character:FindFirstChild(side .. "LowerLeg")
        if lowerLeg and lowerLeg:IsA("BasePart") then
            setMetal(createArmorPiece(
                character, lowerLeg, "IronKnee_" .. side,
                Vector3.new(1.2, 0.45, 1.3),
                CFrame.new(0, 0.45, -0.05),
                armorColor
            ))
            setMetal(createArmorPiece(
                character, lowerLeg, "IronShin_" .. side,
                Vector3.new(1.15, 0.95, 1.2),
                CFrame.new(0, -0.15, -0.05),
                armorColor
            ))
        end

        local foot = character:FindFirstChild(side .. "Foot")
        if foot and foot:IsA("BasePart") then
            setMetal(createArmorPiece(
                character, foot, "IronSabaton_" .. side,
                Vector3.new(1.15, 0.5, 1.25),
                CFrame.new(0, 0.05, -0.05),
                darkerArmor
            ))
        end
    end

    local function makeIronLeg_R6(legName)
        local leg = character:FindFirstChild(legName)
        if not leg or not leg:IsA("BasePart") then return end
        if character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("LeftUpperLeg") then return end

        setMetal(createArmorPiece(
            character, leg, "IronThigh_" .. legName,
            Vector3.new(1.2, 0.75, 1.2),
            CFrame.new(0, 0.35, 0),
            darkerArmor
        ))
        setMetal(createArmorPiece(
            character, leg, "IronKnee_" .. legName,
            Vector3.new(1.2, 0.4, 1.25),
            CFrame.new(0, 0.0, -0.05),
            armorColor
        ))
        setMetal(createArmorPiece(
            character, leg, "IronShin_" .. legName,
            Vector3.new(1.15, 0.75, 1.2),
            CFrame.new(0, -0.45, -0.05),
            armorColor
        ))
        setMetal(createAccentPiece(
            character, leg, "IronThighTrim_" .. legName,
            Vector3.new(1.25, 0.08, 1.25),
            CFrame.new(0, 0.72, 0),
            accentColor
        ))
    end

    makeIronLeg_R15("Right")
    makeIronLeg_R15("Left")
    makeIronLeg_R6("Right Leg")
    makeIronLeg_R6("Left Leg")

    -- ── Back armor & short cape ──────────────────────────────────────────
    if torso and torso:IsA("BasePart") then
        local backPlate = setMetal(createArmorPiece(
            character, torso, "IronBackPlate",
            Vector3.new(1.9, 1.7, 0.3),
            CFrame.new(0, 0.1, 0.55),
            armorColor
        ))
        if backPlate then
            setMetal(createArmorPiece(
                character, backPlate, "IronSpineRidge",
                Vector3.new(0.25, 1.5, 0.15),
                CFrame.new(0, 0, 0.15),
                Color3.fromRGB(65, 70, 75)
            ))
            setMetal(createAccentPiece(
                character, backPlate, "IronBackTrim",
                Vector3.new(1.95, 0.1, 0.35),
                CFrame.new(0, 0.8, 0),
                accentColor
            ))
        end

        -- Short cape using team color (mirrors regular Knight cape logic)
        local capeColor = getTeamCapeColor(player)
        local cape = createArmorPiece(
            character, torso, "IronCape",
            Vector3.new(1.4, 2.0, 0.08),
            CFrame.new(0, -0.7, 0.6),
            capeColor
        )
        if cape then
            cape:SetAttribute(CAPE_TAG, true)
            createAccentPiece(
                character, cape, "IronCapeHem",
                Vector3.new(1.45, 0.08, 0.12),
                CFrame.new(0, -0.96, 0),
                accentColor
            )
            setMetal(createAccentPiece(
                character, torso, "IronCapeClasp",
                Vector3.new(0.45, 0.2, 0.18),
                CFrame.new(0, 0.85, 0.58),
                accentColor
            ))
        end
    end

    dprint(player.Name, "[IronKnight] skin applied successfully –", #character:GetChildren(), "total children")
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
        elseif equipped == "IronKnight" then
            applyIronKnightSkin(player, character)
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

    -- ── Live team-color update: recolor accent trim when team changes ────
    player:GetPropertyChangedSignal("Team"):Connect(function()
        local character = player.Character
        if not character then return end
        local eq = getEquipped(player)
        if eq == "Default" then return end
        local newColor = getTeamAccentColor(player)
        local newCape = getTeamCapeColor(player)
        updateSkinAccentColor(character, newColor, newCape)
        dprint(player.Name, "team changed – accent recolored to", tostring(newColor))
    end)

    -- Apply skin on every character spawn (including respawns).
    -- For non-Default skins the character is hidden until the cosmetic layer
    -- is fully attached so the player never sees a flash of the bare avatar.
    player.CharacterAdded:Connect(function(character)
        dprint(player.Name, "CharacterAdded – starting skin pipeline")

        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            dprint(player.Name, "WARN: Humanoid not found after 10s")
            return
        end

        local equipped = getEquipped(player)
        local needsSkin = equipped ~= "Default"

        -- ── Visibility suppression for non-Default skins ─────────────
        -- Hide every BasePart + accessory handle so the bare Roblox avatar
        -- is never visible while we wait for appearance data to arrive.
        local hiddenParts = {} -- { BasePart = originalTransparency }
        if needsSkin then
            dprint(player.Name, "hiding character pending skin apply")
            for _, desc in ipairs(character:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Transparency < 1 then
                    hiddenParts[desc] = desc.Transparency
                    desc.Transparency = 1
                end
            end
            -- Also catch parts/accessories that replicate slightly later
            local hideConn
            hideConn = character.DescendantAdded:Connect(function(desc)
                if desc:IsA("BasePart") and desc.Transparency < 1
                    and not desc:GetAttribute("_SkinCosmetic") then
                    hiddenParts[desc] = desc.Transparency
                    desc.Transparency = 1
                end
            end)
            task.delay(3, function()
                -- Safety: if something goes wrong, reveal after 3s max
                if hideConn.Connected then
                    hideConn:Disconnect()
                    for part, orig in pairs(hiddenParts) do
                        if part and part.Parent and not part:GetAttribute("_OrigTransparency") then
                            part.Transparency = orig
                        end
                    end
                    hiddenParts = {}
                end
            end)

            local function revealCharacter()
                if hideConn.Connected then hideConn:Disconnect() end
                for part, orig in pairs(hiddenParts) do
                    if part and part.Parent then
                        -- Skip parts the skin intentionally keeps hidden (e.g. accessory handles)
                        if not part:GetAttribute("_OrigTransparency") then
                            part.Transparency = orig
                        end
                    end
                end
                hiddenParts = {}
                dprint(player.Name, "character revealed with skin")
            end

            -- Wait for body parts to exist so the skin can attach properly
            if not player:HasAppearanceLoaded() then
                player.CharacterAppearanceLoaded:Wait()
            end

            -- Pre-save correct original transparency for accessory handles before
            -- the skin runs, so applyKnightSkin records the true value (not our
            -- temporary hidden transparency of 1).
            for _, acc in ipairs(character:GetChildren()) do
                if acc:IsA("Accessory") then
                    local handle = acc:FindFirstChild("Handle")
                    if handle and handle:IsA("BasePart") and hiddenParts[handle] ~= nil then
                        handle:SetAttribute("_OrigTransparency", hiddenParts[handle])
                    end
                end
            end

            -- Verify character is still alive
            if humanoid.Health <= 0 then
                revealCharacter()
                dprint(player.Name, "WARN: humanoid dead after appearance wait – skipping")
                return
            end

            applySkin(player, character)
            revealCharacter()
        else
            -- Default skin: no hiding needed, just wait for appearance normally
            if not player:HasAppearanceLoaded() then
                player.CharacterAppearanceLoaded:Wait()
            end
            if humanoid.Health <= 0 then
                dprint(player.Name, "WARN: humanoid dead – skipping default skin apply")
                return
            end
            applySkin(player, character)
        end

        dprint(player.Name, "skin pipeline complete")
    end)

    -- If already spawned, apply immediately
    if player.Character then
        task.spawn(function()
            applySkin(player, player.Character)
        end)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

Players.PlayerRemoving:Connect(function(player)
    if SaveGuard:ClaimSave(player, "Skin") then
        saveData(player)
        SaveGuard:ReleaseSave(player, "Skin")
    end
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
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if SaveGuard:ClaimSave(p, "Skin") then
                saveData(p)
                SaveGuard:ReleaseSave(p, "Skin")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
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
-- SKIN FAVORITES
--------------------------------------------------------------------------------
favoriteSkinRF.OnServerInvoke = function(player, skinId, state)
    if type(skinId) ~= "string" or type(state) ~= "boolean" then return false end
    local def = SkinDefs.GetById(skinId)
    if not def then return false end
    local data = getOrCreateData(player)
    if not data.favorited then data.favorited = {} end
    data.favorited[skinId] = state or nil
    dprint("FavoriteSkin:", skinId, "=", tostring(state), "for", player.Name)
    task.spawn(function() saveData(player) end)
    return true
end

getSkinFavoritesRF.OnServerInvoke = function(player)
    local data = getOrCreateData(player)
    return data.favorited or {}
end

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

    -- GetSkinOwnedCount(player) -> number (excludes Default)
    local countBF = Instance.new("BindableFunction")
    countBF.Name = "GetSkinOwnedCount"
    countBF.Parent = ServerScriptService
    countBF.OnInvoke = function(player)
        if not player then return 0 end
        local list = getOwnedList(player)
        local count = 0
        for _, id in ipairs(list) do
            if id ~= "Default" then count = count + 1 end
        end
        return count
    end
end

--------------------------------------------------------------------------------
-- SHOWHELM LIVE TOGGLE
-- Listen for ShowHelm setting changes and update the character in real-time.
--------------------------------------------------------------------------------
do
    local updateEV = ReplicatedStorage:WaitForChild("UpdatePlayerSetting", 10)
    if updateEV and updateEV:IsA("RemoteEvent") then
        updateEV.OnServerEvent:Connect(function(player, key, value)
            if key ~= "ShowHelm" then return end

            dprint("[ShowHelm] Toggle received from", player.Name, "value:", tostring(value))

            local character = player.Character
            if not character then
                dprint("[ShowHelm] No character for", player.Name)
                return
            end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then
                dprint("[ShowHelm] Humanoid dead or missing for", player.Name)
                return
            end

            local equipped = getEquipped(player)
            dprint("[ShowHelm] Found equipped skin:", tostring(equipped))
            if equipped == "Default" then
                dprint("[ShowHelm] Default skin, nothing to toggle")
                return
            end

            if value then
                -- ShowHelm ON: rebuild helmet parts, re-hide head accessories
                dprint("[ShowHelm] Restoring skin helm for", player.Name)
                clearSkinHelmetParts(character) -- prevent duplicates
                hideHeadAccessories(character)
                if equipped == "Knight" then
                    applyKnightHelmetParts(player, character)
                elseif equipped == "IronKnight" then
                    applyIronKnightHelmetParts(player, character)
                end
            else
                -- ShowHelm OFF: remove helmet parts, restore head appearance + accessories
                dprint("[ShowHelm] Removing helmet cosmetics from", player.Name)
                clearSkinHelmetParts(character)
                restoreHeadColor(character)
                restoreHeadAccessories(character)
            end
        end)
        dprint("[ShowHelm] live toggle listener registered on UpdatePlayerSetting")
    else
        warn("[SkinService] UpdatePlayerSetting remote not found after 10s – ShowHelm live toggle disabled")
    end
end

dprint("fully initialized")
