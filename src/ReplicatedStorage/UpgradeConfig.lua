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
-- Upgrade IDs
--------------------------------------------------------------------------------
UpgradeConfig.MELEE  = "melee_weapon"
UpgradeConfig.RANGED = "ranged_weapon"
UpgradeConfig.HEALTH = "max_health"

--------------------------------------------------------------------------------
-- Cost tuning  (Shard-based)
--------------------------------------------------------------------------------
UpgradeConfig.CURRENCY      = "scrap"  -- payment currency for upgrades
UpgradeConfig.BASE_COST     = 50        -- first weapon upgrade cost
UpgradeConfig.WEAPON_COST_STEP = 5
UpgradeConfig.WEAPON_COST_CAP = 100
UpgradeConfig.COST_EXPONENT = 1.0       -- 1.0 = flat (kept for legacy compatibility)

-- Legacy global player-level requirement for weapon upgrades.
UpgradeConfig.REQUIRE_PLAYER_LEVEL = false

UpgradeConfig.HEALTH_COST_PER_LEVEL = 100
UpgradeConfig.HEALTH_MAX_LEVEL = 10
UpgradeConfig.HEALTH_LEVEL_STEP = 10
UpgradeConfig.HEALTH_BONUS_PER_LEVEL = 10

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
UpgradeConfig.Definitions = {
	[UpgradeConfig.MELEE] = {
		Title         = "Melee Damage",
		Description   = "Permanently increases melee weapon power.",
		Glyph         = "\u{2694}",    -- ⚔
		Accent        = Color3.fromRGB(255, 120, 65),
		ImageId       = "",
		ImageRotation = -12,
		Cost          = UpgradeConfig.BASE_COST,
		Currency      = UpgradeConfig.CURRENCY,
		Infinite      = true,
		ButtonText    = "UPGRADE",
		StatText      = "+damage",
	},
	[UpgradeConfig.RANGED] = {
		Title         = "Ranged Damage",
		Description   = "Permanently increases ranged weapon power.",
		Glyph         = "\u{1F3AF}",   -- 🎯
		Accent        = Color3.fromRGB(80, 165, 255),
		ImageId       = "",
		ImageRotation = 12,
		Cost          = UpgradeConfig.BASE_COST,
		Currency      = UpgradeConfig.CURRENCY,
		Infinite      = true,
		ButtonText    = "UPGRADE",
		StatText      = "+damage",
	},
	[UpgradeConfig.HEALTH] = {
		Title              = "Max Health",
		Description        = "Increase your maximum health.",
		Glyph              = "\u{2665}",
		Accent             = Color3.fromRGB(95, 235, 120),
		ImageId            = "",
		ImageRotation      = 0,
		Cost               = UpgradeConfig.HEALTH_COST_PER_LEVEL,
		Currency           = UpgradeConfig.CURRENCY,
		MaxLevel           = UpgradeConfig.HEALTH_MAX_LEVEL,
		PlayerLevelStep    = UpgradeConfig.HEALTH_LEVEL_STEP,
		HealthPerLevel     = UpgradeConfig.HEALTH_BONUS_PER_LEVEL,
		UsesLevelBar       = true,
		ButtonText         = "UPGRADE",
		LevelLabelPrefix   = "Lv.",
		ProgressLabel      = "Health Progress",
		StatText           = "+10 HP",
	},
}

UpgradeConfig.Display = UpgradeConfig.Definitions

UpgradeConfig.ValidIds = {}
for upgradeId, _ in pairs(UpgradeConfig.Definitions) do
	UpgradeConfig.ValidIds[upgradeId] = true
end

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

local function getDefinition(upgradeId)
	return UpgradeConfig.Definitions[upgradeId]
end

--------------------------------------------------------------------------------
-- Helper functions  (used by server AND client)
--------------------------------------------------------------------------------

function UpgradeConfig.GetDefinition(upgradeId)
	return getDefinition(upgradeId)
end

--- Cost for the next upgrade at the given level.
function UpgradeConfig.GetCost(level, upgradeId)
	level = math.max(0, math.floor(level or 0))
	if upgradeId == UpgradeConfig.MELEE or upgradeId == UpgradeConfig.RANGED then
		local steppedCost = UpgradeConfig.BASE_COST + (level * UpgradeConfig.WEAPON_COST_STEP)
		return math.min(UpgradeConfig.WEAPON_COST_CAP, steppedCost)
	end
	if upgradeId == UpgradeConfig.HEALTH then
		return math.max(0, (level + 1) * UpgradeConfig.HEALTH_COST_PER_LEVEL)
	end
	local def = getDefinition(upgradeId)
	if def and type(def.Cost) == "number" then
		return math.max(0, math.floor(def.Cost))
	end
	local exp = UpgradeConfig.COST_EXPONENT or 1.0
	if exp <= 1.000001 then
		return UpgradeConfig.BASE_COST
	end
	local raw = UpgradeConfig.BASE_COST * (exp ^ level)
	return roundCost(raw)
end

--- Currency type accessor (always "scrap" now; older code may have asked for coins).
function UpgradeConfig.GetCurrency(upgradeId)
	local def = getDefinition(upgradeId)
	return (def and def.Currency) or UpgradeConfig.CURRENCY or "scrap"
end

function UpgradeConfig.GetMaxLevel(upgradeId)
	local def = getDefinition(upgradeId)
	if not def then return nil end
	if type(def.MaxLevel) == "number" and def.MaxLevel >= 0 then
		return math.floor(def.MaxLevel)
	end
	return nil
end

function UpgradeConfig.HasCap(upgradeId)
	return UpgradeConfig.GetMaxLevel(upgradeId) ~= nil
end

function UpgradeConfig.IsCapped(level, upgradeId)
	level = math.max(0, math.floor(level or 0))
	local maxLevel = UpgradeConfig.GetMaxLevel(upgradeId)
	return maxLevel ~= nil and level >= maxLevel
end

function UpgradeConfig.GetRequiredPlayerLevel(level, upgradeId)
	level = math.max(0, math.floor(level or 0))
	local def = getDefinition(upgradeId)
	if def and type(def.PlayerLevelStep) == "number" and def.PlayerLevelStep > 0 then
		local nextLevel = level + 1
		local maxLevel = UpgradeConfig.GetMaxLevel(upgradeId)
		if maxLevel and nextLevel > maxLevel then
			return nil
		end
		return nextLevel * math.floor(def.PlayerLevelStep)
	end
	if UpgradeConfig.REQUIRE_PLAYER_LEVEL == true then
		return level + 1
	end
	return nil
end

function UpgradeConfig.IsPlayerLevelLocked(level, playerLevel, upgradeId)
	local requiredLevel = UpgradeConfig.GetRequiredPlayerLevel(level, upgradeId)
	if requiredLevel == nil then
		return false, nil
	end
	playerLevel = math.max(1, math.floor(playerLevel or 1))
	return playerLevel < requiredLevel, requiredLevel
end

function UpgradeConfig.GetHealthBonus(level)
	level = math.max(0, math.floor(level or 0))
	return level * UpgradeConfig.HEALTH_BONUS_PER_LEVEL
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
