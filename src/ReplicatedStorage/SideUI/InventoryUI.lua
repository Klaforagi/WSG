--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Sectioned inventory (Melee · Ranged · Special)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 1080
    return math.max(1, math.round(base * screenY / 1080))
end

-- Use neutral SideUI gray instead of navy blue
local CARD_BG      = Color3.fromRGB(35, 35, 40)
local CARD_STROKE  = Color3.fromRGB(60, 60, 64)
local ICON_BG      = Color3.fromRGB(20, 20, 24)
local GOLD         = Color3.fromRGB(255, 215, 80)
local WHITE        = Color3.fromRGB(240, 240, 240)
-- Replace blue button accents with neutral grays to match SideUI
local BLUE_BTN     = Color3.fromRGB(64, 64, 68)
local BLUE_BTN_STR = Color3.fromRGB(110, 110, 115)

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
    rootLayout.Padding = UDim.new(0, px(12))
    rootLayout.Parent = root

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(8))
    rootPad.PaddingBottom = UDim.new(0, px(12))
    rootPad.PaddingLeft = UDim.new(0, px(6))
    rootPad.PaddingRight = UDim.new(0, px(6))
    rootPad.Parent = root

    local items = inventoryApi and inventoryApi:GetItems() or {}

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
        sectionLayout.Padding = UDim.new(0, px(6))
        sectionLayout.Parent = section

        local sectionPad = Instance.new("UIPadding")
        sectionPad.PaddingTop = UDim.new(0, px(6))
        sectionPad.PaddingBottom = UDim.new(0, px(10))
        sectionPad.PaddingLeft = UDim.new(0, px(8))
        sectionPad.PaddingRight = UDim.new(0, px(8))
        sectionPad.Parent = section

        local header = Instance.new("TextLabel")
        header.Name = "SectionHeader"
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = label
        header.TextColor3 = GOLD
        header.TextSize = math.max(18, math.floor(px(18)))
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Size = UDim2.new(1, 0, 0, px(28))
        header.LayoutOrder = 1
        header.Parent = section

        local grid = Instance.new("Frame")
        grid.Name = id .. "_Grid"
        grid.BackgroundTransparency = 1
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.LayoutOrder = 2
        grid.Parent = section

        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0.28, 0, 0, px(140))
        gridLayout.CellPadding = UDim2.new(0.02, 0, 0, px(10))
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

    local GREEN_BTN = Color3.fromRGB(30, 130, 60)
    local GREEN_BTN_STR = Color3.fromRGB(60, 200, 90)
    -- Restore equipped state from inventory API if available (per-category)
    local equippedState = { Melee = nil, Ranged = nil, Special = nil }
    if inventoryApi and inventoryApi.GetEquipped then
        pcall(function()
            equippedState.Melee = inventoryApi:GetEquipped("Melee")
            equippedState.Ranged = inventoryApi:GetEquipped("Ranged")
            equippedState.Special = inventoryApi:GetEquipped("Special")
        end)
    end
    local allEquipBtns = {} -- id -> {btn, stroke, category}

    local function refreshAllEquipButtons()
        for itemId, info in pairs(allEquipBtns) do
            local cat = info.category or classifyItem(itemId)
            if equippedState[cat] == itemId then
                info.btn.Text = "EQUIPPED"
                info.btn.BackgroundColor3 = GREEN_BTN
                info.btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                info.stroke.Color = GREEN_BTN_STR
            else
                info.btn.Text = "EQUIP"
                info.btn.BackgroundColor3 = BLUE_BTN
                info.btn.TextColor3 = WHITE
                info.stroke.Color = BLUE_BTN_STR
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
        corner.CornerRadius = UDim.new(0, px(10))
        corner.Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Color = CARD_STROKE
        stroke.Thickness = 1.5
        stroke.Transparency = 0.25
        stroke.Parent = card
        local cardPad = Instance.new("UIPadding")
        cardPad.PaddingTop = UDim.new(0, px(6))
        cardPad.PaddingBottom = UDim.new(0, px(6))
        cardPad.PaddingLeft = UDim.new(0, px(6))
        cardPad.PaddingRight = UDim.new(0, px(6))
        cardPad.Parent = card

        local leftBox = Instance.new("Frame")
        leftBox.Name = "LeftBox"
        leftBox.Size = UDim2.new(0.45, 0, 1, 0)
        leftBox.Position = UDim2.new(0, 0, 0, 0)
        leftBox.BackgroundColor3 = ICON_BG
        leftBox.ZIndex = 251
        leftBox.Parent = card
        local lCorner = Instance.new("UICorner")
        lCorner.CornerRadius = UDim.new(0, px(8))
        lCorner.Parent = leftBox

        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0.9, 0, 0.9, 0)
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
        -- match ShopUI spacing: smaller header height and centered under thumb
        nameLabel.Size = UDim2.new(1, 0, 0, px(28))
        nameLabel.Position = UDim2.new(0, 0, 0.36, 0)
        nameLabel.Parent = rightBox

        local equipBtn = Instance.new("TextButton")
        equipBtn.Name = "EquipBtn"
        equipBtn.Size = UDim2.new(0.80, 0, 0.30, 0)
        equipBtn.AnchorPoint = Vector2.new(0.5, 1)
        equipBtn.Position = UDim2.new(0.5, 0, 1, 0)
        equipBtn.BackgroundColor3 = BLUE_BTN
        equipBtn.Font = Enum.Font.GothamBold
        equipBtn.TextScaled = true
        equipBtn.TextColor3 = WHITE
        equipBtn.Text = "EQUIP"
        equipBtn.AutoButtonColor = false
        equipBtn.Parent = rightBox
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, px(6))
        btnCorner.Parent = equipBtn
        local btnStroke = Instance.new("UIStroke")
        btnStroke.Color = BLUE_BTN_STR
        btnStroke.Thickness = 1.2
        btnStroke.Transparency = 0.3
        btnStroke.Parent = equipBtn

        local cat = classifyItem(id)
        allEquipBtns[id] = { btn = equipBtn, stroke = btnStroke, category = cat }

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

        -- hover: change gray -> green on hover when actionable
        equipBtn.MouseEnter:Connect(function()
            pcall(function()
                local t = TweenService:Create(equipBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = GREEN_BTN})
                t:Play()
            end)
        end)
        equipBtn.MouseLeave:Connect(function()
            pcall(function()
                local t = TweenService:Create(equipBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = BLUE_BTN})
                t:Play()
            end)
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
        local lbl = Instance.new("TextLabel")
        lbl.Text = "No items owned"
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = px(22)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(180, 180, 200)
        lbl.Size = UDim2.new(1, 0, 0, px(50))
        lbl.Parent = root
    end

    -- Apply initial equipped state visually
    refreshAllEquipButtons()

    return root
end

return InventoryUI
