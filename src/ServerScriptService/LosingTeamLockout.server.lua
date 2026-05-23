-- LosingTeamLockout.server.lua
--
-- Reworked behavior:
-- 1) Losers receive a temporary "Defeat" movement debuff: -10 speed.
-- 2) Debuff lasts 10 seconds OR until death, whichever comes first.
-- 3) During EndGame, losers also get a temporary lock flag that blocks
--    reset/team-change actions (handled by other systems).
-- 4) On Intermission (lobby return) and on next MatchStart, all defeat states
--    are fully cleared.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local MOVEMENT_SPEED_STAT = "MovementSpeed"
local DEFEAT_MODIFIER_ID = "defeat_debuff"
local DEFEAT_SPEED_PENALTY = -10
local DEFEAT_DURATION = 10

local TOOLS_LOCKED_ATTR = "ToolsLocked" -- kept for compatibility with weapon validation checks
local DEFEAT_ACTIVE_ATTR = "DefeatActive"
local DEFEAT_END_TIME_ATTR = "DefeatEndTime"
local DEFEAT_LOCK_ATTR = "DefeatLockActive"

local deathConnections = {}
local charAddedConnections = {}
local charChildAddedConnections = {}

local function disconnectConnectionTableEntry(connectionTable, player)
    local conn = connectionTable[player]
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
        connectionTable[player] = nil
    end
end

local function enforceUnequipped(player)
    if not player or not player.Parent then
        return
    end
    local character = player.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            humanoid:UnequipTools()
        end)
    end
end

local function disconnectToolLockWatcher(player)
    disconnectConnectionTableEntry(charChildAddedConnections, player)
end

local function connectToolLockWatcher(player)
    disconnectToolLockWatcher(player)

    local character = player.Character
    if not character then
        return
    end

    charChildAddedConnections[player] = character.ChildAdded:Connect(function(child)
        if not child or not child:IsA("Tool") then
            return
        end
        if player:GetAttribute(DEFEAT_LOCK_ATTR) == true or player:GetAttribute(TOOLS_LOCKED_ATTR) == true then
            task.defer(function()
                enforceUnequipped(player)
            end)
        end
    end)
end

local function disconnectDeathWatcher(player)
    local conn = deathConnections[player]
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
        deathConnections[player] = nil
    end
end

local function clearDefeatDebuff(player)
    if not player or not player.Parent then
        return
    end

    pcall(function()
        HumanoidStatService:RemoveModifier(player, MOVEMENT_SPEED_STAT, DEFEAT_MODIFIER_ID)
    end)

    player:SetAttribute(DEFEAT_ACTIVE_ATTR, false)
    player:SetAttribute(DEFEAT_END_TIME_ATTR, 0)
end

local function clearDefeatState(player, clearLock)
    clearDefeatDebuff(player)
    disconnectDeathWatcher(player)
    disconnectToolLockWatcher(player)
    player:SetAttribute(TOOLS_LOCKED_ATTR, false)
    if clearLock == true then
        player:SetAttribute(DEFEAT_LOCK_ATTR, false)
    end
end

local function watchDeathForDefeat(player)
    disconnectDeathWatcher(player)

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    deathConnections[player] = humanoid.Died:Connect(function()
        clearDefeatDebuff(player)
        disconnectDeathWatcher(player)
    end)
end

local function applyDefeatToPlayer(player)
    if not player or not player.Parent then
        return
    end

    clearDefeatDebuff(player)

    local endTime = workspace:GetServerTimeNow() + DEFEAT_DURATION
    player:SetAttribute(DEFEAT_ACTIVE_ATTR, true)
    player:SetAttribute(DEFEAT_END_TIME_ATTR, endTime)
    player:SetAttribute(DEFEAT_LOCK_ATTR, true)
    player:SetAttribute(TOOLS_LOCKED_ATTR, true)

    pcall(function()
        HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, DEFEAT_MODIFIER_ID, {
            additive = DEFEAT_SPEED_PENALTY,
            duration = DEFEAT_DURATION,
            source = "Defeat",
        })
    end)

    enforceUnequipped(player)
    connectToolLockWatcher(player)
    watchDeathForDefeat(player)

    task.delay(DEFEAT_DURATION, function()
        if not player or not player.Parent then
            return
        end
        if player:GetAttribute(DEFEAT_ACTIVE_ATTR) == true then
            clearDefeatDebuff(player)
        end
    end)
end

local function clearAllDefeatStates(clearLock)
    for _, player in ipairs(Players:GetPlayers()) do
        clearDefeatState(player, clearLock)
    end
end

local function initializePlayer(player)
    player:SetAttribute(TOOLS_LOCKED_ATTR, false)
    player:SetAttribute(DEFEAT_ACTIVE_ATTR, false)
    player:SetAttribute(DEFEAT_END_TIME_ATTR, 0)
    player:SetAttribute(DEFEAT_LOCK_ATTR, false)

    disconnectConnectionTableEntry(charAddedConnections, player)
    charAddedConnections[player] = player.CharacterAdded:Connect(function()
        if player:GetAttribute(DEFEAT_ACTIVE_ATTR) == true then
            task.defer(function()
                watchDeathForDefeat(player)
            end)
        end
        if player:GetAttribute(DEFEAT_LOCK_ATTR) == true or player:GetAttribute(TOOLS_LOCKED_ATTR) == true then
            task.defer(function()
                enforceUnequipped(player)
                connectToolLockWatcher(player)
            end)
        end
    end)
end

Players.PlayerAdded:Connect(initializePlayer)
for _, player in ipairs(Players:GetPlayers()) do
    initializePlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
    disconnectDeathWatcher(player)
    disconnectToolLockWatcher(player)
    disconnectConnectionTableEntry(charAddedConnections, player)
end)

local function getBindable(name)
    local bindable = ServerScriptService:WaitForChild(name, 30)
    return bindable
end

task.spawn(function()
    local matchEnded = getBindable("MatchEnded")
    if matchEnded then
        matchEnded.Event:Connect(function(winnerTeam)
            if type(winnerTeam) ~= "string" then
                return
            end

            for _, player in ipairs(Players:GetPlayers()) do
                local teamName = player.Team and player.Team.Name or nil
                if teamName == "Blue" or teamName == "Red" then
                    if teamName ~= winnerTeam then
                        applyDefeatToPlayer(player)
                    else
                        clearDefeatState(player, true)
                    end
                else
                    clearDefeatState(player, true)
                end
            end
            print("[LosingTeamLockout] Applied Defeat debuff to losing team.")
        end)
    end

    local matchStarted = getBindable("MatchStarted")
    if matchStarted then
        matchStarted.Event:Connect(function()
            clearAllDefeatStates(true)
            print("[LosingTeamLockout] Cleared Defeat states on match start.")
        end)
    end
end)

ServerScriptService:GetAttributeChangedSignal("MatchState"):Connect(function()
    local state = ServerScriptService:GetAttribute("MatchState")
    if state == "Intermission" then
        clearAllDefeatStates(true)
    end
end)
