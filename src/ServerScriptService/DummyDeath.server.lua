local Workspace = game:GetService("Workspace")

local function handleDummyModel(model)
    if not model or not model:IsA("Model") then return end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if humanoid:GetAttribute("_dummyDeathConnected") then return end
    humanoid:SetAttribute("_dummyDeathConnected", true)

    humanoid.Died:Connect(function()
        -- if already ragdolled by damage code, skip duplicate work
        if humanoid:GetAttribute("_dummyRagdolled") then return end
        -- ensure humanoid state is dead
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end)

        -- unanchor parts and enable collisions so the model can fall naturally
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Anchored = false
                desc.CanCollide = true
            end
            -- also enable any Attachment-based constraints if present (no-op otherwise)
            if desc:IsA("Constraint") then
                -- leave constraints as-is; BreakJoints will handle Motor6D/JointInstances
            end
        end

        -- MobDeathFade handles the fade-out and Destroy.
        -- Skip BreakJoints so tweens on child parts still work.
    end)
end

-- scan existing (use GetDescendants to catch dummies inside folders)
for _, child in ipairs(Workspace:GetDescendants()) do
    if child and child:IsA("Model") and child.Name == "Dummy" then
        handleDummyModel(child)
    end
end

-- watch for new dummies anywhere in workspace
Workspace.DescendantAdded:Connect(function(child)
    if child and child:IsA("Model") and child.Name == "Dummy" then
        handleDummyModel(child)
    end
end)

return nil
