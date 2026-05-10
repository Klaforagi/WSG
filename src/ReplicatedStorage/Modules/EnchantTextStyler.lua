--------------------------------------------------------------------------------
-- EnchantTextStyler.lua
-- ReplicatedStorage/Modules/EnchantTextStyler.lua
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local EnchantTextStyler = {}

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local SHIMMER_BAND_CENTER  =  0.50
local SHIMMER_BAND_HALF_PX =  2.25
local SHIMMER_EDGE_HALF_PX =  1.00
local SHIMMER_PADDING_PX   =  5.50
local SHIMMER_PIXELS_PER_SECOND = 23.5
local SHIMMER_MIN_DURATION = 1.2
local SHIMMER_MAX_DURATION = 4.0

local SHIMMER_CONFIGS = {
    Fiery     = { baseColor = Color3.fromRGB(215,  80,  15),  brightColor = Color3.fromRGB(255, 248, 120) },
    Shock     = { baseColor = Color3.fromRGB(195, 155,  10),  brightColor = Color3.fromRGB(255, 255, 185) },
    Icy       = { baseColor = Color3.fromRGB(100, 190, 235),  brightColor = Color3.fromRGB(225, 250, 255) },
    Toxic     = { baseColor = Color3.fromRGB( 55, 190,  40),  brightColor = Color3.fromRGB(200, 255,  90) },
    Lifesteal = { baseColor = Color3.fromRGB(180,  35,  35),  brightColor = Color3.fromRGB(255, 130, 130) },
    Void      = { baseColor = Color3.fromRGB(130,  55, 205),  brightColor = Color3.fromRGB(255, 185, 255) },
}

local SIZE_SHIMMER_CONFIGS = {
    Tiny  = { baseColor = Color3.fromRGB(150,  90,  35),  brightColor = Color3.fromRGB(240, 195, 110) },
    Large = { baseColor = Color3.fromRGB(150,  90,  35),  brightColor = Color3.fromRGB(240, 195, 110) },
    Giant = { baseColor = Color3.fromRGB(155, 165, 175),  brightColor = Color3.fromRGB(240, 245, 250) },
    King  = { baseColor = Color3.fromRGB(185, 130,  10),  brightColor = Color3.fromRGB(255, 240, 130) },
}

local SIZE_NORMAL_COLOR = Color3.fromRGB(160, 160, 170)

local activeEffects = setmetatable({}, {__mode = "k"})

--------------------------------------------------------------------------------
-- Builds a color sequence with one narrow bright band.
-- The label keeps rendering normally; only the text color brightens as the band
-- pass over it, which avoids the glyph-shaped artifacts caused by text masking.
--------------------------------------------------------------------------------
local function getShimmerMetrics(label)
    local width = math.max(label.AbsoluteSize.X, 48)
    local bandHalf = math.max(SHIMMER_BAND_HALF_PX / width, 0.012)
    local edgeHalf = math.max(SHIMMER_EDGE_HALF_PX / width, 0.005)
    edgeHalf = math.min(edgeHalf, bandHalf - 0.002)
    if edgeHalf <= 0 then
        edgeHalf = bandHalf * 0.5
    end

    local padding = math.max(SHIMMER_PADDING_PX / width, 0.02)
    local startOffset = -(0.5 + bandHalf + padding)
    local endOffset = 0.5 + bandHalf + padding
    local duration = math.clamp(
        ((endOffset - startOffset) * width) / SHIMMER_PIXELS_PER_SECOND,
        SHIMMER_MIN_DURATION,
        SHIMMER_MAX_DURATION
    )

    return {
        bandHalf = bandHalf,
        edgeHalf = edgeHalf,
        startOffset = startOffset,
        endOffset = endOffset,
        duration = duration,
    }
end

local function createShimmerSequence(baseColor, brightColor, shimmerMetrics)
    local bandStart = SHIMMER_BAND_CENTER - shimmerMetrics.bandHalf
    local bandPeak1 = SHIMMER_BAND_CENTER - shimmerMetrics.edgeHalf
    local bandPeak2 = SHIMMER_BAND_CENTER + shimmerMetrics.edgeHalf
    local bandEnd = SHIMMER_BAND_CENTER + shimmerMetrics.bandHalf

    return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, baseColor),
        ColorSequenceKeypoint.new(bandStart, baseColor),
        ColorSequenceKeypoint.new(bandPeak1, brightColor),
        ColorSequenceKeypoint.new(bandPeak2, brightColor),
        ColorSequenceKeypoint.new(bandEnd, baseColor),
        ColorSequenceKeypoint.new(1.00, baseColor),
    })
end

local function createGradient(label, baseColor, brightColor, shimmerMetrics)
    local gradient = Instance.new("UIGradient")
    gradient.Offset = Vector2.new(shimmerMetrics.startOffset, 0)
    gradient.Color = createShimmerSequence(baseColor, brightColor, shimmerMetrics)
    gradient.Parent = label
    return gradient
end

local function startTween(gradient, shimmerMetrics)
    local tween = TweenService:Create(
        gradient,
        TweenInfo.new(shimmerMetrics.duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
        { Offset = Vector2.new(shimmerMetrics.endOffset, 0) }
    )
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Cancels and destroys all tracked resources for `label`.
--------------------------------------------------------------------------------
local function stopEffect(label)
    local effect = activeEffects[label]
    if not effect then return end
    for _, tween in ipairs(effect.tweens or {}) do
        pcall(function() tween:Cancel() end)
    end
    if effect.destroyConn then
        pcall(function() effect.destroyConn:Disconnect() end)
    end
    if effect.gradient and effect.gradient.Parent then
        pcall(function() effect.gradient:Destroy() end)
    end
    if effect.stroke and effect.stroke.Parent then
        pcall(function() effect.stroke:Destroy() end)
    end
    activeEffects[label] = nil
end

--------------------------------------------------------------------------------
-- Applies the shimmer with one animated UIGradient on the label itself.
--------------------------------------------------------------------------------
local function applyShimmer(label, baseColor, brightColor)
    for _, child in ipairs(label:GetChildren()) do
        if child:IsA("UIGradient") or child:IsA("UIStroke") then child:Destroy() end
    end

    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextTransparency = 0

    local stroke        = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(0, 0, 0)
    stroke.Thickness    = 1.5
    stroke.Transparency = 0.2
    stroke.Parent       = label

    local shimmerMetrics = getShimmerMetrics(label)
    local gradient = createGradient(label, baseColor, brightColor, shimmerMetrics)
    local tween = startTween(gradient, shimmerMetrics)

    local effect = {
        gradient = gradient,
        tweens = {tween},
        stroke = stroke,
        destroyConn = nil,
    }
    activeEffects[label] = effect

    effect.destroyConn = label.Destroying:Connect(function()
        stopEffect(label)
    end)
end

--------------------------------------------------------------------------------
-- EnchantTextStyler.Apply(label, enchantName)
--------------------------------------------------------------------------------
function EnchantTextStyler.Apply(label, enchantName)
    if not label or not label:IsA("TextLabel") then return end
    stopEffect(label)

    local cleanName
    if enchantName and tostring(enchantName) ~= "" and enchantName ~= "None" then
        cleanName = tostring(enchantName):gsub("✨", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if cleanName == "" then cleanName = nil end
    end

    if not cleanName then
        label.Text       = ""
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        return
    end

    label.Font       = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextTransparency = 0
    label.Text       = cleanName

    local config = SHIMMER_CONFIGS[cleanName]
    if not config then return end
    applyShimmer(label, config.baseColor, config.brightColor)
end

--------------------------------------------------------------------------------
-- EnchantTextStyler.ApplySize(label, tierName, displayText)
--------------------------------------------------------------------------------
function EnchantTextStyler.ApplySize(label, tierName, displayText)
    if not label or not label:IsA("TextLabel") then return end
    stopEffect(label)

    label.Font = Enum.Font.GothamBold
    if displayText ~= nil then label.Text = tostring(displayText) end

    local config = SIZE_SHIMMER_CONFIGS[tierName]
    if not config then
        -- Normal tier: plain color, no shimmer.
        for _, child in ipairs(label:GetChildren()) do
            if child:IsA("UIGradient") or child:IsA("UIStroke") then child:Destroy() end
        end
        label.TextColor3 = SIZE_NORMAL_COLOR
        label.TextTransparency = 0
        local stroke        = Instance.new("UIStroke")
        stroke.Color        = Color3.fromRGB(0, 0, 0)
        stroke.Thickness    = 1.5
        stroke.Transparency = 0.2
        stroke.Parent       = label
        activeEffects[label] = {stroke = stroke}
        return
    end

    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyShimmer(label, config.baseColor, config.brightColor)
end

--------------------------------------------------------------------------------
-- EnchantTextStyler.Clear(label)
--------------------------------------------------------------------------------
function EnchantTextStyler.Clear(label)
    EnchantTextStyler.Apply(label, nil)
end

return EnchantTextStyler
