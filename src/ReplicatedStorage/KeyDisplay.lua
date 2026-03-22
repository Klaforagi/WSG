-- PREMIUM CRATE / KEY SYSTEM
-- KeyDisplay ModuleScript
-- Provides a reusable key-row UI element wired to CurrencyService remotes.
-- Usage from a client LocalScript:
--   local KeyDisplay = require(ReplicatedStorage:WaitForChild("KeyDisplay"))
--   local row, api = KeyDisplay.Create(parentFrame, layoutOrder)
--   -- api.SetKeys(5)   (manual override, but auto-updates from server)
--
-- Mirrors CoinDisplay.lua structure for consistency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local COLORS = {
    keyBlue = Color3.fromRGB(100, 200, 255),
    white   = Color3.fromRGB(245, 245, 245),
    rowBg   = Color3.fromRGB(22, 24, 42),
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

local KeyDisplay = {}

function KeyDisplay.Create(parent, layoutOrder)
    local row = Instance.new("Frame")
    row.Name = "KeyRow"
    row.LayoutOrder = layoutOrder or 3
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
    inner.Name = "KeyInner"
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
    stroke.Color = COLORS.keyBlue
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inner

    -- Gradient background (dark blue theme for keys)
    local function getKeySeq()
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
            ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(1,1,1), 0.12)),
        })
    end
    local keyGradient = Instance.new("UIGradient")
    keyGradient.Rotation = 135
    keyGradient.Color = getKeySeq()
    keyGradient.Parent = inner
    local lp = Players.LocalPlayer
    if lp then
        lp:GetPropertyChangedSignal("Team"):Connect(function()
            if keyGradient and keyGradient.Parent then
                keyGradient.Color = getKeySeq()
            end
        end)
    end

    -- Key icon (text glyph)
    local keyIcon = Instance.new("TextLabel")
    keyIcon.Name = "KeyIcon"
    keyIcon.BackgroundTransparency = 1
    keyIcon.AnchorPoint = Vector2.new(0, 0.5)
    keyIcon.Position = UDim2.new(0, px(8), 0.5, 0)
    keyIcon.Size = UDim2.new(0, px(24), 0, px(24))
    keyIcon.Font = Enum.Font.GothamBold
    keyIcon.Text = "\u{1F511}"
    keyIcon.TextSize = tpx(18)
    keyIcon.TextColor3 = COLORS.keyBlue
    keyIcon.TextXAlignment = Enum.TextXAlignment.Center
    keyIcon.Parent = inner

    -- Key value label
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "KeysValue"
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBlack
    valueLabel.TextScaled = true
    valueLabel.TextColor3 = COLORS.keyBlue
    valueLabel.Text = "0"
    valueLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    valueLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    valueLabel.Size = UDim2.new(0.5, 0, 0.7, 0)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.Parent = inner

    -- API
    local api = {}
    local currentKeys = 0

    function api.SetKeys(amount)
        amount = math.max(0, tonumber(amount) or 0)
        currentKeys = math.floor(amount)
        valueLabel.Text = tostring(currentKeys)
    end

    function api.GetKeys()
        return currentKeys
    end

    -- Wire to server CurrencyService remotes
    local keysEvent = ReplicatedStorage:FindFirstChild("KeysUpdated")
    local getKeysFn = ReplicatedStorage:FindFirstChild("GetKeys")
    if not keysEvent then
        pcall(function() keysEvent = ReplicatedStorage:WaitForChild("KeysUpdated", 6) end)
    end
    if not getKeysFn then
        pcall(function() getKeysFn = ReplicatedStorage:WaitForChild("GetKeys", 6) end)
    end

    -- Listen for server pushes
    if keysEvent and keysEvent:IsA("RemoteEvent") then
        keysEvent.OnClientEvent:Connect(function(amount)
            pcall(function() api.SetKeys(amount) end)
        end)
    end

    -- Fetch initial value with retry
    if getKeysFn and getKeysFn:IsA("RemoteFunction") then
        local function tryFetch()
            local ok, result = pcall(function() return getKeysFn:InvokeServer() end)
            if ok and type(result) == "number" then
                pcall(function() api.SetKeys(result) end)
                return true
            end
            return false
        end
        task.spawn(function()
            if tryFetch() and currentKeys > 0 then return end
            local delays = {0.5, 1.0, 1.5, 2.0}
            for _, d in ipairs(delays) do
                task.wait(d)
                if tryFetch() and currentKeys > 0 then return end
            end
        end)
    end

    return row, api
end

return KeyDisplay
