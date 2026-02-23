-- XPServiceModule.lua
-- Exposes AwardXP(...) for other server scripts to call.
-- Safe to require before XPService.server.lua has run — stubs warn instead of erroring.

local Module = {}
Module._ready = false

-- Placeholder stubs; XPService.server.lua will overwrite these on startup.
Module.AwardXP = function(player, reason, amountOverride, metadata)
    warn("[XPServiceModule] AwardXP called before XPService initialized — ignoring")
    return false
end

Module.GetPlayerData = function(player)
    warn("[XPServiceModule] GetPlayerData called before XPService initialized")
    return nil
end

Module.GetMobXP = function(mobName)
    warn("[XPServiceModule] GetMobXP called before XPService initialized")
    return 3
end

return Module
