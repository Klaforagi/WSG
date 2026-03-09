-- SideUI.client.lua
-- Main hub menu UI. Coin display is handled by the CoinDisplay module in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
print("[SideUI] initializing for", player and player.Name)

-- Scale pixel values proportionally to viewport height (reference: 1080p)
local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 1080
	return math.max(1, math.round(base * screenY / 1080))
end

-- Try to load AssetCodes safely (may be absent in some environments)
local AssetCodes = nil
do
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        pcall(function() AssetCodes = require(mod) end)
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

-- CoinDisplay module (ReplicatedStorage): creates coin row + wires server remotes
local CoinDisplayModule = nil
do
    local mod = ReplicatedStorage:FindFirstChild("CoinDisplay")
    if not mod then
        pcall(function() mod = ReplicatedStorage:WaitForChild("CoinDisplay", 6) end)
    end
    if mod and mod:IsA("ModuleScript") then
        pcall(function() CoinDisplayModule = require(mod) end)
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
    local equipped = nil -- track currently equipped item id
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
    function Inventory:SetEquipped(id)
        equipped = id
    end
    function Inventory:GetEquipped()
        return equipped
    end
end

-- preload Slingshot into the client inventory so player has ranged start
pcall(function() Inventory:AddItem("Slingshot") end)
pcall(function() Inventory:SetEquipped("Slingshot") end)

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
window.BackgroundColor3 = Color3.fromRGB(12, 14, 28)
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
titlePill.BackgroundColor3 = Color3.fromRGB(22, 40, 80)
titlePill.ZIndex = 10
titlePill.Parent = headerBar
local titlePillCorner = Instance.new("UICorner")
titlePillCorner.CornerRadius = UDim.new(0, px(8))
titlePillCorner.Parent = titlePill
local titlePillStroke = Instance.new("UIStroke")
titlePillStroke.Color = Color3.fromRGB(80, 140, 220)
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
local function hideModal()
    currentModule = nil
    modalOverlay.Visible = false
    clearContent()
end
closeBtn.MouseButton1Click:Connect(hideModal)

local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI")
local shopModule = sideUIFolder:FindFirstChild("ShopUI")
local invModule = sideUIFolder:FindFirstChild("InventoryUI")

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

local function showModule(mod, label)
    if not mod then return end
    clearContent()
    titleLabel.Text = label or "SHOP"
    -- Show coins only on SHOP page
    local isShop = (label == "SHOP")
    headerCoinFrame.Visible = isShop
    if isShop then updateHeaderCoins() end
    pcall(function()
        local ok, loaded = pcall(require, mod)
        if ok and type(loaded.Create) == "function" then
            loaded.Create(contentFrame, coinApi, Inventory)
        end
    end)
    modalOverlay.Visible = true
end

shopBtn.MouseButton1Click:Connect(function()
    if modalOverlay.Visible and currentModule == shopModule then
        hideModal()
    else
        if shopModule then showModule(shopModule, "SHOP") end
        currentModule = shopModule
    end
end)

invBtn.MouseButton1Click:Connect(function()
    if modalOverlay.Visible and currentModule == invModule then
        hideModal()
    else
        if invModule then showModule(invModule, "INVENTORY") end
        currentModule = invModule
    end
end)

-- Coin row from CoinDisplay module (auto-wires to server remotes)
local coinRow
if CoinDisplayModule and CoinDisplayModule.Create then
    coinRow, coinApi = CoinDisplayModule.Create(panel, 2)
    print("[SideUI] CoinDisplay module initialized; coinApi =", tostring(coinApi))
    -- Refresh header immediately once the coin API is available so joins show correct value
    pcall(function() updateHeaderCoins() end)
end

-- Also listen for server coin updates to keep header in sync
pcall(function()
    local coinsEvent = ReplicatedStorage:FindFirstChild("CoinsUpdated")
    if coinsEvent and coinsEvent:IsA("RemoteEvent") then
        coinsEvent.OnClientEvent:Connect(function(amount)
            headerCoinLabel.Text = tostring(math.floor(tonumber(amount) or 0))
        end)
        -- ensure header reflects latest value after wiring the event
        pcall(function() updateHeaderCoins() end)
    end
end)

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
-- Use a local handlers table instead of assigning arbitrary fields on the Script Instance
local scriptHandlers = {}
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