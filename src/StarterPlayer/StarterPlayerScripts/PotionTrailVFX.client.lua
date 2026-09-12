--------------------------------------------------------------------------------
-- PotionTrailVFX.client.lua
-- Shows a faded green trail on a player while Speed Potion is active.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer

local TRAIL_NAME = "_SpeedPotionTrail"
local ATTACH0_NAME = "_SpeedPotionTrailA0"
local ATTACH1_NAME = "_SpeedPotionTrailA1"
local TRAIL_COLOR = Color3.fromRGB(110, 220, 145)
local TRAIL_LIFETIME = 0.55
local FADE_DESTROY_DELAY = 0.8

local active = {} -- [Player] = { token = n, expiresAt = n }

local function getNow()
    local ok, result = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if ok and type(result) == "number" then
        return result
    end
    return os.clock()
end

local function destroyNamed(root, name, fadeTrail)
    local inst = root and root:FindFirstChild(name)
    if not inst then
        return
    end
    if fadeTrail and inst:IsA("Trail") then
        pcall(function()
            inst.Enabled = false
        end)
        Debris:AddItem(inst, FADE_DESTROY_DELAY)
        return
    end
    pcall(function()
        inst:Destroy()
    end)
end

local function clearTrail(character, fade)
    if not character then
        return
    end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    destroyNamed(rootPart, TRAIL_NAME, fade == true)
    destroyNamed(rootPart, ATTACH0_NAME, false)
    destroyNamed(rootPart, ATTACH1_NAME, false)
    if fade then
        Debris:AddItem(rootPart:FindFirstChild(ATTACH0_NAME), FADE_DESTROY_DELAY + 0.05)
        Debris:AddItem(rootPart:FindFirstChild(ATTACH1_NAME), FADE_DESTROY_DELAY + 0.05)
    end
end

local function attachTrail(targetPlayer)
    local character = targetPlayer and targetPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end

    clearTrail(character, false)

    local attach0 = Instance.new("Attachment")
    attach0.Name = ATTACH0_NAME
    attach0.Position = Vector3.new(0, 0.75, 0)
    attach0.Parent = rootPart

    local attach1 = Instance.new("Attachment")
    attach1.Name = ATTACH1_NAME
    attach1.Position = Vector3.new(0, -1.35, 0)
    attach1.Parent = rootPart

    local trail = Instance.new("Trail")
    trail.Name = TRAIL_NAME
    trail.Attachment0 = attach0
    trail.Attachment1 = attach1
    trail.Color = ColorSequence.new(TRAIL_COLOR)
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.52),
        NumberSequenceKeypoint.new(0.55, 0.78),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Lifetime = TRAIL_LIFETIME
    trail.MinLength = 0.05
    trail.FaceCamera = true
    trail.LightEmission = 0.18
    trail.LightInfluence = 0
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.85),
        NumberSequenceKeypoint.new(1, 0.2),
    })
    trail.Enabled = true
    trail.Parent = rootPart
end

local function fadeTrail(targetPlayer)
    local character = targetPlayer and targetPlayer.Character
    if not character then
        return
    end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return
    end
    local trail = rootPart:FindFirstChild(TRAIL_NAME)
    if trail and trail:IsA("Trail") then
        pcall(function()
            trail.Enabled = false
        end)
        Debris:AddItem(trail, FADE_DESTROY_DELAY)
        Debris:AddItem(rootPart:FindFirstChild(ATTACH0_NAME), FADE_DESTROY_DELAY + 0.05)
        Debris:AddItem(rootPart:FindFirstChild(ATTACH1_NAME), FADE_DESTROY_DELAY + 0.05)
    else
        clearTrail(character, false)
    end
end

local function stopTrail(targetPlayer)
    if not targetPlayer then
        return
    end
    active[targetPlayer] = nil
    fadeTrail(targetPlayer)
end

local function startTrail(targetPlayer, expiresAt)
    if not targetPlayer then
        return
    end

    local now = getNow()
    if type(expiresAt) ~= "number" or expiresAt <= now then
        stopTrail(targetPlayer)
        return
    end

    local state = active[targetPlayer] or { token = 0 }
    state.token += 1
    state.expiresAt = expiresAt
    active[targetPlayer] = state
    local token = state.token

    attachTrail(targetPlayer)
    task.delay(expiresAt - now, function()
        local current = active[targetPlayer]
        if current and current.token == token then
            stopTrail(targetPlayer)
        end
    end)
end

local function hookCharacter(targetPlayer)
    if not targetPlayer or targetPlayer:GetAttribute("_SpeedPotionTrailHooked") then
        return
    end
    targetPlayer:SetAttribute("_SpeedPotionTrailHooked", true)

    targetPlayer.CharacterAdded:Connect(function()
        local current = active[targetPlayer]
        if not current or getNow() >= (current.expiresAt or 0) then
            return
        end
        task.defer(function()
            if active[targetPlayer] == current then
                attachTrail(targetPlayer)
            end
        end)
    end)

    targetPlayer.CharacterRemoving:Connect(function(character)
        clearTrail(character, false)
    end)
end

for _, existing in ipairs(Players:GetPlayers()) do
    hookCharacter(existing)
end
Players.PlayerAdded:Connect(hookCharacter)
Players.PlayerRemoving:Connect(function(leaving)
    active[leaving] = nil
end)

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    local potionsFolder = remotes and remotes:WaitForChild("Potions", 10)
    local effectStarted = potionsFolder and potionsFolder:WaitForChild("PotionEffectStarted", 10)
    if not (effectStarted and effectStarted:IsA("RemoteEvent")) then
        warn("[PotionTrailVFX] PotionEffectStarted remote missing")
        return
    end

    effectStarted.OnClientEvent:Connect(function(payload)
        if type(payload) ~= "table" or payload.potionId ~= "speed_potion" then
            return
        end

        local sourceUserId = tonumber(payload.sourceUserId)
        local targetPlayer = sourceUserId and Players:GetPlayerByUserId(sourceUserId) or nil
        if not targetPlayer then
            if not sourceUserId then
                targetPlayer = localPlayer
            else
                return
            end
        end

        hookCharacter(targetPlayer)
        startTrail(targetPlayer, tonumber(payload.expiresAt))
    end)
end)
