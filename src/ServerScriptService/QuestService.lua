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

--- Cleanup when a player leaves.
function QuestService:ClearPlayer(player)
    playerData[player] = nil
end

return QuestService
