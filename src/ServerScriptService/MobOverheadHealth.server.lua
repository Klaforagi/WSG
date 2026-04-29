--[[
	MobOverheadHealth.server.lua
	- Disables default Roblox humanoid name/health display for all players and mobs.
	- Adds a polished overhead health bar to every mob (not players).
	- Visual animations (smooth tween, damage lag bar, hit flash) are handled
	  client-side in MobHealthBar.client.lua.
	Mob detection: CollectionService tag "ZombieNPC", OR model name "Dummy",
	               OR Humanoid + attribute IsMob = true.
--]]

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local MOB_TAG        = "ZombieNPC"
local BILLBOARD_NAME = "MobOverheadHealth"
local BILLBOARD_SIZE = UDim2.fromOffset(200, 50)
local STUDS_OFFSET   = Vector3.new(0, 3.5, 0)
local MAX_DISTANCE   = 55

-- Health-percent colour thresholds (mirrored in MobHealthBar.client.lua)
local COLOR_HIGH = Color3.fromRGB(80, 210, 80)   -- green  (> 60 %)
local COLOR_MID  = Color3.fromRGB(235, 165, 40)  -- orange (30–60 %)
local COLOR_LOW  = Color3.fromRGB(210, 55, 55)   -- red    (< 30 %)
local COLOR_DMG  = Color3.fromRGB(180, 40, 40)   -- damage lag bar tint

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
	local existing = attachPart:FindFirstChild(BILLBOARD_NAME)
	if existing then return existing end

	-- Root billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name         = BILLBOARD_NAME
	billboard.Size         = BILLBOARD_SIZE
	billboard.StudsOffset  = STUDS_OFFSET
	billboard.AlwaysOnTop  = true
	billboard.MaxDistance  = MAX_DISTANCE
	billboard.ResetOnSpawn = false
	billboard.Enabled      = true

	-- Invisible root container
	local bg = Instance.new("Frame")
	bg.Name                   = "Background"
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.Position               = UDim2.fromScale(0, 0)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel        = 0
	bg.Parent                 = billboard

	------------ Name label (bold, crisp UIStroke outline) ------------
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "NameLabel"
	nameLabel.Size                   = UDim2.new(1, 0, 0, 16)
	nameLabel.Position               = UDim2.new(0, 0, 0, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = mobName
	nameLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize               = 14
	nameLabel.Font                   = Enum.Font.GothamBlack
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Center
	nameLabel.TextTransparency       = 0
	nameLabel.TextStrokeTransparency = 1  -- disabled; UIStroke below handles it
	nameLabel.ZIndex                 = 2
	nameLabel.Parent                 = bg

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Name            = "NameStroke"
	nameStroke.Color           = Color3.fromRGB(0, 0, 0)
	nameStroke.Thickness       = 1.5
	nameStroke.Transparency    = 0.1
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nameStroke.Parent          = nameLabel

	------------ Drop shadow behind health bar (subtle depth halo) ------------
	local barShadow = Instance.new("Frame")
	barShadow.Name                   = "BarShadow"
	barShadow.Size                   = UDim2.new(0.76, 6, 0, 20)   -- slightly larger than barOuter
	barShadow.Position               = UDim2.new(0.12, -3, 0, 16)  -- centred around barOuter with 1px offset
	barShadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	barShadow.BackgroundTransparency = 0.60
	barShadow.BorderSizePixel        = 0
	barShadow.ZIndex                 = 0
	barShadow.Parent                 = bg

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 10)
	shadowCorner.Parent       = barShadow

	------------ Health bar outer frame (dark track, rounded, padded) ------------
	local barOuter = Instance.new("Frame")
	barOuter.Name                   = "BarOuter"
	barOuter.Size                   = UDim2.new(0.76, 0, 0, 16)  -- ~12% narrower than before
	barOuter.Position               = UDim2.new(0.12, 0, 0, 18)  -- slight gap reduction from name
	barOuter.BackgroundColor3       = Color3.fromRGB(18, 18, 18)
	barOuter.BackgroundTransparency = 0.50  -- lighter so missing-HP area reads clearly
	barOuter.BorderSizePixel        = 0
	barOuter.ClipsDescendants       = true  -- clips fill/damage bar to rounded bounds
	barOuter.ZIndex                 = 1
	barOuter.Parent                 = bg

	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0, 8)  -- near-pill on a 16 px tall bar
	outerCorner.Parent       = barOuter

	-- Dark border for depth
	local outerStroke = Instance.new("UIStroke")
	outerStroke.Name            = "BarStroke"
	outerStroke.Color           = Color3.fromRGB(0, 0, 0)
	outerStroke.Thickness       = 1
	outerStroke.Transparency    = 0.35
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Parent          = barOuter

	-- UIScale used by MobHealthBar.client.lua for the hit-pulse (tweens 1 → 1.03 → 1)
	local barScale = Instance.new("UIScale")
	barScale.Name   = "BarScale"
	barScale.Scale  = 1
	barScale.Parent = barOuter

	------------ Damage lag bar (dark red, sits behind fill) ------------
	-- Reveals between Fill's right edge and DamageBar's right edge on damage.
	local damageBar = Instance.new("Frame")
	damageBar.Name             = "DamageBar"
	damageBar.Size             = UDim2.fromScale(1, 1)
	damageBar.Position         = UDim2.fromScale(0, 0)
	damageBar.BackgroundColor3 = COLOR_DMG
	damageBar.BorderSizePixel  = 0
	damageBar.ZIndex           = 2
	damageBar.Parent           = barOuter

	local damageBarCorner = Instance.new("UICorner")
	damageBarCorner.CornerRadius = UDim.new(0, 8)
	damageBarCorner.Parent       = damageBar

	------------ Health fill (client tweens this; server sets initial state) ------------
	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(1, 1)
	fill.Position         = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = COLOR_HIGH
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 3
	fill.Parent           = barOuter

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent       = fill

	-- Top-to-bottom gradient: lighter highlight at top, slightly darker at bottom
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Name     = "FillGradient"
	fillGradient.Rotation = 90
	fillGradient.Color    = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 255, 255)), -- top: bright highlight
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(210, 210, 210)), -- mid fade
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(115, 115, 115)), -- bottom: ~45% brightness
	})
	fillGradient.Parent = fill

	------------ HP text (centred over the bar) ------------
	local hpText = Instance.new("TextLabel")
	hpText.Name                   = "HPText"
	hpText.Size                   = UDim2.fromScale(1, 1)
	hpText.Position               = UDim2.fromScale(0, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text                   = ""
	hpText.TextColor3             = Color3.fromRGB(255, 255, 255)
	hpText.TextSize               = 11
	hpText.Font                   = Enum.Font.GothamBold
	hpText.TextXAlignment         = Enum.TextXAlignment.Center
	hpText.TextStrokeTransparency = 1  -- disabled; UIStroke below handles it
	hpText.ZIndex                 = 4
	hpText.Parent                 = barOuter

	local hpStroke = Instance.new("UIStroke")
	hpStroke.Name            = "HPStroke"
	hpStroke.Color           = Color3.fromRGB(0, 0, 0)
	hpStroke.Thickness       = 1.2
	hpStroke.Transparency    = 0.15
	hpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	hpStroke.Parent          = hpText

	------------ Hit flash overlay (white, invisible by default) ------------
	-- MobHealthBar.client.lua briefly turns this semi-opaque on damage.
	local hitFlash = Instance.new("Frame")
	hitFlash.Name                   = "HitFlash"
	hitFlash.Size                   = UDim2.fromScale(1, 1)
	hitFlash.Position               = UDim2.fromScale(0, 0)
	hitFlash.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	hitFlash.BackgroundTransparency = 1
	hitFlash.BorderSizePixel        = 0
	hitFlash.ZIndex                 = 5
	hitFlash.Parent                 = barOuter

	billboard.Parent = attachPart
	return billboard
end

------------------------------------------------------------------------
-- Set initial bar state (fill + damage bar + hp text) — called once.
-- Thereafter, MobHealthBar.client.lua owns fill/damageBar visuals.
------------------------------------------------------------------------
local function setInitialBar(billboard, health, maxHealth)
	local pct    = (maxHealth > 0) and math.clamp(health / maxHealth, 0, 1) or 0
	local bg     = billboard:FindFirstChild("Background")
	local outer  = bg and bg:FindFirstChild("BarOuter")
	local fill   = outer and outer:FindFirstChild("Fill")
	local dmgBar = outer and outer:FindFirstChild("DamageBar")
	local hpText = outer and outer:FindFirstChild("HPText")

	if fill then
		fill.Size             = UDim2.fromScale(pct, 1)
		fill.BackgroundColor3 = healthColor(pct)
	end
	if dmgBar then
		dmgBar.Size = UDim2.fromScale(pct, 1)
	end
	if hpText then
		hpText.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
	end
end

------------------------------------------------------------------------
-- Update HP text only (server-side; fill animations live in client).
------------------------------------------------------------------------
local function updateHPText(billboard, health, maxHealth)
	local bg     = billboard:FindFirstChild("Background")
	local outer  = bg and bg:FindFirstChild("BarOuter")
	local hpText = outer and outer:FindFirstChild("HPText")
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

	-- Set initial fill/text state (client will own animated updates from here on)
	setInitialBar(billboard, hum.Health, hum.MaxHealth)

	-- Track connections for cleanup
	local connections = {}

	-- Server only updates the HP text; fill bar animations are client-side
	connections[1] = hum.HealthChanged:Connect(function(newHealth)
		if billboard and billboard.Parent then
			updateHPText(billboard, newHealth, hum.MaxHealth)
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
