-- DevToolUI.client.lua
-- Standalone Studio-only "+10 COINS" button for quick testing.
-- This is completely independent of SideUI.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for the server-created remote (DevTools.server.lua creates it in Studio)
local addCoinsRemote = ReplicatedStorage:WaitForChild("RequestAddCoins", 10)
if not addCoinsRemote then
    warn("[DevToolUI] RequestAddCoins remote not found – is DevTools.server.lua present?")
    return
end

-- ── Build a small ScreenGui with a single button ──────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DevToolUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000 -- render above everything
gui.Parent = playerGui

local btn = Instance.new("TextButton")
btn.Name = "AddCoinsBtn"
btn.Size = UDim2.new(0, 130, 0, 36)
btn.Position = UDim2.new(0, 12, 1, -48)
btn.AnchorPoint = Vector2.new(0, 1)
btn.BackgroundColor3 = Color3.fromRGB(30, 120, 30)
btn.Font = Enum.Font.GothamBold
btn.Text = "+10 COINS"
btn.TextColor3 = Color3.fromRGB(255, 255, 80)
btn.TextSize = 16
btn.BorderSizePixel = 0
btn.AutoButtonColor = true
btn.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = btn

btn.MouseButton1Click:Connect(function()
    addCoinsRemote:FireServer(10)
    -- Brief visual feedback
    btn.Text = "✓ ADDED"
    task.delay(0.5, function()
        if btn and btn.Parent then btn.Text = "+10 COINS" end
    end)
end)

print("[DevToolUI] +10 COINS button ready (Studio only)")
