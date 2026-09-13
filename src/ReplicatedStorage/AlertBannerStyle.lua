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
	EventTextSize = 34,
	FlagTextSize = 22,
	WinTextSize = 52,
	SuddenTextSize = 40,
	AvatarSize = 40,
	HoldSeconds = 3.6,
	WinHoldSeconds = 9,
	SuddenHoldSeconds = 4,
}

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
