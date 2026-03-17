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

--- Register a menu with its open/close callbacks.
-- @param name        string   unique menu identifier
-- @param callbacks   table    { open, close, closeInstant, isOpen, group? }
function MenuController.RegisterMenu(name, callbacks)
	menus[name] = callbacks
	print("[MenuController] Registered menu:", name)
end

--- Close every open menu. Pass exceptName to skip one (e.g. when about to open it).
function MenuController.CloseAllMenus(exceptName)
	for name, m in pairs(menus) do
		if name ~= exceptName and m.isOpen() then
			if m.closeInstant then
				m.closeInstant()
			else
				m.close()
			end
		end
	end
	if not exceptName then
		currentMenu = nil
	end
end

--- Open a menu by name, closing any other open menu first.
-- When switching between menus in the same group (e.g. two modal pages),
-- the open callback receives sameGroup = true so it can skip the close/open
-- animation and just swap content in place.
function MenuController.OpenMenu(name)
	local menu = menus[name]
	if not menu then
		warn("[MenuController] OpenMenu: unknown menu", name)
		return
	end

	-- Detect if we are switching within the same group (e.g. Shop ↔ Quests)
	local sameGroup = false
	for n, m in pairs(menus) do
		if n ~= name and m.isOpen() then
			if m.group and menu.group and m.group == menu.group then
				sameGroup = true
			end
			-- Instant-close the other menu
			if m.closeInstant then
				m.closeInstant()
			else
				m.close()
			end
		end
	end

	menu.open(sameGroup)
	currentMenu = name
	print("[MenuController] Opened:", name)
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
		print("[MenuController] Closed:", name)
	end
end

--- Toggle a menu: close it if open, open it (closing others) if closed.
function MenuController.ToggleMenu(name)
	local menu = menus[name]
	if not menu then
		warn("[MenuController] ToggleMenu: unknown menu", name)
		return
	end
	if menu.isOpen() then
		MenuController.CloseMenu(name)
	else
		MenuController.OpenMenu(name)
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

return MenuController
