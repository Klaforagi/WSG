local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Listen to the same KillFeed event that the global feed uses
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

-- UI: centered bottom indicator
local screen = Instance.new("ScreenGui")
screen.Name = "LocalKillGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "LocalKillContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 0.85, 0)
container.Size = UDim2.new(0, 0, 0, 36)
container.BackgroundTransparency = 1
container.AutomaticSize = Enum.AutomaticSize.X
container.Parent = screen

local layout = Instance.new("UIListLayout")
layout.Parent = container
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 4)

local function getNameColor(name)
    if not name then return WHITE end
    local pl = Players:FindFirstChild(name)
    if pl and pl:IsA("Player") and pl.Team and pl.Team.TeamColor then
        return pl.Team.TeamColor.Color
    end
    return WHITE
end

local function showLocalKill(victimName, coinAmount)
    -- dark navy pill
    local entry = Instance.new("Frame")
    entry.Size = UDim2.new(0, 0, 0, 32)
    entry.AutomaticSize = Enum.AutomaticSize.X
    entry.BackgroundColor3 = NAVY
    entry.BackgroundTransparency = 1
    entry.BorderSizePixel = 0
    entry.ClipsDescendants = true
    entry.Parent = container

    -- small horizontal padding so background is slightly wider than text
    local entryPad = Instance.new("UIPadding")
    entryPad.PaddingLeft = UDim.new(0, 8)
    entryPad.PaddingRight = UDim.new(0, 8)
    entryPad.Parent = entry

    local entryCorner = Instance.new("UICorner")
    entryCorner.CornerRadius = UDim.new(0, 4)
    entryCorner.Parent = entry

    local entryStroke = Instance.new("UIStroke")
    entryStroke.Color = Color3.fromRGB(60, 55, 35)
    entryStroke.Thickness = 1
    entryStroke.Transparency = 0.5
    entryStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    entryStroke.Parent = entry

    local row = Instance.new("UIListLayout")
    row.Parent = entry
    row.FillDirection = Enum.FillDirection.Horizontal
    row.HorizontalAlignment = Enum.HorizontalAlignment.Center
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder

    local function makeLabel(txt, color)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = tostring(txt or "?")
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 22
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

    makeLabel("You", getNameColor(player.Name))
    makeLabel(" killed ", GOLD_TEXT)
    makeLabel(tostring(victimName or "Unknown"), getNameColor(victimName))
    if coinAmount and type(coinAmount) == "number" and coinAmount > 0 then
        makeLabel(" +" .. tostring(coinAmount), GOLD_TEXT)
        if AssetCodes and type(AssetCodes.Get) == "function" then
            local id = nil
            pcall(function() id = AssetCodes.Get("Coin") end)
            if id and type(id) == "string" then
                local img = Instance.new("ImageLabel")
                img.BackgroundTransparency = 1
                img.Size = UDim2.new(0, 20, 0, 20)
                img.Image = id
                img.ScaleType = Enum.ScaleType.Fit
                img.Parent = entry
            else
                makeLabel("🪙", GOLD_TEXT)
            end
        else
            makeLabel("🪙", GOLD_TEXT)
        end
    end

    -- pop-in: fade background and text in
    TweenService:Create(entry, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.1,
    }):Play()
    for _, child in ipairs(entry:GetChildren()) do
        if child:IsA("TextLabel") then
            child.TextTransparency = 1
            TweenService:Create(child, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
        end
    end

    -- fade out after 4s
    task.delay(3.5, function()
        if entry and entry.Parent then
            for _, child in ipairs(entry:GetChildren()) do
                if child:IsA("TextLabel") then
                    TweenService:Create(child, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
                end
            end
            local fade = TweenService:Create(entry, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
            })
            TweenService:Create(entryStroke, TweenInfo.new(0.5), {Transparency = 1}):Play()
            fade:Play()
            fade.Completed:Wait()
            if entry and entry.Parent then entry:Destroy() end
        end
    end)
end

-- filter KillFeed for local player kills only
killFeedEvent.OnClientEvent:Connect(function(killerName, victimName, coinAmount)
    if killerName == player.Name then
        showLocalKill(victimName, coinAmount)
    end
end)

return nil
