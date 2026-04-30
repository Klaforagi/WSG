--------------------------------------------------------------------------------
-- EnchantTextStyler.lua
-- ReplicatedStorage/Modules/EnchantTextStyler.lua
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local EnchantTextStyler = {}

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
local SHIMMER_DURATION     = 6.0
local SHIMMER_SECOND_DELAY = SHIMMER_DURATION / 2
local SHIMMER_START_OFFSET = -1
local SHIMMER_END_OFFSET   =  1
local SHIMMER_BAND_WIDTH   =  0.08

-- Transparency mask: fully transparent except for a narrow opaque band at center.
-- Offset sweeps from -1 (band off-screen left) to +1 (band off-screen right),
-- so the TweenService RepeatCount=-1 snap is invisible at both endpoints.
local BAND_TRANSPARENCY = NumberSequence.new({
    NumberSequenceKeypoint.new(0.00, 1),
    NumberSequenceKeypoint.new(0.50 - SHIMMER_BAND_WIDTH, 1),
    NumberSequenceKeypoint.new(0.50, 0),
    NumberSequenceKeypoint.new(0.50 + SHIMMER_BAND_WIDTH, 1),
    NumberSequenceKeypoint.new(1.00, 1),
})

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
-- Creates a transparent overlay TextLabel parented to label.Parent.
-- Its UIGradient.Transparency hides all text except where the narrow band is.
-- The base label shows baseColor; the overlay shows brightColor only at the band.
--------------------------------------------------------------------------------
local function createOverlay(label, brightColor)
    local overlay                  = Instance.new("TextLabel")
    overlay.Size                   = label.Size
    overlay.Position               = label.Position
    overlay.AnchorPoint            = label.AnchorPoint
    overlay.Font                   = label.Font
    overlay.Text                   = label.Text
    overlay.TextSize               = label.TextSize
    overlay.TextScaled             = label.TextScaled
    overlay.TextXAlignment         = label.TextXAlignment
    overlay.TextYAlignment         = label.TextYAlignment
    overlay.ZIndex                 = label.ZIndex + 1
    overlay.BackgroundTransparency = 1
    overlay.TextColor3             = brightColor
    overlay.TextTransparency       = 0
    overlay.Parent                 = label.Parent

    local gradient        = Instance.new("UIGradient")
    gradient.Transparency = BAND_TRANSPARENCY
    gradient.Offset       = Vector2.new(SHIMMER_START_OFFSET, 0)
    gradient.Parent       = overlay

    return overlay, gradient
end

local function startTween(gradient)
    local tween = TweenService:Create(
        gradient,
        TweenInfo.new(SHIMMER_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
        { Offset = Vector2.new(SHIMMER_END_OFFSET, 0) }
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
    if effect.delayThread then
        pcall(task.cancel, effect.delayThread)
    end
    for _, tween in ipairs(effect.tweens or {}) do
        pcall(function() tween:Cancel() end)
    end
    for _, overlay in ipairs(effect.overlays or {}) do
        pcall(function()
            if overlay and overlay.Parent then overlay:Destroy() end
        end)
    end
    if effect.stroke and effect.stroke.Parent then
        pcall(function() effect.stroke:Destroy() end)
    end
    activeEffects[label] = nil
end

--------------------------------------------------------------------------------
-- Applies the shimmer: base color on label + two transparent overlay bands.
-- The second band is delayed by SHIMMER_SECOND_DELAY so the two bands are
-- always half a cycle apart.
--------------------------------------------------------------------------------
local function applyShimmer(label, baseColor, brightColor)
    for _, child in ipairs(label:GetChildren()) do
        if child:IsA("UIGradient") or child:IsA("UIStroke") then child:Destroy() end
    end

    label.TextColor3 = baseColor

    local stroke        = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(0, 0, 0)
    stroke.Thickness    = 1.5
    stroke.Transparency = 0.2
    stroke.Parent       = label

    local overlay1, gradient1 = createOverlay(label, brightColor)
    local tween1 = startTween(gradient1)

    local overlay2, gradient2 = createOverlay(label, brightColor)

    local effect = {
        overlays    = {overlay1, overlay2},
        tweens      = {tween1},
        stroke      = stroke,
        delayThread = nil,
    }
    activeEffects[label] = effect

    effect.delayThread = task.delay(SHIMMER_SECOND_DELAY, function()
        local current = activeEffects[label]
        if current ~= effect then return end
        gradient2.Offset = Vector2.new(SHIMMER_START_OFFSET, 0)
        local tween2 = startTween(gradient2)
        effect.tweens[2] = tween2
        effect.delayThread = nil
    end)

    label.Destroying:Connect(function()
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
