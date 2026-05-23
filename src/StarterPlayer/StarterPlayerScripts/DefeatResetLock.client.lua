local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local LOCK_ATTR = "DefeatLockActive"

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
    local locked = player:GetAttribute(LOCK_ATTR) == true
    setResetEnabled(not locked)
end

player:GetAttributeChangedSignal(LOCK_ATTR):Connect(syncResetState)

player.CharacterAdded:Connect(function()
    task.defer(syncResetState)
end)

task.defer(syncResetState)
