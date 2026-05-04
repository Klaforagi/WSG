--------------------------------------------------------------------------------
-- EmoteServiceInit.server.lua
-- Server-side logic for the Emote system: purchase, equip, play, persist.
--
-- Remotes (under ReplicatedStorage.Remotes.Emotes):
--   PlayEmote           (RE client→server)  request animation playback
--   StopEmote           (RE client→server)  cancel current emote
--   GetEquippedEmotes   (RF client→server)  fetch equipped emote loadout
--   EquippedEmotesChanged (RE server→client) push after equip/unequip
--   PurchaseEmote       (RF client→server)  buy an emote with coins
--   EquipEmote          (RE client→server)  equip an owned emote into a slot
--   UnequipEmote        (RE client→server)  clear an emote slot
--   GetOwnedEmotes      (RF client→server)  fetch list of owned emote ids
--------------------------------------------------------------------------------

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

print("[EmoteService] initializing")

-- ── Shared config ──────────────────────────────────────────────────────────
local EmoteConfig = nil
pcall(function()
    local sideUI = ReplicatedStorage:WaitForChild("SideUI", 10)
    local mod = sideUI and sideUI:FindFirstChild("EmoteConfig")
    if mod and mod:IsA("ModuleScript") then EmoteConfig = require(mod) end
end)
if not EmoteConfig then
    warn("[EmoteService] EmoteConfig not found – emote system disabled")
    return
end

local SLOT_COUNT = EmoteConfig.SLOT_COUNT or 6

-- ── CurrencyService ────────────────────────────────────────────────────────
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then CurrencyService = require(mod) end
end)

-- ── DataStore ──────────────────────────────────────────────────────────────
local DATASTORE_NAME = "Emotes_v1"
local RETRIES        = 3
local RETRY_DELAY    = 0.5
local ds = nil
pcall(function() ds = DataStoreService:GetDataStore(DATASTORE_NAME) end)

-- ── Helper ─────────────────────────────────────────────────────────────────
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

local playEmoteRE        = ensureInstance(emotesFolder, "RemoteEvent",    "PlayEmote")
local stopEmoteRE        = ensureInstance(emotesFolder, "RemoteEvent",    "StopEmote")
local getEquippedRF      = ensureInstance(emotesFolder, "RemoteFunction", "GetEquippedEmotes")
local equippedChangedRE  = ensureInstance(emotesFolder, "RemoteEvent",    "EquippedEmotesChanged")
local purchaseEmoteRF    = ensureInstance(emotesFolder, "RemoteFunction", "PurchaseEmote")
local equipEmoteRE       = ensureInstance(emotesFolder, "RemoteEvent",    "EquipEmote")
local unequipEmoteRE     = ensureInstance(emotesFolder, "RemoteEvent",    "UnequipEmote")
local getOwnedRF         = ensureInstance(emotesFolder, "RemoteFunction", "GetOwnedEmotes")

print("[EmoteService] Remotes created")

-- ── Per-player state ───────────────────────────────────────────────────────
-- playerEmoteData[player] = { owned = { [emoteId] = true }, equipped = { [slot] = emoteId } }
local playerEmoteData = {}
-- Active animation tracks per player for cancel logic
local activeEmoteTracks = {} -- [player] = AnimationTrack
local emoteCooldowns    = {} -- [player] = { [emoteId] = os.clock() }
-- Movement / cancel connections per player
local cancelConns       = {} -- [player] = { conn1, conn2, ... }
local emoteSectionRegistered = false

local function copyEmoteData(data)
    return DataStoreOps.DeepCopy(data)
end

local function countOwnedEmotes(data)
    if type(data) ~= "table" or type(data.owned) ~= "table" then
        return 0
    end
    local count = 0
    for _, owned in pairs(data.owned) do
        if owned then
            count += 1
        end
    end
    return count
end

local function markDirty(player, reason, options)
    DataSaveCoordinator:MarkDirty(player, "Emote", reason or "emote", options)
end

-- ── Persistence helpers ────────────────────────────────────────────────────
local function dsKey(player)
    return "User_" .. tostring(player.UserId)
end

local function loadEmoteData(player)
    if not ds then return { owned = {}, equipped = {} }, "failed", "missing datastore" end
    local success, result, err = DataStoreOps.Load(ds, dsKey(player), "Emote/" .. dsKey(player))
    if success and type(result) == "table" then
        -- Normalise owned from array to set if needed (legacy compat)
        local owned = {}
        if type(result.owned) == "table" then
            -- If it's an array of strings, convert to set
            for k, v in pairs(result.owned) do
                if type(k) == "number" and type(v) == "string" then
                    owned[v] = true
                elseif type(v) == "boolean" then
                    owned[k] = v
                end
            end
        end
        local equipped = {}
        if type(result.equipped) == "table" then
            for slot, id in pairs(result.equipped) do
                local s = tonumber(slot)
                if s and type(id) == "string" then equipped[s] = id end
            end
        end
        -- Grant any free emotes
        for _, def in ipairs(EmoteConfig.GetAll()) do
            if def.IsFree then owned[def.Id] = true end
        end
        return { owned = owned, equipped = equipped }, "existing", nil
    end
    -- Default: grant free emotes
    local owned = {}
    for _, def in ipairs(EmoteConfig.GetAll()) do
        if def.IsFree then owned[def.Id] = true end
    end
    return { owned = owned, equipped = {} }, success and "new" or "failed", err
end

local function getSaveData(player)
    local data = playerEmoteData[player]
    if not data then return nil end
    return copyEmoteData(data)
end

local function saveEmoteData(player, data, oldData)
    if not ds then return false, "missing datastore" end
    data = data or playerEmoteData[player]
    if not data then return false, "missing data" end
    -- Convert owned set to array for compact storage
    local ownedArr = {}
    for id, v in pairs(data.owned) do
        if v then table.insert(ownedArr, id) end
    end
    -- Convert equipped map {[number]=string} to storable table
    local equippedMap = {}
    for slot, id in pairs(data.equipped) do
        equippedMap[tostring(slot)] = id
    end
    local payload = { owned = ownedArr, equipped = equippedMap }
    local success, _, err = DataStoreOps.Update(ds, dsKey(player), "Emote/" .. dsKey(player), function(storedPayload)
        local previous = type(oldData) == "table" and oldData or storedPayload or {}
        local previousState = { owned = {}, equipped = {} }
        if type(previous.owned) == "table" then
            for _, emoteId in ipairs(previous.owned) do
                if type(emoteId) == "string" and emoteId ~= "" then
                    previousState.owned[emoteId] = true
                end
            end
        end
        if type(previous.equipped) == "table" then
            for slot, emoteId in pairs(previous.equipped) do
                local normalizedSlot = tonumber(slot)
                if normalizedSlot and type(emoteId) == "string" then
                    previousState.equipped[normalizedSlot] = emoteId
                end
            end
        end
        if countOwnedEmotes(previousState) > 0 and countOwnedEmotes(data) == 0 then
            warn("[EmoteService] suspected wipe blocked for", player.Name)
            return storedPayload
        end
        return payload
    end)
    if success then
        print("[EmoteService] saved emote data for", player.Name)
        return true
    end
    return false, err
end

local function loadProfile(player)
    local data, status, reason = loadEmoteData(player)
    playerEmoteData[player] = data
    print("[EmoteService] loaded emote data for", player.Name,
          "owned:", playerEmoteData[player].owned,
          "equipped:", playerEmoteData[player].equipped)
    return {
        status = status,
        data = copyEmoteData(data),
        reason = reason,
    }
end

local function getOrCreateData(player)
    if not playerEmoteData[player] then
        local data = loadEmoteData(player)
        playerEmoteData[player] = data
        print("[EmoteService] loaded emote data for", player.Name,
              "owned:", playerEmoteData[player].owned,
              "equipped:", playerEmoteData[player].equipped)
    end
    return playerEmoteData[player]
end

-- ── Owned / Equipped helpers ───────────────────────────────────────────────
local function isOwned(player, emoteId)
    local data = getOrCreateData(player)
    return data.owned[emoteId] == true
end

local function getOwnedList(player)
    local data = getOrCreateData(player)
    local list = {}
    for id, v in pairs(data.owned) do
        if v then table.insert(list, id) end
    end
    return list
end

local function getEquippedList(player)
    local data = getOrCreateData(player)
    local result = {}
    for slot = 1, SLOT_COUNT do
        local emoteId = data.equipped[slot]
        if emoteId then
            local def = EmoteConfig.GetById(emoteId)
            if def then
                table.insert(result, {
                    Slot        = slot,
                    Id          = def.Id,
                    DisplayName = def.DisplayName,
                    IconKey     = def.IconKey,
                })
            end
        end
    end
    return result
end

local function pushEquippedToClient(player)
    local list = getEquippedList(player)
    pcall(function() equippedChangedRE:FireClient(player, list) end)
end

-- ── Emote animation state ──────────────────────────────────────────────────
local function stopEmoteForPlayer(player, reason)
    local track = activeEmoteTracks[player]
    if track then
        pcall(function() track:Stop(0.25) end)
        activeEmoteTracks[player] = nil
        print("[EmoteService] emote stopped for", player.Name, "reason:", reason or "unknown")
    end
    -- Disconnect cancel connections
    local conns = cancelConns[player]
    if conns then
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        cancelConns[player] = nil
    end
end

local function playEmoteForPlayer(player, emoteId)
    local def = EmoteConfig.GetById(emoteId)
    if not def then
        warn("[EmoteService] playEmote: unknown emoteId", emoteId)
        return false, "unknown_emote"
    end

    local char = player.Character
    if not char then return false, "no_character" end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false, "no_humanoid" end
    if humanoid.Health <= 0 then return false, "dead" end

    -- Cooldown check
    local now = os.clock()
    local cd = emoteCooldowns[player]
    if cd and cd[emoteId] and (now - cd[emoteId]) < (def.Cooldown or EmoteConfig.DEFAULT_COOLDOWN) then
        return false, "cooldown"
    end

    -- Stop any current emote first
    stopEmoteForPlayer(player, "new_emote")

    -- Create and play animation
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = def.AnimationId
    local track
    local ok, err = pcall(function()
        track = animator:LoadAnimation(animation)
    end)
    animation:Destroy()
    if not ok or not track then
        warn("[EmoteService] failed to load animation:", err)
        return false, "animation_failed"
    end

    track.Priority = Enum.AnimationPriority.Action
    track.Looped = false
    pcall(function() track:Play(0.25) end)
    activeEmoteTracks[player] = track
    print("[EmoteService] animation started for", player.Name, "emote:", emoteId)

    -- Set cooldown
    if not emoteCooldowns[player] then emoteCooldowns[player] = {} end
    emoteCooldowns[player][emoteId] = now

    -- ── Cancel listeners ───────────────────────────────────────────────────
    local conns = {}
    cancelConns[player] = conns

    -- Cancel on track ended naturally
    table.insert(conns, track.Stopped:Connect(function()
        if activeEmoteTracks[player] == track then
            activeEmoteTracks[player] = nil
            print("[EmoteService] emote ended naturally for", player.Name)
        end
        -- Clean up connections
        local c = cancelConns[player]
        if c then
            for _, conn in ipairs(c) do pcall(function() conn:Disconnect() end) end
            cancelConns[player] = nil
        end
    end))

    -- Cancel on death
    table.insert(conns, humanoid.Died:Connect(function()
        stopEmoteForPlayer(player, "died")
    end))

    -- Cancel on significant movement (MoveDirection changes from zero)
    table.insert(conns, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
        if humanoid.MoveDirection.Magnitude > 0.1 then
            stopEmoteForPlayer(player, "moved")
        end
    end))

    -- Cancel on jump
    table.insert(conns, humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
        if humanoid.Jump then
            stopEmoteForPlayer(player, "jumped")
        end
    end))

    -- Cancel if humanoid state changes to something active
    table.insert(conns, humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Jumping
           or newState == Enum.HumanoidStateType.Freefall
           or newState == Enum.HumanoidStateType.Swimming
           or newState == Enum.HumanoidStateType.Climbing then
            stopEmoteForPlayer(player, "state_" .. newState.Name)
        end
    end))

    return true, "ok"
end

local function registerEmoteSection()
    if emoteSectionRegistered then
        return
    end
    emoteSectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "Emote",
        Priority = 75,
        Critical = false,
        Load = loadProfile,
        GetSaveData = getSaveData,
        Save = function(player, currentData, lastGoodData)
            return saveEmoteData(player, currentData, lastGoodData)
        end,
        Cleanup = function(player)
            stopEmoteForPlayer(player, "cleanup")
            playerEmoteData[player] = nil
            activeEmoteTracks[player] = nil
            emoteCooldowns[player] = nil
            cancelConns[player] = nil
        end,
        Validate = function(_, currentData, lastGoodData)
            if countOwnedEmotes(lastGoodData) > 0 and countOwnedEmotes(currentData) == 0 then
                return {
                    suspicious = true,
                    severity = "warning",
                    reason = "owned emotes became empty",
                }
            end
            return nil
        end,
    })
end

-- ── Player lifecycle ───────────────────────────────────────────────────────
registerEmoteSection()
Players.PlayerAdded:Connect(function(player)
    DataSaveCoordinator:LoadSection(player, "Emote")
    print("[EmoteService] player joined, emote state loaded:", player.Name)
end)

-- Hot-reload: initialise existing players
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(function() DataSaveCoordinator:LoadSection(p, "Emote") end)
end

-- ── Remote handlers ────────────────────────────────────────────────────────

-- GET OWNED EMOTES
getOwnedRF.OnServerInvoke = function(player)
    return getOwnedList(player)
end

-- GET EQUIPPED EMOTES
getEquippedRF.OnServerInvoke = function(player)
    return getEquippedList(player)
end

-- PURCHASE EMOTE: returns success (bool), newCoinBalance (number), message (string)
purchaseEmoteRF.OnServerInvoke = function(player, emoteId)
    if type(emoteId) ~= "string" or #emoteId == 0 then
        return false, 0, "invalid_id"
    end

    local def = EmoteConfig.GetById(emoteId)
    if not def then
        warn("[EmoteService] purchase: unknown emote", emoteId)
        return false, 0, "unknown_emote"
    end

    if isOwned(player, emoteId) then
        print("[EmoteService] purchase rejected: already owned", player.Name, emoteId)
        local bal = CurrencyService and CurrencyService:GetCoins(player) or 0
        return false, bal, "already_owned"
    end

    local price = def.CoinCost or 0
    if price > 0 then
        if not CurrencyService then
            warn("[EmoteService] CurrencyService unavailable")
            return false, 0, "no_currency"
        end
        local balance = CurrencyService:GetCoins(player)
        if balance < price then
            print("[EmoteService] purchase rejected: not enough coins", player.Name, balance, "<", price)
            return false, balance, "not_enough_coins"
        end
        CurrencyService:SetCoins(player, balance - price)
    end

    -- Mark as owned
    local data = getOrCreateData(player)
    data.owned[emoteId] = true
    print("[EmoteService] purchase accepted:", player.Name, emoteId)

    -- Auto-equip into the first empty slot if available
    local autoSlot = nil
    for s = 1, SLOT_COUNT do
        if not data.equipped[s] then
            autoSlot = s
            break
        end
    end
    if autoSlot then
        data.equipped[autoSlot] = emoteId
        print("[EmoteService] auto-equipped", emoteId, "into slot", autoSlot)
    end

    -- Persist
    markDirty(player, "purchase_emote")

    -- Push updates
    pushEquippedToClient(player)

    local newBal = CurrencyService and CurrencyService:GetCoins(player) or 0
    return true, newBal, "ok"
end

-- EQUIP EMOTE (client sends emoteId and desired slot number)
equipEmoteRE.OnServerEvent:Connect(function(player, emoteId, slot)
    if type(emoteId) ~= "string" or #emoteId == 0 then return end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > SLOT_COUNT then return end
    slot = math.floor(slot)

    if not isOwned(player, emoteId) then
        warn("[EmoteService] equip rejected: not owned", player.Name, emoteId)
        return
    end

    local data = getOrCreateData(player)

    -- Remove this emote from any other slot (no duplicates)
    for s = 1, SLOT_COUNT do
        if data.equipped[s] == emoteId then
            data.equipped[s] = nil
        end
    end

    data.equipped[slot] = emoteId
    print("[EmoteService] equipped", emoteId, "in slot", slot, "for", player.Name)

    markDirty(player, "equip_emote")
    pushEquippedToClient(player)
end)

-- UNEQUIP EMOTE
unequipEmoteRE.OnServerEvent:Connect(function(player, slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > SLOT_COUNT then return end
    slot = math.floor(slot)

    local data = getOrCreateData(player)
    local removed = data.equipped[slot]
    data.equipped[slot] = nil
    print("[EmoteService] unequipped slot", slot, "for", player.Name, "was:", removed)

    markDirty(player, "unequip_emote")
    pushEquippedToClient(player)
end)

-- PLAY EMOTE
playEmoteRE.OnServerEvent:Connect(function(player, emoteId)
    if type(emoteId) ~= "string" or #emoteId == 0 then
        warn("[EmoteService] PlayEmote: invalid emoteId from", player.Name)
        return
    end

    -- Validate ownership
    if not isOwned(player, emoteId) then
        warn("[EmoteService] PlayEmote rejected: not owned", player.Name, emoteId)
        return
    end

    -- Validate equipped (emote must be in an equipped slot)
    local data = getOrCreateData(player)
    local isEquipped = false
    for s = 1, SLOT_COUNT do
        if data.equipped[s] == emoteId then isEquipped = true; break end
    end
    if not isEquipped then
        warn("[EmoteService] PlayEmote rejected: not equipped", player.Name, emoteId)
        return
    end

    local success, reason = playEmoteForPlayer(player, emoteId)
    print("[EmoteService] PlayEmote result:", player.Name, emoteId, success, reason)
end)

-- STOP EMOTE
stopEmoteRE.OnServerEvent:Connect(function(player)
    stopEmoteForPlayer(player, "client_request")
end)

print("[EmoteService] fully initialized")

-- BindableFunction: GetEmoteOwnedCount(player) -> number
do
    local countBF = Instance.new("BindableFunction")
    countBF.Name = "GetEmoteOwnedCount"
    countBF.Parent = game:GetService("ServerScriptService")
    countBF.OnInvoke = function(player)
        if not player then return 0 end
        local list = getOwnedList(player)
        return #list
    end
end
