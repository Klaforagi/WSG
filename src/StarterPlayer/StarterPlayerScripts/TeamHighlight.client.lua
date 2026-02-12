local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local HIGHLIGHT_NAME = "WSG_TeamHighlight"

local function addHighlightToModel(model, color)
    if not model or not model:IsA("Model") then return end
    -- avoid adding to local player's character
    if localPlayer.Character and model == localPlayer.Character then return end
    -- remove existing
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Highlight") and child.Name == HIGHLIGHT_NAME then
            child:Destroy()
        end
    end
    local h = Instance.new("Highlight")
    h.Name = HIGHLIGHT_NAME
    h.Adornee = model
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = 0.6
    h.OutlineTransparency = 0.4
    h.Parent = model
end

local function removeHighlightFromModel(model)
    if not model or not model:IsA("Model") then return end
    local existing = model:FindFirstChild(HIGHLIGHT_NAME)
    if existing and existing:IsA("Highlight") then
        existing:Destroy()
    end
end

local function isEnemy(player)
    if not player then return false end
    if not localPlayer.Team or not player.Team then return true end
    return player.Team ~= localPlayer.Team
end

-- Player handling
local function handlePlayerCharacter(player)
    local char = player.Character
    if not char then return end
    -- only highlight enemies
    if isEnemy(player) then
        local color = Color3.fromRGB(255,255,255)
        if player.Team and player.Team.TeamColor then
            color = player.Team.TeamColor.Color
        end
        addHighlightToModel(char, color)
    else
        removeHighlightFromModel(char)
    end
end

local function onPlayerAdded(player)
    -- character spawn
    player.CharacterAdded:Connect(function(char)
        -- wait a heartbeat briefly for parts
        task.wait()
        handlePlayerCharacter(player)
    end)
    -- team changes
    player:GetPropertyChangedSignal("Team"):Connect(function()
        if player.Character then
            handlePlayerCharacter(player)
        end
    end)
    -- if character already present
    if player.Character then
        handlePlayerCharacter(player)
    end
end

-- Dummy handling (models named "Dummy")
local function handleDummyModel(model)
    if not model or not model:IsA("Model") then return end
    -- wait briefly for children (Humanoid) to be parented
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = model:WaitForChild("Humanoid", 3)
    end
    if not humanoid then return end
    -- attach red highlight
    addHighlightToModel(model, Color3.fromRGB(255, 75, 75))
end

local function handleDescendant(desc)
    if desc:IsA("Model") then
        if desc.Name == "Dummy" then
            handleDummyModel(desc)
        else
            -- also check for player character models in workspace (in case they spawn in World)
            local pl = Players:GetPlayerFromCharacter(desc)
            if pl then
                handlePlayerCharacter(pl)
            end
        end
    end
end

-- initial players
for _, pl in ipairs(Players:GetPlayers()) do
    if pl ~= localPlayer then
        onPlayerAdded(pl)
    else
        -- still listen for local player's team changes to update others
        pl:GetPropertyChangedSignal("Team"):Connect(function()
            -- refresh all players highlights when local player team changes
            for _, other in ipairs(Players:GetPlayers()) do
                if other.Character then
                    handlePlayerCharacter(other)
                end
            end
        end)
    end
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- initial scan of workspace for existing dummies and characters
for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Model") then
        if desc.Name == "Dummy" then
            task.defer(handleDummyModel, desc)
        else
            local pl = Players:GetPlayerFromCharacter(desc)
            if pl and pl ~= localPlayer then
                handlePlayerCharacter(pl)
            end
        end
    end
end

-- watch for characters/dummies added to workspace
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") then
        if desc.Name == "Dummy" then
            task.defer(handleDummyModel, desc)
        else
            task.defer(function()
                local pl = Players:GetPlayerFromCharacter(desc)
                if pl then
                    handlePlayerCharacter(pl)
                end
            end)
        end
    end
    -- also catch when a Humanoid is added inside a Dummy model
    if desc:IsA("Humanoid") then
        local parent = desc.Parent
        if parent and parent:IsA("Model") and parent.Name == "Dummy" then
            task.defer(handleDummyModel, parent)
        end
    end
end)

-- clean up highlights when characters removed
Workspace.DescendantRemoving:Connect(function(desc)
    if desc:IsA("Model") then
        removeHighlightFromModel(desc)
    end
end)

return nil
