--------------------------------------------------------------------------------
-- UIHelpers.lua  –  Tiny shared UI utilities.
--
-- Right now it provides:
--   * px(base)                  → responsive 1080p-reference scale
--   * tpx(base)                 → device-aware (touch=1.0, desktop=0.85)
--   * ApplyTextStroke(label, opts) → readable outline for text on color bars
--   * ApplyOutlineToProgressText(label) → preset for progress bar text
--
-- Intended to be required by any UI module. Existing local px() helpers can
-- continue to coexist; this is added for future centralization without
-- forcing a wholesale refactor.
--------------------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")

local UIHelpers = {}

--------------------------------------------------------------------------------
-- Responsive pixel scale (1080p reference height).
--------------------------------------------------------------------------------
function UIHelpers.px(base)
    local cam = workspace.CurrentCamera
    local h = (cam and cam.ViewportSize.Y) or 1080
    if h < 200 then h = 1080 end
    return math.max(1, math.floor((tonumber(base) or 0) * (h / 1080) + 0.5))
end

--------------------------------------------------------------------------------
-- Device-aware tweak: touch keeps 1.0, desktop slightly smaller for density.
--------------------------------------------------------------------------------
function UIHelpers.tpx(base)
    local mult = UserInputService.TouchEnabled and 1.0 or 0.85
    return UIHelpers.px((tonumber(base) or 0) * mult)
end

--------------------------------------------------------------------------------
-- ApplyTextStroke(label, { color?, transparency?, thickness? })
--   Adds (or updates) a readable outline on a TextLabel/TextButton. Falls
--   back to TextStrokeColor3/TextStrokeTransparency for legacy targets.
--------------------------------------------------------------------------------
function UIHelpers.ApplyTextStroke(label, opts)
    if not label or not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
        return
    end
    opts = opts or {}
    local color = opts.color or Color3.fromRGB(0, 0, 0)
    local transparency = opts.transparency
    if transparency == nil then transparency = 0.25 end
    local thickness = opts.thickness or 1.5

    -- Legacy stroke (always cheap, immediate on every device)
    label.TextStrokeColor3 = color
    label.TextStrokeTransparency = transparency

    -- Modern UIStroke gives crisper outline; reuse if present.
    local stroke = label:FindFirstChild("ProgressTextStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Name = "ProgressTextStroke"
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        stroke.LineJoinMode = Enum.LineJoinMode.Round
        stroke.Parent = label
    end
    stroke.Color = color
    stroke.Transparency = math.clamp(transparency - 0.15, 0, 1)
    stroke.Thickness = thickness
end

--------------------------------------------------------------------------------
-- Preset for progress bar text (works over any fill color).
--------------------------------------------------------------------------------
function UIHelpers.ApplyOutlineToProgressText(label)
    UIHelpers.ApplyTextStroke(label, {
        color = Color3.fromRGB(0, 0, 0),
        transparency = 0,
        thickness = 1.5,
    })
end

return UIHelpers
