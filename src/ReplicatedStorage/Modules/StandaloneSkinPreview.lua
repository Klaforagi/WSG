--------------------------------------------------------------------------------
-- StandaloneSkinPreview.lua  –  Client-side 3D skin preview for stall cards
--
-- Builds a preview rig from the player's avatar, strips existing cosmetics,
-- applies the selected skin's armor overlay matching SkinService.server.lua,
-- and renders it inside a ViewportFrame.
--
-- Usage: StandaloneSkinPreview.RenderSkinPreview(viewportFrame, skinId, options)
--        StandaloneSkinPreview.Update(viewportFrame, skinId, showHelm)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinDefs = require(ReplicatedStorage:WaitForChild("SkinDefinitions"))

local SkinPreview = {}
local buildRig
local restoreHeadAccessories
local restoreHeadColor
local saveOriginalAppearance
local restoreHeadFaceDetails
local stripAppliedSkinArtifacts

local APPLIED_MODEL_NAME = "AppliedCharacterSkin"
local FULL_BODY_ATTRIBUTE = "FullBodySkin"
local PREVIEW_FOLDER_NAME = "SkinPreviews"
local MOTOR_NAME_PREFIX = "SkinMotor_"
local SAVED_TRANSPARENCY_ATTRIBUTE = "_OrigTransparency"
local DEBUG_LOGS = false
local warnedMessages = {}

local cachedHumanoidDescription = nil
local cachedBaseRig = nil
local cachedHeadSourceRig = nil
local warmupStarted = false

local function dprint(...)
    if DEBUG_LOGS then
        print("[StandaloneSkinPreview]", ...)
    end
end

local function warnOnce(key, ...)
    key = tostring(key or "unknown")
    if warnedMessages[key] then
        return
    end
    warnedMessages[key] = true
    warn("[CosmeticsPreview]", ...)
end

local function stripScripts(instance)
    for _, d in ipairs(instance:GetDescendants()) do
        if d:IsA("BaseScript") then
            d:Destroy()
        end
    end
end

local function buildRigFromDescription(desc)
    if not desc then
        return nil
    end

    local ok, rig = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)

    if ok and rig then
        stripScripts(rig)
        stripAppliedSkinArtifacts(rig)
        saveOriginalAppearance(rig)
        return rig
    end

    return nil
end

local function buildHeadSourceRigFromDescription(desc)
    if not desc then
        return nil
    end

    local ok, rig = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)

    if ok and rig then
        stripScripts(rig)
        return rig
    end

    return nil
end

local function normalizeName(name)
    return string.lower((tostring(name):gsub("[%s%p_]", "")))
end

local BODY_PART_NAMES = {
    Head = true,
    UpperTorso = true,
    LowerTorso = true,
    Torso = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    HumanoidRootPart = true,
}

local ROOT_BINDINGS = {
    { targetNames = { "HumanoidRootPart" }, sourceAliases = { "humanoidrootpart", "root", "rootpart", "rigroot", "hipsroot" } },
    { targetNames = { "UpperTorso", "Torso" }, sourceAliases = { "uppertorso", "torso", "body", "chest", "mainbody" } },
    { targetNames = { "LowerTorso", "Torso" }, sourceAliases = { "lowertorso", "waist", "hips", "pelvis" } },
    { targetNames = { "Head" }, sourceAliases = { "head", "helmetroot", "helmet", "helm" } },
    { targetNames = { "LeftUpperArm", "Left Arm" }, sourceAliases = { "leftupperarm", "leftarm", "larm", "leftshoulder" } },
    { targetNames = { "LeftLowerArm", "Left Arm" }, sourceAliases = { "leftlowerarm", "leftforearm", "leftelbow", "leftgauntlet" } },
    { targetNames = { "LeftHand", "Left Arm" }, sourceAliases = { "lefthand", "leftglove" } },
    { targetNames = { "RightUpperArm", "Right Arm" }, sourceAliases = { "rightupperarm", "rightarm", "rarm", "rightshoulder" } },
    { targetNames = { "RightLowerArm", "Right Arm" }, sourceAliases = { "rightlowerarm", "rightforearm", "rightelbow", "rightgauntlet" } },
    { targetNames = { "RightHand", "Right Arm" }, sourceAliases = { "righthand", "rightglove" } },
    { targetNames = { "LeftUpperLeg", "Left Leg" }, sourceAliases = { "leftupperleg", "leftleg", "lleg", "leftthigh" } },
    { targetNames = { "LeftLowerLeg", "Left Leg" }, sourceAliases = { "leftlowerleg", "leftshin", "leftcalf", "leftknee" } },
    { targetNames = { "LeftFoot", "Left Leg" }, sourceAliases = { "leftfoot", "leftboot" } },
    { targetNames = { "RightUpperLeg", "Right Leg" }, sourceAliases = { "rightupperleg", "rightleg", "rleg", "rightthigh" } },
    { targetNames = { "RightLowerLeg", "Right Leg" }, sourceAliases = { "rightlowerleg", "rightshin", "rightcalf", "rightknee" } },
    { targetNames = { "RightFoot", "Right Leg" }, sourceAliases = { "rightfoot", "rightboot" } },
}

--------------------------------------------------------------------------------
-- COLOR MAPS  (match SkinService.server.lua exactly)
--------------------------------------------------------------------------------
local KNIGHT_COLORS = {
    armor   = Color3.fromRGB(160, 165, 175),
    accent  = Color3.fromRGB(200, 170, 50),
    helmet  = Color3.fromRGB(140, 145, 155),
    visor   = Color3.fromRGB(30, 30, 35),
    darker  = Color3.fromRGB(145, 150, 160),
    cape    = Color3.fromRGB(25, 35, 85),
    spine   = Color3.fromRGB(130, 135, 145),
}

local IRON_COLORS = {
    armor      = Color3.fromRGB(90, 95, 100),
    accent     = Color3.fromRGB(35, 190, 75),
    helmet     = Color3.fromRGB(80, 85, 90),
    visor      = Color3.fromRGB(20, 22, 25),
    darker     = Color3.fromRGB(70, 75, 80),
    cape       = Color3.fromRGB(25, 35, 85),
    spine      = Color3.fromRGB(65, 70, 75),
    chestRidge = Color3.fromRGB(75, 80, 85),
    rivet      = Color3.fromRGB(60, 65, 70),
}

--------------------------------------------------------------------------------
-- TEAM COLOR RESOLUTION  (matches SkinService.server.lua)
--------------------------------------------------------------------------------
local TEAM_ACCENT_COLORS = {
    Blue = Color3.fromRGB(40, 90, 220),
    Red  = Color3.fromRGB(220, 45, 45),
}

local TEAM_CAPE_COLORS = {
    Blue = Color3.fromRGB(20, 30, 120),
    Red  = Color3.fromRGB(120, 20, 20),
}

local function getPreviewTeamAccentColor(fallback)
    local player = Players.LocalPlayer
    local team = player and player.Team
    if team and TEAM_ACCENT_COLORS[team.Name] then
        return TEAM_ACCENT_COLORS[team.Name]
    end
    return fallback or Color3.fromRGB(200, 170, 50)
end

local function getPreviewTeamCapeColor(fallback)
    local player = Players.LocalPlayer
    local team = player and player.Team
    if team and TEAM_CAPE_COLORS[team.Name] then
        return TEAM_CAPE_COLORS[team.Name]
    end
    return fallback or Color3.fromRGB(25, 35, 85)
end

--------------------------------------------------------------------------------
-- PIECE DEFINITIONS
--------------------------------------------------------------------------------
local KNIGHT_HELM = {
    {"KnightHelmet",  "Head",          {1.4,1.4,1.4},    {0,0.05,0},     "helmet", nil, "Block"},
    {"KnightVisor",   "KnightHelmet",  {1.1,0.2,0.2},    {0,0.05,-0.62}, "visor"},
    {"KnightCrest",   "KnightHelmet",  {0.25,0.35,1.2},   {0,0.65,0},     "accent"},
}

local KNIGHT_BODY = {
    {"KnightChestplate",     "UpperTorso|Torso", {2.2,2.1,1.2},   {0,0,-0.1},      "armor"},
    {"KnightChestTrim",      "KnightChestplate", {2.25,0.15,1.25}, {0,0.4,0},       "accent"},
    {"KnightBackPlate",      "UpperTorso|Torso", {1.8,1.6,0.25},  {0,0.1,0.55},    "armor"},
    {"KnightSpineRidge",     "KnightBackPlate",  {0.2,1.4,0.15},  {0,0,0.15},      "spine"},
    {"KnightBackTrim",       "KnightBackPlate",  {1.85,0.12,0.3}, {0,0.75,0},      "accent"},
    {"KnightCape",           "UpperTorso|Torso", {1.5,2.3,0.08},  {0,-0.8,0.6},    "cape"},
    {"KnightCapeHem",        "KnightCape",       {1.55,0.1,0.12}, {0,-1.1,0},      "accent"},
    {"KnightCapeClasp",      "UpperTorso|Torso", {0.5,0.2,0.18},  {0,0.85,0.58},   "accent"},
    {"KnightBelt",           "LowerTorso|Torso", {2.1,0.3,1.15},  {0,0.3,-0.05},   "accent"},
    {"KnightShoulder_R",     "RightUpperArm|Right Arm", {1.3,0.5,1.3},   {0.1,0.55,0},    "armor"},
    {"KnightShoulderEdge_R", "KnightShoulder_R",        {1.35,0.1,1.35}, {0,-0.25,0},     "accent"},
    {"KnightShoulder_L",     "LeftUpperArm|Left Arm",   {1.3,0.5,1.3},   {-0.1,0.55,0},   "armor"},
    {"KnightShoulderEdge_L", "KnightShoulder_L",        {1.35,0.1,1.35}, {0,-0.25,0},     "accent"},
    {"KnightBracer_R",       "RightLowerArm",    {1.15,0.85,1.15},{0,0,0},         "armor"},
    {"KnightBracerTrim_R",   "KnightBracer_R",   {1.2,0.08,1.2}, {0,0.4,0},       "accent"},
    {"KnightBracer_L",       "LeftLowerArm",     {1.15,0.85,1.15},{0,0,0},         "armor"},
    {"KnightBracerTrim_L",   "KnightBracer_L",   {1.2,0.08,1.2}, {0,0.4,0},       "accent"},
    {"KnightHandGuard_R",    "RightHand",        {1.05,0.55,0.5}, {0,0.05,-0.2},   "armor"},
    {"KnightHandGuard_L",    "LeftHand",         {1.05,0.55,0.5}, {0,0.05,-0.2},   "armor"},
    {"KnightThigh_R",        "RightUpperLeg",    {1.15,1.0,1.15}, {0,0,0},         "darker"},
    {"KnightThighTrim_R",    "RightUpperLeg",    {1.2,0.08,1.2},  {0,0.48,0},      "accent"},
    {"KnightKnee_R",         "RightLowerLeg",    {1.15,0.4,1.25}, {0,0.45,-0.05},  "armor"},
    {"KnightShin_R",         "RightLowerLeg",    {1.1,0.9,1.15},  {0,-0.15,-0.05}, "armor"},
    {"KnightSabaton_R",      "RightFoot",        {1.1,0.45,1.2},  {0,0.05,-0.05},  "darker"},
    {"KnightThigh_L",        "LeftUpperLeg",     {1.15,1.0,1.15}, {0,0,0},         "darker"},
    {"KnightThighTrim_L",    "LeftUpperLeg",     {1.2,0.08,1.2},  {0,0.48,0},      "accent"},
    {"KnightKnee_L",         "LeftLowerLeg",     {1.15,0.4,1.25}, {0,0.45,-0.05},  "armor"},
    {"KnightShin_L",         "LeftLowerLeg",     {1.1,0.9,1.15},  {0,-0.15,-0.05}, "armor"},
    {"KnightSabaton_L",      "LeftFoot",         {1.1,0.45,1.2},  {0,0.05,-0.05},  "darker"},
}

local IRON_HELM = {
    {"IronHelmet", "Head",       {1.45,1.45,1.45}, {0,0.05,0},     "helmet", "Metal", "Block"},
    {"IronVisor",  "IronHelmet", {1.0,0.12,0.2},   {0,0,-0.64},    "visor"},
}

local IRON_BODY = {
    {"IronChestplate",     "UpperTorso|Torso", {2.3,2.15,1.25}, {0,0,-0.1},      "armor",      "Metal"},
    {"IronChestTrim",      "IronChestplate",   {2.35,0.12,1.3}, {0,0.45,0},      "accent",     "Metal"},
    {"IronChestRidge",     "IronChestplate",   {0.2,1.6,0.15},  {0,0,-0.1},      "chestRidge", "Metal"},
    {"IronBackPlate",      "UpperTorso|Torso", {1.9,1.7,0.3},   {0,0.1,0.55},    "armor",  "Metal"},
    {"IronSpineRidge",     "IronBackPlate",    {0.25,1.5,0.15},  {0,0,0.15},      "spine",  "Metal"},
    {"IronBackTrim",       "IronBackPlate",    {1.95,0.1,0.35},  {0,0.8,0},       "accent", "Metal"},
    {"IronCape",           "UpperTorso|Torso", {1.4,2.0,0.08},   {0,-0.7,0.6},    "cape"},
    {"IronCapeHem",        "IronCape",         {1.45,0.08,0.12},  {0,-0.96,0},     "accent"},
    {"IronCapeClasp",      "UpperTorso|Torso", {0.45,0.2,0.18},  {0,0.85,0.58},   "accent", "Metal"},
    {"IronBelt",           "LowerTorso|Torso", {2.15,0.35,1.2},  {0,0.3,-0.05},   "accent", "Metal"},
    {"IronShoulder_R",     "RightUpperArm|Right Arm", {1.4,0.55,1.4},   {0.1,0.55,0},    "armor",  "Metal"},
    {"IronShoulderEdge_R", "IronShoulder_R",          {1.45,0.08,1.45}, {0,-0.27,0},     "accent", "Metal"},
    {"IronShoulderRivet_R","IronShoulder_R",          {0.2,0.15,0.2},   {0,0.25,0},      "rivet",  "Metal", "Cylinder"},
    {"IronShoulder_L",     "LeftUpperArm|Left Arm",   {1.4,0.55,1.4},   {-0.1,0.55,0},   "armor",  "Metal"},
    {"IronShoulderEdge_L", "IronShoulder_L",          {1.45,0.08,1.45}, {0,-0.27,0},     "accent", "Metal"},
    {"IronShoulderRivet_L","IronShoulder_L",          {0.2,0.15,0.2},   {0,0.25,0},      "rivet",  "Metal", "Cylinder"},
    {"IronBracer_R",       "RightLowerArm",    {1.2,0.9,1.2},    {0,0,0},         "armor",  "Metal"},
    {"IronBracerTrim_R",   "IronBracer_R",     {1.25,0.08,1.25}, {0,0.42,0},      "accent", "Metal"},
    {"IronBracer_L",       "LeftLowerArm",     {1.2,0.9,1.2},    {0,0,0},         "armor",  "Metal"},
    {"IronBracerTrim_L",   "IronBracer_L",     {1.25,0.08,1.25}, {0,0.42,0},      "accent", "Metal"},
    {"IronHandGuard_R",    "RightHand",        {1.1,0.55,0.5},   {0,0.05,-0.2},   "armor", "Metal"},
    {"IronHandGuard_L",    "LeftHand",         {1.1,0.55,0.5},   {0,0.05,-0.2},   "armor", "Metal"},
    {"IronThigh_R",        "RightUpperLeg",    {1.2,1.05,1.2},   {0,0,0},         "darker", "Metal"},
    {"IronThighTrim_R",    "RightUpperLeg",    {1.25,0.08,1.25}, {0,0.5,0},       "accent", "Metal"},
    {"IronKnee_R",         "RightLowerLeg",    {1.2,0.45,1.3},   {0,0.45,-0.05},  "armor",  "Metal"},
    {"IronShin_R",         "RightLowerLeg",    {1.15,0.95,1.2},  {0,-0.15,-0.05}, "armor",  "Metal"},
    {"IronSabaton_R",      "RightFoot",        {1.15,0.5,1.25},  {0,0.05,-0.05},  "darker", "Metal"},
    {"IronThigh_L",        "LeftUpperLeg",     {1.2,1.05,1.2},   {0,0,0},         "darker", "Metal"},
    {"IronThighTrim_L",    "LeftUpperLeg",     {1.25,0.08,1.25}, {0,0.5,0},       "accent", "Metal"},
    {"IronKnee_L",         "LeftLowerLeg",     {1.2,0.45,1.3},   {0,0.45,-0.05},  "armor",  "Metal"},
    {"IronShin_L",         "LeftLowerLeg",     {1.15,0.95,1.2},  {0,-0.15,-0.05}, "armor",  "Metal"},
    {"IronSabaton_L",      "LeftFoot",         {1.15,0.5,1.25},  {0,0.05,-0.05},  "darker", "Metal"},
}

local GOBLIN_BODY_COLOR = Color3.fromRGB(86, 130, 60)
local GOBLIN_HEAD_COLOR = Color3.fromRGB(106, 150, 70)

local SKIN_CONFIGS = {
    Knight = {
        colors = KNIGHT_COLORS,
        helm = KNIGHT_HELM,
        body = KNIGHT_BODY,
        undersuit = Color3.fromRGB(50, 50, 55),
        headUnder = Color3.fromRGB(50, 50, 55),
    },
    IronKnight = {
        colors = IRON_COLORS,
        helm = IRON_HELM,
        body = IRON_BODY,
        undersuit = Color3.fromRGB(30, 30, 35),
        headUnder = Color3.fromRGB(30, 30, 35),
    },
    Goblin = {
        colors = {},
        helm = {},
        body = {},
        undersuit = GOBLIN_BODY_COLOR,
        headUnder = GOBLIN_HEAD_COLOR,
    },
}

local function resolveConfigColors(skinId, config)
    local colors = {}
    for key, value in pairs(config.colors or {}) do
        colors[key] = value
    end

    local def = SkinDefs.GetById(skinId)
    if def then
        if def.ArmorColor then
            colors.armor = def.ArmorColor
        end
        if def.AccentColor then
            colors.accent = def.AccentColor
        end
        if def.HelmetColor then
            colors.helmet = def.HelmetColor
        end
        if def.VisorColor then
            colors.visor = def.VisorColor
        end
    end

    if skinId == "Knight" or skinId == "IronKnight" then
        colors.accent = getPreviewTeamAccentColor(colors.accent)
        colors.cape = getPreviewTeamCapeColor(colors.cape)
    end

    return colors
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function findPart(model, nameSpec)
    for name in string.gmatch(nameSpec, "[^|]+") do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

local function resolveColor(key, colorMap)
    return colorMap[key] or Color3.fromRGB(150, 150, 155)
end

local function resolveMaterial(mat)
    if mat == "Metal" then return Enum.Material.Metal end
    return Enum.Material.SmoothPlastic
end

local function resolveShape(shape)
    if shape == "Block" then return Enum.PartType.Block end
    if shape == "Cylinder" then return Enum.PartType.Cylinder end
    return nil
end

local function applyPieces(rig, pieces, colorMap)
    for _, spec in ipairs(pieces) do
        local name = spec[1]
        local parentNm = spec[2]
        local sz = spec[3]
        local off = spec[4]
        local colorKey = spec[5]
        local mat = spec[6]
        local shape = spec[7]

        local parent = findPart(rig, parentNm)
        if parent then
            local p = Instance.new("Part")
            p.Name = name
            p.Size = Vector3.new(sz[1], sz[2], sz[3])
            p.Color = resolveColor(colorKey, colorMap)
            p.Material = resolveMaterial(mat)
            p.CanCollide = false
            p.Anchored = true
            p.CastShadow = false
            p.CanTouch = false
            p.CanQuery = false
            local s = resolveShape(shape)
            if s then p.Shape = s end
            p.CFrame = parent.CFrame * CFrame.new(off[1], off[2], off[3])
            p.Parent = rig
        end
    end
end

local HEAD_ATTACHMENTS = {
    HatAttachment = true,
    HairAttachment = true,
    FaceFrontAttachment = true,
    FaceCenterAttachment = true,
    NeckAttachment = true,
    HeadAttachment = true,
}

local function buildAccessoryTypeLookup(typeNames)
    local wanted = {}
    for _, typeName in ipairs(typeNames) do
        wanted[typeName] = true
    end

    local lookup = {}
    for _, enumItem in ipairs(Enum.AccessoryType:GetEnumItems()) do
        if wanted[enumItem.Name] then
            lookup[enumItem] = true
        end
    end
    return lookup
end

local HEAD_ACCESSORY_TYPES = buildAccessoryTypeLookup({
    "Hat",
    "Hair",
    "Face",
    "Eyebrow",
    "Eyelash",
    "Head",
})

local function isHeadAccessory(acc)
    local handle = acc:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return false end
    local accessoryType = nil
    pcall(function()
        accessoryType = acc.AccessoryType
    end)
    if accessoryType and HEAD_ACCESSORY_TYPES[accessoryType] then
        return true
    end
    for _, child in ipairs(handle:GetChildren()) do
        if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
            return true
        end
    end
    local accessoryWeld = handle:FindFirstChild("AccessoryWeld")
    if accessoryWeld and accessoryWeld:IsA("Weld") then
        local part0 = accessoryWeld.Part0
        local part1 = accessoryWeld.Part1
        if (part0 and part0.Name == "Head") or (part1 and part1.Name == "Head") then
            return true
        end
    end
    return false
end

-- Preview-only: remove head accessories that came from a generated/cached rig.
-- Keep Head adds fresh clones from the live character later via Humanoid:AddAccessory,
-- after the preview Head has the live head attachments copied onto it.
local function stripHeadAccessoriesFromPreview(rig)
    if not rig then return end
    for _, child in ipairs(rig:GetChildren()) do
        if child:IsA("Accessory") and isHeadAccessory(child) then
            child:Destroy()
        end
    end
end

local function visiblePreviewTransparency(transparency)
    if type(transparency) == "number" and transparency < 0.99 then
        return transparency
    end
    return 0
end

local function getHeadSourceCharacter(player)
    local character = player and player.Character
    local liveHead = character and character:FindFirstChild("Head")
    if liveHead and liveHead:IsA("BasePart") then
        return character, false
    end

    if cachedHeadSourceRig and cachedHeadSourceRig.Parent == nil then
        local cachedHead = cachedHeadSourceRig:FindFirstChild("Head")
        if cachedHead and cachedHead:IsA("BasePart") then
            return cachedHeadSourceRig, true
        end
        cachedHeadSourceRig:Destroy()
        cachedHeadSourceRig = nil
    end

    local desc = cachedHumanoidDescription
    if not desc and character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            pcall(function()
                desc = humanoid:GetAppliedDescription()
            end)
        end
    end

    if not desc and player and player.UserId and player.UserId > 0 then
        pcall(function()
            desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
        end)
        cachedHumanoidDescription = desc or cachedHumanoidDescription
    end

    cachedHeadSourceRig = buildHeadSourceRigFromDescription(desc)
    if cachedHeadSourceRig then
        return cachedHeadSourceRig, true
    end

    return nil, false
end

local function findPreviewNeckAttachment(part)
    if not part then
        return nil
    end
    local rigAttachment = part:FindFirstChild("NeckRigAttachment")
    if rigAttachment and rigAttachment:IsA("Attachment") then
        return rigAttachment
    end
    local neckAttachment = part:FindFirstChild("NeckAttachment")
    if neckAttachment and neckAttachment:IsA("Attachment") then
        return neckAttachment
    end
    return nil
end

local function getSourceHeadColor(sourceCharacter, sourceHead)
    local bodyColors = sourceCharacter and sourceCharacter:FindFirstChildOfClass("BodyColors")
    local originalColor = bodyColors and bodyColors:GetAttribute("_OrigHeadColor3")
    if typeof(originalColor) == "Color3" then
        return originalColor
    end
    return sourceHead and sourceHead.Color or Color3.fromRGB(255, 255, 255)
end

local function prepareHeadCloneForPreview(headClone, sourceCharacter, sourceHead)
    stripScripts(headClone)
    headClone.Name = "Head"
    headClone.Anchored = false
    headClone.CanCollide = false
    headClone.CanTouch = false
    headClone.CanQuery = false
    headClone.Massless = true
    headClone.Transparency = visiblePreviewTransparency(headClone.Transparency)
    headClone.Color = getSourceHeadColor(sourceCharacter, sourceHead)
    pcall(function() headClone.CastShadow = sourceHead.CastShadow end)
    pcall(function() headClone.MaterialVariant = sourceHead.MaterialVariant end)

    for _, descendant in ipairs(headClone:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = false
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.Massless = true
            descendant.Transparency = visiblePreviewTransparency(descendant.Transparency)
        elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
            local visibleTransparency = visiblePreviewTransparency(descendant.Transparency)
            descendant.Transparency = visibleTransparency
            descendant:SetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE, visibleTransparency)
        end
    end
end

local function replacePreviewHeadWithSourceHead(rig, sourceCharacter)
    local sourceHead = sourceCharacter and sourceCharacter:FindFirstChild("Head")
    local oldHead = rig and rig:FindFirstChild("Head")
    if not (sourceHead and sourceHead:IsA("BasePart") and oldHead and oldHead:IsA("BasePart")) then
        return nil
    end

    local headClone = nil
    local ok, err = pcall(function()
        headClone = sourceHead:Clone()
    end)
    if not ok or not headClone then
        dprint("Head clone failed in preview", tostring(err))
        return nil
    end

    prepareHeadCloneForPreview(headClone, sourceCharacter, sourceHead)

    local oldNeck = findPreviewNeckAttachment(oldHead)
    local cloneNeck = findPreviewNeckAttachment(headClone)
    if oldNeck and cloneNeck then
        headClone.CFrame = oldNeck.WorldCFrame * cloneNeck.CFrame:Inverse()
    else
        headClone.CFrame = oldHead.CFrame
    end

    headClone.Parent = rig
    for _, descendant in ipairs(rig:GetDescendants()) do
        if descendant:IsA("Motor6D") or descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
            if descendant.Part0 == oldHead then
                descendant.Part0 = headClone
            end
            if descendant.Part1 == oldHead then
                descendant.Part1 = headClone
            end
        end
    end
    oldHead:Destroy()

    local bodyColors = rig:FindFirstChildOfClass("BodyColors")
    if bodyColors then
        bodyColors.HeadColor3 = headClone.Color
        bodyColors:SetAttribute("_OrigHeadColor3", headClone.Color)
    end

    return headClone
end

local function warnSkippedPreviewAccessory(accessoryName, reason)
    accessoryName = tostring(accessoryName or "Unknown")
    local key = "skip-preview-head-accessory-" .. accessoryName .. "-" .. tostring(reason or "")
    if warnedMessages[key] then
        return
    end
    warnedMessages[key] = true
    warn("[SkinPreview] Skipped head accessory in preview because " .. tostring(reason or "no valid head attachment was found") .. ": " .. accessoryName)
end

local function isHeadVisualChild(child)
    return child:IsA("Decal")
        or child:IsA("Texture")
        or child:IsA("SpecialMesh")
        or child:IsA("SurfaceAppearance")
        or child.ClassName == "WrapTarget"
end

local function copyLiveHeadAppearanceToPreview(rig, sourceCharacter)
    local liveHead = sourceCharacter and sourceCharacter:FindFirstChild("Head")
    local previewHead = rig and rig:FindFirstChild("Head")
    if not (liveHead and liveHead:IsA("BasePart") and previewHead and previewHead:IsA("BasePart")) then
        return false
    end

    previewHead.Color = liveHead.Color
    previewHead.Material = liveHead.Material
    previewHead.Reflectance = liveHead.Reflectance
    previewHead.Size = liveHead.Size
    previewHead.Transparency = visiblePreviewTransparency(liveHead.Transparency)
    pcall(function() previewHead.MaterialVariant = liveHead.MaterialVariant end)
    pcall(function() previewHead.CastShadow = liveHead.CastShadow end)

    if previewHead:IsA("MeshPart") and liveHead:IsA("MeshPart") then
        pcall(function() previewHead.MeshId = liveHead.MeshId end)
        pcall(function() previewHead.TextureID = liveHead.TextureID end)
        pcall(function() previewHead.RenderFidelity = liveHead.RenderFidelity end)
        pcall(function() previewHead.DoubleSided = liveHead.DoubleSided end)
    end

    for _, child in ipairs(previewHead:GetChildren()) do
        if isHeadVisualChild(child) then
            child:Destroy()
        end
    end

    for _, child in ipairs(liveHead:GetChildren()) do
        if child:IsA("Attachment") then
            local existing = previewHead:FindFirstChild(child.Name)
            if existing and existing:IsA("Attachment") then
                existing:Destroy()
            end
            child:Clone().Parent = previewHead
        elseif isHeadVisualChild(child) then
            local clone = child:Clone()
            if clone:IsA("Decal") or clone:IsA("Texture") then
                clone.Transparency = visiblePreviewTransparency(clone.Transparency)
                clone:SetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE, clone.Transparency)
            end
            clone.Parent = previewHead
        end
    end

    local bodyColors = rig:FindFirstChildOfClass("BodyColors")
    if bodyColors then
        bodyColors.HeadColor3 = liveHead.Color
        bodyColors:SetAttribute("_OrigHeadColor3", liveHead.Color)
    end

    return true
end

local function removeStaleAccessoryWelds(accessory)
    for _, descendant in ipairs(accessory:GetDescendants()) do
        if descendant:IsA("Weld") and descendant.Name == "AccessoryWeld" then
            descendant:Destroy()
        end
    end
end

local function keepOnlyMatchingHeadAttachments(accessory, previewHead)
    local handle = accessory and accessory:FindFirstChild("Handle")
    if not (handle and handle:IsA("BasePart") and previewHead and previewHead:IsA("BasePart")) then
        return false
    end

    local hasValidAttachment = false
    for _, child in ipairs(handle:GetChildren()) do
        if child:IsA("Attachment") then
            local matching = previewHead:FindFirstChild(child.Name)
            if HEAD_ATTACHMENTS[child.Name] and matching and matching:IsA("Attachment") then
                hasValidAttachment = true
            else
                child:Destroy()
            end
        end
    end

    return hasValidAttachment
end

local function prepareAccessoryCloneForPreview(accessory)
    for _, descendant in ipairs(accessory:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = false
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.Massless = true
            local visibleTransparency = visiblePreviewTransparency(descendant.Transparency)
            descendant.Transparency = visibleTransparency
            descendant:SetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE, visibleTransparency)
        end
    end
end

local function accessoryAttachedToPreviewHead(accessory, previewHead)
    local handle = accessory and accessory:FindFirstChild("Handle")
    if not (handle and handle:IsA("BasePart") and previewHead) then
        return false
    end

    local accessoryWeld = handle:FindFirstChild("AccessoryWeld")
    if not (accessoryWeld and accessoryWeld:IsA("Weld")) then
        return false
    end

    return accessoryWeld.Part0 == previewHead or accessoryWeld.Part1 == previewHead
end

local function cloneLiveHeadAccessoryToPreview(rig, humanoid, previewHead, sourceAccessory)
    local accessoryClone = nil
    local cloneOk, cloneErr = pcall(function()
        accessoryClone = sourceAccessory:Clone()
    end)
    if not cloneOk or not accessoryClone then
        warnSkippedPreviewAccessory(sourceAccessory.Name, "it could not be cloned")
        dprint("Accessory clone failed in preview", sourceAccessory.Name, tostring(cloneErr))
        return false
    end

    removeStaleAccessoryWelds(accessoryClone)

    prepareAccessoryCloneForPreview(accessoryClone)

    if keepOnlyMatchingHeadAttachments(accessoryClone, previewHead) then
        local ok, err = pcall(function()
            humanoid:AddAccessory(accessoryClone)
        end)
        if ok and accessoryAttachedToPreviewHead(accessoryClone, previewHead) then
            prepareAccessoryCloneForPreview(accessoryClone)
            return true
        end
        if not ok then
            dprint("AddAccessory failed in preview", sourceAccessory.Name, tostring(err))
        else
            dprint("AddAccessory did not attach to preview head", sourceAccessory.Name)
        end
        accessoryClone:Destroy()
    else
        accessoryClone:Destroy()
    end

    local fallbackClone = nil
    local fallbackOk, fallbackErr = pcall(function()
        fallbackClone = sourceAccessory:Clone()
    end)
    if not fallbackOk or not fallbackClone then
        warnSkippedPreviewAccessory(sourceAccessory.Name, "it could not be cloned for fallback attachment")
        dprint("Accessory fallback clone failed in preview", sourceAccessory.Name, tostring(fallbackErr))
        return false
    end

    removeStaleAccessoryWelds(fallbackClone)
    prepareAccessoryCloneForPreview(fallbackClone)

    local sourceHandle = sourceAccessory:FindFirstChild("Handle")
    local sourceHead = sourceAccessory.Parent and sourceAccessory.Parent:FindFirstChild("Head")
    local cloneHandle = fallbackClone:FindFirstChild("Handle")
    if sourceHandle and sourceHandle:IsA("BasePart") and sourceHead and sourceHead:IsA("BasePart") and cloneHandle and cloneHandle:IsA("BasePart") then
        cloneHandle.CFrame = previewHead.CFrame * sourceHead.CFrame:ToObjectSpace(sourceHandle.CFrame)
        fallbackClone.Parent = rig

        local weld = Instance.new("Weld")
        weld.Name = "AccessoryWeld"
        weld.Part0 = previewHead
        weld.Part1 = cloneHandle
        weld.C0 = previewHead.CFrame:ToObjectSpace(cloneHandle.CFrame)
        weld.C1 = CFrame.new()
        weld.Parent = cloneHandle
        prepareAccessoryCloneForPreview(fallbackClone)
        return true
    end

    fallbackClone:Destroy()
    warnSkippedPreviewAccessory(sourceAccessory.Name, "no valid head attachment was found")
    return false
end

local function applyLiveHeadAppearanceToPreview(rig, preferredPlayer)
    local player = preferredPlayer or Players.LocalPlayer
    local sourceCharacter, usedDescriptionFallback = getHeadSourceCharacter(player)
    if not sourceCharacter then
        return false
    end

    local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    stripHeadAccessoriesFromPreview(rig)

    local previewHead = replacePreviewHeadWithSourceHead(rig, sourceCharacter)
    local clonedLiveHead = previewHead ~= nil
    if not previewHead then
        local copied = copyLiveHeadAppearanceToPreview(rig, sourceCharacter)
        previewHead = rig and rig:FindFirstChild("Head")
        if not (copied and previewHead and previewHead:IsA("BasePart")) then
            return false
        end
    end

    local clonedAccessoryCount = 0
    for _, child in ipairs(sourceCharacter:GetChildren()) do
        if child:IsA("Accessory") and isHeadAccessory(child) then
            if cloneLiveHeadAccessoryToPreview(rig, humanoid, previewHead, child) then
                clonedAccessoryCount += 1
            end
        end
    end

    dprint(
        "KeepHead preview source:",
        "clonedHead=" .. tostring(clonedLiveHead),
        "headAccessories=" .. tostring(clonedAccessoryCount),
        "descriptionFallback=" .. tostring(usedDescriptionFallback)
    )

    return true
end

local function collectBaseParts(model)
    local parts = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
        end
    end
    return parts
end

stripAppliedSkinArtifacts = function(rig)
    for _, desc in ipairs(rig:GetDescendants()) do
        if desc:IsA("BaseScript") or desc:IsA("BillboardGui") or desc:IsA("ForceField") then
            desc:Destroy()
        elseif desc:IsA("Motor6D") and string.sub(desc.Name, 1, #MOTOR_NAME_PREFIX) == MOTOR_NAME_PREFIX then
            desc:Destroy()
        end
    end

    for _, child in ipairs(rig:GetChildren()) do
        if child:IsA("Model") and (child.Name == APPLIED_MODEL_NAME or child:GetAttribute("_FullBodySkinModel")) then
            child:Destroy()
        end
    end

    -- Drop generated head accessories; Keep Head re-adds live clones safely.
    stripHeadAccessoriesFromPreview(rig)
end

local function buildAliasLookup(binding)
    local lookup = {}
    for _, alias in ipairs(binding.sourceAliases) do
        lookup[normalizeName(alias)] = true
    end
    return lookup
end

local function getCharacterTargetPart(character, binding)
    for _, targetName in ipairs(binding.targetNames) do
        local part = character:FindFirstChild(targetName)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    return nil
end

local function findSourcePart(model, usedParts, binding)
    local aliases = buildAliasLookup(binding)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") and not usedParts[desc] and aliases[normalizeName(desc.Name)] then
            usedParts[desc] = true
            return desc
        end
    end
    return nil
end

local function buildRootAttachments(character, model)
    local usedParts = {}
    local attachments = {}
    for _, binding in ipairs(ROOT_BINDINGS) do
        local targetPart = getCharacterTargetPart(character, binding)
        if targetPart then
            local sourcePart = findSourcePart(model, usedParts, binding)
            if sourcePart then
                table.insert(attachments, {
                    targetPart = targetPart,
                    sourcePart = sourcePart,
                })
            end
        end
    end
    return attachments
end

local function chooseReferenceAttachment(rootAttachments)
    local priorities = {
        "HumanoidRootPart",
        "UpperTorso",
        "Torso",
        "LowerTorso",
        "Head",
    }

    for _, targetName in ipairs(priorities) do
        for _, attachment in ipairs(rootAttachments) do
            if attachment.targetPart.Name == targetName then
                return attachment
            end
        end
    end

    return rootAttachments[1]
end

local function alignModelToRig(model, rootAttachments)
    local referenceAttachment = chooseReferenceAttachment(rootAttachments)
    if not referenceAttachment then
        return false
    end

    local delta = referenceAttachment.targetPart.CFrame * referenceAttachment.sourcePart.CFrame:Inverse()
    for _, part in ipairs(collectBaseParts(model)) do
        part.CFrame = delta * part.CFrame
    end

    return true
end

local REPLACEMENT_HEAD_PART_NAMES = {
    head = true,
    face = true,
    helmet = true,
    helm = true,
    helmetroot = true,
    eye = true,
    eyes = true,
    ear = true,
    ears = true,
    mouth = true,
    nose = true,
    hair = true,
    hat = true,
    horn = true,
    horns = true,
    visor = true,
}

local function isReplacementHeadPart(part)
    if not part or not part:IsA("BasePart") then
        return false
    end

    local normalized = normalizeName(part.Name)
    if REPLACEMENT_HEAD_PART_NAMES[normalized] then
        return true
    end

    for headName in pairs(REPLACEMENT_HEAD_PART_NAMES) do
        if string.find(normalized, headName, 1, true) then
            return true
        end
    end

    return false
end

local function collectReplacementHeadParts(model, headRootPart)
    local parts = {}

    if headRootPart and headRootPart.Parent then
        parts[headRootPart] = true
    end

    for _, desc in ipairs(model:GetDescendants()) do
        if isReplacementHeadPart(desc) then
            parts[desc] = true
        end
    end

    return parts
end

local function setModelAnchored(model)
    for _, part in ipairs(collectBaseParts(model)) do
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
    end
end

local function hidePreviewBody(rig)
    for _, child in ipairs(rig:GetChildren()) do
        if child:IsA("BasePart") and BODY_PART_NAMES[child.Name] then
            child.Transparency = 1
        elseif child:IsA("Accessory") then
            local handle = child:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                handle.Transparency = 1
            end
        end
    end

    local head = rig:FindFirstChild("Head")
    if head then
        for _, desc in ipairs(head:GetDescendants()) do
            if desc:IsA("Decal") or desc:IsA("Texture") then
                desc.Transparency = 1
            end
        end
    end
end

local function findReplacementPreviewTemplate(def, skinId)
    local templateName = def.PreviewTemplateName or def.TemplateName or skinId

    local previewFolder = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
    local replicatedTemplate = previewFolder and previewFolder:FindFirstChild(templateName)
    if replicatedTemplate and replicatedTemplate:IsA("Model") then
        return replicatedTemplate
    end

    return nil
end

local function getReplacementPreviewTemplate(def, skinId)
    local replicatedTemplate = findReplacementPreviewTemplate(def, skinId)
    if replicatedTemplate then
        dprint("Using replicated preview template for", skinId)
        return replicatedTemplate:Clone()
    end

    return nil
end

local function buildReplacementPreview(skinId, showHelm)
    local def = SkinDefs.GetById(skinId)
    if not def then return nil end

    local rig = buildRig()
    if not rig then return nil end

    local replacementModel = getReplacementPreviewTemplate(def, skinId)
    if not replacementModel then
        dprint("No replacement preview template found for", skinId)
        rig:Destroy()
        return nil
    end

    saveOriginalAppearance(rig)
    local rootAttachments = buildRootAttachments(rig, replacementModel)
    if #rootAttachments == 0 then
        dprint("Replacement preview could not match body parts for", skinId)
        replacementModel:Destroy()
        rig:Destroy()
        return nil
    end

    alignModelToRig(replacementModel, rootAttachments)
    local headRootPart = nil
    for _, attachment in ipairs(rootAttachments) do
        if attachment.targetPart.Name == "Head" then
            headRootPart = attachment.sourcePart
            break
        end
    end

    local headSkinParts = collectReplacementHeadParts(replacementModel, headRootPart)

    hidePreviewBody(rig)
    if showHelm == false then
        applyLiveHeadAppearanceToPreview(rig)
        local head = rig:FindFirstChild("Head")
        if head then head.Transparency = 0 end
        restoreHeadColor(rig)
        restoreHeadFaceDetails(rig)
        restoreHeadAccessories(rig)
        for part in pairs(headSkinParts) do
            if part and part.Parent then
                part.Transparency = 1
            end
        end
    else
        for part in pairs(headSkinParts) do
            if part and part.Parent then
                local originalTransparency = part:GetAttribute("_FullBodyOrigTransparency")
                if originalTransparency == nil then originalTransparency = 0 end
                part.Transparency = originalTransparency
            end
        end
    end

    setModelAnchored(rig)
    setModelAnchored(replacementModel)

    local container = Instance.new("Model")
    container.Name = skinId .. "Preview"
    rig.Name = "PreviewRig"
    rig.Parent = container
    replacementModel.Name = APPLIED_MODEL_NAME
    replacementModel.Parent = container
    return container
end

local function setUndersuitColors(rig, color)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if not bc then return end
    local c = BrickColor.new(color)
    bc.HeadColor = c
    bc.TorsoColor = c
    bc.LeftArmColor = c
    bc.RightArmColor = c
    bc.LeftLegColor = c
    bc.RightLegColor = c
end

local function restoreBodyColors(rig)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if not bc then return end
    local h = bc:GetAttribute("_OrigHeadColor3")
    local t = bc:GetAttribute("_OrigTorsoColor3")
    local la = bc:GetAttribute("_OrigLeftArmColor3")
    local ra = bc:GetAttribute("_OrigRightArmColor3")
    local ll = bc:GetAttribute("_OrigLeftLegColor3")
    local rl = bc:GetAttribute("_OrigRightLegColor3")
    if h then bc.HeadColor3 = h end
    if t then bc.TorsoColor3 = t end
    if la then bc.LeftArmColor3 = la end
    if ra then bc.RightArmColor3 = ra end
    if ll then bc.LeftLegColor3 = ll end
    if rl then bc.RightLegColor3 = rl end
end

local function hideAccessories(rig)
    for _, acc in ipairs(rig:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                handle.Transparency = 1
            end
        end
    end
end

local function restoreAccessories(rig)
    for _, acc in ipairs(rig:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local orig = handle:GetAttribute("_OrigTransparency")
                handle.Transparency = orig or 0
            end
        end
    end
end

restoreHeadAccessories = function(rig)
    for _, acc in ipairs(rig:GetChildren()) do
        if acc:IsA("Accessory") and isHeadAccessory(acc) then
            for _, desc in ipairs(acc:GetDescendants()) do
                if desc:IsA("BasePart") then
                    local orig = desc:GetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE)
                    desc.Transparency = orig or 0
                end
            end
        end
    end
end

restoreHeadColor = function(rig)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if bc then
        local orig = bc:GetAttribute("_OrigHeadColor3")
        if orig then
            bc.HeadColor3 = orig
            dprint("Preserving player default head appearance in preview")
        else
            dprint("No _OrigHeadColor3 found – head color not restored")
        end
    end
end

restoreHeadFaceDetails = function(rig)
    local head = rig:FindFirstChild("Head")
    if not head then
        return
    end

    for _, desc in ipairs(head:GetDescendants()) do
        if desc:IsA("Decal") or desc:IsA("Texture") then
            local orig = desc:GetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE)
            if orig ~= nil then
                desc.Transparency = orig
            else
                desc.Transparency = 0
            end
        end
    end
end

local function hideHeadFaceDetails(rig)
    local head = rig:FindFirstChild("Head")
    if not head then
        return
    end

    for _, desc in ipairs(head:GetDescendants()) do
        if desc:IsA("Decal") or desc:IsA("Texture") then
            desc.Transparency = 1
        end
    end
end

saveOriginalAppearance = function(rig)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if bc then
        if not bc:GetAttribute("_OrigHeadColor3") then
            bc:SetAttribute("_OrigHeadColor3", bc.HeadColor3)
        end
        if not bc:GetAttribute("_OrigTorsoColor3") then
            bc:SetAttribute("_OrigTorsoColor3", bc.TorsoColor3)
        end
        if not bc:GetAttribute("_OrigLeftArmColor3") then
            bc:SetAttribute("_OrigLeftArmColor3", bc.LeftArmColor3)
        end
        if not bc:GetAttribute("_OrigRightArmColor3") then
            bc:SetAttribute("_OrigRightArmColor3", bc.RightArmColor3)
        end
        if not bc:GetAttribute("_OrigLeftLegColor3") then
            bc:SetAttribute("_OrigLeftLegColor3", bc.LeftLegColor3)
        end
        if not bc:GetAttribute("_OrigRightLegColor3") then
            bc:SetAttribute("_OrigRightLegColor3", bc.RightLegColor3)
        end
    end
    for _, acc in ipairs(rig:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") and handle:GetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE) == nil then
                handle:SetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE, handle.Transparency)
            end
        end
    end

    local head = rig:FindFirstChild("Head")
    if head then
        for _, desc in ipairs(head:GetDescendants()) do
            if (desc:IsA("Decal") or desc:IsA("Texture")) and desc:GetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE) == nil then
                desc:SetAttribute(SAVED_TRANSPARENCY_ATTRIBUTE, desc.Transparency)
            end
        end
    end
end

function SkinPreview.WarmupAsync()
    if warmupStarted and cachedBaseRig then
        return true
    end

    warmupStarted = true

    local localPlayer = Players.LocalPlayer
    if not cachedHumanoidDescription and localPlayer and localPlayer.UserId and localPlayer.UserId > 0 then
        pcall(function()
            cachedHumanoidDescription = Players:GetHumanoidDescriptionFromUserId(localPlayer.UserId)
        end)
    end

    if not cachedBaseRig and cachedHumanoidDescription then
        cachedBaseRig = buildRigFromDescription(cachedHumanoidDescription)
    end

    if not cachedBaseRig and localPlayer and localPlayer.Character then
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                cachedHumanoidDescription = hum:GetAppliedDescription()
            end)
            if cachedHumanoidDescription then
                cachedBaseRig = buildRigFromDescription(cachedHumanoidDescription)
            end
        end
    end

    return cachedBaseRig ~= nil
end

function SkinPreview.InvalidatePlayerAppearanceCache()
    cachedHumanoidDescription = nil
    if cachedBaseRig then
        cachedBaseRig:Destroy()
        cachedBaseRig = nil
    end
    if cachedHeadSourceRig then
        cachedHeadSourceRig:Destroy()
        cachedHeadSourceRig = nil
    end
    warmupStarted = false
end

buildRig = function()
    local player = Players.LocalPlayer
    local character = player.Character

    if cachedBaseRig then
        local clone = cachedBaseRig:Clone()
        stripAppliedSkinArtifacts(clone)
        dprint("Built preview rig from warm cache")
        return clone
    end

    if cachedHumanoidDescription then
        local rig = buildRigFromDescription(cachedHumanoidDescription)
        if rig then
            dprint("Built preview rig from cached HumanoidDescription")
            return rig
        end
    end

    if character then
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then
            local desc
            pcall(function() desc = hum:GetAppliedDescription() end)
            if desc then
                local ok, rig = pcall(function()
                    return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
                end)
                if ok and rig then
                    dprint("Built preview rig from HumanoidDescription")
                    for _, d in ipairs(rig:GetDescendants()) do
                        if d:IsA("BaseScript") then d:Destroy() end
                    end
                    stripAppliedSkinArtifacts(rig)
                    return rig
                end
            end
        end
    end

    if character then
        local rig = character:Clone()
        stripAppliedSkinArtifacts(rig)
        dprint("Built preview rig from character clone")
        return rig
    end

    dprint("No character available for preview")
    return nil
end

local function clearViewportScene(viewportFrame)
    for _, child in ipairs(viewportFrame:GetChildren()) do
        if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") or child.Name == "PreviewPlaceholder" then
            child:Destroy()
        end
    end
    viewportFrame.CurrentCamera = nil
end

local function showPlaceholder(viewportFrame, skinId)
    clearViewportScene(viewportFrame)

    local placeholder = Instance.new("TextLabel")
    placeholder.Name = "PreviewPlaceholder"
    placeholder.BackgroundTransparency = 1
    placeholder.Size = UDim2.fromScale(1, 1)
    placeholder.Font = Enum.Font.GothamBold
    placeholder.Text = "Preview unavailable"
    placeholder.TextColor3 = Color3.fromRGB(205, 210, 225)
    placeholder.TextScaled = true
    placeholder.TextWrapped = true
    placeholder.Parent = viewportFrame

    local textLimit = Instance.new("UITextSizeConstraint")
    textLimit.MinTextSize = 10
    textLimit.MaxTextSize = 18
    textLimit.Parent = placeholder

    viewportFrame:SetAttribute("PreviewSkinId", tostring(skinId or ""))
    viewportFrame:SetAttribute("PreviewFailed", true)
end

local function getPreviewMode(options)
    local mode = type(options) == "table" and tostring(options.mode or options.Mode or "") or ""
    if mode == "Card" or mode == "Small" or mode == "Thumbnail" then
        return "Card"
    end
    return "Large"
end

local function getPreviewShowHelm(options)
    if type(options) == "table" then
        if options.keepHead ~= nil then
            return options.keepHead ~= true
        end
        if options.KeepHead ~= nil then
            return options.KeepHead ~= true
        end
        if options.showHelm ~= nil then
            return options.showHelm ~= false
        end
        if options.ShowHelm ~= nil then
            return options.ShowHelm ~= false
        end
    end
    return true
end

local CAMERA_SETTINGS = {
    Card = {
        fieldOfView = 42,
        padding = 1.12,
        yawDegrees = 205,
        lookYOffset = 0.03,
        cameraYOffset = 0.03,
    },
    Large = {
        fieldOfView = 38,
        padding = 1.24,
        yawDegrees = 205,
        lookYOffset = 0.04,
        cameraYOffset = 0.06,
    },
}

local function positionPreviewModel(contentModel, mode)
    local settings = CAMERA_SETTINGS[mode] or CAMERA_SETTINGS.Large
    local _, initialSize = contentModel:GetBoundingBox()
    local height = math.max(initialSize.Y, 1)

    contentModel:PivotTo(CFrame.new(0, height * 0.5, 0) * CFrame.Angles(0, math.rad(settings.yawDegrees), 0))

    local boundsCFrame, boundsSize = contentModel:GetBoundingBox()
    local targetCenter = Vector3.new(0, math.max(boundsSize.Y, 1) * 0.5, 0)
    contentModel:PivotTo(CFrame.new(targetCenter - boundsCFrame.Position) * contentModel:GetPivot())

    return contentModel:GetBoundingBox()
end

local function setupPreviewCamera(viewportFrame, worldModel, contentModel, mode)
    local settings = CAMERA_SETTINGS[mode] or CAMERA_SETTINGS.Large
    local boundsCFrame, boundsSize = positionPreviewModel(contentModel, mode)
    local center = boundsCFrame.Position
    local width = math.max(boundsSize.X, boundsSize.Z * 0.65, 1)
    local height = math.max(boundsSize.Y, 1)

    local camera = Instance.new("Camera")
    camera.FieldOfView = settings.fieldOfView

    local viewportSize = viewportFrame and viewportFrame.AbsoluteSize
    local aspect = 1
    if viewportSize and viewportSize.Y > 0 then
        aspect = math.max(0.35, viewportSize.X / viewportSize.Y)
    end

    local verticalFov = math.rad(camera.FieldOfView)
    local horizontalFov = 2 * math.atan(math.tan(verticalFov * 0.5) * aspect)
    local distanceForHeight = (height * 0.5) / math.tan(verticalFov * 0.5)
    local distanceForWidth = (width * 0.5) / math.tan(horizontalFov * 0.5)
    local distance = math.max(distanceForHeight, distanceForWidth, 4) * settings.padding

    local lookAt = center + Vector3.new(0, height * settings.lookYOffset, 0)
    local cameraPosition = lookAt + Vector3.new(0, height * settings.cameraYOffset, distance)
    camera.CFrame = CFrame.lookAt(cameraPosition, lookAt)

    pcall(function()
        viewportFrame.Ambient = Color3.fromRGB(130, 136, 160)
        viewportFrame.LightColor = Color3.fromRGB(255, 250, 235)
        viewportFrame.LightDirection = Vector3.new(-0.35, -0.8, -0.45)
    end)

    local keyLightPart = Instance.new("Part")
    keyLightPart.Anchored = true
    keyLightPart.Transparency = 1
    keyLightPart.CanCollide = false
    keyLightPart.CanTouch = false
    keyLightPart.CanQuery = false
    keyLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    keyLightPart.CFrame = CFrame.new(center + Vector3.new(width, height * 1.15, distance * 0.45))
    keyLightPart.Parent = worldModel

    local keyLight = Instance.new("PointLight")
    keyLight.Color = Color3.fromRGB(235, 232, 220)
    keyLight.Brightness = mode == "Card" and 1.35 or 1.65
    keyLight.Range = math.max(18, distance * 2.2)
    keyLight.Parent = keyLightPart

    local fillLightPart = Instance.new("Part")
    fillLightPart.Anchored = true
    fillLightPart.Transparency = 1
    fillLightPart.CanCollide = false
    fillLightPart.CanTouch = false
    fillLightPart.CanQuery = false
    fillLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    fillLightPart.CFrame = CFrame.new(center + Vector3.new(-width * 0.9, height * 0.65, distance * 0.25))
    fillLightPart.Parent = worldModel

    local fillLight = Instance.new("PointLight")
    fillLight.Color = Color3.fromRGB(155, 172, 220)
    fillLight.Brightness = mode == "Card" and 0.55 or 0.7
    fillLight.Range = math.max(14, distance * 1.8)
    fillLight.Parent = fillLightPart

    return camera
end

local function buildViewportScene(viewportFrame, contentModel, options)
    local mode = getPreviewMode(options)
    local worldModel = Instance.new("WorldModel")
    contentModel.Parent = worldModel
    local camera = setupPreviewCamera(viewportFrame, worldModel, contentModel, mode)

    return worldModel, camera
end

local function applyViewportScene(viewportFrame, worldModel, camera)
    clearViewportScene(viewportFrame)
    worldModel.Parent = viewportFrame
    camera.Parent = viewportFrame
    viewportFrame.CurrentCamera = camera
end

function SkinPreview.Update(viewportFrame, skinId, showHelm)
    return SkinPreview.RenderSkinPreview(viewportFrame, skinId, {
        showHelm = showHelm ~= false,
        mode = "Large",
    })
end

function SkinPreview.RenderSkinPreview(viewportFrame, skinId, options)
    if not viewportFrame then return end

    options = type(options) == "table" and options or {}
    skinId = skinId or "Default"
    local mode = getPreviewMode(options)
    local showHelm = getPreviewShowHelm(options)
    local selectedDef = SkinDefs.GetById(skinId)
    local replacementSourceReady = selectedDef and selectedDef.ApplicationType == "ReplacementModel" and findReplacementPreviewTemplate(selectedDef, skinId) ~= nil
    local expectedSource = replacementSourceReady and "ReplacementModel" or "Cosmetic"

    local expectedShowHelm = showHelm and 1 or 0
    if viewportFrame:GetAttribute("PreviewSkinId") == tostring(skinId)
        and viewportFrame:GetAttribute("PreviewShowHelm") == expectedShowHelm
        and viewportFrame:GetAttribute("PreviewMode") == mode
        and viewportFrame:GetAttribute("PreviewSource") == expectedSource
        and viewportFrame.CurrentCamera
        and viewportFrame:FindFirstChildOfClass("WorldModel") then
        return true
    end

    dprint("Rendering skin preview:", tostring(skinId), "mode=" .. mode, "keepHead=" .. tostring(showHelm == false))

    if selectedDef and selectedDef.ApplicationType == "ReplacementModel" then
        local replacementPreview = buildReplacementPreview(skinId, showHelm)
        if replacementPreview then
            local worldModel, camera = buildViewportScene(viewportFrame, replacementPreview, { mode = mode })
            applyViewportScene(viewportFrame, worldModel, camera)

            viewportFrame:SetAttribute("PreviewSkinId", tostring(skinId))
            viewportFrame:SetAttribute("PreviewShowHelm", expectedShowHelm)
            viewportFrame:SetAttribute("PreviewMode", mode)
            viewportFrame:SetAttribute("PreviewSource", "ReplacementModel")
            viewportFrame:SetAttribute("PreviewFailed", nil)
            dprint("Applied skin to preview dummy:", tostring(skinId))
            return true
        end
        warnOnce("missing-replacement-" .. tostring(skinId), "Missing preview source for skinId:", tostring(skinId))
        -- Fall through to cosmetic SKIN_CONFIGS path
    end

    local rig = buildRig()
    if not rig then
        warnOnce("buildrig-" .. tostring(skinId), "Failed to render skin preview for skinId:", tostring(skinId))
        showPlaceholder(viewportFrame, skinId)
        return false
    end

    local toRemove = {}
    for _, child in ipairs(rig:GetChildren()) do
        if child:GetAttribute("_SkinCosmetic") then
            table.insert(toRemove, child)
        end
    end
    for _, child in ipairs(toRemove) do
        child:Destroy()
    end
    dprint("Cleared previous preview assets")

    saveOriginalAppearance(rig)
    local config = SKIN_CONFIGS[skinId]
    if config then
        dprint("Building preview rig for", skinId)
        local effectiveColors = resolveConfigColors(skinId, config)
        if skinId == "Knight" or skinId == "IronKnight" then
            local teamName = Players.LocalPlayer.Team and Players.LocalPlayer.Team.Name or "none"
            dprint("Resolved team color for preview:", teamName)
            dprint("Applying", skinId, "team trim color")
        end
        setUndersuitColors(rig, config.undersuit)
        hideAccessories(rig)
        applyPieces(rig, config.body, effectiveColors)

        local hasHelmPieces = config.helm and #config.helm > 0
        if showHelm and hasHelmPieces then
            hideHeadFaceDetails(rig)
            applyPieces(rig, config.helm, effectiveColors)
            dprint("ShowHelm in preview: true")
        elseif hasHelmPieces then
            applyLiveHeadAppearanceToPreview(rig)
            restoreHeadColor(rig)
            restoreHeadFaceDetails(rig)
            restoreHeadAccessories(rig)
            dprint("ShowHelm in preview: false")
        else
            if showHelm == false then
                applyLiveHeadAppearanceToPreview(rig)
                restoreHeadFaceDetails(rig)
                restoreHeadAccessories(rig)
            else
                hideHeadFaceDetails(rig)
            end
            dprint("ShowHelm in preview: n/a (no helm pieces)")
        end

        dprint("Applied skin to preview rig:", skinId)
    else
        dprint("Building preview rig for Default")
        restoreBodyColors(rig)
        restoreAccessories(rig)
        dprint("Applied skin to preview rig: Default")
    end

    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end

    local worldModel, camera = buildViewportScene(viewportFrame, rig, { mode = mode })
    applyViewportScene(viewportFrame, worldModel, camera)

    viewportFrame:SetAttribute("PreviewSkinId", tostring(skinId))
    viewportFrame:SetAttribute("PreviewShowHelm", expectedShowHelm)
    viewportFrame:SetAttribute("PreviewMode", mode)
    viewportFrame:SetAttribute("PreviewSource", "Cosmetic")
    viewportFrame:SetAttribute("PreviewFailed", nil)
    return true
end

return SkinPreview