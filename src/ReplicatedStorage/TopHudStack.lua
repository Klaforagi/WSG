-- Pixel Y stacking for the top-center match HUD:
-- scoreboard, then top-elims portraits, then text alerts.

local Players = game:GetService("Players")

local AlertBannerStyle = require(script.Parent:WaitForChild("AlertBannerStyle"))

local TopHudStack = {}
TopHudStack.Gap = 8
TopHudStack.KillersBelowScoreboardPad = 32
TopHudStack.KillersHeightScale = 0.85
TopHudStack.KillersSlotGap = 12

local layoutListeners = {}

local function getPlayerGui()
	local player = Players.LocalPlayer
	return player and player:FindFirstChild("PlayerGui")
end

local function getViewport()
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 1 and cam.ViewportSize.Y > 1 then
		return cam.ViewportSize.X, cam.ViewportSize.Y
	end
	return 1280, 720
end

local function getScoreboardRoot()
	local pg = getPlayerGui()
	local hud = pg and pg:FindFirstChild("MatchHUD")
	return hud and hud:FindFirstChild("ScoreboardRoot")
end

local function getKillersRoot()
	local pg = getPlayerGui()
	local hud = pg and pg:FindFirstChild("TopPvpKillersHud")
	return hud and hud:FindFirstChild("Root")
end

function TopHudStack.GetScoreboardHeight()
	local root = getScoreboardRoot()
	if root and root.AbsoluteSize.Y > 1 then
		return root.AbsoluteSize.Y
	end
	local _, vh = getViewport()
	return math.floor(vh * 0.1)
end

function TopHudStack.GetScoreboardBottom()
	local root = getScoreboardRoot()
	local _, vh = getViewport()
	local fallback = math.floor(vh * 0.01) + TopHudStack.GetScoreboardHeight()
	if root and root.Visible and root.AbsoluteSize.Y > 1 then
		return math.max(root.AbsolutePosition.Y + root.AbsoluteSize.Y, fallback)
	end
	return fallback
end

function TopHudStack.GetKillersSlotPx()
	return math.max(32, math.floor(TopHudStack.GetScoreboardHeight() * TopHudStack.KillersHeightScale))
end

function TopHudStack.GetKillersHeight()
	local root = getKillersRoot()
	if root and root.AbsoluteSize.Y > 1 then
		return root.AbsoluteSize.Y
	end
	return TopHudStack.GetKillersSlotPx()
end

function TopHudStack.GetKillersTop()
	return TopHudStack.GetScoreboardBottom() + TopHudStack.KillersBelowScoreboardPad
end

function TopHudStack.GetAlertTop()
	return TopHudStack.GetKillersTop() + TopHudStack.GetKillersHeight() + TopHudStack.Gap
end

function TopHudStack.GetKillersPosition()
	return UDim2.new(0.5, 0, 0, TopHudStack.GetKillersTop())
end

function TopHudStack.GetAlertPosition()
	return UDim2.new(0.5, 0, 0, TopHudStack.GetAlertTop())
end

function TopHudStack.GetRegularAlertHeight()
	return math.max(AlertBannerStyle.EventTextSize, AlertBannerStyle.AvatarSize) + 8
end

local function getLiveAlertBottom()
	local pg = getPlayerGui()
	local gui = pg and pg:FindFirstChild("FlagStatusGui")
	if not gui then
		return nil
	end
	local bottom = nil
	for _, child in ipairs(gui:GetChildren()) do
		if child.Name == "FlagMsgPanel" and child.AbsoluteSize.Y > 1 then
			local childBottom = child.AbsolutePosition.Y + child.AbsoluteSize.Y
			if not bottom or childBottom > bottom then
				bottom = childBottom
			end
		end
	end
	return bottom
end

function TopHudStack.GetWinTop()
	local reservedBottom = TopHudStack.GetAlertTop() + TopHudStack.GetRegularAlertHeight()
	local liveBottom = getLiveAlertBottom() or reservedBottom
	return math.max(reservedBottom, liveBottom) + TopHudStack.Gap
end

function TopHudStack.GetWinPosition()
	return UDim2.new(0.5, 0, 0, TopHudStack.GetWinTop())
end

function TopHudStack.OnLayoutChanged(callback)
	if type(callback) ~= "function" then
		return
	end
	table.insert(layoutListeners, callback)
end

function TopHudStack.NotifyLayoutChanged()
	for _, callback in ipairs(layoutListeners) do
		pcall(callback)
	end
end

return TopHudStack
