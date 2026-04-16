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

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

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

--- Spawn impact spark emitters at a world position.
local function spawnImpact(pos)
    local part = makeAnchorPart(pos)
    local emitter = ImpactPrefab:Clone()
    -- Scale impact particles 2x
    local origSize = emitter.Size
    local scaled = {}
    for _, kp in ipairs(origSize.Keypoints) do
        table.insert(scaled, NumberSequenceKeypoint.new(kp.Time, kp.Value * 2, kp.Envelope * 2))
    end
    emitter.Size = NumberSequence.new(scaled)
    emitter.Parent = part
    emitter:Emit(math.random(IMPACT_EMIT_MIN, IMPACT_EMIT_MAX))
    Debris:AddItem(part, BEAM_LIFETIME + 0.5) -- keep a bit longer so particles finish
end

---------------------------------------------------------------------------
-- Main VFX function
---------------------------------------------------------------------------

local function PlayShockChainVFX(fromTarget, toTarget)
    local startPos = getPosition(fromTarget)
    local endPos   = getPosition(toTarget)
    if not startPos or not endPos then return end

    -- Impact sparks at both endpoints
    spawnImpact(startPos)
    spawnImpact(endPos)

    -- Layered lightning passes
    for _ = 1, BEAM_PASSES do
        local mid = randomMidpoint(startPos, endPos)
        -- Segment 1: start → midpoint
        spawnSegment(startPos, mid)
        -- Segment 2: midpoint → end
        spawnSegment(mid, endPos)
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
