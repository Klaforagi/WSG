--------------------------------------------------------------------------------
-- DevRocketGrant.server.lua  –  Server script that manages the dev rocket
-- launcher lifecycle: tool granting, fire-request handling, cleanup.
--
-- Lives in ServerScriptService.
-- Uses DevWeaponConfig for authorization and DevRocketService for logic.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevWeaponConfig  = require(ReplicatedStorage:WaitForChild("DevWeaponConfig"))
local DevRocketService = require(ServerScriptService:WaitForChild("DevRocketService"))

local TOOL_NAME = DevWeaponConfig.TOOL_NAME
local LOG_PREFIX = "[DevRocket]"

--------------------------------------------------------------------------------
-- CHECK SERVER ELIGIBILITY ONCE AT STARTUP
--------------------------------------------------------------------------------
local serverAllowed, serverReason = DevWeaponConfig.IsDevRocketAllowedInThisServer()
print(LOG_PREFIX, serverAllowed and "Feature ENABLED" or "Feature DISABLED", "-", serverReason)

if not serverAllowed then
    -- Nothing to do — exit early, no remotes created, no events connected.
    return
end

--------------------------------------------------------------------------------
-- REMOTES  (only created when the feature is active)
--------------------------------------------------------------------------------
local function getOrCreateRemoteEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end

local fireRemote  = getOrCreateRemoteEvent("DevRocketFire")
local equipRemote = getOrCreateRemoteEvent("DevRocketEquipToggle")

--------------------------------------------------------------------------------
-- TOOL TEMPLATE  (created once, cloned per-grant)
--------------------------------------------------------------------------------
local toolTemplate = DevRocketService.CreateToolTemplate()

--------------------------------------------------------------------------------
-- GRANT LOGIC
--------------------------------------------------------------------------------
local function hasToolAnywhere(player)
    local bp   = player:FindFirstChildOfClass("Backpack")
    local char = player.Character
    if bp and bp:FindFirstChild(TOOL_NAME) then return true end
    if char and char:FindFirstChild(TOOL_NAME) then return true end
    return false
end

local function grantLauncher(player)
    if not DevWeaponConfig.IsAuthorizedDevPlayer(player) then
        print(LOG_PREFIX, "Player not authorized:", player.Name, player.UserId)
        return
    end

    if hasToolAnywhere(player) then
        print(LOG_PREFIX, "Duplicate tool prevented for", player.Name)
        return
    end

    local bp = player:FindFirstChildOfClass("Backpack")
    if not bp then
        warn(LOG_PREFIX, "No Backpack for", player.Name)
        return
    end

    local clone = toolTemplate:Clone()
    -- Sanitize parts (same pattern as Loadout.server.lua)
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d.CanCollide = false end)
            pcall(function() d.CanTouch = false end)
            pcall(function() d.CanQuery = false end)
            pcall(function() d.Massless = true end)
        end
    end
    clone.Parent = bp

    print(LOG_PREFIX, "Granted launcher to", player.Name, "(" .. tostring(player.UserId) .. ")")
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    if not DevWeaponConfig.IsAuthorizedDevPlayer(player) then return end

    player.CharacterAdded:Connect(function()
        -- Brief yield so the engine creates the fresh Backpack
        task.wait(0.3)
        grantLauncher(player)
    end)

    -- Handle already-spawned character (Studio fast-start)
    if player.Character then
        task.defer(function()
            task.wait(0.3)
            grantLauncher(player)
        end)
    end
end

local function onPlayerRemoving(player)
    DevRocketService.ClearPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Catch players already in-game (Studio)
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end

--------------------------------------------------------------------------------
-- FIRE REQUEST HANDLER
--------------------------------------------------------------------------------
fireRemote.OnServerEvent:Connect(function(player, aimDirection)
    local ok, reason = DevRocketService.ValidateFireRequest(player)
    if not ok then
        if reason ~= "Cooldown active" then
            print(LOG_PREFIX, "Fire rejected for", player.Name, "-", reason)
        end
        return
    end

    -- Final type-check on aimDirection
    if typeof(aimDirection) ~= "Vector3" then
        print(LOG_PREFIX, "Invalid aimDirection from", player.Name)
        return
    end

    -- Magnitude sanity: must be close to unit length
    if aimDirection.Magnitude < 0.01 or aimDirection.Magnitude > 2 then
        print(LOG_PREFIX, "Suspicious aimDirection magnitude from", player.Name, aimDirection.Magnitude)
        return
    end

    DevRocketService.FireRocket(player, aimDirection)
end)

--------------------------------------------------------------------------------
-- EQUIP TOGGLE REQUEST HANDLER
-- The client asks the server to equip/unequip the dev launcher.
--------------------------------------------------------------------------------
equipRemote.OnServerEvent:Connect(function(player)
    if not DevWeaponConfig.IsAuthorizedDevPlayer(player) then return end

    local char = player.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local bp = player:FindFirstChildOfClass("Backpack")

    -- Check if currently equipped (in character)
    local equippedTool = char:FindFirstChild(TOOL_NAME)
    if equippedTool and equippedTool:IsA("Tool") then
        -- Unequip: move back to backpack
        hum:UnequipTools()
        return
    end

    -- Check if in backpack
    if bp then
        local bpTool = bp:FindFirstChild(TOOL_NAME)
        if bpTool and bpTool:IsA("Tool") then
            hum:EquipTool(bpTool)
        end
    end
end)
