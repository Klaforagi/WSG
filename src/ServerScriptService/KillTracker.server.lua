--[[
    KillTracker.server.lua
    Listens for any Humanoid death in the game. If the humanoid was tagged
    with lastDamagerName / lastDamagerUserId (set by the gun server scripts),
    fires KillFeed to all clients and awards +10 to the killer's team via ScoreUpdate.
    Works for both player characters and dummies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ensure RemoteEvents exist
local function ensureEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end

local KillFeed = ensureEvent("KillFeed")

-- BindableEvent for score awards (listened to by GameManager)
local ServerScriptService = game:GetService("ServerScriptService")
local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

local KILL_POINTS = 10
local ATTRIB_TIMEOUT = 5 -- seconds: ignore tags older than this

-- XP integration: require the shared XP module so we can award XP on kills
local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

-- CurrencyService (optional): award coins for mob kills
local CurrencyService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

-- Centralized stat service (single source of truth for all stats & events)
local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

local tracked = {} -- [Humanoid] = true, to avoid double-connecting

local function onHumanoidDied(humanoid, model)
    -- skip if already credited by another script
    if humanoid:GetAttribute("_killCredited") then return end

    -- === Kill Attribution (two detection paths) ===
    local killer = nil
    local damagerName = humanoid:GetAttribute("lastDamagerName")
    local damagerTime = humanoid:GetAttribute("lastDamageTime")
    local damagerUserId = humanoid:GetAttribute("lastDamagerUserId")

    -- Path 1: attribute-based (set by gun/melee hit scripts)
    if damagerName and damagerTime and (tick() - damagerTime) <= ATTRIB_TIMEOUT then
        if damagerUserId then
            killer = Players:GetPlayerByUserId(damagerUserId)
        end
        if not killer then
            killer = Players:FindFirstChild(damagerName)
        end
    end

    -- Path 2: "creator" ObjectValue fallback (standard Roblox weapon pattern)
    if not killer then
        local creator = humanoid:FindFirstChild("creator")
        if creator and creator:IsA("ObjectValue") and creator.Value
            and typeof(creator.Value) == "Instance" and creator.Value:IsA("Player") then
            killer = creator.Value
            damagerName = killer.Name
        end
    end

    if not killer then return end

    -- figure out victim name
    local victimName = model.Name or "Unknown"
    local victimPlayer = Players:GetPlayerFromCharacter(model)
    if victimPlayer then
        victimName = victimPlayer.Name
    end

    -- don't credit self-kills
    if killer == victimPlayer then return end
    if damagerName and damagerName == victimName then return end

    -- Mark as credited to prevent double-counting by other scripts
    humanoid:SetAttribute("_killCredited", true)

    -- award points to the killer's team
    if killer.Team then
        pcall(function() AddScore:Fire(killer.Team.Name, KILL_POINTS) end)
    end

    -- Centralized stat tracking via StatService
    -- (updates scoreboard attributes, fires events for quests/achievements)
    if StatService and killer:IsA("Player") then
        if victimPlayer then
            StatService:RegisterElimination(killer, victimPlayer)
        else
            StatService:RegisterMobKill(killer, victimName)
        end
    end

    -- Award coins: +5 for PvP kills, +1 for mob kills (fallback when weapon scripts didn't credit)
    -- coinAward captures the FINAL amount after boosts so popups display the real value.
    local coinAward = 0
    if victimPlayer and killer then
        -- PvP kill: award 5 coins to the killer
        if CurrencyService and CurrencyService.AddCoins then
            local ok, result = pcall(function() return CurrencyService:AddCoins(killer, 5, "elimination") end)
            coinAward = (ok and type(result) == "number") and result or 5
        end
    elseif not victimPlayer and killer then
        -- Mob kill fallback: award 1 coin
        if CurrencyService and CurrencyService.AddCoins then
            local ok, result = pcall(function() return CurrencyService:AddCoins(killer, 1, "elimination") end)
            coinAward = (ok and type(result) == "number") and result or 1
        end
    end

    -- fire kill feed to all clients (include coin amount if any)
    KillFeed:FireAllClients(damagerName, victimName, coinAward)

    -- Award XP to the killer (include coinAward in metadata so XP popup can show coins)
    if killer and XPModule and XPModule.AwardXP then
        if victimPlayer then
            -- PvP kill → use XPConfig.PlayerKill amount
            pcall(function() XPModule.AwardXP(killer, "PlayerKill", nil, { coinAward = coinAward }) end)
        else
            -- Mob kill → look up per-mob XP from MobSettings via XPModule.GetMobXP
            local mobName = model and model.Name or "Unknown"
            local mobXP = 3
            pcall(function()
                if XPModule.GetMobXP then
                    mobXP = XPModule.GetMobXP(mobName)
                end
            end)
            pcall(function() XPModule.AwardXP(killer, "MobKill", mobXP, { coinAward = coinAward }) end)
        end
    end
end

local function hookHumanoid(humanoid, model)
    if tracked[humanoid] then return end
    tracked[humanoid] = true

    humanoid.Died:Connect(function()
        onHumanoidDied(humanoid, model)
        tracked[humanoid] = nil
    end)
end

local function scanModel(model)
    if not model or not model:IsA("Model") then return end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        hookHumanoid(humanoid, model)
    end
end

-- hook player characters
local function onPlayerAdded(player)
    player.CharacterAdded:Connect(function(char)
        -- wait briefly for Humanoid to be parented
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hookHumanoid(hum, char)
        end
    end)
    -- handle already-spawned character
    if player.Character then
        scanModel(player.Character)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- hook dummies and any NPC models in workspace (scan ALL descendants so nested models are caught)
for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Humanoid") then
        local model = desc.Parent
        if model and model:IsA("Model") then
            hookHumanoid(desc, model)
        end
    end
end

-- watch for any new Humanoid added anywhere in the workspace tree
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Humanoid") then
        local model = desc.Parent
        if model and model:IsA("Model") then
            hookHumanoid(desc, model)
        end
    end
end)
