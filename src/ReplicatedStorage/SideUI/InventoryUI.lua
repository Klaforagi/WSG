--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Compact grid inventory with right-side details panel
--
-- Layout:
--   Left sidebar:   Melee · Ranged · Boosts · Skins · Effects · Emotes
--   Centre:         Scrollable weapon card grid (compact, rarity-coloured)
--   Right panel:    Selected weapon details + Equip button
--
-- Reusable helpers: getRarityColor, getRarityBgColor, classifyItem,
--   createWeaponCard, setSelectedItem, updateEquipButton, renderCategory
--------------------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)
local LeftPanelStyle = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LeftPanelStyle"))

local INVENTORY_GRID_COLUMNS = 5

-- ═══════════════════════════════════════════════════════════════════════════
-- Responsive pixel helper
-- ═══════════════════════════════════════════════════════════════════════════
local function getViewportSize()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize.X, cam.ViewportSize.Y
    end
    return 1920, 1080
end

local function getResponsiveViewportScale()
    local screenX, screenY = getViewportSize()
    local widthScale = screenX / 1920
    local heightScale = screenY / 1080
    return math.clamp(math.min(widthScale, heightScale), 0.38, 1.6)
end

local function px(base)
    return math.max(1, math.round(base * getResponsiveViewportScale()))
end

local function attachResponsiveRootScale(root)
    if not root then return end

    root:SetAttribute("InventoryInitialResponsiveScale", getResponsiveViewportScale())

    local rootScale = Instance.new("UIScale")
    rootScale.Name = "ResponsiveScale"
    rootScale.Scale = 1
    rootScale.Parent = root
end

local function updateResponsiveRootScale(root)
    if not root then return end

    local rootScale = root:FindFirstChild("ResponsiveScale")
    if not (rootScale and rootScale:IsA("UIScale")) then return end

    local initialResponsiveScale = tonumber(root:GetAttribute("InventoryInitialResponsiveScale")) or getResponsiveViewportScale()
    rootScale.Scale = getResponsiveViewportScale() / math.max(0.001, initialResponsiveScale)
end

local function bindViewportResize(trackConn, callback)
    if not (trackConn and callback) then return end

    local cameraViewportConn = nil

    local function attachCamera(camera)
        if cameraViewportConn then
            pcall(function() cameraViewportConn:Disconnect() end)
            cameraViewportConn = nil
        end
        if camera then
            cameraViewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
            trackConn(cameraViewportConn)
        end
    end

    trackConn(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        attachCamera(workspace.CurrentCamera)
        callback()
    end))

    attachCamera(workspace.CurrentCamera)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Palette (from shared UITheme)
-- ═══════════════════════════════════════════════════════════════════════════
local CARD_BG       = UITheme.CARD_BG
local CARD_EQUIPPED = UITheme.CARD_OWNED
local CARD_STROKE   = UITheme.CARD_STROKE
local ICON_BG       = UITheme.ICON_BG
local GOLD          = UITheme.GOLD
local WHITE         = UITheme.WHITE
local DIM_TEXT      = UITheme.DIM_TEXT
local BTN_BG        = UITheme.BTN_BG
local BTN_STROKE_C  = UITheme.BTN_STROKE
local GREEN_GLOW    = UITheme.GREEN_GLOW
local GREEN_BTN     = UITheme.GREEN_BTN or Color3.fromRGB(35, 190, 75)
local DISABLED_BG   = UITheme.DISABLED_BG
local SIDEBAR_BG    = UITheme.SIDEBAR_BG
local TAB_ACTIVE_BG = UITheme.TAB_ACTIVE
local RED_TEXT       = UITheme.RED_TEXT or Color3.fromRGB(255, 80, 80)

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- SALVAGE SYSTEM  – load SalvageConfig for client-side value preview
local SalvageConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("SalvageConfig")
    if mod and mod:IsA("ModuleScript") then
        SalvageConfig = require(mod)
    end
end)

local function getSalvageValueForItem(itemData)
    if not SalvageConfig or type(itemData) ~= "table" then
        return nil
    end

    if type(SalvageConfig.GetValueForItem) == "function" then
        return SalvageConfig.GetValueForItem(itemData)
    end

    if type(SalvageConfig.GetValueForRarity) == "function" then
        return SalvageConfig.GetValueForRarity(itemData.rarity)
    end

    return nil
end

local WeaponMasteryConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("WeaponMasteryConfig")
    if mod and mod:IsA("ModuleScript") then
        WeaponMasteryConfig = require(mod)
    end
end)

-- Crate config (used to infer weapon rarities for non-instance inventory items)
local CrateConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
    if mod and mod:IsA("ModuleScript") then
        CrateConfig = require(mod)
    end
end)

-- ENCHANT SYSTEM — single source of truth for all enchant/size text styling
local EnchantTextStyler
pcall(function()
    local mods = ReplicatedStorage:FindFirstChild("Modules")
    if mods then
        local m = mods:FindFirstChild("EnchantTextStyler")
        if m and m:IsA("ModuleScript") then
            EnchantTextStyler = require(m)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Rarity colour palette
-- ═══════════════════════════════════════════════════════════════════════════
local RARITY_COLORS = {
    Common    = Color3.fromRGB(150, 150, 155),
    Uncommon  = Color3.fromRGB(120, 200, 120),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(180, 60, 255),
    Legendary = Color3.fromRGB(255, 180, 30),
}
local RARITY_BG_COLORS = {
    Common    = Color3.fromRGB(42, 44, 55),
    Uncommon  = Color3.fromRGB(22, 48, 36),
    Rare      = Color3.fromRGB(22, 38, 68),
    Epic      = Color3.fromRGB(46, 22, 65),
    Legendary = Color3.fromRGB(58, 46, 18),
}
-- Vivid full-card backgrounds for weapon inventory cards (reference style)
local WEAPON_CARD_BG = {
    Common    = Color3.fromRGB(105, 110, 120),
    Uncommon  = Color3.fromRGB(56, 131, 49),
    Rare      = Color3.fromRGB(45, 90, 175),
    Epic      = Color3.fromRGB(114, 38, 176),
    Legendary = Color3.fromRGB(195, 150, 25),
}
local WEAPON_CARD_BORDER = {
    Common    = Color3.fromRGB(70, 75, 82),
    Uncommon  = Color3.fromRGB(60, 110, 80),
    Rare      = Color3.fromRGB(30, 62, 125),
    Epic      = Color3.fromRGB(70, 30, 90),
    Legendary = Color3.fromRGB(140, 108, 16),
}

local TextService = game:GetService("TextService")

local function shadeColor(c, factor)
    factor = factor or 0.6
    return Color3.new(math.clamp(c.R * factor, 0, 1), math.clamp(c.G * factor, 0, 1), math.clamp(c.B * factor, 0, 1))
end

local function mixColor(a, b, alpha)
    alpha = math.clamp(alpha or 0.5, 0, 1)
    return Color3.new(
        a.R + (b.R - a.R) * alpha,
        a.G + (b.G - a.G) * alpha,
        a.B + (b.B - a.B) * alpha
    )
end

local function brightenColor(c, amount)
    amount = amount or 0.06
    return Color3.new(
        math.clamp(c.R + amount, 0, 1),
        math.clamp(c.G + amount, 0, 1),
        math.clamp(c.B + amount, 0, 1)
    )
end

local function colorFromRGBArray(value)
    if type(value) == "table" and #value >= 3 then
        return Color3.fromRGB(value[1], value[2], value[3])
    end
    return nil
end

local function accentPanelColor(accentColor, strength)
    return mixColor(Color3.fromRGB(18, 20, 34), accentColor or GOLD, strength or 0.28)
end

local function addTextOutline(label, transparency, thickness)
    local outline = Instance.new("UIStroke", label)
    outline.Color = Color3.fromRGB(0, 0, 0)
    outline.Thickness = thickness or 1.4
    outline.Transparency = transparency or 0.18
    return outline
end

local function addCardSheen(parent, accentColor)
    local sheen = Instance.new("Frame", parent)
    sheen.Name = "CardSheen"
    sheen.BackgroundColor3 = brightenColor(accentColor or WHITE, 0.08)
    sheen.BackgroundTransparency = 0.78
    sheen.BorderSizePixel = 0
    sheen.Size = UDim2.new(1, 0, 0.36, 0)
    sheen.ZIndex = 1
    local corner = Instance.new("UICorner", sheen)
    corner.CornerRadius = UDim.new(0, px(10))
    return sheen
end

local function addCardAccentBar(parent, accentColor, name, anchorBottom)
    local bar = Instance.new("Frame", parent)
    bar.Name = name or "AccentBar"
    bar.BackgroundColor3 = accentColor or GOLD
    bar.BackgroundTransparency = 0.08
    bar.BorderSizePixel = 0
    bar.Size = UDim2.new(1, 0, 0, px(3))
    bar.ZIndex = 6
    if anchorBottom then
        bar.AnchorPoint = Vector2.new(0, 1)
        bar.Position = UDim2.new(0, 0, 1, 0)
    else
        bar.Position = UDim2.new(0, 0, 0, 0)
    end
    return bar
end

local function addIconWellHighlight(iconArea, accentColor)
    local highlight = Instance.new("Frame", iconArea)
    highlight.Name = "IconHighlight"
    highlight.BackgroundColor3 = brightenColor(accentColor or WHITE, 0.05)
    highlight.BackgroundTransparency = 0.72
    highlight.BorderSizePixel = 0
    highlight.Size = UDim2.new(1, 0, 0.35, 0)
    highlight.ZIndex = 1
    Instance.new("UICorner", highlight).CornerRadius = UDim.new(0, px(6))

    local stroke = Instance.new("UIStroke", iconArea)
    stroke.Color = accentColor or CARD_STROKE
    stroke.Thickness = 1
    stroke.Transparency = 0.48
    return highlight, stroke
end

local function setCardStroke(stroke, color, thickness, transparency)
    if not stroke then return end
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency
end

local MASTERY_ROMAN_FALLBACK = {
    [1] = "I",
    [2] = "II",
    [3] = "III",
    [4] = "IV",
    [5] = "V",
    [6] = "VI",
    [7] = "VII",
    [8] = "VIII",
    [9] = "IX",
    [10] = "X",
}

local function formatWholeNumber(value)
    local formatted = tostring(math.max(0, math.floor(tonumber(value) or 0)))
    while true do
        local updated, count = string.gsub(formatted, "^(%-?%d+)(%d%d%d)", "%1,%2")
        formatted = updated
        if count == 0 then
            break
        end
    end
    return formatted
end

local function formatMasteryXP(value)
    local rounded = math.max(0, math.round((tonumber(value) or 0) * 10) / 10)
    local whole = math.floor(rounded)
    local tenths = math.floor(((rounded - whole) * 10) + 0.5)
    if tenths <= 0 then
        return formatWholeNumber(whole)
    end
    return formatWholeNumber(whole) .. "." .. tostring(tenths)
end

local function getMasteryRoman(level, romanNumeral)
    if type(romanNumeral) == "string" and romanNumeral ~= "" then
        return romanNumeral
    end
    if WeaponMasteryConfig and WeaponMasteryConfig.GetRomanNumeral then
        return WeaponMasteryConfig.GetRomanNumeral(level)
    end
    local numericLevel = math.max(1, math.floor(tonumber(level) or 1))
    return MASTERY_ROMAN_FALLBACK[numericLevel] or tostring(numericLevel)
end

local function formatMasteryBonus(bonus)
    return string.format("+%.1f DMG", math.max(0, tonumber(bonus) or 0))
end

-- (SIZE_TIER_STYLES removed — EnchantTextStyler is the sole source of size-tier colors)

-- ═══════════════════════════════════════════════════════════════════════════
-- Tab definitions  (Melee & Ranged are separate; above Boosts/Skins/Effects/Emotes)
-- ═══════════════════════════════════════════════════════════════════════════
local TAB_DEFS = {
    { id = "melee",   icon = "\u{2694}",  label = "Melee",   order = 1 },
    { id = "ranged",  icon = "\u{1F3F9}", label = "Ranged",  order = 2 },
    { id = "boosts",  icon = "\u{26A1}",  label = "Potions", order = 3 },
    { id = "skins",   icon = "\u{2726}",  label = "Skins",   order = 4 },
    { id = "effects", icon = "\u{2738}",  label = "Effects", order = 5 },
    { id = "emotes",  icon = "\u{263A}",  label = "Emotes",  order = 6 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Tab icon helpers  (custom pixel-art icons for Skins & Effects)
-- ═══════════════════════════════════════════════════════════════════════════
local function markIconPart(part)
    part:SetAttribute("TabIconPart", true)
    return part
end

local function setTabIconTint(iconRoot, color)
    if not iconRoot then return end
    if iconRoot:GetAttribute("TabIconPart") then
        if iconRoot:IsA("Frame") then           iconRoot.BackgroundColor3 = color
        elseif iconRoot:IsA("TextLabel") then   iconRoot.TextColor3 = color
        elseif iconRoot:IsA("ImageLabel") then  iconRoot.ImageColor3 = color
        elseif iconRoot:IsA("UIStroke") then    iconRoot.Color = color end
    end
    for _, d in ipairs(iconRoot:GetDescendants()) do
        if d:GetAttribute("TabIconPart") then
            if d:IsA("Frame") then           d.BackgroundColor3 = color
            elseif d:IsA("TextLabel") then   d.TextColor3 = color
            elseif d:IsA("ImageLabel") then  d.ImageColor3 = color
            elseif d:IsA("UIStroke") then    d.Color = color end
        end
    end
end

local CUSTOM_TAB_ICON_COLORS = {
    skins   = { active = Color3.fromRGB(178, 146, 220), inactive = Color3.fromRGB(114, 99, 140) },
    effects = { active = Color3.fromRGB(214, 138, 206), inactive = Color3.fromRGB(136, 90, 131) },
}

local function getCustomTabIconColor(tabId, active)
    local palette = CUSTOM_TAB_ICON_COLORS[tabId]
    if not palette then return active and GOLD or DIM_TEXT end
    return active and palette.active or palette.inactive
end

local function buildCustomTabIcon(parentBtn, tabId)
    local root = Instance.new("Frame")
    root.Name = "IconCustom"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(0, px(26), 0, px(24))
    root.AnchorPoint = Vector2.new(0.5, 0)
    root.Position = UDim2.new(0.5, 0, 0, px(8))
    root.Parent = parentBtn

    if tabId == "skins" then
        local shoulders = markIconPart(Instance.new("Frame"))
        shoulders.BackgroundTransparency = 0; shoulders.BorderSizePixel = 0
        shoulders.Size = UDim2.new(0, px(18), 0, px(7))
        shoulders.Position = UDim2.new(0.5, 0, 0, px(14)); shoulders.AnchorPoint = Vector2.new(0.5, 0)
        shoulders.Parent = root
        Instance.new("UICorner", shoulders).CornerRadius = UDim.new(0, px(3))

        local torso = markIconPart(Instance.new("Frame"))
        torso.BackgroundTransparency = 0; torso.BorderSizePixel = 0
        torso.Size = UDim2.new(0, px(12), 0, px(8))
        torso.Position = UDim2.new(0.5, 0, 0, px(10)); torso.AnchorPoint = Vector2.new(0.5, 0)
        torso.Parent = root
        Instance.new("UICorner", torso).CornerRadius = UDim.new(0, px(3))

        local head = markIconPart(Instance.new("Frame"))
        head.BackgroundTransparency = 0; head.BorderSizePixel = 0
        head.Size = UDim2.new(0, px(8), 0, px(8))
        head.Position = UDim2.new(0.5, 0, 0, px(2)); head.AnchorPoint = Vector2.new(0.5, 0)
        head.Parent = root
        Instance.new("UICorner", head).CornerRadius = UDim.new(1, 0)

    elseif tabId == "effects" then
        local sparkleV = markIconPart(Instance.new("Frame"))
        sparkleV.BackgroundTransparency = 0; sparkleV.BorderSizePixel = 0
        sparkleV.Size = UDim2.new(0, px(3), 0, px(14))
        sparkleV.Position = UDim2.new(0.5, 0, 0, px(4)); sparkleV.AnchorPoint = Vector2.new(0.5, 0)
        sparkleV.Parent = root
        Instance.new("UICorner", sparkleV).CornerRadius = UDim.new(1, 0)

        local sparkleH = markIconPart(Instance.new("Frame"))
        sparkleH.BackgroundTransparency = 0; sparkleH.BorderSizePixel = 0
        sparkleH.Size = UDim2.new(0, px(14), 0, px(3))
        sparkleH.Position = UDim2.new(0.5, 0, 0, px(10)); sparkleH.AnchorPoint = Vector2.new(0.5, 0)
        sparkleH.Parent = root
        Instance.new("UICorner", sparkleH).CornerRadius = UDim.new(1, 0)

        local miniA = markIconPart(Instance.new("Frame"))
        miniA.BackgroundTransparency = 0; miniA.BorderSizePixel = 0
        miniA.Size = UDim2.new(0, px(2), 0, px(7)); miniA.Position = UDim2.new(0, px(4), 0, px(2))
        miniA.Parent = root
        Instance.new("UICorner", miniA).CornerRadius = UDim.new(1, 0)

        local miniB = markIconPart(Instance.new("Frame"))
        miniB.BackgroundTransparency = 0; miniB.BorderSizePixel = 0
        miniB.Size = UDim2.new(0, px(7), 0, px(2)); miniB.Position = UDim2.new(0, px(2), 0, px(4))
        miniB.Parent = root
        Instance.new("UICorner", miniB).CornerRadius = UDim.new(1, 0)

        local miniDot = markIconPart(Instance.new("Frame"))
        miniDot.BackgroundTransparency = 0; miniDot.BorderSizePixel = 0
        miniDot.Size = UDim2.new(0, px(3), 0, px(3)); miniDot.Position = UDim2.new(0, px(20), 0, px(3))
        miniDot.Parent = root
        Instance.new("UICorner", miniDot).CornerRadius = UDim.new(1, 0)
    end
    return root
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Toast notification
-- ═══════════════════════════════════════════════════════════════════════════
local function showToast(parentFrame, message, color, duration)
    local toast = Instance.new("TextLabel")
    toast.Name = "Toast"
    toast.BackgroundColor3 = Color3.fromRGB(18, 20, 36)
    toast.BackgroundTransparency = 0.08
    toast.Size = UDim2.new(0.85, 0, 0, px(40))
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, px(6))
    toast.Font = Enum.Font.GothamBold
    toast.TextSize = math.max(13, math.floor(px(14)))
    toast.TextColor3 = color or GOLD
    toast.Text = message
    toast.TextWrapped = true
    toast.ZIndex = 400
    toast.Parent = parentFrame

    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, px(10))
    local st = Instance.new("UIStroke", toast)
    st.Color = color or GOLD; st.Thickness = 1.2; st.Transparency = 0.35

    toast.BackgroundTransparency = 1; toast.TextTransparency = 1
    TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency = 0.15, TextTransparency = 0}):Play()

    task.delay(duration or 2.2, function()
        if toast and toast.Parent then
            local tw = TweenService:Create(toast, TweenInfo.new(0.25), {BackgroundTransparency = 1, TextTransparency = 1})
            tw:Play()
            tw.Completed:Connect(function() pcall(function() toast:Destroy() end) end)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Boost config helpers
-- ═══════════════════════════════════════════════════════════════════════════
local InventoryUI = {}

local ShopUIModule = nil
pcall(function() ShopUIModule = require(script.Parent.ShopUI) end)

local BoostConfig = nil
local PotionConfigGlobal = nil
local AssetCodesGlobal = nil
local ItemIconRegistryGlobal = nil
local boostRemotes = nil
local potionRemotes = nil

local function safeRequireBoostConfig()
    local mod = ReplicatedStorage:FindFirstChild("BoostConfig")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then return result end
    end
    return nil
end

local function safeRequirePotionConfig()
    local mod = ReplicatedStorage:FindFirstChild("PotionConfig")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then return result end
    end
    return nil
end

local function safeRequireAssetCodes()
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then return result end
    end
    return nil
end

local function safeRequireItemIconRegistry()
    local mod = ReplicatedStorage:FindFirstChild("ItemIconRegistry")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(function() return require(mod) end)
        if ok and type(result) == "table" then return result end
    end
    return nil
end

local function getItemIconData(def)
    ItemIconRegistryGlobal = ItemIconRegistryGlobal or safeRequireItemIconRegistry()
    if not ItemIconRegistryGlobal or type(ItemIconRegistryGlobal.Get) ~= "function" or type(def) ~= "table" then
        return nil
    end
    return ItemIconRegistryGlobal.Get(def.IconKey) or ItemIconRegistryGlobal.Get(def.Id)
end

local function getShardCurrencyImage()
    AssetCodesGlobal = AssetCodesGlobal or safeRequireAssetCodes()
    if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" then
        local image = AssetCodesGlobal.Get("Shards") or AssetCodesGlobal.Get("Shard")
        if type(image) == "string" and #image > 0 then return image end
    end
    return nil
end

local SHARD_UI_ACCENT = Color3.fromRGB(255, 158, 74)
local SHARD_UI_BG = Color3.fromRGB(74, 42, 18)
local SHARD_UI_DIM = Color3.fromRGB(190, 118, 52)
local SHARD_UI_FEEDBACK_BG = Color3.fromRGB(58, 33, 14)
local SHARD_UI_OVERLAY_BG = Color3.fromRGB(22, 12, 4)
local SHARD_UI_CONFIRM_BG = Color3.fromRGB(48, 29, 14)

local function createShardRewardRow(parent, name, size, anchorPoint, position, textSize, shardImage, zIndex, pxFn)
    local row = Instance.new("Frame")
    row.Name = name
    row.BackgroundTransparency = 1
    row.Size = size
    row.AnchorPoint = anchorPoint
    row.Position = position
    row.Visible = false
    if zIndex then row.ZIndex = zIndex end
    row.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, pxFn(5))
    layout.Parent = row

    local label = Instance.new("TextLabel")
    label.Name = "ValueText"
    label.BackgroundTransparency = 1
    label.AutomaticSize = Enum.AutomaticSize.X
    label.Size = UDim2.new(0, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = SHARD_UI_ACCENT
    label.TextSize = textSize
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Text = ""
    if zIndex then label.ZIndex = zIndex end
    label.Parent = row

    if shardImage then
        local icon = Instance.new("ImageLabel")
        icon.Name = "ShardIcon"
        icon.BackgroundTransparency = 1
        icon.Size = UDim2.new(0, pxFn(18), 0, pxFn(18))
        icon.Image = shardImage
        icon.ScaleType = Enum.ScaleType.Fit
        if zIndex then icon.ZIndex = zIndex end
        icon.Parent = row
    else
        local suffix = Instance.new("TextLabel")
        suffix.Name = "ShardText"
        suffix.BackgroundTransparency = 1
        suffix.AutomaticSize = Enum.AutomaticSize.X
        suffix.Size = UDim2.new(0, 0, 1, 0)
        suffix.Font = Enum.Font.GothamBold
        suffix.Text = "SHARDS"
        suffix.TextColor3 = SHARD_UI_ACCENT
        suffix.TextSize = textSize
        if zIndex then suffix.ZIndex = zIndex end
        suffix.Parent = row
    end

    return row, label
end

local function addBlackTextStroke(label)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.15
    stroke.Parent = label
end

local function ensurePotionRemotes()
    if potionRemotes then return potionRemotes end
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return nil end
    local potionsFolder = remotesFolder:FindFirstChild("Potions") or remotesFolder:WaitForChild("Potions", 5)
    if not potionsFolder then return nil end
    local getStateRF = potionsFolder:FindFirstChild("GetPotionState")
    local setEquippedRF = potionsFolder:FindFirstChild("SetPotionEquipped")
    local stateUpdatedRE = remotesFolder:FindFirstChild("PotionStateUpdated")
    if not getStateRF or not setEquippedRF or not stateUpdatedRE then return nil end
    potionRemotes = { getState = getStateRF, setEquipped = setEquippedRF, stateUpdated = stateUpdatedRE }
    return potionRemotes
end

local BOOST_ACCENT_COLORS = {
    coins_2x = Color3.fromRGB(255, 200, 40),
    xp_2x = Color3.fromRGB(180, 120, 255),
    quest_2x = Color3.fromRGB(80, 165, 255),
}

local POTION_CATEGORY_BATTLE = "Battle"
local POTION_CATEGORY_ELIXIR = "Elixir"
local POTION_CATEGORY_SECTIONS = {
    {
        Id = "Battle",
        Category = POTION_CATEGORY_BATTLE,
        Header = "BATTLE",
        Subtitle = "Equip these to slot 4 and use them during battle.",
        EmptyText = "No battle potions owned yet.",
        Accent = Color3.fromRGB(239, 111, 91),
    },
    {
        Id = "Elixir",
        Category = POTION_CATEGORY_ELIXIR,
        Header = "ELIXIR",
        Subtitle = "Activate these for longer-lasting buffs.",
        EmptyText = "No elixirs owned yet.",
        Accent = Color3.fromRGB(190, 139, 255),
    },
}

local function normalizePotionItemCategory(category, fallback)
    if category == POTION_CATEGORY_ELIXIR then
        return POTION_CATEGORY_ELIXIR
    end
    if category == POTION_CATEGORY_BATTLE then
        return POTION_CATEGORY_BATTLE
    end
    return fallback or POTION_CATEGORY_BATTLE
end

local function getBoostIconImage(def)
    if type(def) ~= "table" then return nil end
    if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then return def.IconAssetId end
    local iconData = getItemIconData(def)
    if type(iconData) == "table" and type(iconData.IconAssetId) == "string" and #iconData.IconAssetId > 0 then return iconData.IconAssetId end
    local key = def.IconKey
    if type(iconData) == "table" and type(iconData.AssetKey) == "string" then
        key = iconData.AssetKey
    end
    if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" and key then
        local image = AssetCodesGlobal.Get(key)
        if type(image) == "string" and #image > 0 then return image end
    end
    return nil
end

local function createPotionBottleIcon(parent, iconData, accent, scale)
    iconData = type(iconData) == "table" and iconData or {}
    accent = accent or GREEN_GLOW
    scale = tonumber(scale) or 0.86

    local function colorFromIcon(value, fallback)
        if typeof(value) == "Color3" then return value end
        if type(value) == "table" then
            return Color3.fromRGB(tonumber(value[1]) or 255, tonumber(value[2]) or 255, tonumber(value[3]) or 255)
        end
        return fallback
    end

    local liquidColor = colorFromIcon(iconData.LiquidColor, accent)
    local glassColor = colorFromIcon(iconData.GlassColor, liquidColor:Lerp(Color3.new(1, 1, 1), 0.58))
    local strokeColor = colorFromIcon(iconData.StrokeColor, liquidColor:Lerp(Color3.new(0, 0, 0), 0.48))
    local capColor = colorFromIcon(iconData.CapColor, strokeColor)
    local zBase = (parent and parent.ZIndex or 1) + 1

    local root = Instance.new("Frame")
    root.Name = "GeneratedPotionIcon"
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.Size = UDim2.fromScale(scale, scale)
    root.BackgroundTransparency = 1
    root.ZIndex = zBase
    root.Parent = parent

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.AnchorPoint = Vector2.new(0.5, 1)
    body.Position = UDim2.fromScale(0.5, 0.96)
    body.Size = UDim2.fromScale(0.56, 0.62)
    body.BackgroundColor3 = glassColor
    body.BorderSizePixel = 0
    body.ZIndex = zBase + 1
    body.Parent = root
    Instance.new("UICorner", body).CornerRadius = UDim.new(0, px(8))
    local bodyStroke = Instance.new("UIStroke", body)
    bodyStroke.Color = strokeColor; bodyStroke.Thickness = 1.2; bodyStroke.Transparency = 0.08

    local neck = Instance.new("Frame")
    neck.Name = "Neck"
    neck.AnchorPoint = Vector2.new(0.5, 1)
    neck.Position = UDim2.fromScale(0.5, 0.39)
    neck.Size = UDim2.fromScale(0.22, 0.24)
    neck.BackgroundColor3 = glassColor
    neck.BorderSizePixel = 0
    neck.ZIndex = zBase + 2
    neck.Parent = root
    Instance.new("UICorner", neck).CornerRadius = UDim.new(0, px(5))
    local neckStroke = Instance.new("UIStroke", neck)
    neckStroke.Color = strokeColor; neckStroke.Thickness = 1; neckStroke.Transparency = 0.12

    local cap = Instance.new("Frame")
    cap.Name = "Cap"
    cap.AnchorPoint = Vector2.new(0.5, 0)
    cap.Position = UDim2.fromScale(0.5, 0.08)
    cap.Size = UDim2.fromScale(0.34, 0.11)
    cap.BackgroundColor3 = capColor
    cap.BorderSizePixel = 0
    cap.ZIndex = zBase + 4
    cap.Parent = root
    Instance.new("UICorner", cap).CornerRadius = UDim.new(0, px(5))

    local liquid = Instance.new("Frame")
    liquid.Name = "Liquid"
    liquid.AnchorPoint = Vector2.new(0.5, 1)
    liquid.Position = UDim2.fromScale(0.5, 0.9)
    liquid.Size = UDim2.fromScale(0.44, 0.34)
    liquid.BackgroundColor3 = liquidColor
    liquid.BorderSizePixel = 0
    liquid.ZIndex = zBase + 3
    liquid.Parent = root
    Instance.new("UICorner", liquid).CornerRadius = UDim.new(0, px(7))

    local shine = Instance.new("Frame")
    shine.Name = "Highlight"
    shine.AnchorPoint = Vector2.new(0, 0)
    shine.Position = UDim2.fromScale(0.36, 0.38)
    shine.Size = UDim2.fromScale(0.09, 0.34)
    shine.BackgroundColor3 = WHITE
    shine.BackgroundTransparency = 0.32
    shine.BorderSizePixel = 0
    shine.Rotation = 14
    shine.ZIndex = zBase + 5
    shine.Parent = root
    Instance.new("UICorner", shine).CornerRadius = UDim.new(0, px(5))

    if iconData.Motif == "speed" then
        for index = 1, 3 do
            local streak = Instance.new("Frame")
            streak.Name = "SpeedStreak" .. tostring(index)
            streak.AnchorPoint = Vector2.new(0.5, 0.5)
            streak.Position = UDim2.fromScale(0.34 + (index * 0.11), 0.55 + ((index - 2) * 0.08))
            streak.Size = UDim2.fromScale(0.24 - (index * 0.025), 0.045)
            streak.BackgroundColor3 = WHITE
            streak.BackgroundTransparency = 0.08
            streak.BorderSizePixel = 0
            streak.Rotation = -16
            streak.ZIndex = zBase + 6
            streak.Parent = root
            Instance.new("UICorner", streak).CornerRadius = UDim.new(0, px(5))
        end
    end

    return root
end

local function getSkinIconImage(def)
    if type(def) ~= "table" then return nil end
    if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then return def.IconAssetId end
    local key = def.IconKey
    if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" and key then
        local image = AssetCodesGlobal.Get(key)
        if type(image) == "string" and #image > 0 then return image end
    end
    return nil
end

local function getSkinPreviewImage(def)
    if type(def) ~= "table" then return nil end
    if type(def.PreviewImageAssetId) == "string" and #def.PreviewImageAssetId > 0 then
        return def.PreviewImageAssetId
    end
    local key = def.PreviewImageKey
    if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" and key then
        local image = AssetCodesGlobal.Get(key)
        if type(image) == "string" and #image > 0 then return image end
    end
    return getSkinIconImage(def)
end

local function clearViewportPreviewScene(viewportFrame)
    if not viewportFrame then return end
    for _, child in ipairs(viewportFrame:GetChildren()) do
        if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
            child:Destroy()
        end
    end
end

local function updateSkinDetailPreview(viewportFrame, previewImageLabel, skinId, skinDefsModule, skinPreviewModule)
    if not viewportFrame or not previewImageLabel then return end

    clearViewportPreviewScene(viewportFrame)
    previewImageLabel.Visible = false

    if not skinId or not skinDefsModule then return end

    local def = skinDefsModule.GetById and skinDefsModule.GetById(skinId)
    if not def then return end

    local previewShowHelm = _G.PlayerSettings and _G.PlayerSettings.ShowHelm
    if previewShowHelm == nil then previewShowHelm = true end
    if skinPreviewModule then
        local ok, rendered = pcall(function()
            if type(skinPreviewModule.RenderSkinPreview) == "function" then
                return skinPreviewModule.RenderSkinPreview(viewportFrame, skinId, {
                    mode = "Large",
                    showHelm = previewShowHelm,
                })
            end
            return skinPreviewModule.Update(viewportFrame, skinId, previewShowHelm)
        end)
        if ok and rendered ~= false then
            return
        end
    end

    local previewImage = getSkinPreviewImage(def)
    if previewImage then
        previewImageLabel.Image = previewImage
        previewImageLabel.Visible = true
    end
end

local function ensureBoostRemotes()
    if boostRemotes then return boostRemotes end
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then return nil end
    local boostsFolder = remotesFolder:FindFirstChild("Boosts") or remotesFolder:WaitForChild("Boosts", 5)
    if not boostsFolder then return nil end
    local activateRF  = boostsFolder:FindFirstChild("ActivateInventoryBoost")
    local getStatesRF = boostsFolder:FindFirstChild("GetBoostStates")
    local stateUpdatedRE = remotesFolder:FindFirstChild("BoostStateUpdated")
    if not activateRF or not getStatesRF or not stateUpdatedRE then return nil end
    boostRemotes = { activate = activateRF, getStates = getStatesRF, stateUpdated = stateUpdatedRE }
    return boostRemotes
end

--------------------------------------------------------------------------------
-- InventoryUI.Create
--------------------------------------------------------------------------------
function InventoryUI.Create(parent, coinApi, inventoryApi)
    if not parent then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") then
            pcall(function() c:Destroy() end)
        end
    end

    BoostConfig      = BoostConfig or safeRequireBoostConfig()
    PotionConfigGlobal = PotionConfigGlobal or safeRequirePotionConfig()
    AssetCodesGlobal = AssetCodesGlobal or safeRequireAssetCodes()

    -- ──────────────────────────────────────────────────────────────────────
    -- Dimensions
    -- ──────────────────────────────────────────────────────────────────────
    local TAB_W     = px(LeftPanelStyle.TAB_W)
    local TAB_GAP   = px(LeftPanelStyle.TAB_GAP)
    local DETAIL_W  = px(315)
    local GRID_GAP  = px(10)

    -- ── Shared inventory card layout constants (Melee tab = reference) ──
    local INV_CARD = {
        CornerRadius       = px(8),
        StrokeThickness    = 1.4,
        StrokeTransparency = 0.25,
        NameTextSize       = math.max(13, math.floor(px(15))),
        NameY              = px(4),
        NameHeight         = px(22),
        IconSize           = px(88),
        IconY              = px(28),
        IconCorner         = px(6),
        Line1OffBottom     = px(22),
        Line1Height        = px(16),
        Line1TextSize      = math.max(11, math.floor(px(12))),
        Line2OffBottom     = px(5),
        Line2Height        = px(18),
        Line2TextSize      = math.max(12, math.floor(px(14))),
    }

    local _, screenY = getViewportSize()
    local rootHeight = math.max(px(380), math.floor(screenY * 0.58))

    -- ──────────────────────────────────────────────────────────────────────
    -- Connection tracking
    -- ──────────────────────────────────────────────────────────────────────
    local cleanupConnections = {}
    local function trackConn(conn) table.insert(cleanupConnections, conn) end
    local function cleanup()
        for _, conn in ipairs(cleanupConnections) do pcall(function() conn:Disconnect() end) end
        table.clear(cleanupConnections)
    end

    local function bindFixedColumnGrid(scrollFrame, gridLayout, gridPadding, baseCellWidth, baseCellHeight)
        if not (scrollFrame and gridLayout and gridPadding) then return end

        local aspectRatio = (tonumber(baseCellHeight) or 1) / math.max(1, tonumber(baseCellWidth) or 1)

        local function updateCellSize()
            local availableWidth = scrollFrame.AbsoluteSize.X
                - (gridPadding.PaddingLeft.Offset or 0)
                - (gridPadding.PaddingRight.Offset or 0)
                - math.max(0, scrollFrame.ScrollBarThickness or 0)
            local horizontalPadding = gridLayout.CellPadding.X.Offset * math.max(0, INVENTORY_GRID_COLUMNS - 1)
            local cellWidth = math.max(1, math.floor((availableWidth - horizontalPadding) / INVENTORY_GRID_COLUMNS))
            local cellHeight = math.max(1, math.floor(cellWidth * aspectRatio))
            gridLayout.CellSize = UDim2.new(0, cellWidth, 0, cellHeight)
        end

        gridLayout.FillDirectionMaxCells = INVENTORY_GRID_COLUMNS
        trackConn(scrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize))
        task.defer(updateCellSize)
    end

    -- ──────────────────────────────────────────────────────────────────────
    -- Require config modules
    -- ──────────────────────────────────────────────────────────────────────
    local CrateConfig = nil
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
        if mod and mod:IsA("ModuleScript") then CrateConfig = require(mod) end
    end)

    local isDeveloper = false
    if CrateConfig and CrateConfig.DeveloperUserIds then
        local lp = Players.LocalPlayer
        if lp then
            for _, uid in ipairs(CrateConfig.DeveloperUserIds) do
                if uid == lp.UserId then isDeveloper = true; break end
            end
        end
    end

    local AssetCodes = nil
    pcall(function()
        local ac = ReplicatedStorage:FindFirstChild("AssetCodes")
        if ac and ac:IsA("ModuleScript") then AssetCodes = require(ac) end
    end)

    local meleePresets, rangedPresets = nil, nil
    pcall(function()
        local mm = ReplicatedStorage:FindFirstChild("ToolMeleeSettings")
        if mm and mm:IsA("ModuleScript") then
            local ok, mod = pcall(require, mm)
            if ok and type(mod) == "table" then meleePresets = mod.presets end
        end
    end)
    pcall(function()
        local rm = ReplicatedStorage:FindFirstChild("Toolgunsettings")
        if rm and rm:IsA("ModuleScript") then
            local ok, mod = pcall(require, rm)
            if ok and type(mod) == "table" and mod.presets then rangedPresets = mod.presets end
        end
    end)

    -- ──────────────────────────────────────────────────────────────────────
    -- classifyItem
    -- ──────────────────────────────────────────────────────────────────────
    local function classifyItem(name)
        if not name then return "Ranged" end
        local key = tostring(name):lower()
        if key == "stick" or key == "starter sword" then return "Melee" end
        if meleePresets  and meleePresets[key]  then return "Melee" end
        if rangedPresets and rangedPresets[key] then return "Ranged" end
        return "Ranged"
    end

    -- Infer a weapon's rarity from CrateConfig.WeaponsByRarity (case-insensitive)
    local function getWeaponRarity(name)
        if not name then return "Common" end
        if not CrateConfig or type(CrateConfig.WeaponsByRarity) ~= "table" then return "Common" end
        local key = tostring(name):lower()
        for rarity, list in pairs(CrateConfig.WeaponsByRarity) do
            if type(list) == "table" then
                for _, entry in ipairs(list) do
                    if entry and entry.weapon and tostring(entry.weapon):lower() == key then
                        return rarity
                    end
                end
            end
        end
        return "Common"
    end

    -- ──────────────────────────────────────────────────────────────────────
    -- getRarityColor / getRarityBgColor
    -- ──────────────────────────────────────────────────────────────────────
    local function getRarityColor(rarity)
        return RARITY_COLORS[rarity] or RARITY_COLORS.Common
    end
    local function getRarityBgColor(rarity)
        return RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common
    end

    -- ──────────────────────────────────────────────────────────────────────
    -- Fetch inventory data
    -- ──────────────────────────────────────────────────────────────────────
    local items = inventoryApi and inventoryApi:GetItems() or {}
    if items and type(items) == "table" then
        local normalized = {}
        for _, id in ipairs(items) do
            if type(id) == "string" and tostring(id):lower() == "stick" then
                table.insert(normalized, "Starter Sword")
            else
                table.insert(normalized, id)
            end
        end
        items = normalized
    end

    local weaponInstances = {}
    pcall(function()
        local getInvRF = ReplicatedStorage:FindFirstChild("GetWeaponInventory")
        if getInvRF and getInvRF:IsA("RemoteFunction") then
            local result = getInvRF:InvokeServer()
            if type(result) == "table" then weaponInstances = result end
        end
    end)

    -- ──────────────────────────────────────────────────────────────────────
    -- Build unified weapon item list
    -- ──────────────────────────────────────────────────────────────────────
    local allWeaponItems = {}

    for _, itemName in ipairs(items) do
        table.insert(allWeaponItems, {
            id         = itemName,
            name       = itemName,
            category   = classifyItem(itemName),
            rarity     = getWeaponRarity(itemName),
            isInstance = false,
            sizePercent = 100, -- default size for non-instance items
            sizeTier = "Normal",
        })
    end

    for instanceId, data in pairs(weaponInstances) do
        if type(data) == "table" and data.weaponName then
            table.insert(allWeaponItems, {
                id          = instanceId,
                name        = data.weaponName,
                category    = data.category or classifyItem(data.weaponName),
                rarity      = data.rarity or "Common",
                isInstance  = true,
                instanceId  = instanceId,
                weaponName  = data.weaponName,
                source      = data.source,
                favorited   = data.favorited == true,
                sizePercent = data.sizePercent or 100,   -- SIZE ROLL SYSTEM
                sizeTier    = data.sizeTier or "Normal", -- SIZE ROLL SYSTEM
                enchantName    = data.enchantName or "",       -- ENCHANT SYSTEM
                mastery        = data.mastery,
            })
        end
    end

    -- ──────────────────────────────────────────────────────────────────────
    -- Equipped state (authoritative from hotbar / server loadout)
    -- ──────────────────────────────────────────────────────────────────────
    local equippedState = { Melee = "Starter Sword", Ranged = "Starter Slingshot" }
    -- Separate table to remember equipped instanceIds so we match the right copy
    local equippedInstanceIds = { Melee = nil, Ranged = nil }
    do
        local player = Players.LocalPlayer
        local found  = { Melee = nil, Ranged = nil }
        local function scanContainer(container)
            if not container then return end
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then
                    local cat = child:GetAttribute("HotbarCategory")
                    if type(cat) == "string" then
                        local k = cat:sub(1,1):upper() .. cat:sub(2):lower()
                        if (k == "Melee" or k == "Ranged") and not found[k] then
                            found[k] = child.Name
                        end
                    end
                end
            end
        end
        scanContainer(player:FindFirstChildOfClass("Backpack"))
        if player.Character then scanContainer(player.Character) end

        -- Always query the server for the authoritative loadout (includes instanceIds)
        pcall(function()
            local rf = ReplicatedStorage:WaitForChild("GetLoadout", 5)
            if rf and rf:IsA("RemoteFunction") then
                local data = rf:InvokeServer()
                if type(data) == "table" then
                    if type(data.melee)  == "string" and #data.melee  > 0 then equippedState.Melee  = data.melee  end
                    if type(data.ranged) == "string" and #data.ranged > 0 then equippedState.Ranged = data.ranged end
                    if type(data.meleeInstanceId)  == "string" then equippedInstanceIds.Melee  = data.meleeInstanceId  end
                    if type(data.rangedInstanceId) == "string" then equippedInstanceIds.Ranged = data.rangedInstanceId end
                end
            end
        end)

        -- If server didn't return anything, fall back to scanning tools in backpack
        if not equippedState.Melee or equippedState.Melee == "Starter Sword" then
            if found.Melee then equippedState.Melee = found.Melee end
        end
        if not equippedState.Ranged or equippedState.Ranged == "Starter Slingshot" then
            if found.Ranged then equippedState.Ranged = found.Ranged end
        end
    end

    -- ──────────────────────────────────────────────────────────────────────
    -- isItemEquipped  (handles legacy name ↔ instanceId matching)
    -- ──────────────────────────────────────────────────────────────────────
    local function isItemEquipped(itemData)
        local cat   = itemData.category
        local eqVal = equippedState[cat]
        if eqVal == nil then return false end
        -- Direct id match (works for both instance and non-instance items)
        if eqVal == itemData.id then return true end
        -- Instance item: check by instanceId first (most reliable)
        if itemData.isInstance and itemData.instanceId then
            local eqInstId = equippedInstanceIds[cat]
            if eqInstId then
                -- Only match if instanceId matches exactly
                if itemData.instanceId == eqInstId then
                    equippedState[cat] = itemData.id
                    return true
                end
                -- Another instance of the same weapon but wrong instanceId
                return false
            end
            -- No instanceId tracked yet; fall through to name match
        end
        -- Instance item: equipped state may hold the weapon name instead of instanceId
        -- Only promote to this item if there's no instanceId tracking
        if itemData.isInstance and itemData.weaponName and itemData.weaponName == eqVal and not equippedInstanceIds[cat] then
            equippedState[cat] = itemData.id
            return true
        end
        -- Non-instance item: equipped state may hold the tool name that matches our name
        if not itemData.isInstance and itemData.name == eqVal then return true end
        return false
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  ROOT FRAME
    -- ══════════════════════════════════════════════════════════════════════
    local root = Instance.new("Frame")
    root.Name = "InventoryUI"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 0, rootHeight)
    root.ZIndex = 240
    root.LayoutOrder = 1
    root.ClipsDescendants = true
    root.Parent = parent
    attachResponsiveRootScale(root)

    -- ══════════════════════════════════════════════════════════════════════
    --  SIDEBAR  (tab buttons)
    -- ══════════════════════════════════════════════════════════════════════
    local sidebar = Instance.new("Frame")
    sidebar.Name = "TabSidebar"
    sidebar.Parent = root
    LeftPanelStyle.ApplyLeftTabRailStyle(sidebar, px)

    local tabButtons = {}
    local currentTab = "melee"

    local function makeTabButton(def)
        local btn = Instance.new("TextButton")
        btn.Name = def.label .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size = UDim2.new(1, -px(2), 0, px(62))
        btn.LayoutOrder = def.order
        btn.Text = ""
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, px(10))

        local bar = Instance.new("Frame", btn)
        bar.Name = "ActiveBar"
        bar.BackgroundColor3 = GOLD; bar.BorderSizePixel = 0
        bar.Size = UDim2.new(0, px(3), 0.6, 0)
        bar.AnchorPoint = Vector2.new(0, 0.5); bar.Position = UDim2.new(0, 0, 0.5, 0)
        bar.BackgroundTransparency = 1
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)

        if def.id == "melee" or def.id == "ranged" or def.id == "boosts" or def.id == "emotes" then
            local iconLbl = Instance.new("TextLabel", btn)
            iconLbl.Name = "Icon"
            iconLbl.BackgroundTransparency = 1
            iconLbl.Font = Enum.Font.GothamBold
            iconLbl.Text = def.icon
            iconLbl.TextColor3 = DIM_TEXT
            iconLbl.TextSize = math.max(16, math.floor(px(18)))
            iconLbl.Size = UDim2.new(1, 0, 0, px(24))
            iconLbl.Position = UDim2.new(0, 0, 0, px(8))
            iconLbl.TextXAlignment = Enum.TextXAlignment.Center
        else
            local custom = buildCustomTabIcon(btn, def.id)
            setTabIconTint(custom, getCustomTabIconColor(def.id, false))
        end

        local textLbl = Instance.new("TextLabel", btn)
        textLbl.Name = "Label"
        textLbl.BackgroundTransparency = 1
        textLbl.Font = Enum.Font.GothamBold
        textLbl.Text = def.label
        textLbl.TextColor3 = DIM_TEXT
        textLbl.TextSize = math.max(11, math.floor(px(12)))
        textLbl.Size = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position = UDim2.new(0, px(3), 0, px(34))
        textLbl.TextXAlignment = Enum.TextXAlignment.Center

        local btnStroke = Instance.new("UIStroke", btn)
        btnStroke.Color = CARD_STROKE; btnStroke.Thickness = 1.2; btnStroke.Transparency = 0.6

        return btn
    end

    for _, def in ipairs(TAB_DEFS) do
        tabButtons[def.id] = makeTabButton(def)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  WEAPON AREA  (grid scroll + details panel)  — visible for melee/ranged
    -- ══════════════════════════════════════════════════════════════════════
    local CONTENT_X   = TAB_W + TAB_GAP
    local CONTENT_W_OFF = -(CONTENT_X)

    local weaponArea = Instance.new("Frame")
    weaponArea.Name = "WeaponArea"
    weaponArea.BackgroundTransparency = 1
    weaponArea.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    weaponArea.Position = UDim2.new(0, CONTENT_X, 0, 0)
    weaponArea.Visible = true
    weaponArea.Parent = root

    -- Scrollable grid (left portion)
    local gridScroll = Instance.new("ScrollingFrame")
    gridScroll.Name = "GridScroll"
    gridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
    gridScroll.BackgroundTransparency = 0.5
    gridScroll.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
    gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gridScroll.ScrollBarThickness = px(4)
    gridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
    gridScroll.BorderSizePixel = 0
    gridScroll.Parent = weaponArea
    Instance.new("UICorner", gridScroll).CornerRadius = UDim.new(0, px(10))

    local gridLayout = Instance.new("UIGridLayout", gridScroll)
    gridLayout.CellSize = UDim2.new(0, px(158), 0, px(188))
    gridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local gridPad = Instance.new("UIPadding", gridScroll)
    gridPad.PaddingTop    = UDim.new(0, px(8))
    gridPad.PaddingLeft   = UDim.new(0, px(8))
    gridPad.PaddingRight  = UDim.new(0, px(8))
    gridPad.PaddingBottom = UDim.new(0, px(8))
    bindFixedColumnGrid(gridScroll, gridLayout, gridPad, 158, 188)

    -- Empty state overlay (shown when a category has no items)
    local emptyState = Instance.new("Frame")
    emptyState.Name = "EmptyState"
    emptyState.BackgroundTransparency = 1
    emptyState.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
    emptyState.Visible = false
    emptyState.Parent = weaponArea

    local emptyCard = Instance.new("Frame")
    emptyCard.BackgroundColor3 = CARD_BG
    emptyCard.Size = UDim2.new(0.7, 0, 0, px(130))
    emptyCard.AnchorPoint = Vector2.new(0.5, 0.5)
    emptyCard.Position = UDim2.new(0.5, 0, 0.45, 0)
    emptyCard.Parent = emptyState
    Instance.new("UICorner", emptyCard).CornerRadius = UDim.new(0, px(14))
    local ecStroke = Instance.new("UIStroke", emptyCard)
    ecStroke.Color = CARD_STROKE; ecStroke.Thickness = 1.2; ecStroke.Transparency = 0.3

    local emptyLine1 = Instance.new("TextLabel", emptyCard)
    emptyLine1.BackgroundTransparency = 1
    emptyLine1.Font = Enum.Font.GothamMedium
    emptyLine1.Text = "You don't own any weapons in this category yet."
    emptyLine1.TextColor3 = DIM_TEXT
    emptyLine1.TextSize = math.max(13, math.floor(px(14)))
    emptyLine1.TextWrapped = true
    emptyLine1.Size = UDim2.new(0.85, 0, 0, px(40))
    emptyLine1.AnchorPoint = Vector2.new(0.5, 0)
    emptyLine1.Position = UDim2.new(0.5, 0, 0, px(28))
    emptyLine1.TextXAlignment = Enum.TextXAlignment.Center

    local emptyLine2 = Instance.new("TextLabel", emptyCard)
    emptyLine2.BackgroundTransparency = 1
    emptyLine2.Font = Enum.Font.GothamMedium
    emptyLine2.Text = "Visit the shop to unlock more."
    emptyLine2.TextColor3 = UITheme.GOLD_DIM
    emptyLine2.TextSize = math.max(11, math.floor(px(12)))
    emptyLine2.Size = UDim2.new(0.85, 0, 0, px(20))
    emptyLine2.AnchorPoint = Vector2.new(0.5, 0)
    emptyLine2.Position = UDim2.new(0.5, 0, 0, px(74))
    emptyLine2.TextXAlignment = Enum.TextXAlignment.Center

    -- Shop nav inside empty state
    local emptyShopBtn = Instance.new("TextButton", emptyState)
    emptyShopBtn.Name = "ShopNavBtn"
    emptyShopBtn.AutoButtonColor = false
    emptyShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
    emptyShopBtn.Font = Enum.Font.GothamBold
    emptyShopBtn.Text = "\u{1F6D2}  Browse Shop"
    emptyShopBtn.TextColor3 = WHITE
    emptyShopBtn.TextTransparency = 0
    emptyShopBtn.TextSize = math.max(14, math.floor(px(15)))
    emptyShopBtn.AutomaticSize = Enum.AutomaticSize.X
    emptyShopBtn.Size = UDim2.new(0, 0, 0, px(36))
    emptyShopBtn.AnchorPoint = Vector2.new(0.5, 0)
    emptyShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
    Instance.new("UICorner", emptyShopBtn).CornerRadius = UDim.new(0, px(8))
    local esBtnPad = Instance.new("UIPadding", emptyShopBtn)
    esBtnPad.PaddingLeft = UDim.new(0, px(20)); esBtnPad.PaddingRight = UDim.new(0, px(20))
    local esBtnStroke = Instance.new("UIStroke", emptyShopBtn)
    esBtnStroke.Color = Color3.fromRGB(0, 0, 0); esBtnStroke.Thickness = 1.5; esBtnStroke.Transparency = 0.15

    emptyShopBtn.MouseButton1Click:Connect(function()
        local mc = _G.SideUI and _G.SideUI.MenuController
        if mc then
            mc.OpenMenu("Shop")
            if ShopUIModule and ShopUIModule.setActiveTab then
                ShopUIModule.setActiveTab("weapons")
            end
        end
    end)

    -- ══════════════════════════════════════════════════════════════════════
    --  DETAILS PANEL  (right side of weapon area)
    -- ══════════════════════════════════════════════════════════════════════
    local detailsPanel = Instance.new("Frame")
    detailsPanel.Name = "DetailsPanel"
    detailsPanel.BackgroundColor3 = CARD_BG
    detailsPanel.Size = UDim2.new(0, DETAIL_W, 1, 0)
    detailsPanel.AnchorPoint = Vector2.new(1, 0)
    detailsPanel.Position = UDim2.new(1, 0, 0, 0)
    detailsPanel.Parent = weaponArea
    Instance.new("UICorner", detailsPanel).CornerRadius = UDim.new(0, px(12))
    local dpStroke = Instance.new("UIStroke", detailsPanel)
    dpStroke.Color = CARD_STROKE; dpStroke.Thickness = 1.4; dpStroke.Transparency = 0.2

    -- Placeholder text (visible until a weapon is selected)
    local detailPlaceholder = Instance.new("TextLabel", detailsPanel)
    detailPlaceholder.Name = "Placeholder"
    detailPlaceholder.BackgroundTransparency = 1
    detailPlaceholder.Font = Enum.Font.GothamMedium
    detailPlaceholder.Text = "Select a weapon"
    detailPlaceholder.TextColor3 = DIM_TEXT
    detailPlaceholder.TextSize = px(22)
    detailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
    detailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
    detailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

    -- Detail content (hidden until a weapon is selected)
    local detailContent = Instance.new("Frame", detailsPanel)
    detailContent.Name = "DetailContent"
    detailContent.BackgroundTransparency = 1
    detailContent.Size = UDim2.new(1, 0, 1, 0)
    detailContent.Visible = false

    local dPad = Instance.new("UIPadding", detailContent)
    dPad.PaddingTop  = UDim.new(0, px(12)); dPad.PaddingBottom = UDim.new(0, px(12))
    dPad.PaddingLeft = UDim.new(0, px(12)); dPad.PaddingRight  = UDim.new(0, px(12))

    -- Large image with rarity-coloured background + subtle gradient
    local detailImageBg = Instance.new("Frame", detailContent)
    detailImageBg.Name = "ImageBg"
    detailImageBg.BackgroundColor3 = RARITY_BG_COLORS.Common
    detailImageBg.Size = UDim2.new(1, 0, 0, px(170))
    detailImageBg.ClipsDescendants = true
    Instance.new("UICorner", detailImageBg).CornerRadius = UDim.new(0, px(10))
    local imgBgStroke = Instance.new("UIStroke", detailImageBg)
    imgBgStroke.Color = RARITY_COLORS.Common; imgBgStroke.Thickness = 1.5; imgBgStroke.Transparency = 0.25
    local imgPad = Instance.new("UIPadding", detailImageBg)
    imgPad.PaddingTop = UDim.new(0, px(6)); imgPad.PaddingBottom = UDim.new(0, px(6))
    imgPad.PaddingLeft = UDim.new(0, px(6)); imgPad.PaddingRight = UDim.new(0, px(6))

    local detailImage = Instance.new("ImageLabel", detailImageBg)
    detailImage.Name = "Icon"
    detailImage.BackgroundTransparency = 1
    detailImage.Size = UDim2.new(0.72, 0, 0.72, 0)
    detailImage.AnchorPoint = Vector2.new(0.5, 0.5)
    detailImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    detailImage.ScaleType = Enum.ScaleType.Fit

    -- Weapon name (slightly larger for prominence)
    local detailName = Instance.new("TextLabel", detailContent)
    detailName.Name = "WeaponName"
    detailName.BackgroundTransparency = 1
    detailName.Font = Enum.Font.GothamBold
    detailName.TextColor3 = WHITE
    detailName.TextSize = px(28)
    detailName.TextXAlignment = Enum.TextXAlignment.Center
    detailName.Size = UDim2.new(1, 0, 0, px(36))
    detailName.Position = UDim2.new(0, 0, 0, px(180))
    detailName.TextTruncate = Enum.TextTruncate.AtEnd

    -- Rarity label (slightly smaller than name, rarity-coloured)
    local detailRarity = Instance.new("TextLabel", detailContent)
    detailRarity.Name = "Rarity"
    detailRarity.BackgroundTransparency = 1
    detailRarity.Font = Enum.Font.GothamBold
    detailRarity.TextColor3 = RARITY_COLORS.Common
    detailRarity.TextSize = px(17)
    detailRarity.TextXAlignment = Enum.TextXAlignment.Center
    detailRarity.Size = UDim2.new(1, 0, 0, px(22))
    detailRarity.Position = UDim2.new(0, 0, 0, px(220))

    -- Weapon type (melee/ranged)
    local detailType = Instance.new("TextLabel", detailContent)
    detailType.Name = "WeaponType"
    detailType.BackgroundTransparency = 1
    detailType.Font = Enum.Font.GothamMedium
    detailType.TextColor3 = DIM_TEXT
    detailType.TextSize = px(15)
    detailType.TextXAlignment = Enum.TextXAlignment.Center
    detailType.Size = UDim2.new(1, 0, 0, px(20))
    detailType.Position = UDim2.new(0, 0, 0, px(244))

    -- SIZE ROLL SYSTEM — size info in detail panel (plain coloured text)
    local detailSize = Instance.new("TextLabel", detailContent)
    detailSize.Name = "SizeInfo"
    detailSize.BackgroundTransparency = 1
    detailSize.Font = Enum.Font.GothamBold
    detailSize.RichText = true
    detailSize.TextColor3 = WHITE
    detailSize.TextSize = px(18)
    detailSize.TextXAlignment = Enum.TextXAlignment.Center
    detailSize.Size = UDim2.new(1, 0, 0, px(24))
    detailSize.Position = UDim2.new(0, 0, 0, px(268))

    -- ENCHANT SYSTEM — enchant name in detail panel
    local detailEnchant = Instance.new("TextLabel", detailContent)
    detailEnchant.Name = "EnchantInfo"
    detailEnchant.BackgroundTransparency = 1
    detailEnchant.Font = Enum.Font.GothamBold
    detailEnchant.TextColor3 = GOLD
    detailEnchant.TextSize = px(16)
    detailEnchant.TextXAlignment = Enum.TextXAlignment.Center
    detailEnchant.Size = UDim2.new(1, 0, 0, px(22))
    detailEnchant.Position = UDim2.new(0, 0, 0, px(292))
    detailEnchant.Text = ""

    local masteryPanel = Instance.new("Frame", detailContent)
    masteryPanel.Name = "MasteryPanel"
    masteryPanel.BackgroundColor3 = Color3.fromRGB(22, 24, 38)
    masteryPanel.BackgroundTransparency = 0.08
    masteryPanel.Size = UDim2.new(0.9, 0, 0, px(112))
    masteryPanel.AnchorPoint = Vector2.new(0.5, 0)
    masteryPanel.Position = UDim2.new(0.5, 0, 0, px(324))
    masteryPanel.Visible = false
    Instance.new("UICorner", masteryPanel).CornerRadius = UDim.new(0, px(8))
    local masteryStroke = Instance.new("UIStroke", masteryPanel)
    masteryStroke.Color = Color3.fromRGB(72, 74, 96)
    masteryStroke.Thickness = 1.1
    masteryStroke.Transparency = 0.2

    local masteryTitle = Instance.new("TextLabel", masteryPanel)
    masteryTitle.Name = "Title"
    masteryTitle.BackgroundTransparency = 1
    masteryTitle.Font = Enum.Font.GothamBold
    masteryTitle.TextColor3 = GOLD
    masteryTitle.TextSize = px(18)
    masteryTitle.TextXAlignment = Enum.TextXAlignment.Left
    masteryTitle.Size = UDim2.new(1, -px(24), 0, px(24))
    masteryTitle.Position = UDim2.new(0, px(12), 0, px(8))
    masteryTitle.Text = "MASTERY I"

    local masteryXP = Instance.new("TextLabel", masteryPanel)
    masteryXP.Name = "XP"
    masteryXP.BackgroundTransparency = 1
    masteryXP.Font = Enum.Font.GothamBold
    masteryXP.TextColor3 = WHITE
    masteryXP.TextSize = px(13)
    masteryXP.TextXAlignment = Enum.TextXAlignment.Left
    masteryXP.Size = UDim2.new(1, -px(24), 0, px(18))
    masteryXP.Position = UDim2.new(0, px(12), 0, px(34))
    masteryXP.Text = "0 / 25 XP"

    local masteryBarBg = Instance.new("Frame", masteryPanel)
    masteryBarBg.Name = "ProgressBg"
    masteryBarBg.BackgroundColor3 = Color3.fromRGB(11, 12, 20)
    masteryBarBg.BorderSizePixel = 0
    masteryBarBg.Size = UDim2.new(1, -px(24), 0, px(10))
    masteryBarBg.Position = UDim2.new(0, px(12), 0, px(56))
    Instance.new("UICorner", masteryBarBg).CornerRadius = UDim.new(0, px(5))

    local masteryBarFill = Instance.new("Frame", masteryBarBg)
    masteryBarFill.Name = "Fill"
    masteryBarFill.BackgroundColor3 = GOLD
    masteryBarFill.BorderSizePixel = 0
    masteryBarFill.Size = UDim2.new(0, 0, 1, 0)
    Instance.new("UICorner", masteryBarFill).CornerRadius = UDim.new(0, px(4))

    local masteryElims = Instance.new("TextLabel", masteryPanel)
    masteryElims.Name = "Eliminations"
    masteryElims.BackgroundColor3 = Color3.fromRGB(30, 33, 50)
    masteryElims.BackgroundTransparency = 0.05
    masteryElims.Font = Enum.Font.GothamBold
    masteryElims.TextColor3 = WHITE
    masteryElims.TextSize = px(12)
    masteryElims.TextXAlignment = Enum.TextXAlignment.Center
    masteryElims.TextYAlignment = Enum.TextYAlignment.Center
    masteryElims.Size = UDim2.new(0.48, -px(3), 0, px(30))
    masteryElims.Position = UDim2.new(0, px(12), 0, px(74))
    masteryElims.Text = "ELIMS 0"
    Instance.new("UICorner", masteryElims).CornerRadius = UDim.new(0, px(6))

    local masteryDamage = Instance.new("TextLabel", masteryPanel)
    masteryDamage.Name = "Damage"
    masteryDamage.BackgroundColor3 = Color3.fromRGB(30, 33, 50)
    masteryDamage.BackgroundTransparency = 0.05
    masteryDamage.Font = Enum.Font.GothamBold
    masteryDamage.TextColor3 = WHITE
    masteryDamage.TextSize = px(12)
    masteryDamage.TextXAlignment = Enum.TextXAlignment.Center
    masteryDamage.TextYAlignment = Enum.TextYAlignment.Center
    masteryDamage.Size = UDim2.new(0.48, -px(3), 0, px(30))
    masteryDamage.AnchorPoint = Vector2.new(1, 0)
    masteryDamage.Position = UDim2.new(1, -px(12), 0, px(74))
    masteryDamage.Text = "BONUS +0.0 DMG"
    Instance.new("UICorner", masteryDamage).CornerRadius = UDim.new(0, px(6))

    -- Instance ID (developer-only)
    local detailInstanceId = Instance.new("TextLabel", detailContent)
    detailInstanceId.Name = "InstanceId"
    detailInstanceId.BackgroundTransparency = 1
    detailInstanceId.Font = Enum.Font.Code
    detailInstanceId.TextColor3 = DIM_TEXT
    detailInstanceId.TextSize = px(11)
    detailInstanceId.TextXAlignment = Enum.TextXAlignment.Center
    detailInstanceId.Size = UDim2.new(1, 0, 0, px(16))
    detailInstanceId.Position = UDim2.new(0, 0, 0, px(452))
    detailInstanceId.Visible = false

    -- Equip button (only place weapons can be equipped)
    local detailEquipBtn = Instance.new("TextButton", detailContent)
    detailEquipBtn.Name = "EquipBtn"
    detailEquipBtn.AutoButtonColor = false
    detailEquipBtn.BackgroundColor3 = BTN_BG
    detailEquipBtn.Font = Enum.Font.GothamBold
    detailEquipBtn.Text = "EQUIP"
    detailEquipBtn.TextColor3 = WHITE
    detailEquipBtn.TextTransparency = 0
    detailEquipBtn.TextSize = px(22)
    detailEquipBtn.Size = UDim2.new(0.88, 0, 0, px(48))
    detailEquipBtn.AnchorPoint = Vector2.new(0.5, 1)
    detailEquipBtn.Position = UDim2.new(0.5, 0, 1, -px(4))
    Instance.new("UICorner", detailEquipBtn).CornerRadius = UDim.new(0, px(10))
    local equipStroke = Instance.new("UIStroke", detailEquipBtn)
    equipStroke.Color = Color3.fromRGB(0, 0, 0); equipStroke.Thickness = 1.5; equipStroke.Transparency = 0.15
    -- Action buttons row (Favorite + Salvage) above equip button
    local actionRow = Instance.new("Frame", detailContent)
    actionRow.Name = "ActionRow"
    actionRow.BackgroundTransparency = 1
    actionRow.Size = UDim2.new(0.88, 0, 0, px(42))
    actionRow.AnchorPoint = Vector2.new(0.5, 1)
    actionRow.Position = UDim2.new(0.5, 0, 1, -px(60))

    -- Salvage value preview label (shown above action row for salvageable items)
    local shardWidgets = {}

    shardWidgets.salvageValueRow, shardWidgets.salvageValueLabel = createShardRewardRow(
        detailContent,
        "SalvageValuePreview",
        UDim2.new(0.88, 0, 0, px(24)),
        Vector2.new(0.5, 1),
        UDim2.new(0.5, 0, 1, -px(114)),
        px(18),
        getShardCurrencyImage(),
        nil,
        px
    )
    addBlackTextStroke(shardWidgets.salvageValueLabel)

    -- Feedback label (transient success/error message after salvage)
    local salvageFeedback = Instance.new("TextLabel", detailContent)
    salvageFeedback.Name = "SalvageFeedback"
    salvageFeedback.BackgroundColor3 = SHARD_UI_FEEDBACK_BG
    salvageFeedback.BackgroundTransparency = 0.15
    salvageFeedback.Font = Enum.Font.GothamBold
    salvageFeedback.TextColor3 = SHARD_UI_ACCENT
    salvageFeedback.TextSize = px(14)
    salvageFeedback.TextWrapped = true
    salvageFeedback.TextXAlignment = Enum.TextXAlignment.Center
    salvageFeedback.Size = UDim2.new(0.88, 0, 0, px(28))
    salvageFeedback.AnchorPoint = Vector2.new(0.5, 0.5)
    salvageFeedback.Position = UDim2.new(0.5, 0, 0.5, px(20))
    salvageFeedback.ZIndex = 55
    salvageFeedback.Visible = false
    Instance.new("UICorner", salvageFeedback).CornerRadius = UDim.new(0, px(6))

    local function showSalvageFeedback(text, color, duration)
        salvageFeedback.Text = text
        salvageFeedback.TextColor3 = color or SHARD_UI_ACCENT
        salvageFeedback.BackgroundColor3 = color == RED_TEXT and Color3.fromRGB(50, 20, 20) or SHARD_UI_FEEDBACK_BG
        salvageFeedback.Visible = true
        task.delay(duration or 2.5, function()
            if salvageFeedback and salvageFeedback.Parent then
                salvageFeedback.Visible = false
            end
        end)
    end
    actionRow.AnchorPoint = Vector2.new(0.5, 1)
    actionRow.Position = UDim2.new(0.5, 0, 1, -px(60))

    -- Favorite button (yellow star)
    local FAV_YELLOW = Color3.fromRGB(255, 210, 50)
    local FAV_DIM    = Color3.fromRGB(100, 100, 120)

    local favBtn = Instance.new("TextButton", actionRow)
    favBtn.Name = "FavoriteBtn"
    favBtn.AutoButtonColor = false
    favBtn.BackgroundColor3 = Color3.fromRGB(36, 38, 56)
    favBtn.Font = Enum.Font.GothamBold
    favBtn.Text = "\u{2606}"  -- empty star ☆
    favBtn.TextColor3 = FAV_DIM
    favBtn.TextSize = px(24)
    favBtn.Size = UDim2.new(0.48, 0, 1, 0)
    favBtn.Position = UDim2.new(0, 0, 0, 0)
    Instance.new("UICorner", favBtn).CornerRadius = UDim.new(0, px(8))
    local favStroke = Instance.new("UIStroke", favBtn)
    favStroke.Color = FAV_DIM; favStroke.Thickness = 1.2; favStroke.Transparency = 0.3

    -- Salvage button (orange – replaces old Discard)

    local discardBtn = Instance.new("TextButton", actionRow)
    discardBtn.Name = "SalvageBtn"
    discardBtn.AutoButtonColor = false
    discardBtn.BackgroundColor3 = SHARD_UI_BG
    discardBtn.Font = Enum.Font.GothamBold
    discardBtn.Text = "DISMANTLE"
    discardBtn.TextColor3 = SHARD_UI_ACCENT
    discardBtn.TextSize = px(17)
    discardBtn.Size = UDim2.new(0.48, 0, 1, 0)
    discardBtn.AnchorPoint = Vector2.new(1, 0)
    discardBtn.Position = UDim2.new(1, 0, 0, 0)
    Instance.new("UICorner", discardBtn).CornerRadius = UDim.new(0, px(8))
    local discardStroke = Instance.new("UIStroke", discardBtn)
    discardStroke.Color = SHARD_UI_DIM; discardStroke.Thickness = 1.2; discardStroke.Transparency = 0.3

    -- Salvage confirmation overlay
    local confirmOverlay = Instance.new("Frame", detailsPanel)
    confirmOverlay.Name = "ConfirmOverlay"
    confirmOverlay.BackgroundColor3 = SHARD_UI_OVERLAY_BG
    confirmOverlay.BackgroundTransparency = 0.08
    confirmOverlay.Size = UDim2.new(1, 0, 1, 0)
    confirmOverlay.ZIndex = 50
    confirmOverlay.Visible = false
    Instance.new("UICorner", confirmOverlay).CornerRadius = UDim.new(0, px(12))

    local confirmBox = Instance.new("Frame", confirmOverlay)
    confirmBox.Name = "ConfirmBox"
    confirmBox.BackgroundColor3 = SHARD_UI_CONFIRM_BG
    confirmBox.Size = UDim2.new(0.88, 0, 0, px(160))
    confirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
    confirmBox.Position = UDim2.new(0.5, 0, 0.5, 0)
    confirmBox.ZIndex = 51
    Instance.new("UICorner", confirmBox).CornerRadius = UDim.new(0, px(10))
    local cbStroke = Instance.new("UIStroke", confirmBox)
    cbStroke.Color = SHARD_UI_ACCENT; cbStroke.Thickness = 1.5; cbStroke.Transparency = 0.3

    local confirmTitle = Instance.new("TextLabel", confirmBox)
    confirmTitle.BackgroundTransparency = 1
    confirmTitle.Font = Enum.Font.GothamBold
    confirmTitle.Text = "Dismantle Weapon?"
    confirmTitle.TextColor3 = SHARD_UI_ACCENT
    confirmTitle.TextSize = px(18)
    confirmTitle.Size = UDim2.new(1, 0, 0, px(28))
    confirmTitle.Position = UDim2.new(0, 0, 0, px(16))
    confirmTitle.TextXAlignment = Enum.TextXAlignment.Center
    confirmTitle.ZIndex = 52

    shardWidgets.confirmRewardRow, shardWidgets.confirmRewardLabel = createShardRewardRow(
        confirmBox,
        "RewardRow",
        UDim2.new(0.88, 0, 0, px(24)),
        Vector2.new(0.5, 0),
        UDim2.new(0.5, 0, 0, px(48)),
        px(16),
        getShardCurrencyImage(),
        52,
        px
    )

    local confirmDesc = Instance.new("TextLabel", confirmBox)
    confirmDesc.Name = "Desc"
    confirmDesc.BackgroundTransparency = 1
    confirmDesc.Font = Enum.Font.GothamMedium
    confirmDesc.Text = "This action cannot be undone."
    confirmDesc.TextColor3 = DIM_TEXT
    confirmDesc.TextSize = px(14)
    confirmDesc.TextWrapped = true
    confirmDesc.Size = UDim2.new(0.85, 0, 0, px(36))
    confirmDesc.AnchorPoint = Vector2.new(0.5, 0)
    confirmDesc.Position = UDim2.new(0.5, 0, 0, px(76))
    confirmDesc.TextXAlignment = Enum.TextXAlignment.Center
    confirmDesc.TextYAlignment = Enum.TextYAlignment.Top
    confirmDesc.ZIndex = 52

    local confirmYes = Instance.new("TextButton", confirmBox)
    confirmYes.Name = "YesBtn"
    confirmYes.AutoButtonColor = false
    confirmYes.BackgroundColor3 = SHARD_UI_ACCENT
    confirmYes.Font = Enum.Font.GothamBold
    confirmYes.Text = "DISMANTLE"
    confirmYes.TextColor3 = WHITE
    confirmYes.TextTransparency = 0
    confirmYes.TextSize = px(14)
    confirmYes.Size = UDim2.new(0.42, 0, 0, px(36))
    confirmYes.AnchorPoint = Vector2.new(0, 1)
    confirmYes.Position = UDim2.new(0.06, 0, 1, -px(14))
    confirmYes.ZIndex = 52
    Instance.new("UICorner", confirmYes).CornerRadius = UDim.new(0, px(8))
    local confirmYesStroke = Instance.new("UIStroke", confirmYes)
    confirmYesStroke.Color = Color3.fromRGB(0, 0, 0); confirmYesStroke.Thickness = 1.5; confirmYesStroke.Transparency = 0.15

    local confirmNo = Instance.new("TextButton", confirmBox)
    confirmNo.Name = "NoBtn"
    confirmNo.AutoButtonColor = false
    confirmNo.BackgroundColor3 = BTN_BG
    confirmNo.Font = Enum.Font.GothamBold
    confirmNo.Text = "CANCEL"
    confirmNo.TextColor3 = WHITE
    confirmNo.TextTransparency = 0
    confirmNo.TextSize = px(14)
    confirmNo.Size = UDim2.new(0.42, 0, 0, px(36))
    confirmNo.AnchorPoint = Vector2.new(1, 1)
    confirmNo.Position = UDim2.new(0.94, 0, 1, -px(14))
    confirmNo.ZIndex = 52
    Instance.new("UICorner", confirmNo).CornerRadius = UDim.new(0, px(8))
    local confirmNoStroke = Instance.new("UIStroke", confirmNo)
    confirmNoStroke.Color = Color3.fromRGB(0, 0, 0); confirmNoStroke.Thickness = 1.5; confirmNoStroke.Transparency = 0.15

    local CONFIRM_BOX_BASE_HEIGHT = px(160)
    local CONFIRM_DESC_WIDTH_SCALE = 0.85
    local CONFIRM_DESC_MIN_HEIGHT = px(36)
    local CONFIRM_REWARD_TOP = px(48)
    local CONFIRM_REWARD_HEIGHT = px(24)
    local CONFIRM_DESC_TOP = px(76)
    local CONFIRM_DESC_TOP_NO_REWARD = px(52)
    local CONFIRM_DESC_EXTRA_PADDING = px(6)
    local CONFIRM_DESC_TO_BUTTON_GAP = px(12)
    local CONFIRM_BUTTON_HEIGHT = px(36)
    local CONFIRM_BUTTON_BOTTOM_MARGIN = px(14)

    local function updateConfirmBoxLayout()
        local descTop = shardWidgets.confirmRewardRow.Visible and CONFIRM_DESC_TOP or CONFIRM_DESC_TOP_NO_REWARD
        shardWidgets.confirmRewardRow.Position = UDim2.new(0.5, 0, 0, CONFIRM_REWARD_TOP)
        shardWidgets.confirmRewardRow.Size = UDim2.new(0.88, 0, 0, CONFIRM_REWARD_HEIGHT)
        confirmDesc.Position = UDim2.new(0.5, 0, 0, descTop)

        local descWidth = math.floor(confirmBox.AbsoluteSize.X * CONFIRM_DESC_WIDTH_SCALE)
        if descWidth <= 0 then
            descWidth = math.floor(detailsPanel.AbsoluteSize.X * 0.88 * CONFIRM_DESC_WIDTH_SCALE)
        end
        descWidth = math.max(descWidth, 1)

        local measuredDesc = TextService:GetTextSize(
            confirmDesc.Text or "",
            confirmDesc.TextSize,
            confirmDesc.Font,
            Vector2.new(descWidth, 1000)
        )
        local descHeight = math.max(CONFIRM_DESC_MIN_HEIGHT, measuredDesc.Y + CONFIRM_DESC_EXTRA_PADDING)
        confirmDesc.Size = UDim2.new(CONFIRM_DESC_WIDTH_SCALE, 0, 0, descHeight)

        local requiredHeight = descTop
            + descHeight
            + CONFIRM_DESC_TO_BUTTON_GAP
            + CONFIRM_BUTTON_HEIGHT
            + CONFIRM_BUTTON_BOTTOM_MARGIN
        confirmBox.Size = UDim2.new(0.88, 0, 0, math.max(CONFIRM_BOX_BASE_HEIGHT, requiredHeight))
    end

    task.defer(updateConfirmBoxLayout)

    -- ══════════════════════════════════════════════════════════════════════
    --  SELECTION & EQUIP STATE
    -- ══════════════════════════════════════════════════════════════════════
    local selectedItem  = nil
    local selectedCard  = nil
    local allCardRefs   = {}  -- id -> { card, stroke, itemData }

    local function getMasteryData(itemData)
        if itemData and type(itemData.mastery) == "table" then
            return itemData.mastery
        end
        return {
            level = 1,
            title = "I",
            romanNumeral = "I",
            xp = 0,
            progress = 0,
            nextLevel = 2,
            currentLevelXP = 0,
            nextLevelXP = 25,
            eliminations = 0,
            mobKills = 0,
            captures = 0,
            damage = 0,
            damageBonus = 0,
            maxed = false,
        }
    end

    local function updateMasteryPanel(itemData)
        if not itemData or not itemData.isInstance then
            masteryPanel.Visible = false
            return
        end

        local mastery = getMasteryData(itemData)
        local level = math.max(1, math.floor(tonumber(mastery.level) or 1))
        local romanNumeral = getMasteryRoman(level, mastery.romanNumeral or mastery.title)
        local xp = math.max(0, tonumber(mastery.xp) or 0)
        local progress = math.clamp(tonumber(mastery.progress) or 0, 0, 1)
        local nextLevelXP = math.max(0, tonumber(mastery.nextLevelXP) or 25)
        local damageBonus = math.max(0, tonumber(mastery.damageBonus) or 0)

        masteryPanel.Visible = true
        masteryTitle.Text = "MASTERY " .. romanNumeral

        if mastery.maxed == true then
            masteryXP.Text = formatMasteryXP(xp) .. " XP TOTAL"
            masteryBarFill.Size = UDim2.new(1, 0, 1, 0)
        else
            masteryXP.Text = formatMasteryXP(xp) .. " / " .. formatMasteryXP(nextLevelXP) .. " XP"
            masteryBarFill.Size = UDim2.new(progress, 0, 1, 0)
        end

        masteryElims.Text = "ELIMS " .. formatWholeNumber(mastery.eliminations or 0)
        masteryDamage.Text = "BONUS " .. formatMasteryBonus(damageBonus)
    end

    ---------------------------------------------------------------------------
    -- updateEquipButton(itemData)
    ---------------------------------------------------------------------------
    local function updateActionButtons(itemData)
        -- Favorite & Salvage visibility: hide for starter/non-instance weapons
        local isStarter = itemData and itemData.source == "Starter"
        local isInstance = itemData and itemData.isInstance
        local showActions = itemData and isInstance and not isStarter

        actionRow.Visible = showActions == true
        favBtn.Visible = showActions == true
        discardBtn.Visible = showActions == true

        if itemData and showActions then
            local fav = itemData.favorited == true
            favBtn.Text = fav and "\u{2605}" or "\u{2606}" -- ★ or ☆
            favBtn.TextColor3 = fav and FAV_YELLOW or FAV_DIM
            favStroke.Color = fav and FAV_YELLOW or FAV_DIM
        end

        -- Salvage eligibility: equipped or favorited items can't be salvaged
        local canSalvage = showActions and itemData
            and not isItemEquipped(itemData)
            and itemData.favorited ~= true
        if itemData and not canSalvage and showActions then
            discardBtn.BackgroundColor3 = DISABLED_BG
            discardBtn.TextColor3 = DIM_TEXT
            discardStroke.Color = Color3.fromRGB(0, 0, 0)
            discardStroke.Transparency = 0.15
            -- Show reason
            if isItemEquipped(itemData) then
                discardBtn.Text = "EQUIPPED"
            elseif itemData.favorited == true then
                discardBtn.Text = "FAVORITED"
            else
                discardBtn.Text = "DISMANTLE"
            end
        elseif showActions then
            discardBtn.BackgroundColor3 = SHARD_UI_BG
            discardBtn.TextColor3 = SHARD_UI_ACCENT
            discardStroke.Color = Color3.fromRGB(0, 0, 0)
            discardStroke.Transparency = 0.15
            discardBtn.Text = "DISMANTLE"
        end

        -- Salvage value preview
        if canSalvage and SalvageConfig and itemData.rarity then
            local val = getSalvageValueForItem(itemData)
            if val and val > 0 then
                shardWidgets.salvageValueLabel.Text = "Yield: " .. tostring(val)
                shardWidgets.salvageValueRow.Visible = true
            else
                shardWidgets.salvageValueRow.Visible = false
            end
        else
            shardWidgets.salvageValueRow.Visible = false
        end
    end

    local function updateEquipButton(itemData)
        if not itemData then
            detailEquipBtn.Text = "EQUIP"
            detailEquipBtn.BackgroundColor3 = DISABLED_BG
            detailEquipBtn.TextColor3 = DIM_TEXT
            equipStroke.Color = Color3.fromRGB(0, 0, 0)
            equipStroke.Transparency = 0.15
            actionRow.Visible = false
            shardWidgets.salvageValueRow.Visible = false
            return
        end
        if isItemEquipped(itemData) then
            detailEquipBtn.Text = "\u{2714} EQUIPPED"
            detailEquipBtn.BackgroundColor3 = DISABLED_BG
            detailEquipBtn.TextColor3 = GREEN_GLOW
            equipStroke.Color = Color3.fromRGB(0, 0, 0)
            equipStroke.Transparency = 0.15
        else
            detailEquipBtn.Text = "EQUIP"
            detailEquipBtn.BackgroundColor3 = BTN_BG
            detailEquipBtn.TextColor3 = WHITE
            equipStroke.Color = Color3.fromRGB(0, 0, 0)
            equipStroke.Transparency = 0.15
        end
        updateActionButtons(itemData)
    end

    ---------------------------------------------------------------------------
    -- refreshEquippedIndicators()
    ---------------------------------------------------------------------------
    local function refreshEquippedIndicators()
        for _, ref in pairs(allCardRefs) do
            local equipped = isItemEquipped(ref.itemData)
            local bar = ref.card:FindFirstChild("EquippedBar")
            if bar then bar.Visible = equipped end
            -- Reset background to stored card color (vivid for weapons)
            ref.card.BackgroundColor3 = ref.bgColor or getRarityBgColor(ref.itemData.rarity)
            -- Update stroke: keep gold for the currently selected card,
            -- green for equipped, otherwise border color
            local isSelected = selectedItem and selectedItem.id == ref.itemData.id
            if not isSelected then
                ref.stroke.Color = equipped and GREEN_GLOW or (ref.borderColor or getRarityColor(ref.itemData.rarity))
                ref.stroke.Thickness = ref.bgColor and 2.0 or 1.4
            end
        end
    end

    ---------------------------------------------------------------------------
    -- setSelectedItem(itemData)
    ---------------------------------------------------------------------------
    local function setSelectedItem(itemData)
        -- Remove highlight from old card
        if selectedCard and selectedItem then
            local oldRef = allCardRefs[selectedItem.id]
            if oldRef then
                local eq = isItemEquipped(selectedItem)
                oldRef.stroke.Color = eq and GREEN_GLOW or (oldRef.borderColor or getRarityColor(selectedItem.rarity))
                oldRef.stroke.Thickness = oldRef.bgColor and 2.0 or 1.4
                oldRef.card.BackgroundColor3 = oldRef.bgColor or getRarityBgColor(selectedItem.rarity)
            end
        end

        selectedItem = itemData

        if not itemData then
            detailPlaceholder.Visible = true
            detailContent.Visible = false
            detailsPanel.BackgroundColor3 = CARD_BG
            dpStroke.Color = CARD_STROKE
            detailImageBg.BackgroundColor3 = RARITY_BG_COLORS.Common
            imgBgStroke.Color = RARITY_COLORS.Common
            updateMasteryPanel(nil)
            selectedCard = nil
            return
        end

        detailPlaceholder.Visible = false
        detailContent.Visible = true

        -- Highlight new card
        local newRef = allCardRefs[itemData.id]
        if newRef then
            selectedCard = newRef.card
            newRef.stroke.Color = GOLD
            newRef.stroke.Thickness = 2.5
        end

        -- Update panel
        local rarColor = getRarityColor(itemData.rarity)
        local rarBg    = getRarityBgColor(itemData.rarity)
        local cardBg   = WEAPON_CARD_BG[itemData.rarity] or WEAPON_CARD_BG.Common
        local borderC  = WEAPON_CARD_BORDER[itemData.rarity] or WEAPON_CARD_BORDER.Common

        detailsPanel.BackgroundColor3 = accentPanelColor(cardBg, 0.18)
        dpStroke.Color = borderC
        detailImageBg.BackgroundColor3 = cardBg
        imgBgStroke.Color = borderC

        detailImage.Image = ""
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(itemData.name))
                if img and #img > 0 then detailImage.Image = img end
            end
        end)

        detailName.Text = itemData.name
        detailRarity.Text = itemData.rarity or "Common"
        detailRarity.TextColor3 = rarColor
        detailType.Text = (itemData.category == "Melee") and "Melee Weapon" or "Ranged Weapon"

        -- SIZE ROLL SYSTEM — show size info in detail panel (coloured tier + white %)
        local pct = itemData.sizePercent or 100
        local tier = itemData.sizeTier or "Normal"
        local detailSizeText = tier .. "  " .. tostring(math.floor(pct)) .. "%"
        if EnchantTextStyler then
            EnchantTextStyler.ApplySize(detailSize, tier, detailSizeText)
        else
            detailSize.Text = detailSizeText
        end

        -- ENCHANT SYSTEM — show enchant name in detail panel
        local itemenchantName = itemData.enchantName or ""
        if EnchantTextStyler then
            EnchantTextStyler.Apply(detailEnchant, itemenchantName ~= "" and itemenchantName or nil)
        end

        if isDeveloper and itemData.instanceId then
            detailInstanceId.Text = itemData.instanceId
            detailInstanceId.Visible = true
        else
            detailInstanceId.Visible = false
        end

        updateMasteryPanel(itemData)

        updateEquipButton(itemData)
    end

    ---------------------------------------------------------------------------
    -- createWeaponCard(itemData)  –  compact square card for the grid
    ---------------------------------------------------------------------------
    local function createWeaponCard(itemData)
        local rarity   = itemData.rarity or "Common"
        local rarColor = getRarityColor(rarity)
        local cardBg   = WEAPON_CARD_BG[rarity] or WEAPON_CARD_BG.Common
        local borderC  = WEAPON_CARD_BORDER[rarity] or WEAPON_CARD_BORDER.Common
        local equipped = isItemEquipped(itemData)

        -- ── Card container (fills grid cell) ────────────────────────────
        local card = Instance.new("Frame")
        card.Name = "Card_" .. tostring(itemData.id)
        card.BackgroundColor3 = cardBg
        card.Size = UDim2.new(1, 0, 1, 0)
        card.ClipsDescendants = true
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(10))

        local stroke = Instance.new("UIStroke", card)
        stroke.Color = equipped and GREEN_GLOW or borderC
        stroke.Thickness = 2.0; stroke.Transparency = 0.1

        -- ── SECTION 1: Weapon name (top ~19% of card) ────────────────────
        -- Fixed TextSize so every card title renders at the same size.
        -- TextWrapped = true allows two-line fallback for longer names.
        -- No TextScaled — short names stay at the shared base size.
        local NAME_TEXT_SIZE = math.max(9, math.floor(px(18)))
        local nameLabel = Instance.new("TextLabel", card)
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = WHITE
        nameLabel.TextScaled = false
        nameLabel.TextWrapped = true
        nameLabel.RichText = false
        nameLabel.TextSize = NAME_TEXT_SIZE
        nameLabel.Size = UDim2.new(1, -px(6), 0.19, 0)
        nameLabel.Position = UDim2.new(0, px(3), 0.01, 0)
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.Text = itemData.name
        local nameStroke = Instance.new("UIStroke", nameLabel)
        nameStroke.Color = Color3.fromRGB(0, 0, 0)
        nameStroke.Thickness = 1.5; nameStroke.Transparency = 0.15

        -- ── SECTION 2: enchant tag (right under name, centered, fixed size) ──────
        local enchantName = itemData.enchantName or ""
        if enchantName ~= "" then
            local enchantW = math.floor(px(68))
            local enchantH = math.floor(px(17))

            local enchantBg = Instance.new("Frame", card)
            enchantBg.Name = "EnchantTagBg"
            enchantBg.BackgroundTransparency = 1
            enchantBg.BorderSizePixel = 0
            enchantBg.Size = UDim2.new(0, enchantW, 0, enchantH)
            enchantBg.AnchorPoint = Vector2.new(0.5, 0)
            enchantBg.Position = UDim2.new(0.5, 0, 0.17, 0)
            enchantBg.ZIndex = 6
            enchantBg.ClipsDescendants = false
            local pCorner = Instance.new("UICorner", enchantBg)
            pCorner.CornerRadius = UDim.new(0, math.max(0, math.floor(enchantH / 2)))

            local enchantLabel = Instance.new("TextLabel", enchantBg)
            enchantLabel.Name = "EnchantTag"
            enchantLabel.BackgroundTransparency = 1
            enchantLabel.Font = Enum.Font.GothamBold
            enchantLabel.TextScaled = true
            enchantLabel.Size = UDim2.new(1, -px(4), 1, 0)
            enchantLabel.AnchorPoint = Vector2.new(0.5, 0.5)
            enchantLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
            enchantLabel.TextXAlignment = Enum.TextXAlignment.Center
            enchantLabel.TextYAlignment = Enum.TextYAlignment.Center
            enchantLabel.ZIndex = 7
            if EnchantTextStyler then
                EnchantTextStyler.Apply(enchantLabel, enchantName)
            end
            local pSizeC = Instance.new("UITextSizeConstraint", enchantLabel)
            pSizeC.MinTextSize = 6; pSizeC.MaxTextSize = 13
        end

        -- ── SECTION 3: Weapon icon (middle 44% of card) ─────────────────
        -- Positioned via Scale so it stays proportional at any resolution.
        local thumb = Instance.new("ImageLabel", card)
        thumb.Name = "Thumb"
        thumb.BackgroundTransparency = 1
        thumb.Size = UDim2.new(0.56, 0, 0.44, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0)
        thumb.Position = UDim2.new(0.5, 0, 0.30, 0)
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.Image = ""
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(itemData.name))
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        -- ── SECTION 4: Size tier tag (bottom-left) + Size percent (bottom-right) ──
        local pct  = itemData.sizePercent or 100
        local tier = itemData.sizeTier or "Normal"
        local isNormalTier = string.lower(tostring(tier)) == "normal"

        local function applyInventoryNormalSizeStyle(label, strokeTransparency)
            label.Font = Enum.Font.GothamBold
            pcall(function()
                label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
            end)
            label.TextColor3 = WHITE

            local outline = label:FindFirstChildOfClass("UIStroke")
            if not outline then
                outline = Instance.new("UIStroke")
                outline.Parent = label
            end
            outline.Color = Color3.fromRGB(0, 0, 0)
            outline.Thickness = 1.6
            outline.Transparency = strokeTransparency or 0.1
        end

        -- Size tier pill tag — bottom-left corner (fixed size, text scales to fit)
        do
            local tierW = math.floor(px(isNormalTier and 62 or 46))
            local tierH = math.floor(px(isNormalTier and 22 or 20))

            local tierBg = Instance.new("Frame", card)
            tierBg.Name = "SizeTierBg"
            tierBg.BackgroundTransparency = 1
            tierBg.BorderSizePixel = 0
            tierBg.Size = UDim2.new(0, tierW, 0, tierH)
            tierBg.AnchorPoint = Vector2.new(0, 1)
            tierBg.Position = UDim2.new(0, px(4), 0.96, 0)
            tierBg.ZIndex = 6
            tierBg.ClipsDescendants = false
            local corner = Instance.new("UICorner", tierBg)
            corner.CornerRadius = UDim.new(0, math.max(0, math.floor(tierH / 2)))

            local tierLabel = Instance.new("TextLabel", tierBg)
            tierLabel.Name = "SizeTier"
            tierLabel.BackgroundTransparency = 1
            tierLabel.Font = Enum.Font.GothamBold
            tierLabel.TextScaled = true
            tierLabel.Size = UDim2.new(1, -px(4), 1, 0)
            tierLabel.AnchorPoint = Vector2.new(0.5, 0.5)
            tierLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
            tierLabel.TextXAlignment = Enum.TextXAlignment.Center
            tierLabel.TextYAlignment = Enum.TextYAlignment.Center
            tierLabel.Text = tier
            tierLabel.ZIndex = 7
            local tSizeC = Instance.new("UITextSizeConstraint", tierLabel)
            tSizeC.MinTextSize = 6; tSizeC.MaxTextSize = isNormalTier and 20 or 18
            if EnchantTextStyler then
                EnchantTextStyler.ApplySize(tierLabel, tier, tier)
            end
            if isNormalTier then
                applyInventoryNormalSizeStyle(tierLabel, 0.08)
                tierLabel.Text = "Normal"
            end
        end

        -- Size percent label — bottom-right corner
        local sizeLabel = Instance.new("TextLabel", card)
        sizeLabel.Name = "SizePercent"
        sizeLabel.BackgroundTransparency = 1
        sizeLabel.Font = Enum.Font.GothamBold
        sizeLabel.TextScaled = true
        sizeLabel.Size = UDim2.new(0.45, 0, 0.12, 0)
        sizeLabel.AnchorPoint = Vector2.new(1, 1)
        sizeLabel.Position = UDim2.new(1, -px(4), 0.96, 0)
        sizeLabel.TextXAlignment = Enum.TextXAlignment.Right
        local pctConstraint = Instance.new("UITextSizeConstraint", sizeLabel)
        pctConstraint.MinTextSize = 8
        pctConstraint.MaxTextSize = isNormalTier and 20 or 18
        local sizePercentText = tostring(math.floor(pct)) .. "%"
        if EnchantTextStyler then
            EnchantTextStyler.ApplySize(sizeLabel, tier, sizePercentText)
        else
            sizeLabel.Text = sizePercentText
        end
        if isNormalTier then
            applyInventoryNormalSizeStyle(sizeLabel, 0.08)
        end

        -- ── Equipped bar indicator (green bottom strip) ─────────────────
        local eqBar = Instance.new("Frame", card)
        eqBar.Name = "EquippedBar"
        eqBar.BackgroundColor3 = GREEN_GLOW
        eqBar.Size = UDim2.new(1, 0, 0, 3)
        eqBar.AnchorPoint = Vector2.new(0, 1)
        eqBar.Position = UDim2.new(0, 0, 1, 0)
        eqBar.BorderSizePixel = 0; eqBar.ZIndex = 5
        eqBar.Visible = equipped

        -- ── Favorite star indicator (top-right corner) ──────────────────
        if itemData.favorited == true then
            local favStar = Instance.new("TextLabel", card)
            favStar.Name = "FavStar"
            favStar.BackgroundTransparency = 1
            favStar.Font = Enum.Font.GothamBold
            favStar.Text = "\u{2605}"  -- ★
            favStar.TextColor3 = Color3.fromRGB(255, 210, 50)
            favStar.TextScaled = true
            favStar.Size = UDim2.new(0.14, 0, 0.11, 0)
            favStar.AnchorPoint = Vector2.new(1, 0)
            favStar.Position = UDim2.new(0.97, 0, 0.02, 0)
            favStar.ZIndex = 8
            local favConstraint = Instance.new("UITextSizeConstraint", favStar)
            favConstraint.MinTextSize = 10
            favConstraint.MaxTextSize = 18
        end

        -- ── Store ref (bgColor/borderColor for selection/equip reset) ────
        allCardRefs[itemData.id] = { card = card, stroke = stroke, itemData = itemData, bgColor = cardBg, borderColor = borderC }

        -- ── Click to select ──────────────────────────────────────────────
        local clickBtn = Instance.new("TextButton", card)
        clickBtn.Name = "ClickArea"
        clickBtn.BackgroundTransparency = 1
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.Text = ""; clickBtn.ZIndex = 10

        clickBtn.MouseButton1Click:Connect(function()
            setSelectedItem(itemData)
        end)

        -- ── Hover ────────────────────────────────────────────────────────
        clickBtn.MouseEnter:Connect(function()
            if not selectedItem or selectedItem.id ~= itemData.id then
                TweenService:Create(card, TWEEN_QUICK, { BackgroundColor3 = Color3.new(
                    math.min(1, cardBg.R + 0.06),
                    math.min(1, cardBg.G + 0.06),
                    math.min(1, cardBg.B + 0.06)
                )}):Play()
            end
        end)
        clickBtn.MouseLeave:Connect(function()
            if not selectedItem or selectedItem.id ~= itemData.id then
                TweenService:Create(card, TWEEN_QUICK, {
                    BackgroundColor3 = cardBg
                }):Play()
            end
        end)

        return card
    end

    ---------------------------------------------------------------------------
    -- renderCategory(categoryName)  –  populate grid for Melee or Ranged
    ---------------------------------------------------------------------------
    local currentWeaponCategory = "Melee"

    local function renderCategory(categoryName)
        currentWeaponCategory = categoryName

        -- Clear grid contents (keep UIGridLayout & UIPadding)
        for _, child in ipairs(gridScroll:GetChildren()) do
            if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
        end
        table.clear(allCardRefs)

        -- Filter weapons for this category
        local filtered = {}
        for _, item in ipairs(allWeaponItems) do
            if item.category == categoryName then
                table.insert(filtered, item)
            end
        end

        -- Sort: favorited first, then rarity (rarest first), within rarity sort by sizePercent (larger first), alphabetical, Starter last
        local rarityPriority = { Legendary = 1, Epic = 2, Rare = 3, Uncommon = 4, Common = 5, Starter = 6 }
        table.sort(filtered, function(a, b)
            -- Starter weapons always go to the very end
            local aStarter = (a.source == "Starter") and 1 or 0
            local bStarter = (b.source == "Starter") and 1 or 0
            if aStarter ~= bStarter then return aStarter < bStarter end
            -- Favorited items come first
            local aFav = (a.favorited == true) and 0 or 1
            local bFav = (b.favorited == true) and 0 or 1
            if aFav ~= bFav then return aFav < bFav end
            -- Then by rarity
            local pa = rarityPriority[a.rarity] or 5
            local pb = rarityPriority[b.rarity] or 5
            if pa ~= pb then return pa < pb end
            -- Within same rarity, sort by sizePercent (larger first)
            local sa = tonumber(a.sizePercent) or 100
            local sb = tonumber(b.sizePercent) or 100
            if sa ~= sb then return sa > sb end
            return a.name < b.name
        end)

        if #filtered == 0 then
            gridScroll.Visible = false
            emptyState.Visible = true
            setSelectedItem(nil)
            return
        end

        gridScroll.Visible = true
        emptyState.Visible = false

        for i, item in ipairs(filtered) do
            local card = createWeaponCard(item)
            card.LayoutOrder = i
            card.Parent = gridScroll
        end

        -- Reset selection if it doesn't belong to this category
        if selectedItem and selectedItem.category ~= categoryName then
            setSelectedItem(nil)
        elseif selectedItem then
            local ref = allCardRefs[selectedItem.id]
            if ref then
                ref.stroke.Color = GOLD; ref.stroke.Thickness = 2.5
                updateEquipButton(selectedItem)
            else
                setSelectedItem(nil)
            end
        end

        -- Auto-select the equipped item if nothing is selected
        if not selectedItem then
            for _, item in ipairs(filtered) do
                if isItemEquipped(item) then
                    setSelectedItem(item)
                    break
                end
            end
        end

        refreshEquippedIndicators()
    end

    ---------------------------------------------------------------------------
    -- Equip button handler  (details panel — sole equip point for weapons)
    ---------------------------------------------------------------------------
    detailEquipBtn.MouseButton1Click:Connect(function()
        if not selectedItem then return end
        if isItemEquipped(selectedItem) then return end

        local itemData = selectedItem
        local toolName = itemData.isInstance and itemData.weaponName or itemData.name
        local cat      = itemData.category
        -- SIZE ROLL SYSTEM — send instanceId so server uses the correct size
        local equipInstanceId = itemData.isInstance and itemData.instanceId or nil

        if cat == "Ranged" then
            local remote = ReplicatedStorage:FindFirstChild("SetRangedTool")
            if remote and remote:IsA("RemoteEvent") then
                pcall(function() remote:FireServer(toolName, equipInstanceId) end)
            end
        else
            local remote = ReplicatedStorage:FindFirstChild("SetMeleeTool")
            if remote and remote:IsA("RemoteEvent") then
                pcall(function() remote:FireServer(toolName, equipInstanceId) end)
            end
        end

        equippedState[cat] = itemData.id
        -- SIZE ROLL SYSTEM — track equipped instanceId for correct matching on reopen
        equippedInstanceIds[cat] = itemData.isInstance and itemData.instanceId or nil
        if inventoryApi and inventoryApi.SetEquipped then
            pcall(function() inventoryApi:SetEquipped(cat, itemData.id) end)
        end

        updateEquipButton(itemData)
        refreshEquippedIndicators()

        -- Keep selected card gold-highlighted after equip
        local ref = allCardRefs[itemData.id]
        if ref then ref.stroke.Color = GOLD; ref.stroke.Thickness = 2.5 end

        -- Equip sound
        pcall(function()
            local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
            if soundsFolder then
                local s = soundsFolder:FindFirstChild("Equip")
                    or (soundsFolder:FindFirstChild("UI") and soundsFolder.UI:FindFirstChild("Equip"))
                if s and s:IsA("Sound") then
                    local clone = s:Clone(); clone.Parent = detailEquipBtn; clone:Play()
                    task.delay(clone.TimeLength + 0.1, function() pcall(function() clone:Destroy() end) end)
                end
            end
        end)
    end)

    -- Equip button hover
    detailEquipBtn.MouseEnter:Connect(function()
        if selectedItem and not isItemEquipped(selectedItem) then
            TweenService:Create(detailEquipBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
        end
    end)
    detailEquipBtn.MouseLeave:Connect(function()
        if selectedItem and not isItemEquipped(selectedItem) then
            TweenService:Create(detailEquipBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
        end
    end)

    ---------------------------------------------------------------------------
    -- Favorite button handler
    ---------------------------------------------------------------------------
    favBtn.MouseButton1Click:Connect(function()
        if not selectedItem then return end
        if not selectedItem.isInstance then return end
        if selectedItem.source == "Starter" then return end

        local instanceId = selectedItem.instanceId
        if not instanceId then return end

        local favoriteRF = ReplicatedStorage:FindFirstChild("FavoriteWeapon")
        if not favoriteRF or not favoriteRF:IsA("RemoteFunction") then return end

        local ok, newState = pcall(function()
            return favoriteRF:InvokeServer(instanceId)
        end)

        if ok then
            -- Update local item data
            selectedItem.favorited = (newState == true)
            -- Update the item in allWeaponItems too
            for _, item in ipairs(allWeaponItems) do
                if item.instanceId == instanceId then
                    item.favorited = selectedItem.favorited
                    break
                end
            end
            -- Update button visual
            updateActionButtons(selectedItem)
            -- Re-render grid to reflect new sort order
            renderCategory(currentWeaponCategory)
        end
    end)

    favBtn.MouseEnter:Connect(function()
        TweenService:Create(favBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(50, 52, 72)}):Play()
    end)
    favBtn.MouseLeave:Connect(function()
        TweenService:Create(favBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(36, 38, 56)}):Play()
    end)

    ---------------------------------------------------------------------------
    -- Salvage button handler  (opens confirmation prompt with value preview)
    ---------------------------------------------------------------------------
    local discardTarget = nil

    discardBtn.MouseButton1Click:Connect(function()
        if not selectedItem then return end
        if not selectedItem.isInstance then return end
        if selectedItem.source == "Starter" then return end
        if isItemEquipped(selectedItem) then return end
        if selectedItem.favorited == true then return end

        discardTarget = selectedItem

        -- Show salvage value preview from SalvageConfig (client-side read; server is authoritative)
        local salvageValue = 0
        if SalvageConfig and selectedItem.rarity then
            salvageValue = getSalvageValueForItem(selectedItem) or 0
        end
        confirmTitle.Text = "Dismantle " .. (selectedItem.name or "Weapon") .. "?"
        shardWidgets.confirmRewardRow.Visible = salvageValue > 0
        if salvageValue > 0 then
            shardWidgets.confirmRewardLabel.Text = "Dismantle for " .. tostring(salvageValue)
            confirmDesc.Text = "This action cannot be undone."
        else
            shardWidgets.confirmRewardLabel.Text = ""
            confirmDesc.Text = "Dismantle this weapon\nThis action cannot be undone."
        end
        confirmOverlay.Visible = true
        updateConfirmBoxLayout()
        task.defer(updateConfirmBoxLayout)
    end)

    discardBtn.MouseEnter:Connect(function()
        if selectedItem and not isItemEquipped(selectedItem) and selectedItem.source ~= "Starter" and selectedItem.favorited ~= true then
            TweenService:Create(discardBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(96, 56, 24)}):Play()
        end
    end)
    discardBtn.MouseLeave:Connect(function()
        TweenService:Create(discardBtn, TWEEN_QUICK, {BackgroundColor3 = SHARD_UI_BG}):Play()
    end)

    confirmNo.MouseButton1Click:Connect(function()
        confirmOverlay.Visible = false
        discardTarget = nil
    end)

    confirmYes.MouseButton1Click:Connect(function()
        confirmOverlay.Visible = false
        if not discardTarget then return end

        local instanceId = discardTarget.instanceId
        local itemName = discardTarget.name or "?"
        local cat = discardTarget.category
        if not instanceId then discardTarget = nil return end

        local salvageRF = ReplicatedStorage:FindFirstChild("SalvageWeapon")
        if not salvageRF or not salvageRF:IsA("RemoteFunction") then discardTarget = nil return end

        local ok, success, result = pcall(function()
            return salvageRF:InvokeServer(instanceId)
        end)

        if ok and success then
            -- Show success feedback with awarded amount
            local awarded = (type(result) == "table" and result.awarded) or 0
            if awarded > 0 then
                showSalvageFeedback("Dismantled for +" .. tostring(awarded) .. " Shards", SHARD_UI_ACCENT, 2.5)
            else
                showSalvageFeedback("Dismantled!", SHARD_UI_ACCENT, 2)
            end

            -- Update header salvage display immediately
            if type(result) == "table" and result.newBalance then
                pcall(function()
                    if _G.UpdateShopHeaderSalvage then _G.UpdateShopHeaderSalvage() end
                end)
            end

            -- Remove from local allWeaponItems
            for i, item in ipairs(allWeaponItems) do
                if item.instanceId == instanceId then
                    table.remove(allWeaponItems, i)
                    break
                end
            end
            -- Clear selection
            setSelectedItem(nil)
            -- Re-render
            renderCategory(currentWeaponCategory)
        else
            -- Salvage failed – show error feedback
            local reason = "Dismantle failed"
            if type(result) == "table" and result.reason then
                reason = result.reason
            end
            showSalvageFeedback(reason, RED_TEXT, 3)
        end

        discardTarget = nil
    end)

    -- ══════════════════════════════════════════════════════════════════════
    --  BOOSTS PAGE  (card grid + right-side details panel)
    -- ══════════════════════════════════════════════════════════════════════
    local boostsPage = Instance.new("Frame")
    boostsPage.Name = "BoostsPage"
    boostsPage.BackgroundTransparency = 1
    boostsPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    boostsPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    boostsPage.Visible = false
    boostsPage.Parent = root

    do -- Boosts scope block
        local function shallowCopy(source)
            local result = {}
            if type(source) ~= "table" then
                return result
            end
            for key, value in pairs(source) do
                result[key] = value
            end
            return result
        end

        local boostDefs = {}
        local potionRemoteSet = ensurePotionRemotes()
        local potionState = {
            isLoaded = false,
            potions = {},
            equippedPotionId = nil,
            cooldownEndsAt = 0,
            serverTime = 0,
        }

        local function getPotionCount(potionId)
            local potions = type(potionState.potions) == "table" and potionState.potions or {}
            local entry = potions[potionId]
            return math.max(0, math.floor(tonumber(type(entry) == "table" and entry.count or 0) or 0))
        end

        local function shouldShowPotionInPotionsInventory(potionDef)
            if PotionConfigGlobal and type(PotionConfigGlobal.ShouldShowInPotionsStall) == "function" then
                return PotionConfigGlobal.ShouldShowInPotionsStall(potionDef)
            end
            return type(potionDef) == "table" and potionDef.ShowInPotionsStall == true
        end

        local function shouldShowBoostInPotionsInventory(boostDef)
            if BoostConfig and type(BoostConfig.ShouldShowInPotionsStall) == "function" then
                return BoostConfig.ShouldShowInPotionsStall(boostDef)
            end
            return type(boostDef) == "table"
                and not boostDef.InstantUse
                and boostDef.ShowInPotionsStall == true
                and boostDef.RemovedFromShop ~= true
                and boostDef.Purchasable ~= false
        end

        if PotionConfigGlobal and type(PotionConfigGlobal.GetOrderedPotions) == "function" and potionRemoteSet then
            for _, potionDef in ipairs(PotionConfigGlobal.GetOrderedPotions()) do
                if shouldShowPotionInPotionsInventory(potionDef) then
                    table.insert(boostDefs, {
                        Id = potionDef.Id,
                        Kind = "potion",
                        DisplayName = potionDef.DisplayName,
                        Category = normalizePotionItemCategory(potionDef.Category, POTION_CATEGORY_BATTLE),
                        Description = potionDef.Description,
                        DetailText = potionDef.DetailText,
                        IconKey = potionDef.IconKey,
                        IconShape = "potion_bottle",
                        IconGlyph = potionDef.IconGlyph,
                        IconColor = potionDef.IconColor,
                        BadgeText = potionDef.BadgeText,
                        SortOrder = potionDef.SortOrder or -1000,
                    })
                end
            end
        end

        if BoostConfig and BoostConfig.Boosts then
            for _, def in ipairs(BoostConfig.Boosts) do
                if shouldShowBoostInPotionsInventory(def) then
                    local copied = shallowCopy(def)
                    copied.Kind = "boost"
                    copied.Category = normalizePotionItemCategory(copied.Category, POTION_CATEGORY_ELIXIR)
                    table.insert(boostDefs, copied)
                end
            end
            table.sort(boostDefs, function(a, b) return (a.SortOrder or 0) < (b.SortOrder or 0) end)
        end

        local remotes = ensureBoostRemotes()
        local boostStates = {}
        local timeDelta = 0
        local boostCards = {}
        local entryById = {}
        local selectedBoostId = nil

        for _, def in ipairs(boostDefs) do
            entryById[def.Id] = def
        end

        local function ingestStates(states)
            if type(states) ~= "table" then return end
            boostStates = states
            timeDelta = os.time() - (states._serverTime or os.time())
        end

        local function ingestPotionState(state)
            if type(state) ~= "table" then return end
            potionState = {
                isLoaded = state.isLoaded == true,
                potions = type(state.potions) == "table" and state.potions or {},
                equippedPotionId = type(state.equippedPotionId) == "string" and state.equippedPotionId or nil,
                cooldownEndsAt = tonumber(state.cooldownEndsAt) or 0,
                serverTime = tonumber(state.serverTime) or 0,
            }
            if potionState.equippedPotionId and getPotionCount(potionState.equippedPotionId) <= 0 then
                potionState.equippedPotionId = nil
            end
        end

        if remotes and remotes.getStates then
            pcall(function() ingestStates(remotes.getStates:InvokeServer()) end)
        end
        if potionRemoteSet and potionRemoteSet.getState then
            pcall(function() ingestPotionState(potionRemoteSet.getState:InvokeServer()) end)
        end

        -- ── Grouped potion inventory scroll (left side) ────────────────
        local boostGridScroll = Instance.new("ScrollingFrame")
        boostGridScroll.Name = "BoostGridScroll"
        boostGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
        boostGridScroll.BackgroundTransparency = 0.5
        boostGridScroll.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        boostGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        boostGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        boostGridScroll.ScrollBarThickness = px(4)
        boostGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
        boostGridScroll.BorderSizePixel = 0
        boostGridScroll.Parent = boostsPage
        Instance.new("UICorner", boostGridScroll).CornerRadius = UDim.new(0, px(10))

        local boostScrollLayout = Instance.new("UIListLayout", boostGridScroll)
        boostScrollLayout.FillDirection = Enum.FillDirection.Vertical
        boostScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
        boostScrollLayout.Padding = UDim.new(0, px(14))

        local boostGridPad = Instance.new("UIPadding", boostGridScroll)
        boostGridPad.PaddingTop    = UDim.new(0, px(8))
        boostGridPad.PaddingLeft   = UDim.new(0, px(8))
        boostGridPad.PaddingRight  = UDim.new(0, px(8))
        boostGridPad.PaddingBottom = UDim.new(0, px(8))

        local boostSectionRecords = {}
        local boostSectionByCategory = {}

        local function createPotionInventorySection(sectionDef, layoutOrder)
            local accent = sectionDef.Accent or GOLD

            local sectionFrame = Instance.new("Frame")
            sectionFrame.Name = tostring(sectionDef.Id or sectionDef.Category) .. "Section"
            sectionFrame.BackgroundTransparency = 1
            sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
            sectionFrame.Size = UDim2.new(1, 0, 0, 0)
            sectionFrame.LayoutOrder = layoutOrder
            sectionFrame.Parent = boostGridScroll

            local sectionLayout = Instance.new("UIListLayout", sectionFrame)
            sectionLayout.FillDirection = Enum.FillDirection.Vertical
            sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
            sectionLayout.Padding = UDim.new(0, px(8))

            local header = Instance.new("Frame")
            header.Name = "SectionHeader"
            header.BackgroundColor3 = accentPanelColor(accent, 0.34)
            header.BorderSizePixel = 0
            header.Size = UDim2.new(1, 0, 0, px(54))
            header.LayoutOrder = 1
            header.Parent = sectionFrame
            Instance.new("UICorner", header).CornerRadius = UDim.new(0, px(10))
            local headerStroke = Instance.new("UIStroke", header)
            headerStroke.Color = mixColor(accent, WHITE, 0.08)
            headerStroke.Thickness = 1.2
            headerStroke.Transparency = 0.3

            local accentBar = Instance.new("Frame", header)
            accentBar.Name = "AccentBar"
            accentBar.BackgroundColor3 = accent
            accentBar.BorderSizePixel = 0
            accentBar.Size = UDim2.new(0, px(5), 1, 0)
            accentBar.Position = UDim2.new(0, 0, 0, 0)
            Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, px(9))

            local headerTitle = Instance.new("TextLabel", header)
            headerTitle.Name = "Title"
            headerTitle.BackgroundTransparency = 1
            headerTitle.Font = Enum.Font.GothamBold
            headerTitle.Text = tostring(sectionDef.Header or sectionDef.Category or "POTIONS")
            headerTitle.TextColor3 = WHITE
            headerTitle.TextSize = math.max(16, math.floor(px(19)))
            headerTitle.TextXAlignment = Enum.TextXAlignment.Left
            headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
            headerTitle.Position = UDim2.new(0, px(16), 0, px(7))
            headerTitle.Size = UDim2.new(1, -px(28), 0, px(22))
            addTextOutline(headerTitle, 0.22, 1.2)

            local subtitle = Instance.new("TextLabel", header)
            subtitle.Name = "Subtitle"
            subtitle.BackgroundTransparency = 1
            subtitle.Font = Enum.Font.GothamMedium
            subtitle.Text = tostring(sectionDef.Subtitle or "")
            subtitle.TextColor3 = DIM_TEXT
            subtitle.TextSize = math.max(10, math.floor(px(12)))
            subtitle.TextXAlignment = Enum.TextXAlignment.Left
            subtitle.TextTruncate = Enum.TextTruncate.AtEnd
            subtitle.Position = UDim2.new(0, px(16), 0, px(30))
            subtitle.Size = UDim2.new(1, -px(28), 0, px(18))

            local grid = Instance.new("Frame")
            grid.Name = tostring(sectionDef.Id or sectionDef.Category) .. "Grid"
            grid.BackgroundTransparency = 1
            grid.Size = UDim2.new(1, 0, 0, px(1))
            grid.LayoutOrder = 2
            grid.Visible = false
            grid.Parent = sectionFrame

            local gridLayout = Instance.new("UIGridLayout", grid)
            gridLayout.CellSize = UDim2.new(0, px(140), 0, px(178))
            gridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
            gridLayout.FillDirection = Enum.FillDirection.Horizontal
            gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Name = "EmptyMessage"
            emptyLabel.BackgroundColor3 = accentPanelColor(accent, 0.18)
            emptyLabel.BorderSizePixel = 0
            emptyLabel.Font = Enum.Font.GothamMedium
            emptyLabel.Text = tostring(sectionDef.EmptyText or "No potions owned yet.")
            emptyLabel.TextColor3 = DIM_TEXT
            emptyLabel.TextSize = math.max(12, math.floor(px(13)))
            emptyLabel.TextWrapped = true
            emptyLabel.Size = UDim2.new(1, 0, 0, px(52))
            emptyLabel.LayoutOrder = 3
            emptyLabel.Visible = true
            emptyLabel.Parent = sectionFrame
            Instance.new("UICorner", emptyLabel).CornerRadius = UDim.new(0, px(9))
            local emptyStroke = Instance.new("UIStroke", emptyLabel)
            emptyStroke.Color = CARD_STROKE
            emptyStroke.Thickness = 1
            emptyStroke.Transparency = 0.5

            local record = {
                category = sectionDef.Category,
                grid = grid,
                layout = gridLayout,
                empty = emptyLabel,
                visibleCount = 0,
            }
            table.insert(boostSectionRecords, record)
            boostSectionByCategory[sectionDef.Category] = record
            return record
        end

        for index, sectionDef in ipairs(POTION_CATEGORY_SECTIONS) do
            createPotionInventorySection(sectionDef, index)
        end

        local function updateBoostSectionLayouts()
            local availableWidth = boostGridScroll.AbsoluteSize.X
                - (boostGridPad.PaddingLeft.Offset or 0)
                - (boostGridPad.PaddingRight.Offset or 0)
                - math.max(0, boostGridScroll.ScrollBarThickness or 0)
            local gap = px(10)
            local columns = INVENTORY_GRID_COLUMNS
            local cellWidth = math.max(1, math.floor((availableWidth - (gap * math.max(0, columns - 1))) / columns))
            local cellHeight = math.max(1, math.floor(cellWidth * (178 / 140)))

            for _, record in ipairs(boostSectionRecords) do
                local count = math.max(0, tonumber(record.visibleCount) or 0)
                record.layout.CellPadding = UDim2.new(0, gap, 0, gap)
                record.layout.CellSize = UDim2.new(0, cellWidth, 0, cellHeight)
                record.grid.Visible = count > 0
                record.empty.Visible = count <= 0
                local rows = count > 0 and math.ceil(count / columns) or 0
                local gridHeight = rows > 0 and ((rows * cellHeight) + (math.max(0, rows - 1) * gap)) or px(1)
                record.grid.Size = UDim2.new(1, 0, 0, gridHeight)
            end
        end

        trackConn(boostGridScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateBoostSectionLayouts))
        task.defer(updateBoostSectionLayouts)

        -- Empty state (shown when no boosts owned)
        local boostEmptyState = Instance.new("Frame")
        boostEmptyState.Name = "BoostEmptyState"
        boostEmptyState.BackgroundTransparency = 1
        boostEmptyState.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        boostEmptyState.Visible = false
        boostEmptyState.Parent = boostsPage

        local beCard = Instance.new("Frame")
        beCard.BackgroundColor3 = accentPanelColor(GOLD, 0.22)
        beCard.Size = UDim2.new(0.7, 0, 0, px(130))
        beCard.AnchorPoint = Vector2.new(0.5, 0.5)
        beCard.Position = UDim2.new(0.5, 0, 0.45, 0)
        beCard.Parent = boostEmptyState
        Instance.new("UICorner", beCard).CornerRadius = UDim.new(0, px(14))
        local beStroke = Instance.new("UIStroke", beCard)
        beStroke.Color = UITheme.GOLD_DIM; beStroke.Thickness = 1.4; beStroke.Transparency = 0.18
        addCardSheen(beCard, GOLD)

        local beLine1 = Instance.new("TextLabel", beCard)
        beLine1.BackgroundTransparency = 1; beLine1.Font = Enum.Font.GothamMedium
        beLine1.Text = "You don't own any potions or boosts yet."
        beLine1.TextColor3 = DIM_TEXT; beLine1.TextSize = math.max(13, math.floor(px(14)))
        beLine1.TextWrapped = true; beLine1.Size = UDim2.new(0.85, 0, 0, px(40))
        beLine1.AnchorPoint = Vector2.new(0.5, 0); beLine1.Position = UDim2.new(0.5, 0, 0, px(28))
        beLine1.TextXAlignment = Enum.TextXAlignment.Center

        local beLine2 = Instance.new("TextLabel", beCard)
        beLine2.BackgroundTransparency = 1; beLine2.Font = Enum.Font.GothamMedium
        beLine2.Text = "Visit the shop or spin the wheel to stock up."
        beLine2.TextColor3 = UITheme.GOLD_DIM; beLine2.TextSize = math.max(11, math.floor(px(12)))
        beLine2.Size = UDim2.new(0.85, 0, 0, px(20)); beLine2.AnchorPoint = Vector2.new(0.5, 0)
        beLine2.Position = UDim2.new(0.5, 0, 0, px(74)); beLine2.TextXAlignment = Enum.TextXAlignment.Center

        local boostEmptyShopBtn = Instance.new("TextButton", boostEmptyState)
        boostEmptyShopBtn.Name = "ShopNavBtn"
        boostEmptyShopBtn.AutoButtonColor = false
        boostEmptyShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        boostEmptyShopBtn.Font = Enum.Font.GothamBold
        boostEmptyShopBtn.Text = "\u{1F6D2}  Browse Shop"
        boostEmptyShopBtn.TextColor3 = WHITE
        boostEmptyShopBtn.TextTransparency = 0
        boostEmptyShopBtn.TextSize = math.max(14, math.floor(px(15)))
        boostEmptyShopBtn.AutomaticSize = Enum.AutomaticSize.X
        boostEmptyShopBtn.Size = UDim2.new(0, 0, 0, px(36))
        boostEmptyShopBtn.AnchorPoint = Vector2.new(0.5, 0)
        boostEmptyShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
        Instance.new("UICorner", boostEmptyShopBtn).CornerRadius = UDim.new(0, px(8))
        local besBtnPad = Instance.new("UIPadding", boostEmptyShopBtn)
        besBtnPad.PaddingLeft = UDim.new(0, px(20)); besBtnPad.PaddingRight = UDim.new(0, px(20))
        local besBtnStroke = Instance.new("UIStroke", boostEmptyShopBtn)
        besBtnStroke.Color = Color3.fromRGB(0, 0, 0); besBtnStroke.Thickness = 1.5; besBtnStroke.Transparency = 0.15

        boostEmptyShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("boosts") end
            end
        end)

        -- ── Details panel (right side) ──────────────────────────────────
        local boostDetailsPanel = Instance.new("Frame")
        boostDetailsPanel.Name = "BoostDetailsPanel"
        boostDetailsPanel.BackgroundColor3 = CARD_BG
        boostDetailsPanel.Size = UDim2.new(0, DETAIL_W, 1, 0)
        boostDetailsPanel.AnchorPoint = Vector2.new(1, 0)
        boostDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
        boostDetailsPanel.Parent = boostsPage
        Instance.new("UICorner", boostDetailsPanel).CornerRadius = UDim.new(0, px(12))
        local bdpStroke = Instance.new("UIStroke", boostDetailsPanel)
        bdpStroke.Color = CARD_STROKE; bdpStroke.Thickness = 1.4; bdpStroke.Transparency = 0.2

        -- Placeholder
        local boostDetailPlaceholder = Instance.new("TextLabel", boostDetailsPanel)
        boostDetailPlaceholder.Name = "Placeholder"
        boostDetailPlaceholder.BackgroundTransparency = 1
        boostDetailPlaceholder.Font = Enum.Font.GothamMedium
        boostDetailPlaceholder.Text = "Select a potion or boost"
        boostDetailPlaceholder.TextColor3 = DIM_TEXT
        boostDetailPlaceholder.TextSize = px(22)
        boostDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
        boostDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

        -- Detail content
        local boostDetailContent = Instance.new("Frame", boostDetailsPanel)
        boostDetailContent.Name = "DetailContent"
        boostDetailContent.BackgroundTransparency = 1
        boostDetailContent.Size = UDim2.new(1, 0, 1, 0)
        boostDetailContent.Visible = false

        local bdPad = Instance.new("UIPadding", boostDetailContent)
        bdPad.PaddingTop  = UDim.new(0, px(12)); bdPad.PaddingBottom = UDim.new(0, px(12))
        bdPad.PaddingLeft = UDim.new(0, px(12)); bdPad.PaddingRight  = UDim.new(0, px(12))

        -- Large icon area
        local boostDetailIconBg = Instance.new("Frame", boostDetailContent)
        boostDetailIconBg.Name = "IconBg"
        boostDetailIconBg.BackgroundColor3 = Color3.fromRGB(30, 34, 55)
        boostDetailIconBg.Size = UDim2.new(1, 0, 0, px(170))
        boostDetailIconBg.ClipsDescendants = true
        Instance.new("UICorner", boostDetailIconBg).CornerRadius = UDim.new(0, px(10))
        local bdIconStroke = Instance.new("UIStroke", boostDetailIconBg)
        bdIconStroke.Color = CARD_STROKE; bdIconStroke.Thickness = 1.5; bdIconStroke.Transparency = 0.3
        local boostDetailIconSheen = addCardSheen(boostDetailIconBg, GOLD)
        boostDetailIconSheen.BackgroundTransparency = 0.82

        local boostDetailIconImage = Instance.new("ImageLabel", boostDetailIconBg)
        boostDetailIconImage.Name = "IconImage"
        boostDetailIconImage.BackgroundTransparency = 1
        boostDetailIconImage.Size = UDim2.new(0.45, 0, 0.45, 0)
        boostDetailIconImage.AnchorPoint = Vector2.new(0.5, 0.5)
        boostDetailIconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        boostDetailIconImage.ScaleType = Enum.ScaleType.Fit

        local boostDetailIconGlyph = Instance.new("TextLabel", boostDetailIconBg)
        boostDetailIconGlyph.Name = "IconGlyph"
        boostDetailIconGlyph.BackgroundTransparency = 1
        boostDetailIconGlyph.Size = UDim2.new(1, 0, 1, 0)
        boostDetailIconGlyph.Font = Enum.Font.GothamBold
        boostDetailIconGlyph.TextSize = math.max(40, math.floor(px(60)))
        boostDetailIconGlyph.TextColor3 = WHITE
        boostDetailIconGlyph.Text = ""
        addTextOutline(boostDetailIconGlyph, 0.2, 1.6)

        -- Boost name
        local boostDetailName = Instance.new("TextLabel", boostDetailContent)
        boostDetailName.Name = "BoostName"
        boostDetailName.BackgroundTransparency = 1
        boostDetailName.Font = Enum.Font.GothamBold
        boostDetailName.TextColor3 = WHITE
        boostDetailName.TextSize = px(26)
        boostDetailName.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailName.Size = UDim2.new(1, 0, 0, px(34))
        boostDetailName.Position = UDim2.new(0, 0, 0, px(178))
        boostDetailName.TextTruncate = Enum.TextTruncate.AtEnd

        -- Description
        local boostDetailDesc = Instance.new("TextLabel", boostDetailContent)
        boostDetailDesc.Name = "Description"
        boostDetailDesc.BackgroundTransparency = 1
        boostDetailDesc.Font = Enum.Font.GothamMedium
        boostDetailDesc.TextColor3 = DIM_TEXT
        boostDetailDesc.TextSize = px(17)
        boostDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailDesc.TextWrapped = true
        boostDetailDesc.Size = UDim2.new(1, 0, 0, px(44))
        boostDetailDesc.Position = UDim2.new(0, 0, 0, px(214))

        -- Duration label
        local boostDetailDuration = Instance.new("TextLabel", boostDetailContent)
        boostDetailDuration.Name = "Duration"
        boostDetailDuration.BackgroundTransparency = 1
        boostDetailDuration.Font = Enum.Font.GothamBold
        boostDetailDuration.TextColor3 = DIM_TEXT
        boostDetailDuration.TextSize = px(17)
        boostDetailDuration.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailDuration.Size = UDim2.new(1, 0, 0, px(24))
        boostDetailDuration.Position = UDim2.new(0, 0, 0, px(262))

        -- Owned count
        local boostDetailOwned = Instance.new("TextLabel", boostDetailContent)
        boostDetailOwned.Name = "OwnedCount"
        boostDetailOwned.BackgroundTransparency = 1
        boostDetailOwned.Font = Enum.Font.GothamBold
        boostDetailOwned.TextColor3 = WHITE
        boostDetailOwned.TextSize = px(19)
        boostDetailOwned.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailOwned.Size = UDim2.new(1, 0, 0, px(26))
        boostDetailOwned.Position = UDim2.new(0, 0, 0, px(290))

        -- Status label (Ready / Active / Not Owned)
        local boostDetailStatus = Instance.new("TextLabel", boostDetailContent)
        boostDetailStatus.Name = "Status"
        boostDetailStatus.BackgroundTransparency = 1
        boostDetailStatus.Font = Enum.Font.GothamBold
        boostDetailStatus.TextColor3 = DIM_TEXT
        boostDetailStatus.TextSize = px(18)
        boostDetailStatus.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailStatus.Size = UDim2.new(1, 0, 0, px(26))
        boostDetailStatus.Position = UDim2.new(0, 0, 0, px(320))

        -- Remaining time label (visible only when active)
        local boostDetailTimer = Instance.new("TextLabel", boostDetailContent)
        boostDetailTimer.Name = "Timer"
        boostDetailTimer.BackgroundTransparency = 1
        boostDetailTimer.Font = Enum.Font.GothamBold
        boostDetailTimer.TextColor3 = GREEN_GLOW
        boostDetailTimer.TextSize = px(18)
        boostDetailTimer.TextXAlignment = Enum.TextXAlignment.Center
        boostDetailTimer.Size = UDim2.new(1, 0, 0, px(24))
        boostDetailTimer.Position = UDim2.new(0, 0, 0, px(350))
        boostDetailTimer.Visible = false

        -- Activate button
        local boostActivateBtn = Instance.new("TextButton", boostDetailContent)
        boostActivateBtn.Name = "ActivateBtn"
        boostActivateBtn.AutoButtonColor = false
        boostActivateBtn.BackgroundColor3 = BTN_BG
        boostActivateBtn.Font = Enum.Font.GothamBold
        boostActivateBtn.Text = "ACTIVATE"
        boostActivateBtn.TextColor3 = WHITE
        boostActivateBtn.TextTransparency = 0
        boostActivateBtn.TextSize = px(22)
        boostActivateBtn.Size = UDim2.new(0.88, 0, 0, px(52))
        boostActivateBtn.AnchorPoint = Vector2.new(0.5, 1)
        boostActivateBtn.Position = UDim2.new(0.5, 0, 1, 0)
        Instance.new("UICorner", boostActivateBtn).CornerRadius = UDim.new(0, px(10))
        local boostActivateStroke = Instance.new("UIStroke", boostActivateBtn)
        boostActivateStroke.Color = Color3.fromRGB(0, 0, 0); boostActivateStroke.Thickness = 1.5; boostActivateStroke.Transparency = 0.15

        -- Browse Shop button (above activate)
        local boostShopNavW = Instance.new("Frame", boostDetailContent)
        boostShopNavW.Name = "ShopNavWrap"
        boostShopNavW.BackgroundTransparency = 1
        boostShopNavW.Size = UDim2.new(0.88, 0, 0, px(36))
        boostShopNavW.AnchorPoint = Vector2.new(0.5, 1)
        boostShopNavW.Position = UDim2.new(0.5, 0, 1, -px(58))

        local boostShopBtn = Instance.new("TextButton", boostShopNavW)
        boostShopBtn.AutoButtonColor = false
        boostShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        boostShopBtn.Font = Enum.Font.GothamBold
        boostShopBtn.Text = "\u{1F6D2}  Browse Boosts Shop"
        boostShopBtn.TextColor3 = WHITE
        boostShopBtn.TextTransparency = 0
        boostShopBtn.TextSize = math.max(13, math.floor(px(15)))
        boostShopBtn.AutomaticSize = Enum.AutomaticSize.X
        boostShopBtn.Size = UDim2.new(0, 0, 1, 0)
        boostShopBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        boostShopBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
        Instance.new("UICorner", boostShopBtn).CornerRadius = UDim.new(0, px(8))
        local bsnPad = Instance.new("UIPadding", boostShopBtn)
        bsnPad.PaddingLeft = UDim.new(0, px(14)); bsnPad.PaddingRight = UDim.new(0, px(14))
        local bsnStroke = Instance.new("UIStroke", boostShopBtn)
        bsnStroke.Color = Color3.fromRGB(0, 0, 0); bsnStroke.Thickness = 1.5; bsnStroke.Transparency = 0.15

        boostShopBtn.MouseEnter:Connect(function() TweenService:Create(boostShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
        boostShopBtn.MouseLeave:Connect(function() TweenService:Create(boostShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
        boostShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("boosts") end
            end
        end)

        -- ── Helpers ─────────────────────────────────────────────────────

        local function getBoostState(boostId)
            local boostDef = entryById[boostId]
            if boostDef and boostDef.Kind == "potion" then
                local owned = getPotionCount(boostId)
                local equipped = potionState.equippedPotionId == boostId and owned > 0
                local remaining = math.max(0, (tonumber(potionState.cooldownEndsAt) or 0) - workspace:GetServerTimeNow())
                return owned, equipped, remaining
            end

            local state = boostStates[boostId] or {}
            local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
            local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + timeDelta
            local active = expiresAt > os.time()
            local remaining = active and math.max(0, expiresAt - os.time()) or 0
            return owned, active, remaining
        end

        -- ── Update details panel for selected boost ─────────────────────
        local function updateBoostDetailsPanel()
            if not selectedBoostId then
                boostDetailPlaceholder.Visible = true
                boostDetailContent.Visible = false
                boostDetailPlaceholder.Text = "Select a potion or boost"
                return
            end
            boostDetailPlaceholder.Visible = false
            boostDetailContent.Visible = true

            local def = entryById[selectedBoostId]
            if not def then return end

            local iconData = getItemIconData(def)
            local iconColor = colorFromRGBArray((type(iconData) == "table" and (iconData.IconColor or iconData.LiquidColor)) or def.IconColor) or BOOST_ACCENT_COLORS[def.Id] or GOLD

            -- Icon background tint
            boostDetailIconBg.BackgroundColor3 = Color3.new(
                math.clamp(iconColor.R * 0.22 + 0.08, 0, 1),
                math.clamp(iconColor.G * 0.22 + 0.08, 0, 1),
                math.clamp(iconColor.B * 0.22 + 0.08, 0, 1)
            )
            bdIconStroke.Color = iconColor
            bdIconStroke.Transparency = 0.12
            bdpStroke.Color = iconColor
            bdpStroke.Transparency = 0.14
            boostDetailIconSheen.BackgroundColor3 = brightenColor(iconColor, 0.08)

            -- Icon image or glyph
            local generatedDetailIcon = boostDetailIconBg:FindFirstChild("GeneratedPotionIcon")
            if generatedDetailIcon then
                generatedDetailIcon:Destroy()
            end
            local img = getBoostIconImage(def)
            if type(iconData) == "table" and iconData.Kind == "PotionBottle" then
                boostDetailIconImage.Visible = false
                boostDetailIconGlyph.Visible = false
                createPotionBottleIcon(boostDetailIconBg, iconData, iconColor, 0.62)
            elseif img and #img > 0 then
                boostDetailIconImage.Image = img
                boostDetailIconImage.Visible = true
                boostDetailIconGlyph.Visible = false
            else
                boostDetailIconImage.Visible = false
                boostDetailIconGlyph.Text = (type(iconData) == "table" and iconData.Glyph) or def.IconGlyph or "\u{26A1}"
                boostDetailIconGlyph.TextColor3 = iconColor
                boostDetailIconGlyph.Visible = true
            end

            boostDetailName.Text = def.DisplayName or def.Id
            boostDetailName.TextColor3 = brightenColor(iconColor, 0.1)
            boostDetailDesc.Text = def.Description or ""

            -- Duration
            if def.Kind == "potion" then
                boostDetailDuration.Text = def.DetailText or "Equip to slot 4"
            else
                local durSec = def.DurationSeconds or 0
                if durSec > 0 then
                    local durMin = math.floor(durSec / 60)
                    boostDetailDuration.Text = "Duration: " .. tostring(durMin) .. " minutes"
                else
                    boostDetailDuration.Text = ""
                end
            end

            -- State-dependent fields
            local owned, active, remaining = getBoostState(def.Id)
            boostDetailOwned.Text = "Owned: " .. tostring(owned)

            if def.Kind == "potion" then
                if remaining > 0 then
                    boostDetailStatus.Text = active and "Cooling Down" or "Cooling Down"
                    boostDetailStatus.TextColor3 = Color3.fromRGB(160, 215, 255)
                    boostDetailTimer.Text = string.format("Cooldown: %02d:%02d", math.floor(remaining / 60), remaining % 60)
                    boostDetailTimer.Visible = true
                else
                    boostDetailTimer.Visible = false
                end

                if owned <= 0 then
                    boostDetailStatus.Text = "Not Owned"
                    boostDetailStatus.TextColor3 = DIM_TEXT
                    boostActivateBtn.Text = "EQUIP"
                    boostActivateBtn.Active = false
                    boostActivateBtn.BackgroundColor3 = DISABLED_BG
                    boostActivateBtn.TextColor3 = DIM_TEXT
                    boostActivateStroke.Color = CARD_STROKE
                    boostActivateStroke.Transparency = 0.45
                elseif active then
                    if remaining <= 0 then
                        boostDetailStatus.Text = "Equipped to Slot 4"
                        boostDetailStatus.TextColor3 = WHITE
                    end
                    boostActivateBtn.Text = "UNEQUIP"
                    boostActivateBtn.Active = true
                    boostActivateBtn.BackgroundColor3 = Color3.fromRGB(45, 108, 170)
                    boostActivateBtn.TextColor3 = WHITE
                    boostActivateStroke.Color = Color3.fromRGB(0, 0, 0)
                    boostActivateStroke.Transparency = 0.15
                else
                    boostDetailStatus.Text = remaining > 0 and "Shared Cooldown Active" or "Ready to Equip"
                    boostDetailStatus.TextColor3 = remaining > 0 and Color3.fromRGB(160, 215, 255) or WHITE
                    boostActivateBtn.Text = "EQUIP"
                    boostActivateBtn.Active = true
                    boostActivateBtn.BackgroundColor3 = BTN_BG
                    boostActivateBtn.TextColor3 = WHITE
                    boostActivateStroke.Color = Color3.fromRGB(0, 0, 0)
                    boostActivateStroke.Transparency = 0.15
                end
            elseif active then
                boostDetailStatus.Text = "\u{2714} ACTIVE"
                boostDetailStatus.TextColor3 = GREEN_GLOW
                boostDetailTimer.Text = string.format("Remaining: %02d:%02d", math.floor(remaining / 60), remaining % 60)
                boostDetailTimer.Visible = true
                boostActivateBtn.Text = "\u{2714} ACTIVE"
                boostActivateBtn.Active = false
                boostActivateBtn.BackgroundColor3 = DISABLED_BG
                boostActivateBtn.TextColor3 = GREEN_GLOW
                boostActivateStroke.Color = Color3.fromRGB(0, 0, 0)
                boostActivateStroke.Transparency = 0.15
            elseif owned > 0 then
                boostDetailStatus.Text = "Ready to Use"
                boostDetailStatus.TextColor3 = WHITE
                boostDetailTimer.Visible = false
                boostActivateBtn.Text = "USE"
                boostActivateBtn.Active = true
                boostActivateBtn.BackgroundColor3 = BTN_BG
                boostActivateBtn.TextColor3 = WHITE
                boostActivateStroke.Color = Color3.fromRGB(0, 0, 0)
                boostActivateStroke.Transparency = 0.15
            else
                boostDetailStatus.Text = "Not Owned"
                boostDetailStatus.TextColor3 = DIM_TEXT
                boostDetailTimer.Visible = false
                boostActivateBtn.Text = "USE"
                boostActivateBtn.Active = false
                boostActivateBtn.BackgroundColor3 = DISABLED_BG
                boostActivateBtn.TextColor3 = DIM_TEXT
                boostActivateStroke.Color = CARD_STROKE
                boostActivateStroke.Transparency = 0.45
            end
        end

        -- ── Refresh all boost card visuals ──────────────────────────────
        local function refreshBoostCards()
            for _, record in ipairs(boostSectionRecords) do
                record.visibleCount = 0
            end

            local firstVisibleId = nil
            local selectedStillVisible = false

            for _, def in ipairs(boostDefs) do
                local refs = boostCards[def.Id]
                if not refs then continue end
                local owned, active, remaining = getBoostState(def.Id)
                local shouldShow = owned > 0 or active

                refs.card.Visible = shouldShow
                refs.card.LayoutOrder = refs.layoutOrder or refs.card.LayoutOrder
                if shouldShow then
                    if refs.sectionRecord and refs.sectionRecord.grid then
                        refs.card.Parent = refs.sectionRecord.grid
                        refs.sectionRecord.visibleCount = (refs.sectionRecord.visibleCount or 0) + 1
                    else
                        refs.card.Parent = boostGridScroll
                    end
                    firstVisibleId = firstVisibleId or def.Id
                    if selectedBoostId == def.Id then
                        selectedStillVisible = true
                    end
                else
                    refs.card.Parent = nil
                end

                local isSelected = (selectedBoostId == def.Id)

                local targetBg = refs.baseBg or CARD_BG
                if isSelected then
                    targetBg = active and mixColor(refs.activeBg or CARD_EQUIPPED, GOLD, 0.14) or (refs.selectedBg or CARD_BG)
                    setCardStroke(refs.cardStroke, GOLD, 2.5, 0)
                elseif active then
                    targetBg = refs.activeBg or CARD_EQUIPPED
                    setCardStroke(refs.cardStroke, GREEN_GLOW, 2.0, 0.16)
                elseif owned > 0 then
                    setCardStroke(refs.cardStroke, refs.borderColor or CARD_STROKE, 1.8, 0.12)
                else
                    setCardStroke(refs.cardStroke, refs.borderColor or CARD_STROKE, 1.5, 0.22)
                end
                refs.card.BackgroundColor3 = targetBg
                if refs.accentBar then
                    refs.accentBar.BackgroundColor3 = active and GREEN_GLOW or (refs.accentColor or GOLD)
                    refs.accentBar.BackgroundTransparency = active and 0 or 0.12
                end

                -- Active bar indicator
                local eqBar = refs.card:FindFirstChild("ActiveBar")
                if eqBar then eqBar.Visible = active end

                -- Card status label
                if def.Kind == "potion" then
                    if active and remaining > 0 then
                        refs.statusLabel.Text = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
                        refs.statusLabel.TextColor3 = Color3.fromRGB(160, 215, 255)
                        if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, Color3.fromRGB(70, 145, 220), 0.3) end
                        if refs.statusStroke then refs.statusStroke.Color = Color3.fromRGB(103, 186, 255); refs.statusStroke.Transparency = 0.22 end
                    elseif active then
                        refs.statusLabel.Text = "Equipped"
                        refs.statusLabel.TextColor3 = WHITE
                        if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, refs.accentColor or GOLD, 0.24) end
                        if refs.statusStroke then refs.statusStroke.Color = refs.accentColor or GOLD; refs.statusStroke.Transparency = 0.26 end
                    elseif owned > 0 then
                        refs.statusLabel.Text = "Owned: " .. tostring(owned)
                        refs.statusLabel.TextColor3 = WHITE
                        if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, refs.accentColor or GOLD, 0.18) end
                        if refs.statusStroke then refs.statusStroke.Color = refs.accentColor or GOLD; refs.statusStroke.Transparency = 0.35 end
                    else
                        refs.statusLabel.Text = "Not Owned"
                        refs.statusLabel.TextColor3 = DIM_TEXT
                        if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, Color3.fromRGB(10, 12, 20), 0.28) end
                        if refs.statusStroke then refs.statusStroke.Color = refs.borderColor or CARD_STROKE; refs.statusStroke.Transparency = 0.5 end
                    end
                elseif active then
                    refs.statusLabel.Text = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
                    refs.statusLabel.TextColor3 = GREEN_GLOW
                    if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, GREEN_GLOW, 0.3) end
                    if refs.statusStroke then refs.statusStroke.Color = GREEN_GLOW; refs.statusStroke.Transparency = 0.22 end
                elseif owned > 0 then
                    refs.statusLabel.Text = "Owned: " .. tostring(owned)
                    refs.statusLabel.TextColor3 = WHITE
                    if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, refs.accentColor or GOLD, 0.18) end
                    if refs.statusStroke then refs.statusStroke.Color = refs.accentColor or GOLD; refs.statusStroke.Transparency = 0.35 end
                else
                    refs.statusLabel.Text = "Not Owned"
                    refs.statusLabel.TextColor3 = DIM_TEXT
                    if refs.statusPill then refs.statusPill.BackgroundColor3 = mixColor(refs.baseBg or CARD_BG, Color3.fromRGB(10, 12, 20), 0.28) end
                    if refs.statusStroke then refs.statusStroke.Color = refs.borderColor or CARD_STROKE; refs.statusStroke.Transparency = 0.5 end
                end
            end

            if selectedBoostId and not selectedStillVisible then
                selectedBoostId = firstVisibleId
            elseif not selectedBoostId then
                selectedBoostId = firstVisibleId
            end

            updateBoostSectionLayouts()

            -- Update details panel timer if it's visible
            updateBoostDetailsPanel()
        end

        -- ── Select a boost ──────────────────────────────────────────────
        local function setSelectedBoost(boostId)
            selectedBoostId = boostId
            refreshBoostCards()
        end

        -- ── Create boost cards ──────────────────────────────────────────
        if #boostDefs == 0 or (not remotes and not potionRemoteSet) then
            local unavailable = Instance.new("TextLabel", boostGridScroll)
            unavailable.BackgroundTransparency = 1; unavailable.Font = Enum.Font.GothamMedium
            unavailable.Text = "Potion inventory is currently unavailable."
            unavailable.TextColor3 = DIM_TEXT; unavailable.TextSize = math.max(14, math.floor(px(15)))
            unavailable.Size = UDim2.new(1, 0, 0, px(50)); unavailable.LayoutOrder = 1
        else
            local function createBoostCard(def, layoutOrder)
                local iconData = getItemIconData(def)
                local iconColor = colorFromRGBArray((type(iconData) == "table" and (iconData.IconColor or iconData.LiquidColor)) or def.IconColor) or BOOST_ACCENT_COLORS[def.Id] or GOLD
                local fallbackCategory = def.Kind == "boost" and POTION_CATEGORY_ELIXIR or POTION_CATEGORY_BATTLE
                local category = normalizePotionItemCategory(def.Category, fallbackCategory)
                local sectionRecord = boostSectionByCategory[category] or boostSectionByCategory[POTION_CATEGORY_BATTLE]
                local baseBg = accentPanelColor(iconColor, 0.48)
                local selectedBg = brightenColor(baseBg, 0.05)
                local activeBg = mixColor(baseBg, GREEN_GLOW, 0.2)
                local borderColor = mixColor(shadeColor(iconColor, 0.74), WHITE, 0.1)

                local card = Instance.new("TextButton")
                card.Name = "BoostCard_" .. def.Id
                card.BackgroundColor3 = baseBg
                card.Size = UDim2.new(1, 0, 1, 0)
                card.Text = ""
                card.AutoButtonColor = false
                card.BorderSizePixel = 0
                card.LayoutOrder = layoutOrder
                card.ClipsDescendants = true
                card.Parent = nil
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, INV_CARD.CornerRadius)

                local cStroke = Instance.new("UIStroke", card)
                cStroke.Color = borderColor; cStroke.Thickness = 1.6; cStroke.Transparency = 0.2
                addCardSheen(card, iconColor)
                local accentBar = addCardAccentBar(card, iconColor)

                -- Name label at top (matching weapon card layout)
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = def.DisplayName or def.Id
                cardName.TextColor3 = WHITE
                cardName.TextSize = INV_CARD.NameTextSize
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, INV_CARD.NameHeight)
                cardName.Position = UDim2.new(0, px(5), 0, INV_CARD.NameY)
                cardName.ZIndex = 3
                addTextOutline(cardName, 0.18, 1.35)

                -- Icon area (centered square, matching weapon card layout)
                local iconArea = Instance.new("Frame", card)
                iconArea.Name = "IconArea"
                iconArea.BackgroundColor3 = accentPanelColor(iconColor, 0.22)
                iconArea.Size = UDim2.new(0, INV_CARD.IconSize, 0, INV_CARD.IconSize)
                iconArea.AnchorPoint = Vector2.new(0.5, 0)
                iconArea.Position = UDim2.new(0.5, 0, 0, INV_CARD.IconY)
                iconArea.BorderSizePixel = 0
                Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, INV_CARD.IconCorner)
                addIconWellHighlight(iconArea, iconColor)

                -- Icon image centered in icon area
                local cardIconImage = Instance.new("ImageLabel", iconArea)
                cardIconImage.Name = "IconImage"
                cardIconImage.BackgroundTransparency = 1
                cardIconImage.Size = UDim2.new(0.85, 0, 0.85, 0)
                cardIconImage.AnchorPoint = Vector2.new(0.5, 0.5)
                cardIconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
                cardIconImage.ScaleType = Enum.ScaleType.Fit
                cardIconImage.ZIndex = 3

                local img = getBoostIconImage(def)
                local generatedCardIcon = nil
                if type(iconData) == "table" and iconData.Kind == "PotionBottle" then
                    cardIconImage.Visible = false
                    generatedCardIcon = createPotionBottleIcon(iconArea, iconData, iconColor, 0.86)
                elseif img and #img > 0 then
                    cardIconImage.Image = img
                    cardIconImage.Visible = true
                else
                    cardIconImage.Visible = false
                end

                local cardIconGlyph = Instance.new("TextLabel", iconArea)
                cardIconGlyph.Name = "IconGlyph"
                cardIconGlyph.BackgroundTransparency = 1
                cardIconGlyph.Size = UDim2.new(0.85, 0, 0.85, 0)
                cardIconGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
                cardIconGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
                cardIconGlyph.Font = Enum.Font.GothamBold
                cardIconGlyph.Text = (type(iconData) == "table" and iconData.Glyph) or def.IconGlyph or "\u{26A1}"
                cardIconGlyph.TextScaled = true
                cardIconGlyph.TextColor3 = iconColor
                cardIconGlyph.Visible = not cardIconImage.Visible and generatedCardIcon == nil
                cardIconGlyph.ZIndex = 3
                addTextOutline(cardIconGlyph, 0.2, 1.4)

                local durationBadge = Instance.new("TextLabel", card)
                durationBadge.Name = "DurationBadge"
                durationBadge.BackgroundColor3 = mixColor(baseBg, Color3.fromRGB(8, 10, 18), 0.36)
                durationBadge.Font = Enum.Font.GothamBold
                durationBadge.TextColor3 = WHITE
                durationBadge.TextSize = math.max(10, math.floor(px(11)))
                durationBadge.TextXAlignment = Enum.TextXAlignment.Center
                durationBadge.Size = UDim2.new(0, px(42), 0, px(18))
                durationBadge.AnchorPoint = Vector2.new(1, 0)
                durationBadge.Position = UDim2.new(1, -px(5), 0, px(27))
                if def.Kind == "potion" then
                    local badgeText = def.BadgeText or def.IconGlyph
                    durationBadge.Text = (type(badgeText) == "string" and badgeText ~= "" and badgeText) or "POTION"
                else
                    durationBadge.Text = ((def.DurationSeconds or 0) > 0) and (tostring(math.floor((def.DurationSeconds or 0) / 60)) .. "m") or "BOOST"
                end
                durationBadge.ZIndex = 4
                Instance.new("UICorner", durationBadge).CornerRadius = UDim.new(0, px(6))
                local durationStroke = Instance.new("UIStroke", durationBadge)
                durationStroke.Color = iconColor; durationStroke.Thickness = 1; durationStroke.Transparency = 0.45

                -- Status / owned count label (bottom of card)
                local statusPill = Instance.new("Frame", card)
                statusPill.Name = "StatusPill"
                statusPill.BackgroundColor3 = mixColor(baseBg, Color3.fromRGB(10, 12, 20), 0.28)
                statusPill.BorderSizePixel = 0
                statusPill.Size = UDim2.new(0.84, 0, 0, INV_CARD.Line2Height + px(4))
                statusPill.AnchorPoint = Vector2.new(0.5, 1)
                statusPill.Position = UDim2.new(0.5, 0, 1, -INV_CARD.Line2OffBottom)
                statusPill.ZIndex = 3
                Instance.new("UICorner", statusPill).CornerRadius = UDim.new(0, px(7))
                local statusStroke = Instance.new("UIStroke", statusPill)
                statusStroke.Color = borderColor; statusStroke.Thickness = 1; statusStroke.Transparency = 0.5

                local cardStatus = Instance.new("TextLabel", statusPill)
                cardStatus.Name = "StatusLabel"
                cardStatus.BackgroundTransparency = 1
                cardStatus.Font = Enum.Font.GothamBold
                cardStatus.Text = "Not Owned"
                cardStatus.TextColor3 = DIM_TEXT
                cardStatus.TextSize = INV_CARD.Line1TextSize
                cardStatus.TextXAlignment = Enum.TextXAlignment.Center
                cardStatus.Size = UDim2.new(1, -px(6), 1, 0)
                cardStatus.Position = UDim2.new(0, px(3), 0, 0)
                cardStatus.ZIndex = 4
                addTextOutline(cardStatus, 0.35, 1)

                -- Active bar at bottom (green strip when boost is running)
                local activeBar = Instance.new("Frame", card)
                activeBar.Name = "ActiveBar"
                activeBar.BackgroundColor3 = GREEN_GLOW
                activeBar.Size = UDim2.new(1, 0, 0, px(4))
                activeBar.AnchorPoint = Vector2.new(0, 1)
                activeBar.Position = UDim2.new(0, 0, 1, 0)
                activeBar.BorderSizePixel = 0; activeBar.ZIndex = 5
                activeBar.Visible = false

                boostCards[def.Id] = {
                    card = card,
                    cardStroke = cStroke,
                    statusLabel = cardStatus,
                    statusPill = statusPill,
                    statusStroke = statusStroke,
                    accentBar = accentBar,
                    accentColor = iconColor,
                    baseBg = baseBg,
                    hoverBg = brightenColor(baseBg, 0.07),
                    selectedBg = selectedBg,
                    activeBg = activeBg,
                    borderColor = borderColor,
                    sectionRecord = sectionRecord,
                    layoutOrder = layoutOrder,
                }

                -- Click to select
                card.MouseButton1Click:Connect(function()
                    setSelectedBoost(def.Id)
                end)

                -- Hover effect
                card.MouseEnter:Connect(function()
                    if selectedBoostId ~= def.Id then
                        local refs = boostCards[def.Id]
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = refs and refs.hoverBg or brightenColor(baseBg, 0.07)}):Play()
                    end
                end)
                card.MouseLeave:Connect(function()
                    if selectedBoostId ~= def.Id then
                        local _, isActive = getBoostState(def.Id)
                        local refs = boostCards[def.Id]
                        local targetBg = refs and (isActive and refs.activeBg or refs.baseBg) or baseBg
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = targetBg}):Play()
                    end
                end)
            end

            for i_b, def in ipairs(boostDefs) do
                createBoostCard(def, i_b)
            end

            -- Initial card refresh
            refreshBoostCards()

            -- Listen for server state updates
            if remotes and remotes.stateUpdated then
                trackConn(remotes.stateUpdated.OnClientEvent:Connect(function(states)
                    ingestStates(states); refreshBoostCards()
                end))
            end

            if potionRemoteSet and potionRemoteSet.stateUpdated then
                trackConn(potionRemoteSet.stateUpdated.OnClientEvent:Connect(function(state)
                    ingestPotionState(state); refreshBoostCards()
                end))
            end

            -- Heartbeat timer refresh
            local lastTick = 0
            trackConn(RunService.Heartbeat:Connect(function()
                local now = os.time(); if now == lastTick then return end
                lastTick = now; refreshBoostCards()
            end))
        end

        -- ── Activate button click ───────────────────────────────────────
        boostActivateBtn.MouseButton1Click:Connect(function()
            if not selectedBoostId then return end
            if not boostActivateBtn.Active then return end
            local def = entryById[selectedBoostId]
            if not def then return end

            if def.Kind == "potion" then
                if not potionRemoteSet or not potionRemoteSet.setEquipped then return end
                local _, isEquipped = getBoostState(def.Id)
                local shouldEquip = not isEquipped
                local ok, success, message, state = pcall(function()
                    return potionRemoteSet.setEquipped:InvokeServer(shouldEquip, def.Id)
                end)
                if ok and type(state) == "table" then ingestPotionState(state) end
                refreshBoostCards()
                if ok and success then
                    showToast(boostsPage, shouldEquip and ((def.DisplayName or "Potion") .. " equipped!") or "Potion unequipped!", Color3.fromRGB(103, 186, 255), 2.2)
                else
                    showToast(boostsPage, tostring((ok and message) or "Equip failed"), RED_TEXT, 2.2)
                end
                return
            end

            if not remotes then return end

            local ok, success, message, states = pcall(function()
                return remotes.activate:InvokeServer(selectedBoostId)
            end)
            if ok and success then
                ingestStates(states); refreshBoostCards()
                showToast(boostsPage, "Boost activated!", GREEN_GLOW, 2.2)
            else
                if ok and type(states) == "table" then ingestStates(states) end
                refreshBoostCards()
                showToast(boostsPage, tostring((ok and message) or "Activation failed"), RED_TEXT, 2.2)
            end
        end)

        -- Activate button hover
        boostActivateBtn.MouseEnter:Connect(function()
            if boostActivateBtn.Active then
                TweenService:Create(boostActivateBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end
        end)
        boostActivateBtn.MouseLeave:Connect(function()
            if boostActivateBtn.Active then
                TweenService:Create(boostActivateBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
            end
        end)
    end -- end Boosts scope block

    -- ══════════════════════════════════════════════════════════════════════
    --  SKINS PAGE  (grid + details panel, mirrors weapon tab pattern)
    -- ══════════════════════════════════════════════════════════════════════
    local skinsArea = Instance.new("Frame")
    skinsArea.Name = "SkinsArea"
    skinsArea.BackgroundTransparency = 1
    skinsArea.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    skinsArea.Position = UDim2.new(0, CONTENT_X, 0, 0)
    skinsArea.Visible = false
    skinsArea.Parent = root

    do
        -- ── Skin modules & remotes ──────────────────────────────────────
        local SkinDefs = nil
        pcall(function()
            local mod = ReplicatedStorage:FindFirstChild("SkinDefinitions")
            if mod and mod:IsA("ModuleScript") then SkinDefs = require(mod) end
        end)

        local SkinPreview = nil
        pcall(function()
            local mod = script.Parent:FindFirstChild("SkinPreview")
            if mod and mod:IsA("ModuleScript") then SkinPreview = require(mod) end
        end)

        local skinRemotes = nil
        local function ensureSkinRemotes()
            if skinRemotes then return skinRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local sf = rf:FindFirstChild("Skins") or rf:WaitForChild("Skins", 5)
            if not sf then return nil end
            skinRemotes = {
                getOwned      = sf:FindFirstChild("GetOwnedSkins"),
                equip         = sf:FindFirstChild("EquipSkin"),
                getEquipped   = sf:FindFirstChild("GetEquippedSkin"),
                changed       = sf:FindFirstChild("EquippedSkinChanged"),
                favorite      = sf:FindFirstChild("FavoriteSkin"),
                getFavorites  = sf:FindFirstChild("GetSkinFavorites"),
            }
            return skinRemotes
        end

        local allSkinDefs = SkinDefs and SkinDefs.GetInventorySkins() or {}

        -- ── State ───────────────────────────────────────────────────────
        local ownedSkinSet    = {}
        local equippedSkinId  = nil
        local favoritedSkins  = {}
        local selectedSkinId  = nil
        local skinCards       = {} -- [skinId] = { card, cardStroke, isDefault }

        -- ── Grid (left side) ────────────────────────────────────────────
        local skinGridScroll = Instance.new("ScrollingFrame")
        skinGridScroll.Name = "SkinGridScroll"
        skinGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
        skinGridScroll.BackgroundTransparency = 0.5
        skinGridScroll.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        skinGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        skinGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        skinGridScroll.ScrollBarThickness = px(4)
        skinGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
        skinGridScroll.BorderSizePixel = 0
        skinGridScroll.Parent = skinsArea
        Instance.new("UICorner", skinGridScroll).CornerRadius = UDim.new(0, px(10))

        local skinGridLayout = Instance.new("UIGridLayout", skinGridScroll)
        skinGridLayout.CellSize = UDim2.new(0, px(140), 0, px(178))
        skinGridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
        skinGridLayout.FillDirection = Enum.FillDirection.Horizontal
        skinGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        skinGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local skinGridPad = Instance.new("UIPadding", skinGridScroll)
        skinGridPad.PaddingTop    = UDim.new(0, px(8))
        skinGridPad.PaddingLeft   = UDim.new(0, px(8))
        skinGridPad.PaddingRight  = UDim.new(0, px(8))
        skinGridPad.PaddingBottom = UDim.new(0, px(8))
        bindFixedColumnGrid(skinGridScroll, skinGridLayout, skinGridPad, 140, 178)

        -- Empty state (shown when no owned skins)
        local skinEmptyState = Instance.new("Frame")
        skinEmptyState.Name = "SkinEmptyState"
        skinEmptyState.BackgroundTransparency = 1
        skinEmptyState.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        skinEmptyState.Visible = false
        skinEmptyState.Parent = skinsArea

        local skinEmptyCard = Instance.new("Frame")
        skinEmptyCard.BackgroundColor3 = CARD_BG
        skinEmptyCard.Size = UDim2.new(0.7, 0, 0, px(130))
        skinEmptyCard.AnchorPoint = Vector2.new(0.5, 0.5)
        skinEmptyCard.Position = UDim2.new(0.5, 0, 0.45, 0)
        skinEmptyCard.Parent = skinEmptyState
        Instance.new("UICorner", skinEmptyCard).CornerRadius = UDim.new(0, px(14))
        local secStroke = Instance.new("UIStroke", skinEmptyCard)
        secStroke.Color = CARD_STROKE; secStroke.Thickness = 1.2; secStroke.Transparency = 0.3

        local skinEmptyLbl = Instance.new("TextLabel", skinEmptyCard)
        skinEmptyLbl.BackgroundTransparency = 1
        skinEmptyLbl.Font = Enum.Font.GothamMedium
        skinEmptyLbl.Text = "You don't own any skins yet.\nVisit the shop to unlock more."
        skinEmptyLbl.TextColor3 = DIM_TEXT
        skinEmptyLbl.TextSize = math.max(13, math.floor(px(14)))
        skinEmptyLbl.TextWrapped = true
        skinEmptyLbl.Size = UDim2.new(0.85, 0, 0, px(60))
        skinEmptyLbl.AnchorPoint = Vector2.new(0.5, 0.5)
        skinEmptyLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
        skinEmptyLbl.TextXAlignment = Enum.TextXAlignment.Center

        local skinEmptyShopBtn = Instance.new("TextButton", skinEmptyState)
        skinEmptyShopBtn.Name = "ShopNavBtn"
        skinEmptyShopBtn.AutoButtonColor = false
        skinEmptyShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        skinEmptyShopBtn.Font = Enum.Font.GothamBold
        skinEmptyShopBtn.Text = "\u{1F6D2}  Browse Skins Shop"
        skinEmptyShopBtn.TextColor3 = WHITE
        skinEmptyShopBtn.TextTransparency = 0
        skinEmptyShopBtn.TextSize = math.max(14, math.floor(px(15)))
        skinEmptyShopBtn.AutomaticSize = Enum.AutomaticSize.X
        skinEmptyShopBtn.Size = UDim2.new(0, 0, 0, px(36))
        skinEmptyShopBtn.AnchorPoint = Vector2.new(0.5, 0)
        skinEmptyShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
        Instance.new("UICorner", skinEmptyShopBtn).CornerRadius = UDim.new(0, px(8))
        local sesBtnPad = Instance.new("UIPadding", skinEmptyShopBtn)
        sesBtnPad.PaddingLeft = UDim.new(0, px(20)); sesBtnPad.PaddingRight = UDim.new(0, px(20))
        local sesBtnStroke = Instance.new("UIStroke", skinEmptyShopBtn)
        sesBtnStroke.Color = Color3.fromRGB(0, 0, 0); sesBtnStroke.Thickness = 1.5; sesBtnStroke.Transparency = 0.15

        skinEmptyShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("skins") end
            end
        end)

        -- ── Details panel (right side) ──────────────────────────────────
        local skinDetailsPanel = Instance.new("Frame")
        skinDetailsPanel.Name = "SkinDetailsPanel"
        skinDetailsPanel.BackgroundColor3 = CARD_BG
        skinDetailsPanel.Size = UDim2.new(0, DETAIL_W, 1, 0)
        skinDetailsPanel.AnchorPoint = Vector2.new(1, 0)
        skinDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
        skinDetailsPanel.Parent = skinsArea
        Instance.new("UICorner", skinDetailsPanel).CornerRadius = UDim.new(0, px(12))
        local sdpStroke = Instance.new("UIStroke", skinDetailsPanel)
        sdpStroke.Color = CARD_STROKE; sdpStroke.Thickness = 1.4; sdpStroke.Transparency = 0.2

        -- Placeholder
        local skinDetailPlaceholder = Instance.new("TextLabel", skinDetailsPanel)
        skinDetailPlaceholder.Name = "Placeholder"
        skinDetailPlaceholder.BackgroundTransparency = 1
        skinDetailPlaceholder.Font = Enum.Font.GothamMedium
        skinDetailPlaceholder.Text = "Select a skin"
        skinDetailPlaceholder.TextColor3 = DIM_TEXT
        skinDetailPlaceholder.TextSize = px(22)
        skinDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
        skinDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
        skinDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

        -- Detail content
        local skinDetailContent = Instance.new("Frame", skinDetailsPanel)
        skinDetailContent.Name = "DetailContent"
        skinDetailContent.BackgroundTransparency = 1
        skinDetailContent.Size = UDim2.new(1, 0, 1, 0)
        skinDetailContent.Visible = false

        local sdPad = Instance.new("UIPadding", skinDetailContent)
        sdPad.PaddingTop  = UDim.new(0, px(12)); sdPad.PaddingBottom = UDim.new(0, px(12))
        sdPad.PaddingLeft = UDim.new(0, px(12)); sdPad.PaddingRight  = UDim.new(0, px(12))

        -- 3D preview area with rarity background
        local skinPreviewVP = Instance.new("ViewportFrame", skinDetailContent)
        skinPreviewVP.Name = "PreviewViewport"
        skinPreviewVP.BackgroundColor3 = RARITY_BG_COLORS.Common
        skinPreviewVP.Size = UDim2.new(1, 0, 0, px(170))
        skinPreviewVP.Ambient = Color3.fromRGB(100, 100, 120)
        Instance.new("UICorner", skinPreviewVP).CornerRadius = UDim.new(0, px(10))
        local skinIconStroke = Instance.new("UIStroke", skinPreviewVP)
        skinIconStroke.Color = RARITY_COLORS.Common; skinIconStroke.Thickness = 1.5; skinIconStroke.Transparency = 0.3

        local skinPreviewImage = Instance.new("ImageLabel", skinPreviewVP)
        skinPreviewImage.Name = "PreviewImage"
        skinPreviewImage.BackgroundTransparency = 1
        skinPreviewImage.Size = UDim2.new(0.9, 0, 0.9, 0)
        skinPreviewImage.AnchorPoint = Vector2.new(0.5, 0.5)
        skinPreviewImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        skinPreviewImage.ScaleType = Enum.ScaleType.Fit
        skinPreviewImage.Visible = false
        skinPreviewImage.ZIndex = 2

        -- Skin name
        local skinDetailName = Instance.new("TextLabel", skinDetailContent)
        skinDetailName.Name = "SkinName"
        skinDetailName.BackgroundTransparency = 1
        skinDetailName.Font = Enum.Font.GothamBold
        skinDetailName.TextColor3 = WHITE
        skinDetailName.TextSize = px(26)
        skinDetailName.TextXAlignment = Enum.TextXAlignment.Center
        skinDetailName.Size = UDim2.new(1, 0, 0, px(34))
        skinDetailName.Position = UDim2.new(0, 0, 0, px(178))
        skinDetailName.TextTruncate = Enum.TextTruncate.AtEnd

        -- Rarity label
        local skinDetailRarity = Instance.new("TextLabel", skinDetailContent)
        skinDetailRarity.Name = "Rarity"
        skinDetailRarity.BackgroundTransparency = 1
        skinDetailRarity.Font = Enum.Font.GothamBold
        skinDetailRarity.TextColor3 = RARITY_COLORS.Common
        skinDetailRarity.TextSize = px(19)
        skinDetailRarity.TextXAlignment = Enum.TextXAlignment.Center
        skinDetailRarity.Size = UDim2.new(1, 0, 0, px(26))
        skinDetailRarity.Position = UDim2.new(0, 0, 0, px(214))

        -- Description
        local skinDetailDesc = Instance.new("TextLabel", skinDetailContent)
        skinDetailDesc.Name = "Description"
        skinDetailDesc.BackgroundTransparency = 1
        skinDetailDesc.Font = Enum.Font.GothamBold
        skinDetailDesc.TextColor3 = DIM_TEXT
        skinDetailDesc.TextSize = px(17)
        skinDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
        skinDetailDesc.TextWrapped = true
        skinDetailDesc.Size = UDim2.new(1, 0, 0, px(46))
        skinDetailDesc.Position = UDim2.new(0, 0, 0, px(244))
        local skinDescStroke = Instance.new("UIStroke", skinDetailDesc)
        skinDescStroke.Color = Color3.fromRGB(0, 0, 0)
        skinDescStroke.Thickness = 1.5
        skinDescStroke.Transparency = 0.15

        -- Hide Helm toggle row
        local TOGGLE_ON_C  = Color3.fromRGB(35, 190, 75)
        local TOGGLE_OFF_C = Color3.fromRGB(45, 48, 65)
        local KNOB_C       = Color3.fromRGB(255, 255, 255)

        local helmRow = Instance.new("Frame", skinDetailContent)
        helmRow.Name = "HelmToggleRow"
        helmRow.BackgroundTransparency = 1
        helmRow.Size = UDim2.new(1, 0, 0, px(32))
        helmRow.Position = UDim2.new(0, 0, 0, px(296))

        local helmLabel = Instance.new("TextLabel", helmRow)
        helmLabel.BackgroundTransparency = 1
        helmLabel.Font = Enum.Font.GothamBold
        helmLabel.Text = "Hide Helm"
        helmLabel.TextColor3 = DIM_TEXT
        helmLabel.TextSize = px(17)
        helmLabel.TextXAlignment = Enum.TextXAlignment.Left
        helmLabel.Size = UDim2.new(0.6, 0, 1, 0)
        local helmLabelStroke = Instance.new("UIStroke", helmLabel)
        helmLabelStroke.Color = Color3.fromRGB(0, 0, 0)
        helmLabelStroke.Thickness = 1.5
        helmLabelStroke.Transparency = 0.15

        local helmToggleBg = Instance.new("TextButton", helmRow)
        helmToggleBg.Name = "ToggleBg"
        helmToggleBg.Text = ""
        helmToggleBg.AutoButtonColor = false
        helmToggleBg.Size = UDim2.new(0, px(44), 0, px(24))
        helmToggleBg.AnchorPoint = Vector2.new(1, 0.5)
        helmToggleBg.Position = UDim2.new(1, 0, 0.5, 0)
        helmToggleBg.BorderSizePixel = 0
        Instance.new("UICorner", helmToggleBg).CornerRadius = UDim.new(1, 0)

        local helmKnob = Instance.new("Frame", helmToggleBg)
        helmKnob.Name = "Knob"
        helmKnob.BackgroundColor3 = KNOB_C
        helmKnob.Size = UDim2.new(0, px(18), 0, px(18))
        helmKnob.AnchorPoint = Vector2.new(0, 0.5)
        helmKnob.BorderSizePixel = 0
        Instance.new("UICorner", helmKnob).CornerRadius = UDim.new(1, 0)

        local function syncHelmToggle()
            local hideHelm = _G.PlayerSettings and (_G.PlayerSettings.ShowHelm == false)
            if hideHelm == nil then hideHelm = false end
            helmToggleBg.BackgroundColor3 = hideHelm and TOGGLE_ON_C or TOGGLE_OFF_C
            helmKnob.Position = hideHelm and UDim2.new(1, -px(21), 0.5, 0) or UDim2.new(0, px(3), 0.5, 0)
        end
        syncHelmToggle()

        helmToggleBg.MouseButton1Click:Connect(function()
            if not _G.PlayerSettings then return end
            local hideHelm = (_G.PlayerSettings.ShowHelm == false)
            local newHideHelm = not hideHelm
            local newShowHelm = not newHideHelm
            _G.PlayerSettings.ShowHelm = newShowHelm
            syncHelmToggle()
            -- Fire to server (same as OptionsUI)
            local updateEV = ReplicatedStorage:FindFirstChild("UpdatePlayerSetting")
            if updateEV and updateEV:IsA("RemoteEvent") then
                updateEV:FireServer("ShowHelm", newShowHelm)
            end
            -- Call global ApplySettings if available
            if _G.ApplySettings then
                pcall(_G.ApplySettings, _G.PlayerSettings)
            end
            -- Refresh skin preview on helm toggle
            if selectedSkinId then
                updateSkinDetailPreview(skinPreviewVP, skinPreviewImage, selectedSkinId, SkinDefs, SkinPreview)
            end
        end)

        -- Equip button
        local skinEquipBtn = Instance.new("TextButton", skinDetailContent)
        skinEquipBtn.Name = "EquipBtn"
        skinEquipBtn.AutoButtonColor = false
        skinEquipBtn.BackgroundColor3 = BTN_BG
        skinEquipBtn.Font = Enum.Font.GothamBold
        skinEquipBtn.Text = "EQUIP"
        skinEquipBtn.TextColor3 = WHITE
        skinEquipBtn.TextTransparency = 0
        skinEquipBtn.TextSize = px(22)
        skinEquipBtn.Size = UDim2.new(0.88, 0, 0, px(52))
        skinEquipBtn.AnchorPoint = Vector2.new(0.5, 1)
        skinEquipBtn.Position = UDim2.new(0.5, 0, 1, 0)
        Instance.new("UICorner", skinEquipBtn).CornerRadius = UDim.new(0, px(10))
        local skinEquipStroke = Instance.new("UIStroke", skinEquipBtn)
        skinEquipStroke.Color = Color3.fromRGB(0, 0, 0); skinEquipStroke.Thickness = 1.5; skinEquipStroke.Transparency = 0.15

        -- Action row (Favorite only – no salvage for skins)
        local skinActionRow = Instance.new("Frame", skinDetailContent)
        skinActionRow.Name = "ActionRow"
        skinActionRow.BackgroundTransparency = 1
        skinActionRow.Size = UDim2.new(0.88, 0, 0, px(44))
        skinActionRow.AnchorPoint = Vector2.new(0.5, 1)
        skinActionRow.Position = UDim2.new(0.5, 0, 1, -px(58))

        local SKIN_FAV_YELLOW = Color3.fromRGB(255, 210, 50)
        local SKIN_FAV_DIM    = Color3.fromRGB(100, 100, 120)

        local skinFavBtn = Instance.new("TextButton", skinActionRow)
        skinFavBtn.Name = "FavoriteBtn"
        skinFavBtn.AutoButtonColor = false
        skinFavBtn.BackgroundColor3 = Color3.fromRGB(36, 38, 56)
        skinFavBtn.Font = Enum.Font.GothamBold
        skinFavBtn.Text = "\u{2606}"
        skinFavBtn.TextColor3 = SKIN_FAV_DIM
        skinFavBtn.TextSize = px(24)
        skinFavBtn.Size = UDim2.new(1, 0, 1, 0)
        Instance.new("UICorner", skinFavBtn).CornerRadius = UDim.new(0, px(8))
        local skinFavStroke = Instance.new("UIStroke", skinFavBtn)
        skinFavStroke.Color = SKIN_FAV_DIM; skinFavStroke.Thickness = 1.2; skinFavStroke.Transparency = 0.3

        -- Shop nav button under the grid
        local skinShopNavW = Instance.new("Frame", skinDetailContent)
        skinShopNavW.Name = "ShopNavWrap"
        skinShopNavW.BackgroundTransparency = 1
        skinShopNavW.Size = UDim2.new(0.88, 0, 0, px(36))
        skinShopNavW.AnchorPoint = Vector2.new(0.5, 1)
        skinShopNavW.Position = UDim2.new(0.5, 0, 1, -px(108))

        local skinShopBtn = Instance.new("TextButton", skinShopNavW)
        skinShopBtn.AutoButtonColor = false
        skinShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        skinShopBtn.Font = Enum.Font.GothamBold
        skinShopBtn.Text = "\u{1F6D2}  Browse Skins Shop"
        skinShopBtn.TextColor3 = WHITE
        skinShopBtn.TextTransparency = 0
        skinShopBtn.TextSize = math.max(13, math.floor(px(15)))
        skinShopBtn.AutomaticSize = Enum.AutomaticSize.X
        skinShopBtn.Size = UDim2.new(0, 0, 1, 0)
        skinShopBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        skinShopBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
        Instance.new("UICorner", skinShopBtn).CornerRadius = UDim.new(0, px(8))
        local ssnPad = Instance.new("UIPadding", skinShopBtn)
        ssnPad.PaddingLeft = UDim.new(0, px(14)); ssnPad.PaddingRight = UDim.new(0, px(14))
        local ssnStroke = Instance.new("UIStroke", skinShopBtn)
        ssnStroke.Color = Color3.fromRGB(0, 0, 0); ssnStroke.Thickness = 1.5; ssnStroke.Transparency = 0.15

        skinShopBtn.MouseEnter:Connect(function() TweenService:Create(skinShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
        skinShopBtn.MouseLeave:Connect(function() TweenService:Create(skinShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
        skinShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("skins") end
            end
        end)

        -- ── Helper: update equip button state ───────────────────────────
        local function updateSkinEquipButton()
            if not selectedSkinId then return end
            local isEquipped = (equippedSkinId == selectedSkinId)
            if isEquipped then
                skinEquipBtn.Text = "UNEQUIP"
                skinEquipBtn.BackgroundColor3 = Color3.fromRGB(58, 34, 42)
                skinEquipBtn.TextColor3 = WHITE
                skinEquipStroke.Color = RED_TEXT; skinEquipStroke.Transparency = 0.35
            else
                skinEquipBtn.Text = "EQUIP"
                skinEquipBtn.BackgroundColor3 = BTN_BG
                skinEquipBtn.TextColor3 = WHITE
                skinEquipStroke.Color = Color3.fromRGB(0, 0, 0); skinEquipStroke.Transparency = 0.15
            end
        end

        -- ── Helper: update favorite button state ────────────────────────
        local function updateSkinFavButton()
            if not selectedSkinId then return end
            local isFav = favoritedSkins[selectedSkinId] == true
            skinFavBtn.Text = isFav and "\u{2605}" or "\u{2606}"
            skinFavBtn.TextColor3 = isFav and SKIN_FAV_YELLOW or SKIN_FAV_DIM
            skinFavStroke.Color   = isFav and SKIN_FAV_YELLOW or SKIN_FAV_DIM
        end

        -- ── Helper: update card highlights ──────────────────────────────
        local function refreshSkinCards()
            local visibleCount = 0
            for sid, info in pairs(skinCards) do
                local sOwned = ownedSkinSet[sid] == true
                if sOwned then
                    info.card.Visible = true
                    visibleCount = visibleCount + 1
                else
                    info.card.Visible = false
                end

                -- Selection highlight
                local isSelected = (selectedSkinId == sid)
                local isEquippedCard = (equippedSkinId == sid)
                local targetBg = info.baseBg or CARD_BG

                if isSelected then
                    targetBg = info.selectedBg or CARD_BG
                    setCardStroke(info.cardStroke, GOLD, 2.5, 0)
                elseif isEquippedCard then
                    targetBg = info.equippedBg or CARD_EQUIPPED
                    setCardStroke(info.cardStroke, GREEN_GLOW, 2.0, 0.16)
                else
                    setCardStroke(info.cardStroke, info.baseStrokeColor, info.baseStrokeThickness, info.baseStrokeTransparency)
                end
                info.card.BackgroundColor3 = targetBg
                if info.accentBar then
                    info.accentBar.BackgroundColor3 = isEquippedCard and GREEN_GLOW or (info.accentColor or GOLD)
                    info.accentBar.BackgroundTransparency = isEquippedCard and 0 or 0.1
                end

                -- Equipped bar at bottom of card
                local eqBar = info.card:FindFirstChild("EquippedBar")
                if eqBar then eqBar.Visible = isEquippedCard end

                -- Favorite star on card
                local favStar = info.card:FindFirstChild("FavStar")
                if favStar then favStar.Visible = (favoritedSkins[sid] == true) end
            end
            skinEmptyState.Visible = (visibleCount == 0)
            skinGridScroll.Visible = (visibleCount > 0)
        end

        -- ── Helper: select a skin (update details panel) ────────────────
        local function setSelectedSkin(skinId)
            selectedSkinId = skinId
            if not skinId then
                skinDetailPlaceholder.Visible = true
                skinDetailContent.Visible = false
                refreshSkinCards()
                return
            end
            skinDetailPlaceholder.Visible = false
            skinDetailContent.Visible = true

            local def = SkinDefs and SkinDefs.GetById(skinId)
            if not def then return end

            local isDefault = def.IsDefault or false
            local rarity = def.Rarity or "Common"
            local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
            local rarityBg = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common
            local skinColor = def.ArmorColor or Color3.fromRGB(150, 150, 155)

            skinDetailName.Text = def.DisplayName or skinId
            skinDetailName.TextColor3 = isDefault and WHITE or brightenColor(rarityColor, 0.1)
            skinDetailRarity.Text = rarity
            skinDetailRarity.TextColor3 = rarityColor
            skinDetailDesc.Text = def.Description or ""
            skinPreviewVP.BackgroundColor3 = mixColor(rarityBg, skinColor, isDefault and 0.05 or 0.18)
            skinIconStroke.Color = rarityColor
            skinIconStroke.Transparency = 0.12
            sdpStroke.Color = rarityColor
            sdpStroke.Transparency = 0.14

            -- Update 3D preview
            updateSkinDetailPreview(skinPreviewVP, skinPreviewImage, skinId, SkinDefs, SkinPreview)

            updateSkinEquipButton()
            updateSkinFavButton()
            syncHelmToggle()
            refreshSkinCards()
        end

        -- ── Equip click ─────────────────────────────────────────────────
        skinEquipBtn.MouseButton1Click:Connect(function()
            if not selectedSkinId then return end
            local def = SkinDefs and SkinDefs.GetById(selectedSkinId)
            if not def then return end
            local isOwn = ownedSkinSet[selectedSkinId] == true
            if not isOwn then return end

            local willUnequip = (equippedSkinId == selectedSkinId)
            local sRemotes = ensureSkinRemotes()
            if sRemotes and sRemotes.equip and sRemotes.equip:IsA("RemoteEvent") then
                pcall(function() sRemotes.equip:FireServer(selectedSkinId) end)
            end
            equippedSkinId = willUnequip and nil or selectedSkinId
            updateSkinEquipButton()
            refreshSkinCards()
        end)

        -- Equip button hover
        if not game:GetService("UserInputService").TouchEnabled then
            skinEquipBtn.MouseEnter:Connect(function()
                if selectedSkinId then
                    local hoverColor = (equippedSkinId == selectedSkinId) and Color3.fromRGB(92, 42, 52) or GREEN_BTN
                    TweenService:Create(skinEquipBtn, TWEEN_QUICK, {BackgroundColor3 = hoverColor}):Play()
                end
            end)
            skinEquipBtn.MouseLeave:Connect(function()
                updateSkinEquipButton()
            end)
        end

        -- ── Favorite click ──────────────────────────────────────────────
        skinFavBtn.MouseButton1Click:Connect(function()
            if not selectedSkinId then return end
            local newState = not (favoritedSkins[selectedSkinId] == true)
            favoritedSkins[selectedSkinId] = newState or nil
            updateSkinFavButton()
            refreshSkinCards()
            -- Persist to server
            local sRemotes = ensureSkinRemotes()
            if sRemotes and sRemotes.favorite and sRemotes.favorite:IsA("RemoteFunction") then
                task.spawn(function()
                    pcall(function() sRemotes.favorite:InvokeServer(selectedSkinId, newState) end)
                end)
            end
        end)

        local function createSkinCard(i_sk, def)
            local skinId      = def.Id
            local displayName = def.DisplayName or skinId
            local isDefault   = def.IsDefault or false
            local isEpic      = (def.Rarity == "Epic")
            local skinColor   = def.ArmorColor or Color3.fromRGB(150, 150, 155)
            local accentColor = def.AccentColor or skinColor
            local rarity      = def.Rarity or "Common"
            local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
            local rarityBg    = WEAPON_CARD_BG[rarity] or WEAPON_CARD_BG.Common
            local baseBg      = mixColor(rarityBg, skinColor, isDefault and 0.04 or 0.14)
            local selectedBg  = brightenColor(baseBg, 0.05)
            local equippedBg  = mixColor(baseBg, GREEN_GLOW, 0.16)

            local card = Instance.new("TextButton")
            card.Name = "SkinCard_" .. skinId
            card.BackgroundColor3 = baseBg
            card.Size = UDim2.new(1, 0, 1, 0)
            card.Text = ""
            card.AutoButtonColor = false
            card.BorderSizePixel = 0
            card.LayoutOrder = isDefault and 0 or i_sk
            card.ClipsDescendants = true
            card.Parent = skinGridScroll
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, INV_CARD.CornerRadius)

            local baseStrokeColor = WEAPON_CARD_BORDER[rarity] or shadeColor(rarityColor, 0.65)
            local baseStrokeThickness = isEpic and 2.0 or 1.7
            local baseStrokeTransparency = isEpic and 0.08 or 0.16
            local sCS = Instance.new("UIStroke", card)
            sCS.Color = baseStrokeColor
            sCS.Thickness = baseStrokeThickness
            sCS.Transparency = baseStrokeTransparency
            addCardSheen(card, rarityColor)
            local accentBar = addCardAccentBar(card, accentColor)

            do
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = displayName
                cardName.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                cardName.TextSize = INV_CARD.NameTextSize
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, INV_CARD.NameHeight)
                cardName.Position = UDim2.new(0, px(5), 0, INV_CARD.NameY)
                cardName.ZIndex = 3
                addTextOutline(cardName, 0.18, 1.35)
            end

            do
                local iconArea = Instance.new("Frame", card)
                iconArea.Name = "IconArea"
                iconArea.BackgroundColor3 = mixColor(RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common, skinColor, isDefault and 0.06 or 0.26)
                iconArea.Size = UDim2.new(0, INV_CARD.IconSize, 0, INV_CARD.IconSize)
                iconArea.AnchorPoint = Vector2.new(0.5, 0)
                iconArea.Position = UDim2.new(0.5, 0, 0, INV_CARD.IconY)
                iconArea.BorderSizePixel = 0
                Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, INV_CARD.IconCorner)
                addIconWellHighlight(iconArea, accentColor)

                local cardIcon = Instance.new("TextLabel", iconArea)
                cardIcon.Name = "Icon"
                cardIcon.BackgroundTransparency = 1
                cardIcon.Font = Enum.Font.GothamBold
                cardIcon.Text = isDefault and "\u{1F464}" or "\u{1F6E1}"
                cardIcon.TextScaled = true
                cardIcon.TextColor3 = isDefault and DIM_TEXT or skinColor
                cardIcon.Size = UDim2.new(0.72, 0, 0.72, 0)
                cardIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                cardIcon.Position = UDim2.new(0.5, 0, 0.46, 0)
                cardIcon.ZIndex = 3
                addTextOutline(cardIcon, 0.22, 1.4)

                local cardIconImage = Instance.new("ImageLabel", iconArea)
                cardIconImage.Name = "IconImage"
                cardIconImage.BackgroundTransparency = 1
                cardIconImage.Size = UDim2.new(0.76, 0, 0.76, 0)
                cardIconImage.AnchorPoint = Vector2.new(0.5, 0.5)
                cardIconImage.Position = UDim2.new(0.5, 0, 0.46, 0)
                cardIconImage.ScaleType = Enum.ScaleType.Fit
                cardIconImage.ZIndex = 4
                cardIconImage.Visible = false

                local skinImage = getSkinIconImage(def)
                if skinImage then
                    cardIconImage.Image = skinImage
                    cardIconImage.Visible = true
                    cardIcon.Visible = false
                end

                local swatchWrap = Instance.new("Frame", iconArea)
                swatchWrap.Name = "ArmorSwatch"
                swatchWrap.BackgroundColor3 = skinColor
                swatchWrap.BorderSizePixel = 0
                swatchWrap.Size = UDim2.new(0.62, 0, 0, px(8))
                swatchWrap.AnchorPoint = Vector2.new(0.5, 1)
                swatchWrap.Position = UDim2.new(0.5, 0, 0.92, 0)
                swatchWrap.ZIndex = 4
                Instance.new("UICorner", swatchWrap).CornerRadius = UDim.new(0.5, 0)
                Instance.new("UIGradient", swatchWrap).Color = ColorSequence.new(skinColor, accentColor)
                local swatchStroke = Instance.new("UIStroke", swatchWrap)
                swatchStroke.Color = accentColor
                swatchStroke.Thickness = 1
                swatchStroke.Transparency = 0.24
            end

            do
                local rarityPill = Instance.new("Frame", card)
                rarityPill.Name = "RarityPill"
                rarityPill.BackgroundColor3 = mixColor(baseBg, Color3.fromRGB(8, 10, 18), 0.28)
                rarityPill.BorderSizePixel = 0
                rarityPill.Size = UDim2.new(0.76, 0, 0, INV_CARD.Line2Height + px(4))
                rarityPill.AnchorPoint = Vector2.new(0.5, 1)
                rarityPill.Position = UDim2.new(0.5, 0, 1, -INV_CARD.Line2OffBottom)
                rarityPill.ZIndex = 3
                Instance.new("UICorner", rarityPill).CornerRadius = UDim.new(0, px(7))
                local rarityPillStroke = Instance.new("UIStroke", rarityPill)
                rarityPillStroke.Color = rarityColor
                rarityPillStroke.Thickness = 1
                rarityPillStroke.Transparency = 0.42

                local cardRarity = Instance.new("TextLabel", rarityPill)
                cardRarity.Name = "RarityLabel"
                cardRarity.BackgroundTransparency = 1
                cardRarity.Font = Enum.Font.GothamBold
                cardRarity.Text = rarity
                cardRarity.TextColor3 = rarityColor
                cardRarity.TextSize = INV_CARD.Line1TextSize
                cardRarity.TextXAlignment = Enum.TextXAlignment.Center
                cardRarity.Size = UDim2.new(1, -px(6), 1, 0)
                cardRarity.Position = UDim2.new(0, px(3), 0, 0)
                cardRarity.ZIndex = 4
                addTextOutline(cardRarity, 0.3, 1)
            end

            do
                local eqBar = Instance.new("Frame", card)
                eqBar.Name = "EquippedBar"
                eqBar.BackgroundColor3 = GREEN_GLOW
                eqBar.Size = UDim2.new(1, 0, 0, px(3))
                eqBar.AnchorPoint = Vector2.new(0, 1)
                eqBar.Position = UDim2.new(0, 0, 1, 0)
                eqBar.BorderSizePixel = 0
                eqBar.ZIndex = 5
                eqBar.Visible = false
            end

            do
                local favStar = Instance.new("TextLabel", card)
                favStar.Name = "FavStar"
                favStar.BackgroundTransparency = 1
                favStar.Font = Enum.Font.GothamBold
                favStar.Text = "\u{2605}"
                favStar.TextColor3 = SKIN_FAV_YELLOW
                favStar.TextSize = math.max(14, math.floor(px(16)))
                favStar.Size = UDim2.new(0, px(20), 0, px(20))
                favStar.AnchorPoint = Vector2.new(1, 0)
                favStar.Position = UDim2.new(1, -px(4), 0, px(3))
                favStar.ZIndex = 8
                favStar.Visible = false
                addTextOutline(favStar, 0.2, 1.2)
            end

            skinCards[skinId] = {
                card = card,
                cardStroke = sCS,
                isDefault = isDefault,
                accentBar = accentBar,
                accentColor = accentColor,
                baseBg = baseBg,
                hoverBg = brightenColor(baseBg, 0.07),
                selectedBg = selectedBg,
                equippedBg = equippedBg,
                baseStrokeColor = baseStrokeColor,
                baseStrokeThickness = baseStrokeThickness,
                baseStrokeTransparency = baseStrokeTransparency,
            }

            -- Click to select
            card.MouseButton1Click:Connect(function()
                setSelectedSkin(skinId)
            end)

            -- Hover effect
            if not game:GetService("UserInputService").TouchEnabled then
                card.MouseEnter:Connect(function()
                    if selectedSkinId ~= skinId then
                        local refs = skinCards[skinId]
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = refs and refs.hoverBg or brightenColor(baseBg, 0.07)}):Play()
                    end
                end)
                card.MouseLeave:Connect(function()
                    if selectedSkinId ~= skinId then
                        local isEq = (equippedSkinId == skinId)
                        local refs = skinCards[skinId]
                        local targetBg = refs and (isEq and refs.equippedBg or refs.baseBg) or baseBg
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = targetBg}):Play()
                    end
                end)
            end
        end

        -- ── Create skin cards ───────────────────────────────────────────
        for i_sk, def in ipairs(allSkinDefs) do
            createSkinCard(i_sk, def)
        end

        -- ── Fetch data from server ──────────────────────────────────────
        task.spawn(function()
            local sRemotes = ensureSkinRemotes()
            if not sRemotes then return end
            -- Owned skins
            if sRemotes.getOwned and sRemotes.getOwned:IsA("RemoteFunction") then
                local ok, list = pcall(function() return sRemotes.getOwned:InvokeServer() end)
                if ok and type(list) == "table" then
                    for _, id in ipairs(list) do ownedSkinSet[id] = true end
                end
            end
            -- Equipped skin
            if sRemotes.getEquipped and sRemotes.getEquipped:IsA("RemoteFunction") then
                local ok, equipped = pcall(function() return sRemotes.getEquipped:InvokeServer() end)
                if ok then equippedSkinId = (type(equipped) == "string") and equipped or nil end
            end
            -- Favorites
            if sRemotes.getFavorites and sRemotes.getFavorites:IsA("RemoteFunction") then
                local ok, favs = pcall(function() return sRemotes.getFavorites:InvokeServer() end)
                if ok and type(favs) == "table" then favoritedSkins = favs end
            end
            refreshSkinCards()
            -- Listen for equip changes
            if sRemotes.changed and sRemotes.changed:IsA("RemoteEvent") then
                sRemotes.changed.OnClientEvent:Connect(function(newEquipped)
                    equippedSkinId = (type(newEquipped) == "string") and newEquipped or nil
                    updateSkinEquipButton()
                    refreshSkinCards()
                end)
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  EFFECTS PAGE  (dash trail equip – split layout with preview)
    -- ══════════════════════════════════════════════════════════════════════
    local effectsPage = Instance.new("Frame")
    effectsPage.Name = "EffectsPage"; effectsPage.BackgroundTransparency = 1
    effectsPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    effectsPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    effectsPage.Visible = false; effectsPage.Parent = root

    local _stopEffectsPreview = nil  -- set inside do block, called on tab switch

    do
        local EffectDefs = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
            if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
        end)

        local EffectsPreview = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EffectsPreview")
            if mod and mod:IsA("ModuleScript") then EffectsPreview = require(mod) end
        end)
        if EffectsPreview then
            _stopEffectsPreview = function() EffectsPreview.Stop() end
        end

        local effectRemotes = nil
        local function ensureEffectRemotes()
            if effectRemotes then return effectRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local ef = rf:FindFirstChild("Effects") or rf:WaitForChild("Effects", 5)
            if not ef then return nil end
            effectRemotes = {
                getOwned    = ef:FindFirstChild("GetOwnedEffects"),
                equip       = ef:FindFirstChild("EquipEffect"),
                getEquipped = ef:FindFirstChild("GetEquippedEffects"),
                changed     = ef:FindFirstChild("EquippedEffectsChanged"),
            }
            return effectRemotes
        end

        local allTrailDefs = EffectDefs and EffectDefs.GetBySubType("DashTrail") or {}

        if #allTrailDefs > 0 then
            -- ── Left side: scrolling card grid ──────────────────────────
            local trailGridScroll = Instance.new("ScrollingFrame")
            trailGridScroll.Name = "TrailGridScroll"
            trailGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
            trailGridScroll.BackgroundTransparency = 0.5
            trailGridScroll.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
            trailGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            trailGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            trailGridScroll.ScrollBarThickness = px(4)
            trailGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
            trailGridScroll.BorderSizePixel = 0
            trailGridScroll.Parent = effectsPage
            Instance.new("UICorner", trailGridScroll).CornerRadius = UDim.new(0, px(10))

            local trailGridLayout = Instance.new("UIGridLayout", trailGridScroll)
            trailGridLayout.CellSize = UDim2.new(0, px(140), 0, px(178))
            trailGridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
            trailGridLayout.FillDirection = Enum.FillDirection.Horizontal
            trailGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            trailGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

            local trailGridPad = Instance.new("UIPadding", trailGridScroll)
            trailGridPad.PaddingTop    = UDim.new(0, px(8))
            trailGridPad.PaddingLeft   = UDim.new(0, px(8))
            trailGridPad.PaddingRight  = UDim.new(0, px(8))
            trailGridPad.PaddingBottom = UDim.new(0, px(8))
            bindFixedColumnGrid(trailGridScroll, trailGridLayout, trailGridPad, 140, 178)

            -- Empty state (overlays the grid area)
            local effectsEmptyState = Instance.new("Frame")
            effectsEmptyState.Name = "EffectsEmptyState"
            effectsEmptyState.BackgroundTransparency = 1
            effectsEmptyState.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
            effectsEmptyState.Visible = false
            effectsEmptyState.Parent = effectsPage

            local eeCard = Instance.new("Frame", effectsEmptyState)
            eeCard.BackgroundColor3 = accentPanelColor(Color3.fromRGB(214, 138, 206), 0.22); eeCard.Size = UDim2.new(0.7, 0, 0, px(130))
            eeCard.AnchorPoint = Vector2.new(0.5, 0.5); eeCard.Position = UDim2.new(0.5, 0, 0.45, 0)
            Instance.new("UICorner", eeCard).CornerRadius = UDim.new(0, px(14))
            local eeStroke = Instance.new("UIStroke", eeCard)
            eeStroke.Color = Color3.fromRGB(214, 138, 206); eeStroke.Thickness = 1.4; eeStroke.Transparency = 0.22
            addCardSheen(eeCard, Color3.fromRGB(214, 138, 206))

            local eeL = Instance.new("TextLabel", eeCard)
            eeL.BackgroundTransparency = 1; eeL.Font = Enum.Font.GothamMedium
            eeL.Text = "You don't own any effects yet.\nVisit the shop to unlock more."
            eeL.TextColor3 = DIM_TEXT; eeL.TextSize = math.max(13, math.floor(px(14)))
            eeL.TextWrapped = true; eeL.Size = UDim2.new(0.85, 0, 0, px(60))
            eeL.AnchorPoint = Vector2.new(0.5, 0.5); eeL.Position = UDim2.new(0.5, 0, 0.5, 0)
            eeL.TextXAlignment = Enum.TextXAlignment.Center

            local eeShopBtn = Instance.new("TextButton", effectsEmptyState)
            eeShopBtn.Name = "ShopNavBtn"; eeShopBtn.AutoButtonColor = false
            eeShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT; eeShopBtn.Font = Enum.Font.GothamBold
            eeShopBtn.Text = "\u{1F6D2}  Browse Effects Shop"; eeShopBtn.TextColor3 = WHITE
            eeShopBtn.TextTransparency = 0
            eeShopBtn.TextSize = math.max(14, math.floor(px(15))); eeShopBtn.AutomaticSize = Enum.AutomaticSize.X
            eeShopBtn.Size = UDim2.new(0, 0, 0, px(36)); eeShopBtn.AnchorPoint = Vector2.new(0.5, 0)
            eeShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
            Instance.new("UICorner", eeShopBtn).CornerRadius = UDim.new(0, px(8))
            local eesPad = Instance.new("UIPadding", eeShopBtn)
            eesPad.PaddingLeft = UDim.new(0, px(20)); eesPad.PaddingRight = UDim.new(0, px(20))
            local eesStroke = Instance.new("UIStroke", eeShopBtn)
            eesStroke.Color = Color3.fromRGB(0, 0, 0); eesStroke.Thickness = 1.5; eesStroke.Transparency = 0.15
            eeShopBtn.MouseButton1Click:Connect(function()
                local mc = _G.SideUI and _G.SideUI.MenuController
                if mc then mc.OpenMenu("Shop")
                    if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("effects") end
                end
            end)

            -- ── Right side: details panel ───────────────────────────────
            local trailDetailsPanel = Instance.new("Frame")
            trailDetailsPanel.Name = "TrailDetailsPanel"
            trailDetailsPanel.BackgroundColor3 = CARD_BG
            trailDetailsPanel.Size = UDim2.new(0, DETAIL_W, 1, 0)
            trailDetailsPanel.AnchorPoint = Vector2.new(1, 0)
            trailDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
            trailDetailsPanel.Parent = effectsPage
            Instance.new("UICorner", trailDetailsPanel).CornerRadius = UDim.new(0, px(12))
            local tdpStroke = Instance.new("UIStroke", trailDetailsPanel)
            tdpStroke.Color = CARD_STROKE; tdpStroke.Thickness = 1.4; tdpStroke.Transparency = 0.2

            -- Placeholder text
            local trailDetailPlaceholder = Instance.new("TextLabel", trailDetailsPanel)
            trailDetailPlaceholder.Name = "Placeholder"
            trailDetailPlaceholder.BackgroundTransparency = 1
            trailDetailPlaceholder.Font = Enum.Font.GothamMedium
            trailDetailPlaceholder.Text = "Select a trail"
            trailDetailPlaceholder.TextColor3 = DIM_TEXT
            trailDetailPlaceholder.TextSize = px(22)
            trailDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
            trailDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
            trailDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

            -- Detail content (hidden until selection)
            local trailDetailContent = Instance.new("Frame", trailDetailsPanel)
            trailDetailContent.Name = "DetailContent"
            trailDetailContent.BackgroundTransparency = 1
            trailDetailContent.Size = UDim2.new(1, 0, 1, 0)
            trailDetailContent.Visible = false

            local tdPad = Instance.new("UIPadding", trailDetailContent)
            tdPad.PaddingTop  = UDim.new(0, px(12)); tdPad.PaddingBottom = UDim.new(0, px(12))
            tdPad.PaddingLeft = UDim.new(0, px(12)); tdPad.PaddingRight  = UDim.new(0, px(12))

            -- 3D trail preview viewport
            local trailPreviewVP = Instance.new("ViewportFrame", trailDetailContent)
            trailPreviewVP.Name = "PreviewViewport"
            trailPreviewVP.BackgroundColor3 = RARITY_BG_COLORS.Common
            trailPreviewVP.Size = UDim2.new(1, 0, 0, px(200))
            trailPreviewVP.Ambient = Color3.fromRGB(100, 100, 120)
            trailPreviewVP.ClipsDescendants = true
            Instance.new("UICorner", trailPreviewVP).CornerRadius = UDim.new(0, px(10))
            local trailVPStroke = Instance.new("UIStroke", trailPreviewVP)
            trailVPStroke.Color = RARITY_COLORS.Common; trailVPStroke.Thickness = 1.5; trailVPStroke.Transparency = 0.3

            -- Trail name
            local trailDetailName = Instance.new("TextLabel", trailDetailContent)
            trailDetailName.Name = "TrailName"
            trailDetailName.BackgroundTransparency = 1
            trailDetailName.Font = Enum.Font.GothamBold
            trailDetailName.TextColor3 = WHITE
            trailDetailName.TextSize = px(26)
            trailDetailName.TextXAlignment = Enum.TextXAlignment.Center
            trailDetailName.Size = UDim2.new(1, 0, 0, px(34))
            trailDetailName.Position = UDim2.new(0, 0, 0, px(208))
            trailDetailName.TextTruncate = Enum.TextTruncate.AtEnd

            -- Rarity label
            local trailDetailRarity = Instance.new("TextLabel", trailDetailContent)
            trailDetailRarity.Name = "Rarity"
            trailDetailRarity.BackgroundTransparency = 1
            trailDetailRarity.Font = Enum.Font.GothamBold
            trailDetailRarity.TextColor3 = RARITY_COLORS.Common
            trailDetailRarity.TextSize = px(19)
            trailDetailRarity.TextXAlignment = Enum.TextXAlignment.Center
            trailDetailRarity.Size = UDim2.new(1, 0, 0, px(26))
            trailDetailRarity.Position = UDim2.new(0, 0, 0, px(244))

            -- Description
            local trailDetailDesc = Instance.new("TextLabel", trailDetailContent)
            trailDetailDesc.Name = "Description"
            trailDetailDesc.BackgroundTransparency = 1
            trailDetailDesc.Font = Enum.Font.GothamBold
            trailDetailDesc.TextColor3 = DIM_TEXT
            trailDetailDesc.TextSize = px(17)
            trailDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
            trailDetailDesc.TextWrapped = true
            trailDetailDesc.Size = UDim2.new(1, 0, 0, px(46))
            trailDetailDesc.Position = UDim2.new(0, 0, 0, px(274))
            local trailDescStroke = Instance.new("UIStroke", trailDetailDesc)
            trailDescStroke.Color = Color3.fromRGB(0, 0, 0)
            trailDescStroke.Thickness = 1.5
            trailDescStroke.Transparency = 0.15

            -- Equip button (bottom of detail panel)
            local trailEquipBtn = Instance.new("TextButton", trailDetailContent)
            trailEquipBtn.Name = "EquipBtn"
            trailEquipBtn.AutoButtonColor = false
            trailEquipBtn.BackgroundColor3 = BTN_BG
            trailEquipBtn.Font = Enum.Font.GothamBold
            trailEquipBtn.Text = "EQUIP"
            trailEquipBtn.TextColor3 = WHITE
            trailEquipBtn.TextTransparency = 0
            trailEquipBtn.TextSize = px(22)
            trailEquipBtn.Size = UDim2.new(0.88, 0, 0, px(52))
            trailEquipBtn.AnchorPoint = Vector2.new(0.5, 1)
            trailEquipBtn.Position = UDim2.new(0.5, 0, 1, 0)
            Instance.new("UICorner", trailEquipBtn).CornerRadius = UDim.new(0, px(10))
            local trailEquipStroke = Instance.new("UIStroke", trailEquipBtn)
            trailEquipStroke.Color = Color3.fromRGB(0, 0, 0); trailEquipStroke.Thickness = 1.5; trailEquipStroke.Transparency = 0.15

            -- Shop nav button in detail panel
            local trailShopNavW = Instance.new("Frame", trailDetailContent)
            trailShopNavW.Name = "ShopNavWrap"
            trailShopNavW.BackgroundTransparency = 1
            trailShopNavW.Size = UDim2.new(0.88, 0, 0, px(36))
            trailShopNavW.AnchorPoint = Vector2.new(0.5, 1)
            trailShopNavW.Position = UDim2.new(0.5, 0, 1, -px(58))

            local trailShopBtn = Instance.new("TextButton", trailShopNavW)
            trailShopBtn.AutoButtonColor = false
            trailShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
            trailShopBtn.Font = Enum.Font.GothamBold
            trailShopBtn.Text = "\u{1F6D2}  Browse Effects Shop"
            trailShopBtn.TextColor3 = WHITE
            trailShopBtn.TextTransparency = 0
            trailShopBtn.TextSize = math.max(13, math.floor(px(15)))
            trailShopBtn.AutomaticSize = Enum.AutomaticSize.X
            trailShopBtn.Size = UDim2.new(0, 0, 1, 0)
            trailShopBtn.AnchorPoint = Vector2.new(0.5, 0.5)
            trailShopBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
            Instance.new("UICorner", trailShopBtn).CornerRadius = UDim.new(0, px(8))
            local tsnPad = Instance.new("UIPadding", trailShopBtn)
            tsnPad.PaddingLeft = UDim.new(0, px(14)); tsnPad.PaddingRight = UDim.new(0, px(14))
            local tsnStroke = Instance.new("UIStroke", trailShopBtn)
            tsnStroke.Color = Color3.fromRGB(0, 0, 0); tsnStroke.Thickness = 1.5; tsnStroke.Transparency = 0.15

            trailShopBtn.MouseEnter:Connect(function() TweenService:Create(trailShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
            trailShopBtn.MouseLeave:Connect(function() TweenService:Create(trailShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
            trailShopBtn.MouseButton1Click:Connect(function()
                local mc = _G.SideUI and _G.SideUI.MenuController
                if mc then mc.OpenMenu("Shop")
                    if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("effects") end
                end
            end)

            -- ── State ───────────────────────────────────────────────────
            local ownedSet = {}
            local equippedTrailId = nil
            local selectedEffectId = nil
            local effectCards = {}

            -- ── Helper: update equip button ─────────────────────────────
            local function updateTrailEquipButton()
                if not selectedEffectId then return end
                local isEquipped = (equippedTrailId == selectedEffectId)
                if isEquipped then
                    trailEquipBtn.Text = "\u{2714} EQUIPPED"
                    trailEquipBtn.BackgroundColor3 = DISABLED_BG
                    trailEquipBtn.TextColor3 = GREEN_GLOW
                    trailEquipStroke.Color = Color3.fromRGB(0, 0, 0); trailEquipStroke.Transparency = 0.15
                else
                    trailEquipBtn.Text = "EQUIP"
                    trailEquipBtn.BackgroundColor3 = BTN_BG
                    trailEquipBtn.TextColor3 = WHITE
                    trailEquipStroke.Color = Color3.fromRGB(0, 0, 0); trailEquipStroke.Transparency = 0.15
                end
            end

            -- ── Helper: refresh card highlights ─────────────────────────
            local function refreshEffectCards()
                local visibleCount = 0
                for eid, info in pairs(effectCards) do
                    local isOwned = ownedSet[eid] or info.isFree
                    if isOwned then
                        info.card.Visible = true
                        visibleCount = visibleCount + 1
                    else
                        info.card.Visible = false
                    end

                    local isSelected = (selectedEffectId == eid)
                    local isEquipped = (equippedTrailId == eid)
                    local targetBg = info.baseBg

                    if isSelected then
                        targetBg = info.selectedBg
                        setCardStroke(info.cardStroke, GOLD, 2.5, 0)
                    elseif isEquipped then
                        targetBg = info.equippedBg
                        setCardStroke(info.cardStroke, GREEN_GLOW, 2.0, 0.16)
                    else
                        setCardStroke(info.cardStroke, info.baseStrokeColor, info.baseStrokeThickness, info.baseStrokeTransparency)
                    end
                    info.card.BackgroundColor3 = targetBg
                    if info.accentBar then
                        info.accentBar.BackgroundColor3 = isEquipped and GREEN_GLOW or info.accentColor
                        info.accentBar.BackgroundTransparency = isEquipped and 0 or 0.1
                    end

                    local eqBar = info.card:FindFirstChild("EquippedBar")
                    if eqBar then eqBar.Visible = isEquipped end
                end
                effectsEmptyState.Visible = (visibleCount == 0)
                trailGridScroll.Visible = (visibleCount > 0)
            end

            -- ── Helper: select a trail (update detail panel + preview) ──
            local function setSelectedEffect(effectId)
                selectedEffectId = effectId
                if not effectId then
                    trailDetailPlaceholder.Visible = true
                    trailDetailContent.Visible = false
                    if EffectsPreview then EffectsPreview.Stop() end
                    refreshEffectCards()
                    return
                end
                trailDetailPlaceholder.Visible = false
                trailDetailContent.Visible = true

                local def = EffectDefs and EffectDefs.GetById(effectId)
                if not def then return end

                local rarity = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local rarityBg = RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common
                local isEpic = (rarity == "Epic")
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)

                trailDetailName.Text = def.DisplayName or effectId
                trailDetailName.TextColor3 = isEpic and Color3.fromRGB(220, 185, 255) or brightenColor(effectColor, 0.12)
                trailDetailRarity.Text = rarity
                trailDetailRarity.TextColor3 = rarityColor
                trailDetailDesc.Text = def.IsFree and "Free (default)" or (def.Description or "")
                trailPreviewVP.BackgroundColor3 = mixColor(rarityBg, effectColor, def.IsRainbow and 0.1 or 0.2)
                trailVPStroke.Color = rarityColor
                trailVPStroke.Transparency = 0.12
                tdpStroke.Color = rarityColor
                tdpStroke.Transparency = 0.14

                -- Launch 3D trail preview
                if EffectsPreview then
                    EffectsPreview.Update(trailPreviewVP, effectId)
                end

                updateTrailEquipButton()
                refreshEffectCards()
            end

            -- ── Equip click ─────────────────────────────────────────────
            trailEquipBtn.MouseButton1Click:Connect(function()
                if not selectedEffectId then return end
                if equippedTrailId == selectedEffectId then return end
                local def = EffectDefs and EffectDefs.GetById(selectedEffectId)
                if not def then return end
                local isOwn = ownedSet[selectedEffectId] or (def.IsFree == true)
                if not isOwn then return end

                local eRemotes = ensureEffectRemotes()
                if eRemotes and eRemotes.equip and eRemotes.equip:IsA("RemoteEvent") then
                    pcall(function() eRemotes.equip:FireServer(selectedEffectId, "DashTrail") end)
                end
                equippedTrailId = selectedEffectId
                updateTrailEquipButton()
                refreshEffectCards()
            end)

            -- Equip button hover
            if not game:GetService("UserInputService").TouchEnabled then
                trailEquipBtn.MouseEnter:Connect(function()
                    if selectedEffectId and equippedTrailId ~= selectedEffectId then
                        TweenService:Create(trailEquipBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                    end
                end)
                trailEquipBtn.MouseLeave:Connect(function()
                    if selectedEffectId and equippedTrailId ~= selectedEffectId then
                        TweenService:Create(trailEquipBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                    end
                end)
            end

            -- ── Create trail cards ──────────────────────────────────────
            for i_ef, def in ipairs(allTrailDefs) do
                local effectId    = def.Id
                local displayName = def.DisplayName or effectId
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)
                local isFree      = def.IsFree or false
                local isRainbow   = def.IsRainbow == true
                local isEpic      = (def.Rarity == "Epic")
                local rarity      = def.Rarity or "Common"
                local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
                local baseRarityBg = WEAPON_CARD_BG[rarity] or WEAPON_CARD_BG.Common
                local baseBg = mixColor(baseRarityBg, effectColor, isRainbow and 0.1 or 0.18)
                local selectedBg = brightenColor(baseBg, 0.05)
                local equippedBg = mixColor(baseBg, GREEN_GLOW, 0.16)
                local accentColor = isRainbow and Color3.fromRGB(214, 138, 206) or effectColor

                local card = Instance.new("TextButton")
                card.Name = "EffectCard_" .. effectId
                card.BackgroundColor3 = baseBg
                card.Size = UDim2.new(1, 0, 1, 0)
                card.Text = ""
                card.AutoButtonColor = false
                card.BorderSizePixel = 0
                card.LayoutOrder = isFree and 0 or i_ef
                card.ClipsDescendants = true
                card.Parent = trailGridScroll
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, INV_CARD.CornerRadius)

                local baseStrokeColor = isRainbow and Color3.fromRGB(200, 160, 255) or (WEAPON_CARD_BORDER[rarity] or shadeColor(rarityColor, 0.65))
                local baseStrokeThickness = isEpic and 2.0 or 1.7
                local baseStrokeTransparency = isEpic and 0.08 or 0.16
                local eCS = Instance.new("UIStroke", card)
                eCS.Color = baseStrokeColor
                eCS.Thickness = baseStrokeThickness
                eCS.Transparency = baseStrokeTransparency
                addCardSheen(card, accentColor)
                local accentBar = addCardAccentBar(card, accentColor)
                if isRainbow and def.TrailColorSequence then
                    Instance.new("UIGradient", accentBar).Color = def.TrailColorSequence
                end

                -- Name label at top (matching weapon card layout)
                local cardName = Instance.new("TextLabel", card)
                cardName.Name = "NameLabel"
                cardName.BackgroundTransparency = 1
                cardName.Font = Enum.Font.GothamBold
                cardName.Text = displayName
                cardName.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                cardName.TextSize = INV_CARD.NameTextSize
                cardName.TextTruncate = Enum.TextTruncate.AtEnd
                cardName.TextXAlignment = Enum.TextXAlignment.Center
                cardName.Size = UDim2.new(1, -px(10), 0, INV_CARD.NameHeight)
                cardName.Position = UDim2.new(0, px(5), 0, INV_CARD.NameY)
                cardName.ZIndex = 3
                addTextOutline(cardName, 0.18, 1.35)

                -- Icon area (centered square, matching weapon card layout)
                local iconArea = Instance.new("Frame", card)
                iconArea.Name = "IconArea"
                iconArea.BackgroundColor3 = mixColor(RARITY_BG_COLORS[rarity] or RARITY_BG_COLORS.Common, effectColor, isRainbow and 0.08 or 0.24)
                iconArea.Size = UDim2.new(0, INV_CARD.IconSize, 0, INV_CARD.IconSize)
                iconArea.AnchorPoint = Vector2.new(0.5, 0)
                iconArea.Position = UDim2.new(0.5, 0, 0, INV_CARD.IconY)
                iconArea.BorderSizePixel = 0
                Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, INV_CARD.IconCorner)
                addIconWellHighlight(iconArea, accentColor)

                -- Color swatch inside icon area
                local swatch = Instance.new("Frame", iconArea)
                swatch.Name = "ColorSwatch"
                swatch.Size = UDim2.new(0.68, 0, 0, px(9))
                swatch.AnchorPoint = Vector2.new(0.5, 0)
                swatch.Position = UDim2.new(0.5, 0, 0.14, 0)
                swatch.BackgroundColor3 = isRainbow and Color3.fromRGB(255,255,255) or effectColor
                swatch.BorderSizePixel = 0
                swatch.ZIndex = 4
                Instance.new("UICorner", swatch).CornerRadius = UDim.new(0.5, 0)
                if isRainbow and def.TrailColorSequence then
                    Instance.new("UIGradient", swatch).Color = def.TrailColorSequence
                end
                local swS = Instance.new("UIStroke", swatch)
                swS.Color = isRainbow and Color3.fromRGB(200,160,255) or effectColor
                swS.Thickness = px(2); swS.Transparency = 0.3

                local trailGlyph = Instance.new("TextLabel", iconArea)
                trailGlyph.Text = "\u{2550}\u{2550}\u{2550}"
                trailGlyph.Font = Enum.Font.GothamBold
                trailGlyph.TextColor3 = isRainbow and Color3.fromRGB(255,255,255) or effectColor
                trailGlyph.TextScaled = true
                trailGlyph.BackgroundTransparency = 1
                trailGlyph.Size = UDim2.new(0.76, 0, 0.36, 0)
                trailGlyph.AnchorPoint = Vector2.new(0.5, 1)
                trailGlyph.Position = UDim2.new(0.5, 0, 0.93, 0)
                trailGlyph.ZIndex = 4
                if isRainbow and def.TrailColorSequence then
                    Instance.new("UIGradient", trailGlyph).Color = def.TrailColorSequence
                end
                addTextOutline(trailGlyph, 0.24, 1.4)

                -- Rarity label (bottom of card)
                local rarityPill = Instance.new("Frame", card)
                rarityPill.Name = "RarityPill"
                rarityPill.BackgroundColor3 = mixColor(baseBg, Color3.fromRGB(8, 10, 18), 0.28)
                rarityPill.BorderSizePixel = 0
                rarityPill.Size = UDim2.new(0.76, 0, 0, INV_CARD.Line2Height + px(4))
                rarityPill.AnchorPoint = Vector2.new(0.5, 1)
                rarityPill.Position = UDim2.new(0.5, 0, 1, -INV_CARD.Line2OffBottom)
                rarityPill.ZIndex = 3
                Instance.new("UICorner", rarityPill).CornerRadius = UDim.new(0, px(7))
                local rarityPillStroke = Instance.new("UIStroke", rarityPill)
                rarityPillStroke.Color = rarityColor; rarityPillStroke.Thickness = 1; rarityPillStroke.Transparency = 0.42

                local cardRarity = Instance.new("TextLabel", rarityPill)
                cardRarity.Name = "RarityLabel"
                cardRarity.BackgroundTransparency = 1
                cardRarity.Font = Enum.Font.GothamBold
                cardRarity.Text = rarity
                cardRarity.TextColor3 = rarityColor
                cardRarity.TextSize = INV_CARD.Line1TextSize
                cardRarity.TextXAlignment = Enum.TextXAlignment.Center
                cardRarity.Size = UDim2.new(1, -px(6), 1, 0)
                cardRarity.Position = UDim2.new(0, px(3), 0, 0)
                cardRarity.ZIndex = 4
                addTextOutline(cardRarity, 0.3, 1)

                -- Equipped bar at bottom
                local eqBar = Instance.new("Frame", card)
                eqBar.Name = "EquippedBar"
                eqBar.BackgroundColor3 = GREEN_GLOW
                eqBar.Size = UDim2.new(1, 0, 0, px(3))
                eqBar.AnchorPoint = Vector2.new(0, 1)
                eqBar.Position = UDim2.new(0, 0, 1, 0)
                eqBar.BorderSizePixel = 0; eqBar.ZIndex = 5
                eqBar.Visible = false

                effectCards[effectId] = {
                    card = card,
                    cardStroke = eCS,
                    isFree = isFree,
                    accentBar = accentBar,
                    accentColor = accentColor,
                    baseBg = baseBg,
                    hoverBg = brightenColor(baseBg, 0.07),
                    selectedBg = selectedBg,
                    equippedBg = equippedBg,
                    baseStrokeColor = baseStrokeColor,
                    baseStrokeThickness = baseStrokeThickness,
                    baseStrokeTransparency = baseStrokeTransparency,
                }

                -- Click to select
                card.MouseButton1Click:Connect(function()
                    setSelectedEffect(effectId)
                end)

                -- Hover effect
                if not game:GetService("UserInputService").TouchEnabled then
                    card.MouseEnter:Connect(function()
                        if selectedEffectId ~= effectId then
                            local refs = effectCards[effectId]
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = refs and refs.hoverBg or brightenColor(baseBg, 0.07)}):Play()
                        end
                    end)
                    card.MouseLeave:Connect(function()
                        if selectedEffectId ~= effectId then
                            local isEq = (equippedTrailId == effectId)
                            local refs = effectCards[effectId]
                            local targetBg = refs and (isEq and refs.equippedBg or refs.baseBg) or baseBg
                            TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = targetBg}):Play()
                        end
                    end)
                end
            end

            -- ── Fetch data from server ──────────────────────────────────
            task.spawn(function()
                local eRemotes = ensureEffectRemotes()
                if not eRemotes then return end
                if eRemotes.getOwned and eRemotes.getOwned:IsA("RemoteFunction") then
                    local ok, list = pcall(function() return eRemotes.getOwned:InvokeServer() end)
                    if ok and type(list) == "table" then for _, id in ipairs(list) do ownedSet[id] = true end end
                end
                if eRemotes.getEquipped and eRemotes.getEquipped:IsA("RemoteFunction") then
                    local ok, equipped = pcall(function() return eRemotes.getEquipped:InvokeServer() end)
                    if ok and type(equipped) == "table" then equippedTrailId = equipped.DashTrail end
                end
                refreshEffectCards()
                if eRemotes.changed and eRemotes.changed:IsA("RemoteEvent") then
                    eRemotes.changed.OnClientEvent:Connect(function(newEquipped)
                        if type(newEquipped) == "table" then
                            equippedTrailId = newEquipped.DashTrail
                            updateTrailEquipButton()
                            refreshEffectCards()
                        end
                    end)
                end
            end)
        else
            -- Placeholder when no trail effects exist
            local card = Instance.new("Frame", effectsPage)
            card.BackgroundColor3 = CARD_BG; card.Size = UDim2.new(0.6, 0, 0, px(190))
            card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.5, 0)
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(16))
            Instance.new("UIStroke", card).Color = CARD_STROKE

            local t = Instance.new("TextLabel", card)
            t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold
            t.Text = "EFFECTS"; t.TextColor3 = GOLD
            t.TextSize = math.max(16, math.floor(px(18)))
            t.Size = UDim2.new(1, 0, 0, px(26)); t.Position = UDim2.new(0, 0, 0.46, 0)
            t.TextXAlignment = Enum.TextXAlignment.Center

            local s = Instance.new("TextLabel", card)
            s.BackgroundTransparency = 1; s.Font = Enum.Font.GothamMedium
            s.Text = "You don't own any items in this category yet.\nVisit the shop to unlock more."
            s.TextColor3 = DIM_TEXT; s.TextSize = math.max(12, math.floor(px(13)))
            s.Size = UDim2.new(1, -px(20), 0, px(36)); s.Position = UDim2.new(0, px(10), 0.58, 0)
            s.TextWrapped = true; s.TextXAlignment = Enum.TextXAlignment.Center
        end
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  EMOTES PAGE  (ordered equip loadout with slot compaction)
    -- ══════════════════════════════════════════════════════════════════════
    local emotesPage = Instance.new("Frame")
    emotesPage.Name = "EmotesPage"
    emotesPage.BackgroundTransparency = 1
    emotesPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    emotesPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    emotesPage.Visible = false
    emotesPage.Parent = root

    do
        local EmoteConfig = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EmoteConfig")
            if mod and mod:IsA("ModuleScript") then EmoteConfig = require(mod) end
        end)

        local emoteRemotes = nil
        local function ensureEmoteRemotes()
            if emoteRemotes then return emoteRemotes end
            local rf = ReplicatedStorage:FindFirstChild("Remotes")
            if not rf then rf = ReplicatedStorage:WaitForChild("Remotes", 10) end
            if not rf then return nil end
            local ef = rf:FindFirstChild("Emotes") or rf:WaitForChild("Emotes", 5)
            if not ef then return nil end
            emoteRemotes = {
                getOwned    = ef:FindFirstChild("GetOwnedEmotes"),
                getEquipped = ef:FindFirstChild("GetEquippedEmotes"),
                equip       = ef:FindFirstChild("EquipEmote"),
                unequip     = ef:FindFirstChild("UnequipEmote"),
                changed     = ef:FindFirstChild("EquippedEmotesChanged"),
            }
            return emoteRemotes
        end

        local EMOTE_SLOT_COUNT = (EmoteConfig and EmoteConfig.SLOT_COUNT) or 8
        local EMOTE_GLYPHS = {
            wave = "\u{1F44B}",
            dance = "\u{1F57A}",
            headless = "\u{1F480}",
            rat_dance = "\u{1F400}",
            floss = "\u{1F57A}",
            dab = "DAB",
            macarena = "\u{1F483}",
            ride_the_pony = "\u{1F434}",
            the_robot = "\u{1F916}",
            i_want_money = "\u{1F4B0}",
            take_the_l = "L",
        }

        local function getEmoteIconImage(def)
            if type(def) ~= "table" then return nil end
            if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then return def.IconAssetId end
            local key = def.IconKey
            if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" and key then
                local image = AssetCodesGlobal.Get(key)
                if type(image) == "string" and #image > 0 then return image end
            end
            return nil
        end

        local function getEmoteGlyph(emoteId)
            return EMOTE_GLYPHS[emoteId] or "\u{1F3AD}"
        end

        local allEmoteDefs = EmoteConfig and EmoteConfig.GetAll() or {}

        local emoteGridScroll = Instance.new("ScrollingFrame")
        emoteGridScroll.Name = "EmoteGridScroll"
        emoteGridScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
        emoteGridScroll.BackgroundTransparency = 0.5
        emoteGridScroll.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        emoteGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        emoteGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        emoteGridScroll.ScrollBarThickness = px(4)
        emoteGridScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
        emoteGridScroll.BorderSizePixel = 0
        emoteGridScroll.Parent = emotesPage
        Instance.new("UICorner", emoteGridScroll).CornerRadius = UDim.new(0, px(10))

        local emoteGridLayout = Instance.new("UIGridLayout", emoteGridScroll)
        emoteGridLayout.CellSize = UDim2.new(0, px(140), 0, px(178))
        emoteGridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
        emoteGridLayout.FillDirection = Enum.FillDirection.Horizontal
        emoteGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        emoteGridLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local emoteGridPad = Instance.new("UIPadding", emoteGridScroll)
        emoteGridPad.PaddingTop = UDim.new(0, px(8))
        emoteGridPad.PaddingLeft = UDim.new(0, px(8))
        emoteGridPad.PaddingRight = UDim.new(0, px(8))
        emoteGridPad.PaddingBottom = UDim.new(0, px(8))
        bindFixedColumnGrid(emoteGridScroll, emoteGridLayout, emoteGridPad, 140, 178)

        local emotesEmptyState = Instance.new("Frame")
        emotesEmptyState.Name = "EmotesEmptyState"
        emotesEmptyState.BackgroundTransparency = 1
        emotesEmptyState.Size = UDim2.new(1, -(DETAIL_W + GRID_GAP), 1, 0)
        emotesEmptyState.Visible = false
        emotesEmptyState.Parent = emotesPage

        local eeCard = Instance.new("Frame", emotesEmptyState)
        eeCard.BackgroundColor3 = accentPanelColor(GOLD, 0.22)
        eeCard.Size = UDim2.new(0.7, 0, 0, px(130))
        eeCard.AnchorPoint = Vector2.new(0.5, 0.5)
        eeCard.Position = UDim2.new(0.5, 0, 0.45, 0)
        Instance.new("UICorner", eeCard).CornerRadius = UDim.new(0, px(14))
        local eeStroke = Instance.new("UIStroke", eeCard)
        eeStroke.Color = GOLD
        eeStroke.Thickness = 1.4
        eeStroke.Transparency = 0.22
        addCardSheen(eeCard, GOLD)

        local eeLbl = Instance.new("TextLabel", eeCard)
        eeLbl.BackgroundTransparency = 1
        eeLbl.Font = Enum.Font.GothamMedium
        eeLbl.Text = "You don't own any emotes yet.\nVisit the shop to unlock more."
        eeLbl.TextColor3 = DIM_TEXT
        eeLbl.TextSize = math.max(13, math.floor(px(14)))
        eeLbl.TextWrapped = true
        eeLbl.Size = UDim2.new(0.85, 0, 0, px(60))
        eeLbl.AnchorPoint = Vector2.new(0.5, 0.5)
        eeLbl.Position = UDim2.new(0.5, 0, 0.5, 0)
        eeLbl.TextXAlignment = Enum.TextXAlignment.Center

        local eeShopBtn = Instance.new("TextButton", emotesEmptyState)
        eeShopBtn.Name = "ShopNavBtn"
        eeShopBtn.AutoButtonColor = false
        eeShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        eeShopBtn.Font = Enum.Font.GothamBold
        eeShopBtn.Text = "\u{1F6D2}  Browse Emotes Shop"
        eeShopBtn.TextColor3 = WHITE
        eeShopBtn.TextTransparency = 0
        eeShopBtn.TextSize = math.max(14, math.floor(px(15)))
        eeShopBtn.AutomaticSize = Enum.AutomaticSize.X
        eeShopBtn.Size = UDim2.new(0, 0, 0, px(36))
        eeShopBtn.AnchorPoint = Vector2.new(0.5, 0)
        eeShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
        Instance.new("UICorner", eeShopBtn).CornerRadius = UDim.new(0, px(8))
        local eeShopPad = Instance.new("UIPadding", eeShopBtn)
        eeShopPad.PaddingLeft = UDim.new(0, px(20))
        eeShopPad.PaddingRight = UDim.new(0, px(20))
        local eeShopStroke = Instance.new("UIStroke", eeShopBtn)
        eeShopStroke.Color = Color3.fromRGB(0, 0, 0)
        eeShopStroke.Thickness = 1.5
        eeShopStroke.Transparency = 0.15
        eeShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then
                mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("emotes") end
            end
        end)

        local emoteDetailsPanel = Instance.new("Frame")
        emoteDetailsPanel.Name = "EmoteDetailsPanel"
        emoteDetailsPanel.BackgroundColor3 = CARD_BG
        emoteDetailsPanel.Size = UDim2.new(0, DETAIL_W, 1, 0)
        emoteDetailsPanel.AnchorPoint = Vector2.new(1, 0)
        emoteDetailsPanel.Position = UDim2.new(1, 0, 0, 0)
        emoteDetailsPanel.Parent = emotesPage
        Instance.new("UICorner", emoteDetailsPanel).CornerRadius = UDim.new(0, px(12))
        local edpStroke = Instance.new("UIStroke", emoteDetailsPanel)
        edpStroke.Color = CARD_STROKE
        edpStroke.Thickness = 1.4
        edpStroke.Transparency = 0.2

        local emoteDetailPlaceholder = Instance.new("TextLabel", emoteDetailsPanel)
        emoteDetailPlaceholder.Name = "Placeholder"
        emoteDetailPlaceholder.BackgroundTransparency = 1
        emoteDetailPlaceholder.Font = Enum.Font.GothamMedium
        emoteDetailPlaceholder.Text = "Select an emote"
        emoteDetailPlaceholder.TextColor3 = DIM_TEXT
        emoteDetailPlaceholder.TextSize = px(22)
        emoteDetailPlaceholder.Size = UDim2.new(1, 0, 1, 0)
        emoteDetailPlaceholder.TextXAlignment = Enum.TextXAlignment.Center
        emoteDetailPlaceholder.TextYAlignment = Enum.TextYAlignment.Center

        local emoteDetailContent = Instance.new("Frame", emoteDetailsPanel)
        emoteDetailContent.Name = "DetailContent"
        emoteDetailContent.BackgroundTransparency = 1
        emoteDetailContent.Size = UDim2.new(1, 0, 1, 0)
        emoteDetailContent.Visible = false

        local edPad = Instance.new("UIPadding", emoteDetailContent)
        edPad.PaddingTop = UDim.new(0, px(12))
        edPad.PaddingBottom = UDim.new(0, px(12))
        edPad.PaddingLeft = UDim.new(0, px(12))
        edPad.PaddingRight = UDim.new(0, px(12))

        local emoteHero = Instance.new("Frame", emoteDetailContent)
        emoteHero.Name = "Hero"
        emoteHero.BackgroundColor3 = accentPanelColor(GOLD, 0.24)
        emoteHero.Size = UDim2.new(1, 0, 0, px(184))
        emoteHero.ClipsDescendants = true
        Instance.new("UICorner", emoteHero).CornerRadius = UDim.new(0, px(10))
        local emoteHeroStroke = Instance.new("UIStroke", emoteHero)
        emoteHeroStroke.Color = GOLD
        emoteHeroStroke.Thickness = 1.5
        emoteHeroStroke.Transparency = 0.2
        addCardSheen(emoteHero, GOLD)

        local emoteHeroGlyph = Instance.new("TextLabel", emoteHero)
        emoteHeroGlyph.Name = "Glyph"
        emoteHeroGlyph.BackgroundTransparency = 1
        emoteHeroGlyph.Size = UDim2.new(0.7, 0, 0.7, 0)
        emoteHeroGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
        emoteHeroGlyph.Position = UDim2.new(0.5, 0, 0.52, 0)
        emoteHeroGlyph.Font = Enum.Font.GothamBlack
        emoteHeroGlyph.TextScaled = true
        emoteHeroGlyph.TextColor3 = GOLD
        addTextOutline(emoteHeroGlyph, 0.24, 1.5)

        local emoteHeroImage = Instance.new("ImageLabel", emoteHero)
        emoteHeroImage.Name = "IconImage"
        emoteHeroImage.BackgroundTransparency = 1
        emoteHeroImage.Size = UDim2.new(0.54, 0, 0.54, 0)
        emoteHeroImage.AnchorPoint = Vector2.new(0.5, 0.5)
        emoteHeroImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        emoteHeroImage.ScaleType = Enum.ScaleType.Fit
        emoteHeroImage.Visible = false

        local emoteDetailName = Instance.new("TextLabel", emoteDetailContent)
        emoteDetailName.Name = "EmoteName"
        emoteDetailName.BackgroundTransparency = 1
        emoteDetailName.Font = Enum.Font.GothamBold
        emoteDetailName.TextColor3 = WHITE
        emoteDetailName.TextSize = px(26)
        emoteDetailName.TextXAlignment = Enum.TextXAlignment.Center
        emoteDetailName.Size = UDim2.new(1, 0, 0, px(34))
        emoteDetailName.Position = UDim2.new(0, 0, 0, px(192))
        emoteDetailName.TextTruncate = Enum.TextTruncate.AtEnd

        local emoteDetailDesc = Instance.new("TextLabel", emoteDetailContent)
        emoteDetailDesc.Name = "Description"
        emoteDetailDesc.BackgroundTransparency = 1
        emoteDetailDesc.Font = Enum.Font.GothamBold
        emoteDetailDesc.TextColor3 = DIM_TEXT
        emoteDetailDesc.TextSize = px(16)
        emoteDetailDesc.TextWrapped = true
        emoteDetailDesc.TextXAlignment = Enum.TextXAlignment.Center
        emoteDetailDesc.Size = UDim2.new(1, 0, 0, px(48))
        emoteDetailDesc.Position = UDim2.new(0, 0, 0, px(228))
        local descStroke = Instance.new("UIStroke", emoteDetailDesc)
        descStroke.Color = Color3.fromRGB(0, 0, 0)
        descStroke.Thickness = 1.4
        descStroke.Transparency = 0.15

        local emoteStatusLabel = Instance.new("TextLabel", emoteDetailContent)
        emoteStatusLabel.Name = "StatusLabel"
        emoteStatusLabel.BackgroundTransparency = 1
        emoteStatusLabel.Font = Enum.Font.GothamBold
        emoteStatusLabel.TextColor3 = GOLD
        emoteStatusLabel.TextSize = px(15)
        emoteStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
        emoteStatusLabel.Size = UDim2.new(1, 0, 0, px(22))
        emoteStatusLabel.Position = UDim2.new(0, 0, 0, px(278))

        local emoteSlotsPanel = Instance.new("Frame", emoteDetailContent)
        emoteSlotsPanel.Name = "SlotsPanel"
        emoteSlotsPanel.BackgroundColor3 = accentPanelColor(GOLD, 0.12)
        emoteSlotsPanel.Size = UDim2.new(1, 0, 0, px(190))
        emoteSlotsPanel.Position = UDim2.new(0, 0, 0, px(306))
        Instance.new("UICorner", emoteSlotsPanel).CornerRadius = UDim.new(0, px(10))
        local emoteSlotsStroke = Instance.new("UIStroke", emoteSlotsPanel)
        emoteSlotsStroke.Color = GOLD
        emoteSlotsStroke.Thickness = 1.2
        emoteSlotsStroke.Transparency = 0.32

        local slotsTitle = Instance.new("TextLabel", emoteSlotsPanel)
        slotsTitle.BackgroundTransparency = 1
        slotsTitle.Font = Enum.Font.GothamBold
        slotsTitle.Text = "LOADOUT"
        slotsTitle.TextColor3 = GOLD
        slotsTitle.TextSize = px(16)
        slotsTitle.TextXAlignment = Enum.TextXAlignment.Left
        slotsTitle.Size = UDim2.new(1, -px(18), 0, px(20))
        slotsTitle.Position = UDim2.new(0, px(10), 0, px(8))

        local slotsRows = Instance.new("Frame", emoteSlotsPanel)
        slotsRows.Name = "Rows"
        slotsRows.BackgroundTransparency = 1
        slotsRows.Size = UDim2.new(1, -px(18), 1, -px(34))
        slotsRows.Position = UDim2.new(0, px(9), 0, px(28))

        local slotsRowsLayout = Instance.new("UIListLayout", slotsRows)
        slotsRowsLayout.FillDirection = Enum.FillDirection.Vertical
        slotsRowsLayout.Padding = UDim.new(0, px(3))
        slotsRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local slotRows = {}
        for slotIndex = 1, EMOTE_SLOT_COUNT do
            local row = Instance.new("Frame", slotsRows)
            row.Name = "SlotRow_" .. slotIndex
            row.BackgroundColor3 = Color3.fromRGB(18, 20, 34)
            row.BackgroundTransparency = 0.08
            row.Size = UDim2.new(1, 0, 0, px(18))
            row.LayoutOrder = slotIndex
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, px(6))
            local rowStroke = Instance.new("UIStroke", row)
            rowStroke.Color = CARD_STROKE
            rowStroke.Thickness = 1
            rowStroke.Transparency = 0.45

            local slotLabel = Instance.new("TextLabel", row)
            slotLabel.BackgroundTransparency = 1
            slotLabel.Font = Enum.Font.GothamBold
            slotLabel.Text = string.format("%02d", slotIndex)
            slotLabel.TextColor3 = GOLD
            slotLabel.TextSize = px(12)
            slotLabel.TextXAlignment = Enum.TextXAlignment.Left
            slotLabel.Size = UDim2.new(0, px(24), 1, 0)
            slotLabel.Position = UDim2.new(0, px(8), 0, 0)

            local valueLabel = Instance.new("TextLabel", row)
            valueLabel.BackgroundTransparency = 1
            valueLabel.Font = Enum.Font.GothamMedium
            valueLabel.Text = "Empty"
            valueLabel.TextColor3 = DIM_TEXT
            valueLabel.TextSize = px(12)
            valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
            valueLabel.TextXAlignment = Enum.TextXAlignment.Left
            valueLabel.Size = UDim2.new(1, -px(102), 1, 0)
            valueLabel.Position = UDim2.new(0, px(36), 0, 0)

            local removeBtn = Instance.new("TextButton", row)
            removeBtn.Name = "RemoveBtn"
            removeBtn.AutoButtonColor = false
            removeBtn.BackgroundColor3 = Color3.fromRGB(58, 34, 28)
            removeBtn.Text = "REMOVE"
            removeBtn.TextColor3 = WHITE
            removeBtn.TextSize = px(10)
            removeBtn.Font = Enum.Font.GothamBold
            removeBtn.Size = UDim2.new(0, px(58), 1, -px(2))
            removeBtn.AnchorPoint = Vector2.new(1, 0.5)
            removeBtn.Position = UDim2.new(1, -px(4), 0.5, 0)
            removeBtn.Visible = false
            Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, px(5))
            local removeStroke = Instance.new("UIStroke", removeBtn)
            removeStroke.Color = Color3.fromRGB(0, 0, 0)
            removeStroke.Thickness = 1
            removeStroke.Transparency = 0.15

            slotRows[slotIndex] = {
                row = row,
                rowStroke = rowStroke,
                valueLabel = valueLabel,
                removeBtn = removeBtn,
            }
        end

        local emoteShopNavW = Instance.new("Frame", emoteDetailContent)
        emoteShopNavW.Name = "ShopNavWrap"
        emoteShopNavW.BackgroundTransparency = 1
        emoteShopNavW.Size = UDim2.new(0.88, 0, 0, px(36))
        emoteShopNavW.AnchorPoint = Vector2.new(0.5, 1)
        emoteShopNavW.Position = UDim2.new(0.5, 0, 1, -px(58))

        local emoteShopBtn = Instance.new("TextButton", emoteShopNavW)
        emoteShopBtn.AutoButtonColor = false
        emoteShopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        emoteShopBtn.Font = Enum.Font.GothamBold
        emoteShopBtn.Text = "\u{1F6D2}  Browse Emotes Shop"
        emoteShopBtn.TextColor3 = WHITE
        emoteShopBtn.TextTransparency = 0
        emoteShopBtn.TextSize = math.max(13, math.floor(px(15)))
        emoteShopBtn.AutomaticSize = Enum.AutomaticSize.X
        emoteShopBtn.Size = UDim2.new(0, 0, 1, 0)
        emoteShopBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        emoteShopBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
        Instance.new("UICorner", emoteShopBtn).CornerRadius = UDim.new(0, px(8))
        local esnPad = Instance.new("UIPadding", emoteShopBtn)
        esnPad.PaddingLeft = UDim.new(0, px(14))
        esnPad.PaddingRight = UDim.new(0, px(14))
        local esnStroke = Instance.new("UIStroke", emoteShopBtn)
        esnStroke.Color = Color3.fromRGB(0, 0, 0)
        esnStroke.Thickness = 1.5
        esnStroke.Transparency = 0.15
        emoteShopBtn.MouseEnter:Connect(function() TweenService:Create(emoteShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
        emoteShopBtn.MouseLeave:Connect(function() TweenService:Create(emoteShopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
        emoteShopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then
                mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("emotes") end
            end
        end)

        local emoteActionBtn = Instance.new("TextButton", emoteDetailContent)
        emoteActionBtn.Name = "EquipBtn"
        emoteActionBtn.AutoButtonColor = false
        emoteActionBtn.BackgroundColor3 = BTN_BG
        emoteActionBtn.Font = Enum.Font.GothamBold
        emoteActionBtn.Text = "EQUIP"
        emoteActionBtn.TextColor3 = WHITE
        emoteActionBtn.TextTransparency = 0
        emoteActionBtn.TextSize = px(22)
        emoteActionBtn.Size = UDim2.new(0.88, 0, 0, px(52))
        emoteActionBtn.AnchorPoint = Vector2.new(0.5, 1)
        emoteActionBtn.Position = UDim2.new(0.5, 0, 1, 0)
        Instance.new("UICorner", emoteActionBtn).CornerRadius = UDim.new(0, px(10))
        local emoteActionStroke = Instance.new("UIStroke", emoteActionBtn)
        emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
        emoteActionStroke.Thickness = 1.5
        emoteActionStroke.Transparency = 0.15

        local ownedEmoteSet = {}
        local equippedSlots = {}
        local selectedEmoteId = nil
        local emoteCards = {}

        local function getEquippedSlotForEmote(emoteId)
            for slot = 1, EMOTE_SLOT_COUNT do
                if equippedSlots[slot] == emoteId then
                    return slot
                end
            end
            return nil
        end

        local function countEquippedEmotes()
            local count = 0
            for slot = 1, EMOTE_SLOT_COUNT do
                if equippedSlots[slot] then
                    count += 1
                end
            end
            return count
        end

        local function setEquippedFromList(list)
            equippedSlots = {}
            if type(list) ~= "table" then
                return
            end
            for _, entry in ipairs(list) do
                if type(entry) == "table" then
                    local slot = tonumber(entry.Slot)
                    local emoteId = entry.Id
                    if slot and slot >= 1 and slot <= EMOTE_SLOT_COUNT and type(emoteId) == "string" and emoteId ~= "" then
                        equippedSlots[slot] = emoteId
                    end
                end
            end
        end

        local refreshEmoteCards
        local refreshEmoteSlots

        local function updateEmoteActionButton()
            if not selectedEmoteId then return end
            local equippedSlot = getEquippedSlotForEmote(selectedEmoteId)
            if equippedSlot then
                emoteActionBtn.Text = string.format("UNEQUIP SLOT %d", equippedSlot)
                emoteActionBtn.BackgroundColor3 = DISABLED_BG
                emoteActionBtn.TextColor3 = GOLD
                emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
                emoteActionStroke.Transparency = 0.15
                return
            end

            local nextSlot = countEquippedEmotes() + 1
            if nextSlot > EMOTE_SLOT_COUNT then
                emoteActionBtn.Text = "SLOTS FULL"
                emoteActionBtn.BackgroundColor3 = DISABLED_BG
                emoteActionBtn.TextColor3 = DIM_TEXT
                emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
                emoteActionStroke.Transparency = 0.15
            else
                emoteActionBtn.Text = string.format("EQUIP TO SLOT %d", nextSlot)
                emoteActionBtn.BackgroundColor3 = BTN_BG
                emoteActionBtn.TextColor3 = WHITE
                emoteActionStroke.Color = Color3.fromRGB(0, 0, 0)
                emoteActionStroke.Transparency = 0.15
            end
        end

        local function setSelectedEmote(emoteId)
            selectedEmoteId = emoteId
            if not emoteId then
                emoteDetailPlaceholder.Visible = true
                emoteDetailContent.Visible = false
                if refreshEmoteCards then refreshEmoteCards() end
                if refreshEmoteSlots then refreshEmoteSlots() end
                return
            end

            local def = EmoteConfig and EmoteConfig.GetById(emoteId)
            if not def then return end

            emoteDetailPlaceholder.Visible = false
            emoteDetailContent.Visible = true

            emoteHeroGlyph.Text = getEmoteGlyph(emoteId)
            local imageId = getEmoteIconImage(def)
            emoteHeroImage.Visible = type(imageId) == "string" and #imageId > 0
            if emoteHeroImage.Visible then
                emoteHeroImage.Image = imageId
            else
                emoteHeroImage.Image = ""
            end

            emoteDetailName.Text = def.DisplayName or emoteId
            emoteDetailDesc.Text = def.Description or ""

            local equippedSlot = getEquippedSlotForEmote(emoteId)
            if equippedSlot then
                emoteStatusLabel.Text = string.format("Equipped in slot %d", equippedSlot)
            else
                local nextSlot = countEquippedEmotes() + 1
                if nextSlot <= EMOTE_SLOT_COUNT then
                    emoteStatusLabel.Text = string.format("Next equip fills slot %d", nextSlot)
                else
                    emoteStatusLabel.Text = "All slots are full"
                end
            end

            updateEmoteActionButton()
            if refreshEmoteCards then refreshEmoteCards() end
            if refreshEmoteSlots then refreshEmoteSlots() end
        end

        refreshEmoteSlots = function()
            local selectedSlot = selectedEmoteId and getEquippedSlotForEmote(selectedEmoteId) or nil
            for slotIndex = 1, EMOTE_SLOT_COUNT do
                local refs = slotRows[slotIndex]
                local emoteId = equippedSlots[slotIndex]
                local def = emoteId and EmoteConfig and EmoteConfig.GetById(emoteId) or nil
                refs.valueLabel.Text = def and (def.DisplayName or emoteId) or "Empty"
                refs.valueLabel.TextColor3 = def and WHITE or DIM_TEXT
                refs.removeBtn.Visible = def ~= nil

                local isSelectedSlot = (selectedSlot == slotIndex)
                refs.row.BackgroundColor3 = isSelectedSlot and accentPanelColor(GOLD, 0.28) or Color3.fromRGB(18, 20, 34)
                refs.rowStroke.Color = isSelectedSlot and GOLD or CARD_STROKE
                refs.rowStroke.Transparency = isSelectedSlot and 0.18 or 0.45
            end
        end

        refreshEmoteCards = function()
            local visibleCount = 0
            for emoteId, refs in pairs(emoteCards) do
                local def = refs.def
                local isOwned = ownedEmoteSet[emoteId] or (def and def.IsFree == true)
                refs.card.Visible = isOwned
                if isOwned then
                    visibleCount += 1
                end

                local equippedSlot = getEquippedSlotForEmote(emoteId)
                local isSelected = (selectedEmoteId == emoteId)
                if isSelected then
                    refs.card.BackgroundColor3 = refs.selectedBg
                    setCardStroke(refs.cardStroke, GOLD, 2.2, 0)
                elseif equippedSlot then
                    refs.card.BackgroundColor3 = refs.equippedBg
                    setCardStroke(refs.cardStroke, GREEN_GLOW, 1.9, 0.16)
                else
                    refs.card.BackgroundColor3 = refs.baseBg
                    setCardStroke(refs.cardStroke, refs.baseStrokeColor, refs.baseStrokeThickness, refs.baseStrokeTransparency)
                end

                refs.slotBadge.Visible = (equippedSlot ~= nil)
                refs.slotBadge.Text = equippedSlot and string.format("SLOT %d", equippedSlot) or ""
                refs.eqBar.Visible = (equippedSlot ~= nil)
            end

            emotesEmptyState.Visible = (visibleCount == 0)
            emoteGridScroll.Visible = (visibleCount > 0)
        end

        for slotIndex = 1, EMOTE_SLOT_COUNT do
            local refs = slotRows[slotIndex]
            refs.removeBtn.MouseButton1Click:Connect(function()
                if not equippedSlots[slotIndex] then return end
                local remotes = ensureEmoteRemotes()
                if remotes and remotes.unequip and remotes.unequip:IsA("RemoteEvent") then
                    pcall(function() remotes.unequip:FireServer(slotIndex) end)
                end
            end)
        end

        emoteActionBtn.MouseButton1Click:Connect(function()
            if not selectedEmoteId then return end
            local remotes = ensureEmoteRemotes()
            if not remotes then return end

            local equippedSlot = getEquippedSlotForEmote(selectedEmoteId)
            if equippedSlot then
                if remotes.unequip and remotes.unequip:IsA("RemoteEvent") then
                    pcall(function() remotes.unequip:FireServer(equippedSlot) end)
                end
                return
            end

            if countEquippedEmotes() >= EMOTE_SLOT_COUNT then
                showToast(emotesPage, "All emote slots are full. Unequip one first.", RED_TEXT, 2.2)
                return
            end

            if remotes.equip and remotes.equip:IsA("RemoteEvent") then
                pcall(function() remotes.equip:FireServer(selectedEmoteId) end)
            end
        end)

        emoteActionBtn.MouseEnter:Connect(function()
            local equippedSlot = selectedEmoteId and getEquippedSlotForEmote(selectedEmoteId) or nil
            if not equippedSlot and countEquippedEmotes() < EMOTE_SLOT_COUNT then
                TweenService:Create(emoteActionBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
            end
        end)
        emoteActionBtn.MouseLeave:Connect(function()
            updateEmoteActionButton()
        end)

        for i_emote, def in ipairs(allEmoteDefs) do
            local emoteId = def.Id
            local displayName = def.DisplayName or emoteId
            local baseBg = accentPanelColor(GOLD, 0.18)
            local selectedBg = brightenColor(baseBg, 0.05)
            local equippedBg = mixColor(baseBg, GREEN_GLOW, 0.16)
            local baseStrokeColor = Color3.fromRGB(145, 116, 74)
            local baseStrokeThickness = 1.5
            local baseStrokeTransparency = 0.28

            local card = Instance.new("TextButton")
            card.Name = "EmoteCard_" .. emoteId
            card.BackgroundColor3 = baseBg
            card.Size = UDim2.new(1, 0, 1, 0)
            card.Text = ""
            card.AutoButtonColor = false
            card.BorderSizePixel = 0
            card.LayoutOrder = i_emote
            card.ClipsDescendants = true
            card.Parent = emoteGridScroll
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, INV_CARD.CornerRadius)

            local cardStroke = Instance.new("UIStroke", card)
            cardStroke.Color = baseStrokeColor
            cardStroke.Thickness = baseStrokeThickness
            cardStroke.Transparency = baseStrokeTransparency
            addCardSheen(card, GOLD)
            local accentBar = addCardAccentBar(card, GOLD)

            local cardName = Instance.new("TextLabel", card)
            cardName.Name = "NameLabel"
            cardName.BackgroundTransparency = 1
            cardName.Font = Enum.Font.GothamBold
            cardName.Text = displayName
            cardName.TextColor3 = WHITE
            cardName.TextSize = INV_CARD.NameTextSize
            cardName.TextTruncate = Enum.TextTruncate.AtEnd
            cardName.TextXAlignment = Enum.TextXAlignment.Center
            cardName.Size = UDim2.new(1, -px(10), 0, INV_CARD.NameHeight)
            cardName.Position = UDim2.new(0, px(5), 0, INV_CARD.NameY)
            cardName.ZIndex = 3
            addTextOutline(cardName, 0.18, 1.35)

            local iconArea = Instance.new("Frame", card)
            iconArea.Name = "IconArea"
            iconArea.BackgroundColor3 = mixColor(CARD_BG, GOLD, 0.16)
            iconArea.Size = UDim2.new(0, INV_CARD.IconSize, 0, INV_CARD.IconSize)
            iconArea.AnchorPoint = Vector2.new(0.5, 0)
            iconArea.Position = UDim2.new(0.5, 0, 0, INV_CARD.IconY)
            iconArea.BorderSizePixel = 0
            Instance.new("UICorner", iconArea).CornerRadius = UDim.new(0, INV_CARD.IconCorner)
            addIconWellHighlight(iconArea, GOLD)

            local iconGlyph = Instance.new("TextLabel", iconArea)
            iconGlyph.Name = "Glyph"
            iconGlyph.BackgroundTransparency = 1
            iconGlyph.Size = UDim2.new(0.72, 0, 0.72, 0)
            iconGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
            iconGlyph.Position = UDim2.new(0.5, 0, 0.54, 0)
            iconGlyph.Font = Enum.Font.GothamBlack
            iconGlyph.Text = getEmoteGlyph(emoteId)
            iconGlyph.TextScaled = true
            iconGlyph.TextColor3 = GOLD
            iconGlyph.ZIndex = 4
            addTextOutline(iconGlyph, 0.24, 1.4)

            local iconImage = Instance.new("ImageLabel", iconArea)
            iconImage.Name = "IconImage"
            iconImage.BackgroundTransparency = 1
            iconImage.Size = UDim2.new(0.62, 0, 0.62, 0)
            iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
            iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconImage.ScaleType = Enum.ScaleType.Fit
            iconImage.ZIndex = 5
            local iconImageId = getEmoteIconImage(def)
            iconImage.Visible = type(iconImageId) == "string" and #iconImageId > 0
            iconImage.Image = iconImage.Visible and iconImageId or ""

            local cardType = Instance.new("TextLabel", card)
            cardType.Name = "TypeLabel"
            cardType.BackgroundTransparency = 1
            cardType.Font = Enum.Font.GothamBold
            cardType.Text = "Emote"
            cardType.TextColor3 = GOLD
            cardType.TextSize = INV_CARD.Line1TextSize
            cardType.TextXAlignment = Enum.TextXAlignment.Center
            cardType.Size = UDim2.new(1, -px(10), 0, INV_CARD.Line1Height)
            cardType.Position = UDim2.new(0, px(5), 1, -INV_CARD.Line1OffBottom - INV_CARD.Line1Height)
            cardType.ZIndex = 4

            local slotBadge = Instance.new("TextLabel", card)
            slotBadge.Name = "SlotBadge"
            slotBadge.BackgroundColor3 = Color3.fromRGB(24, 28, 42)
            slotBadge.BackgroundTransparency = 0.12
            slotBadge.BorderSizePixel = 0
            slotBadge.Visible = false
            slotBadge.Font = Enum.Font.GothamBold
            slotBadge.Text = ""
            slotBadge.TextColor3 = GREEN_GLOW
            slotBadge.TextSize = INV_CARD.Line1TextSize
            slotBadge.Size = UDim2.new(0.68, 0, 0, INV_CARD.Line2Height + px(4))
            slotBadge.AnchorPoint = Vector2.new(0.5, 1)
            slotBadge.Position = UDim2.new(0.5, 0, 1, -INV_CARD.Line2OffBottom)
            slotBadge.ZIndex = 4
            Instance.new("UICorner", slotBadge).CornerRadius = UDim.new(0, px(7))
            local slotBadgeStroke = Instance.new("UIStroke", slotBadge)
            slotBadgeStroke.Color = GREEN_GLOW
            slotBadgeStroke.Thickness = 1
            slotBadgeStroke.Transparency = 0.36

            local eqBar = Instance.new("Frame", card)
            eqBar.Name = "EquippedBar"
            eqBar.BackgroundColor3 = GREEN_GLOW
            eqBar.Size = UDim2.new(1, 0, 0, px(3))
            eqBar.AnchorPoint = Vector2.new(0, 1)
            eqBar.Position = UDim2.new(0, 0, 1, 0)
            eqBar.BorderSizePixel = 0
            eqBar.ZIndex = 5
            eqBar.Visible = false

            emoteCards[emoteId] = {
                card = card,
                def = def,
                cardStroke = cardStroke,
                accentBar = accentBar,
                eqBar = eqBar,
                slotBadge = slotBadge,
                baseBg = baseBg,
                hoverBg = brightenColor(baseBg, 0.07),
                selectedBg = selectedBg,
                equippedBg = equippedBg,
                baseStrokeColor = baseStrokeColor,
                baseStrokeThickness = baseStrokeThickness,
                baseStrokeTransparency = baseStrokeTransparency,
            }

            card.MouseButton1Click:Connect(function()
                setSelectedEmote(emoteId)
            end)

            if not game:GetService("UserInputService").TouchEnabled then
                card.MouseEnter:Connect(function()
                    if selectedEmoteId ~= emoteId then
                        local refs = emoteCards[emoteId]
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = refs and refs.hoverBg or brightenColor(baseBg, 0.07)}):Play()
                    end
                end)
                card.MouseLeave:Connect(function()
                    if selectedEmoteId ~= emoteId then
                        local refs = emoteCards[emoteId]
                        local equippedSlot = getEquippedSlotForEmote(emoteId)
                        local targetBg = refs and (equippedSlot and refs.equippedBg or refs.baseBg) or baseBg
                        TweenService:Create(card, TWEEN_QUICK, {BackgroundColor3 = targetBg}):Play()
                    end
                end)
            end
        end

        task.spawn(function()
            local remotes = ensureEmoteRemotes()
            if not remotes then return end

            if remotes.getOwned and remotes.getOwned:IsA("RemoteFunction") then
                local ok, list = pcall(function() return remotes.getOwned:InvokeServer() end)
                if ok and type(list) == "table" then
                    for _, emoteId in ipairs(list) do
                        if type(emoteId) == "string" and emoteId ~= "" then
                            ownedEmoteSet[emoteId] = true
                        end
                    end
                end
            end

            if remotes.getEquipped and remotes.getEquipped:IsA("RemoteFunction") then
                local ok, equippedList = pcall(function() return remotes.getEquipped:InvokeServer() end)
                if ok then
                    setEquippedFromList(equippedList)
                end
            end

            refreshEmoteCards()
            refreshEmoteSlots()

            if not selectedEmoteId then
                for _, def in ipairs(allEmoteDefs) do
                    if ownedEmoteSet[def.Id] or def.IsFree then
                        setSelectedEmote(def.Id)
                        break
                    end
                end
            elseif selectedEmoteId then
                setSelectedEmote(selectedEmoteId)
            end

            if remotes.changed and remotes.changed:IsA("RemoteEvent") then
                trackConn(remotes.changed.OnClientEvent:Connect(function(newEquipped)
                    setEquippedFromList(newEquipped)
                    if selectedEmoteId then
                        setSelectedEmote(selectedEmoteId)
                    else
                        refreshEmoteCards()
                        refreshEmoteSlots()
                    end
                end))
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  TAB SWITCHING
    -- ══════════════════════════════════════════════════════════════════════
    local function setActiveTab(tabId)
        currentTab = tabId

        for id, btn in pairs(tabButtons) do
            local active = (id == tabId)
            btn.BackgroundColor3 = active and TAB_ACTIVE_BG or SIDEBAR_BG

            local bar        = btn:FindFirstChild("ActiveBar")
            local icon       = btn:FindFirstChild("Icon")
            local iconCustom = btn:FindFirstChild("IconCustom")
            local label      = btn:FindFirstChild("Label")
            local btnStroke  = btn:FindFirstChildOfClass("UIStroke")

            if bar       then bar.BackgroundTransparency = active and 0 or 1 end
            if icon      then icon.TextColor3 = active and GOLD or DIM_TEXT end
            if iconCustom then setTabIconTint(iconCustom, getCustomTabIconColor(id, active)) end
            if label     then label.TextColor3 = active and WHITE or DIM_TEXT end
            if btnStroke then btnStroke.Transparency = active and 0.2 or 0.6 end
        end

        -- Page visibility
        local isWeaponTab = (tabId == "melee" or tabId == "ranged")
        weaponArea.Visible  = isWeaponTab
        boostsPage.Visible  = (tabId == "boosts")
        skinsArea.Visible   = (tabId == "skins")
        effectsPage.Visible = (tabId == "effects")
        emotesPage.Visible  = (tabId == "emotes")

        -- Stop trail preview animation when leaving effects tab
        if tabId ~= "effects" and _stopEffectsPreview then
            _stopEffectsPreview()
        end

        -- Render weapon grid for weapon tabs
        if tabId == "melee" then
            renderCategory("Melee")
        elseif tabId == "ranged" then
            renderCategory("Ranged")
        end
    end

    for _, def in ipairs(TAB_DEFS) do
        local id  = def.id
        local btn = tabButtons[id]
        btn.MouseButton1Click:Connect(function() setActiveTab(id) end)
        btn.MouseEnter:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(28, 26, 18)}):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if currentTab ~= id then
                TweenService:Create(btn, TWEEN_QUICK, {BackgroundColor3 = SIDEBAR_BG}):Play()
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  INITIAL STATE
    -- ══════════════════════════════════════════════════════════════════════
    setActiveTab("melee")

    -- ──────────────────────────────────────────────────────────────────────
    -- Listen for server LoadoutChanged to keep equipped state in sync
    -- ──────────────────────────────────────────────────────────────────────
    pcall(function()
        local lcRemote = ReplicatedStorage:FindFirstChild("LoadoutChanged")
        if not lcRemote then
            lcRemote = ReplicatedStorage:WaitForChild("LoadoutChanged", 5)
        end
        if lcRemote and lcRemote:IsA("RemoteEvent") then
            trackConn(lcRemote.OnClientEvent:Connect(function(data)
                if type(data) ~= "table" then return end
                print("[ToolbarSync] InventoryUI received LoadoutChanged:",
                    "melee=", data.melee or "(nil)",
                    "ranged=", data.ranged or "(nil)")
                if type(data.melee) == "string" and #data.melee > 0 then
                    equippedState.Melee = data.melee
                end
                if type(data.ranged) == "string" and #data.ranged > 0 then
                    equippedState.Ranged = data.ranged
                end
                if type(data.meleeInstanceId) == "string" then
                    equippedInstanceIds.Melee = data.meleeInstanceId
                end
                if type(data.rangedInstanceId) == "string" then
                    equippedInstanceIds.Ranged = data.rangedInstanceId
                end
                refreshEquippedIndicators()
                -- Also update detail panel if an equipped item is selected
                if selectedItem then
                    updateEquipButton(selectedItem)
                end
            end))
        end
    end)

    pcall(function()
        local masteryRemote = ReplicatedStorage:FindFirstChild("WeaponMasteryUpdated")
        if not masteryRemote then
            masteryRemote = ReplicatedStorage:WaitForChild("WeaponMasteryUpdated", 5)
        end
        if masteryRemote and masteryRemote:IsA("RemoteEvent") then
            trackConn(masteryRemote.OnClientEvent:Connect(function(instanceId, mastery, meta)
                if type(instanceId) ~= "string" then return end
                if type(meta) == "table" and meta.removed == true then return end
                if type(mastery) ~= "table" then return end
                local sharedWeaponName = mastery.weaponName or (type(meta) == "table" and meta.weaponName) or nil

                local touched = false
                for _, item in ipairs(allWeaponItems) do
                    if item.instanceId == instanceId or (sharedWeaponName and item.weaponName == sharedWeaponName) then
                        item.mastery = mastery
                        touched = true
                    end
                end
                if not touched then return end

                if selectedItem and (selectedItem.instanceId == instanceId or (sharedWeaponName and selectedItem.weaponName == sharedWeaponName)) then
                    selectedItem.mastery = mastery
                    updateMasteryPanel(selectedItem)
                end
            end))
        end
    end)

    local function applyResponsivePanelLayout()
        local rootWidth = root.AbsoluteSize.X
        if rootWidth <= 0 then return end

        local scaleObject = root:FindFirstChild("ResponsiveScale")
        local rootScale = 1
        if scaleObject and scaleObject:IsA("UIScale") then
            rootScale = math.max(0.001, scaleObject.Scale)
        end

        local function offsetFromVisual(visualPixels)
            return math.max(1, math.floor(visualPixels / rootScale))
        end

        local gapVisual = math.clamp(math.floor(rootWidth * 0.012), 6, 18)
        local edgeVisual = math.clamp(math.floor(rootWidth * 0.008), 4, 10)
        local verticalVisual = math.clamp(math.floor(rootWidth * 0.006), 3, 8)
        local sidebarVisual = math.clamp(math.floor(rootWidth * 0.122), 50, 112)
        local detailVisual = math.clamp(math.floor(rootWidth * 0.255), 96, 248)
        local minGridVisual = math.max(160, math.floor(rootWidth * 0.37))
        local availableForPanels = math.max(0, rootWidth - minGridVisual - (gapVisual * 2) - (edgeVisual * 2))

        if availableForPanels > 0 and (sidebarVisual + detailVisual) > availableForPanels then
            local scaleDown = availableForPanels / math.max(1, sidebarVisual + detailVisual)
            sidebarVisual = math.max(40, math.floor(sidebarVisual * scaleDown))
            detailVisual = math.max(78, math.floor(detailVisual * scaleDown))
        end

        local sidebarWidth = offsetFromVisual(sidebarVisual)
        local detailWidth = offsetFromVisual(detailVisual)
        local gapWidth = offsetFromVisual(gapVisual)
        local edgeInset = offsetFromVisual(edgeVisual)
        local verticalInset = offsetFromVisual(verticalVisual)
        local contentX = edgeInset + sidebarWidth + gapWidth
        local contentWOff = -(contentX + edgeInset)
        local contentWidthOffset = detailWidth + gapWidth

        sidebar.AutomaticSize = Enum.AutomaticSize.None
        sidebar.Position = UDim2.new(0, edgeInset, 0, verticalInset)
        sidebar.Size = UDim2.new(0, sidebarWidth, 1, -(verticalInset * 2))

        local function resizePage(pageName, gridName, emptyName, detailName)
            local page = root:FindFirstChild(pageName)
            if not (page and page:IsA("GuiObject")) then return end

            page.Position = UDim2.new(0, contentX, 0, verticalInset)
            page.Size = UDim2.new(1, contentWOff, 1, -(verticalInset * 2))

            local detailPanel = page:FindFirstChild(detailName)
            if detailPanel and detailPanel:IsA("GuiObject") then
                detailPanel.Size = UDim2.new(0, detailWidth, 1, 0)
                detailPanel.Position = UDim2.new(1, 0, 0, 0)
            end

            local grid = page:FindFirstChild(gridName)
            if grid and grid:IsA("GuiObject") then
                grid.Size = UDim2.new(1, -contentWidthOffset, 1, 0)
            end

            local emptyState = page:FindFirstChild(emptyName)
            if emptyState and emptyState:IsA("GuiObject") then
                emptyState.Size = UDim2.new(1, -contentWidthOffset, 1, 0)
            end
        end

        resizePage("WeaponArea", "GridScroll", "EmptyState", "DetailsPanel")
        resizePage("BoostsPage", "BoostGridScroll", "BoostEmptyState", "BoostDetailsPanel")
        resizePage("SkinsArea", "SkinGridScroll", "SkinEmptyState", "SkinDetailsPanel")
        resizePage("EffectsPage", "TrailGridScroll", "EffectsEmptyState", "TrailDetailsPanel")
        resizePage("EmotesPage", "EmoteGridScroll", "EmotesEmptyState", "EmoteDetailsPanel")
    end

    -- Adapt root height to parent size
    local function updateRootLayout()
        local pH = parent.AbsoluteSize.Y
        if pH > 50 then
            rootHeight = math.max(px(380), pH - px(8))
            root.Size = UDim2.new(1, 0, 0, rootHeight)
        end
        updateResponsiveRootScale(root)
        applyResponsivePanelLayout()
    end

    task.defer(updateRootLayout)
    trackConn(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRootLayout))
    trackConn(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRootLayout))
    bindViewportResize(trackConn, updateRootLayout)

    -- Cleanup on removal
    root.AncestryChanged:Connect(function(_, newParent)
        if not newParent then cleanup() end
    end)

    return root
end

return InventoryUI
