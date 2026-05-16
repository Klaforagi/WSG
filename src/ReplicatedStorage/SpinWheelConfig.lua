local SpinWheelConfig = {}

SpinWheelConfig.ModelName = "SpinTheWheel"
SpinWheelConfig.PartNames = {
    PromptPart = "PromptPart",
    WheelBase = "WheelBase",
    Pointer = "Pointer",
    Screen = "Screen",
}

SpinWheelConfig.CooldownSeconds = 2 * 60 * 60
SpinWheelConfig.SpinDuration = 4.2
SpinWheelConfig.FullRotations = 6
SpinWheelConfig.EasingStyle = Enum.EasingStyle.Quint
SpinWheelConfig.EasingDirection = Enum.EasingDirection.Out
SpinWheelConfig.ScreenFace = Enum.NormalId.Front
SpinWheelConfig.ScreenPixelsPerStud = 60
SpinWheelConfig.LoadRetryInterval = 1
SpinWheelConfig.PromptMaxActivationDistance = 10
SpinWheelConfig.PromptKeyboardKeyCode = Enum.KeyCode.E
SpinWheelConfig.RotationAxis = "Z"
SpinWheelConfig.RotationDirection = -1
SpinWheelConfig.TestPurchaseBypass = true

SpinWheelConfig.RewardSectors = {
    { reward = 50, label = "50 COINS" },
    { reward = 100, label = "100 COINS" },
    { reward = 150, label = "150 COINS" },
    { reward = 200, label = "200 COINS" },
    { reward = 250, label = "250 COINS" },
    { reward = 50, label = "50 COINS" },
    { reward = 100, label = "100 COINS" },
    { reward = 150, label = "150 COINS" },
    { reward = 200, label = "200 COINS" },
    { reward = 250, label = "250 COINS" },
}

SpinWheelConfig.SpinPacks = {
    {
        name = "Single Spin",
        spins = 1,
        robuxPrice = 19,
        productId = 0,
    },
    {
        name = "Spin Bundle",
        spins = 10,
        robuxPrice = 149,
        productId = 0,
    },
    {
        name = "Mega Spin Bundle",
        spins = 50,
        robuxPrice = 499,
        productId = 0,
    },
}

SpinWheelConfig.Labels = {
    LoadingHeader = "LOADING...",
    LoadingBody = "SYNCING YOUR SPINS",
    ReadyHeader = "SPIN READY!",
    ReadyBody = "PRESS E TO SPIN",
    CooldownHeader = "NEXT FREE SPIN",
    PromptAction = "Press E to Spin",
    PromptObjectPrefix = "Wheel Spins:",
    PurchaseHeader = "BUY WHEEL SPINS",
    PurchaseBody = "Choose how many Wheel Spins to add.",
    PurchaseCancel = "Not now",
    PurchasePending = "Opening purchase...",
    PurchaseSuccess = "Wheel Spins added!",
}

function SpinWheelConfig.GetSectorCount()
    return #SpinWheelConfig.RewardSectors
end

function SpinWheelConfig.GetSectorAngle()
    return 360 / SpinWheelConfig.GetSectorCount()
end

function SpinWheelConfig.GetRewardSector(index)
    return SpinWheelConfig.RewardSectors[index]
end

function SpinWheelConfig.GetSpinPack(index)
    return SpinWheelConfig.SpinPacks[index]
end

function SpinWheelConfig.GetFinalTickMuteAngle()
    return SpinWheelConfig.GetSectorAngle() * 0.85
end

return SpinWheelConfig