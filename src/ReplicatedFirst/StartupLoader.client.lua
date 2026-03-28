-- ReplicatedFirst/StartupLoader.client.lua

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BANDAGE_ANIM = "rbxassetid://139297808237661"

local function collectAnimationIds()
	local ids = {}
	local seen = {}

	local function add(id)
		if not id or id == "" then
			return
		end

		local s = tostring(id)
		if tonumber(s) then
			s = "rbxassetid://" .. s
		end

		if not seen[s] then
			seen[s] = true
			table.insert(ids, s)
		end
	end

	add(BANDAGE_ANIM)

	local ok, meleeModule = pcall(function()
		local module = ReplicatedStorage:FindFirstChild("ToolMeleeSettings")
		if module then
			return require(module)
		end
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

local function createGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "_StartupLoadingGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 10, 20)
	bg.BorderSizePixel = 0
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
	title.Parent = bg

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 30)
	status.Position = UDim2.new(0, 0, 0.46, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.Text = "Loading game..."
	status.TextSize = 20
	status.TextColor3 = Color3.fromRGB(220, 220, 220)
	status.Parent = bg

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(0, 360, 0, 10)
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0.56, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(24, 28, 48)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(65, 130, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	gui.Parent = playerGui
	return gui, bg, title, status, barBg, barFill
end

local function setProgress(statusLabel, barFill, text, alpha)
	statusLabel.Text = text
	TweenService:Create(
		barFill,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = UDim2.new(alpha, 0, 1, 0)}
	):Play()
end

local function fadeOut(gui, bg, title, status, barBg, barFill)
	local tweens = {
		TweenService:Create(bg, TweenInfo.new(0.45), {BackgroundTransparency = 1}),
		TweenService:Create(title, TweenInfo.new(0.45), {TextTransparency = 1}),
		TweenService:Create(status, TweenInfo.new(0.45), {TextTransparency = 1}),
		TweenService:Create(barBg, TweenInfo.new(0.45), {BackgroundTransparency = 1}),
		TweenService:Create(barFill, TweenInfo.new(0.45), {BackgroundTransparency = 1}),
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
		warn("SideUI folder not found")
		return
	end
end

local gui, bg, title, status, barBg, barFill = createGui()

if not game:IsLoaded() then
	game.Loaded:Wait()
end
-- Load saved player settings early so audio/UI honor user's preferences
pcall(function()
	local rs = ReplicatedStorage
	-- WaitForChild with timeout: server may not have created the remote yet
	local getRF = rs:WaitForChild("GetPlayerSettings", 10)
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
			   ShowMinimap = true,
			   ShowGameState = true,
			   ShowHelm = true,
			   ShowPlayerHighlights = true,
		   }
		   local settings = {}
		   for k, v in pairs(defaults) do settings[k] = v end
		   if ok and type(data) == "table" then
			   for k, v in pairs(data) do settings[k] = v end
		   end
		   _G.PlayerSettings = settings
		   _G.ShowPlayerHighlights = (settings.ShowPlayerHighlights ~= false)
		   -- Prevent music from playing until after volume is set
		   pcall(function()
			   local soundsRoot = ReplicatedStorage:FindFirstChild("Sounds")
			   if soundsRoot then
				   local musicFolder = soundsRoot:FindFirstChild("Music")
				   if musicFolder then
					   -- First, stop all music from playing
					   for _, obj in ipairs(musicFolder:GetDescendants()) do
						   if obj:IsA("Sound") then
							   obj.Playing = false
						   end
					   end
					   -- Now set the correct volume
					   local mapped = math.clamp(tonumber(settings.MusicVolume) or 1.0, 0, 1) * 0.5
					   for _, obj in ipairs(musicFolder:GetDescendants()) do
						   if obj:IsA("Sound") then
							   pcall(function() obj.Volume = mapped end)
						   end
					   end
					   -- Only now, start 'Ancient Castle Halls' if volume > 0
					   if mapped > 0 then
						   local ach = musicFolder:FindFirstChild("Ancient Castle Halls")
						   if ach and ach:IsA("Sound") then
							   ach.Playing = true
						   end
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

setProgress(status, barFill, "Collecting assets...", 0.2)

local ids = collectAnimationIds()
local animations = createAnimationInstances(ids)

setProgress(status, barFill, "Preloading animations...", 0.6)

local ok, err = pcall(function()
	if #animations > 0 then
		ContentProvider:PreloadAsync(animations)
	end
end)

if not ok then
	warn("PreloadAsync failed:", err)
end

setProgress(status, barFill, "Opening menu...", 1)
task.wait(0.15)

openMenu()
fadeOut(gui, bg, title, status, barBg, barFill)