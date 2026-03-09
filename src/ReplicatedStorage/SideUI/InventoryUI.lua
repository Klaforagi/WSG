--------------------------------------------------------------------------------
-- InventoryUI.lua  –  Reference-style inventory grid (icon left · name · EQUIP)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 1080
    return math.max(1, math.round(base * screenY / 1080))
end

local CARD_BG      = Color3.fromRGB(18, 24, 52)
local CARD_STROKE  = Color3.fromRGB(50, 80, 160)
local ICON_BG      = Color3.fromRGB(14, 18, 40)
local GOLD         = Color3.fromRGB(255, 215, 80)
local WHITE        = Color3.fromRGB(240, 240, 240)
local BLUE_BTN     = Color3.fromRGB(30, 70, 160)
local BLUE_BTN_STR = Color3.fromRGB(80, 140, 220)

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

    -- ensure root has vertical stacking and padding so content doesn't overlap header
    local rootLayout = Instance.new("UIListLayout")
    rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rootLayout.Padding = UDim.new(0, px(6))
    rootLayout.Parent = root

    local rootPad = Instance.new("UIPadding")
    rootPad.PaddingTop = UDim.new(0, px(12))
    rootPad.PaddingBottom = UDim.new(0, px(10))
    rootPad.PaddingLeft = UDim.new(0, px(8))
    rootPad.PaddingRight = UDim.new(0, px(8))
    rootPad.Parent = root

    local items = inventoryApi and inventoryApi:GetItems() or {}
    if #items == 0 then
        local lbl = Instance.new("TextLabel")
        lbl.Text = "No items owned"
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = px(22)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(180, 180, 200)
        lbl.Size = UDim2.new(1, 0, 0, px(50))
        lbl.Parent = root
        return root
    end

    -- 3-column grid (same sizing as ShopUI)
    local grid = Instance.new("Frame")
    grid.Name = "Grid"
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.BackgroundTransparency = 1
    grid.Parent = root

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.28, 0, 0, px(140))
    gridLayout.CellPadding = UDim2.new(0.02, 0, 0, px(10))
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.FillDirectionMaxCells = 3
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    grid.LayoutOrder = 2

    local AssetCodes = nil
    pcall(function()
        local ac = game:GetService("ReplicatedStorage"):FindFirstChild("AssetCodes")
        if ac and ac:IsA("ModuleScript") then AssetCodes = require(ac) end
    end)

    local GREEN_BTN = Color3.fromRGB(30, 130, 60)
    local GREEN_BTN_STR = Color3.fromRGB(60, 200, 90)
    -- Restore equipped state from inventory API if available
    local equippedId = nil
    if inventoryApi and inventoryApi.GetEquipped then
        pcall(function() equippedId = inventoryApi:GetEquipped() end)
    end
    local allEquipBtns = {} -- id -> {btn, stroke}

    local function refreshAllEquipButtons()
        for itemId, info in pairs(allEquipBtns) do
            if itemId == equippedId then
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

    for _, id in ipairs(items) do
        local card = Instance.new("Frame")
        card.Name = "ItemCard_" .. tostring(id)
        card.BackgroundColor3 = CARD_BG
        card.Parent = grid
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

        -- LEFT half: weapon image
        local leftBox = Instance.new("Frame")
        leftBox.Name = "LeftBox"
        leftBox.Size = UDim2.new(0.48, 0, 1, 0)
        leftBox.Position = UDim2.new(0, 0, 0, 0)
        leftBox.BackgroundColor3 = ICON_BG
        leftBox.Parent = card
        local lCorner = Instance.new("UICorner")
        lCorner.CornerRadius = UDim.new(0, px(8))
        lCorner.Parent = leftBox

        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0.85, 0, 0.85, 0)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.BackgroundTransparency = 1
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.Parent = leftBox
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(tostring(id))
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        -- RIGHT half: name + equip button
        local rightBox = Instance.new("Frame")
        rightBox.Name = "RightBox"
        rightBox.Size = UDim2.new(0.48, 0, 1, 0)
        rightBox.Position = UDim2.new(0.52, 0, 0, 0)
        rightBox.BackgroundTransparency = 1
        rightBox.Parent = card

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "ItemName"
        nameLabel.Size = UDim2.new(1, 0, 0.40, 0)
        nameLabel.Position = UDim2.new(0, 0, 0.08, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextScaled = true
        nameLabel.TextColor3 = WHITE
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.Text = tostring(id)
        nameLabel.Parent = rightBox

        -- EQUIP button
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

        allEquipBtns[id] = { btn = equipBtn, stroke = btnStroke }

        equipBtn.MouseButton1Click:Connect(function()
            local setRanged = game:GetService("ReplicatedStorage"):FindFirstChild("SetRangedTool")
            if setRanged and setRanged:IsA("RemoteEvent") then
                pcall(function() setRanged:FireServer(tostring(id)) end)
            else
                local fe = game:GetService("ReplicatedStorage"):FindFirstChild("ForceEquipTool")
                if fe and fe:IsA("RemoteEvent") then
                    pcall(function() fe:FireServer("Ranged", tostring(id)) end)
                end
            end
            equippedId = id
            -- persist to inventory API so it survives close/reopen
            if inventoryApi and inventoryApi.SetEquipped then
                pcall(function() inventoryApi:SetEquipped(id) end)
            end
            refreshAllEquipButtons()
        end)
    end

    -- Apply initial equipped state visually
    refreshAllEquipButtons()

    return root
end

return InventoryUI
