local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Default configuration
local defaults = {
    damage = 20,
    cd = 0.4, -- seconds cooldown
    bulletspeed = 100, -- studs/sec
    range = 600,
    projectile_lifetime = 10,
    projectile_size = {0.4, 0.4, 0.4}, -- table to serialize Vector3
    bulletdrop = 0, -- studs per second squared (gravity-like pull)
    showTracer = true, -- whether client shows tracer visuals

}

-- Preset configurations for named tool types (keys are lowercase, e.g. 'pistol', 'sniper')
local presets = {
    pistol = {
        damage = 18,
        cd = 0.18,
        bulletspeed = 600,
        range = 450,
        projectile_lifetime = 2,
        projectile_size = {0.3,0.3,0.3},
        bulletdrop = 0,
        showTracer = true,
    },
    sniper = {
        damage = 120,
        cd = 1.6,
        bulletspeed = 2200,
        range = 5000,
        projectile_lifetime = 6,
        projectile_size = {0.2,0.2,0.8},
        bulletdrop = 0,
        showTracer = true,
    }
}

local function readOverrides()
    local folder = ReplicatedStorage:FindFirstChild("Toolgun")
    if not folder then return nil end
    local cfg = {}
    for k, v in pairs(defaults) do
        local obj = folder:FindFirstChild(k)
        if obj then
            if obj:IsA("NumberValue") then
                cfg[k] = obj.Value
            elseif obj:IsA("BoolValue") then
                cfg[k] = obj.Value
            elseif obj:IsA("Color3Value") then
                cfg[k] = {math.floor(obj.Value.R*255), math.floor(obj.Value.G*255), math.floor(obj.Value.B*255)}
            else
                cfg[k] = v
            end
        else
            cfg[k] = v
        end
    end
    return cfg
end

local settings = readOverrides() or defaults

local module = {}

function module.get()
    return settings
end

function module.refresh()
    settings = readOverrides() or defaults
    return settings
end

-- Convenience accessors
for k, v in pairs(settings) do
    module[k] = v
end

-- expose presets and defaults for callers that want per-tool configs
module.defaults = defaults
module.presets = presets

return module
