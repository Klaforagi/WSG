local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local HealthPotionService = require(ServerScriptService:WaitForChild("HealthPotionService"))
local PotionStockService = require(ServerScriptService:WaitForChild("PotionStockService"))

local HEALTH_POTION_ID = "health_potion"

local sectionRegistered = false
local playerEffectConnections = {}

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

local getPotionStateRF = ensureInstance(potionFolder, "RemoteFunction", "GetPotionState")
local setPotionEquippedRF = ensureInstance(potionFolder, "RemoteFunction", "SetPotionEquipped")
local useEquippedPotionRF = ensureInstance(potionFolder, "RemoteFunction", "UseEquippedPotion")
local purchasePotionRF = ensureInstance(potionFolder, "RemoteFunction", "PurchasePotion")
local potionEffectStartedRE = ensureInstance(potionFolder, "RemoteEvent", "PotionEffectStarted")
local potionStateUpdatedRE = ensureInstance(remotesFolder, "RemoteEvent", "PotionStateUpdated")

local function getHealthPotionCount(data)
    if type(data) ~= "table" then
        return 0
    end

    if type(data.potions) == "table" then
        local entry = data.potions[HEALTH_POTION_ID]
        if type(entry) == "table" then
            return math.max(0, math.floor(tonumber(entry.count) or 0))
        end
        return 0
    end

    return math.max(0, math.floor(tonumber(data.count) or 0))
end

local function getHealthPotionGranted(data)
    if type(data) ~= "table" then
        return 0
    end

    if type(data.potions) == "table" then
        local entry = data.potions[HEALTH_POTION_ID]
        if type(entry) == "table" then
            return math.max(0, math.floor(tonumber(entry.totalGranted) or 0))
        end
        return 0
    end

    return math.max(0, math.floor(tonumber(data.totalGranted) or 0))
end

local function validateHealthPotionData(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end

    local previousCount = getHealthPotionCount(lastGoodData)
    local currentCount = getHealthPotionCount(currentData)
    local currentGranted = getHealthPotionGranted(currentData)

    if previousCount > 0 and currentCount == 0 and currentGranted == 0 then
        return {
            suspicious = true,
            severity = "warning",
            reason = "health potion count reset to zero",
        }
    end

    return nil
end

local function registerSection()
    if sectionRegistered then
        return
    end
    sectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "HealthPotions",
        Priority = 45,
        Critical = false,
        Load = function(player)
            return HealthPotionService:LoadProfileForPlayer(player)
        end,
        GetSaveData = function(player)
            return HealthPotionService:GetSaveData(player)
        end,
        Save = function(player, currentData, lastGoodData)
            return HealthPotionService:SaveProfileForPlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            HealthPotionService:ClearPlayer(player)
        end,
        Validate = validateHealthPotionData,
    })
end

local function onPlayerAdded(player)
    HealthPotionService:MarkLoading(player)
    DataSaveCoordinator:LoadSection(player, "HealthPotions")
    pcall(function()
        potionStateUpdatedRE:FireClient(player, HealthPotionService:GetState(player))
    end)

    if not playerEffectConnections[player] then
        playerEffectConnections[player] = {
            player.CharacterRemoving:Connect(function()
                HealthPotionService:ClearTemporaryPotionEffects(player)
            end),
            player.CharacterAdded:Connect(function(character)
                task.defer(function()
                    local humanoid = character and (character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10))
                    if humanoid then
                        humanoid.Died:Connect(function()
                            HealthPotionService:ClearTemporaryPotionEffects(player)
                        end)
                    end
                end)
            end),
        }
        if player.Character then
            task.defer(function()
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.Died:Connect(function()
                        HealthPotionService:ClearTemporaryPotionEffects(player)
                    end)
                end
            end)
        end
    end
end

Players.PlayerRemoving:Connect(function(player)
    local connections = playerEffectConnections[player]
    if connections then
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        playerEffectConnections[player] = nil
    end
    HealthPotionService:ClearTemporaryPotionEffects(player)
end)

HealthPotionService:GetStateChangedEvent():Connect(function(player, state)
    if not player then
        return
    end
    pcall(function()
        potionStateUpdatedRE:FireClient(player, state or HealthPotionService:GetState(player))
    end)
end)

HealthPotionService:GetEffectStartedEvent():Connect(function(player, payload)
    if not player then
        return
    end
    pcall(function()
        potionEffectStartedRE:FireClient(player, payload)
    end)
end)

getPotionStateRF.OnServerInvoke = function(player)
    return HealthPotionService:GetState(player)
end

setPotionEquippedRF.OnServerInvoke = function(player, shouldEquip, potionId)
    return HealthPotionService:SetEquipped(player, shouldEquip == true, potionId)
end

useEquippedPotionRF.OnServerInvoke = function(player)
    return HealthPotionService:UseEquippedPotion(player)
end

purchasePotionRF.OnServerInvoke = function(player, potionId)
    if type(potionId) ~= "string" then
        return false, "Invalid", HealthPotionService:GetState(player), PotionStockService:BuildState(player)
    end

    -- Gold/coin purchases are gated by per-player stock (server authority).
    -- Robux purchases never reach this remote, so they are unaffected.
    local remaining, maxStock = PotionStockService:GetRemaining(player, potionId)
    if maxStock and maxStock > 0 and remaining <= 0 then
        return false, "OUT_OF_STOCK", HealthPotionService:GetState(player), PotionStockService:BuildState(player)
    end

    local success, message, state = HealthPotionService:PurchasePotion(player, potionId)
    if success then
        -- Only consume stock after coins were deducted and the item granted.
        PotionStockService:Consume(player, potionId)
    end
    return success, message, state, PotionStockService:BuildState(player)
end

registerSection()
Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(player)
    end)
end

_G.HealthPotionService = HealthPotionService
_G.PotionService = HealthPotionService
_G.GetPotionOutgoingDamageMultiplier = function(player)
    return HealthPotionService:GetOutgoingDamageMultiplier(player)
end

print("[HealthPotionServiceInit] Potion system initialized")