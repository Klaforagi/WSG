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
--   Looped      (boolean) nil/true repeats until the server cancels it; false plays once
--   UseRunning  (boolean) false/nil cancels on movement; true allows movement without canceling
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
        CoinCost    = 0,
        Cooldown    = 1,
        Looped      = false,
        IsFree      = true,
    },
    {
        Id          = "dance",
        DisplayName = "Dance",
        Description = "Break into a dance.",
        AnimationId = "rbxassetid://122221160021248",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "i_want_money",
        DisplayName = "I Want Money",
        Description = "Make it rain.",
        AnimationId = "rbxassetid://100054170665680",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "take_the_l",
        DisplayName = "Take The L",
        Description = "Rub in the win.",
        AnimationId = "rbxassetid://78954441062079",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = true,
        IsFree      = false,
    },
    {
        Id          = "headless",
        DisplayName = "Headless",
        Description = "Go full headless mode.",
        AnimationId = "rbxassetid://76606692073439",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "rat_dance",
        DisplayName = "Rat Dance",
        Description = "Do the rat dance.",
        AnimationId = "rbxassetid://119292485335481",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "floss",
        DisplayName = "Floss",
        Description = "Hit the floss.",
        AnimationId = "rbxassetid://130811327314009",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "dab",
        DisplayName = "Dab",
        Description = "Throw a quick dab.",
        AnimationId = "rbxassetid://75003807251572",
        CoinCost    = 20,
        Cooldown    = 1,
        Looped      = false,
        IsFree      = false,
    },
    {
        Id          = "macarena",
        DisplayName = "Macarena",
        Description = "Everybody do the Macarena.",
        AnimationId = "rbxassetid://114789325138547",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    {
        Id          = "ride_the_pony",
        DisplayName = "Ride The Pony",
        Description = "Bring back the classic.",
        AnimationId = "rbxassetid://94326793594112",
        CoinCost    = 20,
        Cooldown    = 1,
        UseRunning  = true,
        IsFree      = false,
    },
    {
        Id          = "the_robot",
        DisplayName = "The Robot",
        Description = "Lock into robot mode.",
        AnimationId = "rbxassetid://140192311385186",
        CoinCost    = 20,
        Cooldown    = 1,
        IsFree      = false,
    },
    -- Future emotes go here.
}

-- ── Cooldown defaults ─────────────────────────────────────────────────────
EmoteConfig.DEFAULT_COOLDOWN = 1  -- seconds

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
