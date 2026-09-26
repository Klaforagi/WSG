local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local LOCK_ATTR = "DefeatLockActive"

local function isOnGameplayTeam()
    local team = player.Team
    return team ~= nil and team.Name ~= "Neutral"
end

local function setResetEnabled(enabled)
    for _ = 1, 6 do
        local ok = pcall(function()
            StarterGui:SetCore("ResetButtonCallback", enabled)
        end)
        if ok then
            return
        end
        task.wait(0.15)
    end
end

local function syncResetState()
    -- Players may reset freely in the Neutral lobby, but cannot use Reset to
    -- leave or respawn while they are assigned to a match team.
    local locked = player:GetAttribute(LOCK_ATTR) == true or isOnGameplayTeam()
    setResetEnabled(not locked)
end

player:GetAttributeChangedSignal(LOCK_ATTR):Connect(syncResetState)
player:GetPropertyChangedSignal("Team"):Connect(syncResetState)

player.CharacterAdded:Connect(function()
    task.defer(syncResetState)
end)

task.defer(syncResetState)
