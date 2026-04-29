--[[
    KillTracker.server.lua
    -----------------------------------------------------------------------------
    SINGLE CENTRALIZED ENTRY POINT for ALL kill credit, including:
      * StatService:RegisterElimination  (PvP kills)
      * StatService:RegisterMobKill      (monster / NPC kills)
      * Coin awards, XP awards, KillFeed, AddScore (team score)
      * Enchant / DoT cleanup on death

    HOW WEAPONS PARTICIPATE:
      Weapons (current and future) only need to TAG the Humanoid they damage
      with the player attacker. They do NOT call StatService and do NOT need
      any quest/achievement code of their own.

      The simplest tag is the standard attribute pattern already used across
      the codebase:
          humanoid:SetAttribute("lastDamagerUserId", player.UserId)
          humanoid:SetAttribute("lastDamagerName",   player.Name)
          humanoid:SetAttribute("lastDamageTime",    tick())

      Or call the global helper this script exposes:
          _G.RegisterCombatHit(humanoid, attackerPlayer)

      When the Humanoid dies, this script reads the last valid tag (within
      KILL_CREDIT_WINDOW seconds) and awards credit exactly once.

    DEDUPLICATION:
      A humanoid is processed at most once. Two attribute names are honored
      to stay backwards compatible with older scripts:
        * EliminationProcessed   (canonical, set by this module)
        * _killCredited          (legacy, may still be set by old code)

    MONSTER DETECTION (in priority order):
      1. Model has IsMonster == true attribute
      2. Model has CollectionService tag "Monster"
      3. Model is a descendant of workspace.Monsters
      4. Model has a Humanoid but is NOT a Player character
]]

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Workspace            = game:GetService("Workspace")
local ServerScriptService  = game:GetService("ServerScriptService")
local CollectionService    = game:GetService("CollectionService")

--------------------------------------------------------------------------------
-- Tunables
--------------------------------------------------------------------------------
local KILL_CREDIT_WINDOW = 15  -- seconds: ignore stale damage tags older than this
local KILL_POINTS        = 10  -- team score per elimination
local PVP_COIN_REWARD    = 5
local MOB_COIN_REWARD    = 1

--------------------------------------------------------------------------------
-- Remotes / BindableEvents
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Kill Card / Death Spectate remotes (inside ReplicatedStorage.Remotes folder)
--------------------------------------------------------------------------------
local RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not RemotesFolder then
    RemotesFolder = Instance.new("Folder")
    RemotesFolder.Name = "Remotes"
    RemotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteIn(parent, name, className)
    local ev = parent:FindFirstChild(name)
    if not ev then
        ev = Instance.new(className)
        ev.Name = name
        ev.Parent = parent
    end
    return ev
end

local DeathSpectateEvent  = ensureRemoteIn(RemotesFolder, "DeathSpectateEvent",  "RemoteEvent")
local RequestRevengeKill  = ensureRemoteIn(RemotesFolder, "RequestRevengeKill",  "RemoteEvent")

local AddScore = ServerScriptService:FindFirstChild("AddScore")
if not AddScore then
    AddScore = Instance.new("BindableEvent")
    AddScore.Name = "AddScore"
    AddScore.Parent = ServerScriptService
end

--------------------------------------------------------------------------------
-- Optional service integrations (lazy / pcall-protected)
--------------------------------------------------------------------------------
local XPModule
pcall(function()
    XPModule = require(ServerScriptService:WaitForChild("XPServiceModule", 10))
end)

local CurrencyService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

local StatService
pcall(function()
    StatService = require(ServerScriptService:WaitForChild("StatService", 10))
end)

local WeaponEnchantService
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponEnchantService")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantService = require(mod)
    end
end)

--------------------------------------------------------------------------------
-- Centralized combat tag helper (exposed for any current/future weapon)
--   _G.RegisterCombatHit(humanoid, attackerPlayer)
-- Stores the attacker on the humanoid via:
--   * lastDamagerUserId / lastDamagerName / lastDamageTime attributes
--   * "LastDamagedBy" ObjectValue child (per spec)
-- Self-hits are ignored so they cannot overwrite a real attacker tag.
--------------------------------------------------------------------------------
local function registerCombatHit(humanoid, attackerPlayer)
    if not humanoid or not humanoid:IsA("Humanoid") then return end
    if not attackerPlayer or not attackerPlayer:IsA("Player") then return end

    -- Ignore self-hits so a player damaging themselves does not credit themselves.
    local victimPlayer = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
    if victimPlayer == attackerPlayer then return end

    pcall(function()
        humanoid:SetAttribute("lastDamagerUserId", attackerPlayer.UserId)
        humanoid:SetAttribute("lastDamagerName",   attackerPlayer.Name)
        humanoid:SetAttribute("lastDamageTime",    tick())
    end)

    local objVal = humanoid:FindFirstChild("LastDamagedBy")
    if not objVal then
        objVal = Instance.new("ObjectValue")
        objVal.Name = "LastDamagedBy"
        objVal.Parent = humanoid
    end
    objVal.Value = attackerPlayer
end

_G.RegisterCombatHit = registerCombatHit

--------------------------------------------------------------------------------
-- NPC -> Player combat tag (used by mob attack scripts)
--   _G.RegisterMobCombatHit(victimHumanoid, npcModel)
-- Tags the player victim so we can show a kill card crediting the NPC.
-- Uses a parallel set of attributes so it does NOT clobber player kill credit.
--------------------------------------------------------------------------------
local function registerMobCombatHit(humanoid, npcModel)
    if not humanoid or not humanoid:IsA("Humanoid") then return end
    if not npcModel or not npcModel:IsA("Model") then return end
    -- Only tag player victims (mobs hitting mobs is irrelevant for kill cards)
    local victimPlayer = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
    if not victimPlayer then return end

    pcall(function()
        humanoid:SetAttribute("lastNpcAttackerName", npcModel.Name)
        humanoid:SetAttribute("lastNpcAttackerTime", tick())
        local npcId = npcModel:GetAttribute("NPCId")
        if npcId then humanoid:SetAttribute("lastNpcAttackerId", tostring(npcId)) end
    end)

    local objVal = humanoid:FindFirstChild("LastNpcAttacker")
    if not objVal then
        objVal = Instance.new("ObjectValue")
        objVal.Name = "LastNpcAttacker"
        objVal.Parent = humanoid
    end
    objVal.Value = npcModel
end

_G.RegisterMobCombatHit = registerMobCombatHit

--------------------------------------------------------------------------------
-- Monster detection (per spec)
--------------------------------------------------------------------------------
local function isMonsterModel(model)
    if not model or not model:IsA("Model") then return false end

    -- 1. Explicit IsMonster attribute
    if model:GetAttribute("IsMonster") == true then return true end

    -- 2. CollectionService "Monster" tag
    local ok, hasTag = pcall(function() return CollectionService:HasTag(model, "Monster") end)
    if ok and hasTag then return true end

    -- 3. Inside workspace.Monsters folder
    local monstersFolder = Workspace:FindFirstChild("Monsters")
    if monstersFolder and model:IsDescendantOf(monstersFolder) then return true end

    -- 4. Has a Humanoid but is NOT a player character
    if not Players:GetPlayerFromCharacter(model) then return true end

    return false
end

--------------------------------------------------------------------------------
-- Resolve the killer Player from the dead humanoid's tag.
-- Honors the KILL_CREDIT_WINDOW. Falls back to the standard "creator"
-- ObjectValue if no fresh attribute tag exists.
--------------------------------------------------------------------------------
local function resolveKiller(humanoid)
    -- Primary: LastDamagedBy ObjectValue + lastDamageTime attribute
    local damagerTime   = humanoid:GetAttribute("lastDamageTime")
    local damagerName   = humanoid:GetAttribute("lastDamagerName")
    local damagerUserId = humanoid:GetAttribute("lastDamagerUserId")

    if damagerTime and (tick() - damagerTime) <= KILL_CREDIT_WINDOW then
        local objVal = humanoid:FindFirstChild("LastDamagedBy")
        if objVal and objVal:IsA("ObjectValue")
            and objVal.Value and typeof(objVal.Value) == "Instance"
            and objVal.Value:IsA("Player") and objVal.Value.Parent == Players then
            return objVal.Value, objVal.Value.Name
        end
        if damagerUserId then
            local killer = Players:GetPlayerByUserId(damagerUserId)
            if killer then return killer, killer.Name end
        end
        if damagerName then
            local killer = Players:FindFirstChild(damagerName)
            if killer then return killer, killer.Name end
        end
    end

    -- Fallback: legacy "creator" ObjectValue (standard Roblox weapon pattern)
    local creator = humanoid:FindFirstChild("creator")
    if creator and creator:IsA("ObjectValue") and creator.Value
        and typeof(creator.Value) == "Instance" and creator.Value:IsA("Player") then
        return creator.Value, creator.Value.Name
    end

    return nil, damagerName
end

--------------------------------------------------------------------------------
-- Resolve NPC killer (model + name) from NPC tag attributes.
-- Honors KILL_CREDIT_WINDOW. Falls back to nil if stale or absent.
--------------------------------------------------------------------------------
local function resolveNpcKiller(humanoid)
    local t = humanoid:GetAttribute("lastNpcAttackerTime")
    if not t or (tick() - t) > KILL_CREDIT_WINDOW then return nil, nil end
    local objVal = humanoid:FindFirstChild("LastNpcAttacker")
    local model
    if objVal and objVal:IsA("ObjectValue") and objVal.Value
        and typeof(objVal.Value) == "Instance" and objVal.Value:IsA("Model")
        and objVal.Value.Parent then
        model = objVal.Value
    end
    local name = humanoid:GetAttribute("lastNpcAttackerName") or (model and model.Name) or "Monster"
    return model, name
end

--------------------------------------------------------------------------------
-- Session-only tracking (cleared on player removal)
--   victimKillCounts[victimUserId][killerKey] = number
--   playerKillStreak[killerUserId]            = number (resets on their death)
-- Killer key formats:
--   "Player_<UserId>"
--   "NPC_<NPCId or Name>"
--------------------------------------------------------------------------------
local victimKillCounts = {}  -- [victimUserId] = { [killerKey] = count }
local playerKillStreak = {}  -- [userId] = streak

local function bumpKillCount(victimUserId, killerKey)
    if not victimUserId or not killerKey then return 0 end
    local t = victimKillCounts[victimUserId]
    if not t then t = {}; victimKillCounts[victimUserId] = t end
    t[killerKey] = (t[killerKey] or 0) + 1
    return t[killerKey]
end

Players.PlayerRemoving:Connect(function(p)
    victimKillCounts[p.UserId] = nil
    playerKillStreak[p.UserId] = nil
end)

local function getPlayerLevel(player)
    if not player then return nil end
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        local lvl = ls:FindFirstChild("Level")
        if lvl and lvl:IsA("IntValue") then return lvl.Value end
    end
    return nil
end

local function npcKillerKey(npcModel, fallbackName)
    if npcModel then
        local id = npcModel:GetAttribute("NPCId")
        if id then return "NPC_" .. tostring(id) end
        return "NPC_" .. npcModel.Name
    end
    return "NPC_" .. tostring(fallbackName or "Unknown")
end

local function categorizeNpc(npcModel, npcName)
    if not npcModel then return "Wild Monster" end
    local threat = npcModel:GetAttribute("Threat")
    if threat and type(threat) == "string" then return threat end
    if npcModel:GetAttribute("IsBoss") == true then return "Boss" end
    if npcModel:GetAttribute("IsElite") == true then return "Elite" end
    return "Wild Monster"
end

local function fireKillCard(victimPlayer, payload)
    if not victimPlayer or not victimPlayer.Parent then return end
    -- Sanitize Instance fields: a destroyed/unparented Instance will throw when
    -- serialized for RemoteEvent transport, killing the FireClient call inside
    -- our pcall and silently dropping the kill card. Strip anything stale.
    if payload.killerModel ~= nil then
        local m = payload.killerModel
        if typeof(m) ~= "Instance" or not m.Parent then
            payload.killerModel = nil
        end
    end
    pcall(function() DeathSpectateEvent:FireClient(victimPlayer, payload) end)
end

--------------------------------------------------------------------------------
-- Death handler — single source of truth
--------------------------------------------------------------------------------
local function onHumanoidDied(humanoid, model)
    -- Dedup: process each death only once
    if humanoid:GetAttribute("EliminationProcessed") then return end
    if humanoid:GetAttribute("_killCredited") then
        -- Legacy flag from older code paths: still mark as processed and exit.
        humanoid:SetAttribute("EliminationProcessed", true)
        return
    end

    local killer, killerName = resolveKiller(humanoid)
    local victimPlayer = Players:GetPlayerFromCharacter(model)
    local victimName   = victimPlayer and victimPlayer.Name or (model and model.Name) or "Unknown"

    -- Always mark processed so re-entry can't double credit.
    humanoid:SetAttribute("EliminationProcessed", true)
    humanoid:SetAttribute("_killCredited", true)  -- legacy compatibility

    -- Cleanup any active enchant DoT/slow effects on this victim
    if WeaponEnchantService and WeaponEnchantService.CleanupTarget then
        pcall(function() WeaponEnchantService.CleanupTarget(humanoid) end)
    end

    --------------------------------------------------------------------------
    -- Kill Card payload (fires only to the victim player). Runs BEFORE any
    -- dedup early-returns above could ever apply (we are already past them),
    -- and BEFORE the credit-bail logic below, so the card fires even when the
    -- killer can't be credited (despawned attacker, environmental fall, etc).
    --------------------------------------------------------------------------
    if victimPlayer then
        -- Reset victim's own kill streak
        playerKillStreak[victimPlayer.UserId] = 0

        local payload
        if killer and killer ~= victimPlayer then
            local key = "Player_" .. tostring(killer.UserId)
            local count = bumpKillCount(victimPlayer.UserId, key)
            local killerChar = killer.Character
            if killerChar and not killerChar.Parent then killerChar = nil end
            payload = {
                killerKind                 = "Player",
                killerName                 = killer.Name,
                killerDisplayName          = killer.DisplayName or killer.Name,
                killerUserId               = killer.UserId,
                killerLevel                = getPlayerLevel(killer),
                killerStreak               = (playerKillStreak[killer.UserId] or 0) + 1, -- includes this kill
                killedByThisKillerCount    = count,
                killerModel                = killerChar,
                killerWeaponName           = humanoid:GetAttribute("lastDamagerWeapon"),
                deathMessage               = nil,
            }
        else
            local npcModel, npcName = resolveNpcKiller(humanoid)
            if npcName then
                local key = npcKillerKey(npcModel, npcName)
                local count = bumpKillCount(victimPlayer.UserId, key)
                if npcModel and not npcModel.Parent then npcModel = nil end
                payload = {
                    killerKind                 = "NPC",
                    killerName                 = npcName,
                    killerDisplayName          = npcName,
                    killerUserId               = nil,
                    killerLevel                = npcModel and npcModel:GetAttribute("Level") or nil,
                    killerStreak               = nil,
                    killedByThisKillerCount    = count,
                    killerModel                = npcModel,
                    killerCategory             = categorizeNpc(npcModel, npcName),
                    killerWeaponName           = nil,
                    deathMessage               = nil,
                }
            else
                payload = {
                    killerKind                 = "Unknown",
                    killerName                 = "Unknown",
                    killerDisplayName          = "Unknown",
                    killedByThisKillerCount    = 0,
                    deathMessage               = "You were defeated",
                }
            end
        end
        fireKillCard(victimPlayer, payload)
    end

    -- Bail if no valid player attacker
    if not killer then return end
    if killer == victimPlayer then return end                 -- self-kill guard
    if killerName and killerName == victimName then return end

    -- Determine victim category
    local isPlayerVictim  = victimPlayer ~= nil
    local isMonsterVictim = (not isPlayerVictim) and isMonsterModel(model)

    -- Award team score
    if killer.Team then
        pcall(function() AddScore:Fire(killer.Team.Name, KILL_POINTS) end)
    end

    -- Centralized stat events (feeds quests + achievements + scoreboard)
    if StatService then
        if isPlayerVictim then
            StatService:RegisterElimination(killer, victimPlayer)
        elseif isMonsterVictim then
            StatService:RegisterMobKill(killer, victimName)
        end
    end

    -- Bump killer's session streak (player victims only – mob kills don't gate streak)
    if isPlayerVictim then
        playerKillStreak[killer.UserId] = (playerKillStreak[killer.UserId] or 0) + 1
    end

    -- Coin reward
    local coinAward = 0
    if CurrencyService and CurrencyService.AddCoins then
        local base = isPlayerVictim and PVP_COIN_REWARD or MOB_COIN_REWARD
        local ok, result = pcall(function() return CurrencyService:AddCoins(killer, base, "elimination") end)
        coinAward = (ok and type(result) == "number") and result or base
    end

    -- Kill feed
    pcall(function() KillFeed:FireAllClients(killer.Name, victimName, coinAward) end)

    -- XP reward (include coinAward in metadata so XP popup can show coins)
    if XPModule and XPModule.AwardXP then
        if isPlayerVictim then
            pcall(function() XPModule.AwardXP(killer, "PlayerKill", nil, { coinAward = coinAward }) end)
        else
            local mobXP = 3
            pcall(function()
                if XPModule.GetMobXP then mobXP = XPModule.GetMobXP(victimName) end
            end)
            pcall(function() XPModule.AwardXP(killer, "MobKill", mobXP, { coinAward = coinAward }) end)
        end
    end
end

--------------------------------------------------------------------------------
-- Universal Humanoid hook (every player + every NPC, current and future)
--------------------------------------------------------------------------------
local tracked = setmetatable({}, { __mode = "k" })

local function hookHumanoid(humanoid)
    if tracked[humanoid] then return end
    tracked[humanoid] = true

    humanoid.Died:Connect(function()
        local model = humanoid.Parent
        if model and model:IsA("Model") then
            onHumanoidDied(humanoid, model)
        end
    end)
end

-- Hook player characters
local function onPlayerAdded(player)
    player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then hookHumanoid(hum) end
    end)
    if player.Character then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hookHumanoid(hum) end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Hook every existing Humanoid in the workspace
for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Humanoid") then hookHumanoid(desc) end
end

-- Hook every newly-spawned Humanoid anywhere in the workspace tree
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Humanoid") then hookHumanoid(desc) end
end)

--------------------------------------------------------------------------------
-- Revenge placeholder handler
--   Client fires RequestRevengeKill with the killer info from the kill card.
--   For now this is a NO-OP: it just logs.
--
--   FUTURE Robux Developer Product flow:
--     1. Add a Developer Product ID to a config (e.g. RevengeProducts.lua).
--     2. Client side: on Revenge button click, instead of FireServer here,
--        call MarketplaceService:PromptProductPurchase(player, REVENGE_PRODUCT_ID).
--     3. Server stores pendingRevengeTarget[player.UserId] = killerKey BEFORE prompt.
--     4. ProcessReceipt validates productId, re-resolves the killer target via
--        the stored key (Player_<id> or NPC_<id>), validates target still exists,
--        is not on the same team / not protected, and applies a kill or explosion.
--     5. Clear pendingRevengeTarget on success / failure.
--     6. Anti-abuse: cooldown per buyer; ignore if killer is gone; refund-friendly.
--------------------------------------------------------------------------------
local pendingRevengeTarget = {}  -- [userId] = { killerKind, killerKey, killerName, ts }

RequestRevengeKill.OnServerEvent:Connect(function(player, info)
    if typeof(info) ~= "table" then return end
    local killerKind = tostring(info.killerKind or "Unknown")
    local killerName = tostring(info.killerName or "Unknown")
    local killerKey
    if killerKind == "Player" and tonumber(info.killerUserId) then
        killerKey = "Player_" .. tostring(info.killerUserId)
    elseif killerKind == "NPC" then
        killerKey = "NPC_" .. (tostring(info.killerId or info.killerName or "Unknown"))
    else
        warn(string.format("[Revenge] Ignoring revenge request from %s (no valid killer)", player.Name))
        return
    end

    pendingRevengeTarget[player.UserId] = {
        killerKind = killerKind,
        killerKey  = killerKey,
        killerName = killerName,
        ts         = tick(),
    }

    warn(string.format("[Revenge] Placeholder requested by %s against %s (%s)",
        player.Name, killerName, killerKind))

    -- TODO: MarketplaceService:PromptProductPurchase(player, REVENGE_PRODUCT_ID)
    -- TODO: implement ProcessReceipt path that consumes pendingRevengeTarget[userId]
    --       and applies the kill/explosion to the resolved target.
end)

Players.PlayerRemoving:Connect(function(p)
    pendingRevengeTarget[p.UserId] = nil
end)
