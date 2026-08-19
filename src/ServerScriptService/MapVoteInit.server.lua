-- Init script to start MapVoteService module
local ServerScriptService = game:GetService("ServerScriptService")
local ok, svc = pcall(function()
    return require(ServerScriptService:WaitForChild("MapVoteService"))
end)
if not ok then
    warn("[MapVoteInit] Failed to require MapVoteService:", svc)
else
    print("[MapVoteInit] MapVoteService required successfully")
end
