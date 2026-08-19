local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local mapVoteFolder = remotes:WaitForChild("MapVote")
local CastVoteRE = mapVoteFolder:WaitForChild("CastVote")
local UpdateRE = mapVoteFolder:WaitForChild("Update")
local PhaseRE = mapVoteFolder:WaitForChild("Phase")

-- UI creation
local screen = Instance.new("ScreenGui")
screen.Name = "MapVoteUI"
screen.ResetOnSpawn = false
screen.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Size = UDim2.new(0, 640, 0, 220)
root.Position = UDim2.new(0.5, 0, 0.12, 0)
root.BackgroundTransparency = 0.35
root.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
root.BorderSizePixel = 0
root.Visible = false
root.Parent = screen

local title = Instance.new("TextLabel")
title.Parent = root
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Vote for the next map"
title.TextSize = 24
title.TextColor3 = Color3.fromRGB(255, 220, 120)

local timerLabel = Instance.new("TextLabel")
timerLabel.Parent = root
timerLabel.Size = UDim2.new(0, 120, 0, 28)
timerLabel.Position = UDim2.new(1, -128, 0, 8)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.Gotham
timerLabel.TextSize = 20
timerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
timerLabel.Text = ""

local optionsFrame = Instance.new("Frame")
optionsFrame.Parent = root
optionsFrame.Size = UDim2.new(1, -24, 0, 160)
optionsFrame.Position = UDim2.new(0, 12, 0, 46)
optionsFrame.BackgroundTransparency = 1

local function createOption(mapName)
    local option = Instance.new("Frame")
    option.Name = "Option_" .. mapName
    option.Size = UDim2.new(0, 280, 0, 140)
    option.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    option.BorderSizePixel = 0
    option.Parent = optionsFrame

    local label = Instance.new("TextLabel")
    label.Parent = option
    label.Size = UDim2.new(1, 0, 0, 28)
    label.Position = UDim2.new(0, 0, 0, 6)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.Text = mapName

    local voteArea = Instance.new("Frame")
    voteArea.Name = "Voters"
    voteArea.Parent = option
    voteArea.Size = UDim2.new(1, -8, 1, -40)
    voteArea.Position = UDim2.new(0, 4, 0, 36)
    voteArea.BackgroundTransparency = 1

    -- click handling
    option.Active = true
    option.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if CastVoteRE then
                CastVoteRE:FireServer(mapName)
            end
        end
    end)

    return option
end

-- Build options from ReplicatedStorage.Maps
local function rebuildOptions()
    for _, child in ipairs(optionsFrame:GetChildren()) do
        child:Destroy()
    end
    -- layout
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 12)
    layout.Parent = optionsFrame

    local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
    if not mapsFolder then return end
    local maps = mapsFolder:GetChildren()
    table.sort(maps, function(a,b) return a.Name < b.Name end)
    for i, map in ipairs(maps) do
        local opt = createOption(map.Name)
        opt.LayoutOrder = i
    end
end

rebuildOptions()

-- Helper to place player icons in a circular layout inside a target frame
local function placeIconsCircular(targetFrame, userIdList)
    -- clear
    for _, child in ipairs(targetFrame:GetChildren()) do
        child:Destroy()
    end
    if #userIdList == 0 then return end
    local centerX = targetFrame.AbsoluteSize.X/2
    local centerY = targetFrame.AbsoluteSize.Y/2
    local radius = math.min(centerX, centerY) - 20
    radius = math.max(radius, 20)
    for i, uid in ipairs(userIdList) do
        local angle = (i-1) * (2*math.pi / #userIdList)
        local px = centerX + math.cos(angle) * radius
        local py = centerY + math.sin(angle) * radius

        local img = Instance.new("ImageLabel")
        img.Name = "Voter_" .. tostring(uid)
        img.Size = UDim2.new(0, 38, 0, 38)
        img.Position = UDim2.new(0, px - 19, 0, py - 19)
        img.AnchorPoint = Vector2.new(0,0)
        img.BackgroundTransparency = 1
        img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(uid) .. "&w=48&h=48"
        img.Parent = targetFrame
        img.ZIndex = 5
    end
end

-- Update handler from server
if UpdateRE then
    UpdateRE.OnClientEvent:Connect(function(payload)
        if not payload or type(payload.mapVotes) ~= "table" then
            -- clear all voter lists
            for _, opt in ipairs(optionsFrame:GetChildren()) do
                if opt:IsA("Frame") then
                    local vf = opt:FindFirstChild("Voters")
                    if vf then
                        for _, c in ipairs(vf:GetChildren()) do c:Destroy() end
                    end
                end
            end
            return
        end
        -- update each option with voters (may be empty)
        for _, opt in ipairs(optionsFrame:GetChildren()) do
            if opt:IsA("Frame") then
                local name = opt.Name:match("^Option_(.+)$")
                local voters = payload.mapVotes[name] or {}
                local votersFrame = opt:FindFirstChild("Voters")
                if votersFrame then
                    placeIconsCircular(votersFrame, voters)
                end
            end
        end
    end)
end

-- Phase handler
if PhaseRE then
    PhaseRE.OnClientEvent:Connect(function(payload)
        if not payload then return end
        local phase = payload.phase
        local duration = payload.duration or 0
        if phase == "voting" then
            root.Visible = true
            -- start countdown
            local endsAt = tick() + duration
            spawn(function()
                while root.Visible do
                    local left = math.max(0, math.floor(endsAt - tick()))
                    timerLabel.Text = string.format("Voting: %ds", left)
                    if left <= 0 then break end
                    task.wait(0.25)
                end
            end)
        else
            root.Visible = false
        end
    end)
end

-- Rebuild options if Maps folder changes
local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
if mapsFolder then
    mapsFolder.ChildAdded:Connect(rebuildOptions)
    mapsFolder.ChildRemoved:Connect(rebuildOptions)
end
