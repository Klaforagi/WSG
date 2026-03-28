--------------------------------------------------------------------------------
-- AchievementService.lua  –  Server-side achievement tracking & persistence
-- ModuleScript in ServerScriptService.
--
-- PHASE 1 OVERHAUL:
--   • Staged achievement lines (one active stage visible at a time)
--   • Completion history (newest-to-oldest archive of every completed stage)
--   • achievedOn timestamps for every completion
--   • Category support
--   • First Blood → First Strike migration
--   • Safe schema-version reset (v2 → v3)
--   • Backward-compatible GetAchievementsForPlayer for existing UI
--
-- Public API:
--   AchievementService:LoadForPlayer(player)
--   AchievementService:SaveForPlayer(player)
--   AchievementService:SaveAll()
--   AchievementService:ClearPlayer(player)
--   AchievementService:IncrementStat(player, statKey, amount)
--   AchievementService:SetStat(player, statKey, value)
--   AchievementService:GetAchievementsForPlayer(player)
--   AchievementService:ClaimReward(player, achievementId) -> bool
--   AchievementService:GetCompletedHistory(player) -> array
--   AchievementService:GetRecentlyCompleted(player, limit) -> array
--   AchievementService:GetCategoryProgressSummary(player) -> table
--------------------------------------------------------------------------------

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AchievementDefs = require(ReplicatedStorage:WaitForChild("AchievementDefs", 10))

local DATASTORE_NAME = "Achievements_v1"
-- Schema v3: staged achievement model with completion history.
-- Bumping from v2 forces a clean reset of all achievement progress.
local ACHIEVEMENT_DATA_VERSION = 3
local RETRIES        = 3
local RETRY_DELAY    = 0.5

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local AchievementService = {}

--------------------------------------------------------------------------------
-- Per-player state:
--   playerData[player] = {
--       achievementDataVersion = 3,
--       stats = { zombieElims = 0, playerElims = 0, ... },
--       achievementPoints = 0,  -- lifetime cumulative AP
--       achievements = {
--           [achievementId] = {
--               stageIndex  = 1,       -- current active stage (1-based)
--               completed   = false,   -- current stage completed?
--               claimed     = false,   -- current stage reward auto-granted?
--               achievedOn  = nil,     -- timestamp of current stage completion
--               maxedOut    = false,   -- entire staged line finished?
--           },
--       },
--       completedHistory = {
--           { id, displayName, category, stageIndex, achievedOn, desc, reward, ap },
--           ...  (newest first)
--       },
--   }
--------------------------------------------------------------------------------
local playerData = {}

--------------------------------------------------------------------------------
-- CurrencyService  (lazy-loaded so require order doesn't matter)
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- All tracked stat keys
-- Stats not yet wired in the game are stubbed here so save data initializes
-- cleanly. Add TODO comments for unwired stats.
--------------------------------------------------------------------------------
local STAT_KEYS = {
    "totalElims",
    "zombieElims",
    "playerElims",
    "flagCarrierElims",     -- TODO: wire when flag-carrier-kill detection exists
    "totalDamage",          -- TODO: wire DamageDealt stat events
    "bestElimStreak",       -- special: set (not increment) by streak tracker
    "doubleElims",          -- TODO: wire multi-elim detection
    "tripleElims",          -- TODO: wire multi-elim detection
    "totalCoinsEarned",
    "totalCoinsSpent",      -- wired: SetCoins wrapper in AchievementServiceInit
    "totalPurchases",       -- TODO: wire shop purchase counter
    "itemsOwned",           -- wired: recalcItemsOwned in AchievementServiceInit
    "flagCaptures",
    "flagReturns",
    "flagCarryTime",        -- wired: polled from CarryingFlag attribute in AchievementServiceInit
    "matchesPlayed",
    "matchWins",
    "matchMinutes",         -- wired: MatchStarted/MatchEnded in AchievementServiceInit
    "consecutiveLogins",    -- wired: synced from DailyRewardService in DailyRewardServiceInit
    "flawlessWins",         -- wired: checked at MatchWon when Deaths == 0 in AchievementServiceInit
    "dailyQuestsCompleted",
    "weeklyQuestsCompleted",
    "eventQuestsCompleted",
    "meleeUpgradeLevel",      -- set by UpgradeServiceInit when melee level changes
    "rangedUpgradeLevel",     -- set by UpgradeServiceInit when ranged level changes
    "totalRobuxSpent",        -- incremented by CoinShopReceipt on Robux purchases
    "salvageEarnedFromRecycling", -- incremented by SalvageService on salvage action
    "achievementsCompleted", -- internal: auto-updated by this service
    "categoriesWithCompletion", -- internal: auto-updated by this service
}

local STAT_KEY_SET = {}
for _, k in ipairs(STAT_KEYS) do STAT_KEY_SET[k] = true end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function sanitizeAchievedOn(value)
    local num = tonumber(value)
    if not num or num <= 0 then return nil end
    return math.floor(num)
end

--- Build clean default player data from current definitions.
local function defaultData()
    local data = {
        achievementDataVersion = ACHIEVEMENT_DATA_VERSION,
        stats = {},
        achievementPoints = 0,
        achievements = {},
        completedHistory = {},
    }
    for _, key in ipairs(STAT_KEYS) do
        data.stats[key] = 0
    end
    for _, def in ipairs(AchievementDefs.Achievements) do
        data.achievements[def.id] = {
            stageIndex = 1,
            completed  = false,
            claimed    = false,
            achievedOn = nil,
            maxedOut   = false,
        }
    end
    return data
end

--- Merge saved data with current definitions.
--- If schema version is too old, performs a clean reset.
local function mergeWithDefaults(saved)
    if type(saved) ~= "table" then
        return defaultData(), false
    end

    local savedVersion = tonumber(saved.achievementDataVersion or saved.dataVersion or 1) or 1
    if savedVersion < ACHIEVEMENT_DATA_VERSION then
        -- Full reset — early testing, old data is incompatible with staged model.
        return defaultData(), true
    end

    local data = {
        achievementDataVersion = ACHIEVEMENT_DATA_VERSION,
        stats = {},
        achievementPoints = tonumber(saved.achievementPoints) or 0,
        achievements = {},
        completedHistory = {},
    }

    -- Stats
    local ss = (type(saved.stats) == "table") and saved.stats or {}
    for _, key in ipairs(STAT_KEYS) do
        data.stats[key] = (type(ss[key]) == "number") and ss[key] or 0
    end

    -- Achievements (merge with defs so new achievements get defaults)
    local sa = (type(saved.achievements) == "table") and saved.achievements or {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        -- Check current id first, then fall back to any old alias that maps to it
        local prev = sa[def.id]
        if not prev then
            for oldId, newId in pairs(AchievementDefs.IdAliases) do
                if newId == def.id and sa[oldId] then
                    prev = sa[oldId]
                    break
                end
            end
        end
        if type(prev) == "table" then
            local maxStage = AchievementDefs.GetMaxStage(def)
            local si = math.clamp(tonumber(prev.stageIndex) or 1, 1, maxStage + 1)
            local maxedOut = si > maxStage
            data.achievements[def.id] = {
                stageIndex = si,
                completed  = (prev.completed == true),
                claimed    = (prev.claimed == true),
                achievedOn = sanitizeAchievedOn(prev.achievedOn),
                maxedOut   = maxedOut,
            }
        else
            data.achievements[def.id] = {
                stageIndex = 1,
                completed  = false,
                claimed    = false,
                achievedOn = nil,
                maxedOut   = false,
            }
        end
    end

    -- Completed history
    if type(saved.completedHistory) == "table" then
        for _, entry in ipairs(saved.completedHistory) do
            if type(entry) == "table" and type(entry.id) == "string" then
                table.insert(data.completedHistory, {
                    id          = entry.id,
                    displayName = entry.displayName or "",
                    category    = entry.category or "",
                    stageIndex  = tonumber(entry.stageIndex) or nil,
                    achievedOn  = sanitizeAchievedOn(entry.achievedOn),
                    desc        = entry.desc or "",
                    reward      = tonumber(entry.reward) or 0,
                    ap          = tonumber(entry.ap) or 0,
                })
            end
        end
    end

    return data, false
end

local function getKey(player)
    return "User_" .. tostring(player.UserId)
end

--------------------------------------------------------------------------------
-- Forward declarations for functions referenced before definition
--------------------------------------------------------------------------------
local pushProgress     -- defined below after Remote helpers
local pushAllAchievements

--------------------------------------------------------------------------------
-- Internal: archive a completed stage into history (newest first)
--------------------------------------------------------------------------------
local function archiveCompletion(data, def, stageIndex, achievedOn)
    local entry = {
        id          = def.id,
        displayName = AchievementDefs.GetStageTitle(def, stageIndex),
        category    = def.category,
        stageIndex  = def.staged and stageIndex or nil,
        achievedOn  = achievedOn,
        desc        = AchievementDefs.GetStageDesc(def, stageIndex),
        reward      = AchievementDefs.GetStageReward(def, stageIndex),
        ap          = AchievementDefs.GetStageAP(def, stageIndex),
    }
    table.insert(data.completedHistory, 1, entry) -- newest first
end

--------------------------------------------------------------------------------
-- Internal: recalculate the meta-stats (achievementsCompleted, categoriesWithCompletion)
-- Called after any completion change.
--------------------------------------------------------------------------------
local function recalcMetaStats(data)
    local totalCompleted = 0
    local categoriesHit = {}
    for _, entry in ipairs(data.completedHistory) do
        totalCompleted = totalCompleted + 1
        if entry.category and entry.category ~= "" then
            categoriesHit[entry.category] = true
        end
    end
    data.stats["achievementsCompleted"] = totalCompleted

    local catCount = 0
    for _ in pairs(categoriesHit) do catCount = catCount + 1 end
    data.stats["categoriesWithCompletion"] = catCount
end

--------------------------------------------------------------------------------
-- Internal: grant reward for a completed achievement stage (manual claim).
-- Server-authoritative: coins + achievement points granted on claim.
-- Returns true if reward was granted, false if already claimed/skipped.
--------------------------------------------------------------------------------
local function grantReward(player, data, def, stageIndex)
    local ach = data.achievements[def.id]
    if not ach then return false end
    if ach.claimed then return false end  -- already rewarded
    if not ach.completed then return false end -- must be completed first

    -- Grant coins
    local coinReward = AchievementDefs.GetStageReward(def, stageIndex)
    if coinReward > 0 then
        local cs = getCurrencyService()
        if cs and cs.AddCoins then
            cs:AddCoins(player, coinReward, "achievement")
        end
    end

    -- Grant achievement points
    local apReward = AchievementDefs.GetStageAP(def, stageIndex)
    if apReward > 0 then
        data.achievementPoints = (data.achievementPoints or 0) + apReward
        print(string.format("[AchievementPoints] %s earned +%d AP (total: %d) from %s",
            player.Name, apReward, data.achievementPoints, def.id))
    end

    ach.claimed = true

    -- Archive into completion history now that reward is claimed
    archiveCompletion(data, def, stageIndex, ach.achievedOn)
    recalcMetaStats(data)

    print(string.format("[AchievementClaim] %s claimed: %s (coins=%d, AP=%d)",
        player.Name, AchievementDefs.GetStageTitle(def, stageIndex), coinReward, apReward))

    return true
end

--------------------------------------------------------------------------------
-- Internal: advance a staged line after manual claim.
-- Called for staged achievements when the current stage is claimed.
-- Does NOT auto-complete or auto-claim the next stage — only makes it active.
-- If the stat already exceeds the next threshold, marks it completed (claimable)
-- but does NOT grant the reward.
--------------------------------------------------------------------------------
local function tryAdvanceStage(player, data, def)
    if not def.staged then return end
    local ach = data.achievements[def.id]
    if not ach then return end
    if not ach.claimed then return end -- must be claimed before advancing

    local maxStage = AchievementDefs.GetMaxStage(def)

    -- Move to next stage
    ach.stageIndex = ach.stageIndex + 1
    ach.completed = false
    ach.claimed = false
    ach.achievedOn = nil

    if ach.stageIndex > maxStage then
        -- Entire line is maxed out
        ach.maxedOut = true
        return
    end

    -- Check if stat already meets the next stage threshold (carry-over)
    -- Mark as completed (claimable) but do NOT grant reward or archive
    local statVal = data.stats[def.stat] or 0
    local nextTarget = AchievementDefs.GetStageTarget(def, ach.stageIndex)
    if statVal >= nextTarget then
        ach.completed = true
        ach.achievedOn = os.time()
        pushProgress(player, def, data)
    end
end

--------------------------------------------------------------------------------
-- Remote helpers (created by AchievementServiceInit, resolved lazily)
--------------------------------------------------------------------------------
local remotesFolder

local function getRemote(name)
    if not remotesFolder then
        remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
    end
    return remotesFolder and remotesFolder:FindFirstChild(name)
end

--- Push a progress update for a single achievement to the client.
--- Sends a flat snapshot the existing UI can consume.
pushProgress = function(player, def, data)
    local ev = getRemote("AchievementProgress")
    if not ev or not ev:IsA("RemoteEvent") then return end

    local ach = data.achievements[def.id]
    if not ach then return end

    local si = ach.stageIndex
    local maxStage = AchievementDefs.GetMaxStage(def)
    if ach.maxedOut then si = maxStage end

    local target   = AchievementDefs.GetStageTarget(def, si)
    local statVal  = data.stats[def.stat] or 0
    local progress = math.min(statVal, target)

    pcall(function()
        ev:FireClient(player, def.id, progress, ach.completed, ach.achievedOn, ach.claimed == true, si)
    end)
end

pushAllAchievements = function(player)
    local ev = getRemote("AchievementProgress")
    if ev and ev:IsA("RemoteEvent") then
        pcall(function()
            ev:FireClient(player, "__full_refresh", 0, false, nil, false)
        end)
    end
end

--------------------------------------------------------------------------------
-- DataStore I/O
--------------------------------------------------------------------------------

function AchievementService:LoadForPlayer(player)
    if not player then return end
    local key = getKey(player)
    local success, result
    for i = 1, RETRIES do
        success, result = pcall(function()
            return ds:GetAsync(key)
        end)
        if success then break end
        warn("[AchievementService] GetAsync attempt", i, "failed:", tostring(result))
        task.wait(RETRY_DELAY * i)
    end

    local data, wasResetByVersion = mergeWithDefaults(success and result or nil)

    -- [AchievementLoad] Log loaded data summary
    print(string.format("[AchievementLoad] %s loaded — AP=%d, completedHistory=%d entries, version=%s",
        player.Name,
        data.achievementPoints or 0,
        #(data.completedHistory or {}),
        tostring(data.achievementDataVersion)))

    -- Retroactively evaluate stat thresholds for all achievements
    -- Mark completed if threshold met, but do NOT auto-grant or auto-advance.
    -- Completed-but-unclaimed achievements remain claimable.
    for _, def in ipairs(AchievementDefs.Achievements) do
        local ach = data.achievements[def.id]
        if not ach then continue end
        if ach.maxedOut then continue end

        local statVal = data.stats[def.stat] or 0
        local si = ach.stageIndex
        local target = AchievementDefs.GetStageTarget(def, si)

        if statVal >= target and not ach.completed then
            ach.completed = true
            if not ach.achievedOn then
                ach.achievedOn = os.time()
            end
            -- Do NOT auto-grant or auto-advance — player must manually claim
        elseif statVal < target and not ach.claimed then
            -- Only reset if not already claimed (claimed achievements stay claimed)
            ach.completed = false
            ach.claimed = false
            ach.achievedOn = nil
        end
    end

    recalcMetaStats(data)
    playerData[player] = data

    if wasResetByVersion then
        task.spawn(function()
            AchievementService:SaveForPlayer(player)
        end)
    end
end

function AchievementService:SaveForPlayer(player)
    if not player then return false end
    local data = playerData[player]
    if not data then return false end
    print(string.format("[AchievementSave] SaveForPlayer(%s): AP=%d, history=%d entries",
        player.Name, data.achievementPoints or 0, #(data.completedHistory or {})))
    local key = getKey(player)
    local success, err
    for i = 1, RETRIES do
        success, err = pcall(function()
            ds:SetAsync(key, data)
        end)
        if success then break end
        warn("[AchievementService] SetAsync attempt", i, "failed:", tostring(err))
        task.wait(RETRY_DELAY * i)
    end
    if not success then
        warn("[AchievementService] failed to save for", tostring(player.Name))
    end
    return success == true
end

function AchievementService:SaveAll()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(function() AchievementService:SaveForPlayer(player) end)
    end
end

function AchievementService:ClearPlayer(player)
    playerData[player] = nil
end

--------------------------------------------------------------------------------
-- Core tracking
--------------------------------------------------------------------------------

--- Increment a lifetime stat and evaluate all related achievements.
function AchievementService:IncrementStat(player, statKey, amount)
    amount = tonumber(amount) or 1
    if amount <= 0 then return end
    if not STAT_KEY_SET[statKey] then return end

    local data = playerData[player]
    if not data then return end

    data.stats[statKey] = (data.stats[statKey] or 0) + amount
    self:_evaluateStatAchievements(player, data, statKey)
end

--- Set a stat to an absolute value (used for "best" stats like bestElimStreak).
function AchievementService:SetStat(player, statKey, value)
    value = tonumber(value) or 0
    if not STAT_KEY_SET[statKey] then return end

    local data = playerData[player]
    if not data then return end

    -- Only update if new value is higher (for "best" type stats)
    if value > (data.stats[statKey] or 0) then
        data.stats[statKey] = value
        self:_evaluateStatAchievements(player, data, statKey)
    end
end

--- Internal: check all achievements using the given stat key.
function AchievementService:_evaluateStatAchievements(player, data, statKey)
    local currentValue = data.stats[statKey]
    local anyCompleted = false

    for _, def in ipairs(AchievementDefs.Achievements) do
        if def.stat ~= statKey then continue end

        local ach = data.achievements[def.id]
        if not ach then continue end
        if ach.maxedOut then continue end

        local si = ach.stageIndex
        local target = AchievementDefs.GetStageTarget(def, si)

        if not ach.completed and currentValue >= target then
            ach.completed = true
            if not ach.achievedOn then
                ach.achievedOn = os.time()
            end
            anyCompleted = true

            -- Do NOT auto-grant reward or archive — player must manually claim
            -- Do NOT auto-advance staged achievements — wait for claim

            pushProgress(player, def, data)
        elseif not ach.completed then
            pushProgress(player, def, data)
        end
    end

    if anyCompleted then
        recalcMetaStats(data)
        -- Re-evaluate meta achievements (overachiever, jack of all trades)
        -- after updating the meta stat counters
        for _, def in ipairs(AchievementDefs.Achievements) do
            if def.stat == "achievementsCompleted" or def.stat == "categoriesWithCompletion" then
                local ach = data.achievements[def.id]
                if ach and not ach.completed and not ach.maxedOut then
                    local target = AchievementDefs.GetStageTarget(def, ach.stageIndex)
                    local val = data.stats[def.stat] or 0
                    if val >= target then
                        ach.completed = true
                        if not ach.achievedOn then
                            ach.achievedOn = os.time()
                        end
                        -- Do NOT auto-grant or archive — player must manually claim
                        pushProgress(player, def, data)
                    end
                end
            end
        end

        -- Push full refresh to update UI after completions
        pushAllAchievements(player)
    end
end

--------------------------------------------------------------------------------
-- Client-facing API
--------------------------------------------------------------------------------

--- Returns an array of achievement snapshots for the client.
--- Each entry represents the CURRENT ACTIVE STAGE only.
--- Backward-compatible: includes id, title, desc, icon, target, reward,
--- progress, completed, claimed, achievedOn, hidden, category, stageIndex.
function AchievementService:GetAchievementsForPlayer(player)
    local data = playerData[player]
    if not data then return {} end

    local out = {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        local ach = data.achievements[def.id]
        if not ach then continue end

        -- Fully maxed staged lines: show last stage as completed
        local si = ach.stageIndex
        local maxStage = AchievementDefs.GetMaxStage(def)
        if ach.maxedOut then si = maxStage end

        local target   = AchievementDefs.GetStageTarget(def, si)
        local statVal  = data.stats[def.stat] or 0
        local progress = math.min(statVal, target)

        table.insert(out, {
            id         = def.id,
            title      = AchievementDefs.GetStageTitle(def, si),
            desc       = AchievementDefs.GetStageDesc(def, si),
            icon       = def.icon,
            target     = target,
            reward     = AchievementDefs.GetStageReward(def, si),
            ap         = AchievementDefs.GetStageAP(def, si),
            progress   = progress,
            completed  = ach.completed or ach.maxedOut,
            claimed    = ach.claimed or ach.maxedOut,
            achievedOn = ach.achievedOn,
            hidden     = def.hidden,
            category   = def.category,
            stageIndex = si,
            staged     = def.staged,
            maxedOut   = ach.maxedOut,
        })
    end
    -- Attach player's total achievement points to the response
    out.achievementPoints = data.achievementPoints or 0
    return out
end

--- ClaimReward: manually claim a completed achievement's reward.
--- Grants coins + AP, archives to history, advances staged lines.
--- Returns true, reward, ap on success; false on failure.
function AchievementService:ClaimReward(player, achievementId)
    if type(achievementId) ~= "string" then return false end
    local data = playerData[player]
    if not data then return false end

    -- Find the definition
    local def
    for _, d in ipairs(AchievementDefs.Achievements) do
        if d.id == achievementId then def = d; break end
    end
    if not def then return false end

    local ach = data.achievements[achievementId]
    if not ach then return false end
    if not ach.completed then return false end
    if ach.claimed then return false end

    local si = ach.stageIndex

    -- Grant reward (marks claimed, archives, recalcs meta)
    local granted = grantReward(player, data, def, si)
    if not granted then return false end

    local coinReward = AchievementDefs.GetStageReward(def, si)
    local apReward = AchievementDefs.GetStageAP(def, si)

    -- For staged achievements, advance to the next stage
    if def.staged then
        tryAdvanceStage(player, data, def)
    end

    -- Re-evaluate meta achievements after claim changes history
    for _, metaDef in ipairs(AchievementDefs.Achievements) do
        if metaDef.stat == "achievementsCompleted" or metaDef.stat == "categoriesWithCompletion" then
            local metaAch = data.achievements[metaDef.id]
            if metaAch and not metaAch.completed and not metaAch.maxedOut then
                local target = AchievementDefs.GetStageTarget(metaDef, metaAch.stageIndex)
                local val = data.stats[metaDef.stat] or 0
                if val >= target then
                    metaAch.completed = true
                    if not metaAch.achievedOn then
                        metaAch.achievedOn = os.time()
                    end
                    pushProgress(player, metaDef, data)
                end
            end
        end
    end

    -- Push full refresh to update UI
    pushAllAchievements(player)

    return true, coinReward, apReward
end

--------------------------------------------------------------------------------
-- History / recently completed
--------------------------------------------------------------------------------

--- Get the player's lifetime achievement points total.
function AchievementService:GetAchievementPoints(player)
    local data = playerData[player]
    if not data then
        print(string.format("[AchievementPoints] GetAchievementPoints(%s): no data, returning 0", tostring(player)))
        return 0
    end
    local ap = data.achievementPoints or 0
    print(string.format("[AchievementPoints] GetAchievementPoints(%s): returning %d", player.Name, ap))
    return ap
end

--- Get full completed history (newest first).
function AchievementService:GetCompletedHistory(player)
    local data = playerData[player]
    if not data then return {} end
    return data.completedHistory
end

--- Get the N most recently completed achievements.
function AchievementService:GetRecentlyCompleted(player, limit)
    limit = tonumber(limit) or 5
    local data = playerData[player]
    if not data then return {} end

    local result = {}
    for i = 1, math.min(limit, #data.completedHistory) do
        table.insert(result, data.completedHistory[i])
    end
    return result
end

--------------------------------------------------------------------------------
-- Category progress summary
--------------------------------------------------------------------------------

--- Returns { [category] = { total, completed, percentage } }
function AchievementService:GetCategoryProgressSummary(player)
    local data = playerData[player]
    if not data then return {} end

    -- Count completed entries per category from history
    local catCompleted = {}
    for _, entry in ipairs(data.completedHistory) do
        local cat = entry.category
        if cat then
            catCompleted[cat] = (catCompleted[cat] or 0) + 1
        end
    end

    -- Count total possible completions per category
    local catTotal = {}
    for _, def in ipairs(AchievementDefs.Achievements) do
        local cat = def.category
        local stages = AchievementDefs.GetMaxStage(def)
        catTotal[cat] = (catTotal[cat] or 0) + stages
    end

    local summary = {}
    for _, cat in ipairs(AchievementDefs.Categories) do
        local total = catTotal[cat] or 0
        local done = catCompleted[cat] or 0
        summary[cat] = {
            total      = total,
            completed  = done,
            percentage = total > 0 and math.floor(done / total * 100) or 0,
        }
    end
    return summary
end

return AchievementService
