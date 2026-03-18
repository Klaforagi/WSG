--------------------------------------------------------------------------------
-- EmoteServiceInit.server.lua
-- Server-side stub for the Emote system.
--
-- Creates the Remotes.Emotes folder and placeholder RemoteEvents /
-- RemoteFunctions so the client can wire to them immediately. No actual
-- emote playback or validation is implemented yet; those are gated behind
-- TODO comments for future development.
--
-- Remotes created:
--   ReplicatedStorage.Remotes.Emotes.PlayEmote          (RemoteEvent)
--     Client → Server: request to play an animation emote.
--   ReplicatedStorage.Remotes.Emotes.StopEmote           (RemoteEvent)
--     Client → Server: request to cancel the current emote.
--   ReplicatedStorage.Remotes.Emotes.GetEquippedEmotes   (RemoteFunction)
--     Client → Server: fetch the player's current equipped emote loadout.
--   ReplicatedStorage.Remotes.Emotes.EquippedEmotesChanged (RemoteEvent)
--     Server → Client: pushed when the player equips / unequips an emote.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[EmoteServiceInit] initializing")

-- ── Shared helper ──────────────────────────────────────────────────────────
local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA(className) then return existing end
        existing:Destroy()
    end
    local inst = Instance.new(className)
    inst.Name = name
    inst.Parent = parent
    return inst
end

-- ── Remote setup ───────────────────────────────────────────────────────────
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local emotesFolder = ensureInstance(remotesFolder, "Folder", "Emotes")

-- Client → Server: play an emote
local playEmoteRE        = ensureInstance(emotesFolder, "RemoteEvent",    "PlayEmote")

-- Client → Server: stop current emote
local stopEmoteRE        = ensureInstance(emotesFolder, "RemoteEvent",    "StopEmote")

-- Client → Server: fetch equipped emote loadout
local getEquippedRF      = ensureInstance(emotesFolder, "RemoteFunction", "GetEquippedEmotes")

-- Server → Client: pushed when equip loadout changes
local equippedChangedRE  = ensureInstance(emotesFolder, "RemoteEvent",    "EquippedEmotesChanged")

print("[EmoteServiceInit] Remotes.Emotes folder and remotes created")

-- ── Per-player emote state ─────────────────────────────────────────────────
-- Stores { ownedEmotes = {}, equippedEmotes = {} } per player.
-- Both are empty until a Shop / Inventory emote purchase system is built.
local playerEmoteData = {}  -- [player] = { owned={}, equipped={} }

local function getOrCreateData(player)
    if not playerEmoteData[player] then
        playerEmoteData[player] = {
            owned    = {},  -- list of emote ids the player owns
            equipped = {},  -- ordered list (index = slot) of emote ids
        }
    end
    return playerEmoteData[player]
end

Players.PlayerAdded:Connect(function(player)
    getOrCreateData(player)
    -- TODO: Load emote data from DataStore when the persistence layer is ready.
    print("[EmoteServiceInit] player joined, emote state initialized:", player.Name)
end)

Players.PlayerRemoving:Connect(function(player)
    -- TODO: Save emote data to DataStore here.
    playerEmoteData[player] = nil
end)

-- Pre-initialize for any players already in the server (hot-reload scenario)
for _, p in ipairs(Players:GetPlayers()) do
    getOrCreateData(p)
end

-- ── Remote handlers ────────────────────────────────────────────────────────

-- GetEquippedEmotes: return the player's equipped emote list.
-- Right now returns empty; future: build from playerEmoteData[player].equipped.
getEquippedRF.OnServerInvoke = function(player)
    local data = getOrCreateData(player)
    -- TODO: map equipped emote ids → full EmoteConfig entries for the client
    local result = {}
    for _, emoteId in ipairs(data.equipped) do
        table.insert(result, { Id = emoteId, DisplayName = emoteId })
    end
    return result
end

-- PlayEmote: validate and broadcast an emote animation request.
-- Empty stub for now; no animation is played. Safety checks are noted below.
playEmoteRE.OnServerEvent:Connect(function(player, emoteId)
    -- TODO: implement when animations are ready:
    --   1. Validate emoteId is a string and non-empty.
    --   2. Check playerEmoteData[player].owned contains emoteId.
    --   3. Enforce per-emote cooldown (server-authoritative).
    --   4. Load & play the animation on the character.
    --   5. Cancel if player moves / jumps within cooldown window.
    if type(emoteId) ~= "string" or #emoteId == 0 then
        warn("[EmoteServiceInit] PlayEmote: invalid emoteId from", player.Name)
        return
    end
    print("[EmoteServiceInit] PlayEmote stub:", player.Name, emoteId)
end)

-- StopEmote: cancel the current emote for the requesting player.
stopEmoteRE.OnServerEvent:Connect(function(player)
    -- TODO: stop the Animation track on the character when playback is implemented.
    print("[EmoteServiceInit] StopEmote stub:", player.Name)
end)

print("[EmoteServiceInit] fully initialized")
