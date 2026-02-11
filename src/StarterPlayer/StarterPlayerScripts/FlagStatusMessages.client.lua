local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlagStatusGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Parent = playerGui

local FlagStatus = ReplicatedStorage:WaitForChild("FlagStatus")

-- map message types to their sounds so we don't need to pair separate events
local EVENT_SOUNDS = {
    pickup = "Flag_taken",
    returned = "Flag_return",
    captured = "Flag_capture",
}

-- queue and state
local messageQueue = {}
local processing = false

---------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------
local function colorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function teamHex(teamName)
    if teamName == "Blue" then return colorToHex(Color3.fromRGB(0, 162, 255)) end
    if teamName == "Red"  then return colorToHex(Color3.fromRGB(255, 75, 75)) end
    return "#FFFFFF"
end

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
-- build RichText for a queue item
---------------------------------------------------------------------
local function buildRichText(item)
    local white = "#FFFFFF"
    local pHex = teamHex(item.playerTeamName)
    local fHex = teamHex(item.flagTeamName)
    local teamWord = item.flagTeamName or ""

    if item.eventType == "pickup" then
        return string.format(
            "<font color='%s'>%s</font><font color='%s'> picked up the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
            pHex, item.playerName or "", white, fHex, teamWord, white)
    elseif item.eventType == "captured" then
        return string.format(
            "<font color='%s'>%s</font><font color='%s'> captured the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>",
            pHex, item.playerName or "", white, fHex, teamWord, white)
    elseif item.eventType == "returned" then
        return string.format(
            "<font color='%s'>The </font><font color='%s'>%s</font><font color='%s'> Flag has been returned!</font>",
            white, fHex, teamWord, white)
    end
    return item.playerName or ""
end

---------------------------------------------------------------------
-- show one message for 3 seconds (2.6s visible + 0.4s fade)
---------------------------------------------------------------------
local function displayItem(item)
    -- play associated sound immediately
    local soundName = EVENT_SOUNDS[item.eventType]
    if soundName then playLocalSound(soundName) end

    local label = Instance.new("TextLabel")
    label.Name = "FlagMsg"
    label.Size = UDim2.new(0.6, 0, 0, 50)
    label.Position = UDim2.new(0.2, 0, 0.12, 0)
    label.AnchorPoint = Vector2.new(0, 0)
    label.BackgroundTransparency = 1
    label.RichText = true
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.ZIndex = 100
    label.Text = buildRichText(item)
    label.Parent = screenGui

    -- visible for 2.6s then fade over 0.4s = 3s total
    task.wait(2.6)
    if label and label.Parent then
        for i = 1, 8 do
            label.TextTransparency = i / 8
            label.TextStrokeTransparency = i / 8
            task.wait(0.05)
        end
        if label and label.Parent then label:Destroy() end
    end
end

---------------------------------------------------------------------
-- queue processor — one message at a time, 3s each
---------------------------------------------------------------------
local function processQueue()
    if processing then return end
    processing = true
    task.spawn(function()
        while #messageQueue > 0 do
            local item = table.remove(messageQueue, 1)
            displayItem(item)  -- blocks ~3s
        end
        processing = false
    end)
end

---------------------------------------------------------------------
-- listen for events
---------------------------------------------------------------------
FlagStatus.OnClientEvent:Connect(function(eventType, playerName, playerTeamName, flagTeamName)
    -- ignore standalone playSound events; sounds are now driven by the message queue
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
