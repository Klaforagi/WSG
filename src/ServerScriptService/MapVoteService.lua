local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MapVoteService = {}
print("[MapVote] MapVoteService (vote-only) loaded")

local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")

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

    local function ensure(name)
        local existing = mv:FindFirstChild(name)
        if existing and existing:IsA("RemoteEvent") then
            return existing
        end
        local re = Instance.new("RemoteEvent")
        re.Name = name
        re.Parent = mv
        return re
    end

    return ensure("CastVote"), ensure("Update"), ensure("Phase")
end

local CastVoteRE, UpdateRE, PhaseRE = ensureRemotes()

-- internal state
local votingActive = false
local userVote = {} -- userId -> mapName
local currentMapInstance = nil
local currentMapName = nil

local function broadcastVotes()
    local perMap = {}
    for userId, mapName in pairs(userVote) do
        perMap[mapName] = perMap[mapName] or {}
        table.insert(perMap[mapName], userId)
    end
    pcall(function() UpdateRE:FireAllClients({ mapVotes = perMap }) end)
end

function MapVoteService.StartVoting()
    userVote = {}
    votingActive = true
    broadcastVotes()
    print("[MapVote] StartVoting")
end

function MapVoteService.StopVotingAndGetWinner()
    votingActive = false
    -- determine winner
    mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
    local mapChildren = mapsFolder and mapsFolder:GetChildren() or {}

    local counts = {}
    for _, map in ipairs(mapChildren) do counts[map.Name] = 0 end
    local totalVotes = 0
    for _, mapName in pairs(userVote) do
        if counts[mapName] ~= nil then
            counts[mapName] = counts[mapName] + 1
            totalVotes = totalVotes + 1
        end
    end

    if totalVotes == 0 then
        if #mapChildren == 0 then return nil end
        local choice = mapChildren[math.random(1, #mapChildren)].Name
        print("[MapVote] No votes - random choice ->", choice)
        return choice
    end

    local tied = {}
    local best = -1
    for mapName, cnt in pairs(counts) do
        if cnt > best then
            tied = { mapName }
            best = cnt
        elseif cnt == best then
            table.insert(tied, mapName)
        end
    end
    if #tied == 0 then return nil end
    local choice = tied[math.random(1, #tied)]
    print("[MapVote] Winner ->", choice)
    return choice
end

function MapVoteService.SpawnMap(name)
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
    if currentMapInstance then
        pcall(function() currentMapInstance:Destroy() end)
        currentMapInstance = nil
        currentMapName = nil
    end
    local clone = template:Clone()
    clone.Name = name
    clone.Parent = Workspace
    currentMapInstance = clone
    currentMapName = name
    print("[MapVote] Spawned map ->", name)
    return clone
end

function MapVoteService.DespawnCurrentMap()
    if currentMapInstance then
        pcall(function() currentMapInstance:Destroy() end)
        currentMapInstance = nil
        currentMapName = nil
        print("[MapVote] Despawned current map")
    end
end

CastVoteRE.OnServerEvent:Connect(function(player, mapName)
    if not votingActive then return end
    mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
    if not mapsFolder or not mapsFolder:FindFirstChild(mapName) then return end
    userVote[player.UserId] = mapName
    broadcastVotes()
end)

Players.PlayerAdded:Connect(function(player)
    -- send current vote snapshot and currentMap info
    local perMap = {}
    for userId, mapName in pairs(userVote) do
        perMap[mapName] = perMap[mapName] or {}
        table.insert(perMap[mapName], userId)
    end
    pcall(function() UpdateRE:FireClient(player, { mapVotes = perMap, currentMap = currentMapName }) end)
end)

Players.PlayerRemoving:Connect(function(player)
    if userVote[player.UserId] then
        userVote[player.UserId] = nil
        if votingActive then broadcastVotes() end
    end
end)

return MapVoteService
