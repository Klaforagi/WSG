-- SideUI.client.lua
-- Main hub menu UI. Coin display is handled by the CoinDisplay module in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Try to load AssetCodes safely (may be absent in some environments)
local AssetCodes = nil
do
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        pcall(function() AssetCodes = require(mod) end)
    end
end

-- Config / constants
-- Panel sizing: compact, scales with screen size
local PANEL_WIDTH = UDim2.new(0.11, 0, 0, 0) -- width only; height is AutomaticSize (halved)
local PANEL_ANCHOR = Vector2.new(0, 0.5) -- left side, vertically centered
local PANEL_POS = UDim2.new(0, 8, 0.5, 0) -- left side, centered vertically

local COLORS = {
    panelBg = Color3.fromRGB(12, 14, 28),
    gold = Color3.fromRGB(255, 215, 80),
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
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.gold
    stroke.Thickness = 1
    stroke.Transparency = 1
    stroke.Parent = panel

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
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
    corner.CornerRadius = UDim.new(0, 8)
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

local function CreateShopButton(parent)
    local btn = makeTextButtonBase("SHOP")
    btn.Name = "ShopButton"
    btn.LayoutOrder = 1
    btn.Size = UDim2.new(1, 0, 0, 48)
    btn.Parent = parent
    -- allow children (icon) to overflow the button bounds for a "pop out" effect
    btn.ClipsDescendants = false

    -- optional shop icon (centered, larger)
    local icon = nil
    local shopAsset = (AssetCodes and type(AssetCodes.Get) == "function") and AssetCodes.Get("Shop")
    -- hide the button's built-in text; we'll draw a smaller overlay above the icon
    btn.Text = ""
    if shopAsset and type(shopAsset) == "string" then
        icon = Instance.new("ImageLabel")
        icon.Name = "ShopIcon"
        icon.Size = UDim2.new(0, 96, 0, 96) -- slightly bigger for stronger emphasis
        icon.Position = UDim2.new(0.5, 0, 0.38, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.BackgroundTransparency = 1
        icon.Image = shopAsset
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ZIndex = 1
        icon.Parent = btn
        -- overlay text on top of icon
        local overlay = Instance.new("TextLabel")
        overlay.Name = "ShopOverlayLabel"
        overlay.BackgroundTransparency = 1
        overlay.Size = UDim2.new(0.9, 0, 0, 18)
        overlay.Position = UDim2.new(0.5, 0, 1, -2)
        overlay.AnchorPoint = Vector2.new(0.5, 1)
        overlay.Font = Enum.Font.GothamBold
        overlay.Text = "SHOP"
        overlay.TextColor3 = COLORS.gold
        overlay.TextSize = 16
        overlay.TextScaled = false
        overlay.TextXAlignment = Enum.TextXAlignment.Center
        overlay.TextYAlignment = Enum.TextYAlignment.Center
        overlay.ZIndex = 2
        overlay.Parent = btn
        local overlayStroke = Instance.new("UIStroke")
        overlayStroke.Color = Color3.fromRGB(0,0,0)
        overlayStroke.Transparency = 0.6
        overlayStroke.Thickness = 1
        overlayStroke.Parent = overlay
    else
        btn.Text = "SHOP"
        btn.TextXAlignment = Enum.TextXAlignment.Center
    end

    -- hover & click feedback
    btn.MouseEnter:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.02}, TweenInfo.new(0.12))
    end)
    btn.MouseLeave:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.12}, TweenInfo.new(0.12))
    end)
    btn.MouseButton1Click:Connect(function()
        -- simple click flash
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.06))
        task.delay(0.09, function() tweenInstance(btn, {BackgroundTransparency = 0.12}, TweenInfo.new(0.12)) end)
        -- action
        if script and script.Parent then
            -- call exposed handler
            if script.OnShop and type(script.OnShop) == "function" then
                pcall(script.OnShop)
            else
                print("Shop")
            end
        end
    end)

    return btn
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
    grid.CellSize = UDim2.new(0, 54, 0, 54)
    grid.CellPadding = UDim2.new(0, 6, 0, 6)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 3
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Top
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = gridContainer

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingLeft = UDim.new(0, 0)
    padding.PaddingRight = UDim.new(0, 0)
    padding.Parent = gridContainer

    -- Prefer sizing cells to match the Shop button width so 3 columns always fit.
    local shopBtn = parent:FindFirstChild("ShopButton")
    local function updateCellSize()
        local cols = grid.FillDirectionMaxCells or 3
        local cellPad = (grid and grid.CellPadding and grid.CellPadding.X) and grid.CellPadding.X.Offset or 6

        local sourceW = 0
        if shopBtn and shopBtn.AbsoluteSize and shopBtn.AbsoluteSize.X and shopBtn.AbsoluteSize.X > 0 then
            sourceW = shopBtn.AbsoluteSize.X
        else
            sourceW = gridContainer.AbsoluteSize.X
        end

        if sourceW <= 0 then return end
        local cellW = math.max(20, math.floor((sourceW - (cellPad * (cols - 1))) / cols))
        grid.CellSize = UDim2.new(0, cellW, 0, cellW)
    end

    if shopBtn then
        shopBtn:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCellSize)
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
    corner.CornerRadius = UDim.new(0, 8)
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
    nameLabel.Position = UDim2.new(0.5, 0, 1, -3)
    nameLabel.Size = UDim2.new(0.95, 0, 0, 11)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = def.label or def.id
    nameLabel.TextColor3 = COLORS.gold
    nameLabel.TextSize = 9
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
    badge.Size = UDim2.new(0, 16, 0, 16)
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Position = UDim2.new(1, -2, 0, -2)
    badge.BackgroundColor3 = COLORS.badgeBg
    badge.Text = "!"
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = 10
    badge.TextColor3 = Color3.new(1, 1, 1)
    badge.Visible = false
    badge.Parent = btn
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0)
    badgeCorner.Parent = badge

    -- hover & click feedback (subtle)
    btn.MouseEnter:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.12))
    end)
    btn.MouseLeave:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12))
    end)
    btn.MouseButton1Click:Connect(function()
        tweenInstance(btn, {BackgroundTransparency = 0}, TweenInfo.new(0.04))
        task.delay(0.06, function() tweenInstance(btn, {BackgroundTransparency = 0.08}, TweenInfo.new(0.12)) end)
        if script and script.OnMenuButton and type(script.OnMenuButton) == "function" then
            pcall(script.OnMenuButton, def.id)
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

-- Clear existing content in screenGui container area (optional safe-guard: only if it's our MainUICard)
local existing = screenGui:FindFirstChild("MainUICard")
if existing then existing:Destroy() end

local panel = CreatePanel(screenGui)
local shopBtn = CreateShopButton(panel)

-- Coin row from CoinDisplay module (auto-wires to server remotes)
local coinRow, coinApi
if CoinDisplayModule and CoinDisplayModule.Create then
    coinRow, coinApi = CoinDisplayModule.Create(panel, 2)
end

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

-- Expose simple handlers on the script so other client scripts can call them (usage: local s = script; s.SetCoins(123))
script.SetCoins = SetCoins
script.SetBadge = SetBadge
script.OpenPage = OpenPage

-- default handlers (can be overridden by assigning to script.OnShop/script.OnMenuButton)
script.OnShop = function()
    print("Shop")
end
script.OnMenuButton = function(id)
    OpenPage(id)
end

-- initial default state
SetCoins(0)
for id,_ in pairs(badgesById) do SetBadge(id, false) end


-- OPTIONAL: small convenience to return refs (not required, but handy during dev)
script.buttonsById = buttonsById
script.badgesById = badgesById

-- finished building UI
return nil