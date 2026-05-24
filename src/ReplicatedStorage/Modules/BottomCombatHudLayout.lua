-- BottomCombatHudLayout.lua
-- Shared responsive layout for the bottom combat HUD: hotbar, dash, and XP bar.

local UserInputService = game:GetService("UserInputService")

local Layout = {}

local GUI_NAME = "BottomCombatHudGui"
local ROOT_NAME = "BottomCombatHudFrame"
local ROW_NAME = "HotbarDashRow"
local HOTBAR_NAME = "HotbarButtonsContainer"
local XP_FRAME_NAME = "XPBarFrame"

local BAR_WIDTH_SCALE = 0.34
local MAX_WIDTH = 720
local DESKTOP_MIN_WIDTH = 420
local TOUCH_MIN_WIDTH = 320

local state = nil

local function getViewportSize()
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
		return cam.ViewportSize.X, cam.ViewportSize.Y
	end
	return 1920, 1080
end

local function ensureFrame(parent, name)
	local frame = parent:FindFirstChild(name)
	if frame and frame:IsA("Frame") then
		return frame
	end
	if frame then
		frame:Destroy()
	end
	frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function computeMetrics()
	local viewportX, viewportY = getViewportSize()
	local uiScale = math.clamp(viewportY / 1080, 0.65, 1.15)
	local touchEnabled = UserInputService.TouchEnabled

	local xpHeight = touchEnabled
		and math.max(30, math.floor(viewportY * 0.031))
		or math.max(36, math.floor(viewportY * 0.034))
	local xpTrackHeight = touchEnabled
		and math.max(11, math.floor(viewportY * 0.014))
		or 16
	local xpLabelSize = touchEnabled
		and math.max(16, math.floor(viewportY * 0.022))
		or math.max(20, math.floor(viewportY * 0.02))

	local safePad = touchEnabled and 16 or 24
	local rawWidth = math.floor((viewportX * BAR_WIDTH_SCALE) + (xpLabelSize * 2) + 24)
	local maxWidth = math.min(MAX_WIDTH, math.max(220, viewportX - (safePad * 2)))
	local minWidth = touchEnabled and TOUCH_MIN_WIDTH or DESKTOP_MIN_WIDTH
	minWidth = math.min(minWidth, maxWidth)
	local rootWidth = math.clamp(rawWidth, minWidth, maxWidth)

	local baseSlotSize = touchEnabled and math.floor(84 * uiScale) or math.floor(96 * uiScale)
	local hotbarGap = touchEnabled and math.max(4, math.floor(6 * uiScale)) or math.max(4, math.floor(8 * uiScale))
	local dashGap = touchEnabled and math.max(8, math.floor(10 * uiScale)) or math.max(10, math.floor(12 * uiScale))
	local maxSlotSize = math.floor((rootWidth - (hotbarGap * 3) - (dashGap * 2)) / 5.96)
	local minSlotSize = 30
	local slotSize = math.max(minSlotSize, math.min(baseSlotSize, maxSlotSize))
	local dashButtonSize = math.max(30, math.floor(slotSize * 0.98))
	local hotbarWidth = (slotSize * 4) + (hotbarGap * 3)
	local rowHeight = math.max(slotSize, dashButtonSize)
	local rowGap = touchEnabled and math.max(8, math.floor(viewportY * 0.008)) or math.max(8, math.floor(viewportY * 0.009))
	local bottomPad = touchEnabled and math.max(6, math.floor(viewportY * 0.006)) or 2
	local rootHeight = rowHeight + rowGap + xpHeight

	return {
		RootWidth = rootWidth,
		RootHeight = rootHeight,
		BottomPad = bottomPad,
		XPHeight = xpHeight,
		XPTrackHeight = xpTrackHeight,
		XPLabelSize = xpLabelSize,
		RowHeight = rowHeight,
		RowGap = rowGap,
		SlotSize = slotSize,
		HotbarGap = hotbarGap,
		HotbarWidth = hotbarWidth,
		DashButtonSize = dashButtonSize,
	}
end

local function applyLayout()
	if not state then
		return computeMetrics()
	end

	local metrics = computeMetrics()
	local root = state.Root
	local row = state.HotbarDashRow
	local hotbar = state.HotbarButtonsContainer
	local xpFrame = state.XPBarFrame

	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -metrics.BottomPad)
	root.Size = UDim2.fromOffset(metrics.RootWidth, metrics.RootHeight)

	xpFrame.AnchorPoint = Vector2.new(0.5, 1)
	xpFrame.Position = UDim2.new(0.5, 0, 1, 0)
	xpFrame.Size = UDim2.new(1, 0, 0, metrics.XPHeight)

	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -(metrics.XPHeight + metrics.RowGap))
	row.Size = UDim2.new(1, 0, 0, metrics.RowHeight)

	hotbar.AnchorPoint = Vector2.new(0.5, 0.5)
	hotbar.Position = UDim2.new(0.5, 0, 0.5, 0)
	hotbar.Size = UDim2.fromOffset(metrics.HotbarWidth, metrics.SlotSize)

	local dashFrame = row:FindFirstChild("DashButtonFrame")
	if dashFrame and dashFrame:IsA("GuiObject") then
		dashFrame.AnchorPoint = Vector2.new(1, 0.5)
		dashFrame.Position = UDim2.new(1, 0, 0.5, 0)
		dashFrame.Size = UDim2.fromOffset(metrics.DashButtonSize, metrics.DashButtonSize)
	end

	return metrics
end

local function bindCamera()
	if not state then return end
	if state.ViewportConn then
		state.ViewportConn:Disconnect()
		state.ViewportConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		state.ViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			applyLayout()
		end)
	end
end

function Layout.Get(playerGui)
	if state and state.Gui and state.Gui.Parent == playerGui then
		state.Metrics = applyLayout()
		return state
	end

	local gui = playerGui:FindFirstChild(GUI_NAME)
	if gui and not gui:IsA("ScreenGui") then
		gui:Destroy()
		gui = nil
	end
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10
		gui.Parent = playerGui
	else
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10
	end

	local root = ensureFrame(gui, ROOT_NAME)
	local row = ensureFrame(root, ROW_NAME)
	local hotbar = ensureFrame(row, HOTBAR_NAME)
	local xpFrame = ensureFrame(root, XP_FRAME_NAME)

	local constraint = root:FindFirstChild("SizeConstraint")
	if not constraint or not constraint:IsA("UISizeConstraint") then
		if constraint then constraint:Destroy() end
		constraint = Instance.new("UISizeConstraint")
		constraint.Name = "SizeConstraint"
		constraint.Parent = root
	end
	constraint.MinSize = Vector2.new(260, 92)
	constraint.MaxSize = Vector2.new(MAX_WIDTH, 190)

	state = {
		Gui = gui,
		Root = root,
		HotbarDashRow = row,
		HotbarButtonsContainer = hotbar,
		XPBarFrame = xpFrame,
		ViewportConn = nil,
		CameraConn = nil,
		Metrics = nil,
	}

	bindCamera()
	state.CameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		applyLayout()
	end)
	state.Metrics = applyLayout()
	task.defer(applyLayout)
	return state
end

function Layout.Apply(playerGui)
	if not state or not state.Gui or state.Gui.Parent ~= playerGui then
		return Layout.Get(playerGui).Metrics
	end
	state.Metrics = applyLayout()
	return state.Metrics
end

return Layout