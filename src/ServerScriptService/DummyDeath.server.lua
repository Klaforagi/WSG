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

        -- short delay to let physics settle, then break joints to allow ragdoll-like collapse
        task.wait(0.05)
        pcall(function()
            model:BreakJoints()
        end)

        -- delete the dummy after 5 seconds to clean up
        task.delay(5, function()
            if model and model.Parent then
                pcall(function()
                    model:Destroy()
                end)
            end
        end)
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
