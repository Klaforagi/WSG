--------------------------------------------------------------------------------
-- UIResponsiveScaler.lua
--
-- Shared responsive UI scaling helper for KingsGround menus.
--
-- Goals (see WSG_Responsive_UI_System):
--   * Provide a single source of truth for a viewport-aware UI scale.
--   * Re-apply scale live when the player resizes the game window.
--   * Cap scale on large monitors so menu content does not balloon in size.
--   * Offer a reusable responsive grid helper that picks column counts based on
--     available container width and capped card sizes (so fullscreen produces
--     more columns instead of giant cards).
--   * Avoid stacking duplicate `UIScale` instances on the same root.
--
-- Public API:
--   GetViewportScale(opts?)            -> number
--   ApplyUIScale(root, opts?)          -> UIScale, disconnect()
--   ApplyResponsiveGrid(grid, opts)    -> disconnect()
--   ApplyResponsiveText(label, opts?)  -> UITextSizeConstraint
--   BindToViewportChanged(callback)    -> disconnect()
--   ReflowNow(root)
--   Px(base, opts?)                    -> number  (utility)
--
-- Design notes:
--   * The default reference resolution is 1920x1080.
--   * The default scale clamp is [0.55, 1.0]. Capping at 1.0 prevents fullscreen
--     monitors from enlarging the whole UI; instead, menus get more usable
--     surface area while card sizes stay capped through `ApplyResponsiveGrid`.
--   * UIScale instances created here are named `ResponsiveUIScale` so callers
--     can rely on a stable name when looking them up.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local UIResponsiveScaler = {}

local DEFAULT_DESIGN_WIDTH  = 1920
local DEFAULT_DESIGN_HEIGHT = 1080
local DEFAULT_MIN_SCALE     = 0.55
local DEFAULT_MAX_SCALE     = 1.00
local SCALE_INSTANCE_NAME   = "ResponsiveUIScale"

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------
local function getViewport()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 1 and cam.ViewportSize.Y > 1 then
        return cam.ViewportSize.X, cam.ViewportSize.Y
    end
    return DEFAULT_DESIGN_WIDTH, DEFAULT_DESIGN_HEIGHT
end

local function safeDisconnect(c)
    if c then pcall(function() c:Disconnect() end) end
end

local function resolveOpts(opts)
    opts = opts or {}
    local designW = tonumber(opts.designWidth)  or DEFAULT_DESIGN_WIDTH
    local designH = tonumber(opts.designHeight) or DEFAULT_DESIGN_HEIGHT
    local minS    = tonumber(opts.minScale)     or DEFAULT_MIN_SCALE
    local maxS    = tonumber(opts.maxScale)     or DEFAULT_MAX_SCALE
    if maxS < minS then maxS = minS end
    return designW, designH, minS, maxS
end

--------------------------------------------------------------------------------
-- GetViewportScale(opts?)
--   Returns a clamped scalar that is the smaller of widthScale/heightScale.
--   opts: { designWidth?, designHeight?, minScale?, maxScale? }
--------------------------------------------------------------------------------
function UIResponsiveScaler.GetViewportScale(opts)
    local designW, designH, minS, maxS = resolveOpts(opts)
    local vw, vh = getViewport()
    local wScale = vw / designW
    local hScale = vh / designH
    local scale = math.min(wScale, hScale)
    if scale ~= scale then scale = 1 end -- NaN guard
    return math.clamp(scale, minS, maxS)
end

--------------------------------------------------------------------------------
-- Px(base, opts?)
--   Convenience: returns base * GetViewportScale(opts), rounded, >=1.
--------------------------------------------------------------------------------
function UIResponsiveScaler.Px(base, opts)
    local s = UIResponsiveScaler.GetViewportScale(opts)
    return math.max(1, math.floor((tonumber(base) or 0) * s + 0.5))
end

--------------------------------------------------------------------------------
-- BindToViewportChanged(callback) -> disconnect()
--   Calls `callback()` whenever the active camera's ViewportSize changes,
--   including when CurrentCamera itself swaps. Safe across camera replacement.
--------------------------------------------------------------------------------
function UIResponsiveScaler.BindToViewportChanged(callback)
    if type(callback) ~= "function" then
        return function() end
    end

    local viewportConn
    local function attachCamera(cam)
        safeDisconnect(viewportConn)
        viewportConn = nil
        if cam then
            viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
        end
    end

    local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        attachCamera(workspace.CurrentCamera)
        callback()
    end)
    attachCamera(workspace.CurrentCamera)

    return function()
        safeDisconnect(cameraConn)
        safeDisconnect(viewportConn)
    end
end

--------------------------------------------------------------------------------
-- ApplyUIScale(root, opts?) -> UIScale, disconnect()
--   Ensures `root` has a single `ResponsiveUIScale` whose Scale tracks the
--   viewport. Reuses any existing instance with that name. Safe to call again.
--
--   opts:
--     designWidth, designHeight, minScale, maxScale  – passed to GetViewportScale
--     onApply(scale)                                 – optional callback
--------------------------------------------------------------------------------
function UIResponsiveScaler.ApplyUIScale(root, opts)
    if not (root and root:IsA("GuiObject")) then
        return nil, function() end
    end
    opts = opts or {}

    local scaleInst = root:FindFirstChild(SCALE_INSTANCE_NAME)
    if not (scaleInst and scaleInst:IsA("UIScale")) then
        -- Remove any other stray UIScale at this level to avoid stacking.
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("UIScale") and child.Name ~= SCALE_INSTANCE_NAME then
                pcall(function() child:Destroy() end)
            end
        end
        scaleInst = Instance.new("UIScale")
        scaleInst.Name = SCALE_INSTANCE_NAME
        scaleInst.Parent = root
    end

    local function apply()
        local s = UIResponsiveScaler.GetViewportScale(opts)
        scaleInst.Scale = s
        if opts.onApply then
            pcall(opts.onApply, s)
        end
    end

    apply()
    local disconnectViewport = UIResponsiveScaler.BindToViewportChanged(apply)

    local ancestryConn
    ancestryConn = root.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            disconnectViewport()
            safeDisconnect(ancestryConn)
        end
    end)

    return scaleInst, function()
        disconnectViewport()
        safeDisconnect(ancestryConn)
    end
end

--------------------------------------------------------------------------------
-- ApplyResponsiveGrid(gridLayout, opts) -> disconnect()
--   Re-sizes UIGridLayout cells based on available container width so that
--   cards stay within [minCardWidth, maxCardWidth] and the column count grows
--   when there is room, instead of cards inflating on large monitors.
--
--   opts:
--     container       Required. ScrollingFrame/Frame whose AbsoluteSize.X drives the layout.
--     padding         Optional UIPadding inside `container` (its left/right offsets are subtracted).
--     aspectRatio     Card height/width ratio (default 1.0). e.g. 188/158 ~= 1.19
--     minCardWidth    Default 130. Hard lower bound on chosen cell width.
--     preferredCardWidth  Default 180. Target width when room is plentiful.
--     maxCardWidth    Default 230. Hard upper bound; prevents giant cards.
--     minColumns      Default 1.
--     maxColumns      Default 8.
--     scrollBarAware  Default true. Reserves container.ScrollBarThickness when present.
--     onLayout(cols, cellW, cellH)  Optional callback after each reflow.
--------------------------------------------------------------------------------
function UIResponsiveScaler.ApplyResponsiveGrid(gridLayout, opts)
    assert(opts and opts.container, "ApplyResponsiveGrid: opts.container is required")
    if not (gridLayout and gridLayout:IsA("UIGridLayout")) then
        return function() end
    end

    local container          = opts.container
    local padding            = opts.padding
    local aspectRatio        = tonumber(opts.aspectRatio)    or 1.0
    local minCardWidth       = tonumber(opts.minCardWidth)   or 130
    local preferredCardWidth = tonumber(opts.preferredCardWidth) or 180
    local maxCardWidth       = tonumber(opts.maxCardWidth)   or 230
    local minColumns         = math.max(1, tonumber(opts.minColumns) or 1)
    local maxColumns         = math.max(minColumns, tonumber(opts.maxColumns) or 8)
    local scrollBarAware     = opts.scrollBarAware ~= false
    if preferredCardWidth < minCardWidth then preferredCardWidth = minCardWidth end
    if preferredCardWidth > maxCardWidth then preferredCardWidth = maxCardWidth end

    local function reflow()
        local availW = container.AbsoluteSize.X
        if availW <= 0 then return end

        if padding then
            availW = availW
                - (padding.PaddingLeft  and padding.PaddingLeft.Offset  or 0)
                - (padding.PaddingRight and padding.PaddingRight.Offset or 0)
        end
        if scrollBarAware and container:IsA("ScrollingFrame") then
            availW = availW - math.max(0, container.ScrollBarThickness or 0)
        end
        if availW <= 0 then return end

        local cellPadX = (gridLayout.CellPadding and gridLayout.CellPadding.X.Offset) or 0

        -- Pick column count using preferred width as the target.
        local cols = math.floor((availW + cellPadX) / (preferredCardWidth + cellPadX))
        cols = math.clamp(cols, minColumns, maxColumns)

        -- Compute the cell width that fully uses the available row.
        local fitW = math.floor((availW - cellPadX * math.max(0, cols - 1)) / cols)
        -- Clamp to card-size bounds. When clamped, leftover space simply
        -- becomes empty horizontal margin within the container.
        local cellW = math.clamp(fitW, minCardWidth, maxCardWidth)
        local cellH = math.max(1, math.floor(cellW * aspectRatio))

        gridLayout.FillDirectionMaxCells = cols
        gridLayout.CellSize = UDim2.new(0, cellW, 0, cellH)

        if opts.onLayout then
            pcall(opts.onLayout, cols, cellW, cellH)
        end
    end

    local connections = {}
    table.insert(connections, container:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow))
    table.insert(connections, UIResponsiveScaler.BindToViewportChanged(reflow))

    local ancestryConn
    ancestryConn = container.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            for _, c in ipairs(connections) do
                if type(c) == "function" then c() else safeDisconnect(c) end
            end
            safeDisconnect(ancestryConn)
        end
    end)

    task.defer(reflow)

    return function()
        for _, c in ipairs(connections) do
            if type(c) == "function" then c() else safeDisconnect(c) end
        end
        safeDisconnect(ancestryConn)
    end
end

--------------------------------------------------------------------------------
-- ApplyResponsiveText(label, opts?) -> UITextSizeConstraint
--   Adds (or reuses) a UITextSizeConstraint so TextScaled labels stay within
--   readable bounds. Safe to call multiple times on the same label.
--   opts: { minTextSize?, maxTextSize? }
--------------------------------------------------------------------------------
function UIResponsiveScaler.ApplyResponsiveText(label, opts)
    if not (label and label:IsA("GuiObject")) then return nil end
    opts = opts or {}
    local minTS = tonumber(opts.minTextSize) or 10
    local maxTS = tonumber(opts.maxTextSize) or 28
    if maxTS < minTS then maxTS = minTS end

    local cons = label:FindFirstChildOfClass("UITextSizeConstraint")
    if not cons then
        cons = Instance.new("UITextSizeConstraint")
        cons.Parent = label
    end
    cons.MinTextSize = minTS
    cons.MaxTextSize = maxTS
    return cons
end

--------------------------------------------------------------------------------
-- ReflowNow(root)
--   Manually force a re-evaluation of the root scale (if one is attached).
--------------------------------------------------------------------------------
function UIResponsiveScaler.ReflowNow(root)
    if not (root and root:IsA("GuiObject")) then return end
    local scaleInst = root:FindFirstChild(SCALE_INSTANCE_NAME)
    if scaleInst and scaleInst:IsA("UIScale") then
        scaleInst.Scale = UIResponsiveScaler.GetViewportScale()
    end
end

return UIResponsiveScaler
