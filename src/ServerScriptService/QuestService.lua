--------------------------------------------------------------------------------
-- QuestService.lua  –  Server-side Daily Quest tracking
-- ModuleScript in ServerScriptService.
--
-- Tracks per-player quest progress in memory.  Progress resets each
-- calendar day (UTC).  Rewards are granted through CurrencyService.
--
-- Public API used by QuestServiceInit.server.lua:
--   QuestService:GetQuestsForPlayer(player)  -> { {id, title, desc, goal, progress, reward, claimed} , ... }
--   QuestService:IncrementQuest(player, questId, amount)
--   QuestService:ClaimReward(player, questId) -> bool success
--------------------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local QuestService = {}

--------------------------------------------------------------------------------
-- Quest definitions  (easy to extend – just add another entry)
--------------------------------------------------------------------------------
local QUEST_DEFS = {
    {
        id       = "zombie_hunter",
        title    = "Zombie Hunter",
        desc     = "Defeat 5 Zombies",
        goal     = 5,
        reward   = 10,   -- coins
    },
    {
        id       = "battle_ready",
        title    = "Battle Ready",
        desc     = "Eliminate 5 Players",
        goal     = 5,
        reward   = 15,
    },
    {
        id       = "team_defender",
        title    = "Team Defender",
        desc     = "Return the Flag 1 Time",
        goal     = 1,
        reward   = 20,
    },
}

--------------------------------------------------------------------------------
-- Per-player state:  playerData[player] = { day = "2025-01-15", quests = { [questId] = {progress, claimed} } }
--------------------------------------------------------------------------------
local playerData = {}

local function todayKey()
    return os.date("!%Y-%m-%d")   -- UTC date string
end

local function ensurePlayerData(player)
    local today = todayKey()
    local pd = playerData[player]
    if pd and pd.day == today then return pd end

    -- first access today (or new day) → reset progress
    pd = { day = today, quests = {} }
    for _, def in ipairs(QUEST_DEFS) do
        pd.quests[def.id] = { progress = 0, claimed = false }
    end
    playerData[player] = pd
    return pd
end

--------------------------------------------------------------------------------
-- CurrencyService  (loaded lazily so require order doesn't matter)
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
-- Public API
--------------------------------------------------------------------------------

--- Returns an array of quest snapshots suitable for sending to the client.
function QuestService:GetQuestsForPlayer(player)
    local pd = ensurePlayerData(player)
    local out = {}
    for _, def in ipairs(QUEST_DEFS) do
        local state = pd.quests[def.id]
        table.insert(out, {
            id       = def.id,
            title    = def.title,
            desc     = def.desc,
            goal     = def.goal,
            progress = math.min(state.progress, def.goal),
            reward   = def.reward,
            claimed  = state.claimed,
        })
    end
    return out
end

--- Increment a quest's progress by `amount` (default 1).
--- Fires the QuestProgress RemoteEvent if it exists so the client can live-update.
function QuestService:IncrementQuest(player, questId, amount)
    amount = tonumber(amount) or 1
    local pd = ensurePlayerData(player)
    local state = pd.quests[questId]
    if not state then return end
    if state.claimed then return end -- already done

    -- find goal
    local goal = 0
    for _, def in ipairs(QUEST_DEFS) do
        if def.id == questId then goal = def.goal break end
    end

    state.progress = math.min(state.progress + amount, goal)

    -- fire live update remote (created by init script)
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    if remote then
        local ev = remote:FindFirstChild("QuestProgress")
        if ev and ev:IsA("RemoteEvent") then
            pcall(function()
                ev:FireClient(player, questId, state.progress)
            end)
        end
    end
end

--- Attempt to claim the reward for a completed quest.  Returns true on success.
function QuestService:ClaimReward(player, questId)
    local pd = ensurePlayerData(player)
    local state = pd.quests[questId]
    if not state then return false end
    if state.claimed then return false end

    -- find definition
    local def
    for _, d in ipairs(QUEST_DEFS) do
        if d.id == questId then def = d break end
    end
    if not def then return false end

    if state.progress < def.goal then return false end

    -- grant reward
    local cs = getCurrencyService()
    if cs and cs.AddCoins then
        cs:AddCoins(player, def.reward)
    end

    state.claimed = true
    return true
end

--------------------------------------------------------------------------------
-- Reroll: replace the quest at `questIndex` with a different template.
-- Returns true/false + message.
--------------------------------------------------------------------------------
function QuestService:RerollQuest(player, questIndex)
    local pd = ensurePlayerData(player)

    -- Determine current quest order for this player
    local currentOrder = {}
    if pd.questOrder then
        for i, qid in ipairs(pd.questOrder) do
            currentOrder[i] = qid
        end
    else
        for i, def in ipairs(QUEST_DEFS) do
            currentOrder[i] = def.id
        end
    end

    if questIndex < 1 or questIndex > #currentOrder then
        return false, "Invalid quest index"
    end

    local oldId = currentOrder[questIndex]
    local state = pd.quests[oldId]
    if state and state.claimed then
        return false, "Quest already claimed"
    end

    -- Build set of currently assigned quest ids (so we don't duplicate)
    local assignedSet = {}
    for _, qid in ipairs(currentOrder) do
        assignedSet[qid] = true
    end

    -- Build alternatives: any QUEST_DEF not currently assigned AND not the old quest
    local alternatives = {}
    for _, def in ipairs(QUEST_DEFS) do
        if def.id ~= oldId and not assignedSet[def.id] then
            table.insert(alternatives, def)
        end
    end

    -- If no truly unique alternatives, fall back to any different quest
    if #alternatives == 0 then
        for _, def in ipairs(QUEST_DEFS) do
            if def.id ~= oldId then
                table.insert(alternatives, def)
            end
        end
    end

    if #alternatives == 0 then
        return false, "No alternative quests available"
    end

    local newDef = alternatives[math.random(#alternatives)]

    -- Swap the quest in player state
    pd.quests[oldId] = nil
    pd.quests[newDef.id] = { progress = 0, claimed = false }

    -- Update per-player quest order
    if not pd.questOrder then
        pd.questOrder = {}
        for i, def in ipairs(QUEST_DEFS) do
            pd.questOrder[i] = def.id
        end
    end
    pd.questOrder[questIndex] = newDef.id

    -- Fire live update to client so UI refreshes
    local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    if remote then
        local ev = remote:FindFirstChild("QuestProgress")
        if ev and ev:IsA("RemoteEvent") then
            pcall(function()
                ev:FireClient(player, "__reroll", 0)
            end)
        end
    end

    return true, "Rerolled"
end

--------------------------------------------------------------------------------
-- Override GetQuestsForPlayer to respect per-player quest order (after rerolls)
--------------------------------------------------------------------------------
local _baseGetQuests = QuestService.GetQuestsForPlayer

function QuestService:GetQuestsForPlayer(player)
    local pd = ensurePlayerData(player)
    if not pd.questOrder then
        -- No rerolls happened, use default order
        return _baseGetQuests(self, player)
    end

    -- Build quests from per-player order
    local out = {}
    local defMap = {}
    for _, def in ipairs(QUEST_DEFS) do
        defMap[def.id] = def
    end
    for _, qid in ipairs(pd.questOrder) do
        local def = defMap[qid]
        if def then
            local state = pd.quests[qid]
            if state then
                table.insert(out, {
                    id       = def.id,
                    title    = def.title,
                    desc     = def.desc,
                    goal     = def.goal,
                    progress = math.min(state.progress, def.goal),
                    reward   = def.reward,
                    claimed  = state.claimed,
                })
            end
        end
    end
    return out
end

--- Cleanup when a player leaves.
function QuestService:ClearPlayer(player)
    playerData[player] = nil
end

return QuestService
