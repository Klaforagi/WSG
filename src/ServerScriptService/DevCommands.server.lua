local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Safely require `DevUserIds` and `SizeService`. If missing, provide safe no-op fallbacks and warn.
local DevUserIds
do
    local inst = ReplicatedStorage:FindFirstChild("DevUserIds")
    if not inst then
        warn("[DevCommands] DevUserIds ModuleScript not found in ReplicatedStorage; defaulting IsDev -> false")
        DevUserIds = { IsDev = function() return false end }
    else
        local ok, mod = pcall(require, inst)
        if not ok or type(mod) ~= "table" then
            warn("[DevCommands] require(DevUserIds) failed; defaulting IsDev -> false; error:", mod)
            DevUserIds = { IsDev = function() return false end }
        else
            DevUserIds = mod
        end
    end
end

local SizeService
local HumanoidStatService -- may be filled if we find the module
do
    local function findModuleByName(root, name)
        local inst = root:FindFirstChild(name)
        if inst and inst.ClassName == "ModuleScript" then
            return inst
        end
        for _, v in ipairs(root:GetDescendants()) do
            if v.ClassName == "ModuleScript" then
                if v.Name == name or v.Name:lower():match(name:lower()) then
                    return v
                end
            end
        end
        return nil
    end

    -- Try to load an explicit SizeService module first
    local inst = findModuleByName(ServerScriptService, "SizeService")
    if inst then
        local ok, mod = pcall(function() return require(inst) end)
        if ok and type(mod) == "table" then
            SizeService = mod
        else
            warn("[DevCommands] require(SizeService) failed; error:", mod)
        end
    end

    -- If no SizeService, try to wrap HumanoidStatService to act like SizeService
    if not SizeService then
        local humInst = findModuleByName(ServerScriptService, "HumanoidStatService")
        if humInst then
            local ok, humMod = pcall(function() return require(humInst) end)
            if ok and type(humMod) == "table" then
                HumanoidStatService = humMod
                SizeService = {
                    SetModifier = function(player, modifierId, options)
                        return HumanoidStatService:SetModifier(player, "Size", modifierId, options)
                    end,
                    RemoveModifier = function(player, modifierId)
                        return HumanoidStatService:RemoveModifier(player, "Size", modifierId)
                    end,
                    GetSize = function(player)
                        local ok2, val = pcall(function() return HumanoidStatService:GetFinalStat(player, "Size") end)
                        if ok2 and type(val) == "number" then return val end
                        return 10
                    end,
                }
            else
                warn("[DevCommands] require(HumanoidStatService) failed; error:", humMod)
            end
        end
    end

    -- Final fallback: no-op service
    if not SizeService then
        warn("[DevCommands] SizeService ModuleScript not found in ServerScriptService; size commands will be no-ops")
        SizeService = {
            SetModifier = function() end,
            RemoveModifier = function() end,
            GetSize = function() return 10 end,
        }
    end
end

local devAdjustments = {} -- [player] = cumulative additive adjustment
-- Set to true to allow any player to use forwarded dev commands (useful for Play testing).
-- Remember to set this to false for production servers if you want to restrict to devs only.
local ALLOW_DEV_COMMANDS_FOR_ALL = true

local function applyAdjustment(player, delta)
    if not player then return end
    local cur = devAdjustments[player] or 0
    local new = cur + (tonumber(delta) or 0)
    devAdjustments[player] = new
    if new == 0 then
        if HumanoidStatService and type(HumanoidStatService.SetModifier) == "function" then
            pcall(function() HumanoidStatService:RemoveModifier(player, "Size", "dev_size_adjust_size") end)
        else
            pcall(function() SizeService:RemoveModifier(player, "dev_size_adjust") end)
        end
    else
        if HumanoidStatService and type(HumanoidStatService.SetModifier) == "function" then
            pcall(function()
                HumanoidStatService:SetModifier(player, "Size", "dev_size_adjust_size", {
                    additive = new,
                    source = "dev_command",
                })
            end)
        else
            pcall(function()
                SizeService:SetModifier(player, "dev_size_adjust", {
                    additive = new,
                    source = "dev_command",
                })
            end)
        end
    end
    -- feedback to server log
    print("[DevCommands] Set dev size adjustment for", player.Name, "to", new)
    -- debug: print actual final stat if available
    if HumanoidStatService and type(HumanoidStatService.GetFinalStat) == "function" then
        local ok, val = pcall(function() return HumanoidStatService:GetFinalStat(player, "Size") end)
        if ok then
            print("[DevCommands] HumanoidStatService final Size for", player.Name, "=", val)
        end
    elseif SizeService and type(SizeService.GetSize) == "function" then
        local ok, val = pcall(function() return SizeService:GetSize(player) end)
        if ok then
            print("[DevCommands] SizeService reported Size for", player.Name, "=", val)
        end
    end
end

local function parseChat(player, msg)
    if not msg or type(msg) ~= "string" then return end
    local s = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- match patterns like "+3 size" or "-2.5 size" or "3 size" (implicit +)
    local numstr = s:match("^([%+%-]?%d+%.?%d*)%s+size$")
    if not numstr then
        -- also allow commands like "+3size" without space
        numstr = s:match("^([%+%-]?%d+%.?%d*)size$")
    end
    if not numstr then return end
    local num = tonumber(numstr)
    if not num then return end
    applyAdjustment(player, num)
end

local function onPlayerAdded(player)
    if not player then return end
    -- connect chat for studio/dev players as fallback
    player.Chatted:Connect(function(msg)
        -- Only handle classic `Chatted` on server when forwarded-all mode is disabled.
        -- This avoids duplicate handling when the client also forwards chat via `DevCommandEvent`.
        if not ALLOW_DEV_COMMANDS_FOR_ALL and (DevUserIds.IsDev(player) or RunService:IsStudio()) then
            parseChat(player, msg)
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Create RemoteEvent to receive forwarded chat from client UI
local function ensureEvent(name)
    local ev = ReplicatedStorage:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = ReplicatedStorage
    end
    return ev
end

local devEvent = ensureEvent("DevCommandEvent")
devEvent.OnServerEvent:Connect(function(player, msg)
    if not player or type(msg) ~= "string" then return end
    -- Accept forwarded commands when running in Studio or from devs.
    -- Additionally allow all players to send forwarded commands when `ALLOW_DEV_COMMANDS_FOR_ALL` is true
    if not DevUserIds.IsDev(player) and not RunService:IsStudio() and not ALLOW_DEV_COMMANDS_FOR_ALL then
        warn("[DevCommands] Non-dev attempted to send dev command:", player.Name)
        return
    end
    -- debug log
    print("[DevCommands] Received forwarded chat from", player.Name, "->", msg)
    parseChat(player, msg)
end)

return nil

