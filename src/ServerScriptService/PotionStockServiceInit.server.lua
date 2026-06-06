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

local REFRESH_BANNER_TEXT = "Potion Stall gold stock has refreshed!"
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

-- Free per-player usage when they leave (stock is session-only by design).
Players.PlayerRemoving:Connect(function(player)
    PotionStockService:ClearPlayer(player)
end)

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
