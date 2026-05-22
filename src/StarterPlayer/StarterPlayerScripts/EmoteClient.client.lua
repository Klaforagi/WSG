--------------------------------------------------------------------------------
-- EmoteClient.client.lua
-- Handles the Emote menu for KingsGround.
--
-- Responsibilities:
--   • Build the Emote panel UI via EmoteUI module.
--   • Register "Emote" with MenuController for unified menu management.
--   • Open the Emote menu while holding F (not while typing in a TextBox).
--   • Expose ToggleEmoteMenu / OpenEmoteMenu / CloseEmoteMenu globally so
--     other scripts can open the menu programmatically.
--   • Render owned/equipped emotes when data becomes available.
--   • Show a polished empty-state when no emotes are owned/equipped.
--
-- Future integration points (marked TODO):
--   • Read owned/equipped emote data from a server RemoteFunction.
--   • Wire emote slots to EmoteUI.RequestPlayEmote(emoteId).
--   • Cancel emotes on movement / jump / attack via Character events.
--------------------------------------------------------------------------------

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService     = game:GetService("TweenService")

-- Keep a stable signal for text entry, including chat/custom text fields.
local textEntryActive = false
UserInputService.TextBoxFocused:Connect(function(textBox)
    textEntryActive = true
    print("[EmoteClient] TextBoxFocused:", textBox and textBox:GetFullName() or "nil")
end)
UserInputService.TextBoxFocusReleased:Connect(function(textBox)
    textEntryActive = UserInputService:GetFocusedTextBox() ~= nil
    print("[EmoteClient] TextBoxFocusReleased:", textBox and textBox:GetFullName() or "nil",
          "| textEntryActive:", textEntryActive)
end)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Script-started confirmation (must be the very first output) ──────────
print("[EmoteClient] ===== SCRIPT STARTED =====", player and player.Name)

-- ── Viewport readiness guard (mirrors SideUI / TeamStatsUI pattern) ──────
do
    local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 5)
    if cam then
        local t = 0
        while cam.ViewportSize.Y < 2 and t < 3 do t = t + task.wait() end
    end
end

print("[EmoteClient] initializing for", player and player.Name)

-- ── Require shared modules ────────────────────────────────────────────────
local sideUIFolder = ReplicatedStorage:WaitForChild("SideUI", 10)
if not sideUIFolder then
    warn("[EmoteClient] SideUI folder not found – aborting emote system")
    return
end

local EmoteUI = nil
do
    local mod = sideUIFolder:WaitForChild("EmoteUI", 5)
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then
            EmoteUI = result
            print("[EmoteClient] EmoteUI module loaded OK")
        else
            warn("[EmoteClient] EmoteUI require() failed:", result)
        end
    else
        warn("[EmoteClient] EmoteUI ModuleScript not found in SideUI")
    end
end
if not EmoteUI then
    warn("[EmoteClient] Aborting: EmoteUI unavailable")
    return
end

local EmoteConfig = nil
do
    local mod = sideUIFolder:FindFirstChild("EmoteConfig")
    if mod and mod:IsA("ModuleScript") then
        local ok, result = pcall(require, mod)
        if ok then EmoteConfig = result end
    end
end

-- MenuController: shared menu registry
local MenuController = nil
do
    local mcMod = sideUIFolder:WaitForChild("MenuController", 5)
    if mcMod and mcMod:IsA("ModuleScript") then
        local ok, result = pcall(require, mcMod)
        if ok then
            MenuController = result
            print("[EmoteClient] MenuController loaded")
        else
            warn("[EmoteClient] MenuController failed:", result)
        end
    end
end

-- ── Create dedicated ScreenGui ────────────────────────────────────────────
-- Destroy any stale gui from a previous hot-reload so we never stack copies.
do
    local existing = playerGui:FindFirstChild("EmoteGui")
    if existing then
        existing:Destroy()
        print("[EmoteClient] Destroyed stale EmoteGui")
    end
end

local emoteGui = Instance.new("ScreenGui")
emoteGui.Name            = "EmoteGui"
emoteGui.ResetOnSpawn    = false
emoteGui.IgnoreGuiInset  = true
emoteGui.DisplayOrder    = 320   -- above SideUI (250), above TeamStats (270)
emoteGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
emoteGui.Parent          = playerGui
print("[EmoteClient] EmoteGui ScreenGui created; parent:", emoteGui.Parent:GetFullName())

-- ── Build the emote panel ─────────────────────────────────────────────────
local emotePanel = EmoteUI.Build(emoteGui)
print("[EmoteClient] Emote panel built; path:", emotePanel and emotePanel:GetFullName() or "NIL")
print("[EmoteClient] emotePanel.Visible (should be false):", emotePanel and emotePanel.Visible)

-- ── Wire the close-after-selection callback ──────────────────────────────
-- When the player clicks a slot (or the backdrop), EmoteUI calls this.
-- We hide the wheel instantly so the player can see the emote clearly.
-- NOTE: OpenEmoteShop, OnSlotSelected, and OnShopClicked are wired further
-- below (after IsEmoteMenuOpen is defined) to avoid forward-reference nils.

-- ── Emote remotes ─────────────────────────────────────────────────────────
local emoteRemotes = nil
do
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    local emoteDir = remotes and (remotes:FindFirstChild("Emotes") or remotes:WaitForChild("Emotes", 5))
    if emoteDir then
        emoteRemotes = {
            getEquipped    = emoteDir:FindFirstChild("GetEquippedEmotes"),
            equippedChanged = emoteDir:FindFirstChild("EquippedEmotesChanged"),
        }
        print("[EmoteClient] emote remotes resolved")
    else
        warn("[EmoteClient] Remotes.Emotes folder not found")
    end
end

-- ── Emote data helpers ────────────────────────────────────────────────────
-- Cache the last-known equipped emote list for fast re-opens
local cachedEquipped = {}

local function GetEquippedEmotes()
    if emoteRemotes and emoteRemotes.getEquipped and emoteRemotes.getEquipped:IsA("RemoteFunction") then
        local ok, list = pcall(function() return emoteRemotes.getEquipped:InvokeServer() end)
        if ok and type(list) == "table" then
            cachedEquipped = list
            return list
        end
    end
    return cachedEquipped
end

local locomotionSuppressToken = 0

local function getLocalHumanoid()
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

local function stopLocalLocomotionTracks()
    local humanoid = getLocalHumanoid()
    if not humanoid then return end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local priority = track.Priority
        if priority == Enum.AnimationPriority.Core
            or priority == Enum.AnimationPriority.Idle
            or priority == Enum.AnimationPriority.Movement then
            pcall(function() track:Stop(0) end)
        end
    end
end

local function setAnimateSuppressed(suppressed)
    local character = player.Character
    if not character then return end

    local animateScript = character:FindFirstChild("Animate")
    if animateScript and (animateScript:IsA("LocalScript") or animateScript:IsA("Script")) then
        animateScript.Disabled = suppressed
    end

    if suppressed then
        stopLocalLocomotionTracks()
    end
end

local function refreshLocalEmoteMovementState()
    local useRunning = player:GetAttribute("ActiveEmoteUseRunning") == true
    local emoteId = player:GetAttribute("ActiveEmoteId")
    local shouldSuppress = useRunning and type(emoteId) == "string" and emoteId ~= ""

    locomotionSuppressToken += 1
    local token = locomotionSuppressToken

    setAnimateSuppressed(shouldSuppress)

    if shouldSuppress then
        task.spawn(function()
            while locomotionSuppressToken == token
                and player:GetAttribute("ActiveEmoteUseRunning") == true
                and type(player:GetAttribute("ActiveEmoteId")) == "string" do
                stopLocalLocomotionTracks()
                task.wait(0.1)
            end
        end)
    end
end

player:GetAttributeChangedSignal("ActiveEmoteId"):Connect(refreshLocalEmoteMovementState)
player:GetAttributeChangedSignal("ActiveEmoteUseRunning"):Connect(refreshLocalEmoteMovementState)
player.CharacterAdded:Connect(function()
    task.defer(refreshLocalEmoteMovementState)
end)
refreshLocalEmoteMovementState()

-- ── Open / close helpers ──────────────────────────────────────────────────
local function OpenEmoteMenu()
    print("[EmoteClient] >>> OpenEmoteMenu() called")
    print("[EmoteClient]   emotePanel:", emotePanel and emotePanel:GetFullName() or "NIL")
    print("[EmoteClient]   emotePanel.Visible before Show:", emotePanel and emotePanel.Visible)
    local equipped = GetEquippedEmotes()
    print("[EmoteClient]   equipped emotes count:", #equipped)
    if #equipped > 0 then
        EmoteUI.RenderEquippedEmotes(emotePanel, equipped)
    else
        EmoteUI.ShowEmptyState(emotePanel)
    end
    EmoteUI.Show(emotePanel)
    print("[EmoteClient]   emotePanel.Visible after Show:", emotePanel and emotePanel.Visible)
end

local function CloseEmoteMenu()
    print("[EmoteClient] >>> CloseEmoteMenu() called")
    print("[EmoteClient]   emotePanel.Visible before Hide:", emotePanel and emotePanel.Visible)
    EmoteUI.Hide(emotePanel)
end

local function CloseEmoteMenuInstant()
    print("[EmoteClient] >>> CloseEmoteMenuInstant() called")
    EmoteUI.HideInstant(emotePanel)
end

local function IsEmoteMenuOpen()
    return EmoteUI.IsVisible(emotePanel)
end

-- ── Wire emote-wheel callbacks (Shop slot + emote slot selection) ────────
-- Placed here so all required locals (IsEmoteMenuOpen, etc.) are in scope.

local function OpenEmoteShop()
    print("[EmoteClient] OpenEmoteShop() called")
    print("[EmoteClient]   EmoteUI.OpenEmoteShop:", typeof(EmoteUI.OpenEmoteShop), EmoteUI.OpenEmoteShop ~= nil)
    -- Close emote wheel first (belt-and-suspenders; OnShopClicked already does this)
    if IsEmoteMenuOpen() then
        EmoteUI.HideInstant(emotePanel)
        if MenuController then
            pcall(function() MenuController.CloseMenu("Emote") end)
        end
    end
    -- Delegate to EmoteUI which uses MenuController to open Shop → Emotes tab
    if type(EmoteUI.OpenEmoteShop) == "function" then
        EmoteUI.OpenEmoteShop()
    else
        warn("[EmoteClient] EmoteUI.OpenEmoteShop is not a function:", typeof(EmoteUI.OpenEmoteShop))
    end
end

EmoteUI.OnSlotSelected = function(emoteId)
    print("[EmoteClient] slot selected, emoteId:", tostring(emoteId), "→ closing wheel immediately")
    EmoteUI.HideInstant(emotePanel)
    if MenuController then
        pcall(function() MenuController.CloseMenu("Emote") end)
    end
end

EmoteUI.OnShopClicked = function()
    print("[EmoteClient] Shop clicked → closing wheel and opening emote shop")
    EmoteUI.HideInstant(emotePanel)
    if MenuController then
        pcall(function() MenuController.CloseMenu("Emote") end)
    end
    OpenEmoteShop()
end

local function OpenEmoteMenuHold()
    if IsEmoteMenuOpen() then
        return
    end

    print("[EmoteClient] >>> OpenEmoteMenuHold()")
    if MenuController then
        MenuController.CloseAllMenus("Emote")
    end
    OpenEmoteMenu()
end

local function ReleaseEmoteMenuHold()
    if not IsEmoteMenuOpen() then
        return
    end

    print("[EmoteClient] >>> ReleaseEmoteMenuHold()")
    local activated = false
    if type(EmoteUI.TriggerHighlightedSelection) == "function" then
        local ok, result = pcall(function()
            return EmoteUI.TriggerHighlightedSelection(emotePanel)
        end)
        activated = ok and result == true
    end

    if activated then
        return
    end

    if MenuController then
        MenuController.CloseMenu("Emote")
    else
        CloseEmoteMenu()
    end
end

-- ── Register with MenuController ──────────────────────────────────────────
-- The Emote menu is NOT part of the "modal" group (it is a floating overlay,
-- not the big SideUI modal window). This means opening Emote will close the
-- modal menus, and opening a modal menu will close the Emote menu.
if MenuController then
    MenuController.RegisterMenu("Emote", {
        -- No group → every open closes all other open menus first.
        open = function(sameGroup)
            OpenEmoteMenu()
        end,
        close = function()
            CloseEmoteMenu()
        end,
        closeInstant = function()
            CloseEmoteMenuInstant()
        end,
        isOpen = function()
            return IsEmoteMenuOpen()
        end,
    })
    print("[EmoteClient] Emote menu registered with MenuController")
end

-- ── Keybind: hold F to keep the emote menu open (via ContextActionService) ──
--
-- WHY CAS instead of InputBegan for the hotkey:
--   1. Roblox's modern TextChatService chat uses an internal TextBox that
--      GetFocusedTextBox() cannot see, so we can't detect chat focus from
--      InputBegan.
--   2. CAS callbacks are AUTOMATICALLY SUPPRESSED by the engine when ANY
--      TextBox is focused — including the chat's internal TextBox. This
--      means our handler simply won't fire while the player is typing in
--      chat, with zero extra detection code needed.
--   3. Keeping the emote toggle on CAS also makes the input handling
--      consistent across keyboard focus changes and respawns.
-- ─────────────────────────────────────────────────────────────────────────

local function handleEmoteHotkey(_actionName, inputState, inputObject)
    print("[EmoteClient] CAS EmoteToggle fired | inputState:", inputState.Name,
          "| textEntryActive:", textEntryActive)

    if inputState == Enum.UserInputState.Begin then
        local focusedTextBox = UserInputService:GetFocusedTextBox()
        if focusedTextBox then
            print("[EmoteClient] F blocked — player is typing in:", focusedTextBox:GetFullName())
            return Enum.ContextActionResult.Pass
        end

        OpenEmoteMenuHold()
        return Enum.ContextActionResult.Sink
    end

    if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
        ReleaseEmoteMenuHold()
        return Enum.ContextActionResult.Sink
    end

    return Enum.ContextActionResult.Sink
end

-- Bind now, and re-bind after every respawn so the action stays active.
local function bindEmoteHotkey()
    ContextActionService:BindAction("EmoteToggle", handleEmoteHotkey, false, Enum.KeyCode.F)
    print("[EmoteClient] EmoteToggle CAS action bound to F")
end

player.CharacterAdded:Connect(function()
    -- Small delay so the swim controller binds first, then we override it
    task.delay(0.5, bindEmoteHotkey)
end)
bindEmoteHotkey()  -- initial bind

-- ── Escape key (stays in InputBegan — no swim conflict) ──────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if not input then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode ~= Enum.KeyCode.Escape then return end

    if gameProcessedEvent then return end

    local focusedTextBox = UserInputService:GetFocusedTextBox()
    if focusedTextBox then return end

    if IsEmoteMenuOpen() then
        print("[EmoteClient] Escape – closing Emote menu")
        CloseEmoteMenu()
    end
end)

-- ── Global API ────────────────────────────────────────────────────────────
-- Exposed so other scripts (Shop, Inventory, etc.) can open/refresh the menu.
_G.EmoteMenu = _G.EmoteMenu or {}
_G.EmoteMenu.Toggle    = function()
    if IsEmoteMenuOpen() then
        ReleaseEmoteMenuHold()
    else
        OpenEmoteMenuHold()
    end
end
_G.EmoteMenu.Open      = function()
    OpenEmoteMenuHold()
end
_G.EmoteMenu.Close     = function()
    if MenuController then MenuController.CloseMenu("Emote") else CloseEmoteMenu() end
end
_G.EmoteMenu.IsOpen    = IsEmoteMenuOpen
_G.EmoteMenu.OpenShop  = OpenEmoteShop
-- Called by Inventory UI once it has real equipped emote data:
--   _G.EmoteMenu.RefreshEmotes({ {Id="wave", DisplayName="Wave", IconAssetId="..."}, ... })
_G.EmoteMenu.RefreshEmotes = function(equippedList)
    if not equippedList then return end
    if #equippedList > 0 then
        EmoteUI.RenderEquippedEmotes(emotePanel, equippedList)
    else
        EmoteUI.ShowEmptyState(emotePanel)
    end
end

-- ── Live data wiring ──────────────────────────────────────────────────────
-- Fetch initial equipped emotes and listen for server-side changes.
task.spawn(function()
    -- Initial fetch (populates cache so first menu open is instant)
    local list = GetEquippedEmotes()
    if list and #list > 0 then
        cachedEquipped = list
        print("[EmoteClient] initial equipped emotes loaded:", #list)
    end

    -- Live updates (e.g. player equipped a new emote in Inventory)
    if emoteRemotes and emoteRemotes.equippedChanged and emoteRemotes.equippedChanged:IsA("RemoteEvent") then
        emoteRemotes.equippedChanged.OnClientEvent:Connect(function(updatedList)
            if type(updatedList) == "table" then
                cachedEquipped = updatedList
                print("[EmoteClient] received EquippedEmotesChanged, count:", #updatedList)
                -- If the emote menu is currently open, refresh it live
                if IsEmoteMenuOpen() then
                    if #updatedList > 0 then
                        EmoteUI.RenderEquippedEmotes(emotePanel, updatedList)
                    else
                        EmoteUI.ShowEmptyState(emotePanel)
                    end
                end
            end
        end)
        print("[EmoteClient] EquippedEmotesChanged listener connected")
    end
end)

-- ── [REMOVED] Debug button was here — now deleted ────────────────────────
-- Hold F to keep the emote wheel open, then release to select or close.
-- Destroy any leftover EmoteDebugBtn ScreenGui from previous sessions.
do
    local staleDebug = playerGui:FindFirstChild("EmoteDebugBtn")
    if staleDebug then
        staleDebug:Destroy()
        print("[EmoteClient] stale EmoteDebugBtn ScreenGui destroyed")
    end
end
print("[EmoteClient] debug button removed – hold F for emotes")

print("[EmoteClient] fully initialized")
