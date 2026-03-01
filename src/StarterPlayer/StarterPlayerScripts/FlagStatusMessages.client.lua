local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fantasy PvP theme palette
local NAVY       = Color3.fromRGB(12, 14, 28)
local GOLD_TEXT   = Color3.fromRGB(255, 215, 80)

-- create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlagStatusGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Parent = playerGui

local FlagStatus = ReplicatedStorage:WaitForChild("FlagStatus")

local EVENT_SOUNDS = {
    pickup = "Flag_taken",
    returned = "Flag_return",
    captured = "Flag_capture",
}

local messageQueue = {}
local processing = false

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function colorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function teamHex(teamName)
    if teamName == "Blue" then return colorToHex(Color3.fromRGB(65, 130, 255)) end
    if teamName == "Red"  then return colorToHex(Color3.fromRGB(255, 75, 75)) end
    return GOLD_HEX
end

local GOLD_HEX = colorToHex(GOLD_TEXT)

local function playLocalSound(soundName)
    if not soundName then return end
    local sounds = ReplicatedStorage:FindFirstChild("Sounds")
    if not sounds then return end
    local flagFolder = sounds:FindFirstChild("Flag")
    if not flagFolder then return end
    local s = flagFolder:FindFirstChild(soundName)
    if not s or not s:IsA("Sound") then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local snd = s:Clone()
    snd.Parent = cam
    snd:Play()
    task.delay((snd.TimeLength or 3) + 0.5, function()
        if snd and snd.Parent then snd:Destroy() end
    end)
end

---------------------------------------------------------------------
-- build RichText with gold verb highlights
---------------------------------------------------------------------
local function buildRichText(item)
    local white = GOLD_HEX
    local pHex = teamHex(item.playerTeamName)
    local fHex = teamHex(item.flagTeamName)
    local teamWord = item.flagTeamName or ""

    if item.eventType == "pickup" then
        return string.format(
            "<font color='%s'>%s</font><font color='%s'> picked up the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
            pHex, item.playerName or "", GOLD_HEX, fHex, teamWord, white)
    elseif item.eventType == "captured" then
        return string.format(
            "<font color='%s'>%s</font><font color='%s'> captured the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
            pHex, item.playerName or "", GOLD_HEX, fHex, teamWord, white)
    elseif item.eventType == "returned" then
        if item.playerName and item.playerName ~= "" then
            return string.format(
                "<font color='%s'>%s</font><font color='%s'> returned the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
                pHex, item.playerName, GOLD_HEX, fHex, teamWord, white)
        else
            return string.format(
                "<font color='%s'>The </font><font color='%s'>%s</font><font color='%s'> Flag has been returned!</font>",
                GOLD_HEX, fHex, teamWord, white)
        end
    end
    return item.playerName or ""
end

---------------------------------------------------------------------
-- show one message for 3 seconds
---------------------------------------------------------------------
local function displayItem(item)
    local soundName = EVENT_SOUNDS[item.eventType]
    if soundName then playLocalSound(soundName) end

    -- dark navy banner with gold border
    local panel = Instance.new("Frame")
    panel.Name = "FlagMsgPanel"
    panel.Size = UDim2.new(0.5, 0, 0, 44)
    panel.AnchorPoint = Vector2.new(0.5, 0)
    panel.Position = UDim2.new(0.5, 0, 0.12, 0)
    panel.BackgroundColor3 = NAVY
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.ZIndex = 100
    panel.Parent = screenGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 4)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(80, 65, 20)
    panelStroke.Thickness = 1.5
    panelStroke.Transparency = 0.3
    panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    panelStroke.Parent = panel

    local label = Instance.new("TextLabel")
    label.Name = "FlagMsg"
    label.Size = UDim2.new(1, -24, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.RichText = true
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.ZIndex = 101
    label.Text = buildRichText(item)
    label.TextTransparency = 1
    label.Parent = panel

    local lblStroke = Instance.new("UIStroke")
    lblStroke.Color = Color3.fromRGB(0, 0, 0)
    lblStroke.Thickness = 1
    lblStroke.Transparency = 0.3
    lblStroke.Parent = label

    -- pop-in: measure text bounds and size panel just wider than the text
    task.wait()
    local textW = (label.TextBounds and label.TextBounds.X) or 0
    local textH = (label.TextBounds and label.TextBounds.Y) or 18
    if textW < 80 then textW = 80 end
    local padX = 48
    local targetW = math.ceil(textW + padX)
    local targetH = math.ceil(textH + 20)

    panel.Size = UDim2.new(0, math.max(120, math.floor(targetW * 0.75)), 0, math.max(38, math.floor(targetH * 0.75)))
    panel.BackgroundTransparency = 0.6
    local popIn = TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, targetW, 0, targetH),
        BackgroundTransparency = 0.08,
    })
    local fadeIn = TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0 })
    popIn:Play()
    fadeIn:Play()

    -- visible for 2.6s then fade over 0.4s = 3s total
    task.wait(2.6)
    if panel and panel.Parent then
        local fadeOut = TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            TextTransparency = 1,
        })
        local panelFade = TweenService:Create(panel, TweenInfo.new(0.4), {
            BackgroundTransparency = 1,
        })
        local strokeFade = TweenService:Create(panelStroke, TweenInfo.new(0.4), {
            Transparency = 1,
        })
        fadeOut:Play()
        panelFade:Play()
        strokeFade:Play()
        panelFade.Completed:Wait()
        if panel and panel.Parent then panel:Destroy() end
    end
end

---------------------------------------------------------------------
-- queue processor
---------------------------------------------------------------------
local function processQueue()
    if processing then return end
    processing = true
    task.spawn(function()
        while #messageQueue > 0 do
            local item = table.remove(messageQueue, 1)
            displayItem(item)
        end
        processing = false
    end)
end

---------------------------------------------------------------------
-- listen for events
---------------------------------------------------------------------
FlagStatus.OnClientEvent:Connect(function(eventType, playerName, playerTeamName, flagTeamName)
    if eventType == "playSound" then return end

    if eventType == "pickup" or eventType == "returned" or eventType == "captured" then
        table.insert(messageQueue, {
            eventType = eventType,
            playerName = playerName,
            playerTeamName = playerTeamName,
            flagTeamName = flagTeamName,
        })
        processQueue()
    end
end)
