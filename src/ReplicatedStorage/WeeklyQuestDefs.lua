--------------------------------------------------------------------------------
-- WeeklyQuestDefs.lua  –  Shared weekly quest pool (ReplicatedStorage)
-- Used by WeeklyQuestService (server) and weekly quest boards (client).
--
-- Weekly quests are scaled copies of the daily pool:
--   goal   x3 / x4 / x5
--   reward x5 / x6 / x7  (matching the chosen goal multiplier)
-- A weekly board never rolls two variants of the same daily quest.
--------------------------------------------------------------------------------

local DailyQuestDefs = require(script.Parent:WaitForChild("DailyQuestDefs"))

local WeeklyQuestDefs = {}

WeeklyQuestDefs.GOAL_MULTIPLIERS = { 3, 4, 5 }
WeeklyQuestDefs.REWARD_MULTIPLIERS = {
	[3] = 5,
	[4] = 6,
	[5] = 7,
}

WeeklyQuestDefs.TrackTypes = table.clone(DailyQuestDefs.TrackTypes)

local function formatGoal(n)
	local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
	while true do
		local nextS, replaced = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		s = nextS
		if replaced == 0 then
			break
		end
	end
	return s
end

local function scaleDescription(desc, newGoal)
	local scaled = tostring(desc or ""):gsub("%d[%d,]*", formatGoal(newGoal), 1)
	if newGoal ~= 1 then
		scaled = scaled:gsub("(%d) match$", "%1 matches")
		scaled = scaled:gsub("(%d) match ", "%1 matches ")
		scaled = scaled:gsub("(%d) time$", "%1 times")
		scaled = scaled:gsub("(%d) time ", "%1 times ")
	end
	return scaled
end

WeeklyQuestDefs.Pool = {}
for _, daily in ipairs(DailyQuestDefs.Pool) do
	for _, goalMult in ipairs(WeeklyQuestDefs.GOAL_MULTIPLIERS) do
		local rewardMult = WeeklyQuestDefs.REWARD_MULTIPLIERS[goalMult]
		local goal = (tonumber(daily.goal) or 0) * goalMult
		local reward = (tonumber(daily.reward) or 0) * rewardMult
		table.insert(WeeklyQuestDefs.Pool, {
			id          = daily.id .. "_x" .. tostring(goalMult),
			sourceId    = daily.id,
			title       = daily.title,
			desc        = scaleDescription(daily.desc, goal),
			goal        = goal,
			reward      = reward,
			trackType   = daily.trackType,
			goalMult    = goalMult,
			rewardMult  = rewardMult,
		})
	end
end

WeeklyQuestDefs.ById = {}
for _, def in ipairs(WeeklyQuestDefs.Pool) do
	WeeklyQuestDefs.ById[def.id] = def
end

WeeklyQuestDefs.ByTrackType = {}
WeeklyQuestDefs.BySourceId = {}
for _, def in ipairs(WeeklyQuestDefs.Pool) do
	if not WeeklyQuestDefs.ByTrackType[def.trackType] then
		WeeklyQuestDefs.ByTrackType[def.trackType] = {}
	end
	table.insert(WeeklyQuestDefs.ByTrackType[def.trackType], def)

	if not WeeklyQuestDefs.BySourceId[def.sourceId] then
		WeeklyQuestDefs.BySourceId[def.sourceId] = {}
	end
	table.insert(WeeklyQuestDefs.BySourceId[def.sourceId], def)
end

return WeeklyQuestDefs
