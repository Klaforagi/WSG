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

--- Raycast forward from rootPart to detect walls; returns clamped distance.
local function clampDistanceToWall(rootPart, direction, maxDist)
    local cfg = getConfig()
    local rayDist = maxDist + (cfg and cfg.WallRayExtra or 3)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { rootPart.Parent }

    local result = workspace:Raycast(rootPart.Position, direction.Unit * rayDist, params)
    if result then
        local wallDist = (result.Position - rootPart.Position).Magnitude - 2 -- 2-stud buffer
        return math.max(0, math.min(maxDist, wallDist))
    end
    return maxDist
end

--------------------------------------------------------------------------------
-- Core dash execution (called after validation)
--------------------------------------------------------------------------------
local function executeDash(player, humanoid, rootPart)
    local cfg = getConfig()
    if not cfg then return false, "config_missing" end

    local state = playerState[player]
    state.isDashing = true

    -- Direction: character's look vector, flattened to XZ
    local lookVector = rootPart.CFrame.LookVector
    local flatDir = Vector3.new(lookVector.X, 0, lookVector.Z)
    if flatDir.Magnitude < 0.01 then
        flatDir = Vector3.new(0, 0, -1)
    end
    flatDir = flatDir.Unit

    -- Wall check
    local distance = clampDistanceToWall(rootPart, flatDir, cfg.Distance)
    if distance < 1 then
        state.isDashing = false
        return false, "blocked"
    end

    local duration = cfg.Duration
    local speed = distance / duration -- studs/s

    -- Apply velocity via LinearVelocity (modern, clean, no lingering objects after removal)
    local attachment = Instance.new("Attachment")
    attachment.Name = "_DashAttachment"
    attachment.Parent = rootPart

    local linVel = Instance.new("LinearVelocity")
    linVel.Name = "_DashLinearVelocity"
    linVel.Attachment0 = attachment
    linVel.VectorVelocity = flatDir * speed + Vector3.new(0, cfg.VerticalDamp * speed, 0)
    linVel.MaxForce = 100000
    linVel.RelativeTo = Enum.ActuatorRelativeTo.World
    linVel.Parent = rootPart

    -- Brief jump lock so dash feels crisp
    local prevJumpPower = humanoid.JumpPower
    local prevJumpHeight = humanoid.JumpHeight
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    log(player.Name, "dashing", distance, "studs over", duration, "s")

    -- Wait for dash duration then clean up
    task.delay(duration, function()
        -- Clean up velocity objects
        if linVel and linVel.Parent then linVel:Destroy() end
        if attachment and attachment.Parent then attachment:Destroy() end

        -- Restore jump
        pcall(function()
            if humanoid and humanoid.Parent then
                humanoid.JumpPower = prevJumpPower
                humanoid.JumpHeight = prevJumpHeight
            end
        end)

        if state then
            state.isDashing = false
        end
        log(player.Name, "dash complete")
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
    playerState[player] = nil
    log("cleared state for", player.Name)
end

return DashService
