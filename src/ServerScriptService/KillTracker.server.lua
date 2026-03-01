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

local tracked = {} -- [Humanoid] = true, to avoid double-connecting

local function onHumanoidDied(humanoid, model)
    -- skip if already credited directly by the damage code
    if humanoid:GetAttribute("_killCredited") then return end

    local damagerName = humanoid:GetAttribute("lastDamagerName")
    local damagerTime = humanoid:GetAttribute("lastDamageTime")

    -- only credit if the tag is recent
    if not damagerName or not damagerTime then return end
    if (tick() - damagerTime) > ATTRIB_TIMEOUT then return end

    -- figure out victim name
    local victimName = model.Name or "Unknown"
    local victimPlayer = Players:GetPlayerFromCharacter(model)
    if victimPlayer then
        victimName = victimPlayer.Name
    end

    -- don't credit self-kills
    if damagerName == victimName then return end

    -- determine killer (by user id or name) so we can award points/coins
    local damagerUserId = humanoid:GetAttribute("lastDamagerUserId")
    local killer = nil
    if damagerUserId then
        killer = Players:GetPlayerByUserId(damagerUserId)
    end
    if not killer then
        -- fallback: find by name
        killer = Players:FindFirstChild(damagerName)
    end

    -- award points to the killer's team
    if killer and killer.Team then
        pcall(function() AddScore:Fire(killer.Team.Name, KILL_POINTS) end)
    end

    -- Award 1 coin for mob kills (fallback for kills not handled by weapon scripts)
    local coinAward = 0
    if not victimPlayer and killer then
        if CurrencyService and CurrencyService.AddCoins then
            pcall(function() CurrencyService:AddCoins(killer, 1) end)
            coinAward = 1
        end
    end

    -- fire kill feed to all clients (include coin amount if any)
    KillFeed:FireAllClients(damagerName, victimName, coinAward)

    -- Award XP to the killer
    if killer and XPModule and XPModule.AwardXP then
        if victimPlayer then
            -- PvP kill → use XPConfig.PlayerKill amount
            pcall(function() XPModule.AwardXP(killer, "PlayerKill") end)
        else
            -- Mob kill → look up per-mob XP from MobSettings via XPModule.GetMobXP
            local mobName = model and model.Name or "Unknown"
            local mobXP = 3
            pcall(function()
                if XPModule.GetMobXP then
                    mobXP = XPModule.GetMobXP(mobName)
                end
            end)
            pcall(function() XPModule.AwardXP(killer, "MobKill", mobXP) end)
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
