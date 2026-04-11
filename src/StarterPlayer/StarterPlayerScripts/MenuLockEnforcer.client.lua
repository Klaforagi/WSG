--------------------------------------------------------------------------------
-- MenuLockEnforcer.client.lua
-- Global client-side system that prevents weapon equipping while any menu is open.
--
-- Responsibilities:
--   1. Listens to MenuController state changes + polls unregistered popups
--   2. Sets player attribute "MenuOpen" (replicated to server for validation)
--   3. Fires MenuStateChanged remote so server can enforce too
--   4. Disables CoreGui Backpack while menu is open (blocks default Roblox hotbar)
--   5. Force-unequips any tool in Character while menu-locked
--   6. Watches Character.ChildAdded as a failsafe to catch tools equipped by
--      any code path while locked
--
-- This is the SINGLE SOURCE OF TRUTH for "is the player menu-locked".
-- Other scripts (Hotbar, ToolMelee, etc.) should check:
--     player:GetAttribute("MenuOpen") == true
-- or:
--     _G.IsMenuLocked and _G.IsMenuLocked()
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player   = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- MENU CONTROLLER (the registered-menu system)
--------------------------------------------------------------------------------
local MenuController = nil
local MenuState = nil
pcall(function()
    local SideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    if SideUI then
        local mc = SideUI:FindFirstChild("MenuController")
        if mc then MenuController = require(mc) end
        local ms = SideUI:FindFirstChild("MenuState")
        if ms then MenuState = require(ms) end
    end
end)

--------------------------------------------------------------------------------
-- SERVER REMOTE (tells server when menu state changes)
--------------------------------------------------------------------------------
local menuStateRemote = ReplicatedStorage:WaitForChild("MenuStateChanged", 10)

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local locked = false   -- current menu-lock state

-- ScreenGui names of blocking popups that MIGHT not register with MenuController
-- (fallback safety net — ideally all are registered, but this catches edge cases).
local UNREGISTERED_POPUP_GUIS = {
    -- Only include popups that should block equips even when they appear
    -- without the player explicitly opening them. DailyRewards is a
    -- user-opened menu (registered via MenuController) so it should NOT
    -- be in this fallback list.
    "CrateOpenScreen",
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

--- Check if any unregistered popup ScreenGui is currently visible.
local function isUnregisteredPopupOpen()
    for _, guiName in ipairs(UNREGISTERED_POPUP_GUIS) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui and gui:IsA("ScreenGui") and gui.Enabled then
            if guiName == "CrateOpenScreen" then return true end
            for _, child in ipairs(gui:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    return true
                end
            end
        end
    end
    return false
end

--- Returns the name of the unregistered popup that is blocking, or nil.
local function getUnregisteredPopupName()
    for _, guiName in ipairs(UNREGISTERED_POPUP_GUIS) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui and gui:IsA("ScreenGui") and gui.Enabled then
            if guiName == "CrateOpenScreen" then return guiName end
            for _, child in ipairs(gui:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    return guiName .. "/" .. child.Name
                end
            end
        end
    end
    return nil
end

--- The definitive "is any menu open" check.
local function computeMenuOpen()
    -- Prefer authoritative MenuState when available
    if MenuState then
        return MenuState.IsAnyMenuOpen()
    end
    if MenuController and MenuController.IsAnyMenuOpen() then
        return true
    end
    if isUnregisteredPopupOpen() then
        return true
    end
    return false
end

--- Safely toggle the default Roblox Backpack CoreGui.
local function setCoreBackpack(enabled)
    -- Roblox can reject SetCoreGuiEnabled during startup; retry a few times.
    for _ = 1, 3 do
        local ok = pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
        end)
        if ok then return end
        task.wait(0.1)
    end
end

--- Force-unequip any tool currently in the player's character.
local function forceUnequip()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:UnequipTools() end)
    end
end

--------------------------------------------------------------------------------
-- APPLY LOCK STATE
-- Called whenever the menu-open state may have changed.
--------------------------------------------------------------------------------
local function applyLockState(nowOpen)
    if nowOpen == locked then return end -- no change
    locked = nowOpen

    -- 1. Set replicated player attribute (server reads this)
    pcall(function() player:SetAttribute("MenuOpen", locked) end)

    -- 2. Tell server explicitly via remote
    if menuStateRemote then
        pcall(function() menuStateRemote:FireServer(locked) end)
    end

    -- 3. Toggle CoreGui Backpack
    if locked then
        setCoreBackpack(false)
    else
        -- Only re-enable if the Hotbar script hasn't permanently disabled it.
        -- In this game the default backpack is always off (Hotbar replaces it),
        -- so we leave it disabled.
    end

    -- 4. If locking, immediately unequip any held tool
    if locked then
        forceUnequip()
    end
end

--------------------------------------------------------------------------------
-- GLOBAL API (for scripts that can't easily require a module)
--------------------------------------------------------------------------------
_G.IsMenuLocked = function()
    return locked
end

--- Returns a human-readable string describing what menu is blocking equip, or nil.
_G.GetMenuLockReason = function()
    if MenuState then
        local open = MenuState.GetOpenMenus()
        if open and #open > 0 then return open[1] end
    end
    if MenuController then
        local name = MenuController.GetOpenMenuName()
        if name then return name end
    end
    local popup = getUnregisteredPopupName()
    if popup then return popup end
    return "unknown"
end

--------------------------------------------------------------------------------
-- LISTEN TO MENUCONTROLLER (registered menus: Shop, Inventory, etc.)
--------------------------------------------------------------------------------
-- Prefer subscribing to MenuState (driven by real GUI visibility). Fallback to MenuController.
if MenuState and MenuState.OnChange then
    MenuState.OnChange(function(_menuName, _isOpen)
        applyLockState(computeMenuOpen())
    end)
elseif MenuController and MenuController.OnMenuStateChanged then
    MenuController.OnMenuStateChanged(function(_anyOpen, _menuName, _action)
        applyLockState(computeMenuOpen())
    end)
end

--------------------------------------------------------------------------------
-- POLL UNREGISTERED POPUPS (fallback for menus not in MenuController)
-- Runs every 0.25s — lightweight since it only checks a few ScreenGui names.
--------------------------------------------------------------------------------
task.spawn(function()
    while true do
        task.wait(0.25)
        local nowOpen = computeMenuOpen()
        if nowOpen ~= locked then
            applyLockState(nowOpen)
        end
    end
end)

--------------------------------------------------------------------------------
-- CHARACTER FAILSAFE
-- If a tool somehow gets parented into Character while locked, unequip it.
--------------------------------------------------------------------------------
local function watchCharacter(char)
    if not char then return end
    char.ChildAdded:Connect(function(child)
        if not locked then return end
        if child:IsA("Tool") then
            task.defer(forceUnequip)
        end
    end)
end

-- Watch current and future characters
if player.Character then watchCharacter(player.Character) end
player.CharacterAdded:Connect(watchCharacter)

--------------------------------------------------------------------------------
-- INITIAL STATE
--------------------------------------------------------------------------------
applyLockState(computeMenuOpen())
print("[MenuLock] MenuLockEnforcer initialized | locked =", locked)
