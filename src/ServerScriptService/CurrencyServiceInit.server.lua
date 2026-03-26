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

    -- PREMIUM CRATE / KEY SYSTEM  – Load Keys
    local keys = 0
    local ok2, keyAmt = pcall(function()
        return CurrencyService:LoadKeysForPlayer(player)
    end)
    if ok2 and type(keyAmt) == "number" then
        keys = keyAmt
    else
        warn("CurrencyServiceInit: failed to load keys for ", tostring(player.Name), "; defaulting to 0")
    end
    CurrencyService:SetKeys(player, keys)

    -- SALVAGE SYSTEM  – Load Salvage
    local salvage = 0
    local ok3, salvageAmt = pcall(function()
        return CurrencyService:LoadSalvageForPlayer(player)
    end)
    if ok3 and type(salvageAmt) == "number" then
        salvage = salvageAmt
    else
        warn("CurrencyServiceInit: failed to load salvage for ", tostring(player.Name), "; defaulting to 0")
    end
    CurrencyService:SetSalvage(player, salvage)
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

        -- PREMIUM CRATE / KEY SYSTEM  – Load Keys for late-join players
        local keys = 0
        local ok2, keyAmt = pcall(function()
            return CurrencyService:LoadKeysForPlayer(player)
        end)
        if ok2 and type(keyAmt) == "number" then
            keys = keyAmt
        end
        CurrencyService:SetKeys(player, keys)

        -- SALVAGE SYSTEM  – Load Salvage for late-join players
        local salvage = 0
        local ok3, salvageAmt = pcall(function()
            return CurrencyService:LoadSalvageForPlayer(player)
        end)
        if ok3 and type(salvageAmt) == "number" then
            salvage = salvageAmt
        end
        CurrencyService:SetSalvage(player, salvage)
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
    -- PREMIUM CRATE / KEY SYSTEM  – Save Keys on leave
    local ok2, err2 = pcall(function()
        CurrencyService:SaveKeysForPlayer(player)
    end)
    if not ok2 then
        warn("CurrencyServiceInit: SaveKeysForPlayer error for ", tostring(player.Name), err2)
    end
    -- SALVAGE SYSTEM  – Save Salvage on leave
    local ok3, err3 = pcall(function()
        CurrencyService:SaveSalvageForPlayer(player)
    end)
    if not ok3 then
        warn("CurrencyServiceInit: SaveSalvageForPlayer error for ", tostring(player.Name), err3)
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
