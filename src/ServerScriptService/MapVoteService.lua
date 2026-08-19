--[[
    MapVoteService.lua (ServerScriptService - ModuleScript)
    Handles map voting, map spawning and the match phase cycle:
      matchResults (15s) -> voting (20s) -> loading (5s) -> prematch (15s) -> match (900s)

    It creates Remotes under ReplicatedStorage/Remotes/MapVote if missing.
    When voting is active it tracks player votes and broadcasts updates to clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MapVoteService = {}

print("[MapVote] MapVoteService module loaded")

-- Phase timings (seconds)
local PHASE_MATCH_RESULTS = "matchResults" -- delete previous map here (15s)
local PHASE_VOTING = "voting"              -- players vote (20s)
local PHASE_LOADING = "loading"            -- spawn map, allow load (5s)
local PHASE_PREMATCH = "prematch"        -- team select (15s)
local PHASE_MATCH = "match"              -- match running (900s)

local DURATION = {
    [PHASE_MATCH_RESULTS] = 15,
    [PHASE_VOTING] = 20,
    [PHASE_LOADING] = 5,
    [PHASE_PREMATCH] = 15,
    [PHASE_MATCH] = 15 * 60,
}

-- Map resources
local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")

-- Remotes (created if missing)
local function ensureRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        remotes = Instance.new("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
    end

    local mv = remotes:FindFirstChild("MapVote")
    if not mv then
        mv = Instance.new("Folder")
        mv.Name = "MapVote"
        mv.Parent = remotes
    end

    local cast = mv:FindFirstChild("CastVote")
    if not cast then
        cast = Instance.new("RemoteEvent")
        cast.Name = "CastVote"
        cast.Parent = mv
    end

    local update = mv:FindFirstChild("Update")
    if not update then
        update = Instance.new("RemoteEvent")
        update.Name = "Update"
        update.Parent = mv
    end

    local phase = mv:FindFirstChild("Phase")
    if not phase then
        phase = Instance.new("RemoteEvent")
        phase.Name = "Phase"
        phase.Parent = mv
    end

    return cast, update, phase
end

local CastVoteRE, UpdateRE, PhaseRE = ensureRemotes()
print("[MapVote] Remotes initialized:", tostring(CastVoteRE), tostring(UpdateRE), tostring(PhaseRE))

-- State
local currentPhase = nil
local currentPhaseStartedAt = 0
local currentMapName = nil
local currentMapInstance = nil

-- Scheduling guard to avoid double-scheduling voting start
local votingScheduled = false

-- votes: userId -> mapName
local userVote = {}

local function broadcastVotes()
    local perMap = {}
    for userId, mapName in pairs(userVote) do
        perMap[mapName] = perMap[mapName] or {}
        table.insert(perMap[mapName], userId)
    end
    UpdateRE:FireAllClients({ mapVotes = perMap })
end

local function setPhase(phase)
    currentPhase = phase
    currentPhaseStartedAt = os.time()
    PhaseRE:FireAllClients({ phase = phase, duration = DURATION[phase] or 0, currentMap = currentMapName })
    print(string.format("[MapVote] setPhase -> %s (duration=%s) at %s", tostring(phase), tostring(DURATION[phase]), os.date("%X")))
end

local function spawnMapByName(name)
    if not mapsFolder then
        mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
        if not mapsFolder then
            warn("[MapVote] ReplicatedStorage.Maps not found; cannot spawn map")
            return nil
        end
    end
    local template = mapsFolder:FindFirstChild(name)
    if not template then
        warn("[MapVote] Map template not found: " .. tostring(name))
        return nil
    end
    -- remove any existing map with the same name at workspace root
    local existing = Workspace:FindFirstChild(name)
    if existing then
        pcall(function() existing:Destroy() end)
    end

    -- Clone map template directly into workspace so other systems (MobSpawner, portals)
    -- can find expected objects at top-level.
    local clone = template:Clone()
    clone.Parent = Workspace
    clone.Name = name
    currentMapInstance = clone
    currentMapName = name
    print("[MapVote] Spawned map in Workspace: " .. tostring(name))

    -- Ensure players are placed into the neutral lobby/team for prematch
    local Teams = game:GetService("Teams")
    local neutral = Teams:FindFirstChild("Neutral")
    for _, pl in ipairs(Players:GetPlayers()) do
        pcall(function()
            if neutral then pl.Team = neutral end
            pl:SetAttribute("Team", nil)
            pcall(function() pl:LoadCharacter() end)
        end)
    end

    return clone
end

local function determineWinner()
    -- fetch maps folder at runtime
    local runtimeMaps = ReplicatedStorage:FindFirstChild("Maps")
    local mapChildren = runtimeMaps and runtimeMaps:GetChildren() or {}

    -- count votes per map
    local counts = {}
    for _, map in ipairs(mapChildren) do
        counts[map.Name] = 0
    end
    local totalVotes = 0
    for _, mapName in pairs(userVote) do
        if counts[mapName] ~= nil then
            counts[mapName] = counts[mapName] + 1
            totalVotes = totalVotes + 1
        end
    end

    -- if no votes, pick a random map from available templates
    if totalVotes == 0 then
        if #mapChildren == 0 then
            return nil
        end
        return mapChildren[math.random(1, #mapChildren)].Name
    end

    -- find highest
    local best = nil
    local bestCount = -1
    for mapName, cnt in pairs(counts) do
        if cnt > bestCount then
            best = { mapName }
            bestCount = cnt
        elseif cnt == bestCount then
            table.insert(best, mapName)
        end
    end
    if not best or #best == 0 then
        return nil
    end
    -- tie-breaker random among tied maps
    local choice = best[math.random(1, #best)]
    return choice
end

local function startVoting()
    userVote = {}
    broadcastVotes()
    votingScheduled = false
    print("[MapVote] startVoting() called")
    setPhase(PHASE_VOTING)
    local duration = DURATION[PHASE_VOTING]
    task.delay(duration, function()
        -- voting ended
        print("[MapVote] voting ended; determining winner")
        local winner = determineWinner()
        if winner then
            -- spawn winner
            spawnMapByName(winner)
        else
            print("[MapVote] No winner determined; skipping spawn")
        end
        -- move to loading -> prematch -> match sequence
        setPhase(PHASE_LOADING)
        task.delay(DURATION[PHASE_LOADING], function()
            setPhase(PHASE_PREMATCH)
            task.delay(DURATION[PHASE_PREMATCH], function()
                        -- helper to begin match phase and schedule its end
                        local function beginMatchPhase()
                            setPhase(PHASE_MATCH)
                            -- Notify authoritative GameManager to start the match
                            local startBE = ServerScriptService:FindFirstChild("StartMatch")
                            if startBE and startBE:IsA("BindableEvent") then
                                pcall(function() startBE:Fire() end)
                                print("[MapVote] Fired StartMatch BindableEvent to GameManager")
                            else
                                print("[MapVote] StartMatch BindableEvent not found; GameManager may auto-start")
                            end
                            print("[MapVote] Match started; scheduling end in seconds:", DURATION[PHASE_MATCH])
                            task.delay(DURATION[PHASE_MATCH], function()
                                -- match ended -> start match results
                                setPhase(PHASE_MATCH_RESULTS)
                                -- delete current map now
                                if currentMapInstance then
                                    pcall(function() currentMapInstance:Destroy() end)
                                    currentMapInstance = nil
                                    currentMapName = nil
                                end
                                -- after match results, start next voting
                                task.delay(DURATION[PHASE_MATCH_RESULTS], function()
                                    startVoting()
                                end)
                            end)
                        end

                        -- only start match if there is at least one player
                        if #Players:GetPlayers() == 0 then
                            print("[MapVote] No players at prematch end; deferring match until a player joins")
                            local conn
                            conn = Players.PlayerAdded:Connect(function()
                                conn:Disconnect()
                                print("[MapVote] Player joined; starting match phase")
                                beginMatchPhase()
                            end)
                        else
                            beginMatchPhase()
                        end
            end)
        end)
    end)
end

-- Player vote handler
CastVoteRE.OnServerEvent:Connect(function(player, mapName)
    if currentPhase ~= PHASE_VOTING then return end
    if not mapsFolder then return end
    local valid = mapsFolder:FindFirstChild(mapName)
    if not valid then return end

    userVote[player.UserId] = mapName
    broadcastVotes()
end)

-- When players join, send them current phase and current votes
Players.PlayerAdded:Connect(function(player)
    -- send current phase
    local sendPhase = currentPhase or PHASE_MATCH_RESULTS
    print(string.format("[MapVote] PlayerAdded -> %s (player=%s)", tostring(sendPhase), player.Name))
    if currentPhase then
        -- don't overwrite the global phase/timestamp; send current phase to this player only
        pcall(function()
            PhaseRE:FireClient(player, { phase = currentPhase, duration = DURATION[currentPhase] or 0, currentMap = currentMapName })
        end)
    else
        setPhase(sendPhase)
    end
    -- send votes snapshot
    broadcastVotes()

    -- If we just set (or observed) matchResults and voting hasn't been scheduled,
    -- schedule voting to start after the remaining matchResults duration.
    if sendPhase == PHASE_MATCH_RESULTS and not votingScheduled then
        local elapsed = 0
        if currentPhaseStartedAt and currentPhaseStartedAt > 0 then
            elapsed = os.time() - currentPhaseStartedAt
        end
        local remaining = math.max(0, (DURATION[PHASE_MATCH_RESULTS] or 0) - elapsed)
        votingScheduled = true
        if remaining <= 0 then
            print("[MapVote] matchResults already expired; starting voting immediately")
            task.spawn(startVoting)
        else
            print(string.format("[MapVote] scheduling startVoting in %s seconds (remaining)", tostring(remaining)))
            task.delay(remaining, function()
                print("[MapVote] scheduled matchResults delay complete; starting voting (PlayerAdded path)")
                startVoting()
            end)
        end
    end
end)

-- Start system on server start: if no map active, go to voting
task.spawn(function()
    -- small delay until game systems initialize
    task.wait(1)
    if not currentPhase then
        print("[MapVote] Init: no currentPhase, entering matchResults first")
        -- begin at match results state to allow cleanup, then start voting
        setPhase(PHASE_MATCH_RESULTS)
        -- if an active map exists, remove it at the start of matchResults
        if currentMapInstance then
            pcall(function() currentMapInstance:Destroy() end)
            currentMapInstance = nil
            currentMapName = nil
        end
        print(string.format("[MapVote] Waiting %s seconds for matchResults then starting voting", tostring(DURATION[PHASE_MATCH_RESULTS])))
        votingScheduled = true
        task.delay(DURATION[PHASE_MATCH_RESULTS], function()
            print("[MapVote] matchResults delay complete; starting voting")
            startVoting()
        end)
    else
        print(string.format("[MapVote] Init: currentPhase already set -> %s", tostring(currentPhase)))
    end
end)

return MapVoteService
