local ServerScriptService = game:GetService("ServerScriptService")

local CombatUtils = {}

local PODIUM_NAMES = {
    PodiumAvatar_1 = true,
    PodiumAvatar_2 = true,
    PodiumAvatar_3 = true,
}

local function isPodiumAvatar(model)
    if not model or not model:IsA("Model") then return false end
    if PODIUM_NAMES[model.Name] then return true end
    local attr = model:GetAttribute("IsPodiumAvatar")
    if attr == true then return true end
    return false
end

local function isPodiumPart(part)
    if not part or not part:IsA("BasePart") then return false end
    local pattr = part:GetAttribute("IsPodiumAvatarPart")
    if pattr == true then return true end
    local model = part:FindFirstAncestorOfClass("Model")
    return isPodiumAvatar(model)
end

local function tagPodiumModel(model)
    if not model or not model:IsA("Model") then return end
    pcall(function() model:SetAttribute("IsPodiumAvatar", true) end)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            pcall(function() descendant:SetAttribute("IsPodiumAvatarPart", true) end)
        end
    end
    -- Humanoid safety fallback
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum:SetAttribute("IgnoreCombatTargeting", true)
            hum:SetAttribute("IsPodiumAvatar", true)
            hum.BreakJointsOnDeath = false
            hum.MaxHealth = math.max(1000000, hum.MaxHealth or 100)
            hum.Health = hum.MaxHealth
        end)
    end
end

CombatUtils.isPodiumAvatar = isPodiumAvatar
CombatUtils.isPodiumPart = isPodiumPart
CombatUtils.tagPodiumModel = tagPodiumModel

return CombatUtils
