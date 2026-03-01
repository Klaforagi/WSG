-- AssetCodes Module
-- Central place to store Roblox image/asset IDs (use rbxassetid://<id> format)

local AssetCodes = {}

AssetCodes.images = {
    -- replace these placeholders with real asset IDs later
    Coin = "rbxassetid://6740408107",
    BlueFlag = "rbxassetid://397459040",
    RedFlag = "rbxassetid://2017769589",
    Shop = "rbxassetid://77580506639212",
    Options = "rbxassetid://11807310328",
    Quests = "rbxassetid://5750849995",
    Upgrade = "rbxassetid://17368045028",
    Boosts = "rbxassetid://138146402871393",
    Trolls = "rbxassetid://4911139003",
    Team = "rbxassetid://12345678",
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
