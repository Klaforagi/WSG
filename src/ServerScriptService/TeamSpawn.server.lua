-- TeamSpawn.server.lua
-- Manages team creation, spawn logic, and team assignment.
--
-- Join flow (new):
--   1. Player joins → assigned Neutral → spawns at workspace.LobbySpawn.
--   2. Player touches workspace.JoinBlue or workspace.JoinRed in the lobby.
--   3. JoinPartHandler fires AssignTeamBE BindableEvent → doAssignTeam().
--   4. Balance + max-capacity validated; team assigned; character reloaded at
--      the team's main spawn (BlueSpawn / RedSpawn inside workspace.WSG).
--   5. On death: auto-respawn at team death spawn or main team spawn.
--   6. On MatchRestart: respawn at main team spawn.
--
-- The legacy ChooseTeamEvent RemoteEvent is still connected (with response)
-- so that any fallback client path continues to work without changes.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Teams               = game:GetService("Teams")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))
local Map              = workspace:WaitForChild("WSG")

-----------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------
local MAX_TEAM_SIZE = 8

-----------------------------------------------------------------------
-- Prevent ALL players from auto-spawning — we control location ourselves.
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

local blueTeam    = ensureTeam("Blue",    BrickColor.new(Color3.fromRGB(36, 72, 178)))
local redTeam     = ensureTeam("Red",     BrickColor.new(Color3.fromRGB(182, 34, 34)))
local neutralTeam = ensureTeam("Neutral", BrickColor.new("Gold"))

-- Leaderboard order: Blue, Red, Neutral
for _, name in ipairs({"Blue", "Red", "Neutral"}) do
	local t = Teams:FindFirstChild(name)
	if t then t.Parent = nil; t.Parent = Teams end
end

-----------------------------------------------------------------------
-- Remote events (kept for backward-compat + client feedback)
-----------------------------------------------------------------------
local function ensureRemote(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = ReplicatedStorage
	end
	return ev
end

local chooseEvent    = ensureRemote("ChooseTeamEvent")
local chooseResponse = ensureRemote("ChooseTeamResponse")

-----------------------------------------------------------------------
-- BindableEvent: AssignTeamBE
-- JoinPartHandler (and any other server code) fires this to assign a
-- team without going through a RemoteEvent.
-----------------------------------------------------------------------
local assignTeamBE = Instance.new("BindableEvent")
assignTeamBE.Name   = "AssignTeamBE"
assignTeamBE.Parent = ServerScriptService

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------
local function randomPointOnPart(part)
	local size = part.Size
	local rx   = (math.random() - 0.5) * size.X
	local rz   = (math.random() - 0.5) * size.Z
	return part.CFrame * CFrame.new(rx, 3, rz)
end

-----------------------------------------------------------------------
-- doAssignTeam(player, teamName, sendResponse)
-- Core team-assignment logic reused by both the RemoteEvent and the
-- server-side BindableEvent from JoinPartHandler.
--   sendResponse: when true, fires ChooseTeamResponse back to the client.
-- Returns true on success, false if the join was rejected.
-----------------------------------------------------------------------
local function doAssignTeam(player, teamName, sendResponse)
	if type(teamName) ~= "string" then return false end
	if teamName ~= "Blue" and teamName ~= "Red" then return false end

	-- Verify team objects exist
	if not blueTeam or not redTeam then
		warn("[TeamSpawn] Blue or Red team object is missing")
		if sendResponse then chooseResponse:FireClient(player, false, "Teams not available") end
		return false
	end

	-- Already on this team — no-op
	if player:GetAttribute("Team") == teamName then
		if sendResponse then
			chooseResponse:FireClient(player, false,
				"You are already on " .. TeamDisplayNames.Get(teamName))
		end
		return false
	end

	-- Count members, excluding the joining player (handles team-switches fairly)
	local blueCount, redCount = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			if p.Team == blueTeam then
				blueCount += 1
			elseif p.Team == redTeam then
				redCount += 1
			end
		end
	end

	-- Max-capacity check (use current count — do NOT simulate the join)
	if teamName == "Blue" and blueCount >= MAX_TEAM_SIZE then
		local msg = TeamDisplayNames.Get("Blue") ..
			" is full (" .. MAX_TEAM_SIZE .. "/" .. MAX_TEAM_SIZE .. ")"
		if sendResponse then chooseResponse:FireClient(player, false, msg) end
		return false
	end
	if teamName == "Red" and redCount >= MAX_TEAM_SIZE then
		local msg = TeamDisplayNames.Get("Red") ..
			" is full (" .. MAX_TEAM_SIZE .. "/" .. MAX_TEAM_SIZE .. ")"
		if sendResponse then chooseResponse:FireClient(player, false, msg) end
		return false
	end

	-- Balance check: a team is locked only when it ALREADY has 2+ more players
	-- than the other team. 1-player difference is still joinable.
	local targetCount = teamName == "Blue" and blueCount or redCount
	local otherCount  = teamName == "Blue" and redCount  or blueCount
	if targetCount - otherCount >= 2 then
		local msg = TeamDisplayNames.Get(teamName) ..
			" has too many players — pick the other side"
		if sendResponse then chooseResponse:FireClient(player, false, msg) end
		return false
	end

	-- Assign the team
	player.Team = teamName == "Blue" and blueTeam or redTeam
	player:SetAttribute("Team", teamName)

	if sendResponse then
		chooseResponse:FireClient(player, true, "Joined " .. TeamDisplayNames.Get(teamName))
	end

	-- Reload character — CharacterAdded handler will teleport to team spawn
	pcall(function() player:LoadCharacter() end)
	return true
end

-----------------------------------------------------------------------
-- ChooseTeamEvent (legacy client-fired path, kept for safety)
-----------------------------------------------------------------------
chooseEvent.OnServerEvent:Connect(function(plr, teamName)
	doAssignTeam(plr, teamName, true)
end)

-----------------------------------------------------------------------
-- AssignTeamBE (server-fired from JoinPartHandler)
-----------------------------------------------------------------------
assignTeamBE.Event:Connect(function(plr, teamName)
	doAssignTeam(plr, teamName, false)
end)

-----------------------------------------------------------------------
-- PlayerAdded: spawn at LobbySpawn immediately; handle all future spawns
-- via a single persistent CharacterAdded connection per player.
-----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.Team = neutralTeam

	-- Per-player spawn-state tracking (lives inside this closure)
	local lastKnownTeam    = nil   -- team we last spawned this player onto
	local hasSpawnedOnTeam = false -- false → next team spawn goes to main spawn

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end

		local currentTeam = player:GetAttribute("Team") -- "Blue" | "Red" | nil

		-- Detect team change → reset first-spawn flag so they land at main spawn
		if currentTeam ~= lastKnownTeam then
			hasSpawnedOnTeam = false
			lastKnownTeam    = currentTeam
		end

		-- MatchRestart attribute → treat next spawn as first-on-team
		local isRestart = player:GetAttribute("MatchRestart") == true
		if isRestart then
			player:SetAttribute("MatchRestart", nil)
			hasSpawnedOnTeam = false
		end

		-- ── Neutral / lobby ─────────────────────────────────────────────────
		if not currentTeam then
			local lobbySpawn = workspace:FindFirstChild("LobbySpawn")
			if lobbySpawn and lobbySpawn:IsA("BasePart") then
				hrp.CFrame = randomPointOnPart(lobbySpawn)
			else
				warn("[TeamSpawn] workspace.LobbySpawn not found — player will spawn at default location")
			end

		-- ── First spawn on a team (or after restart) ────────────────────────
		elseif not hasSpawnedOnTeam then
			hasSpawnedOnTeam = true
			local spawnName = currentTeam == "Red" and "RedSpawn" or "BlueSpawn"
			local spawnPart = Map:FindFirstChild(spawnName)
			if spawnPart and spawnPart:IsA("BasePart") then
				hrp.CFrame = randomPointOnPart(spawnPart)
			else
				warn("[TeamSpawn] Spawn part '" .. spawnName .. "' not found in Map (workspace.WSG)")
			end

		-- ── Death respawn ────────────────────────────────────────────────────
		else
			local deathName = currentTeam == "Red" and "RedDeathSpawn" or "BlueDeathSpawn"
			local candidates = {}
			for _, obj in ipairs(workspace:GetDescendants()) do
				if obj.Name == deathName and obj:IsA("BasePart") then
					table.insert(candidates, obj)
				end
			end

			local spawnName = currentTeam == "Red" and "RedSpawn" or "BlueSpawn"
			local fallback  = Map:FindFirstChild(spawnName)

			if #candidates > 0 then
				hrp.CFrame = randomPointOnPart(candidates[math.random(1, #candidates)])
			elseif fallback then
				hrp.CFrame = randomPointOnPart(fallback)
			else
				warn("[TeamSpawn] No death or fallback spawn found for team: " .. currentTeam)
			end
		end

		-- Auto-respawn on death (CharacterAutoLoads is disabled)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				local respawnTime = 6
				if _G.GetRespawnTime then
					local ok, val = pcall(_G.GetRespawnTime, player)
					if ok and type(val) == "number" then
						respawnTime = val
					end
				end
				task.wait(respawnTime)
				pcall(function() player:LoadCharacter() end)
			end)
		end
	end)

	-- Spawn immediately at the lobby; CharacterAdded will place them at LobbySpawn
	task.spawn(function()
		pcall(function() player:LoadCharacter() end)
	end)
end)
