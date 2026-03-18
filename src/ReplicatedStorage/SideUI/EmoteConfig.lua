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
EmoteConfig.SLOT_COUNT = 8

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
-- To add a new emote: copy one of the entries below, give it a unique Id,
-- set the DisplayName / Description / CoinCost / AnimationId, and register
-- an icon in AssetCodes.lua under the IconKey name.
EmoteConfig.Emotes = {
    {
        Id          = "wave",
        DisplayName = "Wave",
        Description = "Give a friendly wave.",
        IconKey     = "EmoteWave",      -- looked up via AssetCodes.Get("EmoteWave")
        -- REPLACE the animation id below with a real uploaded Wave animation asset.
        -- This placeholder (507770239) is a generic Roblox wave animation.
        AnimationId = "rbxassetid://507770239",
        CoinCost    = 20,
        Cooldown    = 3,
        IsFree      = false,
    },
    -- Future emotes go here:
    -- {
    --     Id          = "dance",
    --     DisplayName = "Dance",
    --     Description = "Break it down!",
    --     IconKey     = "EmoteDance",
    --     AnimationId = "rbxassetid://0",
    --     CoinCost    = 150,
    --     Cooldown    = 5,
    --     IsFree      = false,
    -- },
}

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
