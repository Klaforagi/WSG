local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------------
-- SETTINGS  (all tweakable values in one place)
---------------------------------------------------------------------------

-- World bounds (match your game map)
local MAP_MIN_X = -218
local MAP_MAX_X = 75
local MAP_MIN_Z = -162
local MAP_MAX_Z = 383

local WORLD_W = MAP_MAX_X - MAP_MIN_X  -- 293
local WORLD_H = MAP_MAX_Z - MAP_MIN_Z  -- 545

-- Layout
local HEIGHT_SCALE    = 0.40   -- fraction of screen height
local DESIRED_ASPECT  = 0.45   -- width / height ratio
local MIN_WIDTH_SCALE = 0.08
local MAX_WIDTH_SCALE = 0.60
local MARGIN_SCALE    = 0.012  -- screen-edge margin
local PADDING_PX      = 4     -- gap between outer border and map content
local CORNER_RADIUS   = 8     -- outer corner radius (px)

-- Frame / border colors  (dark navy + gold, matching the HUD)
local FRAME_BG        = Color3.fromRGB(12, 14, 28)
local FRAME_INNER_BG  = Color3.fromRGB(18, 20, 36)
local BORDER_GOLD     = Color3.fromRGB(255, 215, 80)
local BORDER_GOLD_DIM = Color3.fromRGB(180, 150, 55)

-- Terrain colors (simplified top-down battlefield)
local GRASS_COLOR     = Color3.fromRGB(48, 74, 48)
local GRASS_LIGHT     = Color3.fromRGB(58, 86, 54)
local DIRT_COLOR      = Color3.fromRGB(110, 92, 64)
local TREELINE_COLOR  = Color3.fromRGB(34, 54, 38)
local MID_LINE_COLOR  = Color3.fromRGB(85, 85, 72)
local BASE_ZONE_DARK  = Color3.fromRGB(28, 32, 22)

-- Player marker settings
local PLAYER_SIZE_LOCAL  = 10
local PLAYER_SIZE_OTHER  = 7
local PLAYER_COLOR_LOCAL = Color3.fromRGB(255, 225, 0)    -- bright yellow for the local player
local PLAYER_COLOR_BLUE  = Color3.fromRGB(100, 160, 255)
local PLAYER_COLOR_RED   = Color3.fromRGB(220, 80, 80)
local PLAYER_COLOR_NONE  = Color3.fromRGB(180, 180, 180)
local PLAYER_OUTLINE     = Color3.fromRGB(0, 0, 0)
local PLAYER_OUTLINE_LOCAL = Color3.fromRGB(180, 130, 0) -- amber-gold outline for local player

-- Base marker settings
local BASE_SIZE         = 14
local BASE_CORNER_PX    = 3
local BASE_STROKE_PX    = 2
local BASE_COLOR_BLUE   = Color3.fromRGB(65, 105, 225)
local BASE_COLOR_RED    = Color3.fromRGB(200, 60, 60)
local BASE_GLOW_BLUE    = Color3.fromRGB(140, 180, 255)
local BASE_GLOW_RED     = Color3.fromRGB(255, 140, 140)

-- Flag / objective marker settings
local FLAG_SIZE         = 10
local FLAG_STROKE_PX    = 1.5
local FLAG_OUTLINE_GOLD = Color3.fromRGB(255, 215, 80)

-- Flag lookup names
local FLAG_NAMES = { "RedFlag", "BlueFlag" }
local FLAG_TEAM_COLORS = {
    RedFlag  = PLAYER_COLOR_RED,
    BlueFlag = PLAYER_COLOR_BLUE,
}

---------------------------------------------------------------------------
-- SCREEN GUI
---------------------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "MinimapGui"
screen.ResetOnSpawn = false
screen.Parent = playerGui

---------------------------------------------------------------------------
-- 1) OUTER FRAME  (dark navy panel with gold border)
---------------------------------------------------------------------------
local frame = Instance.new("Frame")
frame.Name = "Minimap"
frame.AnchorPoint = Vector2.new(1, 1)
frame.Position = UDim2.new(1 - MARGIN_SCALE, 0, 1 - MARGIN_SCALE, 0)
frame.Size = UDim2.new(0.20, 0, HEIGHT_SCALE, 0)
frame.BackgroundColor3 = FRAME_BG
frame.BackgroundTransparency = 0
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = screen

do -- outer corner + gold stroke
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, CORNER_RADIUS)
    c.Parent = frame

    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Thickness = 2
    s.Color = BORDER_GOLD
    s.Parent = frame
end

---------------------------------------------------------------------------
-- 2) INNER DEPTH FRAME  (subtle inset for layered polish)
---------------------------------------------------------------------------
local innerFrame = Instance.new("Frame")
innerFrame.Name = "InnerFrame"
innerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
innerFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
innerFrame.Size = UDim2.new(1, -PADDING_PX * 2, 1, -PADDING_PX * 2)
innerFrame.BackgroundColor3 = FRAME_INNER_BG
innerFrame.BackgroundTransparency = 0
innerFrame.BorderSizePixel = 0
innerFrame.ClipsDescendants = true
innerFrame.Parent = frame

do -- inner corner + dim gold stroke for depth
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, math.max(CORNER_RADIUS - 2, 4))
    c.Parent = innerFrame

    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Thickness = 1
    s.Color = BORDER_GOLD_DIM
    s.Transparency = 0.5
    s.Parent = innerFrame
end

---------------------------------------------------------------------------
-- 3) MAP CONTENT AREA  (clips terrain + markers)
---------------------------------------------------------------------------
local mapContent = Instance.new("Frame")
mapContent.Name = "MapContent"
mapContent.AnchorPoint = Vector2.new(0.5, 0.5)
mapContent.Position = UDim2.new(0.5, 0, 0.5, 0)
mapContent.Size = UDim2.new(1, -2, 1, -2)
mapContent.BackgroundTransparency = 1
mapContent.ClipsDescendants = true
mapContent.Parent = innerFrame

---------------------------------------------------------------------------
-- 4) TERRAIN LAYERS  (procedural top-down battlefield)
---------------------------------------------------------------------------

-- Grass base fill
local grassBase = Instance.new("Frame")
grassBase.Name = "GrassBase"
grassBase.BackgroundColor3 = GRASS_COLOR
grassBase.Size = UDim2.new(1, 0, 1, 0)
grassBase.BorderSizePixel = 0
grassBase.ZIndex = 1
grassBase.Parent = mapContent

-- Center dirt lane (vertical path down the middle)
local centerLane = Instance.new("Frame")
centerLane.Name = "CenterLane"
centerLane.BackgroundColor3 = DIRT_COLOR
centerLane.BackgroundTransparency = 0.3
centerLane.BorderSizePixel = 0
centerLane.AnchorPoint = Vector2.new(0.5, 0)
centerLane.Position = UDim2.new(0.5, 0, 0, 0)
centerLane.Size = UDim2.new(0.16, 0, 1, 0)
centerLane.ZIndex = 2
centerLane.Parent = mapContent

-- Horizontal cross-path near top third
local crossPathTop = Instance.new("Frame")
crossPathTop.Name = "CrossPathTop"
crossPathTop.BackgroundColor3 = DIRT_COLOR
crossPathTop.BackgroundTransparency = 0.4
crossPathTop.BorderSizePixel = 0
crossPathTop.AnchorPoint = Vector2.new(0, 0.5)
crossPathTop.Position = UDim2.new(0.08, 0, 0.30, 0)
crossPathTop.Size = UDim2.new(0.84, 0, 0.03, 0)
crossPathTop.ZIndex = 2
crossPathTop.Parent = mapContent

-- Horizontal cross-path near bottom third
local crossPathBot = Instance.new("Frame")
crossPathBot.Name = "CrossPathBot"
crossPathBot.BackgroundColor3 = DIRT_COLOR
crossPathBot.BackgroundTransparency = 0.4
crossPathBot.BorderSizePixel = 0
crossPathBot.AnchorPoint = Vector2.new(0, 0.5)
crossPathBot.Position = UDim2.new(0.08, 0, 0.70, 0)
crossPathBot.Size = UDim2.new(0.84, 0, 0.03, 0)
crossPathBot.ZIndex = 2
crossPathBot.Parent = mapContent

-- Left treeline (dark forest strip)
local leftTrees = Instance.new("Frame")
leftTrees.Name = "LeftTrees"
leftTrees.BackgroundColor3 = TREELINE_COLOR
leftTrees.BackgroundTransparency = 0.15
leftTrees.BorderSizePixel = 0
leftTrees.Position = UDim2.new(0, 0, 0.08, 0)
leftTrees.Size = UDim2.new(0.10, 0, 0.84, 0)
leftTrees.ZIndex = 2
leftTrees.Parent = mapContent

-- Right treeline
local rightTrees = Instance.new("Frame")
rightTrees.Name = "RightTrees"
rightTrees.BackgroundColor3 = TREELINE_COLOR
rightTrees.BackgroundTransparency = 0.15
rightTrees.BorderSizePixel = 0
rightTrees.AnchorPoint = Vector2.new(1, 0)
rightTrees.Position = UDim2.new(1, 0, 0.08, 0)
rightTrees.Size = UDim2.new(0.10, 0, 0.84, 0)
rightTrees.ZIndex = 2
rightTrees.Parent = mapContent

-- Lighter grass patches (visual variety)
for _, patch in ipairs({
    { x = 0.17, y = 0.20, w = 0.18, h = 0.16 },
    { x = 0.65, y = 0.58, w = 0.18, h = 0.16 },
}) do
    local p = Instance.new("Frame")
    p.BackgroundColor3 = GRASS_LIGHT
    p.BackgroundTransparency = 0.5
    p.BorderSizePixel = 0
    p.Position = UDim2.new(patch.x, 0, patch.y, 0)
    p.Size = UDim2.new(patch.w, 0, patch.h, 0)
    p.ZIndex = 2
    p.Parent = mapContent
end

-- Midfield divider line (thin horizontal)
local midLine = Instance.new("Frame")
midLine.Name = "MidLine"
midLine.BackgroundColor3 = MID_LINE_COLOR
midLine.BackgroundTransparency = 0.45
midLine.BorderSizePixel = 0
midLine.AnchorPoint = Vector2.new(0, 0.5)
midLine.Position = UDim2.new(0.04, 0, 0.5, 0)
midLine.Size = UDim2.new(0.92, 0, 0, 1)
midLine.ZIndex = 2
midLine.Parent = mapContent

-- Subtle darker zones at top and bottom edges (base areas)
for _, zone in ipairs({
    { y = 0, ay = 0 },
    { y = 1, ay = 1 },
}) do
    local z = Instance.new("Frame")
    z.BackgroundColor3 = BASE_ZONE_DARK
    z.BackgroundTransparency = 0.6
    z.BorderSizePixel = 0
    z.AnchorPoint = Vector2.new(0, zone.ay)
    z.Position = UDim2.new(0, 0, zone.y, 0)
    z.Size = UDim2.new(1, 0, 0.10, 0)
    z.ZIndex = 2
    z.Parent = mapContent
end

---------------------------------------------------------------------------
-- 5) MARKER CONTAINER  (renders above all terrain)
---------------------------------------------------------------------------
local markerLayer = Instance.new("Frame")
markerLayer.Name = "Markers"
markerLayer.BackgroundTransparency = 1
markerLayer.Size = UDim2.new(1, 0, 1, 0)
markerLayer.ZIndex = 10
markerLayer.Parent = mapContent

---------------------------------------------------------------------------
-- RESPONSIVE SIZING
---------------------------------------------------------------------------
local function updateMinimapSize()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    if not vp or vp.X == 0 then return end

    local heightScale = HEIGHT_SCALE
    local widthScale = (DESIRED_ASPECT * heightScale * vp.Y) / math.max(vp.X, 1)
    widthScale = math.clamp(widthScale, MIN_WIDTH_SCALE, MAX_WIDTH_SCALE)
    frame.Size = UDim2.new(widthScale, 0, heightScale, 0)
end

pcall(updateMinimapSize)

---------------------------------------------------------------------------
-- WORLD → MINIMAP  (returns Scale UDim2 0-1 inside marker layer)
---------------------------------------------------------------------------
local function worldToMap(worldPos)
    local nx = 1 - ((worldPos.X - MAP_MIN_X) / WORLD_W)
    local nz = 1 - (worldPos.Z - MAP_MIN_Z) / WORLD_H
    return UDim2.new(
        math.clamp(nx, 0, 1), 0,
        math.clamp(nz, 0, 1), 0
    )
end

---------------------------------------------------------------------------
-- MARKER HELPERS
---------------------------------------------------------------------------

-- Player marker: small circle with subtle dark outline
-- outlineColor / outlineThickness are optional overrides for the local player
local function makePlayerDot(color, size, zindex, outlineColor, outlineThickness)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, size, 0, size)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.ZIndex = zindex or 2

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    local outline = Instance.new("UIStroke")
    outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outline.Thickness = outlineThickness or 1
    outline.Color = outlineColor or PLAYER_OUTLINE
    outline.Transparency = outlineColor and 0 or 0.35
    outline.Parent = dot

    dot.Parent = markerLayer
    return dot
end

-- Base marker: larger rounded square with colored team stroke
local function makeBaseMarker(teamColor, strokeColor)
    local marker = Instance.new("Frame")
    marker.Size = UDim2.new(0, BASE_SIZE, 0, BASE_SIZE)
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.BackgroundColor3 = teamColor
    marker.BackgroundTransparency = 0.12
    marker.BorderSizePixel = 0
    marker.ZIndex = 1

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, BASE_CORNER_PX)
    corner.Parent = marker

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = BASE_STROKE_PX
    stroke.Color = strokeColor
    stroke.Parent = marker

    marker.Parent = markerLayer
    return marker
end

-- Flag marker: diamond (rotated square) with gold outline
local function makeFlagMarker(teamColor)
    -- transparent wrapper sized slightly larger for rotation clearance
    local wrapper = Instance.new("Frame")
    wrapper.Size = UDim2.new(0, FLAG_SIZE + 4, 0, FLAG_SIZE + 4)
    wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
    wrapper.BackgroundTransparency = 1
    wrapper.BorderSizePixel = 0
    wrapper.ZIndex = 4
    wrapper.Parent = markerLayer

    local diamond = Instance.new("Frame")
    diamond.Size = UDim2.new(0, FLAG_SIZE, 0, FLAG_SIZE)
    diamond.AnchorPoint = Vector2.new(0.5, 0.5)
    diamond.Position = UDim2.new(0.5, 0, 0.5, 0)
    diamond.Rotation = 45
    diamond.BackgroundColor3 = teamColor
    diamond.BorderSizePixel = 0
    diamond.ZIndex = 4

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 2)
    corner.Parent = diamond

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = FLAG_STROKE_PX
    stroke.Color = FLAG_OUTLINE_GOLD
    stroke.Parent = diamond

    diamond.Parent = wrapper
    return wrapper
end

---------------------------------------------------------------------------
-- BASE MARKERS  (static – positioned once from FlagStand parts)
---------------------------------------------------------------------------
local function setupBaseMarkers()
    for _, info in ipairs({
        { stand = "BlueFlagStand", color = BASE_COLOR_BLUE, glow = BASE_GLOW_BLUE, label = "BlueBase" },
        { stand = "RedFlagStand",  color = BASE_COLOR_RED,  glow = BASE_GLOW_RED,  label = "RedBase"  },
    }) do
        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name == info.stand and v:IsA("BasePart") then
                local marker = makeBaseMarker(info.color, info.glow)
                marker.Name = info.label
                marker.Position = worldToMap(v.Position)
                break
            end
        end
    end
end

task.spawn(function()
    task.wait(1) -- let workspace populate
    setupBaseMarkers()
end)

---------------------------------------------------------------------------
-- PLAYER MARKERS
---------------------------------------------------------------------------
local playerDots = {}

local function getTeamColor(pl)
    if pl == LocalPlayer then
        return PLAYER_COLOR_LOCAL  -- local player is always yellow
    elseif pl.Team and pl.Team.Name == "Red" then
        return PLAYER_COLOR_RED
    elseif pl.Team and pl.Team.Name == "Blue" then
        return PLAYER_COLOR_BLUE
    else
        return PLAYER_COLOR_NONE
    end
end

local function addPlayerDot(p)
    if playerDots[p] then return end
    local isLocal          = (p == LocalPlayer)
    local size             = isLocal and PLAYER_SIZE_LOCAL or PLAYER_SIZE_OTHER
    local zindex           = isLocal and 3 or 2
    local outlineColor     = isLocal and PLAYER_OUTLINE_LOCAL or nil
    local outlineThickness = isLocal and 1.5 or nil

    playerDots[p] = makePlayerDot(getTeamColor(p), size, zindex, outlineColor, outlineThickness)
    playerDots[p].Name = p.Name

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
-- FLAG / OBJECTIVE MARKERS
---------------------------------------------------------------------------
local flagDots = {}
for _, name in ipairs(FLAG_NAMES) do
    local marker = makeFlagMarker(FLAG_TEAM_COLORS[name])
    marker.Name = name .. "Marker"
    marker.Visible = false
    flagDots[name] = marker
end

-- Get world position for a flag by name ("RedFlag" or "BlueFlag").
-- Priority: CarryingFlag attribute → carried clone in workspace → original model
local function getFlagWorldPos(flagName)
    local teamName = flagName:gsub("Flag", "")

    -- 1) Player carrying the flag
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

    -- 2) Carried clone in workspace (e.g. "RedFlag_Carried")
    local carriedName = flagName .. "_Carried"
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == carriedName and (v:IsA("Model") or v:IsA("BasePart")) then
            for _, pl in ipairs(Players:GetPlayers()) do
                local ch = pl.Character
                if ch and v:IsDescendantOf(ch) then
                    local hrp = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")
                    if hrp then return hrp.Position end
                end
            end
            if v:IsA("Model") then
                local part = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                if part then return part.Position end
            elseif v:IsA("BasePart") then
                return v.Position
            end
        end
    end

    -- 3) Original flag model (on stand or dropped)
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
-- RENDER LOOP
---------------------------------------------------------------------------
local minimapRenderConn
minimapRenderConn = RunService.RenderStepped:Connect(function()
    pcall(updateMinimapSize)

    -- Update player positions
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

    -- Update flag positions
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

-- Cleanup on GUI removal
screen.AncestryChanged:Connect(function()
    if not screen:IsDescendantOf(game) then
        if minimapRenderConn then
            minimapRenderConn:Disconnect()
            minimapRenderConn = nil
        end
    end
end)

