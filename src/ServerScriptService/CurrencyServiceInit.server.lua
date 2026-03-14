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

-- Utility: load coins for a player
local function onPlayerAdded(player)
    -- guard against double-load if we process an already-connected player below
    if player:GetAttribute("_coinsLoaded") then return end
    player:SetAttribute("_coinsLoaded", true)
end

Players.PlayerAdded:Connect(function(player)
    onPlayerAdded(player)
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

-- Handle players who connected before the PlayerAdded signal was hooked
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        if player:GetAttribute("_coinsLoaded") then return end
        player:SetAttribute("_coinsLoaded", true)
        local coins = 0
        local ok, amt = pcall(function()
            return CurrencyService:LoadForPlayer(player)
        end)
        if ok and type(amt) == "number" then
            coins = amt
        end
        CurrencyService:SetCoins(player, coins)
    end)
end

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
