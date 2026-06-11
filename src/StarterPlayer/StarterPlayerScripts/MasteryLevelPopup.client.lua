local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local masteryRemote = ReplicatedStorage:WaitForChild("WeaponMasteryUpdated", 10)
if not masteryRemote or not masteryRemote:IsA("RemoteEvent") then
    return
end

local ROMAN_NUMERALS = {
    [0] = "NIL",
    [1] = "I",
    [2] = "II",
    [3] = "III",
    [4] = "IV",
    [5] = "V",
    [6] = "VI",
    [7] = "VII",
    [8] = "VIII",
    [9] = "IX",
    [10] = "X",
}

local popupGui = Instance.new("ScreenGui")
popupGui.Name = "MasteryLevelPopupGui"
popupGui.ResetOnSpawn = false
popupGui.IgnoreGuiInset = true
popupGui.DisplayOrder = 40
popupGui.Parent = playerGui

local warnedMissingSound = false
local cachedSoundTemplate = nil
local lastShownLevelByWeapon = {}
local popupQueue = {}
local popupRunnerActive = false
local popupRandom = Random.new()

local POPUP_X_MIN = 0.47
local POPUP_X_MAX = 0.65
local POPUP_Y_MIN = 0.38
local POPUP_Y_MAX = 0.60
local POPUP_LIFETIME = 2.8

local function getMasterySoundTemplate()
    if cachedSoundTemplate and cachedSoundTemplate.Parent then
        return cachedSoundTemplate
    end

    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then
        return nil
    end

    local template = soundsFolder:FindFirstChild("Mastery")
    if not template then
        template = soundsFolder:FindFirstChild("Mastery", true)
    end
    if template and template:IsA("Sound") then
        cachedSoundTemplate = template
        return template
    end
    return nil
end

local function playMasterySound()
    local template = getMasterySoundTemplate()
    if not template then
        if not warnedMissingSound then
            warnedMissingSound = true
            warn("[MasteryLevelPopup] ReplicatedStorage.Sounds.Mastery not found; mastery popup sound disabled")
        end
        return
    end

    local sound = template:Clone()
    sound.Parent = SoundService
    sound:Play()
    task.delay(math.max(1, (sound.TimeLength or 1) + 0.25), function()
        if sound and sound.Parent then
            sound:Destroy()
        end
    end)
end

local function getRomanNumeral(level)
    local numericLevel = math.max(0, math.floor(tonumber(level) or 0))
    return ROMAN_NUMERALS[numericLevel] or tostring(numericLevel)
end

local function showPopup(level)
    local container = Instance.new("Frame")
    container.Name = "MasteryLevelPopup"
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Size = UDim2.fromOffset(210, 86)
    container.Position = UDim2.new(
        popupRandom:NextNumber(POPUP_X_MIN, POPUP_X_MAX),
        popupRandom:NextInteger(-18, 18),
        popupRandom:NextNumber(POPUP_Y_MIN, POPUP_Y_MAX),
        popupRandom:NextInteger(-12, 12)
    )
    container.Rotation = popupRandom:NextNumber(-4, 4)
    container.Parent = popupGui

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.AnchorPoint = Vector2.new(0.5, 0)
    titleLabel.Position = UDim2.new(0.5, 0, 0, 0)
    titleLabel.Size = UDim2.new(1, 0, 0.32, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.BorderSizePixel = 0
    titleLabel.Font = Enum.Font.Garamond
    titleLabel.Text = "MASTERY"
    titleLabel.TextColor3 = Color3.fromRGB(234, 212, 156)
    titleLabel.TextScaled = true
    titleLabel.TextTransparency = 1
    titleLabel.Parent = container

    local titleSize = Instance.new("UITextSizeConstraint")
    titleSize.MinTextSize = 14
    titleSize.MaxTextSize = 22
    titleSize.Parent = titleLabel

    local numeralLabel = Instance.new("TextLabel")
    numeralLabel.Name = "Numeral"
    numeralLabel.AnchorPoint = Vector2.new(0.5, 1)
    numeralLabel.Position = UDim2.new(0.5, 0, 1, 0)
    numeralLabel.Size = UDim2.new(1, 0, 0.78, 0)
    numeralLabel.BackgroundTransparency = 1
    numeralLabel.BorderSizePixel = 0
    numeralLabel.Font = Enum.Font.Garamond
    numeralLabel.Text = getRomanNumeral(level)
    numeralLabel.TextColor3 = Color3.fromRGB(255, 241, 182)
    numeralLabel.TextScaled = true
    numeralLabel.TextTransparency = 1
    numeralLabel.Parent = container

    local numeralSize = Instance.new("UITextSizeConstraint")
    numeralSize.MinTextSize = 26
    numeralSize.MaxTextSize = 50
    numeralSize.Parent = numeralLabel

    playMasterySound()

    local originPosition = container.Position
    local driftGoal = originPosition + UDim2.new(0, popupRandom:NextInteger(-14, 14), -0.05, 0)
    TweenService:Create(container, TweenInfo.new(POPUP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = driftGoal,
    }):Play()

    local fadeInInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(titleLabel, fadeInInfo, { TextTransparency = 0 }):Play()
    TweenService:Create(numeralLabel, fadeInInfo, { TextTransparency = 0 }):Play()

    task.delay(POPUP_LIFETIME - 0.55, function()
        if not container.Parent then
            return
        end
        local fadeOutInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(titleLabel, fadeOutInfo, { TextTransparency = 1 }):Play()
        TweenService:Create(numeralLabel, fadeOutInfo, { TextTransparency = 1 }):Play()
        task.delay(0.5, function()
            if container and container.Parent then
                container:Destroy()
            end
        end)
    end)
end

local function runPopupQueue()
    if popupRunnerActive then
        return
    end
    popupRunnerActive = true
    task.spawn(function()
        while #popupQueue > 0 do
            local entry = table.remove(popupQueue, 1)
            showPopup(entry.level)
            task.wait(POPUP_LIFETIME)
        end
        popupRunnerActive = false
    end)
end

local function queuePopup(level)
    table.insert(popupQueue, { level = level })
    runPopupQueue()
end

masteryRemote.OnClientEvent:Connect(function(instanceId, mastery, meta)
    if type(meta) ~= "table" or meta.leveledUp ~= true then
        return
    end
    if type(instanceId) ~= "string" or instanceId == "" then
        return
    end

    local newLevel = math.max(1, math.floor(tonumber(meta.newLevel or (type(mastery) == "table" and mastery.level) or 1) or 1))
    local oldLevel = math.max(0, math.floor(tonumber(meta.oldLevel) or (newLevel - 1)))
    local lastShownLevel = lastShownLevelByWeapon[instanceId] or 0
    if newLevel <= lastShownLevel then
        return
    end

    for level = math.max(oldLevel + 1, lastShownLevel + 1), newLevel do
        queuePopup(level)
    end
    lastShownLevelByWeapon[instanceId] = newLevel
end)