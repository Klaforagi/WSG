local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

-----------------------------------------------------------------------
-- Prevent ALL players from auto-spawning (this is a Players service property)
-----------------------------------------------------------------------
Players.CharacterAutoLoads = false

-----------------------------------------------------------------------
-- Create the three teams if they don't already exist
-----------------------------------------------------------------------
local function ensureTeam(name, color)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = color
		team.AutoAssignable = false
		team.Parent = Teams
	end
	return team
end

-- Create teams in the desired leaderboard order (Blue, Red, Neutral)
local blueTeam    = ensureTeam("Blue",    BrickColor.new("Bright blue"))
local redTeam     = ensureTeam("Red",     BrickColor.new("Bright red"))
local neutralTeam = ensureTeam("Neutral", BrickColor.new("Medium stone grey"))

-- Re-parent teams in the desired order so the Roblox player list
-- displays them top-to-bottom as Blue, Red, Neutral.
local desiredOrder = {"Blue", "Red", "Neutral"}
for _, name in ipairs(desiredOrder) do
	local t = Teams:FindFirstChild(name)
	if t then
		t.Parent = nil
		t.Parent = Teams
	end
end

-----------------------------------------------------------------------
-- Remote event for team choice
-----------------------------------------------------------------------
local CHOOSE_EVENT_NAME = "ChooseTeamEvent"

local chooseEvent = ReplicatedStorage:FindFirstChild(CHOOSE_EVENT_NAME)
if not chooseEvent then
	chooseEvent = Instance.new("RemoteEvent")
	chooseEvent.Name = CHOOSE_EVENT_NAME
	chooseEvent.Parent = ReplicatedStorage
end

-----------------------------------------------------------------------
-- Helper: find the spawn part for a team
-----------------------------------------------------------------------
local function getSpawnForTeam(teamName)
	local spawnName = teamName == "Red" and "RedSpawn" or "BlueSpawn"
	local part = workspace:FindFirstChild(spawnName)
	if part and part:IsA("BasePart") then
		return part
	end
	warn("[TeamSpawn] Could not find spawn part: " .. spawnName)
	return nil
end

-----------------------------------------------------------------------
-- On player join: put them on Neutral (no character yet)
-----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.Team = neutralTeam

	local conn
	conn = chooseEvent.OnServerEvent:Connect(function(plr, teamName)
		if plr ~= player then return end
		if teamName ~= "Red" and teamName ~= "Blue" then return end

		-- Assign to the chosen team
		player.Team = teamName == "Red" and redTeam or blueTeam
		player:SetAttribute("Team", teamName)

		-- Teleport to spawn once character loads
		local spawnPart = getSpawnForTeam(teamName)

		local charConn
		charConn = player.CharacterAdded:Connect(function(char)
			if spawnPart then
				local hrp = char:WaitForChild("HumanoidRootPart")
				hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
			end
			if charConn then charConn:Disconnect() end
		end)

		-- Now spawn the character
		player:LoadCharacter()

		-- Only handle the first team pick per join
		if conn then conn:Disconnect() end
	end)
end)
