--------------------------------------------------------------------------------
-- EffectsService.server.lua
-- Server-side logic for the cosmetic Effects system: purchase, equip, persist.
--
-- Remotes (under ReplicatedStorage.Remotes.Effects):
--   PurchaseEffect       (RF client→server)  buy an effect with coins
--   GetOwnedEffects      (RF client→server)  fetch list of owned effect ids
--   EquipEffect          (RE client→server)  equip an owned effect by subType
--   GetEquippedEffects   (RF client→server)  fetch equipped effects table
--   EquippedEffectsChanged (RE server→client) push after equip changes
--------------------------------------------------------------------------------

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")

local DEBUG = true
local function dprint(...)
    if DEBUG then print("[Effects]", ...) end
end

dprint("initializing")

-- ── Shared config ──────────────────────────────────────────────────────────
local EffectDefs = nil
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    local mod = sideUI and sideUI:FindFirstChild("EffectDefs")
    if mod and mod:IsA("ModuleScript") then EffectDefs = require(mod) end
end)
if not EffectDefs then
    warn("[Effects] EffectDefs not found – effects system disabled")
    return
end

-- Log all registered effects
for _, def in ipairs(EffectDefs.GetAll()) do
    dprint("Registered", def.DisplayName)
end

-- ── CurrencyService ────────────────────────────────────────────────────────
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then CurrencyService = require(mod) end
end)

-- ── DataStore ──────────────────────────────────────────────────────────────
local DATASTORE_NAME = "Effects_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5
local ds = nil
pcall(function() ds = DataStoreService:GetDataStore(DATASTORE_NAME) end)

-- ── Helper ─────────────────────────────────────────────────────────────────
local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA(className) then return existing end
        existing:Destroy()
    end
    local inst = Instance.new(className)
    inst.Name = name
    inst.Parent = parent
    return inst
end

-- ── Remote setup ───────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local effectsFolder = ensureInstance(remotesFolder, "Folder", "Effects")

local purchaseEffectRF      = ensureInstance(effectsFolder, "RemoteFunction", "PurchaseEffect")
local getOwnedRF            = ensureInstance(effectsFolder, "RemoteFunction", "GetOwnedEffects")
local equipEffectRE         = ensureInstance(effectsFolder, "RemoteEvent",    "EquipEffect")
local getEquippedRF         = ensureInstance(effectsFolder, "RemoteFunction", "GetEquippedEffects")
local equippedChangedRE     = ensureInstance(effectsFolder, "RemoteEvent",    "EquippedEffectsChanged")

dprint("Remotes created")

-- ── Per-player state ───────────────────────────────────────────────────────
-- playerData[player] = { owned = { [effectId] = true }, equipped = { [subType] = effectId } }
local playerData = {}

-- ── Persistence helpers ────────────────────────────────────────────────────
local function dsKey(player)
    return "User_" .. tostring(player.UserId)
end

local function loadData(player)
    if not ds then return { owned = {}, equipped = {} } end
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function() return ds:GetAsync(dsKey(player)) end)
        if success then break end
        warn("[Effects] GetAsync fail attempt", i, result)
        task.wait(RETRY_DELAY * i)
    end
    if success and type(result) == "table" then
        -- Parse owned
        local owned = {}
        if type(result.owned) == "table" then
            for k, v in pairs(result.owned) do
                if type(k) == "number" and type(v) == "string" then
                    owned[v] = true
                elseif type(v) == "boolean" then
                    owned[k] = v
                end
            end
        end
        -- Parse equipped (subType -> effectId)
        local equipped = {}
        if type(result.equipped) == "table" then
            for subType, effectId in pairs(result.equipped) do
                if type(subType) == "string" and type(effectId) == "string" then
                    equipped[subType] = effectId
                end
            end
        end
        -- Grant free items
        for _, def in ipairs(EffectDefs.GetAll()) do
            if def.IsFree then owned[def.Id] = true end
        end
        return { owned = owned, equipped = equipped }
    end
    -- Fresh data: grant free items
    local owned = {}
    for _, def in ipairs(EffectDefs.GetAll()) do
        if def.IsFree then owned[def.Id] = true end
    end
    return { owned = owned, equipped = {} }
end

local function saveData(player)
    if not ds then return end
    local data = playerData[player]
    if not data then return end
    local ownedArr = {}
    for id, v in pairs(data.owned) do
        if v then table.insert(ownedArr, id) end
    end
    local payload = { owned = ownedArr, equipped = data.equipped }
    for i = 1, RETRIES do
        local ok, err = pcall(function() ds:SetAsync(dsKey(player), payload) end)
        if ok then
            dprint("saved data for", player.Name)
            return
        end
        warn("[Effects] SetAsync fail attempt", i, err)
        task.wait(RETRY_DELAY * i)
    end
end

local function getOrCreateData(player)
    if not playerData[player] then
        playerData[player] = loadData(player)
    end
    return playerData[player]
end

-- ── Owned / Equipped helpers ───────────────────────────────────────────────
local function isOwned(player, effectId)
    local data = getOrCreateData(player)
    return data.owned[effectId] == true
end

local function getOwnedList(player)
    local data = getOrCreateData(player)
    local list = {}
    for id, v in pairs(data.owned) do
        if v then table.insert(list, id) end
    end
    return list
end

local function getEquippedTable(player)
    local data = getOrCreateData(player)
    return data.equipped or {}
end

local function getEquippedForSubType(player, subType)
    local data = getOrCreateData(player)
    return data.equipped[subType]
end

local function pushEquippedToClient(player)
    local equipped = getEquippedTable(player)
    pcall(function() equippedChangedRE:FireClient(player, equipped) end)
end

-- The default trail every player should have equipped if they haven't chosen one
local DEFAULT_TRAIL_ID = "DefaultTrail"

-- Sync equipped dash trail to player attribute (so DashServiceInit can read it)
local function syncDashTrailAttribute(player)
    local data = getOrCreateData(player)
    local trailId = data.equipped.DashTrail
    -- Fall back to the default white trail if nothing is equipped
    if not trailId or trailId == "" then
        trailId = DEFAULT_TRAIL_ID
        data.equipped.DashTrail = trailId
        dprint(player.Name, "had no equipped trail – set default:", trailId)
    end
    player:SetAttribute("EquippedDashTrail", trailId)
    dprint(player.Name, "synced EquippedDashTrail attribute:", trailId)
end

-- ── Player lifecycle ───────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    local data = getOrCreateData(player)

    -- Ensure DefaultTrail is owned (it's free)
    if not data.owned[DEFAULT_TRAIL_ID] then
        data.owned[DEFAULT_TRAIL_ID] = true
        dprint(player.Name, "granted free DefaultTrail")
    end

    -- Auto-equip the default white trail if nothing is equipped
    if not data.equipped.DashTrail or data.equipped.DashTrail == "" then
        data.equipped.DashTrail = DEFAULT_TRAIL_ID
        dprint(player.Name, "auto-equipped DefaultTrail (first join or missing)")
    end

    syncDashTrailAttribute(player)
    dprint(player.Name, "joined – equipped DashTrail:", data.equipped.DashTrail)
    dprint(player.Name, "loaded trail from data:", data.equipped.DashTrail)
    if data.equipped.DashTrail == "RainbowTrail" then
        dprint(player.Name, "Rainbow Trail loaded from saved data")
    end
end)

local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))

Players.PlayerRemoving:Connect(function(player)
    if SaveGuard:ClaimSave(player, "Effects") then
        saveData(player)
        SaveGuard:ReleaseSave(player, "Effects")
    end
    playerData[player] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        local data = getOrCreateData(p)
        if not data.owned[DEFAULT_TRAIL_ID] then
            data.owned[DEFAULT_TRAIL_ID] = true
        end
        if not data.equipped.DashTrail or data.equipped.DashTrail == "" then
            data.equipped.DashTrail = DEFAULT_TRAIL_ID
            dprint(p.Name, "auto-equipped DefaultTrail (late init)")
        end
        syncDashTrailAttribute(p)
    end)
end

game:BindToClose(function()
    SaveGuard:BeginShutdown()
    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if SaveGuard:ClaimSave(p, "Effects") then
                saveData(p)
                SaveGuard:ReleaseSave(p, "Effects")
            end
        end)
    end
    SaveGuard:WaitForAll(5)
end)

-- ── Remote handlers ────────────────────────────────────────────────────────

getOwnedRF.OnServerInvoke = function(player)
    return getOwnedList(player)
end

getEquippedRF.OnServerInvoke = function(player)
    return getEquippedTable(player)
end

purchaseEffectRF.OnServerInvoke = function(player, effectId)
    if type(effectId) ~= "string" or #effectId == 0 then return false, 0, "invalid_id" end

    local def = EffectDefs.GetById(effectId)
    if not def then return false, 0, "unknown_effect" end

    if isOwned(player, effectId) then
        local bal = CurrencyService and CurrencyService:GetCoins(player) or 0
        return false, bal, "already_owned"
    end

    local price = def.CoinCost or 0
    if price > 0 then
        if not CurrencyService then return false, 0, "no_currency" end
        local balance = CurrencyService:GetCoins(player)
        if balance < price then return false, balance, "not_enough_coins" end
        CurrencyService:SetCoins(player, balance - price)
    end

    local data = getOrCreateData(player)
    data.owned[effectId] = true
    dprint("Purchased", def.DisplayName, "for", player.Name)

    task.spawn(function() saveData(player) end)

    local newBal = CurrencyService and CurrencyService:GetCoins(player) or 0
    return true, newBal, "ok"
end

equipEffectRE.OnServerEvent:Connect(function(player, effectId, subType)
    if type(effectId) ~= "string" or #effectId == 0 then return end
    if type(subType) ~= "string" or #subType == 0 then return end

    -- Validate the effect exists and matches the subType
    local def = EffectDefs.GetById(effectId)
    if not def then return end
    if def.SubType ~= subType then return end

    -- Must own it (free items are auto-owned)
    if not isOwned(player, effectId) then return end

    local data = getOrCreateData(player)
    data.equipped[subType] = effectId
    dprint("Equipped", subType, "=", effectId, "for", player.Name)

    -- Sync attribute for DashServiceInit to read
    if subType == "DashTrail" then
        syncDashTrailAttribute(player)
    end

    task.spawn(function() saveData(player) end)
    pushEquippedToClient(player)
end)

--------------------------------------------------------------------------------
-- BINDABLE API  (server-to-server, used by SalvageShopService)
--------------------------------------------------------------------------------
do
    local ServerScriptService = game:GetService("ServerScriptService")

    -- CheckEffectOwnership(player, effectId) -> bool
    local checkBF = Instance.new("BindableFunction")
    checkBF.Name = "CheckEffectOwnership"
    checkBF.Parent = ServerScriptService
    checkBF.OnInvoke = function(player, effectId)
        if not player or type(effectId) ~= "string" then return false end
        return isOwned(player, effectId)
    end

    -- GrantEffect(player, effectId) -> bool
    local grantBF = Instance.new("BindableFunction")
    grantBF.Name = "GrantEffect"
    grantBF.Parent = ServerScriptService
    grantBF.OnInvoke = function(player, effectId)
        if not player or type(effectId) ~= "string" then return false end
        if isOwned(player, effectId) then return true end -- already owned, success
        local def = EffectDefs.GetById(effectId)
        if not def then
            warn("[EffectsService] GrantEffect: unknown effectId:", effectId)
            return false
        end
        local data = getOrCreateData(player)
        data.owned[effectId] = true
        dprint("Granted effect", effectId, "to", player.Name, "(via BindableFunction)")
        task.spawn(function() saveData(player) end)
        return true
    end

    dprint("BindableFunction API registered (CheckEffectOwnership, GrantEffect)")

    -- GetEffectOwnedCount(player) -> number (excludes DefaultTrail)
    local countBF = Instance.new("BindableFunction")
    countBF.Name = "GetEffectOwnedCount"
    countBF.Parent = ServerScriptService
    countBF.OnInvoke = function(player)
        if not player then return 0 end
        local list = getOwnedList(player)
        local count = 0
        for _, id in ipairs(list) do
            if id ~= "DefaultTrail" then count = count + 1 end
        end
        return count
    end
end

dprint("fully initialized")
