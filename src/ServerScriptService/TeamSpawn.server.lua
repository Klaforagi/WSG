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

local CHOOSE_RESPONSE_NAME = "ChooseTeamResponse"
local chooseResponse = ReplicatedStorage:FindFirstChild(CHOOSE_RESPONSE_NAME)
if not chooseResponse then
	chooseResponse = Instance.new("RemoteEvent")
	chooseResponse.Name = CHOOSE_RESPONSE_NAME
	chooseResponse.Parent = ReplicatedStorage
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

		-- Server-side balance check: compute current counts
		local blueCount = 0
		local redCount = 0
		for _,p in ipairs(Players:GetPlayers()) do
			if p.Team == blueTeam then
				blueCount = blueCount + 1
			elseif p.Team == redTeam then
				redCount = redCount + 1
			end
		end

		if teamName == "Blue" and blueCount > redCount then
			chooseResponse:FireClient(player, false, "Blue has more players — pick the other side")
			return
		end
		if teamName == "Red" and redCount > blueCount then
			chooseResponse:FireClient(player, false, "Red has more players — pick the other side")
			return
		end

		-- Assign to the chosen team
		player.Team = teamName == "Red" and redTeam or blueTeam
		player:SetAttribute("Team", teamName)

		-- Notify client of success
		chooseResponse:FireClient(player, true, "Joined " .. teamName)

		-- Teleport to spawn once character loads
		local spawnPart = getSpawnForTeam(teamName)

		-- Persistent CharacterAdded handler: first spawn -> main spawnPart,
		-- subsequent respawns -> team death spawn (RedDeathSpawn/BlueDeathSpawn).
		local firstSpawn = true
		local deathSpawnNames = { Red = "RedDeathSpawn", Blue = "BlueDeathSpawn" }
		player.CharacterAdded:Connect(function(char)
			local hrp = char:WaitForChild("HumanoidRootPart")
			if not hrp then return end
			if firstSpawn then
				if spawnPart then
					hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
				end
				firstSpawn = false
			else
				local deathName = deathSpawnNames[teamName]
				-- Collect all matching death spawn parts (support multiple with same name)
				local candidates = {}
				for _, obj in ipairs(workspace:GetDescendants()) do
					if obj.Name == deathName and obj:IsA("BasePart") then
						table.insert(candidates, obj)
					end
				end
				local deathPart = nil
				if #candidates > 0 then
					deathPart = candidates[math.random(1, #candidates)]
				end
				if deathPart then
					hrp.CFrame = deathPart.CFrame + Vector3.new(0, 3, 0)
				elseif spawnPart then
					hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
				end
			end

			-- Ensure automatic respawn after death (CharacterAutoLoads is false)
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					-- small delay before respawn to let death animation settle
					wait(2)
					pcall(function() player:LoadCharacter() end)
				end)
			end
		end)

		-- Now spawn the character
		player:LoadCharacter()

		-- Only handle the first team pick per join
		if conn then conn:Disconnect() end
	end)
end)
