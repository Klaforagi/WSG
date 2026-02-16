--[[
    CameraAndFacingLock  –  3rd-person shooter camera

    When a weapon is equipped the mouse locks to center, the camera
    shifts over the right shoulder, and the character auto-rotates
    to face where the camera looks.  Everything uses the BUILT-IN
    Roblox camera – no Scriptable override, no BodyGyro, no manual
    HRP.CFrame writes – so nothing fights with physics.
]]

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Over-the-shoulder offset applied through Humanoid.CameraOffset
-- X = right, Y = up, Z = forward (negative = back)
-- move the camera up 2 studs on the Y axis when equipping weapons
local SHOULDER_OFFSET = Vector3.new(4, 2, 0)

-- ── state ──────────────────────────────────────────────────────
local active                = false   -- is the lock currently on?
local equipped              = {}      -- set of currently-equipped weapon tools
local prevMouseBehavior     = nil
local prevMouseIcon         = nil
local prevCameraOffset      = nil
local prevAutoRotate        = nil
local renderConn            = nil

-- ── helpers ────────────────────────────────────────────────────
local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsWeapon") then return true end
    if tostring(tool.Name):match("^Tool") then return true end
    return false
end

local function getHumanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- ── enable / disable ──────────────────────────────────────────
local function enableLock()
    if active then return end
    active = true

    -- save & apply mouse lock
    prevMouseBehavior = UserInputService.MouseBehavior
    prevMouseIcon     = UserInputService.MouseIconEnabled
    UserInputService.MouseBehavior    = Enum.MouseBehavior.LockCenter
    UserInputService.MouseIconEnabled = false

    -- save & apply shoulder offset + disable AutoRotate (we control facing)
    local hum = getHumanoid()
    if hum then
        prevCameraOffset = hum.CameraOffset
        prevAutoRotate   = hum.AutoRotate
        hum.CameraOffset = SHOULDER_OFFSET
        hum.AutoRotate   = false
    end

    -- each frame: enforce settings + force character to face camera direction
    renderConn = RunService.RenderStepped:Connect(function()
        -- GUARD: if we've been disabled, do nothing (prevents stale-frame re-lock)
        if not active then return end

        -- re-enforce mouse lock (Roblox can reset it)
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end

        local hum2 = getHumanoid()
        if hum2 then
            if hum2.CameraOffset ~= SHOULDER_OFFSET then
                hum2.CameraOffset = SHOULDER_OFFSET
            end
            if hum2.AutoRotate then
                hum2.AutoRotate = false
            end
        end

        -- force the character to face where the camera looks (yaw only)
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local camLook = camera.CFrame.LookVector
        local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
        if flatLook.Magnitude > 0.001 then
            flatLook = flatLook.Unit
            local pos = hrp.Position
            hrp.CFrame = CFrame.new(pos, pos + flatLook)
        end
    end)
end

local function disableLock()
    if not active then return end
    active = false  -- set BEFORE disconnect so the guard stops the loop instantly

    -- disconnect render loop
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end

    -- force-restore mouse (do it twice with a defer to beat any Roblox re-lock)
    local function restoreMouse()
        UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end
    if prevMouseBehavior ~= nil then
        UserInputService.MouseBehavior    = prevMouseBehavior
        UserInputService.MouseIconEnabled = prevMouseIcon ~= nil and prevMouseIcon or true
        prevMouseBehavior = nil
        prevMouseIcon     = nil
    else
        restoreMouse()
    end
    -- safety: force it again next frame in case Roblox stomped on it
    task.defer(function()
        if not active then
            restoreMouse()
        end
    end)

    -- restore camera offset and AutoRotate
    local hum = getHumanoid()
    if hum then
        hum.CameraOffset = prevCameraOffset or Vector3.new(0, 0, 0)
        if prevAutoRotate ~= nil then
            hum.AutoRotate = prevAutoRotate
        end
    end
    prevCameraOffset = nil
    prevAutoRotate   = nil
end

-- ── recalculate whether lock should be on ─────────────────────
local function refresh()
    local shouldBeActive = next(equipped) ~= nil
    if shouldBeActive and not active then
        enableLock()
    elseif not shouldBeActive and active then
        disableLock()
    end
end

-- ── tool watcher ──────────────────────────────────────────────
local function watchTool(tool)
    if not isWeapon(tool) then return end

    tool.Equipped:Connect(function()
        equipped[tool] = true
        refresh()
    end)

    tool.Unequipped:Connect(function()
        equipped[tool] = nil
        refresh()
    end)

    -- if already in character (equipped) at scan time
    if tool.Parent and tool.Parent == player.Character then
        equipped[tool] = true
        refresh()
    end
end

-- ── character scanning ────────────────────────────────────────
local function onCharacter(char)
    -- reset state on respawn
    equipped = {}
    if active then disableLock() end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then watchTool(child) end
    end
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then watchTool(child) end
    end)
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)

-- watch backpack so we catch tools before they move into the character
if player.Backpack then
    player.Backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then task.defer(watchTool, child) end
    end)
end

return nil
