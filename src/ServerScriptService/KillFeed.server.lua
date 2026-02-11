local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- score tracking (server authoritative)
local teamScores = {
    Blue = 0,
    Red = 0,
}

-- ensure KillFeed RemoteEvent exists
local killFeed = ReplicatedStorage:FindFirstChild("KillFeed")
if not killFeed then
    killFeed = Instance.new("RemoteEvent")
    killFeed.Name = "KillFeed"
    killFeed.Parent = ReplicatedStorage
end

local function onHumanoidDied(humanoid)
    -- determine victim name
    local victimName = "Unknown"
    if humanoid and humanoid.Parent then
        victimName = humanoid.Parent.Name or victimName
    end

    local lastDamagerName = humanoid:GetAttribute("lastDamagerName")
    local lastDamagerTime = humanoid:GetAttribute("lastDamageTime") or 0
    local now = tick()
    local killerName = lastDamagerName or "Unknown"

    -- if the last damage was long ago, treat as world death
    if now - lastDamagerTime > 5 then
        killerName = "Environment"
    end

    -- fire to all clients: (killerName, victimName)
    pcall(function()
        killFeed:FireAllClients(killerName, victimName)
    end)

    -- update team score if killer is a player on a team
    local lastDamagerUserId = humanoid:GetAttribute("lastDamagerUserId")
    local killerPlayer = nil
    if lastDamagerUserId and type(lastDamagerUserId) == "number" then
        killerPlayer = Players:GetPlayerByUserId(lastDamagerUserId)
    else
        -- fallback by name
        local lastDamagerName = humanoid:GetAttribute("lastDamagerName")
        if lastDamagerName then
            killerPlayer = Players:FindFirstChild(lastDamagerName)
        end
    end

    if killerPlayer and killerPlayer.Team and killerPlayer.Team.Name then
        local tname = killerPlayer.Team.Name
        if teamScores[tname] ~= nil then
            teamScores[tname] = teamScores[tname] + 1
            -- ensure ScoreUpdate RemoteEvent exists
            local scoreEv = ReplicatedStorage:FindFirstChild("ScoreUpdate")
            if not scoreEv then
                scoreEv = Instance.new("RemoteEvent")
                scoreEv.Name = "ScoreUpdate"
                scoreEv.Parent = ReplicatedStorage
            end
            -- send delta +1 to all clients
            pcall(function()
                scoreEv:FireAllClients(tname, 1, false)
            end)
        end
    end
end

local function watchHumanoid(humanoid)
    if not humanoid or not humanoid:IsA("Humanoid") then return end
    if humanoid:GetAttribute("_killFeedConnected") then return end
    humanoid:SetAttribute("_killFeedConnected", true)
    humanoid.Died:Connect(function()
        onHumanoidDied(humanoid)
    end)
end

-- scan existing
for _, inst in ipairs(Workspace:GetDescendants()) do
    if inst:IsA("Humanoid") then
        watchHumanoid(inst)
    end
end

Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Humanoid") then
        watchHumanoid(desc)
    end
end)

return nil
