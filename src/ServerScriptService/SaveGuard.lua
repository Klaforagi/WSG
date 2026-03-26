-- SaveGuard.lua
-- Shared module to prevent duplicate DataStore saves during shutdown.
-- Place in ServerScriptService. Require from any *Init script.
--
-- Usage:
--   local SaveGuard = require(script.Parent:WaitForChild("SaveGuard"))
--
--   Players.PlayerRemoving:Connect(function(player)
--       if SaveGuard:ClaimSave(player, "MyService") then
--           doSave(player)
--           SaveGuard:ReleaseSave(player, "MyService")
--       end
--   end)
--
--   game:BindToClose(function()
--       SaveGuard:BeginShutdown()
--       for _, p in Players:GetPlayers() do
--           if SaveGuard:ClaimSave(p, "MyService") then
--               task.spawn(function()
--                   doSave(p)
--                   SaveGuard:ReleaseSave(p, "MyService")
--               end)
--           end
--       end
--       SaveGuard:WaitForAll(5)
--   end)

local SaveGuard = {}

-- Internal state
local shuttingDown = false
local activeSaves = {}    -- [userId_serviceName] = true
local saveCount = 0       -- number of in-flight saves

--- Call this at the start of BindToClose to signal that shutdown is in progress.
function SaveGuard:BeginShutdown()
    shuttingDown = true
end

--- Returns true if the server is shutting down.
function SaveGuard:IsShuttingDown()
    return shuttingDown
end

--- Attempt to claim a save slot for a player+service combo.
--- Returns true if the save should proceed, false if it's already in progress
--- or was already completed during this shutdown cycle.
function SaveGuard:ClaimSave(player, serviceName)
    if not player then return false end
    local userId = tostring(player.UserId or player)
    local key = userId .. "_" .. (serviceName or "default")
    if activeSaves[key] then
        return false -- already saving or already saved
    end
    activeSaves[key] = true
    saveCount = saveCount + 1
    return true
end

--- Release a save slot after save completes (success or failure).
function SaveGuard:ReleaseSave(player, serviceName)
    if not player then return end
    local userId = tostring(player.UserId or player)
    local key = userId .. "_" .. (serviceName or "default")
    if activeSaves[key] then
        -- During shutdown, keep the key claimed so it won't be saved again.
        -- During normal play, release it so future saves can happen.
        if not shuttingDown then
            activeSaves[key] = nil
        end
        saveCount = math.max(0, saveCount - 1)
    end
end

--- Wait for all in-flight saves to complete, up to maxWait seconds.
function SaveGuard:WaitForAll(maxWait)
    maxWait = maxWait or 5
    local start = os.clock()
    while saveCount > 0 and (os.clock() - start) < maxWait do
        task.wait(0.1)
    end
    if saveCount > 0 then
        warn("[SaveGuard] Timed out with", saveCount, "saves still in flight")
    end
end

--- Debug: print the current state of SaveGuard.
function SaveGuard:DebugPrint(label, player, serviceName)
    local userId = player and tostring(player.UserId or player) or "?"
    print(string.format("[SaveGuard] %s | player=%s | service=%s | shuttingDown=%s | inFlight=%d",
        tostring(label), userId, tostring(serviceName), tostring(shuttingDown), saveCount))
end

return SaveGuard
