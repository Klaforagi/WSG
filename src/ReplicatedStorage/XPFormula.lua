-- XPFormula.lua
-- Helper functions for XP/level calculations.

local XPFormula = {}

-- Returns XP required to advance FROM the given level to the next level.
-- Level 1 -> needs 50, level 2 -> 100, ... level 9 -> 450, level >=10 -> 500.
function XPFormula.GetXPRequiredForLevel(level)
    level = math.max(1, math.floor(level or 1))
    if level >= 10 then
        return 500
    end
    return level * 50
end

return XPFormula
