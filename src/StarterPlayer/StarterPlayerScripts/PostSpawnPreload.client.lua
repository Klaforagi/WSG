-- StarterPlayerScripts/PostSpawnPreload.client.lua
--
-- Non-blocking post-spawn preloader.  Runs AFTER the player selects a team
-- and their character spawns.  Preloads the actual tool instances + character
-- model so there's no mesh/texture pop-in on the first equip.
--
-- This is separate from StartupLoader (which only handles global pre-spawn
-- assets like WeaponPreviews, animations, sounds, etc.).

local Players         = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer

local PRELOADABLE_CLASSES = {
	MeshPart = true, SpecialMesh = true, Decal = true, Texture = true,
	Sound = true, ParticleEmitter = true, Beam = true, Trail = true,
}

local function collectPreloadable(root)
	local assets = {}
	if not root then return assets end
	for _, desc in ipairs(root:GetDescendants()) do
		if PRELOADABLE_CLASSES[desc.ClassName] then
			table.insert(assets, desc)
		end
	end
	return assets
end

local function preloadCharacterAndLoadout(character)
	local toPreload = {}

	-- Character model (body parts, accessories, etc.)
	for _, a in ipairs(collectPreloadable(character)) do
		table.insert(toPreload, a)
	end

	-- Backpack tools
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				for _, a in ipairs(collectPreloadable(tool)) do
					table.insert(toPreload, a)
				end
			end
		end
	end

	-- StarterGear tools
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then
		for _, tool in ipairs(starterGear:GetChildren()) do
			if tool:IsA("Tool") then
				for _, a in ipairs(collectPreloadable(tool)) do
					table.insert(toPreload, a)
				end
			end
		end
	end

	if #toPreload > 0 then
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
		if not ok then
			warn("[PostSpawnPreload] PreloadAsync failed:", err)
		end
	end
end

-- Fire on every spawn (team switch, respawn, etc.) — non-blocking
player.CharacterAdded:Connect(function(character)
	-- Small delay to let the server finish cloning tools into Backpack
	task.delay(0.5, function()
		preloadCharacterAndLoadout(character)
	end)
end)

-- If a character already exists somehow (e.g. late script load), handle it
if player.Character then
	task.defer(function()
		preloadCharacterAndLoadout(player.Character)
	end)
end
