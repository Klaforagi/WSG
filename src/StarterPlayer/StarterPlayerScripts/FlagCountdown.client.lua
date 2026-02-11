local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Fade countdown text based on distance: fully visible up close, transparent far away
local FADE_START = 60   -- studs – fully opaque up to this distance
local FADE_END   = 200  -- studs – fully transparent beyond this distance

local tracked = {}

local function trackGui(gui)
    if not gui or not gui:IsA("BillboardGui") then return end
    if gui.Name ~= "ReturnCountdown" then return end
    local label = gui:FindFirstChildOfClass("TextLabel")
    if not label then return end
    tracked[gui] = label
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

RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    for gui, label in pairs(tracked) do
        if not gui or not gui.Parent or not gui.Adornee then
            tracked[gui] = nil
        else
            local ok, adornPos = pcall(function() return gui.Adornee.Position end)
            if not ok or not adornPos then
                tracked[gui] = nil
            else
                local dist = (cam.CFrame.Position - adornPos).Magnitude
                -- calculate fade: 0 = fully visible, 1 = fully transparent
                local alpha = math.clamp((dist - FADE_START) / (FADE_END - FADE_START), 0, 1)
                label.TextTransparency = alpha
                label.TextStrokeTransparency = alpha
            end
        end
    end
end)
