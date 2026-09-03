-- MusicController.client.lua
-- Lobby (not on Blue/Red): Sounds/Music/Ancient Castle Halls
-- On a team: fade lobby out, then play Sounds/Music/InGame/<MapName> if present.
-- Forest only starts after the player joins a team AND the loaded map is Forest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local LOBBY_TRACK_NAME = "Ancient Castle Halls"
local FADE_TIME = 1.5
local VOLUME_SCALE = 0.2
local FADE_INFO = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeSound = nil
local targetVolume = 0.2
local fadeGeneration = 0
local fadeBusy = false
local activeTween = nil
local phaseMapName = nil

local function getMappedVolume()
	local slider = 1
	if type(_G) == "table" and _G.PlayerSettings and tonumber(_G.PlayerSettings.MusicVolume) then
		slider = tonumber(_G.PlayerSettings.MusicVolume) or 1
	end
	return math.clamp(slider, 0, 1) * VOLUME_SCALE
end

local function getMusicFolder()
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	return sounds and sounds:FindFirstChild("Music")
end

local function getLobbySound()
	local musicFolder = getMusicFolder()
	if not musicFolder then
		return nil
	end
	local sound = musicFolder:FindFirstChild(LOBBY_TRACK_NAME)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

local function getInGameFolder()
	local musicFolder = getMusicFolder()
	return musicFolder and musicFolder:FindFirstChild("InGame")
end

local function findSoundByName(parent, name)
	if not parent or type(name) ~= "string" or name == "" then
		return nil
	end
	local exact = parent:FindFirstChild(name)
	if exact and exact:IsA("Sound") then
		return exact
	end
	local lower = string.lower(name)
	for _, child in ipairs(parent:GetDescendants()) do
		if child:IsA("Sound") and string.lower(child.Name) == lower then
			return child
		end
	end
	return nil
end

local function isMapInstance(inst)
	if not inst then
		return false
	end
	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if mapsFolder and mapsFolder:FindFirstChild(inst.Name) then
		return true
	end
	if findSoundByName(getInGameFolder(), inst.Name) then
		return true
	end
	return false
end

local function getCurrentMapName()
	local attr = workspace:GetAttribute("CurrentMap")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	if type(phaseMapName) == "string" and phaseMapName ~= "" then
		return phaseMapName
	end

	for _, child in ipairs(workspace:GetChildren()) do
		if isMapInstance(child) then
			return child.Name
		end
	end

	return nil
end

local function isOnMatchTeam()
	local team = player.Team
	if not team then
		return false
	end
	local name = team.Name
	return name == "Blue" or name == "Red"
end

local function desiredSound()
	if not isOnMatchTeam() then
		return getLobbySound()
	end
	local mapName = getCurrentMapName()
	if not mapName then
		return nil
	end
	return findSoundByName(getInGameFolder(), mapName)
end

local function applyMusicVolume(mapped)
	targetVolume = (type(mapped) == "number") and mapped or getMappedVolume()
	if fadeBusy then
		return
	end
	if activeSound and activeSound.IsPlaying then
		pcall(function()
			activeSound.Volume = targetVolume
		end)
	end
end

_G.ApplyMusicVolume = applyMusicVolume

local function cancelFade()
	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end
end

local function stopNow(sound)
	if not sound then
		return
	end
	pcall(function()
		sound.Volume = 0
		sound:Stop()
	end)
end

local function playNow(sound)
	if not sound then
		return
	end
	pcall(function()
		sound.Looped = true
		sound.Volume = targetVolume
		if not sound.IsPlaying then
			sound:Play()
		end
	end)
end

local function fadeVolume(sound, volume, token)
	if not sound then
		return false
	end
	cancelFade()
	local tween = TweenService:Create(sound, FADE_INFO, { Volume = volume })
	activeTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeTween == tween then
		activeTween = nil
	end
	return token == fadeGeneration
end

local function switchTo(nextSound)
	if nextSound == activeSound then
		if nextSound and not nextSound.IsPlaying then
			playNow(nextSound)
		end
		return
	end

	fadeGeneration += 1
	local token = fadeGeneration
	local previous = activeSound
	activeSound = nextSound
	targetVolume = getMappedVolume()

	-- Returning to lobby: cut immediately so the fade doesn't hitch.
	if nextSound and nextSound == getLobbySound() then
		fadeBusy = false
		cancelFade()
		if previous and previous ~= nextSound then
			stopNow(previous)
		end
		playNow(nextSound)
		applyMusicVolume(targetVolume)
		return
	end

	fadeBusy = true

	task.spawn(function()
		if previous and previous ~= nextSound then
			if previous.IsPlaying then
				if not fadeVolume(previous, 0, token) then
					return
				end
			end
			if token ~= fadeGeneration then
				return
			end
			stopNow(previous)
		end

		if token ~= fadeGeneration then
			return
		end

		if nextSound then
			pcall(function()
				nextSound.Looped = true
				nextSound.Volume = 0
				if not nextSound.IsPlaying then
					nextSound:Play()
				end
			end)
			if not fadeVolume(nextSound, targetVolume, token) then
				return
			end
		end

		if token == fadeGeneration then
			fadeBusy = false
			applyMusicVolume(targetVolume)
		end
	end)
end

local function syncMusic()
	targetVolume = getMappedVolume()
	switchTo(desiredSound())
end

local function waitForLoader()
	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
	local deadline = os.clock() + 90
	while os.clock() < deadline do
		local early = playerGui:FindFirstChild("_StartupLoadingGuiEarly")
		local main = playerGui:FindFirstChild("_StartupLoadingGui")
		if not early and not main then
			return
		end
		task.wait(0.1)
	end
end

local function hookPhaseRemote(phaseRE)
	if not phaseRE or not phaseRE:IsA("RemoteEvent") then
		return
	end
	phaseRE.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.currentMap) == "string" and payload.currentMap ~= "" then
			phaseMapName = payload.currentMap
		elseif payload.phase == "voting" then
			phaseMapName = nil
		end
		syncMusic()
	end)
end

task.spawn(function()
	waitForLoader()
	pcall(function()
		local sounds = ReplicatedStorage:WaitForChild("Sounds", 10)
		if sounds then
			sounds:WaitForChild("Music", 5)
		end
	end)
	targetVolume = getMappedVolume()

	local lobby = getLobbySound()
	if lobby and lobby.IsPlaying then
		activeSound = lobby
	end

	syncMusic()

	player:GetPropertyChangedSignal("Team"):Connect(syncMusic)

	workspace:GetAttributeChangedSignal("CurrentMap"):Connect(syncMusic)
	workspace.ChildAdded:Connect(function(child)
		if isMapInstance(child) then
			task.defer(syncMusic)
		end
	end)
	workspace.ChildRemoved:Connect(function(child)
		if isMapInstance(child) then
			task.defer(syncMusic)
		end
	end)

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local mapVote = remotes:FindFirstChild("MapVote")
		local phaseRE = mapVote and mapVote:FindFirstChild("Phase")
		hookPhaseRemote(phaseRE)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "Remotes" then
			local mapVote = child:WaitForChild("MapVote", 5)
			local phaseRE = mapVote and mapVote:WaitForChild("Phase", 5)
			hookPhaseRemote(phaseRE)
		end
	end)
end)
