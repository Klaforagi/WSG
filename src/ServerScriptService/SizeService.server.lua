local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local SizeService = {}

-- Returns the player's current effective size (base 10 = normal)
function SizeService:GetSize(player)
    if not player then return 10 end
    local ok, val = pcall(function()
        return HumanoidStatService:GetFinalStat(player, "Size")
    end)
    if ok and type(val) == "number" then return val end
    return 10
end

-- Set the player's base size (overrides default base until changed)
function SizeService:SetBaseSize(player, base)
    if not player then return nil end
    return HumanoidStatService:SetBaseStat(player, "Size", tonumber(base) or 10)
end

-- Add or update a size modifier (options: additive, multiplier, duration, source)
function SizeService:SetModifier(player, modifierId, options)
    if not player then return nil end
    return HumanoidStatService:SetModifier(player, "Size", modifierId, options)
end

function SizeService:RemoveModifier(player, modifierId)
    if not player then return nil end
    return HumanoidStatService:RemoveModifier(player, "Size", modifierId)
end

return SizeService
