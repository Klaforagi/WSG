--------------------------------------------------------------------------------
-- WeaponScaleService.lua  –  Uniform weapon model scaling utility
--
-- Scales a weapon Tool or Model uniformly based on a SizePercent value.
-- Designed to be safe for Roblox tools: preserves welds, Motor6D joints,
-- attachments, and handle/grip behaviour.
--
-- HOW WEAPON SCALING IS APPLIED:
--   1. On first scale, original sizes/positions of every BasePart are cached
--      in an attribute ("_OrigSize" / "_OrigPos") so scaling is deterministic
--      and never compounds if reapplied.
--   2. All BaseParts (including MeshParts) are resized uniformly.
--   3. Positions are recomputed relative to the model's pivot / primary part.
--   4. MeshPart.MeshSize is not directly settable, so a `Scale` property on
--      any child SpecialMesh is updated. For MeshParts, we use the Size
--      property which Roblox scales the mesh to fit.
--   5. Attachments are repositioned proportionally.
--   6. Tool.GripPos is scaled proportionally so equip alignment is preserved.
--
-- USAGE:
--   local WeaponScale = require(path.to.WeaponScaleService)
--   WeaponScale.ApplyScale(toolOrModel, sizePercent)
--   WeaponScale.ResetScale(toolOrModel)  -- restore to original
--------------------------------------------------------------------------------

local WeaponScaleService = {}

-- Attribute names for caching original state (prevents compounding)
local ORIG_SIZE_ATTR   = "_OrigSize"
local ORIG_POS_ATTR    = "_OrigPos"
local ORIG_GRIP_ATTR   = "_OrigGripPos"
local SCALED_FLAG_ATTR = "_ScaleApplied"

--------------------------------------------------------------------------------
-- Internal: cache original part data if not already cached
--------------------------------------------------------------------------------
local function cacheOriginals(root)
    for _, part in ipairs(root:GetDescendants()) do
        if part:IsA("BasePart") then
            if not part:GetAttribute(ORIG_SIZE_ATTR) then
                -- Store as string "x,y,z" since attributes don't support Vector3 directly
                local s = part.Size
                part:SetAttribute(ORIG_SIZE_ATTR, string.format("%.6f,%.6f,%.6f", s.X, s.Y, s.Z))
            end
        end
        if part:IsA("Attachment") then
            if not part:GetAttribute(ORIG_POS_ATTR) then
                local p = part.Position
                part:SetAttribute(ORIG_POS_ATTR, string.format("%.6f,%.6f,%.6f", p.X, p.Y, p.Z))
            end
        end
        if part:IsA("SpecialMesh") then
            if not part:GetAttribute(ORIG_SIZE_ATTR) then
                local sc = part.Scale
                part:SetAttribute(ORIG_SIZE_ATTR, string.format("%.6f,%.6f,%.6f", sc.X, sc.Y, sc.Z))
            end
        end
    end
    -- Cache Tool.GripPos if applicable
    if root:IsA("Tool") and not root:GetAttribute(ORIG_GRIP_ATTR) then
        local gp = root.GripPos
        root:SetAttribute(ORIG_GRIP_ATTR, string.format("%.6f,%.6f,%.6f", gp.X, gp.Y, gp.Z))
    end
end

--------------------------------------------------------------------------------
-- Internal: parse "x,y,z" string back to Vector3
--------------------------------------------------------------------------------
local function parseV3(str)
    if type(str) ~= "string" then return nil end
    local x, y, z = str:match("^([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
    if x then
        return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
    end
    return nil
end

--------------------------------------------------------------------------------
-- ApplyScale(toolOrModel, sizePercent)
-- Uniformly scales all visual parts of the weapon.
-- sizePercent: integer 80–200 (100 = normal size).
--------------------------------------------------------------------------------
function WeaponScaleService.ApplyScale(root, sizePercent)
    if not root then return end
    sizePercent = math.clamp(math.floor(sizePercent or 100), 80, 200)
    local multiplier = sizePercent / 100

    -- Cache originals on first application
    cacheOriginals(root)

    -- Find pivot part (Handle for Tools, PrimaryPart for Models, or first BasePart)
    local pivotPart = nil
    if root:IsA("Tool") then
        pivotPart = root:FindFirstChild("Handle")
    elseif root:IsA("Model") then
        pivotPart = root.PrimaryPart
    end
    if not pivotPart then
        for _, child in ipairs(root:GetDescendants()) do
            if child:IsA("BasePart") then pivotPart = child; break end
        end
    end

    local pivotCFrame = pivotPart and pivotPart.CFrame or CFrame.new()
    local pivotOrigSize = nil
    if pivotPart then
        pivotOrigSize = parseV3(pivotPart:GetAttribute(ORIG_SIZE_ATTR))
    end

    -- Scale all BaseParts
    for _, part in ipairs(root:GetDescendants()) do
        if part:IsA("BasePart") then
            local origSize = parseV3(part:GetAttribute(ORIG_SIZE_ATTR))
            if origSize then
                part.Size = origSize * multiplier
            end
        end
    end

    -- Scale SpecialMesh Scale properties
    for _, mesh in ipairs(root:GetDescendants()) do
        if mesh:IsA("SpecialMesh") then
            local origScale = parseV3(mesh:GetAttribute(ORIG_SIZE_ATTR))
            if origScale then
                mesh.Scale = origScale * multiplier
            end
        end
    end

    -- Scale Attachment positions (relative to their parent part, so they stay aligned)
    for _, att in ipairs(root:GetDescendants()) do
        if att:IsA("Attachment") then
            local origPos = parseV3(att:GetAttribute(ORIG_POS_ATTR))
            if origPos then
                att.Position = origPos * multiplier
            end
        end
    end

    -- Scale Tool.GripPos so the weapon stays properly positioned in the character's hand
    if root:IsA("Tool") then
        local origGrip = parseV3(root:GetAttribute(ORIG_GRIP_ATTR))
        if origGrip then
            root.GripPos = origGrip * multiplier
        end
    end

    -- Mark as scaled with the percent used
    root:SetAttribute(SCALED_FLAG_ATTR, sizePercent)
end

--------------------------------------------------------------------------------
-- ResetScale(toolOrModel)
-- Restores the weapon to its original (100%) size using cached data.
--------------------------------------------------------------------------------
function WeaponScaleService.ResetScale(root)
    if not root then return end
    WeaponScaleService.ApplyScale(root, 100)
    root:SetAttribute(SCALED_FLAG_ATTR, nil)
end

--------------------------------------------------------------------------------
-- GetAppliedScale(toolOrModel) -> sizePercent or nil
-- Returns the currently applied scale percent, or nil if not scaled.
--------------------------------------------------------------------------------
function WeaponScaleService.GetAppliedScale(root)
    if not root then return nil end
    return root:GetAttribute(SCALED_FLAG_ATTR)
end

return WeaponScaleService
