local MobSkinService = {}

local randomGenerator = Random.new()

local BODY_PART_NAMES = {
    Head = true,
    Torso = true,
    UpperTorso = true,
    LowerTorso = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}

local HEAD_DESCENDANT_PART_NAMES = {
    ["Left Ear"] = true,
    ["Right Ear"] = true,
    Nose = true,
}

local function clampColorChannel(channelValue)
    return math.clamp(channelValue, 0, 255)
end

local function getColorChannelOffset(variationAmount)
    return randomGenerator:NextInteger(-variationAmount, variationAmount)
end

local function color3ToRgb(color)
    return math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)
end

local function getPaletteBlendColor(colorPalette)
    local colorCount = #colorPalette
    if colorCount == 0 then
        return nil
    end

    if colorCount == 1 then
        return colorPalette[1]
    end

    local firstIndex = randomGenerator:NextInteger(1, colorCount)
    local secondIndex = randomGenerator:NextInteger(1, colorCount)

    if firstIndex == secondIndex then
        if secondIndex < colorCount then
            secondIndex = secondIndex + 1
        else
            secondIndex = secondIndex - 1
        end
    end

    local firstColor = colorPalette[firstIndex]
    local secondColor = colorPalette[secondIndex]
    local alpha = randomGenerator:NextNumber()

    return firstColor:Lerp(secondColor, alpha)
end

-- Returns one color per mob instance so all body parts stay matched.
function MobSkinService.getRandomizedColor(baseColor, variationAmount)
    if typeof(baseColor) ~= "Color3" then
        error("MobSkinService.getRandomizedColor expected baseColor to be a Color3")
    end

    local clampedVariation = math.max(0, math.floor(tonumber(variationAmount) or 0))
    local baseRed = math.floor(baseColor.R * 255 + 0.5)
    local baseGreen = math.floor(baseColor.G * 255 + 0.5)
    local baseBlue = math.floor(baseColor.B * 255 + 0.5)

    local randomizedRed = clampColorChannel(baseRed + getColorChannelOffset(clampedVariation))
    local randomizedGreen = clampColorChannel(baseGreen + getColorChannelOffset(clampedVariation))
    local randomizedBlue = clampColorChannel(baseBlue + getColorChannelOffset(clampedVariation))

    return Color3.fromRGB(randomizedRed, randomizedGreen, randomizedBlue)
end

-- Picks a color from the palette, including blended tones between entries,
-- then applies the same bounded RGB variation used by single-base colors.
function MobSkinService.getRandomizedPaletteColor(colorPalette, variationAmount)
    if type(colorPalette) ~= "table" or #colorPalette == 0 then
        error("MobSkinService.getRandomizedPaletteColor expected a non-empty color palette")
    end

    local paletteBaseColor = getPaletteBlendColor(colorPalette)
    if typeof(paletteBaseColor) ~= "Color3" then
        error("MobSkinService.getRandomizedPaletteColor expected palette entries to be Color3 values")
    end

    return MobSkinService.getRandomizedColor(paletteBaseColor, variationAmount)
end

-- Applies the same randomized skin tone to the main body parts only.
-- Accessories, armor, clothing, and weapons are ignored because this only
-- targets the standard character body part names for R6 and R15 rigs.
function MobSkinService.applyMobSkin(mobModel, colorSource, variationAmount)
    if not mobModel or not mobModel:IsA("Model") then
        return nil
    end

    local skinColor
    if typeof(colorSource) == "Color3" then
        skinColor = MobSkinService.getRandomizedColor(colorSource, variationAmount)
    elseif type(colorSource) == "table" and #colorSource > 0 then
        skinColor = MobSkinService.getRandomizedPaletteColor(colorSource, variationAmount)
    else
        return nil
    end

    for partName in pairs(BODY_PART_NAMES) do
        local bodyPart = mobModel:FindFirstChild(partName)
        if bodyPart and bodyPart:IsA("BasePart") then
            bodyPart.Color = skinColor
        end
    end

    local head = mobModel:FindFirstChild("Head")
    if head then
        for _, descendant in ipairs(head:GetDescendants()) do
            if descendant:IsA("BasePart") and HEAD_DESCENDANT_PART_NAMES[descendant.Name] then
                descendant.Color = skinColor
            end
        end
    end

    return skinColor
end

-- Example server-side usage:
-- local orcColor = MobSkinService.applyMobSkin(orcMob, {
--     Color3.fromRGB(161, 196, 140),
--     Color3.fromRGB(93, 102, 70),
--     Color3.fromRGB(117, 107, 57),
--     Color3.fromRGB(115, 115, 96),
-- }, 8)
-- local goblinColor = MobSkinService.applyMobSkin(goblinMob, {
--     Color3.fromRGB(161, 196, 140),
--     Color3.fromRGB(93, 102, 70),
--     Color3.fromRGB(117, 107, 57),
--     Color3.fromRGB(115, 115, 96),
-- }, 8)
-- local ogreColor = MobSkinService.applyMobSkin(ogreMob, {
--     Color3.fromRGB(211, 190, 150),
--     Color3.fromRGB(173, 144, 130),
--     Color3.fromRGB(136, 90, 81),
-- }, 8)

return MobSkinService