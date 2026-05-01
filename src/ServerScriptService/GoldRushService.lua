--[[
    GoldRushService.lua  (ServerScriptService - ModuleScript)
    Server-authoritative Gold Rush event: scatters modest coin pickups along
    battlefield routes while the timed event is active.
]]

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local Debris              = game:GetService("Debris")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig = require(ReplicatedStorage:WaitForChild("EventConfig"))

local CurrencyService
pcall(function()
    CurrencyService = require(ServerScriptService:WaitForChild("CurrencyService", 10))
end)
if not CurrencyService then
    warn("[GoldRush] CurrencyService not found - rewards will not be granted")
end

local AchievementService
pcall(function()
    AchievementService = require(ServerScriptService:WaitForChild("AchievementService", 10))
end)

local ProgressRemote = ReplicatedStorage:FindFirstChild("EventShardProgress")
if not ProgressRemote then
    ProgressRemote = Instance.new("RemoteEvent")
    ProgressRemote.Name = "EventShardProgress"
    ProgressRemote.Parent = ReplicatedStorage
end

local CoinCollectedRemote = ReplicatedStorage:FindFirstChild("GoldRushCoinCollected")
if not CoinCollectedRemote then
    CoinCollectedRemote = Instance.new("RemoteEvent")
    CoinCollectedRemote.Name = "GoldRushCoinCollected"
    CoinCollectedRemote.Parent = ReplicatedStorage
end

local GoldRushService = {}

local _active = false
local _spawnThread = nil
local _activePickups = {}
local _playerProgress = {}
local _playerCompleted = {}
local _playerEarned = {}

local MAP_MIN_X = -218
local MAP_MAX_X = 75
local MAP_MIN_Z = -162
local MAP_MAX_Z = 383

local function getDef()
    return EventConfig.EventDefs and EventConfig.EventDefs.GoldRush or {}
end

local function getRequiredCoins()
    return tonumber(getDef().RequiredCoins) or 8
end

local function getPickupRewardCoins()
    return tonumber(getDef().PickupRewardCoins) or 3
end

local function getCompletionRewardCoins()
    return tonumber(getDef().CompletionRewardCoins) or 25
end

local function getMaxRewardCoins()
    return tonumber(getDef().MaxRewardCoins) or 60
end

local function getPickupLifetime()
    return tonumber(getDef().PickupLifetime) or 18
end

local function fireProgress(player)
    local required = getRequiredCoins()
    local current = math.min(_playerProgress[player.UserId] or 0, required)
    pcall(function()
        ProgressRemote:FireClient(player, current, required)
    end)
end

local function grantCoins(player, amount, source)
    if not CurrencyService or not CurrencyService.AddCoins then return 0 end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    local userId = player.UserId
    local maxCoins = getMaxRewardCoins()
    local alreadyEarned = _playerEarned[userId] or 0
    local grantAmount = math.min(amount, math.max(0, maxCoins - alreadyEarned))
    if grantAmount <= 0 then return 0 end

    _playerEarned[userId] = alreadyEarned + grantAmount
    pcall(function()
        CurrencyService:AddCoins(player, grantAmount, source)
    end)
    return grantAmount
end

local function awardCompletion(player, popupPosition)
    local userId = player.UserId
    if _playerCompleted[userId] then return end

    _playerCompleted[userId] = true
    local granted = grantCoins(player, getCompletionRewardCoins(), "GoldRushObjective")
    if granted > 0 and popupPosition then
        pcall(function()
            CoinCollectedRemote:FireClient(player, popupPosition, granted, "EventReward")
        end)
    end

    if AchievementService and AchievementService.IncrementStat then
        pcall(function()
            AchievementService:IncrementStat(player, "eventQuestsCompleted", 1)
        end)
    end
end

local function getZoneParts()
    local folders = {
        workspace:FindFirstChild("GoldRushZones"),
        workspace:FindFirstChild("EventGoldRushZones"),
        workspace:FindFirstChild("MeteorShowerZones"),
        workspace:FindFirstChild("EventZones"),
    }

    local zones = {}
    for _, folder in ipairs(folders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("BasePart") then
                    table.insert(zones, child)
                end
            end
            if #zones > 0 then break end
        end
    end
    return zones
end

local function raycastToGround(position)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { workspace:FindFirstChild("GoldRushPickups") }

    local result = workspace:Raycast(position + Vector3.new(0, 220, 0), Vector3.new(0, -520, 0), params)
    if result then
        return result.Position + Vector3.new(0, 2.4, 0)
    end

    return Vector3.new(position.X, math.max(position.Y, 8), position.Z)
end

local function samplePickupPosition()
    local zones = getZoneParts()
    if #zones > 0 then
        local zone = zones[math.random(1, #zones)]
        local size = zone.Size
        local localOffset = Vector3.new(
            (math.random() * 2 - 1) * size.X * 0.5,
            size.Y * 0.5,
            (math.random() * 2 - 1) * size.Z * 0.5
        )
        return raycastToGround(zone.CFrame:PointToWorldSpace(localOffset))
    end

    local x = MAP_MIN_X + math.random() * (MAP_MAX_X - MAP_MIN_X)
    local z = MAP_MIN_Z + math.random() * (MAP_MAX_Z - MAP_MIN_Z)
    return raycastToGround(Vector3.new(x, 20, z))
end

local function getPickupFolder()
    local folder = workspace:FindFirstChild("GoldRushPickups")
    if folder then return folder end

    folder = Instance.new("Folder")
    folder.Name = "GoldRushPickups"
    folder.Parent = workspace
    return folder
end

local function cleanupPickup(record)
    if not record then return end
    if record.connection then
        pcall(function() record.connection:Disconnect() end)
        record.connection = nil
    end
    if record.tween then
        pcall(function() record.tween:Cancel() end)
        record.tween = nil
    end
    if record.part then
        pcall(function() record.part:Destroy() end)
        record.part = nil
    end
end

local function spawnPickup(position)
    if not _active then return end

    local pickup = Instance.new("Part")
    pickup.Name = "GoldRushCoin"
    pickup.Shape = Enum.PartType.Ball
    pickup.Size = Vector3.new(1.55, 1.55, 1.55)
    pickup.Material = Enum.Material.Neon
    pickup.Color = Color3.fromRGB(255, 210, 70)
    pickup.Anchored = true
    pickup.CanCollide = false
    pickup.CanQuery = false
    pickup.CanTouch = true
    pickup.CFrame = CFrame.new(position)
    pickup.Parent = getPickupFolder()

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 210, 80)
    light.Brightness = 1.8
    light.Range = 12
    light.Parent = pickup

    local sparkle = Instance.new("Sparkles")
    sparkle.SparkleColor = Color3.fromRGB(255, 230, 120)
    sparkle.Parent = pickup

    local bobTween = TweenService:Create(
        pickup,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { CFrame = pickup.CFrame + Vector3.new(0, 1.1, 0) }
    )
    bobTween:Play()

    local record = { part = pickup, tween = bobTween, connection = nil }
    table.insert(_activePickups, record)

    local collected = false
    record.connection = pickup.Touched:Connect(function(hit)
        if collected or not _active then return end
        local character = hit.Parent
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        if (_playerEarned[player.UserId] or 0) >= getMaxRewardCoins() then
            fireProgress(player)
            return
        end

        collected = true
        pickup.CanTouch = false

        local granted = grantCoins(player, getPickupRewardCoins(), "GoldRushPickup")
        if granted > 0 then
            _playerProgress[player.UserId] = math.min((_playerProgress[player.UserId] or 0) + 1, getRequiredCoins())
            fireProgress(player)
            pcall(function()
                CoinCollectedRemote:FireClient(player, pickup.Position, granted, "GoldRushPickup")
            end)

            if (_playerProgress[player.UserId] or 0) >= getRequiredCoins() then
                awardCompletion(player, pickup.Position)
                fireProgress(player)
            end
        end

        cleanupPickup(record)
    end)

    local lifetime = getPickupLifetime()
    if lifetime > 5 then
        task.delay(lifetime - 4, function()
            if not pickup or not pickup.Parent then return end
            local fadeInfo = TweenInfo.new(4, Enum.EasingStyle.Linear)
            TweenService:Create(pickup, fadeInfo, { Transparency = 1 }):Play()
            if light then TweenService:Create(light, fadeInfo, { Brightness = 0 }):Play() end
        end)
    end
    Debris:AddItem(pickup, lifetime)
end

local function spawnWave()
    local def = getDef()
    local playerCount = math.max(1, #Players:GetPlayers())
    local count = math.max(
        tonumber(def.MinPickupsPerWave) or 12,
        playerCount * (tonumber(def.PickupsPerPlayerPerWave) or 2)
    )
    count = math.min(count, tonumber(def.MaxPickupsPerWave) or 28)

    for _ = 1, count do
        spawnPickup(samplePickupPosition())
    end
    print(("[GoldRush] Spawned wave with %d pickups"):format(count))
end

Players.PlayerAdded:Connect(function(player)
    task.defer(function()
        if _active then
            fireProgress(player)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    _playerProgress[player.UserId] = nil
    _playerCompleted[player.UserId] = nil
    _playerEarned[player.UserId] = nil
end)

function GoldRushService:Start()
    if _active then return end

    _active = true
    _activePickups = {}
    _playerProgress = {}
    _playerCompleted = {}
    _playerEarned = {}

    print("[GoldRush] Event STARTED")
    for _, player in ipairs(Players:GetPlayers()) do
        fireProgress(player)
    end

    _spawnThread = task.spawn(function()
        local waveCount = math.max(1, tonumber(getDef().WaveCount) or 4)
        local duration = tonumber(EventConfig.EVENT_DURATION) or 60
        local interval = math.max(6, duration / waveCount)

        for waveIndex = 1, waveCount do
            if not _active then return end
            spawnWave()
            if waveIndex < waveCount then
                task.wait(interval)
            end
        end
    end)
end

function GoldRushService:Stop()
    if not _active then return end
    _active = false

    print("[GoldRush] Event STOPPED")
    if _spawnThread then
        pcall(task.cancel, _spawnThread)
        _spawnThread = nil
    end

    for _, record in ipairs(_activePickups) do
        cleanupPickup(record)
    end
    _activePickups = {}
    _playerProgress = {}
    _playerCompleted = {}
    _playerEarned = {}
end

function GoldRushService:IsActive()
    return _active
end

return GoldRushService
