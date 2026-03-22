-- DevToolUI.client.lua
-- Standalone Studio-only "+10 COINS" button for quick testing.
-- Completely independent of SideUI — errors here never affect other HUD.
--
-- The server creates ReplicatedStorage.Remotes.RequestAddCoins at startup.
-- We build the button immediately (so it's always visible) and resolve
-- the remote asynchronously.  Once found, the button activates.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Build the button immediately so it always appears ─────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DevToolUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = playerGui

local GREEN  = Color3.fromRGB(30, 120, 30)
local GRAY   = Color3.fromRGB(80, 80, 80)

local btn = Instance.new("TextButton")
btn.Name = "AddCoinsBtn"
btn.Size = UDim2.new(0, 130, 0, 36)
btn.Position = UDim2.new(0, 12, 1, -48)
btn.AnchorPoint = Vector2.new(0, 1)
btn.BackgroundColor3 = GRAY
btn.Font = Enum.Font.GothamBold
btn.Text = "+10 (WAITING…)"
btn.TextColor3 = Color3.fromRGB(255, 255, 80)
btn.TextSize = 16
btn.BorderSizePixel = 0
btn.AutoButtonColor = true
btn.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = btn

-- ── Resolve the remote asynchronously ─────────────────────────────────────
local addCoinsRemote = nil   -- set once found

local function enableButton()
    addCoinsRemote = ReplicatedStorage
        :WaitForChild("Remotes", 15)
    if addCoinsRemote then
        addCoinsRemote = addCoinsRemote:WaitForChild("RequestAddCoins", 15)
    end
    if addCoinsRemote then
        btn.BackgroundColor3 = GREEN
        btn.Text = "+10 COINS"
        print("[DevToolUI] Remote found:", addCoinsRemote:GetFullName())
    else
        btn.BackgroundColor3 = GRAY
        btn.Text = "+10 (NO REMOTE)"
        warn("[DevToolUI] RequestAddCoins not found after waiting."
            .. " Is DevTools.server.lua in ServerScriptService?")
    end
end

-- Run in a separate thread so the button appears instantly
task.spawn(enableButton)

-- ── Click handler ─────────────────────────────────────────────────────────
btn.MouseButton1Click:Connect(function()
    if not addCoinsRemote then return end
    addCoinsRemote:FireServer(10)
    btn.Text = "✓ ADDED"
    task.delay(0.5, function()
        if btn and btn.Parent then btn.Text = "+10 COINS" end
    end)
end)

print("[DevToolUI] Button created (Studio only); waiting for remote…")

--------------------------------------------------------------------------------
-- PREMIUM CRATE / KEY SYSTEM  – "+5 KEYS" dev button
-- TO REMOVE LATER: delete this entire section.
--------------------------------------------------------------------------------
local KEY_GREEN = Color3.fromRGB(30, 80, 130)

local keyBtn = Instance.new("TextButton")
keyBtn.Name = "AddKeysBtn"
keyBtn.Size = UDim2.new(0, 130, 0, 36)
keyBtn.Position = UDim2.new(0, 12, 1, -90)
keyBtn.AnchorPoint = Vector2.new(0, 1)
keyBtn.BackgroundColor3 = GRAY
keyBtn.Font = Enum.Font.GothamBold
keyBtn.Text = "+5 KEYS (WAIT…)"
keyBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
keyBtn.TextSize = 16
keyBtn.BorderSizePixel = 0
keyBtn.AutoButtonColor = true
keyBtn.Parent = gui

local keyCorner = Instance.new("UICorner")
keyCorner.CornerRadius = UDim.new(0, 8)
keyCorner.Parent = keyBtn

local addKeysRemote = nil
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
    if remotes then
        addKeysRemote = remotes:WaitForChild("RequestAddKeys", 15)
    end
    if addKeysRemote then
        keyBtn.BackgroundColor3 = KEY_GREEN
        keyBtn.Text = "+5 KEYS"
        print("[DevToolUI] PREMIUM CRATE / KEY SYSTEM – RequestAddKeys found")
    else
        keyBtn.BackgroundColor3 = GRAY
        keyBtn.Text = "+5 KEYS (NO REMOTE)"
        warn("[DevToolUI] RequestAddKeys not found")
    end
end)

keyBtn.MouseButton1Click:Connect(function()
    if not addKeysRemote then return end
    addKeysRemote:FireServer(5)
    keyBtn.Text = "\u{2713} ADDED"
    task.delay(0.5, function()
        if keyBtn and keyBtn.Parent then keyBtn.Text = "+5 KEYS" end
    end)
end)

print("[DevToolUI] PREMIUM CRATE / KEY SYSTEM – Key button created")
