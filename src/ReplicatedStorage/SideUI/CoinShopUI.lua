--------------------------------------------------------------------------------
-- CoinShopUI.lua  –  Client-side "Buy Coins" popup
-- Place in ReplicatedStorage > SideUI.
-- Toggled by the green "+" button in CoinDisplay.
--
-- Uses MarketplaceService:PromptProductPurchase to prompt Developer Products.
-- Product IDs and coin amounts are defined in ReplicatedStorage.CoinProducts.
--------------------------------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Try to require the central MenuController (optional fallback)
local MenuController = nil
pcall(function()
	MenuController = require(script.Parent:WaitForChild("MenuController"))
end)

--------------------------------------------------------------------------------
-- Load CoinProducts config
--------------------------------------------------------------------------------
local CoinProducts
do
	local mod = ReplicatedStorage:WaitForChild("CoinProducts", 10)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			CoinProducts = result
		else
			warn("[CoinShopUI] Failed to load CoinProducts:", tostring(result))
		end
	else
		warn("[CoinShopUI] CoinProducts module not found")
	end
end

--------------------------------------------------------------------------------
-- Responsive pixel scaling (matches SideUI / ShopUI / BoostsUI)
--------------------------------------------------------------------------------
local function px(base)
	local cam = workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y > 0 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.round(base * screenY / 1080))
end

local deviceTextScale = UserInputService.TouchEnabled and 1.0 or 0.75
local function tpx(base)
	return math.max(1, math.round(px(base) * deviceTextScale))
end

--------------------------------------------------------------------------------
-- Palette (sourced from shared UITheme – Team menu visual language)
--------------------------------------------------------------------------------
local UITheme
do
	local ok, result = pcall(function() return require(script.Parent.UITheme) end)
	if ok then UITheme = result end
end

local POPUP_BG     = UITheme and UITheme.POPUP_BG or Color3.fromRGB(16, 18, 32)
local CARD_BG      = UITheme and UITheme.CARD_BG or Color3.fromRGB(26, 30, 48)
local CARD_STROKE  = UITheme and UITheme.CARD_STROKE or Color3.fromRGB(55, 62, 95)
local GOLD         = UITheme and UITheme.GOLD or Color3.fromRGB(255, 215, 80)
local WHITE        = UITheme and UITheme.WHITE or Color3.fromRGB(245, 245, 252)
local DIM_TEXT     = UITheme and UITheme.DIM_TEXT or Color3.fromRGB(145, 150, 175)
local GREEN_BTN    = UITheme and UITheme.GREEN_BTN or Color3.fromRGB(35, 190, 75)
local RED_BTN      = UITheme and UITheme.RED_BTN or Color3.fromRGB(160, 50, 50)
local OVERLAY_CLR  = UITheme and UITheme.OVERLAY_CLR or Color3.fromRGB(10, 10, 10)

local TWEEN_IN     = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT    = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--------------------------------------------------------------------------------
-- AssetCodes (for coin icon)
--------------------------------------------------------------------------------
local AssetCodes
do
	local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
	if mod and mod:IsA("ModuleScript") then
		pcall(function() AssetCodes = require(mod) end)
	end
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------
local CoinShopUI = {}

local overlay   -- ScreenGui-level overlay frame
local popup     -- the popup frame
local isOpen    = false
local isAnimating = false
local promptDebounce = false

--------------------------------------------------------------------------------
-- Build the popup (called once, lazily)
--------------------------------------------------------------------------------
local function buildPopup(screenGui)
	-- Dark overlay
	overlay = Instance.new("Frame")
	overlay.Name = "CoinShopOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = OVERLAY_CLR
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex = 500
	overlay.Visible = false
	overlay.Parent = screenGui

	-- Popup window (centered)
	popup = Instance.new("Frame")
	popup.Name = "CoinShopPopup"
	popup.Size = UDim2.new(0, px(680), 0, 0)
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.BackgroundColor3 = POPUP_BG
	popup.BorderSizePixel = 0
	popup.ZIndex = 510
	popup.Parent = overlay

	local popupCorner = Instance.new("UICorner")
	popupCorner.CornerRadius = UDim.new(0, px(14))
	popupCorner.Parent = popup

	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = UITheme and UITheme.GOLD_DIM or Color3.fromRGB(180, 150, 50)
	popupStroke.Thickness = 1.5
	popupStroke.Transparency = 0.15
	popupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	popupStroke.Parent = popup

	-- Subtle vertical gradient matching Team menu panel
	local popupGrad = Instance.new("UIGradient")
	popupGrad.Color = UITheme and UITheme.PANEL_GRADIENT or ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
	})
	popupGrad.Rotation = 90
	popupGrad.Parent = popup

	local popupPad = Instance.new("UIPadding")
	popupPad.PaddingTop = UDim.new(0, px(30))
	popupPad.PaddingBottom = UDim.new(0, px(30))
	popupPad.PaddingLeft = UDim.new(0, px(32))
	popupPad.PaddingRight = UDim.new(0, px(32))
	popupPad.Parent = popup

	local popupLayout = Instance.new("UIListLayout")
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	popupLayout.Padding = UDim.new(0, px(22))
	popupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	popupLayout.Parent = popup

	--------------------------------------------------------------------
	-- Title row
	--------------------------------------------------------------------
	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.Size = UDim2.new(1, 0, 0, px(58))
	titleRow.BackgroundTransparency = 1
	titleRow.LayoutOrder = 1
	titleRow.Parent = popup

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -px(54), 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "Buy Coins"
	titleLabel.TextColor3 = GOLD
	titleLabel.TextSize = tpx(46)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleRow

	-- Close X button — dark + gold style
	local CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
	local CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)
	local CLOSE_PRESS   = Color3.fromRGB(18, 20, 32)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, px(44), 0, px(44))
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.BackgroundColor3 = CLOSE_DEFAULT
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.Text = "X"
	closeBtn.TextColor3 = GOLD
	closeBtn.TextSize = tpx(26)
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 520
	closeBtn.Parent = titleRow

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, px(8))
	closeBtnCorner.Parent = closeBtn

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color = GOLD
	closeBtnStroke.Thickness = 1.2
	closeBtnStroke.Transparency = 0.4
	closeBtnStroke.Parent = closeBtn

	-- Hover / press feedback
	local closeFeedback = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_HOVER}):Play()
		TweenService:Create(closeBtn, closeFeedback, {TextColor3 = WHITE}):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_DEFAULT}):Play()
		TweenService:Create(closeBtn, closeFeedback, {TextColor3 = GOLD}):Play()
	end)
	closeBtn.MouseButton1Down:Connect(function()
		TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_PRESS}):Play()
	end)
	closeBtn.MouseButton1Up:Connect(function()
		TweenService:Create(closeBtn, closeFeedback, {BackgroundColor3 = CLOSE_HOVER}):Play()
	end)

	closeBtn.MouseButton1Click:Connect(function()
		CoinShopUI.Hide()
	end)

	-- Clicking the overlay background also closes
	local overlayBtn = Instance.new("TextButton")
	overlayBtn.Name = "OverlayClickCatcher"
	overlayBtn.Size = UDim2.new(1, 0, 1, 0)
	overlayBtn.BackgroundTransparency = 1
	overlayBtn.Text = ""
	overlayBtn.ZIndex = 501
	overlayBtn.Parent = overlay
	overlayBtn.MouseButton1Click:Connect(function()
		CoinShopUI.Hide()
	end)
	-- Popup sits above the click catcher
	popup.ZIndex = 510

	--------------------------------------------------------------------
	-- Gold accent bar under title
	--------------------------------------------------------------------
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(1, 0, 0, px(2))
	accentBar.BackgroundColor3 = GOLD
	accentBar.BackgroundTransparency = 0.3
	accentBar.BorderSizePixel = 0
	accentBar.LayoutOrder = 2
	accentBar.Parent = popup

	--------------------------------------------------------------------
	-- Pack cards
	--------------------------------------------------------------------
	if CoinProducts and CoinProducts.Packs then
		for i, pack in ipairs(CoinProducts.Packs) do
			local card = Instance.new("Frame")
			card.Name = "Pack_" .. tostring(i)
			card.Size = UDim2.new(1, 0, 0, px(115))
			card.BackgroundColor3 = CARD_BG
			card.BorderSizePixel = 0
			card.LayoutOrder = 2 + i
			card.Parent = popup

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, px(10))
			cardCorner.Parent = card

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = CARD_STROKE
			cardStroke.Thickness = 1.2
			cardStroke.Transparency = 0.35
			cardStroke.Parent = card

			local cardPad = Instance.new("UIPadding")
			cardPad.PaddingLeft = UDim.new(0, px(20))
			cardPad.PaddingRight = UDim.new(0, px(18))
			cardPad.Parent = card

			-- Coin icon (image or fallback circle)
			local coinIconSize = px(54)
			local coinAsset = nil
			if AssetCodes and type(AssetCodes.Get) == "function" then
				pcall(function() coinAsset = AssetCodes.Get("Coin") end)
			end
			if coinAsset and type(coinAsset) == "string" then
				local coinIcon = Instance.new("ImageLabel")
				coinIcon.Name = "CoinIcon"
				coinIcon.Size = UDim2.new(0, coinIconSize, 0, coinIconSize)
				coinIcon.AnchorPoint = Vector2.new(0, 0.5)
				coinIcon.Position = UDim2.new(0, 0, 0.5, 0)
				coinIcon.BackgroundTransparency = 1
				coinIcon.Image = coinAsset
				coinIcon.ScaleType = Enum.ScaleType.Fit
				coinIcon.ZIndex = 515
				coinIcon.Parent = card
			else
				-- Fallback: gold circle
				local coinCircle = Instance.new("Frame")
				coinCircle.Name = "CoinIcon"
				coinCircle.Size = UDim2.new(0, coinIconSize, 0, coinIconSize)
				coinCircle.AnchorPoint = Vector2.new(0, 0.5)
				coinCircle.Position = UDim2.new(0, 0, 0.5, 0)
				coinCircle.BackgroundColor3 = Color3.fromRGB(255, 200, 28)
				coinCircle.BorderSizePixel = 0
				coinCircle.ZIndex = 515
				coinCircle.Parent = card
				local cc = Instance.new("UICorner")
				cc.CornerRadius = UDim.new(0.5, 0)
				cc.Parent = coinCircle
			end

			-- Coin amount label
			local coinLabel = Instance.new("TextLabel")
			coinLabel.Name = "CoinAmount"
			coinLabel.Size = UDim2.new(0.55, -coinIconSize, 0.50, 0)
			coinLabel.Position = UDim2.new(0, coinIconSize + px(16), 0, px(10))
			coinLabel.BackgroundTransparency = 1
			coinLabel.Font = Enum.Font.GothamBlack
			coinLabel.Text = tostring(pack.Coins) .. " Coins"
			coinLabel.TextColor3 = GOLD
			coinLabel.TextSize = tpx(34)
			coinLabel.TextXAlignment = Enum.TextXAlignment.Left
			coinLabel.ZIndex = 515
			coinLabel.Parent = card

			-- Pack name subtitle
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "PackName"
			nameLabel.Size = UDim2.new(0.55, -coinIconSize, 0.35, 0)
			nameLabel.Position = UDim2.new(0, coinIconSize + px(16), 0.50, px(4))
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Text = pack.Name
			nameLabel.TextColor3 = DIM_TEXT
			nameLabel.TextSize = tpx(24)
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.ZIndex = 515
			nameLabel.Parent = card

			-- Buy button (right side) with text-based price
			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyBtn"
			buyBtn.Size = UDim2.new(0, px(160), 0, px(56))
			buyBtn.AnchorPoint = Vector2.new(1, 0.5)
			buyBtn.Position = UDim2.new(1, 0, 0.5, 0)
			buyBtn.BackgroundColor3 = GREEN_BTN
			buyBtn.BorderSizePixel = 0
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.Text = "R$ " .. tostring(pack.Price or "??")
			buyBtn.TextColor3 = WHITE
			buyBtn.TextSize = tpx(30)
			buyBtn.AutoButtonColor = false
			buyBtn.ZIndex = 520
			buyBtn.Parent = card

			local buyCorner = Instance.new("UICorner")
			buyCorner.CornerRadius = UDim.new(0, px(8))
			buyCorner.Parent = buyBtn

			local buyStroke = Instance.new("UIStroke")
			buyStroke.Color = Color3.fromRGB(25, 140, 50)
			buyStroke.Thickness = 1.2
			buyStroke.Parent = buyBtn

			-- Hover feedback
			buyBtn.MouseEnter:Connect(function()
				TweenService:Create(buyBtn, TWEEN_IN, {
					BackgroundColor3 = Color3.fromRGB(50, 220, 90),
				}):Play()
			end)
			buyBtn.MouseLeave:Connect(function()
				TweenService:Create(buyBtn, TWEEN_IN, {
					BackgroundColor3 = GREEN_BTN,
				}):Play()
			end)

			-- Purchase click handler
			buyBtn.MouseButton1Click:Connect(function()
				if promptDebounce then return end

				local productId = pack.ProductId
				if not productId or productId == 0 then
					warn("[CoinShopUI] Product ID not set for '" .. pack.Name .. "'. Set it in CoinProducts.lua")
					return
				end

				promptDebounce = true
				print("[CoinShopUI] Prompting purchase:", pack.Name, "ProductId:", productId)

				local ok, err = pcall(function()
					MarketplaceService:PromptProductPurchase(player, productId)
				end)
				if not ok then
					warn("[CoinShopUI] PromptProductPurchase failed:", tostring(err))
				end

				-- Release debounce after a short delay so the Roblox native
				-- prompt has time to appear and the player can't spam-click.
				task.delay(2, function()
					promptDebounce = false
				end)
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------
function CoinShopUI.Show(screenGui)
	-- legacy direct show (kept for compatibility)
	if isOpen or isAnimating then return end
	if not overlay then
		buildPopup(screenGui)
	end
	if not overlay then return end

	isAnimating = true
	overlay.Visible = true
	popup.Position = UDim2.new(0.5, 0, -0.3, 0)

	local tween = TweenService:Create(popup, TWEEN_IN, {
		Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		isAnimating = false
		isOpen = true
	end)
end

function CoinShopUI.Hide()
	-- legacy direct hide (kept for compatibility)
	if not isOpen or isAnimating then return end
	if not overlay then return end

	isAnimating = true
	local tween = TweenService:Create(popup, TWEEN_OUT, {
		Position = UDim2.new(0.5, 0, -0.3, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		overlay.Visible = false
		isAnimating = false
		isOpen = false
	end)
end

function CoinShopUI.Toggle(screenGui)
	-- Prefer to use the central MenuController when available so this popup
	-- participates in the shared single-open-menu behaviour. Fall back to
	-- local toggle when the controller is not present (e.g. unit tests).
	if MenuController then
		MenuController.ToggleMenu("CoinShop", screenGui)
	else
		if isOpen then
			CoinShopUI.Hide()
		else
			CoinShopUI.Show(screenGui)
		end
	end
end

function CoinShopUI.IsOpen()
	return isOpen
end

-- Register with MenuController (if available) so the popup becomes a
-- first-class managed menu. The open callback accepts (sameGroup, screenGui).
if MenuController then
	MenuController.RegisterMenu("CoinShop", {
		open = function(sameGroup, screenGui)
			-- ignore sameGroup for this simple popup; use screenGui to parent
			if not overlay then
				buildPopup(screenGui)
			end
			if overlay then
				-- animate in
				if isAnimating or isOpen then return end
				isAnimating = true
				overlay.Visible = true
				popup.Position = UDim2.new(0.5, 0, -0.3, 0)
				local tween = TweenService:Create(popup, TWEEN_IN, {
					Position = UDim2.new(0.5, 0, 0.5, 0),
				})
				tween:Play()
				tween.Completed:Connect(function()
					isAnimating = false
					isOpen = true
				end)
			end
		end,
		close = function()
			if not isOpen or isAnimating then return end
			isAnimating = true
			local tween = TweenService:Create(popup, TWEEN_OUT, {
				Position = UDim2.new(0.5, 0, -0.3, 0),
			})
			tween:Play()
			tween.Completed:Connect(function()
				overlay.Visible = false
				isAnimating = false
				isOpen = false
			end)
		end,
		closeInstant = function()
			if overlay then
				overlay.Visible = false
			end
			isAnimating = false
			isOpen = false
		end,
		isOpen = function()
			return isOpen
		end,
		group = "modal",
	})
end

return CoinShopUI
