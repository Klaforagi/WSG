local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local HumanoidStatService = require(ServerScriptService:WaitForChild("HumanoidStatService"))

local SizeScaler = {}

local SCALE_VARS = {
    BodyWidthScale = 1,
    BodyHeightScale = 1,
    BodyDepthScale = 1,
    HeadScale = 1,
}

local MIN_SCALE = 0.35
local MAX_SCALE = 3.5

local function clampScale(v)
    return math.clamp(v, MIN_SCALE, MAX_SCALE)
end

local function ensureNumberValue(parent, name, default)
    local v = parent:FindFirstChild(name)
    if v and v:IsA("NumberValue") then
        return v
    end
    v = Instance.new("NumberValue")
    v.Name = name
    v.Value = default or 1
    v.Parent = parent
    return v
end

local function applyHumanoidUniformScale(humanoid, multiplier)
    if not humanoid or humanoid.Parent == nil then return false end
    multiplier = clampScale(multiplier)
    -- Ensure AutomaticScalingEnabled is true so engine applies the NumberValues
    pcall(function() humanoid.AutomaticScalingEnabled = true end)
    -- Create or update NumberValues
    for name, _ in pairs(SCALE_VARS) do
        local nv = ensureNumberValue(humanoid, name, 1)
        -- Use multiplier for all body scales; head scale uses multiplier as well
        pcall(function() nv.Value = multiplier end)
    end
    -- Give engine a tick to apply changes
    RunService.Heartbeat:Wait()
    return true
end

local function onCharacterAdded(player, character)
    if not player or not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
    end

    -- Initial apply based on Humanoid attribute (set by HumanoidStatService.Apply)
    local initialSize = humanoid:GetAttribute("Size")
    if type(initialSize) ~= "number" then
        local ok, val = pcall(function()
            return HumanoidStatService:GetFinalStat(player, "Size")
        end)
        if ok and type(val) == "number" then
            initialSize = val
        else
            initialSize = 10
        end
    end

    local multiplier = tonumber(initialSize) and (initialSize / 10) or 1
    applyHumanoidUniformScale(humanoid, multiplier)

    -- Listen for future attribute changes
    humanoid:GetAttributeChangedSignal("Size"):Connect(function()
        local s = humanoid:GetAttribute("Size")
        if type(s) ~= "number" then return end
        applyHumanoidUniformScale(humanoid, s / 10)
    end)
end

local function trackPlayer(player)
    if not player then return end
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end
Players.PlayerAdded:Connect(trackPlayer)

return SizeScaler
