-- WorldLeaderboardDistanceBlackout.client.lua
-- Applies local-only blackout overlays to the non-selectable world boards.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local UPDATE_INTERVAL_SECONDS = 0.25
local OVERLAY_NAME = "LeaderboardDistanceBlackout"

local BOARD_GROUPS = {
    {
        maxDistance = 100,
        modelNames = {
            "LeaderboardMelee",
            "Leaderboard Melee",
            "Leaderboard Range",
            "LeaderboardRange",
            "LeaderboardQuests",
            "LeaderboardWeeklyQuests",
        },
    },
    {
        maxDistance = 200,
        modelNames = {
            "GiantLeaderboardEliminations",
            "GiantLeaderboardLevels",
        },
    },
}

local function getRootPart()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function ensureBlackout(surfaceGui)
    local overlay = surfaceGui:FindFirstChild(OVERLAY_NAME)
    if overlay and not overlay:IsA("Frame") then
        overlay:Destroy()
        overlay = nil
    end
    if not overlay then
        overlay = Instance.new("Frame")
        overlay.Name = OVERLAY_NAME
        overlay.Parent = surfaceGui
    end
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0
    overlay.BorderSizePixel = 0
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.ZIndex = 10000
    return overlay
end

local function updateBoard(model, maxDistance, rootPart)
    if not model or not model:IsA("Model") then
        return
    end

    local isTooFar = not rootPart
        or (rootPart.Position - model:GetPivot().Position).Magnitude > maxDistance
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("SurfaceGui") then
            descendant.Active = not isTooFar
            ensureBlackout(descendant).Visible = isTooFar
        end
    end
end

while true do
    local rootPart = getRootPart()
    for _, group in ipairs(BOARD_GROUPS) do
        for _, modelName in ipairs(group.modelNames) do
            updateBoard(Workspace:FindFirstChild(modelName), group.maxDistance, rootPart)
        end
    end
    task.wait(UPDATE_INTERVAL_SECONDS)
end
