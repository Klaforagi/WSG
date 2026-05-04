-- TeamChangeHandler.server.lua
-- Handles mid-game team changes requested from the Team Stats UI.
-- Uses a separate RemoteEvent from the initial team pick flow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))
local Map = workspace:WaitForChild("WSG")

---------------------------------------------------------------------------
-- Remote events
---------------------------------------------------------------------------
local changeRequest = Instance.new("RemoteEvent")
changeRequest.Name = "ChangeTeamRequest"
changeRequest.Parent = ReplicatedStorage

local changeResponse = Instance.new("RemoteEvent")
changeResponse.Name = "ChangeTeamResponse"
changeResponse.Parent = ReplicatedStorage

local returnToLobbyRequest = Instance.new("RemoteEvent")
returnToLobbyRequest.Name = "ReturnToLobbyRequest"
returnToLobbyRequest.Parent = ReplicatedStorage

local returnToLobbyResponse = Instance.new("RemoteEvent")
returnToLobbyResponse.Name = "ReturnToLobbyResponse"
returnToLobbyResponse.Parent = ReplicatedStorage

---------------------------------------------------------------------------
-- Rate limit per player
---------------------------------------------------------------------------
local lastChangeTime = {}
local COOLDOWN = 5

---------------------------------------------------------------------------
-- Spawn helper (mirrors TeamSpawn logic)
---------------------------------------------------------------------------
local function randomPointOnPart(part)
	local size = part.Size
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	return part.CFrame * CFrame.new(rx, 3, rz)
end

---------------------------------------------------------------------------
-- Handler
---------------------------------------------------------------------------
changeRequest.OnServerEvent:Connect(function(plr, teamName)
	-- Validate input
	if type(teamName) ~= "string" then return end
	if teamName ~= "Blue" and teamName ~= "Red" then return end

	-- Cooldown
	local now = tick()
	if lastChangeTime[plr] and (now - lastChangeTime[plr]) < COOLDOWN then
		changeResponse:FireClient(plr, false, "Please wait before changing teams again")
		return
	end

	-- Already on this team
	if plr.Team and plr.Team.Name == teamName then
		changeResponse:FireClient(plr, false, "You are already on " .. TeamDisplayNames.Get(teamName))
		return
	end

	-- Find team objects
	local blueTeam = Teams:FindFirstChild("Blue")
	local redTeam  = Teams:FindFirstChild("Red")
	if not blueTeam or not redTeam then
		changeResponse:FireClient(plr, false, "Teams not available")
		warn("[TeamChange] Expected side object missing")
		return
	end

	-- Balance check — exclude the switching player from counts
	local blueCount, redCount = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= plr then
			if p.Team == blueTeam then blueCount = blueCount + 1
			elseif p.Team == redTeam then redCount = redCount + 1
			end
		end
	end

	if teamName == "Blue" and blueCount >= redCount + 2 then
		changeResponse:FireClient(plr, false, TeamDisplayNames.Get("Blue") .. " has too many players")
		return
	end
	if teamName == "Red" and redCount >= blueCount + 2 then
		changeResponse:FireClient(plr, false, TeamDisplayNames.Get("Red") .. " has too many players")
		return
	end

	-- Apply team change
	lastChangeTime[plr] = now
	plr.Team = teamName == "Red" and redTeam or blueTeam
	plr:SetAttribute("Team", teamName)

	changeResponse:FireClient(plr, true, "Switched to " .. TeamDisplayNames.Get(teamName))

	-- Respawn at correct team spawn
	task.spawn(function()
		pcall(function() plr:LoadCharacter() end)
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			task.wait(0.15) -- let other handlers settle, then override position
			local spawnName = teamName == "Red" and "RedSpawn" or "BlueSpawn"
			local spawnPart = Map:FindFirstChild(spawnName)
			if spawnPart and spawnPart:IsA("BasePart") then
				hrp.CFrame = randomPointOnPart(spawnPart)
			end
		end
	end)
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(plr)
	lastChangeTime[plr] = nil
end)

---------------------------------------------------------------------------
-- Return to Lobby handler
-- Moves the player to Neutral and respawns them at workspace.LobbySpawn.
-- TeamSpawn.CharacterAdded sees no "Team" attribute and places the
-- character at LobbySpawn automatically.
---------------------------------------------------------------------------
returnToLobbyRequest.OnServerEvent:Connect(function(plr)
	-- Cooldown (shared with team-change cooldown)
	local now = tick()
	if lastChangeTime[plr] and (now - lastChangeTime[plr]) < COOLDOWN then
		returnToLobbyResponse:FireClient(plr, false, "Please wait before changing teams again")
		return
	end

	-- Already in lobby
	local currentTeam = plr.Team
	if not currentTeam or currentTeam.Name == "Neutral" then
		returnToLobbyResponse:FireClient(plr, false, "You are already in the lobby")
		return
	end

	local neutralTeam = Teams:FindFirstChild("Neutral")
	if not neutralTeam then
		warn("[TeamChange] Neutral team object not found")
		returnToLobbyResponse:FireClient(plr, false, "Lobby team not available")
		return
	end

	lastChangeTime[plr] = now
	plr.Team = neutralTeam
	plr:SetAttribute("Team", nil)  -- clears the attribute; TeamSpawn will see nil → LobbySpawn

	returnToLobbyResponse:FireClient(plr, true, "Returned to lobby")

	-- Reload character; TeamSpawn.CharacterAdded handles placing at LobbySpawn
	task.spawn(function()
		pcall(function() plr:LoadCharacter() end)
	end)
end)
