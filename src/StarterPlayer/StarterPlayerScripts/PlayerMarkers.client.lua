--[[
	PlayerMarkers.client.lua
	Creates a small rotated-square marker as its own BillboardGui.
	- Marker follows the same character anchor as nameplates, but slightly higher.
	- Marker hides when that player is carrying a flag (flag marker takes priority).
	- Teammates: full range + through walls while markers are enabled.
	- Enemies: close-range only.
	- Visibility is controlled by _G.ShowPlayerMarkers (Options menu).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local MARKER_NAME = "PlayerMarkerGui"
local CLOSE_RANGE = 70
local ENEMY_MAX_DISTANCE = 85
local TEAMMATE_FAR_ALPHA = 0.75
local TEAMMATE_MAX_DISTANCE = 100000

local PLAYER_NAMEPLATE_OFFSET_Y = 3.2
local MARKER_EXTRA_HEIGHT = 0.55
local MARKER_STUDS_OFFSET = Vector3.new(0, PLAYER_NAMEPLATE_OFFSET_Y + MARKER_EXTRA_HEIGHT, 0)

local MARKER_SIZE = UDim2.fromOffset(10, 10)
local MARKER_STROKE = 1

local TEAM_COLORS = {
	Blue = Color3.fromRGB(85, 170, 255),
	Red = Color3.fromRGB(255, 95, 95),
}

local markers = {}
local playersConnected = {}

local function getCharacterRoot(character)
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
end

local function getAttachPart(character)
	if not character then
		return nil
	end
	return character:FindFirstChild("Head")
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChildWhichIsA("BasePart")
end

local function isTeammate(player)
	if not player or player == localPlayer then
		return false
	end
	return localPlayer.Team and player.Team and localPlayer.Team == player.Team
end

local function getTeamColor(player)
	if player and player.Team then
		return TEAM_COLORS[player.Team.Name] or player.Team.TeamColor.Color
	end
	return Color3.fromRGB(255, 226, 120)
end

local function ensureMarkerForPlayer(player)
	if not player or player == localPlayer then
		return
	end

	local character = player.Character
	local attachPart = getAttachPart(character)
	if not attachPart then
		return
	end

	local existing = attachPart:FindFirstChild(MARKER_NAME)
	if existing and existing:IsA("BillboardGui") then
		markers[player] = existing
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = MARKER_NAME
	gui.Size = UDim2.fromOffset(24, 24)
	gui.StudsOffset = MARKER_STUDS_OFFSET
	gui.AlwaysOnTop = false
	gui.MaxDistance = ENEMY_MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.LightInfluence = 0
	gui.Enabled = true
	gui.Parent = attachPart

	local holder = Instance.new("Frame")
	holder.Name = "Diamond"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = MARKER_SIZE
	holder.BackgroundColor3 = getTeamColor(player)
	holder.BorderSizePixel = 0
	holder.Rotation = 45
	holder.BackgroundTransparency = 0
	holder.ZIndex = 2
	holder.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = MARKER_STROKE
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.25
	stroke.Parent = holder

	markers[player] = gui
end

local function cleanupPlayer(player)
	local gui = markers[player]
	if gui and gui.Parent then
		gui:Destroy()
	end
	markers[player] = nil

	local conns = playersConnected[player]
	if conns then
		for _, conn in ipairs(conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		playersConnected[player] = nil
	end
end

local function refreshMarker(player)
	if not player or player == localPlayer then
		return
	end

	local gui = markers[player]
	if not gui or not gui.Parent then
		ensureMarkerForPlayer(player)
		gui = markers[player]
	end
	if not gui then
		return
	end

	local attachPart = getAttachPart(player.Character)
	if not attachPart then
		gui.Enabled = false
		return
	end
	if gui.Parent ~= attachPart then
		gui.Parent = attachPart
	end
	gui.StudsOffset = MARKER_STUDS_OFFSET

	local marker = gui:FindFirstChild("Diamond")
	if not marker or not marker:IsA("Frame") then
		return
	end

	marker.BackgroundColor3 = getTeamColor(player)
	local teammate = isTeammate(player)
	local showMarkers = (_G.ShowPlayerMarkers ~= false)
	local carryingFlag = player:GetAttribute("CarryingFlag")
	if not showMarkers then
		gui.Enabled = false
		return
	end

	local myCharacter = localPlayer.Character
	local myRoot = getCharacterRoot(myCharacter)
	local theirRoot = getCharacterRoot(player.Character)

	if not myRoot or not theirRoot then
		gui.Enabled = false
		return
	end

	local dist = (theirRoot.Position - myRoot.Position).Magnitude
	local hasFlag = (type(carryingFlag) == "string" and carryingFlag ~= "")
	local useMarkerMode = (dist > CLOSE_RANGE) and (not hasFlag)

	if teammate then
		gui.Enabled = useMarkerMode
		gui.AlwaysOnTop = true
		gui.MaxDistance = TEAMMATE_MAX_DISTANCE
		marker.BackgroundTransparency = (dist > CLOSE_RANGE) and (1 - TEAMMATE_FAR_ALPHA) or 0
		return
	end

	gui.AlwaysOnTop = false
	gui.MaxDistance = ENEMY_MAX_DISTANCE
	gui.Enabled = useMarkerMode and (dist <= ENEMY_MAX_DISTANCE)
	marker.BackgroundTransparency = 0
end

local function refreshAllMarkers()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			refreshMarker(player)
		end
	end
end

_G.RefreshPlayerMarkers = refreshAllMarkers

local function bindPlayer(player)
	if player == localPlayer or playersConnected[player] then
		return
	end

	playersConnected[player] = {
		player.CharacterAdded:Connect(function()
			task.defer(function()
				ensureMarkerForPlayer(player)
				refreshMarker(player)
			end)
		end),
		player:GetPropertyChangedSignal("Team"):Connect(function()
			refreshMarker(player)
		end),
		player:GetAttributeChangedSignal("CarryingFlag"):Connect(function()
			refreshMarker(player)
		end),
	}

	ensureMarkerForPlayer(player)
	refreshMarker(player)
end

Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	cleanupPlayer(player)
end)

localPlayer:GetPropertyChangedSignal("Team"):Connect(function()
	refreshAllMarkers()
end)

localPlayer.CharacterAdded:Connect(function()
	task.wait(0.15)
	refreshAllMarkers()
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

RunService.Heartbeat:Connect(function()
	if _G.ShowPlayerMarkers == false then
		for _, gui in pairs(markers) do
			if gui and gui.Parent then
				gui.Enabled = false
			end
		end
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			refreshMarker(player)
		end
	end
end)
