--------------------------------------------------------------------------------
-- WeaponEnchantConfig.lua  –  Shared enchant data module (server + client)
--
-- Defines the 7 elemental weapon enchants, their colors, and roll logic.
-- Shared between server (roll + apply) and client (trail color + UI reading).
--
-- USAGE:
--   local EnchantCfg = require(path.to.WeaponEnchantConfig)
--   local enchantName = EnchantCfg.RollEnchant()       --> "Fiery" or nil
--   local data     = EnchantCfg.GetEnchantData("Fiery")
--   local allEnchants = EnchantCfg.Enchants
--------------------------------------------------------------------------------

local WeaponEnchantConfig = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

-- Chance (0–1) that any weapon roll receives an enchant.
-- TODO: revert to 0.20 after testing
WeaponEnchantConfig.ENCHANT_CHANCE = 1.00

--------------------------------------------------------------------------------
-- ENCHANT DEFINITIONS
-- Each enchant has:
--   name        : display name / key
--   color       : Color3 used for aura, trail, hit particles
--   statusType  : placeholder string for future gameplay effect
--   description : short flavour text (future UI)
--------------------------------------------------------------------------------
WeaponEnchantConfig.Enchants = {
    {
        name        = "Fiery",
        color       = Color3.fromRGB(255, 122, 0),
        trail_color = Color3.fromRGB(233, 130, 12),   -- sword trail color
        statusType  = "Burn",
        description = "Wreathed in flame",
    },
    {
        name        = "Icy",
        color       = Color3.fromRGB(95, 220, 255),
        trail_color = Color3.fromRGB(140, 213, 255),   -- sword trail color
        statusType  = "Slow",
        description = "Chilling strikes",
    },
    {
        name        = "Shock",
        color       = Color3.fromRGB(255, 217, 0),
        trail_color = Color3.fromRGB(255, 208, 0),   -- sword trail color
        statusType  = "Stun",
        description = "Crackling energy",
    },
    {
        name        = "Toxic",
        color       = Color3.fromRGB(57, 255, 20),
        trail_color = Color3.fromRGB(100, 255, 80),    -- sword trail color
        statusType  = "Poison",
        description = "Venomous edge",
    },
    {
        name        = "Lifesteal",
        color       = Color3.fromRGB(139, 0, 0),
        trail_color = Color3.fromRGB(180, 30, 30),     -- sword trail color
        statusType  = "Lifesteal",
        description = "Drains vitality",
    },
    {
        name        = "Void",
        color       = Color3.fromRGB(106, 13, 173),
        trail_color = Color3.fromRGB(141, 40, 218),    -- sword trail color
        statusType  = "Curse",
        description = "Dark resonance",
    },
}

-- Fast lookup table: EnchantsByName["Fiery"] = { name, color, ... }
WeaponEnchantConfig.EnchantsByName = {}
for _, enchant in ipairs(WeaponEnchantConfig.Enchants) do
    WeaponEnchantConfig.EnchantsByName[enchant.name] = enchant
end

--------------------------------------------------------------------------------
-- GetEnchantData(enchantName) -> enchantTable or nil
--------------------------------------------------------------------------------
function WeaponEnchantConfig.GetEnchantData(enchantName)
    if type(enchantName) ~= "string" or enchantName == "" then return nil end
    return WeaponEnchantConfig.EnchantsByName[enchantName]
end

--------------------------------------------------------------------------------
-- RollEnchant() -> enchantName (string) or nil
-- 20% chance to receive an enchant; on success picks one uniformly at random.
--------------------------------------------------------------------------------
function WeaponEnchantConfig.RollEnchant()
    if math.random() > WeaponEnchantConfig.ENCHANT_CHANCE then
        return nil -- no enchant this roll
    end
    local list = WeaponEnchantConfig.Enchants
    return list[math.random(1, #list)].name
end

--------------------------------------------------------------------------------
-- GetColorForEnchant(enchantName) -> Color3 or nil
-- Convenience helper used by client UI / aura code.
--------------------------------------------------------------------------------
function WeaponEnchantConfig.GetColorForEnchant(enchantName)
    local data = WeaponEnchantConfig.GetEnchantData(enchantName)
    return data and data.color or nil
end

--------------------------------------------------------------------------------
-- GetTrailColorForEnchant(enchantName) -> Color3 or nil
-- Returns trail_color if defined, otherwise falls back to color.
--------------------------------------------------------------------------------
function WeaponEnchantConfig.GetTrailColorForEnchant(enchantName)
    local data = WeaponEnchantConfig.GetEnchantData(enchantName)
    if not data then return nil end
    return data.trail_color or data.color
end

return WeaponEnchantConfig
