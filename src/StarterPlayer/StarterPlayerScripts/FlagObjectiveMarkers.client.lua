local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

local FLAG_TEAMS = {"Blue", "Red"}
local TEAM_COLORS = {
    Blue = Color3.fromRGB(55, 135, 255),
    Red = Color3.fromRGB(245, 65, 65),
}
local TEAM_DARK_COLORS = {
    Blue = Color3.fromRGB(8, 28, 72),
    Red = Color3.fromRGB(82, 14, 16),
}
local NEUTRAL_MARKER_COLOR = Color3.fromRGB(132, 138, 148)
local NEUTRAL_MARKER_DARK_COLOR = Color3.fromRGB(70, 74, 80)
local CAPTURE_MARKER_COLOR = Color3.fromRGB(255, 196, 64)
local CAPTURE_MARKER_PULSE_COLOR = Color3.fromRGB(255, 244, 184)
local CAPTURE_MARKER_DARK_COLOR = Color3.fromRGB(120, 74, 8)
local HOLD_MARKER_TEXT_COLOR = Color3.fromRGB(225, 228, 232)
local TIMER_BADGE_BACKGROUND = Color3.fromRGB(18, 20, 26)
local FLAG_MODEL_NAMES = {
    Blue = {"BlueFlag", "Blue Flag"},
    Red = {"RedFlag", "Red Flag"},
}
local CARRIED_FLAG_MODEL_NAMES = {
    Blue = {"BlueFlag_Carried", "Blue Flag_Carried"},
    Red = {"RedFlag_Carried", "Red Flag_Carried"},
}
local FLAG_STAND_NAMES = {
    Blue = {"BlueFlagStand", "Blue Flag Stand", "BlueStand", "KnightsFlagStand", "KnightFlagStand"},
    Red = {"RedFlagStand", "Red Flag Stand", "RedStand", "BerserkerFlagStand", "BerserkersFlagStand"},
}
local FLAG_ACTION_PROMPT_NAME = "FlagActionPrompt"
local RETURN_DEADLINE_ATTRIBUTE = "ReturnDeadline"
local STATE_ATTRIBUTES = {"Team", "AtBase", "CarrierUserId", "CarrierTeam", "CarrierName", "IsCarried", "IsDropped", RETURN_DEADLINE_ATTRIBUTE}

local markers = {}
local warnedKeys = {}
local wiredStateObjects = {}
local flagStatesFolder = nil
local updateScheduled = false
local updateMarkers = nil

local function createMarkerState()
    return {
        gui = nil,
        attachment = nil,
        adorneePart = nil,
        label = nil,
        badge = nil,
        pointer = nil,
        stroke = nil,
        timerBadge = nil,
        timerLabel = nil,
        timerStroke = nil,
        iconRoot = nil,
        iconBanner = nil,
        iconFold = nil,
        styleName = nil,
        returnDeadline = 0,
    }
end

for _, flagTeam in ipairs(FLAG_TEAMS) do
    markers[flagTeam] = createMarkerState()
end
markers.Hold = createMarkerState()

local function warnOnce(key, message)
    if warnedKeys[key] then return end
    warnedKeys[key] = true
    warn(message)
end

local function canonicalTeamName(value)
    local text = string.lower(tostring(value or ""))
    if text == "" or text == "neutral" then
        return nil
    end
    if text == "blue" or text == "knight" or text == "knights" then
        return "Blue"
    end
    if text == "red" or text == "berserker" or text == "berserkers" or text == "barbarian" or text == "barbarians" then
        return "Red"
    end
    return nil
end

local function getLocalTeamName()
    local team = localPlayer.Team
    local canonicalTeam = team and canonicalTeamName(team.Name) or nil
    if canonicalTeam then
        return canonicalTeam
    end
    return canonicalTeamName(localPlayer:GetAttribute("Team"))
end

local function getStateObject(flagTeam)
    if not flagStatesFolder or not flagStatesFolder:IsA("Folder") then
        return nil
    end
    local stateObject = flagStatesFolder:FindFirstChild(flagTeam)
    if stateObject and stateObject:IsA("Folder") then
        return stateObject
    end
    return nil
end

local function getSearchRoots()
    local roots = {}
    local seen = {}

    local function addRoot(instance)
        if instance and not seen[instance] then
            seen[instance] = true
            table.insert(roots, instance)
        end
    end

    addRoot(Workspace:FindFirstChild("WSG"))
    addRoot(Workspace:FindFirstChild("Map"))
    addRoot(Workspace:FindFirstChild("Flags"))
    addRoot(Workspace:FindFirstChild("CTF"))
    addRoot(Workspace)

    return roots
end

local function getAdorneePart(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") then
        if instance.PrimaryPart then
            return instance.PrimaryPart
        end
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end
    return nil
end

local function findNamedBasePart(container, targetName)
    if not container then
        return nil
    end
    if container:IsA("BasePart") and container.Name == targetName then
        return container
    end

    local namedPart = container:FindFirstChild(targetName, true)
    if namedPart and namedPart:IsA("BasePart") then
        return namedPart
    end

    return nil
end

local function getFlagAnchorPart(instance)
    local planePart = findNamedBasePart(instance, "Plane")
    if planePart then
        return planePart
    end

    local parent = instance and instance.Parent
    if parent and parent:IsA("Model") then
        planePart = findNamedBasePart(parent, "Plane")
        if planePart then
            return planePart
        end
    end

    return getAdorneePart(instance)
end

local function getStandAnchorPart(standInstance)
    if not standInstance then
        return nil
    end

    if standInstance:IsA("Model") then
        local stonePart = standInstance:FindFirstChild("Stone", true)
        if stonePart and stonePart:IsA("BasePart") then
            return stonePart
        end
        if standInstance.PrimaryPart and standInstance.PrimaryPart:IsA("BasePart") then
            return standInstance.PrimaryPart
        end
        return standInstance:FindFirstChildWhichIsA("BasePart", true)
    end

    if standInstance:IsA("BasePart") then
        if standInstance.Name == "Stone" then
            return standInstance
        end
        local parent = standInstance.Parent
        if parent and parent:IsA("Model") then
            local stonePart = parent:FindFirstChild("Stone", true)
            if stonePart and stonePart:IsA("BasePart") then
                return stonePart
            end
        end
        return standInstance
    end

    return nil
end

local function isAwaitingRespawn(stateObject)
    if not stateObject then
        return false
    end
    return stateObject:GetAttribute("AtBase") ~= true
        and stateObject:GetAttribute("IsCarried") ~= true
        and stateObject:GetAttribute("IsDropped") ~= true
end

local function matchesDroppedPreference(instance, preferredDropped)
    if preferredDropped == nil then
        return true
    end
    local isDropped = instance:GetAttribute("IsDropped")
    return isDropped == preferredDropped or (preferredDropped == false and isDropped == nil)
end

local function hasExactName(instance, names)
    for _, name in ipairs(names) do
        if instance.Name == name then
            return true
        end
    end
    return false
end

local function isFlagInstance(instance, flagTeam)
    if not instance or (not instance:IsA("Model") and not instance:IsA("BasePart")) then
        return false
    end
    if string.find(string.lower(instance.Name), "stand") then
        return false
    end
    if hasExactName(instance, FLAG_MODEL_NAMES[flagTeam]) then
        return true
    end
    local attributeTeam = canonicalTeamName(instance:GetAttribute("Team"))
    return attributeTeam == flagTeam and string.find(string.lower(instance.Name), "flag") ~= nil
end

local function findFlagInstance(flagTeam, preferredDropped)
    for _, root in ipairs(getSearchRoots()) do
        for _, name in ipairs(FLAG_MODEL_NAMES[flagTeam]) do
            local direct = root:FindFirstChild(name, true)
            if direct and isFlagInstance(direct, flagTeam) and matchesDroppedPreference(direct, preferredDropped) then
                return direct
            end
        end
    end

    for _, root in ipairs(getSearchRoots()) do
        for _, descendant in ipairs(root:GetDescendants()) do
            if isFlagInstance(descendant, flagTeam) and matchesDroppedPreference(descendant, preferredDropped) then
                return descendant
            end
        end
    end

    return nil
end

local function findStandPart(flagTeam)
    for _, root in ipairs(getSearchRoots()) do
        for _, standName in ipairs(FLAG_STAND_NAMES[flagTeam]) do
            local standInstance = root:FindFirstChild(standName, true)
            if standInstance and (standInstance:IsA("BasePart") or standInstance:IsA("Model")) then
                return standInstance
            end
        end
    end
    return nil
end

local function findStandMarkerPart(flagTeam)
    local standInstance = findStandPart(flagTeam)
    if standInstance then
        return getStandAnchorPart(standInstance), 5.5
    end

    return nil, 0
end

local function getCarrierPlayer(stateObject)
    if not stateObject then return nil end
    local carrierUserId = tonumber(stateObject:GetAttribute("CarrierUserId")) or 0
    if carrierUserId > 0 then
        local carrierPlayer = Players:GetPlayerByUserId(carrierUserId)
        if carrierPlayer then
            return carrierPlayer
        end
    end

    local carrierName = tostring(stateObject:GetAttribute("CarrierName") or "")
    if carrierName ~= "" then
        return Players:FindFirstChild(carrierName)
    end

    return nil
end

local function findCarriedFlagPart(flagTeam, carrierPlayer)
    local character = carrierPlayer and carrierPlayer.Character or nil
    if not character then
        return nil
    end

    local head = character:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    for _, carriedName in ipairs(CARRIED_FLAG_MODEL_NAMES[flagTeam]) do
        local carriedFlag = character:FindFirstChild(carriedName)
        local carriedPart = getFlagAnchorPart(carriedFlag)
        if carriedPart then
            return carriedPart
        end
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if isFlagInstance(descendant, flagTeam) and descendant:GetAttribute("IsCarried") == true then
            local carriedPart = getFlagAnchorPart(descendant)
            if carriedPart then
                return carriedPart
            end
        end
    end

    return nil
end

local function findMarkerPart(flagTeam, stateObject)
    if stateObject and stateObject:GetAttribute("IsCarried") == true then
        local carriedPart = findCarriedFlagPart(flagTeam, getCarrierPlayer(stateObject))
        if carriedPart then
            return carriedPart, 6.0
        end
        return nil, 0
    end

    if stateObject and stateObject:GetAttribute("IsDropped") == true then
        local droppedFlag = findFlagInstance(flagTeam, true)
        local droppedPart = getFlagAnchorPart(droppedFlag)
        if droppedPart then
            return droppedPart, 4.0
        end
        return nil, 0
    end

    if stateObject and stateObject:GetAttribute("AtBase") == true then
        local baseFlag = findFlagInstance(flagTeam, false) or findFlagInstance(flagTeam, nil)
        local basePart = getFlagAnchorPart(baseFlag)
        if basePart then
            return basePart, 4.5
        end

        return findStandMarkerPart(flagTeam)
    end

    return nil, 0
end

local function destroyMarker(markerKey)
    local marker = markers[markerKey]
    if marker.gui then
        marker.gui:Destroy()
    end
    if marker.attachment then
        marker.attachment:Destroy()
    end
    marker.gui = nil
    marker.attachment = nil
    marker.adorneePart = nil
    marker.label = nil
    marker.badge = nil
    marker.pointer = nil
    marker.stroke = nil
    marker.timerBadge = nil
    marker.timerLabel = nil
    marker.timerStroke = nil
    marker.iconRoot = nil
    marker.iconBanner = nil
    marker.iconFold = nil
    marker.styleName = nil
    marker.returnDeadline = 0
end

local function setMarkerEnabled(markerKey, enabled)
    local marker = markers[markerKey]
    if marker.gui then
        marker.gui.Enabled = enabled
    end
end

local function createMarker(markerKey, adorneePart, verticalOffset, themeTeam)
    destroyMarker(markerKey)

    local attachment = Instance.new("Attachment")
    attachment.Name = "FlagObjectiveMarker_" .. markerKey
    attachment.Position = Vector3.new(0, math.max(2.5, (adorneePart.Size.Y * 0.5) + verticalOffset), 0)
    attachment.Parent = adorneePart

    local gui = Instance.new("BillboardGui")
    gui.Name = "FlagObjectiveMarker"
    gui.Adornee = attachment
    gui.AlwaysOnTop = true
    gui.MaxDistance = 1000
    gui.LightInfluence = 0
    gui.Size = UDim2.fromOffset(86, 72)
    gui.Enabled = false
    gui.Parent = attachment

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui

    local color = TEAM_COLORS[themeTeam] or NEUTRAL_MARKER_COLOR
    local darkColor = TEAM_DARK_COLORS[themeTeam] or NEUTRAL_MARKER_DARK_COLOR

    local pointer = Instance.new("Frame")
    pointer.Name = "Pointer"
    pointer.AnchorPoint = Vector2.new(0.5, 0)
    pointer.Position = UDim2.new(0.5, 0, 0, 50)
    pointer.Size = UDim2.fromOffset(12, 12)
    pointer.Rotation = 45
    pointer.BackgroundColor3 = color
    pointer.BackgroundTransparency = 0.08
    pointer.BorderSizePixel = 0
    pointer.ZIndex = 1
    pointer.Parent = root

    local badge = Instance.new("Frame")
    badge.Name = "Badge"
    badge.AnchorPoint = Vector2.new(0.5, 0)
    badge.Position = UDim2.new(0.5, 0, 0, 34)
    badge.Size = UDim2.fromOffset(74, 20)
    badge.BackgroundColor3 = color
    badge.BackgroundTransparency = 0.08
    badge.BorderSizePixel = 0
    badge.ZIndex = 2
    badge.Parent = root

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = badge

    local stroke = Instance.new("UIStroke")
    stroke.Color = darkColor
    stroke.Thickness = 1.2
    stroke.Transparency = 0.05
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = badge

    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(4, 0)
    label.Size = UDim2.new(1, -8, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.Text = ""
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.35
    label.ZIndex = 3
    label.Parent = badge

    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = 8
    textConstraint.MaxTextSize = 12
    textConstraint.Parent = label

    local icon = Instance.new("Frame")
    icon.Name = "FlagIcon"
    icon.AnchorPoint = Vector2.new(0.5, 0)
    icon.Position = UDim2.new(0.5, 0, 0, 18)
    icon.Size = UDim2.fromOffset(18, 14)
    icon.BackgroundTransparency = 1
    icon.BorderSizePixel = 0
    icon.ZIndex = 3
    icon.Parent = root

    local pole = Instance.new("Frame")
    pole.Name = "Pole"
    pole.AnchorPoint = Vector2.new(0.5, 0.5)
    pole.Position = UDim2.new(0.22, 0, 0.54, 0)
    pole.Size = UDim2.new(0.12, 0, 0.86, 0)
    pole.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    pole.BorderSizePixel = 0
    pole.ZIndex = 4
    pole.Parent = icon
    local poleCorner = Instance.new("UICorner")
    poleCorner.CornerRadius = UDim.new(1, 0)
    poleCorner.Parent = pole

    local iconBanner = Instance.new("Frame")
    iconBanner.Name = "Banner"
    iconBanner.AnchorPoint = Vector2.new(0, 0)
    iconBanner.Position = UDim2.new(0.3, 0, 0.12, 0)
    iconBanner.Size = UDim2.new(0.62, 0, 0.42, 0)
    iconBanner.BorderSizePixel = 0
    iconBanner.ZIndex = 5
    iconBanner.Parent = icon
    local iconBannerCorner = Instance.new("UICorner")
    iconBannerCorner.CornerRadius = UDim.new(0, 3)
    iconBannerCorner.Parent = iconBanner

    local iconFold = Instance.new("Frame")
    iconFold.Name = "LowerFold"
    iconFold.AnchorPoint = Vector2.new(0, 0)
    iconFold.Position = UDim2.new(0.3, 0, 0.48, 0)
    iconFold.Size = UDim2.new(0.46, 0, 0.3, 0)
    iconFold.BorderSizePixel = 0
    iconFold.ZIndex = 4
    iconFold.Parent = icon
    local iconFoldCorner = Instance.new("UICorner")
    iconFoldCorner.CornerRadius = UDim.new(0, 3)
    iconFoldCorner.Parent = iconFold

    local timerBadge = Instance.new("Frame")
    timerBadge.Name = "TimerBadge"
    timerBadge.AnchorPoint = Vector2.new(0.5, 1)
    timerBadge.Position = UDim2.new(0.5, 0, 0, 15)
    timerBadge.Size = UDim2.fromOffset(52, 16)
    timerBadge.BackgroundColor3 = TIMER_BADGE_BACKGROUND
    timerBadge.BackgroundTransparency = 0.12
    timerBadge.BorderSizePixel = 0
    timerBadge.Visible = false
    timerBadge.ZIndex = 4
    timerBadge.Parent = root

    local timerCorner = Instance.new("UICorner")
    timerCorner.CornerRadius = UDim.new(0, 4)
    timerCorner.Parent = timerBadge

    local timerStroke = Instance.new("UIStroke")
    timerStroke.Thickness = 1.2
    timerStroke.Transparency = 0.15
    timerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    timerStroke.Parent = timerBadge

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "Text"
    timerLabel.BackgroundTransparency = 1
    timerLabel.Position = UDim2.fromOffset(4, 0)
    timerLabel.Size = UDim2.new(1, -8, 1, 0)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Text = ""
    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerLabel.TextScaled = true
    timerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    timerLabel.TextStrokeTransparency = 0.25
    timerLabel.ZIndex = 5
    timerLabel.Parent = timerBadge

    local timerConstraint = Instance.new("UITextSizeConstraint")
    timerConstraint.MinTextSize = 8
    timerConstraint.MaxTextSize = 12
    timerConstraint.Parent = timerLabel

    local marker = markers[markerKey]
    marker.gui = gui
    marker.attachment = attachment
    marker.adorneePart = adorneePart
    marker.label = label
    marker.badge = badge
    marker.pointer = pointer
    marker.stroke = stroke
    marker.timerBadge = timerBadge
    marker.timerLabel = timerLabel
    marker.timerStroke = timerStroke
    marker.iconRoot = icon
    marker.iconBanner = iconBanner
    marker.iconFold = iconFold
    marker.returnDeadline = 0

    return marker
end

local function ensureMarker(markerKey, adorneePart, verticalOffset, themeTeam)
    local marker = markers[markerKey]
    if marker.adorneePart ~= adorneePart or not marker.gui or not marker.gui.Parent then
        marker = createMarker(markerKey, adorneePart, verticalOffset, themeTeam)
    elseif marker.attachment then
        marker.attachment.Position = Vector3.new(0, math.max(2.5, (adorneePart.Size.Y * 0.5) + verticalOffset), 0)
    end
    return marker
end

local function getOpposingTeam(teamName)
    for _, flagTeam in ipairs(FLAG_TEAMS) do
        if flagTeam ~= teamName then
            return flagTeam
        end
    end
    return nil
end

local function isCarriedByLocalPlayer(stateObject)
    return stateObject and (tonumber(stateObject:GetAttribute("CarrierUserId")) or 0) == localPlayer.UserId
end

local function isCarriedByTeam(stateObject, teamName)
    if not stateObject or stateObject:GetAttribute("IsCarried") ~= true then
        return false
    end
    return canonicalTeamName(stateObject:GetAttribute("CarrierTeam")) == teamName
end

local function getMarkerPresentation(localTeam, flagTeam, stateObject, localPlayerHasEnemyFlag)
    if isAwaitingRespawn(stateObject) then
        return false, nil, nil
    end

    if flagTeam == localTeam then
        local atBase = stateObject:GetAttribute("AtBase") == true
        local isCarried = stateObject:GetAttribute("IsCarried") == true
        local isDropped = stateObject:GetAttribute("IsDropped") == true
        if atBase and not isCarried and not isDropped then
            if localPlayerHasEnemyFlag then
                return true, "CAPTURE", "capture"
            end
            return true, "DEFEND", "team"
        end
        if isCarried then
            return true, "ELIMINATE", "eliminate"
        end
        if isDropped then
            return true, "RETURN", "team"
        end
        return false, nil, nil
    end

    if isCarriedByLocalPlayer(stateObject) then
        return false, nil, nil
    end

    local carrierTeam = canonicalTeamName(stateObject:GetAttribute("CarrierTeam"))
    if stateObject:GetAttribute("IsCarried") == true and carrierTeam == localTeam then
        return true, "PROTECT", "local"
    end
    return true, "STEAL", "team"
end

local function applyMarkerStyle(marker, styleName, themeTeam, localTeam)
    if not marker.badge or not marker.pointer or not marker.stroke or not marker.label then
        return
    end

    local displayTeam = themeTeam
    local iconTeam = themeTeam
    local showFlagIcon = true

    if styleName == "local" then
        displayTeam = localTeam or themeTeam
        iconTeam = getOpposingTeam(localTeam) or displayTeam
    elseif styleName == "eliminate" then
        displayTeam = getOpposingTeam(localTeam) or themeTeam
        iconTeam = localTeam or themeTeam
    elseif styleName == "capture" or styleName == "hold" then
        showFlagIcon = false
    end

    local backgroundColor = TEAM_COLORS[displayTeam] or NEUTRAL_MARKER_COLOR
    local strokeColor = TEAM_DARK_COLORS[displayTeam] or NEUTRAL_MARKER_DARK_COLOR
    local iconColor = TEAM_COLORS[iconTeam] or backgroundColor
    local textColor = Color3.fromRGB(255, 255, 255)
    local badgeTransparency = 0.08
    local pointerTransparency = 0.08
    local strokeTransparency = 0.05
    local textStrokeTransparency = 0.35

    if styleName == "capture" then
        backgroundColor = CAPTURE_MARKER_COLOR
        strokeColor = CAPTURE_MARKER_DARK_COLOR
        textColor = CAPTURE_MARKER_PULSE_COLOR
        textStrokeTransparency = 0.18
    elseif styleName == "hold" then
        backgroundColor = NEUTRAL_MARKER_COLOR
        strokeColor = NEUTRAL_MARKER_DARK_COLOR
        textColor = HOLD_MARKER_TEXT_COLOR
        badgeTransparency = 0.28
        pointerTransparency = 0.42
        strokeTransparency = 0.22
        textStrokeTransparency = 0.5
    elseif styleName == "local" then
        backgroundColor = TEAM_COLORS[localTeam] or backgroundColor
        strokeColor = TEAM_DARK_COLORS[localTeam] or strokeColor
    end

    marker.badge.BackgroundColor3 = backgroundColor
    marker.badge.BackgroundTransparency = badgeTransparency
    marker.pointer.BackgroundColor3 = backgroundColor
    marker.pointer.BackgroundTransparency = pointerTransparency
    marker.stroke.Color = strokeColor
    marker.stroke.Transparency = strokeTransparency
    marker.label.TextColor3 = textColor
    marker.label.TextStrokeTransparency = textStrokeTransparency
    if marker.iconRoot then
        marker.iconRoot.Visible = showFlagIcon
    end
    if marker.iconBanner then
        marker.iconBanner.BackgroundColor3 = iconColor
    end
    if marker.iconFold then
        marker.iconFold.BackgroundColor3 = iconColor:Lerp(Color3.new(0, 0, 0), 0.18)
    end
    if marker.timerBadge then
        marker.timerBadge.BackgroundColor3 = TIMER_BADGE_BACKGROUND
        marker.timerBadge.BackgroundTransparency = 0.12
    end
    if marker.timerStroke then
        marker.timerStroke.Color = backgroundColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25)
        marker.timerStroke.Transparency = 0.15
    end
    if marker.timerLabel then
        marker.timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        marker.timerLabel.TextStrokeTransparency = 0.25
    end
    marker.styleName = styleName
end

local function updateFlagActionPrompt(localTeam, flagTeam, stateObject)
    local targetModel = nil
    if stateObject:GetAttribute("IsDropped") == true then
        targetModel = findFlagInstance(flagTeam, true)
    elseif stateObject:GetAttribute("AtBase") == true then
        targetModel = findFlagInstance(flagTeam, false) or findFlagInstance(flagTeam, nil)
    end

    local prompt = targetModel and targetModel:FindFirstChild(FLAG_ACTION_PROMPT_NAME, true)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if not localTeam then
        prompt.Enabled = false
        return
    end

    local enabled = false
    local actionText = "Steal"
    if not isAwaitingRespawn(stateObject) and stateObject:GetAttribute("IsCarried") ~= true then
        if flagTeam == localTeam then
            enabled = stateObject:GetAttribute("IsDropped") == true
            actionText = "Return"
        else
            enabled = true
            if stateObject:GetAttribute("IsDropped") == true then
                actionText = "Pick Up"
            end
        end
    end

    prompt.Enabled = enabled
    prompt.ActionText = actionText
    prompt.ObjectText = flagTeam .. " Flag"
end

local function scheduleUpdate()
    if updateScheduled then return end
    updateScheduled = true
    task.defer(function()
        updateScheduled = false
        if updateMarkers then
            updateMarkers()
        end
    end)
end

local function wireStateObject(stateObject)
    if not stateObject or wiredStateObjects[stateObject] then return end
    wiredStateObjects[stateObject] = true
    for _, attributeName in ipairs(STATE_ATTRIBUTES) do
        stateObject:GetAttributeChangedSignal(attributeName):Connect(scheduleUpdate)
    end
    stateObject.AncestryChanged:Connect(scheduleUpdate)
end

local function wireFlagStatesFolder(folder)
    if not folder or not folder:IsA("Folder") then return end
    flagStatesFolder = folder
    for _, flagTeam in ipairs(FLAG_TEAMS) do
        wireStateObject(getStateObject(flagTeam))
    end
    folder.ChildAdded:Connect(function(child)
        wireStateObject(child)
        scheduleUpdate()
    end)
    scheduleUpdate()
end

function updateMarkers()
    local localTeam = getLocalTeamName()
    if not localTeam then
        for _, flagTeam in ipairs(FLAG_TEAMS) do
            setMarkerEnabled(flagTeam, false)
            local stateObject = getStateObject(flagTeam)
            if stateObject then
                updateFlagActionPrompt(nil, flagTeam, stateObject)
            end
        end
        setMarkerEnabled("Hold", false)
        return
    end

    if not flagStatesFolder then
        warnOnce("FlagStatesMissing", "[FlagObjectiveMarkers] ReplicatedStorage.FlagStates was not found; flag objective markers are hidden.")
        for _, flagTeam in ipairs(FLAG_TEAMS) do
            setMarkerEnabled(flagTeam, false)
            local stateObject = getStateObject(flagTeam)
            if stateObject then
                updateFlagActionPrompt(localTeam, flagTeam, stateObject)
            end
        end
        setMarkerEnabled("Hold", false)
        return
    end

    local stateObjects = {}
    for _, flagTeam in ipairs(FLAG_TEAMS) do
        stateObjects[flagTeam] = getStateObject(flagTeam)
    end

    local enemyTeam = getOpposingTeam(localTeam)
    local enemyState = enemyTeam and stateObjects[enemyTeam] or nil
    local localPlayerHasEnemyFlag = isCarriedByLocalPlayer(enemyState)

    for _, flagTeam in ipairs(FLAG_TEAMS) do
        local stateObject = stateObjects[flagTeam]
        if not stateObject then
            warnOnce("FlagStateMissing_" .. flagTeam, "[FlagObjectiveMarkers] Missing replicated state for " .. flagTeam .. " flag.")
            setMarkerEnabled(flagTeam, false)
        else
            updateFlagActionPrompt(localTeam, flagTeam, stateObject)
            local shouldShowMarker, markerText, markerStyle = getMarkerPresentation(localTeam, flagTeam, stateObject, localPlayerHasEnemyFlag)
            if not shouldShowMarker then
                setMarkerEnabled(flagTeam, false)
            else
                local adorneePart, verticalOffset = findMarkerPart(flagTeam, stateObject)
                if not adorneePart then
                    warnOnce("FlagAnchorMissing_" .. flagTeam, "[FlagObjectiveMarkers] Could not find an anchor for the " .. flagTeam .. " flag marker.")
                    setMarkerEnabled(flagTeam, false)
                else
                    local marker = ensureMarker(flagTeam, adorneePart, verticalOffset, flagTeam)
                    marker.label.Text = markerText
                    applyMarkerStyle(marker, markerStyle, flagTeam, localTeam)
                    marker.returnDeadline = stateObject:GetAttribute("IsDropped") == true and (tonumber(stateObject:GetAttribute(RETURN_DEADLINE_ATTRIBUTE)) or 0) or 0
                    marker.gui.Enabled = true
                end
            end
        end
    end

    local localFlagState = stateObjects[localTeam]
    local shouldShowHoldMarker = localPlayerHasEnemyFlag and localFlagState and localFlagState:GetAttribute("AtBase") ~= true
    if shouldShowHoldMarker then
        local holdPart, holdOffset = findStandMarkerPart(localTeam)
        if not holdPart then
            warnOnce("FlagHoldAnchorMissing_" .. localTeam, "[FlagObjectiveMarkers] Could not find an anchor for the RETURN stand marker.")
            setMarkerEnabled("Hold", false)
        else
            local holdMarker = ensureMarker("Hold", holdPart, holdOffset, localTeam)
            holdMarker.label.Text = "RETURN"
            applyMarkerStyle(holdMarker, "hold", localTeam, localTeam)
            holdMarker.returnDeadline = 0
            holdMarker.gui.Enabled = true
        end
    else
        setMarkerEnabled("Hold", false)
    end
end

local initialStateFolder = ReplicatedStorage:FindFirstChild("FlagStates")
if initialStateFolder and initialStateFolder:IsA("Folder") then
    wireFlagStatesFolder(initialStateFolder)
else
    ReplicatedStorage.ChildAdded:Connect(function(child)
        if child.Name == "FlagStates" and child:IsA("Folder") then
            wireFlagStatesFolder(child)
        end
    end)
    task.delay(10, function()
        if not flagStatesFolder then
            warnOnce("FlagStatesMissingDelayed", "[FlagObjectiveMarkers] ReplicatedStorage.FlagStates was not found after waiting.")
        end
    end)
end

localPlayer:GetPropertyChangedSignal("Team"):Connect(scheduleUpdate)
localPlayer:GetAttributeChangedSignal("Team"):Connect(scheduleUpdate)
localPlayer.CharacterAdded:Connect(function()
    task.delay(0.25, scheduleUpdate)
end)

for _, playerInstance in ipairs(Players:GetPlayers()) do
    playerInstance:GetPropertyChangedSignal("Team"):Connect(scheduleUpdate)
    playerInstance.CharacterAdded:Connect(function()
        task.delay(0.25, scheduleUpdate)
    end)
end
Players.PlayerAdded:Connect(function(playerInstance)
    playerInstance:GetPropertyChangedSignal("Team"):Connect(scheduleUpdate)
    playerInstance.CharacterAdded:Connect(function()
        task.delay(0.25, scheduleUpdate)
    end)
    scheduleUpdate()
end)
Players.PlayerRemoving:Connect(scheduleUpdate)

Workspace.DescendantAdded:Connect(function(descendant)
    local descendantName = string.lower(descendant.Name)
    if string.find(descendantName, "flag") or descendant.Name == "HumanoidRootPart" or descendantName == "plane" or descendantName == "stone" or descendant.Name == FLAG_ACTION_PROMPT_NAME then
        scheduleUpdate()
    end
end)
Workspace.DescendantRemoving:Connect(function(descendant)
    local descendantName = string.lower(descendant.Name)
    if string.find(descendantName, "flag") or descendant.Name == "HumanoidRootPart" or descendantName == "plane" or descendantName == "stone" or descendant.Name == FLAG_ACTION_PROMPT_NAME then
        scheduleUpdate()
    end
end)

local flagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
if flagStatus and flagStatus:IsA("RemoteEvent") then
    flagStatus.OnClientEvent:Connect(function(eventType)
        if eventType == "pickup" or eventType == "returned" or eventType == "captured" then
            scheduleUpdate()
            task.delay(0.15, scheduleUpdate)
        end
    end)
end

local pulseClock = 0
RunService.RenderStepped:Connect(function(deltaTime)
    pulseClock += deltaTime
    local pulseAlpha = (math.sin(pulseClock * 6) + 1) * 0.5
    local now = Workspace:GetServerTimeNow()

    for _, marker in pairs(markers) do
        if marker.gui and marker.gui.Enabled then
            if marker.styleName == "capture" and marker.label and marker.badge and marker.pointer then
                marker.label.TextColor3 = CAPTURE_MARKER_COLOR:Lerp(CAPTURE_MARKER_PULSE_COLOR, pulseAlpha)
                local accentColor = CAPTURE_MARKER_COLOR:Lerp(CAPTURE_MARKER_PULSE_COLOR, pulseAlpha * 0.3)
                marker.badge.BackgroundColor3 = accentColor
                marker.pointer.BackgroundColor3 = accentColor
            end

            if marker.timerBadge and marker.timerLabel then
                local remaining = (tonumber(marker.returnDeadline) or 0) - now
                local showTimer = remaining > 0.05
                marker.timerBadge.Visible = showTimer
                if showTimer then
                    marker.timerLabel.Text = tostring(math.ceil(remaining))
                end
            end
        elseif marker.timerBadge then
            marker.timerBadge.Visible = false
        end
    end
end)

scheduleUpdate()