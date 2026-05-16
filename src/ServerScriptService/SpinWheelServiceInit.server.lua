local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
local SpinWheelService = require(ServerScriptService:WaitForChild("SpinWheelService"))

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

local spinWheelFolder = ensureInstance(remotesFolder, "Folder", "SpinWheel")
local getStateRF = ensureInstance(spinWheelFolder, "RemoteFunction", "GetSpinWheelState")
local requestSpinRF = ensureInstance(spinWheelFolder, "RemoteFunction", "RequestSpinWheelSpin")
local buyPackRF = ensureInstance(spinWheelFolder, "RemoteFunction", "RequestBuyWheelSpinPack")

local spinWheelSectionRegistered = false

local function validateSpinWheelData(_, currentData, lastGoodData)
    if type(currentData) ~= "table" or type(lastGoodData) ~= "table" then
        return nil
    end
    if (tonumber(lastGoodData.totalSpins) or 0) > 0 and (tonumber(currentData.totalSpins) or 0) == 0 then
        return {
            suspicious = true,
            severity = "warning",
            reason = "spin wheel totalSpins reset to zero",
        }
    end
    return nil
end

local function registerSpinWheelSection()
    if spinWheelSectionRegistered then
        return
    end
    spinWheelSectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "SpinWheel",
        Priority = 44,
        Critical = false,
        Load = function(player)
            return SpinWheelService:LoadProfileForPlayer(player)
        end,
        GetSaveData = function(player)
            return SpinWheelService:GetSaveData(player)
        end,
        Save = function(player, currentData, lastGoodData)
            return SpinWheelService:SaveProfileForPlayer(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            SpinWheelService:ClearPlayer(player)
        end,
        Validate = validateSpinWheelData,
    })
end

getStateRF.OnServerInvoke = function(player)
    if not player then
        return {}
    end
    return SpinWheelService:GetState(player)
end

requestSpinRF.OnServerInvoke = function(player)
    if not player then
        return false, "Invalid player", {}
    end
    return SpinWheelService:RequestSpin(player)
end

buyPackRF.OnServerInvoke = function(player, packIndex)
    if not player then
        return false, "Invalid player", {}
    end
    return SpinWheelService:GrantSpinPack(player, packIndex)
end

local function onPlayerAdded(player)
    SpinWheelService:MarkLoading(player)
    DataSaveCoordinator:LoadSection(player, "SpinWheel")
end

registerSpinWheelSection()
Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        onPlayerAdded(player)
    end)
end

print("[SpinWheelServiceInit] Spin Wheel system initialized")