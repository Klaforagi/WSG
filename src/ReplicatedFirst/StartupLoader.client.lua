-- ReplicatedFirst/StartupLoader.client.lua
--
-- Custom loading screen that preloads all game assets before letting the
-- player interact.  Designed to be fail-safe: every wait has a timeout so the
-- loader never permanently hangs.
--
-- GAME FLOW:  Loading screen → Team Select menu → player picks a team →
--              character spawns.  NO character exists during startup loading.
--
-- PRELOAD STAGES (all pre-spawn, global assets only):
--   0. Player settings (audio/volume)
--   1. Animations (melee swing combos, bandage)
--   2. Images (weapon icons, UI icons via AssetCodes)
--   3. Weapon models (from ReplicatedStorage.WeaponPreviews — published by
--      WeaponPreviewPublisher.server.lua from ServerStorage.Tools)
--   4. Enchant visual effects (particles, beams, meshes)
--   5. Sounds (ReplicatedStorage.Sounds)
--   6. SideUI modules (pre-require so first menu open is instant)
--   7. Quest data + remotes
--   8. Finalize (best-effort sweep of any remaining client assets)

local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider  = game:GetService("ContentProvider")
local TweenService     = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Set true when the user clicks Skip. The preload stages keep running in the
-- background; only the UI visibility / input blocker are short-circuited.
local skipped = false

local BANDAGE_ANIM = "rbxassetid://139297808237661"
local FALLBACK_LOGO_IMAGE = "rbxassetid://137602836160101"
local BG_TOP = Color3.fromRGB(48, 70, 118)
local BG_BOTTOM = Color3.fromRGB(26, 34, 62)
local BAR_BG_COLOR = Color3.fromRGB(20, 28, 50)
local BAR_STROKE_COLOR = Color3.fromRGB(84, 122, 196)
local BAR_FILL_START = Color3.fromRGB(82, 146, 255)
local BAR_FILL_END = Color3.fromRGB(170, 220, 255)
local STATUS_TEXT_COLOR = Color3.fromRGB(178, 186, 208)
local SKIP_BG_COLOR = Color3.fromRGB(42, 55, 92)
local SKIP_HOVER_COLOR = Color3.fromRGB(60, 78, 126)

--------------------------------------------------------------------------------
-- UTILITY HELPERS
--------------------------------------------------------------------------------

--- WaitForChild with a bounded timeout. Returns the child or nil.
local function safeWaitForChild(parent, name, timeout)
	if not parent then return nil end
	local child = parent:FindFirstChild(name)
	if child then return child end
	child = parent:WaitForChild(name, timeout or 5)
	return child
end

--- Poll a predicate with a timeout. Returns true if predicate passed.
local function waitForCondition(timeout, pollInterval, predicate)
	local elapsed = 0
	while elapsed < timeout do
		if predicate() then return true end
		task.wait(pollInterval or 0.1)
		elapsed = elapsed + (pollInterval or 0.1)
	end
	return false
end

local function normalizeAssetId(id)
	if id == nil then return nil end
	local s = tostring(id)
	if s == "" then return nil end
	if tonumber(s) then
		return "rbxassetid://" .. s
	end
	return s
end

local function getLoaderLogoImage()
	local ok, logoImage = pcall(function()
		local assetCodesModule = ReplicatedStorage:FindFirstChild("AssetCodes")
		if not assetCodesModule then return nil end
		local AssetCodes = require(assetCodesModule)
		if type(AssetCodes.Get) ~= "function" then return nil end
		return AssetCodes.Get("Logo")
	end)

	if ok then
		return normalizeAssetId(logoImage) or FALLBACK_LOGO_IMAGE
	end

	return FALLBACK_LOGO_IMAGE
end

local function uiPx(base)
	local cam = workspace.CurrentCamera
	local screenY = 1080
	if cam and cam.ViewportSize and cam.ViewportSize.Y >= 600 then
		screenY = cam.ViewportSize.Y
	end
	return math.max(1, math.floor(base * screenY / 1080 + 0.5))
end

local function trackedStatusText(text)
	return tostring(text or "")
end

--- Collect all preloadable asset instances under a root.
local PRELOADABLE_CLASSES = {
	MeshPart = true, SpecialMesh = true, Decal = true, Texture = true,
	Sound = true, ParticleEmitter = true, Beam = true, Trail = true,
}
local function collectPreloadableAssets(root)
	local assets = {}
	if not root then return assets end
	local seen = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if PRELOADABLE_CLASSES[desc.ClassName] and not seen[desc] then
			seen[desc] = true
			table.insert(assets, desc)
		end
	end
	return assets
end

--- Deduplicated PreloadAsync wrapper with progress label.
local function preloadAssets(label, progressAlpha, assets, statusLabel, barFill)
	if #assets == 0 then return end
	setProgress(statusLabel, barFill, label, progressAlpha)
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
	if not ok then
		warn("[StartupLoader] PreloadAsync failed during '" .. label .. "':", err)
	end
end

--------------------------------------------------------------------------------
-- ANIMATION COLLECTION
--------------------------------------------------------------------------------

local function collectAnimationIds()
	local ids = {}
	local seen = {}

	local function add(id)
		if not id or id == "" then return end
		local s = tostring(id)
		if tonumber(s) then s = "rbxassetid://" .. s end
		if not seen[s] then
			seen[s] = true
			table.insert(ids, s)
		end
	end

	add(BANDAGE_ANIM)

	local ok, meleeModule = pcall(function()
		local module = ReplicatedStorage:FindFirstChild("ToolMeleeSettings")
		if module then return require(module) end
	end)

	if ok and meleeModule and meleeModule.presets then
		for _, preset in pairs(meleeModule.presets) do
			add(preset.swing_anim_id)
			if type(preset.swing_anim_ids) == "table" then
				for _, id in ipairs(preset.swing_anim_ids) do
					add(id)
				end
			end
		end
	end

	return ids
end

local function createAnimationInstances(ids)
	local animations = {}
	for i, id in ipairs(ids) do
		local anim = Instance.new("Animation")
		anim.Name = "PreloadAnim_" .. i
		anim.AnimationId = id
		table.insert(animations, anim)
	end
	return animations
end

--------------------------------------------------------------------------------
-- GUI CREATION
--------------------------------------------------------------------------------

local function createGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "_StartupLoadingGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local blocker = Instance.new("TextButton")
	blocker.Name = "InputBlocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Position = UDim2.fromScale(0, 0)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.Active = true
	blocker.AutoButtonColor = false
	blocker.ZIndex = 0
	blocker.Parent = gui

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG_TOP
	bg.BorderSizePixel = 0
	bg.ZIndex = 1
	bg.Parent = gui

	local bgGradient = Instance.new("UIGradient")
	bgGradient.Rotation = 90
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BG_TOP),
		ColorSequenceKeypoint.new(1, BG_BOTTOM),
	})
	bgGradient.Parent = bg

	local title = Instance.new("ImageLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0, uiPx(820), 0, uiPx(460))
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 0.60, uiPx(34))
	title.BackgroundTransparency = 1
	title.ZIndex = 7
	title.Parent = bg

	local logoImageId = getLoaderLogoImage()

	local logoGoldGlow = Instance.new("ImageLabel")
	logoGoldGlow.Name = "LogoGoldGlow"
	logoGoldGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	logoGoldGlow.Position = UDim2.new(0.5, 0, 0.5, uiPx(2))
	logoGoldGlow.Size = UDim2.new(1, uiPx(26), 1, uiPx(26))
	logoGoldGlow.BackgroundTransparency = 1
	logoGoldGlow.Image = logoImageId
	logoGoldGlow.ImageColor3 = Color3.fromRGB(255, 202, 110)
	logoGoldGlow.ImageTransparency = 0.92
	logoGoldGlow.ScaleType = Enum.ScaleType.Fit
	logoGoldGlow.ZIndex = 6
	logoGoldGlow.Parent = title

	local logoBlueGlow = Instance.new("ImageLabel")
	logoBlueGlow.Name = "LogoBlueGlow"
	logoBlueGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	logoBlueGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	logoBlueGlow.Size = UDim2.new(1, uiPx(34), 1, uiPx(34))
	logoBlueGlow.BackgroundTransparency = 1
	logoBlueGlow.Image = logoImageId
	logoBlueGlow.ImageColor3 = Color3.fromRGB(102, 167, 255)
	logoBlueGlow.ImageTransparency = 0.94
	logoBlueGlow.ScaleType = Enum.ScaleType.Fit
	logoBlueGlow.ZIndex = 6
	logoBlueGlow.Parent = title

	title.Image = logoImageId
	title.ScaleType = Enum.ScaleType.Fit

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.Size = UDim2.new(0, uiPx(470), 0, uiPx(28))
	statusLbl.AnchorPoint = Vector2.new(0.5, 0)
	statusLbl.Position = UDim2.new(0.5, 0, 0.60, uiPx(42))
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.Text = trackedStatusText("Preparing the Battlefield...")
	statusLbl.TextSize = uiPx(18)
	statusLbl.TextColor3 = STATUS_TEXT_COLOR
	statusLbl.ZIndex = 5
	statusLbl.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(0, uiPx(500), 0, uiPx(22))
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0.60, uiPx(4))
	barBg.BackgroundColor3 = BAR_BG_COLOR
	barBg.BackgroundTransparency = 0.08
	barBg.BorderSizePixel = 0
	barBg.ClipsDescendants = true
	barBg.ZIndex = 5
	barBg.Parent = bg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBg

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = BAR_STROKE_COLOR
	barStroke.Thickness = 1.6
	barStroke.Transparency = 0.2
	barStroke.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = BAR_FILL_START
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 6
	barFill.Parent = barBg

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(1, 0)
	barFillCorner.Parent = barFill

	local barFillGradient = Instance.new("UIGradient")
	barFillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BAR_FILL_START),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(116, 178, 255)),
		ColorSequenceKeypoint.new(1, BAR_FILL_END),
	})
	barFillGradient.Rotation = 0
	barFillGradient.Parent = barFill

	local skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipButton"
	skipBtn.AnchorPoint = Vector2.new(0.5, 0)
	skipBtn.Position = UDim2.new(0.5, 0, 0.60, uiPx(82))
	skipBtn.Size = UDim2.new(0, uiPx(132), 0, uiPx(38))
	skipBtn.BackgroundColor3 = SKIP_BG_COLOR
	skipBtn.BackgroundTransparency = 0.28
	skipBtn.BorderSizePixel = 0
	skipBtn.AutoButtonColor = false
	skipBtn.Font = Enum.Font.GothamBold
	skipBtn.Text = "Skip"
	skipBtn.TextSize = uiPx(15)
	skipBtn.TextColor3 = Color3.fromRGB(222, 228, 245)
	skipBtn.TextTransparency = 0.08
	skipBtn.ZIndex = 5
	skipBtn.Parent = bg

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, uiPx(12))
	skipCorner.Parent = skipBtn

	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = Color3.fromRGB(130, 160, 220)
	skipStroke.Thickness = 1.4
	skipStroke.Transparency = 0.45
	skipStroke.Parent = skipBtn

	local baseTitlePos = title.Position
	task.spawn(function()
		while gui.Parent do
			local riseTween = TweenService:Create(title, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Position = UDim2.new(baseTitlePos.X.Scale, baseTitlePos.X.Offset, baseTitlePos.Y.Scale, baseTitlePos.Y.Offset - uiPx(8))
			})
			local glowInGold = TweenService:Create(logoGoldGlow, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { ImageTransparency = 0.89 })
			local glowInBlue = TweenService:Create(logoBlueGlow, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { ImageTransparency = 0.92 })
			riseTween:Play()
			glowInGold:Play()
			glowInBlue:Play()
			riseTween.Completed:Wait()
			if not gui.Parent then break end

			local settleTween = TweenService:Create(title, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Position = baseTitlePos
			})
			local glowOutGold = TweenService:Create(logoGoldGlow, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { ImageTransparency = 0.92 })
			local glowOutBlue = TweenService:Create(logoBlueGlow, TweenInfo.new(2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { ImageTransparency = 0.94 })
			settleTween:Play()
			glowOutGold:Play()
			glowOutBlue:Play()
			settleTween.Completed:Wait()
		end
	end)

	local function doSkip()
		if skipped then return end
		skipped = true
		if blocker then
			blocker:Destroy()
			blocker = nil
		end
		bg.Visible = false
	end

	skipBtn.MouseEnter:Connect(function()
		TweenService:Create(skipBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = SKIP_HOVER_COLOR,
			BackgroundTransparency = 0.18,
		}):Play()
	end)

	skipBtn.MouseLeave:Connect(function()
		TweenService:Create(skipBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = SKIP_BG_COLOR,
			BackgroundTransparency = 0.28,
		}):Play()
	end)

	skipBtn.MouseButton1Click:Connect(doSkip)
	skipBtn.TouchTap:Connect(doSkip)

	gui.Parent = playerGui
	return gui, blocker, bg, title, statusLbl, barBg, barFill
end

function setProgress(statusLabel, barFill, text, alpha)
	statusLabel.Text = trackedStatusText(text)
	TweenService:Create(
		barFill,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(alpha, 0, 1, 0) }
	):Play()
end

local function fadeOut(gui, blocker, bg, title, statusLbl, barBg, barFill)
	-- If the user already hit Skip, the UI is hidden and the blocker is gone.
	-- Just clean up the gui and bail out — no tweens needed.
	if skipped then
		if gui then gui:Destroy() end
		return
	end

	-- Remove input blocker immediately so gameplay input works during fade
	if blocker then blocker:Destroy() end

	local tweens = {
		TweenService:Create(bg,        TweenInfo.new(0.45), { BackgroundTransparency = 1 }),
		TweenService:Create(title,     TweenInfo.new(0.45), { ImageTransparency = 1 }),
		TweenService:Create(statusLbl, TweenInfo.new(0.45), { TextTransparency = 1 }),
		TweenService:Create(barBg,     TweenInfo.new(0.45), { BackgroundTransparency = 1 }),
		TweenService:Create(barFill,   TweenInfo.new(0.45), { BackgroundTransparency = 1 }),
	}
	for _, desc in ipairs(title:GetDescendants()) do
		if desc:IsA("ImageLabel") then
			table.insert(tweens, TweenService:Create(desc, TweenInfo.new(0.45), { ImageTransparency = 1 }))
		end
	end
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
	tweens[1].Completed:Wait()
	gui:Destroy()
end

local function openMenu()
	local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
	if not sideUI then
		warn("[StartupLoader] SideUI folder not found")
	end
end

--------------------------------------------------------------------------------
-- MAIN LOADING SEQUENCE
--------------------------------------------------------------------------------

local gui, blocker, bg, title, statusLbl, barBg, barFill = createGui()

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 0: Player settings (audio/volume)
-- Load early so music and SFX volumes are correct from the start.
-- ═══════════════════════════════════════════════════════════════════════════
pcall(function()
	local getRF = safeWaitForChild(ReplicatedStorage, "GetPlayerSettings", 10)
	if getRF and getRF:IsA("RemoteFunction") then
		local ok, data = pcall(function()
			return getRF:InvokeServer()
		end)
		local defaults = {
			MusicVolume = 1.0,
			SFXVolume = 1.0,
			CameraSensitivity = 0.5,
			InvertCamera = false,
			SprintMode = "Hold",
			ShowTooltips = true,
			ShowGameState = true,
			ShowHelm = true,
			ShowPlayerHighlights = false,
		}
		local settings = {}
		for k, v in pairs(defaults) do settings[k] = v end
		if ok and type(data) == "table" then
			for k, _ in pairs(defaults) do
				if data[k] ~= nil then settings[k] = data[k] end
			end
		end
		_G.PlayerSettings = settings
		_G.ShowPlayerHighlights = (settings.ShowPlayerHighlights ~= false)

		pcall(function()
			local soundsRoot = ReplicatedStorage:FindFirstChild("Sounds")
			if soundsRoot then
				local musicFolder = soundsRoot:FindFirstChild("Music")
				if musicFolder then
					for _, obj in ipairs(musicFolder:GetDescendants()) do
						if obj:IsA("Sound") then obj.Playing = false end
					end
					local mapped = math.clamp(tonumber(settings.MusicVolume) or 1.0, 0, 1) * 0.5
					for _, obj in ipairs(musicFolder:GetDescendants()) do
						if obj:IsA("Sound") then pcall(function() obj.Volume = mapped end) end
					end
					if mapped > 0 then
						local ach = musicFolder:FindFirstChild("Ancient Castle Halls")
						if ach and ach:IsA("Sound") then ach.Playing = true end
					end
				end
			end
			local SoundService = game:GetService("SoundService")
			local sfxGroup = SoundService:FindFirstChild("SFX")
			if sfxGroup and sfxGroup:IsA("SoundGroup") then
				sfxGroup.Volume = math.clamp(tonumber(settings.SFXVolume) or 1.0, 0, 1)
			end
		end)
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 1: Animations
-- Melee swing combos + bandage — used immediately on first equip/use.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Preparing the Battlefield...", 0.10)
pcall(function()
	if title and title:IsA("ImageLabel") and title.Image ~= "" then
		ContentProvider:PreloadAsync({ title })
	end
end)
local animIds    = collectAnimationIds()
local animAssets = createAnimationInstances(animIds)
preloadAssets("Drilling the Ranks...", 0.15, animAssets, statusLbl, barFill)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 2: Images (weapon icons, UI icons)
-- Used in inventory, shop, quest reward previews, hotbar — avoids white
-- placeholder flash on first UI open.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Raising the Banners...", 0.25)
pcall(function()
	local assetCodesModule = ReplicatedStorage:FindFirstChild("AssetCodes")
	if assetCodesModule then
		local AssetCodes = require(assetCodesModule)
		local imageList = AssetCodes.List and AssetCodes.List() or {}
		local imageAssets = {}
		for _, assetId in pairs(imageList) do
			if type(assetId) == "string" and assetId ~= "" then
				table.insert(imageAssets, assetId)
			end
		end
		if #imageAssets > 0 then
			ContentProvider:PreloadAsync(imageAssets)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 3: Weapon models (from WeaponPreviews)
-- WeaponPreviewPublisher.server.lua clones every weapon template from
-- ServerStorage.Tools into ReplicatedStorage.WeaponPreviews on server start.
-- Preloading these means the first equip shows the weapon instantly — no
-- mesh/texture pop-in — because Roblox caches by asset ID, not by instance.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Forging Weapons...", 0.35)
pcall(function()
	-- The server script may not have finished publishing yet; wait briefly
	local weaponPreviews = safeWaitForChild(ReplicatedStorage, "WeaponPreviews", 8)
	if weaponPreviews then
		local weaponAssets = collectPreloadableAssets(weaponPreviews)
		if #weaponAssets > 0 then
			ContentProvider:PreloadAsync(weaponAssets)
		end
	else
		warn("[StartupLoader] WeaponPreviews folder not found — first equip may lag")
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 4: Enchant visual assets
-- Cloned onto weapons by the server; preloading their meshes/particles
-- prevents a brief flash on first enchant display.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Charging the Relics...", 0.45)
pcall(function()
	local enchantsFolder = ReplicatedStorage:FindFirstChild("Enchants")
	if enchantsFolder then
		local enchantAssets = collectPreloadableAssets(enchantsFolder)
		if #enchantAssets > 0 then
			ContentProvider:PreloadAsync(enchantAssets)
		end
	end
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	if vfxFolder then
		local vfxAssets = collectPreloadableAssets(vfxFolder)
		if #vfxAssets > 0 then
			ContentProvider:PreloadAsync(vfxAssets)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 5: Sounds
-- All sounds under ReplicatedStorage.Sounds (swing, hit, enchant procs,
-- music, UI) — prevents audio stutter on first play.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Calling the War Drums...", 0.55)
pcall(function()
	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
	if soundsFolder then
		local soundAssets = {}
		for _, desc in ipairs(soundsFolder:GetDescendants()) do
			if desc:IsA("Sound") then
				table.insert(soundAssets, desc)
			end
		end
		if #soundAssets > 0 then
			ContentProvider:PreloadAsync(soundAssets)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 6: Menus (pre-require SideUI modules)
-- The DailyQuestsUI, ShopUI, etc. are lazy-loaded on first open. Requiring
-- them now compiles the Lua bytecode early so the first menu open is instant
-- instead of hitching for 0.5–1s.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Preparing the War Table...", 0.65)
pcall(function()
	local sideUIFolder = ReplicatedStorage:FindFirstChild("SideUI")
	if sideUIFolder then
		local moduleNames = {
			"DailyQuestsUI", "ShopUI", "InventoryUI", "OptionsUI",
			"UpgradesUI", "BoostsUI", "DailyRewardsUI", "EmoteUI",
		}
		for _, name in ipairs(moduleNames) do
			local mod = sideUIFolder:FindFirstChild(name)
			if mod and mod:IsA("ModuleScript") then
				pcall(require, mod)
			end
		end
	end
end)

-- Pre-require quest definitions so data tables are cached
pcall(function()
	local dailyDefs = ReplicatedStorage:FindFirstChild("DailyQuestDefs")
	if dailyDefs and dailyDefs:IsA("ModuleScript") then pcall(require, dailyDefs) end
	local weeklyDefs = ReplicatedStorage:FindFirstChild("WeeklyQuestDefs")
	if weeklyDefs and weeklyDefs:IsA("ModuleScript") then pcall(require, weeklyDefs) end
end)

-- Pre-cache quest remotes so first InvokeServer doesn't stall
pcall(function()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local questRemotes = remotes:FindFirstChild("Quests")
		if questRemotes then
			safeWaitForChild(questRemotes, "GetQuests", 5)
			safeWaitForChild(questRemotes, "GetWeeklyQuests", 5)
			safeWaitForChild(questRemotes, "QuestProgress", 5)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 7: Finalize
-- Quick best-effort sweep of any remaining ReplicatedStorage assets that
-- weren't covered by earlier stages (e.g. new folders added later).
-- No character exists yet — team select hasn't happened. Do NOT wait for
-- Character, Backpack, LoadoutChanged, or any spawn-dependent state here.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Taking Final Positions...", 0.90)
pcall(function()
	-- Best-effort: sweep any stray preloadable assets under ReplicatedStorage
	-- that the earlier stages may have missed (new UI elements, etc.).
	local misc = {}
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		-- Skip folders already preloaded in earlier stages
		local skip = {
			WeaponPreviews = true, Enchants = true, VFX = true,
			Sounds = true, SideUI = true,
		}
		if child:IsA("Folder") and not skip[child.Name] then
			for _, a in ipairs(collectPreloadableAssets(child)) do
				table.insert(misc, a)
			end
		end
	end
	if #misc > 0 then
		ContentProvider:PreloadAsync(misc)
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- DONE — fade out and hand off to team select
-- Character-specific preloading (loadout tools, accessories) happens later
-- in PostSpawnPreload.client.lua after the player picks a team and spawns.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Ready for Battle...", 1)
task.wait(0.15)

openMenu()
fadeOut(gui, blocker, bg, title, statusLbl, barBg, barFill)