--!strict
--!native
--!optimize 2

-- Client script: initialise the RagdollService client-side components
-- so the local player's character enters Physics state, enables limb
-- collisions, and gets the camera spring effect when ragdolled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RagdollService"))
