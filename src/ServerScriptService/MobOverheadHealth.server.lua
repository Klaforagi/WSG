--[[
	MobOverheadHealth.server.lua
	- Disables default Roblox humanoid name/health display for all players and mobs.
	- Adds a custom stylized overhead health bar to every mob (not players).
	Mob detection: CollectionService tag "ZombieNPC", OR model name "Dummy",
	               OR Humanoid + attribute IsMob = true.
--]]

local Players         = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace       = game:GetService("Workspace")

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local MOB_TAG         = "ZombieNPC"
local BILLBOARD_NAME  = "MobOverheadHealth"
local BILLBOARD_SIZE  = UDim2.fromOffset(160, 42)
local STUDS_OFFSET    = Vector3.new(0, 3.2, 0)
local MAX_DISTANCE    = 55

-- Health-percent colour thresholds
local COLOR_HIGH   = Color3.fromRGB(80, 210, 80)   -- green  (> 60 %)
local COLOR_MID    = Color3.fromRGB(235, 165, 40)  -- orange (30–60 %)
local COLOR_LOW    = Color3.fromRGB(210, 55, 55)   -- red    (< 30 %)

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function isMob(model)
	if not model or not model:IsA("Model") then return false end
	-- Must have a Humanoid to be considered
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	-- Exclude player characters
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character == model then return false end
	end
	-- Tag check
	if CollectionService:HasTag(model, MOB_TAG) then return true end
	-- Name check
	if model.Name == "Dummy" then return true end
	-- Attribute check
	if model:GetAttribute("IsMob") == true then return true end
	return false
end

local function getAttachPart(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function healthColor(pct)
	if pct > 0.6 then return COLOR_HIGH
	elseif pct > 0.3 then return COLOR_MID
	else return COLOR_LOW end
end

------------------------------------------------------------------------
-- Disable default display
------------------------------------------------------------------------
local function disableDefaultDisplay(hum, label)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
	print(string.format("[MobOverheadHealth] Default display disabled for %s", label))
end

------------------------------------------------------------------------
-- Build BillboardGui
------------------------------------------------------------------------
local function buildBillboard(attachPart, mobName)
	-- Avoid duplicates
	local existing = attachPart:FindFirstChild(BILLBOARD_NAME)
	if existing then return existing end

	-- Root billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name            = BILLBOARD_NAME
	billboard.Size            = BILLBOARD_SIZE
	billboard.StudsOffset     = STUDS_OFFSET
	billboard.AlwaysOnTop     = true
	billboard.MaxDistance     = MAX_DISTANCE
	billboard.ResetOnSpawn    = false
	billboard.Enabled         = true

	-- Invisible background container (fully transparent)
	local bg = Instance.new("Frame")
	bg.Name             = "Background"
	bg.Size             = UDim2.fromScale(1, 1)
	bg.Position         = UDim2.fromScale(0, 0)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel  = 0
	bg.Parent           = billboard

	-- Mob name label (centered, bold)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name              = "NameLabel"
	nameLabel.Size              = UDim2.new(1, 0, 0, 15)
	nameLabel.Position          = UDim2.new(0, 0, 0, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text              = mobName
	nameLabel.TextColor3        = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize          = 13
	nameLabel.Font              = Enum.Font.GothamBlack
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Center
	nameLabel.TextTransparency  = 0
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3  = Color3.fromRGB(0, 0, 0)
	nameLabel.Parent            = bg

	-- Health bar track (dark inset, 75% width, centered)
	local barTrack = Instance.new("Frame")
	barTrack.Name             = "BarTrack"
	barTrack.Size             = UDim2.new(0.75, 0, 0, 14)
	barTrack.Position         = UDim2.new(0.125, 0, 0, 22)
	barTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barTrack.BackgroundTransparency = 0.2
	barTrack.BorderSizePixel  = 0
	barTrack.ClipsDescendants = true
	barTrack.Parent           = bg

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = barTrack

	-- Health fill
	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(1, 1)
	fill.Position         = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = COLOR_HIGH
	fill.BorderSizePixel  = 0
	fill.Parent           = barTrack

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	-- HP text overlay on the bar
	local hpText = Instance.new("TextLabel")
	hpText.Name              = "HPText"
	hpText.Size              = UDim2.fromScale(1, 1)
	hpText.Position          = UDim2.fromScale(0, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text              = ""
	hpText.TextColor3        = Color3.fromRGB(255, 255, 255)
	hpText.TextSize          = 12
	hpText.Font              = Enum.Font.GothamBold
	hpText.TextXAlignment    = Enum.TextXAlignment.Center
	hpText.TextStrokeTransparency = 0.4
	hpText.TextStrokeColor3  = Color3.fromRGB(0, 0, 0)
	hpText.ZIndex            = 2
	hpText.Parent            = barTrack

	billboard.Parent = attachPart
	return billboard
end

------------------------------------------------------------------------
-- Update fill bar
------------------------------------------------------------------------
local function updateBar(billboard, health, maxHealth)
	local pct = (maxHealth > 0) and math.clamp(health / maxHealth, 0, 1) or 0
	local fill   = billboard:FindFirstChild("Background")
		and billboard.Background:FindFirstChild("BarTrack")
		and billboard.Background.BarTrack:FindFirstChild("Fill")
	local hpText = billboard:FindFirstChild("Background")
		and billboard.Background:FindFirstChild("BarTrack")
		and billboard.Background.BarTrack:FindFirstChild("HPText")

	if fill then
		fill.Size             = UDim2.fromScale(pct, 1)
		fill.BackgroundColor3 = healthColor(pct)
	end
	if hpText then
		hpText.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
	end
end

------------------------------------------------------------------------
-- Attach custom health UI to a mob
------------------------------------------------------------------------
local function attachMobUI(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Disable default display on mob
	disableDefaultDisplay(hum, "mob " .. model.Name)

	local attachPart = getAttachPart(model)
	if not attachPart then
		warn("[MobOverheadHealth] No attach part found for " .. model:GetFullName())
		return
	end

	-- Reuse existing billboard if present
	local billboard = attachPart:FindFirstChild(BILLBOARD_NAME)
		or buildBillboard(attachPart, model.Name)

	print(string.format("[MobOverheadHealth] Custom health UI created for mob '%s'", model.Name))

	-- Initial state
	updateBar(billboard, hum.Health, hum.MaxHealth)

	-- Track connections for cleanup
	local connections = {}

	connections[1] = hum.HealthChanged:Connect(function(newHealth)
		if billboard and billboard.Parent then
			updateBar(billboard, newHealth, hum.MaxHealth)
		end
	end)

	connections[2] = hum.Died:Connect(function()
		if billboard and billboard.Parent then
			billboard.Enabled = false
			-- Small delay so death animation can play before hiding
			task.delay(0.5, function()
				if billboard and billboard.Parent then
					billboard:Destroy()
				end
			end)
		end
		for _, c in ipairs(connections) do c:Disconnect() end
	end)

	-- Clean up if mob model is destroyed before dying
	connections[3] = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			for _, c in ipairs(connections) do c:Disconnect() end
		end
	end)
end

------------------------------------------------------------------------
-- Player setup: disable default display only, no custom UI
------------------------------------------------------------------------
local function setupPlayer(player)
	local function onCharacter(character)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum then
			disableDefaultDisplay(hum, "player " .. player.Name)
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------

-- Existing players
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)

-- Existing tagged mobs
for _, model in ipairs(CollectionService:GetTagged(MOB_TAG)) do
	if isMob(model) then
		attachMobUI(model)
	end
end

-- Future tagged mobs
CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(model)
	-- Wait one frame so the model is fully parented/set up
	task.defer(function()
		if isMob(model) then
			attachMobUI(model)
		end
	end)
end)

-- Scan Workspace for untagged mobs (Dummy models or IsMob attribute)
local function scanWorkspace()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and isMob(desc) then
			-- Avoid double-processing tagged mobs already handled above
			if not CollectionService:HasTag(desc, MOB_TAG) then
				attachMobUI(desc)
			end
		end
	end
end
scanWorkspace()

-- Watch for future untagged mobs added to Workspace
Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") and isMob(desc) then
		if not CollectionService:HasTag(desc, MOB_TAG) then
			task.defer(function()
				attachMobUI(desc)
			end)
		end
	end
end)
