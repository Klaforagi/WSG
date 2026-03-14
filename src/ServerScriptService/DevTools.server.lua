-- DevTools.server.lua
-- Studio-only server utilities for quick testing (e.g. granting coins).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Only wire up dev remotes when running inside Studio
if not RunService:IsStudio() then return end

-- Lazy-require CurrencyService (same pattern the rest of the codebase uses)
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

-- Create the RemoteEvent clients will fire
local addCoinsRemote = Instance.new("RemoteEvent")
addCoinsRemote.Name = "RequestAddCoins"
addCoinsRemote.Parent = ReplicatedStorage

addCoinsRemote.OnServerEvent:Connect(function(player, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 or amount > 1000 then return end

    if CurrencyService and type(CurrencyService.AddCoins) == "function" then
        CurrencyService:AddCoins(player, amount)
        print("[DevTools] Granted", amount, "coins to", player.Name)
    else
        warn("[DevTools] CurrencyService not available – could not grant coins")
    end
end)

print("[DevTools] Studio dev remotes ready")
