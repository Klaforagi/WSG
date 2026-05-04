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

local previousOnIncomingMessage = TextChatService.OnIncomingMessage

TextChatService.OnIncomingMessage = function(message)
    local properties

    if previousOnIncomingMessage then
        local ok, result = pcall(previousOnIncomingMessage, message)
        if ok and result then
            properties = result
        end
    end

    local sourceText = (properties and properties.Text) or message.Text
    local rewrittenText = rewriteTeamNotice(sourceText)
    if rewrittenText == sourceText then
        return properties
    end

    properties = properties or Instance.new("TextChatMessageProperties")
    properties.Text = rewrittenText
    return properties
end
