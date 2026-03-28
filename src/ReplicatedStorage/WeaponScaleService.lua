-- WeaponScaleService.lua
-- Weld-first, robust weapon scaling for Tools whose visual parts are welded.
-- Core rules:
--  - Do NOT set CFrame for welded parts; scale the weld offsets instead.
--  - Cache originals (sizes, mesh scales, weld C0/C1) and always compute from originals.

local WeaponScaleService = {}

local cache = setmetatable({}, { __mode = "k" }) -- weak keys

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

local function getHandle(tool)
    if not tool then return nil end
    local h = tool:FindFirstChild("Handle")
    if h and h:IsA("BasePart") then return h end
    return nil
end

-- Find and update the character's right-hand grip Motor6D to match the tool Grip.
local function refreshCharacterRightGrip(tool)
    if not tool or not tool.Parent then return end
    local char = tool.Parent
    if not char:IsA("Model") then return end
    -- find a Motor6D whose Part1 is the tool's Handle
    for _, obj in ipairs(char:GetDescendants()) do
        if obj and obj:IsA("Motor6D") and obj.Part1 == tool:FindFirstChild("Handle") then
            -- Update only the C1 so the held position follows the tool.Grip
            pcall(function()
                obj.C1 = tool.Grip
            end)
            print("[WeaponScale] Updated character Motor6D C1 for", tool.Name, "->", obj:GetFullName())
            return
        end
    end
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
