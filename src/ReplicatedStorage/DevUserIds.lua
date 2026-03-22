-- DevUserIds.lua
-- Centralized list of developer UserIds.
-- Used by both client and server to gate dev-only features (e.g. noclip).

local DevUserIds = {
	[285568988] = true, -- Edithonus
	[285563003] = true, -- Klaf
}

function DevUserIds.IsDev(player)
	return DevUserIds[player.UserId] == true
end

return DevUserIds
