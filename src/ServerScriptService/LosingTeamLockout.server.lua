--------------------------------------------------------------------------------
-- LosingTeamLockout.server.lua  –  Server-authoritative tool lockout for the
-- losing team between match end and the next match start.
--
-- Mechanism:
--   * On MatchEnded BindableEvent (winnerTeam): every player whose Team is
--     NOT the winner is flagged with an attribute "ToolsLocked"=true and has
--     all their currently-equipped tools force-unequipped. The Backpack is
--     also temporarily emptied (tools archived in a stash folder) so they
--     cannot be re-equipped via hotkeys, click, mobile button, or any other
--     equip path.
--   * On MatchStarted BindableEvent: the flag clears for everyone and the
--     stashed tools are restored.
--
-- This script is ENTIRELY server-authoritative. Client toolbar scripts may
-- additionally honor the attribute for snappier feedback, but the server
-- guarantee is sufficient.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local STASH_NAME = "_LockedToolsStash"
local LOCK_ATTR  = "ToolsLocked"

local function getStash(player)
    local stash = player:FindFirstChild(STASH_NAME)
    if not stash then
        stash = Instance.new("Folder")
        stash.Name = STASH_NAME
        stash.Parent = player
    end
    return stash
end

local function unequipAndStash(player)
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:UnequipTools() end) end
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    local stash = getStash(player)
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = stash
        end
    end
end

local function restoreFromStash(player)
    local stash = player:FindFirstChild(STASH_NAME)
    if not stash then return end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    for _, tool in ipairs(stash:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = backpack
        end
    end
    stash:Destroy()
end

local function lockPlayer(player)
    if not player or not player.Parent then return end
    player:SetAttribute(LOCK_ATTR, true)
    unequipAndStash(player)
end

local function unlockPlayer(player)
    if not player or not player.Parent then return end
    player:SetAttribute(LOCK_ATTR, false)
    restoreFromStash(player)
end

-- Continuous enforcement: while ToolsLocked, immediately move any tool that
-- ends up in the backpack OR the character (re-equip path) into the stash.
local function watchPlayer(player)
    local function onChildAdded(parent, child)
        if not child:IsA("Tool") then return end
        if player:GetAttribute(LOCK_ATTR) ~= true then return end
        if parent == player.Character then
            -- Tool just got equipped — yank it back.
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum:UnequipTools() end) end
        end
        local stash = getStash(player)
        if child.Parent ~= stash then
            child.Parent = stash
        end
    end

    local function bindBackpack()
        local bp = player:FindFirstChildOfClass("Backpack")
        if not bp then return end
        bp.ChildAdded:Connect(function(c) onChildAdded(bp, c) end)
    end

    bindBackpack()
    player.CharacterAdded:Connect(function(char)
        bindBackpack() -- new Backpack on respawn
        char.ChildAdded:Connect(function(c) onChildAdded(char, c) end)
        -- If the player respawns mid-lock, scrub any starter tools.
        if player:GetAttribute(LOCK_ATTR) == true then
            task.defer(function()
                if player:GetAttribute(LOCK_ATTR) == true then
                    unequipAndStash(player)
                end
            end)
        end
    end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end

-- Also clean up stash on player leave so it doesn't stick around.
Players.PlayerRemoving:Connect(function(p)
    local stash = p:FindFirstChild(STASH_NAME)
    if stash then stash:Destroy() end
end)

--------------------------------------------------------------------------------
-- Hook into GameManager BindableEvents (MatchStarted / MatchEnded).
--------------------------------------------------------------------------------
local function getBindable(name)
    local b = ServerScriptService:WaitForChild(name, 30)
    return b
end

task.spawn(function()
    local matchEnded = getBindable("MatchEnded")
    if matchEnded then
        matchEnded.Event:Connect(function(winnerTeam)
            for _, pl in ipairs(Players:GetPlayers()) do
                local plTeam = pl.Team and pl.Team.Name or nil
                if winnerTeam and plTeam and plTeam ~= winnerTeam then
                    lockPlayer(pl)
                elseif not winnerTeam then
                    -- No declared winner (sudden-death edge / draw) — leave tools alone.
                end
            end
            print("[LosingTeamLockout] Locked losing team. Winner =", tostring(winnerTeam))
        end)
    end

    local matchStarted = getBindable("MatchStarted")
    if matchStarted then
        matchStarted.Event:Connect(function()
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl:GetAttribute(LOCK_ATTR) == true then
                    unlockPlayer(pl)
                end
            end
            print("[LosingTeamLockout] All locks cleared on match start.")
        end)
    end
end)
