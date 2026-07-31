local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
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
    local properties = Instance.new("TextChatMessageProperties")
    local changed = false

    local sourceText = message.Text
    local rewrittenText = rewriteTeamNotice(sourceText)
    if rewrittenText ~= sourceText then
        properties.Text = rewrittenText
        changed = true
    end

    local textSource = message.TextSource
    local userId = textSource and textSource.UserId
    if type(userId) == "number" then
        local player = Players:GetPlayerByUserId(userId)
        if player then
            local chatPrefix = player:GetAttribute("ShopChatPrefix")
            if type(chatPrefix) == "string" and chatPrefix ~= "" then
                local prefixText = message.PrefixText or ""
                properties.PrefixText = chatPrefix .. (prefixText ~= "" and (" " .. prefixText) or "")
                changed = true
            end
        end
    end

    if not changed then
        return nil
    end
    return properties
end
