--------------------------------------------------------------------------------
-- SizeRollService.lua  –  Shared size-roll module (server + client)
--
-- Every weapon rolled from a crate receives a SizePercent between 80 and 200.
-- Size is rolled using weighted tiers so that Normal sizes are common and
-- extreme sizes (King) are very rare.
--
-- SIZE TIERS:
--   Tiny   = 80–89%    (weight 25)  — slightly undersized
--   Normal = 90–110%   (weight 50)  — most common, near default
--   Large  = 111–149%  (weight 18)  — noticeably bigger
--   Giant  = 150–189%  (weight  6)  — very big, uncommon
--   King   = 190–200%  (weight  1)  — massive, extremely rare
--
-- WEIGHTED ROLLING:
--   1. A weighted random pick selects one of the five tiers.
--   2. A uniform random integer is chosen within that tier's range.
--   This produces a bell-curve-like distribution centred on Normal.
--
-- USAGE:
--   local SizeRoll = require(path.to.SizeRollService)
--   local pct, tier = SizeRoll.RollSize()
--   local multiplier = SizeRoll.GetSizeMultiplier(pct)
--   local formatted  = SizeRoll.FormatSizePercent(pct)  --> "107%"
--------------------------------------------------------------------------------

local SizeRollService = {}

--------------------------------------------------------------------------------
-- TIER DEFINITIONS
-- Each tier has a name, an inclusive min/max range, and a weight that controls
-- how likely the tier is to be selected during a roll.
--------------------------------------------------------------------------------
SizeRollService.Tiers = {
    { name = "Tiny",   min = 80,  max = 89,  weight = 25 },
    { name = "Normal", min = 90,  max = 110, weight = 50 },
    { name = "Large",  min = 111, max = 149, weight = 18 },
    { name = "Giant",  min = 150, max = 189, weight = 6  },
    { name = "King",   min = 190, max = 200, weight = 1  },
}

-- Pre-compute cumulative weights for fast lookup
local _cumulativeTiers = {}
local _totalWeight = 0
do
    for _, tier in ipairs(SizeRollService.Tiers) do
        _totalWeight = _totalWeight + tier.weight
        table.insert(_cumulativeTiers, { tier = tier, cumulative = _totalWeight })
    end
end

--------------------------------------------------------------------------------
-- GetSizeTier(percent) -> tierName
-- Returns the tier name string for a given size percentage.
--------------------------------------------------------------------------------
function SizeRollService.GetSizeTier(percent)
    percent = math.clamp(math.floor(percent), 80, 200)
    for _, t in ipairs(SizeRollService.Tiers) do
        if percent >= t.min and percent <= t.max then
            return t.name
        end
    end
    return "Normal" -- fallback
end

--------------------------------------------------------------------------------
-- GetSizeMultiplier(percent) -> number
-- Converts a size percentage (e.g. 107) to a scale multiplier (e.g. 1.07).
--------------------------------------------------------------------------------
function SizeRollService.GetSizeMultiplier(percent)
    return math.clamp(percent, 80, 200) / 100
end

--------------------------------------------------------------------------------
-- FormatSizePercent(percent) -> string
-- Centralized display formatter, e.g. 107 -> "107%"
--------------------------------------------------------------------------------
function SizeRollService.FormatSizePercent(percent)
    return tostring(math.floor(percent)) .. "%"
end

--------------------------------------------------------------------------------
-- RollSize() -> sizePercent (int), sizeTier (string)
-- Performs a weighted random roll:
--   1. Pick a tier using cumulative weights.
--   2. Pick a uniform random integer within that tier's [min, max].
--------------------------------------------------------------------------------
function SizeRollService.RollSize()
    local roll = math.random() * _totalWeight
    local chosenTier = _cumulativeTiers[#_cumulativeTiers].tier -- fallback to last

    for _, entry in ipairs(_cumulativeTiers) do
        if roll <= entry.cumulative then
            chosenTier = entry.tier
            break
        end
    end

    local sizePercent = math.random(chosenTier.min, chosenTier.max)
    return sizePercent, chosenTier.name
end

return SizeRollService
