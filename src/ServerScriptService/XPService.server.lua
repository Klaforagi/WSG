-- XPService.server.lua
-- Server-authoritative XP/Level system with DataStore saving and RemoteEvent notifications.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local XPConfig = require(ReplicatedStorage:WaitForChild("XPConfig"))
local XPFormula = require(ReplicatedStorage:WaitForChild("XPFormula"))
local XPModule = require(script.Parent:WaitForChild("XPServiceModule"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

local BoostService
local function getBoostService()
    if BoostService then return BoostService end
    pcall(function()
        local mod = script.Parent:FindFirstChild("BoostService")
        if mod and mod:IsA("ModuleScript") then
            BoostService = require(mod)
        end
    end)
    return BoostService
end

-- DataStore
local DS = DataStoreService:GetDataStore("WSG_XP_v1")

-- Remote event names
local REMOTE_NAMES = {
    Update = "XP_Update",    -- payload: {playerUserId, newLevel, xp, xpToNext, delta, reason}
    Popup  = "XP_Popup",     -- payload: {playerUserId, delta, reason}
    Level  = "XP_LevelUp",   -- payload: {playerUserId, oldLevel, newLevel}
}

-- Ensure remotes exist in ReplicatedStorage (create under ReplicatedStorage.Remotes)
local function ensureRemotes()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotesFolder then
        remotesFolder = Instance.new("Folder")
        remotesFolder.Name = "Remotes"
        remotesFolder.Parent = ReplicatedStorage
    end

    for _, name in pairs(REMOTE_NAMES) do
        local existing = remotesFolder:FindFirstChild(name)
        if not existing then
            local re = Instance.new("RemoteEvent")
            re.Name = name
            re.Parent = remotesFolder
        end
    end
end

ensureRemotes()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local XP_Update  = Remotes:WaitForChild(REMOTE_NAMES.Update)
local XP_Popup   = Remotes:WaitForChild(REMOTE_NAMES.Popup)
local XP_LevelUp = Remotes:WaitForChild(REMOTE_NAMES.Level)

-- In-memory store for quick access (server authoritative)
-- structure: data[player.UserId] = {Level = int, XP = int, TotalXP = int}
local data = {}
local xpRegistered = false
local updateLeaderstats

-- Helper: get required xp for level (use XPFormula)
local function GetXPRequiredForLevel(level)
    return XPFormula.GetXPRequiredForLevel(level)
end

-- Load/save helpers
local function normalizeXPData(rawData)
    rawData = type(rawData) == "table" and rawData or {}
    return {
        Level = math.max(1, math.floor(tonumber(rawData.Level) or 1)),
        XP = math.max(0, math.floor(tonumber(rawData.XP) or 0)),
        TotalXP = math.max(0, math.floor(tonumber(rawData.TotalXP) or 0)),
    }
end

local function applyXPEntry(player, entry)
    entry = normalizeXPData(entry)
    data[player.UserId] = entry

    local xpToNext = GetXPRequiredForLevel(entry.Level)
    pcall(function()
        player:SetAttribute("Level", entry.Level)
        player:SetAttribute("XP", entry.XP)
        player:SetAttribute("XPToNext", xpToNext)
        player:SetAttribute("TotalXP", entry.TotalXP)
    end)

    updateLeaderstats(player, entry.Level)
    pcall(function()
        XP_Update:FireClient(player, { playerUserId = player.UserId, newLevel = entry.Level, xp = entry.XP, xpToNext = xpToNext, delta = 0, reason = "Init" })
    end)
end

local function loadPlayer(userId)
    local key = tostring(userId)
    local ok, result, err = DataStoreOps.Load(DS, key, "XP/" .. key)
    if not ok then
        warn("[XPService] DataStore unavailable for", userId, "— using temporary defaults and blocking saves")
        return {
            status = "failed",
            data = normalizeXPData(nil),
            reason = err,
        }
    end

    if type(result) == "table" then
        local entry = normalizeXPData(result)
        print("[XPService] Loaded saved data for", userId, "— Level:", entry.Level, "XP:", entry.XP)
        return {
            status = "existing",
            data = entry,
        }
    end

    print("[XPService] No saved data for", userId, "— starting fresh")
    return {
        status = "new",
        data = normalizeXPData(nil),
    }
end

local function savePlayer(player, payload, lastGoodData)
    if not player then return false, "missing player" end
    local userId = player.UserId
    local key = tostring(userId)
    payload = normalizeXPData(payload or data[userId])
    lastGoodData = normalizeXPData(lastGoodData)

    local ok, _, err = DataStoreOps.Update(DS, key, "XP/" .. key, function(oldData)
        local stored = normalizeXPData(oldData)
        if (stored.Level or 1) > 1 and (payload.Level or 1) <= 1 then
            warn("[XPService] suspected level wipe blocked for", userId)
            return oldData
        end
        if (stored.TotalXP or 0) > 0 and (payload.TotalXP or 0) == 0 and (lastGoodData.TotalXP or 0) > 0 then
            warn("[XPService] suspected TotalXP wipe blocked for", userId)
            return oldData
        end
        return payload
    end)

    if not ok then
        warn("XPService: failed to save data for", userId)
        return false, err
    end
    return true
end

-- Public getter
local function GetPlayerData(player)
    if not player then return nil end
    return data[player.UserId]
end

local function validateXP(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end

    if (tonumber(lastGoodData.Level) or 1) > 1 and (tonumber(currentData.Level) or 1) <= 1 then
        return {
            suspicious = true,
            severity = "severe",
            reason = "level dropped back to 1",
        }
    end

    if (tonumber(lastGoodData.TotalXP) or 0) > 0 and (tonumber(currentData.TotalXP) or 0) == 0 then
        return {
            suspicious = true,
            severity = "severe",
            reason = "TotalXP reset to 0",
        }
    end

    return nil
end

local function registerXPSection()
    if xpRegistered then
        return
    end
    xpRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "XP",
        Priority = 15,
        Critical = true,
        Load = function(player)
            local result = loadPlayer(player.UserId)
            applyXPEntry(player, result.data)
            return result
        end,
        GetSaveData = function(player)
            return DataStoreOps.DeepCopy(data[player.UserId])
        end,
        Save = function(player, currentData, lastGoodData)
            return savePlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            data[player.UserId] = nil
        end,
        Validate = validateXP,
    })
end

-- Load MobSettings so we can resolve per-mob XP values
local MobSettings
if ReplicatedStorage:FindFirstChild("MobSettings") then
    MobSettings = require(ReplicatedStorage:WaitForChild("MobSettings"))
end

--- Returns the XP reward for killing a mob of the given template name.
--- Falls back to XPConfig.DefaultMobXP if the mob has no xp_reward field.
local function GetMobXP(mobName)
    if MobSettings and MobSettings.presets then
        local cfg = MobSettings.presets[mobName]
        if cfg and type(cfg.xp_reward) == "number" then
            return cfg.xp_reward
        end
    end
    return XPConfig.DefaultMobXP or 3
end

-- Helper: update the Level value inside leaderstats
updateLeaderstats = function(player, level)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return end
    local lv = ls:FindFirstChild("Level")
    if lv then lv.Value = level end
end

-- AwardXP core function
local function AwardXP(player, reason, amountOverride, metadata)
    if not player then
        warn("[XPService] AwardXP called with nil player")
        return false
    end
    if not player:IsA("Player") then
        warn("[XPService] AwardXP called with non-Player:", tostring(player))
        return false
    end

    local entry = data[player.UserId]
    if not entry then
        warn("[XPService] No cached data for", player.Name, "— loading now")
        entry = loadPlayer(player.UserId)
        data[player.UserId] = entry
    end

    local reasonKey = reason or ""
    local base = XPConfig.Reasons[reasonKey]
    local amount = 0
    if amountOverride and type(amountOverride) == "number" then
        amount = math.floor(amountOverride)
    elseif base and type(base) == "number" then
        amount = math.floor(base)
    else
        warn("[XPService] Unknown reason '" .. tostring(reasonKey) .. "' and no amountOverride — skipping")
        return false
    end

    if amount <= 0 then return false end

    -- Apply optional XP boost multiplier (2x XP, etc.)
    local boostSvc = getBoostService()
    if boostSvc and type(boostSvc.GetXPMultiplier) == "function" then
        local mult = tonumber(boostSvc:GetXPMultiplier(player)) or 1
        mult = math.max(1, mult)
        amount = math.floor(amount * mult)
    end

    if amount <= 0 then return false end

    print("[XPService] Awarding", amount, "XP to", player.Name, "for", reasonKey)

    local oldLevel = entry.Level
    local oldXP = entry.XP

    -- Add XP
    entry.XP = entry.XP + amount
    entry.TotalXP = (entry.TotalXP or 0) + amount

    local delta = amount
    -- Handle level-ups (may level up multiple times)
    local leveled = false
    while true do
        local xpToNext = GetXPRequiredForLevel(entry.Level)
        if entry.XP >= xpToNext then
            entry.XP = entry.XP - xpToNext
            entry.Level = entry.Level + 1
            leveled = true
            -- notify clients of level up
            pcall(function()
                XP_LevelUp:FireAllClients({ playerUserId = player.UserId, oldLevel = entry.Level - 1, newLevel = entry.Level })
            end)
        else
            break
        end
    end

    -- compute xpToNext for current level
    local xpToNext = GetXPRequiredForLevel(entry.Level)

    -- set Player Attributes for debugging/inspection
    pcall(function()
        player:SetAttribute("Level", entry.Level)
        player:SetAttribute("XP", entry.XP)
        player:SetAttribute("XPToNext", xpToNext)
        player:SetAttribute("TotalXP", entry.TotalXP)
    end)

    -- keep leaderboard in sync
    updateLeaderstats(player, entry.Level)

    -- notify the client with structured payload
    local payload = {
        playerUserId = player.UserId,
        newLevel = entry.Level,
        xp = entry.XP,
        xpToNext = xpToNext,
        delta = delta,
        reason = reasonKey,
    }
    -- include optional coinAward from metadata so client can show coins with XP popup
    local popup = { playerUserId = player.UserId, delta = delta, reason = reasonKey }
    if metadata and metadata.coinAward and type(metadata.coinAward) == "number" then
        popup.coin = metadata.coinAward
    end
    print("[XPService] Popup payload for", player.Name, "— XP:", delta, "Coin:", popup.coin or 0, "Reason:", reasonKey)
    pcall(function()
        XP_Update:FireClient(player, payload)
        XP_Popup:FireClient(player, popup)
    end)

    DataSaveCoordinator:MarkDirty(player, "XP", reasonKey)

    return true
end

-- Hook Module exports so other server scripts can require and call AwardXP
XPModule.AwardXP = AwardXP
XPModule.GetPlayerData = GetPlayerData
XPModule.GetMobXP = GetMobXP
XPModule._ready = true
print("[XPService] Module exports ready")

-- Player lifecycle: load and save
Players.PlayerAdded:Connect(function(player)
    -- Create leaderstats folder so Level shows on the in-game leaderboard
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls.Parent = player

    local levelStat = Instance.new("IntValue")
    levelStat.Name = "Level"
    levelStat.Value = 1
    levelStat.Parent = ls

    DataSaveCoordinator:LoadSection(player, "XP")
end)

registerXPSection()

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        if player:FindFirstChild("leaderstats") == nil then
            local ls = Instance.new("Folder")
            ls.Name = "leaderstats"
            ls.Parent = player

            local levelStat = Instance.new("IntValue")
            levelStat.Name = "Level"
            levelStat.Value = 1
            levelStat.Parent = ls
        end
        DataSaveCoordinator:LoadSection(player, "XP")
    end)
end

-- Expose a BindableFunction for scripts that prefer event binding (optional)
local bindableName = "XPService_AwardBindable"
local bs = script:FindFirstChild(bindableName)
if not bs then
    bs = Instance.new("BindableFunction")
    bs.Name = bindableName
    bs.Parent = script
end
bs.OnInvoke = function(player, reason, amountOverride, metadata)
    return AwardXP(player, reason, amountOverride, metadata)
end

print("XPService: initialized")
