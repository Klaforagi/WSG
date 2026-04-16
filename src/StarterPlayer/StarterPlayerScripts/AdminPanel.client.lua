--------------------------------------------------------------------------------
-- AdminPanel.client.lua  –  Dev-only admin weapon management UI
--
-- Shows an "Admin" button at the top of the screen ONLY for whitelisted devs.
-- Clicking it opens a full admin panel with two tabs:
--   1. Weapon Search  – search by WeaponId, OwnerUserId, or Username
--   2. Grant Weapon   – grant weapons to any player
--
-- All operations are server-authoritative via RemoteFunctions:
--   AdminSearchWeaponsRF, AdminGrantWeaponRF
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local DevUserIds = require(ReplicatedStorage:WaitForChild("DevUserIds"))

-- Only run for whitelisted devs
if not DevUserIds.IsDev(player) then
    return
end

-- Wait for remotes
local searchRF = ReplicatedStorage:WaitForChild("AdminSearchWeaponsRF", 10)
local grantRF  = ReplicatedStorage:WaitForChild("AdminGrantWeaponRF", 10)
local deleteRF = ReplicatedStorage:WaitForChild("AdminDeleteWeaponRF", 10)

if not searchRF or not grantRF or not deleteRF then
    warn("[AdminPanel] Admin remotes not found; aborting.")
    return
end

--------------------------------------------------------------------------------
-- COLOR PALETTE
--------------------------------------------------------------------------------
local COLORS = {
    BG_DARK       = Color3.fromRGB(20, 20, 25),
    BG_PANEL      = Color3.fromRGB(30, 30, 38),
    BG_INPUT      = Color3.fromRGB(40, 40, 50),
    BG_CARD       = Color3.fromRGB(38, 38, 48),
    BG_CARD_HOVER = Color3.fromRGB(50, 50, 65),
    ACCENT        = Color3.fromRGB(80, 140, 255),
    ACCENT_HOVER  = Color3.fromRGB(100, 160, 255),
    GREEN         = Color3.fromRGB(60, 200, 100),
    GREEN_HOVER   = Color3.fromRGB(80, 220, 120),
    RED           = Color3.fromRGB(220, 60, 60),
    TEXT_PRIMARY  = Color3.fromRGB(230, 230, 240),
    TEXT_SECONDARY= Color3.fromRGB(160, 160, 175),
    TEXT_DIM      = Color3.fromRGB(100, 100, 115),
    BORDER        = Color3.fromRGB(55, 55, 70),
    TAB_ACTIVE    = Color3.fromRGB(80, 140, 255),
    TAB_INACTIVE  = Color3.fromRGB(45, 45, 58),

    -- Rarity colors
    Common    = Color3.fromRGB(180, 180, 180),
    Uncommon  = Color3.fromRGB(80, 200, 120),
    Rare      = Color3.fromRGB(60, 140, 255),
    Epic      = Color3.fromRGB(150, 50, 230),
    Legendary = Color3.fromRGB(255, 180, 30),
}

--------------------------------------------------------------------------------
-- UI CONSTRUCTION HELPERS
--------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")

local function createInstance(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" and k ~= "Children" then
            obj[k] = v
        end
    end
    if props.Children then
        for _, child in ipairs(props.Children) do
            child.Parent = obj
        end
    end
    if props.Parent then
        obj.Parent = props.Parent
    end
    return obj
end

local function addCorner(parent, radius)
    return createInstance("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function addStroke(parent, color, thickness)
    return createInstance("UIStroke", {
        Color = color or COLORS.BORDER,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function addPadding(parent, t, b, l, r)
    return createInstance("UIPadding", {
        PaddingTop    = UDim.new(0, t or 8),
        PaddingBottom = UDim.new(0, b or 8),
        PaddingLeft   = UDim.new(0, l or 8),
        PaddingRight  = UDim.new(0, r or 8),
        Parent = parent,
    })
end

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local screenGui = createInstance("ScreenGui", {
    Name = "AdminPanelGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 500,
    Parent = playerGui,
})

--------------------------------------------------------------------------------
-- ADMIN BUTTON (top-left, small square with "A")
--------------------------------------------------------------------------------
local adminButton = createInstance("TextButton", {
    Name = "AdminButton",
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(0, 6, 0, 6),
    BackgroundColor3 = COLORS.RED,
    Text = "A",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Parent = screenGui,
})
addCorner(adminButton, 6)

--------------------------------------------------------------------------------
-- MAIN PANEL (centered, large, hidden by default)
--------------------------------------------------------------------------------
local panelFrame = createInstance("Frame", {
    Name = "AdminPanel",
    Size = UDim2.new(0, 900, 0, 560),
    Position = UDim2.new(0.5, -450, 0.5, -280),
    BackgroundColor3 = COLORS.BG_DARK,
    Visible = false,
    Parent = screenGui,
})
addCorner(panelFrame, 10)
addStroke(panelFrame, COLORS.BORDER, 2)

-- Title bar
local titleBar = createInstance("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = panelFrame,
})
addCorner(titleBar, 10)

-- Fill bottom corners of title bar
createInstance("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = COLORS.BG_PANEL,
    BorderSizePixel = 0,
    Parent = titleBar,
})

createInstance("TextLabel", {
    Size = UDim2.new(1, -50, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Text = "Admin Panel",
    TextColor3 = COLORS.TEXT_PRIMARY,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = titleBar,
})

local closeButton = createInstance("TextButton", {
    Name = "CloseBtn",
    Size = UDim2.new(0, 32, 0, 32),
    Position = UDim2.new(1, -36, 0, 4),
    BackgroundColor3 = COLORS.RED,
    Text = "X",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Parent = titleBar,
})
addCorner(closeButton, 6)

-- Tab bar
local tabBar = createInstance("Frame", {
    Name = "TabBar",
    Size = UDim2.new(1, 0, 0, 36),
    Position = UDim2.new(0, 0, 0, 42),
    BackgroundTransparency = 1,
    Parent = panelFrame,
})

local function createTab(name, text, order)
    local btn = createInstance("TextButton", {
        Name = name,
        Size = UDim2.new(0, 140, 0, 30),
        Position = UDim2.new(0, 12 + (order - 1) * 150, 0, 3),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = text,
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        Parent = tabBar,
    })
    addCorner(btn, 6)
    return btn
end

local searchTab = createTab("SearchTab", "Weapon Search", 1)
local grantTab  = createTab("GrantTab", "Grant Weapon", 2)

-- Content area
local contentArea = createInstance("Frame", {
    Name = "Content",
    Size = UDim2.new(1, -16, 1, -86),
    Position = UDim2.new(0, 8, 0, 80),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Parent = panelFrame,
})

--------------------------------------------------------------------------------
-- TAB 1: WEAPON SEARCH
--------------------------------------------------------------------------------
local searchPage = createInstance("Frame", {
    Name = "SearchPage",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Visible = true,
    Parent = contentArea,
})

-- Left column: search controls + results list
local searchLeft = createInstance("Frame", {
    Name = "SearchLeft",
    Size = UDim2.new(0.5, -4, 1, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = searchPage,
})
addCorner(searchLeft, 8)
addPadding(searchLeft, 10, 10, 10, 10)

-- Search type selector
createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18),
    BackgroundTransparency = 1,
    Text = "Search Type",
    TextColor3 = COLORS.TEXT_SECONDARY,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = searchLeft,
})

-- Search type toggle buttons
local searchTypeFrame = createInstance("Frame", {
    Name = "SearchTypeFrame",
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 0, 22),
    BackgroundTransparency = 1,
    Parent = searchLeft,
})

local searchTypes = { "WeaponId", "OwnerUserId", "Username" }
local searchTypeLabels = { "Weapon ID", "Owner UserId", "Username" }
local searchTypeBtns = {}
local currentSearchType = "WeaponId"

for i, st in ipairs(searchTypes) do
    local btn = createInstance("TextButton", {
        Name = st,
        Size = UDim2.new(0, 110, 0, 26),
        Position = UDim2.new(0, (i - 1) * 118, 0, 0),
        BackgroundColor3 = (i == 1) and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE,
        Text = searchTypeLabels[i],
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        Parent = searchTypeFrame,
    })
    addCorner(btn, 4)
    searchTypeBtns[st] = btn
end

-- Search value input
createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 0, 0, 58),
    BackgroundTransparency = 1,
    Text = "Search Value",
    TextColor3 = COLORS.TEXT_SECONDARY,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = searchLeft,
})

local searchInput = createInstance("TextBox", {
    Name = "SearchInput",
    Size = UDim2.new(1, -80, 0, 32),
    Position = UDim2.new(0, 0, 0, 78),
    BackgroundColor3 = COLORS.BG_INPUT,
    Text = "",
    PlaceholderText = "Enter weapon ID...",
    TextColor3 = COLORS.TEXT_PRIMARY,
    PlaceholderColor3 = COLORS.TEXT_DIM,
    Font = Enum.Font.Gotham,
    TextSize = 13,
    ClearTextOnFocus = false,
    Parent = searchLeft,
})
addCorner(searchInput, 4)
addPadding(searchInput, 0, 0, 8, 8)

local searchButton = createInstance("TextButton", {
    Name = "SearchBtn",
    Size = UDim2.new(0, 70, 0, 32),
    Position = UDim2.new(1, -70, 0, 78),
    BackgroundColor3 = COLORS.ACCENT,
    Text = "Search",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Parent = searchLeft,
})
addCorner(searchButton, 4)

-- Status label
local searchStatus = createInstance("TextLabel", {
    Name = "SearchStatus",
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 0, 0, 115),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = COLORS.TEXT_DIM,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = searchLeft,
})

-- Results scroll list
local resultsScroll = createInstance("ScrollingFrame", {
    Name = "ResultsScroll",
    Size = UDim2.new(1, 0, 1, -140),
    Position = UDim2.new(0, 0, 0, 136),
    BackgroundTransparency = 1,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.ACCENT,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = searchLeft,
})

local resultsLayout = createInstance("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 4),
    Parent = resultsScroll,
})

-- Right column: detail view
local searchRight = createInstance("Frame", {
    Name = "SearchRight",
    Size = UDim2.new(0.5, -4, 1, 0),
    Position = UDim2.new(0.5, 4, 0, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = searchPage,
})
addCorner(searchRight, 8)
addPadding(searchRight, 10, 10, 10, 10)

local detailTitle = createInstance("TextLabel", {
    Name = "DetailTitle",
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    Text = "Select a weapon to view details",
    TextColor3 = COLORS.TEXT_DIM,
    Font = Enum.Font.GothamMedium,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = searchRight,
})

local detailScroll = createInstance("ScrollingFrame", {
    Name = "DetailScroll",
    Size = UDim2.new(1, 0, 1, -74),
    Position = UDim2.new(0, 0, 0, 26),
    BackgroundTransparency = 1,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.ACCENT,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = searchRight,
})

local detailLayout = createInstance("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 2),
    Parent = detailScroll,
})

-- Delete button (bottom of detail panel, hidden until a weapon is selected)
local deleteWeaponBtn = createInstance("TextButton", {
    Name = "DeleteWeaponBtn",
    Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.new(0, 0, 1, -38),
    BackgroundColor3 = COLORS.RED,
    Text = "Delete Weapon",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    Visible = false,
    Parent = searchRight,
})
addCorner(deleteWeaponBtn, 6)

--------------------------------------------------------------------------------
-- TAB 2: GRANT WEAPON
--------------------------------------------------------------------------------
local grantPage = createInstance("Frame", {
    Name = "GrantPage",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = contentArea,
})

-- Left column: input form
local grantLeft = createInstance("Frame", {
    Name = "GrantLeft",
    Size = UDim2.new(0.5, -4, 1, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = grantPage,
})
addCorner(grantLeft, 8)
addPadding(grantLeft, 12, 12, 12, 12)

local function createFormField(parent, labelText, placeholder, yPos)
    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 0, yPos),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = COLORS.TEXT_SECONDARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent,
    })

    local input = createInstance("TextBox", {
        Size = UDim2.new(1, 0, 0, 32),
        Position = UDim2.new(0, 0, 0, yPos + 18),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = "",
        PlaceholderText = placeholder,
        TextColor3 = COLORS.TEXT_PRIMARY,
        PlaceholderColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
        Parent = parent,
    })
    addCorner(input, 4)
    addPadding(input, 0, 0, 8, 8)

    return input
end

-- Quick-select dev buttons
createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    Text = "Quick Select",
    TextColor3 = COLORS.TEXT_SECONDARY,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = grantLeft,
})

local DEV_PRESETS = {
    { name = "Edithonus",  userId = "285568988" },
    { name = "Klaforagi",  userId = "285563003" },
}

for i, preset in ipairs(DEV_PRESETS) do
    local qBtn = createInstance("TextButton", {
        Name = "Quick_" .. preset.name,
        Size = UDim2.new(0, 120, 0, 26),
        Position = UDim2.new(0, (i - 1) * 128, 0, 18),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = preset.name,
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = grantLeft,
    })
    addCorner(qBtn, 4)
    addStroke(qBtn, COLORS.BORDER, 1)
    qBtn.MouseEnter:Connect(function() qBtn.BackgroundColor3 = COLORS.BG_CARD_HOVER end)
    qBtn.MouseLeave:Connect(function() qBtn.BackgroundColor3 = COLORS.BG_INPUT end)
    -- Clicking pastes the userId into the Target UserId field
    qBtn.MouseButton1Click:Connect(function()
        -- targetUserIdInput is referenced below; uses upvalue closure
        local field = grantLeft:FindFirstChild("TargetUserIdField")
        if field then
            field.Text = preset.userId
        end
    end)
end

local QUICK_SELECT_OFFSET = 52 -- space taken by quick-select row

local targetUserIdInput  = createFormField(grantLeft, "Target UserId", "e.g. 285568988", 0 + QUICK_SELECT_OFFSET)
targetUserIdInput.Name = "TargetUserIdField"
local weaponNameInput    = createFormField(grantLeft, "Weapon Name", "e.g. Kingsblade", 60 + QUICK_SELECT_OFFSET)
local sizePercentInput   = createFormField(grantLeft, "Size Percent (80-200)", "e.g. 150", 120 + QUICK_SELECT_OFFSET)
local enchantNameInput   = createFormField(grantLeft, "Enchant Name (optional)", "e.g. Fiery, Icy, Void...", 180 + QUICK_SELECT_OFFSET)

-- Right column: grant button + result
local grantRight = createInstance("Frame", {
    Name = "GrantRight",
    Size = UDim2.new(0.5, -4, 1, 0),
    Position = UDim2.new(0.5, 4, 0, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = grantPage,
})
addCorner(grantRight, 8)
addPadding(grantRight, 12, 12, 12, 12)

createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundTransparency = 1,
    Text = "Grant Confirmation",
    TextColor3 = COLORS.TEXT_PRIMARY,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = grantRight,
})

local grantPreview = createInstance("TextLabel", {
    Name = "GrantPreview",
    Size = UDim2.new(1, 0, 0, 160),
    Position = UDim2.new(0, 0, 0, 28),
    BackgroundColor3 = COLORS.BG_INPUT,
    Text = "Fill in the fields on the left\nand click Grant to create a weapon.",
    TextColor3 = COLORS.TEXT_DIM,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = grantRight,
})
addCorner(grantPreview, 6)
addPadding(grantPreview, 8, 8, 8, 8)

local grantButton = createInstance("TextButton", {
    Name = "GrantBtn",
    Size = UDim2.new(1, 0, 0, 40),
    Position = UDim2.new(0, 0, 0, 200),
    BackgroundColor3 = COLORS.GREEN,
    Text = "Create / Grant Weapon",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Parent = grantRight,
})
addCorner(grantButton, 6)

local grantStatus = createInstance("TextLabel", {
    Name = "GrantStatus",
    Size = UDim2.new(1, 0, 0, 100),
    Position = UDim2.new(0, 0, 0, 250),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = COLORS.GREEN,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = grantRight,
})

--------------------------------------------------------------------------------
-- LOGIC: PANEL TOGGLE
--------------------------------------------------------------------------------
local panelOpen = false

local function togglePanel()
    panelOpen = not panelOpen
    panelFrame.Visible = panelOpen
end

adminButton.MouseButton1Click:Connect(togglePanel)
closeButton.MouseButton1Click:Connect(function()
    panelOpen = false
    panelFrame.Visible = false
end)

--------------------------------------------------------------------------------
-- LOGIC: TAB SWITCHING
--------------------------------------------------------------------------------
local function switchTab(tabName)
    searchPage.Visible = (tabName == "Search")
    grantPage.Visible  = (tabName == "Grant")
    searchTab.BackgroundColor3 = (tabName == "Search") and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    grantTab.BackgroundColor3  = (tabName == "Grant") and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
end

searchTab.MouseButton1Click:Connect(function() switchTab("Search") end)
grantTab.MouseButton1Click:Connect(function() switchTab("Grant") end)

--------------------------------------------------------------------------------
-- LOGIC: SEARCH TYPE TOGGLE
--------------------------------------------------------------------------------
local placeholderMap = {
    WeaponId    = "Enter weapon ID (e.g. WPN-A1B2C3)...",
    OwnerUserId = "Enter owner UserId (e.g. 285568988)...",
    Username    = "Enter username...",
}

local function setSearchType(st)
    currentSearchType = st
    searchInput.PlaceholderText = placeholderMap[st] or ""
    for name, btn in pairs(searchTypeBtns) do
        btn.BackgroundColor3 = (name == st) and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    end
end

for st, btn in pairs(searchTypeBtns) do
    btn.MouseButton1Click:Connect(function()
        setSearchType(st)
    end)
end

--------------------------------------------------------------------------------
-- LOGIC: SEARCH
--------------------------------------------------------------------------------
local function clearResults()
    for _, child in ipairs(resultsScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

-- Track the currently displayed weapon record for delete
local currentDetailRecord = nil
local deleteConfirmPending = false

local function clearDetail()
    for _, child in ipairs(detailScroll:GetChildren()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            child:Destroy()
        end
    end
    detailTitle.Text = "Select a weapon to view details"
    deleteWeaponBtn.Visible = false
    deleteWeaponBtn.Text = "Delete Weapon"
    deleteWeaponBtn.BackgroundColor3 = COLORS.RED
    currentDetailRecord = nil
    deleteConfirmPending = false
end

-- Forward-declare doSearch so clickable detail rows can trigger searches
local doSearch

local function createDetailRow(label, value, order, color)
    local row = createInstance("TextLabel", {
        Name = "Detail_" .. label,
        Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = order,
        BackgroundTransparency = 1,
        RichText = true,
        Text = string.format(
            '<font color="rgb(%d,%d,%d)">%s:</font>  %s',
            math.floor(COLORS.TEXT_SECONDARY.R * 255),
            math.floor(COLORS.TEXT_SECONDARY.G * 255),
            math.floor(COLORS.TEXT_SECONDARY.B * 255),
            label,
            tostring(value or "—")
        ),
        TextColor3 = color or COLORS.TEXT_PRIMARY,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        Parent = detailScroll,
    })
    return row
end

--- Clickable detail row: looks like a normal row but is a TextButton with underline hint.
local function createClickableDetailRow(label, value, order, color, onClick)
    local row = createInstance("TextButton", {
        Name = "Detail_" .. label,
        Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = order,
        BackgroundTransparency = 1,
        RichText = true,
        Text = string.format(
            '<font color="rgb(%d,%d,%d)">%s:</font>  <u>%s</u>',
            math.floor(COLORS.TEXT_SECONDARY.R * 255),
            math.floor(COLORS.TEXT_SECONDARY.G * 255),
            math.floor(COLORS.TEXT_SECONDARY.B * 255),
            label,
            tostring(value or "—")
        ),
        TextColor3 = color or COLORS.ACCENT,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        AutoButtonColor = false,
        Parent = detailScroll,
    })
    row.MouseEnter:Connect(function() row.TextColor3 = COLORS.ACCENT_HOVER end)
    row.MouseLeave:Connect(function() row.TextColor3 = color or COLORS.ACCENT end)
    row.MouseButton1Click:Connect(function()
        if onClick then onClick() end
    end)
    return row
end

local function showDetail(record)
    clearDetail()
    currentDetailRecord = record
    detailTitle.Text = record.WeaponName or "Weapon Details"

    -- Show the delete button for this weapon
    deleteWeaponBtn.Visible = true
    deleteWeaponBtn.Text = "Delete Weapon"
    deleteWeaponBtn.BackgroundColor3 = COLORS.RED
    deleteConfirmPending = false

    local rarityColor = COLORS[record.Rarity] or COLORS.TEXT_PRIMARY

    -- Weapon ID: clickable -> searches by WeaponId
    createClickableDetailRow("Weapon ID", record.WeaponId, 1, nil, function()
        if record.WeaponId then
            setSearchType("WeaponId")
            searchInput.Text = record.WeaponId
            doSearch()
        end
    end)

    createDetailRow("Weapon Name",   record.WeaponName, 2)
    createDetailRow("Rarity",        record.Rarity, 3, rarityColor)

    -- Owner: clickable -> searches by OwnerUserId to show all their weapons
    createClickableDetailRow("Owner",
        (record.OwnerUsername or "?") .. " (" .. tostring(record.OwnerUserId or "?") .. ")",
        4, nil, function()
            if record.OwnerUserId then
                setSearchType("OwnerUserId")
                searchInput.Text = tostring(record.OwnerUserId)
                doSearch()
            end
        end
    )

    createDetailRow("Size",          tostring(record.SizePercent or 100) .. "%", 5)
    createDetailRow("Enchant",       (record.Enchant and record.Enchant ~= "") and record.Enchant or "None", 6)

    -- Format timestamp
    local obtainedStr = "Unknown"
    if record.ObtainedAt and record.ObtainedAt > 0 then
        local ok, formatted = pcall(function()
            return os.date("%Y-%m-%d %H:%M:%S", record.ObtainedAt)
        end)
        if ok then obtainedStr = formatted end
    end
    createDetailRow("Obtained At",   obtainedStr, 7)
    createDetailRow("Obtained Via",  record.ObtainedMethod or "Unknown", 8)

    if record.GrantedByUsername and record.GrantedByUsername ~= "" then
        -- Granted By: clickable -> searches by that admin's UserId
        createClickableDetailRow("Granted By",
            record.GrantedByUsername .. " (" .. tostring(record.GrantedByUserId or "?") .. ")",
            9, nil, function()
                if record.GrantedByUserId then
                    setSearchType("OwnerUserId")
                    searchInput.Text = tostring(record.GrantedByUserId)
                    doSearch()
                end
            end
        )
    end

    if record.LastUpdatedAt and record.LastUpdatedAt > 0 then
        local ok2, formatted2 = pcall(function()
            return os.date("%Y-%m-%d %H:%M:%S", record.LastUpdatedAt)
        end)
        if ok2 then
            createDetailRow("Last Updated", formatted2, 10)
        end
    end
end

--------------------------------------------------------------------------------
-- DELETE WEAPON HANDLER (two-click confirm)
--------------------------------------------------------------------------------
local deleteBusy = false

deleteWeaponBtn.MouseButton1Click:Connect(function()
    if deleteBusy then return end
    local rec = currentDetailRecord
    if not rec or not rec.WeaponId or not rec.OwnerUserId then return end

    if not deleteConfirmPending then
        -- First click: ask for confirmation
        deleteConfirmPending = true
        deleteWeaponBtn.Text = "CONFIRM DELETE?"
        deleteWeaponBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
        -- Auto-reset after 3 seconds if not confirmed
        task.delay(3, function()
            if deleteConfirmPending and currentDetailRecord == rec then
                deleteConfirmPending = false
                deleteWeaponBtn.Text = "Delete Weapon"
                deleteWeaponBtn.BackgroundColor3 = COLORS.RED
            end
        end)
        return
    end

    -- Second click: actually delete
    deleteBusy = true
    deleteConfirmPending = false
    deleteWeaponBtn.Text = "Deleting..."
    deleteWeaponBtn.BackgroundColor3 = COLORS.TAB_INACTIVE

    local ok, result = pcall(function()
        return deleteRF:InvokeServer(rec.OwnerUserId, rec.WeaponId)
    end)

    deleteBusy = false

    if not ok then
        deleteWeaponBtn.Text = "Error!"
        deleteWeaponBtn.BackgroundColor3 = COLORS.RED
        task.delay(2, function()
            if currentDetailRecord == rec then
                deleteWeaponBtn.Text = "Delete Weapon"
            end
        end)
        return
    end

    if result and result.success then
        deleteWeaponBtn.Text = "Deleted!"
        deleteWeaponBtn.BackgroundColor3 = COLORS.GREEN
        -- Remove the card from the results list
        local card = resultsScroll:FindFirstChild("Result_" .. rec.WeaponId)
        if card then card:Destroy() end
        -- Auto-clear detail after a moment
        task.delay(1.5, function()
            if currentDetailRecord == rec then
                clearDetail()
            end
        end)
    else
        deleteWeaponBtn.Text = (result and result.error) or "Delete failed"
        deleteWeaponBtn.BackgroundColor3 = COLORS.RED
        task.delay(2, function()
            if currentDetailRecord == rec then
                deleteWeaponBtn.Text = "Delete Weapon"
            end
        end)
    end
end)

-- Hover effect for delete button (inline since addHoverEffect is defined later)
deleteWeaponBtn.MouseEnter:Connect(function()
    if not deleteConfirmPending and not deleteBusy then
        deleteWeaponBtn.BackgroundColor3 = Color3.fromRGB(240, 80, 80)
    end
end)
deleteWeaponBtn.MouseLeave:Connect(function()
    if not deleteConfirmPending and not deleteBusy then
        deleteWeaponBtn.BackgroundColor3 = COLORS.RED
    end
end)

local function createResultCard(record, order)
    local rarityColor = COLORS[record.Rarity] or COLORS.Common

    local card = createInstance("TextButton", {
        Name = "Result_" .. tostring(record.WeaponId),
        Size = UDim2.new(1, 0, 0, 48),
        LayoutOrder = order,
        BackgroundColor3 = COLORS.BG_CARD,
        Text = "",
        AutoButtonColor = false,
        Parent = resultsScroll,
    })
    addCorner(card, 4)

    -- Rarity accent bar on left
    createInstance("Frame", {
        Size = UDim2.new(0, 3, 1, -8),
        Position = UDim2.new(0, 4, 0, 4),
        BackgroundColor3 = rarityColor,
        BorderSizePixel = 0,
        Parent = card,
    })

    -- Weapon name
    createInstance("TextLabel", {
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.new(0, 14, 0, 4),
        BackgroundTransparency = 1,
        Text = (record.WeaponName or "?") .. "  [" .. tostring(record.WeaponId or "?") .. "]",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = card,
    })

    -- Details line
    local enchantStr = (record.Enchant and record.Enchant ~= "") and (" | " .. record.Enchant) or ""
    local dateStr = ""
    if record.ObtainedAt and record.ObtainedAt > 0 then
        local ok, formatted = pcall(function()
            return os.date("%Y-%m-%d %H:%M", record.ObtainedAt)
        end)
        if ok then dateStr = " | " .. formatted end
    end
    createInstance("TextLabel", {
        Size = UDim2.new(1, -20, 0, 16),
        Position = UDim2.new(0, 14, 0, 24),
        BackgroundTransparency = 1,
        Text = (record.Rarity or "?") .. " | " .. tostring(record.SizePercent or 100) .. "%" .. enchantStr .. " | " .. (record.OwnerUsername or "?") .. dateStr,
        TextColor3 = COLORS.TEXT_SECONDARY,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = card,
    })

    -- Hover effect
    card.MouseEnter:Connect(function()
        card.BackgroundColor3 = COLORS.BG_CARD_HOVER
    end)
    card.MouseLeave:Connect(function()
        card.BackgroundColor3 = COLORS.BG_CARD
    end)

    -- Click to show detail
    card.MouseButton1Click:Connect(function()
        showDetail(record)
    end)

    return card
end

local searchBusy = false

doSearch = function()
    if searchBusy then return end
    searchBusy = true

    local value = searchInput.Text
    if value == "" then
        searchStatus.Text = "Enter a search value."
        searchStatus.TextColor3 = COLORS.RED
        searchBusy = false
        return
    end

    searchStatus.Text = "Searching..."
    searchStatus.TextColor3 = COLORS.TEXT_DIM
    clearResults()
    clearDetail()

    local ok, result = pcall(function()
        return searchRF:InvokeServer(currentSearchType, value)
    end)

    searchBusy = false

    if not ok then
        searchStatus.Text = "Request failed: " .. tostring(result)
        searchStatus.TextColor3 = COLORS.RED
        return
    end

    if not result or not result.success then
        searchStatus.Text = "Error: " .. tostring(result and result.error or "Unknown error")
        searchStatus.TextColor3 = COLORS.RED
        return
    end

    local results = result.results or {}
    if #results == 0 then
        searchStatus.Text = "No weapons found."
        searchStatus.TextColor3 = COLORS.TEXT_DIM
        return
    end

    searchStatus.Text = tostring(#results) .. " weapon(s) found."
    searchStatus.TextColor3 = COLORS.GREEN

    -- Sort by date obtained (newest first)
    table.sort(results, function(a, b)
        local aTime = (a.ObtainedAt and a.ObtainedAt > 0) and a.ObtainedAt or 0
        local bTime = (b.ObtainedAt and b.ObtainedAt > 0) and b.ObtainedAt or 0
        return aTime > bTime
    end)

    for i, record in ipairs(results) do
        createResultCard(record, i)
    end

    -- Auto-select first result
    if #results == 1 then
        showDetail(results[1])
    end
end

searchButton.MouseButton1Click:Connect(doSearch)
searchInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        doSearch()
    end
end)

--------------------------------------------------------------------------------
-- LOGIC: GRANT WEAPON
--------------------------------------------------------------------------------
local grantBusy = false

-- Update preview when fields change
local function updateGrantPreview()
    local uid = targetUserIdInput.Text
    local wname = weaponNameInput.Text
    local size = sizePercentInput.Text
    local ench = enchantNameInput.Text

    local lines = {}
    table.insert(lines, "Target UserId: " .. (uid ~= "" and uid or "(empty)"))
    table.insert(lines, "Weapon: " .. (wname ~= "" and wname or "(empty)"))
    table.insert(lines, "Size: " .. (size ~= "" and size or "100") .. "%")
    table.insert(lines, "Enchant: " .. (ench ~= "" and ench or "None"))
    table.insert(lines, "")
    table.insert(lines, "Click 'Create / Grant Weapon' to confirm.")

    grantPreview.Text = table.concat(lines, "\n")
    grantPreview.TextColor3 = COLORS.TEXT_SECONDARY
end

targetUserIdInput.FocusLost:Connect(updateGrantPreview)
weaponNameInput.FocusLost:Connect(updateGrantPreview)
sizePercentInput.FocusLost:Connect(updateGrantPreview)
enchantNameInput.FocusLost:Connect(updateGrantPreview)

local function doGrant()
    if grantBusy then return end
    grantBusy = true

    local uid = tonumber(targetUserIdInput.Text)
    local wname = weaponNameInput.Text
    local size = tonumber(sizePercentInput.Text) or 100
    local ench = enchantNameInput.Text

    -- Client-side quick validation
    if not uid or uid <= 0 then
        grantStatus.Text = "Invalid Target UserId."
        grantStatus.TextColor3 = COLORS.RED
        grantBusy = false
        return
    end
    if wname == "" then
        grantStatus.Text = "Weapon Name is required."
        grantStatus.TextColor3 = COLORS.RED
        grantBusy = false
        return
    end

    grantStatus.Text = "Granting weapon..."
    grantStatus.TextColor3 = COLORS.TEXT_DIM
    grantButton.BackgroundColor3 = COLORS.TAB_INACTIVE

    local ok, result = pcall(function()
        return grantRF:InvokeServer(uid, wname, size, ench)
    end)

    grantButton.BackgroundColor3 = COLORS.GREEN
    grantBusy = false

    if not ok then
        grantStatus.Text = "Request failed: " .. tostring(result)
        grantStatus.TextColor3 = COLORS.RED
        return
    end

    if not result or not result.success then
        grantStatus.Text = "Error: " .. tostring(result and result.error or "Unknown error")
        grantStatus.TextColor3 = COLORS.RED
        return
    end

    -- Success!
    local rec = result.weaponRecord
    if rec then
        grantStatus.Text = string.format(
            "SUCCESS!\nWeapon ID: %s\nGranted %s to %s (%d)\nSize: %d%% | Enchant: %s",
            rec.WeaponId or "?",
            rec.WeaponName or "?",
            rec.OwnerUsername or "?",
            rec.OwnerUserId or 0,
            rec.SizePercent or 100,
            (rec.Enchant and rec.Enchant ~= "") and rec.Enchant or "None"
        )
    else
        grantStatus.Text = "Weapon granted successfully!"
    end
    grantStatus.TextColor3 = COLORS.GREEN
end

grantButton.MouseButton1Click:Connect(doGrant)

-- Button hover effects
local function addHoverEffect(btn, normalColor, hoverColor)
    btn.MouseEnter:Connect(function()
        if btn.BackgroundColor3 == normalColor then
            btn.BackgroundColor3 = hoverColor
        end
    end)
    btn.MouseLeave:Connect(function()
        if btn.BackgroundColor3 == hoverColor then
            btn.BackgroundColor3 = normalColor
        end
    end)
end

addHoverEffect(adminButton, COLORS.RED, Color3.fromRGB(240, 80, 80))
addHoverEffect(searchButton, COLORS.ACCENT, COLORS.ACCENT_HOVER)
addHoverEffect(grantButton, COLORS.GREEN, COLORS.GREEN_HOVER)

print("[AdminPanel] Admin UI ready for " .. player.Name)
