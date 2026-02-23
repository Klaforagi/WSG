-- XPService.server.lua
-- Server-authoritative XP/Level system with DataStore saving and RemoteEvent notifications.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local XPConfig = require(ReplicatedStorage:WaitForChild("XPConfig"))
local XPFormula = require(ReplicatedStorage:WaitForChild("XPFormula"))
local XPModule = require(script.Parent:WaitForChild("XPServiceModule"))

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

-- Helper: get required xp for level (use XPFormula)
local function GetXPRequiredForLevel(level)
    return XPFormula.GetXPRequiredForLevel(level)
end

-- Load/save helpers
local function loadPlayer(userId)
    local key = tostring(userId)
    local ok, res = pcall(function()
        return DS:GetAsync(key)
    end)
    if ok and type(res) == "table" then
        local lvl = tonumber(res.Level) or 1
        local xp  = tonumber(res.XP) or 0
        local total = tonumber(res.TotalXP) or 0
        print("[XPService] Loaded saved data for", userId, "— Level:", lvl, "XP:", xp)
        return {Level = lvl, XP = xp, TotalXP = total}
    else
        if not ok then
            warn("[XPService] DataStore unavailable for", userId, "— using defaults (XP will work but won't persist)")
        else
            print("[XPService] No saved data for", userId, "— starting fresh")
        end
        return {Level = 1, XP = 0, TotalXP = 0}
    end
end

local function savePlayer(userId)
    local p = data[userId]
    if not p then return false end
    local key = tostring(userId)
    local payload = { Level = p.Level, XP = p.XP, TotalXP = p.TotalXP }
    local tries = 0
    while tries < 3 do
        local ok, err = pcall(function()
            DS:SetAsync(key, payload)
        end)
        if ok then return true end
        tries = tries + 1
        task.wait(1 + tries * 0.5)
    end
    warn("XPService: failed to save data for", userId)
    return false
end

-- Public getter
local function GetPlayerData(player)
    if not player then return nil end
    return data[player.UserId]
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
local function updateLeaderstats(player, level)
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
            -- save on level up (non-blocking so callers aren't stalled by DataStore)
            task.spawn(function() savePlayer(player.UserId) end)
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
    pcall(function()
        XP_Update:FireClient(player, payload)
        XP_Popup:FireClient(player, { playerUserId = player.UserId, delta = delta, reason = reasonKey })
    end)

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
    local entry = loadPlayer(player.UserId)
    data[player.UserId] = entry

    -- Create leaderstats folder so Level shows on the in-game leaderboard
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls.Parent = player

    local levelStat = Instance.new("IntValue")
    levelStat.Name = "Level"
    levelStat.Value = entry.Level
    levelStat.Parent = ls

    -- set Attributes
    local xpToNext = GetXPRequiredForLevel(entry.Level)
    pcall(function()
        player:SetAttribute("Level", entry.Level)
        player:SetAttribute("XP", entry.XP)
        player:SetAttribute("XPToNext", xpToNext)
        player:SetAttribute("TotalXP", entry.TotalXP)
    end)
    -- send initial update
    pcall(function()
        XP_Update:FireClient(player, { playerUserId = player.UserId, newLevel = entry.Level, xp = entry.XP, xpToNext = xpToNext, delta = 0, reason = "Init" })
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    savePlayer(player.UserId)
    data[player.UserId] = nil
end)

-- Periodic autosave
task.spawn(function()
    while true do
        task.wait(120)
        for userId, _ in pairs(data) do
            pcall(function() savePlayer(userId) end)
        end
    end
end)

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
