local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MapVoteService = {}
print("[MapVote] MapVoteService (vote-only) loaded")

local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
local currentOptions = nil -- list of map names shown this voting round

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
    -- ensure currentOptions exported, fall back to all maps
    local options = currentOptions
    if not options then
        mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
        options = {}
        for _, m in ipairs(mapsFolder and mapsFolder:GetChildren() or {}) do table.insert(options, m.Name) end
    end
    -- init perMap with empty lists for each option
    for _, name in ipairs(options) do
        perMap[name] = perMap[name] or {}
    end
    for userId, voteData in pairs(userVote) do
        -- voteData may be either a string (mapName) for legacy or a table {map=..., pos=...}
        local mapName, pos
        if type(voteData) == "table" then
            mapName = voteData.map
            pos = voteData.pos
        else
            mapName = voteData
        end
        if mapName and perMap[mapName] ~= nil then
            table.insert(perMap[mapName], { userId = userId, pos = pos })
        end
    end
    pcall(function() UpdateRE:FireAllClients({ mapVotes = perMap, mapOptions = options }) end)
end

function MapVoteService.StartVoting()
    userVote = {}
    votingActive = true
    -- pick up to 3 random maps from Maps folder as the options for this round
    mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
    local mapChildren = mapsFolder and mapsFolder:GetChildren() or {}
    local names = {}
    for _, m in ipairs(mapChildren) do table.insert(names, m.Name) end
    local options = {}
    if #names <= 3 then
        options = names
    else
        -- pick 3 unique random entries
        local picked = {}
        while #options < 3 do
            local idx = math.random(1, #names)
            local name = names[idx]
            if not picked[name] then
                picked[name] = true
                table.insert(options, name)
            end
        end
    end
    currentOptions = options
    broadcastVotes()
    print("[MapVote] StartVoting options:", unpack(currentOptions or {}))
end

function MapVoteService.StopVotingAndGetWinner()
    votingActive = false
    -- determine winner among currentOptions
    local options = currentOptions or {}
    local counts = {}
    for _, name in ipairs(options) do counts[name] = 0 end
    local totalVotes = 0
    for _, voteData in pairs(userVote) do
        local mapName = type(voteData) == "table" and voteData.map or voteData
        if counts[mapName] ~= nil then
            counts[mapName] = counts[mapName] + 1
            totalVotes = totalVotes + 1
        end
    end

    if totalVotes == 0 then
        -- pick random from options (fallback)
        if #options == 0 then
            mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
            local mapChildren = mapsFolder and mapsFolder:GetChildren() or {}
            if #mapChildren == 0 then return nil end
            local choice = mapChildren[math.random(1, #mapChildren)].Name
            print("[MapVote] No votes - random choice ->", choice)
            return choice
        end
        local choice = options[math.random(1, #options)]
        print("[MapVote] No votes - random option choice ->", choice)
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

function MapVoteService.GetCurrentMapName()
    return currentMapName
end

function MapVoteService.DespawnCurrentMap()
    if currentMapInstance then
        pcall(function() currentMapInstance:Destroy() end)
        currentMapInstance = nil
        currentMapName = nil
        print("[MapVote] Despawned current map")
    end
end

CastVoteRE.OnServerEvent:Connect(function(player, mapName, posArg)
    if not votingActive then return end
    -- support optional position parameter (map click normalized pos) passed as second arg
    local pos = nil
    if posArg and type(posArg) == "table" then
        pos = posArg
    end
    -- validate against currentOptions if set, otherwise allow any existing map
    local valid = false
    if currentOptions then
        for _, name in ipairs(currentOptions) do if name == mapName then valid = true; break end end
    else
        mapsFolder = mapsFolder or ReplicatedStorage:FindFirstChild("Maps")
        if mapsFolder and mapsFolder:FindFirstChild(mapName) then valid = true end
    end
    if not valid then return end
    userVote[player.UserId] = { map = mapName, pos = pos }
    broadcastVotes()
end)

Players.PlayerAdded:Connect(function(player)
    -- send current vote snapshot and currentMap info
    local perMap = {}
    for userId, voteData in pairs(userVote) do
        local mapName, pos
        if type(voteData) == "table" then mapName = voteData.map; pos = voteData.pos else mapName = voteData end
        perMap[mapName] = perMap[mapName] or {}
        table.insert(perMap[mapName], { userId = userId, pos = pos })
    end
    pcall(function() UpdateRE:FireClient(player, { mapVotes = perMap, currentMap = currentMapName, mapOptions = currentOptions }) end)
end)

Players.PlayerRemoving:Connect(function(player)
    if userVote[player.UserId] then
        userVote[player.UserId] = nil
        if votingActive then broadcastVotes() end
    end
end)

return MapVoteService
