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

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local MATCH_DURATION   = 5 * 60   -- round duration in seconds (5 minutes)
local END_SCREEN_TIME  = 10       -- seconds the winner screen (endgame) stays up
local MATCH_RESULTS_DURATION = 15 -- seconds for match results display (intermission)
local VOTING_DURATION = 15       -- seconds for map voting
local LOADING_DURATION = 2        -- seconds for loading/map spawn settling
local PREMATCH_DURATION = 15      -- seconds for prematch team selection
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
    -- Store payload to be emitted at Intermission (so clients see it when matchResults/intermission state begins)
    lastMatchResultsPayload = {
        winner = winnerTeam,
        score = { Blue = teamScores.Blue, Red = teamScores.Red },
        players = playersSummary,
        mvpUserId = mvpUserId,
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
    -- Destroy any Barrier parts/models at the moment the match actually starts.
    -- Barriers remain during Prematch but should be removed for active Game play.
    for _, obj in ipairs(workspace:GetDescendants()) do
        local isBarrier = false
        pcall(function()
            if obj.Name == "Barrier" then isBarrier = true end
            local ga = obj.GetAttribute
            if type(ga) == "function" then
                local ok, val = pcall(function() return obj:GetAttribute("IsBarrier") end)
                if ok and val == true then isBarrier = true end
            end
        end)
        if isBarrier then
            pcall(function() obj:Destroy() end)
        end
    end
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
