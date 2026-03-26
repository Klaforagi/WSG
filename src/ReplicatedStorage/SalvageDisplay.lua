--------------------------------------------------------------------------------
-- SalvageDisplay.lua  –  Client-side Salvage currency row for the HUD
--
-- Mirrors the CoinDisplay / KeyDisplay pattern.
-- Usage:
--   local SalvageDisplay = require(ReplicatedStorage:WaitForChild("SalvageDisplay"))
--   local row, api = SalvageDisplay.Create(parentFrame, layoutOrder)
--   -- api.SetSalvage(123)   (auto-updates from server via SalvageUpdated)
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local COLORS = {
    salvageGreen = Color3.fromRGB(35, 190, 75),
    white        = Color3.fromRGB(245, 245, 245),
    rowBg        = Color3.fromRGB(22, 24, 42),
}

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75
local function tpx(base)
    return math.max(1, math.round(px(base) * deviceTextScale))
end

local SalvageDisplay = {}

function SalvageDisplay.Create(parent, layoutOrder)
    local row = Instance.new("Frame")
    row.Name = "SalvageRow"
    row.LayoutOrder = layoutOrder or 4
    row.BackgroundTransparency = 1
    row.Parent = parent

    local function calcRowHeight()
        local screenY = 720
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            screenY = cam.ViewportSize.Y
        end
        return math.max(28, math.floor(screenY * 0.05))
    end
    row.Size = UDim2.new(1, 0, 0, calcRowHeight())

    -- Inner background
    local inner = Instance.new("Frame")
    inner.Name = "SalvageInner"
    inner.Size = UDim2.new(1, 0, 1, 0)
    inner.BackgroundTransparency = 0
    inner.BackgroundColor3 = Color3.new(1, 1, 1)
    inner.BorderSizePixel = 0
    inner.ClipsDescendants = false
    inner.Parent = row

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(6))
    corner.Parent = inner

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.salvageGreen
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inner

    -- Gradient background (green-tinted, team-aware)
    local function getSalvageSeq()
        local lp = Players.LocalPlayer
        local team = lp and lp.Team
        local base
        if team and team.Name ~= "Neutral" then
            if team.Name == "Blue" then
                base = Color3.fromRGB(12, 51, 168)
            elseif team.Name == "Red" then
                base = Color3.fromRGB(202, 24, 24)
            else
                base = team.TeamColor.Color
            end
            base = base:Lerp(Color3.new(0, 0, 0), 0.12)
        else
            base = Color3.fromRGB(20, 30, 50)
        end
        local dark = base:Lerp(Color3.fromRGB(4, 4, 6), 0.72)
        return ColorSequence.new({
            ColorSequenceKeypoint.new(0, dark),
            ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(1, 1, 1), 0.12)),
        })
    end

    local salvageGradient = Instance.new("UIGradient")
    salvageGradient.Rotation = 135
    salvageGradient.Color = getSalvageSeq()
    salvageGradient.Parent = inner

    local lp = Players.LocalPlayer
    if lp then
        lp:GetPropertyChangedSignal("Team"):Connect(function()
            if salvageGradient and salvageGradient.Parent then
                salvageGradient.Color = getSalvageSeq()
            end
        end)
    end

    -- Salvage icon (gear glyph)
    local salvageIcon = Instance.new("TextLabel")
    salvageIcon.Name = "SalvageIcon"
    salvageIcon.BackgroundTransparency = 1
    salvageIcon.AnchorPoint = Vector2.new(0, 0.5)
    salvageIcon.Position = UDim2.new(0, px(8), 0.5, 0)
    salvageIcon.Size = UDim2.new(0, px(24), 0, px(24))
    salvageIcon.Font = Enum.Font.GothamBold
    salvageIcon.Text = "\u{2699}" -- ⚙
    salvageIcon.TextSize = tpx(18)
    salvageIcon.TextColor3 = COLORS.salvageGreen
    salvageIcon.TextXAlignment = Enum.TextXAlignment.Center
    salvageIcon.Parent = inner

    -- Value label
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "SalvageValue"
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBlack
    valueLabel.TextScaled = true
    valueLabel.TextColor3 = COLORS.salvageGreen
    valueLabel.Text = "0"
    valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    valueLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    valueLabel.Size = UDim2.new(0.5, 0, 0.7, 0)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.Parent = inner

    -- API
    local api = {}
    local currentSalvage = 0

    function api.SetSalvage(amount)
        amount = math.max(0, tonumber(amount) or 0)
        currentSalvage = math.floor(amount)
        valueLabel.Text = tostring(currentSalvage)
    end

    function api.GetSalvage()
        return currentSalvage
    end

    -- Wire to server CurrencyService remotes
    local salvageEvent = ReplicatedStorage:FindFirstChild("SalvageUpdated")
    local getSalvageFn = ReplicatedStorage:FindFirstChild("GetSalvage")
    if not salvageEvent then
        pcall(function() salvageEvent = ReplicatedStorage:WaitForChild("SalvageUpdated", 6) end)
    end
    if not getSalvageFn then
        pcall(function() getSalvageFn = ReplicatedStorage:WaitForChild("GetSalvage", 6) end)
    end

    -- Listen for server pushes
    if salvageEvent and salvageEvent:IsA("RemoteEvent") then
        salvageEvent.OnClientEvent:Connect(function(amount)
            pcall(function() api.SetSalvage(amount) end)
        end)
    end

    -- Fetch initial value with retry
    if getSalvageFn and getSalvageFn:IsA("RemoteFunction") then
        local function tryFetch()
            local ok, result = pcall(function() return getSalvageFn:InvokeServer() end)
            if ok and type(result) == "number" then
                pcall(function() api.SetSalvage(result) end)
                return true
            end
            return false
        end
        task.spawn(function()
            if tryFetch() and currentSalvage > 0 then return end
            local delays = { 0.5, 1.0, 1.5, 2.0 }
            for _, d in ipairs(delays) do
                task.wait(d)
                if tryFetch() and currentSalvage > 0 then return end
            end
        end)
    end

    return row, api
end

return SalvageDisplay
