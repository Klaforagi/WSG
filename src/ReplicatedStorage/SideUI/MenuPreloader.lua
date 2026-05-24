-- MenuPreloader.lua
-- Small state machine for warming modal menus before the player opens them.

local MenuPreloader = {}

local DEBUG_MENU_PRELOAD = false
MenuPreloader.DEBUG_MENU_PRELOAD = DEBUG_MENU_PRELOAD

local State = {
    NotStarted = "NotStarted",
    Loading = "Loading",
    Ready = "Ready",
    Failed = "Failed",
}
MenuPreloader.State = State

local menus = {}
local WAIT_STEP_SECONDS = 0.03

local function debugPrint(...)
    if MenuPreloader.DEBUG_MENU_PRELOAD then
        print("[MenuPreloader]", ...)
    end
end

local function cleanError(err)
    return tostring(err or "unknown error")
end

function MenuPreloader.SetDebug(enabled)
    MenuPreloader.DEBUG_MENU_PRELOAD = enabled == true
end

function MenuPreloader.RegisterMenu(name, config)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local entry = menus[name]
    if entry then
        entry.config = config or entry.config or {}
        return entry
    end

    entry = {
        name = name,
        config = config or {},
        state = State.NotStarted,
        result = nil,
        error = nil,
        startedAt = 0,
        finishedAt = 0,
    }
    menus[name] = entry
    return entry
end

function MenuPreloader.GetEntry(name)
    return menus[name]
end

function MenuPreloader.GetState(name)
    local entry = menus[name]
    return entry and entry.state or nil
end

function MenuPreloader.GetResult(name)
    local entry = menus[name]
    if entry and entry.state == State.Ready then
        return entry.result
    end
    return nil
end

function MenuPreloader.IsReady(name)
    local entry = menus[name]
    return entry and entry.state == State.Ready or false
end

function MenuPreloader.ResetMenu(name)
    local entry = menus[name]
    if not entry or entry.state == State.Loading then
        return false
    end

    local oldResult = entry.result
    if oldResult and entry.config and type(entry.config.onReset) == "function" then
        pcall(entry.config.onReset, oldResult)
    end

    entry.state = State.NotStarted
    entry.result = nil
    entry.error = nil
    entry.startedAt = 0
    entry.finishedAt = 0
    return true
end

local function waitForEntry(entry, timeoutSeconds)
    local started = os.clock()
    while entry.state == State.Loading or entry.state == State.NotStarted do
        if type(timeoutSeconds) == "number" and timeoutSeconds >= 0 then
            local elapsed = os.clock() - started
            if elapsed >= timeoutSeconds then
                return nil, "Timed out waiting for " .. entry.name
            end
        end
        task.wait(WAIT_STEP_SECONDS)
    end

    if entry.state == State.Ready then
        return entry.result, nil
    end
    return nil, entry.error or entry.state
end

function MenuPreloader.WaitForMenu(name, timeoutSeconds)
    local entry = menus[name]
    if not entry then
        return nil, "Unknown menu: " .. tostring(name)
    end
    if entry.state == State.Ready then
        return entry.result, nil
    end
    if entry.state ~= State.Loading and entry.state ~= State.NotStarted then
        return nil, entry.error or entry.state
    end
    return waitForEntry(entry, timeoutSeconds)
end

function MenuPreloader.PreloadMenu(name)
    local entry = menus[name]
    if not entry then
        warn("[MenuPreloader] Unknown menu: " .. tostring(name))
        return nil, "Unknown menu"
    end

    if entry.state == State.Ready then
        return entry.result, nil
    end
    if entry.state == State.Loading then
        return waitForEntry(entry, nil)
    end
    if entry.state == State.Failed then
        return nil, entry.error or "Failed"
    end

    entry.state = State.Loading
    entry.error = nil
    entry.startedAt = os.clock()
    entry.finishedAt = 0
    debugPrint("Starting preload:", name)

    local config = entry.config or {}
    local ok, result = xpcall(function()
        if type(config.preload) ~= "function" then
            return true
        end
        return config.preload(name)
    end, function(err)
        return cleanError(err) .. "\n" .. debug.traceback()
    end)

    entry.finishedAt = os.clock()
    if ok then
        entry.result = result
        entry.state = State.Ready
        debugPrint("Ready:", name)
        if type(config.onReady) == "function" then
            pcall(config.onReady, result)
        end
        return result, nil
    end

    entry.result = nil
    entry.error = cleanError(result)
    entry.state = State.Failed
    warn("[MenuPreloader] Failed: " .. tostring(name) .. " - " .. entry.error)
    if type(config.onFailed) == "function" then
        pcall(config.onFailed, entry.error)
    end
    return nil, entry.error
end

function MenuPreloader.StartPreload(name)
    local entry = menus[name]
    if not entry then
        warn("[MenuPreloader] Unknown menu: " .. tostring(name))
        return nil
    end
    if entry.state == State.Ready or entry.state == State.Loading then
        return entry.state
    end

    task.spawn(function()
        MenuPreloader.PreloadMenu(name)
    end)
    return State.Loading
end

function MenuPreloader.PreloadMenus(names, staggerSeconds)
    if type(names) ~= "table" then return end
    for _, name in ipairs(names) do
        MenuPreloader.PreloadMenu(name)
        if type(staggerSeconds) == "number" and staggerSeconds > 0 then
            task.wait(staggerSeconds)
        end
    end
    debugPrint("All high priority menus preloaded")
end

function MenuPreloader.GetRegisteredMenus()
    local copy = {}
    for name, entry in pairs(menus) do
        copy[name] = {
            state = entry.state,
            error = entry.error,
            startedAt = entry.startedAt,
            finishedAt = entry.finishedAt,
        }
    end
    return copy
end

return MenuPreloader