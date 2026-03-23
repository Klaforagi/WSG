--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Compact grid inventory with right-side details panel
--
-- Layout:
--   Left sidebar:   Melee · Ranged · Boosts · Skins · Effects
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

-- ═══════════════════════════════════════════════════════════════════════════
-- Responsive pixel helper
-- ═══════════════════════════════════════════════════════════════════════════
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
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

-- ═══════════════════════════════════════════════════════════════════════════
-- Rarity colour palette
-- ═══════════════════════════════════════════════════════════════════════════
local RARITY_COLORS = {
    Common    = Color3.fromRGB(150, 150, 155),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(180, 60, 255),
    Legendary = Color3.fromRGB(255, 180, 30),
}
local RARITY_BG_COLORS = {
    Common    = Color3.fromRGB(42, 44, 55),
    Rare      = Color3.fromRGB(22, 38, 68),
    Epic      = Color3.fromRGB(46, 22, 65),
    Legendary = Color3.fromRGB(58, 46, 18),
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Tab definitions  (Melee & Ranged are separate; above Boosts/Skins/Effects)
-- ═══════════════════════════════════════════════════════════════════════════
local TAB_DEFS = {
    { id = "melee",   icon = "\u{2694}",  label = "Melee",   order = 1 },
    { id = "ranged",  icon = "\u{1F3F9}", label = "Ranged",  order = 2 },
    { id = "boosts",  icon = "\u{26A1}",  label = "Boosts",  order = 3 },
    { id = "skins",   icon = "\u{2726}",  label = "Skins",   order = 4 },
    { id = "effects", icon = "\u{2738}",  label = "Effects", order = 5 },
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
local AssetCodesGlobal = nil
local boostRemotes = nil

local function safeRequireBoostConfig()
    local mod = ReplicatedStorage:FindFirstChild("BoostConfig")
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

local BOOST_ACCENT_COLORS = {
    coins_2x = Color3.fromRGB(255, 200, 40),
    quest_2x = Color3.fromRGB(80, 165, 255),
}

local function getBoostIconImage(def)
    if type(def) ~= "table" then return nil end
    if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then return def.IconAssetId end
    local key = def.IconKey
    if AssetCodesGlobal and type(AssetCodesGlobal.Get) == "function" and key then
        local image = AssetCodesGlobal.Get(key)
        if type(image) == "string" and #image > 0 then return image end
    end
    return nil
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
    AssetCodesGlobal = AssetCodesGlobal or safeRequireAssetCodes()

    -- ──────────────────────────────────────────────────────────────────────
    -- Dimensions
    -- ──────────────────────────────────────────────────────────────────────
    local TAB_W     = px(140)
    local TAB_GAP   = px(10)
    local DETAIL_W  = px(315)
    local GRID_GAP  = px(10)

    local screenY   = 1080
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize.Y > 0 then screenY = cam.ViewportSize.Y end
    end)
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
            rarity     = "Common",
            isInstance = false,
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

    -- ══════════════════════════════════════════════════════════════════════
    --  SIDEBAR  (tab buttons)
    -- ══════════════════════════════════════════════════════════════════════
    local sidebar = Instance.new("Frame")
    sidebar.Name = "TabSidebar"
    sidebar.BackgroundColor3 = SIDEBAR_BG
    sidebar.BorderSizePixel = 0
    sidebar.Size = UDim2.new(0, TAB_W, 1, 0)
    sidebar.ClipsDescendants = false
    sidebar.Parent = root
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, px(10))

    local sideStroke = Instance.new("UIStroke", sidebar)
    sideStroke.Color = CARD_STROKE; sideStroke.Thickness = 1.2; sideStroke.Transparency = 0.3

    local sideLayout = Instance.new("UIListLayout", sidebar)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sideLayout.Padding = UDim.new(0, px(3))
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local sidePad = Instance.new("UIPadding", sidebar)
    sidePad.PaddingTop    = UDim.new(0, px(10))
    sidePad.PaddingBottom = UDim.new(0, px(10))
    sidePad.PaddingLeft   = UDim.new(0, px(4))
    sidePad.PaddingRight  = UDim.new(0, px(4))

    local tabButtons = {}
    local currentTab = "melee"

    local function makeTabButton(def)
        local btn = Instance.new("TextButton")
        btn.Name = def.label .. "Tab"
        btn.AutoButtonColor = false
        btn.BackgroundColor3 = SIDEBAR_BG
        btn.BorderSizePixel = 0
        btn.Size = UDim2.new(1, -px(4), 0, px(64))
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

        if def.id == "melee" or def.id == "ranged" or def.id == "boosts" then
            local iconLbl = Instance.new("TextLabel", btn)
            iconLbl.Name = "Icon"
            iconLbl.BackgroundTransparency = 1
            iconLbl.Font = Enum.Font.GothamBold
            iconLbl.Text = def.icon
            iconLbl.TextColor3 = DIM_TEXT
            iconLbl.TextSize = math.max(18, math.floor(px(22)))
            iconLbl.Size = UDim2.new(1, 0, 0, px(26))
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
        textLbl.TextSize = math.max(12, math.floor(px(13)))
        textLbl.Size = UDim2.new(1, -px(6), 0, px(16))
        textLbl.Position = UDim2.new(0, px(3), 0, px(38))
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
    gridLayout.CellSize = UDim2.new(0, px(140), 0, px(178))
    gridLayout.CellPadding = UDim2.new(0, px(10), 0, px(10))
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local gridPad = Instance.new("UIPadding", gridScroll)
    gridPad.PaddingTop    = UDim.new(0, px(8))
    gridPad.PaddingLeft   = UDim.new(0, px(8))
    gridPad.PaddingRight  = UDim.new(0, px(8))
    gridPad.PaddingBottom = UDim.new(0, px(8))

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
    emptyShopBtn.TextColor3 = UITheme.GOLD_DIM
    emptyShopBtn.TextSize = math.max(13, math.floor(px(14)))
    emptyShopBtn.AutomaticSize = Enum.AutomaticSize.X
    emptyShopBtn.Size = UDim2.new(0, 0, 0, px(36))
    emptyShopBtn.AnchorPoint = Vector2.new(0.5, 0)
    emptyShopBtn.Position = UDim2.new(0.5, 0, 0.75, 0)
    Instance.new("UICorner", emptyShopBtn).CornerRadius = UDim.new(0, px(8))
    local esBtnPad = Instance.new("UIPadding", emptyShopBtn)
    esBtnPad.PaddingLeft = UDim.new(0, px(20)); esBtnPad.PaddingRight = UDim.new(0, px(20))
    local esBtnStroke = Instance.new("UIStroke", emptyShopBtn)
    esBtnStroke.Color = UITheme.GOLD_DIM; esBtnStroke.Thickness = 1.2; esBtnStroke.Transparency = 0.45

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

    -- Large image with rarity-coloured background
    local detailImageBg = Instance.new("Frame", detailContent)
    detailImageBg.Name = "ImageBg"
    detailImageBg.BackgroundColor3 = RARITY_BG_COLORS.Common
    detailImageBg.Size = UDim2.new(1, 0, 0, px(170))
    Instance.new("UICorner", detailImageBg).CornerRadius = UDim.new(0, px(10))
    local imgBgStroke = Instance.new("UIStroke", detailImageBg)
    imgBgStroke.Color = RARITY_COLORS.Common; imgBgStroke.Thickness = 1.5; imgBgStroke.Transparency = 0.3

    local detailImage = Instance.new("ImageLabel", detailImageBg)
    detailImage.Name = "Icon"
    detailImage.BackgroundTransparency = 1
    detailImage.Size = UDim2.new(0.75, 0, 0.75, 0)
    detailImage.AnchorPoint = Vector2.new(0.5, 0.5)
    detailImage.Position = UDim2.new(0.5, 0, 0.5, 0)
    detailImage.ScaleType = Enum.ScaleType.Fit

    -- Weapon name
    local detailName = Instance.new("TextLabel", detailContent)
    detailName.Name = "WeaponName"
    detailName.BackgroundTransparency = 1
    detailName.Font = Enum.Font.GothamBold
    detailName.TextColor3 = WHITE
    detailName.TextSize = px(26)
    detailName.TextXAlignment = Enum.TextXAlignment.Center
    detailName.Size = UDim2.new(1, 0, 0, px(34))
    detailName.Position = UDim2.new(0, 0, 0, px(178))
    detailName.TextTruncate = Enum.TextTruncate.AtEnd

    -- Rarity label
    local detailRarity = Instance.new("TextLabel", detailContent)
    detailRarity.Name = "Rarity"
    detailRarity.BackgroundTransparency = 1
    detailRarity.Font = Enum.Font.GothamBold
    detailRarity.TextColor3 = RARITY_COLORS.Common
    detailRarity.TextSize = px(19)
    detailRarity.TextXAlignment = Enum.TextXAlignment.Center
    detailRarity.Size = UDim2.new(1, 0, 0, px(26))
    detailRarity.Position = UDim2.new(0, 0, 0, px(214))

    -- Weapon type
    local detailType = Instance.new("TextLabel", detailContent)
    detailType.Name = "WeaponType"
    detailType.BackgroundTransparency = 1
    detailType.Font = Enum.Font.GothamMedium
    detailType.TextColor3 = DIM_TEXT
    detailType.TextSize = px(17)
    detailType.TextXAlignment = Enum.TextXAlignment.Center
    detailType.Size = UDim2.new(1, 0, 0, px(24))
    detailType.Position = UDim2.new(0, 0, 0, px(242))

    -- SIZE ROLL SYSTEM — size percent + tier in detail panel
    local detailSize = Instance.new("TextLabel", detailContent)
    detailSize.Name = "SizeInfo"
    detailSize.BackgroundTransparency = 1
    detailSize.Font = Enum.Font.GothamBold
    detailSize.TextColor3 = GOLD
    detailSize.TextSize = px(18)
    detailSize.TextXAlignment = Enum.TextXAlignment.Center
    detailSize.Size = UDim2.new(1, 0, 0, px(24))
    detailSize.Position = UDim2.new(0, 0, 0, px(268))

    -- Instance ID (developer-only)
    local detailInstanceId = Instance.new("TextLabel", detailContent)
    detailInstanceId.Name = "InstanceId"
    detailInstanceId.BackgroundTransparency = 1
    detailInstanceId.Font = Enum.Font.Code
    detailInstanceId.TextColor3 = DIM_TEXT
    detailInstanceId.TextSize = px(11)
    detailInstanceId.TextXAlignment = Enum.TextXAlignment.Center
    detailInstanceId.Size = UDim2.new(1, 0, 0, px(16))
    detailInstanceId.Position = UDim2.new(0, 0, 0, px(294))
    detailInstanceId.Visible = false

    -- Equip button (only place weapons can be equipped)
    local detailEquipBtn = Instance.new("TextButton", detailContent)
    detailEquipBtn.Name = "EquipBtn"
    detailEquipBtn.AutoButtonColor = false
    detailEquipBtn.BackgroundColor3 = BTN_BG
    detailEquipBtn.Font = Enum.Font.GothamBold
    detailEquipBtn.Text = "EQUIP"
    detailEquipBtn.TextColor3 = WHITE
    detailEquipBtn.TextSize = px(22)
    detailEquipBtn.Size = UDim2.new(0.88, 0, 0, px(52))
    detailEquipBtn.AnchorPoint = Vector2.new(0.5, 1)
    detailEquipBtn.Position = UDim2.new(0.5, 0, 1, 0)
    Instance.new("UICorner", detailEquipBtn).CornerRadius = UDim.new(0, px(10))
    local equipStroke = Instance.new("UIStroke", detailEquipBtn)
    equipStroke.Color = BTN_STROKE_C; equipStroke.Thickness = 1.4; equipStroke.Transparency = 0.25

    -- Action buttons row (Favorite + Discard) above equip button
    local actionRow = Instance.new("Frame", detailContent)
    actionRow.Name = "ActionRow"
    actionRow.BackgroundTransparency = 1
    actionRow.Size = UDim2.new(0.88, 0, 0, px(44))
    actionRow.AnchorPoint = Vector2.new(0.5, 1)
    actionRow.Position = UDim2.new(0.5, 0, 1, -px(58))

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

    -- Discard button (red)
    local DISCARD_RED  = Color3.fromRGB(220, 60, 60)
    local DISCARD_BG   = Color3.fromRGB(56, 28, 28)
    local DISCARD_DIM  = Color3.fromRGB(100, 60, 60)

    local discardBtn = Instance.new("TextButton", actionRow)
    discardBtn.Name = "DiscardBtn"
    discardBtn.AutoButtonColor = false
    discardBtn.BackgroundColor3 = DISCARD_BG
    discardBtn.Font = Enum.Font.GothamBold
    discardBtn.Text = "DISCARD"
    discardBtn.TextColor3 = DISCARD_RED
    discardBtn.TextSize = px(17)
    discardBtn.Size = UDim2.new(0.48, 0, 1, 0)
    discardBtn.AnchorPoint = Vector2.new(1, 0)
    discardBtn.Position = UDim2.new(1, 0, 0, 0)
    Instance.new("UICorner", discardBtn).CornerRadius = UDim.new(0, px(8))
    local discardStroke = Instance.new("UIStroke", discardBtn)
    discardStroke.Color = DISCARD_DIM; discardStroke.Thickness = 1.2; discardStroke.Transparency = 0.3

    -- Discard confirmation overlay
    local confirmOverlay = Instance.new("Frame", detailsPanel)
    confirmOverlay.Name = "ConfirmOverlay"
    confirmOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 26)
    confirmOverlay.BackgroundTransparency = 0.08
    confirmOverlay.Size = UDim2.new(1, 0, 1, 0)
    confirmOverlay.ZIndex = 50
    confirmOverlay.Visible = false
    Instance.new("UICorner", confirmOverlay).CornerRadius = UDim.new(0, px(12))

    local confirmBox = Instance.new("Frame", confirmOverlay)
    confirmBox.Name = "ConfirmBox"
    confirmBox.BackgroundColor3 = Color3.fromRGB(26, 30, 48)
    confirmBox.Size = UDim2.new(0.88, 0, 0, px(160))
    confirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
    confirmBox.Position = UDim2.new(0.5, 0, 0.5, 0)
    confirmBox.ZIndex = 51
    Instance.new("UICorner", confirmBox).CornerRadius = UDim.new(0, px(10))
    local cbStroke = Instance.new("UIStroke", confirmBox)
    cbStroke.Color = DISCARD_RED; cbStroke.Thickness = 1.5; cbStroke.Transparency = 0.3

    local confirmTitle = Instance.new("TextLabel", confirmBox)
    confirmTitle.BackgroundTransparency = 1
    confirmTitle.Font = Enum.Font.GothamBold
    confirmTitle.Text = "Discard Weapon?"
    confirmTitle.TextColor3 = DISCARD_RED
    confirmTitle.TextSize = px(18)
    confirmTitle.Size = UDim2.new(1, 0, 0, px(28))
    confirmTitle.Position = UDim2.new(0, 0, 0, px(16))
    confirmTitle.TextXAlignment = Enum.TextXAlignment.Center
    confirmTitle.ZIndex = 52

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
    confirmDesc.Position = UDim2.new(0.5, 0, 0, px(48))
    confirmDesc.TextXAlignment = Enum.TextXAlignment.Center
    confirmDesc.ZIndex = 52

    local confirmYes = Instance.new("TextButton", confirmBox)
    confirmYes.Name = "YesBtn"
    confirmYes.AutoButtonColor = false
    confirmYes.BackgroundColor3 = DISCARD_RED
    confirmYes.Font = Enum.Font.GothamBold
    confirmYes.Text = "YES, DISCARD"
    confirmYes.TextColor3 = WHITE
    confirmYes.TextSize = px(14)
    confirmYes.Size = UDim2.new(0.42, 0, 0, px(36))
    confirmYes.AnchorPoint = Vector2.new(0, 1)
    confirmYes.Position = UDim2.new(0.06, 0, 1, -px(14))
    confirmYes.ZIndex = 52
    Instance.new("UICorner", confirmYes).CornerRadius = UDim.new(0, px(8))

    local confirmNo = Instance.new("TextButton", confirmBox)
    confirmNo.Name = "NoBtn"
    confirmNo.AutoButtonColor = false
    confirmNo.BackgroundColor3 = BTN_BG
    confirmNo.Font = Enum.Font.GothamBold
    confirmNo.Text = "CANCEL"
    confirmNo.TextColor3 = WHITE
    confirmNo.TextSize = px(14)
    confirmNo.Size = UDim2.new(0.42, 0, 0, px(36))
    confirmNo.AnchorPoint = Vector2.new(1, 1)
    confirmNo.Position = UDim2.new(0.94, 0, 1, -px(14))
    confirmNo.ZIndex = 52
    Instance.new("UICorner", confirmNo).CornerRadius = UDim.new(0, px(8))

    -- ══════════════════════════════════════════════════════════════════════
    --  SELECTION & EQUIP STATE
    -- ══════════════════════════════════════════════════════════════════════
    local selectedItem  = nil
    local selectedCard  = nil
    local allCardRefs   = {}  -- id -> { card, stroke, itemData }

    ---------------------------------------------------------------------------
    -- updateEquipButton(itemData)
    ---------------------------------------------------------------------------
    local function updateActionButtons(itemData)
        -- Favorite & Discard visibility: hide for starter/non-instance weapons
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

        -- Don't allow discarding the currently equipped weapon
        if itemData and isItemEquipped(itemData) then
            discardBtn.BackgroundColor3 = DISABLED_BG
            discardBtn.TextColor3 = DIM_TEXT
            discardStroke.Color = DIM_TEXT
        else
            discardBtn.BackgroundColor3 = DISCARD_BG
            discardBtn.TextColor3 = DISCARD_RED
            discardStroke.Color = DISCARD_DIM
        end
    end

    local function updateEquipButton(itemData)
        if not itemData then
            detailEquipBtn.Text = "EQUIP"
            detailEquipBtn.BackgroundColor3 = DISABLED_BG
            detailEquipBtn.TextColor3 = DIM_TEXT
            equipStroke.Color = CARD_STROKE
            actionRow.Visible = false
            return
        end
        if isItemEquipped(itemData) then
            detailEquipBtn.Text = "\u{2714} EQUIPPED"
            detailEquipBtn.BackgroundColor3 = DISABLED_BG
            detailEquipBtn.TextColor3 = GREEN_GLOW
            equipStroke.Color = GREEN_GLOW
            equipStroke.Transparency = 0.45
        else
            detailEquipBtn.Text = "EQUIP"
            detailEquipBtn.BackgroundColor3 = BTN_BG
            detailEquipBtn.TextColor3 = WHITE
            equipStroke.Color = BTN_STROKE_C
            equipStroke.Transparency = 0.25
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
            -- No green background for equipped items; always use rarity bg
            ref.card.BackgroundColor3 = getRarityBgColor(ref.itemData.rarity)
            -- Update stroke: keep gold for the currently selected card,
            -- green for equipped, otherwise rarity color
            local isSelected = selectedItem and selectedItem.id == ref.itemData.id
            if not isSelected then
                ref.stroke.Color = equipped and GREEN_GLOW or getRarityColor(ref.itemData.rarity)
                ref.stroke.Thickness = 1.4
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
                oldRef.stroke.Color = eq and GREEN_GLOW or getRarityColor(selectedItem.rarity)
                oldRef.stroke.Thickness = 1.4
                oldRef.card.BackgroundColor3 = getRarityBgColor(selectedItem.rarity)
            end
        end

        selectedItem = itemData

        if not itemData then
            detailPlaceholder.Visible = true
            detailContent.Visible = false
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

        detailImageBg.BackgroundColor3 = rarBg
        imgBgStroke.Color = rarColor

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

        -- SIZE ROLL SYSTEM — show size info in detail panel
        local pct = itemData.sizePercent or 100
        local tier = itemData.sizeTier or "Normal"
        detailSize.Text = tier .. "  " .. tostring(math.floor(pct)) .. "%"
        if tier == "King" then
            detailSize.TextColor3 = Color3.fromRGB(255, 60, 60)
        elseif tier == "Giant" then
            detailSize.TextColor3 = GOLD
        elseif tier == "Large" then
            detailSize.TextColor3 = Color3.fromRGB(100, 200, 255)
        elseif tier == "Tiny" then
            detailSize.TextColor3 = Color3.fromRGB(160, 160, 170)
        else
            detailSize.TextColor3 = DIM_TEXT
        end

        if isDeveloper and itemData.instanceId then
            detailInstanceId.Text = itemData.instanceId
            detailInstanceId.Visible = true
        else
            detailInstanceId.Visible = false
        end

        updateEquipButton(itemData)
    end

    ---------------------------------------------------------------------------
    -- createWeaponCard(itemData)  –  compact square card for the grid
    ---------------------------------------------------------------------------
    local function createWeaponCard(itemData)
        local rarColor = getRarityColor(itemData.rarity)
        local rarBg    = getRarityBgColor(itemData.rarity)
        local equipped = isItemEquipped(itemData)

        local card = Instance.new("Frame")
        card.Name = "Card_" .. tostring(itemData.id)
        card.BackgroundColor3 = rarBg
        card.Size = UDim2.new(1, 0, 1, 0)
        card.ClipsDescendants = true
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(8))

        local stroke = Instance.new("UIStroke", card)
        stroke.Color = equipped and GREEN_GLOW or rarColor
        stroke.Thickness = 1.4; stroke.Transparency = 0.25

        -- Name at top
        local nameLabel = Instance.new("TextLabel", card)
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = WHITE
        nameLabel.TextSize = math.max(13, math.floor(px(15)))
        nameLabel.Size = UDim2.new(1, -px(10), 0, px(22))
        nameLabel.Position = UDim2.new(0, px(5), 0, px(4))
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Text = itemData.name

        -- Icon square (centred)
        local iconBg = Instance.new("Frame", card)
        iconBg.Name = "IconBg"
        iconBg.BackgroundColor3 = Color3.new(
            math.clamp(rarBg.R * 0.65, 0, 1),
            math.clamp(rarBg.G * 0.65, 0, 1),
            math.clamp(rarBg.B * 0.65, 0, 1)
        )
        iconBg.Size = UDim2.new(0, px(88), 0, px(88))
        iconBg.AnchorPoint = Vector2.new(0.5, 0)
        iconBg.Position = UDim2.new(0.5, 0, 0, px(28))
        Instance.new("UICorner", iconBg).CornerRadius = UDim.new(0, px(6))

        local thumb = Instance.new("ImageLabel", iconBg)
        thumb.Name = "Thumb"
        thumb.BackgroundTransparency = 1
        thumb.Size = UDim2.new(0.85, 0, 0.85, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.Image = ""
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(itemData.name))
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        -- SIZE ROLL SYSTEM — show tier name + size percent at bottom of card
        -- Rarity data is preserved on the backend; only the visible card label changes.
        local pct = itemData.sizePercent or 100
        local tier = itemData.sizeTier or "Normal"

        -- Tier-based colors for both labels
        local tierColor = DIM_TEXT
        if tier == "King" then
            tierColor = Color3.fromRGB(255, 60, 60)
        elseif tier == "Giant" then
            tierColor = GOLD
        elseif tier == "Large" then
            tierColor = Color3.fromRGB(100, 200, 255)
        elseif tier == "Tiny" then
            tierColor = Color3.fromRGB(160, 160, 170)
        end

        -- Tier name label (above the percent)
        local tierLabel = Instance.new("TextLabel", card)
        tierLabel.Name = "SizeTier"
        tierLabel.BackgroundTransparency = 1
        tierLabel.Font = Enum.Font.GothamBold
        tierLabel.TextColor3 = tierColor
        tierLabel.TextSize = math.max(11, math.floor(px(12)))
        tierLabel.Size = UDim2.new(1, 0, 0, px(16))
        tierLabel.AnchorPoint = Vector2.new(0, 1)
        tierLabel.Position = UDim2.new(0, 0, 1, -px(22))
        tierLabel.TextXAlignment = Enum.TextXAlignment.Center
        tierLabel.Text = tier

        -- Size percent label (bottom of card, below tier)
        local sizeLabel = Instance.new("TextLabel", card)
        sizeLabel.Name = "SizePercent"
        sizeLabel.BackgroundTransparency = 1
        sizeLabel.Font = Enum.Font.GothamBold
        sizeLabel.TextColor3 = tierColor
        sizeLabel.TextSize = math.max(12, math.floor(px(14)))
        sizeLabel.Size = UDim2.new(1, 0, 0, px(18))
        sizeLabel.AnchorPoint = Vector2.new(0, 1)
        sizeLabel.Position = UDim2.new(0, 0, 1, -px(5))
        sizeLabel.TextXAlignment = Enum.TextXAlignment.Center
        sizeLabel.Text = tostring(math.floor(pct)) .. "%"

        -- Equipped bar indicator (green bottom strip)
        local eqBar = Instance.new("Frame", card)
        eqBar.Name = "EquippedBar"
        eqBar.BackgroundColor3 = GREEN_GLOW
        eqBar.Size = UDim2.new(1, 0, 0, px(3))
        eqBar.AnchorPoint = Vector2.new(0, 1)
        eqBar.Position = UDim2.new(0, 0, 1, 0)
        eqBar.BorderSizePixel = 0; eqBar.ZIndex = 5
        eqBar.Visible = equipped

        -- Favorite star indicator (top-right corner)
        if itemData.favorited == true then
            local favStar = Instance.new("TextLabel", card)
            favStar.Name = "FavStar"
            favStar.BackgroundTransparency = 1
            favStar.Font = Enum.Font.GothamBold
            favStar.Text = "\u{2605}"  -- ★
            favStar.TextColor3 = Color3.fromRGB(255, 210, 50)
            favStar.TextSize = math.max(14, math.floor(px(16)))
            favStar.Size = UDim2.new(0, px(20), 0, px(20))
            favStar.AnchorPoint = Vector2.new(1, 0)
            favStar.Position = UDim2.new(1, -px(4), 0, px(3))
            favStar.ZIndex = 8
        end

        -- Store ref
        allCardRefs[itemData.id] = { card = card, stroke = stroke, itemData = itemData }

        -- Click to select
        local clickBtn = Instance.new("TextButton", card)
        clickBtn.Name = "ClickArea"
        clickBtn.BackgroundTransparency = 1
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.Text = ""; clickBtn.ZIndex = 10

        clickBtn.MouseButton1Click:Connect(function()
            setSelectedItem(itemData)
        end)

        -- Hover
        clickBtn.MouseEnter:Connect(function()
            if not selectedItem or selectedItem.id ~= itemData.id then
                TweenService:Create(card, TWEEN_QUICK, { BackgroundColor3 = Color3.new(
                    math.min(1, rarBg.R + 0.05),
                    math.min(1, rarBg.G + 0.05),
                    math.min(1, rarBg.B + 0.05)
                )}):Play()
            end
        end)
        clickBtn.MouseLeave:Connect(function()
            if not selectedItem or selectedItem.id ~= itemData.id then
                TweenService:Create(card, TWEEN_QUICK, {
                    BackgroundColor3 = rarBg
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

        -- Sort: favorited first, then rarity (rarest first), alphabetical, Starter last
        local rarityPriority = { Legendary = 1, Epic = 2, Rare = 3, Common = 4, Starter = 5 }
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
            local pa = rarityPriority[a.rarity] or 4
            local pb = rarityPriority[b.rarity] or 4
            if pa ~= pb then return pa < pb end
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
    -- Discard button handler  (opens confirmation prompt)
    ---------------------------------------------------------------------------
    local discardTarget = nil

    discardBtn.MouseButton1Click:Connect(function()
        if not selectedItem then return end
        if not selectedItem.isInstance then return end
        if selectedItem.source == "Starter" then return end
        if isItemEquipped(selectedItem) then return end

        discardTarget = selectedItem
        confirmDesc.Text = 'Discard "' .. (selectedItem.name or "?") .. '"?\nThis action cannot be undone.'
        confirmOverlay.Visible = true
    end)

    discardBtn.MouseEnter:Connect(function()
        if selectedItem and not isItemEquipped(selectedItem) and selectedItem.source ~= "Starter" then
            TweenService:Create(discardBtn, TWEEN_QUICK, {BackgroundColor3 = Color3.fromRGB(76, 32, 32)}):Play()
        end
    end)
    discardBtn.MouseLeave:Connect(function()
        TweenService:Create(discardBtn, TWEEN_QUICK, {BackgroundColor3 = DISCARD_BG}):Play()
    end)

    confirmNo.MouseButton1Click:Connect(function()
        confirmOverlay.Visible = false
        discardTarget = nil
    end)

    confirmYes.MouseButton1Click:Connect(function()
        confirmOverlay.Visible = false
        if not discardTarget then return end

        local instanceId = discardTarget.instanceId
        local cat = discardTarget.category
        if not instanceId then discardTarget = nil return end

        local discardRF = ReplicatedStorage:FindFirstChild("DiscardWeapon")
        if not discardRF or not discardRF:IsA("RemoteFunction") then discardTarget = nil return end

        local ok, success = pcall(function()
            return discardRF:InvokeServer(instanceId)
        end)

        if ok and success then
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
        end

        discardTarget = nil
    end)

    -- ══════════════════════════════════════════════════════════════════════
    --  BOOSTS PAGE
    -- ══════════════════════════════════════════════════════════════════════
    local boostsPage = Instance.new("ScrollingFrame")
    boostsPage.Name = "BoostsPage"
    boostsPage.BackgroundTransparency = 1
    boostsPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    boostsPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    boostsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
    boostsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    boostsPage.ScrollBarThickness = px(4)
    boostsPage.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
    boostsPage.BorderSizePixel = 0
    boostsPage.Visible = false
    boostsPage.Parent = root

    local boostsLayout = Instance.new("UIListLayout", boostsPage)
    boostsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    boostsLayout.Padding = UDim.new(0, px(12))

    local bPad = Instance.new("UIPadding", boostsPage)
    bPad.PaddingTop = UDim.new(0, px(6)); bPad.PaddingBottom = UDim.new(0, px(12))
    bPad.PaddingLeft = UDim.new(0, px(8)); bPad.PaddingRight = UDim.new(0, px(8))

    -- Boosts header
    local boostsHeader = Instance.new("Frame", boostsPage)
    boostsHeader.Name = "BoostsHeader"
    boostsHeader.BackgroundTransparency = 1
    boostsHeader.Size = UDim2.new(1, 0, 0, px(54)); boostsHeader.LayoutOrder = 1

    local boostsTitle = Instance.new("TextLabel", boostsHeader)
    boostsTitle.BackgroundTransparency = 1; boostsTitle.Font = Enum.Font.GothamBold
    boostsTitle.Text = "BOOSTS"; boostsTitle.TextColor3 = GOLD
    boostsTitle.TextSize = math.max(20, math.floor(px(24)))
    boostsTitle.TextXAlignment = Enum.TextXAlignment.Left
    boostsTitle.Size = UDim2.new(1, 0, 0, px(30))

    local boostsSub = Instance.new("TextLabel", boostsHeader)
    boostsSub.BackgroundTransparency = 1; boostsSub.Font = Enum.Font.GothamMedium
    boostsSub.Text = "Activate owned boosts when you need them. Activation consumes one stored boost."
    boostsSub.TextColor3 = DIM_TEXT
    boostsSub.TextSize = math.max(11, math.floor(px(12)))
    boostsSub.TextXAlignment = Enum.TextXAlignment.Left
    boostsSub.Size = UDim2.new(1, 0, 0, px(16)); boostsSub.Position = UDim2.new(0, 0, 0, px(30))

    local boostsAccent = Instance.new("Frame", boostsHeader)
    boostsAccent.BackgroundColor3 = GOLD; boostsAccent.BackgroundTransparency = 0.3
    boostsAccent.BorderSizePixel = 0
    boostsAccent.Size = UDim2.new(1, 0, 0, px(2)); boostsAccent.Position = UDim2.new(0, 0, 1, -px(2))

    local helperNote = Instance.new("TextLabel", boostsPage)
    helperNote.BackgroundTransparency = 1; helperNote.Font = Enum.Font.GothamMedium
    helperNote.Text = "Active boosts continue to drive coin and quest multipliers. Owning a boost does nothing until you activate it here."
    helperNote.TextColor3 = DIM_TEXT
    helperNote.TextSize = math.max(10, math.floor(px(11)))
    helperNote.TextXAlignment = Enum.TextXAlignment.Left
    helperNote.Size = UDim2.new(1, 0, 0, px(14)); helperNote.LayoutOrder = 2

    local boostDefs = {}
    if BoostConfig and BoostConfig.Boosts then
        for _, def in ipairs(BoostConfig.Boosts) do
            if not def.InstantUse then table.insert(boostDefs, def) end
        end
        table.sort(boostDefs, function(a, b) return (a.SortOrder or 0) < (b.SortOrder or 0) end)
    end

    local remotes = ensureBoostRemotes()
    local boostStates = {}
    local timeDelta = 0
    local boostCards = {}

    local function ingestStates(states)
        if type(states) ~= "table" then return end
        boostStates = states
        timeDelta = os.time() - (states._serverTime or os.time())
    end

    if remotes and remotes.getStates then
        pcall(function() ingestStates(remotes.getStates:InvokeServer()) end)
    end

    -- Boosts empty state
    local boostsEmptyState = Instance.new("Frame", boostsPage)
    boostsEmptyState.Name = "EmptyState"; boostsEmptyState.BackgroundTransparency = 1
    boostsEmptyState.Size = UDim2.new(1, 0, 0, px(160)); boostsEmptyState.LayoutOrder = 500
    boostsEmptyState.Visible = false

    local beCard = Instance.new("Frame", boostsEmptyState)
    beCard.BackgroundColor3 = CARD_BG; beCard.Size = UDim2.new(0.7, 0, 0, px(130))
    beCard.AnchorPoint = Vector2.new(0.5, 0.5); beCard.Position = UDim2.new(0.5, 0, 0.5, 0)
    Instance.new("UICorner", beCard).CornerRadius = UDim.new(0, px(14))
    local beStroke = Instance.new("UIStroke", beCard)
    beStroke.Color = CARD_STROKE; beStroke.Thickness = 1.2; beStroke.Transparency = 0.3

    local beLine1 = Instance.new("TextLabel", beCard)
    beLine1.BackgroundTransparency = 1; beLine1.Font = Enum.Font.GothamMedium
    beLine1.Text = "You don't own any boosts yet."
    beLine1.TextColor3 = DIM_TEXT; beLine1.TextSize = math.max(13, math.floor(px(14)))
    beLine1.TextWrapped = true; beLine1.Size = UDim2.new(0.85, 0, 0, px(40))
    beLine1.AnchorPoint = Vector2.new(0.5, 0); beLine1.Position = UDim2.new(0.5, 0, 0, px(28))
    beLine1.TextXAlignment = Enum.TextXAlignment.Center

    local beLine2 = Instance.new("TextLabel", beCard)
    beLine2.BackgroundTransparency = 1; beLine2.Font = Enum.Font.GothamMedium
    beLine2.Text = "Visit the shop to unlock more."
    beLine2.TextColor3 = UITheme.GOLD_DIM; beLine2.TextSize = math.max(11, math.floor(px(12)))
    beLine2.Size = UDim2.new(0.85, 0, 0, px(20)); beLine2.AnchorPoint = Vector2.new(0.5, 0)
    beLine2.Position = UDim2.new(0.5, 0, 0, px(74)); beLine2.TextXAlignment = Enum.TextXAlignment.Center

    local function refreshBoostCards()
        local visibleCount = 0
        for _, def in ipairs(boostDefs) do
            local refs = boostCards[def.Id]
            local state = boostStates[def.Id] or {}
            if refs then
                local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
                local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + timeDelta
                local active = expiresAt > os.time()

                if owned > 0 or active then
                    refs.card.Parent = boostsPage; visibleCount = visibleCount + 1
                else
                    refs.card.Parent = nil
                end

                refs.card.BackgroundColor3 = active and CARD_EQUIPPED or CARD_BG
                refs.cardStroke.Color = active and GREEN_GLOW or CARD_STROKE
                refs.cardStroke.Thickness = active and 1.8 or 1.2
                refs.cardStroke.Transparency = active and 0.3 or 0.35
                refs.owned.Text = string.format("Owned: %d", owned)

                if active then
                    local remaining = math.max(0, expiresAt - os.time())
                    refs.status.Text = string.format("Time Remaining: %02d:%02d", math.floor(remaining / 60), remaining % 60)
                    refs.status.TextColor3 = GREEN_GLOW
                    refs.button.Text = "ACTIVE"; refs.button.Active = false
                    refs.button.BackgroundColor3 = DISABLED_BG; refs.button.TextColor3 = GREEN_GLOW
                    refs.buttonStroke.Color = GREEN_GLOW
                elseif owned > 0 then
                    refs.status.Text = "Ready to activate"; refs.status.TextColor3 = DIM_TEXT
                    refs.button.Text = "ACTIVATE"; refs.button.Active = true
                    refs.button.BackgroundColor3 = BTN_BG; refs.button.TextColor3 = WHITE
                    refs.buttonStroke.Color = BTN_STROKE_C
                end
            end
        end
        boostsEmptyState.Visible = (visibleCount == 0)
    end

    if #boostDefs == 0 or not remotes then
        local unavailable = Instance.new("TextLabel", boostsPage)
        unavailable.BackgroundTransparency = 1; unavailable.Font = Enum.Font.GothamMedium
        unavailable.Text = "Boost inventory is currently unavailable."
        unavailable.TextColor3 = DIM_TEXT; unavailable.TextSize = math.max(14, math.floor(px(15)))
        unavailable.Size = UDim2.new(1, 0, 0, px(50)); unavailable.LayoutOrder = 10
    else
        for index, def in ipairs(boostDefs) do
            local card = Instance.new("Frame")
            card.Name = "Boost_" .. def.Id; card.BackgroundColor3 = CARD_BG
            card.Size = UDim2.new(1, 0, 0, px(122)); card.LayoutOrder = 10 + index
            card.Parent = boostsPage
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(12))
            local cStroke = Instance.new("UIStroke", card)
            cStroke.Color = CARD_STROKE; cStroke.Thickness = 1.2; cStroke.Transparency = 0.35

            local cPad = Instance.new("UIPadding", card)
            cPad.PaddingTop = UDim.new(0, px(12)); cPad.PaddingBottom = UDim.new(0, px(12))
            cPad.PaddingLeft = UDim.new(0, px(14)); cPad.PaddingRight = UDim.new(0, px(14))

            local iconColor = BOOST_ACCENT_COLORS[def.Id] or GOLD
            if type(def.IconColor) == "table" and #def.IconColor >= 3 then
                iconColor = Color3.fromRGB(def.IconColor[1], def.IconColor[2], def.IconColor[3])
            end

            local iconFrame = Instance.new("Frame", card)
            iconFrame.Name = "BoostIcon"
            iconFrame.Size = UDim2.new(0, px(60), 0, px(60))
            iconFrame.Position = UDim2.new(0, 0, 0.5, 0); iconFrame.AnchorPoint = Vector2.new(0, 0.5)
            iconFrame.BackgroundColor3 = iconColor; iconFrame.BorderSizePixel = 0
            Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, px(8))
            local iStroke = Instance.new("UIStroke", iconFrame)
            iStroke.Color = WHITE; iStroke.Thickness = 1.2; iStroke.Transparency = 0.75

            local iconImage = Instance.new("ImageLabel", iconFrame)
            iconImage.Name = "BoostIconImage"; iconImage.BackgroundTransparency = 1
            iconImage.AnchorPoint = Vector2.new(0.5, 0.5); iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconImage.Size = UDim2.new(0.72, 0, 0.72, 0); iconImage.ScaleType = Enum.ScaleType.Fit
            iconImage.Image = getBoostIconImage(def) or ""; iconImage.Visible = iconImage.Image ~= ""

            local iconGlyph = Instance.new("TextLabel", iconFrame)
            iconGlyph.Name = "BoostIconGlyph"; iconGlyph.BackgroundTransparency = 1
            iconGlyph.Size = UDim2.new(1, 0, 1, 0); iconGlyph.Font = Enum.Font.GothamBold
            iconGlyph.Text = def.IconGlyph or "?"; iconGlyph.TextSize = math.max(16, math.floor(px(33)))
            iconGlyph.TextColor3 = WHITE; iconGlyph.Visible = not iconImage.Visible

            local title = Instance.new("TextLabel", card)
            title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBold
            title.Text = def.DisplayName; title.TextColor3 = WHITE
            title.TextSize = math.max(16, math.floor(px(18)))
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Size = UDim2.new(0.58, -px(74), 0, px(24)); title.Position = UDim2.new(0, px(74), 0, 0)

            local desc = Instance.new("TextLabel", card)
            desc.BackgroundTransparency = 1; desc.Font = Enum.Font.GothamMedium
            desc.Text = def.Description; desc.TextColor3 = DIM_TEXT
            desc.TextSize = math.max(11, math.floor(px(12))); desc.TextWrapped = true
            desc.TextXAlignment = Enum.TextXAlignment.Left; desc.TextYAlignment = Enum.TextYAlignment.Top
            desc.Size = UDim2.new(0.58, -px(74), 0, px(42)); desc.Position = UDim2.new(0, px(74), 0, px(28))

            local owned = Instance.new("TextLabel", card)
            owned.BackgroundTransparency = 1; owned.Font = Enum.Font.GothamBold
            owned.Text = "Owned: 0"; owned.TextColor3 = WHITE
            owned.TextSize = math.max(11, math.floor(px(12)))
            owned.TextXAlignment = Enum.TextXAlignment.Right
            owned.Size = UDim2.new(0.34, 0, 0, px(18)); owned.Position = UDim2.new(0.66, 0, 0, px(12))

            local status = Instance.new("TextLabel", card)
            status.BackgroundTransparency = 1; status.Font = Enum.Font.GothamMedium
            status.Text = "Not owned"; status.TextColor3 = DIM_TEXT
            status.TextSize = math.max(10, math.floor(px(11)))
            status.TextXAlignment = Enum.TextXAlignment.Right
            status.Size = UDim2.new(0.34, 0, 0, px(16)); status.Position = UDim2.new(0.66, 0, 0, px(34))

            local activateBtn = Instance.new("TextButton", card)
            activateBtn.Name = "ActivateBtn"; activateBtn.AutoButtonColor = false
            activateBtn.BackgroundColor3 = BTN_BG; activateBtn.Font = Enum.Font.GothamBold
            activateBtn.Text = "ACTIVATE"; activateBtn.TextColor3 = WHITE
            activateBtn.TextSize = math.max(12, math.floor(px(13)))
            activateBtn.Size = UDim2.new(0, px(132), 0, px(36))
            activateBtn.AnchorPoint = Vector2.new(1, 1); activateBtn.Position = UDim2.new(1, 0, 1, 0)
            Instance.new("UICorner", activateBtn).CornerRadius = UDim.new(0, px(10))
            local bStroke = Instance.new("UIStroke", activateBtn)
            bStroke.Color = BTN_STROKE_C; bStroke.Thickness = 1.3; bStroke.Transparency = 0.25

            activateBtn.MouseEnter:Connect(function()
                if activateBtn.Active then TweenService:Create(activateBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play() end
            end)
            activateBtn.MouseLeave:Connect(function()
                if activateBtn.Active then TweenService:Create(activateBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play() end
            end)

            activateBtn.MouseButton1Click:Connect(function()
                local ok, success, message, states = pcall(function()
                    return remotes.activate:InvokeServer(def.Id)
                end)
                if ok and success then
                    ingestStates(states); refreshBoostCards()
                    showToast(boostsPage, "Boost activated.", GREEN_GLOW, 2.2)
                else
                    if ok and type(states) == "table" then ingestStates(states) end
                    refreshBoostCards()
                    if ok and message == "Already active" then
                        local r = boostCards[def.Id]
                        if r then r.status.Text = "Already Active"; r.status.TextColor3 = GOLD
                            task.delay(1.2, function() if r.card and r.card.Parent then refreshBoostCards() end end)
                        end
                    end
                    showToast(boostsPage, tostring((ok and message) or "Activation failed"), RED_TEXT, 2.2)
                end
            end)

            boostCards[def.Id] = {
                card = card, cardStroke = cStroke,
                owned = owned, status = status,
                button = activateBtn, buttonStroke = bStroke,
            }
        end

        refreshBoostCards()

        trackConn(remotes.stateUpdated.OnClientEvent:Connect(function(states)
            ingestStates(states); refreshBoostCards()
        end))

        local lastTick = 0
        trackConn(RunService.Heartbeat:Connect(function()
            local now = os.time(); if now == lastTick then return end
            lastTick = now; refreshBoostCards()
        end))
    end

    -- Boosts shop nav
    do
        local shopWrap = Instance.new("Frame", boostsPage)
        shopWrap.BackgroundTransparency = 1
        shopWrap.Size = UDim2.new(1, 0, 0, px(50)); shopWrap.LayoutOrder = 9999

        local shopBtn = Instance.new("TextButton", shopWrap)
        shopBtn.AutoButtonColor = false; shopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        shopBtn.Font = Enum.Font.GothamBold; shopBtn.Text = "\u{1F6D2}  Browse Shop"
        shopBtn.TextColor3 = UITheme.GOLD_DIM; shopBtn.TextSize = math.max(13, math.floor(px(14)))
        shopBtn.AutomaticSize = Enum.AutomaticSize.X
        shopBtn.Size = UDim2.new(0, 0, 0, px(38)); shopBtn.AnchorPoint = Vector2.new(0.5, 0)
        shopBtn.Position = UDim2.new(0.5, 0, 0, px(12))
        Instance.new("UICorner", shopBtn).CornerRadius = UDim.new(0, px(8))
        local sp = Instance.new("UIPadding", shopBtn)
        sp.PaddingLeft = UDim.new(0, px(20)); sp.PaddingRight = UDim.new(0, px(20))
        local ss = Instance.new("UIStroke", shopBtn)
        ss.Color = UITheme.GOLD_DIM; ss.Thickness = 1.2; ss.Transparency = 0.45

        shopBtn.MouseEnter:Connect(function() TweenService:Create(shopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
        shopBtn.MouseLeave:Connect(function() TweenService:Create(shopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
        shopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("boosts") end
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  SKINS PAGE  (placeholder)
    -- ══════════════════════════════════════════════════════════════════════
    local skinsPage = Instance.new("Frame")
    skinsPage.Name = "SkinsPage"; skinsPage.BackgroundTransparency = 1
    skinsPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    skinsPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    skinsPage.Visible = false; skinsPage.Parent = root

    local skinsCard = Instance.new("Frame", skinsPage)
    skinsCard.BackgroundColor3 = CARD_BG
    skinsCard.Size = UDim2.new(0.6, 0, 0, px(190)); skinsCard.AnchorPoint = Vector2.new(0.5, 0.5)
    skinsCard.Position = UDim2.new(0.5, 0, 0.5, 0)
    Instance.new("UICorner", skinsCard).CornerRadius = UDim.new(0, px(16))
    local scStroke = Instance.new("UIStroke", skinsCard)
    scStroke.Color = CARD_STROKE; scStroke.Thickness = 1.4; scStroke.Transparency = 0.25

    do
        local iconPlate = Instance.new("Frame", skinsCard)
        iconPlate.BackgroundColor3 = ICON_BG; iconPlate.BackgroundTransparency = 0.15
        iconPlate.BorderSizePixel = 0
        iconPlate.Size = UDim2.new(0, px(74), 0, px(74))
        iconPlate.AnchorPoint = Vector2.new(0.5, 0); iconPlate.Position = UDim2.new(0.5, 0, 0, px(12))
        Instance.new("UICorner", iconPlate).CornerRadius = UDim.new(0, px(14))

        local sourceBtn    = tabButtons["skins"]
        local sourceCustom = sourceBtn and sourceBtn:FindFirstChild("IconCustom")
        if sourceCustom then
            local iconClone = sourceCustom:Clone()
            iconClone.AnchorPoint = Vector2.new(0.5, 0.5)
            iconClone.Position = UDim2.new(0.5, 0, 0.5, 0)
            iconClone.Parent = iconPlate
            Instance.new("UIScale", iconClone).Scale = 2.3
            setTabIconTint(iconClone, getCustomTabIconColor("skins", true))
        end
    end

    local skinsTitleLbl = Instance.new("TextLabel", skinsCard)
    skinsTitleLbl.BackgroundTransparency = 1; skinsTitleLbl.Font = Enum.Font.GothamBold
    skinsTitleLbl.Text = "SKINS"; skinsTitleLbl.TextColor3 = GOLD
    skinsTitleLbl.TextSize = math.max(16, math.floor(px(18)))
    skinsTitleLbl.Size = UDim2.new(1, 0, 0, px(26)); skinsTitleLbl.Position = UDim2.new(0, 0, 0.46, 0)
    skinsTitleLbl.TextXAlignment = Enum.TextXAlignment.Center

    local skinsSubLbl = Instance.new("TextLabel", skinsCard)
    skinsSubLbl.BackgroundTransparency = 1; skinsSubLbl.Font = Enum.Font.GothamMedium
    skinsSubLbl.Text = "You don't own any items in this category yet.\nVisit the shop to unlock more."
    skinsSubLbl.TextColor3 = DIM_TEXT; skinsSubLbl.TextSize = math.max(12, math.floor(px(13)))
    skinsSubLbl.Size = UDim2.new(1, -px(20), 0, px(36))
    skinsSubLbl.Position = UDim2.new(0, px(10), 0.58, 0)
    skinsSubLbl.TextWrapped = true; skinsSubLbl.TextXAlignment = Enum.TextXAlignment.Center

    do
        local shopWrap = Instance.new("Frame", skinsPage)
        shopWrap.BackgroundTransparency = 1
        shopWrap.Size = UDim2.new(1, 0, 0, px(50))
        shopWrap.AnchorPoint = Vector2.new(0.5, 0)
        shopWrap.Position = UDim2.new(0.5, 0, 0.5, px(100))

        local shopBtn = Instance.new("TextButton", shopWrap)
        shopBtn.AutoButtonColor = false; shopBtn.BackgroundColor3 = UITheme.NAVY_LIGHT
        shopBtn.Font = Enum.Font.GothamBold; shopBtn.Text = "\u{1F6D2}  Browse Shop"
        shopBtn.TextColor3 = UITheme.GOLD_DIM; shopBtn.TextSize = math.max(13, math.floor(px(14)))
        shopBtn.AutomaticSize = Enum.AutomaticSize.X
        shopBtn.Size = UDim2.new(0, 0, 0, px(38)); shopBtn.AnchorPoint = Vector2.new(0.5, 0)
        shopBtn.Position = UDim2.new(0.5, 0, 0, px(12))
        Instance.new("UICorner", shopBtn).CornerRadius = UDim.new(0, px(8))
        local sp2 = Instance.new("UIPadding", shopBtn)
        sp2.PaddingLeft = UDim.new(0, px(20)); sp2.PaddingRight = UDim.new(0, px(20))
        local ss2 = Instance.new("UIStroke", shopBtn)
        ss2.Color = UITheme.GOLD_DIM; ss2.Thickness = 1.2; ss2.Transparency = 0.45

        shopBtn.MouseEnter:Connect(function() TweenService:Create(shopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_MID}):Play() end)
        shopBtn.MouseLeave:Connect(function() TweenService:Create(shopBtn, TWEEN_QUICK, {BackgroundColor3 = UITheme.NAVY_LIGHT}):Play() end)
        shopBtn.MouseButton1Click:Connect(function()
            local mc = _G.SideUI and _G.SideUI.MenuController
            if mc then mc.OpenMenu("Shop")
                if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("skins") end
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════════════
    --  EFFECTS PAGE  (dash trail equip)
    -- ══════════════════════════════════════════════════════════════════════
    local effectsPage = Instance.new("ScrollingFrame")
    effectsPage.Name = "EffectsPage"; effectsPage.BackgroundTransparency = 1
    effectsPage.Size = UDim2.new(1, CONTENT_W_OFF, 1, 0)
    effectsPage.Position = UDim2.new(0, CONTENT_X, 0, 0)
    effectsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
    effectsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    effectsPage.ScrollBarThickness = px(4)
    effectsPage.ScrollBarImageColor3 = Color3.fromRGB(180, 150, 50)
    effectsPage.BorderSizePixel = 0
    effectsPage.Visible = false; effectsPage.Parent = root

    do
        local EffectDefs = nil
        pcall(function()
            local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
            local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
            if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
        end)

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
            local epLayout = Instance.new("UIListLayout", effectsPage)
            epLayout.SortOrder = Enum.SortOrder.LayoutOrder; epLayout.Padding = UDim.new(0, px(16))

            local trailSection = Instance.new("Frame", effectsPage)
            trailSection.Name = "DashTrails_Section"; trailSection.BackgroundTransparency = 1
            trailSection.Size = UDim2.new(1, 0, 0, 0); trailSection.AutomaticSize = Enum.AutomaticSize.Y
            trailSection.LayoutOrder = 1

            local tsLay = Instance.new("UIListLayout", trailSection)
            tsLay.SortOrder = Enum.SortOrder.LayoutOrder; tsLay.Padding = UDim.new(0, px(10))
            local tsP = Instance.new("UIPadding", trailSection)
            tsP.PaddingTop = UDim.new(0, px(4)); tsP.PaddingBottom = UDim.new(0, px(10))
            tsP.PaddingLeft = UDim.new(0, px(8)); tsP.PaddingRight = UDim.new(0, px(8))

            local hWrap = Instance.new("Frame", trailSection)
            hWrap.Name = "HeaderWrap"; hWrap.BackgroundTransparency = 1
            hWrap.Size = UDim2.new(1, 0, 0, px(40)); hWrap.LayoutOrder = 1

            local hdr = Instance.new("TextLabel", hWrap)
            hdr.BackgroundTransparency = 1; hdr.Font = Enum.Font.GothamBold
            hdr.Text = "Dash Trails"; hdr.TextColor3 = GOLD
            hdr.TextSize = math.max(18, math.floor(px(20)))
            hdr.TextXAlignment = Enum.TextXAlignment.Left; hdr.Size = UDim2.new(1, 0, 0, px(28))

            local hBar = Instance.new("Frame", hWrap)
            hBar.BackgroundColor3 = GOLD; hBar.BackgroundTransparency = 0.3
            hBar.Size = UDim2.new(1, 0, 0, px(2)); hBar.Position = UDim2.new(0, 0, 1, -px(2))
            hBar.BorderSizePixel = 0

            local trailGrid = Instance.new("Frame", trailSection)
            trailGrid.Name = "DashTrails_Grid"; trailGrid.BackgroundTransparency = 1
            trailGrid.Size = UDim2.new(1, 0, 0, 0); trailGrid.AutomaticSize = Enum.AutomaticSize.Y
            trailGrid.LayoutOrder = 2

            local tgLay = Instance.new("UIGridLayout", trailGrid)
            tgLay.CellSize = UDim2.new(0.30, 0, 0, px(160))
            tgLay.CellPadding = UDim2.new(0.025, 0, 0, px(12))
            tgLay.FillDirection = Enum.FillDirection.Horizontal; tgLay.FillDirectionMaxCells = 3
            tgLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
            tgLay.SortOrder = Enum.SortOrder.LayoutOrder

            local ownedSet = {}
            local equippedTrailId = nil
            local effectEquipBtns = {}
            local effectsEmptyState = nil

            local function refreshAllEffectBtns()
                local visibleCount = 0
                for eid, info in pairs(effectEquipBtns) do
                    local isOwned = ownedSet[eid] or info.isFree
                    if isOwned then info.card.Parent = trailGrid; visibleCount = visibleCount + 1
                    else info.card.Parent = nil end

                    if equippedTrailId == eid then
                        info.btn.Text = "\u{2714} EQUIPPED"
                        info.btn.BackgroundColor3 = DISABLED_BG; info.btn.TextColor3 = GREEN_GLOW
                        info.stroke.Color = GREEN_GLOW; info.stroke.Transparency = 0.45
                        if info.card then info.card.BackgroundColor3 = CARD_EQUIPPED end
                        if info.cardStroke then info.cardStroke.Color = GREEN_GLOW; info.cardStroke.Thickness = 1.8; info.cardStroke.Transparency = 0.3 end
                    elseif isOwned then
                        info.btn.Text = "EQUIP"
                        info.btn.BackgroundColor3 = BTN_BG; info.btn.TextColor3 = WHITE
                        info.stroke.Color = BTN_STROKE_C; info.stroke.Transparency = 0.25
                        if info.card then info.card.BackgroundColor3 = CARD_BG end
                        if info.cardStroke then info.cardStroke.Color = CARD_STROKE; info.cardStroke.Thickness = 1.2; info.cardStroke.Transparency = 0.35 end
                    end
                end
                if effectsEmptyState then effectsEmptyState.Visible = (visibleCount == 0) end
            end

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
                refreshAllEffectBtns()
                if eRemotes.changed and eRemotes.changed:IsA("RemoteEvent") then
                    eRemotes.changed.OnClientEvent:Connect(function(newEquipped)
                        if type(newEquipped) == "table" then equippedTrailId = newEquipped.DashTrail; refreshAllEffectBtns() end
                    end)
                end
            end)

            for _, def in ipairs(allTrailDefs) do
                local effectId    = def.Id
                local displayName = def.DisplayName or effectId
                local effectColor = def.Color or Color3.fromRGB(180, 220, 255)
                local description = def.Description or ""
                local isFree      = def.IsFree or false
                local isRainbow   = def.IsRainbow == true
                local isEpic      = (def.Rarity == "Epic")

                local card = Instance.new("Frame")
                card.Name = "EffectCard_" .. effectId; card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 1, 0); card.AutomaticSize = Enum.AutomaticSize.Y
                card.Parent = trailGrid
                Instance.new("UICorner", card).CornerRadius = UDim.new(0, px(12))
                local eCS = Instance.new("UIStroke", card)
                eCS.Color = isEpic and Color3.fromRGB(180, 120, 255) or CARD_STROKE
                eCS.Thickness = isEpic and 1.6 or 1.2; eCS.Transparency = isEpic and 0.2 or 0.35
                local eP = Instance.new("UIPadding", card)
                eP.PaddingTop = UDim.new(0, px(8)); eP.PaddingBottom = UDim.new(0, px(8))
                eP.PaddingLeft = UDim.new(0, px(8)); eP.PaddingRight = UDim.new(0, px(8))

                local leftBox = Instance.new("Frame", card)
                leftBox.Name = "LeftBox"; leftBox.Size = UDim2.new(0.45, 0, 1, 0)
                leftBox.BackgroundColor3 = ICON_BG; leftBox.ZIndex = 251
                Instance.new("UICorner", leftBox).CornerRadius = UDim.new(0, px(10))
                local lS = Instance.new("UIStroke", leftBox); lS.Color = CARD_STROKE; lS.Thickness = 1; lS.Transparency = 0.5

                local swatch = Instance.new("Frame", leftBox)
                swatch.Name = "ColorSwatch"; swatch.Size = UDim2.new(0.6, 0, 0.15, 0)
                swatch.AnchorPoint = Vector2.new(0.5, 0.5); swatch.Position = UDim2.new(0.5, 0, 0.4, 0)
                swatch.BackgroundColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                swatch.BorderSizePixel = 0; swatch.ZIndex = 252
                Instance.new("UICorner", swatch).CornerRadius = UDim.new(0.5, 0)
                if isRainbow and def.TrailColorSequence then Instance.new("UIGradient", swatch).Color = def.TrailColorSequence end
                local swS = Instance.new("UIStroke", swatch)
                swS.Color = isRainbow and Color3.fromRGB(200, 160, 255) or effectColor; swS.Thickness = px(2); swS.Transparency = 0.3

                local tG = Instance.new("TextLabel", leftBox)
                tG.Text = "\u{2550}\u{2550}\u{2550}"; tG.Font = Enum.Font.GothamBold
                tG.TextColor3 = isRainbow and Color3.fromRGB(255, 255, 255) or effectColor
                tG.TextScaled = true; tG.BackgroundTransparency = 1
                tG.Size = UDim2.new(0.8, 0, 0.2, 0); tG.AnchorPoint = Vector2.new(0.5, 0)
                tG.Position = UDim2.new(0.5, 0, 0.6, 0); tG.ZIndex = 252
                if isRainbow and def.TrailColorSequence then Instance.new("UIGradient", tG).Color = def.TrailColorSequence end

                local rightBox = Instance.new("Frame", card)
                rightBox.Size = UDim2.new(0.52, 0, 1, 0); rightBox.Position = UDim2.new(0.48, 0, 0, 0)
                rightBox.BackgroundTransparency = 1; rightBox.ZIndex = 251

                local nL = Instance.new("TextLabel", rightBox)
                nL.Size = UDim2.new(0.95, 0, 0.28, 0); nL.Position = UDim2.new(0.04, 0, 0.08, 0)
                nL.BackgroundTransparency = 1; nL.Font = Enum.Font.GothamBold
                nL.Text = displayName; nL.TextColor3 = isEpic and Color3.fromRGB(210, 170, 255) or WHITE
                nL.TextSize = math.max(13, math.floor(px(15)))
                nL.TextXAlignment = Enum.TextXAlignment.Left; nL.TextTruncate = Enum.TextTruncate.AtEnd; nL.ZIndex = 252

                local dL = Instance.new("TextLabel", rightBox)
                dL.Size = UDim2.new(0.95, 0, 0.22, 0); dL.Position = UDim2.new(0.04, 0, 0.36, 0)
                dL.BackgroundTransparency = 1; dL.Font = Enum.Font.GothamMedium
                dL.Text = isFree and "Free (default)" or description; dL.TextColor3 = DIM_TEXT
                dL.TextSize = math.max(10, math.floor(px(11)))
                dL.TextXAlignment = Enum.TextXAlignment.Left; dL.TextWrapped = true; dL.ZIndex = 252

                local eBtn = Instance.new("TextButton", rightBox)
                eBtn.Name = "EquipBtn"; eBtn.Size = UDim2.new(0.85, 0, 0.26, 0)
                eBtn.AnchorPoint = Vector2.new(0.5, 1); eBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
                eBtn.BackgroundColor3 = BTN_BG; eBtn.BorderSizePixel = 0; eBtn.AutoButtonColor = false
                eBtn.Font = Enum.Font.GothamBold; eBtn.Text = "EQUIP"; eBtn.TextColor3 = WHITE
                eBtn.TextSize = math.max(13, math.floor(px(14))); eBtn.ZIndex = 253
                Instance.new("UICorner", eBtn).CornerRadius = UDim.new(0, px(8))
                local eSt = Instance.new("UIStroke", eBtn); eSt.Color = BTN_STROKE_C; eSt.Thickness = 1.2; eSt.Transparency = 0.25

                effectEquipBtns[effectId] = { btn = eBtn, stroke = eSt, card = card, cardStroke = eCS, isFree = isFree }

                if not game:GetService("UserInputService").TouchEnabled then
                    eBtn.MouseEnter:Connect(function()
                        if (ownedSet[effectId] or isFree) and equippedTrailId ~= effectId then
                            TweenService:Create(eBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                        end
                    end)
                    eBtn.MouseLeave:Connect(function()
                        if (ownedSet[effectId] or isFree) and equippedTrailId ~= effectId then
                            TweenService:Create(eBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                        end
                    end)
                end

                eBtn.MouseButton1Click:Connect(function()
                    if not ownedSet[effectId] and not isFree then return end
                    if equippedTrailId == effectId then return end
                    local eRemotes = ensureEffectRemotes()
                    if eRemotes and eRemotes.equip and eRemotes.equip:IsA("RemoteEvent") then
                        pcall(function() eRemotes.equip:FireServer(effectId, "DashTrail") end)
                    end
                    equippedTrailId = effectId; refreshAllEffectBtns()
                end)
            end

            effectsEmptyState = Instance.new("Frame", effectsPage)
            effectsEmptyState.BackgroundTransparency = 1
            effectsEmptyState.Size = UDim2.new(1, 0, 0, px(160)); effectsEmptyState.LayoutOrder = 500
            effectsEmptyState.Visible = false

            local eeCard = Instance.new("Frame", effectsEmptyState)
            eeCard.BackgroundColor3 = CARD_BG; eeCard.Size = UDim2.new(0.7, 0, 0, px(130))
            eeCard.AnchorPoint = Vector2.new(0.5, 0.5); eeCard.Position = UDim2.new(0.5, 0, 0.5, 0)
            Instance.new("UICorner", eeCard).CornerRadius = UDim.new(0, px(14))
            Instance.new("UIStroke", eeCard).Color = CARD_STROKE

            local eeL = Instance.new("TextLabel", eeCard)
            eeL.BackgroundTransparency = 1; eeL.Font = Enum.Font.GothamMedium
            eeL.Text = "You don't own any effects yet.\nVisit the shop to unlock more."
            eeL.TextColor3 = DIM_TEXT; eeL.TextSize = math.max(13, math.floor(px(14)))
            eeL.TextWrapped = true; eeL.Size = UDim2.new(0.85, 0, 0, px(60))
            eeL.AnchorPoint = Vector2.new(0.5, 0.5); eeL.Position = UDim2.new(0.5, 0, 0.5, 0)
            eeL.TextXAlignment = Enum.TextXAlignment.Center

            -- Effects shop nav
            local eShopW = Instance.new("Frame", effectsPage)
            eShopW.BackgroundTransparency = 1; eShopW.Size = UDim2.new(1, 0, 0, px(50)); eShopW.LayoutOrder = 9999
            local eShopB = Instance.new("TextButton", eShopW)
            eShopB.AutoButtonColor = false; eShopB.BackgroundColor3 = UITheme.NAVY_LIGHT
            eShopB.Font = Enum.Font.GothamBold; eShopB.Text = "\u{1F6D2}  Browse Shop"
            eShopB.TextColor3 = UITheme.GOLD_DIM; eShopB.TextSize = math.max(13, math.floor(px(14)))
            eShopB.AutomaticSize = Enum.AutomaticSize.X
            eShopB.Size = UDim2.new(0, 0, 0, px(38)); eShopB.AnchorPoint = Vector2.new(0.5, 0)
            eShopB.Position = UDim2.new(0.5, 0, 0, px(12))
            Instance.new("UICorner", eShopB).CornerRadius = UDim.new(0, px(8))
            local esp = Instance.new("UIPadding", eShopB); esp.PaddingLeft = UDim.new(0, px(20)); esp.PaddingRight = UDim.new(0, px(20))
            local ess = Instance.new("UIStroke", eShopB); ess.Color = UITheme.GOLD_DIM; ess.Thickness = 1.2; ess.Transparency = 0.45
            eShopB.MouseButton1Click:Connect(function()
                local mc = _G.SideUI and _G.SideUI.MenuController
                if mc then mc.OpenMenu("Shop")
                    if ShopUIModule and ShopUIModule.setActiveTab then ShopUIModule.setActiveTab("effects") end
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
        skinsPage.Visible   = (tabId == "skins")
        effectsPage.Visible = (tabId == "effects")

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

    -- Adapt root height to parent size
    task.defer(function()
        local pH = parent.AbsoluteSize.Y
        if pH > 50 then
            rootHeight = math.max(px(380), pH - px(8))
            root.Size = UDim2.new(1, 0, 0, rootHeight)
        end
    end)
    trackConn(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local pH = parent.AbsoluteSize.Y
        if pH > 50 then
            rootHeight = math.max(px(380), pH - px(8))
            root.Size = UDim2.new(1, 0, 0, rootHeight)
        end
    end))

    -- Cleanup on removal
    root.AncestryChanged:Connect(function(_, newParent)
        if not newParent then cleanup() end
    end)

    return root
end

return InventoryUI
