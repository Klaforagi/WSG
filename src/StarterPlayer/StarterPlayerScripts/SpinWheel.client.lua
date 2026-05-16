local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local wheelParts = resolveWheelParts()
if not wheelParts then
    return
end

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
local purchaseModalOpen = false
local currentState = makeLoadingState()
local serverTimeOffset = 0
local lastScreenKey = nil

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
    prompt.Enabled = currentState.isLoaded == true and not requestInFlight and not isSpinning
end

local function updatePromptState()
    prompt.ActionText = SpinWheelConfig.Labels.PromptAction
    if currentState.isLoaded ~= true then
        prompt.ObjectText = SpinWheelConfig.Labels.LoadingBody
        prompt.Enabled = false
        return
    end

    prompt.ObjectText = string.format("%s %d", SpinWheelConfig.Labels.PromptObjectPrefix, getWheelSpinsCount())
    prompt.Enabled = not requestInFlight and not isSpinning and not purchaseModalOpen
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
        headerLabel.TextColor3 = Color3.fromRGB(255, 208, 64)
        bodyLabel.Text = string.format("%s\n%s %d", SpinWheelConfig.Labels.ReadyBody, SpinWheelConfig.Labels.PromptObjectPrefix, wheelSpinsCount)
        bodyLabel.TextColor3 = Color3.fromRGB(235, 239, 244)
    else
        headerLabel.Text = SpinWheelConfig.Labels.CooldownHeader
        headerLabel.TextColor3 = Color3.fromRGB(88, 190, 255)
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
end

local function refreshState()
    local ok, result = pcall(function()
        return getStateRF:InvokeServer()
    end)
    if not ok then
        warn("[SpinWheel] Failed to fetch state:", result)
        return
    end
    setState(result)
end

local function animateSpin(resultPayload)
    if type(resultPayload) ~= "table" then
        return
    end

    isSpinning = true
    updatePromptState()

    local startAngle = currentAngleDegrees
    local sectorAngle = SpinWheelConfig.GetSectorAngle()
    local targetAngle = startAngle
        + ((tonumber(resultPayload.fullRotations) or SpinWheelConfig.FullRotations) * 360)
        + (tonumber(resultPayload.landingAngle) or 0)
    local angleValue = Instance.new("NumberValue")
    angleValue.Value = startAngle

    local lastTickStep = math.floor(startAngle / sectorAngle)
    local angleConn = angleValue:GetPropertyChangedSignal("Value"):Connect(function()
        local currentAngle = angleValue.Value
        applyWheelAngle(currentAngle)

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

    tween:Play()
    tween.Completed:Once(function()
        angleConn:Disconnect()
        currentAngleDegrees = targetAngle % 360
        applyWheelAngle(currentAngleDegrees)
        angleValue:Destroy()
        isSpinning = false
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
    if requestInFlight or isSpinning or purchaseModalOpen then
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

task.spawn(function()
    while true do
        updateScreen()
        task.wait(0.25)
    end
end)