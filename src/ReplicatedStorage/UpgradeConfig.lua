--------------------------------------------------------------------------------
-- UpgradeConfig.lua  –  Shared upgrade definitions (ReplicatedStorage)
-- Readable by both server and client. All upgrade metadata lives here.
--
-- NEW SYSTEM: Two weapon upgrade paths (melee & ranged).
-- Each has infinite levels, scaling cost, and a small permanent damage bonus.
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
-- Tuning constants (easy to rebalance in one place)
--------------------------------------------------------------------------------
UpgradeConfig.BASE_COST        = 25      -- starting coin cost at level 0
UpgradeConfig.COST_EXPONENT    = 1.15    -- cost multiplier per level
UpgradeConfig.DAMAGE_PER_LEVEL = 0.005   -- +0.5% base damage per level

--------------------------------------------------------------------------------
-- Display metadata per upgrade type
--------------------------------------------------------------------------------
UpgradeConfig.Display = {
	[UpgradeConfig.MELEE] = {
		Title         = "MELEE",
		Description   = "Permanently increases base melee weapon damage.",
		Glyph         = "\u{2694}",    -- ⚔
		Accent        = Color3.fromRGB(255, 120, 65),
		ImageId       = "",  -- Replace with rbxassetid://XXXXXXX for custom melee weapon art
		ImageRotation = -12,
	},
	[UpgradeConfig.RANGED] = {
		Title         = "RANGED",
		Description   = "Permanently increases base ranged weapon damage.",
		Glyph         = "\u{1F3AF}",   -- 🎯
		Accent        = Color3.fromRGB(80, 165, 255),
		ImageId       = "",  -- Replace with rbxassetid://XXXXXXX for custom ranged weapon art
		ImageRotation = 12,
	},
}

--------------------------------------------------------------------------------
-- Helper functions (used by server AND client)
--------------------------------------------------------------------------------

--- Cost for the next upgrade at the given level.
--- Returns a whole-number coin price. No cap.
function UpgradeConfig.GetCost(level)
	level = math.max(0, math.floor(level or 0))
	return math.floor(UpgradeConfig.BASE_COST * (UpgradeConfig.COST_EXPONENT ^ level))
end

--- Damage multiplier at a given level (e.g. level 3 → 1.015).
function UpgradeConfig.GetMultiplier(level)
	level = math.max(0, math.floor(level or 0))
	return 1 + (level * UpgradeConfig.DAMAGE_PER_LEVEL)
end

--- Human-readable bonus text, e.g. "+1.5% damage".
function UpgradeConfig.GetBonusText(level)
	level = math.max(0, math.floor(level or 0))
	if level == 0 then return "No bonus" end
	local pct = level * UpgradeConfig.DAMAGE_PER_LEVEL * 100
	-- show one decimal if fractional, else whole number
	local txt
	if pct == math.floor(pct) then
		txt = tostring(math.floor(pct))
	else
		txt = string.format("%.1f", pct)
	end
	return "+" .. txt .. "% damage"
end

--- Returns true if upgradeId is a recognised weapon upgrade.
function UpgradeConfig.IsValid(upgradeId)
	return UpgradeConfig.ValidIds[upgradeId] == true
end

return UpgradeConfig
