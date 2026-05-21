local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatDefinitions = require(ReplicatedStorage:WaitForChild("StatDefinitions"))

local HumanoidStatService = {}

local DEFAULT_MULTIPLIER = 1

local subjectStates = {}
local playerConnections = {}
local subjectConnections = {}
local applyStat
local ensureStatState

local function shallowCopy(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function resolveDefinition(statId)
    local definition = StatDefinitions.GetDefinition(statId)
    if not definition then
        error(string.format("[HumanoidStatService] Unknown stat '%s'", tostring(statId)))
    end
    return definition
end

local function getSubjectKey(subject)
    if typeof(subject) ~= "Instance" then
        error("[HumanoidStatService] Subject must be an Instance")
    end

    if subject:IsA("Player") or subject:IsA("Humanoid") then
        return subject
    end

    error(string.format("[HumanoidStatService] Unsupported subject type '%s'", subject.ClassName))
end

local function computeStat(statState, definition)
    local additiveTotal = 0
    local multiplierTotal = DEFAULT_MULTIPLIER

    for _, modifier in pairs(statState.modifiers) do
        additiveTotal += modifier.additive or 0
        multiplierTotal *= modifier.multiplier or DEFAULT_MULTIPLIER
    end

    local finalValue = (statState.base + additiveTotal) * multiplierTotal
    local minValue = definition.MinValue
    if type(minValue) == "number" then
        finalValue = math.max(minValue, finalValue)
    end

    statState.final = finalValue
    statState.additiveTotal = additiveTotal
    statState.multiplierTotal = multiplierTotal
    return finalValue
end

applyStat = function(subjectState, statId)
    local statState = subjectState.stats[statId]
    if not statState then
        return nil
    end

    local definition = resolveDefinition(statId)
    local finalValue = computeStat(statState, definition)
    definition.Apply(subjectState, finalValue, statState)
    return finalValue
end

ensureStatState = function(subjectState, statId)
    local statState = subjectState.stats[statId]
    if statState then
        return statState
    end

    local definition = resolveDefinition(statId)
    statState = {
        base = definition.DefaultBase,
        final = definition.DefaultBase,
        additiveTotal = 0,
        multiplierTotal = DEFAULT_MULTIPLIER,
        modifiers = {},
    }
    subjectState.stats[statId] = statState
    return statState
end

local function initializeDefaultStats(subjectState)
    local definitions = StatDefinitions.GetAllDefinitions()
    local isPlayerSubject = subjectState.subject:IsA("Player")
    local isHumanoidSubject = subjectState.subject:IsA("Humanoid")
    for statId, definition in pairs(definitions) do
        if definition.AutoInitialize == true
            or (isPlayerSubject and definition.AutoInitializeForPlayers == true)
            or (isHumanoidSubject and definition.AutoInitializeForHumanoids == true) then
            ensureStatState(subjectState, statId)
            applyStat(subjectState, statId)
        end
    end
end

local function disconnectPlayerSignals(player)
    local connections = playerConnections[player]
    if not connections then
        return
    end

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    playerConnections[player] = nil
end

local function disconnectSubjectSignals(subject)
    local connection = subjectConnections[subject]
    if not connection then
        return
    end

    pcall(function()
        connection:Disconnect()
    end)
    subjectConnections[subject] = nil
end

local function clearHumanoidSubject(subject)
    local subjectState = subjectStates[subject]
    if not subjectState then
        return
    end

    subjectStates[subject] = nil
end

local function getBoundHumanoid(subject)
    if not subject then
        return nil
    end

    if subject:IsA("Humanoid") then
        return subject
    end

    local character = subject.Character
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function ensureSubjectState(subject)
    local key = getSubjectKey(subject)
    local subjectState = subjectStates[key]
    if subjectState then
        return subjectState
    end

    local humanoid = getBoundHumanoid(key)
    subjectState = {
        subject = key,
        humanoid = humanoid,
        stats = {},
    }
    subjectStates[key] = subjectState
    if key:IsA("Humanoid") then
        disconnectSubjectSignals(key)
        subjectConnections[key] = key.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                HumanoidStatService:ClearSubject(key)
            end
        end)
    end
    initializeDefaultStats(subjectState)
    return subjectState
end

local function scheduleModifierExpiry(subjectState, statId, modifierId, token, duration)
    task.delay(duration, function()
        local currentSubjectState = subjectStates[subjectState.subject]
        if not currentSubjectState then
            return
        end

        local statState = currentSubjectState.stats[statId]
        if not statState then
            return
        end

        local modifier = statState.modifiers[modifierId]
        if not modifier or modifier.token ~= token then
            return
        end

        HumanoidStatService:RemoveModifier(currentSubjectState.subject, statId, modifierId)
    end)
end

function HumanoidStatService:Init()
    for _, player in ipairs(Players:GetPlayers()) do
        self:TrackPlayer(player)
    end

    Players.PlayerAdded:Connect(function(player)
        self:TrackPlayer(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:ClearSubject(player)
        disconnectPlayerSignals(player)
    end)
end

function HumanoidStatService:TrackPlayer(player)
    if not player or not player:IsA("Player") then
        return nil
    end

    disconnectPlayerSignals(player)
    self:EnsureSubject(player)

    playerConnections[player] = {
        player.CharacterAdded:Connect(function(character)
            local humanoid = character:WaitForChild("Humanoid", 10)
            if humanoid then
                self:BindHumanoid(player, humanoid)
            end
        end),
        player.CharacterRemoving:Connect(function()
            local subjectState = subjectStates[player]
            if subjectState then
                subjectState.humanoid = nil
            end
        end),
    }

    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            self:BindHumanoid(player, humanoid)
        end
    end

    return subjectStates[player]
end

function HumanoidStatService:EnsureSubject(subject)
    return ensureSubjectState(subject)
end

function HumanoidStatService:EnsureHumanoidSubject(humanoid)
    return ensureSubjectState(humanoid)
end

function HumanoidStatService:BindHumanoid(subject, humanoid)
    local subjectState = ensureSubjectState(subject)
    subjectState.humanoid = humanoid

    for statId in pairs(subjectState.stats) do
        applyStat(subjectState, statId)
    end

    return subjectState
end

function HumanoidStatService:SetBaseStat(subject, statId, baseValue)
    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    statState.base = tonumber(baseValue) or statState.base
    return applyStat(subjectState, statId)
end

function HumanoidStatService:GetBaseStat(subject, statId)
    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    return statState.base
end

function HumanoidStatService:SetModifier(subject, statId, modifierId, options)
    if type(modifierId) ~= "string" or modifierId == "" then
        error("[HumanoidStatService] Modifier id must be a non-empty string")
    end

    if type(options) ~= "table" then
        error("[HumanoidStatService] Modifier options must be a table")
    end

    local additive = tonumber(options.additive) or 0
    local multiplier = options.multiplier
    if multiplier == nil then
        multiplier = DEFAULT_MULTIPLIER
    else
        multiplier = tonumber(multiplier) or DEFAULT_MULTIPLIER
    end

    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    local existing = statState.modifiers[modifierId]
    local token = (existing and existing.token or 0) + 1

    statState.modifiers[modifierId] = {
        id = modifierId,
        additive = additive,
        multiplier = multiplier,
        duration = tonumber(options.duration),
        source = options.source,
        token = token,
    }

    local duration = tonumber(options.duration)
    if duration and duration > 0 then
        scheduleModifierExpiry(subjectState, statId, modifierId, token, duration)
    end

    return applyStat(subjectState, statId)
end

function HumanoidStatService:RemoveModifier(subject, statId, modifierId)
    local subjectState = subjectStates[getSubjectKey(subject)]
    if not subjectState then
        return nil
    end

    local statState = subjectState.stats[statId]
    if not statState then
        return nil
    end

    if not statState.modifiers[modifierId] then
        return statState.final
    end

    statState.modifiers[modifierId] = nil
    return applyStat(subjectState, statId)
end

function HumanoidStatService:ClearModifiers(subject, statId)
    local subjectState = subjectStates[getSubjectKey(subject)]
    if not subjectState then
        return nil
    end

    local statState = subjectState.stats[statId]
    if not statState then
        return nil
    end

    statState.modifiers = {}
    return applyStat(subjectState, statId)
end

function HumanoidStatService:GetFinalStat(subject, statId)
    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    return statState.final
end

function HumanoidStatService:GetModifiers(subject, statId)
    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    return shallowCopy(statState.modifiers)
end

function HumanoidStatService:GetStatBreakdown(subject, statId)
    local subjectState = ensureSubjectState(subject)
    local statState = ensureStatState(subjectState, statId)
    return {
        base = statState.base,
        additiveTotal = statState.additiveTotal,
        multiplierTotal = statState.multiplierTotal,
        final = statState.final,
        modifiers = shallowCopy(statState.modifiers),
    }
end

function HumanoidStatService:ClearSubject(subject)
    local key = getSubjectKey(subject)
    local subjectState = subjectStates[key]
    if not subjectState then
        return
    end

    if key:IsA("Player") then
        disconnectPlayerSignals(key)
    else
        disconnectSubjectSignals(key)
        clearHumanoidSubject(key)
    end

    subjectStates[key] = nil
end

return HumanoidStatService