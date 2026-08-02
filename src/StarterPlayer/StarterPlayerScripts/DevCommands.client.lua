local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

local function findEvent()
    local ev = ReplicatedStorage:FindFirstChild("DevCommandEvent")
    if ev and ev:IsA("RemoteEvent") then return ev end
    -- wait a short time
    ev = ReplicatedStorage:WaitForChild("DevCommandEvent", 5)
    if ev and ev:IsA("RemoteEvent") then return ev end
    return nil
end

local devEvent = findEvent()
if not devEvent then
    -- nothing to do
    return
end

-- Forward classic chat (Chatted) to server
player.Chatted:Connect(function(msg)
    pcall(function() devEvent:FireServer(msg) end)
end)

do
    local success, channel = pcall(function()
        return TextChatService and TextChatService.DefaultTextChannel
    end)
    if success and channel and channel.OnMessageDoneFiltering then
        channel.OnMessageDoneFiltering:Connect(function(message)
            local ok, text = pcall(function() return message and message.Text end)
            if ok and text and text ~= "" then
                pcall(function() devEvent:FireServer(text) end)
            end
        end)
    end
end

return nil
