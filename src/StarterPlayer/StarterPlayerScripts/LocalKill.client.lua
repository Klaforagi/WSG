local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Listen to the same KillFeed event that the global feed uses
local killFeedEvent = ReplicatedStorage:WaitForChild("KillFeed")

-- UI: centered bottom indicator (styled like KillFeed but local-only)
local screen = Instance.new("ScreenGui")
screen.Name = "LocalKillGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "LocalKillContainer"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 0.85, 0)
container.Size = UDim2.new(0.3, 0, 0, 32)
container.BackgroundTransparency = 1
container.Parent = screen

local layout = Instance.new("UIListLayout")
layout.Parent = container
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 4)

local function getNameColor(name)
    if not name then return Color3.fromRGB(255,255,255) end
    local pl = Players:FindFirstChild(name)
    if pl and pl:IsA("Player") and pl.Team and pl.Team.TeamColor then
        return pl.Team.TeamColor.Color
    end
    return Color3.fromRGB(255,255,255)
end

local function showLocalKill(victimName)
    local entry = Instance.new("Frame")
    entry.Size = UDim2.new(1, 0, 0, 28)
    entry.BackgroundTransparency = 1
    entry.Parent = container

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
        lbl.TextSize = 24
        lbl.TextColor3 = color or Color3.fromRGB(255,255,255)
        lbl.TextStrokeTransparency = 0.6
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Size = UDim2.new(0, 0, 1, 0)
        lbl.Parent = entry
        return lbl
    end

    makeLabel("You", getNameColor(player.Name))
    makeLabel(" killed ", Color3.fromRGB(255,255,255))
    makeLabel(tostring(victimName or "Unknown"), getNameColor(victimName))

    -- fade out and remove after 4 seconds
    task.delay(4, function()
        if entry and entry.Parent then
            entry:Destroy()
        end
    end)
end

-- filter KillFeed for local player kills only
killFeedEvent.OnClientEvent:Connect(function(killerName, victimName)
    if killerName == player.Name then
        showLocalKill(victimName)
    end
end)

return nil
