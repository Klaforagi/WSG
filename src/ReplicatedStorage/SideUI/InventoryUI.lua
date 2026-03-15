--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Sectioned inventory (Melee · Ranged · Special)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- Palette (matches BoostsUI / QuestsUI / ShopUI deep-blue / gold theme)
local CARD_BG       = Color3.fromRGB(26, 30, 48)
local CARD_EQUIPPED = Color3.fromRGB(22, 38, 34)
local CARD_STROKE   = Color3.fromRGB(55, 62, 95)
local ICON_BG       = Color3.fromRGB(16, 18, 30)
local GOLD          = Color3.fromRGB(255, 215, 60)
local WHITE         = Color3.fromRGB(245, 245, 252)
local DIM_TEXT      = Color3.fromRGB(145, 150, 175)
local BTN_BG        = Color3.fromRGB(48, 55, 82)
local BTN_STROKE_C  = Color3.fromRGB(90, 100, 140)
local GREEN_GLOW    = Color3.fromRGB(50, 230, 110)
local DISABLED_BG   = Color3.fromRGB(35, 38, 52)

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local InventoryUI = {}

function InventoryUI.Create(parent, coinApi, inventoryApi)
    if not parent then return nil end
    for _, c in ipairs(parent:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") then
            pcall(function() c:Destroy() end)
        end
    end

    local root = Instance.new("Frame")
    root.Name = "InventoryUI"
    root.BackgroundTransparency = 1
    root.Size = UDim2.new(1, 0, 0, 0)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.Parent = parent

    local rootLayout = Instance.new("UIListLayout")
    rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rootLayout.Padding = UDim.new(0, px(16))
    rootLayout.Parent = root

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(6))
    rootPad.PaddingBottom = UDim.new(0, px(16))
    rootPad.PaddingLeft = UDim.new(0, px(8))
    rootPad.PaddingRight = UDim.new(0, px(8))
    rootPad.Parent = root

    local items = inventoryApi and inventoryApi:GetItems() or {}
    -- Normalize legacy item IDs to current names so UI shows correct labels
    if items and type(items) == "table" then
        local normalized = {}
        for _, id in ipairs(items) do
            if type(id) == "string" and tostring(id):lower() == "stick" then
                table.insert(normalized, "Wooden Sword")
            else
                table.insert(normalized, id)
            end
        end
        items = normalized
    end

    -- Assets & presets for classification
    local AssetCodes = nil
    pcall(function()
        local ac = game:GetService("ReplicatedStorage"):FindFirstChild("AssetCodes")
        if ac and ac:IsA("ModuleScript") then AssetCodes = require(ac) end
    end)

    local meleePresets = nil
    pcall(function()
        local mm = game:GetService("ReplicatedStorage"):FindFirstChild("ToolMeleeSettings")
        if mm and mm:IsA("ModuleScript") then
            local ok, mod = pcall(function() return require(mm) end)
            if ok and type(mod) == "table" then meleePresets = mod.presets end
        end
    end)
    local rangedPresets = nil
    pcall(function()
        local rm = game:GetService("ReplicatedStorage"):FindFirstChild("Toolgunsettings")
        if rm and rm:IsA("ModuleScript") then
            local ok, mod = pcall(function() return require(rm) end)
            if ok and type(mod) == "table" and mod.presets then rangedPresets = mod.presets end
        end
    end)

    local function classifyItem(name)
        if not name then return "Ranged" end
        local key = tostring(name):lower()
        -- legacy alias mapping: treat certain historical IDs as melee
        local aliasMap = {
            ["stick"] = "Melee",
        }
        if aliasMap[key] then return aliasMap[key] end
        if meleePresets and meleePresets[key] then return "Melee" end
        if rangedPresets and rangedPresets[key] then return "Ranged" end
        return "Ranged"
    end

    -- Helper: create a section with header + grid
    local function makeSection(parent, id, label)
        local section = Instance.new("Frame")
        section.Name = id .. "_Section"
        section.BackgroundTransparency = 1
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        section.Parent = parent

        -- stack header + grid vertically, mirror ShopUI spacing
        local sectionLayout = Instance.new("UIListLayout")
        sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
        sectionLayout.Padding = UDim.new(0, px(10))
        sectionLayout.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingTop = UDim.new(0, px(4))
        sectionPad.PaddingBottom = UDim.new(0, px(10))
        sectionPad.PaddingLeft = UDim.new(0, px(8))
        sectionPad.PaddingRight = UDim.new(0, px(8))
        sectionPad.Parent = section

        -- Header wrapper with accent bar (matches Boosts/Quests/Shop header style)
        local headerWrap = Instance.new("Frame")
        headerWrap.Name = "HeaderWrap"
        headerWrap.BackgroundTransparency = 1
        headerWrap.Size = UDim2.new(1, 0, 0, px(40))
        headerWrap.LayoutOrder = 1
        headerWrap.Parent = section

        local header = Instance.new("TextLabel")
        header.Name = "SectionHeader"
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = label
        header.TextColor3 = GOLD
        header.TextSize = math.max(18, math.floor(px(20)))
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Size = UDim2.new(1, 0, 0, px(28))
        header.Position = UDim2.new(0, 0, 0, 0)
        header.Parent = headerWrap

        -- Gold accent bar under header
        local accentBar = Instance.new("Frame")
        accentBar.Name = "AccentBar"
        accentBar.BackgroundColor3 = GOLD
        accentBar.BackgroundTransparency = 0.3
        accentBar.Size = UDim2.new(1, 0, 0, px(2))
        accentBar.Position = UDim2.new(0, 0, 1, -px(2))
        accentBar.BorderSizePixel = 0
        accentBar.Parent = headerWrap

        local grid = Instance.new("Frame")
        grid.Name = id .. "_Grid"
        grid.BackgroundTransparency = 1
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.LayoutOrder = 2
        grid.Parent = section

        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0.30, 0, 0, px(160))
        gridLayout.CellPadding = UDim2.new(0.025, 0, 0, px(12))
        gridLayout.FillDirection = Enum.FillDirection.Horizontal
        gridLayout.FillDirectionMaxCells = 3
        gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gridLayout.Parent = grid

        return section, grid
    end

    -- Create sections stacked vertically
    local meleeSection, meleeGrid = makeSection(root, "Melee", "Melee Weapons")
    local rangedSection, rangedGrid = makeSection(root, "Ranged", "Ranged Weapons")
    local specialSection, specialGrid = makeSection(root, "Special", "Special Weapons")
    meleeSection.LayoutOrder = 1
    rangedSection.LayoutOrder = 2
    specialSection.LayoutOrder = 3

    local GREEN_BTN = Color3.fromRGB(35, 190, 75)
    local GREEN_BTN_STR = Color3.fromRGB(50, 230, 110)
    -- Restore equipped state from inventory API if available (per-category)
    local equippedState = { Melee = nil, Ranged = nil, Special = nil }
    if inventoryApi and inventoryApi.GetEquipped then
        pcall(function()
            equippedState.Melee = inventoryApi:GetEquipped("Melee")
            equippedState.Ranged = inventoryApi:GetEquipped("Ranged")
            equippedState.Special = inventoryApi:GetEquipped("Special")
            -- normalize legacy equipped references
            if type(equippedState.Melee) == "string" and equippedState.Melee:lower() == "stick" then
                equippedState.Melee = "Wooden Sword"
            end
            if type(equippedState.Ranged) == "string" and equippedState.Ranged:lower() == "stick" then
                equippedState.Ranged = "Wooden Sword"
            end
            if type(equippedState.Special) == "string" and equippedState.Special:lower() == "stick" then
                equippedState.Special = "Wooden Sword"
            end
        end)
    end
    local allEquipBtns = {} -- id -> {btn, stroke, category, card, cardStroke}

    local function refreshAllEquipButtons()
        for itemId, info in pairs(allEquipBtns) do
            local cat = info.category or classifyItem(itemId)
            if equippedState[cat] == itemId then
                info.btn.Text = "\u{2714} EQUIPPED"
                info.btn.BackgroundColor3 = DISABLED_BG
                info.btn.TextColor3 = GREEN_GLOW
                info.stroke.Color = GREEN_GLOW
                info.stroke.Transparency = 0.45
                -- Update card visual for equipped state
                if info.card then
                    info.card.BackgroundColor3 = CARD_EQUIPPED
                end
                if info.cardStroke then
                    info.cardStroke.Color = GREEN_GLOW
                    info.cardStroke.Thickness = 1.8
                    info.cardStroke.Transparency = 0.3
                end
            else
                info.btn.Text = "EQUIP"
                info.btn.BackgroundColor3 = BTN_BG
                info.btn.TextColor3 = WHITE
                info.stroke.Color = BTN_STROKE_C
                info.stroke.Transparency = 0.25
                -- Reset card visual
                if info.card then
                    info.card.BackgroundColor3 = CARD_BG
                end
                if info.cardStroke then
                    info.cardStroke.Color = CARD_STROKE
                    info.cardStroke.Thickness = 1.2
                    info.cardStroke.Transparency = 0.35
                end
            end
        end
    end

    -- Helper to create item card inside a specific grid
    local function createCard(gridParent, id)
        local card = Instance.new("Frame")
        card.Name = "ItemCard_" .. tostring(id)
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(1, 0, 1, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.Parent = gridParent
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, px(12))
        corner.Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Color = CARD_STROKE
        stroke.Thickness = 1.2
        stroke.Transparency = 0.35
        stroke.Parent = card
        local cardPad = Instance.new("UIPadding")
        cardPad.PaddingTop = UDim.new(0, px(8))
        cardPad.PaddingBottom = UDim.new(0, px(8))
        cardPad.PaddingLeft = UDim.new(0, px(8))
        cardPad.PaddingRight = UDim.new(0, px(8))
        cardPad.Parent = card

        local leftBox = Instance.new("Frame")
        leftBox.Name = "LeftBox"
        leftBox.Size = UDim2.new(0.45, 0, 1, 0)
        leftBox.Position = UDim2.new(0, 0, 0, 0)
        leftBox.BackgroundColor3 = ICON_BG
        leftBox.ZIndex = 251
        leftBox.Parent = card
        local lCorner = Instance.new("UICorner")
        lCorner.CornerRadius = UDim.new(0, px(10))
        lCorner.Parent = leftBox

        -- Subtle highlight in icon area for depth
        local iconHighlight = Instance.new("Frame")
        iconHighlight.Name = "IconHighlight"
        iconHighlight.Size = UDim2.new(1, 0, 0.35, 0)
        iconHighlight.Position = UDim2.new(0, 0, 0, 0)
        iconHighlight.BackgroundColor3 = Color3.fromRGB(30, 35, 55)
        iconHighlight.BackgroundTransparency = 0.5
        iconHighlight.BorderSizePixel = 0
        iconHighlight.ZIndex = 251
        iconHighlight.Parent = leftBox
        local hlCr = Instance.new("UICorner")
        hlCr.CornerRadius = UDim.new(0, px(10))
        hlCr.Parent = iconHighlight

        -- Subtle stroke on icon area
        local iconStroke = Instance.new("UIStroke")
        iconStroke.Color = CARD_STROKE
        iconStroke.Thickness = 1
        iconStroke.Transparency = 0.5
        iconStroke.Parent = leftBox

        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0.85, 0, 0.85, 0)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.BackgroundTransparency = 1
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.ZIndex = 252
        thumb.Parent = leftBox
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(id))
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        local rightBox = Instance.new("Frame")
        rightBox.Name = "RightBox"
        rightBox.Size = UDim2.new(0.52, 0, 1, 0)
        rightBox.Position = UDim2.new(0.48, 0, 0, 0)
        rightBox.BackgroundTransparency = 1
        rightBox.ZIndex = 251
        rightBox.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "ItemName"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextScaled = true
        nameLabel.TextColor3 = WHITE
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Text = tostring(id)
        nameLabel.Size = UDim2.new(1, 0, 0, px(28))
        nameLabel.Position = UDim2.new(0, 0, 0.34, 0)
        nameLabel.Parent = rightBox

        local equipBtn = Instance.new("TextButton")
        equipBtn.Name = "EquipBtn"
        equipBtn.Size = UDim2.new(0.85, 0, 0.24, 0)
        equipBtn.AnchorPoint = Vector2.new(0.5, 1)
        equipBtn.Position = UDim2.new(0.5, 0, 1, -px(2))
        equipBtn.BackgroundColor3 = BTN_BG
        equipBtn.Font = Enum.Font.GothamBold
        equipBtn.TextScaled = true
        equipBtn.TextColor3 = WHITE
        equipBtn.Text = "EQUIP"
        equipBtn.AutoButtonColor = false
        equipBtn.Parent = rightBox
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(10))
        btnCorner.Parent = equipBtn
        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = BTN_STROKE_C
        btnStroke.Thickness = 1.4
        btnStroke.Transparency = 0.25
        btnStroke.Parent = equipBtn

        local cat = classifyItem(id)
        allEquipBtns[id] = { btn = equipBtn, stroke = btnStroke, category = cat, card = card, cardStroke = stroke }

        equipBtn.MouseButton1Click:Connect(function()
            local rs = game:GetService("ReplicatedStorage")
            local toolName = tostring(id)
            local category = classifyItem(toolName)
            if category == "Ranged" then
                local setRanged = rs:FindFirstChild("SetRangedTool")
                if setRanged and setRanged:IsA("RemoteEvent") then
                    pcall(function() setRanged:FireServer(toolName) end)
                else
                    local fe = rs:FindFirstChild("ForceEquipTool")
                    if fe and fe:IsA("RemoteEvent") then
                        pcall(function() fe:FireServer("Ranged", toolName) end)
                    end
                end
            else
                local setMelee = rs:FindFirstChild("SetMeleeTool")
                if setMelee and setMelee:IsA("RemoteEvent") then
                    pcall(function() setMelee:FireServer(toolName) end)
                else
                    local fe = rs:FindFirstChild("ForceEquipTool")
                    if fe and fe:IsA("RemoteEvent") then
                        pcall(function() fe:FireServer("Melee", toolName) end)
                    end
                end
            end

            equippedState[category] = id
            if inventoryApi and inventoryApi.SetEquipped then
                pcall(function() inventoryApi:SetEquipped(category, id) end)
            end
            refreshAllEquipButtons()
            -- play local equip sound if available
            pcall(function()
                local soundsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Sounds")
                if soundsFolder then
                    local s = soundsFolder:FindFirstChild("Equip") or (soundsFolder:FindFirstChild("UI") and soundsFolder.UI:FindFirstChild("Equip"))
                    if s and s:IsA("Sound") then
                        local clone = s:Clone()
                        clone.Parent = equipBtn
                        clone:Play()
                        task.delay(clone.TimeLength + 0.1, function()
                            pcall(function() clone:Destroy() end)
                        end)
                    end
                end
            end)
        end)

        -- hover: highlight on hover (matches Boosts/Quests/Shop style)
        equipBtn.MouseEnter:Connect(function()
            local info = allEquipBtns[id]
            local isEquipped = info and equippedState[info.category] == id
            if not isEquipped then
                pcall(function()
                    TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = GREEN_BTN}):Play()
                end)
            end
        end)
        equipBtn.MouseLeave:Connect(function()
            local info = allEquipBtns[id]
            local isEquipped = info and equippedState[info.category] == id
            if not isEquipped then
                pcall(function()
                    TweenService:Create(equipBtn, TWEEN_QUICK, {BackgroundColor3 = BTN_BG}):Play()
                end)
            end
        end)

        return card
    end

    -- Populate sections with owned items
    for _, id in ipairs(items) do
        local cat = classifyItem(id)
        if cat == "Melee" then
            createCard(meleeGrid, id)
        elseif cat == "Ranged" then
            createCard(rangedGrid, id)
        else
            createCard(specialGrid, id)
        end
    end

    -- If no items, show friendly message in root
    if #items == 0 then
        local emptyCard = Instance.new("Frame")
        emptyCard.Name = "EmptyState"
        emptyCard.BackgroundColor3 = CARD_BG
        emptyCard.Size = UDim2.new(1, 0, 0, px(110))
        emptyCard.Parent = root
        local emptyCr = Instance.new("UICorner")
        emptyCr.CornerRadius = UDim.new(0, px(12))
        emptyCr.Parent = emptyCard
        local emptyStroke = Instance.new("UIStroke")
        emptyStroke.Color = CARD_STROKE
        emptyStroke.Thickness = 1.2
        emptyStroke.Transparency = 0.35
        emptyStroke.Parent = emptyCard
        local lbl = Instance.new("TextLabel")
        lbl.Text = "No items owned"
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = px(16)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = DIM_TEXT
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.Parent = emptyCard
    end

    -- Apply initial equipped state visually
    refreshAllEquipButtons()

    return root
end

return InventoryUI
