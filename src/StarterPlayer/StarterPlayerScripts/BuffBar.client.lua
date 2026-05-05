--------------------------------------------------------------------------------
-- BuffBar.client.lua
-- Compact lower-right HUD for active events, healing, bandage, flags, and boosts.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local elapsed = 0
        while cam.ViewportSize.Y < 2 and elapsed < 3 do
            elapsed += task.wait()
        end
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

local function safeRequire(moduleName, timeout)
    local mod = ReplicatedStorage:WaitForChild(moduleName, timeout or 5)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            return result
        end
        warn("[BuffBar] Failed to require " .. moduleName .. ":", tostring(result))
    end
    return nil
end

local AssetCodes = safeRequire("AssetCodes", 5)
local BoostConfig = safeRequire("BoostConfig", 5)
local BuffBarConfig = safeRequire("BuffBarConfig", 5)
local BandageConfig = safeRequire("BandageConfig", 5) or { CastDuration = 6 }
local EventConfig = safeRequire("EventConfig", 5)

local UITheme
pcall(function()
    local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
    local themeModule = sideUI and sideUI:FindFirstChild("UITheme")
    if themeModule and themeModule:IsA("ModuleScript") then
        UITheme = require(themeModule)
    end
end)

local COLORS = {
    navy = (UITheme and UITheme.NAVY) or Color3.fromRGB(12, 14, 28),
    navyLight = (UITheme and UITheme.NAVY_LIGHT) or Color3.fromRGB(22, 26, 48),
    iconBg = (UITheme and UITheme.ICON_BG) or Color3.fromRGB(16, 18, 30),
    gold = (UITheme and UITheme.GOLD) or Color3.fromRGB(255, 215, 80),
    goldDim = (UITheme and UITheme.GOLD_DIM) or Color3.fromRGB(180, 150, 50),
    white = (UITheme and UITheme.WHITE) or Color3.fromRGB(245, 245, 252),
    dim = (UITheme and UITheme.DIM_TEXT) or Color3.fromRGB(145, 150, 175),
    green = (UITheme and UITheme.GREEN_GLOW) or Color3.fromRGB(50, 230, 110),
}

local function colorFrom(value, fallback)
    if typeof(value) == "Color3" then
        return value
    end
    if type(value) == "table" then
        return Color3.fromRGB(tonumber(value[1]) or 255, tonumber(value[2]) or 255, tonumber(value[3]) or 255)
    end
    return fallback or COLORS.gold
end

local function cloneDefinition(def)
    local copy = {}
    if type(def) == "table" then
        for key, value in pairs(def) do
            copy[key] = value
        end
    end
    return copy
end

local function getStaticDef(id)
    if BuffBarConfig and type(BuffBarConfig.GetStaticEntry) == "function" then
        return BuffBarConfig.GetStaticEntry(id)
    end
    return nil
end

local function resolveAsset(def)
    if type(def.IconAssetId) == "string" and #def.IconAssetId > 0 then
        return def.IconAssetId
    end
    if AssetCodes and type(AssetCodes.Get) == "function" and type(def.IconKey) == "string" then
        local ok, assetId = pcall(function()
            return AssetCodes.Get(def.IconKey)
        end)
        if ok and type(assetId) == "string" and #assetId > 0 then
            return assetId
        end
    end
    return nil
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function nowFor(kind)
    if kind == "os" then
        return os.time()
    end
    return workspace:GetServerTimeNow()
end

for _, guiName in ipairs({ "BuffBarGui", "EventObjectiveTracker", "EventPopupGui" }) do
    local old = playerGui:FindFirstChild(guiName)
    if old then
        old:Destroy()
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuffBarGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 245
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local TILE_SIZE = px(70)
local TILE_WIDTH = px(76)
local TIMER_HEIGHT = px(20)
local TILE_GAP = px(8)
local TOTAL_HEIGHT = TILE_SIZE + px(4) + TIMER_HEIGHT

local container = Instance.new("Frame")
container.Name = "BuffBarContainer"
container.AnchorPoint = Vector2.new(1, 1)
container.BackgroundTransparency = 1
container.Size = UDim2.new(0, px(540), 0, TOTAL_HEIGHT)
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, TILE_GAP)
layout.Parent = container

local relayoutTiles

local function applyLayout()
    TILE_SIZE = px(70)
    TILE_WIDTH = px(76)
    TIMER_HEIGHT = px(20)
    TILE_GAP = px(8)
    TOTAL_HEIGHT = TILE_SIZE + px(4) + TIMER_HEIGHT

    local bottomOffset = UserInputService.TouchEnabled and px(48) or px(24)
    container.Position = UDim2.new(1, -px(14), 1, -bottomOffset)
    container.Size = UDim2.new(0, px(560), 0, TOTAL_HEIGHT)
    layout.Padding = UDim.new(0, TILE_GAP)
    if relayoutTiles then
        relayoutTiles()
    end
end

applyLayout()

local cameraConn
local function bindCamera()
    if cameraConn then
        cameraConn:Disconnect()
        cameraConn = nil
    end
    local cam = workspace.CurrentCamera
    if cam then
        cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
    end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCamera()
    task.defer(applyLayout)
end)

local activeEntries = {}
local tileRefs = {}

relayoutTiles = function()
    for _, refs in pairs(tileRefs) do
        if refs.wrapper then
            refs.wrapper.Size = UDim2.new(0, TILE_WIDTH, 0, TOTAL_HEIGHT)
        end
        if refs.iconFrame then
            refs.iconFrame.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
        end
        if refs.timerLabel then
            refs.timerLabel.Position = UDim2.new(0, 0, 0, TILE_SIZE + px(3))
            refs.timerLabel.Size = UDim2.new(1, 0, 0, TIMER_HEIGHT)
            refs.timerLabel.TextSize = math.max(11, px(14))
        end
        if refs.textConstraint then
            local entry = refs.entryId and activeEntries[refs.entryId]
            local def = entry and entry.def
            refs.textConstraint.MaxTextSize = px(def and def.IconLabel and 34 or 80)
        end
    end
end

local function updateTileTimer(id)
    local entry = activeEntries[id]
    local refs = tileRefs[id]
    if not entry or not refs then
        return false
    end

    if entry.expiresAt then
        local remaining = entry.expiresAt - nowFor(entry.timeKind)
        if remaining <= 0 then
            return false
        end
        refs.timerLabel.Text = formatTime(remaining)
    else
        refs.timerLabel.Text = entry.fixedLabel or "ACTIVE"
    end
    refs.timerLabel.TextColor3 = entry.accent
    return true
end

local function createTile(entry)
    local def = entry.def
    local accent = entry.accent

    local wrapper = Instance.new("Frame")
    wrapper.Name = "BuffTile_" .. entry.id
    wrapper.BackgroundTransparency = 1
    wrapper.Size = UDim2.new(0, TILE_WIDTH, 0, TOTAL_HEIGHT)
    wrapper.LayoutOrder = entry.sortOrder
    wrapper.Parent = container

    local iconFrame = Instance.new("Frame")
    iconFrame.Name = "IconFrame"
    iconFrame.AnchorPoint = Vector2.new(0.5, 0)
    iconFrame.Position = UDim2.new(0.5, 0, 0, 0)
    iconFrame.Size = UDim2.new(0, TILE_SIZE, 0, TILE_SIZE)
    iconFrame.BackgroundColor3 = COLORS.iconBg
    iconFrame.BackgroundTransparency = 0.05
    iconFrame.BorderSizePixel = 0
    iconFrame.ClipsDescendants = true
    iconFrame.Parent = wrapper

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, px(8))
    corner.Parent = iconFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = accent
    stroke.Thickness = 1.6
    stroke.Transparency = 0.12
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = iconFrame

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 32, 50)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 24)),
    })
    gradient.Parent = iconFrame

    local assetId = resolveAsset(def)
    if def.IconShape == "plus" then
        local arm = Color3.new(1, 1, 1)
        local plusV = Instance.new("Frame")
        plusV.Name = "PlusV"
        plusV.AnchorPoint = Vector2.new(0.5, 0.5)
        plusV.Position = UDim2.new(0.5, 0, 0.5, 0)
        plusV.Size = UDim2.new(0.26, 0, 0.78, 0)
        plusV.BackgroundColor3 = arm
        plusV.BorderSizePixel = 0
        plusV.Parent = iconFrame
        local cV = Instance.new("UICorner")
        cV.CornerRadius = UDim.new(0, px(3))
        cV.Parent = plusV

        local plusH = Instance.new("Frame")
        plusH.Name = "PlusH"
        plusH.AnchorPoint = Vector2.new(0.5, 0.5)
        plusH.Position = UDim2.new(0.5, 0, 0.5, 0)
        plusH.Size = UDim2.new(0.78, 0, 0.26, 0)
        plusH.BackgroundColor3 = arm
        plusH.BorderSizePixel = 0
        plusH.Parent = iconFrame
        local cH = Instance.new("UICorner")
        cH.CornerRadius = UDim.new(0, px(3))
        cH.Parent = plusH

        -- Tint background slightly with accent for visual identity
        iconFrame.BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.65)
    elseif assetId then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.Size = UDim2.new(0.92, 0, 0.92, 0)
        icon.BackgroundTransparency = 1
        icon.Image = assetId
        icon.ScaleType = Enum.ScaleType.Fit
        icon.ImageColor3 = def.TintImage == true and accent or Color3.new(1, 1, 1)
        icon.Parent = iconFrame
    else
        local glyph = Instance.new("TextLabel")
        glyph.Name = "Glyph"
        glyph.AnchorPoint = Vector2.new(0.5, 0.5)
        glyph.Position = def.IconLabel and UDim2.new(0.5, 0, 0.38, 0) or UDim2.new(0.5, 0, 0.5, 0)
        glyph.Size = def.IconLabel and UDim2.new(0.82, 0, 0.58, 0) or UDim2.new(0.95, 0, 0.95, 0)
        glyph.BackgroundTransparency = 1
        glyph.Font = Enum.Font.GothamBlack
        glyph.Text = tostring(def.IconGlyph or def.DisplayName or "*")
        glyph.TextColor3 = accent
        glyph.TextScaled = true
        glyph.TextWrapped = false
        glyph.TextXAlignment = Enum.TextXAlignment.Center
        glyph.TextYAlignment = Enum.TextYAlignment.Center
        glyph.Parent = iconFrame

        local textConstraint = Instance.new("UITextSizeConstraint")
        textConstraint.MinTextSize = 10
        textConstraint.MaxTextSize = px(def.IconLabel and 34 or 80)
        textConstraint.Parent = glyph

        if def.IconLabel then
            local iconLabel = Instance.new("TextLabel")
            iconLabel.Name = "IconLabel"
            iconLabel.AnchorPoint = Vector2.new(0.5, 1)
            iconLabel.Position = UDim2.new(0.5, 0, 0.92, 0)
            iconLabel.Size = UDim2.new(0.92, 0, 0, px(16))
            iconLabel.BackgroundTransparency = 1
            iconLabel.Font = Enum.Font.GothamBlack
            iconLabel.Text = tostring(def.IconLabel)
            iconLabel.TextColor3 = accent
            iconLabel.TextScaled = true
            iconLabel.TextXAlignment = Enum.TextXAlignment.Center
            iconLabel.TextYAlignment = Enum.TextYAlignment.Center
            iconLabel.Parent = iconFrame

            local labelStroke = Instance.new("UIStroke")
            labelStroke.Color = Color3.fromRGB(0, 0, 0)
            labelStroke.Thickness = 1
            labelStroke.Transparency = 0.12
            labelStroke.Parent = iconLabel

            local labelConstraint = Instance.new("UITextSizeConstraint")
            labelConstraint.MinTextSize = 8
            labelConstraint.MaxTextSize = px(13)
            labelConstraint.Parent = iconLabel
        end
    end

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "Timer"
    timerLabel.BackgroundTransparency = 1
    timerLabel.Position = UDim2.new(0, 0, 0, TILE_SIZE + px(3))
    timerLabel.Size = UDim2.new(1, 0, 0, TIMER_HEIGHT)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Text = "--:--"
    timerLabel.TextSize = math.max(11, px(14))
    timerLabel.TextXAlignment = Enum.TextXAlignment.Center
    timerLabel.TextYAlignment = Enum.TextYAlignment.Center
    timerLabel.TextTruncate = Enum.TextTruncate.AtEnd
    timerLabel.TextColor3 = accent
    timerLabel.Parent = wrapper

    local timerStroke = Instance.new("UIStroke")
    timerStroke.Color = Color3.fromRGB(0, 0, 0)
    timerStroke.Thickness = 1
    timerStroke.Transparency = 0.15
    timerStroke.Parent = timerLabel

    local scale = Instance.new("UIScale")
    scale.Scale = 0.88
    scale.Parent = wrapper
    TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    tileRefs[entry.id] = {
        entryId = entry.id,
        wrapper = wrapper,
        iconFrame = iconFrame,
        timerLabel = timerLabel,
        stroke = stroke,
        scale = scale,
        textConstraint = iconFrame:FindFirstChildWhichIsA("UITextSizeConstraint", true),
    }
    updateTileTimer(entry.id)
end

local function removeEntry(id)
    activeEntries[id] = nil
    local refs = tileRefs[id]
    tileRefs[id] = nil
    if refs and refs.wrapper then
        local wrapper = refs.wrapper
        if refs.scale then
            TweenService:Create(refs.scale, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.82 }):Play()
        end
        TweenService:Create(wrapper, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
        task.delay(0.11, function()
            if wrapper and wrapper.Parent then
                wrapper:Destroy()
            end
        end)
    end
end

local function upsertEntry(id, def, options)
    options = options or {}
    if not def then
        removeEntry(id)
        return
    end

    local expiresAt = tonumber(options.expiresAt)
    local timeKind = options.timeKind or "server"
    if expiresAt and expiresAt <= nowFor(timeKind) then
        removeEntry(id)
        return
    end

    local entry = activeEntries[id]
    local definition = cloneDefinition(def)
    local accent = colorFrom(definition.IconColor, COLORS.gold)
    if not entry then
        entry = { id = id }
        activeEntries[id] = entry
    end

    entry.def = definition
    entry.kind = options.kind or definition.Kind
    entry.expiresAt = expiresAt
    entry.timeKind = timeKind
    entry.fixedLabel = options.fixedLabel
    entry.sortOrder = options.sortOrder or definition.SortOrder or 999
    entry.accent = accent

    if tileRefs[id] then
        local refs = tileRefs[id]
        refs.wrapper.LayoutOrder = entry.sortOrder
        if refs.stroke then
            refs.stroke.Color = accent
        end
        updateTileTimer(id)
    else
        createTile(entry)
    end
end

RunService.Heartbeat:Connect(function()
    local currentSecond = math.floor(workspace:GetServerTimeNow())
    if screenGui:GetAttribute("LastSecond") == currentSecond then
        return
    end
    screenGui:SetAttribute("LastSecond", currentSecond)

    for id in pairs(activeEntries) do
        if not updateTileTimer(id) then
            removeEntry(id)
        end
    end
end)

local function syncEvent(active, eventId, endTime)
    if not active then
        removeEntry("event")
        return
    end

    local expiresAt = tonumber(endTime) or tonumber(ReplicatedStorage:GetAttribute("EventEndTime")) or 0
    local def = getStaticDef("event") or { Id = "event", DisplayName = "Event", IconGlyph = "EVENT", IconColor = {255, 215, 80}, SortOrder = 10 }
    local eventDef = EventConfig and EventConfig.EventDefs and EventConfig.EventDefs[eventId]
    if eventDef then
        def.DisplayName = eventDef.Name or def.DisplayName
        def.IconKey = eventDef.IconKey or def.IconKey
        def.IconAssetId = eventDef.IconAssetId or def.IconAssetId
        def.IconColor = eventDef.IconColor or def.IconColor
    end
    upsertEntry("event", def, { expiresAt = expiresAt, timeKind = "server" })
end

local function syncEventFromAttributes()
    syncEvent(
        ReplicatedStorage:GetAttribute("EventActive") == true,
        ReplicatedStorage:GetAttribute("ActiveEventId"),
        ReplicatedStorage:GetAttribute("EventEndTime")
    )
end

task.spawn(function()
    syncEventFromAttributes()
    local eventRemote = ReplicatedStorage:WaitForChild("EventStateChanged", 15)
    if eventRemote and eventRemote:IsA("RemoteEvent") then
        eventRemote.OnClientEvent:Connect(syncEvent)
    end
end)
ReplicatedStorage:GetAttributeChangedSignal("EventActive"):Connect(syncEventFromAttributes)
ReplicatedStorage:GetAttributeChangedSignal("ActiveEventId"):Connect(syncEventFromAttributes)
ReplicatedStorage:GetAttributeChangedSignal("EventEndTime"):Connect(syncEventFromAttributes)

local characterConnections = {}

local function clearCharacterConnections()
    for _, conn in ipairs(characterConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    table.clear(characterConnections)
end

local function syncHutHeal(humanoid)
    if not humanoid or humanoid.Health <= 0 or humanoid:GetAttribute("_hut_heal_active") ~= true then
        removeEntry("hut_heal")
        return
    end

    local endTime = tonumber(humanoid:GetAttribute("_hut_heal_end_time"))
    if not endTime or endTime <= 0 then
        endTime = workspace:GetServerTimeNow() + 8
    end
    upsertEntry("hut_heal", getStaticDef("hut_heal"), { expiresAt = endTime, timeKind = "server" })
end

local function syncBandage(character)
    if not character or character:GetAttribute("IsBandaging") ~= true then
        removeEntry("bandage")
        return
    end

    local endTime = tonumber(character:GetAttribute("BandageEndTime"))
    if not endTime or endTime <= 0 then
        endTime = workspace:GetServerTimeNow() + (tonumber(BandageConfig.CastDuration) or 6)
    end
    upsertEntry("bandage", getStaticDef("bandage"), { expiresAt = endTime, timeKind = "server" })
end

local function bindCharacter(character)
    clearCharacterConnections()
    removeEntry("hut_heal")
    removeEntry("bandage")

    if not character then
        return
    end

    table.insert(characterConnections, character:GetAttributeChangedSignal("IsBandaging"):Connect(function()
        syncBandage(character)
    end))
    table.insert(characterConnections, character:GetAttributeChangedSignal("BandageEndTime"):Connect(function()
        syncBandage(character)
    end))

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    if humanoid then
        table.insert(characterConnections, humanoid:GetAttributeChangedSignal("_hut_heal_active"):Connect(function()
            syncHutHeal(humanoid)
        end))
        table.insert(characterConnections, humanoid:GetAttributeChangedSignal("_hut_heal_end_time"):Connect(function()
            syncHutHeal(humanoid)
        end))
        table.insert(characterConnections, humanoid.Died:Connect(function()
            removeEntry("hut_heal")
            removeEntry("bandage")
        end))
        syncHutHeal(humanoid)
    end

    syncBandage(character)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
    task.defer(bindCharacter, player.Character)
end

task.spawn(function()
    local bandageStarted = ReplicatedStorage:WaitForChild("BandageStarted", 10)
    if bandageStarted and bandageStarted:IsA("RemoteEvent") then
        bandageStarted.OnClientEvent:Connect(function(endTime)
            local character = player.Character
            local expiresAt = tonumber(endTime)
            if not expiresAt or expiresAt <= 0 then
                expiresAt = character and tonumber(character:GetAttribute("BandageEndTime"))
            end
            if not expiresAt or expiresAt <= 0 then
                expiresAt = workspace:GetServerTimeNow() + (tonumber(BandageConfig.CastDuration) or 6)
            end
            upsertEntry("bandage", getStaticDef("bandage"), { expiresAt = expiresAt, timeKind = "server" })
            syncBandage(character)
        end)
    end

    local bandageEnded = ReplicatedStorage:WaitForChild("BandageEnded", 10)
    if bandageEnded and bandageEnded:IsA("RemoteEvent") then
        bandageEnded.OnClientEvent:Connect(function()
            removeEntry("bandage")
        end)
    end
end)

local function syncFlag()
    local flagTeam = player:GetAttribute("CarryingFlag")
    if not flagTeam then
        removeEntry("flag")
        return
    end

    local teamName = tostring(flagTeam)
    local def = getStaticDef(teamName == "Blue" and "flag_blue" or "flag_red")
    if not def then
        return
    end
    def.DisplayName = teamName .. " Flag"
    upsertEntry("flag", def, { fixedLabel = "FLAG", sortOrder = def.SortOrder or 40 })
end

player:GetAttributeChangedSignal("CarryingFlag"):Connect(syncFlag)
task.defer(syncFlag)

local function applyBoostStates(states)
    if type(states) ~= "table" or not BoostConfig or not BuffBarConfig then
        return
    end

    local serverTime = tonumber(states._serverTime) or os.time()
    local delta = os.time() - serverTime
    local activeBoostIds = {}

    for _, def in ipairs(BoostConfig.Boosts or {}) do
        if def.Type == "Timed" then
            local state = states[def.Id]
            if state and state.active then
                local expiresAt = (tonumber(state.expiresAt) or 0) + delta
                if expiresAt > os.time() then
                    local boostDef = BuffBarConfig.FromBoostDef(def)
                    if boostDef then
                        activeBoostIds[boostDef.Id] = true
                        upsertEntry(boostDef.Id, boostDef, { kind = "boost", expiresAt = expiresAt, timeKind = "os" })
                    end
                end
            end
        end
    end

    for id, entry in pairs(activeEntries) do
        if entry.kind == "boost" and not activeBoostIds[id] then
            removeEntry(id)
        end
    end
end

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then
        return
    end

    local stateEvent = remotes:WaitForChild("BoostStateUpdated", 10)
    if stateEvent and stateEvent:IsA("RemoteEvent") then
        stateEvent.OnClientEvent:Connect(applyBoostStates)
    end

    local boostFolder = remotes:WaitForChild("Boosts", 5)
    local getStates = boostFolder and boostFolder:FindFirstChild("GetBoostStates")
    if getStates and getStates:IsA("RemoteFunction") then
        local ok, states = pcall(function()
            return getStates:InvokeServer()
        end)
        if ok then
            applyBoostStates(states)
        end
    end
end)