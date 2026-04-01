--------------------------------------------------------------------------------
-- WeaponPerkConfig.lua  –  Shared perk data module (server + client)
--
-- Defines the 7 elemental weapon perks, their colors, and roll logic.
-- Shared between server (roll + apply) and client (trail color + UI reading).
--
-- USAGE:
--   local PerkCfg = require(path.to.WeaponPerkConfig)
--   local perkName = PerkCfg.RollPerk()       --> "Fiery" or nil
--   local data     = PerkCfg.GetPerkData("Fiery")
--   local allPerks = PerkCfg.Perks
--------------------------------------------------------------------------------

local WeaponPerkConfig = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

-- Chance (0–1) that any weapon roll receives a perk.
-- TODO: revert to 0.20 after testing
WeaponPerkConfig.PERK_CHANCE = 1.00

--------------------------------------------------------------------------------
-- PERK DEFINITIONS
-- Each perk has:
--   name        : display name / key
--   color       : Color3 used for aura, trail, hit particles
--   statusType  : placeholder string for future gameplay effect
--   description : short flavour text (future UI)
--------------------------------------------------------------------------------
WeaponPerkConfig.Perks = {
    {
        name        = "Fiery",
        color       = Color3.fromRGB(255, 122, 0),
        statusType  = "Burn",            -- future: DoT fire damage
        description = "Wreathed in flame",
    },
    {
        name        = "Frost",
        color       = Color3.fromRGB(95, 220, 255),
        statusType  = "Slow",            -- future: movement slow on hit
        description = "Chilling strikes",
    },
    {
        name        = "Shock",
        color       = Color3.fromRGB(255, 242, 0),
        statusType  = "Stun",            -- future: stun chance on hit
        description = "Crackling energy",
    },
    {
        name        = "Toxic",
        color       = Color3.fromRGB(57, 255, 20),
        statusType  = "Poison",          -- future: poison DoT
        description = "Venomous edge",
    },
    {
        name        = "Holy",
        color       = Color3.fromRGB(255, 255, 255),
        statusType  = "Holy",            -- future: bonus vs undead/mobs
        description = "Blessed radiance",
    },
    {
        name        = "Lifesteal",
        color       = Color3.fromRGB(139, 0, 0),
        statusType  = "Lifesteal",       -- future: heal on hit
        description = "Drains vitality",
    },
    {
        name        = "Void",
        color       = Color3.fromRGB(106, 13, 173),
        statusType  = "Curse",           -- future: anti-heal / curse
        description = "Dark resonance",
    },
}

-- Fast lookup table: PerksByName["Fiery"] = { name, color, ... }
WeaponPerkConfig.PerksByName = {}
for _, perk in ipairs(WeaponPerkConfig.Perks) do
    WeaponPerkConfig.PerksByName[perk.name] = perk
end

--------------------------------------------------------------------------------
-- GetPerkData(perkName) -> perkTable or nil
--------------------------------------------------------------------------------
function WeaponPerkConfig.GetPerkData(perkName)
    if type(perkName) ~= "string" or perkName == "" then return nil end
    return WeaponPerkConfig.PerksByName[perkName]
end

--------------------------------------------------------------------------------
-- RollPerk() -> perkName (string) or nil
-- 20% chance to receive a perk; on success picks one uniformly at random.
--------------------------------------------------------------------------------
function WeaponPerkConfig.RollPerk()
    if math.random() > WeaponPerkConfig.PERK_CHANCE then
        return nil -- no perk this roll
    end
    local list = WeaponPerkConfig.Perks
    return list[math.random(1, #list)].name
end

--------------------------------------------------------------------------------
-- GetColorForPerk(perkName) -> Color3 or nil
-- Convenience helper used by client trail / UI code.
--------------------------------------------------------------------------------
function WeaponPerkConfig.GetColorForPerk(perkName)
    local data = WeaponPerkConfig.GetPerkData(perkName)
    return data and data.color or nil
end

return WeaponPerkConfig
