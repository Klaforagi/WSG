--------------------------------------------------------------------------------
-- ShockChainVFX.client.lua  –  Client visual effect for shock chain lightning
--
-- Listens for the ShockChainVFX RemoteEvent fired by the server each time a
-- shock chain jumps between targets.  Spawns layered beams with a midpoint
-- system for chaotic lightning, plus impact spark emitters at both endpoints.
--
-- VFX prefabs (must exist in Studio):
--   ReplicatedStorage.VFX.ShockChainBeam      (Beam)
--   ReplicatedStorage.VFX.ShockImpactEmitter   (ParticleEmitter)
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local VFXFolder = ReplicatedStorage:WaitForChild("VFX")
local BeamPrefab    = VFXFolder:WaitForChild("ShockChainBeam")
local ImpactPrefab  = VFXFolder:WaitForChild("ShockImpactEmitter")

local BEAM_LIFETIME   = 0.12   -- seconds before cleanup
local BEAM_PASSES     = 3      -- 1 main + 2 extras
local Y_OFFSET        = 0.2    -- very small vertical nudge
local MID_Y_MIN       = -1     -- vertical range for midpoint (can be level or below)
local MID_Y_MAX       = 5
local MID_XZ_RANGE    = 2      -- random horizontal scatter for midpoint
local CURVE_MIN       = -6     -- CurveSize randomisation
local CURVE_MAX       = 6
local IMPACT_EMIT_MIN = 10
local IMPACT_EMIT_MAX = 20
local IMPACT_LINGER   = 0.6    -- how long the impact attachment stays on the target

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Return the best torso-level BasePart on a model, or nil.
local function getEffectPart(model)
    if not model or not model.Parent then return nil end
    local part = model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("HumanoidRootPart")
    if part and part:IsA("BasePart") then return part end
    return nil
end

local function getPosition(model)
    if not model or not model.Parent then return nil end
    -- Prefer torso-level parts for chest-height lightning
    local torso = model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
    if torso and torso:IsA("BasePart") then
        return torso.Position + Vector3.new(0, Y_OFFSET, 0)
    end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp.Position + Vector3.new(0, Y_OFFSET, 0)
    end
    -- Fallback to model pivot
    local ok, pivot = pcall(function() return model:GetPivot().Position end)
    if ok and pivot then
        return pivot + Vector3.new(0, Y_OFFSET, 0)
    end
    return nil
end

local function randomInRange(lo, hi)
    return lo + math.random() * (hi - lo)
end

local function randomMidpoint(startPos, endPos)
    local baseMid = (startPos + endPos) / 2
    return baseMid + Vector3.new(
        randomInRange(-MID_XZ_RANGE, MID_XZ_RANGE),
        randomInRange(MID_Y_MIN, MID_Y_MAX),
        randomInRange(-MID_XZ_RANGE, MID_XZ_RANGE)
    )
end

--- Create an anchored, invisible, non-collide part at `pos`.
local function makeAnchorPart(pos)
    local part = Instance.new("Part")
    part.Name = "_ShockAnchor"
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.CFrame = CFrame.new(pos)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Transparency = 1
    part.Parent = workspace  -- lightweight parent
    return part
end

--- Spawn a single beam segment between two world positions.
local function spawnSegment(fromPos, toPos)
    local partA = makeAnchorPart(fromPos)
    local partB = makeAnchorPart(toPos)

    local attA = Instance.new("Attachment")
    attA.Parent = partA
    local attB = Instance.new("Attachment")
    attB.Parent = partB

    local beam = BeamPrefab:Clone()
    beam.Attachment0 = attA
    beam.Attachment1 = attB
    beam.CurveSize0 = randomInRange(CURVE_MIN, CURVE_MAX)
    beam.CurveSize1 = randomInRange(CURVE_MIN, CURVE_MAX)
    beam.Parent = partA

    Debris:AddItem(partA, BEAM_LIFETIME)
    Debris:AddItem(partB, BEAM_LIFETIME)
end

--- Clone the impact emitter with 2x size scaling applied.
local function cloneScaledImpact()
    local emitter = ImpactPrefab:Clone()
    local origSize = emitter.Size
    local scaled = {}
    for _, kp in ipairs(origSize.Keypoints) do
        table.insert(scaled, NumberSequenceKeypoint.new(kp.Time, kp.Value * 2, kp.Envelope * 2))
    end
    emitter.Size = NumberSequence.new(scaled)
    return emitter
end

--- Spawn impact sparks attached to a target model so they follow movement.
--- Falls back to a fixed world-position anchor if no body part is available.
local function spawnImpactAtModel(targetModel, fallbackPos)
    local bodyPart = getEffectPart(targetModel)
    if bodyPart then
        local att = Instance.new("Attachment")
        att.Name = "_ShockImpactAtt"
        att.Parent = bodyPart
        local emitter = cloneScaledImpact()
        emitter.Parent = att
        emitter:Emit(math.random(IMPACT_EMIT_MIN, IMPACT_EMIT_MAX))
        Debris:AddItem(att, IMPACT_LINGER)
    else
        -- Fallback: anchored world part
        if not fallbackPos then return end
        local part = makeAnchorPart(fallbackPos)
        local emitter = cloneScaledImpact()
        emitter.Parent = part
        emitter:Emit(math.random(IMPACT_EMIT_MIN, IMPACT_EMIT_MAX))
        Debris:AddItem(part, IMPACT_LINGER)
    end
end

--- Create an attachment on a body part, or fall back to a world anchor.
--- Returns the Attachment and an optional anchor Part (nil if body-attached).
local function makeAttachment(model, worldPos)
    local bodyPart = getEffectPart(model)
    if bodyPart then
        local att = Instance.new("Attachment")
        att.Parent = bodyPart
        return att, nil
    end
    local anchor = makeAnchorPart(worldPos)
    local att = Instance.new("Attachment")
    att.Parent = anchor
    return att, anchor
end

---------------------------------------------------------------------------
-- Main VFX function
---------------------------------------------------------------------------

local function PlayShockChainVFX(fromTarget, toTarget)
    local startPos = getPosition(fromTarget)
    if not startPos then return end

    -- Impact sparks on the source target (always)
    spawnImpactAtModel(fromTarget, startPos)

    -- If no chain target, impact-only mode — no beams
    local endPos = getPosition(toTarget)
    if not endPos then return end

    -- Impact sparks on the chain target
    spawnImpactAtModel(toTarget, endPos)

    -- Layered lightning passes
    for _ = 1, BEAM_PASSES do
        local mid = randomMidpoint(startPos, endPos)

        -- Segment 1: start → midpoint
        local att0, anchor0 = makeAttachment(fromTarget, startPos)
        local attM1 = Instance.new("Attachment")
        local anchorM1 = makeAnchorPart(mid)
        attM1.Parent = anchorM1

        local beam1 = BeamPrefab:Clone()
        beam1.Attachment0 = att0
        beam1.Attachment1 = attM1
        beam1.CurveSize0 = randomInRange(CURVE_MIN, CURVE_MAX)
        beam1.CurveSize1 = randomInRange(CURVE_MIN, CURVE_MAX)
        beam1.Parent = attM1.Parent

        -- Segment 2: midpoint → end
        local attM2 = Instance.new("Attachment")
        local anchorM2 = makeAnchorPart(mid)
        attM2.Parent = anchorM2
        local att1, anchor1 = makeAttachment(toTarget, endPos)

        local beam2 = BeamPrefab:Clone()
        beam2.Attachment0 = attM2
        beam2.Attachment1 = att1
        beam2.CurveSize0 = randomInRange(CURVE_MIN, CURVE_MAX)
        beam2.CurveSize1 = randomInRange(CURVE_MIN, CURVE_MAX)
        beam2.Parent = attM2.Parent

        -- Cleanup: body-attached attachments + world anchors
        Debris:AddItem(att0, BEAM_LIFETIME)
        Debris:AddItem(anchorM1, BEAM_LIFETIME)
        Debris:AddItem(anchorM2, BEAM_LIFETIME)
        Debris:AddItem(att1, BEAM_LIFETIME)
        if anchor0 then Debris:AddItem(anchor0, BEAM_LIFETIME) end
        if anchor1 then Debris:AddItem(anchor1, BEAM_LIFETIME) end
    end
end

---------------------------------------------------------------------------
-- Event listener
---------------------------------------------------------------------------

local shockChainEvent = ReplicatedStorage:WaitForChild("ShockChainVFX", 10)
if not shockChainEvent then
    warn("[ShockChainVFX] RemoteEvent 'ShockChainVFX' not found in ReplicatedStorage")
    return
end

shockChainEvent.OnClientEvent:Connect(function(fromModel, toModel)
    PlayShockChainVFX(fromModel, toModel)
end)
