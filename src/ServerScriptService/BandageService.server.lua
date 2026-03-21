--------------------------------------------------------------------------------
-- BandageService.server.lua
-- Server-authoritative bandage healing system for slot 3 utility.
-- Creates its own remotes, validates usage, applies heal ticks, manages cooldowns.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

--------------------------------------------------------------------------------
-- LOAD CONFIG
--------------------------------------------------------------------------------
local BandageConfig
do
    local mod = ReplicatedStorage:WaitForChild("BandageConfig", 10)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then BandageConfig = result end
    end
end
if not BandageConfig then
    warn("[BandageService] BandageConfig not found – using defaults")
    BandageConfig = {
        CastDuration = 6, TickInterval = 1.5, HealPerTick = 10,
        MaxTotalHeal = 40, Cooldown = 20, MoveThreshold = 1.5,
    }
end

--------------------------------------------------------------------------------
-- REMOTES  (server creates so they always exist)
--------------------------------------------------------------------------------
local function getOrCreateRemote(className, name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing then return existing end
    local remote = Instance.new(className)
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

-- Client -> Server: request to start bandaging
local requestBandage  = getOrCreateRemote("RemoteEvent", "RequestBandage")
-- Client -> Server: request to cancel bandaging (voluntary or detected interrupt)
local cancelBandage   = getOrCreateRemote("RemoteEvent", "CancelBandage")
-- Server -> Client: bandage started (confirmed)
local bandageStarted  = getOrCreateRemote("RemoteEvent", "BandageStarted")
-- Server -> Client: heal tick applied { newHealth }
local bandageHealTick = getOrCreateRemote("RemoteEvent", "BandageHealTick")
-- Server -> Client: bandage ended { reason: "complete"|"interrupted"|"died"|"full_hp" }
local bandageEnded    = getOrCreateRemote("RemoteEvent", "BandageEnded")
-- Server -> Client: cooldown started { duration }
local bandageCooldown = getOrCreateRemote("RemoteEvent", "BandageCooldown")

--------------------------------------------------------------------------------
-- PER-PLAYER STATE
--------------------------------------------------------------------------------
local playerState = {} -- [player] = { active, cooldownEnd, startPos, totalHealed, thread }

local function getState(player)
    if not playerState[player] then
        playerState[player] = {
            active       = false,
            cooldownEnd  = 0,
            startPos     = nil,
            totalHealed  = 0,
            thread       = nil,
            healthConn   = nil,
        }
    end
    return playerState[player]
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function getHumanoid(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function startCooldown(player, state)
    state.cooldownEnd = tick() + BandageConfig.Cooldown
    pcall(function()
        bandageCooldown:FireClient(player, BandageConfig.Cooldown)
    end)
end

--------------------------------------------------------------------------------
-- STOP BANDAGE  (called for any reason: complete, interrupt, death)
--------------------------------------------------------------------------------
local function stopBandage(player, reason)
    local state = getState(player)
    if not state.active then return end

    state.active = false
    state.startPos = nil
    state.totalHealed = 0

    -- Cancel running heal thread
    if state.thread then
        pcall(task.cancel, state.thread)
        state.thread = nil
    end

    -- Disconnect health listener
    if state.healthConn then
        pcall(function() state.healthConn:Disconnect() end)
        state.healthConn = nil
    end

    -- Clear attribute on character
    local char = player.Character
    if char then
        char:SetAttribute("IsBandaging", false)
    end

    -- Notify client
    pcall(function()
        bandageEnded:FireClient(player, reason or "interrupted")
    end)

    -- Start cooldown (always, even on interrupt)
    startCooldown(player, state)
end

--------------------------------------------------------------------------------
-- HEAL LOOP  (runs as a coroutine/thread)
--------------------------------------------------------------------------------
local function healLoop(player)
    local state = getState(player)
    local tickCount = 0
    local maxTicks = math.floor(BandageConfig.MaxTotalHeal / BandageConfig.HealPerTick)

    for i = 1, maxTicks do
        task.wait(BandageConfig.TickInterval)

        -- Validate still active
        if not state.active then return end

        local hum = getHumanoid(player)
        if not hum or hum.Health <= 0 then
            stopBandage(player, "died")
            return
        end

        -- Check movement
        local hrp = getRootPart(player)
        if hrp and state.startPos then
            local dist = (hrp.Position - state.startPos).Magnitude
            if dist > BandageConfig.MoveThreshold then
                stopBandage(player, "interrupted")
                return
            end
        end

        -- Apply heal tick
        local healAmount = math.min(BandageConfig.HealPerTick, hum.MaxHealth - hum.Health)
        if healAmount > 0 then
            hum.Health = math.min(hum.Health + healAmount, hum.MaxHealth)
            state.totalHealed = state.totalHealed + healAmount
            pcall(function()
                bandageHealTick:FireClient(player, hum.Health, healAmount)
            end)
        end

        tickCount = tickCount + 1

        -- Check if full HP
        if hum.Health >= hum.MaxHealth then
            stopBandage(player, "full_hp")
            return
        end

        -- Check if max heal reached
        if state.totalHealed >= BandageConfig.MaxTotalHeal then
            stopBandage(player, "complete")
            return
        end
    end

    -- All ticks done
    if state.active then
        stopBandage(player, "complete")
    end
end

--------------------------------------------------------------------------------
-- START BANDAGE  (server-authoritative validation)
--------------------------------------------------------------------------------
local function startBandage(player)
    local state = getState(player)

    -- Already bandaging
    if state.active then return end

    -- On cooldown
    if tick() < state.cooldownEnd then return end

    -- Validate character
    local hum = getHumanoid(player)
    if not hum or hum.Health <= 0 then return end

    -- Already at full HP
    if hum.Health >= hum.MaxHealth then
        pcall(function()
            bandageEnded:FireClient(player, "full_hp")
        end)
        return
    end

    -- Get start position for movement check
    local hrp = getRootPart(player)
    if not hrp then return end

    -- Activate
    state.active = true
    state.startPos = hrp.Position
    state.totalHealed = 0

    -- Set attribute so other systems can check
    local char = player.Character
    if char then
        char:SetAttribute("IsBandaging", true)
    end

    -- Monitor for damage during cast (health going DOWN = interrupt)
    local prevHealth = hum.Health
    state.healthConn = hum.HealthChanged:Connect(function(newHealth)
        if not state.active then return end
        if newHealth < prevHealth then
            -- Took damage → interrupt
            stopBandage(player, "interrupted")
        end
        prevHealth = newHealth
    end)

    -- Notify client bandage confirmed
    pcall(function()
        bandageStarted:FireClient(player)
    end)

    -- Start heal loop in a separate thread
    state.thread = task.spawn(healLoop, player)
end

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------
requestBandage.OnServerEvent:Connect(function(player)
    startBandage(player)
end)

cancelBandage.OnServerEvent:Connect(function(player)
    local state = getState(player)
    if state.active then
        stopBandage(player, "interrupted")
    end
end)

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        -- Reset bandage state on respawn
        local state = getState(player)
        if state.active then
            -- Silently stop without firing cooldown
            state.active = false
            state.startPos = nil
            state.totalHealed = 0
            if state.thread then pcall(task.cancel, state.thread); state.thread = nil end
            if state.healthConn then pcall(function() state.healthConn:Disconnect() end); state.healthConn = nil end
        end
        state.cooldownEnd = 0
        char:SetAttribute("IsBandaging", false)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local state = playerState[player]
    if state then
        if state.active then
            state.active = false
            if state.thread then pcall(task.cancel, state.thread); state.thread = nil end
            if state.healthConn then pcall(function() state.healthConn:Disconnect() end); state.healthConn = nil end
        end
    end
    playerState[player] = nil
end)

-- Handle players already in-game (Studio fast-start)
for _, p in ipairs(Players:GetPlayers()) do
    local state = getState(p)
    if p.Character then
        p.Character:SetAttribute("IsBandaging", false)
    end
end
