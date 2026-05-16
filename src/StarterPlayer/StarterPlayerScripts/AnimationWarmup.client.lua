-- StarterPlayerScripts/AnimationWarmup.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local BANDAGE_ANIM = "rbxassetid://139297808237661"
local warmedAnimators = setmetatable({}, { __mode = "k" })
local watchedCharacters = setmetatable({}, { __mode = "k" })

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

local allAnimationIds = collectAnimationIds()

local function warmAnimatorAnimations(animator)
	if not animator or warmedAnimators[animator] then
		return
	end
	warmedAnimators[animator] = true

	for _, id in ipairs(allAnimationIds) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id

		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)

		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0, 0.01, 1)
			task.wait()
			track:Stop(0)
		else
			warmedAnimators[animator] = nil
			warn("Failed to warm animation:", id)
		end
	end
end

local function watchCharacter(character)
	if not character or watchedCharacters[character] then
		return
	end
	watchedCharacters[character] = true

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Animator") then
			task.defer(function()
				warmAnimatorAnimations(desc)
			end)
		end
	end

	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("Animator") then
			task.defer(function()
				warmAnimatorAnimations(desc)
			end)
		end
	end)
end

local function watchPlayer(targetPlayer)
	targetPlayer.CharacterAdded:Connect(function(character)
		task.defer(function()
			watchCharacter(character)
		end)
	end)

	if targetPlayer.Character then
		task.defer(function()
			watchCharacter(targetPlayer.Character)
		end)
	end
end

for _, targetPlayer in ipairs(Players:GetPlayers()) do
	watchPlayer(targetPlayer)
end

Players.PlayerAdded:Connect(watchPlayer)