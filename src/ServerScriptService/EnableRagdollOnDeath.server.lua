--!strict
--!native
--!optimize 2

-- Server script: initialise the RagdollService component system and
-- tag every Humanoid in the game so ANY model ragdolls on death
-- (players, NPCs, dummies, etc.)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Boot the server-side RagdollService components (Ragdoll, Ragdollable,
-- RagdollOnHumanoidDied) so they start listening for CollectionService tags.
local RagdollService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RagdollService"))

-- Tag a humanoid for ragdoll-on-death (idempotent – safe to call twice)
local function tagHumanoid(humanoid: Humanoid)
    if not CollectionService:HasTag(humanoid, "RagdollOnHumanoidDied") then
        CollectionService:AddTag(humanoid, "RagdollOnHumanoidDied")
    end
end

-- When any Model is added anywhere in Workspace, check for a Humanoid
local function onDescendantAdded(descendant: Instance)
    if descendant:IsA("Humanoid") then
        tagHumanoid(descendant)
    end
end

-- Tag every Humanoid that already exists in Workspace
for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Humanoid") then
        task.spawn(tagHumanoid, desc)
    end
end

-- Listen for any new Humanoid added at runtime (spawned NPCs, player respawns, etc.)
Workspace.DescendantAdded:Connect(onDescendantAdded)

-- Also handle player characters via CharacterAdded (covers the brief window
-- before the character is parented to Workspace)
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if humanoid and humanoid:IsA("Humanoid") then
        tagHumanoid(humanoid)
    end
end

local function onPlayerAdded(player: Player)
    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        task.spawn(onCharacterAdded, player.Character)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end