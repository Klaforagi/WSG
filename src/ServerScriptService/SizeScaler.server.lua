local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

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
local SIZE_TWEEN_INFO = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local scaleTweens = {} -- [Humanoid] = { Tween }

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

local function cancelScaleTweens(humanoid)
    local bag = scaleTweens[humanoid]
    if not bag then
        return
    end
    for _, tween in ipairs(bag) do
        pcall(function()
            tween:Cancel()
        end)
    end
    scaleTweens[humanoid] = nil
end

local function applyHumanoidUniformScale(humanoid, multiplier, instant)
    if not humanoid or humanoid.Parent == nil then return false end
    multiplier = clampScale(multiplier)
    pcall(function() humanoid.AutomaticScalingEnabled = true end)
    cancelScaleTweens(humanoid)
    local bag = {}
    for name, _ in pairs(SCALE_VARS) do
        local nv = ensureNumberValue(humanoid, name, 1)
        if instant or math.abs(nv.Value - multiplier) < 0.001 then
            pcall(function() nv.Value = multiplier end)
        else
            local tween = TweenService:Create(nv, SIZE_TWEEN_INFO, { Value = multiplier })
            table.insert(bag, tween)
            tween:Play()
        end
    end
    if #bag > 0 then
        scaleTweens[humanoid] = bag
    end
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
    applyHumanoidUniformScale(humanoid, multiplier, true)

    humanoid:GetAttributeChangedSignal("Size"):Connect(function()
        local s = humanoid:GetAttribute("Size")
        if type(s) ~= "number" then return end
        applyHumanoidUniformScale(humanoid, s / 10, false)
    end)

    humanoid.Destroying:Connect(function()
        cancelScaleTweens(humanoid)
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
