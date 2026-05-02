--------------------------------------------------------------------------------
-- AdminPanel.client.lua  –  Dev-only admin weapon management UI
--
-- Shows an "Admin" button at the top of the screen ONLY for whitelisted devs.
-- Clicking it opens a full admin panel with two tabs:
--   1. Weapon Search  – search by WeaponId, OwnerUserId, or Username
--   2. Grant Weapon   – grant weapons to any player
--   3. Grant Currency – grant coins, keys, or salvage to any player
--
-- All operations are server-authoritative via RemoteFunctions:
--   AdminSearchWeaponsRF, AdminGrantWeaponRF, AdminGrantCurrencyRF
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
local grantCurrencyRF = ReplicatedStorage:WaitForChild("AdminGrantCurrencyRF", 10)
local deleteRF = ReplicatedStorage:WaitForChild("AdminDeleteWeaponRF", 10)

if not searchRF or not grantRF or not grantCurrencyRF or not deleteRF then
    warn("[AdminPanel] Admin remotes not found; aborting.")
    return
end

--------------------------------------------------------------------------------
-- USER DATA TAB REMOTES (best-effort: tab is hidden if remotes missing)
--------------------------------------------------------------------------------
local AdminUserDataConfig
local getSavedRF, searchSavedRF, getUserRF, resetUserRF
local getHistoryRF, searchHistoryRF, getBackupRF, restoreRF
do
    local okCfg, cfg = pcall(function()
        return require(ReplicatedStorage:WaitForChild("AdminUserDataConfig", 5))
    end)
    if okCfg then AdminUserDataConfig = cfg end

    local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
    local adminFolder   = remotesFolder and remotesFolder:WaitForChild("Admin", 5)
    if adminFolder then
        getSavedRF      = adminFolder:WaitForChild("AdminGetSavedPlayers", 5)
        searchSavedRF   = adminFolder:WaitForChild("AdminSearchSavedPlayers", 5)
        getUserRF       = adminFolder:WaitForChild("AdminGetUserData", 5)
        resetUserRF     = adminFolder:WaitForChild("AdminResetUserData", 5)
        getHistoryRF    = adminFolder:WaitForChild("AdminGetResetHistory", 5)
        searchHistoryRF = adminFolder:WaitForChild("AdminSearchResetHistory", 5)
        getBackupRF     = adminFolder:WaitForChild("AdminGetResetBackup", 5)
        restoreRF       = adminFolder:WaitForChild("AdminRestoreUserDataBackup", 5)
    end
end
local USER_DATA_AVAILABLE =
    AdminUserDataConfig ~= nil and getSavedRF ~= nil and searchSavedRF ~= nil
    and getUserRF ~= nil and resetUserRF ~= nil
local RESTORE_AVAILABLE =
    USER_DATA_AVAILABLE
    and getHistoryRF ~= nil and searchHistoryRF ~= nil
    and getBackupRF ~= nil and restoreRF ~= nil
if not USER_DATA_AVAILABLE then
    warn("[AdminPanel] User Data remotes not found; tab will be hidden.")
end
if not RESTORE_AVAILABLE then
    warn("[AdminPanel] Restore remotes not found; User Data (R) tab will be hidden.")
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
local grantCurrencyTab = createTab("GrantCurrencyTab", "Grant Currency", 3)
local userDataTab = createTab("UserDataTab", "User Data", 4)
userDataTab.Visible = USER_DATA_AVAILABLE
local userDataRTab = createTab("UserDataRTab", "User Data (R)", 5)
userDataRTab.Visible = RESTORE_AVAILABLE

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
-- TAB 3: GRANT CURRENCY
--------------------------------------------------------------------------------
local updateCurrencyPreview

local currencyPage = createInstance("Frame", {
    Name = "GrantCurrencyPage",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = contentArea,
})

local currencyLeft = createInstance("Frame", {
    Name = "GrantCurrencyLeft",
    Size = UDim2.new(0.5, -4, 1, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = currencyPage,
})
addCorner(currencyLeft, 8)
addPadding(currencyLeft, 12, 12, 12, 12)

createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    Text = "Quick Select",
    TextColor3 = COLORS.TEXT_SECONDARY,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = currencyLeft,
})

for i, preset in ipairs(DEV_PRESETS) do
    local qBtn = createInstance("TextButton", {
        Name = "QuickCurrency_" .. preset.name,
        Size = UDim2.new(0, 120, 0, 26),
        Position = UDim2.new(0, (i - 1) * 128, 0, 18),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = preset.name,
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = currencyLeft,
    })
    addCorner(qBtn, 4)
    addStroke(qBtn, COLORS.BORDER, 1)
    qBtn.MouseEnter:Connect(function() qBtn.BackgroundColor3 = COLORS.BG_CARD_HOVER end)
    qBtn.MouseLeave:Connect(function() qBtn.BackgroundColor3 = COLORS.BG_INPUT end)
    qBtn.MouseButton1Click:Connect(function()
        local field = currencyLeft:FindFirstChild("TargetUserIdField")
        if field then
            field.Text = preset.userId
        end
        if updateCurrencyPreview then
            updateCurrencyPreview()
        end
    end)
end

local currencyTargetUserIdInput = createFormField(currencyLeft, "Target UserId", "e.g. 285568988", 0 + QUICK_SELECT_OFFSET)
currencyTargetUserIdInput.Name = "TargetUserIdField"

createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16),
    Position = UDim2.new(0, 0, 0, 112),
    BackgroundTransparency = 1,
    Text = "Currency Type",
    TextColor3 = COLORS.TEXT_SECONDARY,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = currencyLeft,
})

local currencyTypeFrame = createInstance("Frame", {
    Name = "CurrencyTypeFrame",
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 0, 132),
    BackgroundTransparency = 1,
    Parent = currencyLeft,
})

local currencyTypes = {
    { key = "Coins", label = "Coins" },
    { key = "Keys", label = "Keys" },
    { key = "Salvage", label = "Salvage" },
}
local selectedCurrencyType = "Coins"
local currencyTypeBtns = {}

for i, currency in ipairs(currencyTypes) do
    local btn = createInstance("TextButton", {
        Name = currency.key .. "Btn",
        Size = UDim2.new(0, 110, 0, 26),
        Position = UDim2.new(0, (i - 1) * 118, 0, 0),
        BackgroundColor3 = (currency.key == selectedCurrencyType) and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE,
        Text = currency.label,
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        Parent = currencyTypeFrame,
    })
    addCorner(btn, 4)
    currencyTypeBtns[currency.key] = btn
end

local currencyAmountInput = createFormField(currencyLeft, "Amount", "e.g. 100", 172)
currencyAmountInput.Name = "CurrencyAmountField"

local currencyRight = createInstance("Frame", {
    Name = "GrantCurrencyRight",
    Size = UDim2.new(0.5, -4, 1, 0),
    Position = UDim2.new(0.5, 4, 0, 0),
    BackgroundColor3 = COLORS.BG_PANEL,
    Parent = currencyPage,
})
addCorner(currencyRight, 8)
addPadding(currencyRight, 12, 12, 12, 12)

createInstance("TextLabel", {
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundTransparency = 1,
    Text = "Currency Grant",
    TextColor3 = COLORS.TEXT_PRIMARY,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = currencyRight,
})

local presetFrame = createInstance("Frame", {
    Name = "CurrencyPresetFrame",
    Size = UDim2.new(1, 0, 0, 34),
    Position = UDim2.new(0, 0, 0, 30),
    BackgroundTransparency = 1,
    Parent = currencyRight,
})

local currencyPresets = {
    { label = "+100 Coins", currencyType = "Coins", amount = 100 },
    { label = "+5 Keys", currencyType = "Keys", amount = 5 },
    { label = "+50 Salvage", currencyType = "Salvage", amount = 50 },
}
local currencyPresetButtons = {}

for i, preset in ipairs(currencyPresets) do
    local btn = createInstance("TextButton", {
        Name = "Preset_" .. preset.currencyType,
        Size = UDim2.new(0, 122, 0, 30),
        Position = UDim2.new(0, (i - 1) * 130, 0, 0),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = preset.label,
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = presetFrame,
    })
    addCorner(btn, 4)
    addStroke(btn, COLORS.BORDER, 1)
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = COLORS.BG_CARD_HOVER end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = COLORS.BG_INPUT end)
    table.insert(currencyPresetButtons, { button = btn, preset = preset })
end

local currencyPreview = createInstance("TextLabel", {
    Name = "CurrencyGrantPreview",
    Size = UDim2.new(1, 0, 0, 116),
    Position = UDim2.new(0, 0, 0, 78),
    BackgroundColor3 = COLORS.BG_INPUT,
    Text = "Choose a target, currency, and amount. Preset buttons fill the form.",
    TextColor3 = COLORS.TEXT_DIM,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = currencyRight,
})
addCorner(currencyPreview, 6)
addPadding(currencyPreview, 8, 8, 8, 8)

local currencyGrantButton = createInstance("TextButton", {
    Name = "GrantCurrencyBtn",
    Size = UDim2.new(1, 0, 0, 40),
    Position = UDim2.new(0, 0, 0, 206),
    BackgroundColor3 = COLORS.GREEN,
    Text = "Grant Currency",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Parent = currencyRight,
})
addCorner(currencyGrantButton, 6)

local currencyStatus = createInstance("TextLabel", {
    Name = "GrantCurrencyStatus",
    Size = UDim2.new(1, 0, 0, 110),
    Position = UDim2.new(0, 0, 0, 258),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = COLORS.GREEN,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = currencyRight,
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
local userDataPage -- forward decl, created later if available
local userDataRPage -- forward decl, created later if available
local function switchTab(tabName)
    searchPage.Visible = (tabName == "Search")
    grantPage.Visible  = (tabName == "Grant")
    currencyPage.Visible = (tabName == "GrantCurrency")
    if userDataPage  then userDataPage.Visible  = (tabName == "UserData")  end
    if userDataRPage then userDataRPage.Visible = (tabName == "UserDataR") end
    searchTab.BackgroundColor3    = (tabName == "Search")    and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    grantTab.BackgroundColor3     = (tabName == "Grant")     and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    grantCurrencyTab.BackgroundColor3 = (tabName == "GrantCurrency") and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    userDataTab.BackgroundColor3  = (tabName == "UserData")  and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    userDataRTab.BackgroundColor3 = (tabName == "UserDataR") and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
end

searchTab.MouseButton1Click:Connect(function() switchTab("Search") end)
grantTab.MouseButton1Click:Connect(function() switchTab("Grant") end)
grantCurrencyTab.MouseButton1Click:Connect(function() switchTab("GrantCurrency") end)
if USER_DATA_AVAILABLE then
    userDataTab.MouseButton1Click:Connect(function() switchTab("UserData") end)
end
if RESTORE_AVAILABLE then
    userDataRTab.MouseButton1Click:Connect(function() switchTab("UserDataR") end)
end

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

--------------------------------------------------------------------------------
-- LOGIC: GRANT CURRENCY
--------------------------------------------------------------------------------
local currencyGrantBusy = false
local MAX_CURRENCY_GRANT = 1000000

local function setCurrencyType(currencyType)
    if not currencyTypeBtns[currencyType] then return end
    selectedCurrencyType = currencyType
    for key, btn in pairs(currencyTypeBtns) do
        btn.BackgroundColor3 = (key == selectedCurrencyType) and COLORS.TAB_ACTIVE or COLORS.TAB_INACTIVE
    end
end

updateCurrencyPreview = function()
    local uid = currencyTargetUserIdInput.Text
    local amount = currencyAmountInput.Text

    local lines = {}
    table.insert(lines, "Target UserId: " .. (uid ~= "" and uid or "(empty)"))
    table.insert(lines, "Currency: " .. tostring(selectedCurrencyType))
    table.insert(lines, "Amount: " .. (amount ~= "" and amount or "(empty)"))
    table.insert(lines, "")
    table.insert(lines, "Click 'Grant Currency' to confirm.")

    currencyPreview.Text = table.concat(lines, "\n")
    currencyPreview.TextColor3 = COLORS.TEXT_SECONDARY
end

for key, btn in pairs(currencyTypeBtns) do
    btn.MouseButton1Click:Connect(function()
        setCurrencyType(key)
        updateCurrencyPreview()
    end)
end

for _, entry in ipairs(currencyPresetButtons) do
    entry.button.MouseButton1Click:Connect(function()
        setCurrencyType(entry.preset.currencyType)
        currencyAmountInput.Text = tostring(entry.preset.amount)
        updateCurrencyPreview()
    end)
end

currencyTargetUserIdInput.FocusLost:Connect(updateCurrencyPreview)
currencyAmountInput.FocusLost:Connect(updateCurrencyPreview)
updateCurrencyPreview()

local function doGrantCurrency()
    if currencyGrantBusy then return end
    currencyGrantBusy = true

    local uid = tonumber(currencyTargetUserIdInput.Text)
    local amount = tonumber(currencyAmountInput.Text)

    if not uid or uid <= 0 then
        currencyStatus.Text = "Invalid Target UserId."
        currencyStatus.TextColor3 = COLORS.RED
        currencyGrantBusy = false
        return
    end
    if not amount or amount <= 0 then
        currencyStatus.Text = "Amount must be positive."
        currencyStatus.TextColor3 = COLORS.RED
        currencyGrantBusy = false
        return
    end

    amount = math.floor(amount)
    if amount <= 0 then
        currencyStatus.Text = "Amount must be at least 1."
        currencyStatus.TextColor3 = COLORS.RED
        currencyGrantBusy = false
        return
    end
    if amount > MAX_CURRENCY_GRANT then
        currencyStatus.Text = "Amount is too large."
        currencyStatus.TextColor3 = COLORS.RED
        currencyGrantBusy = false
        return
    end

    currencyStatus.Text = "Granting currency..."
    currencyStatus.TextColor3 = COLORS.TEXT_DIM
    currencyGrantButton.BackgroundColor3 = COLORS.TAB_INACTIVE

    local ok, result = pcall(function()
        return grantCurrencyRF:InvokeServer(uid, selectedCurrencyType, amount)
    end)

    currencyGrantButton.BackgroundColor3 = COLORS.GREEN
    currencyGrantBusy = false

    if not ok then
        currencyStatus.Text = "Request failed: " .. tostring(result)
        currencyStatus.TextColor3 = COLORS.RED
        return
    end

    if not result or not result.success then
        currencyStatus.Text = "Error: " .. tostring(result and result.error or "Unknown error")
        currencyStatus.TextColor3 = COLORS.RED
        return
    end

    local rec = result.currencyRecord
    if rec then
        currencyStatus.Text = string.format(
            "SUCCESS!\nAdded %d %s to %s (%d)\nBalance: %d -> %d\nTarget was %s.%s",
            rec.Amount or amount,
            rec.CurrencyLabel or selectedCurrencyType,
            rec.TargetUsername or "?",
            rec.TargetUserId or uid,
            rec.PreviousBalance or 0,
            rec.NewBalance or 0,
            rec.WasOnline and "online" or "offline",
            rec.Warning and ("\nWarning: " .. tostring(rec.Warning)) or ""
        )
    else
        currencyStatus.Text = "Currency granted successfully!"
    end
    currencyStatus.TextColor3 = COLORS.GREEN
end

currencyGrantButton.MouseButton1Click:Connect(doGrantCurrency)

--------------------------------------------------------------------------------
-- TAB 4: USER DATA  (saved-player browser + reset controls)
--------------------------------------------------------------------------------
if USER_DATA_AVAILABLE then
    userDataPage = createInstance("Frame", {
        Name = "UserDataPage",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = contentArea,
    })

    ------------------------------------------------------------------
    -- LEFT: saved-player browser
    ------------------------------------------------------------------
    local udLeft = createInstance("Frame", {
        Name = "UD_Left",
        Size = UDim2.new(0.4, -4, 1, 0),
        BackgroundColor3 = COLORS.BG_PANEL,
        Parent = userDataPage,
    })
    addCorner(udLeft, 8)
    addPadding(udLeft, 10, 10, 10, 10)

    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "Saved Players",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = udLeft,
    })

    local udSearchInput = createInstance("TextBox", {
        Name = "UD_SearchInput",
        Size = UDim2.new(1, -78, 0, 30),
        Position = UDim2.new(0, 0, 0, 26),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = "",
        PlaceholderText = "Search username or UserId...",
        TextColor3 = COLORS.TEXT_PRIMARY,
        PlaceholderColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = udLeft,
    })
    addCorner(udSearchInput, 4)
    addPadding(udSearchInput, 0, 0, 8, 8)

    local udSearchBtn = createInstance("TextButton", {
        Name = "UD_SearchBtn",
        Size = UDim2.new(0, 70, 0, 30),
        Position = UDim2.new(1, -70, 0, 26),
        BackgroundColor3 = COLORS.ACCENT,
        Text = "Search",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = udLeft,
    })
    addCorner(udSearchBtn, 4)

    local udStatus = createInstance("TextLabel", {
        Name = "UD_Status",
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 0, 60),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = udLeft,
    })

    local udListScroll = createInstance("ScrollingFrame", {
        Name = "UD_ListScroll",
        Size = UDim2.new(1, 0, 1, -120),
        Position = UDim2.new(0, 0, 0, 80),
        BackgroundTransparency = 1,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COLORS.ACCENT,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = udLeft,
    })
    createInstance("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = udListScroll,
    })

    -- Pagination controls
    local udPageBar = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 1, -32),
        BackgroundTransparency = 1,
        Parent = udLeft,
    })
    local udPrevBtn = createInstance("TextButton", {
        Size = UDim2.new(0, 70, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "< Prev",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = udPageBar,
    })
    addCorner(udPrevBtn, 4)
    local udNextBtn = createInstance("TextButton", {
        Size = UDim2.new(0, 70, 1, 0),
        Position = UDim2.new(1, -70, 0, 0),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "Next >",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = udPageBar,
    })
    addCorner(udNextBtn, 4)
    local udPageLabel = createInstance("TextLabel", {
        Size = UDim2.new(1, -160, 1, 0),
        Position = UDim2.new(0, 80, 0, 0),
        BackgroundTransparency = 1,
        Text = "Page 1",
        TextColor3 = COLORS.TEXT_SECONDARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = udPageBar,
    })

    ------------------------------------------------------------------
    -- RIGHT: selected player data
    ------------------------------------------------------------------
    local udRight = createInstance("Frame", {
        Name = "UD_Right",
        Size = UDim2.new(0.6, -4, 1, 0),
        Position = UDim2.new(0.4, 4, 0, 0),
        BackgroundColor3 = COLORS.BG_PANEL,
        Parent = userDataPage,
    })
    addCorner(udRight, 8)
    addPadding(udRight, 10, 10, 10, 10)

    local udHeader = createInstance("TextLabel", {
        Name = "UD_Header",
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "Select a player to view saved data.",
        TextColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = udRight,
    })

    local udDataScroll = createInstance("ScrollingFrame", {
        Name = "UD_DataScroll",
        Size = UDim2.new(1, 0, 1, -200),
        Position = UDim2.new(0, 0, 0, 30),
        BackgroundTransparency = 1,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COLORS.ACCENT,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = udRight,
    })
    createInstance("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = udDataScroll,
    })

    -- Reset action area (bottom of right panel)
    local udResetArea = createInstance("Frame", {
        Name = "UD_ResetArea",
        Size = UDim2.new(1, 0, 0, 165),
        Position = UDim2.new(0, 0, 1, -165),
        BackgroundColor3 = COLORS.BG_INPUT,
        Visible = false,
        Parent = udRight,
    })
    addCorner(udResetArea, 6)
    addStroke(udResetArea, COLORS.RED, 1)
    addPadding(udResetArea, 8, 8, 8, 8)

    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Text = "DANGEROUS ACTIONS",
        TextColor3 = COLORS.RED,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = udResetArea,
    })

    local resetButtonsFrame = createInstance("Frame", {
        Size = UDim2.new(1, 0, 1, -22),
        Position = UDim2.new(0, 0, 0, 22),
        BackgroundTransparency = 1,
        Parent = udResetArea,
    })
    local resetGrid = createInstance("UIGridLayout", {
        CellSize = UDim2.new(0.5, -4, 0, 36),
        CellPadding = UDim2.new(0, 6, 0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = resetButtonsFrame,
    })

    local resetBtns = {}
    for i, btnSpec in ipairs(AdminUserDataConfig.ResetButtons) do
        local isFull = (btnSpec.id == "Full")
        local btn = createInstance("TextButton", {
            Name = "Reset_" .. btnSpec.id,
            BackgroundColor3 = isFull and Color3.fromRGB(150, 30, 30) or COLORS.RED,
            Text = btnSpec.label,
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            LayoutOrder = i,
            AutoButtonColor = true,
            Parent = resetButtonsFrame,
        })
        addCorner(btn, 4)
        resetBtns[btnSpec.id] = { btn = btn, spec = btnSpec }
    end

    ------------------------------------------------------------------
    -- CONFIRMATION MODAL (sibling overlay on the panel)
    ------------------------------------------------------------------
    local confirmOverlay = createInstance("Frame", {
        Name = "UD_ConfirmOverlay",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.4,
        Visible = false,
        ZIndex = 50,
        Parent = panelFrame,
    })

    local confirmBox = createInstance("Frame", {
        Size = UDim2.new(0, 420, 0, 220),
        Position = UDim2.new(0.5, -210, 0.5, -110),
        BackgroundColor3 = COLORS.BG_DARK,
        ZIndex = 51,
        Parent = confirmOverlay,
    })
    addCorner(confirmBox, 8)
    addStroke(confirmBox, COLORS.RED, 2)
    addPadding(confirmBox, 14, 14, 14, 14)

    local confirmTitle = createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "Confirm Reset",
        TextColor3 = COLORS.RED,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 52,
        Parent = confirmBox,
    })

    local confirmBody = createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 90),
        Position = UDim2.new(0, 0, 0, 28),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 52,
        Parent = confirmBox,
    })

    local confirmTypeBox = createInstance("TextBox", {
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 122),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = "",
        PlaceholderText = "Type RESET to enable Confirm",
        TextColor3 = COLORS.TEXT_PRIMARY,
        PlaceholderColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
        Visible = false,
        ZIndex = 52,
        Parent = confirmBox,
    })
    addCorner(confirmTypeBox, 4)
    addPadding(confirmTypeBox, 0, 0, 8, 8)

    local confirmCancel = createInstance("TextButton", {
        Size = UDim2.new(0, 120, 0, 34),
        Position = UDim2.new(0, 0, 1, -34),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "Cancel",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        ZIndex = 52,
        Parent = confirmBox,
    })
    addCorner(confirmCancel, 4)

    local confirmOk = createInstance("TextButton", {
        Size = UDim2.new(0, 160, 0, 34),
        Position = UDim2.new(1, -160, 1, -34),
        BackgroundColor3 = COLORS.RED,
        Text = "Confirm",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        ZIndex = 52,
        Parent = confirmBox,
    })
    addCorner(confirmOk, 4)

    ------------------------------------------------------------------
    -- USER DATA: STATE + RENDERING
    ------------------------------------------------------------------
    local currentPage      = 1
    local hasNextPage      = false
    local selectedUserId   = nil
    local selectedSnapshot = nil
    local udBusy           = false

    local function clearListRows()
        for _, child in ipairs(udListScroll:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
        end
    end

    local function clearDataView()
        for _, child in ipairs(udDataScroll:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
        end
    end

    local function setSelectionEmpty(reason)
        selectedUserId = nil
        selectedSnapshot = nil
        udHeader.Text = reason or "Select a player to view saved data."
        udHeader.TextColor3 = COLORS.TEXT_DIM
        clearDataView()
        udResetArea.Visible = false
    end

    local function fmtTime(t)
        if not t or t == 0 then return "N/A" end
        local ok, s = pcall(function() return os.date("%Y-%m-%d %H:%M", t) end)
        return ok and s or "N/A"
    end

    local function safeNum(v) if type(v) == "number" then return tostring(v) end return "N/A" end
    local function safeStr(v)
        if v == nil then return "N/A" end
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return tostring(v) end
        return "(table)"
    end

    -- Recursively serialize a Lua table into a sorted, JSON-ish string for the
    -- raw data section. Bounded depth to avoid runaway prints.
    local function serialize(value, depth, maxDepth)
        depth = depth or 0
        maxDepth = maxDepth or 6
        if depth > maxDepth then return '"<max depth>"' end
        local t = type(value)
        if t == "nil" then return "null" end
        if t == "boolean" then return tostring(value) end
        if t == "number" then return tostring(value) end
        if t == "string" then return string.format("%q", value) end
        if t == "table" then
            local keys = {}
            for k in pairs(value) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            if #keys == 0 then return "{}" end
            local parts = {}
            local indent = string.rep("  ", depth + 1)
            local closeIndent = string.rep("  ", depth)
            for _, k in ipairs(keys) do
                table.insert(parts, string.format("%s%q: %s", indent, tostring(k), serialize(value[k], depth + 1, maxDepth)))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. closeIndent .. "}"
        end
        return string.format("%q", "<" .. t .. ">")
    end

    local function makeSection(title, order)
        local frame = createInstance("Frame", {
            Name = "Section_" .. title,
            Size = UDim2.new(1, 0, 0, 28),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = COLORS.BG_CARD,
            LayoutOrder = order,
            Parent = udDataScroll,
        })
        addCorner(frame, 6)
        addPadding(frame, 8, 8, 10, 10)
        createInstance("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = frame,
        })
        createInstance("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = COLORS.ACCENT,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 0,
            Parent = frame,
        })
        return frame
    end

    local function addRow(parent, label, value, order)
        createInstance("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            RichText = true,
            Text = string.format(
                '<font color="rgb(%d,%d,%d)">%s:</font>  %s',
                math.floor(COLORS.TEXT_SECONDARY.R * 255),
                math.floor(COLORS.TEXT_SECONDARY.G * 255),
                math.floor(COLORS.TEXT_SECONDARY.B * 255),
                tostring(label),
                tostring(value or "N/A")
            ),
            TextColor3 = COLORS.TEXT_PRIMARY,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = order or 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = parent,
        })
    end

    -- Count keys in a table-as-set / table-as-array.
    local function countKeys(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    local function renderDataView(snap)
        clearDataView()
        local d = snap.data or {}
        local order = 0
        local function nextOrder() order = order + 1; return order end

        -- Identity
        do
            local s = makeSection("Identity", nextOrder())
            addRow(s, "Username",    snap.username,    1)
            addRow(s, "DisplayName", snap.displayName, 2)
            addRow(s, "UserId",      tostring(snap.userId), 3)
            addRow(s, "Online",      snap.isOnline and "yes" or "no", 4)
            addRow(s, "First Seen",  fmtTime(snap.firstSeen), 5)
            addRow(s, "Last Seen",   fmtTime(snap.lastSeen),  6)
        end

        -- Currency
        do
            local s = makeSection("Currency", nextOrder())
            addRow(s, "Coins",   safeNum(d.Coins),   1)
            addRow(s, "Keys",    safeNum(d.Keys),    2)
            addRow(s, "Salvage", safeNum(d.Salvage), 3)
        end

        -- Progression
        do
            local s = makeSection("Progression", nextOrder())
            local xp = d.XP
            if type(xp) == "table" then
                addRow(s, "Level",    safeNum(xp.Level),   1)
                addRow(s, "XP",       safeNum(xp.XP),      2)
                addRow(s, "Total XP", safeNum(xp.TotalXP), 3)
            else
                addRow(s, "Level",    "N/A", 1)
                addRow(s, "XP",       "N/A", 2)
                addRow(s, "Total XP", "N/A", 3)
            end
            local up = d.Upgrades
            if type(up) == "table" then
                local i = 4
                for k, v in pairs(up) do
                    addRow(s, "Upgrade: " .. tostring(k), safeStr(v), i); i = i + 1
                end
            else
                addRow(s, "Upgrades", "N/A", 4)
            end
        end

        -- Inventory
        do
            local s = makeSection("Inventory", nextOrder())
            local weapons = d.Weapons
            addRow(s, "Owned Weapons", weapons and tostring(countKeys(weapons)) or "N/A", 1)
            local skins = d.Skins
            if type(skins) == "table" then
                addRow(s, "Owned Skins",    tostring(countKeys(skins.owned or {})), 2)
                addRow(s, "Equipped Skin",  safeStr(skins.equipped),                3)
            else
                addRow(s, "Owned Skins",   "N/A", 2)
                addRow(s, "Equipped Skin", "N/A", 3)
            end
            local effects = d.Effects
            if type(effects) == "table" then
                addRow(s, "Owned Effects", tostring(countKeys(effects.owned or {})), 4)
            else
                addRow(s, "Owned Effects", "N/A", 4)
            end
            local emotes = d.Emotes
            if type(emotes) == "table" then
                addRow(s, "Owned Emotes", tostring(countKeys(emotes.owned or {})), 5)
            else
                addRow(s, "Owned Emotes", "N/A", 5)
            end
            local lo = d.Loadout
            if type(lo) == "table" then
                addRow(s, "Equipped Melee",  safeStr(lo.melee  or lo.meleeInstanceId),  6)
                addRow(s, "Equipped Ranged", safeStr(lo.ranged or lo.rangedInstanceId), 7)
            else
                addRow(s, "Loadout", "N/A", 6)
            end
        end

        -- Quests
        do
            local s = makeSection("Quests", nextOrder())
            local dq = d.DailyQuests
            if type(dq) == "table" then
                addRow(s, "Daily day",     safeStr(dq.day), 1)
                addRow(s, "Daily quests",  tostring(countKeys(dq.quests or {})), 2)
            else
                addRow(s, "Daily Quests", "N/A", 1)
            end
            local wq = d.WeeklyQuests
            if type(wq) == "table" then
                addRow(s, "Weekly week",    safeStr(wq.weekKey), 3)
                addRow(s, "Weekly quests",  tostring(countKeys(wq.quests or {})), 4)
            else
                addRow(s, "Weekly Quests", "N/A", 3)
            end
        end

        -- Achievements
        do
            local s = makeSection("Achievements", nextOrder())
            local ach = d.Achievements
            if type(ach) == "table" then
                addRow(s, "Achievement Points", safeNum(ach.achievementPoints), 1)
                addRow(s, "Tracked",            tostring(countKeys(ach.achievements or {})), 2)
                if type(ach.stats) == "table" then
                    addRow(s, "Total Eliminations", safeNum(ach.stats.totalElims), 3)
                    addRow(s, "Best Elim Streak",   safeNum(ach.stats.bestElimStreak), 4)
                end
            else
                addRow(s, "Achievement data", "N/A", 1)
            end
        end

        -- Login / Streak
        do
            local s = makeSection("Login/Streak", nextOrder())
            local dr = d.DailyRewards
            if type(dr) == "table" then
                addRow(s, "Current Streak", safeNum(dr.currentStreak), 1)
                addRow(s, "Cycle Day",      safeNum(dr.currentDay),    2)
                addRow(s, "Total Claims",   safeNum(dr.totalClaims),   3)
                addRow(s, "Last Claim",     fmtTime(dr.lastClaimTime), 4)
            else
                addRow(s, "Daily Rewards", "N/A", 1)
            end
        end

        -- Career
        do
            local s = makeSection("Career", nextOrder())
            local cs = d.CareerStats
            if type(cs) == "table" and type(cs.stats) == "table" then
                local i = 1
                local keys = {}
                for k in pairs(cs.stats) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    addRow(s, k, safeStr(cs.stats[k]), i); i = i + 1
                end
            else
                addRow(s, "Career stats", "N/A", 1)
            end
        end

        -- Raw Data (collapsible)
        do
            local s = makeSection("Raw Data", nextOrder())
            local toggle = createInstance("TextButton", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = COLORS.TAB_INACTIVE,
                Text = "Show Raw Data",
                TextColor3 = COLORS.TEXT_PRIMARY,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                LayoutOrder = 1,
                Parent = s,
            })
            addCorner(toggle, 4)

            local rawScroll = createInstance("ScrollingFrame", {
                Size = UDim2.new(1, 0, 0, 220),
                BackgroundColor3 = COLORS.BG_DARK,
                BorderSizePixel = 0,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = COLORS.ACCENT,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                Visible = false,
                LayoutOrder = 2,
                Parent = s,
            })
            addCorner(rawScroll, 4)
            local rawLabel = createInstance("TextLabel", {
                Size = UDim2.new(1, -8, 0, 0),
                Position = UDim2.new(0, 4, 0, 4),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = COLORS.TEXT_PRIMARY,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                AutomaticSize = Enum.AutomaticSize.Y,
                TextWrapped = false,
                Parent = rawScroll,
            })
            local rawRendered = false
            toggle.MouseButton1Click:Connect(function()
                if not rawScroll.Visible then
                    if not rawRendered then
                        local ok, str = pcall(function() return serialize(d) end)
                        rawLabel.Text = ok and str or "(serialize error)"
                        rawRendered = true
                    end
                    rawScroll.Visible = true
                    toggle.Text = "Hide Raw Data"
                else
                    rawScroll.Visible = false
                    toggle.Text = "Show Raw Data"
                end
            end)
        end
    end

    local function setHeaderForSelection(snap)
        udHeader.Text = string.format("%s (@%s)  •  UserId %d  %s",
            snap.displayName or "?", snap.username or "?", snap.userId or 0,
            snap.isOnline and "[ONLINE]" or "")
        udHeader.TextColor3 = snap.isOnline and COLORS.GREEN or COLORS.TEXT_PRIMARY
    end

    local function loadSelectedUser(userId)
        if not userId then return end
        if udBusy then return end
        udBusy = true
        udHeader.Text = "Loading data for UserId " .. tostring(userId) .. "..."
        udHeader.TextColor3 = COLORS.TEXT_DIM
        clearDataView()
        udResetArea.Visible = false

        local ok, result = pcall(function() return getUserRF:InvokeServer(userId) end)
        udBusy = false

        if not ok or not result or not result.success then
            local msg = (result and result.error) or tostring(result) or "Unknown error"
            setSelectionEmpty("Failed to load: " .. msg)
            return
        end

        selectedUserId = result.userId
        selectedSnapshot = result
        setHeaderForSelection(result)
        renderDataView(result)
        udResetArea.Visible = true
    end

    local function buildPlayerCard(entry, order)
        local card = createInstance("TextButton", {
            Name = "Card_" .. tostring(entry.userId),
            Size = UDim2.new(1, 0, 0, 42),
            BackgroundColor3 = COLORS.BG_CARD,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = udListScroll,
        })
        addCorner(card, 4)

        createInstance("TextLabel", {
            Size = UDim2.new(1, -50, 0, 18),
            Position = UDim2.new(0, 8, 0, 4),
            BackgroundTransparency = 1,
            Text = string.format("%s (@%s)",
                tostring(entry.displayName or entry.username or "?"),
                tostring(entry.username or "?")),
            TextColor3 = COLORS.TEXT_PRIMARY,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = card,
        })
        createInstance("TextLabel", {
            Size = UDim2.new(1, -50, 0, 14),
            Position = UDim2.new(0, 8, 0, 22),
            BackgroundTransparency = 1,
            Text = "UserId " .. tostring(entry.userId)
                .. (entry.lastSeen and entry.lastSeen > 0 and ("  •  seen " .. fmtTime(entry.lastSeen)) or "")
                .. (entry.unindexed and "  •  not indexed" or ""),
            TextColor3 = COLORS.TEXT_SECONDARY,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = card,
        })
        if entry.isOnline then
            local dot = createInstance("Frame", {
                Size = UDim2.new(0, 10, 0, 10),
                Position = UDim2.new(1, -16, 0, 6),
                BackgroundColor3 = COLORS.GREEN,
                BorderSizePixel = 0,
                Parent = card,
            })
            addCorner(dot, 5)
            createInstance("TextLabel", {
                Size = UDim2.new(0, 50, 0, 14),
                Position = UDim2.new(1, -56, 0, 22),
                BackgroundTransparency = 1,
                Text = "ONLINE",
                TextColor3 = COLORS.GREEN,
                Font = Enum.Font.GothamBold,
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = card,
            })
        end

        card.MouseEnter:Connect(function() card.BackgroundColor3 = COLORS.BG_CARD_HOVER end)
        card.MouseLeave:Connect(function() card.BackgroundColor3 = COLORS.BG_CARD end)
        card.MouseButton1Click:Connect(function() loadSelectedUser(entry.userId) end)
    end

    local function loadPlayerListPage(page)
        if udBusy then return end
        udBusy = true
        clearListRows()
        udStatus.Text = "Loading page " .. tostring(page) .. "..."
        udStatus.TextColor3 = COLORS.TEXT_DIM

        local ok, result = pcall(function()
            return getSavedRF:InvokeServer(page, AdminUserDataConfig.PageSize)
        end)
        udBusy = false

        if not ok or not result or not result.success then
            udStatus.Text = "Error: " .. tostring(result and result.error or result or "?")
            udStatus.TextColor3 = COLORS.RED
            return
        end

        local entries = result.entries or {}
        if #entries == 0 then
            udStatus.Text = "No saved players found."
            udStatus.TextColor3 = COLORS.TEXT_DIM
        else
            udStatus.Text = string.format("%d player(s) on page", #entries)
            udStatus.TextColor3 = COLORS.GREEN
            for i, entry in ipairs(entries) do buildPlayerCard(entry, i) end
        end

        currentPage = result.page or page
        hasNextPage = result.hasNextPage == true
        udPageLabel.Text = "Page " .. tostring(currentPage)
        udPrevBtn.AutoButtonColor = currentPage > 1
        udNextBtn.AutoButtonColor = hasNextPage
    end

    local function doManualSearch()
        local q = udSearchInput.Text or ""
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then
            loadPlayerListPage(1)
            return
        end
        if udBusy then return end
        udBusy = true
        clearListRows()
        udStatus.Text = "Searching..."
        udStatus.TextColor3 = COLORS.TEXT_DIM

        local ok, result = pcall(function() return searchSavedRF:InvokeServer(q) end)
        udBusy = false

        if not ok or not result or not result.success then
            udStatus.Text = "Error: " .. tostring(result and result.error or result or "?")
            udStatus.TextColor3 = COLORS.RED
            return
        end

        local entries = result.entries or {}
        if #entries == 0 then
            udStatus.Text = "No saved players found."
            udStatus.TextColor3 = COLORS.TEXT_DIM
            return
        end
        udStatus.Text = string.format("%d match(es)", #entries)
        udStatus.TextColor3 = COLORS.GREEN
        for i, entry in ipairs(entries) do buildPlayerCard(entry, i) end
        if #entries == 1 then loadSelectedUser(entries[1].userId) end
    end

    udSearchBtn.MouseButton1Click:Connect(doManualSearch)
    udSearchInput.FocusLost:Connect(function(enter) if enter then doManualSearch() end end)
    udPrevBtn.MouseButton1Click:Connect(function()
        if currentPage > 1 then loadPlayerListPage(currentPage - 1) end
    end)
    udNextBtn.MouseButton1Click:Connect(function()
        if hasNextPage then loadPlayerListPage(currentPage + 1) end
    end)

    ------------------------------------------------------------------
    -- RESET CONFIRMATION FLOW
    ------------------------------------------------------------------
    local activeReset = nil -- { id = "Currency"/.../"Full" }

    local function hideConfirm()
        confirmOverlay.Visible = false
        confirmTypeBox.Visible = false
        confirmTypeBox.Text = ""
        confirmOk.BackgroundColor3 = COLORS.RED
        confirmOk.AutoButtonColor = true
        activeReset = nil
    end

    local function refreshConfirmOkEnabled()
        if activeReset and activeReset.id == "Full" then
            local typed = (confirmTypeBox.Text or "")
            if typed == "RESET" then
                confirmOk.BackgroundColor3 = COLORS.RED
                confirmOk.AutoButtonColor = true
                confirmOk.TextColor3 = Color3.new(1, 1, 1)
            else
                confirmOk.BackgroundColor3 = COLORS.TAB_INACTIVE
                confirmOk.AutoButtonColor = false
                confirmOk.TextColor3 = COLORS.TEXT_DIM
            end
        end
    end

    confirmTypeBox:GetPropertyChangedSignal("Text"):Connect(refreshConfirmOkEnabled)

    local function showConfirm(resetId, spec)
        if not selectedSnapshot or not selectedUserId then return end
        activeReset = { id = resetId, spec = spec }
        confirmTitle.Text = spec.label
        local who = string.format("%s (%d)", selectedSnapshot.username or "?", selectedUserId)
        local body = string.format(
            "Are you sure you want to reset %s data for %s? This cannot be undone.\n\nDetails: %s",
            spec.id == "Full" and "ALL" or spec.id, who, spec.desc or ""
        )
        if selectedSnapshot.isOnline then
            body = body .. "\n\nThis player is ONLINE."
            if spec.id == "Full" then
                body = body .. " They will be kicked to reload defaults."
            elseif spec.id == "Currency" then
                body = body .. " Their currency UI will refresh live."
            else
                body = body .. " They will be kicked so the reset isn't overwritten on save."
            end
        end
        confirmBody.Text = body

        if spec.id == "Full" then
            confirmTypeBox.Visible = true
            confirmTypeBox.Text = ""
            refreshConfirmOkEnabled()
        else
            confirmTypeBox.Visible = false
            confirmOk.BackgroundColor3 = COLORS.RED
            confirmOk.AutoButtonColor = true
            confirmOk.TextColor3 = Color3.new(1, 1, 1)
        end

        confirmOverlay.Visible = true
    end

    for resetId, info in pairs(resetBtns) do
        info.btn.MouseButton1Click:Connect(function()
            showConfirm(resetId, info.spec)
        end)
    end

    confirmCancel.MouseButton1Click:Connect(hideConfirm)

    confirmOk.MouseButton1Click:Connect(function()
        if not activeReset or not selectedUserId then return end
        if not confirmOk.AutoButtonColor then return end -- disabled (Full without typed RESET)
        if udBusy then return end

        local resetId = activeReset.id
        local targetUserId = selectedUserId
        udBusy = true
        confirmOk.Text = "Working..."
        confirmOk.AutoButtonColor = false

        local ok, result = pcall(function()
            return resetUserRF:InvokeServer(targetUserId, resetId)
        end)

        udBusy = false
        confirmOk.Text = "Confirm"

        if not ok or not result or not result.success then
            confirmBody.Text = "ERROR: " .. tostring(result and result.error or result or "?")
            confirmBody.TextColor3 = COLORS.RED
            confirmOk.AutoButtonColor = true
            return
        end

        -- Build a status message
        local lines = {
            "Reset OK: " .. resetId,
            "Wiped: " .. table.concat(result.wiped or {}, ", "),
        }
        if result.failed and #result.failed > 0 then
            table.insert(lines, "Failed: " .. table.concat(result.failed, ", "))
        end
        if result.backupOk then
            table.insert(lines, "Backup: " .. tostring(result.backupKey))
        else
            table.insert(lines, "Backup: FAILED (no snapshot stored)")
        end
        if result.wasOnline then
            if result.kicked then
                table.insert(lines, "Player was online and has been kicked to refresh.")
            elseif result.liveRefreshed and #result.liveRefreshed > 0 then
                table.insert(lines, "Live-refreshed: " .. table.concat(result.liveRefreshed, ", "))
            end
            if result.needsRejoinForFull then
                table.insert(lines, "Note: player must rejoin for full refresh.")
            end
        end
        confirmBody.Text = table.concat(lines, "\n")
        confirmBody.TextColor3 = COLORS.GREEN
        confirmOk.Text = "Close"
        confirmOk.AutoButtonColor = true

        -- Re-bind confirm to close, then reload data view.
        local conn
        conn = confirmOk.MouseButton1Click:Connect(function()
            if conn then conn:Disconnect(); conn = nil end
            hideConfirm()
            -- If player wasn't kicked / still selected, reload their snapshot.
            if not result.kicked then
                loadSelectedUser(targetUserId)
            else
                setSelectionEmpty("Player kicked. Select another player.")
            end
        end)
    end)

    -- Initial load when the panel first opens with the user-data tab.
    local userDataLoaded = false
    userDataTab.MouseButton1Click:Connect(function()
        if not userDataLoaded then
            userDataLoaded = true
            loadPlayerListPage(1)
        end
    end)
end -- USER_DATA_AVAILABLE

--------------------------------------------------------------------------------
-- TAB 5: USER DATA (R)  (reset history + restore)
--------------------------------------------------------------------------------
if RESTORE_AVAILABLE then
    userDataRPage = createInstance("Frame", {
        Name = "UserDataRPage",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = contentArea,
    })

    ------------------------------------------------------------------
    -- LEFT: reset-history browser
    ------------------------------------------------------------------
    local rLeft = createInstance("Frame", {
        Name = "R_Left",
        Size = UDim2.new(0.4, -4, 1, 0),
        BackgroundColor3 = COLORS.BG_PANEL,
        Parent = userDataRPage,
    })
    addCorner(rLeft, 8)
    addPadding(rLeft, 10, 10, 10, 10)

    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "Reset History",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = rLeft,
    })

    local rSearchInput = createInstance("TextBox", {
        Size = UDim2.new(1, -78, 0, 30),
        Position = UDim2.new(0, 0, 0, 26),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = "",
        PlaceholderText = "Search username or UserId...",
        TextColor3 = COLORS.TEXT_PRIMARY,
        PlaceholderColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = rLeft,
    })
    addCorner(rSearchInput, 4)
    addPadding(rSearchInput, 0, 0, 8, 8)

    local rSearchBtn = createInstance("TextButton", {
        Size = UDim2.new(0, 70, 0, 30),
        Position = UDim2.new(1, -70, 0, 26),
        BackgroundColor3 = COLORS.ACCENT,
        Text = "Search",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = rLeft,
    })
    addCorner(rSearchBtn, 4)

    local rStatus = createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 0, 60),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = rLeft,
    })

    local rListScroll = createInstance("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -120),
        Position = UDim2.new(0, 0, 0, 80),
        BackgroundTransparency = 1,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COLORS.ACCENT,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = rLeft,
    })
    createInstance("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = rListScroll,
    })

    local rPageBar = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 1, -32),
        BackgroundTransparency = 1,
        Parent = rLeft,
    })
    local rPrevBtn = createInstance("TextButton", {
        Size = UDim2.new(0, 70, 1, 0),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "< Prev",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = rPageBar,
    })
    addCorner(rPrevBtn, 4)
    local rNextBtn = createInstance("TextButton", {
        Size = UDim2.new(0, 70, 1, 0),
        Position = UDim2.new(1, -70, 0, 0),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "Next >",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = rPageBar,
    })
    addCorner(rNextBtn, 4)
    local rPageLabel = createInstance("TextLabel", {
        Size = UDim2.new(1, -160, 1, 0),
        Position = UDim2.new(0, 80, 0, 0),
        BackgroundTransparency = 1,
        Text = "Page 1",
        TextColor3 = COLORS.TEXT_SECONDARY,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        Parent = rPageBar,
    })

    ------------------------------------------------------------------
    -- RIGHT: backup details + restore controls
    ------------------------------------------------------------------
    local rRight = createInstance("Frame", {
        Size = UDim2.new(0.6, -4, 1, 0),
        Position = UDim2.new(0.4, 4, 0, 0),
        BackgroundColor3 = COLORS.BG_PANEL,
        Parent = userDataRPage,
    })
    addCorner(rRight, 8)
    addPadding(rRight, 10, 10, 10, 10)

    local rHeader = createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "Select a reset record to view backup details.",
        TextColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = rRight,
    })

    local rDataScroll = createInstance("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -90),
        Position = UDim2.new(0, 0, 0, 30),
        BackgroundTransparency = 1,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = COLORS.ACCENT,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = rRight,
    })
    createInstance("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = rDataScroll,
    })

    -- Restore action area at the bottom of the right panel.
    local rRestoreArea = createInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 54),
        Position = UDim2.new(0, 0, 1, -54),
        BackgroundColor3 = COLORS.BG_INPUT,
        Visible = false,
        Parent = rRight,
    })
    addCorner(rRestoreArea, 6)
    addStroke(rRestoreArea, COLORS.RED, 2)
    addPadding(rRestoreArea, 8, 8, 10, 10)

    local rRestoreBtn = createInstance("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(150, 30, 30),
        Text = "Restore This Backup",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        AutoButtonColor = true,
        Parent = rRestoreArea,
    })
    addCorner(rRestoreBtn, 4)

    ------------------------------------------------------------------
    -- RESTORE CONFIRMATION MODAL (separate from reset modal)
    ------------------------------------------------------------------
    local restoreOverlay = createInstance("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.4,
        Visible = false,
        ZIndex = 60,
        Parent = panelFrame,
    })
    local restoreBox = createInstance("Frame", {
        Size = UDim2.new(0, 440, 0, 240),
        Position = UDim2.new(0.5, -220, 0.5, -120),
        BackgroundColor3 = COLORS.BG_DARK,
        ZIndex = 61,
        Parent = restoreOverlay,
    })
    addCorner(restoreBox, 8)
    addStroke(restoreBox, COLORS.RED, 2)
    addPadding(restoreBox, 14, 14, 14, 14)

    createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        Text = "Confirm Restore",
        TextColor3 = COLORS.RED,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 62,
        Parent = restoreBox,
    })
    local restoreBody = createInstance("TextLabel", {
        Size = UDim2.new(1, 0, 0, 110),
        Position = UDim2.new(0, 0, 0, 28),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 62,
        Parent = restoreBox,
    })
    local restoreTypeBox = createInstance("TextBox", {
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.new(0, 0, 0, 142),
        BackgroundColor3 = COLORS.BG_INPUT,
        Text = "",
        PlaceholderText = "Type RESTORE to enable Confirm",
        TextColor3 = COLORS.TEXT_PRIMARY,
        PlaceholderColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
        ZIndex = 62,
        Parent = restoreBox,
    })
    addCorner(restoreTypeBox, 4)
    addPadding(restoreTypeBox, 0, 0, 8, 8)

    local restoreCancel = createInstance("TextButton", {
        Size = UDim2.new(0, 120, 0, 34),
        Position = UDim2.new(0, 0, 1, -34),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "Cancel",
        TextColor3 = COLORS.TEXT_PRIMARY,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        ZIndex = 62,
        Parent = restoreBox,
    })
    addCorner(restoreCancel, 4)
    local restoreOk = createInstance("TextButton", {
        Size = UDim2.new(0, 180, 0, 34),
        Position = UDim2.new(1, -180, 1, -34),
        BackgroundColor3 = COLORS.TAB_INACTIVE,
        Text = "Confirm Restore",
        TextColor3 = COLORS.TEXT_DIM,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
        ZIndex = 62,
        Parent = restoreBox,
    })
    addCorner(restoreOk, 4)

    ------------------------------------------------------------------
    -- STATE + RENDERING
    ------------------------------------------------------------------
    local rPage          = 1
    local rHasNextPage   = false
    local rSelectedRecord = nil
    local rBusy          = false

    local function rFmtTime(t)
        if not t or t == 0 then return "N/A" end
        local ok, s = pcall(function() return os.date("%Y-%m-%d %H:%M:%S", t) end)
        return ok and s or "N/A"
    end

    local function rSafe(v)
        if v == nil then return "N/A" end
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return tostring(v) end
        return "(table)"
    end

    local function rCountKeys(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    local function rSerialize(value, depth, maxDepth)
        depth = depth or 0
        maxDepth = maxDepth or 6
        if depth > maxDepth then return '"<max depth>"' end
        local t = type(value)
        if t == "nil" then return "null" end
        if t == "boolean" or t == "number" then return tostring(value) end
        if t == "string" then return string.format("%q", value) end
        if t == "table" then
            local keys = {}
            for k in pairs(value) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            if #keys == 0 then return "{}" end
            local parts = {}
            local indent = string.rep("  ", depth + 1)
            local closeIndent = string.rep("  ", depth)
            for _, k in ipairs(keys) do
                table.insert(parts, string.format("%s%q: %s", indent, tostring(k), rSerialize(value[k], depth + 1, maxDepth)))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. closeIndent .. "}"
        end
        return string.format("%q", "<" .. t .. ">")
    end

    local function rClearList()
        for _, child in ipairs(rListScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
    end

    local function rClearData()
        for _, child in ipairs(rDataScroll:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
        end
    end

    local function rSection(title, order)
        local frame = createInstance("Frame", {
            Size = UDim2.new(1, 0, 0, 28),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = COLORS.BG_CARD,
            LayoutOrder = order,
            Parent = rDataScroll,
        })
        addCorner(frame, 6)
        addPadding(frame, 8, 8, 10, 10)
        createInstance("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = frame,
        })
        createInstance("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = COLORS.ACCENT,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 0,
            Parent = frame,
        })
        return frame
    end

    local function rRow(parent, label, value, order)
        createInstance("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            RichText = true,
            Text = string.format(
                '<font color="rgb(%d,%d,%d)">%s:</font>  %s',
                math.floor(COLORS.TEXT_SECONDARY.R * 255),
                math.floor(COLORS.TEXT_SECONDARY.G * 255),
                math.floor(COLORS.TEXT_SECONDARY.B * 255),
                tostring(label), tostring(value or "N/A")
            ),
            TextColor3 = COLORS.TEXT_PRIMARY,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
            LayoutOrder = order or 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = parent,
        })
    end

    local function rRefreshRestoreButton()
        if not rSelectedRecord then
            rRestoreArea.Visible = false
            return
        end
        rRestoreArea.Visible = true
        if rSelectedRecord.restored then
            rRestoreBtn.Text = "This backup has already been restored."
            rRestoreBtn.BackgroundColor3 = COLORS.TAB_INACTIVE
            rRestoreBtn.AutoButtonColor = false
            rRestoreBtn.TextColor3 = COLORS.TEXT_DIM
        else
            rRestoreBtn.Text = "Restore This Backup"
            rRestoreBtn.BackgroundColor3 = Color3.fromRGB(150, 30, 30)
            rRestoreBtn.AutoButtonColor = true
            rRestoreBtn.TextColor3 = Color3.new(1, 1, 1)
        end
    end

    local function rRenderBackup(rec)
        rClearData()
        local prev = rec.previousData or {}
        local order = 0
        local function nextOrder() order = order + 1; return order end

        -- Identity / metadata
        do
            local s = rSection("Backup Summary", nextOrder())
            rRow(s, "Backup Id",      rSafe(rec.backupId),      1)
            rRow(s, "Target Username", rSafe(rec.targetUsername), 2)
            rRow(s, "Target DisplayName", rSafe(rec.targetDisplayName), 3)
            rRow(s, "Target UserId",  rSafe(rec.targetUserId),  4)
            rRow(s, "Reset Type",     rSafe(rec.resetType),     5)
            rRow(s, "Performed By",   string.format("%s (%s)", rSafe(rec.adminUsername), rSafe(rec.adminUserId)), 6)
            rRow(s, "Performed At",   rFmtTime(rec.timestamp),  7)
            rRow(s, "Restored",       rec.restored and "YES" or "no", 8)
            if rec.restored then
                rRow(s, "Restored By",   string.format("%s (%s)", rSafe(rec.restoredByUsername), rSafe(rec.restoredByUserId)), 9)
                rRow(s, "Restored At",   rFmtTime(rec.restoredAt), 10)
            end
        end

        do
            local s = rSection("Previous Currency", nextOrder())
            rRow(s, "Coins",   rSafe(prev.Coins),   1)
            rRow(s, "Keys",    rSafe(prev.Keys),    2)
            rRow(s, "Salvage", rSafe(prev.Salvage), 3)
        end

        do
            local s = rSection("Previous Progression", nextOrder())
            local xp = prev.XP
            if type(xp) == "table" then
                rRow(s, "Level",    rSafe(xp.Level),   1)
                rRow(s, "XP",       rSafe(xp.XP),      2)
                rRow(s, "Total XP", rSafe(xp.TotalXP), 3)
            else
                rRow(s, "Level",    "N/A", 1)
                rRow(s, "XP",       "N/A", 2)
                rRow(s, "Total XP", "N/A", 3)
            end
            local up = prev.Upgrades
            if type(up) == "table" then
                local i = 4
                for k, v in pairs(up) do rRow(s, "Upgrade: " .. tostring(k), rSafe(v), i); i = i + 1 end
            else
                rRow(s, "Upgrades", "N/A", 4)
            end
        end

        do
            local s = rSection("Previous Inventory", nextOrder())
            rRow(s, "Owned Weapons", prev.Weapons and tostring(rCountKeys(prev.Weapons)) or "N/A", 1)
            local skins = prev.Skins
            if type(skins) == "table" then
                rRow(s, "Owned Skins",   tostring(rCountKeys(skins.owned or {})), 2)
                rRow(s, "Equipped Skin", rSafe(skins.equipped),                   3)
            else
                rRow(s, "Skins", "N/A", 2)
            end
            local effects = prev.Effects
            if type(effects) == "table" then
                rRow(s, "Owned Effects", tostring(rCountKeys(effects.owned or {})), 4)
            else
                rRow(s, "Effects", "N/A", 4)
            end
            local emotes = prev.Emotes
            if type(emotes) == "table" then
                rRow(s, "Owned Emotes", tostring(rCountKeys(emotes.owned or {})), 5)
            else
                rRow(s, "Emotes", "N/A", 5)
            end
            local lo = prev.Loadout
            if type(lo) == "table" then
                rRow(s, "Equipped Melee",  rSafe(lo.melee  or lo.meleeInstanceId),  6)
                rRow(s, "Equipped Ranged", rSafe(lo.ranged or lo.rangedInstanceId), 7)
            else
                rRow(s, "Loadout", "N/A", 6)
            end
        end

        do
            local s = rSection("Previous Quests", nextOrder())
            local dq = prev.DailyQuests
            if type(dq) == "table" then
                rRow(s, "Daily day",    rSafe(dq.day), 1)
                rRow(s, "Daily quests", tostring(rCountKeys(dq.quests or {})), 2)
            else
                rRow(s, "Daily Quests", "N/A", 1)
            end
            local wq = prev.WeeklyQuests
            if type(wq) == "table" then
                rRow(s, "Weekly week",    rSafe(wq.weekKey), 3)
                rRow(s, "Weekly quests",  tostring(rCountKeys(wq.quests or {})), 4)
            else
                rRow(s, "Weekly Quests", "N/A", 3)
            end
        end

        do
            local s = rSection("Previous Achievements", nextOrder())
            local ach = prev.Achievements
            if type(ach) == "table" then
                rRow(s, "Achievement Points", rSafe(ach.achievementPoints), 1)
                rRow(s, "Tracked",            tostring(rCountKeys(ach.achievements or {})), 2)
            else
                rRow(s, "Achievements", "N/A", 1)
            end
        end

        -- Raw Backup Data (collapsible)
        do
            local s = rSection("Raw Backup Data", nextOrder())
            local toggle = createInstance("TextButton", {
                Size = UDim2.new(1, 0, 0, 24),
                BackgroundColor3 = COLORS.TAB_INACTIVE,
                Text = "Show Raw Backup Data",
                TextColor3 = COLORS.TEXT_PRIMARY,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                LayoutOrder = 1,
                Parent = s,
            })
            addCorner(toggle, 4)
            local rawScroll = createInstance("ScrollingFrame", {
                Size = UDim2.new(1, 0, 0, 220),
                BackgroundColor3 = COLORS.BG_DARK,
                BorderSizePixel = 0,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = COLORS.ACCENT,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                Visible = false,
                LayoutOrder = 2,
                Parent = s,
            })
            addCorner(rawScroll, 4)
            local rawLabel = createInstance("TextLabel", {
                Size = UDim2.new(1, -8, 0, 0),
                Position = UDim2.new(0, 4, 0, 4),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = COLORS.TEXT_PRIMARY,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                AutomaticSize = Enum.AutomaticSize.Y,
                TextWrapped = false,
                Parent = rawScroll,
            })
            local rawRendered = false
            toggle.MouseButton1Click:Connect(function()
                if not rawScroll.Visible then
                    if not rawRendered then
                        local ok, str = pcall(function() return rSerialize(prev) end)
                        rawLabel.Text = ok and str or "(serialize error)"
                        rawRendered = true
                    end
                    rawScroll.Visible = true
                    toggle.Text = "Hide Raw Backup Data"
                else
                    rawScroll.Visible = false
                    toggle.Text = "Show Raw Backup Data"
                end
            end)
        end
    end

    local function rSetHeader(rec)
        rHeader.Text = string.format("%s (@%s)  •  %s  •  %s",
            tostring(rec.targetDisplayName or rec.targetUsername or "?"),
            tostring(rec.targetUsername or "?"),
            tostring(rec.resetType or "?"),
            rFmtTime(rec.timestamp))
        rHeader.TextColor3 = rec.restored and COLORS.TEXT_DIM or COLORS.TEXT_PRIMARY
    end

    local function loadSelectedBackup(backupId)
        if not backupId then return end
        if rBusy then return end
        rBusy = true
        rHeader.Text = "Loading backup..."
        rHeader.TextColor3 = COLORS.TEXT_DIM
        rClearData()
        rRestoreArea.Visible = false

        local ok, result = pcall(function() return getBackupRF:InvokeServer(backupId) end)
        rBusy = false

        if not ok or not result or not result.success then
            rHeader.Text = "Failed to load backup: " .. tostring(result and result.error or result or "?")
            rHeader.TextColor3 = COLORS.RED
            rSelectedRecord = nil
            return
        end

        rSelectedRecord = result.record
        rSetHeader(result.record)
        rRenderBackup(result.record)
        rRefreshRestoreButton()
    end

    local function buildHistoryCard(entry, order)
        local card = createInstance("TextButton", {
            Name = "Hist_" .. tostring(entry.backupId),
            Size = UDim2.new(1, 0, 0, 56),
            BackgroundColor3 = COLORS.BG_CARD,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = rListScroll,
        })
        addCorner(card, 4)

        local accent = entry.restored and COLORS.GREEN or COLORS.RED
        createInstance("Frame", {
            Size = UDim2.new(0, 3, 1, -8),
            Position = UDim2.new(0, 4, 0, 4),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            Parent = card,
        })

        createInstance("TextLabel", {
            Size = UDim2.new(1, -20, 0, 18),
            Position = UDim2.new(0, 14, 0, 4),
            BackgroundTransparency = 1,
            Text = string.format("%s  (UserId %s)",
                tostring(entry.targetUsername or "?"),
                tostring(entry.targetUserId or "?")),
            TextColor3 = COLORS.TEXT_PRIMARY,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = card,
        })
        createInstance("TextLabel", {
            Size = UDim2.new(1, -20, 0, 14),
            Position = UDim2.new(0, 14, 0, 22),
            BackgroundTransparency = 1,
            Text = string.format("%s  •  %s", tostring(entry.resetType or "?"), rFmtTime(entry.timestamp)),
            TextColor3 = COLORS.TEXT_SECONDARY,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = card,
        })
        createInstance("TextLabel", {
            Size = UDim2.new(1, -20, 0, 14),
            Position = UDim2.new(0, 14, 0, 38),
            BackgroundTransparency = 1,
            Text = entry.restored and "RESTORED" or "Not Restored",
            TextColor3 = entry.restored and COLORS.GREEN or COLORS.RED,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })

        card.MouseEnter:Connect(function() card.BackgroundColor3 = COLORS.BG_CARD_HOVER end)
        card.MouseLeave:Connect(function() card.BackgroundColor3 = COLORS.BG_CARD end)
        card.MouseButton1Click:Connect(function() loadSelectedBackup(entry.backupId) end)
    end

    local function loadHistoryPage(page)
        if rBusy then return end
        rBusy = true
        rClearList()
        rStatus.Text = "Loading page " .. tostring(page) .. "..."
        rStatus.TextColor3 = COLORS.TEXT_DIM

        local ok, result = pcall(function()
            return getHistoryRF:InvokeServer(page, 25)
        end)
        rBusy = false

        if not ok or not result or not result.success then
            rStatus.Text = "Error: " .. tostring(result and result.error or result or "?")
            rStatus.TextColor3 = COLORS.RED
            return
        end

        local entries = result.entries or {}
        if #entries == 0 then
            rStatus.Text = "No reset records found."
            rStatus.TextColor3 = COLORS.TEXT_DIM
        else
            rStatus.Text = string.format("%d record(s) on page", #entries)
            rStatus.TextColor3 = COLORS.GREEN
            for i, entry in ipairs(entries) do buildHistoryCard(entry, i) end
        end

        rPage = result.page or page
        rHasNextPage = result.hasNextPage == true
        rPageLabel.Text = "Page " .. tostring(rPage)
    end

    local function doHistorySearch()
        local q = rSearchInput.Text or ""
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then
            loadHistoryPage(1)
            return
        end
        if rBusy then return end
        rBusy = true
        rClearList()
        rStatus.Text = "Searching..."
        rStatus.TextColor3 = COLORS.TEXT_DIM

        local ok, result = pcall(function() return searchHistoryRF:InvokeServer(q) end)
        rBusy = false

        if not ok or not result or not result.success then
            rStatus.Text = "Error: " .. tostring(result and result.error or result or "?")
            rStatus.TextColor3 = COLORS.RED
            return
        end

        local entries = result.entries or {}
        if #entries == 0 then
            rStatus.Text = "No reset records found."
            rStatus.TextColor3 = COLORS.TEXT_DIM
            return
        end
        rStatus.Text = string.format("%d match(es)", #entries)
        rStatus.TextColor3 = COLORS.GREEN
        for i, entry in ipairs(entries) do buildHistoryCard(entry, i) end
    end

    rSearchBtn.MouseButton1Click:Connect(doHistorySearch)
    rSearchInput.FocusLost:Connect(function(enter) if enter then doHistorySearch() end end)
    rPrevBtn.MouseButton1Click:Connect(function()
        if rPage > 1 then loadHistoryPage(rPage - 1) end
    end)
    rNextBtn.MouseButton1Click:Connect(function()
        if rHasNextPage then loadHistoryPage(rPage + 1) end
    end)

    ------------------------------------------------------------------
    -- RESTORE FLOW
    ------------------------------------------------------------------
    local function refreshRestoreOkEnabled()
        if (restoreTypeBox.Text or "") == "RESTORE" then
            restoreOk.BackgroundColor3 = COLORS.RED
            restoreOk.TextColor3 = Color3.new(1, 1, 1)
            restoreOk.AutoButtonColor = true
        else
            restoreOk.BackgroundColor3 = COLORS.TAB_INACTIVE
            restoreOk.TextColor3 = COLORS.TEXT_DIM
            restoreOk.AutoButtonColor = false
        end
    end
    restoreTypeBox:GetPropertyChangedSignal("Text"):Connect(refreshRestoreOkEnabled)

    local function hideRestoreModal()
        restoreOverlay.Visible = false
        restoreTypeBox.Text = ""
        restoreBody.TextColor3 = COLORS.TEXT_PRIMARY
        restoreOk.Text = "Confirm Restore"
        refreshRestoreOkEnabled()
    end

    local function showRestoreModal()
        if not rSelectedRecord or rSelectedRecord.restored then return end
        local rec = rSelectedRecord
        restoreBody.Text = string.format(
            "Are you sure you want to restore %s (%s) to the saved backup from %s? This will overwrite their current saved data.\n\nReset type: %s\nA safety snapshot of their CURRENT data will be captured first.",
            tostring(rec.targetUsername or "?"),
            tostring(rec.targetUserId or "?"),
            rFmtTime(rec.timestamp),
            tostring(rec.resetType or "?")
        )
        restoreTypeBox.Text = ""
        restoreOk.Text = "Confirm Restore"
        refreshRestoreOkEnabled()
        restoreOverlay.Visible = true
    end

    rRestoreBtn.MouseButton1Click:Connect(function()
        if not rSelectedRecord or rSelectedRecord.restored then return end
        showRestoreModal()
    end)
    restoreCancel.MouseButton1Click:Connect(hideRestoreModal)

    restoreOk.MouseButton1Click:Connect(function()
        if not rSelectedRecord or not rSelectedRecord.backupId then return end
        if not restoreOk.AutoButtonColor then return end
        if rBusy then return end

        local backupId = rSelectedRecord.backupId
        rBusy = true
        restoreOk.Text = "Restoring..."
        restoreOk.AutoButtonColor = false

        local ok, result = pcall(function() return restoreRF:InvokeServer(backupId) end)
        rBusy = false

        if not ok or not result or not result.success then
            restoreBody.Text = "ERROR: " .. tostring(result and result.error or result or "?")
            restoreBody.TextColor3 = COLORS.RED
            restoreOk.Text = "Confirm Restore"
            refreshRestoreOkEnabled()
            return
        end

        local headline
        if result.message then
            headline = result.message
        elseif not result.wasOnline then
            headline = "Backup restored. Player is offline and will receive restored data next time they join."
        elseif result.liveApplied then
            headline = "Backup restored and live refreshed."
        elseif result.kicked then
            headline = "Backup restored. Player was kicked so the restored data can take effect."
        else
            headline = "Backup saved, but live refresh failed. Player may need to rejoin."
        end
        local lines = {
            headline,
            "Subsystems applied: " .. tostring(#(result.restored or {})),
        }
        if result.liveRefreshed and #result.liveRefreshed > 0 then
            table.insert(lines, "Live refreshed: " .. table.concat(result.liveRefreshed, ", "))
        end
        if result.failed and #result.failed > 0 then
            table.insert(lines, "Failed: " .. table.concat(result.failed, ", "))
        end
        if result.safetyBackupKey then
            table.insert(lines, "Safety backup: " .. tostring(result.safetyBackupKey))
        else
            table.insert(lines, "Safety backup: NOT SAVED")
        end
        restoreBody.Text = table.concat(lines, "\n")
        restoreBody.TextColor3 = COLORS.GREEN
        restoreOk.Text = "Close"
        restoreOk.BackgroundColor3 = COLORS.GREEN
        restoreOk.TextColor3 = Color3.new(1, 1, 1)
        restoreOk.AutoButtonColor = true

        -- Mark current selection restored locally and refresh button.
        rSelectedRecord.restored = true
        rSelectedRecord.restoredAt = os.time()
        rSelectedRecord.restoredByUserId = player.UserId
        rSelectedRecord.restoredByUsername = player.Name
        rRefreshRestoreButton()
        rRenderBackup(rSelectedRecord)

        local conn
        conn = restoreOk.MouseButton1Click:Connect(function()
            if conn then conn:Disconnect(); conn = nil end
            hideRestoreModal()
            -- Refresh history list so the row colors reflect restored=true.
            loadHistoryPage(rPage)
        end)
    end)

    -- Initial load on first tab open.
    local restoreLoaded = false
    userDataRTab.MouseButton1Click:Connect(function()
        if not restoreLoaded then
            restoreLoaded = true
            loadHistoryPage(1)
        end
    end)
end -- RESTORE_AVAILABLE

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
