local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SpinWheelConfig = require(ReplicatedStorage:WaitForChild("SpinWheelConfig"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 15)
if not remotesFolder then
    warn("[SpinWheel] Remotes folder missing")
    return
end

local spinWheelFolder = remotesFolder:WaitForChild("SpinWheel", 15)
if not spinWheelFolder then
    warn("[SpinWheel] SpinWheel remotes missing")
    return
end

local getStateRF = spinWheelFolder:WaitForChild("GetSpinWheelState", 15)
local requestSpinRF = spinWheelFolder:WaitForChild("RequestSpinWheelSpin", 15)
local buyPackRF = spinWheelFolder:WaitForChild("RequestBuyWheelSpinPack", 15)
if not getStateRF or not requestSpinRF or not buyPackRF then
    warn("[SpinWheel] SpinWheel remote functions missing")
    return
end

local function ensureChild(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing
    end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

local function formatCountdown(secondsRemaining)
    local total = math.max(0, math.floor(tonumber(secondsRemaining) or 0))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local seconds = total % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function getAdjustedServerTime(serverTimeOffset)
    return os.time() + (serverTimeOffset or 0)
end

local function playTickSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local tickSound = soundsFolder and soundsFolder:FindFirstChild("Tick")
    if not (tickSound and tickSound:IsA("Sound")) then
        return
    end

    local soundClone = tickSound:Clone()
    soundClone.Parent = tickSound.Parent
    soundClone:Play()
    soundClone.Ended:Once(function()
        pcall(function()
            soundClone:Destroy()
        end)
    end)
end

local function playWheelSpinSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local wheelSpinSound = soundsFolder and soundsFolder:FindFirstChild("WheelSpin")
    if not (wheelSpinSound and wheelSpinSound:IsA("Sound")) then
        return
    end

    local soundClone = wheelSpinSound:Clone()
    soundClone.Parent = wheelSpinSound.Parent
    soundClone:Play()
    soundClone.Ended:Once(function()
        pcall(function()
            soundClone:Destroy()
        end)
    end)
end

local function playWheelEndSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    local wheelEndSound = soundsFolder and soundsFolder:FindFirstChild("WheelEnd")
    if not (wheelEndSound and wheelEndSound:IsA("Sound")) then
        return
    end

    local soundClone = wheelEndSound:Clone()
    soundClone.Parent = wheelEndSound.Parent
    soundClone:Play()
    soundClone.Ended:Once(function()
        pcall(function()
            soundClone:Destroy()
        end)
    end)
end

local function resolveWheelParts()
    local model = Workspace:WaitForChild(SpinWheelConfig.ModelName, 30)
    if not (model and model:IsA("Model")) then
        warn("[SpinWheel] Missing wheel model", SpinWheelConfig.ModelName)
        return nil
    end

    local partNames = SpinWheelConfig.PartNames
    local promptPart = model:WaitForChild(partNames.PromptPart, 30)
    local wheelBase = model:WaitForChild(partNames.WheelBase, 30)
    local screenPart = model:WaitForChild(partNames.Screen, 30)
    local pointer = model:FindFirstChild(partNames.Pointer)

    if not (promptPart and promptPart:IsA("BasePart")) then
        warn("[SpinWheel] Missing PromptPart")
        return nil
    end
    if not (wheelBase and wheelBase:IsA("BasePart")) then
        warn("[SpinWheel] Missing WheelBase")
        return nil
    end
    if not (screenPart and screenPart:IsA("BasePart")) then
        warn("[SpinWheel] Missing Screen")
        return nil
    end
    if pointer and not pointer:IsA("BasePart") then
        pointer = nil
    end

    return {
        model = model,
        promptPart = promptPart,
        wheelBase = wheelBase,
        screenPart = screenPart,
        pointer = pointer,
    }
end

local function extractWheelLightOrder(part)
    local attrs = part:GetAttributes()

    local bestNumericKey = nil
    for key, value in pairs(attrs) do
        local numericKey = tonumber(key)
        if numericKey then
            if not bestNumericKey or numericKey < bestNumericKey then
                bestNumericKey = numericKey
            end
        end

        if key == "WheelLightIndex" or key == "LightIndex" or key == "Order" or key == "Index" then
            local numericValue = tonumber(value)
            if numericValue then
                return numericValue
            end
        end
    end

    if bestNumericKey then
        return bestNumericKey
    end

    local suffix = tonumber(string.match(part.Name, "(%d+)$"))
    return suffix
end

local function resolveWheelLights(model)
    local lights = {}
    local discoveredIndex = 0

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Name == "WheelLight" then
            discoveredIndex += 1

            local childLights = {}
            for _, child in ipairs(descendant:GetDescendants()) do
                if child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
                    table.insert(childLights, {
                        instance = child,
                        brightness = child.Brightness,
                        enabled = child.Enabled,
                        color = child.Color,
                    })
                end
            end

            table.insert(lights, {
                part = descendant,
                order = extractWheelLightOrder(descendant),
                discoveredIndex = discoveredIndex,
                baseColor = descendant.Color,
                baseTransparency = descendant.Transparency,
                childLights = childLights,
            })
        end
    end

    table.sort(lights, function(a, b)
        local left = a.order or math.huge
        local right = b.order or math.huge
        if left == right then
            return a.discoveredIndex < b.discoveredIndex
        end
        return left < right
    end)

    return lights
end

local wheelParts = resolveWheelParts()
if not wheelParts then
    return
end

local wheelLights = resolveWheelLights(wheelParts.model)

local function makeLoadingState()
    return {
        isLoaded = false,
        canSpinNow = false,
        canUseFreeSpin = false,
        canUsePaidSpin = false,
        canAttemptSpin = false,
        serverTime = os.time(),
        nextFreeSpinAt = 0,
        secondsRemaining = 0,
        wheelSpins = 0,
    }
end

local prompt = ensureChild(wheelParts.promptPart, "ProximityPrompt", "SpinWheelPrompt")
prompt.ActionText = SpinWheelConfig.Labels.PromptAction
prompt.ObjectText = SpinWheelConfig.Labels.LoadingBody
prompt.KeyboardKeyCode = SpinWheelConfig.PromptKeyboardKeyCode
prompt.MaxActivationDistance = SpinWheelConfig.PromptMaxActivationDistance
prompt.HoldDuration = 0
prompt.RequiresLineOfSight = false
prompt.Style = Enum.ProximityPromptStyle.Default
prompt.Enabled = false

local surfaceGui = ensureChild(wheelParts.screenPart, "SurfaceGui", "SpinWheelSurfaceGui")
surfaceGui.Adornee = wheelParts.screenPart
surfaceGui.Face = SpinWheelConfig.ScreenFace
surfaceGui.ResetOnSpawn = false
surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
surfaceGui.PixelsPerStud = SpinWheelConfig.ScreenPixelsPerStud
surfaceGui.LightInfluence = 0
surfaceGui.AlwaysOnTop = false
surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = ensureChild(surfaceGui, "Frame", "Root")
root.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)

local rootCorner = ensureChild(root, "UICorner", "Corner")
rootCorner.CornerRadius = UDim.new(0, 10)

local rootStroke = ensureChild(root, "UIStroke", "Stroke")
rootStroke.Color = Color3.fromRGB(65, 68, 77)
rootStroke.Thickness = 2
rootStroke.Transparency = 0.2

local headerLabel = ensureChild(root, "TextLabel", "Header")
headerLabel.BackgroundTransparency = 1
headerLabel.Size = UDim2.new(1, -16, 0.4, 0)
headerLabel.Position = UDim2.new(0, 8, 0, 6)
headerLabel.Font = Enum.Font.GothamBlack
headerLabel.TextColor3 = Color3.fromRGB(255, 208, 64)
headerLabel.TextScaled = true
headerLabel.TextWrapped = true
headerLabel.Text = SpinWheelConfig.Labels.LoadingHeader

local bodyLabel = ensureChild(root, "TextLabel", "Body")
bodyLabel.BackgroundTransparency = 1
bodyLabel.Size = UDim2.new(1, -16, 0.46, 0)
bodyLabel.Position = UDim2.new(0, 8, 0.42, 0)
bodyLabel.Font = Enum.Font.GothamBold
bodyLabel.TextColor3 = Color3.fromRGB(235, 239, 244)
bodyLabel.TextScaled = true
bodyLabel.TextWrapped = true
bodyLabel.Text = SpinWheelConfig.Labels.LoadingBody

local overlayGui = ensureChild(playerGui, "ScreenGui", "SpinWheelOverlayGui")
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.DisplayOrder = 45

local toastContainer = ensureChild(overlayGui, "Frame", "ToastContainer")
toastContainer.BackgroundTransparency = 1
toastContainer.AnchorPoint = Vector2.new(0.5, 1)
toastContainer.Position = UDim2.new(0.5, 0, 1, -180)
toastContainer.Size = UDim2.new(0, 420, 0, 100)

local modalShade = ensureChild(overlayGui, "Frame", "PurchaseShade")
modalShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
modalShade.BackgroundTransparency = 0.3
modalShade.BorderSizePixel = 0
modalShade.Size = UDim2.fromScale(1, 1)
modalShade.Visible = false

local modalCard = ensureChild(modalShade, "Frame", "PurchaseCard")
modalCard.AnchorPoint = Vector2.new(0.5, 0.5)
modalCard.Position = UDim2.fromScale(0.5, 0.5)
modalCard.Size = UDim2.new(0, 430, 0, 330)
modalCard.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
modalCard.BorderSizePixel = 0

local modalCorner = ensureChild(modalCard, "UICorner", "Corner")
modalCorner.CornerRadius = UDim.new(0, 14)

local modalStroke = ensureChild(modalCard, "UIStroke", "Stroke")
modalStroke.Color = Color3.fromRGB(74, 85, 110)
modalStroke.Thickness = 2
modalStroke.Transparency = 0.1

local modalHeader = ensureChild(modalCard, "TextLabel", "Header")
modalHeader.BackgroundTransparency = 1
modalHeader.Size = UDim2.new(1, -30, 0, 56)
modalHeader.Position = UDim2.new(0, 15, 0, 18)
modalHeader.Font = Enum.Font.GothamBlack
modalHeader.TextSize = 30
modalHeader.TextColor3 = Color3.fromRGB(255, 208, 64)
modalHeader.Text = SpinWheelConfig.Labels.PurchaseHeader

local modalBody = ensureChild(modalCard, "TextLabel", "Body")
modalBody.BackgroundTransparency = 1
modalBody.Size = UDim2.new(1, -30, 0, 56)
modalBody.Position = UDim2.new(0, 15, 0, 68)
modalBody.Font = Enum.Font.GothamMedium
modalBody.TextSize = 20
modalBody.TextColor3 = Color3.fromRGB(227, 232, 240)
modalBody.TextWrapped = true
modalBody.Text = SpinWheelConfig.Labels.PurchaseBody

local buttonList = ensureChild(modalCard, "Frame", "ButtonList")
buttonList.BackgroundTransparency = 1
buttonList.Size = UDim2.new(1, -30, 0, 150)
buttonList.Position = UDim2.new(0, 15, 0, 128)

local buttonLayout = ensureChild(buttonList, "UIListLayout", "Layout")
buttonLayout.FillDirection = Enum.FillDirection.Vertical
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Top
buttonLayout.Padding = UDim.new(0, 10)

local cancelButton = ensureChild(modalCard, "TextButton", "CancelButton")
cancelButton.Size = UDim2.new(1, -30, 0, 44)
cancelButton.Position = UDim2.new(0, 15, 1, -58)
cancelButton.BackgroundColor3 = Color3.fromRGB(42, 47, 60)
cancelButton.BorderSizePixel = 0
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 18
cancelButton.TextColor3 = Color3.fromRGB(235, 239, 244)
cancelButton.Text = SpinWheelConfig.Labels.PurchaseCancel

local cancelCorner = ensureChild(cancelButton, "UICorner", "Corner")
cancelCorner.CornerRadius = UDim.new(0, 10)

local wheelBaseStartCFrame = wheelParts.wheelBase.CFrame
local currentAngleDegrees = 0
local requestInFlight = false
local isSpinning = false
local spinSequenceLocked = false
local purchaseModalOpen = false
local currentState = makeLoadingState()
local serverTimeOffset = 0
local lastScreenKey = nil
local stateFetchInFlight = false
local lastStateRefreshAt = 0
local lightMode = "loading"
local lightModeStartedAt = os.clock()
local lightModeEndsAt = nil
local lastLightUpdateAt = os.clock()
local lightHeadPosition = 1
local startLightAnchorPosition = 1
local winLightAnchorPosition = 1
local rainbowCycleColors = {
    Color3.fromRGB(255, 72, 72),
    Color3.fromRGB(255, 150, 56),
    Color3.fromRGB(255, 234, 92),
    Color3.fromRGB(86, 232, 116),
    Color3.fromRGB(82, 162, 255),
    Color3.fromRGB(176, 98, 255),
}
local idleLightColor = Color3.fromRGB(255, 244, 196)
local spinWhiteColor = Color3.fromRGB(255, 252, 244)
local spinYellowColor = Color3.fromRGB(255, 228, 110)
local currentSpinColors = {
    spinWhiteColor,
    rainbowCycleColors[1],
}

local function wrapLightPosition(position, count)
    if count <= 0 then
        return 1
    end
    return ((position - 1) % count) + 1
end

local function setLightHeadPosition(position)
    local count = #wheelLights
    if count <= 0 then
        lightHeadPosition = 1
        return
    end

    lightHeadPosition = wrapLightPosition(position, count)
end

local function getLightOrbitSpeed(mode, count)
    if count <= 0 then
        return 0
    end

    local loopDuration = math.max(0.001, tonumber(SpinWheelConfig.LightShowStartDuration) or 1.0)

    if mode == "idle" then
        return 3.2
    end

    if mode == "start" then
        return count / loopDuration
    end

    if mode == "spinning" then
        return 7.5
    end

    if mode == "win" then
        return count / loopDuration
    end

    return 0
end

local function advanceLightHead(now)
    local count = #wheelLights
    if count <= 0 then
        lastLightUpdateAt = now
        return
    end

    local deltaTime = math.max(0, now - lastLightUpdateAt)
    if deltaTime > 0 then
        local orbitSpeed = getLightOrbitSpeed(lightMode, count)
        if orbitSpeed ~= 0 then
            lightHeadPosition = wrapLightPosition(lightHeadPosition + (orbitSpeed * deltaTime), count)
        end
    end

    lastLightUpdateAt = now
end

local function chooseSpinColors()
    local colorPool = { spinWhiteColor }
    for _, color in ipairs(rainbowCycleColors) do
        table.insert(colorPool, color)
    end

    if #colorPool <= 1 then
        currentSpinColors = { spinWhiteColor, spinYellowColor }
        return
    end

    local firstIndex = math.random(1, #colorPool)
    local secondIndex = firstIndex
    while secondIndex == firstIndex do
        secondIndex = math.random(1, #colorPool)
    end

    currentSpinColors = {
        colorPool[firstIndex],
        colorPool[secondIndex],
    }
end

local function setLightMode(mode, durationSeconds, anchorPosition)
    local now = os.clock()
    advanceLightHead(now)
    if anchorPosition ~= nil then
        setLightHeadPosition(anchorPosition)
    end

    lightMode = mode
    lightModeStartedAt = now
    if durationSeconds and durationSeconds > 0 then
        lightModeEndsAt = lightModeStartedAt + durationSeconds
    else
        lightModeEndsAt = nil
    end

    if mode == "start" then
        startLightAnchorPosition = lightHeadPosition
    elseif mode == "win" then
        winLightAnchorPosition = lightHeadPosition
    end

    if mode == "spinning" then
        chooseSpinColors()
    end
end

local function applyWheelLightVisual(lightData, brightness, colorOverride)
    brightness = math.clamp(brightness or 0, 0, 1)
    local targetColor = colorOverride or lightData.baseColor
    local partColor = lightData.baseColor:Lerp(targetColor, brightness)

    lightData.part.Color = partColor
    lightData.part.Transparency = math.clamp(lightData.baseTransparency + (1 - brightness) * 0.65, 0, 0.95)

    for _, childLight in ipairs(lightData.childLights) do
        childLight.instance.Color = childLight.color:Lerp(targetColor, brightness)
        childLight.instance.Enabled = brightness > 0.06
        childLight.instance.Brightness = math.max(0.05, childLight.brightness * (0.2 + brightness * 0.8))
    end
end

local function updateWheelLights(now)
    local count = #wheelLights
    if count == 0 then
        return
    end

    advanceLightHead(now)

    if lightMode == "loading" then
        local pulse = 0.2 + 0.35 * (0.5 + 0.5 * math.sin(now * 2.4))
        for _, lightData in ipairs(wheelLights) do
            applyWheelLightVisual(lightData, pulse, nil)
        end
        return
    end

    if lightMode == "idle" then
        local head = lightHeadPosition
        local idleSpeed = math.max(0.001, getLightOrbitSpeed("idle", count))
        local fadeDurationSeconds = 1
        for index, lightData in ipairs(wheelLights) do
            local trailDistance = (head - index) % count
            local leadDistance = (index - head) % count
            local brightness = 0

            local trailTime = trailDistance / idleSpeed
            local leadTime = leadDistance / idleSpeed

            if trailTime <= fadeDurationSeconds then
                local normalized = math.clamp(1 - (trailTime / fadeDurationSeconds), 0, 1)
                brightness = normalized * normalized * (3 - (2 * normalized))
            elseif leadTime <= fadeDurationSeconds then
                local normalized = math.clamp(1 - (leadTime / fadeDurationSeconds), 0, 1)
                brightness = normalized * normalized * (3 - (2 * normalized))
            end

            applyWheelLightVisual(lightData, brightness, idleLightColor)
        end
        return
    end

    if lightMode == "start" then
        local headIndex = math.floor(wrapLightPosition(lightHeadPosition, count))
        for index, lightData in ipairs(wheelLights) do
            local segmentIndex = (index - headIndex) % count
            local brightness = 0
            local color = lightData.baseColor
            if segmentIndex < 6 then
                brightness = 1 - (segmentIndex * 0.1)
                color = (segmentIndex % 2 == 0) and spinWhiteColor or spinYellowColor
            end
            applyWheelLightVisual(lightData, brightness, color)
        end
        return
    end

    if lightMode == "spinning" then
        local headIndex = math.floor(wrapLightPosition(lightHeadPosition, count))
        for index, lightData in ipairs(wheelLights) do
            local patternIndex = ((index - headIndex) % #currentSpinColors) + 1
            local brightness = 0.85 + (0.15 * (0.5 + 0.5 * math.sin(((now - lightModeStartedAt) * 8) + index)))
            local color = currentSpinColors[patternIndex]
            applyWheelLightVisual(lightData, brightness, color)
        end
        return
    end

    if lightMode == "win" then
        local headIndex = math.floor(wrapLightPosition(lightHeadPosition, count))
        for index, lightData in ipairs(wheelLights) do
            local segmentIndex = (index - headIndex) % count
            local brightness = 0
            local color = lightData.baseColor
            if segmentIndex < #rainbowCycleColors then
                color = rainbowCycleColors[segmentIndex + 1]
                brightness = 1
            end
            applyWheelLightVisual(lightData, brightness, color)
        end
        return
    end

    for _, lightData in ipairs(wheelLights) do
        applyWheelLightVisual(lightData, 0.35, nil)
    end
end

local function syncAmbientWheelMode()
    if isSpinning then
        return
    end

    if currentState.isLoaded ~= true then
        if lightMode ~= "loading" then
            setLightMode("loading")
        end
        return
    end

    if lightMode ~= "idle" then
        setLightMode("idle")
    end
end

local function applyWheelAngle(angleDegrees)
    local radians = math.rad((tonumber(angleDegrees) or 0) * (SpinWheelConfig.RotationDirection or 1))
    local axis = string.upper(tostring(SpinWheelConfig.RotationAxis or "Z"))

    if axis == "X" then
        wheelParts.wheelBase.CFrame = wheelBaseStartCFrame * CFrame.Angles(radians, 0, 0)
    elseif axis == "Y" then
        wheelParts.wheelBase.CFrame = wheelBaseStartCFrame * CFrame.Angles(0, radians, 0)
    else
        wheelParts.wheelBase.CFrame = wheelBaseStartCFrame * CFrame.Angles(0, 0, radians)
    end
end

local function showToast(message, color)
    local toast = Instance.new("TextLabel")
    toast.Name = "Toast"
    toast.BackgroundColor3 = Color3.fromRGB(18, 20, 36)
    toast.BackgroundTransparency = 1
    toast.Size = UDim2.new(1, 0, 0, 58)
    toast.AnchorPoint = Vector2.new(0.5, 1)
    toast.Position = UDim2.new(0.5, 0, 1, 40)
    toast.Font = Enum.Font.GothamBold
    toast.TextSize = 26
    toast.TextColor3 = color or Color3.fromRGB(123, 255, 94)
    toast.Text = message
    toast.TextWrapped = true
    toast.Parent = toastContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = toast

    local stroke = Instance.new("UIStroke")
    stroke.Color = toast.TextColor3
    stroke.Thickness = 1.2
    stroke.Transparency = 0.35
    stroke.Parent = toast

    local tweenIn = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.08,
        Position = UDim2.new(0.5, 0, 1, 0),
    })
    tweenIn:Play()

    task.delay(2.8, function()
        if not toast.Parent then
            return
        end
        local tweenOut = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1,
            TextTransparency = 1,
            Position = UDim2.new(0.5, 0, 1, 40),
        })
        tweenOut:Play()
        tweenOut.Completed:Once(function()
            pcall(function()
                toast:Destroy()
            end)
        end)
    end)
end

local function updateServerTimeOffset(state)
    if type(state) == "table" and type(state.serverTime) == "number" then
        serverTimeOffset = state.serverTime - os.time()
    end
end

local function getCurrentSecondsRemaining()
    if type(currentState) ~= "table" or currentState.isLoaded ~= true then
        return 0
    end
    local nextFreeSpinAt = math.floor(tonumber(currentState.nextFreeSpinAt) or 0)
    return math.max(0, nextFreeSpinAt - getAdjustedServerTime(serverTimeOffset))
end

local function getWheelSpinsCount()
    if type(currentState) ~= "table" then
        return 0
    end
    return math.max(0, math.floor(tonumber(currentState.wheelSpins) or 0))
end

local function closePurchaseModal()
    purchaseModalOpen = false
    modalShade.Visible = false
    prompt.Enabled = currentState.isLoaded == true and not requestInFlight and not isSpinning and not spinSequenceLocked
end

local function updatePromptState()
    prompt.ActionText = SpinWheelConfig.Labels.PromptAction
    if currentState.isLoaded ~= true then
        prompt.ObjectText = SpinWheelConfig.Labels.LoadingBody
        prompt.Enabled = false
        return
    end

    prompt.ObjectText = string.format("%s %d", SpinWheelConfig.Labels.PromptObjectPrefix, getWheelSpinsCount())
    prompt.Enabled = not requestInFlight and not isSpinning and not spinSequenceLocked and not purchaseModalOpen
end

local function updateScreen()
    local secondsRemaining = getCurrentSecondsRemaining()
    local wheelSpinsCount = getWheelSpinsCount()
    local stateKey
    if currentState.isLoaded ~= true then
        stateKey = "loading"
    elseif secondsRemaining <= 0 then
        stateKey = string.format("ready|%d", wheelSpinsCount)
    else
        stateKey = string.format("cooldown|%d|%d", secondsRemaining, wheelSpinsCount)
    end

    if lastScreenKey == stateKey then
        updatePromptState()
        return
    end
    lastScreenKey = stateKey

    if currentState.isLoaded ~= true then
        headerLabel.Text = SpinWheelConfig.Labels.LoadingHeader
        headerLabel.TextColor3 = Color3.fromRGB(150, 210, 255)
        bodyLabel.Text = SpinWheelConfig.Labels.LoadingBody
        bodyLabel.TextColor3 = Color3.fromRGB(235, 239, 244)
    elseif secondsRemaining <= 0 then
        headerLabel.Text = SpinWheelConfig.Labels.ReadyHeader
        headerLabel.TextColor3 = Color3.fromRGB(123, 255, 94)
        bodyLabel.Text = string.format("%s\n%s %d", SpinWheelConfig.Labels.ReadyBody, SpinWheelConfig.Labels.PromptObjectPrefix, wheelSpinsCount)
        bodyLabel.TextColor3 = Color3.fromRGB(235, 239, 244)
    else
        headerLabel.Text = SpinWheelConfig.Labels.CooldownHeader
        headerLabel.TextColor3 = Color3.fromRGB(255, 208, 64)
        bodyLabel.Text = string.format("%s\n%s %d", formatCountdown(secondsRemaining), SpinWheelConfig.Labels.PromptObjectPrefix, wheelSpinsCount)
        bodyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    updatePromptState()
end

local function setState(state)
    if type(state) ~= "table" then
        return
    end
    currentState = state
    updateServerTimeOffset(state)
    updateScreen()
    syncAmbientWheelMode()
end

local function refreshState()
    if stateFetchInFlight then
        return false
    end

    stateFetchInFlight = true
    local ok, result = pcall(function()
        return getStateRF:InvokeServer()
    end)
    stateFetchInFlight = false
    lastStateRefreshAt = os.clock()
    if not ok then
        warn("[SpinWheel] Failed to fetch state:", result)
        return false
    end
    setState(result)
    return true
end

local function animateSpin(resultPayload)
    if type(resultPayload) ~= "table" then
        return
    end

    isSpinning = true
    spinSequenceLocked = true
    local startupDuration = (tonumber(SpinWheelConfig.LightShowStartDuration) or 1.0) + 0.5
    setLightMode("start", startupDuration)
    playWheelSpinSound()
    updatePromptState()

    local startAngle = currentAngleDegrees
    local sectorAngle = SpinWheelConfig.GetSectorAngle()
    local targetAngle = startAngle
        + ((tonumber(resultPayload.fullRotations) or SpinWheelConfig.FullRotations) * 360)
        + (tonumber(resultPayload.landingAngle) or 0)
    local angleValue = Instance.new("NumberValue")
    angleValue.Value = startAngle
    angleValue.Parent = wheelParts.model

    local lastTickStep = math.floor(startAngle / sectorAngle)
    local finalTickMuteAngle = tonumber(SpinWheelConfig.GetFinalTickMuteAngle and SpinWheelConfig.GetFinalTickMuteAngle() or (sectorAngle * 0.85)) or (sectorAngle * 0.85)
    local angleConn = angleValue:GetPropertyChangedSignal("Value"):Connect(function()
        local currentAngle = angleValue.Value
        applyWheelAngle(currentAngle)

        local remainingAngle = targetAngle - currentAngle
        if remainingAngle <= finalTickMuteAngle then
            return
        end

        local currentTickStep = math.floor(currentAngle / sectorAngle)
        if currentTickStep > lastTickStep then
            for _ = lastTickStep + 1, currentTickStep do
                playTickSound()
            end
            lastTickStep = currentTickStep
        end
    end)

    local tween = TweenService:Create(angleValue, TweenInfo.new(
        tonumber(resultPayload.spinDuration) or SpinWheelConfig.SpinDuration,
        SpinWheelConfig.EasingStyle,
        SpinWheelConfig.EasingDirection
    ), {
        Value = targetAngle,
    })

    task.delay(startupDuration, function()
        if not isSpinning or not angleValue.Parent then
            return
        end
        setLightMode("spinning", nil, startLightAnchorPosition)
        tween:Play()
    end)

    tween.Completed:Once(function()
        angleConn:Disconnect()
        currentAngleDegrees = targetAngle % 360
        applyWheelAngle(currentAngleDegrees)
        angleValue:Destroy()
        isSpinning = false
        setLightMode("win", SpinWheelConfig.LightShowWinDuration or 1.1, 1)
        playWheelEndSound()
        updatePromptState()
        showToast(string.format("You got %d coins!", tonumber(resultPayload.reward) or 0), Color3.fromRGB(123, 255, 94))
    end)
end

local function openPurchaseModal()
    if currentState.isLoaded ~= true then
        return
    end
    purchaseModalOpen = true
    modalShade.Visible = true
    updatePromptState()
end

local function handlePurchaseResult(success, message, payload)
    local responseState = type(payload) == "table" and payload.state or nil
    if responseState then
        setState(responseState)
    end

    if success then
        closePurchaseModal()
        showToast(message ~= "" and message or SpinWheelConfig.Labels.PurchaseSuccess, Color3.fromRGB(123, 255, 94))
        return
    end

    if type(message) == "string" and message ~= "" then
        showToast(message, Color3.fromRGB(255, 153, 83))
    end
end

for index, pack in ipairs(SpinWheelConfig.SpinPacks) do
    local button = ensureChild(buttonList, "TextButton", "PackButton" .. tostring(index))
    button.Size = UDim2.new(1, 0, 0, 42)
    button.BackgroundColor3 = Color3.fromRGB(34, 39, 52)
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Font = Enum.Font.GothamBold
    button.TextSize = 19
    button.TextColor3 = Color3.fromRGB(245, 247, 250)
    button.Text = string.format("%d Wheel Spins  •  R$%d", pack.spins, pack.robuxPrice)

    local buttonCorner = ensureChild(button, "UICorner", "Corner")
    buttonCorner.CornerRadius = UDim.new(0, 10)

    local buttonStroke = ensureChild(button, "UIStroke", "Stroke")
    buttonStroke.Color = Color3.fromRGB(255, 208, 64)
    buttonStroke.Transparency = 0.35
    buttonStroke.Thickness = 1

    button.MouseButton1Click:Connect(function()
        if requestInFlight then
            return
        end

        if pack.productId and pack.productId > 0 and not SpinWheelConfig.TestPurchaseBypass then
            closePurchaseModal()
            local ok, err = pcall(function()
                MarketplaceService:PromptProductPurchase(player, pack.productId)
            end)
            if ok then
                showToast(SpinWheelConfig.Labels.PurchasePending, Color3.fromRGB(150, 210, 255))
            else
                warn("[SpinWheel] PromptProductPurchase failed:", tostring(err))
                showToast("Unable to open purchase prompt", Color3.fromRGB(255, 153, 83))
            end
            return
        end

        requestInFlight = true
        updatePromptState()

        local ok, success, message, payload = pcall(function()
            return buyPackRF:InvokeServer(index)
        end)

        requestInFlight = false
        if not ok then
            warn("[SpinWheel] Buy pack request failed:", success)
            showToast("Unable to add Wheel Spins", Color3.fromRGB(255, 153, 83))
            updatePromptState()
            return
        end

        handlePurchaseResult(success, message, payload)
        updatePromptState()
    end)
end

cancelButton.MouseButton1Click:Connect(function()
    closePurchaseModal()
end)

prompt.Triggered:Connect(function()
    if requestInFlight or isSpinning or spinSequenceLocked or purchaseModalOpen then
        return
    end
    if currentState.isLoaded ~= true then
        return
    end

    requestInFlight = true
    updatePromptState()

    local ok, success, message, payload = pcall(function()
        return requestSpinRF:InvokeServer()
    end)

    requestInFlight = false

    if not ok then
        warn("[SpinWheel] Spin request failed:", success)
        refreshState()
        updatePromptState()
        return
    end

    if success then
        if type(payload) == "table" and type(payload.state) == "table" then
            setState(payload.state)
        end
        animateSpin(payload)
        return
    end

    local reasonCode = nil
    local responseState = nil
    if type(payload) == "table" then
        reasonCode = payload.reasonCode
        responseState = payload.state or payload
    end

    if type(responseState) == "table" then
        setState(responseState)
    else
        refreshState()
    end

    if reasonCode == "purchase_required" then
        openPurchaseModal()
    elseif type(message) == "string" and message ~= "" then
        showToast(message, Color3.fromRGB(255, 153, 83))
    end
    updatePromptState()
end)

setState(makeLoadingState())
refreshState()
syncAmbientWheelMode()

task.spawn(function()
    while true do
        if currentState.isLoaded ~= true and not stateFetchInFlight and not requestInFlight then
            local retryInterval = tonumber(SpinWheelConfig.LoadRetryInterval) or 1
            if (os.clock() - lastStateRefreshAt) >= retryInterval then
                refreshState()
            end
        end
        updateScreen()
        task.wait(0.25)
    end
end)

RunService.RenderStepped:Connect(function(deltaTime)
    local now = os.clock()

    if lightModeEndsAt and now >= lightModeEndsAt then
        if lightMode == "win" then
            spinSequenceLocked = false
            setLightMode("idle", nil, winLightAnchorPosition)
            updatePromptState()
        else
            lightModeEndsAt = nil
        end
    end

    if not isSpinning and currentState.isLoaded == true and lightMode == "idle" then
        currentAngleDegrees = (currentAngleDegrees + (tonumber(SpinWheelConfig.IdleRotationDegreesPerSecond) or 4) * deltaTime) % 360
        applyWheelAngle(currentAngleDegrees)
    end

    updateWheelLights(now)
end)