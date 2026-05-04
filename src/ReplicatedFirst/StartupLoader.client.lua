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

	-- Full-screen input blocker: absorbs all mouse/touch/gamepad input so
	-- nothing behind the loading screen can be clicked or activated.
	local blocker = Instance.new("TextButton")
	blocker.Name = "InputBlocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Position = UDim2.fromScale(0, 0)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.Active = true            -- absorbs input
	blocker.AutoButtonColor = false
	blocker.ZIndex = 0               -- behind visuals but inside the high-DisplayOrder gui
	blocker.Parent = gui

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
	bg.BorderSizePixel = 0
	bg.ZIndex = 1
	bg.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.new(0, 0, 0.34, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "Loading"
	title.TextSize = 40
	title.TextColor3 = Color3.fromRGB(255, 215, 80)
	title.ZIndex = 2
	title.Parent = bg

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Name = "Status"
	statusLbl.Size = UDim2.new(1, 0, 0, 30)
	statusLbl.Position = UDim2.new(0, 0, 0.46, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.Gotham
	statusLbl.Text = "Loading game..."
	statusLbl.TextSize = 20
	statusLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	statusLbl.ZIndex = 2
	statusLbl.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(0, 360, 0, 10)
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0.56, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(24, 28, 48)
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 2
	barBg.Parent = bg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(65, 130, 255)
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 3
	barFill.Parent = barBg

	-- Skip button: hides the loading UI immediately and removes the input
	-- blocker. Loading continues in the background; fadeOut becomes a no-op
	-- (just destroys the gui) once the real sequence completes.
	local skipBtn = Instance.new("TextButton")
	skipBtn.Name = "SkipButton"
	skipBtn.AnchorPoint = Vector2.new(0.5, 0)
	skipBtn.Position = UDim2.new(0.5, 0, 0.62, 0)
	skipBtn.Size = UDim2.new(0, 140, 0, 36)
	skipBtn.BackgroundColor3 = Color3.fromRGB(40, 48, 80)
	skipBtn.BorderSizePixel = 0
	skipBtn.AutoButtonColor = true
	skipBtn.Font = Enum.Font.GothamBold
	skipBtn.Text = "Skip"
	skipBtn.TextSize = 18
	skipBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
	skipBtn.ZIndex = 4
	skipBtn.Parent = bg

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 6)
	skipCorner.Parent = skipBtn

	local function doSkip()
		if skipped then return end
		skipped = true
		-- Remove input blocker so gameplay/menu input works immediately.
		if blocker then
			blocker:Destroy()
			blocker = nil
		end
		-- Hide all visuals; do NOT destroy the gui yet so fadeOut can clean up
		-- safely whenever loading actually finishes.
		bg.Visible = false
	end

	skipBtn.MouseButton1Click:Connect(doSkip)
	skipBtn.TouchTap:Connect(doSkip)

	gui.Parent = playerGui
	return gui, blocker, bg, title, statusLbl, barBg, barFill
end

function setProgress(statusLabel, barFill, text, alpha)
	statusLabel.Text = text
	TweenService:Create(
		barFill,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
		TweenService:Create(title,     TweenInfo.new(0.45), { TextTransparency = 1 }),
		TweenService:Create(statusLbl, TweenInfo.new(0.45), { TextTransparency = 1 }),
		TweenService:Create(barBg,     TweenInfo.new(0.45), { BackgroundTransparency = 1 }),
		TweenService:Create(barFill,   TweenInfo.new(0.45), { BackgroundTransparency = 1 }),
	}
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
setProgress(statusLbl, barFill, "Collecting assets...", 0.10)
local animIds    = collectAnimationIds()
local animAssets = createAnimationInstances(animIds)
preloadAssets("Preloading animations...", 0.15, animAssets, statusLbl, barFill)

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGE 2: Images (weapon icons, UI icons)
-- Used in inventory, shop, quest reward previews, hotbar — avoids white
-- placeholder flash on first UI open.
-- ═══════════════════════════════════════════════════════════════════════════
setProgress(statusLbl, barFill, "Preloading images...", 0.25)
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
setProgress(statusLbl, barFill, "Preloading weapons...", 0.35)
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
setProgress(statusLbl, barFill, "Preloading enchant effects...", 0.45)
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
setProgress(statusLbl, barFill, "Preloading sounds...", 0.55)
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
setProgress(statusLbl, barFill, "Preloading menus...", 0.65)
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
setProgress(statusLbl, barFill, "Finalizing...", 0.90)
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
setProgress(statusLbl, barFill, "Opening menu...", 1)
task.wait(0.15)

openMenu()
fadeOut(gui, blocker, bg, title, statusLbl, barBg, barFill)