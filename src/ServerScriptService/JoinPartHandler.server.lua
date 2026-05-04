-- JoinPartHandler.server.lua
-- Server-side handler for workspace.JoinBlue and workspace.JoinRed touch parts.
--
-- Responsibilities:
--   • Detect when a player's character touches a join part.
--   • Validate: real character, alive Humanoid, Player exists.
--   • Debounce per-player to prevent spam.
--   • Fire AssignTeamBE BindableEvent → TeamSpawn.doAssignTeam() handles
--     the balance check, assignment, and respawn — no logic duplication.
--   • Create BillboardGuis above each part showing team name + player count.
--   • Enable/disable all Beam descendants named "Glow" under each part
--     based on whether that team is currently joinable.
--   • Update billboard text and glow whenever players join, leave, or switch.

local Players             = game:GetService("Players")
local Teams               = game:GetService("Teams")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))

-----------------------------------------------------------------------
-- Config
-----------------------------------------------------------------------
local MAX_TEAM_SIZE  = 8
local DEBOUNCE_TIME  = 3    -- seconds before same player can trigger again

-----------------------------------------------------------------------
-- Wait for dependencies
-----------------------------------------------------------------------

-- AssignTeamBE is created by TeamSpawn.server.lua; wait for it
local assignTeamBE = ServerScriptService:WaitForChild("AssignTeamBE", 30)
if not assignTeamBE then
	warn("[JoinParts] AssignTeamBE BindableEvent not found in ServerScriptService." ..
		" Make sure TeamSpawn.server.lua runs before this script.")
	return
end

-- Join parts in workspace
local joinBlue = workspace:WaitForChild("JoinBlue", 30)
local joinRed  = workspace:WaitForChild("JoinRed",  30)

if not joinBlue then
	warn("[JoinParts] workspace.JoinBlue not found — Blue join part will not work.")
end
if not joinRed then
	warn("[JoinParts] workspace.JoinRed not found — Red join part will not work.")
end

-----------------------------------------------------------------------
-- BillboardGui creation (server-side; replicated to all clients)
-- Floating text only — no background frames.
-----------------------------------------------------------------------
local function createBillboard(part, teamName, accentColor)
	-- Guard: only create once
	if part:FindFirstChild("TeamJoinBillboard") then
		return part:FindFirstChild("TeamJoinBillboard")
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name           = "TeamJoinBillboard"
	billboard.Adornee        = part
	billboard.StudsOffset    = Vector3.new(0, 10, 0)
	billboard.AlwaysOnTop    = false
	billboard.LightInfluence = 0
	billboard.MaxDistance    = 200
	billboard.Size           = UDim2.new(16, 0, 8, 0)  -- studs = shrinks with distance
	billboard.Parent         = part

	-- Team name (e.g. "Knights" / "Barbarians")
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "TeamName"
	nameLabel.Size                   = UDim2.new(1, 0, 0.52, 0)
	nameLabel.Position               = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextScaled             = true
	nameLabel.TextColor3             = accentColor
	nameLabel.TextStrokeTransparency = 0.25
	nameLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	nameLabel.Text                   = TeamDisplayNames.Get(teamName)
	nameLabel.Parent                 = billboard

	-- Count (e.g. "3/8")
	local countLabel = Instance.new("TextLabel")
	countLabel.Name                   = "Count"
	countLabel.Size                   = UDim2.new(1, 0, 0.36, 0)
	countLabel.Position               = UDim2.new(0, 0, 0.50, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Font                   = Enum.Font.GothamBold
	countLabel.TextScaled             = true
	countLabel.TextColor3             = Color3.fromRGB(230, 230, 230)
	countLabel.TextStrokeTransparency = 0.4
	countLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	countLabel.Text                   = "0/" .. MAX_TEAM_SIZE
	countLabel.Parent                 = billboard

	-- Status ("FULL" / "LOCKED" / hidden when joinable)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name                   = "Status"
	statusLabel.Size                   = UDim2.new(1, 0, 0.24, 0)
	statusLabel.Position               = UDim2.new(0, 0, 0.78, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font                   = Enum.Font.GothamBold
	statusLabel.TextScaled             = true
	statusLabel.TextColor3             = Color3.fromRGB(220, 100, 100)
	statusLabel.TextStrokeTransparency = 0.5
	statusLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	statusLabel.Text                   = ""
	statusLabel.Parent                 = billboard

	return billboard
end

-- Create both billboards now (parts may not have all children yet, that's ok)
local blueBillboard = joinBlue and createBillboard(joinBlue, "Blue", Color3.fromRGB(60, 140, 255))
local redBillboard  = joinRed  and createBillboard(joinRed,  "Red",  Color3.fromRGB(255, 60, 60))

-----------------------------------------------------------------------
-- Glow helper
-- Finds all Beam descendants named "Glow" under a part and sets Enabled.
-----------------------------------------------------------------------
local function setGlowEnabled(part, enabled)
	if not part then return end
	local found = 0
	for _, desc in ipairs(part:GetDescendants()) do
		if desc:IsA("Beam") and desc.Name == "Glow" then
			desc.Enabled = enabled
			found += 1
		end
	end
	if found == 0 then
		warn("[JoinParts] No Beam descendants named 'Glow' found under " .. part.Name ..
			". Glow behavior will not work until Glow beams are added.")
	end
end

-----------------------------------------------------------------------
-- isTeamLocked(teamName, blueCount, redCount)
-- Returns (locked: boolean, reason: string).
-- Rule: a team is locked only when it ALREADY has 2+ more players than
-- the other team. A 1-player lead is still joinable.
-- Do NOT simulate the join — use current counts as-is.
-----------------------------------------------------------------------
local function isTeamLocked(teamName, blueCount, redCount)
	local targetCount = teamName == "Blue" and blueCount or redCount
	local otherCount  = teamName == "Blue" and redCount  or blueCount

	if targetCount >= MAX_TEAM_SIZE then
		return true, "FULL"
	end
	if targetCount - otherCount >= 2 then
		return true, "LOCKED"
	end
	return false, ""
end

-----------------------------------------------------------------------
-- updateJoinState()
-- Refreshes billboard text and glow beams for both join parts.
-- Called whenever player counts change.
-----------------------------------------------------------------------
local function updateJoinState()
	local blueTeam = Teams:FindFirstChild("Blue")
	local redTeam  = Teams:FindFirstChild("Red")

	local blueCount, redCount = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Team == blueTeam then
			blueCount += 1
		elseif p.Team == redTeam then
			redCount += 1
		end
	end

	-- ── Blue ────────────────────────────────────────────────────────────────
	local blueLocked, blueReason = isTeamLocked("Blue", blueCount, redCount)

	if joinBlue and blueBillboard then
		local countLbl  = blueBillboard:FindFirstChild("Count",  true)
		local statusLbl = blueBillboard:FindFirstChild("Status", true)
		if countLbl  then countLbl.Text  = blueCount .. "/" .. MAX_TEAM_SIZE end
		if statusLbl then statusLbl.Text = blueLocked and blueReason or "" end
	end

	if joinBlue then setGlowEnabled(joinBlue, not blueLocked) end

	-- ── Red ─────────────────────────────────────────────────────────────────
	local redLocked, redReason = isTeamLocked("Red", blueCount, redCount)

	if joinRed and redBillboard then
		local countLbl  = redBillboard:FindFirstChild("Count",  true)
		local statusLbl = redBillboard:FindFirstChild("Status", true)
		if countLbl  then countLbl.Text  = redCount .. "/" .. MAX_TEAM_SIZE end
		if statusLbl then statusLbl.Text = redLocked and redReason or "" end
	end

	if joinRed then setGlowEnabled(joinRed, not redLocked) end
end

-----------------------------------------------------------------------
-- Wire up count-change events so billboards always stay current
-----------------------------------------------------------------------
local function connectPlayerEvents(p)
	p:GetPropertyChangedSignal("Team"):Connect(updateJoinState)
end

for _, p in ipairs(Players:GetPlayers()) do
	connectPlayerEvents(p)
end

Players.PlayerAdded:Connect(function(p)
	connectPlayerEvents(p)
	task.defer(updateJoinState)
end)

Players.PlayerRemoving:Connect(function()
	task.defer(updateJoinState)
end)

-- Initial state (deferred so teams/players are fully loaded)
task.defer(updateJoinState)

-----------------------------------------------------------------------
-- Per-player debounce table
-----------------------------------------------------------------------
local debounce = {}  -- [Player] = lastTouchTick

Players.PlayerRemoving:Connect(function(p)
	debounce[p] = nil
end)

-----------------------------------------------------------------------
-- Touch handler factory
-- Returns the Touched callback for the given part + teamName.
-----------------------------------------------------------------------
local function makeTouchHandler(teamName)
	return function(hit)
		-- Validate: the hit must be a part of a character
		local character = hit.Parent
		if not character then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		-- Debounce: prevent the same player from firing repeatedly
		local now = tick()
		if debounce[player] and (now - debounce[player]) < DEBOUNCE_TIME then return end
		debounce[player] = now

		-- If the player is already on this team, nothing to do
		if player:GetAttribute("Team") == teamName then return end

		-- Delegate to TeamSpawn's validated assignment function
		assignTeamBE:Fire(player, teamName)
	end
end

-----------------------------------------------------------------------
-- Connect touch events
-----------------------------------------------------------------------
if joinBlue then
	joinBlue.Touched:Connect(makeTouchHandler("Blue"))
end

if joinRed then
	joinRed.Touched:Connect(makeTouchHandler("Red"))
end
