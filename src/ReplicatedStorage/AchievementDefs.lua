--------------------------------------------------------------------------------
-- AchievementDefs.lua  –  Shared achievement definitions (ReplicatedStorage)
-- Used by both server (AchievementService) and client (Achievements UI).
--
-- HOW TO ADD A NEW ACHIEVEMENT:
--   1. Add an entry to the Achievements table below.
--   2. Make sure the `stat` key matches one the server tracks:
--      "totalElims", "zombieElims", "playerElims",
--      "totalCoinsEarned", "flagActions", "matchesPlayed"
--   3. That's it – the system picks it up automatically.
--------------------------------------------------------------------------------

local AchievementDefs = {}

AchievementDefs.Achievements = {
    {
        id          = "first_blood",
        title       = "First Blood",
        desc        = "Get your first elimination.",
        stat        = "totalElims",
        target      = 1,
        reward      = 10,
        icon        = "⚔",        -- glyph fallback
        hidden      = false,
    },
    {
        id          = "zombie_hunter",
        title       = "Monster Hunter",
        desc        = "Eliminate 25 monsters.",
        stat        = "zombieElims",
        target      = 25,
        reward      = 20,
        icon        = "💀",
        hidden      = false,
    },
    {
        id          = "player_slayer",
        title       = "Player Slayer",
        desc        = "Eliminate 10 enemy players.",
        stat        = "playerElims",
        target      = 10,
        reward      = 25,
        icon        = "🗡",
        hidden      = false,
    },
    {
        id          = "flag_capturer",
        title       = "Capture Artist",
        desc        = "Capture the flag 3 times.",
        stat        = "flagCaptures",
        target      = 3,
        reward      = 30,
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "flag_returner",
        title       = "Banner Guardian",
        desc        = "Return the flag 3 times.",
        stat        = "flagReturns",
        target      = 3,
        reward      = 20,
        icon        = "🚩",
        hidden      = false,
    },
    {
        id          = "coin_collector",
        title       = "Coin Collector",
        desc        = "Earn 100 total coins over time.",
        stat        = "totalCoinsEarned",
        target      = 100,
        reward      = 25,
        icon        = "💰",
        hidden      = false,
    },
    {
        id          = "dedicated_fighter",
        title       = "Dedicated Fighter",
        desc        = "Play 5 matches.",
        stat        = "matchesPlayed",
        target      = 5,
        reward      = 20,
        icon        = "🏟",
        hidden      = false,
    },
}

-- Quick lookup by id
AchievementDefs.ById = {}
for _, def in ipairs(AchievementDefs.Achievements) do
    AchievementDefs.ById[def.id] = def
end

-- Debug: verify flag achievement names
if game:GetService("RunService"):IsServer() then
    local capturer = AchievementDefs.ById["flag_capturer"]
    local returner = AchievementDefs.ById["flag_returner"]
    if capturer then
        print("[AchievementDefs] flag_capturer loaded: '" .. capturer.title .. "' (trackstat: " .. capturer.stat .. ")")
    end
    if returner then
        print("[AchievementDefs] flag_returner loaded: '" .. returner.title .. "' (tracks stat: " .. returner.stat .. ")")
    end
end

return AchievementDefs
