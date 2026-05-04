local TeamDisplayNames = {}

local DISPLAY_NAMES = {
	Blue = "Knights",
	Red = "Barbarians",
}

local NORMALIZED_DISPLAY_NAMES = {
	blue = DISPLAY_NAMES.Blue,
	red = DISPLAY_NAMES.Red,
}

function TeamDisplayNames.Get(teamName)
	local name = tostring(teamName or "")
	return DISPLAY_NAMES[name] or NORMALIZED_DISPLAY_NAMES[string.lower(name)] or name
end

function TeamDisplayNames.GetUpper(teamName)
	return string.upper(TeamDisplayNames.Get(teamName))
end

return TeamDisplayNames