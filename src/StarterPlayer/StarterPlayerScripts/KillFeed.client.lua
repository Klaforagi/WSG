local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local killFeedEvent = ReplicatedStorage:WaitForChild("KillFeed")

-- try to require AssetCodes for coin image
local AssetCodes = nil
pcall(function()
    AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes", 5))
end)

-- Fantasy PvP theme palette
local NAVY       = Color3.fromRGB(12, 14, 28)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)
local WHITE       = GOLD_TEXT

-- create UI container in PlayerGui
local screen = Instance.new("ScreenGui")
screen.Name = "KillFeedGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -16, 0.10, 0)
frame.Size = UDim2.new(0, 0, 0.30, 0)
frame.AutomaticSize = Enum.AutomaticSize.X
frame.BackgroundTransparency = 1
frame.Parent = screen

local uiLayout = Instance.new("UIListLayout")
uiLayout.Parent = frame
uiLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
uiLayout.VerticalAlignment = Enum.VerticalAlignment.Top
uiLayout.Padding = UDim.new(0, 4)

local camera = workspace.CurrentCamera
local function getEntryMetrics()
    local vh = 720
    if camera and camera.ViewportSize and camera.ViewportSize.Y then
        vh = camera.ViewportSize.Y
    end
    local entryHeight = math.clamp(math.floor(vh * 0.038), 16, 40)
    local padding = math.clamp(math.floor(vh * 0.008), 3, 10)
    local textSize = math.clamp(math.floor(entryHeight * 0.55), 10, 20)
    return entryHeight, padding, textSize
end

if camera then
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        local _, padding = getEntryMetrics()
        uiLayout.Padding = UDim.new(0, padding)
    end)
    uiLayout.Padding = UDim.new(0, select(2, getEntryMetrics()))
end

local function getNameColor(name)
    if not name then return WHITE end
    local pl = Players:FindFirstChild(name)
    if pl and pl:IsA("Player") and pl.Team and pl.Team.TeamColor then
        return pl.Team.TeamColor.Color
    end
    return WHITE
end

local function pushKillText(killer, victim, coinAmount)
    local entryHeight, _, textSize = getEntryMetrics()

    -- dark navy pill with subtle gold border
    local entry = Instance.new("Frame")
    entry.Size = UDim2.new(0, 0, 0, entryHeight)
    entry.AutomaticSize = Enum.AutomaticSize.X
    entry.BackgroundColor3 = NAVY
    entry.BackgroundTransparency = 0.12
    entry.BorderSizePixel = 0
    entry.ClipsDescendants = true
    entry.Parent = frame

    local entryCorner = Instance.new("UICorner")
    entryCorner.CornerRadius = UDim.new(0, 4)
    entryCorner.Parent = entry

    local entryStroke = Instance.new("UIStroke")
    entryStroke.Color = Color3.fromRGB(60, 55, 35)
    entryStroke.Thickness = 1
    entryStroke.Transparency = 0.5
    entryStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    entryStroke.Parent = entry

    local entryPad = Instance.new("UIPadding")
    entryPad.PaddingLeft = UDim.new(0, 6)
    entryPad.PaddingRight = UDim.new(0, 6)
    entryPad.Parent = entry

    local hLayout = Instance.new("UIListLayout")
    hLayout.Parent = entry
    hLayout.FillDirection = Enum.FillDirection.Horizontal
    hLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    hLayout.SortOrder = Enum.SortOrder.LayoutOrder
    hLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local function makeLabel(txt, color)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = tostring(txt or "?")
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = math.clamp(textSize + 1, 11, 22)
        lbl.TextColor3 = color or WHITE
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Size = UDim2.new(0, 0, 1, 0)
        lbl.Parent = entry
        local lblStroke = Instance.new("UIStroke")
        lblStroke.Color = Color3.fromRGB(0, 0, 0)
        lblStroke.Thickness = 0.8
        lblStroke.Transparency = 0.4
        lblStroke.Parent = lbl
        return lbl
    end

    makeLabel(killer, getNameColor(killer))
    makeLabel(" killed ", GOLD_TEXT)
    makeLabel(victim, getNameColor(victim))
    if coinAmount and type(coinAmount) == "number" and coinAmount > 0 then
        -- show +N and coin image if available
        makeLabel(" +" .. tostring(coinAmount), GOLD_TEXT)
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local id = nil
            pcall(function() id = AssetCodes.Get("Coin") end)
            if id and type(id) == "string" then
                local img = Instance.new("ImageLabel")
                img.BackgroundTransparency = 1
                img.Size = UDim2.new(0, 18, 0, 18)
                img.Image = id
                img.ScaleType = Enum.ScaleType.Fit
                img.Parent = entry
            else
                -- fallback to emoji if image not available
                makeLabel("🪙", GOLD_TEXT)
            end
        else
            makeLabel("🪙", GOLD_TEXT)
        end
    end

    -- pop-in: slide from right + fade
    entry.Position = UDim2.new(0.15, 0, 0, 0)
    entry.BackgroundTransparency = 1
    TweenService:Create(entry, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 0.12,
    }):Play()

    -- fade out after 4s total
    task.delay(3.5, function()
        if entry and entry.Parent then
            for _, child in ipairs(entry:GetChildren()) do
                if child:IsA("TextLabel") then
                    TweenService:Create(child, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
                end
            end
            local fadeOut = TweenService:Create(entry, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
            })
            fadeOut:Play()
            fadeOut.Completed:Wait()
            if entry and entry.Parent then entry:Destroy() end
        end
    end)
end

killFeedEvent.OnClientEvent:Connect(function(killerName, victimName, coinAmount)
    pcall(function()
        pushKillText(killerName, victimName, coinAmount)
    end)
end)

return nil
