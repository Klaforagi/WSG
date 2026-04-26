-- WeaponLockService.lua
-- Server-authoritative weapon switch lock shared by ToolMeleeSetup and ToolGunSetup.
--
-- Lock state per player:
--   token      – increments every ApplyWeaponLock call; old task.delay callbacks are no-ops once stale
--   expireAt   – tick() value when the current lock expires
--   toolName   – Name of the tool that owns the current lock
--
-- Player attributes set while locked (readable by the client hotbar):
--   WeaponLocked       (bool)   – true while any cooldown is active
--   WeaponLockedTool   (string) – Name of the locked tool
--   WeaponLockExpireAt (number) – tick()-based expiry (client uses os.clock() offset; see note)
--
-- NOTE: tick() is server-local. Clients cannot compare directly. The client uses
-- the attribute as a signal (truthy/falsy) for UX only; security enforcement is
-- server-side via the IsLocked / GetLockedTool checks in each weapon handler.

local Players = game:GetService("Players")

local lockState = {} -- [player] = { token: number, expireAt: number, toolName: string }

local module = {}

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function clearAttributes(player)
    pcall(function() player:SetAttribute("WeaponLocked",       false) end)
    pcall(function() player:SetAttribute("WeaponLockedTool",   "")    end)
    pcall(function() player:SetAttribute("WeaponLockExpireAt", 0)     end)
end

local function setAttributes(player, toolName, expireAt)
    pcall(function() player:SetAttribute("WeaponLocked",       true)     end)
    pcall(function() player:SetAttribute("WeaponLockedTool",   toolName) end)
    pcall(function() player:SetAttribute("WeaponLockExpireAt", expireAt) end)
end

local function restoreBackpack(player)
    local holder  = player:FindFirstChild("_WeaponLockHolder")
    local backpack = player:FindFirstChildOfClass("Backpack")
    if holder and backpack then
        for _, tool in ipairs(holder:GetChildren()) do
            tool.Parent = backpack
        end
    end
    if holder then pcall(function() holder:Destroy() end) end
end

local function hideBackpack(player)
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    local holder = player:FindFirstChild("_WeaponLockHolder")
    if not holder then
        holder = Instance.new("Folder")
        holder.Name = "_WeaponLockHolder"
        holder.Parent = player
    end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = holder
        end
    end
end

local function releaseLock(player, token)
    local state = lockState[player]
    if not state then return end
    if state.token ~= token then return end  -- stale callback

    local now = tick()
    if now < state.expireAt then
        -- Someone else extended the lock; reschedule for the new expiry.
        task.delay((state.expireAt - now) + 0.05, function()
            releaseLock(player, token)
        end)
        return
    end

    if lockState[player] and lockState[player].token == token then
        lockState[player] = nil
    end

    if player and player.Parent then
        restoreBackpack(player)
        clearAttributes(player)
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Returns true while the player is inside a weapon cooldown lock.
function module.IsLocked(player)
    local state = lockState[player]
    if not state then return false end
    return tick() < state.expireAt
end

-- Returns the Name of the tool that holds the current lock, or nil.
function module.GetLockedTool(player)
    local state = lockState[player]
    if not state then return nil end
    if tick() >= state.expireAt then return nil end
    return state.toolName
end

-- Returns seconds remaining on the current lock (0 if not locked).
function module.GetRemaining(player)
    local state = lockState[player]
    if not state then return 0 end
    return math.max(state.expireAt - tick(), 0)
end

-- Primary lock entry point.
-- equippedTool: the Tool instance currently in the character (or nil to derive by name).
-- duration: cooldown length in seconds.
function module.ApplyWeaponLock(player, equippedTool, duration)
    if not player or not player.Parent then return end

    local now        = tick()
    local expireAt   = now + duration
    local toolName   = (equippedTool and equippedTool.Name) or ""

    local state = lockState[player]
    if not state then
        state = { token = 0, expireAt = 0, toolName = "" }
        lockState[player] = state
    end

    state.token    += 1
    state.expireAt  = expireAt
    state.toolName  = toolName

    local myToken = state.token

    -- Hide other backpack tools so hotbar slots go dark.
    hideBackpack(player)
    -- Broadcast lock state to client via attributes.
    setAttributes(player, toolName, expireAt)

    task.delay(duration + 0.05, function()
        releaseLock(player, myToken)
    end)
end

-- Backwards-compatible lowercase alias for scripts that haven't updated yet.
-- Finds the currently equipped tool automatically.
module.applyWeaponLock = function(player, duration)
    if not player or not player.Character then return end
    local equippedTool = nil
    for _, v in ipairs(player.Character:GetChildren()) do
        if v:IsA("Tool") then
            equippedTool = v
            break
        end
    end
    module.ApplyWeaponLock(player, equippedTool, duration)
end

-- Call from CharacterRemoving: tools re-grant on respawn so just wipe state.
function module.cleanupCharacter(player)
    if lockState[player] then
        lockState[player] = nil
    end
    if player and player.Parent then
        local holder = player:FindFirstChild("_WeaponLockHolder")
        if holder then pcall(function() holder:Destroy() end) end
        clearAttributes(player)
    end
end

-- Call from PlayerRemoving: return tools before cleanup.
function module.cleanupPlayer(player)
    if lockState[player] then
        lockState[player] = nil
    end
    if player and player.Parent then
        restoreBackpack(player)
        clearAttributes(player)
    end
end

return module
