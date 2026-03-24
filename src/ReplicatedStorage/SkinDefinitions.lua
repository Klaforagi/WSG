--------------------------------------------------------------------------------
-- SkinDefinitions.lua  –  Shared skin config (ReplicatedStorage)
--
-- Each skin entry defines: Id, DisplayName, Description, Price, Rarity,
-- Category, ShopVisible, IsDefault, ApplicationType, and visual references.
--
-- Readable by both server and client.
--------------------------------------------------------------------------------

local SkinDefinitions = {}

SkinDefinitions.Skins = {
    ---------------------------------------------------------------------------
    -- DEFAULT  –  always owned, uses the player's normal Roblox avatar
    ---------------------------------------------------------------------------
    {
        Id              = "Default",
        DisplayName     = "Default",
        Description     = "Your original Roblox avatar.",
        Price           = 0,
        Rarity          = "Common",
        Category        = "Skin",
        ShopVisible     = false,   -- never shown in shop
        InventoryVisible = true,
        IsDefault       = true,
        ApplicationType = "Avatar", -- restores normal avatar
    },

    ---------------------------------------------------------------------------
    -- KNIGHT  –  purchasable cosmetic skin
    ---------------------------------------------------------------------------
    {
        Id              = "Knight",
        DisplayName     = "Knight",
        Description     = "Don a full suit of knightly armor.",
        Price           = 150,
        Rarity          = "Epic",
        Category        = "Skin",
        ShopVisible     = true,
        InventoryVisible = true,
        IsDefault       = false,
        ApplicationType = "Cosmetic", -- scripted cosmetic overlay

        -- Visual spec: shirt/pants overrides + welded armor parts
        -- All parts are built programmatically on the server
        ShirtColor      = Color3.fromRGB(50, 50, 55),
        PantsColor      = Color3.fromRGB(45, 42, 48),
        ArmorColor      = Color3.fromRGB(160, 165, 175),
        AccentColor     = Color3.fromRGB(200, 170, 50),  -- gold trim
        HelmetColor     = Color3.fromRGB(140, 145, 155),
        VisorColor      = Color3.fromRGB(30, 30, 35),
    },
}

--------------------------------------------------------------------------------
-- Lookup helpers
--------------------------------------------------------------------------------
function SkinDefinitions.GetById(id)
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.Id == id then return def end
    end
    return nil
end

function SkinDefinitions.GetAll()
    return SkinDefinitions.Skins
end

function SkinDefinitions.GetShopSkins()
    local list = {}
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.ShopVisible then
            table.insert(list, def)
        end
    end
    return list
end

function SkinDefinitions.GetInventorySkins()
    local list = {}
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.InventoryVisible then
            table.insert(list, def)
        end
    end
    return list
end

function SkinDefinitions.GetDefault()
    for _, def in ipairs(SkinDefinitions.Skins) do
        if def.IsDefault then return def end
    end
    return SkinDefinitions.Skins[1]
end

return SkinDefinitions
