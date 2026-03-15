-- PlayerMatchStats.server.lua
-- Initializes per-player match stat attributes (Score, Eliminations, Deaths,
-- FlagCaptures, FlagReturns) on join and tracks Deaths via Humanoid.Died.
-- Other scripts (KillTracker, FlagPickup) increment Eliminations, Score,
-- FlagCaptures, and FlagReturns directly on the player attributes.

local Players = game:GetService("Players")

local STAT_DEFAULTS = {
	Score = 0,
	Eliminations = 0,
	Deaths = 0,
	FlagCaptures = 0,
	FlagReturns = 0,
}

local function initStats(player)
	for stat, default in pairs(STAT_DEFAULTS) do
		if player:GetAttribute(stat) == nil then
			player:SetAttribute(stat, default)
		end
	end
end

local function trackDeaths(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then return end
		humanoid.Died:Connect(function()
			local prev = player:GetAttribute("Deaths") or 0
			player:SetAttribute("Deaths", prev + 1)
		end)
	end)
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				local prev = player:GetAttribute("Deaths") or 0
				player:SetAttribute("Deaths", prev + 1)
			end)
		end
	end
end

local function onPlayerAdded(player)
	initStats(player)
	trackDeaths(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
