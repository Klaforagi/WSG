local Workspace = game:GetService("Workspace")
local Map = Workspace:WaitForChild("WSG")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

-- CurrencyService (lazy-loaded for objective coin rewards)
local CurrencyService
local XPModule
pcall(function()
	local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
	if mod and mod:IsA("ModuleScript") then
		CurrencyService = require(mod)
	end
end)

-- Centralized stat service (single source of truth for all stats & events)
local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

local WeaponMasteryService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponMasteryService")
    if mod and mod:IsA("ModuleScript") then
        WeaponMasteryService = require(mod)
    end
end)
local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))
local MOVEMENT_SPEED_STAT = "MovementSpeed"
local FLAG_CARRY_SPEED_MODIFIER_ID = "flag_carry"
local FLAG_CARRY_SPEED_PENALTY = -1

local function applyFlagCarrySlow(player)
    if not player then
        return
    end
    HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, FLAG_CARRY_SPEED_MODIFIER_ID, {
        additive = FLAG_CARRY_SPEED_PENALTY,
        source = "FlagCarry",
    })
end

local function clearFlagCarrySlow(player)
    if not player then
        return
    end
    pcall(function()
        HumanoidStatService:RemoveModifier(player, MOVEMENT_SPEED_STAT, FLAG_CARRY_SPEED_MODIFIER_ID)
    end)
end

local function getEquippedWeaponInstanceId(player)
    local char = player and player.Character
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local instanceId = child:GetAttribute("WeaponInstanceId")
            if type(instanceId) == "string" and instanceId ~= "" then
                return instanceId
            end
        end
    end
    return nil
end

-- RemoteEvent for flag status announcements
local FlagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
if not FlagStatus or not FlagStatus:IsA("RemoteEvent") then
    if FlagStatus then FlagStatus:Destroy() end
    FlagStatus = Instance.new("RemoteEvent")
    FlagStatus.Name = "FlagStatus"
    FlagStatus.Parent = ReplicatedStorage
end

local FlagStatesFolder = ReplicatedStorage:FindFirstChild("FlagStates")
if FlagStatesFolder and not FlagStatesFolder:IsA("Folder") then
    FlagStatesFolder:Destroy()
    FlagStatesFolder = nil
end
if not FlagStatesFolder then
    FlagStatesFolder = Instance.new("Folder")
    FlagStatesFolder.Name = "FlagStates"
    FlagStatesFolder.Parent = ReplicatedStorage
end

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

-- Configuration: exact object names that belong to the flag system.
local FLAG_NAMES = {"BlueFlag", "RedFlag", "Blue Flag", "Red Flag"}
local FLAG_TEAMS_BY_NAME = {
    BlueFlag = "Blue",
    ["Blue Flag"] = "Blue",
    RedFlag = "Red",
    ["Red Flag"] = "Red",
}
local FLAG_STAND_TEAMS_BY_NAME = {
    BlueFlagStand = "Blue",
    RedFlagStand = "Red",
}
local PLAYABLE_TEAMS = {
    Blue = true,
    Red = true,
}
local FLAG_TEAM_ORDER = {"Blue", "Red"}

local function getFlagTeamFromModelName(name)
    return FLAG_TEAMS_BY_NAME[tostring(name)]
end

local function getFlagTeamFromStandName(name)
    return FLAG_STAND_TEAMS_BY_NAME[tostring(name)]
end

local function isPlayableTeamName(teamName)
    return PLAYABLE_TEAMS[tostring(teamName)] == true
end

local function isFlagInteractionState(matchState)
    return matchState == "Game" or matchState == "SuddenDeath"
end

local function areFlagsInteractive()
    return isFlagInteractionState(ServerScriptService:GetAttribute("MatchState"))
end

local flags = {} -- map team -> {model=Model, pickupPart=BasePart, spawnCFrame=CFrame}
local carrying = {} -- map player -> data {team, modelClone}
local captureDebounce = {}
local lastCarrierPos = {} -- player -> Vector3 (tracked for disconnect safety)

local function getFlagStateObject(team)
    local stateObject = FlagStatesFolder:FindFirstChild(team)
    if not stateObject or not stateObject:IsA("Folder") then
        if stateObject then
            stateObject:Destroy()
        end
        stateObject = Instance.new("Folder")
        stateObject.Name = team
        stateObject.Parent = FlagStatesFolder
    end
    return stateObject
end

local function getCarrierForFlag(team)
    for carrierPlayer, carryData in pairs(carrying) do
        if carryData and carryData.team == team then
            return carrierPlayer
        end
    end
    return nil
end

local function getStandRoot(instance)
    local current = instance
    while current and current ~= Workspace do
        if getFlagTeamFromStandName(current.Name) then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function getStandTeamFromInstance(instance)
    local standRoot = getStandRoot(instance)
    if standRoot then
        return getFlagTeamFromStandName(standRoot.Name)
    end
    return nil
end

local function getStandPromptPart(instance)
    local standRoot = getStandRoot(instance) or instance
    if not standRoot then
        return nil
    end

    if standRoot:IsA("Model") then
        local stonePart = standRoot:FindFirstChild("Stone", true)
        if stonePart and stonePart:IsA("BasePart") then
            return stonePart
        end
        if standRoot.PrimaryPart and standRoot.PrimaryPart:IsA("BasePart") then
            return standRoot.PrimaryPart
        end
        return standRoot:FindFirstChildWhichIsA("BasePart", true)
    end

    if standRoot:IsA("BasePart") then
        local parent = standRoot.Parent
        if parent and parent:IsA("Model") then
            local stonePart = parent:FindFirstChild("Stone", true)
            if stonePart and stonePart:IsA("BasePart") then
                return stonePart
            end
        end
        return standRoot
    end

    return nil
end

local function findStandInstance(team)
    for standName, standTeam in pairs(FLAG_STAND_TEAMS_BY_NAME) do
        if standTeam == team then
            local standInstance = Map:FindFirstChild(standName, true) or Workspace:FindFirstChild(standName, true)
            if standInstance and (standInstance:IsA("BasePart") or standInstance:IsA("Model")) then
                return standInstance
            end
        end
    end
    return nil
end

local function findFlagStandPart(team)
    return getStandPromptPart(findStandInstance(team))
end

local function setFlagInstanceAttributes(instance, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
    if not instance then return end
    local carrierTeamName = ""
    if carrierPlayer and carrierPlayer.Team then
        carrierTeamName = carrierPlayer.Team.Name
    end

    instance:SetAttribute("Team", team)
    instance:SetAttribute("AtBase", atBase == true)
    instance:SetAttribute("CarrierUserId", carrierPlayer and carrierPlayer.UserId or 0)
    instance:SetAttribute("CarrierTeam", carrierTeamName)
    instance:SetAttribute("CarrierName", carrierPlayer and carrierPlayer.Name or "")
    instance:SetAttribute("IsCarried", isCarried == true)
    instance:SetAttribute("IsDropped", isDropped == true)
    instance:SetAttribute("ReturnDeadline", tonumber(returnDeadline) or 0)
end

local function syncFlagState(team)
    local flagInfo = flags[team]
    local carrierPlayer = getCarrierForFlag(team)
    local isCarried = carrierPlayer ~= nil
    local isDropped = flagInfo and flagInfo.dropped == true
    local activeModel = flagInfo and (flagInfo.dropModel or flagInfo.model) or nil
    local returnDeadline = (isDropped and flagInfo and tonumber(flagInfo.returnDeadline)) or 0
    local atBase = false

    if flagInfo and flagInfo.model and flagInfo.model.Parent == Map and not isCarried and not isDropped then
        atBase = true
    end

    local stateObject = getFlagStateObject(team)
    setFlagInstanceAttributes(stateObject, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)

    if activeModel then
        setFlagInstanceAttributes(activeModel, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
    end

    local standPart = findFlagStandPart(team)
    if standPart then
        setFlagInstanceAttributes(standPart, team, atBase, isCarried, isDropped, carrierPlayer, returnDeadline)
    end
end

local function syncAllFlagStates()
    for _, team in ipairs(FLAG_TEAM_ORDER) do
        syncFlagState(team)
    end
end

for _, team in ipairs(FLAG_TEAM_ORDER) do
    getFlagStateObject(team)
end

for _, playerInstance in ipairs(Players:GetPlayers()) do
    playerInstance:GetPropertyChangedSignal("Team"):Connect(syncAllFlagStates)
end
Players.PlayerAdded:Connect(function(playerInstance)
    playerInstance:GetPropertyChangedSignal("Team"):Connect(syncAllFlagStates)
    syncAllFlagStates()
end)

-- Global: seconds before a dropped flag auto-returns to base (all drop reasons)
local FLAG_RETURN_TIME = 15
local FLAG_ACTION_PROMPT_NAME = "FlagActionPrompt"
local FLAG_RETURN_DEADLINE_ATTRIBUTE = "ReturnDeadline"
local startDroppedFlagReturnTimer
local setupFlagModel
local wiredStandPromptParts = {}

local function removeScriptsFromModel(model)
    if not model then return end
    for _, d in ipairs(model:GetDescendants()) do
        if d and (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) then
            pcall(function() d:Destroy() end)
        end
    end
end

local function restoreScriptsFromOriginal(original, target)
    if not original or not target then return end
    for _, s in ipairs(original:GetDescendants()) do
        if s and (s:IsA("Script") or s:IsA("LocalScript") or s:IsA("ModuleScript")) then
            -- attempt to parent the cloned script under the same-named child in target if it exists
            local relParent = s.Parent
            local path = {}
            while relParent and relParent ~= original do
                table.insert(path, 1, relParent.Name)
                relParent = relParent.Parent
            end
            local parent = target
            for _, name in ipairs(path) do
                local found = parent:FindFirstChild(name)
                if not found then
                    -- create a placeholder folder to match structure
                    found = Instance.new("Folder")
                    found.Name = name
                    found.Parent = parent
                end
                parent = found
            end
            local clone = s:Clone()
            clone.Parent = parent
        end
    end
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
    -- Velocity-based trail toggle: enable FlagTrail only while the carrier is moving
    local trailPlane = clone:FindFirstChild("Plane", true)
    local flagTrail = trailPlane and trailPlane:FindFirstChild("FlagTrail")
    if flagTrail then
        flagTrail.Enabled = false
        task.spawn(function()
            local moveThreshold = 0.01
            local stopGraceSeconds = 0.15
            local lastMovingAt = 0
            -- Run only while the carried clone is alive in the world
            while clone and clone.Parent do
                local hrp = character and character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local isMoving = hrp.AssemblyLinearVelocity.Magnitude > moveThreshold
                    if isMoving then
                        lastMovingAt = os.clock()
                    end
                    flagTrail.Enabled = isMoving or ((os.clock() - lastMovingAt) <= stopGraceSeconds)
                else
                    flagTrail.Enabled = false
                end
                task.wait(0.03)
            end
            -- Ensure trail is off after the clone is destroyed
            pcall(function() flagTrail.Enabled = false end)
        end)
    end

    return clone
end

local function respawnFlag(team)
    local info = flags[team]
    if not info or not info.original then return end
    -- remove any existing flag models in the world (dropped or misplaced) to avoid duplicates
    for _, child in ipairs(Map:GetChildren()) do
        if child and child:IsA("Model") then
            local childTeam = getFlagTeamFromModelName(child.Name)
            if childTeam == team then
                pcall(function() child:Destroy() end)
            end
        end
    end

    -- clone the canonical original (keep scripts intact for stand behavior)
    local spawnModel = info.original:Clone()
    spawnModel.Parent = Map
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
    info.returnDeadline = 0
    syncFlagState(team)
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

local function awardFlagReturnRewards(player)
    if not player then
        return
    end

    if XPModule and XPModule.AwardXP then
        pcall(function() XPModule.AwardXP(player, "FlagReturn") end)
    end

    if CurrencyService and CurrencyService.AddCoins then
        pcall(function() CurrencyService:AddCoins(player, 5, "objective") end)
    end

    if StatService then
        StatService:RegisterFlagReturn(player)
    end
end

local function returnDroppedFlag(team, player, allowDirectRespawn)
    local flagInfo = flags[team]
    if not flagInfo then
        return false
    end
    if flagInfo.dropped ~= true and allowDirectRespawn ~= true then
        return false
    end

    local dropModel = flagInfo.dropModel
    if dropModel and dropModel.Parent then
        pcall(function() dropModel:Destroy() end)
    end

    flagInfo.dropped = false
    flagInfo.dropModel = nil
    flagInfo.returnDeadline = 0
    respawnFlag(team)

    local playerName = player and player.Name or nil
    local playerTeamName = player and player.Team and player.Team.Name or nil
    FlagStatus:FireAllClients("returned", playerName, playerTeamName, team)
    FlagStatus:FireAllClients("playSound", "Flag_return")

    if player then
        awardFlagReturnRewards(player)
    end

    return true
end

local function pickUpFlag(team, model, player)
    if not player or not model then
        return false
    end

    local character = player.Character
    if not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if carrying[player] then
        return false
    end

    local playerTeamName = player.Team and player.Team.Name or nil

    if model.Parent then
        for _, obj in ipairs(model:GetDescendants()) do
            if obj and obj:IsA("ProximityPrompt") and obj.Name == FLAG_ACTION_PROMPT_NAME then
                pcall(function() obj:Destroy() end)
            end
        end

        model.Parent = ServerStorage
        if flags[team] then
            flags[team].dropped = false
            flags[team].dropModel = nil
            flags[team].model = nil
            flags[team].returnDeadline = 0
        end

        for _, d in ipairs(model:GetDescendants()) do
            if d and (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) then
                pcall(function() d:Destroy() end)
            end
        end

        if not flags[team].pickupTemplate then
            local pickupTemplate = (flags[team].original and flags[team].original:Clone()) or model:Clone()
            for _, d in ipairs(pickupTemplate:GetDescendants()) do
                if d and (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")) then
                    pcall(function() d:Destroy() end)
                end
            end
            pickupTemplate.Parent = ServerStorage
            flags[team].pickupTemplate = pickupTemplate
        end
    end

    local template = (flags[team].pickupTemplate or flags[team].original)
    local carried = makeCarryClone(template, character)
    if not carried then
        return false
    end

    carrying[player] = {team = team, model = carried}
    player:SetAttribute("CarryingFlag", team)
    setFlagInstanceAttributes(carried, team, false, true, false, player, 0)
    syncFlagState(team)
    applyFlagCarrySlow(player)
    FlagStatus:FireAllClients("pickup", player.Name, playerTeamName, team)
    FlagStatus:FireAllClients("playSound", "Flag_taken")

    local function onDied()
        if not carrying[player] or carrying[player].team ~= team then
            return
        end

        local dropModel = nil
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            dropModel = flags[team].original:Clone()
            dropModel.Parent = Map
        end

        if carrying[player] and carrying[player].model then
            pcall(function() carrying[player].model:Destroy() end)
        end
        if carrying[player] and carrying[player].deathConn then
            pcall(function() carrying[player].deathConn:Disconnect() end)
        end
        carrying[player] = nil
        pcall(function() player:SetAttribute("CarryingFlag", nil) end)
        clearFlagCarrySlow(player)
        if not areFlagsInteractive() then
            return
        end

        if hrp and dropModel then
            if dropModel.PrimaryPart then
                local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
                carryRot = carryRot * CFrame.Angles(math.rad(180), 0, 0)
                dropModel:SetPrimaryPartCFrame(hrp.CFrame * CFrame.new(0, 0.5, 0) * carryRot)
            end
            setupFlagModel(dropModel)
            flags[team].dropped = true
            flags[team].dropModel = dropModel
            syncFlagState(team)
            startDroppedFlagReturnTimer(team, dropModel)
        else
            task.delay(FLAG_RETURN_TIME, function()
                if not areFlagsInteractive() then
                    return
                end
                returnDroppedFlag(team, nil, true)
            end)
        end
    end

    local deathConn = humanoid.Died:Connect(onDied)
    if carrying[player] then
        carrying[player].deathConn = deathConn
    end

    return true
end

local function setupFlagActionPrompt(team, model)
    local pickupPart = findPickupPart(model)
    if not pickupPart then
        return
    end

    local prompt = pickupPart:FindFirstChild(FLAG_ACTION_PROMPT_NAME)
    if prompt and not prompt:IsA("ProximityPrompt") then
        prompt:Destroy()
        prompt = nil
    end

    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Parent = pickupPart
    end

    prompt.Name = FLAG_ACTION_PROMPT_NAME
    prompt.ActionText = "Steal"
    prompt.ObjectText = team .. " Flag"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Enabled = true
    prompt.Style = Enum.ProximityPromptStyle.Default
    prompt:SetAttribute("FlagTeam", team)

    prompt.Triggered:Connect(function(player)
        if not player or not areFlagsInteractive() then
            return
        end

        local playerTeamName = player.Team and player.Team.Name or nil
        if not isPlayableTeamName(playerTeamName) then
            return
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return
        end

        if not flags[team] then
            return
        end

        local isDroppedFlag = flags[team].dropped == true and flags[team].dropModel == model
        local isBaseFlag = flags[team].dropped ~= true and flags[team].model == model
        if not isDroppedFlag and not isBaseFlag then
            return
        end

        if playerTeamName == team then
            if isDroppedFlag then
                returnDroppedFlag(team, player)
            end
            return
        end

        pickUpFlag(team, model, player)
    end)
end

startDroppedFlagReturnTimer = function(team, dropModel)
    if not dropModel then
        return
    end

    setupFlagActionPrompt(team, dropModel)
    if flags[team] then
        flags[team].returnDeadline = workspace:GetServerTimeNow() + FLAG_RETURN_TIME
    end
    syncFlagState(team)

    local dropVersion = (flags[team]._dropVersion or 0) + 1
    flags[team]._dropVersion = dropVersion

    print("[FlagPickup] auto-return timer started for", team, "flag (" .. FLAG_RETURN_TIME .. "s)")
    task.spawn(function()
        while true do
            if not flags[team] or not flags[team].dropped or flags[team]._dropVersion ~= dropVersion or flags[team].dropModel ~= dropModel then
                print("[FlagPickup] auto-return timer aborted (flag picked up or returned)")
                return
            end
            if not areFlagsInteractive() then
                return
            end
            local remaining = (flags[team].returnDeadline or 0) - workspace:GetServerTimeNow()
            if remaining <= 0 then
                break
            end
            task.wait(math.min(1, remaining))
        end

        if not flags[team] or not flags[team].dropped or flags[team]._dropVersion ~= dropVersion or flags[team].dropModel ~= dropModel then
            return
        end
        if not areFlagsInteractive() then
            return
        end

        if returnDroppedFlag(team, nil) then
            print("[FlagPickup] auto-return timer completed –", team, "flag returned to base")
        end
    end)
end

    setupFlagModel = function(model)
        if not model or not model:IsA("Model") then return end
        local team = getFlagTeamFromModelName(model.Name)
        if not team then return end
        local pickupPart = findPickupPart(model)
        if not pickupPart then return end
        pickupPart.CanQuery = false
        flags[team] = flags[team] or {}
        flags[team].model = model
        flags[team].pickupPart = pickupPart
        -- attach a team-colored particle trail to the flag's Plane part (follows the model)
        do
            local plane = model:FindFirstChild("Plane", true)
            if plane and plane:IsA("BasePart") then
                local teamColor = Color3.new(1, 1, 1)
                if team == "Blue" then
                    teamColor = Color3.fromRGB(100, 160, 255)
                elseif team == "Red" then
                    teamColor = Color3.fromRGB(220, 80, 80)
                end
                if not plane:FindFirstChild("FlagTrail") then
                    local att0 = Instance.new("Attachment")
                    att0.Name = "FlagTrail_Att0"
                    att0.Position = Vector3.new(-1.4, -0.5, 0.1)
                    att0.Parent = plane

                    local att1 = Instance.new("Attachment")
                    att1.Name = "FlagTrail_Att1"
                    att1.Position = Vector3.new(-1.4, 0.5, 0.1)
                    att1.Parent = plane

                    local trail = Instance.new("Trail")
                    trail.Name = "FlagTrail"
                    trail.Attachment0 = att0
                    trail.Attachment1 = att1
                    trail.Enabled = true
                    trail.Lifetime = 2
                    trail.FaceCamera = false
                    trail.LightInfluence = 0.4
                    trail.MinLength = 0
                    trail.Color = ColorSequence.new(teamColor)
                    trail.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0),
                        NumberSequenceKeypoint.new(0.6, 0.25),
                        NumberSequenceKeypoint.new(1, 1),
                    })
                    trail.WidthScale = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1.6),
                        NumberSequenceKeypoint.new(1, 0.2),
                    })
                    trail.Parent = plane
                    trail.Enabled = false
                end
            end
        end

        if not flags[team].original then
            flags[team].original = model:Clone()
            flags[team].spawnCFrame = (model.PrimaryPart and model:GetPrimaryPartCFrame()) or model:GetModelCFrame()
            flags[team].original.Parent = ServerStorage
            local pickupTemplate = flags[team].original:Clone()
            for _, d in ipairs(pickupTemplate:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                    pcall(function() d:Destroy() end)
                end
            end
            pickupTemplate.Parent = ServerStorage
            flags[team].pickupTemplate = pickupTemplate
        end

        syncFlagState(team)
        setupFlagActionPrompt(team, model)
end

-- initial scan for flags in Workspace.WSG
for _, child in ipairs(Map:GetChildren()) do
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

-- watch for flags added dynamically under the map folder
Map.ChildAdded:Connect(function(child)
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

-- XP integration
pcall(function()
    XPModule = require(game:GetService("ServerScriptService"):WaitForChild("XPServiceModule", 10))
end)

-- BindableEvent: fired when a player returns their team's dropped flag.
-- Other server scripts (e.g. QuestServiceInit) listen to this for quest progress.
local FlagReturned = Instance.new("BindableEvent")
FlagReturned.Name = "FlagReturned"
FlagReturned.Parent = game:GetService("ServerScriptService")

local FlagCaptured = Instance.new("BindableEvent")
FlagCaptured.Name = "FlagCaptured"
FlagCaptured.Parent = game:GetService("ServerScriptService")

-- helper: award points to a team
local function awardPoints(teamName, points)
    if not teamName or type(points) ~= "number" then return end
    pcall(function() AddScore:Fire(teamName, points) end)
end

local function captureFlagAtStand(pl, standTeam)
    if not pl or not areFlagsInteractive() then
        return false
    end

    local char = pl.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end

    local playerTeamName = pl.Team and pl.Team.Name or nil
    if not isPlayableTeamName(playerTeamName) or playerTeamName ~= standTeam then
        return false
    end

    local carry = carrying[pl]
    if not carry then return false end
    local flagTeam = carry.team
    if flagTeam == standTeam then return false end

    local ownFlagInfo = flags[standTeam]
    local ownFlagPresent = ownFlagInfo and ownFlagInfo.model and (ownFlagInfo.dropped ~= true)
    if not ownFlagPresent then
        return false
    end

    if captureDebounce[pl] then return false end
    captureDebounce[pl] = true
    task.delay(5, function() captureDebounce[pl] = nil end)

    if carry.model then
        pcall(function() carry.model:Destroy() end)
    end
    if carry.deathConn then
        pcall(function() carry.deathConn:Disconnect() end)
    end
    carrying[pl] = nil
    pcall(function() pl:SetAttribute("CarryingFlag", nil) end)
    clearFlagCarrySlow(pl)
    syncFlagState(flagTeam)

    awardPoints(playerTeamName, 100)

    if XPModule and XPModule.AwardXP then
        pcall(function() XPModule.AwardXP(pl, "FlagCapture") end)
    end

    if CurrencyService and CurrencyService.AddCoins then
        pcall(function() CurrencyService:AddCoins(pl, 10, "objective") end)
    end

    if StatService then
        StatService:RegisterFlagCapture(pl)
    end

    FlagStatus:FireAllClients("captured", pl.Name, playerTeamName, flagTeam)
    FlagStatus:FireAllClients("playSound", "Flag_capture")

    task.delay(5, function()
        respawnFlag(flagTeam)
        FlagStatus:FireAllClients("returned", nil, nil, flagTeam)
        FlagStatus:FireAllClients("playSound", "Flag_return")
    end)

    return true
end

local function setupStand(standInstance)
    local standPart = getStandPromptPart(standInstance)
    local standTeam = getStandTeamFromInstance(standInstance)
    if not standPart or not standTeam then return end
    if wiredStandPromptParts[standPart] then return end
    wiredStandPromptParts[standPart] = true

    local prompt = standPart:FindFirstChild("FlagCapturePrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        prompt:Destroy()
    end

    standPart.Touched:Connect(function(hit)
        local character = hit and hit:FindFirstAncestorOfClass("Model")
        if not character then
            return
        end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then
            return
        end

        captureFlagAtStand(player, standTeam)
    end)
end

-- wire up existing stands and future additions
for _, obj in ipairs(Workspace:GetDescendants()) do
    if (obj:IsA("BasePart") or obj:IsA("Model")) and (obj.Name == "BlueFlagStand" or obj.Name == "RedFlagStand") then
        setupStand(obj)
    end
end
Workspace.DescendantAdded:Connect(function(desc)
    if (desc:IsA("BasePart") or desc:IsA("Model")) and (desc.Name == "BlueFlagStand" or desc.Name == "RedFlagStand") then
        setupStand(desc)
    end
end)

---------------------------------------------------------------------
-- Full flag reset (called by GameManager between matches)
---------------------------------------------------------------------
local function destroyAllFlags()
    -- 1) Destroy carried flag models and clear carrying state
    for pl, data in pairs(carrying) do
        if data.model then
            pcall(function() data.model:Destroy() end)
        end
        if data.deathConn then
            pcall(function() data.deathConn:Disconnect() end)
        end
        pcall(function() pl:SetAttribute("CarryingFlag", nil) end)
        clearFlagCarrySlow(pl)
    end
    carrying = {}
    captureDebounce = {}
    -- clear tracked positions from disconnect safety system
    for pl, _ in pairs(lastCarrierPos) do
        lastCarrierPos[pl] = nil
    end

    -- 2) Remove any flag models currently in Map (dropped or leftover)
    for _, child in ipairs(Map:GetChildren()) do
        local team = getFlagTeamFromModelName(child.Name)
        if team and child:IsA("Model") then
            child:Destroy()
        end
    end

    for _, team in ipairs({"Blue", "Red"}) do
        if flags[team] then
            flags[team].dropped = false
            flags[team].dropModel = nil
            flags[team].model = nil
            flags[team]._dropVersion = (flags[team]._dropVersion or 0) + 1
        end
    end
    syncAllFlagStates()

    print("[FlagPickup] All flags destroyed")
end

local function spawnAllFlags()
    destroyAllFlags()

    -- 3) Respawn both flags at their stands
    for _, team in ipairs({"Blue", "Red"}) do
        if flags[team] and flags[team].original then
            flags[team].dropped = false
            flags[team].dropModel = nil
            respawnFlag(team)
        end
    end

    -- HUD indicators are cleared by the MatchStart event in MatchHUD,
    -- so no need to fire "returned" here (which would show unwanted alerts).
    print("[FlagPickup] All flags spawned")
end

local function resetAllFlags(mode)
    if mode == "destroy" then
        destroyAllFlags()
    else
        spawnAllFlags()
    end
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

---------------------------------------------------------------------
-- DISCONNECT / STALE-CARRIER SAFETY
-- If a player leaves while carrying a flag, force-drop it so the flag
-- never vanishes with them.
---------------------------------------------------------------------

-- Force-drop a flag for a given player.  Works for disconnects, stale
-- carrier cleanup, or any situation where the carrier is no longer valid.
-- `lastPos` is an optional fallback Vector3 if HRP is already gone.
local function forceDropFlag(pl, lastPos)
    local carry = carrying[pl]
    if not carry then return end
    local team = carry.team

    -- Clean up carried model & connections immediately
    if carry.model then
        pcall(function() carry.model:Destroy() end)
    end
    if carry.deathConn then
        pcall(function() carry.deathConn:Disconnect() end)
    end
    carrying[pl] = nil
    pcall(function() pl:SetAttribute("CarryingFlag", nil) end)
    clearFlagCarrySlow(pl)

    if not areFlagsInteractive() then
        syncFlagState(team)
        return
    end

    -- Determine drop position
    local dropCFrame
    local char = pl.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        dropCFrame = hrp.CFrame * CFrame.new(0, 0.5, 0)
    elseif lastPos then
        dropCFrame = CFrame.new(lastPos + Vector3.new(0, 0.5, 0))
    end

    -- If we have a valid position, drop the flag there with a return timer.
    -- Otherwise, return it directly to base.
    if dropCFrame and flags[team] and flags[team].original then
        print("[FlagPickup] force-dropping", team, "flag for", pl.Name, "at", tostring(dropCFrame.Position))

        local dropModel = flags[team].original:Clone()
        dropModel.Parent = Map

        if not dropModel.PrimaryPart then
            for _, d in ipairs(dropModel:GetDescendants()) do
                if d:IsA("BasePart") then dropModel.PrimaryPart = d; break end
            end
        end

        if dropModel.PrimaryPart then
            local carryRot = CFrame.Angles(math.rad(180), math.rad(180), math.rad(90))
                           * CFrame.Angles(math.rad(180), 0, 0)
            dropModel:SetPrimaryPartCFrame(dropCFrame * carryRot)
        end

        setupFlagModel(dropModel)
        flags[team].dropped = true
        flags[team].dropModel = dropModel
        syncFlagState(team)
        startDroppedFlagReturnTimer(team, dropModel)
    else
        -- No valid position: return directly to base
        print("[FlagPickup] no valid drop position for", team, "flag – returning to base")
        returnDroppedFlag(team, nil, true)
    end
end

-- Track last-known server position for each player carrying a flag,
-- so we have a fallback if HRP is gone by the time PlayerRemoving fires.
RunService.Heartbeat:Connect(function()
    for pl, data in pairs(carrying) do
        local char = pl.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            lastCarrierPos[pl] = hrp.Position
        end
    end
end)

-- Handle player disconnect: force-drop any carried flag
Players.PlayerRemoving:Connect(function(pl)
    if not carrying[pl] then
        lastCarrierPos[pl] = nil
        captureDebounce[pl] = nil
        return
    end
    print("[FlagPickup]", pl.Name, "disconnected while carrying flag")
    forceDropFlag(pl, lastCarrierPos[pl])
    lastCarrierPos[pl] = nil
    captureDebounce[pl] = nil
end)

-- Periodic stale-carrier check: every 5 seconds, verify all carriers are
-- still valid players with live characters. Catches edge cases where
-- PlayerRemoving or Died events were missed.
task.spawn(function()
    while true do
        task.wait(5)
        for pl, data in pairs(carrying) do
            -- Player object is invalid or no longer in game
            local valid = pl and pl.Parent ~= nil
            if valid then
                local char = pl.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                valid = char ~= nil and hum ~= nil and hum.Health > 0
            end
            if not valid then
                warn("[FlagPickup] stale carrier detected:", tostring(pl), "– force dropping")
                forceDropFlag(pl, lastCarrierPos[pl])
                lastCarrierPos[pl] = nil
            end
        end
    end
end)

return nil
