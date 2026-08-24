local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local AssetCodes = require(ReplicatedStorage:WaitForChild("AssetCodes"))

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
root.Size = UDim2.new(0.7, 0, 0.35, 0)
root.Position = UDim2.new(0.5, 0, 0.18, 0)
root.BackgroundTransparency = 0.12
root.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
root.BorderSizePixel = 0
root.Visible = false
root.Parent = screen

local rootCorner = Instance.new("UICorner", root)
rootCorner.CornerRadius = UDim.new(0, 8)
local rootStroke = Instance.new("UIStroke", root)
rootStroke.Color = Color3.fromRGB(254, 214, 56)
rootStroke.Thickness = 2
rootStroke.Transparency = 0.4
rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local title = Instance.new("TextLabel")
title.Parent = root
title.Size = UDim2.new(1, 0, 0.14, 0)
title.Position = UDim2.new(0, 0, 0, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Vote for the next map"
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 220, 120)

local timerLabel = Instance.new("TextLabel")
timerLabel.Parent = root
timerLabel.Size = UDim2.new(0.28, 0, 0.12, 0)
timerLabel.AnchorPoint = Vector2.new(1, 0)
timerLabel.Position = UDim2.new(0.98, 0, 0.02, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.Gotham
timerLabel.TextScaled = true
timerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
timerLabel.Text = ""

local optionsFrame = Instance.new("Frame")
optionsFrame.Parent = root
optionsFrame.Size = UDim2.new(0.98, 0, 0.8, 0)
optionsFrame.Position = UDim2.new(0.01, 0, 0.16, 0)
optionsFrame.BackgroundTransparency = 1

local function createOption(mapName)
    local option = Instance.new("Frame")
    option.Name = "Option_" .. mapName
    option.Size = UDim2.new(0.32, 0, 0.94, 0)
    option.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
    option.BorderSizePixel = 0
    option.Parent = optionsFrame

    local optCorner = Instance.new("UICorner", option)
    optCorner.CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Parent = option
    label.Size = UDim2.new(1, 0, 0.16, 0)
    label.Position = UDim2.new(0, 0, 0.02, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.Text = mapName
    label.ZIndex = 6

    local votesLabel = Instance.new("TextLabel")
    votesLabel.Name = "VotesLabel"
    votesLabel.Parent = option
    votesLabel.Size = UDim2.new(1, 0, 0.12, 0)
    votesLabel.Position = UDim2.new(0, 0, 0.18, 0)
    votesLabel.BackgroundTransparency = 1
    votesLabel.Font = Enum.Font.Gotham
    votesLabel.TextScaled = true
    votesLabel.TextColor3 = Color3.fromRGB(200,200,200)
    votesLabel.Text = "0 votes"
    votesLabel.ZIndex = 6

    local voteArea = Instance.new("Frame")
    voteArea.Name = "Voters"
    voteArea.Parent = option
    voteArea.Size = UDim2.new(0.96, 0, 0.78, 0)
    voteArea.Position = UDim2.new(0.02, 0, 0.32, 0)
    voteArea.BackgroundTransparency = 1

    -- Map thumbnail: try to find an asset in AssetCodes matching the map name
    local function assetKeyForName(name)
        if not name then return nil end
        -- try exact
        local v = AssetCodes.Get(name)
        if v and v ~= "" then return v end
        -- normalize: lowercase, remove spaces and non-alphanum
        local key = name:lower():gsub("%s+", "")
        key = key:gsub("[^%w_]", "")
        v = AssetCodes.Get(key)
        if v and v ~= "" then return v end
        return nil
    end
    local thumbAsset = assetKeyForName(mapName)
    if thumbAsset then
        print("[MapVoteUI] found thumbnail for", mapName, "->", thumbAsset)
        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumbnail"
        -- size and position to match the voteArea so it visually sits behind where voters appear
        thumb.Size = voteArea.Size
        thumb.Position = voteArea.Position
        thumb.BackgroundTransparency = 1
        thumb.ScaleType = Enum.ScaleType.Crop
        -- parent to the option frame (not the Voters frame) so it survives voter updates
        thumb.Parent = option
        -- ensure visible behind voter icons but above base background and below labels
        thumb.ZIndex = 4
        thumb.Image = thumbAsset
        thumb.ImageTransparency = 0
        thumb.ImageColor3 = Color3.fromRGB(255,255,255)
        thumb.Visible = true
    else
        print("[MapVoteUI] no thumbnail for", mapName)
    end

    -- click handling: compute normalized click within voteArea and send to server
    option.Active = true
    option.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if CastVoteRE then
                -- compute normalized position inside voteArea
                local absPos = voteArea.AbsolutePosition
                local absSize = voteArea.AbsoluteSize
                if absSize.X > 0 and absSize.Y > 0 then
                    local relX = (input.Position.X - absPos.X) / absSize.X
                    local relY = (input.Position.Y - absPos.Y) / absSize.Y
                    relX = math.clamp(relX, 0, 1)
                    relY = math.clamp(relY, 0, 1)
                    CastVoteRE:FireServer(mapName, { x = relX, y = relY })
                else
                    CastVoteRE:FireServer(mapName)
                end
            end
        end
    end)

    return option
end

-- Build options from a supplied list of map names
local function buildOptionsFromList(mapList)
    for _, child in ipairs(optionsFrame:GetChildren()) do
        child:Destroy()
    end
    -- layout
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0.02, 0)
    layout.Parent = optionsFrame

    for i, mapName in ipairs(mapList) do
        local opt = createOption(mapName)
        opt.LayoutOrder = i
    end
end

-- Helper to place player icons in a circular layout inside a target frame
local function placeVoterIcons(targetFrame, voters)
    -- clear
    for _, child in ipairs(targetFrame:GetChildren()) do
        child:Destroy()
    end
    if #voters == 0 then return end
    for i, entry in ipairs(voters) do
        local uid = entry.userId
        local pos = entry.pos
        local img = Instance.new("ImageLabel")
        img.Name = "Voter_" .. tostring(uid)
        img.Size = UDim2.new(0.28, 0, 0.28, 0)
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Crop
        img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(uid) .. "&w=48&h=48"
        -- force square aspect ratio so rounding doesn't stretch
        local aspect = Instance.new("UIAspectRatioConstraint")
        aspect.AspectRatio = 1
        aspect.Parent = img
        -- round the image into a circle
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = img
        -- add a yellow border for style
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 215, 0)
        stroke.Thickness = 2
        stroke.Parent = img
        img.Parent = targetFrame
        img.ZIndex = 5
        if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
            img.Position = UDim2.new(pos.x, 0, pos.y, 0)
        else
            -- fallback: place in a row
            local frac = (i-1) / math.max(1, #voters)
            img.Position = UDim2.new(frac * 0.9 + 0.05, 0, 0.5, 0)
        end
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
        -- if server provided explicit options, (re)build UI from that list
        if payload.mapOptions and type(payload.mapOptions) == "table" then
            buildOptionsFromList(payload.mapOptions)
        end
        -- update each option with voters (may be empty)
        for _, opt in ipairs(optionsFrame:GetChildren()) do
            if opt:IsA("Frame") then
                local name = opt.Name:match("^Option_(.+)$")
                local voters = payload.mapVotes[name] or {}
                local votersFrame = opt:FindFirstChild("Voters")
                local votesLabel = opt:FindFirstChild("VotesLabel")
                if votesLabel then
                    votesLabel.Text = tostring(#voters) .. " votes"
                end
                if votersFrame then
                    placeVoterIcons(votersFrame, voters)
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
-- No-op: server provides `mapOptions` during voting; client rebuilds from payload.
