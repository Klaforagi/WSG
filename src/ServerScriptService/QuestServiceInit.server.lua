--------------------------------------------------------------------------------
-- QuestServiceInit.server.lua
-- Creates remotes and hooks quest progress into existing game systems:
--   • Mob kills  → ZombieKill RemoteEvent (from MobSpawner)
--   • PvP kills  → KillTracker's humanoid death handler (attribute-based)
--   • Flag returns → FlagStatus RemoteEvent (from FlagPickup)
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require QuestService module
local QuestService = require(ServerScriptService:WaitForChild("QuestService", 10))

--------------------------------------------------------------------------------
-- Create Remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

-- GetQuests: client asks for the full quest list
local getQuestsRF = Instance.new("RemoteFunction")
getQuestsRF.Name = "GetQuests"
getQuestsRF.Parent = remotesFolder

-- QuestProgress: server pushes live progress updates to client
local questProgressRE = Instance.new("RemoteEvent")
questProgressRE.Name = "QuestProgress"
questProgressRE.Parent = remotesFolder

-- ClaimQuest: client requests reward claim
local claimQuestRF = Instance.new("RemoteFunction")
claimQuestRF.Name = "ClaimQuest"
claimQuestRF.Parent = remotesFolder

--------------------------------------------------------------------------------
-- Remote handlers
--------------------------------------------------------------------------------
getQuestsRF.OnServerInvoke = function(player)
    return QuestService:GetQuestsForPlayer(player)
end

claimQuestRF.OnServerInvoke = function(player, questId)
    if type(questId) ~= "string" then return false end
    return QuestService:ClaimReward(player, questId)
end

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    QuestService:ClearPlayer(player)
end)

--------------------------------------------------------------------------------
-- Hook: Zombie kills  (ZombieKill RemoteEvent fired by MobSpawner to the killer)
-- MobSpawner fires  ZombieKill:FireClient(killer)  when a zombie dies.
-- We listen server-side by hooking the event before MobSpawner fires it:
-- Since RemoteEvents can also be listened to from the server via .OnServerEvent
-- we instead tap into the KillTracker death handler for mob kills.
--------------------------------------------------------------------------------

-- We hook into KillTracker's system: when a non-player humanoid dies and
-- the killer is identified, the KillTracker fires KillFeed RemoteEvent.
-- Instead of duplicating that logic, we listen for the KillFeed event and
-- detect mob kills (victimName is NOT a player name).
task.spawn(function()
    local killFeed = ReplicatedStorage:WaitForChild("KillFeed", 15)
    if not killFeed then
        warn("[QuestServiceInit] KillFeed remote not found – zombie quest won't track")
        return
    end

    -- KillFeed fires: damagerName, victimName, coinAward
    -- Mob kills: victimName is NOT a player name
    killFeed.OnClientEvent = nil -- we're on server, use different approach

    -- Actually, KillFeed is a RemoteEvent fired to all clients.  On the server
    -- we can't listen to OnClientEvent.  Instead, we'll wrap KillTracker's
    -- existing logic by monitoring the humanoid death path ourselves.
    -- 
    -- Better approach: listen for DescendantRemoving / tag-based tracking.
    -- Simplest: hook Workspace.DescendantRemoving for tagged NPCs.
    
    -- Watch for ZombieKill remote. MobSpawner fires this to the killer client.
    -- We can't intercept FireClient from server.  So instead we duplicate the
    -- attribution check by hooking humanoid deaths on tagged mobs.
end)

-- Robust approach: Track mob deaths via CollectionService tag "ZombieNPC" (set by MobSpawner)
local CollectionService = game:GetService("CollectionService")
local MOB_TAG = "ZombieNPC"

local function hookMobForQuest(mob)
    if not mob:IsA("Model") then return end
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = mob:WaitForChild("Humanoid", 3)
    end
    if not humanoid then return end

    local hooked = false
    humanoid.Died:Connect(function()
        if hooked then return end
        hooked = true

        local damagerName = humanoid:GetAttribute("lastDamagerName")
        local damagerUserId = humanoid:GetAttribute("lastDamagerUserId")
        if not damagerName then return end

        local killer
        if damagerUserId then
            killer = Players:GetPlayerByUserId(damagerUserId)
        end
        if not killer then
            killer = Players:FindFirstChild(damagerName)
        end
        if killer then
            QuestService:IncrementQuest(killer, "zombie_hunter", 1)
        end
    end)
end

-- Hook existing tagged mobs
for _, mob in ipairs(CollectionService:GetTagged(MOB_TAG)) do
    task.spawn(hookMobForQuest, mob)
end

-- Hook future tagged mobs
CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(mob)
    task.spawn(hookMobForQuest, mob)
end)

--------------------------------------------------------------------------------
-- Hook: PvP kills  (piggyback on _G.AwardPlayerKill from PvpKills.server.lua)
-- Wrap the global function so quest progress is tracked alongside PvP kills.
--------------------------------------------------------------------------------
task.spawn(function()
    -- Wait briefly for PvpKills.server.lua to set up _G.AwardPlayerKill
    local tries = 0
    while not _G.AwardPlayerKill and tries < 20 do
        task.wait(0.25)
        tries = tries + 1
    end

    local originalAward = _G.AwardPlayerKill
    if type(originalAward) == "function" then
        _G.AwardPlayerKill = function(killerPlayer, victimPlayer)
            -- call original first
            originalAward(killerPlayer, victimPlayer)
            -- track quest
            if typeof(killerPlayer) == "Instance" and killerPlayer:IsA("Player") then
                QuestService:IncrementQuest(killerPlayer, "battle_ready", 1)
            end
        end
    else
        warn("[QuestServiceInit] _G.AwardPlayerKill not found – PvP quest won't auto-track")
    end

    -- Also listen to KillTracker deaths to catch PvP kills that go through
    -- the humanoid attribute path rather than _G.AwardPlayerKill.
    -- KillTracker fires KillFeed:FireAllClients(damagerName, victimName, coinAward).
    -- We can't intercept that from the server, but the PvP path in KillTracker
    -- also awards XP via XPModule.AwardXP(killer, "PlayerKill"), so wrapping
    -- _G.AwardPlayerKill covers the PvpKills.server.lua path.
    -- For the KillTracker path (attribute-based without creator ObjectValue),
    -- we add a secondary hook via DescendantAdded on player characters.

    local function hookPlayerCharForPvpQuest(player)
        player.CharacterAdded:Connect(function(char)
            local hum = char:WaitForChild("Humanoid", 5)
            if not hum then return end
            local awarded = false
            hum.Died:Connect(function()
                if awarded then return end
                awarded = true
                -- Check who killed this player
                local damagerName = hum:GetAttribute("lastDamagerName")
                local damagerUserId = hum:GetAttribute("lastDamagerUserId")
                if not damagerName then return end
                -- Don't self-credit
                if damagerName == player.Name then return end

                local killer
                if damagerUserId then
                    killer = Players:GetPlayerByUserId(damagerUserId)
                end
                if not killer then
                    killer = Players:FindFirstChild(damagerName)
                end
                if killer and killer:IsA("Player") then
                    QuestService:IncrementQuest(killer, "battle_ready", 1)
                end
            end)
        end)
    end

    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(hookPlayerCharForPvpQuest, p)
    end
    Players.PlayerAdded:Connect(function(p)
        hookPlayerCharForPvpQuest(p)
    end)
end)

--------------------------------------------------------------------------------
-- Hook: Flag returns  (FlagReturned BindableEvent from FlagPickup.server.lua)
-- FlagPickup fires  FlagReturned:Fire(player)  when a player returns their
-- team's dropped flag.  We listen on the server via the BindableEvent.
--------------------------------------------------------------------------------
task.spawn(function()
    local flagReturnedEvent = ServerScriptService:WaitForChild("FlagReturned", 15)
    if not flagReturnedEvent or not flagReturnedEvent:IsA("BindableEvent") then
        warn("[QuestServiceInit] FlagReturned BindableEvent not found – flag return quest won't auto-track")
        return
    end

    flagReturnedEvent.Event:Connect(function(player)
        if typeof(player) == "Instance" and player:IsA("Player") then
            QuestService:IncrementQuest(player, "team_defender", 1)
        end
    end)
    print("[QuestServiceInit] FlagReturned hook connected")
end)

print("[QuestServiceInit] Daily quest system initialized")
