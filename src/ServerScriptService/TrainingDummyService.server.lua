local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local PRACTICE_DUMMY_TAG = "PracticeDummy"
local DEFAULT_PROFILE_NAME = "TrainingDummy"
local MIN_HEALTH = 1
local REGEN_DELAY = 5
local REGEN_TICK_INTERVAL = 0.1

local DUMMY_PROFILES = {
    TrainingDummy = {
        MaxHealth = 100,
        RecoveryPerSecond = 20,
    },
    EliteDummy = {
        MaxHealth = 200,
        RecoveryPerSecond = 40,
    },
}

local DEFAULT_PROFILE = DUMMY_PROFILES[DEFAULT_PROFILE_NAME]

local function getDummyProfile(model)
    if not model or not model:IsA("Model") then return nil end
    return DUMMY_PROFILES[model.Name] or (model:GetAttribute("IsPracticeDummy") == true and DEFAULT_PROFILE) or nil
end

local function isTrainingDummyModel(model)
    return getDummyProfile(model) ~= nil
end

local function configureHumanoid(humanoid, profile, fillToMax)
    if not humanoid or not humanoid.Parent then return end
    if not profile then return end

    local maxHealth = tonumber(profile.MaxHealth) or DEFAULT_PROFILE.MaxHealth

    humanoid.MaxHealth = maxHealth
    humanoid.BreakJointsOnDeath = false
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    end)

    if fillToMax then
        humanoid.Health = maxHealth
    else
        humanoid.Health = math.clamp(humanoid.Health, MIN_HEALTH, maxHealth)
    end

    pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
    end)
end

local function manageTrainingDummy(model)
    local profile = getDummyProfile(model)
    if not profile then return end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if humanoid:GetAttribute("_trainingDummyManaged") then return end
    humanoid:SetAttribute("_trainingDummyManaged", true)

    model:SetAttribute("IsPracticeDummy", true)
    if not CollectionService:HasTag(model, PRACTICE_DUMMY_TAG) then
        CollectionService:AddTag(model, PRACTICE_DUMMY_TAG)
    end

    configureHumanoid(humanoid, profile, true)

    local alive = true
    local lastDamageAt = os.clock()
    local previousHealth = humanoid.Health
    local nextRegenAt = math.huge
    local maxHealth = tonumber(profile.MaxHealth) or DEFAULT_PROFILE.MaxHealth
    local recoveryPerSecond = tonumber(profile.RecoveryPerSecond) or 0
    local recoveryPerTick = recoveryPerSecond * REGEN_TICK_INTERVAL

    local function clampHealth(fillToMax)
        if not humanoid or not humanoid.Parent then return end
        configureHumanoid(humanoid, profile, fillToMax)
        previousHealth = humanoid.Health
    end

    local healthConn = humanoid.HealthChanged:Connect(function(newHealth)
        if newHealth < previousHealth then
            lastDamageAt = os.clock()
            nextRegenAt = math.huge
        end

        if newHealth < MIN_HEALTH then
            clampHealth(false)
            return
        end

        if newHealth > maxHealth then
            humanoid.Health = maxHealth
            newHealth = maxHealth
        end

        previousHealth = newHealth
    end)

    local maxHealthConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        if humanoid.MaxHealth ~= maxHealth then
            humanoid.MaxHealth = maxHealth
        end
    end)

    local diedConn = humanoid.Died:Connect(function()
        clampHealth(false)
    end)

    local ancestryConn = model.AncestryChanged:Connect(function(_, parent)
        if not parent then
            alive = false
        end
    end)

    task.spawn(function()
        while alive and humanoid and humanoid.Parent and model.Parent do
            local now = os.clock()
            if humanoid.Health < maxHealth then
                if now - lastDamageAt >= REGEN_DELAY then
                    if nextRegenAt == math.huge then
                        nextRegenAt = now
                    end
                    if now >= nextRegenAt then
                        humanoid.Health = math.min(maxHealth, math.max(MIN_HEALTH, humanoid.Health) + recoveryPerTick)
                        previousHealth = humanoid.Health
                        nextRegenAt = now + REGEN_TICK_INTERVAL
                    end
                else
                    nextRegenAt = math.huge
                end
            else
                nextRegenAt = math.huge
            end

            task.wait(0.1)
        end

        if healthConn.Connected then healthConn:Disconnect() end
        if maxHealthConn.Connected then maxHealthConn:Disconnect() end
        if diedConn.Connected then diedConn:Disconnect() end
        if ancestryConn.Connected then ancestryConn:Disconnect() end
    end)
end

for _, desc in ipairs(Workspace:GetDescendants()) do
    if desc:IsA("Model") and isTrainingDummyModel(desc) then
        task.defer(manageTrainingDummy, desc)
    end
end

Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") and isTrainingDummyModel(desc) then
        task.defer(manageTrainingDummy, desc)
    elseif desc:IsA("Humanoid") then
        local model = desc.Parent
        if model and model:IsA("Model") and isTrainingDummyModel(model) then
            task.defer(manageTrainingDummy, model)
        end
    end
end)
