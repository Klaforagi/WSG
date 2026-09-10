-- AssetCodes Module
-- Central place to store Roblox image/asset IDs (use rbxassetid://<id> format)

local AssetCodes = {}

AssetCodes.images = {
    -- GAME icons
    Logo = "rbxassetid://134714248434074",  
    -- UI icons
    Coin = "rbxassetid://15589362394",
    Shards = "rbxassetid://138717301679393",
    Key = "rbxassetid://126037497405484",
    Robux = "rbxassetid://11560341824",
    BlueFlag = "rbxassetid://397459040",
    RedFlag = "rbxassetid://2017769589",
    Shop = "rbxassetid://12674129868",
    Inventory = "rbxassetid://12878997112",
    Options = "rbxassetid://11807310328",
    Quests = "rbxassetid://5750849995",
    SideShop = "rbxassetid://132240746566342",
    SideInventory = "rbxassetid://88658578258778",
    SideAchieves = "rbxassetid://14153470806",
    Upgrade = "rbxassetid://17368045028",
    Boosts = "rbxassetid://138146402871393",
    Event = "",      -- replace with a final uploaded event icon asset ID later
    HealBuff = "",   -- replace with a final uploaded heal buff icon asset ID later
    Trolls = "rbxassetid://4911139003",
    Team = "rbxassetid://93323617037148",
    DailyReward = "rbxassetid://6034281693",  -- calendar/gift icon
    KnightPreview = "",      -- static inventory/shop preview for the Knight skin
    IronKnightPreview = "",   -- static inventory/shop preview for the Iron Knight skin
    GoblinPreview = "",       -- static inventory/shop preview for the Goblin skin
    --POTION icons
    HealthPotion = "rbxassetid://100548032317989",
    SpeedPotion = "rbxassetid://112364730003039",
    StrengthPotion = "rbxassetid://74649590699347",
    ["2xCoinsElixir"] = "rbxassetid://94023162242458",
    ["2xXPElixir"] = "rbxassetid://93623567142594",
    ["2xMasteryElixir"] = "rbxassetid://135725356152560",
    SpeedElixir = "rbxassetid://79419027714389",
    StrengthElixir = "rbxassetid://135034291396159",
    HealthElixir = "rbxassetid://132326360806365",
    PowerElixir = "rbxassetid://135034291396159",
    VitalityElixir = "rbxassetid://132326360806365",
    --WEAPON icons
    --MELEE
    Melee = "rbxassetid://856575323",
    --Common
    ["Wooden Sword"] = "rbxassetid://137149577851414",
    ["Starter Sword"] = "rbxassetid://137149577851414",
    Branch = "rbxassetid://77658206141783",
    Bat = "rbxassetid://70714531979735",
    Plunger = "rbxassetid://106479991943542",
   --Uncommon
   ["Stone Hammer"] = "rbxassetid://139192177366165",
   ["Wooden Spear"] = "rbxassetid://86988825914270",
   Axe = "rbxassetid://96497459859557",
    --Rare
    ["Flanged Mace"] = "rbxassetid://80288535043725",
    Spear = "rbxassetid://92401070096107",
    Shortsword = "rbxassetid://87749478192733",
    ["Lil Crusher"] = "rbxassetid://123803527576267",
    --Epic
    ["Spiked Mace"] = "rbxassetid://140429696847728",
    Crusher = "rbxassetid://70478795441387",
    ["Ethereal Sword"] = "rbxassetid://111494866162478",
    --Legendary
    Punisher = "rbxassetid://120062027388705",
    Kingsblade = "rbxassetid://77109527769141",
    ["Doom Sword"] = "rbxassetid://131537900374777",
    --UTILITY
    -- ↓ PLACEHOLDER: replace with a final uploaded bandage icon asset ID later
    Bandage = "rbxassetid://14029553034",

    --RANGED
    Ranged = "rbxassetid://13303448470",
    --Common
    -- Paste uploaded icon texture IDs as "rbxassetid://<id>". Empty values
    -- fall back to the tool TextureId until you fill these in.
    ["Starter Slingshot"] = "",
    Slingshot = "",
    Bow = "",
    --Uncommon
    ["Pixel Bow"] = "",
    ["Elderwood Bow"] = "",
    --Rare
    ["Ironwood Bow"] = "",
    ["Skeletal Bow"] = "",
    --Epic
    -- Ethereal Bow icons are per-enchant; see weaponEnchantIcons below.
    ["Ethereal Bow"] = "",
    --Legendary
    ["Golden Bow"] = "",



    -- MAP ICONS
    thepit = "rbxassetid://123730386850830",
    forest = "rbxassetid://103357261697578",
    ["Frozen Lake"] = "rbxassetid://103449125404264",
    frozenlake = "rbxassetid://103449125404264",
    wintergate = "rbxassetid://103449125404264",

    -- Emote icons. Fill these with uploaded image IDs; empty values use UI fallback visuals.
    EmoteWave = "",
    EmoteDance = "",
    EmoteMoney = "",
    EmoteTakeTheL = "",
    EmoteHeadless = "",
    EmoteRatDance = "",
    EmoteFloss = "",
    EmoteDab = "",
    EmoteMacarena = "",
    EmoteRideThePony = "",
    EmoteRobot = "",
}

-- Per-enchant weapon icons. Used when a weapon's look depends on its enchant.
AssetCodes.weaponEnchantIcons = {
    ["Ethereal Bow"] = {
        Lifesteal = "rbxassetid://84955260485481",
        Fiery     = "rbxassetid://110375733339041",
        Shock     = "rbxassetid://98845734477861",
        Toxic     = "rbxassetid://126119811248143",
        Icy       = "rbxassetid://119934736385316",
        Void      = "rbxassetid://131226844312711",
    },
}

local function normalizeAssetId(id)
    if type(id) == "number" then
        return "rbxassetid://" .. tostring(id)
    end
    if type(id) ~= "string" then
        return nil
    end
    local trimmed = id:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    if string.find(trimmed, "rbxassetid://", 1, true) == 1 then
        return trimmed
    end
    if tonumber(trimmed) then
        return "rbxassetid://" .. trimmed
    end
    return trimmed
end

-- Returns the asset string for a named key, or nil. Accepts raw numeric IDs
-- and matches keys case-insensitively.
function AssetCodes.Get(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local direct = normalizeAssetId(AssetCodes.images[name])
    if direct then
        return direct
    end

    local lowerName = string.lower(name)
    for key, value in pairs(AssetCodes.images) do
        if type(key) == "string" and string.lower(key) == lowerName then
            return normalizeAssetId(value)
        end
    end

    return nil
end

-- Weapon icon lookup that can swap by enchant (Ethereal Bow, etc.).
function AssetCodes.GetWeaponIcon(weaponName, enchantName)
    if type(weaponName) ~= "string" or weaponName == "" then
        return nil
    end

    local byEnchant = AssetCodes.weaponEnchantIcons[weaponName]
    if not byEnchant then
        local lowerName = string.lower(weaponName)
        for name, icons in pairs(AssetCodes.weaponEnchantIcons) do
            if type(name) == "string" and string.lower(name) == lowerName then
                byEnchant = icons
                break
            end
        end
    end

    if type(byEnchant) == "table" and type(enchantName) == "string" then
        local trimmed = enchantName:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" and trimmed ~= "None" then
            local icon = byEnchant[trimmed]
            if not icon then
                local lowerEnchant = string.lower(trimmed)
                for name, value in pairs(byEnchant) do
                    if type(name) == "string" and string.lower(name) == lowerEnchant then
                        icon = value
                        break
                    end
                end
            end
            icon = normalizeAssetId(icon)
            if icon then
                return icon
            end
        end
    end

    return AssetCodes.Get(weaponName)
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

-- Returns a shallow copy of the images table, including per-enchant weapon icons.
function AssetCodes.List()
    local copy = {}
    for k,v in pairs(AssetCodes.images) do copy[k] = v end
    for weaponName, byEnchant in pairs(AssetCodes.weaponEnchantIcons) do
        if type(byEnchant) == "table" then
            for enchantName, assetId in pairs(byEnchant) do
                copy[tostring(weaponName) .. "_" .. tostring(enchantName)] = assetId
            end
        end
    end
    return copy
end

return AssetCodes
