-- MenuController.lua
-- Centralized menu management for all KingsGround menus.
-- Ensures only one menu is open at a time and switching is instant (one click).
--
-- Usage:
--   local MenuController = require(path.to.MenuController)
--
--   MenuController.RegisterMenu("Shop", {
--       open       = function(sameGroup) ... end,  -- show this menu
--       close      = function() ... end,            -- animated close
--       closeInstant = function() ... end,          -- instant close (for switching)
--       isOpen     = function() return bool end,    -- is this menu visible?
--       group      = "modal",                       -- optional: menus in the same group
--   })                                              -- swap content without full close/open
--
--   MenuController.ToggleMenu("Shop")
--   MenuController.OpenMenu("Quests")
--   MenuController.CloseMenu("Shop")
--   MenuController.CloseAllMenus()
--
-- To add a future menu, call RegisterMenu with the same callback table shape.

local MenuController = {}

local menus = {}        -- { [name] = { open, close, closeInstant, isOpen, group } }
local currentMenu = nil -- name of the currently open menu (or nil)

-- Callbacks fired whenever the overall "any menu open" state changes.
-- Each callback receives (isAnyOpen: boolean, menuName: string, action: "open"|"close")
local _onChangeCallbacks = {}

--- Register a callback to be fired when any menu opens or closes.
function MenuController.OnMenuStateChanged(callback)
	table.insert(_onChangeCallbacks, callback)
end

--- Internal: fire all registered state-change callbacks.
local function fireStateChanged(menuName, action)
	local anyOpen = MenuController.IsAnyMenuOpen()
	for _, cb in ipairs(_onChangeCallbacks) do
		pcall(cb, anyOpen, menuName, action)
	end
end

--- Register a menu with its open/close callbacks.
-- @param name        string   unique menu identifier
-- @param callbacks   table    { open, close, closeInstant, isOpen, group? }
function MenuController.RegisterMenu(name, callbacks)
	menus[name] = callbacks
end

--- Close every open menu. Pass exceptName to skip one (e.g. when about to open it).
function MenuController.CloseAllMenus(exceptName)
	for name, m in pairs(menus) do
		if name ~= exceptName and m.isOpen() then
			if m.closeInstant then
				m.closeInstant(false)
			else
				m.close()
			end
		end
	end
	if not exceptName then
		currentMenu = nil
	end
	fireStateChanged("all", "close")
end

--- Open a menu by name, closing any other open menu first.
-- When switching between menus in the same group (e.g. two modal pages),
-- the open callback receives sameGroup = true so it can skip the close/open
-- animation and just swap content in place.
-- closeInstant receives sameGroup so same-group menus can keep their shared
-- overlay visible during the switch (prevents flicker).
function MenuController.OpenMenu(name, ...)
	local menu = menus[name]
	if not menu then
		warn("[MenuController] OpenMenu: unknown menu", name)
		return
	end

	-- Detect if we are switching within the same group (e.g. Shop ↔ Quests)
	local sameGroup = false
	local closingMenuName = nil
	for n, m in pairs(menus) do
		if n ~= name and m.isOpen() then
			closingMenuName = n
			if m.group and menu.group and m.group == menu.group then
				sameGroup = true
			end
			-- Instant-close the other menu.
			-- sameGroup: true when same overlay group (content swap only).
			-- isSwitching (2nd arg): true so menus know another menu is
			--   about to open and should NOT tear down their backdrop.
			if m.closeInstant then
				m.closeInstant(sameGroup, true)
			else
				m.close()
			end
		end
	end

	-- forward any extra args (e.g. a parent ScreenGui) to the menu.open callback
	menu.open(sameGroup, ...)
	currentMenu = name
	fireStateChanged(name, "open")
end

--- Close a specific menu (animated).
function MenuController.CloseMenu(name)
	local menu = menus[name]
	if not menu then return end
	if menu.isOpen() then
		menu.close()
		if currentMenu == name then
			currentMenu = nil
		end
		fireStateChanged(name, "close")
	end
end

--- Toggle a menu: close it if open, open it (closing others) if closed.
function MenuController.ToggleMenu(name, ...)
	local menu = menus[name]
	if not menu then
		warn("[MenuController] ToggleMenu: unknown menu", name)
		return
	end
	if menu.isOpen() then
		MenuController.CloseMenu(name)
	else
		MenuController.OpenMenu(name, ...)
	end
end

--- Check whether a specific menu is currently open.
function MenuController.IsOpen(name)
	local menu = menus[name]
	return menu and menu.isOpen() or false
end

--- Get the name of the currently open menu, or nil.
function MenuController.GetCurrentMenu()
	return currentMenu
end

--- Returns true if ANY registered menu reports itself as open.
--- More robust than GetCurrentMenu() because it polls each menu's isOpen()
--- callback directly instead of relying on the tracked currentMenu variable.
function MenuController.IsAnyMenuOpen()
	for _, m in pairs(menus) do
		if m.isOpen and m.isOpen() then
			return true
		end
	end
	return currentMenu ~= nil
end

--- Returns the name of the first registered menu that reports isOpen=true,
--- or currentMenu if set, or nil if nothing is open.
function MenuController.GetOpenMenuName()
	for name, m in pairs(menus) do
		if m.isOpen and m.isOpen() then
			return name
		end
	end
	if currentMenu ~= nil then
		return currentMenu .. " (stale currentMenu)"
	end
	return nil
end

return MenuController
