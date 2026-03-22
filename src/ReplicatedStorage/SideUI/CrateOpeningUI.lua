--------------------------------------------------------------------------------
-- CrateOpeningUI.lua  –  Full-screen crate-opening roulette animation
--
-- Shows a horizontal strip of weapon cards scrolling past a center marker,
-- decelerating to land on the won weapon. Rarity-colored glow on reveal.
--
-- Usage: require and call CrateOpeningUI.Init(playerGui) once on client,
-- then set _G.OpenCrateRequested = function(crateId) ... end from ShopUI.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local DEBUG_CRATE = false -- set true to print layout diagnostics

local CrateConfig = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
    if mod and mod:IsA("ModuleScript") then
        CrateConfig = require(mod)
    end
end)

local AssetCodes = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        AssetCodes = require(mod)
    end
end)

local CrateOpeningUI = {}

local function px(base)
    local cam = workspace.CurrentCamera
    local screenY = 1080
    if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
        screenY = cam.ViewportSize.Y
    end
    return math.max(1, math.round(base * screenY / 1080))
end

-- Colors
local GOLD      = Color3.fromRGB(255, 215, 80)
local WHITE     = Color3.fromRGB(255, 255, 255)
local DIM_TEXT  = Color3.fromRGB(140, 140, 160)
local CARD_BG   = Color3.fromRGB(26, 30, 48)
local OVERLAY_C = Color3.fromRGB(10, 10, 26)

local CARD_W = 160  -- base card width
local CARD_H = 200  -- base card height
local CARD_GAP = 10  -- gap between cards
local STRIP_CARDS = 40  -- total cards in the roulette strip
local WINNING_INDEX = 30 -- card index where the winner is placed (near end for nice decel)

--------------------------------------------------------------------------------
-- Get rarity color
--------------------------------------------------------------------------------
local function rarityColor(rarity)
    if CrateConfig and CrateConfig.Rarities and CrateConfig.Rarities[rarity] then
        return CrateConfig.Rarities[rarity].color
    end
    return DIM_TEXT
end

--------------------------------------------------------------------------------
-- Build a randomized strip of weapon cards with the winner at WINNING_INDEX.
-- Cards are chosen using weighted rarity selection so the visual strip
-- reflects actual drop rates from CrateConfig.
-- PREMIUM CRATE / KEY SYSTEM  – uses per-crate rarities table if present.
--------------------------------------------------------------------------------
local function buildStrip(crateDef, wonWeapon, wonRarity)
    local pool = crateDef.pool or {}
    if #pool == 0 then return {} end

    -- Group weapons by rarity
    local byRarity = {}
    for _, entry in ipairs(pool) do
        if not byRarity[entry.rarity] then
            byRarity[entry.rarity] = {}
        end
        table.insert(byRarity[entry.rarity], entry.weapon)
    end

    -- Build weighted rarity list
    -- PREMIUM CRATE / KEY SYSTEM  – prefer per-crate rarities over global weights
    local hasCrateRarities = (type(crateDef.rarities) == "table")
    local weightedRarities = {}
    local totalWeight = 0

    for rarity, weapons in pairs(byRarity) do
        local w = 0
        if hasCrateRarities and crateDef.rarities[rarity] then
            w = crateDef.rarities[rarity]
        elseif CrateConfig and CrateConfig.Rarities then
            local def = CrateConfig.Rarities[rarity]
            w = (def and def.weight) or 0
        end
        if w > 0 and #weapons > 0 then
            totalWeight = totalWeight + w
            table.insert(weightedRarities, { rarity = rarity, cumWeight = totalWeight })
        end
    end

    -- Fallback: if no valid weights, pick uniformly from pool
    local function pickWeighted()
        if totalWeight <= 0 or #weightedRarities == 0 then
            local p = pool[math.random(1, #pool)]
            return p.weapon, p.rarity
        end
        local roll = math.random() * totalWeight
        for _, entry in ipairs(weightedRarities) do
            if roll <= entry.cumWeight then
                local weapons = byRarity[entry.rarity]
                return weapons[math.random(1, #weapons)], entry.rarity
            end
        end
        -- Shouldn't reach here, but fallback to last rarity
        local last = weightedRarities[#weightedRarities]
        local weapons = byRarity[last.rarity]
        return weapons[math.random(1, #weapons)], last.rarity
    end

    local strip = {}
    for i = 1, STRIP_CARDS do
        if i == WINNING_INDEX then
            table.insert(strip, { weapon = wonWeapon, rarity = wonRarity, isWinner = true })
        else
            local wep, rar = pickWeighted()
            table.insert(strip, { weapon = wep, rarity = rar, isWinner = false })
        end
    end
    return strip
end

--------------------------------------------------------------------------------
-- INIT  –  create persistent overlay (hidden) in PlayerGui
--------------------------------------------------------------------------------
function CrateOpeningUI.Init(playerGui)
    if not playerGui then return end

    -- ScreenGui
    local screen = Instance.new("ScreenGui")
    screen.Name = "CrateOpenScreen"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 500
    screen.IgnoreGuiInset = true
    screen.Enabled = false
    screen.Parent = playerGui

    -- Dark overlay
    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.BackgroundColor3 = OVERLAY_C
    overlay.BackgroundTransparency = 0.25
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.ZIndex = 1
    overlay.Parent = screen

    -- Center marker (thin vertical line)
    local marker = Instance.new("Frame")
    marker.Name = "CenterMarker"
    marker.BackgroundColor3 = GOLD
    marker.BorderSizePixel = 0
    marker.Size = UDim2.new(0, px(3), 0, px(CARD_H + 40))
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.Position = UDim2.new(0.5, 0, 0.5, 0)
    marker.ZIndex = 10
    marker.Parent = screen

    local markerGlow = Instance.new("UIStroke")
    markerGlow.Color = GOLD
    markerGlow.Thickness = 2
    markerGlow.Transparency = 0.4
    markerGlow.Parent = marker

    -- Scroll container (clips the strip)
    local scrollClip = Instance.new("Frame")
    scrollClip.Name = "ScrollClip"
    scrollClip.BackgroundTransparency = 1
    scrollClip.ClipsDescendants = true
    scrollClip.Size = UDim2.new(1, 0, 0, px(CARD_H + 30))
    scrollClip.AnchorPoint = Vector2.new(0.5, 0.5)
    scrollClip.Position = UDim2.new(0.5, 0, 0.5, 0)
    scrollClip.ZIndex = 5
    scrollClip.Parent = screen

    -- Strip frame (will be shifted left via Position)
    local strip = Instance.new("Frame")
    strip.Name = "Strip"
    strip.BackgroundTransparency = 1
    strip.Size = UDim2.new(0, 0, 1, 0) -- width set dynamically
    strip.Position = UDim2.new(0, 0, 0, 0)
    strip.ZIndex = 6
    strip.Parent = scrollClip

    -- Result overlay (shown after spin)
    local resultFrame = Instance.new("Frame")
    resultFrame.Name = "ResultFrame"
    resultFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 32)
    resultFrame.BackgroundTransparency = 0.06
    resultFrame.Size = UDim2.new(0, px(360), 0, px(360))
    resultFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    resultFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    resultFrame.Visible = false
    resultFrame.ZIndex = 20
    resultFrame.Parent = screen

    local rfCorner = Instance.new("UICorner")
    rfCorner.CornerRadius = UDim.new(0, px(16))
    rfCorner.Parent = resultFrame

    local rfStroke = Instance.new("UIStroke")
    rfStroke.Color = GOLD
    rfStroke.Thickness = 2
    rfStroke.Transparency = 0.2
    rfStroke.Parent = resultFrame

    local resultTitle = Instance.new("TextLabel")
    resultTitle.Name = "Title"
    resultTitle.BackgroundTransparency = 1
    resultTitle.Font = Enum.Font.GothamBold
    resultTitle.Text = "YOU GOT"
    resultTitle.TextColor3 = DIM_TEXT
    resultTitle.TextSize = math.max(14, math.floor(px(16)))
    resultTitle.Size = UDim2.new(1, 0, 0, px(24))
    resultTitle.Position = UDim2.new(0, 0, 0, px(14))
    resultTitle.TextXAlignment = Enum.TextXAlignment.Center
    resultTitle.ZIndex = 21
    resultTitle.Parent = resultFrame

    local resultImage = Instance.new("ImageLabel")
    resultImage.Name = "WeaponImage"
    resultImage.BackgroundTransparency = 1
    resultImage.Size = UDim2.new(0, px(100), 0, px(100))
    resultImage.AnchorPoint = Vector2.new(0.5, 0)
    resultImage.Position = UDim2.new(0.5, 0, 0, px(42))
    resultImage.ScaleType = Enum.ScaleType.Fit
    resultImage.ZIndex = 21
    resultImage.Parent = resultFrame

    local resultName = Instance.new("TextLabel")
    resultName.Name = "WeaponName"
    resultName.BackgroundTransparency = 1
    resultName.Font = Enum.Font.GothamBold
    resultName.Text = "?"
    resultName.TextColor3 = WHITE
    resultName.TextSize = math.max(24, math.floor(px(28)))
    resultName.TextWrapped = true
    resultName.Size = UDim2.new(1, 0, 0, px(36))
    resultName.Position = UDim2.new(0, 0, 0, px(150))
    resultName.TextXAlignment = Enum.TextXAlignment.Center
    resultName.ZIndex = 21
    resultName.Parent = resultFrame

    local resultRarity = Instance.new("TextLabel")
    resultRarity.Name = "Rarity"
    resultRarity.BackgroundTransparency = 1
    resultRarity.Font = Enum.Font.GothamBold
    resultRarity.Text = "Common"
    resultRarity.TextColor3 = DIM_TEXT
    resultRarity.TextSize = math.max(14, math.floor(px(16)))
    resultRarity.Size = UDim2.new(1, 0, 0, px(22))
    resultRarity.Position = UDim2.new(0, 0, 0, px(192))
    resultRarity.TextXAlignment = Enum.TextXAlignment.Center
    resultRarity.ZIndex = 21
    resultRarity.Parent = resultFrame

    -- SIZE ROLL SYSTEM — shows the exact rolled size percentage below rarity
    local resultSizeLabel = Instance.new("TextLabel")
    resultSizeLabel.Name = "SizePercent"
    resultSizeLabel.BackgroundTransparency = 1
    resultSizeLabel.Font = Enum.Font.GothamBold
    resultSizeLabel.Text = ""
    resultSizeLabel.TextColor3 = GOLD
    resultSizeLabel.TextSize = math.max(18, math.floor(px(22)))
    resultSizeLabel.Size = UDim2.new(1, 0, 0, px(26))
    resultSizeLabel.Position = UDim2.new(0, 0, 0, px(218))
    resultSizeLabel.TextXAlignment = Enum.TextXAlignment.Center
    resultSizeLabel.ZIndex = 21
    resultSizeLabel.Parent = resultFrame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.BackgroundColor3 = Color3.fromRGB(48, 55, 82)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "CLOSE"
    closeBtn.TextColor3 = WHITE
    closeBtn.TextSize = math.max(14, math.floor(px(16)))
    closeBtn.Size = UDim2.new(0, px(140), 0, px(40))
    closeBtn.AnchorPoint = Vector2.new(0.5, 1)
    closeBtn.Position = UDim2.new(0.5, 0, 1, -px(16))
    closeBtn.AutoButtonColor = false
    closeBtn.ZIndex = 22
    closeBtn.Parent = resultFrame

    local cbCorner = Instance.new("UICorner")
    cbCorner.CornerRadius = UDim.new(0, px(10))
    cbCorner.Parent = closeBtn

    local isAnimating = false
    local activeTween = nil           -- current spin tween (cancelled on re-play)
    local completedConn = nil         -- tween.Completed connection

    ---------------------------------------------------------------------------
    -- Wait until Roblox layout engine has fully resolved sizes for the strip.
    -- Returns true when stable, false on timeout.
    ---------------------------------------------------------------------------
    local function waitForStableLayout(expectedCardCount, timeoutSec)
        timeoutSec = timeoutSec or 2
        local elapsed = 0
        local stableFrames = 0
        local lastClipW, lastStripW = 0, 0

        while elapsed < timeoutSec do
            RunService.Heartbeat:Wait()
            elapsed += 1 / 60 -- approximate

            local clipW  = scrollClip.AbsoluteSize.X
            local stripW = strip.AbsoluteSize.X
            if clipW <= 0 or stripW <= 0 then
                stableFrames = 0
                lastClipW, lastStripW = clipW, stripW
                continue
            end

            -- Check all card frames exist and have size
            local cards = {}
            local allReady = true
            for _, child in ipairs(strip:GetChildren()) do
                if child:IsA("Frame") and child.Name:match("^Card_") then
                    table.insert(cards, child)
                    if child.AbsoluteSize.X <= 0 then
                        allReady = false
                    end
                end
            end
            if #cards < expectedCardCount or not allReady then
                stableFrames = 0
                lastClipW, lastStripW = clipW, stripW
                continue
            end

            -- Values unchanged from last frame?
            if clipW == lastClipW and stripW == lastStripW then
                stableFrames += 1
            else
                stableFrames = 0
            end
            lastClipW, lastStripW = clipW, stripW

            if stableFrames >= 2 then
                return true
            end
        end
        warn("[CrateOpeningUI] waitForStableLayout timed out")
        return false
    end

    ---------------------------------------------------------------------------
    -- Close handler
    ---------------------------------------------------------------------------
    local function closeOverlay()
        screen.Enabled = false
        resultFrame.Visible = false
        -- Clear strip children
        for _, c in ipairs(strip:GetChildren()) do
            pcall(function() c:Destroy() end)
        end
    end

    closeBtn.MouseButton1Click:Connect(closeOverlay)

    ---------------------------------------------------------------------------
    -- Create a card frame for the strip
    ---------------------------------------------------------------------------
    local function makeStripCard(data, index)
        local cw = px(CARD_W)
        local ch = px(CARD_H)
        local gap = px(CARD_GAP)

        local card = Instance.new("Frame")
        card.Name = "Card_" .. index
        card.BackgroundColor3 = CARD_BG
        card.Size = UDim2.new(0, cw, 0, ch)
        card.Position = UDim2.new(0, (index - 1) * (cw + gap), 0.5, 0)
        card.AnchorPoint = Vector2.new(0, 0.5)
        card.ZIndex = 7
        card.Parent = strip

        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(0, px(10))
        cc.Parent = card

        local cs = Instance.new("UIStroke")
        cs.Color = rarityColor(data.rarity)
        cs.Thickness = data.isWinner and 2 or 1.2
        cs.Transparency = 0.3
        cs.Parent = card

        -- Rarity bar at top
        local bar = Instance.new("Frame")
        bar.BackgroundColor3 = rarityColor(data.rarity)
        bar.BackgroundTransparency = 0.3
        bar.Size = UDim2.new(1, 0, 0, px(4))
        bar.Position = UDim2.new(0, 0, 0, 0)
        bar.BorderSizePixel = 0
        bar.ZIndex = 8
        bar.Parent = card
        local barCr = Instance.new("UICorner")
        barCr.CornerRadius = UDim.new(0, px(4))
        barCr.Parent = bar

        -- Weapon image
        local thumb = Instance.new("ImageLabel")
        thumb.Name = "Thumb"
        thumb.BackgroundTransparency = 1
        thumb.Size = UDim2.new(0.6, 0, 0.45, 0)
        thumb.AnchorPoint = Vector2.new(0.5, 0)
        thumb.Position = UDim2.new(0.5, 0, 0, px(12))
        thumb.ScaleType = Enum.ScaleType.Fit
        thumb.ZIndex = 8
        thumb.Parent = card
        pcall(function()
            if AssetCodes and type(AssetCodes.Get) == "function" then
                local img = AssetCodes.Get(data.weapon)
                if img and #img > 0 then thumb.Image = img end
            end
        end)

        -- Weapon name (below image, wraps)
        local wname = Instance.new("TextLabel")
        wname.BackgroundTransparency = 1
        wname.Font = Enum.Font.GothamBold
        wname.Text = data.weapon
        wname.TextColor3 = WHITE
        wname.TextSize = math.max(11, math.floor(px(13)))
        wname.TextWrapped = true
        wname.Size = UDim2.new(0.9, 0, 0, px(34))
        wname.AnchorPoint = Vector2.new(0.5, 0)
        wname.Position = UDim2.new(0.5, 0, 0.58, 0)
        wname.TextXAlignment = Enum.TextXAlignment.Center
        wname.TextYAlignment = Enum.TextYAlignment.Top
        wname.ZIndex = 8
        wname.Parent = card

        -- Rarity label
        local rlbl = Instance.new("TextLabel")
        rlbl.BackgroundTransparency = 1
        rlbl.Font = Enum.Font.GothamBold
        rlbl.Text = data.rarity
        rlbl.TextColor3 = rarityColor(data.rarity)
        rlbl.TextSize = math.max(10, math.floor(px(11)))
        rlbl.Size = UDim2.new(1, 0, 0, px(16))
        rlbl.AnchorPoint = Vector2.new(0.5, 1)
        rlbl.Position = UDim2.new(0.5, 0, 1, -px(6))
        rlbl.TextXAlignment = Enum.TextXAlignment.Center
        rlbl.ZIndex = 8
        rlbl.Parent = card

        return card
    end

    ---------------------------------------------------------------------------
    -- PLAY ANIMATION
    -- Called with the server result after the server confirms the crate open.
    ---------------------------------------------------------------------------
    function CrateOpeningUI.Play(crateId, resultData, coinApi)
        if isAnimating then return end
        isAnimating = true

        local crateDef = CrateConfig and CrateConfig.Crates[crateId]
        if not crateDef then
            isAnimating = false
            return
        end

        -- Build strip data
        local stripData = buildStrip(crateDef, resultData.weaponName, resultData.rarity)
        if #stripData == 0 then
            isAnimating = false
            return
        end

        -- Cancel any prior tween / disconnect old completion handler
        if activeTween then
            pcall(function() activeTween:Cancel() end)
            activeTween = nil
        end
        if completedConn then
            pcall(function() completedConn:Disconnect() end)
            completedConn = nil
        end

        -- Clear old cards
        for _, c in ipairs(strip:GetChildren()) do
            pcall(function() c:Destroy() end)
        end
        resultFrame.Visible = false

        -- Calculate sizes
        local cw = px(CARD_W)
        local gap = px(CARD_GAP)
        local totalWidth = #stripData * (cw + gap) - gap
        strip.Size = UDim2.new(0, totalWidth, 1, 0)

        -- Create card UI elements; keep ordered references
        local cardFrames = {}
        for i, data in ipairs(stripData) do
            cardFrames[i] = makeStripCard(data, i)
        end
        local winnerCard = cardFrames[WINNING_INDEX]

        -- Park strip off-screen to the right (rough estimate before layout)
        local roughScreenW = workspace.CurrentCamera.ViewportSize.X
        strip.Position = UDim2.new(0, roughScreenW, 0, 0)

        -- Show overlay
        screen.Enabled = true

        -- Wait for the layout engine to fully resolve
        waitForStableLayout(#stripData)

        -- Compute target using actual absolute positions
        local markerCenterX = marker.AbsolutePosition.X + marker.AbsoluteSize.X / 2
        local winnerCenterX = winnerCard.AbsolutePosition.X + winnerCard.AbsoluteSize.X / 2
        local currentOffset = strip.Position.X.Offset
        local delta = winnerCenterX - markerCenterX
        local targetOffset = currentOffset - delta

        if DEBUG_CRATE then
            print("[CrateDebug] scrollClip.AbsoluteSize.X =", scrollClip.AbsoluteSize.X)
            print("[CrateDebug] strip.AbsoluteSize.X      =", strip.AbsoluteSize.X)
            print("[CrateDebug] winnerCard.AbsPos / Size   =", winnerCard.AbsolutePosition, winnerCard.AbsoluteSize)
            print("[CrateDebug] marker.AbsPos / Size       =", marker.AbsolutePosition, marker.AbsoluteSize)
            print("[CrateDebug] currentOffset =", currentOffset, "delta =", delta, "targetOffset =", targetOffset)
        end

        -- Set the real start position (strip scrolls in from right)
        local screenW = scrollClip.AbsoluteSize.X
        if screenW <= 0 then screenW = roughScreenW end
        local startOffset = screenW / 2
        strip.Position = UDim2.new(0, startOffset, 0, 0)

        -- Recalculate target from the real start position using the same delta
        -- (we just moved the strip, so re-derive target relative to the new start)
        waitForStableLayout(#stripData)
        local winnerCenterX2 = winnerCard.AbsolutePosition.X + winnerCard.AbsoluteSize.X / 2
        local delta2 = winnerCenterX2 - markerCenterX
        targetOffset = startOffset - delta2

        if DEBUG_CRATE then
            print("[CrateDebug] after reposition: startOffset =", startOffset, "delta2 =", delta2, "targetOffset =", targetOffset)
        end

        -- Locate tick sound in ReplicatedStorage.Sounds
        local tickSound = nil
        pcall(function()
            local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
            if soundsFolder then
                tickSound = soundsFolder:FindFirstChild("Tick")
            end
        end)

        -- Animate: ease-out quint for deceleration feel
        local spinDuration = 3.5
        local tweenInfo = TweenInfo.new(spinDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        activeTween = TweenService:Create(strip, tweenInfo, {
            Position = UDim2.new(0, targetOffset, 0, 0)
        })

        -- Per-frame tick: play sound each time a new card crosses the center marker
        local lastCardIndex = -1
        local tickConn = nil
        local cardStep = px(CARD_W) + px(CARD_GAP)
        tickConn = RunService.Heartbeat:Connect(function()
            local currentOffset2 = strip.Position.X.Offset
            -- How far the strip has scrolled left from start
            local scrolled = startOffset - currentOffset2
            -- markerCenterX is at screen center; cards start at scrollClip left edge + strip offset
            -- Determine which card index is currently under the marker
            local markerLocal = markerCenterX - scrollClip.AbsolutePosition.X - currentOffset2
            local idx = math.floor(markerLocal / cardStep) + 1
            if idx ~= lastCardIndex and idx >= 1 and idx <= STRIP_CARDS then
                lastCardIndex = idx
                if tickSound and tickSound:IsA("Sound") then
                    local s = tickSound:Clone()
                    s.Parent = tickSound.Parent
                    s:Play()
                    -- Clean up after playing
                    s.Ended:Once(function()
                        pcall(function() s:Destroy() end)
                    end)
                end
            end
        end)

        activeTween:Play()

        completedConn = activeTween.Completed:Once(function()
            -- Disconnect tick listener
            if tickConn then
                tickConn:Disconnect()
                tickConn = nil
            end
            activeTween = nil
            completedConn = nil

            -- Brief pause then show result
            task.wait(0.4)

            -- Update result frame
            local rc = rarityColor(resultData.rarity)
            resultName.Text = resultData.weaponName
            resultName.TextColor3 = WHITE
            resultRarity.Text = resultData.rarity
            resultRarity.TextColor3 = rc
            rfStroke.Color = rc

            -- SIZE ROLL SYSTEM — display exact rolled size percentage
            if resultData.sizePercent and resultData.sizePercent ~= 100 then
                resultSizeLabel.Text = tostring(math.floor(resultData.sizePercent)) .. "%"
                -- Tint King/Giant sizes gold, others white
                if resultData.sizeTier == "King" or resultData.sizeTier == "Giant" then
                    resultSizeLabel.TextColor3 = GOLD
                else
                    resultSizeLabel.TextColor3 = WHITE
                end
            elseif resultData.sizePercent then
                resultSizeLabel.Text = tostring(math.floor(resultData.sizePercent)) .. "%"
                resultSizeLabel.TextColor3 = DIM_TEXT
            else
                resultSizeLabel.Text = ""
            end

            -- Set weapon image
            resultImage.Image = ""
            pcall(function()
                if AssetCodes and type(AssetCodes.Get) == "function" then
                    local img = AssetCodes.Get(resultData.weaponName)
                    if img and #img > 0 then resultImage.Image = img end
                end
            end)

            -- Fade in result
            resultFrame.Visible = true
            resultFrame.BackgroundTransparency = 1
            TweenService:Create(resultFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.06}):Play()

            -- Update coins
            if coinApi and coinApi.SetCoins and resultData.newBalance then
                pcall(function() coinApi.SetCoins(resultData.newBalance) end)
            end
            -- PREMIUM CRATE / KEY SYSTEM  – update keys display
            if coinApi and coinApi.SetKeys and resultData.newKeyBalance then
                pcall(function() coinApi.SetKeys(resultData.newKeyBalance) end)
            end
            pcall(function()
                if _G.UpdateShopHeaderCoins then _G.UpdateShopHeaderCoins() end
            end)

            isAnimating = false
        end)
    end

    ---------------------------------------------------------------------------
    -- Wire up the global callback for ShopUI
    ---------------------------------------------------------------------------
    _G.OpenCrateRequested = function(crateId)
        if isAnimating then return end
        isAnimating = true

        local openCrateRF = ReplicatedStorage:FindFirstChild("OpenCrate")
        if not openCrateRF or not openCrateRF:IsA("RemoteFunction") then
            warn("[CrateOpeningUI] OpenCrate remote not found")
            isAnimating = false
            return
        end

        -- Call server
        local ok, success, result = pcall(function()
            return openCrateRF:InvokeServer(crateId)
        end)

        if ok and success and type(result) == "table" then
            isAnimating = false -- Play will re-set it
            CrateOpeningUI.Play(crateId, result, _G.CrateOpeningCoinApi)
        else
            -- Show error toast and close
            isAnimating = false
            local errMsg = "Purchase failed"
            if ok and type(result) == "string" then
                errMsg = result
            end
            -- Brief flash of the overlay with error text
            screen.Enabled = true
            resultFrame.Visible = true
            resultImage.Image = ""
            resultName.Text = errMsg
            resultName.TextColor3 = Color3.fromRGB(255, 80, 80)
            resultRarity.Text = ""
            resultSizeLabel.Text = ""
            rfStroke.Color = Color3.fromRGB(255, 80, 80)
            resultFrame.BackgroundTransparency = 0.06

            task.delay(2, function()
                closeOverlay()
            end)
        end
    end

    return screen
end

return CrateOpeningUI
