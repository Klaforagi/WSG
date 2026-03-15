-- TeamChangeHandler.server.lua
-- Handles mid-game team changes requested from the Team Stats UI.
-- Uses a separate RemoteEvent from the initial team pick flow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

---------------------------------------------------------------------------
-- Remote events
---------------------------------------------------------------------------
local changeRequest = Instance.new("RemoteEvent")
changeRequest.Name = "ChangeTeamRequest"
changeRequest.Parent = ReplicatedStorage

local changeResponse = Instance.new("RemoteEvent")
changeResponse.Name = "ChangeTeamResponse"
changeResponse.Parent = ReplicatedStorage

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
		changeResponse:FireClient(plr, false, "You are already on " .. teamName .. " team")
		return
	end

	-- Find team objects
	local blueTeam = Teams:FindFirstChild("Blue")
	local redTeam  = Teams:FindFirstChild("Red")
	if not blueTeam or not redTeam then
		changeResponse:FireClient(plr, false, "Teams not available")
		warn("[TeamChange] Blue or Red team object missing")
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
		changeResponse:FireClient(plr, false, "Blue team has too many players")
		return
	end
	if teamName == "Red" and redCount >= blueCount + 2 then
		changeResponse:FireClient(plr, false, "Red team has too many players")
		return
	end

	-- Apply team change
	lastChangeTime[plr] = now
	plr.Team = teamName == "Red" and redTeam or blueTeam
	plr:SetAttribute("Team", teamName)

	changeResponse:FireClient(plr, true, "Switched to " .. teamName .. " team")

	-- Respawn at correct team spawn
	task.spawn(function()
		pcall(function() plr:LoadCharacter() end)
		local char = plr.Character or plr.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			task.wait(0.15) -- let other handlers settle, then override position
			local spawnName = teamName == "Red" and "RedSpawn" or "BlueSpawn"
			local spawnPart = workspace:FindFirstChild(spawnName)
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
