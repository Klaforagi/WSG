local HealthPotionConfig = {}

HealthPotionConfig.Id = "health_potion"
HealthPotionConfig.DisplayName = "Health Potion"
HealthPotionConfig.Description = "Equip it to slot 4 to drink it for an instant heal."
HealthPotionConfig.DetailText = "Restores 40 HP instantly"
HealthPotionConfig.IconGlyph = "HP"
HealthPotionConfig.IconColor = { 103, 186, 255 }
HealthPotionConfig.HotbarSlot = 4
HealthPotionConfig.HotbarLabel = "Potion"
HealthPotionConfig.HealAmount = 40
HealthPotionConfig.CooldownSeconds = 20

return HealthPotionConfig
