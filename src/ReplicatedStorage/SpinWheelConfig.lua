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
SpinWheelConfig.IdleRotationDegreesPerSecond = 5.5
SpinWheelConfig.LightShowStartDuration = 1.0
SpinWheelConfig.LightShowWinDuration = 1.6
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
SpinWheelConfig.LandingPaddingDegrees = 1
SpinWheelConfig.FinalTickMuteAngle = 6

local function normalizeAngle(angleDegrees)
    angleDegrees = tonumber(angleDegrees) or 0
    return ((angleDegrees + 180) % 360) - 180
end

local function normalizeAnglePositive(angleDegrees)
    angleDegrees = tonumber(angleDegrees) or 0
    return ((angleDegrees % 360) + 360) % 360
end

local function visualAngleToSpinAngle(angleDegrees)
    local direction = tonumber(SpinWheelConfig.RotationDirection) or 1
    return normalizeAngle((tonumber(angleDegrees) or 0) * direction)
end

local function toSpinRange(range)
    if type(range) ~= "table" then
        return nil
    end

    local direction = tonumber(SpinWheelConfig.RotationDirection) or 1
    local startAngle = visualAngleToSpinAngle(range.startAngle)
    local endAngle = visualAngleToSpinAngle(range.endAngle)

    if direction < 0 then
        startAngle, endAngle = endAngle, startAngle
    end

    return {
        startAngle = startAngle,
        endAngle = endAngle,
    }
end

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source) do
        result[index] = value
    end
    return result
end

local function rangeWidth(range)
    local startAngle = normalizeAnglePositive(range.startAngle)
    local endAngle = normalizeAnglePositive(range.endAngle)
    local width = endAngle - startAngle
    if width <= 0 then
        width += 360
    end
    return width
end

local function isAngleInRange(angleDegrees, range)
    local angle = normalizeAnglePositive(angleDegrees)
    local startAngle = normalizeAnglePositive(range.startAngle)
    local endAngle = normalizeAnglePositive(range.endAngle)
    if startAngle < endAngle then
        return angle >= startAngle and angle <= endAngle
    end
    return angle >= startAngle or angle <= endAngle
end

local function rangeMidpoint(range)
    local startAngle = normalizeAnglePositive(range.startAngle)
    local midpoint = startAngle + (rangeWidth(range) * 0.5)
    return normalizeAngle(midpoint)
end

local function pickWeightedEntry(entries, randomSource)
    local totalWeight = 0
    for _, entry in ipairs(entries) do
        local weight = math.max(0, tonumber(entry.weight) or 0)
        totalWeight += weight
    end

    if totalWeight <= 0 then
        return entries[1]
    end

    local roll
    if randomSource and randomSource.NextNumber then
        roll = randomSource:NextNumber(0, totalWeight)
    else
        roll = math.random() * totalWeight
    end

    local cumulative = 0
    for _, entry in ipairs(entries) do
        cumulative += math.max(0, tonumber(entry.weight) or 0)
        if roll <= cumulative then
            return entry
        end
    end

    return entries[#entries]
end

SpinWheelConfig.CoinRewards = {
    { amount = 50, weight = 150 },
    { amount = 75, weight = 120 },
    { amount = 100, weight = 95 },
    { amount = 150, weight = 70 },
    { amount = 200, weight = 52 },
    { amount = 250, weight = 36 },
    { amount = 350, weight = 22 },
    { amount = 500, weight = 10 },
    { amount = 750, weight = 3 },
    { amount = 1000, weight = 1 },
}

SpinWheelConfig.ScrapRewards = {
    { amount = 25, weight = 40 },
    { amount = 50, weight = 30 },
    { amount = 75, weight = 18 },
    { amount = 100, weight = 10 },
    { amount = 200, weight = 2 },
}

SpinWheelConfig.HealthPotionRewards = {
    { amount = 1, weight = 70 },
    { amount = 2, weight = 20 },
    { amount = 3, weight = 10 },
}

SpinWheelConfig.RewardSlices = {
    {
        id = "Red",
        colorName = "Red",
        weight = 1,
        label = "LEGENDARY CHEST",
        rewardType = "crate",
        crateId = "WheelLegendaryCrate",
        angleRanges = {
            { startAngle = -28.4, endAngle = 30.8 },
        },
    },
    {
        id = "Green",
        colorName = "Green",
        weight = 25,
        label = "COINS",
        rewardType = "coins",
        rewards = SpinWheelConfig.CoinRewards,
        angleRanges = {
            { startAngle = 32.3, endAngle = 89.7 },
        },
    },
    {
        id = "Orange",
        colorName = "Orange",
        weight = 22,
        label = "SHARDS",
        rewardType = "scrap",
        rewards = SpinWheelConfig.ScrapRewards,
        angleRanges = {
            { startAngle = 91.4, endAngle = 150 },
        },
    },
    {
        id = "Blue",
        colorName = "Blue",
        weight = 35,
        label = "HEALTH POTION",
        rewardType = "health_potions",
        rewards = SpinWheelConfig.HealthPotionRewards,
        angleRanges = {
            { startAngle = 151.2, endAngle = -149.8 },
        },
    },
    {
        id = "Yellow",
        colorName = "Yellow",
        weight = 7,
        label = "GIANT CRATE",
        rewardType = "crate",
        crateId = "WheelGiantCrate",
        angleRanges = {
            { startAngle = -148.2, endAngle = -90.2 },
        },
    },
    {
        id = "Purple",
        colorName = "Purple",
        weight = 10,
        label = "1 KEY",
        rewardType = "keys",
        amount = 1,
        angleRanges = {
            { startAngle = -88.4, endAngle = -30.4 },
        },
    },
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
    ReadyHeader = "FREE SPIN READY!",
    ReadyBody = "PRESS E TO SPIN",
    CooldownHeader = "NEXT FREE SPIN",
    PromptAction = "Press E to Spin",
    PromptObjectPrefix = "Wheel Spins:",
    PurchaseHeader = "BUY WHEEL SPINS",
    PurchaseBody = "You're out of spins. Pick a pack below.",
    PurchaseCancel = "Not now",
    PurchasePending = "Opening purchase...",
    PurchaseSuccess = "Wheel Spins added!",
}

SpinWheelConfig.RewardSectors = SpinWheelConfig.RewardSlices

local tickBoundaryAngles = {}
do
    local seen = {}
    for _, slice in ipairs(SpinWheelConfig.RewardSlices) do
        for _, range in ipairs(slice.angleRanges or {}) do
            local spinRange = toSpinRange(range)
            local startAngle = normalizeAnglePositive(spinRange.startAngle)
            local endAngle = normalizeAnglePositive(spinRange.endAngle)
            local startKey = string.format("%.3f", startAngle)
            local endKey = string.format("%.3f", endAngle)
            if not seen[startKey] then
                seen[startKey] = true
                table.insert(tickBoundaryAngles, startAngle)
            end
            if not seen[endKey] then
                seen[endKey] = true
                table.insert(tickBoundaryAngles, endAngle)
            end
        end
    end
    table.sort(tickBoundaryAngles)
end

function SpinWheelConfig.NormalizeAngle(angleDegrees)
    return normalizeAngle(angleDegrees)
end

function SpinWheelConfig.NormalizeAnglePositive(angleDegrees)
    return normalizeAnglePositive(angleDegrees)
end

function SpinWheelConfig.IsAngleInRange(angleDegrees, range)
    return isAngleInRange(angleDegrees, range)
end

function SpinWheelConfig.GetRewardSlice(identifier)
    if type(identifier) == "number" then
        return SpinWheelConfig.RewardSlices[identifier]
    end
    if type(identifier) ~= "string" then
        return nil
    end
    for _, slice in ipairs(SpinWheelConfig.RewardSlices) do
        if slice.id == identifier then
            return slice
        end
    end
    return nil
end

function SpinWheelConfig.GetRewardSliceCount()
    return #SpinWheelConfig.RewardSlices
end

function SpinWheelConfig.IsAngleInSlice(angleDegrees, slice)
    if type(slice) ~= "table" then
        return false
    end
    for _, range in ipairs(slice.angleRanges or {}) do
        local spinRange = toSpinRange(range)
        if spinRange and isAngleInRange(angleDegrees, spinRange) then
            return true
        end
    end
    return false
end

function SpinWheelConfig.RollLandingAngle(slice, randomSource, paddingDegrees)
    if type(slice) ~= "table" then
        return nil
    end

    local padding = math.max(0, tonumber(paddingDegrees) or SpinWheelConfig.LandingPaddingDegrees or 0)
    local weightedRanges = {}
    for _, range in ipairs(slice.angleRanges or {}) do
        local spinRange = toSpinRange(range)
        local width = spinRange and rangeWidth(spinRange) or 0
        local usableWidth = math.max(0, width - (padding * 2))
        table.insert(weightedRanges, {
            range = spinRange,
            weight = usableWidth > 0 and usableWidth or width,
        })
    end

    if #weightedRanges == 0 then
        return nil
    end

    local pickedRange = pickWeightedEntry(weightedRanges, randomSource)
    local range = pickedRange and pickedRange.range or weightedRanges[1].range
    local width = rangeWidth(range)
    if width <= (padding * 2) then
        return rangeMidpoint(range)
    end

    local startAngle = normalizeAnglePositive(range.startAngle) + padding
    local endAngle = normalizeAnglePositive(range.startAngle) + width - padding
    local roll
    if randomSource and randomSource.NextNumber then
        roll = randomSource:NextNumber(startAngle, endAngle)
    else
        roll = startAngle + ((endAngle - startAngle) * math.random())
    end
    return normalizeAngle(roll)
end

function SpinWheelConfig.RollWeightedReward(entries, randomSource)
    return pickWeightedEntry(entries, randomSource)
end

function SpinWheelConfig.GetTickBoundaryAngles()
    return copyArray(tickBoundaryAngles)
end

function SpinWheelConfig.VisualAngleToSpinAngle(angleDegrees)
    return visualAngleToSpinAngle(angleDegrees)
end

function SpinWheelConfig.GetSpinPack(index)
    return SpinWheelConfig.SpinPacks[index]
end

function SpinWheelConfig.GetSectorCount()
    return SpinWheelConfig.GetRewardSliceCount()
end

function SpinWheelConfig.GetSectorAngle()
    return 360 / math.max(1, SpinWheelConfig.GetSectorCount())
end

function SpinWheelConfig.GetRewardSector(index)
    return SpinWheelConfig.GetRewardSlice(index)
end

function SpinWheelConfig.GetFinalTickMuteAngle()
    return SpinWheelConfig.FinalTickMuteAngle
end

return SpinWheelConfig