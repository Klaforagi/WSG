local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatUtils = require(ServerScriptService:WaitForChild("CombatUtils"))

local PodiumTagger = {}

local function tagAllPodiums()
    local count = 0
    -- Directly tag known podium avatar models
    for _, name in ipairs({"PodiumAvatar_1","PodiumAvatar_2","PodiumAvatar_3"}) do
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj and obj:IsA("Model") and obj.Name == name then
                pcall(function() CombatUtils.tagPodiumModel(obj) end)
                count = count + 1
            end
        end
    end

    -- Also tag any podium models under leaderboard structures
    local leaderboard = Workspace:FindFirstChild("GiantLeaderboardLevels")
    if leaderboard and leaderboard:IsA("Model") then
        local podium = leaderboard:FindFirstChild("Podium")
        if podium and podium:IsA("Model") then
            for _, child in ipairs(podium:GetDescendants()) do
                local m = child:FindFirstAncestorOfClass("Model")
                if m and m:IsA("Model") then
                    pcall(function() CombatUtils.tagPodiumModel(m) end)
                    count = count + 1
                end
            end
        end
    end

    if _G.DEBUG_COMBAT then
        print(string.format("[Combat] PodiumTagger: tagged %d models as podium avatars", count))
    end
    return count
end

-- Expose for manual invocation
PodiumTagger.TagAll = tagAllPodiums

-- Auto-run at startup to catch pre-spawned podiums
pcall(tagAllPodiums)

return PodiumTagger
