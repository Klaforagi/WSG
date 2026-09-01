--[[
        CameraAndFacingLock  –  3rd-person shooter camera

        When a weapon is equipped the mouse locks to center, the camera
        shifts over the right shoulder, and the character auto-rotates
        to face where the camera looks. Zooming all the way in keeps this
        custom camera (mouse lock + facing) but eases CameraOffset to 0
        so the view is centered first-person. Zooming out restores the
        shoulder offset. Everything uses the built-in Roblox camera.
        This script defers disabling the weapon camera briefly when a
        tool is unequipped so quick swaps between weapons do NOT cause
        the camera to snap back to default and then return.

        Implementation notes:
        - `ApplyWeaponCamera()` enables the lock immediately.
        - `ApplyDefaultCamera()` restores default behavior.
        - On `Tool.Unequipped`, we schedule a short delayed re-check
            (UNEQUIP_DELAY) to see whether another weapon is already
            equipped; if so, we keep the weapon camera active. This prevents
            flicker when swapping tools rapidly.
        - The delay is cancellable by bumping `unequipVersion` whenever
            a new equip/unequip event happens.
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
local CENTER_OFFSET = Vector3.new(0, 0, 0)
local UNEQUIP_DELAY = 0.06 -- seconds: short delay to avoid camera flicker on swaps
-- Tight hysteresis: enter only at min zoom, leave after one scroll notch.
local ZOOM_IN_SLACK = 0.2
local ZOOM_OUT_SLACK = 0.4
local OFFSET_BLEND_SPEED = 14 -- higher = faster ease between shoulder and center
local VISIBILITY_BIND = "WeaponCamAvatarVisible"
local VISIBILITY_PRIORITY = Enum.RenderPriority.Camera.Value + 2

-- ── state ──────────────────────────────────────────────────────
local active                = false   -- is the lock currently on?
local equipped              = {}      -- set of currently-equipped weapon tools (tool->true)
local prevMouseBehavior     = nil
local prevMouseIcon         = nil
local prevCameraOffset      = nil
local prevAutoRotate        = nil
local renderConn            = nil
local unequipVersion        = 0      -- bump to cancel pending delayed checks
local firstPersonZoom       = false  -- fully zoomed in; use centered offset
local ApplyDefaultCamera
local HasEquippedWeapon

-- ── helpers ────────────────────────────────────────────────────
local function isWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool:GetAttribute("IsWeapon") then return true end
    local name = tostring(tool.Name)
    if name:match("^Tool") then return true end
    -- accept non-prefixed tool names if they match known weapon presets
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ok, meleeMod = pcall(function()
        if ReplicatedStorage:FindFirstChild("ToolMeleeSettings") then
            return require(ReplicatedStorage:WaitForChild("ToolMeleeSettings"))
        end
        return nil
    end)
    local ok2, gunMod = pcall(function()
        if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
            return require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
        end
        return nil
    end)
    local key = name:lower()
    if meleeMod and meleeMod.presets and meleeMod.presets[key] then return true end
    if gunMod and gunMod.presets and gunMod.presets[key] then return true end
    return false
end

local function getHumanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getOrbitZoom()
    local cam = workspace.CurrentCamera or camera
    if not cam then
        return math.huge
    end
    camera = cam
    -- Offset is camera-local XY, so distance along LookVector is the orbit zoom.
    local delta = cam.CFrame.Position - cam.Focus.Position
    return math.abs(delta:Dot(cam.CFrame.LookVector))
end

local function updateFirstPersonZoom()
    local minZoom = tonumber(player.CameraMinZoomDistance) or 0.5
    local zoom = getOrbitZoom()
    if firstPersonZoom then
        if zoom > minZoom + ZOOM_OUT_SLACK then
            firstPersonZoom = false
        end
    elseif zoom <= minZoom + ZOOM_IN_SLACK then
        firstPersonZoom = true
    end
    return firstPersonZoom
end

local RIGHT_ARM_PARTS = {
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    ["Right Arm"] = true,
}

local RIGHT_ARM_ATTACHMENTS = {
    RightGripAttachment = true,
    RightShoulderAttachment = true,
    RightCollarAttachment = true,
    RightWristAttachment = true,
}

local function accessoryIsOnRightArm(accessory)
    local handle = accessory and accessory:FindFirstChild("Handle")
    if not handle then
        return false
    end
    for _, child in ipairs(handle:GetChildren()) do
        if child:IsA("Attachment") and RIGHT_ARM_ATTACHMENTS[child.Name] then
            return true
        end
        if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D") then
            local p0, p1 = child.Part0, child.Part1
            if (p0 and RIGHT_ARM_PARTS[p0.Name]) or (p1 and RIGHT_ARM_PARTS[p1.Name]) then
                return true
            end
        end
    end
    return false
end

local function keepAvatarVisible()
    local char = player.Character
    if not char then
        return
    end

    local hideBody = firstPersonZoom
    local rightArmAccessories = {}
    if hideBody then
        for _, child in ipairs(char:GetChildren()) do
            if (child:IsA("Accessory") or child:IsA("Hat") or child:IsA("Accoutrement"))
                and accessoryIsOnRightArm(child) then
                rightArmAccessories[child] = true
            end
        end
    end

    for _, inst in ipairs(char:GetDescendants()) do
        if inst:GetAttribute("PlayerHealthRing") == true then
            continue
        end
        if not (inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture")) then
            continue
        end

        local keep = not hideBody
        if hideBody then
            local current = inst
            while current and current ~= char do
                if current:IsA("Tool") then
                    keep = true
                    break
                end
                if current:IsA("BasePart") and RIGHT_ARM_PARTS[current.Name] then
                    keep = true
                    break
                end
                if rightArmAccessories[current] then
                    keep = true
                    break
                end
                current = current.Parent
            end
        end

        local goal = keep and 0 or 1
        if inst.LocalTransparencyModifier ~= goal then
            inst.LocalTransparencyModifier = goal
        end
    end
end

local function desiredCameraOffset()
    if updateFirstPersonZoom() then
        return CENTER_OFFSET
    end
    return SHOULDER_OFFSET
end

local function shouldSuspendWeaponCamera()
    local char = player.Character
    if not char then return true end
    if char:GetAttribute("_ragdolled") then return true end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return true end
    return hum.Health <= 0
end

-- ── enable / disable ──────────────────────────────────────────
local function ApplyWeaponCamera()
    if active then return end
    if shouldSuspendWeaponCamera() then return end
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
        hum.CameraOffset = desiredCameraOffset()
        hum.AutoRotate   = false
    end

    pcall(function()
        RunService:UnbindFromRenderStep(VISIBILITY_BIND)
    end)
    RunService:BindToRenderStep(VISIBILITY_BIND, VISIBILITY_PRIORITY, keepAvatarVisible)

    -- each frame: enforce settings + force character to face camera direction
    renderConn = RunService.RenderStepped:Connect(function(dt)
        if not active then return end -- guard against stale frame loops
        if shouldSuspendWeaponCamera() or not HasEquippedWeapon() then
            ApplyDefaultCamera()
            return
        end

        -- re-enforce mouse lock (Roblox can reset it)
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end

        local hum2 = getHumanoid()
        if hum2 then
            local goal = desiredCameraOffset()
            local current = hum2.CameraOffset
            if (current - goal).Magnitude > 0.01 then
                local alpha = 1 - math.exp(-OFFSET_BLEND_SPEED * math.max(dt, 0))
                hum2.CameraOffset = current:Lerp(goal, math.clamp(alpha, 0, 1))
            elseif current ~= goal then
                hum2.CameraOffset = goal
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

ApplyDefaultCamera = function()
    if not active then return end
    active = false  -- set BEFORE disconnect so the guard stops the loop instantly

    -- disconnect render loop
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    pcall(function()
        RunService:UnbindFromRenderStep(VISIBILITY_BIND)
    end)

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
HasEquippedWeapon = function()
    if shouldSuspendWeaponCamera() then return false end

    local char = player.Character
    if not char then return false end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and isWeapon(child) then
            return true
        end
    end
    return false
end

local function refresh()
    local shouldBeActive = HasEquippedWeapon()
    if shouldBeActive and not active then
        ApplyWeaponCamera()
    elseif not shouldBeActive and active then
        ApplyDefaultCamera()
    end
end

-- ── tool watcher ──────────────────────────────────────────────
local function rebuildEquippedFromCharacter()
    equipped = {}
    local char = player.Character
    if not char then return end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and isWeapon(child) then
            equipped[child] = true
        end
    end
end

local function scheduleUnequipCheck()
    unequipVersion = unequipVersion + 1
    local myVer = unequipVersion
    task.delay(UNEQUIP_DELAY, function()
        if myVer ~= unequipVersion then return end -- canceled by newer equip/unequip
        rebuildEquippedFromCharacter()
        refresh()
    end)
end

local function watchTool(tool)
    if not isWeapon(tool) then return end

    tool.Equipped:Connect(function()
        -- cancel pending uneven checks by bumping version
        unequipVersion = unequipVersion + 1
        equipped[tool] = true
        refresh()
    end)

    tool.Unequipped:Connect(function()
        -- schedule a short delayed check instead of immediately disabling
        -- the camera. This prevents flicker when swapping weapons.
        scheduleUnequipCheck()
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
    firstPersonZoom = false
    if active then ApplyDefaultCamera() end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.Died:Connect(function()
            ApplyDefaultCamera()
        end)
    end
    char:GetAttributeChangedSignal("_ragdolled"):Connect(function()
        if char:GetAttribute("_ragdolled") then
            ApplyDefaultCamera()
        end
    end)

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
