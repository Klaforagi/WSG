local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Fade countdown text based on distance: fully visible up close, transparent far away
local FADE_START = 60   -- studs – fully opaque up to this distance
local FADE_END   = 200  -- studs – fully transparent beyond this distance
local BADGE_BASE_TRANSPARENCY = 0.12
local BADGE_STROKE_BASE_TRANSPARENCY = 0.15

local tracked = {}

local function trackGui(gui)
    if not gui or not gui:IsA("BillboardGui") then return end
    if gui.Name ~= "ReturnCountdown" then return end
    local label = gui:FindFirstChildWhichIsA("TextLabel", true)
    if not label then return end
    local badge = gui:FindFirstChild("Badge", true)
    local stroke = badge and badge:FindFirstChildWhichIsA("UIStroke") or nil
    tracked[gui] = {
        label = label,
        badge = badge,
        stroke = stroke,
    }
end

-- find existing
for _, g in ipairs(Workspace:GetDescendants()) do
    if g:IsA("BillboardGui") and g.Name == "ReturnCountdown" then
        trackGui(g)
    end
end

Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("BillboardGui") and desc.Name == "ReturnCountdown" then
        trackGui(desc)
    end
end)

Workspace.DescendantRemoving:Connect(function(desc)
    if tracked[desc] then
        tracked[desc] = nil
    end
end)

local flagCountdownRenderConn
flagCountdownRenderConn = RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    for gui, elements in pairs(tracked) do
        if not gui or not gui.Parent or not gui.Adornee then
            tracked[gui] = nil
        else
            local ok, adornPos = pcall(function()
                if gui.Adornee:IsA("Attachment") then
                    return gui.Adornee.WorldPosition
                end
                return gui.Adornee.Position
            end)
            if not ok or not adornPos then
                tracked[gui] = nil
            else
                local dist = (cam.CFrame.Position - adornPos).Magnitude
                -- calculate fade: 0 = fully visible, 1 = fully transparent
                local alpha = math.clamp((dist - FADE_START) / (FADE_END - FADE_START), 0, 1)
                elements.label.TextTransparency = alpha
                elements.label.TextStrokeTransparency = math.min(1, alpha + 0.25)
                if elements.badge then
                    elements.badge.BackgroundTransparency = BADGE_BASE_TRANSPARENCY + ((1 - BADGE_BASE_TRANSPARENCY) * alpha)
                end
                if elements.stroke then
                    elements.stroke.Transparency = BADGE_STROKE_BASE_TRANSPARENCY + ((1 - BADGE_STROKE_BASE_TRANSPARENCY) * alpha)
                end
            end
        end
    end
end)

-- Cleanup: if Workspace is ever removed from the DataModel, stop the render loop
workspace.AncestryChanged:Connect(function()
    if not workspace:IsDescendantOf(game) then
        if flagCountdownRenderConn then
            flagCountdownRenderConn:Disconnect()
            flagCountdownRenderConn = nil
        end
    end
end)
