local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PLAYER_RING_ATTRIBUTE = "PlayerHealthRing"
local PLAYER_RING_OWNER_ATTRIBUTE = "PlayerHealthRingOwnerUserId"

local playerConnections = {}
local lastVisible = nil

local function playerRingsVisible()
	local settings = _G.PlayerSettings
	if type(settings) == "table" and settings.ShowPlayerRings ~= nil then
		return settings.ShowPlayerRings ~= false
	end
	return _G.ShowPlayerRings ~= false
end

local function isPlayerRingRoot(instance)
	return instance and instance:GetAttribute(PLAYER_RING_ATTRIBUTE) == true
end

local function getPlayerRingRoot(instance)
	local current = instance
	while current and current ~= Workspace do
		if isPlayerRingRoot(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function setRingDescendantVisible(instance, visible)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = visible and 0 or 1
	elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		instance.Enabled = visible
	elseif instance:IsA("GuiObject") then
		instance.Visible = visible
	elseif instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("ParticleEmitter") then
		instance.Enabled = visible
	end
end

local function setRingVisible(ringRoot, visible)
	if not ringRoot or not ringRoot.Parent then return end
	setRingDescendantVisible(ringRoot, visible)
	for _, descendant in ipairs(ringRoot:GetDescendants()) do
		setRingDescendantVisible(descendant, visible)
	end
end

local function applyPlayerRingVisibility(player)
	if not player then return end
	local visible = playerRingsVisible()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if isPlayerRingRoot(descendant)
			and tonumber(descendant:GetAttribute(PLAYER_RING_OWNER_ATTRIBUTE)) == player.UserId then
			setRingVisible(descendant, visible)
		end
	end
end

local function applyPlayerRingVisibilityToAllPlayers()
	lastVisible = playerRingsVisible()
	for _, player in ipairs(Players:GetPlayers()) do
		applyPlayerRingVisibility(player)
	end
end

_G.RefreshPlayerRingVisibility = applyPlayerRingVisibilityToAllPlayers

local function watchPlayer(player)
	if playerConnections[player] then return end
	playerConnections[player] = player.CharacterAdded:Connect(function()
		task.defer(applyPlayerRingVisibility, player)
		task.delay(0.25, applyPlayerRingVisibility, player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	watchPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local conn = playerConnections[player]
	if conn then
		conn:Disconnect()
		playerConnections[player] = nil
	end
end)

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(function()
		local ringRoot = getPlayerRingRoot(instance)
		if ringRoot then
			setRingVisible(ringRoot, playerRingsVisible())
		end
	end)
end)

task.defer(applyPlayerRingVisibilityToAllPlayers)

task.spawn(function()
	while true do
		task.wait(0.25)
		local visible = playerRingsVisible()
		if visible ~= lastVisible then
			applyPlayerRingVisibilityToAllPlayers()
		end
	end
end)