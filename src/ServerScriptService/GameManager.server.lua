--[[
    GameManager.server.lua
    Authoritative game-state machine.
    States: WaitingForPlayers → Game → (SuddenDeath) → EndGame → Game …
    
    Other server scripts award points by firing BindableEvent "AddScore"
    in ServerScriptService with args (teamName: string, delta: number).
    This avoids all require() / ModuleScript timing issues.
]]

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local MATCH_DURATION   = 5 * 60   -- round duration in seconds (5 minutes)
local END_SCREEN_TIME  = 10       -- seconds the winner screen (endgame) stays up
local MATCH_RESULTS_DURATION = 15 -- seconds for match results display (intermission)
local VOTING_DURATION = 15       -- seconds for map voting
local LOADING_DURATION = 2        -- seconds for loading/map spawn settling
local PREMATCH_DURATION = 15      -- seconds for prematch team selection
local BARRIER_FADE_TIME = 1       -- seconds to fade barriers before they are destroyed
local INTERMISSION_DURATION = 60  -- seconds players wait in the lobby between rounds
local MIN_PLAYERS      = 0        -- set >0 if you want a lobby phase

---------------------------------------------------------------------
-- Remote events  (server → client)
---------------------------------------------------------------------
local function ensureRemote(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end

local ScoreUpdate = ensureRemote("ScoreUpdate")
local MatchStart  = ensureRemote("MatchStart")
local MatchEnd    = ensureRemote("MatchEnd")
local IntermissionStart = ensureRemote("IntermissionStart")
local MatchResults = ensureRemote("MatchResults")
local AdjustMatchTime = ensureRemote("AdjustMatchTime")

-- MVP display: a dancing avatar of the last match MVP, standing on Workspace.MVPblock.
-- Built when MatchResults fire; the previous rig is destroyed only once a replacement is ready.
local MVP_MODEL_NAME = "MVP_Avatar"
local MVP_SCALE = 1.5
local MVP_GOLD = Color3.fromRGB(255, 214, 70)
local MVP_GOLD_LIGHT = Color3.fromRGB(255, 240, 170)
local MVP_GOLD_WARM = Color3.fromRGB(255, 196, 48)
local MVP_WHITE = Color3.fromRGB(245, 245, 252)
local MVP_NAVY = Color3.fromRGB(10, 12, 26)
local MVP_LIGHT_KNIGHTS = Color3.fromRGB(0, 110, 254)
local MVP_LIGHT_BARBARIANS = Color3.fromRGB(254, 88, 88)
local currentMVP = {
    model = nil,
    track = nil,
    userId = nil,
}

local EmoteConfig
pcall(function()
    local sideui = ReplicatedStorage:WaitForChild("SideUI", 10)
    if sideui then
        local mod = sideui:WaitForChild("EmoteConfig", 5)
        if mod then
            EmoteConfig = require(mod)
        end
    end
end)

local CombatUtils
pcall(function()
    CombatUtils = require(ServerScriptService:WaitForChild("CombatUtils", 5))
end)

local function findMVPSpawnPart()
    local direct = workspace:FindFirstChild("MVPblock")
    if direct and direct:IsA("BasePart") then
        return direct
    end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and string.lower(obj.Name) == "mvpblock" then
            return obj
        end
    end
    return nil
end

local function findMVPBlockRoot()
    local direct = workspace:FindFirstChild("MVPblock")
    if direct then
        return direct
    end
    return findMVPSpawnPart()
end

local function colorForMVPTeam(teamKey)
    if teamKey == "Red" then
        return MVP_LIGHT_BARBARIANS
    end
    return MVP_LIGHT_KNIGHTS
end

local function applyMVPBlockLights(teamKey)
    local root = findMVPBlockRoot()
    if not root then
        return
    end

    local color = colorForMVPTeam(teamKey)
    local function paint(inst)
        if inst.Name ~= "Light" then
            return
        end
        if inst:IsA("BasePart") then
            inst.Color = color
        elseif inst:IsA("Light") then
            inst.Color = color
        end
    end

    paint(root)
    for _, desc in ipairs(root:GetDescendants()) do
        paint(desc)
    end
end

local function stopAndDestroyCurrentMVP()
    if currentMVP.track then
        pcall(function() currentMVP.track:Stop(0.15) end)
        pcall(function() currentMVP.track:Destroy() end)
        currentMVP.track = nil
    end
    if currentMVP.model then
        pcall(function() currentMVP.model:Destroy() end)
        currentMVP.model = nil
    end
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == MVP_MODEL_NAME and child:IsA("Model") then
            pcall(function() child:Destroy() end)
        end
    end
    currentMVP.userId = nil
end

-- Dances live in EmoteConfig (animation ids). AssetCodes only has empty icon slots.
-- Treat Looped ~= false as a dance so entries that omit Looped (rat dance, floss, etc.) are included.
local function pickMVPDanceDef()
    if not (EmoteConfig and type(EmoteConfig.GetAll) == "function") then
        return nil
    end

    local candidates = {}
    for _, emote in ipairs(EmoteConfig.GetAll() or {}) do
        if type(emote) == "table"
            and type(emote.AnimationId) == "string"
            and emote.AnimationId ~= ""
            and emote.Looped ~= false then
            table.insert(candidates, emote)
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(1, #candidates)]
end

-- Prefer the live in-game look (skins). Fall back to the Roblox avatar, then a blank description.
local function resolveMVPDescription(userId)
    local player = Players:GetPlayerByUserId(userId)
    if player and player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local ok, desc = pcall(function()
                return humanoid:GetAppliedDescription()
            end)
            if ok and desc then
                return desc
            end
        end
    end

    local ok2, desc2 = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if ok2 and desc2 then
        return desc2
    end

    warn("[GameManager] Could not resolve HumanoidDescription for", userId, "-", tostring(desc2))
    return Instance.new("HumanoidDescription")
end

local function scaleMVPRig(rig, humanoid)
    if type(rig.ScaleTo) == "function" then
        local ok = pcall(function()
            rig:ScaleTo(MVP_SCALE)
        end)
        if ok then
            return
        end
    end

    -- Fallback for engines without Model:ScaleTo — 1.5x the current body NumberValues.
    pcall(function()
        humanoid.AutomaticScalingEnabled = true
    end)
    for _, name in ipairs({ "BodyWidthScale", "BodyHeightScale", "BodyDepthScale", "HeadScale" }) do
        local nv = humanoid:FindFirstChild(name)
        if not (nv and nv:IsA("NumberValue")) then
            nv = Instance.new("NumberValue")
            nv.Name = name
            nv.Value = 1
            nv.Parent = humanoid
        end
        nv.Value = (tonumber(nv.Value) or 1) * MVP_SCALE
    end
    task.wait()
end

local function placeMVPRig(model, spawnPart)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    local lift
    if humanoid and root and root:IsA("BasePart") then
        lift = (spawnPart.Size.Y * 0.5) + humanoid.HipHeight + (root.Size.Y * 0.5)
    else
        local _, size = model:GetBoundingBox()
        lift = (spawnPart.Size.Y * 0.5) + (size.Y * 0.5)
    end
    model:PivotTo(spawnPart.CFrame * CFrame.new(0, lift, 0))
end

local function resolveMVPDisplayName(userId)
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local displayName = player.DisplayName
        if type(displayName) == "string" and displayName ~= "" then
            return displayName
        end
        return player.Name
    end

    local ok, username = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    if ok and type(username) == "string" and username ~= "" then
        return username
    end
    return "Unknown"
end

local function attachMVPLabel(rig, userId)
    local head = rig:FindFirstChild("Head")
    local adornee = (head and head:IsA("BasePart") and head) or rig:FindFirstChild("HumanoidRootPart")
    if not (adornee and adornee:IsA("BasePart")) then
        return
    end

    local headLift = 0.9
    if head and head:IsA("BasePart") then
        headLift = (head.Size.Y * 0.5) + 0.85
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "MVPLabel"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 220
    billboard.Size = UDim2.new(6.2, 0, 1.85, 0)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, headLift, 0)
    billboard.ResetOnSpawn = false
    billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    billboard.Parent = rig

    local plate = Instance.new("Frame")
    plate.Name = "Plate"
    plate.BackgroundColor3 = MVP_NAVY
    plate.BackgroundTransparency = 0.28
    plate.BorderSizePixel = 0
    plate.Size = UDim2.fromScale(1, 1)
    plate.Parent = billboard

    local plateCorner = Instance.new("UICorner")
    plateCorner.CornerRadius = UDim.new(0, 10)
    plateCorner.Parent = plate

    local plateStroke = Instance.new("UIStroke")
    plateStroke.Color = MVP_GOLD
    plateStroke.Thickness = 1.6
    plateStroke.Transparency = 0.12
    plateStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    plateStroke.Parent = plate

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0.06, 0)
    pad.PaddingRight = UDim.new(0.06, 0)
    pad.PaddingTop = UDim.new(0.08, 0)
    pad.PaddingBottom = UDim.new(0.08, 0)
    pad.Parent = plate

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.BorderSizePixel = 0
    title.Size = UDim2.new(1, 0, 0.55, 0)
    title.Position = UDim2.fromScale(0, 0)
    title.Font = Enum.Font.GothamBlack
    title.Text = "◆  MVP  ◆"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextScaled = true
    title.TextStrokeColor3 = Color3.fromRGB(48, 32, 4)
    title.TextStrokeTransparency = 0.2
    title.Parent = plate

    local titleSize = Instance.new("UITextSizeConstraint")
    titleSize.MinTextSize = 16
    titleSize.MaxTextSize = 32
    titleSize.Parent = title

    local shine = Instance.new("UIGradient")
    shine.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, MVP_GOLD_LIGHT),
        ColorSequenceKeypoint.new(0.45, MVP_GOLD_WARM),
        ColorSequenceKeypoint.new(1, MVP_GOLD_LIGHT),
    })
    shine.Rotation = 0
    shine.Parent = title

    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.AnchorPoint = Vector2.new(0.5, 0.5)
    divider.BackgroundColor3 = MVP_GOLD
    divider.BackgroundTransparency = 0.35
    divider.BorderSizePixel = 0
    divider.Position = UDim2.new(0.5, 0, 0.58, 0)
    divider.Size = UDim2.new(0.42, 0, 0, 2)
    divider.Parent = plate

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "PlayerName"
    nameLabel.BackgroundTransparency = 1
    nameLabel.BorderSizePixel = 0
    nameLabel.Size = UDim2.new(1, 0, 0.36, 0)
    nameLabel.Position = UDim2.fromScale(0, 0.64)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = resolveMVPDisplayName(userId)
    nameLabel.TextColor3 = MVP_WHITE
    nameLabel.TextScaled = true
    nameLabel.TextStrokeColor3 = MVP_NAVY
    nameLabel.TextStrokeTransparency = 0.25
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = plate

    local nameSize = Instance.new("UITextSizeConstraint")
    nameSize.MinTextSize = 12
    nameSize.MaxTextSize = 20
    nameSize.Parent = nameLabel
end

local function playMVPDance(rig, humanoid)
    local emoteDef = pickMVPDanceDef()
    if not emoteDef then
        warn("[GameManager] No dance animations found in EmoteConfig for MVP rig")
        return nil
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.Name = "MVPDance"
    animation.AnimationId = emoteDef.AnimationId
    animation.Parent = rig

    local ok, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not ok or not track then
        warn("[GameManager] Failed to load MVP dance", emoteDef.Id, track)
        return nil
    end

    track.Priority = Enum.AnimationPriority.Action
    track.Looped = emoteDef.Looped ~= false
    pcall(function()
        track:Play(0.25)
    end)
    return track
end

local function spawnMVPAvatar(userId, preparedDescription, teamKey)
    if type(userId) ~= "number" or userId <= 0 then
        return
    end

    local spawnPart = findMVPSpawnPart()
    if not spawnPart then
        warn("[GameManager] MVP spawn part not found in workspace (expected a BasePart named 'MVPblock')")
        return
    end

    local desc = preparedDescription or resolveMVPDescription(userId)
    local ok, rigOrErr = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not ok or typeof(rigOrErr) ~= "Instance" then
        warn("[GameManager] Failed to create MVP rig for user", userId, rigOrErr)
        return
    end

    local rig = rigOrErr
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        pcall(function() rig:Destroy() end)
        warn("[GameManager] MVP rig missing Humanoid for user", userId)
        return
    end

    -- Replacement is ready: only now tear down the previous MVP.
    stopAndDestroyCurrentMVP()

    rig.Name = MVP_MODEL_NAME
    rig.Parent = workspace

    if CombatUtils and type(CombatUtils.tagPodiumModel) == "function" then
        pcall(function() CombatUtils.tagPodiumModel(rig) end)
    end

    for _, part in ipairs(rig:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Massless = true
        end
    end

    local root = rig:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        root.Anchored = true
    end

    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.NameDisplayDistance = 0
    humanoid.HealthDisplayDistance = 0
    humanoid.AutoRotate = false
    humanoid.BreakJointsOnDeath = false
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    pcall(function()
        scaleMVPRig(rig, humanoid)
    end)
    pcall(function()
        placeMVPRig(rig, spawnPart)
    end)
    pcall(function()
        attachMVPLabel(rig, userId)
    end)

    currentMVP.model = rig
    currentMVP.userId = userId
    currentMVP.track = playMVPDance(rig, humanoid)
    applyMVPBlockLights(teamKey)
    print(string.format("[GameManager] Spawned MVP avatar for userId=%s team=%s", tostring(userId), tostring(teamKey)))
end

-- Centralized stat service (single source of truth for all stats & events)
local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

-- Event scheduler (timed match events)
local EventScheduler
pcall(function()
    EventScheduler = require(ServerScriptService:WaitForChild("EventScheduler", 10))
end)

---------------------------------------------------------------------
-- Bindable event  (server script → GameManager)
---------------------------------------------------------------------
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

-- BindableEvents for other server scripts (e.g. WeeklyQuestServiceInit)
local MatchStartedBE = ServerScriptService:FindFirstChild("MatchStarted")
if not MatchStartedBE then
    MatchStartedBE = Instance.new("BindableEvent")
    MatchStartedBE.Name = "MatchStarted"
    MatchStartedBE.Parent = ServerScriptService
end

local MatchEndedBE = ServerScriptService:FindFirstChild("MatchEnded")
if not MatchEndedBE then
    MatchEndedBE = Instance.new("BindableEvent")
    MatchEndedBE.Name = "MatchEnded"
    MatchEndedBE.Parent = ServerScriptService
end

---------------------------------------------------------------------
-- State  (must be declared BEFORE GetMatchState closure captures them)
---------------------------------------------------------------------
local State = "Idle"   -- Idle | Game | SuddenDeath | EndGame | Intermission
local teamScores = { Blue = 0, Red = 0 }
local matchStartTick = nil
local intermissionStartTick = nil
local phaseGen = 0
local phaseStartTick = nil
local lastMatchResultsPayload = nil

local STATE_DURATION = {
    Intermission = MATCH_RESULTS_DURATION,
    Voting = VOTING_DURATION,
    Loading = LOADING_DURATION,
    Prematch = PREMATCH_DURATION,
    Game = MATCH_DURATION,
    EndGame = END_SCREEN_TIME,
}

local function setMatchState(newState)
    phaseGen = phaseGen + 1
    State = newState
    phaseStartTick = workspace:GetServerTimeNow()
    ServerScriptService:SetAttribute("MatchState", State)
    -- also expose the phase start tick as an attribute for diagnostics
    ServerScriptService:SetAttribute("MatchStateStartedAt", phaseStartTick)
    print(string.format("[GameManager] setMatchState -> %s (gen=%s) at %s", tostring(newState), tostring(phaseGen), tostring(phaseStartTick)))
    return phaseGen
end

-- Expose match state as an attribute so other server scripts can poll it
-- without race conditions on BindableEvent subscriptions.
ServerScriptService:SetAttribute("MatchState", State)

---------------------------------------------------------------------
-- RemoteFunction for clients to request current match state
---------------------------------------------------------------------
local function ensureFunction(name)
    local fn = ReplicatedStorage:FindFirstChild(name)
    if not fn then
        fn = Instance.new("RemoteFunction")
        fn.Name = name
        fn.Parent = ReplicatedStorage
    end
    return fn
end
local GetMatchState = ensureFunction("GetMatchState")

GetMatchState.OnServerInvoke = function(player)
    local duration = STATE_DURATION[State]
    local startedAt = phaseStartTick
    if State == "Game" then
        startedAt = matchStartTick
        duration = MATCH_DURATION
    elseif State == "Intermission" then
        startedAt = intermissionStartTick or phaseStartTick
        duration = MATCH_RESULTS_DURATION
    end
    return {
        state = State or "Idle",
        startedAt = startedAt,
        duration = duration,
        matchStartTick = matchStartTick,
        matchDuration = MATCH_DURATION,
        teamScores = { Blue = teamScores.Blue or 0, Red = teamScores.Red or 0 },
    }
end

local function broadcastScore(teamName, value, absolute)
    pcall(function() ScoreUpdate:FireAllClients(teamName, value, absolute) end)
end

local function afterDelay(seconds, expectedState, capturedGen, callback)
    task.delay(seconds or 0, function()
        if capturedGen and capturedGen ~= phaseGen then
            print(string.format("[GameManager] stale delay ignored (wanted gen=%s have=%s state=%s)", tostring(capturedGen), tostring(phaseGen), tostring(State)))
            return
        end
        if expectedState and State ~= expectedState then
            print(string.format("[GameManager] delay ignored; expected %s got %s", tostring(expectedState), tostring(State)))
            return
        end
        callback()
    end)
end

---------------------------------------------------------------------
-- Barriers (named "Barrier" or attribute IsBarrier)
---------------------------------------------------------------------
local function isBarrierObject(obj)
    if not obj then
        return false
    end
    if obj.Name == "Barrier" then
        return true
    end
    local ok, val = pcall(function()
        return obj:GetAttribute("IsBarrier")
    end)
    return ok and val == true
end

local function collectBarriers()
    local barriers = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isBarrierObject(obj) then
            local ancestorIsBarrier = false
            local parent = obj.Parent
            while parent and parent ~= workspace do
                if isBarrierObject(parent) then
                    ancestorIsBarrier = true
                    break
                end
                parent = parent.Parent
            end
            if not ancestorIsBarrier then
                table.insert(barriers, obj)
            end
        end
    end
    return barriers
end

local function fadeBarriers(duration)
    duration = duration or BARRIER_FADE_TIME
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, obj in ipairs(collectBarriers()) do
        local parts = {}
        if obj:IsA("BasePart") then
            table.insert(parts, obj)
        end
        for _, desc in ipairs(obj:GetDescendants()) do
            table.insert(parts, desc)
        end
        for _, inst in ipairs(parts) do
            if inst:IsA("BasePart") then
                pcall(function()
                    TweenService:Create(inst, tweenInfo, { Transparency = 1 }):Play()
                end)
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                pcall(function()
                    TweenService:Create(inst, tweenInfo, { Transparency = 1 }):Play()
                end)
            end
        end
    end
end

local function destroyBarriers()
    for _, obj in ipairs(collectBarriers()) do
        pcall(function()
            obj:Destroy()
        end)
    end
end

---------------------------------------------------------------------
-- Score handler  (called by the BindableEvent from any script)
---------------------------------------------------------------------
local function onAddScore(teamName, delta)
    if type(teamName) ~= "string" or type(delta) ~= "number" then return end
    if not teamScores[teamName] then return end

    if State == "SuddenDeath" then
        -- first point wins immediately
        teamScores[teamName] = teamScores[teamName] + delta
        broadcastScore(teamName, delta, false)
        -- end the match with this team as winner
        endMatch(teamName)   -- forward-declared below
        return
    end

    if State ~= "Game" then return end   -- ignore points outside active play

    teamScores[teamName] = teamScores[teamName] + delta
    broadcastScore(teamName, delta, false)
end

AddScore.Event:Connect(onAddScore)

---------------------------------------------------------------------
-- End match
---------------------------------------------------------------------
local function setPlayersToNeutralLobby()
    local neutralTeam = Teams:FindFirstChild("Neutral")

    for _, pl in ipairs(Players:GetPlayers()) do
        pcall(function()
            if neutralTeam then
                pl.Team = neutralTeam
            end
            pl:SetAttribute("Team", nil)
            pl:LoadCharacter()
        end)
    end
end

local function registerMatchOutcome(winnerTeam)
    if not StatService then return end

    for _, pl in ipairs(Players:GetPlayers()) do
        pcall(function()
            StatService:RegisterMatchPlayed(pl)
            if winnerTeam and pl.Team and pl.Team.Name == winnerTeam then
                StatService:RegisterMatchWon(pl)
            end
        end)
    end
end

local function resetMatchForIntermission()
    local ResetFlags = ServerScriptService:FindFirstChild("ResetFlags")
    if ResetFlags then
        pcall(function() ResetFlags:Fire("destroy") end)
    end

    for _, pl in ipairs(Players:GetPlayers()) do
        pcall(function()
            if StatService then
                StatService:ResetMatchStats(pl)
            end
        end)
    end

    teamScores.Blue = 0
    teamScores.Red = 0
    broadcastScore("Blue", 0, true)
    broadcastScore("Red", 0, true)

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:GetAttribute("IsSpawnedMob") == true then
            pcall(function() obj:Destroy() end)
        end
    end

    setPlayersToNeutralLobby()
end

local MapVote = nil
local mapVoteModule = ServerScriptService:FindFirstChild("MapVoteService")
if mapVoteModule then
    local ok, mod = pcall(function() return require(mapVoteModule) end)
    if ok then
        MapVote = mod
        print("[GameManager] MapVoteService required")
    else
        warn("[GameManager] Failed to require MapVoteService:", tostring(mod))
    end
end

-- If the MapVote module exists but failed to require (race), try a short retry
if mapVoteModule and not MapVote then
    task.spawn(function()
        task.wait(1)
        local ok2, mod2 = pcall(function() return require(mapVoteModule) end)
        if ok2 and mod2 then
            MapVote = mod2
            print("[GameManager] MapVoteService required on retry")
        else
            warn("[GameManager] MapVoteService still unavailable after retry:", tostring(mod2))
        end
    end)
end

local PhaseRE = nil
do
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    PhaseRE = rem and rem:FindFirstChild("MapVote") and rem.MapVote:FindFirstChild("Phase")
end

-- runLobbyCycle manages matchResults -> voting -> loading -> prematch -> match
local function runLobbyCycle()
    local myGen = phaseGen + 1
    -- move to matchResults/Intermission
    setMatchState("Intermission")
        -- If we have a stored match results payload from the previous endMatch,
        -- emit it now so clients show the MatchResults UI during Intermission.
        if lastMatchResultsPayload then
            pcall(function()
                MatchResults:FireAllClients(lastMatchResultsPayload)
            end)
            -- Attempt to increment career MVP stat for the selected player (ensure profile loaded)
            local mvpId = lastMatchResultsPayload.mvpUserId
            if mvpId and mvpId > 0 then
                local pl = Players:GetPlayerByUserId(mvpId)
                if pl then
                    local ok, CareerStatsService = pcall(function() return require(ServerScriptService:WaitForChild("CareerStatsService")) end)
                    if ok and CareerStatsService and type(CareerStatsService.LoadForPlayer) == "function" then
                        pcall(function()
                            CareerStatsService:LoadForPlayer(pl)
                            CareerStatsService:IncrementStat(pl, "MVPs", 1)
                        end)
                    end
                end
                -- Capture appearance before lobby reset; build the rig without blocking intermission.
                local mvpDescription = resolveMVPDescription(mvpId)
                local mvpTeam = lastMatchResultsPayload.winner
                for _, entry in ipairs(lastMatchResultsPayload.players or {}) do
                    if entry.userId == mvpId then
                        mvpTeam = entry.team or mvpTeam
                        break
                    end
                end
                task.spawn(function()
                    spawnMVPAvatar(mvpId, mvpDescription, mvpTeam)
                end)
            end
            lastMatchResultsPayload = nil
        end
        if MapVote and MapVote.DespawnCurrentMap then
            pcall(function()
                MapVote.DespawnCurrentMap()
            end)
        end
        resetMatchForIntermission()
    intermissionStartTick = workspace:GetServerTimeNow()
    pcall(function() IntermissionStart:FireAllClients(MATCH_RESULTS_DURATION, intermissionStartTick) end)

    afterDelay(MATCH_RESULTS_DURATION, "Intermission", myGen, function()
        -- Voting
        setMatchState("Voting")
        if MapVote and MapVote.StartVoting then pcall(function() MapVote.StartVoting() end) end
        if PhaseRE and PhaseRE:IsA("RemoteEvent") then
            pcall(function() PhaseRE:FireAllClients({ phase = "voting", duration = VOTING_DURATION, currentMap = nil }) end)
        end
        local genVoting = phaseGen

        afterDelay(VOTING_DURATION, "Voting", genVoting, function()
            -- Stop voting and pick winner
            local winner
            if MapVote and MapVote.StopVotingAndGetWinner then
                local ok, res = pcall(function() return MapVote.StopVotingAndGetWinner() end)
                if ok then winner = res end
            end
            -- Spawn winner map if available
            if winner and MapVote and MapVote.SpawnMap then pcall(function() MapVote.SpawnMap(winner) end) end

            -- Loading
            setMatchState("Loading")
            if PhaseRE and PhaseRE:IsA("RemoteEvent") then
                pcall(function() PhaseRE:FireAllClients({ phase = "loading", duration = LOADING_DURATION, currentMap = winner }) end)
            end
            local genLoading = phaseGen

            afterDelay(LOADING_DURATION, "Loading", genLoading, function()
                -- Prematch
                setMatchState("Prematch")
                if PhaseRE and PhaseRE:IsA("RemoteEvent") then
                    pcall(function() PhaseRE:FireAllClients({ phase = "prematch", duration = PREMATCH_DURATION, currentMap = winner }) end)
                end
                local genPrematch = phaseGen

                afterDelay(math.max(0, PREMATCH_DURATION - BARRIER_FADE_TIME), "Prematch", genPrematch, function()
                    fadeBarriers(BARRIER_FADE_TIME)
                end)

                afterDelay(PREMATCH_DURATION, "Prematch", genPrematch, function()
                    -- If no players, wait for a join to start match
                    if #Players:GetPlayers() == 0 then
                        local conn
                        conn = Players.PlayerAdded:Connect(function()
                            if conn then conn:Disconnect() end
                            if State == "Prematch" then
                                startMatch()
                            end
                        end)
                    else
                        startMatch()
                    end
                end)
            end)
        end)
    end)
end

function endMatch(winnerTeam)
    if State == "EndGame" or State == "Intermission" then return end
    setMatchState("EndGame")
    matchStartTick = nil
    intermissionStartTick = nil
    -- Stop event scheduler for this match
    if EventScheduler then pcall(function() EventScheduler:StopMatch() end) end
    print("[GameManager] END — winner:", winnerTeam, "  Blue:", teamScores.Blue, " Red:", teamScores.Red)
    pcall(function() MatchEnd:FireAllClients("win", winnerTeam) end)
    pcall(function() MatchEndedBE:Fire(winnerTeam) end)
    registerMatchOutcome(winnerTeam)

    -- Build match results payload and compute MVP (only from winning team)
    local playersSummary = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        local entry = {
            userId = pl.UserId,
            name = pl.Name,
            displayName = (pcall(function() return pl.DisplayName end) and pl.DisplayName) or pl.Name,
            team = (pl.Team and pl.Team.Name) or "Neutral",
            level = tonumber(pl:GetAttribute("Level")) or 0,
            score = (StatService and StatService:GetStat(pl, "Score")) or tonumber(pl:GetAttribute("Score")) or 0,
            eliminations = (StatService and StatService:GetStat(pl, "Eliminations")) or tonumber(pl:GetAttribute("Eliminations")) or 0,
            deaths = (StatService and StatService:GetStat(pl, "Deaths")) or tonumber(pl:GetAttribute("Deaths")) or 0,
            captures = (StatService and StatService:GetStat(pl, "FlagCaptures")) or tonumber(pl:GetAttribute("FlagCaptures")) or 0,
            returns = (StatService and StatService:GetStat(pl, "FlagReturns")) or tonumber(pl:GetAttribute("FlagReturns")) or 0,
        }
        table.insert(playersSummary, entry)
    end

    -- Filter to winning team
    local contenders = {}
    for _, e in ipairs(playersSummary) do
        if e.team == winnerTeam then table.insert(contenders, e) end
    end

    local mvpEntry = nil
    if #contenders > 0 then
        local ties = contenders
        -- 1) Highest Score
        local function filterMax(list, key, chooseMin)
            local best = nil
            for _, v in ipairs(list) do
                local val = tonumber(v[key]) or 0
                if best == nil then best = val end
                if chooseMin then
                    if val < best then best = val end
                else
                    if val > best then best = val end
                end
            end
            local out = {}
            for _, v in ipairs(list) do
                local val = tonumber(v[key]) or 0
                if val == best then table.insert(out, v) end
            end
            return out
        end

        ties = filterMax(ties, "score")
        if #ties > 1 then ties = filterMax(ties, "eliminations") end
        if #ties > 1 then ties = filterMax(ties, "captures") end
        if #ties > 1 then ties = filterMax(ties, "deaths", true) end
        if #ties > 1 then ties = filterMax(ties, "returns") end
        if #ties > 1 then
            math.randomseed(tick() + #ties)
            mvpEntry = ties[ math.random(1, #ties) ]
        else
            mvpEntry = ties[1]
        end
    end

    local mvpUserId = mvpEntry and mvpEntry.userId or nil
    local mapName = nil
    if MapVote and type(MapVote.GetCurrentMapName) == "function" then
        pcall(function()
            mapName = MapVote.GetCurrentMapName()
        end)
    end
    -- Store payload to be emitted at Intermission (so clients see it when matchResults/intermission state begins)
    lastMatchResultsPayload = {
        winner = winnerTeam,
        score = { Blue = teamScores.Blue, Red = teamScores.Red },
        players = playersSummary,
        mvpUserId = mvpUserId,
        mapName = mapName,
    }

    -- After endgame display, run the lobby cycle (matchResults -> voting -> loading -> prematch -> match)
    afterDelay(END_SCREEN_TIME, "EndGame", phaseGen, function()
            runLobbyCycle()
        end)
end

---------------------------------------------------------------------
-- Start match
---------------------------------------------------------------------
function startMatch()
    local ResetFlags = ServerScriptService:FindFirstChild("ResetFlags")
    if ResetFlags then
        pcall(function() ResetFlags:Fire("spawn") end)
    end

    teamScores.Blue = 0
    teamScores.Red = 0
    intermissionStartTick = nil
    setMatchState("Game")
    -- Fade starts 1s before match start during Prematch; destroy once Game begins.
    destroyBarriers()
    matchStartTick = workspace:GetServerTimeNow()
    print("[GameManager] MATCH START —", MATCH_DURATION, "s")
    pcall(function() MatchStart:FireAllClients(MATCH_DURATION, matchStartTick) end)
    pcall(function() MatchStartedBE:Fire() end)

    -- Start event scheduler for this match
    if EventScheduler then pcall(function() EventScheduler:StartMatch(matchStartTick) end) end

    -- Monitor remaining time; sleeps exactly until 0 so it fires instantly.
    -- Re-checks after waking in case matchStartTick was adjusted mid-sleep.
    task.spawn(function()
        while State == "Game" do
            local now = workspace:GetServerTimeNow()
            local remaining = MATCH_DURATION - (now - matchStartTick)
            if remaining <= 1 then
                if teamScores.Blue == teamScores.Red then
                    setMatchState("SuddenDeath")
                    print("[GameManager] SUDDEN DEATH — scores tied at", teamScores.Blue)
                    pcall(function() MatchEnd:FireAllClients("sudden") end)
                else
                    local winner = (teamScores.Blue > teamScores.Red) and "Blue" or "Red"
                    endMatch(winner)
                end
                return
            end
            -- Sleep for the lesser of remaining time or 1s, so we wake
            -- right at 0 but still re-check periodically for adjustments.
            task.wait(math.min(remaining, 1))
        end
    end)
end

-- (boot logic moved below to allow MapVoteService to control match starts)
-- Allow external systems (e.g. MapVoteService) to request a match start
local StartMatchBE = ServerScriptService:FindFirstChild("StartMatch")
if not StartMatchBE then
    StartMatchBE = Instance.new("BindableEvent")
    StartMatchBE.Name = "StartMatch"
    StartMatchBE.Parent = ServerScriptService
end
StartMatchBE.Event:Connect(function()
    if not (State == "Prematch" or State == "Idle") then
        print("[GameManager] StartMatch requested but not allowed in state=", State)
        return
    end
    startMatch()
end)

-- If MapVoteService exists, defer auto-start to MapVote; otherwise keep existing boot logic
if MapVote then
    print("[GameManager] MapVoteService detected; starting managed match cycle")
    task.spawn(function()
        runLobbyCycle()
    end)
else
    if MIN_PLAYERS <= 0 then
        -- start immediately
        startMatch()
    else
        -- wait for enough players
        local function checkStart()
            if State ~= "Idle" then return end
            local count = #Players:GetPlayers()
            if count >= MIN_PLAYERS then
                startMatch()
            end
        end
        Players.PlayerAdded:Connect(checkStart)
        checkStart()
    end
end

-- Ensure players who join mid-match receive the current MatchStart info
Players.PlayerAdded:Connect(function(pl)
    if State == "Game" and matchStartTick then
        pcall(function()
            MatchStart:FireClient(pl, MATCH_DURATION, matchStartTick)
        end)
        -- Sync event state to the late-joining player
        if EventScheduler then pcall(function() EventScheduler:SyncPlayer(pl) end) end
    elseif State == "Intermission" and intermissionStartTick then
        pcall(function()
            IntermissionStart:FireClient(pl, MATCH_RESULTS_DURATION, intermissionStartTick)
        end)
    end
end)

-- Allow authorized clients (devs/studio or game creator) to adjust remaining match time for testing.
local RunService = game:GetService("RunService")
AdjustMatchTime.OnServerEvent:Connect(function(player, deltaSeconds)
    if type(deltaSeconds) ~= "number" then return end
    -- allow in Studio or the game's creator only
    if not (RunService:IsStudio() or (player and player.UserId == game.CreatorId)) then
        warn("AdjustMatchTime: unauthorized player", player and player.Name)
        return
    end
    if State ~= "Game" or type(matchStartTick) ~= "number" then return end
    -- apply delta: adding to matchStartTick moves start later and increases remaining time
    matchStartTick = matchStartTick + deltaSeconds
    print("[GameManager] AdjustMatchTime by", deltaSeconds, "new matchStartTick", matchStartTick)
    -- notify all clients to resync (use AdjustMatchTime, NOT MatchStart, to avoid resetting scores)
    pcall(function() AdjustMatchTime:FireAllClients(matchStartTick) end)
    -- The match-monitor loop (in startMatch) will detect remaining <= 0 on the
    -- next iteration (~0.5 s) and resolve the match automatically.
end)
