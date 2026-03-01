-- AssetCodes Module
-- Central place to store Roblox image/asset IDs (use rbxassetid://<id> format)

local AssetCodes = {}

AssetCodes.images = {
    -- replace these placeholders with real asset IDs later
    Coin = "rbxassetid://6740408107",
    Flag = "rbxassetid://87654321",
}

-- Returns the asset string for a named key, or nil
function AssetCodes.Get(name)
    return AssetCodes.images[name]
end

-- Sets/updates an asset id for a named key. Accepts number or string.
function AssetCodes.Set(name, id)
    if not name or id == nil then return end
    local out
    if type(id) == "number" then
        out = "rbxassetid://" .. tostring(id)
    else
        out = tostring(id)
    end
    AssetCodes.images[name] = out
    return out
end

-- Returns a shallow copy of the images table
function AssetCodes.List()
    local copy = {}
    for k,v in pairs(AssetCodes.images) do copy[k] = v end
    return copy
end

return AssetCodes
