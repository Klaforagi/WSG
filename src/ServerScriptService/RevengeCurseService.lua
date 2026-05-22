local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local RevengeCurseService = {}

local MOVEMENT_SPEED_STAT = "MovementSpeed"
local MODIFIER_ID = "revenge_curse"
local DEFAULT_DURATION = 75
local SPEED_MULTIPLIER = 0.90
local DAMAGE_MULTIPLIER = 0.90

local activeCurses = {}

local function now()
    return Workspace:GetServerTimeNow()
end

local function clearAttributes(player)
    if not player or not player.Parent then
        return
    end
    player:SetAttribute("RevengeCurseActive", false)
    player:SetAttribute("RevengeCurseExpiresAt", nil)
end

local function setAttributes(player, expiresAt)
    if not player or not player.Parent then
        return
    end
    player:SetAttribute("RevengeCurseActive", true)
    player:SetAttribute("RevengeCurseExpiresAt", expiresAt)
end

local function removeSpeedModifier(player)
    if not player then
        return
    end
    pcall(function()
        HumanoidStatService:RemoveModifier(player, MOVEMENT_SPEED_STAT, MODIFIER_ID)
    end)
end

local function applySpeedModifier(player, duration)
    if not player or not player.Parent then
        return
    end
    HumanoidStatService:SetModifier(player, MOVEMENT_SPEED_STAT, MODIFIER_ID, {
        multiplier = SPEED_MULTIPLIER,
        duration = duration,
        source = "Revenge Curse",
    })
end

function RevengeCurseService:Expire(player, silent)
    if not player then
        return false
    end

    local userId = player.UserId
    if not activeCurses[userId] then
        clearAttributes(player)
        removeSpeedModifier(player)
        return false
    end

    activeCurses[userId] = nil
    clearAttributes(player)
    removeSpeedModifier(player)

    if not silent then
        print(string.format("[RevengeCurse] Expired for %s.", player.Name))
    end
    return true
end

function RevengeCurseService:Apply(player, duration)
    if not player or not player:IsA("Player") or player.Parent ~= Players then
        return false
    end

    local seconds = math.max(1, tonumber(duration) or DEFAULT_DURATION)
    local expiresAt = now() + seconds
    local existing = activeCurses[player.UserId]
    local token = (existing and existing.token or 0) + 1

    activeCurses[player.UserId] = {
        player = player,
        expiresAt = expiresAt,
        token = token,
    }

    setAttributes(player, expiresAt)
    applySpeedModifier(player, seconds)

    if existing then
        print(string.format("[RevengeCurse] Refreshed on %s.", player.Name))
    else
        print(string.format("[RevengeCurse] Applied to %s for %d seconds.", player.Name, seconds))
    end

    task.delay(seconds, function()
        local state = activeCurses[player.UserId]
        if not state or state.token ~= token or state.player ~= player then
            return
        end
        if state.expiresAt > now() + 0.05 then
            return
        end
        self:Expire(player)
    end)

    return true
end

function RevengeCurseService:GetRemaining(player)
    if not player then
        return 0
    end

    local state = activeCurses[player.UserId]
    if not state then
        return 0
    end

    local remaining = state.expiresAt - now()
    if remaining <= 0 then
        self:Expire(player)
        return 0
    end
    return remaining
end

function RevengeCurseService:IsActive(player)
    return self:GetRemaining(player) > 0
end

function RevengeCurseService:GetDamageMultiplier(player)
    if self:IsActive(player) then
        return DAMAGE_MULTIPLIER
    end
    return 1
end

Players.PlayerRemoving:Connect(function(player)
    if activeCurses[player.UserId] then
        activeCurses[player.UserId] = nil
    end
end)

_G.GetRevengeCurseDamageMultiplier = function(player)
    return RevengeCurseService:GetDamageMultiplier(player)
end

return RevengeCurseService
