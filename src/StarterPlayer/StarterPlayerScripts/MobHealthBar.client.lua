--[[
	MobHealthBar.client.lua
	Client-side animation layer for mob overhead health bars.

	Responsibilities:
	  • Smooth fill bar transitions on HP change (instant snap, ~0.12 s tween)
	  • Damage lag bar: stays at old position, then tweens to new HP after a delay
	  • Hit flash: brief white overlay on the bar when damage is taken
	  • Corrects initial fill state when a client joins mid-fight

	Works alongside:
	  • MobOverheadHealth.server.lua  — builds the BillboardGui hierarchy
	  • MobHealthFade.client.lua      — fades the whole billboard by distance
--]]

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- Constants (must match MobOverheadHealth.server.lua)
--------------------------------------------------------------------------------
local BILLBOARD_NAME = "MobOverheadHealth"

-- Timings
local FILL_SNAP           = true   -- main fill snaps instantly (no tween, most responsive)
local DAMAGE_BAR_DELAY    = 0.25   -- seconds before damage bar starts catching up
local DAMAGE_BAR_DURATION = 0.45   -- tween duration for damage bar catch-up
local FLASH_OUT_TIME      = 0.12   -- duration of flash fade-out
local PULSE_OUT_TIME      = 0.14   -- bar scale pulse return duration

-- Health colours (must match server)
local COLOR_HIGH = Color3.fromRGB(80, 210, 80)
local COLOR_MID  = Color3.fromRGB(235, 165, 40)
local COLOR_LOW  = Color3.fromRGB(210, 55, 55)

local function healthColor(pct)
	if pct > 0.6 then return COLOR_HIGH
	elseif pct > 0.3 then return COLOR_MID
	else return COLOR_LOW end
end

--------------------------------------------------------------------------------
-- Per-billboard state
-- state[billboard] = {
--   prevPct      : number   — fill pct from last update
--   connections  : table    — event connections for cleanup
--   damageTween  : Tween?   — currently running damage bar tween
--   damageTask   : thread?  — pending task.delay thread (cancellable)
-- }
--------------------------------------------------------------------------------
local state = {}
local trackBillboard
local TRACK_RETRY_DELAY = 0.05
local TRACK_RETRY_LIMIT = 20

local function scheduleTrackRetry(billboard)
	if not billboard or not billboard.Parent then return end
	local s = state[billboard]
	if not s or s.tracked then return end
	if s.retryScheduled then return end
	if (s.retryCount or 0) >= TRACK_RETRY_LIMIT then return end
	s.retryScheduled = true
	task.delay(TRACK_RETRY_DELAY, function()
		local st = state[billboard]
		if not st then return end
		st.retryScheduled = false
		if st.tracked or not billboard.Parent then return end
		st.retryCount = (st.retryCount or 0) + 1
		trackBillboard(billboard)
	end)
end

--------------------------------------------------------------------------------
-- Element accessor (caches nothing; call each time to stay safe)
--------------------------------------------------------------------------------
local function getElements(billboard)
	local bg       = billboard:FindFirstChild("Background")
	local barOuter = bg and bg:FindFirstChild("BarOuter")
	if not barOuter then return nil end
	return {
		fill      = barOuter:FindFirstChild("Fill"),
		damageBar = barOuter:FindFirstChild("DamageBar"),
		hitFlash  = barOuter:FindFirstChild("HitFlash"),
		barScale  = barOuter:FindFirstChild("BarScale"),
	}
end

--------------------------------------------------------------------------------
-- Apply health update with all visual effects
--------------------------------------------------------------------------------
local function onHealthChanged(billboard, newHealth, maxHealth)
	local s = state[billboard]
	if not s then return end

	local el = getElements(billboard)
	if not el then return end

	local newPct = (maxHealth > 0) and math.clamp(newHealth / maxHealth, 0, 1) or 0
	local oldPct = s.prevPct
	s.prevPct = newPct  -- update state immediately

	-- ── Main fill: instant snap to new health ─────────────────────────────
	if el.fill then
		el.fill.Size             = UDim2.fromScale(newPct, 1)
		el.fill.BackgroundColor3 = healthColor(newPct)
	end

	-- ── Hit flash: brief white overlay on any damage ────────────────────────
	if newPct < oldPct and el.hitFlash then
		el.hitFlash.BackgroundTransparency = 0.45
		TweenService:Create(
			el.hitFlash,
			TweenInfo.new(FLASH_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end

	-- ── Bar scale pulse: brief 1.03× grow then snap back on damage ───────────
	if newPct < oldPct and el.barScale then
		el.barScale.Scale = 1.03
		TweenService:Create(
			el.barScale,
			TweenInfo.new(PULSE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	-- ── Damage lag bar ──────────────────────────────────────────────────────
	if el.damageBar then
		if newPct < oldPct then
			-- Cancel any in-flight damage tween/task so we start fresh
			if s.damageTween then
				s.damageTween:Cancel()
				s.damageTween = nil
			end
			if s.damageTask then
				task.cancel(s.damageTask)
				s.damageTask = nil
			end

			-- Keep damage bar at the higher of its current position and oldPct.
			-- This handles rapid multi-hits: bar stays large until it fully catches up.
			local currentDmgScale = el.damageBar.Size.X.Scale
			if currentDmgScale < oldPct then
				-- Damage bar has already caught up past oldPct somehow; pin it back
				el.damageBar.Size = UDim2.fromScale(oldPct, 1)
			end
			-- else: damage bar is still lagging from a previous hit — leave it in place

			-- Schedule catch-up tween after the lag delay
			local captureBillboard = billboard
			local captureNewPct    = newPct
			s.damageTask = task.delay(DAMAGE_BAR_DELAY, function()
				local st = state[captureBillboard]
				if not st then return end
				if not captureBillboard.Parent then return end
				local elNow = getElements(captureBillboard)
				if not elNow or not elNow.damageBar then return end

				local tween = TweenService:Create(
					elNow.damageBar,
					TweenInfo.new(DAMAGE_BAR_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromScale(captureNewPct, 1) }
				)
				st.damageTween = tween
				st.damageTask  = nil
				tween:Play()
			end)

		else
			-- Healing: no trail; damage bar snaps to new (higher) fill position
			if s.damageTween then
				s.damageTween:Cancel()
				s.damageTween = nil
			end
			if s.damageTask then
				task.cancel(s.damageTask)
				s.damageTask = nil
			end
			el.damageBar.Size = UDim2.fromScale(newPct, 1)
		end
	end
end

--------------------------------------------------------------------------------
-- Cleanup a tracked billboard and its connections
--------------------------------------------------------------------------------
local function cleanupBillboard(billboard)
	local s = state[billboard]
	if not s then return end
	for _, c in ipairs(s.connections) do
		c:Disconnect()
	end
	if s.damageTween then s.damageTween:Cancel() end
	if s.damageTask  then task.cancel(s.damageTask) end
	state[billboard] = nil
end

--------------------------------------------------------------------------------
-- Begin tracking a billboard
--------------------------------------------------------------------------------
trackBillboard = function(billboard)
	local s = state[billboard]
	if s and s.tracked then return end  -- already tracked
	if not s then
		s = {
			tracked = false,
			connections = {},
			damageTween = nil,
			damageTask = nil,
			retryScheduled = false,
			retryCount = 0,
		}
		state[billboard] = s
	end

	local attachPart = billboard.Parent
	if not attachPart or not attachPart:IsA("BasePart") then return end
	local model = attachPart.Parent
	if not model or not model:IsA("Model") then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local el = getElements(billboard)
	if not el then
		scheduleTrackRetry(billboard)
		return
	end

	-- Correct initial state from current humanoid HP
	local initPct = (hum.MaxHealth > 0) and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
	if el.fill then
		el.fill.Size             = UDim2.fromScale(initPct, 1)
		el.fill.BackgroundColor3 = healthColor(initPct)
	end
	if el.damageBar then
		el.damageBar.Size = UDim2.fromScale(initPct, 1)
	end

	local connections = s.connections
	s.prevPct = initPct
	s.tracked = true
	s.retryCount = 0

	-- Health change → drive all visual effects
	connections[#connections + 1] = hum.HealthChanged:Connect(function(newHealth)
		if billboard.Parent then
			onHealthChanged(billboard, newHealth, hum.MaxHealth)
		end
	end)

	connections[#connections + 1] = hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if billboard.Parent then
			onHealthChanged(billboard, hum.Health, hum.MaxHealth)
		end
	end)

	-- Billboard removed from workspace → clean up
	connections[#connections + 1] = billboard.AncestryChanged:Connect(function()
		if not billboard:IsDescendantOf(game) then
			cleanupBillboard(billboard)
		end
	end)

	connections[#connections + 1] = billboard.DescendantAdded:Connect(function()
		if not s.tracked then
			scheduleTrackRetry(billboard)
		end
	end)
end

--------------------------------------------------------------------------------
-- Respond to new descendants (billboards may be added after this script loads)
--------------------------------------------------------------------------------
local function onDescendantAdded(inst)
	if inst:IsA("BillboardGui") and inst.Name == BILLBOARD_NAME then
		-- Defer one frame so the server finishes building all child elements
		task.defer(function()
			if inst.Parent then
				trackBillboard(inst)
			end
		end)
		return
	end

	local ancestor = inst.Parent
	while ancestor do
		if ancestor:IsA("BillboardGui") and ancestor.Name == BILLBOARD_NAME then
			scheduleTrackRetry(ancestor)
			return
		end
		ancestor = ancestor.Parent
	end
end

-- Scan what's already in the workspace
for _, desc in ipairs(Workspace:GetDescendants()) do
	onDescendantAdded(desc)
end

-- Watch for mobs that spawn after this script
Workspace.DescendantAdded:Connect(onDescendantAdded)
