local TeamDisplayNames = {}

local DISPLAY_NAMES = {
	Blue = "Knights",
	Red = "Barbarians",
}

function TeamDisplayNames.Get(teamName)
	return DISPLAY_NAMES[teamName] or tostring(teamName or "")
end

function TeamDisplayNames.GetUpper(teamName)
	return string.upper(TeamDisplayNames.Get(teamName))
end

return TeamDisplayNames