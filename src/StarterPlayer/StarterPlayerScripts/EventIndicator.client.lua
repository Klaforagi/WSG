--[[
    EventIndicator.client.lua  (StarterPlayerScripts)
    Shows a non-interactive "EVENT" card inside the left-side menu panel
    whenever the server signals that a timed event is active.

    The card is inserted into the MainUICard panel at LayoutOrder 100
    so it sits below the existing buttons (Quests, Upgrade, Team).

    Layer stack (bottom to top):
      1. Base frame  (dark background + gradient)           ZIndex 0
      2. SilhouetteArt  (medieval battle atmosphere)        ZIndex 1
      3. TeamPulseOverlay  (team-coloured tint, animates)   ZIndex 2
      4. GoldBorderStroke  (UIStroke on base frame)         ZIndex n/a
      5. EventLabel + Shadow  (centered "EVENT" text)       ZIndex 9-10

    Pulse animation:
      - Starts inside createIndicator() after all layers are built
      - Runs in pulseThread (task.spawn loop)
      - Tweens TeamPulseOverlay.BackgroundTransparency between
        PULSE_MIN_TRANSPARENCY (strong tint) and PULSE_MAX_TRANSPARENCY (weak tint)
      - Stops in destroyIndicator() via task.cancel + tween cleanup
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Load shared config
local EventConfig
do
    local mod = ReplicatedStorage:WaitForChild("EventConfig", 10)
    if mod then
        local ok, cfg = pcall(require, mod)
        if ok then EventConfig = cfg end
    end
end

---------------------------------------------------------------------
-- Tunable pulse constants
---------------------------------------------------------------------
local PULSE_BLUE_COLOR       = Color3.fromRGB(40, 90, 220)   -- blue team overlay
local PULSE_RED_COLOR        = Color3.fromRGB(220, 45, 45)   -- red team overlay
local PULSE_MIN_TRANSPARENCY = 0.25                           -- strongest tint (most visible)
local PULSE_MAX_TRANSPARENCY = 0.70                           -- weakest tint  (background shows through)
local PULSE_CYCLE            = (EventConfig and EventConfig.PULSE_CYCLE) or 1.75

---------------------------------------------------------------------
-- Responsive pixel helper (mirrors SideUI.px)
---------------------------------------------------------------------
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75

---------------------------------------------------------------------
-- Colour helpers
---------------------------------------------------------------------
local COLORS = {
    gold      = Color3.fromRGB(255, 215, 80),
    brown     = Color3.fromRGB(122, 85, 46),
    darkBase  = Color3.fromRGB(8, 10, 20),
    ember     = Color3.fromRGB(180, 70, 20),
}

local function getTeamPulseColor()
    local team = player and player.Team
    if team and team.Name == "Blue" then
        return PULSE_BLUE_COLOR
    elseif team and team.Name == "Red" then
        return PULSE_RED_COLOR
    end
    return PULSE_BLUE_COLOR -- default fallback
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local currentCard    = nil   -- the Frame inserted into the panel
local pulseThread    = nil   -- coroutine running the pulse loop
local pulseTweens    = {}    -- current active tweens (for cleanup)

---------------------------------------------------------------------
-- Cleanup — stops pulse, cancels tweens, destroys card
---------------------------------------------------------------------
local function destroyIndicator()
    if pulseThread then
        pcall(task.cancel, pulseThread)
        pulseThread = nil
    end
    for _, tw in ipairs(pulseTweens) do
        pcall(function() tw:Cancel() end)
    end
    pulseTweens = {}
    if currentCard then
        pcall(function() currentCard:Destroy() end)
        currentCard = nil
    end
end

---------------------------------------------------------------------
-- Layer 2: Decorative silhouette art (medieval battle atmosphere)
-- Lighter shapes against the dark card base (~30-60 RGB vs ~8-14).
---------------------------------------------------------------------
local function buildSilhouetteArt(parent)
    local artContainer = Instance.new("Frame")
    artContainer.Name = "SilhouetteArt"
    artContainer.BackgroundTransparency = 1
    artContainer.Size = UDim2.new(1, 0, 1, 0)
    artContainer.ZIndex = 1
    artContainer.ClipsDescendants = true
    artContainer.Parent = parent

    local function sil(name, pos, size, color, transparency, rotation)
        local f = Instance.new("Frame")
        f.Name = name
        f.BackgroundColor3 = color or Color3.fromRGB(28, 32, 52)
        f.BackgroundTransparency = transparency or 0.40
        f.BorderSizePixel = 0
        f.Size = size
        f.Position = pos
        f.Rotation = rotation or 0
        f.ZIndex = 1
        f.Parent = artContainer
        return f
    end

    -- Ground / horizon line
    sil("Ground", UDim2.new(0, 0, 0.78, 0), UDim2.new(1, 0, 0.22, 0),
        Color3.fromRGB(22, 24, 40), 0.25)

    -- Left tower silhouette
    local tower1 = sil("Tower1", UDim2.new(0.04, 0, 0.22, 0), UDim2.new(0.10, 0, 0.58, 0),
        Color3.fromRGB(30, 34, 54), 0.30)
    local t1corner = Instance.new("UICorner")
    t1corner.CornerRadius = UDim.new(0, px(3))
    t1corner.Parent = tower1

    -- Tower 1 battlement
    sil("T1Top", UDim2.new(0.02, 0, 0.18, 0), UDim2.new(0.14, 0, 0.08, 0),
        Color3.fromRGB(30, 34, 54), 0.30)

    -- Right tower (taller, thinner)
    local tower2 = sil("Tower2", UDim2.new(0.82, 0, 0.15, 0), UDim2.new(0.08, 0, 0.65, 0),
        Color3.fromRGB(26, 30, 48), 0.35)
    local t2corner = Instance.new("UICorner")
    t2corner.CornerRadius = UDim.new(0, px(2))
    t2corner.Parent = tower2

    -- Tower 2 spire
    sil("T2Spire", UDim2.new(0.83, 0, 0.08, 0), UDim2.new(0.06, 0, 0.10, 0),
        Color3.fromRGB(26, 30, 48), 0.38)

    -- Left banner (angled flag on tower)
    sil("Banner1", UDim2.new(0.12, 0, 0.28, 0), UDim2.new(0.08, 0, 0.12, 0),
        Color3.fromRGB(34, 30, 50), 0.40, 15)

    -- Mid-ground wall segment
    sil("Wall", UDim2.new(0.18, 0, 0.58, 0), UDim2.new(0.60, 0, 0.22, 0),
        Color3.fromRGB(24, 26, 42), 0.45)

    -- Smoke / haze wisps
    sil("Smoke1", UDim2.new(0.25, 0, 0.30, 0), UDim2.new(0.20, 0, 0.14, 0),
        Color3.fromRGB(40, 38, 55), 0.60)
    sil("Smoke2", UDim2.new(0.55, 0, 0.24, 0), UDim2.new(0.18, 0, 0.12, 0),
        Color3.fromRGB(40, 38, 55), 0.65)

    -- Faint ember glow at base
    local ember = sil("Ember", UDim2.new(0.30, 0, 0.72, 0), UDim2.new(0.40, 0, 0.10, 0),
        COLORS.ember, 0.72)
    local emberCorner = Instance.new("UICorner")
    emberCorner.CornerRadius = UDim.new(1, 0)
    emberCorner.Parent = ember

    -- Small dragon/bird silhouette
    sil("DragonWingL", UDim2.new(0.62, 0, 0.18, 0), UDim2.new(0.06, 0, 0.04, 0),
        Color3.fromRGB(32, 36, 56), 0.42, -20)
    sil("DragonWingR", UDim2.new(0.67, 0, 0.17, 0), UDim2.new(0.06, 0, 0.04, 0),
        Color3.fromRGB(32, 36, 56), 0.42, 20)
    sil("DragonBody", UDim2.new(0.645, 0, 0.185, 0), UDim2.new(0.035, 0, 0.025, 0),
        Color3.fromRGB(32, 36, 56), 0.38)

    return artContainer
end

---------------------------------------------------------------------
-- Build the event card
---------------------------------------------------------------------
local function createIndicator()
    destroyIndicator()

    -- Find the MainUICard panel inside the MainUI ScreenGui
    local mainUI = playerGui:FindFirstChild("MainUI")
    if not mainUI then
        mainUI = playerGui:WaitForChild("MainUI", 5)
    end
    if not mainUI then
        warn("[EventIndicator] MainUI not found – cannot show event card")
        return
    end
    local panel = mainUI:FindFirstChild("MainUICard")
    if not panel then
        panel = mainUI:WaitForChild("MainUICard", 5)
    end
    if not panel then
        warn("[EventIndicator] MainUICard not found – cannot show event card")
        return
    end

    -- Card height: similar to the Shop/Inventory row
    local function calcCardHeight()
        local screenY = 720
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then screenY = cam.ViewportSize.Y end
        return math.max(42, math.floor(screenY * 0.075))
    end
    local cardH = calcCardHeight()

    -----------------------------------------------------------------
    -- LAYER 1: Base frame (dark background + gradient)
    -- Inserted into panel's UIListLayout; LayoutOrder 100 places it
    -- below Boosts/ShopInv/Coins/Grid (all < 100).
    -----------------------------------------------------------------
    local card = Instance.new("Frame")
    card.Name = "EventCard"
    card.LayoutOrder = 100
    card.Size = UDim2.new(1, 0, 0, cardH)
    card.BackgroundColor3 = COLORS.darkBase
    card.BackgroundTransparency = 0
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = panel
    currentCard = card

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, px(8))
    cardCorner.Parent = card

    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 12, 26)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 18)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 8, 16)),
    })
    bgGrad.Rotation = 90
    bgGrad.Parent = card

    -----------------------------------------------------------------
    -- LAYER 2: Silhouette art (background art — always visible)
    -----------------------------------------------------------------
    buildSilhouetteArt(card)

    -----------------------------------------------------------------
    -- LAYER 3: Team-coloured pulse overlay
    -- This is the overlay whose transparency is animated by the pulse.
    -- It tints the entire card with the local player's team colour.
    -----------------------------------------------------------------
    local teamPulseOverlay = Instance.new("Frame")
    teamPulseOverlay.Name = "TeamPulseOverlay"
    teamPulseOverlay.BackgroundColor3 = getTeamPulseColor()
    teamPulseOverlay.BackgroundTransparency = PULSE_MAX_TRANSPARENCY
    teamPulseOverlay.Size = UDim2.new(1, 0, 1, 0)
    teamPulseOverlay.BorderSizePixel = 0
    teamPulseOverlay.ZIndex = 2
    teamPulseOverlay.Parent = card

    local pulseOverlayCorner = Instance.new("UICorner")
    pulseOverlayCorner.CornerRadius = UDim.new(0, px(8))
    pulseOverlayCorner.Parent = teamPulseOverlay

    -- Update overlay color when team changes
    player:GetPropertyChangedSignal("Team"):Connect(function()
        pcall(function()
            teamPulseOverlay.BackgroundColor3 = getTeamPulseColor()
        end)
    end)

    -----------------------------------------------------------------
    -- LAYER 4: Gold border stroke (always visible, sits on base frame)
    -----------------------------------------------------------------
    local goldStroke = Instance.new("UIStroke")
    goldStroke.Name = "GoldBorderStroke"
    goldStroke.Color = COLORS.gold
    goldStroke.Thickness = 2
    goldStroke.Transparency = 0.15
    goldStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    goldStroke.Parent = card

    -----------------------------------------------------------------
    -- LAYER 5: "EVENT" label + shadow
    -----------------------------------------------------------------
    local shadow = Instance.new("TextLabel")
    shadow.Name = "Shadow"
    shadow.BackgroundTransparency = 1
    shadow.Size = UDim2.new(0.9, 0, 0.85, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.new(0.5, px(1), 0.5, px(1))
    shadow.Font = Enum.Font.GothamBold
    shadow.Text = "EVENT"
    shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
    shadow.TextTransparency = 0.55
    shadow.TextSize = math.max(13, math.floor(cardH * 0.50 * deviceTextScale))
    shadow.TextXAlignment = Enum.TextXAlignment.Center
    shadow.TextYAlignment = Enum.TextYAlignment.Center
    shadow.ZIndex = 9
    shadow.Parent = card

    local label = Instance.new("TextLabel")
    label.Name = "EventLabel"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.9, 0, 0.85, 0)
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.new(0.5, 0, 0.5, 0)
    label.Font = Enum.Font.GothamBold
    label.Text = "EVENT"
    label.TextColor3 = COLORS.gold
    label.TextSize = math.max(13, math.floor(cardH * 0.50 * deviceTextScale))
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 10
    label.Parent = card

    local labelStroke = Instance.new("UIStroke")
    labelStroke.Color = Color3.fromRGB(30, 20, 6)
    labelStroke.Thickness = 1
    labelStroke.Transparency = 0.1
    labelStroke.Parent = label

    -----------------------------------------------------------------
    -- Pulse animation  (STARTS HERE)
    -- Tweens teamPulseOverlay.BackgroundTransparency between
    -- PULSE_MIN_TRANSPARENCY (strong tint) and PULSE_MAX_TRANSPARENCY
    -- (weak tint).  Gold stroke stays constant.  Background art
    -- remains visible underneath at all times.
    -----------------------------------------------------------------
    pulseThread = task.spawn(function()
        local halfCycle = PULSE_CYCLE / 2
        local tweenInfo = TweenInfo.new(halfCycle, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

        while currentCard and currentCard.Parent do
            -- Phase 1: overlay becomes more visible (stronger team tint)
            local tw1 = TweenService:Create(teamPulseOverlay, tweenInfo, {
                BackgroundTransparency = PULSE_MIN_TRANSPARENCY,
            })
            pulseTweens = { tw1 }
            tw1:Play()
            tw1.Completed:Wait()

            if not currentCard or not currentCard.Parent then break end

            -- Phase 2: overlay fades back (weaker tint, background shows more)
            local tw2 = TweenService:Create(teamPulseOverlay, tweenInfo, {
                BackgroundTransparency = PULSE_MAX_TRANSPARENCY,
            })
            pulseTweens = { tw2 }
            tw2:Play()
            tw2.Completed:Wait()
        end
        -- Pulse STOPS when the loop exits (card destroyed or unparented)
    end)
end

---------------------------------------------------------------------
-- Listen for server event state changes
---------------------------------------------------------------------
local EventStateChanged = ReplicatedStorage:WaitForChild("EventStateChanged", 15)
if EventStateChanged then
    EventStateChanged.OnClientEvent:Connect(function(active, eventIndex)
        if active then
            createIndicator()
        else
            destroyIndicator()
        end
    end)
else
    warn("[EventIndicator] EventStateChanged remote not found – event UI will not work")
end

-- Clean up on match end
local MatchEnd = ReplicatedStorage:FindFirstChild("MatchEnd")
if MatchEnd and MatchEnd:IsA("RemoteEvent") then
    MatchEnd.OnClientEvent:Connect(function()
        destroyIndicator()
    end)
end
