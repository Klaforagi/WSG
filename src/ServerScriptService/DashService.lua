--------------------------------------------------------------------------------
-- DashService.lua  –  Server-authoritative dash ability logic
-- ModuleScript in ServerScriptService.
--
-- Validates dash requests, enforces cooldown, applies movement, and fires
-- effects back to the client.
--
-- Public API (used by DashServiceInit.server.lua):
--   DashService:Init()
--   DashService:TryDash(player) -> bool, string
--   DashService:ClearPlayer(player)
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local DEBUG = false

--------------------------------------------------------------------------------
-- Lazy-load DashConfig from ReplicatedStorage
--------------------------------------------------------------------------------
local DashConfig
local function getConfig()
    if DashConfig then return DashConfig end
    pcall(function()
        local mod = ReplicatedStorage:WaitForChild("DashConfig", 10)
        if mod and mod:IsA("ModuleScript") then
            DashConfig = require(mod)
        end
    end)
    return DashConfig
end

--------------------------------------------------------------------------------
-- Module table
--------------------------------------------------------------------------------
local DashService = {}

-- Per-player state: { lastDashTime = number, isDashing = bool }
local playerState = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function log(...)
    if DEBUG then print("[DashService]", ...) end
end

local function getCharacterParts(player)
    local char = player.Character
    if not char then return nil, nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    return humanoid, rootPart
end

-- Sweep the torso volume so corners cannot slip past a single center ray.
-- Keep the volume above the feet to avoid treating flat ground as a wall.
local function castDashObstacle(rootPart, direction, distance)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { rootPart.Parent }
    params.RespectCanCollide = true
    params.CollisionGroup = rootPart.CollisionGroup
    local size = rootPart.Size
    return workspace:Blockcast(
        CFrame.lookAt(rootPart.Position, rootPart.Position + direction),
        Vector3.new(size.X + 1, size.Y * 1.5, size.Z + 0.5),
        direction * distance,
        params
    )
end

local function clampDistanceToWall(rootPart, direction, maxDist)
    local result = castDashObstacle(rootPart, direction, maxDist + 0.5)
    if result then
        return math.max(0, math.min(maxDist, result.Distance - 0.5))
    end
    return maxDist
end

--------------------------------------------------------------------------------
-- Core dash execution (called after validation)
-- Burst in the player's move direction (same in air and on ground), then a
-- short ease back to WalkSpeed so leftover dash speed does not snap off.
-- Standing still falls back to facing direction.
--------------------------------------------------------------------------------
local function executeDash(player, humanoid, rootPart)
    local cfg = getConfig()
    if not cfg then return false, "config_missing" end

    local state = playerState[player]
    state.isDashing = true

    local move = humanoid.MoveDirection
    local flatDir = Vector3.new(move.X, 0, move.Z)
    if flatDir.Magnitude < 0.1 then
        local lookVector = rootPart.CFrame.LookVector
        flatDir = Vector3.new(lookVector.X, 0, lookVector.Z)
    end
    if flatDir.Magnitude < 0.01 then
        flatDir = Vector3.new(0, 0, -1)
    end
    flatDir = flatDir.Unit

    local distance = clampDistanceToWall(rootPart, flatDir, cfg.Distance)
    if distance < 1 then
        state.isDashing = false
        player:SetAttribute("IsDashing", false)
        return false, "blocked"
    end

    local duration = cfg.Duration
    local speed = distance / duration
    local maxForce = tonumber(cfg.MaxForce) or 1e6
    local dashVelocity = flatDir * speed
    player:SetAttribute("IsDashing", true)

    local attachment = Instance.new("Attachment")
    attachment.Name = "_DashAttachment"
    attachment.Parent = rootPart

    -- Hold a straight horizontal line for the burst (no gravity drop mid-dash).
    local linVel = Instance.new("LinearVelocity")
    linVel.Name = "_DashLinearVelocity"
    linVel.Attachment0 = attachment
    linVel.RelativeTo = Enum.ActuatorRelativeTo.World
    linVel.VectorVelocity = dashVelocity
    linVel.ForceLimitsEnabled = true
    linVel.MaxForce = maxForce
    linVel.Parent = rootPart

    log(player.Name, "dashing", distance, "studs over", duration, "s")

    local cleanedUp = false
    local obstacleConnection
    local decelTween
    local function finishDashCleanup(hitObstacle)
        if cleanedUp then return end
        cleanedUp = true
        if obstacleConnection then obstacleConnection:Disconnect() end
        if decelTween then decelTween:Cancel() end
        if linVel and linVel.Parent then linVel:Destroy() end
        if attachment and attachment.Parent then attachment:Destroy() end
        if hitObstacle and rootPart.Parent and humanoid.Health > 0 then
            local velocity = rootPart.AssemblyLinearVelocity
            rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
            local spin = rootPart.AssemblyAngularVelocity
            rootPart.AssemblyAngularVelocity = Vector3.new(0, spin.Y, 0)
        end
        if state then
            state.isDashing = false
            state.cleanup = nil
        end
        player:SetAttribute("IsDashing", false)
        log(player.Name, "dash complete")
    end
    state.cleanup = finishDashCleanup

    -- Remains connected during deceleration: the slowdown still applies force.
    obstacleConnection = RunService.PreSimulation:Connect(function(dt)
        if player.Character ~= rootPart.Parent or not rootPart.Parent
            or humanoid.Health <= 0 or not linVel.Parent then
            finishDashCleanup()
            return
        end
        local velocity = rootPart.AssemblyLinearVelocity
        local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        local lookAhead = math.max(horizontalSpeed, linVel.VectorVelocity.Magnitude)
            * math.max(dt, 1 / 30) + 0.5
        if castDashObstacle(rootPart, flatDir, lookAhead) then
            finishDashCleanup(true)
        end
    end)

    task.delay(duration, function()
        if cleanedUp then return end
        if not (linVel and linVel.Parent) then
            finishDashCleanup()
            return
        end

        local walkSpeed = 16
        if humanoid and humanoid.Parent then
            walkSpeed = tonumber(humanoid.WalkSpeed) or 16
        end
        local endVel = flatDir * walkSpeed

        -- Release vertical lock so gravity returns, then ease leftover dash speed off.
        pcall(function()
            linVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
            linVel.MaxAxesForce = Vector3.new(maxForce, 0, maxForce)
        end)

        local decelTime = math.max(0.05, tonumber(cfg.DecelDuration) or 0.2)
        local tween = TweenService:Create(
            linVel,
            TweenInfo.new(decelTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { VectorVelocity = endVel }
        )
        decelTween = tween

        local finished = false
        local function onDecelDone()
            if finished then return end
            finished = true
            finishDashCleanup()
        end

        tween.Completed:Connect(onDecelDone)
        tween:Play()
        task.delay(decelTime + 0.05, onDecelDone)
    end)

    return true, "ok"
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function DashService:Init()
    log("initialized")
end

--- Attempt a dash for the given player. Returns success, reason.
function DashService:TryDash(player)
    local cfg = getConfig()
    if not cfg then return false, "config_missing" end

    -- Ensure state table
    if not playerState[player] then
        playerState[player] = { lastDashTime = 0, isDashing = false }
    end
    if player:GetAttribute("IsDashing") == nil then
        player:SetAttribute("IsDashing", false)
    end
    local state = playerState[player]

    -- Already dashing?
    if state.isDashing then
        log(player.Name, "rejected: already dashing")
        return false, "already_dashing"
    end

    -- Cooldown check
    local now = tick()
    local elapsed = now - state.lastDashTime
    if elapsed < cfg.Cooldown then
        log(player.Name, "rejected: cooldown", string.format("%.1f", cfg.Cooldown - elapsed), "s remaining")
        return false, "cooldown"
    end

    -- Character validation
    local humanoid, rootPart = getCharacterParts(player)
    if not humanoid or not rootPart then
        return false, "no_character"
    end
    if humanoid.Health <= 0 then
        return false, "dead"
    end

    -- Disallow dashing while carrying the flag
    if player:GetAttribute("CarryingFlag") then
        log(player.Name, "rejected: carrying flag")
        return false, "carrying_flag"
    end
    -- Record dash time BEFORE execution so rapid re-fires are blocked
    state.lastDashTime = now

    -- Execute
    local ok, reason = executeDash(player, humanoid, rootPart)
    if not ok then
        -- Revert timestamp if dash was blocked (e.g. wall)
        if reason == "blocked" then
            state.lastDashTime = state.lastDashTime - cfg.Cooldown
        end
    end

    return ok, reason
end

function DashService:ClearPlayer(player)
    local state = playerState[player]
    if state and state.cleanup then state.cleanup() end
    playerState[player] = nil
    player:SetAttribute("IsDashing", false)
    log("cleared state for", player.Name)
end

return DashService
