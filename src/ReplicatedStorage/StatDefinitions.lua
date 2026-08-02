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
    SizePercent = {
        Id = "SizePercent",
        DefaultBase = 100,
        AutoInitializeForPlayers = true,
        MinValue = 1,
        Apply = function(context, finalValue)
            -- Store resulting size percent on the humanoid (or player) as an attribute.
            -- Other systems can read this attribute to perform actual visual/physical scaling.
            local humanoid = context and context.humanoid
            if humanoid and humanoid.Parent then
                pcall(function() humanoid:SetAttribute("SizePercent", math.floor(finalValue)) end)
                return
            end
            local subject = context and context.subject
            if subject and subject.SetAttribute then
                pcall(function() subject:SetAttribute("SizePercent", math.floor(finalValue)) end)
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