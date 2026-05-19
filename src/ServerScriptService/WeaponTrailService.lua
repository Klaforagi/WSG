--------------------------------------------------------------------------------
-- WeaponTrailService.lua
-- Ensures weapon Tools get a shared server-created Trail named "SwordTrail".
-- ToolMeleeSetup.server.lua already pulses that name during melee swings, so
-- newly added weapons only need to pass through the shared tool grant path.
--------------------------------------------------------------------------------

local WeaponTrailService = {}

local TRAIL_NAME = "SwordTrail"
local AUTO_ATTACHMENT0_NAME = "_WeaponTrailA0"
local AUTO_ATTACHMENT1_NAME = "_WeaponTrailA1"

local HANDLE_TRAIL_A_NAMES = { "Trail A", "TrailA", "Trail_A" }
local HANDLE_TRAIL_B_NAMES = { "Trail B", "TrailB", "Trail_B" }

local ATTACHMENT0_NAMES = {
    AUTO_ATTACHMENT0_NAME,
    "SwordTrailA0",
    "SwordTrailAttachment0",
    "WeaponTrailA0",
    "WeaponTrailAttachment0",
    "TrailAttachment0",
}

local ATTACHMENT1_NAMES = {
    AUTO_ATTACHMENT1_NAME,
    "SwordTrailA1",
    "SwordTrailAttachment1",
    "WeaponTrailA1",
    "WeaponTrailAttachment1",
    "TrailAttachment1",
}

local PREFERRED_PART_NAME_FRAGMENTS = {
    "blade",
    "tip",
    "head",
    "barrel",
    "handle",
}

local function isWeaponTool(tool)
    if not tool or not tool:IsA("Tool") then return false end

    local category = tool:GetAttribute("WeaponCategory") or tool:GetAttribute("HotbarCategory")
    if category == "Melee" or category == "Ranged" or category == "DevWeapon" then
        return true
    end

    return tool:GetAttribute("IsWeapon") == true
        or tool:GetAttribute("IsMelee") == true
        or tool:GetAttribute("IsRanged") == true
        or tool:GetAttribute("IsDevWeapon") == true
end

local function findFirstDescendant(root, predicate)
    if not root then return nil end
    for _, descendant in ipairs(root:GetDescendants()) do
        if predicate(descendant) then
            return descendant
        end
    end
    return nil
end

local function findAttachmentByExactName(root, names)
    for _, name in ipairs(names) do
        local found = root:FindFirstChild(name, true)
        if found and found:IsA("Attachment") then
            return found
        end
    end
    return nil
end

local function findDirectHandleAttachment(handle, names)
    if not handle or not handle:IsA("BasePart") then return nil end
    for _, name in ipairs(names) do
        local found = handle:FindFirstChild(name)
        if found and found:IsA("Attachment") then
            return found
        end
    end
    return nil
end

local function findHandleTrailPair(tool)
    local handle = tool and tool:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return nil, nil end

    local attachment0 = findDirectHandleAttachment(handle, HANDLE_TRAIL_A_NAMES)
    local attachment1 = findDirectHandleAttachment(handle, HANDLE_TRAIL_B_NAMES)
    if attachment0 and attachment1 then
        return attachment0, attachment1
    end

    return nil, nil
end

local function findTrailAttachment(root, exactNames, isFirstAttachment)
    local exact = findAttachmentByExactName(root, exactNames)
    if exact then return exact end

    return findFirstDescendant(root, function(descendant)
        if not descendant:IsA("Attachment") then return false end
        local name = string.lower(descendant.Name)
        if not string.find(name, "trail", 1, true) then return false end

        if isFirstAttachment then
            return string.find(name, "0", 1, true)
                or string.find(name, "start", 1, true)
                or string.find(name, "base", 1, true)
        end

        return string.find(name, "1", 1, true)
            or string.find(name, "end", 1, true)
            or string.find(name, "tip", 1, true)
    end)
end

local function getLongestAxisOffset(part)
    local size = part.Size
    local longest = math.max(size.X, size.Y, size.Z)
    local halfLength = math.max(longest * 0.45, 0.25)

    if size.X >= size.Y and size.X >= size.Z then
        return Vector3.new(halfLength, 0, 0)
    elseif size.Y >= size.X and size.Y >= size.Z then
        return Vector3.new(0, halfLength, 0)
    end

    return Vector3.new(0, 0, halfLength)
end

local function getPartScore(part)
    local name = string.lower(part.Name)
    local size = part.Size
    local score = math.max(size.X, size.Y, size.Z)

    for priority, fragment in ipairs(PREFERRED_PART_NAME_FRAGMENTS) do
        if string.find(name, fragment, 1, true) then
            score += 1000 - priority
            break
        end
    end

    return score
end

local function chooseTrailPart(tool)
    local bestPart = nil
    local bestScore = -math.huge

    for _, descendant in ipairs(tool:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local score = getPartScore(descendant)
            if score > bestScore then
                bestPart = descendant
                bestScore = score
            end
        end
    end

    return bestPart
end

local function ensureAutoAttachments(tool)
    local handleAttachment0, handleAttachment1 = findHandleTrailPair(tool)
    if handleAttachment0 and handleAttachment1 then
        return handleAttachment0, handleAttachment1
    end

    local attachment0 = findTrailAttachment(tool, ATTACHMENT0_NAMES, true)
    local attachment1 = findTrailAttachment(tool, ATTACHMENT1_NAMES, false)
    if attachment0 and attachment1 then
        return attachment0, attachment1
    end

    local hostPart = chooseTrailPart(tool)
    if not hostPart then return nil, nil end

    local offset = getLongestAxisOffset(hostPart)

    attachment0 = hostPart:FindFirstChild(AUTO_ATTACHMENT0_NAME)
    if not attachment0 or not attachment0:IsA("Attachment") then
        attachment0 = Instance.new("Attachment")
        attachment0.Name = AUTO_ATTACHMENT0_NAME
        attachment0.Parent = hostPart
    end
    attachment0.Position = offset * -1

    attachment1 = hostPart:FindFirstChild(AUTO_ATTACHMENT1_NAME)
    if not attachment1 or not attachment1:IsA("Attachment") then
        attachment1 = Instance.new("Attachment")
        attachment1.Name = AUTO_ATTACHMENT1_NAME
        attachment1.Parent = hostPart
    end
    attachment1.Position = offset

    return attachment0, attachment1
end

local function configureTrailDefaults(trail)
    trail.Enabled = false
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 240, 240)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(0.5, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = 0.14
    trail.MinLength = 0
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.15),
        NumberSequenceKeypoint.new(0.6, 0.8),
        NumberSequenceKeypoint.new(1, 0.2),
    })
    trail.FaceCamera = false
    trail.LightEmission = 0
    trail.LightInfluence = 0
    trail:SetAttribute("AutoWeaponTrail", true)
end

function WeaponTrailService.ApplyToTool(tool)
    if not isWeaponTool(tool) then return nil end

    local attachment0, attachment1 = ensureAutoAttachments(tool)
    if not attachment0 or not attachment1 then return nil end

    local trail = tool:FindFirstChild(TRAIL_NAME, true)
    if not trail or not trail:IsA("Trail") then
        trail = Instance.new("Trail")
        trail.Name = TRAIL_NAME
        trail.Parent = attachment0.Parent or tool
    end

    trail.Attachment0 = trail.Attachment0 or attachment0
    trail.Attachment1 = trail.Attachment1 or attachment1

    if not trail.Attachment0 or not trail.Attachment1 then
        trail.Attachment0 = attachment0
        trail.Attachment1 = attachment1
    end

    configureTrailDefaults(trail)
    return trail
end

function WeaponTrailService.PulseTrail(tool, activeDuration)
    if not tool or not tool:IsA("Tool") then return false end

    local trail = tool:FindFirstChild(TRAIL_NAME, true)
    if not trail or not trail:IsA("Trail") then
        trail = WeaponTrailService.ApplyToTool(tool)
    end
    if not trail or not trail:IsA("Trail") then return false end

    local duration = math.max(activeDuration or 0.14, 0.05)
    pcall(function()
        trail.Lifetime = math.max(trail.Lifetime, duration)
        trail.Enabled = false
    end)

    task.spawn(function()
        pcall(function() trail.Enabled = true end)
        task.wait(duration)
        if trail and trail.Parent then
            pcall(function() trail.Enabled = false end)
        end
    end)

    return true
end

return WeaponTrailService