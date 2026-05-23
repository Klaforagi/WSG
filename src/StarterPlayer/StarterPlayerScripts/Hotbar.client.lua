--------------------------------------------------------------------------------
-- Hotbar.client.lua
-- 4-slot hotbar: Melee / Ranged / Bandage / Slot 4
-- Builds the entire UI at runtime — no Studio ScreenGui required.
-- Equip is INSTANT — always delegates to server ForceEquipTool.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player      = Players.LocalPlayer
local backpack    = player:WaitForChild("Backpack")
local starterGear = player:WaitForChild("StarterGear", 5)
local camera      = workspace.CurrentCamera or workspace:WaitForChild("Camera")

-- Disable default backpack UI
pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local requestSpecialUnlock = ReplicatedStorage:WaitForChild("RequestSpecialUnlock")
local specialUnlockGranted = ReplicatedStorage:WaitForChild("SpecialUnlockGranted")
local forceEquipRemote     = ReplicatedStorage:WaitForChild("ForceEquipTool")

local PotionConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("PotionConfig")
    if mod and mod:IsA("ModuleScript") then
        PotionConfig = require(mod)
    end
end)

--------------------------------------------------------------------------------
-- MENU LOCK CHECK
-- MenuLockEnforcer.client.lua sets player:SetAttribute("MenuOpen", bool)
-- and exposes _G.IsMenuLocked(). We use the attribute as the single source
-- of truth for "is the player currently in a menu".
--------------------------------------------------------------------------------
local function isAnyMenuOpen()
    -- Primary: player attribute (set by MenuLockEnforcer)
    if player:GetAttribute("MenuOpen") == true then
        local reason = _G.GetMenuLockReason and _G.GetMenuLockReason() or "unknown"
        warn("[Hotbar] Equip blocked — menu open:", reason)
        return true
    end
    -- Fallback: global function (in case attribute hasn't propagated yet)
    if _G.IsMenuLocked and _G.IsMenuLocked() then
        local reason = _G.GetMenuLockReason and _G.GetMenuLockReason() or "unknown"
        warn("[Hotbar] Equip blocked — menu open:", reason)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- SLOT DEFINITIONS
--------------------------------------------------------------------------------
local SLOT_DEFS = {
    { index = 1, key = Enum.KeyCode.One,   category = "Melee",   toolName = "Sword",      label = "1" },
    { index = 2, key = Enum.KeyCode.Two,   category = "Ranged",  toolName = "Slingshot",   label = "2" },
    { index = 3, key = Enum.KeyCode.Three, category = "Utility", toolName = "Bandage",     label = "3", isUtility = true, utilityType = "bandage" },
    { index = 4, key = Enum.KeyCode.Four,  category = "Extra",   toolName = "",            label = "4", isUtility = true, utilityType = "potion" },
}

local SLOT_COUNT = #SLOT_DEFS

--------------------------------------------------------------------------------
-- STYLE  (all sizing is screen-relative)
--------------------------------------------------------------------------------
-- Slot height as a fraction of viewport height  (~9% of screen)
local SLOT_SCALE     = 0.10
-- Gap between slots as a fraction of viewport width
local GAP_SCALE      = 0.005
-- Bottom margin as a fraction of viewport height
local MARGIN_SCALE   = 0.012

-- Fantasy PvP theme palette
local NAVY        = Color3.fromRGB(12, 14, 28)
local NAVY_LIGHT  = Color3.fromRGB(22, 26, 48)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)
local BLUE_GLOW   = Color3.fromRGB(65, 130, 255)
local RED_GLOW    = Color3.fromRGB(255, 75, 75)
local MUTED_STROKE = Color3.fromRGB(60, 55, 35)

local COLOR_BG       = NAVY
local COLOR_BG_SEL   = NAVY_LIGHT
local COLOR_BG_LOCK  = Color3.fromRGB(35, 12, 12)
local COLOR_STROKE   = GOLD_TEXT
local COLOR_STROKE_S = GOLD_TEXT
local COLOR_STROKE_L = COLOR_STROKE
local COLOR_TEXT     = GOLD_TEXT
local COLOR_KEY      = Color3.fromRGB(200, 180, 120)
local COLOR_LOCK_TXT = COLOR_TEXT

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local specialUnlocked = true   -- slot 3 is now always unlocked (Bandage utility)
local selectedSlot    = 0
local slotUI          = {}
local slotTools       = {}
local potionState     = {
    isLoaded = false,
    potions = {},
    equippedPotionId = nil,
    count = 0,
    equipped = false,
    cooldownEndsAt = 0,
    cooldownRemaining = 0,
}
local potionCooldownMarker = 0
-- current cached team tint (Color3 or nil)
local currentTeamColor = nil

local function getPotionDefinition(potionId)
    if type(potionId) ~= "string" or potionId == "" then
        return nil
    end
    if not PotionConfig or type(PotionConfig.GetById) ~= "function" then
        return nil
    end
    return PotionConfig.GetById(potionId)
end

local function getPotionAccentColor(potionDef)
    local iconColor = potionDef and potionDef.IconColor
    if type(iconColor) == "table" then
        local red = tonumber(iconColor[1])
        local green = tonumber(iconColor[2])
        local blue = tonumber(iconColor[3])
        if red and green and blue then
            return Color3.fromRGB(red, green, blue)
        end
    end
    return Color3.fromRGB(103, 186, 255)
end

-- Weapon cooldown lock state (driven by player attributes set by WeaponLockService)
local weaponLocked     = false
local weaponLockedTool = ""

local function isWeaponLocked()
    return player:GetAttribute("WeaponLocked") == true
end
local function getLockedToolName()
    return player:GetAttribute("WeaponLockedTool") or ""
end

local function teamColorOrNil(team)
    if not team then return nil end
    local name = tostring(team.Name):lower()
    if string.find(name, "neutral") then return nil end
    if team.TeamColor then return team.TeamColor.Color end
    return nil
end

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")

-- Cleanup leftover strokes from previous runs (remove long gold borders)
local function cleanupHotbarStrokes()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, gui in ipairs(pg:GetChildren()) do
        for _, desc in ipairs(gui:GetDescendants()) do
            if desc:IsA("Frame") and (desc.Name == "HotbarContainer" or desc.Name == "Hotbar") then
                for _, child in ipairs(desc:GetChildren()) do
                    if child:IsA("UIStroke") then
                        child:Destroy()
                    end
                end
            end
        end
    end
end
task.defer(cleanupHotbarStrokes)
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "Hotbar"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.DisplayOrder    = 10
screenGui.Parent          = playerGui

-- Container — scale-based, anchored bottom-center
-- Width: enough for N square slots + gaps  (each slot = SLOT_SCALE of viewportY,
-- expressed as a fraction of viewportX for width).
local container = Instance.new("Frame")
container.Name                    = "HotbarContainer"
container.BackgroundTransparency  = 1
container.AnchorPoint             = Vector2.new(0.5, 1)
container.Position                = UDim2.new(0.5, 0, 1 - (MARGIN_SCALE + 0.058), 0)
container.Size                    = UDim2.fromScale(1, SLOT_SCALE) -- initial size; refined by responsive layout
container.Parent                  = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Center
layout.SortOrder           = Enum.SortOrder.LayoutOrder
layout.Padding             = UDim.new(GAP_SCALE, 0)
layout.Parent              = container

local function getViewportSize()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize.X, cam.ViewportSize.Y
    end
    return 1920, 1080
end

local function getXPBarTopPixel(viewportY)
    local shellHeight = UserInputService.TouchEnabled
        and math.max(30, math.floor(viewportY * 0.031))
        or math.max(36, math.floor(viewportY * 0.034))
    return viewportY - 2 - shellHeight
end

local function applyHotbarLayout()
    local _, viewportY = getViewportSize()
    local uiScale = math.clamp(viewportY / 1080, 0.65, 1.15)
    local slotPixels = UserInputService.TouchEnabled
        and math.floor(84 * uiScale)
        or math.floor(96 * uiScale)
    local gapPixels = UserInputService.TouchEnabled
        and math.max(4, math.floor(6 * uiScale))
        or math.max(4, math.floor(8 * uiScale))
    local gapAboveXP = UserInputService.TouchEnabled
        and math.max(4, math.floor(viewportY * 0.006))
        or math.max(6, math.floor(viewportY * 0.007))
    local hotbarBottom = getXPBarTopPixel(viewportY) - gapAboveXP

    container.Size = UDim2.new(1, 0, 0, slotPixels)
    container.Position = UDim2.new(0.5, 0, 0, hotbarBottom)
    layout.Padding = UDim.new(0, gapPixels)
end

do
    local viewportConn = nil
    local function bindCamera()
        if viewportConn then
            viewportConn:Disconnect()
            viewportConn = nil
        end
        local cam = workspace.CurrentCamera
        if cam then
            viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyHotbarLayout)
        end
    end
    bindCamera()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        bindCamera()
        applyHotbarLayout()
    end)
end

task.defer(applyHotbarLayout)

--------------------------------------------------------------------------------
-- FORWARD DECLARE
--------------------------------------------------------------------------------
local equipSlot

local function buildPotionIcon(parent)
    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "PotionIcon"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    iconFrame.Position = UDim2.fromScale(0.5, 0.44)
    iconFrame.Size = UDim2.fromScale(0.56, 0.56)
    iconFrame.BackgroundTransparency = 1
    iconFrame.ZIndex = 2
    iconFrame.Parent = parent

    local bottleColor = Color3.fromRGB(103, 186, 255)
    local bottleDark = Color3.fromRGB(40, 92, 140)
    local liquidColor = Color3.fromRGB(62, 156, 245)

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.AnchorPoint = Vector2.new(0.5, 1)
    body.Position = UDim2.fromScale(0.5, 1)
    body.Size = UDim2.fromScale(0.62, 0.72)
    body.BackgroundColor3 = bottleColor
    body.BorderSizePixel = 0
    body.ZIndex = 2
    body.Parent = iconFrame
    Instance.new("UICorner", body).CornerRadius = UDim.new(0.22, 0)

    local bodyStroke = Instance.new("UIStroke", body)
    bodyStroke.Color = bottleDark
    bodyStroke.Thickness = 1.2

    local neck = Instance.new("Frame")
    neck.Name = "Neck"
    neck.AnchorPoint = Vector2.new(0.5, 1)
    neck.Position = UDim2.fromScale(0.5, 0.32)
    neck.Size = UDim2.fromScale(0.26, 0.24)
    neck.BackgroundColor3 = bottleColor
    neck.BorderSizePixel = 0
    neck.ZIndex = 3
    neck.Parent = iconFrame
    Instance.new("UICorner", neck).CornerRadius = UDim.new(0.2, 0)

    local cap = Instance.new("Frame")
    cap.Name = "Cap"
    cap.AnchorPoint = Vector2.new(0.5, 0)
    cap.Position = UDim2.fromScale(0.5, 0.02)
    cap.Size = UDim2.fromScale(0.32, 0.1)
    cap.BackgroundColor3 = bottleDark
    cap.BorderSizePixel = 0
    cap.ZIndex = 4
    cap.Parent = iconFrame
    Instance.new("UICorner", cap).CornerRadius = UDim.new(0.25, 0)

    local liquid = Instance.new("Frame")
    liquid.Name = "Liquid"
    liquid.AnchorPoint = Vector2.new(0.5, 1)
    liquid.Position = UDim2.fromScale(0.5, 0.94)
    liquid.Size = UDim2.fromScale(0.48, 0.32)
    liquid.BackgroundColor3 = liquidColor
    liquid.BorderSizePixel = 0
    liquid.ZIndex = 3
    liquid.Parent = iconFrame
    Instance.new("UICorner", liquid).CornerRadius = UDim.new(0.2, 0)

    local plusH = Instance.new("Frame")
    plusH.Name = "PlusH"
    plusH.AnchorPoint = Vector2.new(0.5, 0.5)
    plusH.Position = UDim2.fromScale(0.5, 0.6)
    plusH.Size = UDim2.fromScale(0.26, 0.08)
    plusH.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    plusH.BorderSizePixel = 0
    plusH.ZIndex = 4
    plusH.Parent = iconFrame
    Instance.new("UICorner", plusH).CornerRadius = UDim.new(1, 0)

    local plusV = Instance.new("Frame")
    plusV.Name = "PlusV"
    plusV.AnchorPoint = Vector2.new(0.5, 0.5)
    plusV.Position = UDim2.fromScale(0.5, 0.6)
    plusV.Size = UDim2.fromScale(0.08, 0.26)
    plusV.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    plusV.BorderSizePixel = 0
    plusV.ZIndex = 4
    plusV.Parent = iconFrame
    Instance.new("UICorner", plusV).CornerRadius = UDim.new(1, 0)

    return iconFrame
end

--------------------------------------------------------------------------------
-- BANDAGE ICON (programmatic — built from UI primitives)
--------------------------------------------------------------------------------
local function buildBandageIcon(parent)
    local iconFrame = Instance.new("Frame")
    iconFrame.Name                   = "BandageIcon"
    iconFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
    iconFrame.Position               = UDim2.fromScale(0.5, 0.45)
    iconFrame.Size                   = UDim2.fromScale(0.58, 0.58)
    iconFrame.BackgroundTransparency = 1
    iconFrame.ZIndex                 = 2
    iconFrame.Parent                 = parent

    local TAN       = Color3.fromRGB(235, 210, 170)
    local TAN_DARK  = Color3.fromRGB(175, 145, 105)
    local PAD_COLOR = Color3.fromRGB(248, 242, 230)
    local RED_CROSS = Color3.fromRGB(195, 55, 55)

    -- Main diagonal strip
    local strip1 = Instance.new("Frame")
    strip1.Name                   = "Strip1"
    strip1.AnchorPoint            = Vector2.new(0.5, 0.5)
    strip1.Position               = UDim2.fromScale(0.5, 0.5)
    strip1.Size                   = UDim2.fromScale(0.90, 0.30)
    strip1.Rotation               = -35
    strip1.BackgroundColor3       = TAN
    strip1.BorderSizePixel        = 0
    strip1.Parent                 = iconFrame
    Instance.new("UICorner", strip1).CornerRadius = UDim.new(0.35, 0)
    local s1s = Instance.new("UIStroke", strip1)
    s1s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s1s.Color     = TAN_DARK
    s1s.Thickness = 1

    -- Second crossing strip
    local strip2 = Instance.new("Frame")
    strip2.Name                   = "Strip2"
    strip2.AnchorPoint            = Vector2.new(0.5, 0.5)
    strip2.Position               = UDim2.fromScale(0.5, 0.5)
    strip2.Size                   = UDim2.fromScale(0.90, 0.30)
    strip2.Rotation               = 35
    strip2.BackgroundColor3       = TAN
    strip2.BorderSizePixel        = 0
    strip2.Parent                 = iconFrame
    Instance.new("UICorner", strip2).CornerRadius = UDim.new(0.35, 0)
    local s2s = Instance.new("UIStroke", strip2)
    s2s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s2s.Color     = TAN_DARK
    s2s.Thickness = 1

    -- Center pad (gauze)
    local pad = Instance.new("Frame")
    pad.Name                   = "Pad"
    pad.AnchorPoint            = Vector2.new(0.5, 0.5)
    pad.Position               = UDim2.fromScale(0.5, 0.5)
    pad.Size                   = UDim2.fromScale(0.24, 0.24)
    pad.BackgroundColor3       = PAD_COLOR
    pad.BorderSizePixel        = 0
    pad.ZIndex                 = 3
    pad.Parent                 = iconFrame
    Instance.new("UICorner", pad).CornerRadius = UDim.new(0.18, 0)
    local ps = Instance.new("UIStroke", pad)
    ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    ps.Color     = TAN_DARK
    ps.Thickness = 1

    -- Small red cross on the pad
    local crossH = Instance.new("Frame")
    crossH.AnchorPoint       = Vector2.new(0.5, 0.5)
    crossH.Position          = UDim2.fromScale(0.5, 0.5)
    crossH.Size              = UDim2.fromScale(0.55, 0.16)
    crossH.BackgroundColor3  = RED_CROSS
    crossH.BorderSizePixel   = 0
    crossH.ZIndex            = 4
    crossH.Parent            = pad

    local crossV = Instance.new("Frame")
    crossV.AnchorPoint       = Vector2.new(0.5, 0.5)
    crossV.Position          = UDim2.fromScale(0.5, 0.5)
    crossV.Size              = UDim2.fromScale(0.16, 0.55)
    crossV.BackgroundColor3  = RED_CROSS
    crossV.BorderSizePixel   = 0
    crossV.ZIndex            = 4
    crossV.Parent            = pad

    return iconFrame
end

--------------------------------------------------------------------------------
-- BUILD SLOTS
--------------------------------------------------------------------------------
local function buildSlot(def)
    local idx = def.index

    -- Square button — both axes resolve from container HEIGHT (RelativeYY)
    -- so fromScale(1, 1) = a perfect square matching the container's height
    local btn = Instance.new("TextButton")
    btn.Name                    = "Slot" .. idx
    btn.LayoutOrder             = idx
    btn.SizeConstraint          = Enum.SizeConstraint.RelativeYY
    btn.Size                    = UDim2.fromScale(1, 1)
    btn.BackgroundColor3        = COLOR_BG
    btn.BackgroundTransparency  = 0.15
    btn.AutoButtonColor         = false
    btn.Text                    = ""
    btn.Parent                  = container

    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 4)

    local stroke = Instance.new("UIStroke", btn)
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness       = 2
    stroke.Color           = COLOR_STROKE

    -- Key number (top-left, scale-based)
    local keyLabel = Instance.new("TextLabel")
    keyLabel.Name                  = "KeyLabel"
    keyLabel.Size                  = UDim2.fromScale(0.3, 0.28)
    keyLabel.Position              = UDim2.fromScale(0.06, 0.02)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Text                  = tostring(idx)
    keyLabel.Font                  = Enum.Font.GothamBlack
    keyLabel.TextScaled            = true
    keyLabel.TextColor3            = COLOR_KEY
    keyLabel.TextXAlignment        = Enum.TextXAlignment.Left
    keyLabel.Parent                = btn

    -- Tool thumbnail (centered, scale-based)
    local thumb = Instance.new("ImageLabel")
    thumb.Name                  = "Thumb"
    thumb.AnchorPoint           = Vector2.new(0.5, 0.5)
    thumb.Position              = UDim2.fromScale(0.5, 0.45)
    thumb.Size                  = UDim2.fromScale(0.58, 0.58)
    thumb.BackgroundTransparency = 1
    thumb.ScaleType             = Enum.ScaleType.Fit
    thumb.Image                 = ""
    thumb.Visible               = false
    thumb.Parent                = btn

    -- Tool name (bottom, scale-based)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name                  = "NameLabel"
    nameLabel.AnchorPoint           = Vector2.new(0.5, 1)
    nameLabel.Position              = UDim2.fromScale(0.5, 0.96)
    nameLabel.Size                  = UDim2.fromScale(0.9, 0.22)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text                  = ""
    nameLabel.Font                  = Enum.Font.GothamBold
    nameLabel.TextScaled            = true
    nameLabel.TextColor3            = COLOR_TEXT
    nameLabel.TextTruncate          = Enum.TextTruncate.AtEnd
    nameLabel.Parent                = btn

    -- Cooldown overlay: dark semi-transparent frame anchored to the bottom.
    -- Starts at 0 height (ready). On weapon use it jumps to full height (slot dims)
    -- then tweens height back to 0 (wipes away bottom-to-top) over cooldown duration.
    local cooldownOverlay = Instance.new("Frame")
    cooldownOverlay.Name                   = "CooldownOverlay"
    cooldownOverlay.AnchorPoint            = Vector2.new(0, 0)
    cooldownOverlay.Position               = UDim2.fromScale(0, 0)
    cooldownOverlay.Size                   = UDim2.fromScale(1, 0)
    cooldownOverlay.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    cooldownOverlay.BackgroundTransparency = 0.45
    cooldownOverlay.BorderSizePixel        = 0
    cooldownOverlay.ZIndex                 = 5
    cooldownOverlay.Parent                 = btn

    local overlayCorner = Instance.new("UICorner", cooldownOverlay)
    overlayCorner.CornerRadius = UDim.new(0, 4)

    -- Numeric cooldown countdown (centered, shows seconds remaining)
    local cdCountdown = Instance.new("TextLabel")
    cdCountdown.Name                   = "CooldownCountdown"
    cdCountdown.AnchorPoint            = Vector2.new(0.5, 0.5)
    cdCountdown.Position               = UDim2.fromScale(0.5, 0.45)
    cdCountdown.Size                   = UDim2.fromScale(0.7, 0.45)
    cdCountdown.BackgroundTransparency = 1
    cdCountdown.Text                   = ""
    cdCountdown.Font                   = Enum.Font.GothamBlack
    cdCountdown.TextScaled             = true
    cdCountdown.TextColor3             = Color3.fromRGB(255, 255, 255)
    cdCountdown.TextStrokeColor3       = Color3.new(0, 0, 0)
    cdCountdown.TextStrokeTransparency = 0.3
    cdCountdown.ZIndex                 = 6
    cdCountdown.Visible                = false
    cdCountdown.Parent                 = btn

    -- Build programmatic bandage icon for the utility slot
    local bandageIcon = nil
    local potionIcon = nil
    if def.utilityType == "bandage" then
        bandageIcon = buildBandageIcon(btn)
    elseif def.utilityType == "potion" then
        potionIcon = buildPotionIcon(btn)
    end

    local countBadge = Instance.new("Frame")
    countBadge.Name = "CountBadge"
    countBadge.AnchorPoint = Vector2.new(1, 0)
    countBadge.Position = UDim2.new(1, -6, 0, 6)
    countBadge.Size = UDim2.new(0, 24, 0, 18)
    countBadge.BackgroundColor3 = Color3.fromRGB(18, 26, 40)
    countBadge.BorderSizePixel = 0
    countBadge.ZIndex = 6
    countBadge.Visible = false
    countBadge.Parent = btn
    Instance.new("UICorner", countBadge).CornerRadius = UDim.new(0, 8)

    local countStroke = Instance.new("UIStroke", countBadge)
    countStroke.Color = Color3.fromRGB(103, 186, 255)
    countStroke.Thickness = 1
    countStroke.Transparency = 0.25

    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "CountLabel"
    countLabel.BackgroundTransparency = 1
    countLabel.Size = UDim2.fromScale(1, 1)
    countLabel.Font = Enum.Font.GothamBold
    countLabel.TextScaled = true
    countLabel.Text = ""
    countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    countLabel.ZIndex = 7
    countLabel.Parent = countBadge

    slotUI[idx] = {
        btn               = btn,
        stroke            = stroke,
        keyLabel          = keyLabel,
        nameLabel         = nameLabel,
        thumb             = thumb,
        bandageIcon       = bandageIcon,
        potionIcon        = potionIcon,
        countBadge        = countBadge,
        countLabel        = countLabel,
        cooldownOverlay   = cooldownOverlay,
        cooldownCountdown = cdCountdown,
    }

    btn.Activated:Connect(function()
        equipSlot(idx)
    end)
end

for _, def in ipairs(SLOT_DEFS) do
    buildSlot(def)
end

--------------------------------------------------------------------------------
-- COOLDOWN API  (_G.HotbarCooldown.start(slotIndex, duration))
-- Called by ToolMelee and ToolGunHUD after an attack fires.
-- The slot overlay jumps to full height (instant dim) then wipes away
-- bottom-to-top over `duration` seconds, matching the weapon's cooldown.
--------------------------------------------------------------------------------
_G.HotbarCooldown = {}
_G.HotbarCooldown.start = function(slotIndex, duration)
    local ui = slotUI[slotIndex]
    if not ui or not ui.cooldownOverlay then return end
    local overlay = ui.cooldownOverlay
    -- Cancel any running tween by setting size directly (interrupts previous tween)
    overlay.Size = UDim2.fromScale(1, 1)    -- fill slot immediately (dim)
    -- Wipe from bottom to top over the cooldown duration
    TweenService:Create(
        overlay,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { Size = UDim2.fromScale(1, 0) }
    ):Play()
end

-- Numeric countdown that ticks every second on a slot (used by bandage cooldown)
_G.HotbarCooldown.startCountdown = function(slotIndex, duration)
    local ui = slotUI[slotIndex]
    if not ui or not ui.cooldownCountdown then return end
    local cdLabel = ui.cooldownCountdown
    cdLabel.Visible = true
    local endTime = tick() + duration
    task.spawn(function()
        while tick() < endTime do
            local remaining = math.ceil(endTime - tick())
            if remaining <= 0 then break end
            cdLabel.Text = tostring(remaining)
            task.wait(0.5)
        end
        cdLabel.Text = ""
        cdLabel.Visible = false
    end)
end

--------------------------------------------------------------------------------
-- TOOL LOOKUP
--------------------------------------------------------------------------------
local function getToolForSlot(idx)
    local def = SLOT_DEFS[idx]
    if not def then return nil end
    local function scan(cont)
        if not cont then return nil end
        for _, child in ipairs(cont:GetChildren()) do
            if not child:IsA("Tool") then continue end
            local attr = child:GetAttribute("HotbarCategory")
            if type(attr) == "string" and string.lower(attr) == string.lower(def.category) then
                return child
            end
            if child.Name == def.toolName then
                return child
            end
        end
        return nil
    end
    return scan(player.Character) or scan(backpack) or scan(starterGear)
end

-- AssetCodes for weapon icons
local AssetCodes = nil
pcall(function()
    local ac = ReplicatedStorage:FindFirstChild("AssetCodes")
    if ac and ac:IsA("ModuleScript") then AssetCodes = require(ac) end
end)

local function getToolIcon(tool)
    if not tool then return "" end
    -- 1) Check for an explicit Icon attribute
    local attr = tool:GetAttribute("Icon")
    if type(attr) == "string" and #attr > 0 then return attr end
    -- 2) Check AssetCodes by tool name (e.g. "Shortbow" -> Shortbow icon)
    if AssetCodes and type(AssetCodes.Get) == "function" then
        local acIcon = AssetCodes.Get(tool.Name)
        if type(acIcon) == "string" and #acIcon > 0 then return acIcon end
    end
    -- 3) Fall back to tool TextureId
    local ok, tex = pcall(function() return tool.TextureId end)
    if ok and type(tex) == "string" and #tex > 0 then return tex end
    return ""
end

--------------------------------------------------------------------------------
-- REFRESH UI
--------------------------------------------------------------------------------
local function refreshSlots()
    for idx = 1, SLOT_COUNT do
        local ui  = slotUI[idx]
        local def = SLOT_DEFS[idx]
        if not ui then continue end

        local tool = getToolForSlot(idx)
        slotTools[idx] = tool

        local locked       = isWeaponLocked()
        local lockedName   = getLockedToolName()
        local isUtility  = def.isUtility == true
        local utilityType = def.utilityType
        local isLocked   = (idx == 3 and not specialUnlocked and not isUtility)
        local isEquipped = (not isUtility and tool ~= nil and player.Character ~= nil
                            and tool.Parent == player.Character)
        -- A non-equipped slot is weapon-cooldown-locked when the weapon lock is
        -- active and this slot's tool is not the one holding the lock.
        local isCooldownLocked = locked and (not isEquipped or (tool and tool.Name ~= lockedName))

        if isEquipped then
            selectedSlot = idx
        elseif selectedSlot == idx and not isEquipped then
            selectedSlot = 0
        end

        -- thumbnail
        if utilityType == "bandage" then
            -- Bandage slot: use programmatic icon, hide image thumbnail
            ui.thumb.Visible = false
            if ui.bandageIcon then
                ui.bandageIcon.Visible = true
            end
            if ui.potionIcon then
                ui.potionIcon.Visible = false
            end
            if ui.countBadge then
                ui.countBadge.Visible = false
            end
        elseif utilityType == "potion" then
            local hasEquippedPotion = potionState.equipped == true and (tonumber(potionState.count) or 0) > 0
            ui.thumb.Visible = false
            if ui.bandageIcon then
                ui.bandageIcon.Visible = false
            end
            if ui.potionIcon then
                ui.potionIcon.Visible = hasEquippedPotion
            end
            if ui.countBadge and ui.countLabel then
                ui.countLabel.Text = tostring(math.max(0, math.floor(tonumber(potionState.count) or 0)))
                ui.countBadge.Visible = hasEquippedPotion and math.max(0, math.floor(tonumber(potionState.count) or 0)) > 0
            end
        else
            local icon = getToolIcon(tool)
            if #icon > 0 then
                ui.thumb.Image   = icon
                ui.thumb.Visible = true
            else
                ui.thumb.Image   = ""
                ui.thumb.Visible = false
            end
        end

        -- colours / text
            -- compute colors, allowing an optional team tint to influence active/selected background
                    local teamColor = currentTeamColor
                    local bgColor = COLOR_BG
                    local selBg = COLOR_BG_SEL
                    local lockBg = COLOR_BG_LOCK
                    local strokeColor = COLOR_STROKE
                    local strokeSel = COLOR_STROKE_S
                    if teamColor then
                        -- Unselected background: darker team tint instead of gray
                        bgColor = teamColor:Lerp(Color3.new(0,0,0), 0.55)
                        -- Selected background: slightly lighter team tint for contrast
                        selBg = teamColor:Lerp(Color3.new(1,1,1), 0.12)
                        -- Selected stroke: brightened team color for a clear outline when equipped
                        strokeSel = teamColor:Lerp(Color3.new(1,1,1), 0.6)
                    end

                    if utilityType == "bandage" then
                        -- Bandage utility slot: always looks ready (not locked)
                        ui.btn.BackgroundColor3 = bgColor
                        ui.stroke.Color         = strokeColor
                        ui.nameLabel.TextColor3 = COLOR_TEXT
                        ui.nameLabel.Text       = "Bandage"
                    elseif utilityType == "potion" then
                        local equippedPotionDef = getPotionDefinition(potionState.equippedPotionId)
                        local potionAccent = getPotionAccentColor(equippedPotionDef)
                        local hasEquippedPotion = potionState.equipped == true and (tonumber(potionState.count) or 0) > 0
                        local isPotionCoolingDown = hasEquippedPotion and (tonumber(potionState.cooldownRemaining) or 0) > 0
                        if hasEquippedPotion then
                            ui.btn.BackgroundColor3 = isPotionCoolingDown and Color3.fromRGB(14, 28, 44) or bgColor
                            ui.stroke.Color         = potionAccent
                            ui.nameLabel.TextColor3 = potionAccent:Lerp(Color3.fromRGB(255, 255, 255), 0.22)
                            ui.nameLabel.Text       = equippedPotionDef and (equippedPotionDef.HotbarLabel or equippedPotionDef.DisplayName) or "Potion"
                        else
                            ui.btn.BackgroundColor3 = bgColor
                            ui.stroke.Color         = Color3.fromRGB(58, 70, 95)
                            ui.nameLabel.TextColor3 = Color3.fromRGB(95, 106, 132)
                            ui.nameLabel.Text       = ""
                        end
                    elseif isLocked then
                        ui.btn.BackgroundColor3 = lockBg
                        ui.stroke.Color         = COLOR_STROKE_L
                        ui.nameLabel.Text       = "LOCKED"
                        ui.nameLabel.TextColor3 = COLOR_LOCK_TXT
                    elseif isCooldownLocked then
                        -- Weapon cooldown lock: dim the slot visually
                        ui.btn.BackgroundColor3 = Color3.fromRGB(28, 20, 10)
                        ui.stroke.Color         = Color3.fromRGB(120, 90, 30)
                        ui.nameLabel.TextColor3 = Color3.fromRGB(130, 110, 60)
                        ui.nameLabel.Text       = tool and tool.Name or ""
                    elseif isEquipped then
                        ui.btn.BackgroundColor3 = selBg
                        ui.stroke.Color         = strokeSel
                        ui.nameLabel.TextColor3 = COLOR_TEXT
                        ui.nameLabel.Text       = tool and tool.Name or def.label
                    else
                        ui.btn.BackgroundColor3 = bgColor
                        ui.stroke.Color         = strokeColor
                        ui.nameLabel.TextColor3 = COLOR_TEXT
                        ui.nameLabel.Text       = tool and tool.Name or ""
                    end
    end
end

local function ensurePotionRemotes()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotesFolder then
        return nil
    end

    local potionFolder = remotesFolder:FindFirstChild("Potions") or remotesFolder:WaitForChild("Potions", 5)
    if not potionFolder then
        return nil
    end

    local getState = potionFolder:FindFirstChild("GetPotionState")
    local usePotion = potionFolder:FindFirstChild("UseEquippedPotion")
    local stateUpdated = remotesFolder:FindFirstChild("PotionStateUpdated")
    if not getState or not usePotion or not stateUpdated then
        return nil
    end

    return {
        getState = getState,
        usePotion = usePotion,
        stateUpdated = stateUpdated,
    }
end

local function clearPotionCooldownVisuals()
    local ui = slotUI[4]
    if not ui then
        return
    end
    if ui.cooldownOverlay then
        ui.cooldownOverlay.Size = UDim2.fromScale(1, 0)
    end
    if ui.cooldownCountdown then
        ui.cooldownCountdown.Text = ""
        ui.cooldownCountdown.Visible = false
    end
    potionCooldownMarker = 0
end

local function syncPotionCooldownVisuals()
    local remaining = math.max(0, tonumber(potionState.cooldownRemaining) or 0)
    local cooldownEndsAt = tonumber(potionState.cooldownEndsAt) or 0
    local hasEquippedPotion = potionState.equipped == true and math.max(0, math.floor(tonumber(potionState.count) or 0)) > 0
    if not hasEquippedPotion or remaining <= 0 then
        clearPotionCooldownVisuals()
        return
    end

    if cooldownEndsAt == potionCooldownMarker then
        return
    end

    potionCooldownMarker = cooldownEndsAt
    if _G.HotbarCooldown and _G.HotbarCooldown.start then
        _G.HotbarCooldown.start(4, remaining)
    end
    if _G.HotbarCooldown and _G.HotbarCooldown.startCountdown then
        _G.HotbarCooldown.startCountdown(4, remaining)
    end
end

local function ingestPotionState(state)
    if type(state) ~= "table" then
        return
    end

    potionState = {
        isLoaded = state.isLoaded == true,
        potions = type(state.potions) == "table" and state.potions or {},
        equippedPotionId = type(state.equippedPotionId) == "string" and state.equippedPotionId or nil,
        count = math.max(0, math.floor(tonumber(state.count) or 0)),
        equipped = state.equipped == true,
        cooldownEndsAt = tonumber(state.cooldownEndsAt) or 0,
        cooldownRemaining = math.max(0, tonumber(state.cooldownRemaining) or 0),
        serverTime = tonumber(state.serverTime) or 0,
    }

    if potionState.count <= 0 then
        potionState.equipped = false
        potionState.equippedPotionId = nil
    end

    syncPotionCooldownVisuals()
    task.defer(refreshSlots)
end

local function refreshPotionState()
    local remotes = ensurePotionRemotes()
    if not remotes or not remotes.getState then
        return
    end

    local ok, state = pcall(function()
        return remotes.getState:InvokeServer()
    end)
    if ok then
        ingestPotionState(state)
    end
end

--------------------------------------------------------------------------------
-- EQUIP / UNEQUIP  — always instant, delegates to server
--------------------------------------------------------------------------------
equipSlot = function(idx)
    local def = SLOT_DEFS[idx]
    if not def then return end

    -- MENU LOCK: block all equip attempts while any menu is open
    if isAnyMenuOpen() then return end

    -- WEAPON COOLDOWN LOCK: block switching to a different weapon while locked.
    -- Unequipping the current weapon (clicking the equipped slot) is still allowed.
    if isWeaponLocked() then
        if not def.isUtility then
            local lockedName = getLockedToolName()
            local tool = getToolForSlot(idx)
            -- Block only if this slot's tool is not the locked one
            if tool and tool.Name ~= lockedName then return end
        end
    end

    -- Slot 3 = Bandage utility (not a weapon)
    if def.isUtility then
        if def.utilityType == "bandage" then
            if _G.ActivateBandage then
                _G.ActivateBandage()
            end
        elseif def.utilityType == "potion" then
            local hasEquippedPotion = potionState.equipped == true and math.max(0, math.floor(tonumber(potionState.count) or 0)) > 0
            if not hasEquippedPotion then
                refreshSlots()
                return
            end
            if _G.IsBandaging and _G.CancelBandage then
                _G.CancelBandage()
            end

            local remotes = ensurePotionRemotes()
            if not remotes or not remotes.usePotion then
                return
            end

            local ok, success, _, payload = pcall(function()
                return remotes.usePotion:InvokeServer()
            end)
            if ok and success and type(payload) == "table" then
                ingestPotionState(payload.state)
            elseif ok and type(payload) == "table" then
                ingestPotionState(payload.state)
            else
                refreshPotionState()
            end
        end
        return
    end

    -- Slot 3 locked (legacy special slot — kept for safety)
    if idx == 3 and not specialUnlocked then
        requestSpecialUnlock:FireServer()
        local ui = slotUI[3]
        if ui then
            ui.nameLabel.Text = "UNLOCKING..."
            task.delay(1.5, function()
                if not specialUnlocked then ui.nameLabel.Text = "LOCKED" end
            end)
        end
        return
    end

    -- Cancel bandage if switching to a weapon slot
    if _G.IsBandaging then
        if _G.CancelBandage then
            _G.CancelBandage()
        end
    end

    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- block equipping while dead / ragdolled
    if hum.Health <= 0 or char:GetAttribute("_ragdolled") then return end

    local tool = getToolForSlot(idx)
    if not tool then
        refreshSlots()
        return
    end

    if tool.Parent == char then
        -- Already equipped → unequip
        hum:UnequipTools()
        task.defer(refreshSlots)
        return
    end

    -- If tool is in Backpack, try local equip (fastest path)
    if tool.Parent == backpack then
        hum:UnequipTools()
        pcall(function() hum:EquipTool(tool) end)
        task.defer(refreshSlots)
        return
    end

    -- Tool only in StarterGear or elsewhere → ask server to handle it
    hum:UnequipTools()
    forceEquipRemote:FireServer(def.category, tool.Name)
end

--------------------------------------------------------------------------------
-- EVENTS: KEEP UI IN SYNC
--------------------------------------------------------------------------------
local function connectContainerEvents(cont)
    cont.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then task.defer(refreshSlots) end
    end)
    cont.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then task.defer(refreshSlots) end
    end)
end

connectContainerEvents(backpack)
if starterGear then connectContainerEvents(starterGear) end

local function onCharacter(char)
    connectContainerEvents(char)
    task.defer(refreshSlots)
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(function(char)
    task.wait(0.3)
    onCharacter(char)
end)

-- apply initial team color and update when team changes
currentTeamColor = teamColorOrNil(player.Team)
player:GetPropertyChangedSignal("Team"):Connect(function()
    currentTeamColor = teamColorOrNil(player.Team)
    task.defer(refreshSlots)
end)

--------------------------------------------------------------------------------
-- SPECIAL UNLOCK RESPONSE
--------------------------------------------------------------------------------
specialUnlockGranted.OnClientEvent:Connect(function(unlocked)
    specialUnlocked = (unlocked == true)
    refreshSlots()
end)

do
    local remotes = ensurePotionRemotes()
    if remotes and remotes.stateUpdated and remotes.stateUpdated:IsA("RemoteEvent") then
        remotes.stateUpdated.OnClientEvent:Connect(function(state)
            ingestPotionState(state)
        end)
    end
end

--------------------------------------------------------------------------------
-- WEAPON LOCK ATTRIBUTE LISTENER
-- WeaponLockService sets WeaponLocked / WeaponLockedTool on the player.
-- Re-render the hotbar immediately when the lock changes so slots gray out
-- and re-enable at the right moment.
--------------------------------------------------------------------------------
player:GetAttributeChangedSignal("WeaponLocked"):Connect(function()
    task.defer(refreshSlots)
end)
player:GetAttributeChangedSignal("WeaponLockedTool"):Connect(function()
    task.defer(refreshSlots)
end)

--------------------------------------------------------------------------------
-- LOADOUT CHANGED (server notifies client after equip changes / load complete)
--------------------------------------------------------------------------------
local loadoutChangedRemote = ReplicatedStorage:FindFirstChild("LoadoutChanged")
if not loadoutChangedRemote then
    loadoutChangedRemote = ReplicatedStorage:WaitForChild("LoadoutChanged", 10)
end
if loadoutChangedRemote and loadoutChangedRemote:IsA("RemoteEvent") then
    loadoutChangedRemote.OnClientEvent:Connect(function(data)
        print("[ToolbarSync] LoadoutChanged received:",
            "melee=", data and data.melee or "(nil)",
            "ranged=", data and data.ranged or "(nil)")
        -- Force refresh after a brief wait to let tools arrive in Backpack
        task.wait(0.15)
        refreshSlots()
        -- Second refresh in case tools were still being cloned
        task.wait(0.5)
        refreshSlots()
    end)
end

--------------------------------------------------------------------------------
-- KEYBOARD INPUT
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    -- Block hotbar keys while any menu/popup is open
    if isAnyMenuOpen() then return end
    for _, def in ipairs(SLOT_DEFS) do
        if input.KeyCode == def.key then
            -- While weapon-locked, only allow the key of the currently locked tool
            -- (so the player can unequip by pressing their weapon key).
            if isWeaponLocked() and not def.isUtility then
                local lockedName = getLockedToolName()
                local tool = getToolForSlot(def.index)
                if not tool or tool.Name ~= lockedName then return end
            end
            equipSlot(def.index)
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- INITIAL REFRESH (wait briefly for server to deliver tools)
--------------------------------------------------------------------------------
task.spawn(function()
    refreshPotionState()
    for _ = 1, 30 do
        refreshSlots()
        if slotTools[1] and slotTools[2] then break end
        task.wait(0.2)
    end
end)
