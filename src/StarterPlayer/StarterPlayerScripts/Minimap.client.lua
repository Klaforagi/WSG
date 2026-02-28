local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------------
-- World bounds (your coordinates)
---------------------------------------------------------------------------
local MAP_MIN_X = -218
local MAP_MAX_X = 75
local MAP_MIN_Z = -162
local MAP_MAX_Z = 383

local WORLD_W = MAP_MAX_X - MAP_MIN_X -- 293
local WORLD_H = MAP_MAX_Z - MAP_MIN_Z -- 545
local MAP_ASPECT = WORLD_W / WORLD_H  -- ~0.537  (taller than wide)

---------------------------------------------------------------------------
-- UI sizing – all Scale-based so it adapts to any screen
---------------------------------------------------------------------------
local MAP_HEIGHT_SCALE = 0.40            -- 40% of screen height
local MAP_WIDTH_SCALE  = MAP_HEIGHT_SCALE * MAP_ASPECT
local MARGIN_SCALE     = 0.012
local PADDING_SCALE    = 0.04            -- fraction of frame

---------------------------------------------------------------------------
-- Screen GUI
---------------------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "MinimapGui"
screen.ResetOnSpawn = false
screen.Parent = playerGui

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
local frame = Instance.new("Frame")
frame.Name = "Minimap"
frame.AnchorPoint = Vector2.new(1, 1)
frame.Position = UDim2.new(1 - MARGIN_SCALE, 0, 1 - MARGIN_SCALE, 0)
frame.Size = UDim2.new(MAP_WIDTH_SCALE, 0, MAP_HEIGHT_SCALE, 0)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = screen

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = frame

-- gold border for minimap
local frameStroke = Instance.new("UIStroke")
frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
frameStroke.Thickness = 2
frameStroke.Color = Color3.fromRGB(255, 215, 80)
frameStroke.Parent = frame

-- Keep minimap height fixed relative to screen height and compute width from desired aspect
local DESIRED_ASPECT = 0.45 -- width = DESIRED_ASPECT * height (controls how tall vs wide it is)
local HEIGHT_SCALE = 0.40   -- fraction of screen height the minimap should occupy
local MIN_WIDTH_SCALE = 0.08
local MAX_WIDTH_SCALE = 0.6

local function updateMinimapSize()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    if not vp or vp.X == 0 then return end
    local vh = vp.Y
    local vw = vp.X

    -- height is fixed fraction of viewport height
    local heightScale = HEIGHT_SCALE
    -- compute widthScale so width_pixels = DESIRED_ASPECT * height_pixels
    local widthScale = (DESIRED_ASPECT * heightScale * vh) / math.max(vw, 1)
    widthScale = math.clamp(widthScale, MIN_WIDTH_SCALE, MAX_WIDTH_SCALE)

    frame.Size = UDim2.new(widthScale, 0, heightScale, 0)
    -- inner uses scale-based padding so it will adapt automatically
end

-- initialize size
pcall(updateMinimapSize)

---------------------------------------------------------------------------
-- Inner (clips content, has padding)
---------------------------------------------------------------------------
local inner = Instance.new("Frame")
inner.Name = "Inner"
inner.AnchorPoint = Vector2.new(0.5, 0.5)
inner.Position = UDim2.new(0.5, 0, 0.5, 0)
inner.Size = UDim2.new(1 - PADDING_SCALE * 2, 0, 1 - PADDING_SCALE * 2, 0)
inner.BackgroundTransparency = 1
inner.ClipsDescendants = true
inner.Parent = frame

---------------------------------------------------------------------------
-- Colored background bands  (top = greenish-blue, bottom = sandy orange)
---------------------------------------------------------------------------
local topBg = Instance.new("Frame")
topBg.Name = "TopBg"
topBg.BackgroundColor3 = Color3.fromRGB(45, 120, 100)
topBg.BackgroundTransparency = 0.15
topBg.BorderSizePixel = 0
topBg.Size = UDim2.new(1, 0, 0.5, 0)
topBg.Position = UDim2.new(0, 0, 0, 0)
topBg.ZIndex = 1
topBg.Parent = inner

local bottomBg = Instance.new("Frame")
bottomBg.Name = "BottomBg"
bottomBg.BackgroundColor3 = Color3.fromRGB(190, 150, 90)
bottomBg.BackgroundTransparency = 0.15
bottomBg.BorderSizePixel = 0
bottomBg.Size = UDim2.new(1, 0, 0.5, 0)
bottomBg.Position = UDim2.new(0, 0, 0.5, 0)
bottomBg.ZIndex = 1
bottomBg.Parent = inner

---------------------------------------------------------------------------
-- Dot container (above background)
---------------------------------------------------------------------------
local dotFolder = Instance.new("Frame")
dotFolder.Name = "Dots"
dotFolder.BackgroundTransparency = 1
dotFolder.Size = UDim2.new(1, 0, 1, 0)
dotFolder.ZIndex = 3
dotFolder.Parent = inner

---------------------------------------------------------------------------
-- World → minimap  (returns a Scale UDim2 inside inner, 0-1)
---------------------------------------------------------------------------
local function worldToMap(worldPos)
    -- mirror X axis so world left maps to UI left (fix flipped behavior)
    local nx = 1 - ((worldPos.X - MAP_MIN_X) / WORLD_W)
    local nz = 1 - (worldPos.Z - MAP_MIN_Z) / WORLD_H -- invert so high-Z = top
    return UDim2.new(
        math.clamp(nx, 0, 1), 0,
        math.clamp(nz, 0, 1), 0
    )
end

---------------------------------------------------------------------------
-- Dot helpers
---------------------------------------------------------------------------
local function makeDot(color, pxSize, zindex, cornerRadius)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, pxSize or 8, 0, pxSize or 8)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.ZIndex = zindex or 3
    local c = Instance.new("UICorner")
    if cornerRadius == nil then
        c.CornerRadius = UDim.new(1, 0)
    else
        c.CornerRadius = UDim.new(0, cornerRadius)
    end
    c.Parent = dot
    dot.Parent = dotFolder
    return dot
end

---------------------------------------------------------------------------
-- Player dots
---------------------------------------------------------------------------
local playerDots = {}

local function addPlayerDot(p)
    if playerDots[p] then return end
    local isLocal = (p == LocalPlayer)
    local function getTeamColor(pl)
        if pl.Team and pl.Team.Name == "Red" then
            return Color3.fromRGB(220, 80, 80)
        elseif pl.Team and pl.Team.Name == "Blue" then
            return Color3.fromRGB(100, 160, 255)
        else
            return (pl == LocalPlayer) and Color3.fromRGB(100,160,255) or Color3.fromRGB(180,180,180)
        end
    end
    local color = getTeamColor(p)
    local size  = isLocal and 10 or 8
    playerDots[p] = makeDot(color, size, isLocal and 4 or 3)
    playerDots[p].Name = p.Name
    -- update color on team change
    p:GetPropertyChangedSignal("Team"):Connect(function()
        if playerDots[p] and playerDots[p].Parent then
            playerDots[p].BackgroundColor3 = getTeamColor(p)
        end
    end)
end

local function removePlayerDot(p)
    if playerDots[p] then
        playerDots[p]:Destroy()
        playerDots[p] = nil
    end
end

for _, p in ipairs(Players:GetPlayers()) do addPlayerDot(p) end
Players.PlayerAdded:Connect(addPlayerDot)
Players.PlayerRemoving:Connect(removePlayerDot)

---------------------------------------------------------------------------
-- Flag dots  (dynamic – re-finds each frame so carried flags track correctly)
---------------------------------------------------------------------------
local FLAG_NAMES = { "RedFlag", "BlueFlag" }
local FLAG_COLORS = {
    RedFlag  = Color3.fromRGB(220, 80, 80),
    BlueFlag = Color3.fromRGB(100, 160, 255),
}

-- one UI dot per flag name (persists across re-parents / respawns)
local flagDots = {}
for _, name in ipairs(FLAG_NAMES) do
    local dot = makeDot(FLAG_COLORS[name], 12, 3, 0) -- square flag icon
    dot.Name = name .. "Dot"
    dot.Visible = false
    flagDots[name] = dot
end

-- Get world position for a flag by name ("RedFlag" or "BlueFlag").
-- Priority order:
--   1. CarryingFlag attribute on a player  → follow that player's HRP
--   2. Carried clone in workspace (e.g. "RedFlag_Carried") → follow parent character HRP
--   3. Original model in workspace (e.g. "RedFlag") → use its position (on stand or dropped)
local function getFlagWorldPos(flagName)
    -- flagName is "RedFlag" or "BlueFlag"; extract team name for attribute check
    local teamName = flagName:gsub("Flag", "") -- "Red" or "Blue"

    -- 1) Check if any player has CarryingFlag == teamName
    for _, pl in ipairs(Players:GetPlayers()) do
        local attr = pl:GetAttribute("CarryingFlag")
        if attr == teamName then
            local ch = pl.Character
            local hrp = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart"))
            if hrp then
                return hrp.Position
            end
        end
    end

    -- 2) Search workspace for the carried clone (named e.g. "RedFlag_Carried")
    local carriedName = flagName .. "_Carried"
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == carriedName and (v:IsA("Model") or v:IsA("BasePart")) then
            -- it's welded to a character; find parent character's HRP
            for _, pl in ipairs(Players:GetPlayers()) do
                local ch = pl.Character
                if ch and v:IsDescendantOf(ch) then
                    local hrp = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")
                    if hrp then return hrp.Position end
                end
            end
            -- if not under a character for some reason, use its own position
            if v:IsA("Model") then
                local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                if part then return part.Position end
            elseif v:IsA("BasePart") then
                return v.Position
            end
        end
    end

    -- 3) Search workspace for the original flag model (on stand or dropped)
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == flagName and (v:IsA("Model") or v:IsA("BasePart")) then
            if v:IsA("Model") then
                local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                if part then return part.Position end
            elseif v:IsA("BasePart") then
                return v.Position
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Render loop
---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    -- keep minimap size responsive to viewport/aspect
    pcall(updateMinimapSize)
    -- update players
    for p, ui in pairs(playerDots) do
        local c = p.Character
        local h = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart"))
        if h then
            ui.Position = worldToMap(h.Position)
            ui.Visible = true
        else
            ui.Visible = false
        end
    end

    -- update flags (uses CarryingFlag attribute + carried clone + workspace flag)
    for _, name in ipairs(FLAG_NAMES) do
        local ui = flagDots[name]
        local pos = getFlagWorldPos(name)
        if pos then
            ui.Position = worldToMap(pos)
            ui.Visible = true
        else
            ui.Visible = false
        end
    end
end)

