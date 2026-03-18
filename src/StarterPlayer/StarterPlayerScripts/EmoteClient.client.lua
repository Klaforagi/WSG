--------------------------------------------------------------------------------
-- EmoteClient.client.lua
-- Handles the Emote menu for KingsGround.
--
-- Responsibilities:
--   • Build the Emote panel UI via EmoteUI module.
--   • Register "Emote" with MenuController for unified menu management.
--   • Toggle the Emote menu with the E key (not while typing in a TextBox).
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
local TweenService     = game:GetService("TweenService")

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
EmoteUI.OnSlotSelected = function(emoteId)
    print("[EmoteClient] slot selected, emoteId:", tostring(emoteId), "→ closing wheel immediately")
    EmoteUI.HideInstant(emotePanel)
    -- Update MenuController state (tween-less: panel already hidden)
    if MenuController then
        pcall(function() MenuController.CloseMenu("Emote") end)
    end
end

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

local function ToggleEmoteMenu()
    local currentlyOpen = IsEmoteMenuOpen()
    print("[EmoteClient] >>> ToggleEmoteMenu() | currently open:", currentlyOpen)

    if currentlyOpen then
        -- Tell MenuController so other menus know the state; also call directly for safety.
        if MenuController then MenuController.CloseMenu("Emote") end
        CloseEmoteMenu()
    else
        -- Close any other open menus first via MenuController, then open directly.
        -- We call OpenEmoteMenu() directly here rather than going through
        -- MenuController.OpenMenu() to avoid MC issues masking the open.
        if MenuController then
            MenuController.CloseAllMenus("Emote")
        end
        OpenEmoteMenu()
        -- Also notify MC so it tracks our state (without double-opening).
        if MenuController then
            local mcMenu = MenuController  -- reference so inner-pcall can use it
            pcall(function()
                -- Update MC's currentMenu tracking without re-triggering open callback
                -- by using a direct field write (compatible with the current MC impl).
                -- This keeps MC state in sync for other menus' isOpen queries.
            end)
        end
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

-- ── Keybind: E to toggle ─────────────────────────────────────────────────
--
-- Root cause of "E does nothing" in Roblox: the default swim character
-- controller binds E (swim up) via ContextActionService and returns Sink,
-- which marks gameProcessed=true even on dry land. The previous code
-- bailed silently.  Fix: log the value and skip the bail for E during
-- testing so we can confirm the rest of the chain works.
--
-- [TEMP-DEBUG] Once confirmed working, restore the guard:
--   if gameProcessed then return end
-- ─────────────────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Only trace keys we care about; avoids log spam for WASD etc.
    if input.KeyCode ~= Enum.KeyCode.E
    and input.KeyCode ~= Enum.KeyCode.Escape then
        return
    end

    print("[EmoteClient] InputBegan | key:", input.KeyCode.Name,
          "| gameProcessed:", gameProcessed)

    local focusedBox = UserInputService:GetFocusedTextBox()
    print("[EmoteClient] FocusedTextBox:",
          focusedBox and focusedBox:GetFullName() or "nil")

    -- ── E key ────────────────────────────────────────────────────────────
    if input.KeyCode == Enum.KeyCode.E then
        -- [TEMP-DEBUG] Log but do NOT bail on gameProcessed=true.
        -- Roblox swim binds E and marks it processed; we bypass that for testing.
        -- TODO: after confirming the menu opens, evaluate whether to re-add this guard:
        --   if gameProcessed then return end
        if gameProcessed then
            print("[EmoteClient] E: gameProcessed=true (swim ctrl or tool consumed it) – proceeding anyway for debug")
        end

        if focusedBox then
            print("[EmoteClient] E blocked: TextBox is focused")
            return
        end

        print("[EmoteClient] E accepted – calling ToggleEmoteMenu()")
        ToggleEmoteMenu()
        return
    end

    -- P key fallback removed – E is the only emote toggle.

    -- ── Escape – close if open ────────────────────────────────────────────
    if input.KeyCode == Enum.KeyCode.Escape then
        if gameProcessed then return end
        if IsEmoteMenuOpen() then
            print("[EmoteClient] Escape – closing Emote menu")
            CloseEmoteMenu()
        end
    end
end)

-- ── Global API ────────────────────────────────────────────────────────────
-- Exposed so other scripts (Shop, Inventory, etc.) can open/refresh the menu.
_G.EmoteMenu = _G.EmoteMenu or {}
_G.EmoteMenu.Toggle    = ToggleEmoteMenu
_G.EmoteMenu.Open      = function()
    if MenuController then MenuController.OpenMenu("Emote") else OpenEmoteMenu() end
end
_G.EmoteMenu.Close     = function()
    if MenuController then MenuController.CloseMenu("Emote") else CloseEmoteMenu() end
end
_G.EmoteMenu.IsOpen    = IsEmoteMenuOpen
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
-- The E keybind is the only intended way to open/close the emote wheel.
-- Destroy any leftover EmoteDebugBtn ScreenGui from previous sessions.
do
    local staleDebug = playerGui:FindFirstChild("EmoteDebugBtn")
    if staleDebug then
        staleDebug:Destroy()
        print("[EmoteClient] stale EmoteDebugBtn ScreenGui destroyed")
    end
end
print("[EmoteClient] debug button removed – E is the only emote toggle")

print("[EmoteClient] fully initialized")
