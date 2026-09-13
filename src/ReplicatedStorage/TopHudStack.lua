-- Pixel Y stacking for the top-center match HUD:
-- scoreboard, then top-elims portraits, then text alerts.

local Players = game:GetService("Players")

local AlertBannerStyle = require(script.Parent:WaitForChild("AlertBannerStyle"))

local TopHudStack = {}
TopHudStack.Gap = 6

local KILLERS_UI_SCALE = 0.6

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

local function findDescendant(parent, name)
	if not parent then
		return nil
	end
	return parent:FindFirstChild(name, true)
end

function TopHudStack.GetKillersHeight()
	local vw = getViewport()
	local slotPx = math.clamp(math.floor(vw * 0.05 * KILLERS_UI_SCALE), 24, 80 * KILLERS_UI_SCALE)
	return slotPx + math.floor(slotPx * 0.4)
end

function TopHudStack.GetScoreboardBottom()
	local pg = getPlayerGui()
	local hud = pg and pg:FindFirstChild("MatchHUD")
	local root = hud and findDescendant(hud, "ScoreboardRoot")
	if root and root.Visible and root.AbsoluteSize.Y > 1 then
		return root.AbsolutePosition.Y + root.AbsoluteSize.Y
	end
	local _, vh = getViewport()
	return math.floor(vh * 0.01) + math.floor(vh * 0.1)
end

function TopHudStack.GetKillersTop()
	return TopHudStack.GetScoreboardBottom() + TopHudStack.Gap
end

function TopHudStack.GetAlertTop()
	local pg = getPlayerGui()
	local hud = pg and pg:FindFirstChild("TopPvpKillersHud")
	local root = hud and hud:FindFirstChild("Root")
	if root and root.Visible and root.AbsoluteSize.Y > 1 then
		return root.AbsolutePosition.Y + root.AbsoluteSize.Y + TopHudStack.Gap
	end
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

return TopHudStack
