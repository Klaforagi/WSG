--------------------------------------------------------------------------------
-- PotionStockServiceInit.server.lua  (ServerScriptService)
-- Creates the Potion Stall stock remotes and runs the server-wide refresh loop.
--
--  * GetPotionStockState (RemoteFunction)  -> per-player stock snapshot
--  * PotionStockRefreshed (RemoteEvent)    -> fired to all clients when a new
--                                             10-minute cycle begins
--
-- The refresh announcement reuses the existing event banner system
-- (ReplicatedStorage.FlagStatus, eventType "event") so it looks identical to
-- Coin Rush / Meteor Shower start popups.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PotionStockService = require(ServerScriptService:WaitForChild("PotionStockService"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataStoreService = game:GetService("DataStoreService")
local DATASTORE_NAME = "PotionStock_v1"
local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local REFRESH_BANNER_TEXT = "Potion Stall stock has refreshed!"
local REFRESH_BANNER_COLOR = Color3.fromRGB(255, 208, 95)

local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing
    end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local potionFolder = remotesFolder:FindFirstChild("Potions")
if not potionFolder then
    potionFolder = Instance.new("Folder")
    potionFolder.Name = "Potions"
    potionFolder.Parent = remotesFolder
end

local getPotionStockStateRF = ensureInstance(potionFolder, "RemoteFunction", "GetPotionStockState")
local potionStockRefreshedRE = ensureInstance(potionFolder, "RemoteEvent", "PotionStockRefreshed")

getPotionStockStateRF.OnServerInvoke = function(player)
    return PotionStockService:BuildState(player)
end

-- Register a DataSaveCoordinator section so per-player stock usage
-- is saved as part of the player's profile save flow. This is a fallback
-- persistence channel in addition to the dedicated DataStore updates in
-- PotionStockService, and helps prevent re-purchase on quick reconnects.
DataSaveCoordinator:RegisterSection({
    Name = "PotionStock",
    Priority = 40,
    Critical = false,
    Load = function(player)
        if not player then return { status = "failed" } end
        local key = "User_" .. tostring(player.UserId)
        local ok, result, err = DataStoreOps.Load(ds, key, "PotionStock/" .. key)
        if not ok then
            return { status = "failed", data = nil, reason = tostring(err or result) }
        end
        if type(result) ~= "table" then
            return { status = "new", data = {} }
        end
        -- Apply loaded data into memory for immediate effect
        PotionStockService:ApplyPersistedData(player, result)
        return { status = "existing", data = PotionStockService:GetPersistedData(player) }
    end,
    GetSaveData = function(player)
        return PotionStockService:GetPersistedData(player)
    end,
    Save = function(player, currentData, lastGoodData)
        if not player or type(currentData) ~= "table" then
            return { status = "failed", data = nil, reason = "invalid data" }
        end
        local key = "User_" .. tostring(player.UserId)
        local ok, res, err = DataStoreOps.Update(ds, key, "PotionStock/" .. key, function(stored)
            stored = type(stored) == "table" and stored or {}
            stored.cycle = currentData.cycle or PotionStockService:GetCurrentCycle()
            stored.purchases = type(currentData.purchases) == "table" and DataStoreOps.DeepCopy(currentData.purchases) or {}
            return stored
        end)
        if not ok then
            return { status = "failed", data = nil, reason = tostring(res or err) }
        end
        return { status = "existing", data = currentData }
    end,
    Cleanup = function(player)
        PotionStockService:ClearPlayer(player)
    end,
})

-- Ensure the section is loaded when players join so purchases persist across reconnects
Players.PlayerAdded:Connect(function(player)
    pcall(function()
        DataSaveCoordinator:LoadSection(player, "PotionStock")
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function() DataSaveCoordinator:LoadSection(player, "PotionStock") end)
end

-- Do not clear per-player usage on leave so purchases persist across rejoins.
-- Clearing here made players able to repurchase after reconnecting within
-- the same cycle. Persistence is handled by PotionStockService via DataStore.

--------------------------------------------------------------------------------
-- Refresh broadcast loop. Detects cycle changes and notifies all clients once
-- per 10-minute window. Initialising lastBroadcastCycle to the current cycle
-- prevents an announcement on server startup.
--------------------------------------------------------------------------------
local lastBroadcastCycle = PotionStockService:GetCurrentCycle()

task.spawn(function()
    while true do
        task.wait(1)

        local currentCycle = PotionStockService:GetCurrentCycle()
        if currentCycle ~= lastBroadcastCycle then
            lastBroadcastCycle = currentCycle
            local secondsRemaining = PotionStockService:GetSecondsUntilRefresh()

            pcall(function()
                potionStockRefreshedRE:FireAllClients({
                    cycle = currentCycle,
                    secondsRemaining = secondsRemaining,
                    refreshInterval = PotionStockService.RefreshInterval,
                    items = PotionStockService:GetCycleItems(),
                })
            end)

            -- Reuse the shared event banner so the popup matches event-start
            -- announcements. Only in-game clients with the banner UI loaded
            -- will display it, and it fires exactly once per cycle.
            local flagStatus = ReplicatedStorage:FindFirstChild("FlagStatus")
            if flagStatus and flagStatus:IsA("RemoteEvent") then
                pcall(function()
                    flagStatus:FireAllClients("event", REFRESH_BANNER_TEXT, nil, nil, REFRESH_BANNER_COLOR)
                end)
            end
        end
    end
end)

print("[PotionStockServiceInit] Potion Stall stock system initialized")
