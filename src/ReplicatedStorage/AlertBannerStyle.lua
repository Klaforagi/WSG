-- Shared look for match alerts: event names, flag status, and win/sudden death.
-- Text-only banners (no panel fill) so they sit over the world cleanly.

local AlertBannerStyle = {
	Font = Enum.Font.GothamBlack,
	BodyFont = Enum.Font.GothamBold,
	TextColor = Color3.fromRGB(255, 215, 80),
	StrokeColor = Color3.fromRGB(0, 0, 0),
	StrokeThickness = 2,
	StrokeTransparency = 0.12,
	KnightsColor = Color3.fromRGB(65, 130, 255),
	BarbariansColor = Color3.fromRGB(255, 75, 75),
	EventTextSize = 43,
	FlagTextSize = 28,
	WinTextSize = 58,
	SuddenTextSize = 50,
	AvatarSize = 50,
	HoldSeconds = 3.6,
	WinHoldSeconds = 9,
	SuddenHoldSeconds = 4,
}

-- Scale text, portraits, and outlines together, including after device rotation.
function AlertBannerStyle.BindResponsiveScale(frame)
	local input = game:GetService("UserInputService")
	local scale = Instance.new("UIScale")
	scale.Name = "BannerScale"
	scale.Parent = frame
	local connection = game:GetService("RunService").RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or camera.ViewportSize.Y < 100 then return end
		local viewport = camera.ViewportSize
		local target = input.TouchEnabled
			and math.clamp(math.min(viewport.X, viewport.Y) / 800, 0.45, 0.80)
			or math.clamp(viewport.Y / 1080, 0.65, 1)
		target *= 1.85
		local naturalWidth = frame.AbsoluteSize.X / math.max(scale.Scale, 0.01)
		if naturalWidth > 0 then target = math.min(target, viewport.X * 0.92 / naturalWidth) end
		if math.abs(scale.Scale - target) > 0.001 then scale.Scale = target end
	end)
	frame.Destroying:Once(function() connection:Disconnect() end)
	return scale
end

function AlertBannerStyle.TeamColor(teamName)
	if teamName == "Blue" then
		return AlertBannerStyle.KnightsColor
	end
	if teamName == "Red" then
		return AlertBannerStyle.BarbariansColor
	end
	return AlertBannerStyle.TextColor
end

function AlertBannerStyle.ApplyTextStroke(label)
	local stroke = Instance.new("UIStroke")
	stroke.Color = AlertBannerStyle.StrokeColor
	stroke.Thickness = AlertBannerStyle.StrokeThickness
	stroke.Transparency = AlertBannerStyle.StrokeTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return stroke
end

return AlertBannerStyle
