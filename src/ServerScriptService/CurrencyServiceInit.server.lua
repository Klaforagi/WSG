local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Require sibling ModuleScript `CurrencyService` under ServerScriptService.
local SSS = game:GetService("ServerScriptService")
local moduleInst = SSS:FindFirstChild("CurrencyService")
if not moduleInst then
    moduleInst = SSS:WaitForChild("CurrencyService", 10)
end
if not moduleInst or not moduleInst:IsA("ModuleScript") then
    warn("CurrencyServiceInit: CurrencyService ModuleScript not found; aborting")
    return
end
local CurrencyService = require(moduleInst)

-- Utility: create leaderstats folder and Coins IntValue for a player
Players.PlayerAdded:Connect(function(player)
    -- Load (with retries inside CurrencyService)
    local coins = 0
    local ok, amt = pcall(function()
        return CurrencyService:LoadForPlayer(player)
    end)
    if ok and type(amt) == "number" then
        coins = amt
    else
        warn("CurrencyServiceInit: failed to load for ", tostring(player.Name), "; defaulting to 0")
    end

    -- ensure the module's in-memory table is set and notify the client via RemoteEvent
    CurrencyService:SetCoins(player, coins)
end)

Players.PlayerRemoving:Connect(function(player)
    -- save and cleanup
    local ok, err = pcall(function()
        CurrencyService:SaveForPlayer(player)
    end)
    if not ok then
        warn("CurrencyServiceInit: SaveForPlayer error for ", tostring(player.Name), err)
    end
    CurrencyService:RemovePlayer(player)
end)

-- BindToClose: attempt to save all players
if RunService:IsServer() then
    game:BindToClose(function()
        local ok, err = pcall(function()
            CurrencyService:SaveAll()
        end)
        if not ok then
            warn("CurrencyServiceInit: SaveAll on shutdown failed:", tostring(err))
        end
    end)
end
