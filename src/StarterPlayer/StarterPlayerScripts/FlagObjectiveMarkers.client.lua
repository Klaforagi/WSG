local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local STATE_ATTRIBUTES = {"Team", "AtBase", "CarrierUserId", "CarrierTeam", "CarrierName", "IsCarried", "IsDropped"}

local markers = {}
local warnedKeys = {}
local wiredStateObjects = {}
local flagStatesFolder = nil
local updateScheduled = false
local updateMarkers = nil

for _, flagTeam in ipairs(FLAG_TEAMS) do
    markers[flagTeam] = {
        gui = nil,
        attachment = nil,
        adorneePart = nil,
        label = nil,
        badge = nil,
        pointer = nil,
        stroke = nil,
    }
end

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
            local standPart = root:FindFirstChild(standName, true)
            if standPart and standPart:IsA("BasePart") then
                return standPart
            end
        end
    end
    return nil
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

    for _, carriedName in ipairs(CARRIED_FLAG_MODEL_NAMES[flagTeam]) do
        local carriedFlag = character:FindFirstChild(carriedName)
        local carriedPart = getAdorneePart(carriedFlag)
        if carriedPart then
            return carriedPart
        end
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if isFlagInstance(descendant, flagTeam) and descendant:GetAttribute("IsCarried") == true then
            local carriedPart = getAdorneePart(descendant)
            if carriedPart then
                return carriedPart
            end
        end
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    return nil
end

local function findMarkerPart(flagTeam, stateObject)
    if stateObject and stateObject:GetAttribute("IsCarried") == true then
        local carriedPart = findCarriedFlagPart(flagTeam, getCarrierPlayer(stateObject))
        if carriedPart then
            return carriedPart, 3.2
        end
    end

    if stateObject and stateObject:GetAttribute("IsDropped") == true then
        local droppedFlag = findFlagInstance(flagTeam, true)
        local droppedPart = getAdorneePart(droppedFlag)
        if droppedPart then
            return droppedPart, 4.0
        end
    end

    local baseFlag = findFlagInstance(flagTeam, false) or findFlagInstance(flagTeam, nil)
    local basePart = getAdorneePart(baseFlag)
    if basePart then
        return basePart, 4.5
    end

    local standPart = findStandPart(flagTeam)
    if standPart then
        return standPart, 5.5
    end

    return nil, 0
end

local function destroyMarker(flagTeam)
    local marker = markers[flagTeam]
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
end

local function setMarkerEnabled(flagTeam, enabled)
    local marker = markers[flagTeam]
    if marker.gui then
        marker.gui.Enabled = enabled
    end
end

local function createMarker(flagTeam, adorneePart, verticalOffset)
    destroyMarker(flagTeam)

    local attachment = Instance.new("Attachment")
    attachment.Name = "FlagObjectiveMarker_" .. flagTeam
    attachment.Position = Vector3.new(0, math.max(2.5, (adorneePart.Size.Y * 0.5) + verticalOffset), 0)
    attachment.Parent = adorneePart

    local gui = Instance.new("BillboardGui")
    gui.Name = "FlagObjectiveMarker"
    gui.Adornee = attachment
    gui.AlwaysOnTop = true
    gui.MaxDistance = 1000
    gui.LightInfluence = 0
    gui.Size = UDim2.fromOffset(80, 42)
    gui.Enabled = false
    gui.Parent = attachment

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.BackgroundTransparency = 1
    root.BorderSizePixel = 0
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui

    local color = TEAM_COLORS[flagTeam]
    local darkColor = TEAM_DARK_COLORS[flagTeam]

    local pointer = Instance.new("Frame")
    pointer.Name = "Pointer"
    pointer.AnchorPoint = Vector2.new(0.5, 0)
    pointer.Position = UDim2.new(0.5, 0, 0, 17)
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
    badge.Position = UDim2.new(0.5, 0, 0, 2)
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

    local marker = markers[flagTeam]
    marker.gui = gui
    marker.attachment = attachment
    marker.adorneePart = adorneePart
    marker.label = label
    marker.badge = badge
    marker.pointer = pointer
    marker.stroke = stroke

    return marker
end

local function ensureMarker(flagTeam, adorneePart, verticalOffset)
    local marker = markers[flagTeam]
    if marker.adorneePart ~= adorneePart or not marker.gui or not marker.gui.Parent then
        marker = createMarker(flagTeam, adorneePart, verticalOffset)
    elseif marker.attachment then
        marker.attachment.Position = Vector3.new(0, math.max(2.5, (adorneePart.Size.Y * 0.5) + verticalOffset), 0)
    end
    return marker
end

local function getMarkerText(localTeam, flagTeam, stateObject)
    if flagTeam == localTeam then
        local atBase = stateObject:GetAttribute("AtBase") == true
        local isCarried = stateObject:GetAttribute("IsCarried") == true
        local isDropped = stateObject:GetAttribute("IsDropped") == true
        if atBase and not isCarried and not isDropped then
            return "DEFEND"
        end
        return "RETURN"
    end

    local carrierTeam = canonicalTeamName(stateObject:GetAttribute("CarrierTeam"))
    if stateObject:GetAttribute("IsCarried") == true and carrierTeam == localTeam then
        return "ESCORT"
    end
    return "CAPTURE"
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
        end
        return
    end

    if not flagStatesFolder then
        warnOnce("FlagStatesMissing", "[FlagObjectiveMarkers] ReplicatedStorage.FlagStates was not found; flag objective markers are hidden.")
        for _, flagTeam in ipairs(FLAG_TEAMS) do
            setMarkerEnabled(flagTeam, false)
        end
        return
    end

    for _, flagTeam in ipairs(FLAG_TEAMS) do
        local stateObject = getStateObject(flagTeam)
        if not stateObject then
            warnOnce("FlagStateMissing_" .. flagTeam, "[FlagObjectiveMarkers] Missing replicated state for " .. flagTeam .. " flag.")
            setMarkerEnabled(flagTeam, false)
        else
            local adorneePart, verticalOffset = findMarkerPart(flagTeam, stateObject)
            if not adorneePart then
                warnOnce("FlagAnchorMissing_" .. flagTeam, "[FlagObjectiveMarkers] Could not find an anchor for the " .. flagTeam .. " flag marker.")
                setMarkerEnabled(flagTeam, false)
            else
                local marker = ensureMarker(flagTeam, adorneePart, verticalOffset)
                marker.label.Text = getMarkerText(localTeam, flagTeam, stateObject)
                marker.gui.Enabled = true
            end
        end
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
    if string.find(string.lower(descendant.Name), "flag") or descendant.Name == "HumanoidRootPart" then
        scheduleUpdate()
    end
end)
Workspace.DescendantRemoving:Connect(function(descendant)
    if string.find(string.lower(descendant.Name), "flag") or descendant.Name == "HumanoidRootPart" then
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

scheduleUpdate()