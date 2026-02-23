-- XPFormula.lua
-- Helper functions for XP/level calculations.

local XPFormula = {}

-- Returns XP required to advance FROM the given level to the next level.
-- Level 1 -> needs 100, level 2 -> 200, ... level 9 -> 900, level >=10 -> 1000.
function XPFormula.GetXPRequiredForLevel(level)
    level = math.max(1, math.floor(level or 1))
    if level >= 10 then
        return 1000
    end
    return level * 100
end

return XPFormula
