-- DisablePlayerList.client.lua
-- LocalScript: disables Roblox default PlayerList so only the custom KingsGround scoreboard shows.

local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local MAX_RETRIES = 10
local RETRY_DELAY = 0.25 -- seconds

local function tryDisable()
    local ok, err = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
    end)
    return ok, err
end

print("[DisablePlayerList] LocalScript started")

-- Retry loop for early startup race conditions
local ok, err = tryDisable()
local attempts = 1
while not ok and attempts < MAX_RETRIES do
    task.wait(RETRY_DELAY)
    attempts = attempts + 1
    ok, err = tryDisable()
end

if ok then
    print(string.format("[DisablePlayerList] PlayerList disabled after %d attempt(s)", attempts))
else
    warn("[DisablePlayerList] Failed to disable PlayerList:", tostring(err))
end

-- Reapply on CharacterAdded to be robust across respawns
local function onCharacterAdded()
    local ok2, err2 = tryDisable()
    if ok2 then
        print("[DisablePlayerList] Reapplied disable on CharacterAdded")
    else
        warn("[DisablePlayerList] Reapply on CharacterAdded failed:", tostring(err2))
    end
end

if player then
    player.CharacterAdded:Connect(onCharacterAdded)
else
    -- Fallback: wait for LocalPlayer and then hook
    Players:GetPropertyChangedSignal("LocalPlayer"):Connect(function()
        player = Players.LocalPlayer
        if player then
            player.CharacterAdded:Connect(onCharacterAdded)
        end
    end)
end

-- Small verification: check whether a custom scoreboard ScreenGui is present in PlayerGui
task.spawn(function()
    task.wait(0.6)
    if not Players.LocalPlayer then return end
    local pg = Players.LocalPlayer:FindFirstChild("PlayerGui") or Players.LocalPlayer:WaitForChild("PlayerGui", 3)
    if not pg then
        print("[DisablePlayerList] PlayerGui not found for verification")
        return
    end

    local found = pg:FindFirstChild("KingsGroundScoreboard") or pg:FindFirstChild("Scoreboard") or pg:FindFirstChild("KG_Scoreboard")
    print("[DisablePlayerList] custom scoreboard present:", tostring(found ~= nil), (found and found.Name) or "nil")
end)
