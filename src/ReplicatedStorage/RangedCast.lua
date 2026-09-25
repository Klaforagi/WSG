-- Shared filtering for camera aim and server FastCast collision.
local Players = game:GetService("Players")
local RangedCast = {}

-- 0.9 studs across, centered on the cast path (the projectile's Tip attachment).
-- Independent of the cosmetic arrow's size.
-- Set to 0 to restore the original thin-ray collision.
RangedCast.ProjectileHitRadius = 0.45
-- Extra coverage below the Tip in world space; total downward reach is 0.9.
RangedCast.ProjectileHitDownwardExtension = 0.45

-- FastCast routes all travel/piercing queries through WorldRoot:Raycast.
-- Sweep the Tip sphere and an overlapping sphere below it along the segment,
-- keeping the same filtering, hit events and server damage authority.
function RangedCast.CreateProjectileWorldRoot(worldRoot)
    local function isHumanoidPart(instance)
        local model = instance and instance:FindFirstAncestorOfClass("Model")
        return model and model:FindFirstChildOfClass("Humanoid") ~= nil
    end
    return {
        Raycast = function(_, origin, direction, params)
            if direction.Magnitude <= 0.000001 then return nil end
            local rayHit = worldRoot:Raycast(origin, direction, params)
            local radius = RangedCast.ProjectileHitRadius
            if radius <= 0 then return rayHit end
            local sphereHit = worldRoot:Spherecast(origin, radius, direction, params)
            if sphereHit and not isHumanoidPart(sphereHit.Instance) then
                sphereHit = nil
            end
            local downwardExtension = RangedCast.ProjectileHitDownwardExtension
            if downwardExtension > 0 then
                local lowerOrigin = origin - Vector3.new(0, downwardExtension, 0)
                local lowerHit = worldRoot:Spherecast(lowerOrigin, radius, direction, params)
                if lowerHit and not isHumanoidPart(lowerHit.Instance) then
                    lowerHit = nil
                end
                if lowerHit and (not sphereHit or lowerHit.Distance < sphereHit.Distance) then
                    sphereHit = lowerHit
                end
            end
            -- Spherecasts omit initially overlapping geometry. Keep the central
            -- ray as a fallback so close walls still block the projectile.
            if rayHit and (not sphereHit or rayHit.Distance < sphereHit.Distance) then
                return rayHit
            end
            if not sphereHit then return nil end
            -- FastCast uses Position as the projectile's travel point. A sphere
            -- result instead reports the surface contact, which is off-center.
            -- Keep the Tip on its original path, including hits by the lower
            -- sphere; the added coverage must not pull the visual downward.
            return {
                Instance = sphereHit.Instance,
                Position = origin + direction.Unit * sphereHit.Distance,
                Distance = sphereHit.Distance,
                Normal = sphereHit.Normal,
                Material = sphereHit.Material,
            }
        end,
    }
end

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
