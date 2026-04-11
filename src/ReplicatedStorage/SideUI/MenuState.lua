-- MenuState.lua
-- Centralized authoritative menu visibility tracker.
-- Tracks menus by name and watches GUI instances (Visible/Enabled),
-- or accepts custom isOpen provider functions. Cleans up stale entries.

local MenuState = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local _entries = {} -- [name] = { gui=Instance?, isOpenFunc=fn?, conns={}, lastOpen=bool }
local _onChange = {}

local function safeCall(fn)
    if not fn then return nil end
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function evaluateEntry(name, e)
    -- Return true/false whether the menu is actually open now.
    if e.isOpenFunc then
        local ok, res = pcall(e.isOpenFunc)
        if ok and type(res) == "boolean" then
            return res
        end
    end
    if e.gui and e.gui:IsA("ScreenGui") then
        return e.gui.Enabled == true
    end
    if e.gui and e.gui:IsA("GuiObject") then
        -- use Visible for frames/panels
        return e.gui.Visible == true
    end
    return false
end

local function fireChange(name, isOpen)
    for _, cb in ipairs(_onChange) do
        pcall(cb, name, isOpen)
    end
end

local function cleanupEntry(name)
    local e = _entries[name]
    if not e then return end
    -- disconnect conns
    if e.conns then
        for _, c in ipairs(e.conns) do
            pcall(function() c:Disconnect() end)
        end
    end
    _entries[name] = nil
    print("[MenuState] Removed stale menu:", name)
end

local function syncEntry(name, e)
    -- Remove if gui destroyed or not in PlayerGui
    if e.gui then
        if not e.gui.Parent then
            cleanupEntry(name)
            return
        end
        -- If it's a ScreenGui ensure it belongs to a PlayerGui or is valid
        -- If the gui is descendant of Players.LocalPlayer.PlayerGui that's fine.
        -- Otherwise still allow (some modules create ScreenGuis elsewhere) but
        -- rely on Destroying/AncestryChanged to prune.
    end

    local nowOpen = evaluateEntry(name, e)
    if e.lastOpen ~= nowOpen then
        e.lastOpen = nowOpen
        fireChange(name, nowOpen)
    end
end

local function ensureWatch(name, e)
    e.conns = e.conns or {}
    if e.gui then
        -- Watch Visible (Frames) and Enabled (ScreenGui) property changes
        if e.gui:GetAttribute("_menuStateWatching") then
            -- already watched by another registration of same instance
        else
            e.gui:SetAttribute("_menuStateWatching", true)
        end

        -- Visible
        if e.gui.GetPropertyChangedSignal then
            local ok, visSig = pcall(function()
                return e.gui:GetPropertyChangedSignal("Visible")
            end)
            if ok and visSig then
                table.insert(e.conns, visSig:Connect(function()
                    syncEntry(name, e)
                end))
            end
            local ok2, enSig = pcall(function()
                return e.gui:GetPropertyChangedSignal("Enabled")
            end)
            if ok2 and enSig then
                table.insert(e.conns, enSig:Connect(function()
                    syncEntry(name, e)
                end))
            end
        end

        -- AncestryChanged: cleanup if removed from hierarchy
        table.insert(e.conns, e.gui.AncestryChanged:Connect(function(_, parent)
            -- If gui removed (parent nil) or it's no longer in the game tree, clean up
            if not e.gui.Parent then
                cleanupEntry(name)
            else
                -- sync state when reparented
                syncEntry(name, e)
            end
        end))

        -- Destroying event
        table.insert(e.conns, e.gui.Destroying:Connect(function()
            cleanupEntry(name)
        end))
    end
end

-- Public API

-- RegisterMenu(name, provider)
-- provider may be:
--  * an Instance (ScreenGui or Frame)
--  * a table { gui = Instance?, isOpen = function() -> bool }
--  * a function that returns boolean (isOpen)
function MenuState.RegisterMenu(name, provider)
    if not name or type(name) ~= "string" then return end
    if _entries[name] then
        -- prevent duplicate registration; update provider if needed
        local e = _entries[name]
        if type(provider) == "table" then
            e.gui = provider.gui or e.gui
            e.isOpenFunc = provider.isOpen or e.isOpenFunc
        elseif typeof(provider) == "Instance" then
            e.gui = provider
        elseif type(provider) == "function" then
            e.isOpenFunc = provider
        end
        syncEntry(name, e)
        return
    end

    local e = { gui = nil, isOpenFunc = nil, conns = {}, lastOpen = false }
    if type(provider) == "table" then
        e.gui = provider.gui
        e.isOpenFunc = provider.isOpen
    elseif typeof(provider) == "Instance" then
        e.gui = provider
    elseif type(provider) == "function" then
        e.isOpenFunc = provider
    else
        return
    end

    _entries[name] = e
    ensureWatch(name, e)
    syncEntry(name, e)
    print("[MenuState] Registered", name)
end

function MenuState.UnregisterMenu(name)
    if not name or type(name) ~= "string" then return end
    if _entries[name] then
        cleanupEntry(name)
    end
end

function MenuState.IsAnyMenuOpen()
    -- Perform a quick sync before returning
    for name, e in pairs(_entries) do
        syncEntry(name, e)
    end
    for name, e in pairs(_entries) do
        if e.lastOpen == true then
            return true
        end
    end
    return false
end

function MenuState.GetOpenMenus()
    local out = {}
    for name, e in pairs(_entries) do
        if e.lastOpen == true then
            table.insert(out, name)
        end
    end
    return out
end

function MenuState.GetAllEntries()
    -- returns table copy for debugging
    local out = {}
    for name, e in pairs(_entries) do
        out[name] = {
            gui = e.gui,
            hasGui = e.gui ~= nil,
            lastOpen = e.lastOpen,
        }
    end
    return out
end

function MenuState.DebugDump()
    print("[MenuState] === Dump ===")
    for name, info in pairs(MenuState.GetAllEntries()) do
        local guiInfo = info.hasGui and (tostring(info.gui) .. " parent=" .. tostring(info.gui.Parent and info.gui.Parent.Name or "nil")) or "no-gui"
        print("[MenuState] ", name, "open=", tostring(info.lastOpen), guiInfo)
    end
    print("[MenuState] AnyOpen=", tostring(MenuState.IsAnyMenuOpen()))
    print("[MenuState] === End ===")
end

function MenuState.OnChange(cb)
    if type(cb) == "function" then
        table.insert(_onChange, cb)
    end
end

-- Periodic cleanup in case something slips through
RunService.Heartbeat:Connect(function()
    for name, e in pairs(_entries) do
        if e.gui and not e.gui.Parent then
            cleanupEntry(name)
        end
    end
end)

return MenuState
