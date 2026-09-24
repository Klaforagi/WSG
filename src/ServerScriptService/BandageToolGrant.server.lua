--------------------------------------------------------------------------------
-- BandageToolGrant.server.lua
-- Grants a fallback Bandage tool to every player so slot 3 can equip an
-- actual tool instead of immediately firing the heal action.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")

local BANDAGE_TOOL_NAME = "Bandage"

-- Use the authored tool; keep its grip, geometry, attachments and texture.
local ServerStorage = game:GetService("ServerStorage")
local toolsFolder = ServerStorage:WaitForChild("Tools", 15)
local specialFolder = toolsFolder and toolsFolder:WaitForChild("Special", 15)
local template = specialFolder and specialFolder:WaitForChild(BANDAGE_TOOL_NAME, 15)
if not template or not template:IsA("Tool") then
    warn("[BandageToolGrant] Missing Tool ServerStorage.Tools.Special.Bandage")
    return
end
local bandageToolTemplate = template:Clone()
local AssetCodes = require(game:GetService("ReplicatedStorage"):WaitForChild("AssetCodes"))
bandageToolTemplate.TextureId = AssetCodes.Get("Bandage") or ""
bandageToolTemplate.CanBeDropped = false
bandageToolTemplate:SetAttribute("HotbarCategory", "Utility")
bandageToolTemplate:SetAttribute("UtilityType", "bandage")
bandageToolTemplate:SetAttribute("BandageTool", true)
local handle = bandageToolTemplate:FindFirstChild("Handle")
local thumbnailCamera = bandageToolTemplate:FindFirstChild("ThumbnailCamera", true)
if handle and handle:IsA("BasePart") and thumbnailCamera and thumbnailCamera:IsA("Camera") then
    -- Cameras need not replicate: publish the authored view relative to Handle.
    bandageToolTemplate:SetAttribute("BandageThumbnailCFrame", handle.CFrame:ToObjectSpace(thumbnailCamera.CFrame))
    bandageToolTemplate:SetAttribute("BandageThumbnailFOV", thumbnailCamera.FieldOfView)
end
for _, part in ipairs(bandageToolTemplate:GetDescendants()) do
    if part:IsA("BasePart") then
        part.Anchored = false
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
    end
end

local function grantBandageTool(player)
    if not player or not player.Parent then
        return
    end

    local starterGear = player:WaitForChild("StarterGear", 5)
    local backpack = player:WaitForChild("Backpack", 5)
    local character = player.Character

    local starterHas = starterGear and starterGear:FindFirstChild(BANDAGE_TOOL_NAME)
    local backpackHas = backpack and backpack:FindFirstChild(BANDAGE_TOOL_NAME)
    local characterHas = character and character:FindFirstChild(BANDAGE_TOOL_NAME)

    if starterGear and not starterHas then
        local starterClone = bandageToolTemplate:Clone()
        starterClone.Parent = starterGear
    end

    if backpack and not backpackHas and not characterHas then
        local backpackClone = bandageToolTemplate:Clone()
        backpackClone.Parent = backpack
    end
end

local function hookPlayer(player)
    if not player then
        return
    end

    player.CharacterAdded:Connect(function()
        task.spawn(grantBandageTool, player)
    end)

    task.defer(function()
        grantBandageTool(player)
    end)
end

Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(player)
    -- The tool is cloned per-player and cleaned up automatically with the player.
end)

for _, player in ipairs(Players:GetPlayers()) do
    hookPlayer(player)
end
