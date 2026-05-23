local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local TeamDisplayNames = require(ReplicatedStorage:WaitForChild("TeamDisplayNames"))

local TEAM_NOTICE_PATTERN = "You are now on the '([^']+)' team%."

local function rewriteTeamNotice(text)
    if type(text) ~= "string" or text == "" then
        return text
    end

    return (text:gsub(TEAM_NOTICE_PATTERN, function(teamName)
        local displayName = TeamDisplayNames.Get(teamName)
        if displayName == "" then
            displayName = teamName
        end
        return "You are now on the '" .. displayName .. "' team."
    end))
end

TextChatService.OnIncomingMessage = function(message)
    local sourceText = message.Text
    local rewrittenText = rewriteTeamNotice(sourceText)
    if rewrittenText == sourceText then
        return nil
    end

    local properties = Instance.new("TextChatMessageProperties")
    properties.Text = rewrittenText
    return properties
end
