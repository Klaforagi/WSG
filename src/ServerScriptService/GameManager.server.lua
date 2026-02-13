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

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local MATCH_DURATION   = 1 * 60   -- seconds
local END_SCREEN_TIME  = 10       -- seconds the winner screen stays up
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

---------------------------------------------------------------------
-- Bindable event  (server script → GameManager)
---------------------------------------------------------------------
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

---------------------------------------------------------------------
-- State  (must be declared BEFORE GetMatchState closure captures them)
---------------------------------------------------------------------
local State = "Idle"   -- Idle | Game | SuddenDeath | EndGame
local teamScores = { Blue = 0, Red = 0 }
local matchStartTick = nil

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
    return {
        state = State or "Idle",
        matchStartTick = matchStartTick,
        matchDuration = MATCH_DURATION,
        teamScores = { Blue = teamScores.Blue or 0, Red = teamScores.Red or 0 },
    }
end

local function broadcastScore(teamName, value, absolute)
    pcall(function() ScoreUpdate:FireAllClients(teamName, value, absolute) end)
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
function endMatch(winnerTeam)
    if State == "EndGame" then return end
    State = "EndGame"
    print("[GameManager] END — winner:", winnerTeam, "  Blue:", teamScores.Blue, " Red:", teamScores.Red)
    pcall(function() MatchEnd:FireAllClients("win", winnerTeam) end)

    task.delay(END_SCREEN_TIME, function()
        -- reset flags before respawning players
        local ResetFlags = ServerScriptService:FindFirstChild("ResetFlags")
        if ResetFlags then
            pcall(function() ResetFlags:Fire() end)
        end

        -- reset scores
        teamScores.Blue = 0
        teamScores.Red = 0
        broadcastScore("Blue", 0, true)
        broadcastScore("Red", 0, true)

        -- respawn all players (flag them so TeamSpawn uses the main spawn)
        for _, pl in ipairs(Players:GetPlayers()) do
            pcall(function()
                pl:SetAttribute("MatchRestart", true)
                pl:LoadCharacter()
            end)
        end

        task.wait(1)
        startMatch()   -- forward-declared below
    end)
end

---------------------------------------------------------------------
-- Start match
---------------------------------------------------------------------
function startMatch()
    teamScores.Blue = 0
    teamScores.Red = 0
    State = "Game"
    matchStartTick = tick()
    print("[GameManager] MATCH START —", MATCH_DURATION, "s")
    pcall(function() MatchStart:FireAllClients(MATCH_DURATION, matchStartTick) end)

    -- server-side countdown
    task.spawn(function()
        local remaining = MATCH_DURATION
        while remaining > 0 do
            task.wait(1)
            remaining = remaining - 1
            -- if the state changed (e.g. EndGame from sudden-death win) bail out
            if State ~= "Game" then return end
        end

        -- timer expired — decide winner or sudden death
        if State ~= "Game" then return end

        if teamScores.Blue == teamScores.Red then
            State = "SuddenDeath"
            print("[GameManager] SUDDEN DEATH — scores tied at", teamScores.Blue)
            pcall(function() MatchEnd:FireAllClients("sudden") end)
            -- match stays in SuddenDeath until someone scores
        else
            local winner = (teamScores.Blue > teamScores.Red) and "Blue" or "Red"
            endMatch(winner)
        end
    end)
end

---------------------------------------------------------------------
-- Boot: start first match once at least MIN_PLAYERS are playing
---------------------------------------------------------------------
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

-- Ensure players who join mid-match receive the current MatchStart info
Players.PlayerAdded:Connect(function(pl)
    if State == "Game" and matchStartTick then
        pcall(function()
            MatchStart:FireClient(pl, MATCH_DURATION, matchStartTick)
        end)
    end
end)
