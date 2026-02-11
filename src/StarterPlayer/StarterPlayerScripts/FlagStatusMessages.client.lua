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

local function showMessage(text, playerTeamName, flagTeamName)
    -- pick colors for player name and flag word
    local playerTeamColor = Color3.new(1, 1, 1)
    if playerTeamName == "Blue" then
        playerTeamColor = Color3.fromRGB(0, 162, 255)
    elseif playerTeamName == "Red" then
        playerTeamColor = Color3.fromRGB(255, 75, 75)
    end
    local flagTeamColor = Color3.new(1, 1, 1)
    if flagTeamName == "Blue" then
        flagTeamColor = Color3.fromRGB(0, 162, 255)
    elseif flagTeamName == "Red" then
        flagTeamColor = Color3.fromRGB(255, 75, 75)
    end

    local function colorToHex(c)
        return string.format("#%02X%02X%02X", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
    end

    local whiteHex = "#FFFFFF"
    local playerTeamHex = colorToHex(playerTeamColor)
    local flagTeamHex = colorToHex(flagTeamColor)

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
    label.Parent = screenGui
    -- set text using incoming string and team color information
    -- expected `text` forms: "<PlayerName> picked up the <Team> Flag!" or "The <Team> Flag has been returned!"
    local function makeRichText(msg)
        -- determine team word (flag team preferred)
        local teamWord = flagTeamName or playerTeamName or ""
        -- if message contains ' picked up the ', color player name by playerTeamHex and the team word by flagTeamHex
        local pickedIdx = string.find(msg, " picked up the ")
        if pickedIdx then
            local playerName = string.sub(msg, 1, pickedIdx - 1)
            return string.format("<font color='%s'>%s</font><font color='%s'> picked up the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>", playerTeamHex, playerName, whiteHex, flagTeamHex, teamWord, whiteHex)
        end
        -- handle captures using ' captured the '
        local capIdx = string.find(msg, " captured the ")
        if capIdx then
            local playerName = string.sub(msg, 1, capIdx - 1)
            return string.format("<font color='%s'>%s</font><font color='%s'> captured the </font><font color='%s'>%s</font><font color='%s'> Flag!</font>", playerTeamHex, playerName, whiteHex, flagTeamHex, teamWord, whiteHex)
        end
        -- returned message: 'The <Team> Flag has been returned!'
        local returnedIdx = string.find(msg, "The ")
        if returnedIdx then
            return string.format("<font color='%s'>The </font><font color='%s'>%s</font><font color='%s'> Flag has been returned!</font>", whiteHex, flagTeamHex, teamWord, whiteHex)
        end
        -- fallback: plain white
        return string.format("<font color='%s'>%s</font>", whiteHex, msg)
    end

    label.Text = makeRichText(text)

    -- fade out after 3 seconds
    task.delay(3, function()
        if label and label.Parent then
            for i = 1, 10 do
                label.TextTransparency = i / 10
                label.TextStrokeTransparency = i / 10
                task.wait(0.05)
            end
            if label and label.Parent then
                label:Destroy()
            end
        end
    end)
end

FlagStatus.OnClientEvent:Connect(function(eventType, playerName, playerTeamName, flagTeamName)
    if eventType == "pickup" then
        -- color player name by their team (playerTeamName), and the flag word by flagTeamName
        showMessage(playerName .. " picked up the " .. (flagTeamName or "") .. " Flag!", playerTeamName, flagTeamName)
    elseif eventType == "returned" then
        showMessage("The " .. (flagTeamName or "") .. " Flag has been returned!", nil, flagTeamName)
    elseif eventType == "captured" then
        -- show capture announcement
        showMessage(playerName .. " captured the " .. (flagTeamName or "") .. " Flag!", playerTeamName, flagTeamName)
    elseif eventType == "playSound" then
        local soundName = playerName
        -- play local sound from ReplicatedStorage.Sounds.Flag
        local sounds = ReplicatedStorage:FindFirstChild("Sounds")
        if sounds then
            local flagFolder = sounds:FindFirstChild("Flag")
            if flagFolder then
                local s = flagFolder:FindFirstChild(soundName)
                if s and s:IsA("Sound") then
                    local cam = workspace.CurrentCamera
                    if cam then
                        local snd = s:Clone()
                        snd.Parent = cam
                        snd:Play()
                        task.delay((snd.TimeLength or 3) + 0.5, function()
                            if snd and snd.Parent then
                                snd:Destroy()
                            end
                        end)
                    end
                end
            end
        end
    end
end)
