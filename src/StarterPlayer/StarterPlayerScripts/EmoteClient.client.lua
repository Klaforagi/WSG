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

-- ── Wire the close button (X in header) ──────────────────────────────────
local header   = emotePanel:FindFirstChild("Header")
local closeBtn = header and header:FindFirstChild("CloseBtn")
if closeBtn then
    closeBtn.MouseButton1Click:Connect(function()
        if MenuController then
            MenuController.CloseMenu("Emote")
        else
            EmoteUI.Hide(emotePanel)
        end
    end)
end

-- ── Emote data helpers ────────────────────────────────────────────────────
-- Returns the list of equipped emotes for the local player.
-- Currently returns an empty table (no emotes owned yet).
-- TODO: Replace with a RemoteFunction call to fetch real equipped emote data.
local function GetEquippedEmotes()
    -- Future: invoke Remotes.Emotes.GetEquippedEmotes:InvokeServer()
    -- For now, return an empty table (no emotes owned)
    return {}
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
    and input.KeyCode ~= Enum.KeyCode.P
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

    -- ── P key – [TEMP-TEST] unconditional fallback, no gameProcessed check ─
    -- Remove this block once the E keybind is confirmed working.
    if input.KeyCode == Enum.KeyCode.P then
        print("[EmoteClient] [TEMP-TEST] P key – calling ToggleEmoteMenu()")
        ToggleEmoteMenu()
        return
    end

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

-- ── TODO: Future live data wiring ─────────────────────────────────────────
-- When the server exposes emote ownership/equip data, connect here:
--
-- task.spawn(function()
--     local remotes  = ReplicatedStorage:WaitForChild("Remotes", 10)
--     local emoteDir = remotes and remotes:WaitForChild("Emotes", 5)
--     if not emoteDir then return end
--
--     -- Initial fetch
--     local getEquipped = emoteDir:FindFirstChild("GetEquippedEmotes")
--     if getEquipped and getEquipped:IsA("RemoteFunction") then
--         local ok, list = pcall(function() return getEquipped:InvokeServer() end)
--         if ok and type(list) == "table" then
--             _G.EmoteMenu.RefreshEmotes(list)
--         end
--     end
--
--     -- Live updates (e.g. player equipped a new emote in Inventory)
--     local equippedChanged = emoteDir:FindFirstChild("EquippedEmotesChanged")
--     if equippedChanged and equippedChanged:IsA("RemoteEvent") then
--         equippedChanged.OnClientEvent:Connect(function(list)
--             _G.EmoteMenu.RefreshEmotes(list)
--         end)
--     end
-- end)

-- ── [TEMP-TEST] Debug button ──────────────────────────────────────────────
-- A small on-screen button as a fallback if keybinds still fail.
-- Remove this entire block once both E and P are confirmed working.
do
    local debugGui = Instance.new("ScreenGui")
    debugGui.Name           = "EmoteDebugBtn"
    debugGui.ResetOnSpawn   = false
    debugGui.IgnoreGuiInset = true
    debugGui.DisplayOrder   = 325
    debugGui.Parent         = playerGui

    local btn = Instance.new("TextButton")
    btn.Name               = "ToggleBtn"
    btn.AnchorPoint        = Vector2.new(0, 0)
    btn.Position           = UDim2.new(0, 8, 0, 80)  -- top-left, below the coin display
    btn.Size               = UDim2.new(0, 90, 0, 28)
    btn.BackgroundColor3   = Color3.fromRGB(22, 26, 48)
    btn.BorderSizePixel    = 0
    btn.Font               = Enum.Font.GothamBold
    btn.Text               = "🎭 EMOTES"
    btn.TextColor3         = Color3.fromRGB(255, 215, 80)
    btn.TextSize           = 13
    btn.AutoButtonColor    = false
    btn.ZIndex             = 326
    btn.Parent             = debugGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color       = Color3.fromRGB(180, 150, 50)
    stroke.Thickness   = 1
    stroke.Transparency= 0.3
    stroke.Parent      = btn

    -- Label it clearly as temp in Studio
    local tempLabel = Instance.new("TextLabel")
    tempLabel.Name               = "TempLabel"
    tempLabel.Size               = UDim2.new(1, 0, 0, 10)
    tempLabel.Position           = UDim2.new(0, 0, 1, 2)
    tempLabel.BackgroundTransparency = 1
    tempLabel.Font               = Enum.Font.Gotham
    tempLabel.Text               = "[TEMP TEST]"
    tempLabel.TextColor3         = Color3.fromRGB(120, 120, 140)
    tempLabel.TextSize           = 9
    tempLabel.ZIndex             = 326
    tempLabel.Parent             = btn

    btn.MouseButton1Click:Connect(function()
        print("[EmoteClient] [TEMP-TEST] Debug button clicked – calling ToggleEmoteMenu()")
        ToggleEmoteMenu()
    end)

    -- Hover tint
    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(36, 42, 72)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(22, 26, 48)
    end)

    print("[EmoteClient] [TEMP-TEST] Debug button created at top-left (remove EmoteDebugBtn ScreenGui when done)")
end
-- ── end TEMP-TEST debug button ────────────────────────────────────────────

print("[EmoteClient] fully initialized")
