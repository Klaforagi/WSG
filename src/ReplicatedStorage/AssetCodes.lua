-- AssetCodes Module
-- Central place to store Roblox image/asset IDs (use rbxassetid://<id> format)

local AssetCodes = {}

AssetCodes.images = {
    -- UI icons
    Coin = "rbxassetid://6740408107",
    BlueFlag = "rbxassetid://397459040",
    RedFlag = "rbxassetid://2017769589",
    Shop = "rbxassetid://12674129868",
    Inventory = "rbxassetid://12878997112",
    Options = "rbxassetid://11807310328",
    Quests = "rbxassetid://5750849995",
    Upgrade = "rbxassetid://17368045028",
    Boosts = "rbxassetid://138146402871393",
    Trolls = "rbxassetid://4911139003",
    Team = "rbxassetid://12345678",
    DailyReward = "rbxassetid://6034281693",  -- calendar/gift icon

    --WEAPON icons
    --MELEE
    --Common
    ["Wooden Sword"] = "rbxassetid://137149577851414",
    ["Starter Sword"] = "rbxassetid://137149577851414",
    Branch = "rbxassetid://137149577851414",
   --Uncommon
   ["Stone Hammer"] = "rbxassetid://139192177366165",
    --Rare
    ["Flanged Mace"] = "rbxassetid://80288535043725",
    --Epic
    ["Spiked Mace"] = "rbxassetid://140429696847728",
    --Legendary
    Punisher = "rbxassetid://120062027388705",
    Kingsblade = "rbxassetid://77109527769141",
    --UTILITY
    -- ↓ PLACEHOLDER: replace with a final uploaded bandage icon asset ID later
    Bandage = "rbxassetid://14029553034",

    --RANGED
    Slingshot = "rbxassetid://5830603041",
    ["Starter Slingshot"] = "rbxassetid://5830603041",
    Shortbow = "rbxassetid://15950019592",
    Longbow = "rbxassetid://13303448470",
    Xbow = "rbxassetid://87445004842826",

    -- Emote icons
    EmoteWave = "rbxassetid://4720094407",  -- waving hand icon
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
