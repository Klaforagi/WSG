-- Shared filtering for camera aim and server FastCast collision.
local Players = game:GetService("Players")
local RangedCast = {}

-- The model's PrimaryPart can be a handle/pivot rather than the shaft. Infer
-- the flight axis from visible geometry, then express it in primary-part space.
-- Tip position determines which end points forward; its rotation is irrelevant.
function RangedCast.GetShaftLookCorrection(visual, primary)
    if not primary or not primary:IsA("BasePart") then return CFrame.new() end
    local shaft, axis, longest = nil, nil, 0
    local function consider(part)
        if not part:IsA("BasePart") or part.Name == "EnchantBlock" or part.Transparency >= 1 then return end
        local size = part.Size
        local length = math.max(size.X, size.Y, size.Z)
        if length < 0.05 or length < math.min(size.X, size.Y, size.Z) * 1.25 then return end
        if length <= longest then return end
        shaft, longest = part, length
        if size.Y >= size.X and size.Y >= size.Z then
            axis = Vector3.new(0, 1, 0)
        elseif size.X >= size.Y and size.X >= size.Z then
            axis = Vector3.new(1, 0, 0)
        else
            axis = Vector3.new(0, 0, -1)
        end
    end
    consider(visual)
    for _, part in ipairs(visual:GetDescendants()) do consider(part) end
    if not shaft then return CFrame.new() end
    local tip = visual:FindFirstChild("Tip", true)
    if tip and tip:IsA("Attachment") then
        local tipOffset = shaft.CFrame:PointToObjectSpace(tip.WorldPosition)
        if tipOffset:Dot(axis) < -0.001 then axis = -axis end
    end
    local upAxis = math.abs(axis.Y) > 0.5 and Vector3.new(0, 0, 1) or Vector3.new(0, 1, 0)
    local forward = primary.CFrame:VectorToObjectSpace(shaft.CFrame:VectorToWorldSpace(axis))
    local up = primary.CFrame:VectorToObjectSpace(shaft.CFrame:VectorToWorldSpace(upAxis))
    return CFrame.lookAt(Vector3.zero, forward, up):Inverse()
end

function RangedCast.ShouldPierce(inst, attackerPlayer)
    local acc = nil
    local shouldSkip = false
    if inst and inst.FindFirstAncestorWhichIsA then
        acc = inst:FindFirstAncestorWhichIsA("Accessory")
    end
    if inst and inst:IsA("BasePart") then
        local instName = tostring(inst.Name)
        local ogreModel = (instName == "Helmet") and inst:FindFirstAncestor("Ogre") or nil
        shouldSkip = (
            instName == "InvisWall"
            or instName == "PickupPart"
            or instName == "DefaultZone"
            or (ogreModel and ogreModel:FindFirstChildOfClass("Humanoid") ~= nil)
            or inst.CanQuery == false
        )
        -- Skip teammate character parts so tracers/projectiles pass through allies
        if not shouldSkip then
            local maybeModel = inst:FindFirstAncestorOfClass("Model")
            if maybeModel then
                local targetPlayer = Players:GetPlayerFromCharacter(maybeModel)
                if targetPlayer and attackerPlayer and targetPlayer.Team and attackerPlayer.Team and targetPlayer.Team == attackerPlayer.Team then
                    shouldSkip = true
                end
            end
        end
        if not shouldSkip and inst:FindFirstAncestor("EventMeteorZones") then
            shouldSkip = true
        end
    end
    return acc ~= nil or shouldSkip
end

-- This ray only chooses the crosshair target. FastCast handles projectile travel.
function RangedCast.RaycastAim(worldRoot, origin, direction, rayParams, attackerPlayer)
    local start = origin
    local remaining = direction
    for _ = 1, 10 do
        if not remaining or remaining.Magnitude <= 0.001 then break end
        local result = worldRoot:Raycast(start, remaining, rayParams)
        if not result or not result.Instance then return result end
        if not RangedCast.ShouldPierce(result.Instance, attackerPlayer) then return result end
        local traveled = (result.Position - start).Magnitude
        local dirUnit = remaining.Unit
        start = result.Position + dirUnit * 0.02
        remaining = dirUnit * math.max(0, remaining.Magnitude - traveled)
    end
    return nil
end

return RangedCast
