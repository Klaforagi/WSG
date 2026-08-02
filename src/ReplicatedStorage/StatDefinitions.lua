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
    Size = {
        Id = "Size",
        DefaultBase = 10,
        AutoInitializeForPlayers = true,
        MinValue = 1,
        Apply = function(context, finalValue)
            -- finalValue is in 'size units' where 10 = normal (100%).
            -- Write both `Size` and derived `SizePercent` attributes for other systems.
            local humanoid = context and context.humanoid
            local pct = math.floor(finalValue * 10)
            if humanoid and humanoid.Parent then
                pcall(function()
                    humanoid:SetAttribute("Size", finalValue)
                    humanoid:SetAttribute("SizePercent", pct)
                end)
                return
            end
            local subject = context and context.subject
            if subject and subject.SetAttribute then
                pcall(function()
                    subject:SetAttribute("Size", finalValue)
                    subject:SetAttribute("SizePercent", pct)
                end)
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