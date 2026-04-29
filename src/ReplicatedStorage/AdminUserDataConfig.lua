--------------------------------------------------------------------------------
-- AdminUserDataConfig.lua  –  Shared constants for the Admin "User Data" tab
--
-- Used by both client (AdminPanel.client.lua) and server (PlayerDataAdminService)
-- to keep reset-type names and section labels in sync.
--------------------------------------------------------------------------------

local AdminUserDataConfig = {}

-- Whitelist of reset types accepted by the server.
-- Anything not in this set is rejected before any DataStore write.
AdminUserDataConfig.ResetTypes = {
    Currency     = "Currency",
    Progression  = "Progression",
    Inventory    = "Inventory",
    Quests       = "Quests",
    Achievements = "Achievements",
    Full         = "Full",
}

-- Display order + labels used by the client UI.
AdminUserDataConfig.ResetButtons = {
    { id = "Currency",     label = "Reset Currency",     desc = "Coins, Keys, Salvage" },
    { id = "Progression",  label = "Reset Progression",  desc = "Level, XP, Upgrades" },
    { id = "Inventory",    label = "Reset Inventory",    desc = "Weapons, Skins, Effects, Emotes, Loadout" },
    { id = "Quests",       label = "Reset Quests",       desc = "Daily + Weekly quest progress" },
    { id = "Achievements", label = "Reset Achievements", desc = "Achievement progress + AP" },
    { id = "Full",         label = "FULL DATA RESET",    desc = "Wipes ALL saved data (requires typed confirm)" },
}

-- Section labels for the right-hand data panel.
AdminUserDataConfig.Sections = {
    "Identity",
    "Currency",
    "Progression",
    "Inventory",
    "Quests",
    "Achievements",
    "Login/Streak",
    "Career",
    "Raw Data",
}

AdminUserDataConfig.PageSize = 25

return AdminUserDataConfig
