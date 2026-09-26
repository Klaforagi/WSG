-- Disable automatic knockdown on each spawn on the physics-owning client.
-- Death ragdolls still use Physics/Dead and are left intact.
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

-- Recover immediately if the character was already knocked down while loading.
local state = humanoid:GetState()
if humanoid.Health > 0 and (state == Enum.HumanoidStateType.FallingDown
    or state == Enum.HumanoidStateType.Ragdoll) then
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end
