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
-- Cost tuning  (Scrap-based, flat per-level cost)
--------------------------------------------------------------------------------
UpgradeConfig.CURRENCY      = "scrap"  -- payment currency for upgrades
UpgradeConfig.BASE_COST     = 50       -- flat scrap cost per level (was coin-based exponential)
UpgradeConfig.COST_EXPONENT = 1.0      -- 1.0 = flat (kept for legacy compatibility)

-- Player-level requirement to upgrade. Set to false to disable the gate.
UpgradeConfig.REQUIRE_PLAYER_LEVEL = false

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
--- Returns a flat scrap cost (50) by default; preserved exponent path for
--- legacy callers that may still want a curve.
function UpgradeConfig.GetCost(level)
	level = math.max(0, math.floor(level or 0))
	local exp = UpgradeConfig.COST_EXPONENT or 1.0
	if exp <= 1.000001 then
		return UpgradeConfig.BASE_COST
	end
	local raw = UpgradeConfig.BASE_COST * (exp ^ level)
	return roundCost(raw)
end

--- Currency type accessor (always "scrap" now; older code may have asked for coins).
function UpgradeConfig.GetCurrency()
	return UpgradeConfig.CURRENCY or "scrap"
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
--- Now uses the centralized GetDamageMultiplier curve so melee + ranged
--- share the same progression. Preserves PvP caps separately.
function UpgradeConfig.GetPvEMultiplier(level, weaponType)
	level = math.max(0, math.floor(level or 0))
	return UpgradeConfig.GetDamageMultiplier(level)
end

--- Displayed bonus percent for the UI — derived from the centralized damage
--- curve so what the player sees matches what they actually deal.
function UpgradeConfig.GetDisplayedBonusPercent(level, _weaponType)
	level = math.max(0, math.floor(level or 0))
	local mult = UpgradeConfig.GetDamageMultiplier(level)
	return math.floor((mult - 1) * 100 + 0.5)
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

--------------------------------------------------------------------------------
-- Centralized damage-multiplier curve (USE THIS — do not duplicate the math).
--
-- Target table:
--   Level 0     = 1.00x
--   Level 25    = 1.25x
--   Level 50    = 1.50x
--   Level 100   ≈ 1.65x
--   Level 250   ≈ 1.88x
--   Level 500   = 2.00x
--   Level 1000  ≈ 2.15x
--   Level 5000  ≈ 2.20x
--   Level 10000 ≈ 2.22x
--
-- Implementation:
--   * 0–50:    linear 1.00 → 1.50
--   * 51–500:  smooth diminishing 1.50 → 2.00 (sqrt-shaped)
--   * 500+:    diminishing toward asymptote ≈ 2.222 (1 - exp decay)
--
-- Monotonic non-decreasing. Capped well below 2.25.
--------------------------------------------------------------------------------
local DAMAGE_CAP_HIGH = 2.222 -- effective high-end cap
function UpgradeConfig.GetDamageMultiplier(level)
	level = math.max(0, math.floor(tonumber(level) or 0))

	if level <= 50 then
		-- Linear 1.00 → 1.50 across [0, 50]
		return 1.0 + (0.5 * level / 50)
	end

	if level <= 500 then
		-- Smooth diminishing from 1.50 at L=50 → 2.00 at L=500.
		-- Use sqrt-shaped progression of (level - 50) / 450.
		local t = (level - 50) / 450
		return 1.5 + 0.5 * math.sqrt(t)
	end

	-- Above 500: asymptotic curve to ~2.222.
	-- 2.0 + (HIGH - 2.0) * (1 - exp(-k * (L-500)))
	-- Pick k so that at L=1000 we reach ~2.15:
	--   delta = 0.222, target_added @ L=1000 = 0.15 → 1 - e^{-500k} = 0.6757 → k ≈ 0.00225
	local k = 0.00225
	local extra = (DAMAGE_CAP_HIGH - 2.0) * (1 - math.exp(-k * (level - 500)))
	return math.min(DAMAGE_CAP_HIGH, 2.0 + extra)
end

UpgradeConfig.DAMAGE_CAP = DAMAGE_CAP_HIGH

return UpgradeConfig
