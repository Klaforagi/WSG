--------------------------------------------------------------------------------
-- MobDeathFade.server.lua
-- On death: wait for ragdoll to settle → fade all parts → destroy model.
-- Works for ZombieNPC-tagged mobs and legacy "Dummy" models.
--------------------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local MOB_TAG        = "ZombieNPC"
local PRE_FADE_DELAY = 2    -- seconds to let ragdoll play before fading
local FADE_TIME      = 1    -- seconds the transparency tween takes
local POST_FADE_WAIT = 0.5  -- extra buffer after tween before Destroy

---------------------------------------------------------------------------
-- Collect every tweeneable descendant, tween them, then destroy the model.
---------------------------------------------------------------------------
local function fadeAndDestroy(model)
    if not model or not model.Parent then return end

    -- 1) wait so ragdoll / falling animation is visible
    task.wait(PRE_FADE_DELAY)
    if not model or not model.Parent then return end

    -- 2) disable collisions and tween transparency on every part / decal
    local ti = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            pcall(function()
                desc.CanCollide = false
                desc.Anchored = true          -- freeze in place while fading
                TweenService:Create(desc, ti, { Transparency = 1 }):Play()
            end)
        elseif desc:IsA("Decal") or desc:IsA("Texture") then
            pcall(function()
                TweenService:Create(desc, ti, { Transparency = 1 }):Play()
            end)
        end
    end

    -- 3) wait for tween to finish, then clean up
    task.wait(FADE_TIME + POST_FADE_WAIT)
    if model and model.Parent then
        pcall(function() model:Destroy() end)
    end
end

---------------------------------------------------------------------------
-- Hook into Humanoid.Died
---------------------------------------------------------------------------
local function attachToModel(model)
    if not model or not model:IsA("Model") then return end
    if model:GetAttribute("_fadeHandlerAttached") then return end
    model:SetAttribute("_fadeHandlerAttached", true)

    local function hookHumanoid(hum)
        hum.Died:Connect(function()
            task.spawn(fadeAndDestroy, model)
        end)
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then hookHumanoid(hum) end

    model.ChildAdded:Connect(function(child)
        if child and child:IsA("Humanoid") then hookHumanoid(child) end
    end)
end

-- Existing tagged mobs
for _, m in ipairs(CollectionService:GetTagged(MOB_TAG)) do
    pcall(function() attachToModel(m) end)
end
-- Newly tagged mobs
CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(m)
    pcall(function() attachToModel(m) end)
end)

-- Legacy "Dummy" models
for _, child in ipairs(Workspace:GetDescendants()) do
    if child:IsA("Model") and child.Name == "Dummy" then
        pcall(function() attachToModel(child) end)
    end
end
Workspace.DescendantAdded:Connect(function(child)
    if child and child:IsA("Model") and child.Name == "Dummy" then
        pcall(function() attachToModel(child) end)
    end
end)
