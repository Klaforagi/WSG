--------------------------------------------------------------------------------
-- EmoteConfig.lua  –  Shared configuration for the Emote system
-- Readable by both server and client (lives in ReplicatedStorage/SideUI).
--
-- Future usage:
--   local EmoteConfig = require(path.to.EmoteConfig)
--   local slotCount   = EmoteConfig.SLOT_COUNT
--   local allEmotes   = EmoteConfig.GetAll()
--   local emote       = EmoteConfig.GetById("wave")
--------------------------------------------------------------------------------

local EmoteConfig = {}

-- ── Slot configuration ────────────────────────────────────────────────────
-- How many equip slots the player has in the Emote wheel/panel.
EmoteConfig.SLOT_COUNT = 6

-- ── Emote definitions ─────────────────────────────────────────────────────
-- Each entry represents an emote that *could* exist in the game.
-- Add real entries here once emotes are created.
--
-- Fields:
--   Id          (string)  unique emote identifier
--   DisplayName (string)  shown in the emote slot label
--   Description (string)  shown in Shop / tooltip
--   IconKey     (string)  key for AssetCodes.Get() lookup (optional)
--   IconAssetId (string)  fallback direct asset id (optional)
--   AnimationId (string)  Roblox animation asset id (placeholder for now)
--   CoinCost    (number)  purchase price in the Shop
--   Cooldown    (number)  seconds before this emote can be played again
--   IsFree      (boolean) granted to all players automatically if true
--
-- Example (uncomment and fill when real emotes are ready):
-- EmoteConfig.Emotes = {
--     {
--         Id          = "wave",
--         DisplayName = "Wave",
--         Description = "A friendly wave.",
--         IconKey     = "EmoteWave",
--         AnimationId = "rbxassetid://0",
--         CoinCost    = 0,
--         Cooldown    = 3,
--         IsFree      = true,
--     },
--     {
--         Id          = "dance",
--         DisplayName = "Dance",
--         Description = "Break it down!",
--         IconKey     = "EmoteDance",
--         AnimationId = "rbxassetid://0",
--         CoinCost    = 150,
--         Cooldown    = 5,
--         IsFree      = false,
--     },
-- }
EmoteConfig.Emotes = {}  -- empty until emotes are added

-- ── Cooldown defaults ─────────────────────────────────────────────────────
EmoteConfig.DEFAULT_COOLDOWN = 3  -- seconds

-- ── Lookup helpers ────────────────────────────────────────────────────────

--- Return all emote definitions.
function EmoteConfig.GetAll()
    return EmoteConfig.Emotes
end

--- Return the emote definition for the given id, or nil.
function EmoteConfig.GetById(id)
    for _, def in ipairs(EmoteConfig.Emotes) do
        if def.Id == id then
            return def
        end
    end
    return nil
end

--- Return the display name for an emote id (or a fallback string).
function EmoteConfig.GetDisplayName(id)
    local def = EmoteConfig.GetById(id)
    return (def and def.DisplayName) or tostring(id)
end

return EmoteConfig
