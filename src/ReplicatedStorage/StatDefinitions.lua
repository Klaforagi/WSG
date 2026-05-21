local StatDefinitions = {}

local definitions = {
    MovementSpeed = {
        Id = "MovementSpeed",
        DefaultBase = 20,
        AutoInitializeForPlayers = true,
        MinValue = 0.1,
        Apply = function(context, finalValue)
            local humanoid = context and context.humanoid
            if humanoid and humanoid.Parent then
                humanoid.WalkSpeed = finalValue
            end
        end,
    },
}

function StatDefinitions.GetDefinition(statId)
    return definitions[statId]
end

function StatDefinitions.GetAllDefinitions()
    local copy = {}
    for statId, definition in pairs(definitions) do
        copy[statId] = definition
    end
    return copy
end

return StatDefinitions