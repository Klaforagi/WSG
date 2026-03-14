-- SideUI.client.lua
-- Main hub menu UI. Coin display is handled by the CoinDisplay module in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
print("[SideUI] initializing for", player and player.Name)

-- In Team Test the camera ViewportSize can be (0,0) until the first frame
-- renders. Since 0 is truthy in Lua, the old `or 1080` fallback never fired,
-- causing every px() call to return 1 and making all UI elements invisible.
-- Wait briefly so all sizing uses the real resolution.
do
	local cam = workspace.CurrentCamera
	if not cam then
		cam = workspace:WaitForChild("Camera", 5)
	end
	if cam then
		local t = 0
		while cam.ViewportSize.Y < 2 and t < 3 do
			t = t + task.wait()
		end
	end
end

-- Scale pixel values proportionally to viewport height (reference: 1080p)
local function px(base)
	local cam = workspace.CurrentCamera
	-- Guard: if ViewportSize.Y is 0, fall back to 1080 so UI is correctly
	-- proportioned instead of collapsing to 1px (the Team Test root cause).
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

-- Load AssetCodes with WaitForChild so it is available in Team Test where
-- ReplicatedStorage contents may not have replicated when this script starts.
local AssetCodes = nil
do
    local mod = ReplicatedStorage:WaitForChild("AssetCodes", 5)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            AssetCodes = result
        else
            warn("[SideUI] AssetCodes failed to load:", tostring(result))
        end
    else
        warn("[SideUI] AssetCodes not found after 5s – button icons may be missing")
    end
end

-- Config / constants
-- Panel sizing: narrower on desktop (8%), wider on mobile (16%)
local PANEL_WIDTH_SCALE = UserInputService.TouchEnabled and 0.16 or 0.11
local PANEL_WIDTH = UDim2.new(PANEL_WIDTH_SCALE, 0, 0, 0) -- width only; height is AutomaticSize
local PANEL_ANCHOR = Vector2.new(0, 0.5) -- left side, vertically centered
local PANEL_POS = UDim2.new(0, px(8), 0.5, 0) -- left side, centered vertically

-- Device text scale (smaller on desktop)
local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75
local function tpx(base)
    return math.max(1, math.round(px(base) * deviceTextScale))
end

local COLORS = {
    panelBg = Color3.fromRGB(12, 14, 28),
    gold = Color3.fromRGB(255, 215, 80),
    brown = Color3.fromRGB(122, 85, 46),
    white = Color3.fromRGB(245, 245, 245),
    buttonBg = Color3.fromRGB(18, 20, 36),
    badgeBg = Color3.fromRGB(220, 40, 40),
}

-- Team gradient helpers
local function getTeamGradientSequence()
    local ok, base = pcall(function()
        local team = player and player.Team
        if team and team.TeamColor and team.Name ~= "Neutral" then
            if team.Name == "Blue" then
                return Color3.fromRGB(12, 51, 168) -- royal blue (match MatchHUD BLUE_ACCENT)
            elseif team.Name == "Red" then
                return Color3.fromRGB(202, 24, 24) -- match MatchHUD RED_ACCENT
            end
            return team.TeamColor.Color
        end
        return nil
    end)
    if not ok or not base then
        base = Color3.fromRGB(35, 35, 40) -- default: dark gray (toolbar style)
    else
        -- slightly darken team colors (blue/red) for stronger contrast
        base = base:Lerp(Color3.new(0, 0, 0), 0.12)
    end
    local dark = base:Lerp(Color3.fromRGB(4, 4, 6), 0.72)
    local bright = base:Lerp(Color3.new(1, 1, 1), 0.12)
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, dark),
        ColorSequenceKeypoint.new(1, bright),
    })
end

local function makeButtonGradient(parent)
    local g = Instance.new("UIGradient")
    g.Rotation = 135
    g.Color = getTeamGradientSequence()
    g.Parent = parent
    -- Each gradient listens for team changes directly (reliable)
    player:GetPropertyChangedSignal("Team"):Connect(function()
        pcall(function()
            g.Color = getTeamGradientSequence()
        end)
    end)
    return g
end

local MENU_DEFS = {
    { id = "Missions", label = "QUESTS", iconKey = "Quests" },
    { id = "Upgrade", label = "UPGRADE", iconKey = "Upgrade" },
    { id = "Boosts", label = "BOOSTS", iconKey = "Boosts" },
    { id = "Trolls", label = "TROLLS", iconKey = "Trolls" },
    { id = "Team", label = "TEAM", iconKey = "Team" },
    { id = "Options", label = "OPTIONS", iconKey = "Options" },
}

-- Internal state tables to expose
local buttonsById = {}
local badgesById = {}
-- Local handlers table (defined early so click handlers can safely reference it)
local scriptHandlers = {}

-- Helper tween
local function tweenInstance(inst, props, info)
    info = info or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local suc, t = pcall(function() return TweenService:Create(inst, info, props) end)
    if suc and t then t:Play() end
end

-- UI creation helpers
local function CreatePanel(screenGui)
    local panel = Instance.new("Frame")
    panel.Name = "MainUICard"
    panel.AnchorPoint = PANEL_ANCHOR
    panel.Position = PANEL_POS
    panel.Size = PANEL_WIDTH
    panel.BackgroundColor3 = COLORS.panelBg
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(10))
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1
    stroke.Transparency = 1
    stroke.Parent = panel

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, px(10))
    padding.PaddingBottom = UDim.new(0, px(10))
    padding.PaddingLeft = UDim.new(0, px(10))
    padding.PaddingRight = UDim.new(0, px(10))
    padding.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, px(4))
    layout.Parent = panel

    return panel
end

local function makeTextButtonBase(text)
    local btn = Instance.new("TextButton")
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.new(1, 1, 1) -- white so UIGradient colour shows through
    btn.BackgroundTransparency = 0
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.Text = text or ""
    btn.TextColor3 = COLORS.gold
    btn.TextScaled = true
    btn.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(8))
    corner.Parent = btn

    makeButtonGradient(btn)

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = btn

    return btn
end

-- Helper: create a half-width top button (used for SHOP and INVENTORY)
local function makeTopHalfButton(label, iconKey, layoutOrder)
    local btn = makeTextButtonBase(label)
    btn.Name = label .. "Button"
    btn.LayoutOrder = layoutOrder or 1
    btn.ClipsDescendants = false

    local function calcBtnHeight()
        local screenY = 720
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then screenY = cam.ViewportSize.Y end
        return math.max(36, math.floor(screenY * 0.07))
    end
    local btnH = calcBtnHeight()
    btn.Size = UDim2.new(1, 0, 0, btnH)

    -- optional icon
    local assetId = (AssetCodes and type(AssetCodes.Get) == "function") and AssetCodes.Get(iconKey or label)
    btn.Text = ""
    if assetId and type(assetId) == "string" then
        local icon = Instance.new("ImageLabel")
        icon.Name = label .. "Icon"
        local function updateIconSize()
            local h = btn.AbsoluteSize.Y > 0 and btn.AbsoluteSize.Y or btnH
            local s = math.max(50, math.floor(h * 1.4))
            icon.Size = UDim2.new(0, s, 0, s)
            icon.Position = UDim2.new(0.5, 0, 0.35, 0)
            icon.AnchorPoint = Vector2.new(0.5, 0.5)
        end
        updateIconSize()
        icon.BackgroundTransparency = 1
        icon.Image = assetId
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ZIndex = 1
        icon.Parent = btn
        btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateIconSize)
        local cam = workspace.CurrentCamera
        if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateIconSize) end

        local overlay = Instance.new("TextLabel")
        overlay.Name = label .. "OverlayLabel"
        overlay.BackgroundTransparency = 1
        overlay.Size = UDim2.new(0.9, 0, 0, math.max(12, math.floor(btnH * 0.28)))
        overlay.Position = UDim2.new(0.5, 0, 1, -px(2))
        overlay.AnchorPoint = Vector2.new(0.5, 1)
        overlay.Font = Enum.Font.GothamBold
        overlay.Text = label
        overlay.TextColor3 = COLORS.gold
        overlay.TextSize = math.max(14, math.floor(btnH * 0.78 * deviceTextScale))
        overlay.TextScaled = false
        overlay.TextXAlignment = Enum.TextXAlignment.Center
        overlay.TextYAlignment = Enum.TextYAlignment.Center
        overlay.ZIndex = 2
        overlay.TextStrokeColor3 = COLORS.brown
        overlay.TextStrokeTransparency = 0
        overlay.Parent = btn
    else
        btn.Text = label
        btn.TextXAlignment = Enum.TextXAlignment.Center
        btn.TextScaled = false
        btn.TextSize = math.max(14, math.floor(btnH * 0.78 * deviceTextScale))
        btn.TextColor3 = COLORS.gold
        btn.TextStrokeColor3 = COLORS.brown
        btn.TextStrokeTransparency = 0
    end

    -- hover & click feedback
    btn.MouseEnter:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.12)) end
        local lbl = btn:FindFirstChild(label .. "OverlayLabel")
        if lbl then tweenInstance(lbl, {TextColor3 = Color3.new(1,1,1)}, TweenInfo.new(0.12))
        else tweenInstance(btn, {TextColor3 = Color3.new(1,1,1)}, TweenInfo.new(0.12)) end
    end)
    btn.MouseLeave:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.12}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        local lbl = btn:FindFirstChild(label .. "OverlayLabel")
        if lbl then tweenInstance(lbl, {TextColor3 = COLORS.gold}, TweenInfo.new(0.12))
        else tweenInstance(btn, {TextColor3 = COLORS.gold}, TweenInfo.new(0.12)) end
    end)

    return btn, btnH
end

local function CreateShopAndInventoryRow(parent)
    -- Container frame: full width, holds two half-width buttons side by side
    local row = Instance.new("Frame")
    row.Name = "ShopInventoryRow"
    row.LayoutOrder = 1
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.Parent = parent

    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, px(4))
    rowLayout.Parent = row

    -- SHOP button (left half)
    local shopBtn, shopH = makeTopHalfButton("SHOP", "Shop", 1)
    shopBtn.Size = UDim2.new(0.5, -px(2), 0, shopH)
    shopBtn.Parent = row

    shopBtn.MouseButton1Click:Connect(function()
        tweenInstance(shopBtn, {BackgroundTransparency = 0}, TweenInfo.new(0.06))
        local s = shopBtn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.06)) end
        task.delay(0.09, function()
            tweenInstance(shopBtn, {BackgroundTransparency = 0.12}, TweenInfo.new(0.12))
            if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        end)
        if _G and _G.SideUI and type(_G.SideUI.OnShop) == "function" then
            pcall(_G.SideUI.OnShop)
        elseif type(scriptHandlers.OnShop) == "function" then
            pcall(scriptHandlers.OnShop)
        else
            print("Shop")
        end
    end)

    -- INVENTORY button (right half)
    local invBtn, invH = makeTopHalfButton("INVENTORY", "Inventory", 2)
    invBtn.Size = UDim2.new(0.5, -px(2), 0, invH)
    invBtn.Parent = row

    invBtn.MouseButton1Click:Connect(function()
        tweenInstance(invBtn, {BackgroundTransparency = 0}, TweenInfo.new(0.06))
        local s = invBtn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.06)) end
        task.delay(0.09, function()
            tweenInstance(invBtn, {BackgroundTransparency = 0.12}, TweenInfo.new(0.12))
            if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        end)
        if _G and _G.SideUI and type(_G.SideUI.OnInventory) == "function" then
            pcall(_G.SideUI.OnInventory)
        elseif type(scriptHandlers.OnInventory) == "function" then
            pcall(scriptHandlers.OnInventory)
        else
            print("Inventory")
        end
    end)

    return row, shopBtn, invBtn
end

-- CoinDisplay module (ReplicatedStorage): creates coin row + wires server remotes.
-- WaitForChild ensures availability in Team Test (separate server/client processes).
local CoinDisplayModule = nil
do
    local mod = ReplicatedStorage:WaitForChild("CoinDisplay", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            CoinDisplayModule = result
        else
            warn("[SideUI] CoinDisplay failed to load:", tostring(result))
        end
    else
        warn("[SideUI] CoinDisplay not found – coin row will be unavailable")
    end
end

local function CreateMenuGrid(parent)
    local gridContainer = Instance.new("Frame")
    gridContainer.Name = "MenuGridContainer"
    gridContainer.LayoutOrder = 3
    gridContainer.Size = UDim2.new(1, 0, 0, 0)
    gridContainer.AutomaticSize = Enum.AutomaticSize.Y
    gridContainer.BackgroundTransparency = 1
    gridContainer.Parent = parent

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, px(54), 0, px(54))
    grid.CellPadding = UDim2.new(0, px(6), 0, px(6))
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 3
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = gridContainer

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, px(2))
    padding.PaddingBottom = UDim.new(0, px(6))
    padding.PaddingLeft = UDim.new(0, 0)
    padding.PaddingRight = UDim.new(0, 0)
    padding.Parent = gridContainer

    -- Prefer sizing cells to match the Shop button width so 3 columns always fit.
    -- Use the ShopInventoryRow (or fallback to grid container width) for cell sizing
    local shopInvRow = parent:FindFirstChild("ShopInventoryRow")
    local function updateCellSize()
        local cols = grid.FillDirectionMaxCells or 3
        local cellPad = (grid and grid.CellPadding and grid.CellPadding.X) and grid.CellPadding.X.Offset or 6

        local sourceW = 0
        if shopInvRow and shopInvRow.AbsoluteSize and shopInvRow.AbsoluteSize.X > 0 then
            sourceW = shopInvRow.AbsoluteSize.X
        else
            sourceW = gridContainer.AbsoluteSize.X
        end

        if sourceW <= 0 then return end
        local cellW = math.max(20, math.floor((sourceW - (cellPad * (cols - 1))) / cols))
        grid.CellSize = UDim2.new(0, cellW, 0, cellW)
    end

    if shopInvRow then
        shopInvRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    end
    gridContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    if gridContainer.Parent then
        gridContainer.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
    end
    task.defer(updateCellSize)

    return gridContainer
end

local function CreateMenuButton(def)
    local btn = Instance.new("TextButton")
    btn.Name = "Btn_" .. tostring(def.id)
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.new(1, 1, 1) -- white so UIGradient colour shows through
    btn.BackgroundTransparency = 0
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.Text = "" -- we use a separate small label for the name
    btn.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(8))
    corner.Parent = btn

    makeButtonGradient(btn)

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = btn

    -- Background image (fills the button)
    if def.iconKey and AssetCodes and type(AssetCodes.Get) == "function" then
        local ok, id = pcall(function() return AssetCodes.Get(def.iconKey) end)
        if ok and id and type(id) == "string" then
            local bgImg = Instance.new("ImageLabel")
            bgImg.Name = "BgIcon"
            bgImg.BackgroundTransparency = 1
            bgImg.Size = UDim2.new(0.7, 0, 0.6, 0)
            bgImg.AnchorPoint = Vector2.new(0.5, 0.4)
            bgImg.Position = UDim2.new(0.5, 0, 0.38, 0)
            bgImg.Image = id
            bgImg.ScaleType = Enum.ScaleType.Fit
            bgImg.Parent = btn
        end
    end

    -- Small text label at the bottom of the button
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 1, -px(3))
    nameLabel.Size = UDim2.new(0.95, 0, 0, px(11))
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = def.label or def.id
    nameLabel.TextColor3 = COLORS.gold
    nameLabel.TextSize = tpx(24)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = btn
    local nameStroke = Instance.new("UIStroke")
    nameStroke.Color = Color3.fromRGB(0, 0, 0)
    nameStroke.Thickness = 0.6
    nameStroke.Transparency = 0.3
    nameStroke.Parent = nameLabel

    -- badge (hidden by default)
    local badge = Instance.new("TextLabel")
    badge.Name = "Badge"
    badge.Size = UDim2.new(0, px(16), 0, px(16))
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -px(2), 0, -px(2))
    badge.BackgroundColor3 = COLORS.badgeBg
    badge.Text = "!"
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = tpx(24)
    badge.TextColor3 = Color3.new(1, 1, 1)
    badge.Visible = false
    badge.Parent = btn
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = badge

    -- hover & click feedback (more pronounced: background + stroke tweak)
    btn.MouseEnter:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.12)) end
        -- brighten label text on hover
        pcall(function()
            tweenInstance(nameLabel, {TextColor3 = Color3.new(1,1,1)}, TweenInfo.new(0.12))
        end)
    end)
    btn.MouseLeave:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        pcall(function()
            tweenInstance(nameLabel, {TextColor3 = COLORS.gold}, TweenInfo.new(0.12))
        end)
    end)
    btn.MouseButton1Click:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.04))
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then tweenInstance(s, {Transparency = 0}, TweenInfo.new(0.04)) end
        task.delay(0.06, function()
            tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12))
            if s then tweenInstance(s, {Transparency = 0.12}, TweenInfo.new(0.12)) end
        end)
        if _G and _G.SideUI and type(_G.SideUI.OnMenuButton) == "function" then
            pcall(_G.SideUI.OnMenuButton, def.id)
        elseif type(scriptHandlers.OnMenuButton) == "function" then
            pcall(scriptHandlers.OnMenuButton, def.id)
        else
            print("Menu button clicked:", def.id)
        end
    end)

    return btn, badge
end

-- Build UI (create ScreenGui if script not already parented to one)
local screenGui = nil
if script.Parent and script.Parent:IsA("ScreenGui") then
    screenGui = script.Parent
else
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MainUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui
    -- move the script into this ScreenGui so that script.Parent references remain intuitive
    pcall(function() script.Parent = screenGui end)
end
pcall(function() screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
-- Ensure shop ScreenGui renders above other UI (hotbar, HUD). Adjust as needed.
pcall(function() screenGui.DisplayOrder = 250 end)
print("[SideUI] screenGui ready; parent =", tostring(screenGui.Parent))

-- Clear existing content in screenGui container area (optional safe-guard: only if it's our MainUICard)
local existing = screenGui:FindFirstChild("MainUICard")
if existing then existing:Destroy() end

local panel = CreatePanel(screenGui)
local shopInvRow, shopBtn, invBtn = CreateShopAndInventoryRow(panel)
print("[SideUI] panel created; shopBtn =", tostring(shopBtn), "invBtn =", tostring(invBtn))

-- Simple client-side inventory API
local Inventory = {}
do
    local items = {}
    local equipped = { Melee = nil, Ranged = nil, Special = nil }
    function Inventory:AddItem(id)
        if not id then return end
        for _, v in ipairs(items) do if v == id then return end end
        table.insert(items, id)
    end
    function Inventory:HasItem(id)
        for _, v in ipairs(items) do if v == id then return true end end
        return false
    end
    function Inventory:GetItems()
        return table.clone(items)
    end
    function Inventory:SetEquipped(category, id)
        if type(category) ~= "string" then return end
        local k = tostring(category):gsub("%s+", "")
        if not equipped[k] then equipped[k] = nil end
        equipped[k] = id
    end
    function Inventory:GetEquipped(category)
        if type(category) ~= "string" then return nil end
        local k = tostring(category):gsub("%s+", "")
        return equipped[k]
    end
end

-- preload Slingshot into the client inventory so player has ranged start
pcall(function() Inventory:AddItem("Slingshot") end)
pcall(function() Inventory:SetEquipped("Ranged", "Slingshot") end)
-- preload Stick so player shows it as owned at start (free starter melee)
pcall(function() Inventory:AddItem("Stick") end)
pcall(function() Inventory:SetEquipped("Melee", "Stick") end)

-- Create centered modal window (hidden by default)
local modalOverlay = Instance.new("Frame")
modalOverlay.Name = "ModalOverlay"
modalOverlay.Size = UDim2.new(1,0,1,0)
modalOverlay.Position = UDim2.new(0,0,0,0)
modalOverlay.BackgroundTransparency = 0.5
modalOverlay.BackgroundColor3 = Color3.fromRGB(10,10,10)
modalOverlay.Visible = false
modalOverlay.Parent = screenGui

-- ── Modal window ──────────────────────────────────────────────────────────
local window = Instance.new("Frame")
window.Name = "ModalWindow"
window.Size = UDim2.new(0.65, 0, 0.72, 0)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.new(0.5, 0, 0.5, 0)
-- Use the neutral SideUI gray for modal background instead of navy
window.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
window.Parent = modalOverlay
window.ZIndex = 260
local winCorner = Instance.new("UICorner")
winCorner.CornerRadius = UDim.new(0, px(14))
winCorner.Parent = window
local winStroke = Instance.new("UIStroke")
winStroke.Color = Color3.fromRGB(255, 215, 80)
winStroke.Thickness = 2
winStroke.Transparency = 0.15
winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
winStroke.Parent = window
local winPad = Instance.new("UIPadding")
winPad.PaddingTop = UDim.new(0, px(10))
winPad.PaddingBottom = UDim.new(0, px(10))
winPad.PaddingLeft = UDim.new(0, px(14))
winPad.PaddingRight = UDim.new(0, px(14))
winPad.Parent = window

-- ── Header bar (title + coin display + close X) ──────────────────────────
local HEADER_H = 0.10 -- fraction of window height
local headerBar = Instance.new("Frame")
headerBar.Name = "HeaderBar"
headerBar.Size = UDim2.new(1, 0, HEADER_H, 0)
headerBar.BackgroundTransparency = 1
headerBar.ZIndex = 10
headerBar.Parent = window
headerBar.ZIndex = 270

-- Title pill
local titlePill = Instance.new("Frame")
titlePill.Name = "TitlePill"
titlePill.Size = UDim2.new(0.30, 0, 0.80, 0)
titlePill.AnchorPoint = Vector2.new(0.5, 0.5)
titlePill.Position = UDim2.new(0.5, 0, 0.5, 0)
    -- Use neutral gray when not on a team (match SideUI neutral)
    titlePill.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
titlePill.ZIndex = 10
titlePill.Parent = headerBar
local titlePillCorner = Instance.new("UICorner")
titlePillCorner.CornerRadius = UDim.new(0, px(8))
titlePillCorner.Parent = titlePill
local titlePillStroke = Instance.new("UIStroke")
    titlePillStroke.Color = Color3.fromRGB(90, 90, 96)
    titlePillStroke.Thickness = 1.5
    titlePillStroke.Transparency = 0.3
titlePillStroke.Parent = titlePill

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
titleLabel.Text = "SHOP"
titleLabel.ZIndex = 11
titleLabel.Parent = titlePill
titleLabel.ZIndex = 275

-- Coin display in header (right side)
local headerCoinFrame = Instance.new("Frame")
headerCoinFrame.Name = "HeaderCoin"
headerCoinFrame.Size = UDim2.new(0.28, 0, 0.70, 0)
headerCoinFrame.AnchorPoint = Vector2.new(1, 0.5)
headerCoinFrame.Position = UDim2.new(0.92, 0, 0.5, 0)
headerCoinFrame.BackgroundTransparency = 1
headerCoinFrame.ZIndex = 10
headerCoinFrame.Parent = headerBar
headerCoinFrame.ZIndex = 275

local headerCoinLabel = Instance.new("TextLabel")
headerCoinLabel.Name = "CoinLabel"
headerCoinLabel.Size = UDim2.new(0.72, 0, 1, 0)
headerCoinLabel.Position = UDim2.new(0, 0, 0, 0)
headerCoinLabel.BackgroundTransparency = 1
headerCoinLabel.Font = Enum.Font.GothamBold
headerCoinLabel.TextScaled = true
headerCoinLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
headerCoinLabel.TextXAlignment = Enum.TextXAlignment.Right
headerCoinLabel.Text = "0"
headerCoinLabel.ZIndex = 11
headerCoinLabel.Parent = headerCoinFrame

-- Coin icon after text
local headerCoinIcon = Instance.new("ImageLabel")
headerCoinIcon.Name = "CoinIcon"
-- Bigger and centered vertically to match the header label
headerCoinIcon.Size = UDim2.new(0.70, 0, 0.92, 0)
headerCoinIcon.Position = UDim2.new(0.75, 0, 0.5, 1.5)
headerCoinIcon.AnchorPoint = Vector2.new(0, 0.5)
headerCoinIcon.BackgroundTransparency = 1
headerCoinIcon.ScaleType = Enum.ScaleType.Fit
headerCoinIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
headerCoinIcon.ZIndex = 11
headerCoinIcon.Parent = headerCoinFrame
pcall(function()
    if AssetCodes and type(AssetCodes.Get) == "function" then
        local ci = AssetCodes.Get("Coin")
        if ci and #ci > 0 then headerCoinIcon.Image = ci end
    end
end)

-- Close X (top-right corner of window)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextScaled = true
closeBtn.Size = UDim2.new(0.05, 0, HEADER_H * 0.85, 0)
closeBtn.SizeConstraint = Enum.SizeConstraint.RelativeYY
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, 0, 0, 0)
closeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 300
closeBtn.Parent = window
local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, px(6))
closeBtnCorner.Parent = closeBtn

-- ── Content area (below header) ───────────────────────────────────────────
local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Name = "ModalContent"
contentFrame.BackgroundTransparency = 1
contentFrame.Size = UDim2.new(1, 0, 1 - HEADER_H - 0.02, 0)
contentFrame.Position = UDim2.new(0, 0, HEADER_H + 0.01, 0)
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.ScrollBarThickness = px(4)
contentFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 80)
contentFrame.BorderSizePixel = 0
contentFrame.ZIndex = 1
contentFrame.Parent = window

local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, px(8))
contentLayout.Parent = contentFrame

-- add top padding so first row of cards is not clipped by fixed header
local contentPadding = Instance.new("UIPadding")
contentPadding.PaddingTop = UDim.new(0, px(14))
contentPadding.PaddingLeft = UDim.new(0, px(10))
contentPadding.PaddingRight = UDim.new(0, px(10))
contentPadding.Parent = contentFrame

-- ensure content sits above other UI but behind header elements
contentFrame.ZIndex = 260

-- Forward-declare coinApi so closures below can reference it
local coinApi = nil

local function clearContent()
    for _, c in ipairs(contentFrame:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") then
            pcall(function() c:Destroy() end)
        end
    end
end
local currentModule = nil
local isAnimating = false
local TWEEN_IN_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT_INFO = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function clearAndHide()
    currentModule = nil
    modalOverlay.Visible = false
    clearContent()
end

local function tweenWindowIn(done)
    if isAnimating then return end
    isAnimating = true
    modalOverlay.Visible = true
    -- start above the viewport and tween to center
    window.Position = UDim2.new(0.5, 0, -0.35, 0)
    local suc, t = pcall(function() return TweenService:Create(window, TWEEN_IN_INFO, {Position = UDim2.new(0.5, 0, 0.5, 0)}) end)
    if suc and t then
        t:Play()
        t.Completed:Connect(function()
            isAnimating = false
            if type(done) == "function" then pcall(done) end
        end)
    else
        -- fallback: immediate
        window.Position = UDim2.new(0.5, 0, 0.5, 0)
        isAnimating = false
        if type(done) == "function" then pcall(done) end
    end
end

local function tweenWindowOut(done)
    if isAnimating then return end
    isAnimating = true
    -- tween window up offscreen, then hide overlay and clear
    local suc, t = pcall(function() return TweenService:Create(window, TWEEN_OUT_INFO, {Position = UDim2.new(0.5, 0, -0.35, 0)}) end)
    if suc and t then
        t:Play()
        t.Completed:Connect(function()
            clearAndHide()
            isAnimating = false
            if type(done) == "function" then pcall(done) end
        end)
    else
        -- fallback: immediate
        clearAndHide()
        isAnimating = false
        if type(done) == "function" then pcall(done) end
    end
end

closeBtn.MouseButton1Click:Connect(function()
    if modalOverlay.Visible then
        tweenWindowOut()
    end
end)

-- WaitForChild for the folder AND its children: in Team Test the folder may
-- replicate before its child ModuleScripts are available.
local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI", 10)
local shopModule = sideUIFolder and sideUIFolder:WaitForChild("ShopUI", 5)
local invModule = sideUIFolder and sideUIFolder:WaitForChild("InventoryUI", 5)
local optionsModule = sideUIFolder and sideUIFolder:WaitForChild("OptionsUI", 5)
local questsModule = sideUIFolder and sideUIFolder:WaitForChild("DailyQuestsUI", 5)
local boostsModule = sideUIFolder and sideUIFolder:WaitForChild("BoostsUI", 5)
if not sideUIFolder then
    warn("[SideUI] SideUI folder not found in ReplicatedStorage – modals unavailable")
end

local function updateHeaderCoins()
    local coins = 0
    -- Try coinApi first (tracks live value from CoinDisplay)
    if coinApi and coinApi.GetCoins then
        local ok, val = pcall(function() return coinApi.GetCoins() end)
        if ok and type(val) == "number" then coins = val end
    end
    -- If still 0, try server
    if coins == 0 then
        pcall(function()
            local getCoinsFn = ReplicatedStorage:FindFirstChild("GetCoins")
            if getCoinsFn and getCoinsFn:IsA("RemoteFunction") then
                local res = getCoinsFn:InvokeServer()
                if type(res) == "number" then coins = res end
            end
        end)
    end
    headerCoinLabel.Text = tostring(math.floor(coins))
end
-- Expose so ShopUI can trigger a refresh after purchase
_G.UpdateShopHeaderCoins = updateHeaderCoins

local function showModuleImmediate(mod, label)
    if not mod then return end
    clearContent()
    titleLabel.Text = label or "SHOP"
    local showCoins = (label == "SHOP" or label == "BOOSTS")
    headerCoinFrame.Visible = showCoins
    if showCoins then updateHeaderCoins() end
    pcall(function()
        local ok, loaded = pcall(require, mod)
        if ok and type(loaded.Create) == "function" then
            loaded.Create(contentFrame, coinApi, Inventory)
        end
    end)
    currentModule = mod
    -- animate into view
    tweenWindowIn()
end

local function requestShowModule(mod, label)
    if not mod then return end
    if isAnimating then return end
    -- If modal open with same module -> close
    if modalOverlay.Visible and currentModule == mod then
        tweenWindowOut()
        return
    end
    -- If modal open with a different module -> just close the current modal
    if modalOverlay.Visible and currentModule and currentModule ~= mod then
        tweenWindowOut()
        return
    end
    -- modal not visible -> open directly
    showModuleImmediate(mod, label)
end

shopBtn.MouseButton1Click:Connect(function()
    requestShowModule(shopModule, "SHOP")
end)

invBtn.MouseButton1Click:Connect(function()
    requestShowModule(invModule, "INVENTORY")
end)

-- Coin row from CoinDisplay module (auto-wires to server remotes)
local coinRow
if CoinDisplayModule and CoinDisplayModule.Create then
    coinRow, coinApi = CoinDisplayModule.Create(panel, 2)
    print("[SideUI] CoinDisplay module initialized; coinApi =", tostring(coinApi))
    -- Refresh header immediately once the coin API is available so joins show correct value
    pcall(function() updateHeaderCoins() end)
end

-- Listen for server coin updates. Uses task.spawn + WaitForChild so the remote
-- is found reliably in Team Test without blocking the rest of UI init.
task.spawn(function()
    local coinsEvent = ReplicatedStorage:WaitForChild("CoinsUpdated", 10)
    if coinsEvent and coinsEvent:IsA("RemoteEvent") then
        coinsEvent.OnClientEvent:Connect(function(amount)
            headerCoinLabel.Text = tostring(math.floor(tonumber(amount) or 0))
        end)
        pcall(updateHeaderCoins)
    else
        warn("[SideUI] CoinsUpdated remote not found – coin header won't auto-update")
    end
end)

-- Deferred retry to catch slow DataStore loads (same schedule as CoinDisplay)
task.spawn(function()
    local delays = {1, 2, 3, 5}
    for _, d in ipairs(delays) do
        task.wait(d)
        pcall(updateHeaderCoins)
    end
end)

--------------------------------------------------------------------------------
-- Active Boosts HUD  – Floating Roblox-style buff icons above Shop/Inv row
-- Each active timed boost gets a rounded-square tile with icon, green active
-- indicator, and a mm:ss countdown underneath. Hidden when nothing is active.
--------------------------------------------------------------------------------
local boostIconTiles  = {} -- [boostId] = { tile, timerLabel, expiresAt }
local boostHudFrame        -- container frame
local boostHudConn         -- Heartbeat connection for countdown ticks

do
    local RunService = game:GetService("RunService")

    -- Load BoostConfig for definitions
    local BoostConfigHud
    pcall(function()
        local mod = ReplicatedStorage:WaitForChild("BoostConfig", 5)
        if mod and mod:IsA("ModuleScript") then BoostConfigHud = require(mod) end
    end)

    -- Icon images (prefer real asset ids; fall back to AssetCodes or glyph text)
    local ICON_ASSETS = {}         -- [boostId] = assetId string (set below)
    local ICON_GLYPHS = {          -- fallback emoji / text if no image
        coins_2x = "\u{1F4B0}",
        quest_2x = "\u{26A1}",
    }
    local ICON_TINT = {
        coins_2x = Color3.fromRGB(255, 215, 80),
        quest_2x = Color3.fromRGB(100, 180, 255),
    }

    -- Try to pull asset ids from AssetCodes
    pcall(function()
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local coinId = AssetCodes.Get("Coin")
            if coinId and #coinId > 0 then ICON_ASSETS["coins_2x"] = coinId end
            local questId = AssetCodes.Get("Quests")
            if questId and #questId > 0 then ICON_ASSETS["quest_2x"] = questId end
        end
    end)

    -- Tile sizing  (≈2x the original for readability)
    local TILE_SIZE  = px(88)
    local TILE_GAP   = px(10)
    local TIMER_H    = px(18)
    -- px(36) bottom buffer keeps the whole cluster (icons + timers) clearly above Shop/Inv
    local TOTAL_H    = TILE_SIZE + px(4) + TIMER_H + px(36)  -- icon + gap + timer + bottom spacing

    -- Container: sits above ShopInvRow via LayoutOrder = 0
    boostHudFrame = Instance.new("Frame")
    boostHudFrame.Name = "ActiveBoostIcons"
    boostHudFrame.LayoutOrder = 0
    boostHudFrame.BackgroundTransparency = 1
    boostHudFrame.Size = UDim2.new(1, 0, 0, TOTAL_H)
    boostHudFrame.Visible = false
    boostHudFrame.Parent = panel

    -- Horizontal layout so icons sit side by side, centered
    local iconsRow = Instance.new("Frame")
    iconsRow.Name = "IconsRow"
    iconsRow.BackgroundTransparency = 1
    iconsRow.Size = UDim2.new(1, 0, 1, 0)
    iconsRow.Parent = boostHudFrame

    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Padding = UDim.new(0, TILE_GAP)
    rowLayout.Parent = iconsRow

    ---------------------------------------------------------------------------
    -- Build a single icon tile for a boost
    ---------------------------------------------------------------------------
    local function createBoostTile(boostId, expiresAt)
        -- Wrapper frame for icon + timer stacked vertically
        local wrapper = Instance.new("Frame")
        wrapper.Name = "BoostTile_" .. boostId
        wrapper.BackgroundTransparency = 1
        wrapper.Size = UDim2.new(0, TILE_SIZE, 0, TOTAL_H)
        wrapper.LayoutOrder = (boostId == "coins_2x") and 1 or 2
        wrapper.Parent = iconsRow

        -- Icon tile (rounded square)
        local tile = Instance.new("Frame")
        tile.Name = "Tile"
        tile.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
        tile.BackgroundColor3 = Color3.fromRGB(18, 20, 34)
        tile.BackgroundTransparency = 0.1
        tile.Parent = wrapper

        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(0, px(12))
        tCorner.Parent = tile

        local tStroke = Instance.new("UIStroke")
        tStroke.Color = COLORS.gold
        tStroke.Thickness = 2
        tStroke.Transparency = 0.12
        tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        tStroke.Parent = tile

        -- Icon content (image or text glyph)
        local assetId = ICON_ASSETS[boostId]
        if assetId then
            local img = Instance.new("ImageLabel")
            img.Name = "Icon"
            img.BackgroundTransparency = 1
            img.Size = UDim2.new(0.60, 0, 0.60, 0)
            img.AnchorPoint = Vector2.new(0.5, 0.5)
            img.Position = UDim2.new(0.5, 0, 0.48, 0)
            img.Image = assetId
            img.ScaleType = Enum.ScaleType.Fit
            img.ImageColor3 = ICON_TINT[boostId] or Color3.new(1, 1, 1)
            img.Parent = tile
        else
            local glyph = Instance.new("TextLabel")
            glyph.Name = "Glyph"
            glyph.BackgroundTransparency = 1
            glyph.Size = UDim2.new(1, 0, 0.75, 0)
            glyph.AnchorPoint = Vector2.new(0.5, 0.5)
            glyph.Position = UDim2.new(0.5, 0, 0.48, 0)
            glyph.Font = Enum.Font.GothamBold
            glyph.Text = ICON_GLYPHS[boostId] or "\u{2728}"
            glyph.TextSize = math.max(24, math.floor(TILE_SIZE * 0.42))
            glyph.TextColor3 = ICON_TINT[boostId] or COLORS.gold
            glyph.Parent = tile
        end

        -- Green active indicator (small checkmark badge, top-right corner)
        local badge = Instance.new("Frame")
        badge.Name = "ActiveBadge"
        badge.Size = UDim2.new(0, px(20), 0, px(20))
        badge.AnchorPoint = Vector2.new(1, 0)
        badge.Position = UDim2.new(1, px(4), 0, -px(4))
        badge.BackgroundColor3 = Color3.fromRGB(40, 180, 60)
        badge.Parent = tile

        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(1, 0)
        badgeCorner.Parent = badge

        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color = Color3.fromRGB(20, 80, 30)
        badgeStroke.Thickness = 1.5
        badgeStroke.Parent = badge

        local checkmark = Instance.new("TextLabel")
        checkmark.Name = "Check"
        checkmark.BackgroundTransparency = 1
        checkmark.Size = UDim2.new(1, 0, 1, 0)
        checkmark.Font = Enum.Font.GothamBold
        checkmark.Text = "\u{2713}"
        checkmark.TextSize = math.max(11, math.floor(px(12)))
        checkmark.TextColor3 = Color3.new(1, 1, 1)
        checkmark.Parent = badge

        -- Subtle green glow behind the tile (using a slightly larger transparent frame)
        local glow = Instance.new("Frame")
        glow.Name = "Glow"
        glow.Size = UDim2.new(1, px(6), 1, px(6))
        glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.Position = UDim2.new(0.5, 0, 0.5, 0)
        glow.BackgroundColor3 = Color3.fromRGB(40, 180, 60)
        glow.BackgroundTransparency = 0.78
        glow.ZIndex = 0
        glow.Parent = tile
        local glowCorner = Instance.new("UICorner")
        glowCorner.CornerRadius = UDim.new(0, px(14))
        glowCorner.Parent = glow

        -- Timer label underneath
        local timerLabel = Instance.new("TextLabel")
        timerLabel.Name = "Timer"
        timerLabel.BackgroundTransparency = 1
        timerLabel.Size = UDim2.new(1, 0, 0, TIMER_H)
        timerLabel.Position = UDim2.new(0, 0, 0, TILE_SIZE + px(3))
        timerLabel.Font = Enum.Font.GothamBold
        timerLabel.Text = "--:--"
        timerLabel.TextSize = math.max(13, math.floor(px(14)))
        timerLabel.TextColor3 = COLORS.gold
        timerLabel.TextXAlignment = Enum.TextXAlignment.Center
        timerLabel.Parent = wrapper

        boostIconTiles[boostId] = {
            tile = wrapper,
            timerLabel = timerLabel,
            expiresAt = expiresAt,
        }
    end

    ---------------------------------------------------------------------------
    local function removeTile(boostId)
        local info = boostIconTiles[boostId]
        if info and info.tile then
            pcall(function() info.tile:Destroy() end)
        end
        boostIconTiles[boostId] = nil
    end

    local function refreshVisibility()
        local any = false
        for _, info in pairs(boostIconTiles) do
            if info.tile and info.tile.Parent then any = true; break end
        end
        boostHudFrame.Visible = any
    end

    ---------------------------------------------------------------------------
    -- Apply full boost state from server
    ---------------------------------------------------------------------------
    local function applyBoostStates(states)
        if type(states) ~= "table" then return end
        local srvTime = states._serverTime or os.time()
        local delta = os.time() - srvTime
        print("[BoostHUD] State update, serverTime offset:", delta)

        local activeIds = {}
        if BoostConfigHud and BoostConfigHud.Boosts then
            for _, def in ipairs(BoostConfigHud.Boosts) do
                if def.Type == "Timed" then
                    local st = states[def.Id]
                    if st and st.active then
                        local localExpire = (st.expiresAt or 0) + delta
                        if localExpire > os.time() then
                            activeIds[def.Id] = localExpire
                        end
                    end
                end
            end
        end

        for bid, _ in pairs(boostIconTiles) do
            if not activeIds[bid] then removeTile(bid) end
        end
        for bid, expAt in pairs(activeIds) do
            if boostIconTiles[bid] and boostIconTiles[bid].tile.Parent then
                boostIconTiles[bid].expiresAt = expAt
            else
                createBoostTile(bid, expAt)
            end
        end
        refreshVisibility()
    end

    ---------------------------------------------------------------------------
    -- Countdown tick (once per second)
    ---------------------------------------------------------------------------
    local lastTick = 0
    boostHudConn = RunService.Heartbeat:Connect(function()
        local now = os.time()
        if now == lastTick then return end
        lastTick = now

        local changed = false
        for bid, info in pairs(boostIconTiles) do
            if info.tile and info.tile.Parent then
                local remaining = info.expiresAt - now
                if remaining > 0 then
                    local mins = math.floor(remaining / 60)
                    local secs = remaining % 60
                    info.timerLabel.Text = string.format("%02d:%02d", mins, secs)
                else
                    removeTile(bid)
                    changed = true
                end
            end
        end
        if changed then refreshVisibility() end
    end)

    ---------------------------------------------------------------------------
    -- Remote connections (reuse existing BoostStateUpdated + GetBoostStates)
    ---------------------------------------------------------------------------
    task.spawn(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then return end
        local stateEv = remotes:WaitForChild("BoostStateUpdated", 10)
        if not stateEv or not stateEv:IsA("RemoteEvent") then
            warn("[BoostHUD] BoostStateUpdated remote not found")
            return
        end
        stateEv.OnClientEvent:Connect(function(states) applyBoostStates(states) end)
        print("[BoostHUD] Listening for BoostStateUpdated")
    end)

    task.spawn(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then return end
        local boostDir = remotes:WaitForChild("Boosts", 5)
        if not boostDir then return end
        local getStates = boostDir:FindFirstChild("GetBoostStates")
        if getStates and getStates:IsA("RemoteFunction") then
            local ok, states = pcall(function() return getStates:InvokeServer() end)
            if ok and type(states) == "table" then applyBoostStates(states) end
        end
    end)
end
--------------------------------------------------------------------------------

local menuGridContainer = CreateMenuGrid(panel)

-- populate menu buttons from definitions
for _, def in ipairs(MENU_DEFS) do
    local btn, badge = CreateMenuButton(def)
    btn.LayoutOrder = #buttonsById + 1
    btn.Parent = menuGridContainer
    buttonsById[def.id] = btn
    badgesById[def.id] = badge
end

-- Exposed API
local function SetCoins(amount)
    if coinApi and coinApi.SetCoins then
        coinApi.SetCoins(amount)
    end
end

local function SetBadge(id, enabled)
    local badge = badgesById[id]
    if badge then
        badge.Visible = enabled and true or false
    end
end

local function OpenPage(id)
    if id == "Options" then
        requestShowModule(optionsModule, "OPTIONS")
        return
    end
    if id == "Missions" then
        requestShowModule(questsModule, "DAILY QUESTS")
        return
    end
    if id == "Boosts" then
        requestShowModule(boostsModule, "BOOSTS")
        return
    end
    print("OpenPage:", id)
    -- placeholder; integrate your page switching here
end

-- Expose simple handlers via a small global table so other local scripts can call them
-- (using _G avoids assigning arbitrary members on the Instance which can error)
_G.SideUI = _G.SideUI or {}
_G.SideUI.SetCoins = SetCoins
_G.SideUI.SetBadge = SetBadge
_G.SideUI.OpenPage = OpenPage

-- default handlers (can be overridden by assigning to script.OnShop/script.OnMenuButton)
-- Assign to the forward-declared scriptHandlers table (line ~106) so click closures above see these
scriptHandlers.OnShop = function()
    print("Shop")
end
scriptHandlers.OnInventory = function()
    print("Inventory")
end
scriptHandlers.OnMenuButton = function(id)
    OpenPage(id)
end

-- initial default state: only default to 0 if CoinDisplay failed to initialize
if not coinApi then
    SetCoins(0)
end
for id,_ in pairs(badgesById) do SetBadge(id, false) end


-- OPTIONAL: small convenience to return refs (not required, but handy during dev)
pcall(function() script.buttonsById = buttonsById end)
pcall(function() script.badgesById = badgesById end)

-- finished building UI
return nil