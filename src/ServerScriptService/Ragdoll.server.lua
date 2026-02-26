--!strict
-- Single-file server-side Ragdoll implementation
-- Replaces Motor6D joints with BallSocketConstraints on death

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function makePartsPhysical(model)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = true
            p.Massless = false
        end
    end
end

local function convertMotorsToConstraints(model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local motor = inst
            local p0 = motor.Part0
            local p1 = motor.Part1
            if not (p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart")) then
                pcall(function() motor:Destroy() end)
                continue
            end

            -- Create attachments positioned by motor's C0/C1
            local a0 = Instance.new("Attachment")
            a0.Name = "_rag_att0_" .. motor.Name
            a0.CFrame = motor.C0
            a0.Parent = p0

            local a1 = Instance.new("Attachment")
            a1.Name = "_rag_att1_" .. motor.Name
            a1.CFrame = motor.C1
            a1.Parent = p1

            local bsc = Instance.new("BallSocketConstraint")
            bsc.Name = "_rag_bsc_" .. motor.Name
            bsc.Attachment0 = a0
            bsc.Attachment1 = a1
            bsc.LimitsEnabled = false
            bsc.Parent = model

            pcall(function() motor:Destroy() end)
        end
    end
end

-- Safety-net: if an accessory lost its weld, re-weld its Handle to the
-- matching body part so hats/hair stay on during ragdoll.
local function attachAccessories(model)
    for _, acc in ipairs(model:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if not (handle and handle:IsA("BasePart")) then continue end

            -- check if the handle already has a live weld to a character part
            local alreadyWelded = false
            for _, w in ipairs(handle:GetChildren()) do
                if (w:IsA("Weld") or w:IsA("WeldConstraint")) and w.Part1 and w.Part1:IsDescendantOf(model) then
                    alreadyWelded = true
                    break
                end
            end
            if alreadyWelded then continue end

            -- find matching attachment on the character body (not on the handle itself)
            for _, a in ipairs(handle:GetChildren()) do
                if a:IsA("Attachment") then
                    local match = model:FindFirstChild(a.Name, true)
                    if match and match:IsA("Attachment")
                        and match ~= a
                        and match.Parent
                        and match.Parent:IsA("BasePart")
                        and match.Parent ~= handle then

                        local weld = Instance.new("WeldConstraint")
                        weld.Name = "_rag_weld_" .. acc.Name
                        weld.Part0 = handle
                        weld.Part1 = match.Parent
                        weld.Parent = handle
                        handle.Anchored = false
                        break
                    end
                end
            end
        end
    end
end

local function ragdollModel(model)
    if not model or not model.Parent then return end
    if model:GetAttribute("_ragdolled") then return end
    model:SetAttribute("_ragdolled", true)

    makePartsPhysical(model)
    -- first attach accessories so they remain connected
    attachAccessories(model)
    convertMotorsToConstraints(model)

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        -- unequip any held tool and move ALL tools to backpack so they can't be used
        pcall(function() humanoid:UnequipTools() end)
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("Tool") then
                local owner = Players:GetPlayerFromCharacter(model)
                if owner then
                    pcall(function() child.Parent = owner.Backpack end)
                else
                    pcall(function() child.Parent = nil end)
                end
            end
        end
        pcall(function() humanoid.PlatformStand = true end)
    end
end

local function bindHumanoid(humanoid)
    if not humanoid or not humanoid.Parent then return end
    if humanoid:GetAttribute("_rag_binded") then return end
    humanoid:SetAttribute("_rag_binded", true)

    -- Prevent Roblox from auto-breaking ALL joints on death
    -- (this is what strips accessory welds and causes hair/hats to fall off)
    pcall(function() humanoid.BreakJointsOnDeath = false end)

    humanoid.Died:Connect(function()
        local model = humanoid.Parent
        if model then ragdollModel(model) end
    end)
end

-- scan workspace for existing humanoids
for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Humanoid") then
        bindHumanoid(desc)
    end
end

Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Humanoid") then
        bindHumanoid(desc)
    elseif desc:IsA("Model") then
        local h = desc:FindFirstChildOfClass("Humanoid")
        if h then bindHumanoid(h) end
    end
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        local h = char:WaitForChild("Humanoid", 10)
        if h and h:IsA("Humanoid") then bindHumanoid(h) end
    end)
    if player.Character then
        local h = player.Character:FindFirstChildOfClass("Humanoid")
        if h then bindHumanoid(h) end
    end
end)

return {}
