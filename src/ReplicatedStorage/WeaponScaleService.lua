-- WeaponScaleService.lua
-- Weld-first, robust weapon scaling for Tools whose visual parts are welded.
-- Core rules:
--  - Do NOT set CFrame for welded parts; scale the weld offsets instead.
--  - Cache originals (sizes, mesh scales, weld C0/C1) and always compute from originals.

local WeaponScaleService = {}
local GRIP_DEBUG = true

local cache = setmetatable({}, { __mode = "k" }) -- weak keys
local gripMotorDefaults = setmetatable({}, { __mode = "k" })
local boundGripTools = setmetatable({}, { __mode = "k" })
local pendingGripRefresh = setmetatable({}, { __mode = "k" })

local APPLIED_MODEL_NAME = "AppliedCharacterSkin"
local FULL_BODY_SKIN_MODEL_ATTRIBUTE = "_FullBodySkinModel"
local RunService = game:GetService("RunService")

local function normalizeScaleInput(s)
    if type(s) ~= "number" then return nil end
    if s > 10 then -- user passed percent like 150
        return s / 100
    end
    return s
end

-- Scale the translation component of a CFrame while preserving its exact rotation.
local function scaleCFrameTranslationPreserveRotation(cf, scale)
    -- cf = CFrame.new(pos) * R where R is rotation; extract R by removing translation
    local pos = cf.Position * scale
    local rot = CFrame.new(cf.Position):Inverse() * cf -- rotation CFrame
    return CFrame.new(pos) * rot
end

local function replaceCFrameTranslationPreserveRotation(cf, position)
    local rot = CFrame.new(cf.Position):Inverse() * cf
    return CFrame.new(position) * rot
end

local function getHandle(tool)
    if not tool then return nil end
    local h = tool:FindFirstChild("Handle")
    if h and h:IsA("BasePart") then return h end
    return nil
end

local function normalizeName(name)
    return string.lower((tostring(name):gsub("[%s%p_]", "")))
end

local function dprint(...)
    if GRIP_DEBUG then
        print("[WeaponGripDebug]", ...)
    end
end

local function formatVector3(vector)
    if typeof(vector) ~= "Vector3" then
        return tostring(vector)
    end
    return string.format("(%.3f, %.3f, %.3f)", vector.X, vector.Y, vector.Z)
end

local function formatAngles(rotationVector)
    if typeof(rotationVector) ~= "Vector3" then
        return tostring(rotationVector)
    end
    return string.format("(%.1f, %.1f, %.1f)", math.deg(rotationVector.X), math.deg(rotationVector.Y), math.deg(rotationVector.Z))
end

local function formatCFrame(cf)
    if typeof(cf) ~= "CFrame" then
        return tostring(cf)
    end
    local rx, ry, rz = cf:ToOrientation()
    return string.format("pos=%s rot=%s", formatVector3(cf.Position), formatAngles(Vector3.new(rx, ry, rz)))
end

local function getFullNameSafe(instance)
    if not instance then
        return "(nil)"
    end
    local ok, fullName = pcall(function()
        return instance:GetFullName()
    end)
    return ok and fullName or tostring(instance)
end

local function getAppliedSkinModel(character)
    if not character or not character:IsA("Model") then
        return nil
    end

    local direct = character:FindFirstChild(APPLIED_MODEL_NAME)
    if direct and direct:IsA("Model") then
        return direct
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute(FULL_BODY_SKIN_MODEL_ATTRIBUTE) then
            return child
        end
    end

    return nil
end

local function buildRightHandNameSet(handPart)
    local nameSet = {}
    local handName = normalizeName(handPart and handPart.Name or "RightHand")
    nameSet[handName] = true

    if handName == "righthand" then
        nameSet.rightarm = true
        nameSet.rightlowerarm = true
        nameSet.rightupperarm = true
    elseif handName == "rightarm" then
        nameSet.righthand = true
        nameSet.rightlowerarm = true
        nameSet.rightupperarm = true
    elseif handName == "rightlowerarm" then
        nameSet.righthand = true
        nameSet.rightarm = true
        nameSet.rightupperarm = true
    elseif handName == "rightupperarm" then
        nameSet.righthand = true
        nameSet.rightarm = true
        nameSet.rightlowerarm = true
    end

    return nameSet
end

local function findSkinGripAttachment(character, handPart)
    local skinModel = getAppliedSkinModel(character)
    if not skinModel then
        return nil
    end

    local rightHandNames = buildRightHandNameSet(handPart)
    local fallback = nil

    for _, desc in ipairs(skinModel:GetDescendants()) do
        if desc:IsA("Attachment") and desc.Name == "Grip" then
            local parent = desc.Parent
            if parent and parent:IsA("BasePart") then
                local parentName = normalizeName(parent.Name)
                if rightHandNames[parentName] then
                    return desc
                end
                if not fallback and string.find(parentName, "right", 1, true)
                    and (string.find(parentName, "hand", 1, true) or string.find(parentName, "arm", 1, true)) then
                    fallback = desc
                end
            end
        end
    end

    return fallback
end

local function isToolDescendant(tool, instance)
    return tool and instance and instance:IsDescendantOf(tool) or false
end

local function findCharacterGripMotor(character, tool, handle)
    local bestMatch = nil
    local fallbackMatch = nil

    for _, obj in ipairs(character:GetDescendants()) do
        if obj and obj:IsA("JointInstance") and obj.Part1 == handle then
            local part0 = obj.Part0
            local name = normalizeName(obj.Name)
            local isToolMotor = isToolDescendant(tool, obj) or isToolDescendant(tool, part0)
            if not isToolMotor and part0 and part0:IsDescendantOf(character) then
                if not fallbackMatch then
                    fallbackMatch = obj
                end
                if name == "rightgrip" or name == "toolgrip" then
                    bestMatch = obj
                    break
                end
            end
        end
    end

    return bestMatch or fallbackMatch
end

local function debugGripMotorCandidates(character, tool, handle)
    for _, obj in ipairs(character:GetDescendants()) do
        if obj and obj:IsA("JointInstance") and obj.Part1 == handle then
            local part0 = obj.Part0
            local isToolMotor = isToolDescendant(tool, obj) or isToolDescendant(tool, part0)
            dprint(
                "candidate joint",
                getFullNameSafe(obj),
                "class=",
                obj.ClassName,
                "name=",
                obj.Name,
                "part0=",
                getFullNameSafe(part0),
                "toolMotor=",
                tostring(isToolMotor)
            )
        end
    end
end

local function debugSkinGripCandidates(character)
    local skinModel = getAppliedSkinModel(character)
    if not skinModel then
        dprint("no applied skin model found under", getFullNameSafe(character))
        return
    end

    dprint("applied skin model", getFullNameSafe(skinModel))
    for _, desc in ipairs(skinModel:GetDescendants()) do
        if desc:IsA("Attachment") and desc.Name == "Grip" then
            dprint(
                "skin Grip candidate",
                getFullNameSafe(desc),
                "parent=",
                getFullNameSafe(desc.Parent),
                "local=",
                formatCFrame(desc.CFrame)
            )
        end
    end
end

-- Find and update the character's right-hand grip Motor6D to match the tool Grip.
local function refreshCharacterRightGrip(tool)
    if not tool or not tool.Parent then return false end
    local char = tool.Parent
    if not char:IsA("Model") then return false end
    local handle = getHandle(tool)
    if not handle then return false end
    dprint("refresh start tool=", getFullNameSafe(tool), "char=", getFullNameSafe(char), "handle=", getFullNameSafe(handle))
    local handleGripAttachment = handle:FindFirstChild("Grip")
    if handleGripAttachment and not handleGripAttachment:IsA("Attachment") then
        handleGripAttachment = nil
    end
    local obj = findCharacterGripMotor(char, tool, handle)
    if obj then
        if gripMotorDefaults[obj] == nil then
            gripMotorDefaults[obj] = obj.C0
        end

        local desiredC0 = gripMotorDefaults[obj]
        local desiredC1 = tool.Grip
        local skinGripAttachment = findSkinGripAttachment(char, obj.Part0)
        if skinGripAttachment then
            local skinGripWorldCFrame = skinGripAttachment.Parent.CFrame * skinGripAttachment.CFrame
            local localGripPosition = obj.Part0.CFrame:PointToObjectSpace(skinGripWorldCFrame.Position)
            desiredC0 = replaceCFrameTranslationPreserveRotation(gripMotorDefaults[obj], localGripPosition)
        end
        if handleGripAttachment then
            desiredC1 = replaceCFrameTranslationPreserveRotation(tool.Grip, handleGripAttachment.Position)
        end

        pcall(function()
            obj.C0 = desiredC0
            obj.C1 = desiredC1
        end)
        dprint("selected grip motor", getFullNameSafe(obj), "part0=", getFullNameSafe(obj.Part0), "part1=", getFullNameSafe(obj.Part1))
        dprint("selected skin Grip", skinGripAttachment and getFullNameSafe(skinGripAttachment) or "(none)")
        dprint("selected handle Grip", handleGripAttachment and getFullNameSafe(handleGripAttachment) or "(none)")
        dprint("tool.Grip", formatCFrame(tool.Grip))
        if skinGripAttachment then
            dprint("skin Grip local", formatCFrame(skinGripAttachment.CFrame))
            dprint("skin Grip parent", getFullNameSafe(skinGripAttachment.Parent), "world=", formatCFrame(skinGripAttachment.Parent.CFrame * skinGripAttachment.CFrame))
        end
        if handleGripAttachment then
            dprint("handle Grip local", formatCFrame(handleGripAttachment.CFrame))
            dprint("handle Grip world", formatCFrame(handleGripAttachment.Parent.CFrame * handleGripAttachment.CFrame))
        end
        dprint("applied desired C0", formatCFrame(desiredC0))
        dprint("applied desired C1", formatCFrame(desiredC1))
        return true
    end

    dprint("no valid character grip motor found for", getFullNameSafe(tool))
    debugGripMotorCandidates(char, tool, handle)
    debugSkinGripCandidates(char)

    return false
end

function WeaponScaleService.RefreshGrip(tool)
    return refreshCharacterRightGrip(tool)
end

local function scheduleGripRefresh(tool)
    if not tool or pendingGripRefresh[tool] then
        return
    end

    pendingGripRefresh[tool] = true
    task.spawn(function()
        for _ = 1, 12 do
            if not tool or not tool.Parent then
                break
            end
            if refreshCharacterRightGrip(tool) then
                break
            end
            RunService.Heartbeat:Wait()
        end
        pendingGripRefresh[tool] = nil
    end)
end

function WeaponScaleService.BindGripAlignment(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end
    if boundGripTools[tool] then
        return true
    end

    boundGripTools[tool] = true

    tool.Equipped:Connect(function()
        scheduleGripRefresh(tool)
    end)

    tool.AncestryChanged:Connect(function()
        scheduleGripRefresh(tool)
    end)

    scheduleGripRefresh(tool)

    return true
end

-- Collect BaseParts that are the Handle or descendants of the Handle
local function collectHandleParts(handle)
    local parts = {}
    if not handle then return parts end
    parts[#parts+1] = handle
    for _, obj in ipairs(handle:GetDescendants()) do
        if obj:IsA("BasePart") then parts[#parts+1] = obj end
    end
    return parts
end

-- Collect weld-like joints under the tool
local function collectWelds(tool)
    local welds = {}
    for _, obj in ipairs(tool:GetDescendants()) do
        if obj:IsA("Weld") or obj:IsA("ManualWeld") or obj:IsA("Motor6D") then
            welds[#welds+1] = obj
        end
    end
    return welds
end

-- Cache originals per-tool. Returns entry or nil on failure.
function WeaponScaleService.CacheOriginals(tool)
    if not tool or not tool.Parent then return nil end
    if cache[tool] then return cache[tool] end

    local handle = getHandle(tool)
    if not handle then
        warn("[WeaponScale] No Handle found for tool:", tool.Name)
        return nil
    end

    local entry = {
        tool = tool,
        handle = handle,
        parts = {},     -- [part] = { Size, MeshScale, RelCFrame, RelToGrip }
        welds = {},     -- [weld] = { C0, C1, Part0, Part1, inside0, inside1 }
        weldControlled = {}, -- set of parts controlled by welds
    }

    -- Grip attachment (pivot). Cache original Tool.Grip and attachment CFrame.
    local gripAtt = handle:FindFirstChild("Grip")
    if not gripAtt or not gripAtt:IsA("Attachment") then
        warn("[WeaponScale] Grip attachment missing on Handle for tool:", tool.Name)
        entry.grip = nil
        entry.originalGripLocalCF = nil
        entry.originalGripWorldCF = nil
    else
        entry.grip = gripAtt
        entry.originalGripLocalCF = gripAtt.CFrame
        entry.originalGripWorldCF = handle.CFrame * gripAtt.CFrame
    end
    entry.originalToolGrip = tool.Grip

    -- Parts: handle + descendants of handle
    local parts = collectHandleParts(handle)
    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") then
            local mesh = part:FindFirstChildOfClass("SpecialMesh")
            -- Compute part CFrame relative to Grip pivot if available, otherwise relative to Handle
            local relCF = handle.CFrame:ToObjectSpace(part.CFrame)
            local relToGrip = nil
            if entry.originalGripWorldCF then
                relToGrip = entry.originalGripWorldCF:ToObjectSpace(part.CFrame)
            else
                relToGrip = relCF
            end
            local partEntry = {
                Size = part.Size,
                MeshScale = mesh and mesh.Scale or nil,
                RelCFrame = relCF,
                RelToGrip = relToGrip,
                Attachments = {},
            }
            -- Cache attachments (Grip, Trail anchors, etc.) so their local positions scale with the part
            for _, child in ipairs(part:GetChildren()) do
                if child and child:IsA("Attachment") then
                    local ok, pos = pcall(function() return child.Position end)
                    local ok2, ori = pcall(function() return child.Orientation end)
                    partEntry.Attachments[child] = {
                        Position = (ok and pos) and pos or Vector3.new(),
                        Orientation = (ok2 and ori) and ori or Vector3.new(),
                    }
                end
            end
            entry.parts[part] = partEntry
        end
    end

    -- Weld-like joints inside the tool
    local welds = collectWelds(tool)
    for _, w in ipairs(welds) do
        local p0 = w.Part0
        local p1 = w.Part1
        local inside0 = p0 and entry.parts[p0]
        local inside1 = p1 and entry.parts[p1]
        entry.welds[w] = {
            C0 = w.C0,
            C1 = w.C1,
            Part0 = p0,
            Part1 = p1,
            inside0 = (inside0 ~= nil),
            inside1 = (inside1 ~= nil),
        }
        if inside0 then entry.weldControlled[p0] = true end
        if inside1 then entry.weldControlled[p1] = true end
    end

    -- Debug prints: discovered welds
    print("[WeaponScale] Cached tool:", tool:GetFullName())
    if next(entry.welds) == nil then
        warn("[WeaponScale] No weld-like joints discovered inside tool:", tool.Name)
    else
        for w, wdata in pairs(entry.welds) do
            local tname = w.ClassName or "Weld"
            local n0 = (wdata.Part0 and wdata.Part0.Name) or "(nil)"
            local n1 = (wdata.Part1 and wdata.Part1.Name) or "(nil)"
            print("[WeaponScale] Weld:", w:GetFullName(), tname, "Part0=", n0, "Part1=", n1)
        end
    end

    -- Debug: which parts are weld-controlled
    for part, pd in pairs(entry.parts) do
        if entry.weldControlled[part] then
            print("[WeaponScale] Part weld-controlled:", part:GetFullName())
        else
            print("[WeaponScale] Part free (non-welded):", part:GetFullName())
        end
    end

    cache[tool] = entry
    return entry
end

local function applyScaleFromCache(entry, scale)
    if not entry or not entry.handle then return end
    local handle = entry.handle

    -- 1) Scale handle size from original
    local hpd = entry.parts[handle]
    if hpd and hpd.Size then
        pcall(function() handle.Size = hpd.Size * scale end)
    end

    -- 2) Scale sizes and mesh scales for all parts (works for welded and free parts)
    for part, pd in pairs(entry.parts) do
        if part and part.Parent then
            if pd.Size then pcall(function() part.Size = pd.Size * scale end) end
            if pd.MeshScale then
                local mesh = part:FindFirstChildOfClass("SpecialMesh")
                if mesh then pcall(function() mesh.Scale = pd.MeshScale * scale end) end
            end
            -- Scale attachments (Grip, Trail anchors) so they move with the part size
            if pd.Attachments then
                for att, adot in pairs(pd.Attachments) do
                    if att and att.Parent then
                        pcall(function() att.Position = adot.Position * scale end)
                        pcall(function() att.Orientation = adot.Orientation end)
                        print("[WeaponScale] Scaled attachment:", att:GetFullName(), "on part", part:GetFullName())
                    end
                end
            end
        end
    end

    -- 3) For weld-driven parts, scale the weld offsets (C0/C1). Do NOT set part.CFrame.
    for w, wdata in pairs(entry.welds) do
        if w and w.Parent then
            -- only scale the C0/C1 positional component; preserve rotation exactly
            local ok0, newC0 = pcall(function() return scaleCFrameTranslationPreserveRotation(wdata.C0, scale) end)
            if ok0 then
                pcall(function() w.C0 = newC0 end)
            end
            local ok1, newC1 = pcall(function() return scaleCFrameTranslationPreserveRotation(wdata.C1, scale) end)
            if ok1 then
                pcall(function() w.C1 = newC1 end)
            end
        end
    end

    -- 4) For parts not controlled by welds, set world CFrame relative to Handle
    for part, pd in pairs(entry.parts) do
        if part and part.Parent then
                if not entry.weldControlled[part] then
                    -- Position free parts relative to the Handle (never reposition the Handle itself)
                    if part ~= handle then
                        local rel = pd.RelCFrame
                        local rot = CFrame.new(rel.Position):Inverse() * rel -- preserve rotation exactly
                        local newRel = CFrame.new(rel.Position * scale) * rot
                        local world = handle.CFrame * newRel
                        pcall(function() part.CFrame = world end)
                        print("[WeaponScale] Free-part positioned:", part:GetFullName())
                    end
            else
                print("[WeaponScale] Weld-driven part left to weld system:", part:GetFullName())
            end
        end
    end
    
    -- 5) After scaling parts/welds/attachments, compensate Tool.Grip so player's hand remains on the Grip attachment
    if entry.originalToolGrip and entry.originalGripLocalCF and entry.grip then
        local currentGripLocalCF = entry.grip.CFrame
        -- Correct formula: keep the same transform from Grip -> hand.
        -- original grip->hand = originalGripLocalCF:Inverse() * originalToolGrip
        -- new Tool.Grip should be: currentGripLocalCF * (originalGripLocalCF:Inverse() * originalToolGrip)
        -- i.e. newToolGrip = currentGripLocalCF * originalGripLocalCF:Inverse() * entry.originalToolGrip
        local newToolGrip = currentGripLocalCF * entry.originalGripLocalCF:Inverse() * entry.originalToolGrip
        pcall(function() entry.tool.Grip = newToolGrip end)
        print("[WeaponScale] Adjusted Tool.Grip for", entry.tool:GetFullName())

        -- If tool is currently equipped, update the character's RightGrip Motor6D C1 instead of unequipping
        refreshCharacterRightGrip(entry.tool)
    elseif entry.originalToolGrip and entry.originalGripLocalCF and not entry.grip then
        warn("[WeaponScale] Grip attachment not present; Tool.Grip not adjusted for", entry.tool.Name)
    end
end

-- API: ApplyScale(tool, scalePercent)
function WeaponScaleService.ApplyScale(tool, scalePercent)
    if not tool then return false, "no tool" end
    local s = normalizeScaleInput(scalePercent)
    if not s then return false, "invalid scale" end

    local entry = cache[tool] or WeaponScaleService.CacheOriginals(tool)
    if not entry then return false, "cache failed" end

    -- Always compute from original cache (no compounding)
    applyScaleFromCache(entry, s)
    print("[WeaponScale] Applied scale", s, "to", tool:GetFullName())
    return true
end

function WeaponScaleService.ResetScale(tool)
    if not tool then return false end
    local entry = cache[tool]
    if not entry then return false end
    applyScaleFromCache(entry, 1.0)
    print("[WeaponScale] Reset scale for", tool:GetFullName())
    return true
end

function WeaponScaleService.ClearCache(tool)
    if not tool then return false end
    cache[tool] = nil
    print("[WeaponScale] Cleared cache for", tool:GetFullName())
    return true
end

return WeaponScaleService
