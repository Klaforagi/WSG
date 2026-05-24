--------------------------------------------------------------------------------
-- SkinPreview.lua  –  Client-side 3D skin preview for Inventory ViewportFrame
--
-- Builds a preview rig from the player's avatar, strips existing cosmetics,
-- applies the selected skin's armor overlay matching SkinService.server.lua,
-- and renders it inside a ViewportFrame.
--
-- Usage:  SkinPreview.Update(viewportFrame, skinId, showHelm)
--------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinDefs = require(ReplicatedStorage:WaitForChild("SkinDefinitions"))

local SkinPreview = {}
local buildRig
local restoreHeadAccessories
local restoreHeadColor
local saveOriginalAppearance

local APPLIED_MODEL_NAME = "AppliedCharacterSkin"
local FULL_BODY_ATTRIBUTE = "FullBodySkin"
local PREVIEW_FOLDER_NAME = "SkinPreviews"
local MOTOR_NAME_PREFIX = "SkinMotor_"

local function dprint(...)
    print("[SkinsPreview]", ...)
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
-- Format: { name, parentPart, {sX,sY,sZ}, {oX,oY,oZ}, colorKey [, mat [, shape]] }
-- parentPart uses "|" for R15|R6 fallback (e.g. "UpperTorso|Torso")
-- mat: nil = SmoothPlastic, "Metal" = Metal
-- shape: nil = default, "Block" = Block, "Cylinder" = Cylinder
--------------------------------------------------------------------------------

-- Knight helmet pieces (conditional on showHelm)
local KNIGHT_HELM = {
    {"KnightHelmet",  "Head",          {1.4,1.4,1.4},    {0,0.05,0},     "helmet", nil, "Block"},
    {"KnightVisor",   "KnightHelmet",  {1.1,0.2,0.2},    {0,0.05,-0.62}, "visor"},
    {"KnightCrest",   "KnightHelmet",  {0.25,0.35,1.2},   {0,0.65,0},     "accent"},
}

-- Knight body pieces (always applied)
local KNIGHT_BODY = {
    -- Chest
    {"KnightChestplate",     "UpperTorso|Torso", {2.2,2.1,1.2},   {0,0,-0.1},      "armor"},
    {"KnightChestTrim",      "KnightChestplate", {2.25,0.15,1.25}, {0,0.4,0},       "accent"},
    -- Back
    {"KnightBackPlate",      "UpperTorso|Torso", {1.8,1.6,0.25},  {0,0.1,0.55},    "armor"},
    {"KnightSpineRidge",     "KnightBackPlate",  {0.2,1.4,0.15},  {0,0,0.15},      "spine"},
    {"KnightBackTrim",       "KnightBackPlate",  {1.85,0.12,0.3}, {0,0.75,0},      "accent"},
    -- Cape
    {"KnightCape",           "UpperTorso|Torso", {1.5,2.3,0.08},  {0,-0.8,0.6},    "cape"},
    {"KnightCapeHem",        "KnightCape",       {1.55,0.1,0.12}, {0,-1.1,0},      "accent"},
    {"KnightCapeClasp",      "UpperTorso|Torso", {0.5,0.2,0.18},  {0,0.85,0.58},   "accent"},
    -- Belt
    {"KnightBelt",           "LowerTorso|Torso", {2.1,0.3,1.15},  {0,0.3,-0.05},   "accent"},
    -- Right shoulder
    {"KnightShoulder_R",     "RightUpperArm|Right Arm", {1.3,0.5,1.3},   {0.1,0.55,0},    "armor"},
    {"KnightShoulderEdge_R", "KnightShoulder_R",        {1.35,0.1,1.35}, {0,-0.25,0},     "accent"},
    -- Left shoulder
    {"KnightShoulder_L",     "LeftUpperArm|Left Arm",   {1.3,0.5,1.3},   {-0.1,0.55,0},   "armor"},
    {"KnightShoulderEdge_L", "KnightShoulder_L",        {1.35,0.1,1.35}, {0,-0.25,0},     "accent"},
    -- Right bracer
    {"KnightBracer_R",       "RightLowerArm",    {1.15,0.85,1.15},{0,0,0},         "armor"},
    {"KnightBracerTrim_R",   "KnightBracer_R",   {1.2,0.08,1.2}, {0,0.4,0},       "accent"},
    -- Left bracer
    {"KnightBracer_L",       "LeftLowerArm",     {1.15,0.85,1.15},{0,0,0},         "armor"},
    {"KnightBracerTrim_L",   "KnightBracer_L",   {1.2,0.08,1.2}, {0,0.4,0},       "accent"},
    -- Hands
    {"KnightHandGuard_R",    "RightHand",        {1.05,0.55,0.5}, {0,0.05,-0.2},   "armor"},
    {"KnightHandGuard_L",    "LeftHand",         {1.05,0.55,0.5}, {0,0.05,-0.2},   "armor"},
    -- Right leg
    {"KnightThigh_R",        "RightUpperLeg",    {1.15,1.0,1.15}, {0,0,0},         "darker"},
    {"KnightThighTrim_R",    "RightUpperLeg",    {1.2,0.08,1.2},  {0,0.48,0},      "accent"},
    {"KnightKnee_R",         "RightLowerLeg",    {1.15,0.4,1.25}, {0,0.45,-0.05},  "armor"},
    {"KnightShin_R",         "RightLowerLeg",    {1.1,0.9,1.15},  {0,-0.15,-0.05}, "armor"},
    {"KnightSabaton_R",      "RightFoot",        {1.1,0.45,1.2},  {0,0.05,-0.05},  "darker"},
    -- Left leg
    {"KnightThigh_L",        "LeftUpperLeg",     {1.15,1.0,1.15}, {0,0,0},         "darker"},
    {"KnightThighTrim_L",    "LeftUpperLeg",     {1.2,0.08,1.2},  {0,0.48,0},      "accent"},
    {"KnightKnee_L",         "LeftLowerLeg",     {1.15,0.4,1.25}, {0,0.45,-0.05},  "armor"},
    {"KnightShin_L",         "LeftLowerLeg",     {1.1,0.9,1.15},  {0,-0.15,-0.05}, "armor"},
    {"KnightSabaton_L",      "LeftFoot",         {1.1,0.45,1.2},  {0,0.05,-0.05},  "darker"},
}

-- Iron Knight helmet pieces (conditional on showHelm)
local IRON_HELM = {
    {"IronHelmet", "Head",       {1.45,1.45,1.45}, {0,0.05,0},     "helmet", "Metal", "Block"},
    {"IronVisor",  "IronHelmet", {1.0,0.12,0.2},   {0,0,-0.64},    "visor"},
}

-- Iron Knight body pieces (always applied)
local IRON_BODY = {
    -- Chest
    {"IronChestplate",     "UpperTorso|Torso", {2.3,2.15,1.25}, {0,0,-0.1},      "armor",      "Metal"},
    {"IronChestTrim",      "IronChestplate",   {2.35,0.12,1.3}, {0,0.45,0},      "accent",     "Metal"},
    {"IronChestRidge",     "IronChestplate",   {0.2,1.6,0.15},  {0,0,-0.1},      "chestRidge", "Metal"},
    -- Back
    {"IronBackPlate",      "UpperTorso|Torso", {1.9,1.7,0.3},   {0,0.1,0.55},    "armor",  "Metal"},
    {"IronSpineRidge",     "IronBackPlate",    {0.25,1.5,0.15},  {0,0,0.15},      "spine",  "Metal"},
    {"IronBackTrim",       "IronBackPlate",    {1.95,0.1,0.35},  {0,0.8,0},       "accent", "Metal"},
    -- Cape
    {"IronCape",           "UpperTorso|Torso", {1.4,2.0,0.08},   {0,-0.7,0.6},    "cape"},
    {"IronCapeHem",        "IronCape",         {1.45,0.08,0.12},  {0,-0.96,0},     "accent"},
    {"IronCapeClasp",      "UpperTorso|Torso", {0.45,0.2,0.18},  {0,0.85,0.58},   "accent", "Metal"},
    -- Belt
    {"IronBelt",           "LowerTorso|Torso", {2.15,0.35,1.2},  {0,0.3,-0.05},   "accent", "Metal"},
    -- Right shoulder
    {"IronShoulder_R",     "RightUpperArm|Right Arm", {1.4,0.55,1.4},   {0.1,0.55,0},    "armor",  "Metal"},
    {"IronShoulderEdge_R", "IronShoulder_R",          {1.45,0.08,1.45}, {0,-0.27,0},     "accent", "Metal"},
    {"IronShoulderRivet_R","IronShoulder_R",          {0.2,0.15,0.2},   {0,0.25,0},      "rivet",  "Metal", "Cylinder"},
    -- Left shoulder
    {"IronShoulder_L",     "LeftUpperArm|Left Arm",   {1.4,0.55,1.4},   {-0.1,0.55,0},   "armor",  "Metal"},
    {"IronShoulderEdge_L", "IronShoulder_L",          {1.45,0.08,1.45}, {0,-0.27,0},     "accent", "Metal"},
    {"IronShoulderRivet_L","IronShoulder_L",          {0.2,0.15,0.2},   {0,0.25,0},      "rivet",  "Metal", "Cylinder"},
    -- Right bracer
    {"IronBracer_R",       "RightLowerArm",    {1.2,0.9,1.2},    {0,0,0},         "armor",  "Metal"},
    {"IronBracerTrim_R",   "IronBracer_R",     {1.25,0.08,1.25}, {0,0.42,0},      "accent", "Metal"},
    -- Left bracer
    {"IronBracer_L",       "LeftLowerArm",     {1.2,0.9,1.2},    {0,0,0},         "armor",  "Metal"},
    {"IronBracerTrim_L",   "IronBracer_L",     {1.25,0.08,1.25}, {0,0.42,0},      "accent", "Metal"},
    -- Hands
    {"IronHandGuard_R",    "RightHand",        {1.1,0.55,0.5},   {0,0.05,-0.2},   "armor", "Metal"},
    {"IronHandGuard_L",    "LeftHand",         {1.1,0.55,0.5},   {0,0.05,-0.2},   "armor", "Metal"},
    -- Right leg
    {"IronThigh_R",        "RightUpperLeg",    {1.2,1.05,1.2},   {0,0,0},         "darker", "Metal"},
    {"IronThighTrim_R",    "RightUpperLeg",    {1.25,0.08,1.25}, {0,0.5,0},       "accent", "Metal"},
    {"IronKnee_R",         "RightLowerLeg",    {1.2,0.45,1.3},   {0,0.45,-0.05},  "armor",  "Metal"},
    {"IronShin_R",         "RightLowerLeg",    {1.15,0.95,1.2},  {0,-0.15,-0.05}, "armor",  "Metal"},
    {"IronSabaton_R",      "RightFoot",        {1.15,0.5,1.25},  {0,0.05,-0.05},  "darker", "Metal"},
    -- Left leg
    {"IronThigh_L",        "LeftUpperLeg",     {1.2,1.05,1.2},   {0,0,0},         "darker", "Metal"},
    {"IronThighTrim_L",    "LeftUpperLeg",     {1.25,0.08,1.25}, {0,0.5,0},       "accent", "Metal"},
    {"IronKnee_L",         "LeftLowerLeg",     {1.2,0.45,1.3},   {0,0.45,-0.05},  "armor",  "Metal"},
    {"IronShin_L",         "LeftLowerLeg",     {1.15,0.95,1.2},  {0,-0.15,-0.05}, "armor",  "Metal"},
    {"IronSabaton_L",      "LeftFoot",         {1.15,0.5,1.25},  {0,0.05,-0.05},  "darker", "Metal"},
}

-- Skin config: maps skinId → { colors, helmPieces, bodyPieces, undersuitColor, headUndersuitColor }
local SKIN_CONFIGS = {
    Knight = {
        colors    = KNIGHT_COLORS,
        helm      = KNIGHT_HELM,
        body      = KNIGHT_BODY,
        undersuit = Color3.fromRGB(50, 50, 55),
        headUnder = Color3.fromRGB(50, 50, 55),
    },
    IronKnight = {
        colors    = IRON_COLORS,
        helm      = IRON_HELM,
        body      = IRON_BODY,
        undersuit = Color3.fromRGB(30, 30, 35),
        headUnder = Color3.fromRGB(30, 30, 35),
    },
    Goblin = {
        colors    = {},
        helm      = {},
        body      = {},
        undersuit = Color3.fromRGB(86, 130, 60),
        headUnder = Color3.fromRGB(106, 150, 70),
    },
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

-- Find a part in the model by name, with "|" fallback for R15/R6
local function findPart(model, nameSpec)
    for name in string.gmatch(nameSpec, "[^|]+") do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

-- Resolve a color key from a color map
local function resolveColor(key, colorMap)
    return colorMap[key] or Color3.fromRGB(150, 150, 155)
end

-- Resolve material string to Enum
local function resolveMaterial(mat)
    if mat == "Metal" then return Enum.Material.Metal end
    return Enum.Material.SmoothPlastic
end

-- Resolve shape string to Enum
local function resolveShape(shape)
    if shape == "Block" then return Enum.PartType.Block end
    if shape == "Cylinder" then return Enum.PartType.Cylinder end
    return nil
end

-- Apply a list of piece specs to a rig model
local function applyPieces(rig, pieces, colorMap)
    for _, spec in ipairs(pieces) do
        local name     = spec[1]
        local parentNm = spec[2]
        local sz       = spec[3]
        local off      = spec[4]
        local colorKey = spec[5]
        local mat      = spec[6]
        local shape    = spec[7]

        local parent = findPart(rig, parentNm)
        if parent then
            local p = Instance.new("Part")
            p.Name        = name
            p.Size        = Vector3.new(sz[1], sz[2], sz[3])
            p.Color       = resolveColor(colorKey, colorMap)
            p.Material    = resolveMaterial(mat)
            p.CanCollide  = false
            p.Anchored    = true
            p.CastShadow  = false
            p.CanTouch    = false
            p.CanQuery    = false
            local s = resolveShape(shape)
            if s then p.Shape = s end
            p.CFrame = parent.CFrame * CFrame.new(off[1], off[2], off[3])
            p.Parent = rig
        end
    end
end

-- Head-attachment names for detecting head accessories
local HEAD_ATTACHMENTS = {
    HatAttachment = true, HairAttachment = true,
    FaceFrontAttachment = true, FaceCenterAttachment = true,
}

local HEAD_ACCESSORY_TYPES = {
    [Enum.AccessoryType.Hat] = true,
    [Enum.AccessoryType.Hair] = true,
    [Enum.AccessoryType.Face] = true,
    [Enum.AccessoryType.Eyebrow] = true,
    [Enum.AccessoryType.Eyelash] = true,
}

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

local function collectBaseParts(model)
    local parts = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            table.insert(parts, desc)
        end
    end
    return parts
end

local function stripAppliedSkinArtifacts(rig)
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

local function buildJointAdjacency(model)
    local adjacency = {}

    local function connect(part0, part1)
        if not part0 or not part1 then return end
        if not part0:IsA("BasePart") or not part1:IsA("BasePart") then return end
        adjacency[part0] = adjacency[part0] or {}
        adjacency[part1] = adjacency[part1] or {}
        adjacency[part0][part1] = true
        adjacency[part1][part0] = true
    end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
            connect(desc.Part0, desc.Part1)
        end
    end

    return adjacency
end

local function collectConnectedGroup(startPart, adjacency)
    local connected = {}
    if not startPart then return connected end

    local stack = { startPart }
    connected[startPart] = true
    while #stack > 0 do
        local current = stack[#stack]
        stack[#stack] = nil
        for neighbor in pairs(adjacency[current] or {}) do
            if not connected[neighbor] then
                connected[neighbor] = true
                stack[#stack + 1] = neighbor
            end
        end
    end

    return connected
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
            if desc:IsA("Decal") then
                desc.Transparency = 1
            end
        end
    end
end

local function getReplacementPreviewTemplate(def, skinId)
    local templateName = def.PreviewTemplateName or def.TemplateName or skinId

    local previewFolder = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
    local replicatedTemplate = previewFolder and previewFolder:FindFirstChild(templateName)
    if replicatedTemplate and replicatedTemplate:IsA("Model") then
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

    local headSkinParts = collectConnectedGroup(headRootPart, buildJointAdjacency(replacementModel))

    hidePreviewBody(rig)
    if showHelm == false then
        local head = rig:FindFirstChild("Head")
        if head then head.Transparency = 0 end
        restoreHeadColor(rig)
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

-- Set all body colors to a uniform undersuit color
local function setUndersuitColors(rig, color)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if not bc then return end
    local c = BrickColor.new(color)
    bc.HeadColor     = c
    bc.TorsoColor    = c
    bc.LeftArmColor  = c
    bc.RightArmColor = c
    bc.LeftLegColor  = c
    bc.RightLegColor = c
end

-- Restore original body colors from saved attributes
local function restoreBodyColors(rig)
    local bc = rig:FindFirstChildOfClass("BodyColors")
    if not bc then return end
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
end

-- Hide all accessories (set handles transparent)
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

-- Restore all accessory visibility
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

-- Restore only head accessories (for showHelm OFF)
restoreHeadAccessories = function(rig)
    for _, acc in ipairs(rig:GetChildren()) do
        if acc:IsA("Accessory") and isHeadAccessory(acc) then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                local orig = handle:GetAttribute("_OrigTransparency")
                handle.Transparency = orig or 0
            end
        end
    end
end

-- Restore original head color only (for showHelm OFF with armored skin)
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

-- Save original appearance state before applying skin so restore functions work
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
            if handle and handle:IsA("BasePart") and handle:GetAttribute("_OrigTransparency") == nil then
                handle:SetAttribute("_OrigTransparency", handle.Transparency)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- BUILD PREVIEW RIG
-- Tries CreateHumanoidModelFromDescription for a clean neutral pose,
-- falls back to character clone.
--------------------------------------------------------------------------------
buildRig = function()
    local player = Players.LocalPlayer
    local character = player.Character

    -- Try 1: Build from HumanoidDescription (gives neutral standing pose)
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
                    -- Clean up scripts from generated model
                    for _, d in ipairs(rig:GetDescendants()) do
                        if d:IsA("BaseScript") then d:Destroy() end
                    end
                    stripAppliedSkinArtifacts(rig)
                    return rig
                end
            end
        end
    end

    -- Try 2: Clone the current character
    if character then
        local rig = character:Clone()
        stripAppliedSkinArtifacts(rig)
        dprint("Built preview rig from character clone")
        return rig
    end

    dprint("No character available for preview")
    return nil
end

--------------------------------------------------------------------------------
-- MAIN UPDATE
-- Builds a preview rig, applies selected skin, renders in ViewportFrame.
--------------------------------------------------------------------------------
function SkinPreview.Update(viewportFrame, skinId, showHelm)
    if not viewportFrame then return end

    -- Clear previous preview
    for _, child in ipairs(viewportFrame:GetChildren()) do
        if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
            child:Destroy()
        end
    end

    dprint("Selected skin changed:", tostring(skinId))

    local selectedDef = SkinDefs.GetById(skinId)
    if selectedDef and selectedDef.ApplicationType == "ReplacementModel" then
        local replacementPreview = buildReplacementPreview(skinId, showHelm)
        if replacementPreview then
            replacementPreview:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(180), 0))

            local worldModel = Instance.new("WorldModel")
            replacementPreview.Parent = worldModel
            worldModel.Parent = viewportFrame

            local camera = Instance.new("Camera")
            camera.FieldOfView = 45
            camera.CFrame = CFrame.lookAt(
                Vector3.new(2.5, 4.2, 4),
                Vector3.new(0, 3.5, 0)
            )
            camera.Parent = viewportFrame
            viewportFrame.CurrentCamera = camera

            local keyLightPart = Instance.new("Part")
            keyLightPart.Anchored = true
            keyLightPart.Transparency = 1
            keyLightPart.CanCollide = false
            keyLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
            keyLightPart.CFrame = CFrame.new(4, 6, 5)
            keyLightPart.Parent = worldModel

            local keyLight = Instance.new("PointLight")
            keyLight.Color = Color3.fromRGB(230, 225, 215)
            keyLight.Brightness = 1.5
            keyLight.Range = 20
            keyLight.Parent = keyLightPart

            local fillLightPart = Instance.new("Part")
            fillLightPart.Anchored = true
            fillLightPart.Transparency = 1
            fillLightPart.CanCollide = false
            fillLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
            fillLightPart.CFrame = CFrame.new(-3, 4, 3)
            fillLightPart.Parent = worldModel

            local fillLight = Instance.new("PointLight")
            fillLight.Color = Color3.fromRGB(160, 170, 200)
            fillLight.Brightness = 0.7
            fillLight.Range = 16
            fillLight.Parent = fillLightPart
            return true
        end

        dprint("ReplacementModel preview unavailable for", skinId, "- falling back to cosmetic rig")
        -- Fall through to cosmetic SKIN_CONFIGS path
    end

    local rig = buildRig()
    if not rig then return false end

    -- Strip existing cosmetic skin parts from the rig
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

    -- Anchor all parts for static display
    for _, d in ipairs(rig:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        end
    end

    -- Save original appearance BEFORE any skin modifications
    saveOriginalAppearance(rig)

    -- Position and rotate rig: face camera (rotate 180° around Y)
    rig:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(180), 0))

    -- Apply skin visuals
    local config = SKIN_CONFIGS[skinId]
    if config then
        -- Armored skin
        dprint("Building preview rig for", skinId)
        local effectiveColors = config.colors
        if skinId == "Knight" or skinId == "IronKnight" then
            effectiveColors = {}
            for k, v in pairs(config.colors) do
                effectiveColors[k] = v
            end
            effectiveColors.accent = getPreviewTeamAccentColor(config.colors.accent)
            effectiveColors.cape   = getPreviewTeamCapeColor(config.colors.cape)
            local teamName = Players.LocalPlayer.Team and Players.LocalPlayer.Team.Name or "none"
            dprint("Resolved team color for preview:", teamName)
            dprint("Applying", skinId, "team trim color")
        end
        setUndersuitColors(rig, config.undersuit)
        hideAccessories(rig)

        -- Body armor (always)
        applyPieces(rig, config.body, effectiveColors)

        -- Helmet (conditional on showHelm)
        local hasHelmPieces = config.helm and #config.helm > 0
        if showHelm and hasHelmPieces then
            applyPieces(rig, config.helm, effectiveColors)
            dprint("ShowHelm in preview: true")
        elseif hasHelmPieces then
            -- ShowHelm OFF: restore head color and head accessories
            restoreHeadColor(rig)
            restoreHeadAccessories(rig)
            dprint("ShowHelm in preview: false")
        else
            -- No helm pieces defined; keep undersuit tint on head
            restoreHeadAccessories(rig)
            dprint("ShowHelm in preview: n/a (no helm pieces)")
        end

        dprint("Applied skin to preview rig:", skinId)
    else
        -- Default skin or unknown: restore original appearance
        dprint("Building preview rig for Default")
        restoreBodyColors(rig)
        restoreAccessories(rig)
        dprint("Applied skin to preview rig: Default")
    end

    -- Create WorldModel and parent rig into it
    local worldModel = Instance.new("WorldModel")
    rig.Parent = worldModel
    worldModel.Parent = viewportFrame

    -- Setup camera (3/4 upper-body view)
    local camera = Instance.new("Camera")
    camera.FieldOfView = 45
    camera.CFrame = CFrame.lookAt(
        Vector3.new(2.5, 4.2, 4),  -- slightly right, above, in front
        Vector3.new(0, 3.5, 0)     -- look at chest/neck area
    )
    camera.Parent = viewportFrame
    viewportFrame.CurrentCamera = camera

    -- Lighting: subtle warm key light from front-right, cool fill from left
    local keyLightPart = Instance.new("Part")
    keyLightPart.Anchored = true
    keyLightPart.Transparency = 1
    keyLightPart.CanCollide = false
    keyLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    keyLightPart.CFrame = CFrame.new(4, 6, 5)
    keyLightPart.Parent = worldModel

    local keyLight = Instance.new("PointLight")
    keyLight.Color = Color3.fromRGB(230, 225, 215)
    keyLight.Brightness = 1.5
    keyLight.Range = 20
    keyLight.Parent = keyLightPart

    local fillLightPart = Instance.new("Part")
    fillLightPart.Anchored = true
    fillLightPart.Transparency = 1
    fillLightPart.CanCollide = false
    fillLightPart.Size = Vector3.new(0.1, 0.1, 0.1)
    fillLightPart.CFrame = CFrame.new(-3, 4, 3)
    fillLightPart.Parent = worldModel

    local fillLight = Instance.new("PointLight")
    fillLight.Color = Color3.fromRGB(160, 170, 200)
    fillLight.Brightness = 0.7
    fillLight.Range = 16
    fillLight.Parent = fillLightPart
    return true
end

return SkinPreview
