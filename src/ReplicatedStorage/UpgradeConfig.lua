--------------------------------------------------------------------------------
-- UpgradeConfig.lua  –  Shared upgrade definitions (ReplicatedStorage)
-- Readable by both server and client. All upgrade metadata lives here.
-- To add a new upgrade, append another entry to UPGRADES.
--------------------------------------------------------------------------------

local UpgradeConfig = {}

--- Effect type constants
UpgradeConfig.EffectType = {
	CoinMultiplier       = "CoinMultiplier",       -- increases earnable coin rewards
	QuestProgress        = "QuestProgress",        -- increases quest progress gain
	RespawnReduction     = "RespawnReduction",      -- reduces respawn time
	ObjectiveCoinBonus   = "ObjectiveCoinBonus",   -- increases objective-based coin rewards
}

--- Source categories for coin rewards (used by the reward pipeline)
UpgradeConfig.CoinSource = {
	Elimination = "elimination",  -- PvP kills, mob kills
	Quest       = "quest",        -- quest reward claims
	Objective   = "objective",    -- flag captures, flag returns, etc.
	Purchase    = "purchase",     -- Robux coin purchases (excluded from upgrades)
	Admin       = "admin",        -- admin/test grants (excluded from upgrades)
}

--- Master upgrade definitions list. SortOrder controls display order in the UI.
UpgradeConfig.Upgrades = {
	{
		Id            = "coin_mastery",
		DisplayName   = "Coin Mastery",
		Description   = "Permanently increases earnable coin rewards.",
		MaxLevel      = 5,
		LevelPrices   = { 25, 50, 85, 130, 185 },
		IconAssetId   = "",   -- placeholder; set a Roblox decal id later
		SortOrder     = 1,
		EffectType    = UpgradeConfig.EffectType.CoinMultiplier,
		EffectPerLevel = 0.05,  -- +5% per level
	},
	{
		Id            = "quest_mastery",
		DisplayName   = "Quest Mastery",
		Description   = "Permanently increases daily quest progress gain.",
		MaxLevel      = 5,
		LevelPrices   = { 25, 50, 85, 130, 185 },
		IconAssetId   = "",
		SortOrder     = 2,
		EffectType    = UpgradeConfig.EffectType.QuestProgress,
		EffectPerLevel = 0.10,  -- +10% per level
	},
	{
		Id            = "rapid_recovery",
		DisplayName   = "Rapid Recovery",
		Description   = "Permanently reduces respawn time after elimination.",
		MaxLevel      = 5,
		LevelPrices   = { 20, 40, 70, 110, 160 },
		IconAssetId   = "",
		SortOrder     = 3,
		EffectType    = UpgradeConfig.EffectType.RespawnReduction,
		EffectPerLevel = 0.05,  -- -5% respawn time per level
	},
	{
		Id            = "objective_specialist",
		DisplayName   = "Objective Specialist",
		Description   = "Permanently increases objective-based coin rewards.",
		MaxLevel      = 5,
		LevelPrices   = { 25, 55, 95, 145, 210 },
		IconAssetId   = "",
		SortOrder     = 4,
		EffectType    = UpgradeConfig.EffectType.ObjectiveCoinBonus,
		EffectPerLevel = 0.10,  -- +10% per level
	},
}

--- Lookup an upgrade definition by Id.
function UpgradeConfig.GetById(upgradeId)
	for _, def in ipairs(UpgradeConfig.Upgrades) do
		if def.Id == upgradeId then
			return def
		end
	end
	return nil
end

--- Get the price for the next level of an upgrade. Returns nil if already maxed.
function UpgradeConfig.GetPrice(upgradeId, currentLevel)
	local def = UpgradeConfig.GetById(upgradeId)
	if not def then return nil end
	currentLevel = currentLevel or 0
	if currentLevel >= def.MaxLevel then return nil end
	return def.LevelPrices[currentLevel + 1]
end

--- Get the total effect bonus for a given level (e.g. level 3 at 0.05/level = 0.15).
function UpgradeConfig.GetEffect(upgradeId, level)
	local def = UpgradeConfig.GetById(upgradeId)
	if not def then return 0 end
	level = math.clamp(level or 0, 0, def.MaxLevel)
	return def.EffectPerLevel * level
end

--- Get a human-readable description of the next level's effect.
function UpgradeConfig.GetNextLevelText(upgradeId, currentLevel)
	local def = UpgradeConfig.GetById(upgradeId)
	if not def then return "" end
	if currentLevel >= def.MaxLevel then return "Maxed" end

	local effectType = def.EffectType
	local bonus = def.EffectPerLevel
	local pct = math.floor(bonus * 100 + 0.5)

	if effectType == UpgradeConfig.EffectType.CoinMultiplier then
		return "+" .. pct .. "% earnable coins"
	elseif effectType == UpgradeConfig.EffectType.QuestProgress then
		return "+" .. pct .. "% quest progress"
	elseif effectType == UpgradeConfig.EffectType.RespawnReduction then
		return "-" .. pct .. "% respawn time"
	elseif effectType == UpgradeConfig.EffectType.ObjectiveCoinBonus then
		return "+" .. pct .. "% objective coins"
	end
	return "+" .. pct .. "%"
end

-- TODO: Add more upgrades here in the future

return UpgradeConfig
