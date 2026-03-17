--------------------------------------------------------------------------------
-- DevRocketClient.client.lua  –  Client-side input for the dev rocket launcher
-- LocalScript in StarterPlayerScripts.
--
-- Handles:
--   • P key  →  equip / unequip toggle  (server-authoritative via remote)
--   • Tool.Activated  →  fire request   (sends aim direction to server)
--   • TextBox focus guard (ignores P while typing)
--
-- All damage, projectile spawning, and validation happen on the server.
-- This script does nothing if the local player is not authorized.
--------------------------------------------------------------------------------

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- AUTHORIZATION CHECK (client-side gate — server still validates everything)
--------------------------------------------------------------------------------
local DevWeaponConfig = require(ReplicatedStorage:WaitForChild("DevWeaponConfig"))

if not DevWeaponConfig.IsAuthorizedDevPlayer(player) then
    return -- silently exit; this script does nothing for non-devs
end

local TOOL_NAME = DevWeaponConfig.TOOL_NAME

--------------------------------------------------------------------------------
-- WAIT FOR REMOTES  (only exist when feature is active on the server)
--------------------------------------------------------------------------------
local fireRemote  = ReplicatedStorage:WaitForChild("DevRocketFire", 10)
local equipRemote = ReplicatedStorage:WaitForChild("DevRocketEquipToggle", 10)

if not fireRemote or not equipRemote then
    -- Server didn't create remotes → feature is disabled in this server type.
    return
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

--- Returns true if any TextBox is currently focused (player is typing).
local function isTyping()
    local focused = UserInputService:GetFocusedTextBox()
    return focused ~= nil
end

--- Find the dev launcher tool wherever it might be (Backpack or Character).
local function findTool()
    local bp   = player:FindFirstChildOfClass("Backpack")
    local char = player.Character
    local inBP   = bp and bp:FindFirstChild(TOOL_NAME)
    local inChar = char and char:FindFirstChild(TOOL_NAME)
    return inBP or inChar
end

--- Returns the aim direction based on the mouse / camera.
local function getAimDirection()
    local mouse = player:GetMouse()
    if mouse and mouse.Hit then
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local origin = hrp.Position
                local target = mouse.Hit.Position
                local dir = (target - origin)
                if dir.Magnitude > 0.01 then
                    return dir.Unit
                end
            end
        end
    end
    -- Fallback: camera look direction
    local cam = Workspace.CurrentCamera
    if cam then
        return cam.CFrame.LookVector
    end
    return Vector3.new(0, 0, -1)
end

--------------------------------------------------------------------------------
-- P KEY  →  EQUIP / UNEQUIP TOGGLE
--------------------------------------------------------------------------------
local toggleDebounce = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode ~= Enum.KeyCode.P then return end
    if isTyping() then return end
    if toggleDebounce then return end

    -- Only proceed if the tool actually exists
    if not findTool() then return end

    toggleDebounce = true
    equipRemote:FireServer()

    -- Small debounce to prevent spam
    task.delay(0.2, function()
        toggleDebounce = false
    end)
end)

--------------------------------------------------------------------------------
-- TOOL ACTIVATED  →  FIRE REQUEST
-- We connect to each instance of the tool whenever it enters the character.
--------------------------------------------------------------------------------
local fireDebounce = false
local currentConnection = nil

local function connectActivated(tool)
    -- Disconnect previous connection if any
    if currentConnection then
        currentConnection:Disconnect()
        currentConnection = nil
    end

    if not tool or not tool:IsA("Tool") then return end

    currentConnection = tool.Activated:Connect(function()
        if fireDebounce then return end
        fireDebounce = true

        local aimDir = getAimDirection()
        fireRemote:FireServer(aimDir)

        -- Client-side cooldown matching server cooldown
        task.delay(DevWeaponConfig.ROCKET_COOLDOWN, function()
            fireDebounce = false
        end)
    end)
end

--- Watch for the tool being equipped (parented to character) or unequipped.
local function watchCharacter(char)
    if not char then return end

    -- Check if tool is already equipped
    local existing = char:FindFirstChild(TOOL_NAME)
    if existing and existing:IsA("Tool") then
        connectActivated(existing)
    end

    char.ChildAdded:Connect(function(child)
        if child.Name == TOOL_NAME and child:IsA("Tool") then
            connectActivated(child)
        end
    end)

    char.ChildRemoved:Connect(function(child)
        if child.Name == TOOL_NAME then
            if currentConnection then
                currentConnection:Disconnect()
                currentConnection = nil
            end
        end
    end)
end

-- Connect for current and future characters
if player.Character then
    watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)
