--[[
    GoldRushService.lua  (ServerScriptService - ModuleScript)
    Server-authoritative Gold Rush event: scatters modest coin pickups along
    battlefield routes while the timed event is active.
]]

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")

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

local function getPickupLifetime()
    return tonumber(getDef().PickupLifetime) or 20
end

local function fireProgress(player)
    local required = getRequiredCoins()
    if required <= 0 then return end
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
    local grantAmount = amount
    _playerEarned[userId] = (_playerEarned[userId] or 0) + grantAmount
    local ok, credited = pcall(function()
        return CurrencyService:AddCoins(player, grantAmount, source)
    end)
    return ok and math.max(0, math.floor(tonumber(credited) or 0)) or 0
end

local function awardCompletion(player, popupPosition)
    if getRequiredCoins() <= 0 then return end
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

-- Create a default zone folder/part matching the MeteorShower fallback behavior
local function getOrCreateZoneFolder()
    local folder = workspace:FindFirstChild("GoldRushZones")
    if folder then return folder end

    warn("[GoldRush] Zone folder 'GoldRushZones' not found – creating default 200×200 fallback zone.")

    folder = Instance.new("Folder")
    folder.Name = "GoldRushZones"
    folder.Parent = workspace

    local centerPart = workspace:FindFirstChild("CenterPoint")
    local centerPos = centerPart and centerPart.Position or Vector3.new(0, 0, 0)

    local zone = Instance.new("Part")
    zone.Name = "DefaultZone"
    zone.Size = Vector3.new(200, 1, 200)
    zone.Position = Vector3.new(centerPos.X, centerPos.Y + 5, centerPos.Z)
    zone.Anchored = true
    zone.CanCollide = false
    zone.CanTouch = false
    zone.CanQuery = false
    zone.Transparency = 1
    zone.Parent = folder

    return folder
end

local function raycastToGround(position)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = { workspace:FindFirstChild("GoldRushPickups") }
    params.FilterDescendantsInstances = ignored

    local origin = position + Vector3.new(0, 220, 0)
    local direction = Vector3.new(0, -520, 0)
    for _ = 1, 32 do
        params.FilterDescendantsInstances = ignored
        local result = workspace:Raycast(origin, direction, params)
        if not result then break end
        local tree = result.Instance:FindFirstAncestor("Tree")
        if tree and result.Instance.Name == "TreeLeaves" then
            table.insert(ignored, result.Instance)
        elseif tree and result.Instance.Name == "Part" then
            return nil -- Never place Coin Rush drops on a tree trunk.
        else
            return result.Position + Vector3.new(0, 2.4, 0)
        end
    end

    return nil
end

local function samplePickupPosition()
    local zones = getZoneParts()
    local attempts = 8
    for i = 1, attempts do
        if #zones > 0 then
            local zone = zones[math.random(1, #zones)]
            local size = zone.Size
            local localOffset = Vector3.new(
                (math.random() * 2 - 1) * (size.X * 0.5),
                size.Y * 0.5,
                (math.random() * 2 - 1) * (size.Z * 0.5)
            )
            local sampled = raycastToGround(zone.CFrame:PointToWorldSpace(localOffset))
            if sampled and sampled.Y >= 0 and sampled.Y <= 10 then
                return sampled
            end
        else
            -- create a default zone folder like MeteorShower uses
            local folder = getOrCreateZoneFolder()
            local folderZones = {}
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("BasePart") then
                    table.insert(folderZones, child)
                end
            end
            if #folderZones > 0 then
                local zone = folderZones[math.random(1, #folderZones)]
                local size = zone.Size
                local localOffset = Vector3.new(
                    (math.random() * 2 - 1) * (size.X * 0.5),
                    size.Y * 0.5,
                    (math.random() * 2 - 1) * (size.Z * 0.5)
                )
                local sampled = raycastToGround(zone.CFrame:PointToWorldSpace(localOffset))
                if sampled and sampled.Y >= 0 and sampled.Y <= 10 then
                    return sampled
                end
            else
                local x = MAP_MIN_X + math.random() * (MAP_MAX_X - MAP_MIN_X)
                local z = MAP_MIN_Z + math.random() * (MAP_MAX_Z - MAP_MIN_Z)
                local sampled = raycastToGround(Vector3.new(x, 20, z))
                if sampled and sampled.Y >= 0 and sampled.Y <= 10 then
                    return sampled
                end
            end
        end
    end

    -- If all attempts failed, return nil so caller can skip spawning here
    return nil
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
    if record.spin then
        pcall(function() record.spin:Disconnect() end)
        record.spin = nil
    end
    if record.part then
        pcall(function() record.part:Destroy() end)
        record.part = nil
    end
    if record.sensor then
        pcall(function() record.sensor:Destroy() end)
        record.sensor = nil
    end
end

local function spawnPickup(position)
    if not _active then return end

    local items = ServerStorage:FindFirstChild("Items")
    local template = items and items:FindFirstChild("Coin")
    if not template then
        warn("[GoldRush] ServerStorage.Items.Coin is missing")
        return
    end
    local pickup = template:Clone()
    pickup.Name = "GoldRushCoin"
    local touchPart
    for _, descendant in ipairs({ pickup, table.unpack(pickup:GetDescendants()) }) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = true
            touchPart = touchPart or descendant
            -- Keep the authored particles, but make the event readable rather than noisy.
            for _, effect in ipairs(descendant:GetDescendants()) do
                if effect:IsA("ParticleEmitter") then
                    effect.Rate = math.min(effect.Rate, 4)
                    effect.Speed = NumberRange.new(0.15, 0.6)
                    effect.Lifetime = NumberRange.new(0.25, 0.55)
                end
            end
        end
    end
    if not touchPart then
        pickup:Destroy()
        warn("[GoldRush] ServerStorage.Items.Coin has no BasePart")
        return
    end
    -- Resolve the first surface below the drop rather than placing the coin at
    -- a fixed height. This lets it settle on hills, props, and other geometry.
    local pickupFolder = getPickupFolder()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { pickupFolder }
    local hit = workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), rayParams)
    local sourcePivot = pickup:GetPivot()
    local boxCF, boxSize
    if pickup:IsA("BasePart") then
        boxCF, boxSize = pickup.CFrame, pickup.Size
    else
        boxCF, boxSize = pickup:GetBoundingBox()
    end
    -- An invisible, slightly oversized sensor defines the resting clearance.
    -- Its bottom reaches the surface first, leaving the visible coin just above it.
    local sensor = Instance.new("Part")
    sensor.Name = "GoldRushCoinSensor"
    sensor.Size = boxSize + Vector3.new(.24, .24, .24)
    sensor.Anchored = true
    sensor.CanCollide = false
    sensor.CanQuery = false
    sensor.CanTouch = true
    sensor.Transparency = 1
    sensor.CastShadow = false
    local sensorRelative = sourcePivot:ToObjectSpace(boxCF)
    local pivotToBottom = sourcePivot:PointToObjectSpace(boxCF.Position).Y - sensor.Size.Y * .5
    local rotation = CFrame.new(sourcePivot.Position):Inverse() * sourcePivot
    local landingPosition = hit and (hit.Position + Vector3.new(0, -pivotToBottom + .03, 0)) or position
    local landingPivot = CFrame.new(landingPosition) * rotation
    pickup:PivotTo(landingPivot * CFrame.new(0, 15, 0))
    pickup.Parent = pickupFolder
    sensor.CFrame = pickup:GetPivot() * sensorRelative
    sensor.Parent = pickupFolder

    local dropStartedAt = workspace:GetServerTimeNow()
    local spinOffset = math.rad(math.random(0, 359))
    local lifetime = getPickupLifetime()
    local visualParts = {}
    local visualTextures = {}
    for _, part in ipairs({ pickup, table.unpack(pickup:GetDescendants()) }) do
        if part:IsA("BasePart") then visualParts[part] = part.Transparency end
        if part:IsA("Decal") or part:IsA("Texture") then
            visualTextures[part] = part.Transparency
        end
    end
    local record = { part = pickup, sensor = sensor, tween = nil, connection = nil, spin = nil,
        visualParts = visualParts, visualTextures = visualTextures, fadeStartedAt = dropStartedAt + lifetime - 5 }
    record.spin = RunService.Heartbeat:Connect(function()
        if not pickup.Parent then
            if record.spin then record.spin:Disconnect(); record.spin = nil end
            return
        end
        local t = workspace:GetServerTimeNow()
        local hoverDuration = 1
        local elapsedSinceDrop = t - dropStartedAt
        local dropProgress = math.clamp((elapsedSinceDrop - hoverDuration) / 4, 0, 1)
        local currentPivot
        if elapsedSinceDrop < hoverDuration then
            -- Briefly present the drop in the air before it begins gliding down.
            currentPivot = landingPivot * CFrame.new(0, 15, 0)
                * CFrame.Angles(0, spinOffset + elapsedSinceDrop * math.rad(45), 0)
        elseif dropProgress < 1 then
            -- A gentle glide from ten studs up, rather than a quick pop-in.
            -- Ease out: it decelerates into its resting position instead of
            -- accelerating toward the ground.
            local eased = 1 - (1 - dropProgress) * (1 - dropProgress)
            currentPivot = landingPivot * CFrame.new(0, 15 * (1 - eased), 0)
                * CFrame.Angles(0, spinOffset + elapsedSinceDrop * math.rad(45), 0)
        else
            -- One relaxed rotation every eight seconds, with the existing soft bob.
            local landedFor = elapsedSinceDrop - hoverDuration - 4
            currentPivot = landingPivot * CFrame.new(0, math.sin(landedFor * 2) * .2, 0)
                * CFrame.Angles(0, spinOffset + elapsedSinceDrop * math.rad(45), 0)
        end
        pickup:PivotTo(currentPivot)
        sensor.CFrame = currentPivot * sensorRelative
        local fade = math.clamp((t - record.fadeStartedAt) / 5, 0, 1)
        if fade > 0 then
            for part, originalTransparency in pairs(record.visualParts) do
                if part.Parent then part.Transparency = originalTransparency + (1 - originalTransparency) * fade end
            end
            for texture, originalTransparency in pairs(record.visualTextures) do
                if texture.Parent then texture.Transparency = originalTransparency + (1 - originalTransparency) * fade end
            end
        end
    end)
    table.insert(_activePickups, record)

    local collected = false
    record.connection = sensor.Touched:Connect(function(hit)
        if collected then return end
        local character = hit.Parent
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        collected = true
        sensor.CanTouch = false

        local granted = grantCoins(player, getPickupRewardCoins(), "GoldRushPickup")
        if granted > 0 then
            pcall(function()
                CoinCollectedRemote:FireClient(player, touchPart.Position, granted, "GoldRushPickup")
            end)

            local required = getRequiredCoins()
            if required > 0 then
                _playerProgress[player.UserId] = math.min((_playerProgress[player.UserId] or 0) + 1, required)
                fireProgress(player)

                if (_playerProgress[player.UserId] or 0) >= required then
                    awardCompletion(player, touchPart.Position)
                    fireProgress(player)
                end
            end
        end

        cleanupPickup(record)
    end)

    task.delay(lifetime, function()
        cleanupPickup(record)
    end)
end

local function spawnWave()
    local def = getDef()
    local playerCount = math.max(1, #Players:GetPlayers())
    local count = math.max(
        tonumber(def.MinPickupsPerWave) or 18,
        playerCount * (tonumber(def.PickupsPerPlayerPerWave) or 4)
    )
    count = math.min(count, tonumber(def.MaxPickupsPerWave) or 40)

    local spawned = 0
    local attempts = 0
    local maxAttempts = math.max(8, count * 3)
    while spawned < count and attempts < maxAttempts do
        attempts = attempts + 1
        local pos = samplePickupPosition()
        if pos then
            spawnPickup(pos)
            spawned = spawned + 1
        end
    end
    print(("[GoldRush] Spawned wave with %d pickups (attempts=%d)"):format(spawned, attempts))
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
        local waveCount = math.max(1, tonumber(getDef().WaveCount) or 5)
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

    -- Existing drops finish their own lifetime. They should not blink away
    -- just because the event timer ended.
    _playerProgress = {}
    _playerCompleted = {}
    _playerEarned = {}
end

function GoldRushService:IsActive()
    return _active
end

return GoldRushService
