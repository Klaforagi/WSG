local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

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
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

local currencyRegistered = false

local function validateCurrency(player, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end

    local recentMutations = CurrencyService:GetRecentMutationInfo(player)
    local function droppedToZero(fieldName)
        local oldValue = math.max(0, math.floor(tonumber(lastGoodData[fieldName]) or 0))
        local newValue = math.max(0, math.floor(tonumber(currentData[fieldName]) or 0))
        local mutation = recentMutations[fieldName]
        local recent = type(mutation) == "table" and (os.clock() - (mutation.at or 0)) <= 15
        if oldValue > 0 and newValue == 0 and not recent then
            return true
        end
        return false
    end

    if droppedToZero("coins") then
        return {
            suspicious = true,
            severity = "severe",
            reason = "coins dropped to zero without a tracked transaction",
        }
    end
    if droppedToZero("keys") or droppedToZero("salvage") then
        return {
            suspicious = true,
            severity = "warning",
            reason = "premium currency dropped to zero without a tracked transaction",
        }
    end

    local oldTotal = (tonumber(lastGoodData.coins) or 0) + (tonumber(lastGoodData.keys) or 0) + (tonumber(lastGoodData.salvage) or 0)
    local newTotal = (tonumber(currentData.coins) or 0) + (tonumber(currentData.keys) or 0) + (tonumber(currentData.salvage) or 0)
    if oldTotal > 0 and newTotal == 0 then
        return {
            suspicious = true,
            severity = "severe",
            reason = "all currency balances reset to zero at once",
        }
    end

    return nil
end

local function registerCurrencySection()
    if currencyRegistered then
        return
    end
    currencyRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "Currency",
        Priority = 10,
        Critical = true,
        Load = function(player)
            return CurrencyService:LoadProfileForPlayer(player)
        end,
        GetSaveData = function(player)
            return CurrencyService:GetSaveData(player)
        end,
        Save = function(player, currentData, lastGoodData)
            return CurrencyService:SaveProfileForPlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            CurrencyService:RemovePlayer(player)
        end,
        Validate = validateCurrency,
    })
end

-- Utility: load coins for a player
local function onPlayerAdded(player)
    -- guard against double-load if we process an already-connected player below
    if player:GetAttribute("_coinsLoaded") then return end
    player:SetAttribute("_coinsLoaded", true)
    DataSaveCoordinator:LoadSection(player, "Currency")
end

registerCurrencySection()
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players who connected before the PlayerAdded signal was hooked
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(player)
    end)
end
