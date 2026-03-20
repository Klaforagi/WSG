--------------------------------------------------------------------------------
-- UpgradeConfig.lua  –  Shared upgrade definitions (ReplicatedStorage)
-- Readable by both server and client. All upgrade metadata lives here.
--
-- SYSTEM: Two weapon upgrade paths (melee & ranged) with infinite levels.
-- PvP damage is capped for fairness; PvE damage scales indefinitely.
-- Upgrade costs round to clean values (multiples of 5 / 10 / 25).
--------------------------------------------------------------------------------

local UpgradeConfig = {}

--------------------------------------------------------------------------------
-- Upgrade IDs (the only two upgrade paths)
--------------------------------------------------------------------------------
UpgradeConfig.MELEE  = "melee_weapon"
UpgradeConfig.RANGED = "ranged_weapon"

--- All valid upgrade ids for validation
UpgradeConfig.ValidIds = {
	[UpgradeConfig.MELEE]  = true,
	[UpgradeConfig.RANGED] = true,
}

--------------------------------------------------------------------------------
-- Cost tuning
--------------------------------------------------------------------------------
UpgradeConfig.BASE_COST     = 25    -- starting coin cost at level 0→1
UpgradeConfig.COST_EXPONENT = 1.08  -- cost growth per level (smooth ramp)

--------------------------------------------------------------------------------
-- PvP damage tuning  (capped for balance)
--   bonus = min(level * BONUS_PER_LEVEL, MAX_BONUS)
--   multiplier = 1 + bonus
--------------------------------------------------------------------------------
UpgradeConfig.PvP = {
	[UpgradeConfig.MELEE] = {
		BONUS_PER_LEVEL = 0.02,  -- +2 % per level
		MAX_BONUS       = 0.50,  -- 50 % cap  (effective cap level ≈ 25)
	},
	[UpgradeConfig.RANGED] = {
		BONUS_PER_LEVEL = 0.015, -- +1.5 % per level
		MAX_BONUS       = 0.35,  -- 35 % cap  (effective cap level ≈ 24)
	},
}

--------------------------------------------------------------------------------
-- PvE damage tuning  (generous, no cap — scales indefinitely)
--   multiplier = 1 + level * BONUS_PER_LEVEL
--------------------------------------------------------------------------------
UpgradeConfig.PvE = {
	[UpgradeConfig.MELEE] = {
		BONUS_PER_LEVEL = 0.03,  -- +3 % per level (level 100 → 4× damage to mobs)
	},
	[UpgradeConfig.RANGED] = {
		BONUS_PER_LEVEL = 0.03,  -- +3 % per level
	},
}

--------------------------------------------------------------------------------
-- Display metadata per upgrade type
--------------------------------------------------------------------------------
UpgradeConfig.Display = {
	[UpgradeConfig.MELEE] = {
		Title         = "MELEE",
		Description   = "Permanently increases melee weapon power.",
		Glyph         = "\u{2694}",    -- ⚔
		Accent        = Color3.fromRGB(255, 120, 65),
		ImageId       = "",
		ImageRotation = -12,
	},
	[UpgradeConfig.RANGED] = {
		Title         = "RANGED",
		Description   = "Permanently increases ranged weapon power.",
		Glyph         = "\u{1F3AF}",   -- 🎯
		Accent        = Color3.fromRGB(80, 165, 255),
		ImageId       = "",
		ImageRotation = 12,
	},
}

--------------------------------------------------------------------------------
-- Internal: round a raw cost to a clean player-facing number.
--------------------------------------------------------------------------------
local function roundCost(raw)
	if raw <= 100 then
		return math.max(5, math.ceil(raw / 5) * 5)      -- nearest 5
	elseif raw <= 1000 then
		return math.ceil(raw / 10) * 10                  -- nearest 10
	else
		return math.ceil(raw / 25) * 25                  -- nearest 25
	end
end

--------------------------------------------------------------------------------
-- Helper functions  (used by server AND client)
--------------------------------------------------------------------------------

--- Cost for the next upgrade at the given level.
--- Always returns a cleanly rounded whole number.
function UpgradeConfig.GetCost(level)
	level = math.max(0, math.floor(level or 0))
	local raw = UpgradeConfig.BASE_COST * (UpgradeConfig.COST_EXPONENT ^ level)
	return roundCost(raw)
end

--- PvP damage multiplier (capped).
function UpgradeConfig.GetPvPMultiplier(level, weaponType)
	level = math.max(0, math.floor(level or 0))
	local cfg = UpgradeConfig.PvP[weaponType]
	if not cfg then return 1 end
	local bonus = math.min(level * cfg.BONUS_PER_LEVEL, cfg.MAX_BONUS)
	return 1 + bonus
end

--- PvE damage multiplier (uncapped — keeps scaling).
function UpgradeConfig.GetPvEMultiplier(level, weaponType)
	level = math.max(0, math.floor(level or 0))
	local cfg = UpgradeConfig.PvE[weaponType]
	if not cfg then return 1 end
	return 1 + (level * cfg.BONUS_PER_LEVEL)
end

--- Displayed bonus percent for the UI (matches weapon level directly).
--- Level 1 = +1%, Level 11 = +11%, Level 100 = +100%.
function UpgradeConfig.GetDisplayedBonusPercent(level, _weaponType)
	level = math.max(0, math.floor(level or 0))
	return level
end

--- Human-readable bonus text for the UI.
function UpgradeConfig.GetBonusText(level, weaponType)
	level = math.max(0, math.floor(level or 0))
	if level == 0 then return "No bonus" end
	local pct = UpgradeConfig.GetDisplayedBonusPercent(level, weaponType)
	return "+" .. tostring(pct) .. "%"
end

--- Legacy general multiplier (backward compat — returns PvE melee rate).
function UpgradeConfig.GetMultiplier(level)
	level = math.max(0, math.floor(level or 0))
	return 1 + (level * 0.03)
end

--- Returns true if upgradeId is a recognised weapon upgrade.
function UpgradeConfig.IsValid(upgradeId)
	return UpgradeConfig.ValidIds[upgradeId] == true
end

return UpgradeConfig
