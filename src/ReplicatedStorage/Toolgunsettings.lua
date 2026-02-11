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
}

local function readOverrides()
    local folder = ReplicatedStorage:FindFirstChild("Toolgun")
    if not folder then return nil end
    local cfg = {}
    for k, v in pairs(defaults) do
        local obj = folder:FindFirstChild(k)
        if obj and obj:IsA("NumberValue") then
            cfg[k] = obj.Value
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

return module
