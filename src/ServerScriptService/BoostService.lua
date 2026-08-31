--------------------------------------------------------------------------------
-- BoostService.lua
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))

local DATASTORE_NAME = "Boosts_v2"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)
local _SaveCoordinator

local BoostConfig
local function getBoostConfig()
	if BoostConfig then return BoostConfig end
	pcall(function()
		local mod = ReplicatedStorage:WaitForChild("BoostConfig", 10)
		if mod and mod:IsA("ModuleScript") then
			BoostConfig = require(mod)
		end
	end)
	return BoostConfig
end

local CurrencyService
local function getCurrencyService()
	if CurrencyService then return CurrencyService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("CurrencyService")
		if mod and mod:IsA("ModuleScript") then
			CurrencyService = require(mod)
		end
	end)
	return CurrencyService
end

local function getSaveCoordinator()
	if _SaveCoordinator == nil then
		local ok, coordinator = pcall(function()
			return require(ServerScriptService:WaitForChild("DataSaveCoordinator"))
		end)
		if ok then
			_SaveCoordinator = coordinator
		else
			_SaveCoordinator = false
		end
	end
	if _SaveCoordinator == false then
		return nil
	end
	return _SaveCoordinator
end

local function markDirty(player, reason, options)
	local coordinator = getSaveCoordinator()
	if coordinator then
		coordinator:MarkDirty(player, "Boost", reason or "boost", options)
	end
end

local QuestService
local function getQuestService()
	if QuestService then return QuestService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("QuestService")
		if mod and mod:IsA("ModuleScript") then
			QuestService = require(mod)
		end
	end)
	return QuestService
end

local HumanoidStatService
local function getHumanoidStatService()
	if HumanoidStatService then return HumanoidStatService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("HumanoidStatService")
		if mod and mod:IsA("ModuleScript") then
			HumanoidStatService = require(mod)
		end
	end)
	return HumanoidStatService
end

local HealthPotionService
local function getHealthPotionService()
	if HealthPotionService then return HealthPotionService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("HealthPotionService")
		if mod and mod:IsA("ModuleScript") then
			HealthPotionService = require(mod)
		end
	end)
	return HealthPotionService
end

local MOVEMENT_SPEED_STAT = "MovementSpeed"

local WeeklyQuestService
local function getWeeklyQuestService()
	if WeeklyQuestService then return WeeklyQuestService end
	pcall(function()
		local mod = ServerScriptService:FindFirstChild("WeeklyQuestService")
		if mod and mod:IsA("ModuleScript") then
			WeeklyQuestService = require(mod)
		end
	end)
	return WeeklyQuestService
end

local BoostService = {}

local playerBoosts = {}
local playerHealTasks = {}
local boostSaveWatch = {}

local DAILY_REROLL_COOLDOWN  = 45
local WEEKLY_REROLL_COOLDOWN = 90
local rerollCooldowns = {}

local function getKey(player)
	return "User_" .. tostring(player.UserId)
end

local function makeEmptyState()
	local state = {
		inventory = {},
		active = {},
		bonusClaimed = {},
		freeRerolls = 0,
	}

	local config = getBoostConfig()
	if config and config.Boosts then
		for _, def in ipairs(config.Boosts) do
			if not def.InstantUse then
				state.inventory[def.Id] = 0
				state.active[def.Id] = { expiresAt = 0 }
			end
		end
	end

	return state
end

local function remainingToExpiresAt(rem)
	rem = math.max(0, math.floor(tonumber(rem) or 0))
	if rem <= 0 then
		return 0
	end
	return os.time() + rem
end

local function normalizePlayerState(raw)
	local state = makeEmptyState()
	raw = type(raw) == "table" and raw or {}

	state.freeRerolls = math.max(0, math.floor(tonumber(raw.freeRerolls) or 0))

	if type(raw.inventory) == "table" then
		for boostId, count in pairs(raw.inventory) do
			state.inventory[boostId] = math.max(0, math.floor(tonumber(count) or 0))
		end
	end

	local function readActive(entry)
		if type(entry) ~= "table" then
			return 0
		end
		if entry.remaining ~= nil then
			return remainingToExpiresAt(entry.remaining)
		end
		return math.floor(tonumber(entry.expiresAt) or 0)
	end

	if type(raw.active) == "table" then
		for boostId, entry in pairs(raw.active) do
			state.active[boostId] = { expiresAt = readActive(entry) }
		end
	elseif type(raw.timed) == "table" then
		for boostId, entry in pairs(raw.timed) do
			state.active[boostId] = { expiresAt = readActive(entry) }
		end
	end

	if type(raw.bonusClaimed) == "table" then
		for questId, claimed in pairs(raw.bonusClaimed) do
			if claimed then
				state.bonusClaimed[questId] = true
			end
		end
	end

	return state
end

local function clearExpiredBoosts(player)
	local pd = playerBoosts[player]
	if not pd then return end

	local now = os.time()
	for boostId, entry in pairs(pd.active) do
		if type(entry) ~= "table" or (entry.expiresAt or 0) <= now then
			pd.active[boostId] = { expiresAt = 0 }
		end
	end
end

local function applyActiveBoostEffects(player, boostId, entry)
	if not player or type(boostId) ~= "string" or type(entry) ~= "table" then return end
	local config = getBoostConfig()
	if not config then return end
	local def = config.GetById(boostId)
	if not def then return end

	local remaining = math.max(0, (tonumber(entry.expiresAt) or 0) - os.time())
	if remaining <= 0 then
		return
	end

	if def.AdditiveBonus and tonumber(def.AdditiveBonus) and tonumber(def.AdditiveBonus) ~= 0 then
		local hss = getHumanoidStatService()
		if hss and type(hss.SetModifier) == "function" then
			pcall(function()
				hss:SetModifier(player, MOVEMENT_SPEED_STAT, def.ModifierId or def.Id, {
					additive = tonumber(def.AdditiveBonus) or 0,
					duration = remaining,
					source = def.DisplayName,
				})
			end)
		end
	end

	if def.OutgoingFlatAdd and tonumber(def.OutgoingFlatAdd) and tonumber(def.OutgoingFlatAdd) ~= 0 then
		local hps = getHealthPotionService()
		if hps and type(hps.SetOutgoingFlatModifier) == "function" then
			pcall(function()
				hps:SetOutgoingFlatModifier(player, def.ModifierId or def.Id, tonumber(def.OutgoingFlatAdd), remaining, def.DisplayName)
			end)
		end
	end

	if def.HealthRegenPerTick and tonumber(def.HealthRegenPerTick) and def.HealthRegenTickInterval and tonumber(def.HealthRegenTickInterval) then
		local amount = math.max(0, math.floor(tonumber(def.HealthRegenPerTick) or 0))
		local tick = math.max(0.1, tonumber(def.HealthRegenTickInterval) or 5)
		if amount > 0 then
			if not playerHealTasks[player] then playerHealTasks[player] = {} end
			if playerHealTasks[player][def.Id] then return end
			local token = {}
			playerHealTasks[player][def.Id] = token
			task.spawn(function()
				local expiresAtLocal = os.time() + remaining
				while true do
					if not playerHealTasks[player] or playerHealTasks[player][def.Id] ~= token then break end
					if os.time() >= expiresAtLocal then break end
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local missing = math.max(0, humanoid.MaxHealth - humanoid.Health)
						if missing > 0 then
							humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
						end
					end
					local rem = expiresAtLocal - os.time()
					if rem <= 0 then break end
					task.wait(math.min(tick, rem))
				end
				if playerHealTasks[player] then playerHealTasks[player][def.Id] = nil end
			end)
		end
	end
end

local function serializePlayerState(pd)
	local payload = {
		inventory = {},
		active = {},
		bonusClaimed = {},
		freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0)),
	}

	local now = os.time()

	for boostId, count in pairs(pd.inventory) do
		payload.inventory[boostId] = math.max(0, math.floor(tonumber(count) or 0))
	end

	local written = {}
	for boostId, entry in pairs(pd.active) do
		local expiresAt = 0
		if type(entry) == "table" then
			expiresAt = math.floor(tonumber(entry.expiresAt) or 0)
		end
		payload.active[boostId] = {
			remaining = math.max(0, expiresAt - now),
		}
		written[boostId] = true
	end

	local config = getBoostConfig()
	if config and config.Boosts then
		for _, def in ipairs(config.Boosts) do
			if not def.InstantUse and not written[def.Id] then
				payload.active[def.Id] = { remaining = 0 }
			end
		end
	end

	for questId, claimed in pairs(pd.bonusClaimed) do
		if claimed then
			payload.bonusClaimed[questId] = true
		end
	end

	return payload
end

local function ensurePlayerData(player)
	if not playerBoosts[player] then
		playerBoosts[player] = makeEmptyState()
	end
	return playerBoosts[player]
end

local boostStateEvent

local function pushBoostState(player)
	if not boostStateEvent then return end
	local states = BoostService:GetPlayerBoostStates(player)
	pcall(function()
		boostStateEvent:FireClient(player, states)
	end)
end

local function hasLiveBoost(player)
	local pd = playerBoosts[player]
	if not pd or type(pd.active) ~= "table" then
		return false
	end
	local now = os.time()
	for _, entry in pairs(pd.active) do
		if type(entry) == "table" and (tonumber(entry.expiresAt) or 0) > now then
			return true
		end
	end
	return false
end

local function startBoostSaveWatch(player)
	if not player or boostSaveWatch[player] then
		return
	end
	boostSaveWatch[player] = true

	task.spawn(function()
		local lastRemaining = {}

		while player.Parent and playerBoosts[player] do
			clearExpiredBoosts(player)

			local pd = playerBoosts[player]
			local now = os.time()
			local expiredNow = false

			if pd and type(pd.active) == "table" then
				for boostId, entry in pairs(pd.active) do
					local remaining = 0
					if type(entry) == "table" then
						remaining = math.max(0, (tonumber(entry.expiresAt) or 0) - now)
					end
					if lastRemaining[boostId] ~= nil and lastRemaining[boostId] > 0 and remaining <= 0 then
						expiredNow = true
					end
					lastRemaining[boostId] = remaining
				end
			end

			if expiredNow then
				pushBoostState(player)
				markDirty(player, "boost_expired", { force = true })
			elseif hasLiveBoost(player) then
				markDirty(player, "boost_tick")
			end

			task.wait(10)
		end

		boostSaveWatch[player] = nil
	end)
end

function BoostService:Init()
	getBoostConfig()
	getCurrencyService()
	getQuestService()
	getWeeklyQuestService()

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		boostStateEvent = remotesFolder:FindFirstChild("BoostStateUpdated")
	end
end

function BoostService:LoadProfileForPlayer(player)
	if not player then
		return {
			status = "failed",
			data = makeEmptyState(),
			reason = "missing player",
		}
	end

	local key = getKey(player)
	local success, result, err = DataStoreOps.Load(ds, key, "Boost/" .. key)

	if success then
		playerBoosts[player] = normalizePlayerState(result)
	else
		warn("[BoostService] Failed to load boost data for", player.Name, "- using defaults")
		playerBoosts[player] = makeEmptyState()
	end

	clearExpiredBoosts(player)
	pushBoostState(player)

	local pd = playerBoosts[player]
	if pd and type(pd.active) == "table" then
		for boostId, entry in pairs(pd.active) do
			if type(entry) == "table" and (entry.expiresAt or 0) > os.time() then
				pcall(function()
					applyActiveBoostEffects(player, boostId, entry)
				end)
			end
		end
	end

	startBoostSaveWatch(player)

	if not success then
		return {
			status = "failed",
			data = DataStoreOps.DeepCopy(playerBoosts[player]),
			reason = err,
		}
	end
	if result == nil then
		return {
			status = "new",
			data = DataStoreOps.DeepCopy(playerBoosts[player]),
		}
	end
	return {
		status = "existing",
		data = DataStoreOps.DeepCopy(playerBoosts[player]),
	}
end

function BoostService:LoadForPlayer(player)
	local result = self:LoadProfileForPlayer(player)
	return result and result.status ~= "failed"
end

function BoostService:GetSaveData(player)
	local pd = playerBoosts[player]
	if not pd then return nil end
	clearExpiredBoosts(player)
	return serializePlayerState(pd)
end

function BoostService:SaveProfileForPlayer(player, payload, oldData)
	local pd = playerBoosts[player]
	if not player or not pd then return false, "missing boost state" end

	clearExpiredBoosts(player)

	local key = getKey(player)
	payload = payload or serializePlayerState(pd)
	local success, _, err = DataStoreOps.Update(ds, key, "Boost/" .. key, function(storedPayload)
		return payload or storedPayload
	end)

	if not success then
		warn("[BoostService] Failed to save boost data for", player.Name)
	end

	return success, err
end

function BoostService:SaveForPlayer(player)
	return self:SaveProfileForPlayer(player)
end

function BoostService:SaveAll()
	for _, plr in ipairs(Players:GetPlayers()) do
		self:SaveForPlayer(plr)
	end
end

function BoostService:PurchaseOwnedBoost(player, boostId)
	if not player or type(boostId) ~= "string" then
		return false, "Invalid request"
	end

	local config = getBoostConfig()
	if not config then return false, "Config unavailable" end
	local def = config.GetById(boostId)
	if not def then return false, "Unknown boost" end
	if def.InstantUse then
		return false, "Use the dedicated action for this boost"
	end
	if def.RemovedFromShop == true or def.Purchasable == false then
		return false, "Boost unavailable"
	end

	local pd = ensurePlayerData(player)
	local cs = getCurrencyService()
	if not cs then return false, "Currency system unavailable" end
	if cs:GetCoins(player) < def.PriceCoins then
		return false, "Insufficient coins"
	end

	cs:AddCoins(player, -def.PriceCoins)
	pd.inventory[boostId] = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0)) + 1

	pushBoostState(player)
	markDirty(player, "boost_purchase")
	return true, "Purchased", self:GetPlayerBoostStates(player)
end

function BoostService:ActivateOwnedBoost(player, boostId)
	if not player or type(boostId) ~= "string" then
		return false, "Invalid request"
	end

	local config = getBoostConfig()
	if not config then return false, "Config unavailable" end
	local def = config.GetById(boostId)
	if not def then return false, "Unknown boost" end
	if def.InstantUse then
		return false, "Use the dedicated action for this boost"
	end

	local pd = ensurePlayerData(player)
	clearExpiredBoosts(player)

	local owned = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0))
	if owned < 1 then
		return false, "Not owned", self:GetPlayerBoostStates(player)
	end

	local activeEntry = pd.active[boostId]
	if not def.Stackable and activeEntry and (activeEntry.expiresAt or 0) > os.time() then
		return false, "Already active", self:GetPlayerBoostStates(player)
	end

	pd.inventory[boostId] = owned - 1
	pd.active[boostId] = { expiresAt = os.time() + def.DurationSeconds }

	applyActiveBoostEffects(player, boostId, pd.active[boostId])
	pushBoostState(player)
	markDirty(player, "boost_activate", { force = true })
	startBoostSaveWatch(player)
	return true, "Activated", self:GetPlayerBoostStates(player)
end

function BoostService:BuyAndActivate(player, boostId)
	return self:PurchaseOwnedBoost(player, boostId)
end

local function getRerollCooldownRemaining(player, questType)
	local cd = rerollCooldowns[player]
	if not cd then return 0 end
	return math.max(0, (cd[questType] or 0) - os.time())
end

local function setRerollCooldown(player, questType)
	if not rerollCooldowns[player] then
		rerollCooldowns[player] = { daily = 0, weekly = 0 }
	end
	local duration = questType == "weekly" and WEEKLY_REROLL_COOLDOWN or DAILY_REROLL_COOLDOWN
	rerollCooldowns[player][questType] = os.time() + duration
end

function BoostService:GetRerollCooldowns(player)
	if not player then return { daily = 0, weekly = 0, freeRerolls = 0 } end
	local pd = ensurePlayerData(player)
	return {
		daily = getRerollCooldownRemaining(player, "daily"),
		weekly = getRerollCooldownRemaining(player, "weekly"),
		freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0)),
	}
end

function BoostService:RerollQuest(player, questType, questIndex)
	if not player or type(questType) ~= "string" or type(questIndex) ~= "number" then
		return false, "Invalid request"
	end

	local config = getBoostConfig()
	if not config then return false, "Config unavailable" end
	local def = config.GetById("quest_reroll")
	if not def then return false, "Reroll config missing" end

	local cdRemaining = getRerollCooldownRemaining(player, questType)
	if cdRemaining > 0 then
		return false, "Reroll on cooldown", nil, cdRemaining
	end

	local pd = ensurePlayerData(player)
	local usedFreeReroll = false
	if pd.freeRerolls and pd.freeRerolls > 0 then
		usedFreeReroll = true
	else
		local cs = getCurrencyService()
		if not cs then return false, "Currency system unavailable" end
		if cs:GetCoins(player) < def.PriceCoins then
			return false, "Insufficient coins"
		end
	end

	local service
	local quests
	if questType == "daily" then
		service = getQuestService()
		if not service then return false, "Quest system unavailable" end
		quests = service:GetQuestsForPlayer(player)
	elseif questType == "weekly" then
		service = getWeeklyQuestService()
		if not service then return false, "Weekly quest system unavailable" end
		quests = service:GetWeeklyQuests(player)
	else
		return false, "Invalid quest type"
	end

	if not quests or questIndex < 1 or questIndex > #quests then
		return false, "Invalid quest index"
	end

	local target = quests[questIndex]
	if target.progress >= target.goal then
		return false, "Completed quests cannot be rerolled"
	end
	if target.claimed then
		return false, "Quest already claimed"
	end

	local success, msg, updatedQuests = service:RerollQuest(player, questIndex)
	if not success then
		return false, msg or "Reroll failed"
	end

	if usedFreeReroll then
		pd.freeRerolls = pd.freeRerolls - 1
		markDirty(player, "free_reroll_consumed", { force = true })
	else
		local cs = getCurrencyService()
		if cs then
			cs:AddCoins(player, -def.PriceCoins)
		end
	end

	setRerollCooldown(player, questType)
	pushBoostState(player)
	markDirty(player, "quest_reroll")
	return true, "Quest rerolled", updatedQuests
end

function BoostService:BonusClaim(player, questId)
	if not player or type(questId) ~= "string" then
		return false, "Invalid request"
	end

	local config = getBoostConfig()
	if not config then return false, "Config unavailable" end
	local def = config.GetById("bonus_claim")
	if not def then return false, "Bonus claim config missing" end

	local pd = ensurePlayerData(player)
	if pd.bonusClaimed[questId] then
		return false, "Bonus already claimed for this quest"
	end

	local cs = getCurrencyService()
	if not cs then return false, "Currency system unavailable" end
	if cs:GetCoins(player) < def.PriceCoins then
		return false, "Insufficient coins"
	end

	local qs = getQuestService()
	if not qs then return false, "Quest system unavailable" end

	local quests = qs:GetQuestsForPlayer(player)
	local questDef
	for _, q in ipairs(quests) do
		if q.id == questId then questDef = q break end
	end
	if not questDef then
		return false, "Quest not found"
	end
	if questDef.progress < questDef.goal then
		return false, "Quest not completed"
	end

	cs:AddCoins(player, -def.PriceCoins, "bonus_claim")
	cs:AddCoins(player, questDef.reward, "quest_bonus")
	pd.bonusClaimed[questId] = true

	pushBoostState(player)
	markDirty(player, "bonus_claim")
	return true, "Bonus reward claimed"
end

function BoostService:HasActiveBoost(player, boostId)
	clearExpiredBoosts(player)
	local pd = playerBoosts[player]
	if not pd then return false end
	local entry = pd.active[boostId]
	if not entry then return false end
	return (entry.expiresAt or 0) > os.time()
end

function BoostService:GetCoinMultiplier(player)
	if self:HasActiveBoost(player, "coins_2x") then
		local def = getBoostConfig() and getBoostConfig().GetById("coins_2x")
		return def and def.Multiplier or 2
	end
	return 1
end

function BoostService:GetQuestProgressMultiplier(player)
	if self:HasActiveBoost(player, "quest_2x") then
		local def = getBoostConfig() and getBoostConfig().GetById("quest_2x")
		return def and def.Multiplier or 2
	end
	return 1
end

function BoostService:GetXPMultiplier(player)
	if self:HasActiveBoost(player, "xp_2x") then
		local def = getBoostConfig() and getBoostConfig().GetById("xp_2x")
		return def and def.Multiplier or 2
	end
	return 1
end

function BoostService:GetMasteryMultiplier(player)
	if self:HasActiveBoost(player, "mastery_2x") then
		local def = getBoostConfig() and getBoostConfig().GetById("mastery_2x")
		return def and def.Multiplier or 2
	end
	return 1
end

function BoostService:GetPlayerBoostStates(player)
	local pd = ensurePlayerData(player)
	clearExpiredBoosts(player)
	local states = {}
	local config = getBoostConfig()
	if not config then return states end

	local now = os.time()
	for _, def in ipairs(config.Boosts) do
		local entry = {
			active = false,
			expiresAt = 0,
			owned = 0,
		}
		if not def.InstantUse then
			entry.owned = math.max(0, math.floor(tonumber(pd.inventory[def.Id]) or 0))
			local active = pd.active[def.Id]
			if active and (active.expiresAt or 0) > now then
				entry.active = true
				entry.expiresAt = active.expiresAt
			end
		end
		states[def.Id] = entry
	end

	states._bonusClaimed = pd.bonusClaimed
	states._serverTime = now
	states._freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0))
	return states
end

function BoostService:ClearPlayer(player)
	playerBoosts[player] = nil
	playerHealTasks[player] = nil
	boostSaveWatch[player] = nil
end

function BoostService:GrantFreeReroll(player, count)
	if not player then return false end
	count = math.max(1, math.floor(tonumber(count) or 1))
	local pd = ensurePlayerData(player)
	pd.freeRerolls = math.max(0, math.floor(tonumber(pd.freeRerolls) or 0)) + count
	pushBoostState(player)
	markDirty(player, "grant_free_reroll", { force = true })
	return true
end

function BoostService:GetFreeRerolls(player)
	if not player then return 0 end
	local pd = ensurePlayerData(player)
	return math.max(0, math.floor(tonumber(pd.freeRerolls) or 0))
end

function BoostService:GrantFreeBoost(player, boostId, count)
	if not player or type(boostId) ~= "string" then return false end
	count = math.max(1, math.floor(tonumber(count) or 1))

	local config = getBoostConfig()
	if not config then return false end
	local def = config.GetById(boostId)
	if not def or def.InstantUse then return false end

	local pd = ensurePlayerData(player)
	pd.inventory[boostId] = math.max(0, math.floor(tonumber(pd.inventory[boostId]) or 0)) + count
	pushBoostState(player)
	markDirty(player, "grant_free_boost")
	return true
end

return BoostService