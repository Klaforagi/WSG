--------------------------------------------------------------------------------
-- TeamUI.lua
-- Modal-based Team / Career Stats panel for SideUI modal host.
-- Implements: TeamUI.Create(parent, _coinApi, _inventoryApi)
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))

local TeamUI = {}

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local function createTeamPanel(parent)
    local panel = Instance.new("Frame")
    panel.Name = "TeamStatsPanel"
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundTransparency = 1
    panel.Parent = parent

    -- Simple header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, px(56))
    header.BackgroundTransparency = 1
    header.Parent = panel

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBlack
    title.Text = "TEAMS"
    title.TextSize = px(24)
    title.TextColor3 = Color3.fromRGB(230, 200, 80)
    title.Parent = header

    -- Content scrolling area
    local content = Instance.new("ScrollingFrame")
    content.Name = "Content"
    content.Position = UDim2.new(0, 0, 0, px(64))
    content.Size = UDim2.new(1, 0, 1, -px(64))
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, px(8))
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = content

    return panel, content, layout
end

local function buildPlayerRow(plr)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, px(48))
    row.BackgroundTransparency = 0.9
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = px(18)
    lbl.TextColor3 = Color3.fromRGB(235,235,240)
    lbl.Text = plr.DisplayName
    lbl.Parent = row
    return row
end

-- Public: Create(parent)
function TeamUI.Create(parent, _coinApi, _inventoryApi)
    if not parent then return end
    local host = Instance.new("Frame")
    host.Name = "TeamRoot"
    host.Size = UDim2.new(1, 0, 1, 0)
    host.BackgroundTransparency = 1
    host.LayoutOrder = 1
    host.Parent = parent

    local panel, content, layout = createTeamPanel(host)

    local playerRows = {}

    local function rebuild()
        -- clear
        for _, child in ipairs(content:GetChildren()) do
            if child:IsA("GuiObject") and child ~= layout then pcall(function() child:Destroy() end) end
        end
        -- Populate simple list grouped by team
        local function addSection(labelText)
            local sec = Instance.new("Frame")
            sec.Size = UDim2.new(1, 0, 0, px(28))
            sec.BackgroundTransparency = 1
            sec.Parent = content
            local lab = Instance.new("TextLabel")
            lab.Size = UDim2.new(1, 0, 1, 0)
            lab.BackgroundTransparency = 1
            lab.Font = Enum.Font.GothamBold
            lab.TextSize = px(16)
            lab.TextColor3 = Color3.fromRGB(180,180,190)
            lab.Text = labelText
            lab.TextXAlignment = Enum.TextXAlignment.Left
            lab.Parent = sec
        end

        addSection("Blue Team")
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Team and plr.Team.Name == "Blue" then
                local r = buildPlayerRow(plr)
                r.Parent = content
            end
        end
        addSection("Red Team")
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Team and plr.Team.Name == "Red" then
                local r = buildPlayerRow(plr)
                r.Parent = content
            end
        end
        addSection("Neutral")
        for _, plr in ipairs(Players:GetPlayers()) do
            if not plr.Team or (plr.Team.Name ~= "Blue" and plr.Team.Name ~= "Red") then
                local r = buildPlayerRow(plr)
                r.Parent = content
            end
        end
    end

    -- Simple listeners
    Players.PlayerAdded:Connect(function() rebuild() end)
    Players.PlayerRemoving:Connect(function() rebuild() end)
    for _, pl in ipairs(Players:GetPlayers()) do
        pl:GetPropertyChangedSignal("Team"):Connect(rebuild)
    end

    rebuild()

    return host
end

return TeamUI
