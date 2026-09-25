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
WeaponEnchantConfig.ENCHANT_CHANCE = 0.20

-- Weapons that always roll an enchant, even if the crate chance fails.
WeaponEnchantConfig.GuaranteedEnchantWeapons = {
    ["Ethereal Bow"] = true,
    ["Ethereal Sword"] = true,
}

-- Handle / mesh tint used by Ethereal Sword and Ethereal Bow.
-- Kept separate from aura/trail colors so the weapon body matches the sword.
WeaponEnchantConfig.EtherealPartColors = {
    Lifesteal = Color3.fromRGB(255, 0, 4),   -- red
    Fiery     = Color3.fromRGB(255, 111, 0), -- orange
    Shock     = Color3.fromRGB(255, 213, 0), -- yellow
    Toxic     = Color3.fromRGB(98, 255, 0),  -- green
    Icy       = Color3.fromRGB(0, 166, 255), -- blue
    Void      = Color3.fromRGB(162, 0, 255), -- purple
}

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
        trail_color = Color3.fromRGB(231, 189, 1),   -- sword trail color
        statusType  = "Stun",
        description = "Crackling energy",
    },
    {
        name        = "Toxic",
        color       = Color3.fromRGB(65, 170, 35),
        trail_color = Color3.fromRGB(100, 200, 70),    -- sword trail color
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
        color       = Color3.fromRGB(180, 80, 255),
        trail_color = Color3.fromRGB(200, 110, 255),    -- sword trail color
        statusType  = "Curse",
        description = "Dark resonance",
    },
}

-- Fast lookup table: EnchantsByName["Fiery"] = { name, color, ... }
WeaponEnchantConfig.EnchantsByName = {}
local EnchantsByLowerName = {}
for _, enchant in ipairs(WeaponEnchantConfig.Enchants) do
    WeaponEnchantConfig.EnchantsByName[enchant.name] = enchant
    EnchantsByLowerName[string.lower(enchant.name)] = enchant
end

local function resolveVisualEnchantData(enchantName)
    if type(enchantName) ~= "string" then return nil end

    local trimmed = enchantName:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return nil end

    local lowerName = string.lower(trimmed)
    if lowerName == "none" or lowerName == "no enchant" then return nil end

    return WeaponEnchantConfig.EnchantsByName[trimmed] or EnchantsByLowerName[lowerName]
end

local function buildTrailColorSequence(trailBaseColor)
    local h, s, v = Color3.toHSV(trailBaseColor)
    local brightColor = Color3.fromHSV(h, math.clamp(s * 0.6, 0, 1), math.clamp(v * 1.3, 0, 1))

    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, brightColor),
        ColorSequenceKeypoint.new(0.4, trailBaseColor),
        ColorSequenceKeypoint.new(1, trailBaseColor),
    })
end

--------------------------------------------------------------------------------
-- PROC CONFIG  –  Flat enchant proc tuning (server-side gameplay effects)
-- All damage here is FLAT — does NOT scale from weapon damage, size, rarity,
-- upgrades, combo step, or swing speed.
-- Ranged enchant procs deal 75% less (25% of these values).
--------------------------------------------------------------------------------
WeaponEnchantConfig.RangedProcDamageMultiplier = 0.25

WeaponEnchantConfig.ProcConfig = {
    Fiery = {
        ProcChance = 0.28,
        ProcDamage = 20,
        SoundId    = "rbxassetid://REPLACE_ME",
    },
    Icy = {
        ProcChance    = 0.30,
        TickDamage    = 5,          -- damage per tick while slowed
        TickInterval  = 1,          -- tick once per second
        SlowPercent   = 0.30,
        SlowDuration  = 4,          -- 4 ticks total = 2+2+2+2 = 8 damage
        SoundId       = "rbxassetid://REPLACE_ME",
    },
    Shock = {
        ProcChance    = 0.32,
        ProcDamage    = 12,
        ChainRange    = 20,
        MaxChains     = 4,
        ChainDamage   = 8,
        ChainCooldown = 0.3,
        SoundId       = "rbxassetid://REPLACE_ME",
    },
    Toxic = {
        ProcChance       = 0.40,
        TickDamage       = 7,
        TickInterval     = 2,
        DurationPerProc  = 9,
        MaxDuration      = 18,
        SoundId          = "rbxassetid://REPLACE_ME",
    },
    Lifesteal = {
        ProcChance = 0.35,
        ProcDamage = 10,
        HealAmount = 5,
        SoundId    = "rbxassetid://REPLACE_ME",
    },
    Void = {
        ProcChance         = 0.18,
        ProcDamage         = 35,
        KnockbackForce     = 45,
        KnockbackUpwardForce = 6,
        SoundId            = "rbxassetid://REPLACE_ME",
    },
}

--------------------------------------------------------------------------------
-- GetEnchantData(enchantName) -> enchantTable or nil
--------------------------------------------------------------------------------
function WeaponEnchantConfig.GetEnchantData(enchantName)
    if type(enchantName) ~= "string" or enchantName == "" then return nil end
    return WeaponEnchantConfig.EnchantsByName[enchantName]
end

local function resolveRarityName(context)
    local rarityName = context
    if type(context) == "table" then
        rarityName = context.rarity or context.rarityName
    end

    if type(rarityName) ~= "string" then
        return nil
    end

    local trimmed = rarityName:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end

    return trimmed
end

local function resolveEnchantChance(context)
    local chance = WeaponEnchantConfig.ENCHANT_CHANCE
    if type(context) ~= "table" then
        return math.clamp(chance, 0, 1)
    end

    local multiplier = tonumber(context.enchantChanceMultiplier)
    if multiplier and multiplier > 0 then
        chance *= multiplier
    end

    local bonus = tonumber(context.enchantChanceBonus)
    if bonus then
        chance += bonus
    end

    local overrideChance = tonumber(context.enchantChance)
    if overrideChance then
        chance = overrideChance
    end

    return math.clamp(chance, 0, 1)
end

local function resolveWeaponName(context)
    if type(context) ~= "table" then
        return nil
    end

    local weaponName = context.weaponName or context.weapon or context.toolName
    if type(weaponName) ~= "string" then
        return nil
    end

    local trimmed = weaponName:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end

    return trimmed
end

local Toolgunsettings
local function getToolgunsettings()
    if Toolgunsettings ~= nil then
        return Toolgunsettings
    end

    local ok, module = pcall(function()
        local scriptModule = script.Parent and script.Parent:FindFirstChild("Toolgunsettings")
        if scriptModule and scriptModule:IsA("ModuleScript") then
            return require(scriptModule)
        end
        return nil
    end)
    Toolgunsettings = (ok and module) or false
    return Toolgunsettings
end

local function isRangedWeapon(context, weaponName)
    if type(context) == "table" then
        local category = context.category or context.weaponCategory or context.weaponType
        if type(category) == "string" and string.lower(category) == "ranged" then
            return true
        end
    end

    if type(weaponName) ~= "string" or weaponName == "" then
        return false
    end

    local settings = getToolgunsettings()
    if settings and type(settings.getPreset) == "function" then
        local ok, preset = pcall(function()
            return settings.getPreset(weaponName)
        end)
        if ok and type(preset) == "table" then
            return true
        end
    end

    return false
end

function WeaponEnchantConfig.RequiresEnchant(weaponName)
    if type(weaponName) ~= "string" or weaponName == "" then
        return false
    end

    if WeaponEnchantConfig.GuaranteedEnchantWeapons[weaponName] then
        return true
    end

    local lowerName = string.lower(weaponName)
    for name, enabled in pairs(WeaponEnchantConfig.GuaranteedEnchantWeapons) do
        if enabled and type(name) == "string" and string.lower(name) == lowerName then
            return true
        end
    end

    return false
end

function WeaponEnchantConfig.GetEtherealPartColor(enchantName)
    if type(enchantName) ~= "string" or enchantName == "" then
        return nil
    end

    local trimmed = enchantName:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end

    local direct = WeaponEnchantConfig.EtherealPartColors[trimmed]
    if direct then
        return direct
    end

    local lowerName = string.lower(trimmed)
    for name, color in pairs(WeaponEnchantConfig.EtherealPartColors) do
        if type(name) == "string" and string.lower(name) == lowerName then
            return color
        end
    end

    return nil
end

local function pickRandomEnchantName()
    local list = WeaponEnchantConfig.Enchants
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[math.random(1, #list)].name
end

--------------------------------------------------------------------------------
-- RollEnchant() -> enchantName (string) or nil
-- 20% chance to receive an enchant; on success picks one uniformly at random.
-- Common melee cannot roll enchants. Common ranged can.
-- Weapons in GuaranteedEnchantWeapons always receive one.
--------------------------------------------------------------------------------
function WeaponEnchantConfig.RollEnchant(context)
    local weaponName = resolveWeaponName(context)
    local guaranteed = WeaponEnchantConfig.RequiresEnchant(weaponName)
        or (type(context) == "table" and context.guaranteedEnchant == true)

    local rarityName = resolveRarityName(context)
    if not guaranteed and rarityName and string.lower(rarityName) == "common" then
        if not isRangedWeapon(context, weaponName) then
            return nil
        end
    end

    if not guaranteed and math.random() > resolveEnchantChance(context) then
        return nil -- no enchant this roll
    end

    return pickRandomEnchantName()
end

-- Keep a valid enchant for guaranteed weapons; otherwise return the original.
function WeaponEnchantConfig.EnsureEnchantName(weaponName, enchantName)
    if type(enchantName) == "string" then
        local trimmed = enchantName:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" and trimmed ~= "None" and WeaponEnchantConfig.GetEnchantData(trimmed) then
            return trimmed
        end
    end

    if WeaponEnchantConfig.RequiresEnchant(weaponName) then
        return WeaponEnchantConfig.RollEnchant({
            weaponName = weaponName,
            guaranteedEnchant = true,
        })
    end

    return nil
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
    local data = resolveVisualEnchantData(enchantName)
    if not data then return nil end
    return data.trail_color or data.color
end

--------------------------------------------------------------------------------
-- GetTrailColorSequenceForEnchant(enchantName) -> ColorSequence or nil
-- Shared melee/projectile trail style. Returns nil for no/unknown enchant.
--------------------------------------------------------------------------------
function WeaponEnchantConfig.GetTrailColorSequenceForEnchant(enchantName)
    local trailBaseColor = WeaponEnchantConfig.GetTrailColorForEnchant(enchantName)
    if not trailBaseColor then return nil end

    return buildTrailColorSequence(trailBaseColor)
end

return WeaponEnchantConfig
