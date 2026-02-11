local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- RemoteEvent for flag status announcements
local FlagStatus = Instance.new("RemoteEvent")
FlagStatus.Name = "FlagStatus"
FlagStatus.Parent = ReplicatedStorage

-- Configuration: possible flag model names to look for
local FLAG_NAMES = {"BlueFlag", "RedFlag", "Blue Flag", "Red Flag"}

local function getFlagTeamFromName(name)
    local n = tostring(name):lower()
    if string.find(n, "blue") then return "Blue" end
    if string.find(n, "red") then return "Red" end
    return nil
end

local function makeCarryClone(originalModel, character)
    if not originalModel or not character then return nil end
    local clone = originalModel:Clone()
    clone.Name = originalModel.Name .. "_Carried"
    -- ensure primary part exists
    if not clone.PrimaryPart then
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                clone.PrimaryPart = d
                break
            end
        end
    end

    clone.Parent = character
    -- position & weld all parts to the player's back part (UpperTorso / Torso), fall back to HumanoidRootPart
    local attachPart = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
    if attachPart then
        if clone.PrimaryPart then
            -- scale the model down to half size (parts + special meshes)
            local primary = clone.PrimaryPart
            -- scale special meshes if present
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("SpecialMesh") then
                    d.Scale = d.Scale * 0.5
                end
            end
            -- scale BaseParts and reposition them relative to the primary
            for _, p in ipairs(clone:GetDescendants()) do
                if p:IsA("BasePart") then
                    if p == primary then
                        p.Size = p.Size * 0.5
                    else
                        local rel = primary.CFrame:ToObjectSpace(p.CFrame)
                        local rx, ry, rz = rel:ToEulerAnglesXYZ()
                        local newPos = rel.Position * 0.5
                        p.Size = p.Size * 0.5
                        p.CFrame = primary.CFrame * CFrame.new(newPos) * CFrame.Angles(rx, ry, rz)
                    end
                end
            end

            -- place the flag slightly above and behind the player,
            -- rotate to face backward and flip so it's upright; then rotate 180° around X instead
            -- move flag further back slightly and up by 3 studs (Y +3, Z +3.0)
            local offset = CFrame.new(0, 1.8, 0.7) * CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
            -- apply additional 180° rotation around X axis to correct facing
            offset = offset * CFrame.Angles(math.rad(180), 0, 0)
            clone:SetPrimaryPartCFrame(attachPart.CFrame * offset)
        end
        for _, v in ipairs(clone:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
                v.Anchored = false
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = v
                weld.Part1 = attachPart
                weld.Parent = v
            end
        end
        -- remove pickup-like parts from the carried clone to avoid touch/physics issues
        for _, name in ipairs({"PickupPart", "Pickup", "Flag", "Base"}) do
            local p = clone:FindFirstChild(name, true)
            if p and p:IsA("BasePart") and p ~= clone.PrimaryPart then
                p:Destroy()
            end
        end
    end
    return clone
end

local function respawnFlag(team)
    local info = flags[team]
    if not info or not info.original then return end
    local spawnModel = info.original:Clone()
    spawnModel.Parent = Workspace
    if spawnModel.PrimaryPart and info.spawnCFrame then
        spawnModel:SetPrimaryPartCFrame(info.spawnCFrame)
    end
    setupFlagModel(spawnModel)
    info.model = spawnModel
end

local flags = {} -- map team -> {model=Model, pickupPart=BasePart, spawnCFrame=CFrame}
local carrying = {} -- map player -> data {team, modelClone}

local function findPickupPart(model)
    if not model or not model:IsA("Model") then return nil end
    -- prefer a child named "PickupPart" then "Pickup", "Flag", or "Base", else first BasePart
    for _, name in ipairs({"PickupPart", "Pickup", "Flag", "Base"}) do
        local p = model:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

function setupFlagModel(model)
    if not model or not model:IsA("Model") then return end
    local team = getFlagTeamFromName(model.Name)
    if not team then return end
    local pickupPart = findPickupPart(model)
    if not pickupPart then return end
    flags[team] = flags[team] or {}
    flags[team].model = model
    flags[team].pickupPart = pickupPart
    -- store original in ServerStorage for cloning on respawn
    if not flags[team].original then
        flags[team].original = model:Clone()
        flags[team].spawnCFrame = (model.PrimaryPart and model:GetPrimaryPartCFrame()) or model:GetModelCFrame()
        flags[team].original.Parent = ServerStorage
    end

    local conn
    conn = pickupPart.Touched:Connect(function(part)
        local char = part and part:FindFirstAncestorOfClass("Model")
        if not char then return end
        local pl = Players:GetPlayerFromCharacter(char)
        if not pl then return end
        -- ensure character has humanoid
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        -- player's team must be opposite of flag team
        if not pl.Team or pl.Team.Name == team then return end
        -- cannot pick up if already carrying
        if carrying[pl] then return end

        -- pickup: move original to ServerStorage (remove from workspace)
        if model.Parent then
            model.Parent = ServerStorage
        end

        -- attach clone to character
        local carried = makeCarryClone(flags[team].original, char)
        if carried then
            carrying[pl] = {team = team, model = carried}
            pl:SetAttribute("CarryingFlag", team)
            -- announce pickup to all clients
            FlagStatus:FireAllClients("pickup", pl.Name, team)
            -- connect death handler to drop flag
            local function onDied()
                -- drop at HRP position
                local dropModel = nil
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    dropModel = flags[team].original:Clone()
                    dropModel.Parent = Workspace
                end
                -- cleanup carried model and state
                if carrying[pl] and carrying[pl].model then
                    pcall(function() carrying[pl].model:Destroy() end)
                end
                carrying[pl] = nil
                pcall(function() pl:SetAttribute("CarryingFlag", nil) end)
                -- if we created a dropped model, apply rotation and schedule return to base after 8s
                if hrp and dropModel then
                    if dropModel.PrimaryPart then
                        local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
                        carryRot = carryRot * CFrame.Angles(math.rad(180), 0, 0)
                        dropModel:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0.5, 0) * carryRot)
                    end
                    setupFlagModel(dropModel)

                    -- create a visible countdown above the dropped flag and return it to the stand
                    -- only if nobody picks it up within 8 seconds
                    -- ensure a PrimaryPart exists for GUI attachment
                    if not dropModel.PrimaryPart then
                        for _, d in ipairs(dropModel:GetDescendants()) do
                            if d:IsA("BasePart") then
                                dropModel.PrimaryPart = d
                                break
                            end
                        end
                    end

                    local gui
                    local label
                    if dropModel.PrimaryPart then
                        gui = Instance.new("BillboardGui")
                        gui.Name = "ReturnCountdown"
                        gui.Adornee = dropModel.PrimaryPart
                        gui.AlwaysOnTop = false
                        gui.Size = UDim2.new(6, 0, 3, 0)
                        gui.StudsOffset = Vector3.new(0, 10, 0)
                        gui.MaxDistance = 200
                        -- choose color by team
                        local teamColor = Color3.new(1, 1, 1)
                        if team == "Blue" then
                            teamColor = Color3.fromRGB(0, 162, 255)
                        elseif team == "Red" then
                            teamColor = Color3.fromRGB(255, 75, 75)
                        end
                        label = Instance.new("TextLabel")
                        label.Size = UDim2.new(1, 0, 1, 0)
                        label.BackgroundTransparency = 1
                        label.TextColor3 = teamColor
                        label.TextStrokeTransparency = 0
                        label.TextStrokeColor3 = Color3.new(0, 0, 0)
                        label.Font = Enum.Font.SourceSansBold
                        label.TextScaled = true
                        label.Parent = gui
                        gui.Parent = dropModel.PrimaryPart
                    end

                    task.spawn(function()
                        for i = 8, 1, -1 do
                            if not dropModel or dropModel.Parent ~= Workspace then
                                if gui then pcall(function() gui:Destroy() end) end
                                return
                            end
                            if label then
                                label.Text = tostring(i)
                            end
                            task.wait(1)
                        end

                        if not dropModel or dropModel.Parent ~= Workspace then
                            if gui then pcall(function() gui:Destroy() end) end
                            return
                        end

                        local standName = team .. "FlagStand"
                        local stand = Workspace:FindFirstChild(standName, true)
                        if stand and stand:IsA("BasePart") then
                            if dropModel.PrimaryPart then
                                dropModel:SetPrimaryPartCFrame(stand.CFrame)
                            else
                                for _, d in ipairs(dropModel:GetDescendants()) do
                                    if d:IsA("BasePart") then
                                        dropModel.PrimaryPart = d
                                        break
                                    end
                                end
                                if dropModel.PrimaryPart then
                                    dropModel:SetPrimaryPartCFrame(stand.CFrame)
                                end
                            end
                            setupFlagModel(dropModel)
                            -- announce return to all clients
                            FlagStatus:FireAllClients("returned", nil, team)
                        else
                            respawnFlag(team)
                            FlagStatus:FireAllClients("returned", nil, team)
                        end

                        if gui then pcall(function() gui:Destroy() end) end
                    end)
                else
                    -- ensure original eventually respawns if something went wrong
                    task.delay(8, function()
                        respawnFlag(team)
                    end)
                end
            end
            humanoid.Died:Connect(onDied)
        end
    end)
end

-- initial scan for flags in Workspace
for _, child in ipairs(Workspace:GetChildren()) do
    for _, name in ipairs(FLAG_NAMES) do
        if child.Name == name then
            -- ensure model has PrimaryPart set if possible
            if child:IsA("Model") and not child.PrimaryPart then
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("BasePart") then
                        child.PrimaryPart = d
                        break
                    end
                end
            end
            setupFlagModel(child)
        end
    end
end

-- watch for flags added dynamically
Workspace.ChildAdded:Connect(function(child)
    for _, name in ipairs(FLAG_NAMES) do
        if child.Name == name then
            setupFlagModel(child)
            break
        end
    end
end)

return nil
