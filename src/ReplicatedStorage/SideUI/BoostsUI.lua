--------------------------------------------------------------------------------
-- BoostsUI.lua  –  Client-side Boosts panel
-- Place in ReplicatedStorage > SideUI alongside ShopUI.lua / DailyQuestsUI.lua
-- Loaded by SideUI.client.lua via the modal window system.
--
-- Shows purchasable boosts and active timers.
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / ShopUI / OptionsUI)
--------------------------------------------------------------------------------
local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

--------------------------------------------------------------------------------
-- Palette (matches SideUI neutral-gray / gold theme)
--------------------------------------------------------------------------------
local CARD_BG       = Color3.fromRGB(26, 30, 48)
local CARD_ACTIVE_BG= Color3.fromRGB(22, 38, 34)
local CARD_STROKE   = Color3.fromRGB(55, 62, 95)
local ICON_BG       = Color3.fromRGB(16, 18, 30)
local GOLD          = Color3.fromRGB(255, 215, 60)
local WHITE         = Color3.fromRGB(245, 245, 252)
local DIM_TEXT      = Color3.fromRGB(145, 150, 175)
local BTN_BG        = Color3.fromRGB(48, 55, 82)
local BTN_STROKE_C  = Color3.fromRGB(90, 100, 140)
local GREEN_BTN     = Color3.fromRGB(35, 190, 75)
local RED_TEXT      = Color3.fromRGB(255, 80, 80)
local ACTIVE_GLOW   = Color3.fromRGB(50, 230, 110)
local DISABLED_BG   = Color3.fromRGB(35, 38, 52)

local ACCENT_COLORS = {
    coins_2x     = Color3.fromRGB(255, 200, 40),
    quest_2x     = Color3.fromRGB(80, 165, 255),
}

local TWEEN_QUICK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- BoostConfig (shared)
--------------------------------------------------------------------------------
local BoostConfig
pcall(function()
    local mod = ReplicatedStorage:WaitForChild("BoostConfig", 10)
    if mod and mod:IsA("ModuleScript") then
        --------------------------------------------------------------------------------
        -- BoostsUI.lua  –  passive boost overview panel
        -- Purchase flow now lives in Shop > Boosts.
        -- Activation flow now lives in Inventory > Boosts.
        --------------------------------------------------------------------------------

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local RunService = game:GetService("RunService")

        local function px(base)
            local cam = workspace.CurrentCamera
            local screenY = 1080
            if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
                screenY = cam.ViewportSize.Y
            end
            return math.max(1, math.round(base * screenY / 1080))
        end

        local CARD_BG = Color3.fromRGB(26, 30, 48)
        local CARD_ACTIVE_BG = Color3.fromRGB(22, 38, 34)
        local CARD_STROKE = Color3.fromRGB(55, 62, 95)
        local GOLD = Color3.fromRGB(255, 215, 60)
        local WHITE = Color3.fromRGB(245, 245, 252)
        local DIM_TEXT = Color3.fromRGB(145, 150, 175)
        local GREEN_GLOW = Color3.fromRGB(50, 230, 110)

        local BoostsUI = {}

        local BoostConfig = nil
        local boostRemotes = nil

        local function safeRequireBoostConfig()
            local mod = ReplicatedStorage:FindFirstChild("BoostConfig")
            if mod and mod:IsA("ModuleScript") then
                local ok, result = pcall(function() return require(mod) end)
                if ok and type(result) == "table" then
                    return result
                end
            end
            return nil
        end

        local function ensureRemotes()
            if boostRemotes then return boostRemotes end

            local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
            if not remotesFolder then return nil end

            local boostsFolder = remotesFolder:FindFirstChild("Boosts") or remotesFolder:WaitForChild("Boosts", 5)
            if not boostsFolder then return nil end

            local getStatesRF = boostsFolder:FindFirstChild("GetBoostStates")
            local stateUpdatedRE = remotesFolder:FindFirstChild("BoostStateUpdated")
            if not getStatesRF or not stateUpdatedRE then
                return nil
            end

            boostRemotes = {
                getStates = getStatesRF,
                stateUpdated = stateUpdatedRE,
            }
            return boostRemotes
        end

        function BoostsUI.Create(parent, _coinApi, _inventoryApi)
            if not parent then return nil end

            for _, child in ipairs(parent:GetChildren()) do
                if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
                    pcall(function() child:Destroy() end)
                end
            end

            BoostConfig = BoostConfig or safeRequireBoostConfig()
            local remotes = ensureRemotes()

            local root = Instance.new("Frame")
            root.Name = "BoostsOverview"
            root.BackgroundTransparency = 1
            root.Size = UDim2.new(1, 0, 0, 0)
            root.AutomaticSize = Enum.AutomaticSize.Y
            root.LayoutOrder = 1
            root.Parent = parent

            local rootLayout = Instance.new("UIListLayout")
            rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
            rootLayout.Padding = UDim.new(0, px(12))
            rootLayout.Parent = root

            local rootPad = Instance.new("UIPadding")
            rootPad.PaddingTop = UDim.new(0, px(6))
            rootPad.PaddingBottom = UDim.new(0, px(16))
            rootPad.PaddingLeft = UDim.new(0, px(8))
            rootPad.PaddingRight = UDim.new(0, px(8))
            rootPad.Parent = root

            local headerWrap = Instance.new("Frame")
            headerWrap.BackgroundTransparency = 1
            headerWrap.Size = UDim2.new(1, 0, 0, px(54))
            headerWrap.LayoutOrder = 1
            headerWrap.Parent = root

            local header = Instance.new("TextLabel")
            header.BackgroundTransparency = 1
            header.Font = Enum.Font.GothamBold
            header.Text = "BOOSTS"
            header.TextColor3 = GOLD
            header.TextSize = math.max(20, math.floor(px(24)))
            header.TextXAlignment = Enum.TextXAlignment.Left
            header.Size = UDim2.new(1, 0, 0, px(30))
            header.Parent = headerWrap

            local subHeader = Instance.new("TextLabel")
            subHeader.BackgroundTransparency = 1
            subHeader.Font = Enum.Font.GothamMedium
            subHeader.Text = "Boost purchases moved to Shop > Boosts. Activate owned boosts from Inventory > Boosts."
            subHeader.TextColor3 = DIM_TEXT
            subHeader.TextSize = math.max(11, math.floor(px(12)))
            subHeader.TextXAlignment = Enum.TextXAlignment.Left
            subHeader.Size = UDim2.new(1, 0, 0, px(16))
            subHeader.Position = UDim2.new(0, 0, 0, px(30))
            subHeader.Parent = headerWrap

            local accentBar = Instance.new("Frame")
            accentBar.BackgroundColor3 = GOLD
            accentBar.BackgroundTransparency = 0.3
            accentBar.BorderSizePixel = 0
            accentBar.Size = UDim2.new(1, 0, 0, px(2))
            accentBar.Position = UDim2.new(0, 0, 1, -px(2))
            accentBar.Parent = headerWrap

            local helper = Instance.new("TextLabel")
            helper.BackgroundTransparency = 1
            helper.Font = Enum.Font.GothamMedium
            helper.Text = "This screen is now informational so the old immediate-activation purchase path stays disabled."
            helper.TextColor3 = DIM_TEXT
            helper.TextSize = math.max(10, math.floor(px(11)))
            helper.TextXAlignment = Enum.TextXAlignment.Left
            helper.Size = UDim2.new(1, 0, 0, px(14))
            helper.LayoutOrder = 2
            helper.Parent = root

            if not BoostConfig or not remotes then
                local unavailable = Instance.new("TextLabel")
                unavailable.BackgroundTransparency = 1
                unavailable.Font = Enum.Font.GothamMedium
                unavailable.Text = "Boost overview unavailable."
                unavailable.TextColor3 = DIM_TEXT
                unavailable.TextSize = math.max(14, math.floor(px(15)))
                unavailable.Size = UDim2.new(1, 0, 0, px(50))
                unavailable.LayoutOrder = 10
                unavailable.Parent = root
                return root
            end

            local cleanupConnections = {}
            local function trackConn(conn)
                table.insert(cleanupConnections, conn)
            end
            local function cleanup()
                for _, conn in ipairs(cleanupConnections) do
                    pcall(function() conn:Disconnect() end)
                end
                table.clear(cleanupConnections)
            end

            local boostDefs = {}
            for _, def in ipairs(BoostConfig.Boosts) do
                if not def.InstantUse then
                    table.insert(boostDefs, def)
                end
            end
            table.sort(boostDefs, function(a, b)
                return (a.SortOrder or 0) < (b.SortOrder or 0)
            end)

            local boostStates = {}
            local timeDelta = 0
            local cards = {}

            local function ingestStates(states)
                if type(states) ~= "table" then return end
                boostStates = states
                timeDelta = os.time() - (states._serverTime or os.time())
            end

            pcall(function()
                ingestStates(remotes.getStates:InvokeServer())
            end)

            local function refreshCards()
                for _, def in ipairs(boostDefs) do
                    local refs = cards[def.Id]
                    local state = boostStates[def.Id] or {}
                    if refs then
                        local owned = math.max(0, math.floor(tonumber(state.owned) or 0))
                        local expiresAt = math.floor(tonumber(state.expiresAt) or 0) + timeDelta
                        local active = expiresAt > os.time()

                        refs.card.BackgroundColor3 = active and CARD_ACTIVE_BG or CARD_BG
                        refs.stroke.Color = active and GREEN_GLOW or CARD_STROKE
                        refs.owned.Text = string.format("Owned: %d", owned)

                        if active then
                            local remaining = math.max(0, expiresAt - os.time())
                            refs.status.Text = string.format("Active • %02d:%02d remaining", math.floor(remaining / 60), remaining % 60)
                            refs.status.TextColor3 = GREEN_GLOW
                        elseif owned > 0 then
                            refs.status.Text = "Stored in inventory - activate from Inventory > Boosts"
                            refs.status.TextColor3 = WHITE
                        else
                            refs.status.Text = "Buy from Shop > Boosts"
                            refs.status.TextColor3 = DIM_TEXT
                        end
                    end
                end
            end

            for index, def in ipairs(boostDefs) do
                local card = Instance.new("Frame")
                card.Name = "Boost_" .. def.Id
                card.BackgroundColor3 = CARD_BG
                card.Size = UDim2.new(1, 0, 0, px(118))
                card.LayoutOrder = 10 + index
                card.Parent = root

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, px(12))
                corner.Parent = card

                local stroke = Instance.new("UIStroke")
                stroke.Color = CARD_STROKE
                stroke.Thickness = 1.2
                stroke.Transparency = 0.35
                stroke.Parent = card

                local pad = Instance.new("UIPadding")
                pad.PaddingTop = UDim.new(0, px(12))
                pad.PaddingBottom = UDim.new(0, px(12))
                pad.PaddingLeft = UDim.new(0, px(14))
                pad.PaddingRight = UDim.new(0, px(14))
                pad.Parent = card

                local title = Instance.new("TextLabel")
                title.BackgroundTransparency = 1
                title.Font = Enum.Font.GothamBold
                title.Text = def.DisplayName
                title.TextColor3 = WHITE
                title.TextSize = math.max(16, math.floor(px(18)))
                title.TextXAlignment = Enum.TextXAlignment.Left
                title.Size = UDim2.new(0.58, 0, 0, px(24))
                title.Parent = card

                local desc = Instance.new("TextLabel")
                desc.BackgroundTransparency = 1
                desc.Font = Enum.Font.GothamMedium
                desc.Text = def.Description
                desc.TextColor3 = DIM_TEXT
                desc.TextSize = math.max(11, math.floor(px(12)))
                desc.TextWrapped = true
                desc.TextXAlignment = Enum.TextXAlignment.Left
                desc.TextYAlignment = Enum.TextYAlignment.Top
                desc.Size = UDim2.new(0.64, 0, 0, px(42))
                desc.Position = UDim2.new(0, 0, 0, px(28))
                desc.Parent = card

                local owned = Instance.new("TextLabel")
                owned.BackgroundTransparency = 1
                owned.Font = Enum.Font.GothamBold
                owned.Text = "Owned: 0"
                owned.TextColor3 = WHITE
                owned.TextSize = math.max(11, math.floor(px(12)))
                owned.TextXAlignment = Enum.TextXAlignment.Right
                owned.Size = UDim2.new(0.34, 0, 0, px(18))
                owned.Position = UDim2.new(0.66, 0, 0, px(12))
                owned.Parent = card

                local status = Instance.new("TextLabel")
                status.BackgroundTransparency = 1
                status.Font = Enum.Font.GothamMedium
                status.Text = "Buy from Shop > Boosts"
                status.TextColor3 = DIM_TEXT
                status.TextSize = math.max(10, math.floor(px(11)))
                status.TextWrapped = true
                status.TextXAlignment = Enum.TextXAlignment.Right
                status.TextYAlignment = Enum.TextYAlignment.Top
                status.Size = UDim2.new(0.34, 0, 0, px(38))
                status.Position = UDim2.new(0.66, 0, 0, px(34))
                status.Parent = card

                local route = Instance.new("TextLabel")
                route.BackgroundTransparency = 1
                route.Font = Enum.Font.GothamBold
                route.Text = "Shop to buy • Inventory to use"
                route.TextColor3 = GOLD
                route.TextSize = math.max(10, math.floor(px(11)))
                route.TextXAlignment = Enum.TextXAlignment.Left
                route.Size = UDim2.new(0.64, 0, 0, px(16))
                route.Position = UDim2.new(0, 0, 1, -px(18))
                route.Parent = card

                cards[def.Id] = {
                    card = card,
                    stroke = stroke,
                    owned = owned,
                    status = status,
                }
            end

            refreshCards()

            trackConn(remotes.stateUpdated.OnClientEvent:Connect(function(states)
                ingestStates(states)
                refreshCards()
            end))

            local lastTick = 0
            trackConn(RunService.Heartbeat:Connect(function()
                local now = os.time()
                if now == lastTick then return end
                lastTick = now
                refreshCards()
            end))

            trackConn(root.AncestryChanged:Connect(function(_, newParent)
                if not newParent then
                    cleanup()
                end
            end))

            return root
        end

        return BoostsUI

