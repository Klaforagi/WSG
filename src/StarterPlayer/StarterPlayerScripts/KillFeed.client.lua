local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local killFeedEvent = ReplicatedStorage:WaitForChild("KillFeed")

-- create UI container in PlayerGui
local screen = Instance.new("ScreenGui")
screen.Name = "KillFeedGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(1, 0)
-- move down 10% of screen and anchor to right edge
frame.Position = UDim2.new(1, -16, 0.10, 0)
-- size is proportional to screen (25% width, 25% height)
frame.Size = UDim2.new(0.25, 0, 0.25, 0)
frame.BackgroundTransparency = 1
frame.Parent = screen

local uiLayout = Instance.new("UIListLayout")
uiLayout.Parent = frame
uiLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
uiLayout.VerticalAlignment = Enum.VerticalAlignment.Top
-- padding will be set relative to viewport size below
uiLayout.Padding = UDim.new(0, 6)

local camera = workspace.CurrentCamera
local function getEntryMetrics()
    local vh = 720
    if camera and camera.ViewportSize and camera.ViewportSize.Y then
        vh = camera.ViewportSize.Y
    end
    local entryHeight = math.clamp(math.floor(vh * 0.035), 12, 36)
    local padding = math.clamp(math.floor(vh * 0.01), 4, 12)
    local textSize = math.clamp(math.floor(entryHeight * 0.6), 10, 22)
    return entryHeight, padding, textSize
end

-- update padding on resize
if camera then
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        local _, padding = getEntryMetrics()
        uiLayout.Padding = UDim.new(0, padding)
    end)
    -- initialize padding
    uiLayout.Padding = UDim.new(0, select(2, getEntryMetrics()))
end

local function getNameColor(name)
    if not name then return Color3.fromRGB(255,255,255) end
    local pl = Players:FindFirstChild(name)
    if pl and pl:IsA("Player") then
        if pl.Team and pl.Team.TeamColor then
            return pl.Team.TeamColor.Color
        else
            return Color3.fromRGB(255,255,255)
        end
    end
    return Color3.fromRGB(255,255,255)
end

local function pushKillText(killer, victim)
    local entryHeight, _, textSize = getEntryMetrics()
    local entry = Instance.new("Frame")
    entry.Size = UDim2.new(1, 0, 0, entryHeight)
    entry.BackgroundTransparency = 1
    entry.Parent = frame

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
        lbl.TextSize = math.clamp(textSize + 2, 12, 28) -- slightly larger
        lbl.TextColor3 = color or Color3.fromRGB(255,255,255)
        lbl.TextStrokeTransparency = 0.6
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Parent = entry
        return lbl
    end

    -- create labels: killer, verb, victim (right-aligned in the container)
    local killerLbl = makeLabel(killer, getNameColor(killer))
    local verbLbl = makeLabel(" killed ", Color3.fromRGB(255,255,255))
    local victimLbl = makeLabel(victim, getNameColor(victim))

    -- remove after 4 seconds
    task.delay(4, function()
        if entry and entry.Parent then
            entry:Destroy()
        end
    end)
end

killFeedEvent.OnClientEvent:Connect(function(killerName, victimName)
    pcall(function()
        pushKillText(killerName, victimName)
    end)
end)

return nil
