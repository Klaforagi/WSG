--------------------------------------------------------------------------------
-- BuffBar.client.lua
-- Compact lower-right HUD for active events, healing, bandage, flags, and boosts.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local elapsed = 0
        while cam.ViewportSize.Y < 2 and elapsed < 3 do
            elapsed += task.wait()
        end
    end
end

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local function safeRequire(moduleName, timeout)
    local mod = ReplicatedStorage:WaitForChild(moduleName, timeout or 5)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            return result
        end
        warn("[BuffBar] Failed to require " .. moduleName .. ":", tostring(result))
    end
    return nil
end

local AssetCodes = safeRequire("AssetCodes", 5)
local BoostConfig = safeRequire("BoostConfig", 5)
local BuffBarConfig = safeRequire("BuffBarConfig", 5)
local BandageConfig = safeRequire("BandageConfig", 5) or { CastDuration = 6 }
local EventConfig = safeRequire("EventConfig", 5)

local UITheme
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local themeModule = sideUI and sideUI:FindFirstChild("UITheme")
    if themeModule and themeModule:IsA("ModuleScript") then
        UITheme = require(themeModule)
    end
end)

local COLORS = {
    navy = (UITheme and UITheme.NAVY) or Color3.fromRGB(12, 14, 28),
    navyLight = (UITheme and UITheme.NAVY_LIGHT) or Color3.fromRGB(22, 26, 48),
    iconBg = (UITheme and UITheme.ICON_BG) or Color3.fromRGB(16, 18, 30),
    gold = (UITheme and UITheme.GOLD) or Color3.fromRGB(255, 215, 80),
    goldDim = (UITheme and UITheme.GOLD_DIM) or Color3.fromRGB(180, 150, 50),
    white = (UITheme and UITheme.WHITE) or Color3.fromRGB(245, 245, 252),
    dim = (UITheme and UITheme.DIM_TEXT) or Color3.fromRGB(145, 150, 175),
    green = (UITheme and UITheme.GREEN_GLOW) or Color3.fromRGB(50, 230, 110),
}

local function colorFrom(value, fallback)
    if typeof(value) == "Color3" then
        return value
    end
    if type(value) == "table" then
        return Color3.fromRGB(tonumber(value[1]) or 255, tonumber(value[2]) or 255, tonumber(value[3]) or 255)
    end
    return fallback or COLORS.gold
end

local function cloneDefinition(def)
    local copy = {}
    if type(def) == "table" then
        for key, value in pairs(def) do
            copy[key] = value
        end
    end
    return copy
end

local function getStaticDef(id)
    if BuffBarConfig and type(BuffBarConfig.GetStaticEntry) == "function" then
        return BuffBarConfig.GetStaticEntry(id)
    end
    return nil
end

local warnedMissingIcons = {}

local function hasFallbackSymbol(def)
    if type(def) ~= "table" then
        return false
    end

    for _, key in ipairs({ "FallbackSymbol", "IconGlyph" }) do
        local value = def[key]
        if value ~= nil and tostring(value) ~= "" then
            return true
        end
    end
    return false
end

local function warnMissingIcon(def, reason)
    local key = tostring((def and (def.Id or def.IconKey or def.DisplayName)) or "unknown")
    if warnedMissingIcons[key] then
        return
    end
    warnedMissingIcons[key] = true
    warn("[BuffBar] Missing icon for " .. tostring(def and (def.Id or def.DisplayName) or "unknown") .. " (" .. tostring(reason) .. "); using fallback.")
end

local function normalizeAssetId(assetId)
    if type(assetId) == "number" then
        return "rbxassetid://" .. tostring(assetId)
    end
    if type(assetId) ~= "string" then
        return nil
    end

    local trimmed = assetId:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    if trimmed:match("^%d+$") then
        return "rbxassetid://" .. trimmed
    end
    if trimmed:match("^rbxassetid://%d+$") or trimmed:match("^rbxasset://") then
        return trimmed
    end

    return nil
end

local function resolveAsset(def)
    if type(def) ~= "table" then
        return nil
    end

    local invalidDirectAsset = nil
    for _, key in ipairs({ "IconAssetId", "IconAsset", "Icon", "Image" }) do
        local value = def[key]
        local directAsset = normalizeAssetId(value)
        if directAsset then
            return directAsset
        elseif value ~= nil and tostring(value) ~= "" then
            invalidDirectAsset = key
        end
    end
    if invalidDirectAsset and not hasFallbackSymbol(def) then
        warnMissingIcon(def, "invalid " .. invalidDirectAsset)
    end

    if AssetCodes and type(AssetCodes.Get) == "function" and type(def.IconKey) == "string" then
        local ok, assetId = pcall(function()
            return AssetCodes.Get(def.IconKey)
        end)
        if ok then
            local normalizedAsset = normalizeAssetId(assetId)
            if normalizedAsset then
                return normalizedAsset
            end
            if not hasFallbackSymbol(def) then
                warnMissingIcon(def, "empty or invalid IconKey " .. tostring(def.IconKey))
            end
        else
            if not hasFallbackSymbol(def) then
                warnMissingIcon(def, "IconKey lookup failed " .. tostring(def.IconKey))
            end
        end
    end
    return nil
end

local function shouldShowTimer(def)
    if type(def) == "table" and def.ShowTimer == false then
        return false
    end
    return true
end

local function getFallbackGlyph(def)
    if type(def) ~= "table" then
        return "?"
    end
    return tostring(def.FallbackSymbol or def.IconGlyph or "?")
end

local function buildVisualKey(def)
    if type(def) ~= "table" then
        return ""
    end

    local color = colorFrom(def.AccentColor or def.IconColor, COLORS.gold)
    return table.concat({
        tostring(def.Id or ""),
        tostring(def.DisplayName or ""),
        tostring(def.Description or ""),
        tostring(def.IconShape or ""),
        tostring(def.IconAssetId or ""),
        tostring(def.IconAsset or ""),
        tostring(def.Icon or ""),
        tostring(def.Image or ""),
        tostring(def.IconKey or ""),
        tostring(def.IconGlyph or ""),
        tostring(def.FallbackSymbol or ""),
        tostring(def.IconTextMaxSize or ""),
        tostring(def.TintImage == true),
        tostring(shouldShowTimer(def)),
        tostring(color.R), tostring(color.G), tostring(color.B),
    }, "|")
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function nowFor(kind)
    if kind == "os" then
        return os.time()
    end
    return workspace:GetServerTimeNow()
end

for _, guiName in ipairs({ "BuffBarGui", "EventObjectiveTracker", "EventPopupGui" }) do
    local old = playerGui:FindFirstChild(guiName)
    if old then
        old:Destroy()
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuffBarGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 245
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local TOOLTIP_WIDTH = px(250)
local TOOLTIP_PADDING = px(10)
local TILE_SIZE = px(70)
local TILE_WIDTH = px(76)
local TIMER_HEIGHT = px(20)
local TILE_GAP = px(8)
local TOTAL_HEIGHT = TILE_SIZE + px(4) + TIMER_HEIGHT

local container = Instance.new("Frame")
container.Name = "BuffBarContainer"
container.AnchorPoint = Vector2.new(1, 1)
container.BackgroundTransparency = 1
container.Size = UDim2.new(1, -px(28), 0, TOTAL_HEIGHT)
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, TILE_GAP)
layout.Parent = container

local relayoutTiles
local activeTooltipEntryId = nil

local tooltip = Instance.new("Frame")
tooltip.Name = "BuffTooltip"
tooltip.AnchorPoint = Vector2.new(0, 1)
tooltip.BackgroundColor3 = COLORS.navy
tooltip.BackgroundTransparency = 0.03
tooltip.BorderSizePixel = 0
tooltip.Size = UDim2.new(0, TOOLTIP_WIDTH, 0, px(72))
tooltip.AutomaticSize = Enum.AutomaticSize.Y
tooltip.Visible = false
tooltip.ZIndex = 60
tooltip.Parent = screenGui

local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, px(8))
tooltipCorner.Parent = tooltip

local tooltipStroke = Instance.new("UIStroke")
tooltipStroke.Color = COLORS.goldDim
tooltipStroke.Thickness = 1.2
tooltipStroke.Transparency = 0.15
tooltipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
tooltipStroke.Parent = tooltip

local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingTop = UDim.new(0, TOOLTIP_PADDING)
tooltipPadding.PaddingBottom = UDim.new(0, TOOLTIP_PADDING)
tooltipPadding.PaddingLeft = UDim.new(0, TOOLTIP_PADDING)
tooltipPadding.PaddingRight = UDim.new(0, TOOLTIP_PADDING)
tooltipPadding.Parent = tooltip

local tooltipLayout = Instance.new("UIListLayout")
tooltipLayout.FillDirection = Enum.FillDirection.Vertical
tooltipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
tooltipLayout.VerticalAlignment = Enum.VerticalAlignment.Top
tooltipLayout.SortOrder = Enum.SortOrder.LayoutOrder
tooltipLayout.Padding = UDim.new(0, px(3))
tooltipLayout.Parent = tooltip

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Name = "Title"
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Size = UDim2.new(1, 0, 0, px(20))
tooltipTitle.Font = Enum.Font.GothamBold
tooltipTitle.Text = ""
tooltipTitle.TextColor3 = COLORS.gold
tooltipTitle.TextSize = math.max(13, px(15))
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.TextYAlignment = Enum.TextYAlignment.Center
tooltipTitle.TextTruncate = Enum.TextTruncate.AtEnd
tooltipTitle.ZIndex = tooltip.ZIndex + 1
tooltipTitle.LayoutOrder = 1
tooltipTitle.Parent = tooltip

local tooltipDescription = Instance.new("TextLabel")
tooltipDescription.Name = "Description"
tooltipDescription.BackgroundTransparency = 1
tooltipDescription.Size = UDim2.new(1, 0, 0, px(36))
tooltipDescription.AutomaticSize = Enum.AutomaticSize.Y
tooltipDescription.Font = Enum.Font.GothamMedium
tooltipDescription.Text = ""
tooltipDescription.TextColor3 = COLORS.white
tooltipDescription.TextSize = math.max(11, px(12))
tooltipDescription.TextWrapped = true
tooltipDescription.TextXAlignment = Enum.TextXAlignment.Left
tooltipDescription.TextYAlignment = Enum.TextYAlignment.Top
tooltipDescription.ZIndex = tooltip.ZIndex + 1
tooltipDescription.LayoutOrder = 2
tooltipDescription.Parent = tooltip

local function refreshTooltipLayout()
    TOOLTIP_WIDTH = px(250)
    TOOLTIP_PADDING = px(10)
    tooltip.Size = UDim2.new(0, TOOLTIP_WIDTH, 0, px(72))
    tooltipCorner.CornerRadius = UDim.new(0, px(8))
    tooltipStroke.Thickness = math.max(1, px(1))
    tooltipPadding.PaddingTop = UDim.new(0, TOOLTIP_PADDING)
    tooltipPadding.PaddingBottom = UDim.new(0, TOOLTIP_PADDING)
    tooltipPadding.PaddingLeft = UDim.new(0, TOOLTIP_PADDING)
    tooltipPadding.PaddingRight = UDim.new(0, TOOLTIP_PADDING)
    tooltipLayout.Padding = UDim.new(0, px(3))
    tooltipTitle.Size = UDim2.new(1, 0, 0, px(20))
    tooltipTitle.TextSize = math.max(13, px(15))
    tooltipDescription.Size = UDim2.new(1, 0, 0, px(36))
    tooltipDescription.TextSize = math.max(11, px(12))
end

local function applyLayout()
    refreshTooltipLayout()
    TILE_SIZE = px(70)
    TILE_WIDTH = px(76)
    TIMER_HEIGHT = px(20)
    TILE_GAP = px(8)
    TOTAL_HEIGHT = TILE_SIZE + px(4) + TIMER_HEIGHT

    local bottomOffset = UserInputService.TouchEnabled and px(48) or px(24)
    container.Position = UDim2.new(1, -px(14), 1, -bottomOffset)
    container.Size = UDim2.new(1, -px(28), 0, TOTAL_HEIGHT)
    layout.Padding = UDim.new(0, TILE_GAP)
    if relayoutTiles then
        relayoutTiles()
    end
end

applyLayout()

local cameraConn
local function bindCamera()
    if cameraConn then
        cameraConn:Disconnect()
        cameraConn = nil
    end
    local cam = workspace.CurrentCamera
    if cam then
        cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
    end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCamera()
    task.defer(applyLayout)
end)

local activeEntries = {}
local tileRefs = {}

local function getScreenSize()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

local function positionTooltip(entryId)
    local refs = entryId and tileRefs[entryId]
    local target = refs and (refs.iconFrame or refs.wrapper)
    if not target or not target.Parent or not tooltip.Visible then
        return
    end

    local screenSize = getScreenSize()
    local margin = px(8)
    local tooltipWidth = math.max(1, tooltip.AbsoluteSize.X > 0 and tooltip.AbsoluteSize.X or TOOLTIP_WIDTH)
    local tooltipHeight = math.max(1, tooltip.AbsoluteSize.Y > 0 and tooltip.AbsoluteSize.Y or px(72))
    local targetPos = target.AbsolutePosition
    local targetSize = target.AbsoluteSize

    local x = targetPos.X + (targetSize.X * 0.5) - (tooltipWidth * 0.5)
    x = math.clamp(x, margin, math.max(margin, screenSize.X - tooltipWidth - margin))

    local bottomY = targetPos.Y + px(10)
    if bottomY - tooltipHeight < margin then
        bottomY = targetPos.Y + targetSize.Y + px(6) + tooltipHeight
    end
    bottomY = math.clamp(bottomY, tooltipHeight + margin, math.max(tooltipHeight + margin, screenSize.Y - margin))

    tooltip.Position = UDim2.fromOffset(x, bottomY)
end

local function showTooltip(entryId)
    local entry = activeEntries[entryId]
    local refs = tileRefs[entryId]
    if not entry or not refs then
        return
    end

    local def = entry.def or {}
    local description = tostring(def.Description or "")
    activeTooltipEntryId = entryId
    tooltipTitle.Text = tostring(def.DisplayName or entry.id or "Status")
    tooltipTitle.TextColor3 = entry.accent or COLORS.gold
    tooltipStroke.Color = entry.accent or COLORS.goldDim
    tooltipDescription.Text = description
    tooltipDescription.Visible = description ~= ""
    tooltip.Visible = true
    tooltip.Parent = screenGui
    task.defer(positionTooltip, entryId)
end

local function hideTooltip(entryId)
    if activeTooltipEntryId ~= entryId then
        return
    end
    activeTooltipEntryId = nil
    tooltip.Visible = false
end

relayoutTiles = function()
    for _, refs in pairs(tileRefs) do
        if refs.wrapper then
            refs.wrapper.Size = UDim2.new(0, TILE_WIDTH, 0, TOTAL_HEIGHT)
        end
        if refs.iconFrame then
            refs.iconFrame.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
        end
        if refs.timerLabel then
            refs.timerLabel.Position = UDim2.new(0, 0, 0, TILE_SIZE + px(3))
            refs.timerLabel.Size = UDim2.new(1, 0, 0, TIMER_HEIGHT)
            refs.timerLabel.TextSize = math.max(11, px(14))
        end
        if refs.glyphConstraint then
            local entry = refs.entryId and activeEntries[refs.entryId]
            local def = entry and entry.def
            refs.glyphConstraint.MaxTextSize = px(tonumber(def and def.IconTextMaxSize) or refs.glyphMaxTextSize or 82)
        end
    end
    if activeTooltipEntryId then
        task.defer(positionTooltip, activeTooltipEntryId)
    end
end

local function updateTileTimer(id)
    local entry = activeEntries[id]
    local refs = tileRefs[id]
    if not entry or not refs then
        return false
    end

    if refs.timerLabel then
        refs.timerLabel.Visible = entry.showTimer ~= false
    end
    if entry.showTimer == false then
        return true
    end

    if entry.expiresAt then
        local remaining = entry.expiresAt - nowFor(entry.timeKind)
        if remaining <= 0 then
            return false
        end
        refs.timerLabel.Text = formatTime(remaining)
    elseif entry.fixedLabel then
        refs.timerLabel.Text = entry.fixedLabel or "ACTIVE"
    else
        refs.timerLabel.Visible = false
        return true
    end
    refs.timerLabel.TextColor3 = entry.accent
    return true
end

local function addSoftTextStroke(label)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = label
    return stroke
end

local function createPlusIcon(parent, accent)
    local plusV = Instance.new("Frame")
    plusV.Name = "PlusV"
    plusV.AnchorPoint = Vector2.new(0.5, 0.5)
    plusV.Position = UDim2.new(0.5, 0, 0.5, 0)
    plusV.Size = UDim2.new(0.24, 0, 0.74, 0)
    plusV.BackgroundColor3 = COLORS.white
    plusV.BorderSizePixel = 0
    plusV.ZIndex = parent.ZIndex + 1
    plusV.Parent = parent

    local cV = Instance.new("UICorner")
    cV.CornerRadius = UDim.new(0, px(3))
    cV.Parent = plusV

    local plusH = Instance.new("Frame")
    plusH.Name = "PlusH"
    plusH.AnchorPoint = Vector2.new(0.5, 0.5)
    plusH.Position = UDim2.new(0.5, 0, 0.5, 0)
    plusH.Size = UDim2.new(0.74, 0, 0.24, 0)
    plusH.BackgroundColor3 = COLORS.white
    plusH.BorderSizePixel = 0
    plusH.ZIndex = parent.ZIndex + 1
    plusH.Parent = parent

    local cH = Instance.new("UICorner")
    cH.CornerRadius = UDim.new(0, px(3))
    cH.Parent = plusH

    parent.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.68)
end

local function createFlagIcon(parent, accent)
    local group = Instance.new("Frame")
    group.Name = "FlagIcon"
    group.AnchorPoint = Vector2.new(0.5, 0.5)
    group.Position = UDim2.new(0.5, 0, 0.5, 0)
    group.Size = UDim2.new(0.72, 0, 0.72, 0)
    group.BackgroundTransparency = 1
    group.ZIndex = parent.ZIndex + 1
    group.Parent = parent

    local pole = Instance.new("Frame")
    pole.Name = "Pole"
    pole.AnchorPoint = Vector2.new(0.5, 0.5)
    pole.Position = UDim2.new(0.26, 0, 0.52, 0)
    pole.Size = UDim2.new(0.09, 0, 0.84, 0)
    pole.BackgroundColor3 = COLORS.white
    pole.BorderSizePixel = 0
    pole.ZIndex = group.ZIndex + 1
    pole.Parent = group

    local poleCorner = Instance.new("UICorner")
    poleCorner.CornerRadius = UDim.new(1, 0)
    poleCorner.Parent = pole

    local banner = Instance.new("Frame")
    banner.Name = "Banner"
    banner.AnchorPoint = Vector2.new(0, 0)
    banner.Position = UDim2.new(0.32, 0, 0.16, 0)
    banner.Size = UDim2.new(0.56, 0, 0.34, 0)
    banner.BackgroundColor3 = accent
    banner.BorderSizePixel = 0
    banner.ZIndex = group.ZIndex + 2
    banner.Parent = group

    local bannerCorner = Instance.new("UICorner")
    bannerCorner.CornerRadius = UDim.new(0, px(4))
    bannerCorner.Parent = banner

    local lowerFold = Instance.new("Frame")
    lowerFold.Name = "LowerFold"
    lowerFold.AnchorPoint = Vector2.new(0, 0)
    lowerFold.Position = UDim2.new(0.32, 0, 0.45, 0)
    lowerFold.Size = UDim2.new(0.42, 0, 0.22, 0)
    lowerFold.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.18)
    lowerFold.BorderSizePixel = 0
    lowerFold.ZIndex = group.ZIndex + 1
    lowerFold.Parent = group

    local foldCorner = Instance.new("UICorner")
    foldCorner.CornerRadius = UDim.new(0, px(4))
    foldCorner.Parent = lowerFold

    parent.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.72)
end

local function createGlyphIcon(parent, def, accent)
    local glyph = Instance.new("TextLabel")
    glyph.Name = "Glyph"
    glyph.AnchorPoint = Vector2.new(0.5, 0.5)
    glyph.Position = UDim2.new(0.5, 0, 0.5, 0)
    glyph.Size = UDim2.fromScale(0.92, 0.92)
    glyph.BackgroundTransparency = 1
    glyph.Font = Enum.Font.GothamBlack
    glyph.Text = getFallbackGlyph(def)
    glyph.TextColor3 = accent
    glyph.TextScaled = true
    glyph.TextSize = px(64)
    glyph.TextWrapped = false
    glyph.TextXAlignment = Enum.TextXAlignment.Center
    glyph.TextYAlignment = Enum.TextYAlignment.Center
    glyph.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    glyph.TextStrokeTransparency = 0.28
    glyph.ZIndex = parent.ZIndex + 1
    glyph.Parent = parent
    addSoftTextStroke(glyph)

    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = 18
    textConstraint.MaxTextSize = px(tonumber(def.IconTextMaxSize) or 82)
    textConstraint.Parent = glyph

    return glyph, textConstraint
end

local function createTile(entry)
    local def = entry.def
    local accent = entry.accent

    local wrapper = Instance.new("Frame")
    wrapper.Name = "BuffTile_" .. entry.id
    wrapper.BackgroundTransparency = 1
    wrapper.Size = UDim2.new(0, TILE_WIDTH, 0, TOTAL_HEIGHT)
    wrapper.LayoutOrder = entry.sortOrder
    wrapper.Parent = container

    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0)
    iconFrame.Position = UDim2.new(0.5, 0, 0, 0)
    iconFrame.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
    iconFrame.BackgroundColor3 = COLORS.iconBg
    iconFrame.BackgroundTransparency = 0.05
    iconFrame.BorderSizePixel = 0
    iconFrame.ClipsDescendants = true
    iconFrame.Active = true
    iconFrame.ZIndex = 2
    iconFrame.Parent = wrapper

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(8))
    corner.Parent = iconFrame

    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = 1
    aspect.DominantAxis = Enum.DominantAxis.Width
    aspect.Parent = iconFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = 1.6
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = iconFrame

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 32, 50)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 24)),
    })
    gradient.Parent = iconFrame

    local glyphConstraint = nil
    local glyphMaxTextSize = tonumber(def.IconTextMaxSize) or 82
    local assetId = resolveAsset(def)
    if def.IconShape == "plus" then
        createPlusIcon(iconFrame, accent)
    elseif def.IconShape == "flag" then
        createFlagIcon(iconFrame, accent)
    elseif assetId then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.Size = UDim2.fromScale(0.92, 0.92)
        icon.BackgroundTransparency = 1
        icon.Image = assetId
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ImageColor3 = def.TintImage == true and accent or Color3.new(1, 1, 1)
        icon.ZIndex = iconFrame.ZIndex + 1
        icon.Parent = iconFrame
    else
        local _, newGlyphConstraint = createGlyphIcon(iconFrame, def, accent)
        glyphConstraint = newGlyphConstraint
    end

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "Timer"
    timerLabel.BackgroundTransparency = 1
    timerLabel.Position = UDim2.new(0, 0, 0, TILE_SIZE + px(3))
    timerLabel.Size = UDim2.new(1, 0, 0, TIMER_HEIGHT)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Text = "--:--"
    timerLabel.TextSize = math.max(11, px(14))
    timerLabel.TextXAlignment = Enum.TextXAlignment.Center
    timerLabel.TextYAlignment = Enum.TextYAlignment.Center
    timerLabel.TextTruncate = Enum.TextTruncate.AtEnd
    timerLabel.TextColor3 = accent
    timerLabel.ZIndex = 2
    timerLabel.Parent = wrapper

    local timerStroke = Instance.new("UIStroke")
    timerStroke.Color = Color3.fromRGB(0, 0, 0)
    timerStroke.Thickness = 1
    timerStroke.Transparency = 0.15
    timerStroke.Parent = timerLabel

    local scale = Instance.new("UIScale")
    scale.Scale = 0.88
    scale.Parent = wrapper
    TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    tileRefs[entry.id] = {
        entryId = entry.id,
        wrapper = wrapper,
        iconFrame = iconFrame,
        timerLabel = timerLabel,
        stroke = stroke,
        scale = scale,
        glyphConstraint = glyphConstraint,
        glyphMaxTextSize = glyphMaxTextSize,
        visualKey = entry.visualKey,
    }

    iconFrame.MouseEnter:Connect(function()
        showTooltip(entry.id)
    end)
    iconFrame.MouseMoved:Connect(function()
        if activeTooltipEntryId == entry.id then
            positionTooltip(entry.id)
        end
    end)
    iconFrame.MouseLeave:Connect(function()
        hideTooltip(entry.id)
    end)
    iconFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            showTooltip(entry.id)
            task.delay(2.5, function()
                hideTooltip(entry.id)
            end)
        end
    end)
    updateTileTimer(entry.id)
end

local function removeEntry(id)
    activeEntries[id] = nil
    hideTooltip(id)
    local refs = tileRefs[id]
    tileRefs[id] = nil
    if refs and refs.wrapper then
        local wrapper = refs.wrapper
        if refs.scale then
            TweenService:Create(refs.scale, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.82 }):Play()
        end
        TweenService:Create(wrapper, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
        task.delay(0.11, function()
            if wrapper and wrapper.Parent then
                wrapper:Destroy()
            end
        end)
    end
end

local function upsertEntry(id, def, options)
    options = options or {}
    if not def then
        removeEntry(id)
        return
    end

    local expiresAt = tonumber(options.expiresAt)
    local timeKind = options.timeKind or "server"
    if expiresAt and expiresAt <= nowFor(timeKind) then
        removeEntry(id)
        return
    end

    local entry = activeEntries[id]
    local definition = cloneDefinition(def)
    local accent = colorFrom(definition.AccentColor or definition.IconColor, COLORS.gold)
    if not entry then
        entry = { id = id }
        activeEntries[id] = entry
    end

    entry.def = definition
    entry.kind = options.kind or definition.Kind
    entry.expiresAt = expiresAt
    entry.timeKind = timeKind
    entry.fixedLabel = options.fixedLabel
    entry.sortOrder = options.sortOrder or definition.SortOrder or 999
    entry.accent = accent
    entry.showTimer = options.showTimer
    if entry.showTimer == nil then
        entry.showTimer = shouldShowTimer(definition)
    end
    entry.visualKey = buildVisualKey(definition)

    if tileRefs[id] then
        local refs = tileRefs[id]
        if refs.visualKey ~= entry.visualKey then
            if refs.wrapper then
                refs.wrapper:Destroy()
            end
            tileRefs[id] = nil
            createTile(entry)
            if activeTooltipEntryId == id then
                showTooltip(id)
            end
        else
            refs.wrapper.LayoutOrder = entry.sortOrder
            if refs.stroke then
                refs.stroke.Color = accent
            end
            updateTileTimer(id)
            if activeTooltipEntryId == id then
                showTooltip(id)
            end
        end
    else
        createTile(entry)
    end
end

RunService.Heartbeat:Connect(function()
    local currentSecond = math.floor(workspace:GetServerTimeNow())
    if screenGui:GetAttribute("LastSecond") == currentSecond then
        return
    end
    screenGui:SetAttribute("LastSecond", currentSecond)

    for id in pairs(activeEntries) do
        if not updateTileTimer(id) then
            removeEntry(id)
        end
    end
end)

local function syncEvent(active, eventId, endTime)
    if not active then
        removeEntry("event")
        return
    end

    local expiresAt = tonumber(endTime) or tonumber(ReplicatedStorage:GetAttribute("EventEndTime")) or 0
    local def = getStaticDef("event") or { Id = "event", DisplayName = "Event", Description = "Meteor Shower active - collect shards for coins.", FallbackSymbol = "\u{2605}", IconGlyph = "\u{2605}", IconColor = {255, 215, 80}, AccentColor = {255, 215, 80}, IconTextMaxSize = 86, ShowTimer = true, SortOrder = 10 }
    local eventDef = EventConfig and EventConfig.EventDefs and EventConfig.EventDefs[eventId]
    if eventDef then
        def.DisplayName = eventDef.Name or def.DisplayName
        if eventId == "GoldRush" then
            def.Description = eventDef.Description or "Gold Rush active - collect scattered coins for rewards."
        else
            def.Description = eventDef.Description or def.Description
        end
        def.IconKey = eventDef.IconKey or def.IconKey
        def.IconAssetId = eventDef.IconAssetId or def.IconAssetId
        def.IconColor = eventDef.IconColor or def.IconColor
    end
    upsertEntry("event", def, { expiresAt = expiresAt, timeKind = "server" })
end

local function syncEventFromAttributes()
    syncEvent(
        ReplicatedStorage:GetAttribute("EventActive") == true,
        ReplicatedStorage:GetAttribute("ActiveEventId"),
        ReplicatedStorage:GetAttribute("EventEndTime")
    )
end

task.spawn(function()
    syncEventFromAttributes()
    local eventRemote = ReplicatedStorage:WaitForChild("EventStateChanged", 15)
    if eventRemote and eventRemote:IsA("RemoteEvent") then
        eventRemote.OnClientEvent:Connect(syncEvent)
    end
end)
ReplicatedStorage:GetAttributeChangedSignal("EventActive"):Connect(syncEventFromAttributes)
ReplicatedStorage:GetAttributeChangedSignal("ActiveEventId"):Connect(syncEventFromAttributes)
ReplicatedStorage:GetAttributeChangedSignal("EventEndTime"):Connect(syncEventFromAttributes)

local characterConnections = {}

local function clearCharacterConnections()
    for _, conn in ipairs(characterConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(characterConnections)
end

local function syncHutHeal(humanoid)
    if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("_hut_heal_active") ~= true then
        removeEntry("hut_heal")
        return
    end

    local endTime = tonumber(humanoid:GetAttribute("_hut_heal_end_time"))
    if not endTime or endTime <= 0 then
        endTime = workspace:GetServerTimeNow() + 8
    end
    upsertEntry("hut_heal", getStaticDef("hut_heal"), { expiresAt = endTime, timeKind = "server" })
end

local function syncBandage(character)
    if not character or character:GetAttribute("IsBandaging") ~= true then
        removeEntry("bandage")
        return
    end

    local endTime = tonumber(character:GetAttribute("BandageEndTime"))
    if not endTime or endTime <= 0 then
        endTime = workspace:GetServerTimeNow() + (tonumber(BandageConfig.CastDuration) or 6)
    end
    upsertEntry("bandage", getStaticDef("bandage"), { expiresAt = endTime, timeKind = "server" })
end

local function bindCharacter(character)
    clearCharacterConnections()
    removeEntry("hut_heal")
    removeEntry("bandage")

    if not character then
        return
    end

    table.insert(characterConnections, character:GetAttributeChangedSignal("IsBandaging"):Connect(function()
        syncBandage(character)
    end))
    table.insert(characterConnections, character:GetAttributeChangedSignal("BandageEndTime"):Connect(function()
        syncBandage(character)
    end))

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    if humanoid then
        table.insert(characterConnections, humanoid:GetAttributeChangedSignal("_hut_heal_active"):Connect(function()
            syncHutHeal(humanoid)
        end))
        table.insert(characterConnections, humanoid:GetAttributeChangedSignal("_hut_heal_end_time"):Connect(function()
            syncHutHeal(humanoid)
        end))
        table.insert(characterConnections, humanoid.Died:Connect(function()
            removeEntry("hut_heal")
            removeEntry("bandage")
        end))
        syncHutHeal(humanoid)
    end

    syncBandage(character)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
    task.defer(bindCharacter, player.Character)
end

task.spawn(function()
    local bandageStarted = ReplicatedStorage:WaitForChild("BandageStarted", 10)
    if bandageStarted and bandageStarted:IsA("RemoteEvent") then
        bandageStarted.OnClientEvent:Connect(function(endTime)
            local character = player.Character
            local expiresAt = tonumber(endTime)
            if not expiresAt or expiresAt <= 0 then
                expiresAt = character and tonumber(character:GetAttribute("BandageEndTime"))
            end
            if not expiresAt or expiresAt <= 0 then
                expiresAt = workspace:GetServerTimeNow() + (tonumber(BandageConfig.CastDuration) or 6)
            end
            upsertEntry("bandage", getStaticDef("bandage"), { expiresAt = expiresAt, timeKind = "server" })
            syncBandage(character)
        end)
    end

    local bandageEnded = ReplicatedStorage:WaitForChild("BandageEnded", 10)
    if bandageEnded and bandageEnded:IsA("RemoteEvent") then
        bandageEnded.OnClientEvent:Connect(function()
            removeEntry("bandage")
        end)
    end
end)

local function syncFlag()
    local flagTeam = player:GetAttribute("CarryingFlag")
    if not flagTeam then
        removeEntry("flag")
        return
    end

    local teamName = tostring(flagTeam)
    local def = getStaticDef(teamName == "Blue" and "flag_blue" or "flag_red")
    if not def then
        return
    end
    def.DisplayName = teamName .. " Flag"
    upsertEntry("flag", def, { showTimer = false, sortOrder = def.SortOrder or 40 })
end

player:GetAttributeChangedSignal("CarryingFlag"):Connect(syncFlag)
task.defer(syncFlag)

local function syncRevengeCurse()
    if player:GetAttribute("RevengeCurseActive") ~= true then
        removeEntry("revenge_curse")
        return
    end

    local expiresAt = tonumber(player:GetAttribute("RevengeCurseExpiresAt"))
    if not expiresAt or expiresAt <= workspace:GetServerTimeNow() then
        removeEntry("revenge_curse")
        return
    end

    upsertEntry("revenge_curse", getStaticDef("revenge_curse"), {
        kind = "debuff",
        expiresAt = expiresAt,
        timeKind = "server",
    })
end

player:GetAttributeChangedSignal("RevengeCurseActive"):Connect(syncRevengeCurse)
player:GetAttributeChangedSignal("RevengeCurseExpiresAt"):Connect(syncRevengeCurse)
task.defer(syncRevengeCurse)

local function applyBoostStates(states)
    if type(states) ~= "table" or not BoostConfig or not BuffBarConfig then
        return
    end

    local serverTime = tonumber(states._serverTime) or os.time()
    local delta = os.time() - serverTime
    local activeBoostIds = {}

    for _, def in ipairs(BoostConfig.Boosts or {}) do
        if def.Type == "Timed" then
            local state = states[def.Id]
            if state and state.active then
                local expiresAt = (tonumber(state.expiresAt) or 0) + delta
                if expiresAt > os.time() then
                    local boostDef = BuffBarConfig.FromBoostDef(def)
                    if boostDef then
                        activeBoostIds[boostDef.Id] = true
                        upsertEntry(boostDef.Id, boostDef, { kind = "boost", expiresAt = expiresAt, timeKind = "os" })
                    end
                end
            end
        end
    end

    for id, entry in pairs(activeEntries) do
        if entry.kind == "boost" and not activeBoostIds[id] then
            removeEntry(id)
        end
    end
end

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then
        return
    end

    local stateEvent = remotes:WaitForChild("BoostStateUpdated", 10)
    if stateEvent and stateEvent:IsA("RemoteEvent") then
        stateEvent.OnClientEvent:Connect(applyBoostStates)
    end

    local boostFolder = remotes:WaitForChild("Boosts", 5)
    local getStates = boostFolder and boostFolder:FindFirstChild("GetBoostStates")
    if getStates and getStates:IsA("RemoteFunction") then
        local ok, states = pcall(function()
            return getStates:InvokeServer()
        end)
        if ok then
            applyBoostStates(states)
        end
    end
end)