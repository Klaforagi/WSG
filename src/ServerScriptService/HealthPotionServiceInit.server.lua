local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local HealthPotionService = require(ServerScriptService:WaitForChild("HealthPotionService"))

local sectionRegistered = false

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
local potionStateUpdatedRE = ensureInstance(remotesFolder, "RemoteEvent", "PotionStateUpdated")

local function validateHealthPotionData(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end

    local previousCount = math.max(0, math.floor(tonumber(lastGoodData.count) or 0))
    local currentCount = math.max(0, math.floor(tonumber(currentData.count) or 0))
    local currentGranted = math.max(0, math.floor(tonumber(currentData.totalGranted) or 0))

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
end

HealthPotionService:GetStateChangedEvent():Connect(function(player, state)
    if not player then
        return
    end
    pcall(function()
        potionStateUpdatedRE:FireClient(player, state or HealthPotionService:GetState(player))
    end)
end)

getPotionStateRF.OnServerInvoke = function(player)
    return HealthPotionService:GetState(player)
end

setPotionEquippedRF.OnServerInvoke = function(player, shouldEquip)
    return HealthPotionService:SetEquipped(player, shouldEquip == true)
end

useEquippedPotionRF.OnServerInvoke = function(player)
    return HealthPotionService:UseEquippedPotion(player)
end

registerSection()
Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(player)
    end)
end

print("[HealthPotionServiceInit] Health Potion system initialized")