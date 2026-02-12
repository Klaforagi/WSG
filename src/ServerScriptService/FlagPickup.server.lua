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

-- helper: play a sound from ReplicatedStorage.Sounds.Flag at a given part
local function playFlagSound(soundName, part)
    if not part then return end
    local sounds = ReplicatedStorage:FindFirstChild("Sounds")
    if not sounds then return end
    local flagFolder = sounds:FindFirstChild("Flag")
    if not flagFolder then return end
    local s = flagFolder:FindFirstChild(soundName)
    if s and s:IsA("Sound") then
        local snd = s:Clone()
        snd.Parent = part
        snd:Play()
        Debris:AddItem(snd, 5)
    end
end

-- Configuration: possible flag model names to look for
local FLAG_NAMES = {"BlueFlag", "RedFlag", "Blue Flag", "Red Flag"}

local function getFlagTeamFromName(name)
    local n = tostring(name):lower()
    if string.find(n, "blue") then return "Blue" end
    if string.find(n, "red") then return "Red" end
    return nil
end

local flags = {} -- map team -> {model=Model, pickupPart=BasePart, spawnCFrame=CFrame}
local carrying = {} -- map player -> data {team, modelClone}
local captureDebounce = {}

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
    -- ensure PrimaryPart exists so we can position the model correctly
    if not spawnModel.PrimaryPart then
        for _, d in ipairs(spawnModel:GetDescendants()) do
            if d:IsA("BasePart") then
                spawnModel.PrimaryPart = d
                break
            end
        end
    end
    if info.spawnCFrame and spawnModel.PrimaryPart then
        spawnModel:SetPrimaryPartCFrame(info.spawnCFrame)
    end
    setupFlagModel(spawnModel)
    info.model = spawnModel
    info.dropped = false
end

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
        if not pl.Team then return end

        -- Same team: return the flag to its stand if it's been dropped
        if pl.Team.Name == team then
            if flags[team] and flags[team].dropped then
                flags[team].dropped = false
                -- destroy dropped model (cancels auto-return countdown)
                if model and model.Parent then
                    model:Destroy()
                end
                -- respawn at stand
                respawnFlag(team)
                -- announce with player name
                FlagStatus:FireAllClients("returned", pl.Name, pl.Team.Name, team)
                FlagStatus:FireAllClients("playSound", "Flag_return")
            end
            return
        end

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
            -- announce pickup to all clients (send player team and flag team)
            local playerTeamName = (pl.Team and pl.Team.Name) or nil
            FlagStatus:FireAllClients("pickup", pl.Name, playerTeamName, team)
            -- notify clients to play pickup sound locally
            FlagStatus:FireAllClients("playSound", "Flag_taken")
            -- connect death handler to drop flag
            local function onDied()
                -- only proceed if this player is still recorded as carrying this flag
                if not carrying[pl] or carrying[pl].team ~= team then
                    return
                end
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
                -- disconnect any death connection stored on the carrying record
                if carrying[pl] and carrying[pl].deathConn then
                    pcall(function() carrying[pl].deathConn:Disconnect() end)
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
                    flags[team].dropped = true

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
                            -- apply same carried rotation when returning to the stand
                            local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90)) * CFrame.Angles(math.rad(180), 0, 0)
                            if dropModel.PrimaryPart then
                                dropModel:SetPrimaryPartCFrame(stand.CFrame * CFrame.new(0, 6, 0) * carryRot)
                            else
                                for _, d in ipairs(dropModel:GetDescendants()) do
                                    if d:IsA("BasePart") then
                                        dropModel.PrimaryPart = d
                                        break
                                    end
                                end
                                if dropModel.PrimaryPart then
                                    dropModel:SetPrimaryPartCFrame(stand.CFrame * CFrame.new(0, 6, 0) * carryRot)
                                end
                            end
                            setupFlagModel(dropModel)
                            flags[team].dropped = false
                            -- notify clients to play return sound locally
                            FlagStatus:FireAllClients("playSound", "Flag_return")
                            -- announce return to all clients
                            FlagStatus:FireAllClients("returned", nil, nil, team)
                        else
                            respawnFlag(team)
                            FlagStatus:FireAllClients("playSound", "Flag_return")
                            FlagStatus:FireAllClients("returned", nil, nil, team)
                        end

                        if gui then pcall(function() gui:Destroy() end) end
                    end)
                else
                    -- ensure original eventually respawns if something went wrong
                    task.delay(8, function()
                        respawnFlag(team)
                        FlagStatus:FireAllClients("playSound", "Flag_return")
                        FlagStatus:FireAllClients("returned", nil, nil, team)
                    end)
                end
            end
            local deathConn = humanoid.Died:Connect(onDied)
            -- store death connection so it can be cleaned up if flag is captured
            if carrying[pl] then carrying[pl].deathConn = deathConn end
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

-- BindableEvent for score awards (listened to by GameManager)
local AddScore = game:GetService("ServerScriptService"):FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = game:GetService("ServerScriptService")
end

-- helper: award points to a team
local function awardPoints(teamName, points)
    if not teamName or type(points) ~= "number" then return end
    pcall(function() AddScore:Fire(teamName, points) end)
end

-- Stand capture detection: when a player carrying an enemy flag touches their own stand
local function setupStand(standPart)
    if not standPart or not standPart:IsA("BasePart") then return end
    local standTeam = getFlagTeamFromName(standPart.Name)
    if not standTeam then return end

    standPart.Touched:Connect(function(hit)
        local char = hit and hit:FindFirstAncestorOfClass("Model")
        if not char then return end
        local pl = Players:GetPlayerFromCharacter(char)
        if not pl then return end
        -- must have a humanoid and be alive
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        -- player must belong to the stand's team
        if not pl.Team or pl.Team.Name ~= standTeam then return end
        -- player must be carrying a flag, and it must be the enemy flag (not their own)
        local carry = carrying[pl]
        if not carry then return end
        local flagTeam = carry.team
        if flagTeam == standTeam then return end

        -- debounce per player to avoid multiple triggers
        if captureDebounce[pl] then return end
        captureDebounce[pl] = true
        task.delay(1, function() captureDebounce[pl] = nil end)

        -- award points to the player's team
        local capturingTeamName = pl.Team and pl.Team.Name or nil
        awardPoints(capturingTeamName, 100)

        -- announce capture to clients
        local playerTeamName = capturingTeamName
        FlagStatus:FireAllClients("captured", pl.Name, playerTeamName, flagTeam)
        FlagStatus:FireAllClients("playSound", "Flag_capture")

        -- cleanup carried model and state
        if carry.model then
            pcall(function() carry.model:Destroy() end)
        end
        carrying[pl] = nil
        pcall(function() pl:SetAttribute("CarryingFlag", nil) end)

        -- respawn the captured flag back to its stand after a short delay
        task.delay(5, function()
            respawnFlag(flagTeam)
            FlagStatus:FireAllClients("returned", nil, nil, flagTeam)
            FlagStatus:FireAllClients("playSound", "Flag_return")
        end)
    end)
end

-- wire up existing stands and future additions
for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("BasePart") and (obj.Name == "BlueFlagStand" or obj.Name == "RedFlagStand") then
        setupStand(obj)
    end
end
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("BasePart") and (desc.Name == "BlueFlagStand" or desc.Name == "RedFlagStand") then
        setupStand(desc)
    end
end)

---------------------------------------------------------------------
-- Full flag reset (called by GameManager between matches)
---------------------------------------------------------------------
local function resetAllFlags()
    -- 1) Destroy carried flag models and clear carrying state
    for pl, data in pairs(carrying) do
        if data.model then
            pcall(function() data.model:Destroy() end)
        end
        if data.deathConn then
            pcall(function() data.deathConn:Disconnect() end)
        end
        pcall(function() pl:SetAttribute("CarryingFlag", nil) end)
    end
    carrying = {}
    captureDebounce = {}

    -- 2) Remove any flag models currently in Workspace (dropped or leftover)
    for _, child in ipairs(Workspace:GetChildren()) do
        local team = getFlagTeamFromName(child.Name)
        if team and child:IsA("Model") then
            child:Destroy()
        end
    end

    -- 3) Respawn both flags at their stands
    for _, team in ipairs({"Blue", "Red"}) do
        if flags[team] and flags[team].original then
            flags[team].dropped = false
            respawnFlag(team)
        end
    end

    -- HUD indicators are cleared by the MatchStart event in MatchHUD,
    -- so no need to fire "returned" here (which would show unwanted alerts).
    print("[FlagPickup] All flags reset")
end

-- Listen for ResetFlags from GameManager
local ServerScriptService = game:GetService("ServerScriptService")
local ResetFlags = ServerScriptService:FindFirstChild("ResetFlags")
if not ResetFlags then
    ResetFlags = Instance.new("BindableEvent")
    ResetFlags.Name = "ResetFlags"
    ResetFlags.Parent = ServerScriptService
end
ResetFlags.Event:Connect(resetAllFlags)

return nil
