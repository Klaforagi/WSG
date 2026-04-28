--------------------------------------------------------------------------------
-- EnchantTextStyler.lua
-- ReplicatedStorage/Modules/EnchantTextStyler.lua
--
-- Applies a premium animated shimmer/color-sweep effect to enchant name
-- TextLabels.  Manages its own UIGradient child and looping TweenService
-- animation.  Safe to call on the same label repeatedly — old effects are
-- cancelled and cleaned up automatically.
--
-- USAGE:
--   local EnchantTextStyler = require(ReplicatedStorage.Modules.EnchantTextStyler)
--   EnchantTextStyler.Apply(label, "Fiery")      -- set + animate enchant
--   EnchantTextStyler.Apply(label, nil)             -- clear enchant, hide text
--   EnchantTextStyler.ApplySize(label, "King", "100%") -- set + animate size tier
--------------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local EnchantTextStyler = {}

--------------------------------------------------------------------------------
-- Per-enchant shimmer gradient: dark base edges → bright highlight center.
-- The UIGradient Rotation is tweened 0→360 so the bright band sweeps
-- diagonally across the text in a seamless loop (~2 s per revolution).
--------------------------------------------------------------------------------
local SHIMMER_CONFIGS = {
    Fiery = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(215,  80,  15)),  -- warm orange, readable
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(248, 140,  35)),  -- bright orange
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 248, 120)),  -- yellow-white highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(248, 140,  35)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(215,  80,  15)),
        }),
    },
    Shock = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(195, 155,  10)),  -- golden yellow, readable
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(235, 205,  40)),  -- bright yellow
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 255, 185)),  -- near-white yellow highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(235, 205,  40)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(195, 155,  10)),
        }),
    },
    Icy = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(100, 190, 235)),  -- readable sky blue
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(160, 220, 255)),  -- bright ice blue
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(225, 250, 255)),  -- near-white highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(160, 220, 255)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(100, 190, 235)),
        }),
    },
    Toxic = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB( 55, 190,  40)),  -- readable bright green
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(110, 230,  60)),  -- lime
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(200, 255,  90)),  -- yellow-green highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(110, 230,  60)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB( 55, 190,  40)),
        }),
    },
    Lifesteal = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(180,  35,  35)),  -- readable crimson
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(225,  65,  65)),  -- bright red
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 130, 130)),  -- light red highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(225,  65,  65)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(180,  35,  35)),
        }),
    },
    Void = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(130,  55, 205)),  -- readable purple
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(185, 105, 240)),  -- bright violet
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 185, 255)),  -- pink-white highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(185, 105, 240)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(130,  55, 205)),
        }),
    },
}

--------------------------------------------------------------------------------
-- Per-size-tier shimmer gradients.
-- Normal gets no shimmer (just plain gray text).
-- Tiny / Large = bronze, Giant = silver, King = gold.
--------------------------------------------------------------------------------
local SIZE_SHIMMER_CONFIGS = {
    Tiny = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(150,  90,  35)),  -- dark bronze
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(200, 130,  55)),  -- bronze
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(240, 195, 110)),  -- bright bronze highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(200, 130,  55)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(150,  90,  35)),
        }),
    },
    Large = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(150,  90,  35)),  -- dark bronze
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(200, 130,  55)),  -- bronze
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(240, 195, 110)),  -- bright bronze highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(200, 130,  55)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(150,  90,  35)),
        }),
    },
    Giant = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(155, 165, 175)),  -- dark silver
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(195, 205, 215)),  -- silver
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(240, 245, 250)),  -- near-white silver highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(195, 205, 215)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(155, 165, 175)),
        }),
    },
    King = {
        colorSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(185, 130,  10)),  -- dark gold
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(230, 185,  40)),  -- gold
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 240, 130)),  -- bright gold highlight
            ColorSequenceKeypoint.new(0.65, Color3.fromRGB(230, 185,  40)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(185, 130,  10)),
        }),
    },
}

-- Fallback flat color for Normal (no shimmer)
local SIZE_NORMAL_COLOR = Color3.fromRGB(160, 160, 170)

local activeEffects = setmetatable({}, {__mode = "k"})

-- TweenInfo reused for every shimmer: linear, infinite, ~2.8 s per left-to-right pass.
-- End offset is 1.2 so the bright band fully exits the right edge before the loop snaps
-- back to -1 (both extremes are off-screen so the reset is invisible).
local SHIMMER_TWEEN_INFO = TweenInfo.new(2.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0)

--------------------------------------------------------------------------------
-- Internal: cancel + destroy any active effect on `label`.
--------------------------------------------------------------------------------
local function stopEffect(label)
    local effect = activeEffects[label]
    if not effect then return end
    if effect.tween then
        pcall(function() effect.tween:Cancel() end)
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
-- EnchantTextStyler.Apply(label, enchantName)
--
-- label       : TextLabel instance to style
-- enchantName : string enchant key ("Fiery", "Void", …) or nil/"None"/""
--               to clear the effect and hide text.
--------------------------------------------------------------------------------
function EnchantTextStyler.Apply(label, enchantName)
    if not label or not label:IsA("TextLabel") then return end

    -- Stop + remove any previous effect on this label.
    stopEffect(label)

    -- Also destroy any abandoned UIGradient (e.g. from first-time setup).
    local orphan = label:FindFirstChildWhichIsA("UIGradient")
    if orphan then orphan:Destroy() end
    local orphanStroke = label:FindFirstChildWhichIsA("UIStroke")
    if orphanStroke then orphanStroke:Destroy() end

    -- Normalise the enchant name: strip ✨ and whitespace just in case.
    local cleanName = nil
    if enchantName and tostring(enchantName) ~= "" and enchantName ~= "None" then
        cleanName = tostring(enchantName):gsub("✨", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if cleanName == "" then cleanName = nil end
    end

    -- No enchant → clear text and bail.
    if not cleanName then
        label.Text       = ""
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        return
    end

    -- Apply font + base text.
    label.Font       = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255) -- gradient overrides
    label.Text       = cleanName

    -- Look up shimmer config; fall back to plain white if not found.
    local config = SHIMMER_CONFIGS[cleanName]
    if not config then return end

    -- Build and attach UIGradient.
    -- Rotation = 0 keeps the gradient horizontal (left-to-right).
    -- Offset.X starts at -1 so the bright centre band is fully off the left edge.
    -- End at 0.65 rather than 1: the bright band has already exited the right edge
    -- by ~offset 0.5, so capping at 0.65 cuts the dead time on the right while
    -- the snap back to -1 stays invisible (band still off-screen).
    local gradient    = Instance.new("UIGradient")
    gradient.Color    = config.colorSeq
    gradient.Rotation = 0
    gradient.Offset   = Vector2.new(-1, 0)
    gradient.Parent   = label

    -- Tween the X offset left→right and instantly snap back for a clean loop.
    local tween = TweenService:Create(gradient, SHIMMER_TWEEN_INFO, {Offset = Vector2.new(1.2, 0)})
    tween:Play()

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.2
    stroke.Parent = label

    activeEffects[label] = {tween = tween, gradient = gradient, stroke = stroke}

    -- Auto-cleanup when the label is destroyed so the tween never orphans.
    label.Destroying:Connect(function()
        stopEffect(label)
    end)
end

--------------------------------------------------------------------------------
-- EnchantTextStyler.ApplySize(label, tierName, displayText)
--
-- label       : TextLabel instance to style
-- tierName    : "Normal" | "Tiny" | "Large" | "Giant" | "King"
-- displayText : the string to put in the label (e.g. "King  100%").
--               If nil the label text is left unchanged.
--------------------------------------------------------------------------------
function EnchantTextStyler.ApplySize(label, tierName, displayText)
    if not label or not label:IsA("TextLabel") then return end

    stopEffect(label)
    local orphan = label:FindFirstChildWhichIsA("UIGradient")
    if orphan then orphan:Destroy() end
    local orphanStroke = label:FindFirstChildWhichIsA("UIStroke")
    if orphanStroke then orphanStroke:Destroy() end

    label.Font = Enum.Font.GothamBold
    if displayText ~= nil then label.Text = tostring(displayText) end

    local config = SIZE_SHIMMER_CONFIGS[tierName]
    if not config then
        -- Normal: plain, no shimmer, but still gets the border
        label.TextColor3 = SIZE_NORMAL_COLOR
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.2
        stroke.Parent = label
        activeEffects[label] = {stroke = stroke}
        return
    end

    label.TextColor3 = Color3.fromRGB(255, 255, 255) -- gradient overrides

    local gradient    = Instance.new("UIGradient")
    gradient.Color    = config.colorSeq
    gradient.Rotation = 0
    gradient.Offset   = Vector2.new(-1, 0)
    gradient.Parent   = label

    local tween = TweenService:Create(gradient, SHIMMER_TWEEN_INFO, {Offset = Vector2.new(1.2, 0)})
    tween:Play()

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.2
    stroke.Parent = label

    activeEffects[label] = {tween = tween, gradient = gradient, stroke = stroke}

    label.Destroying:Connect(function()
        stopEffect(label)
    end)
end

--------------------------------------------------------------------------------
-- EnchantTextStyler.Clear(label)
--
-- Convenience alias: removes the shimmer effect and clears the label text.
--------------------------------------------------------------------------------
function EnchantTextStyler.Clear(label)
    EnchantTextStyler.Apply(label, nil)
end

return EnchantTextStyler
