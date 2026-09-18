-- Shared filtering for camera aim and server FastCast collision.
local Players = game:GetService("Players")
local RangedCast = {}

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
