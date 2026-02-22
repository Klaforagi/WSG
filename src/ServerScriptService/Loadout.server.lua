--------------------------------------------------------------------------------
-- Loadout.server.lua
-- Gives each player their default tools on spawn and handles the Special-slot
-- Game Pass unlock flow.
--
-- Tool templates live in ServerStorage.Tools/{Melee, Ranged, Special}.
-- The client NEVER clones tools — only this server script does.
--------------------------------------------------------------------------------

local Players            = game:GetService("Players")
local ServerStorage      = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local GAMEPASS_ID = 0 -- ← replace with your real Game Pass ID

-- Which tools to give every player on spawn (path inside ServerStorage.Tools)
local DEFAULT_LOADOUT = {
    { folder = "Melee",  toolName = "ToolSword" },
    { folder = "Ranged", toolName = "ToolBow"   },
}

-- Optional: tool to give when the special slot is unlocked
local SPECIAL_TOOL = { folder = "Special", toolName = "ToolSpecial" }

--------------------------------------------------------------------------------
-- FOLDERS & REMOTES
--------------------------------------------------------------------------------
local toolsRoot = ServerStorage:WaitForChild("Tools")

-- Create remotes from server code so they always exist
local function getOrCreateRemote(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing then return existing end
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

local requestSpecialUnlock = getOrCreateRemote("RequestSpecialUnlock")
local specialUnlockGranted = getOrCreateRemote("SpecialUnlockGranted")
local forceEquipRemote = getOrCreateRemote("ForceEquipTool")

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local unlockState = {}   -- [player] = true/false
local promptDebounce = {} -- [player] = tick

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

--- Resolve the tool template from ServerStorage.Tools/<folder>/<toolName>.
local function getTemplate(folder, toolName)
    local categoryFolder = toolsRoot:FindFirstChild(folder)
    if not categoryFolder then
        warn("[Loadout] Missing folder ServerStorage.Tools." .. folder)
        return nil
    end
    local template = categoryFolder:FindFirstChild(toolName)
    if not template then
        warn("[Loadout] Missing tool ServerStorage.Tools." .. folder .. "." .. toolName)
        return nil
    end
    return template
end

--- Clone a tool into both StarterGear (respawn persistence) and Backpack.
--- Sets HotbarCategory attribute.  Skips duplicates per-container.
local function grantTool(player, folder, toolName)
    local template = getTemplate(folder, toolName)
    if not template then return end

    local sg   = player:WaitForChild("StarterGear", 5)
    local bp   = player:FindFirstChildOfClass("Backpack")
    local char = player.Character

    -- 1) StarterGear — persists across respawns; engine auto-clones to Backpack
    if sg and not sg:FindFirstChild(toolName) then
        local clone = template:Clone()
        clone:SetAttribute("HotbarCategory", folder)
        clone.Parent = sg
    end

    -- 2) Backpack — skip if already in Backpack or equipped in Character
    local inBP   = bp and bp:FindFirstChild(toolName)
    local inChar = char and char:FindFirstChild(toolName)
    if not inBP and not inChar and bp then
        local clone = template:Clone()
        clone:SetAttribute("HotbarCategory", folder)
        clone.Parent = bp
    end
end

--- Safety net: copy anything in StarterGear that the engine missed to Backpack.
local function ensureBackpackFromStarterGear(player)
    local sg   = player:WaitForChild("StarterGear", 5)
    local bp   = player:FindFirstChildOfClass("Backpack")
    local char = player.Character
    if not sg or not bp then return end
    for _, tool in ipairs(sg:GetChildren()) do
        if not tool:IsA("Tool") then continue end
        local inBP   = bp:FindFirstChild(tool.Name)
        local inChar = char and char:FindFirstChild(tool.Name)
        if not inBP and not inChar then
            local clone = tool:Clone()
            -- preserve HotbarCategory attribute when copying
            local cat = tool:GetAttribute("HotbarCategory")
            if cat then
                clone:SetAttribute("HotbarCategory", cat)
            end
            clone.Parent = bp
        end
    end
end

-- Create RequestToolCopy RemoteFunction now that helpers exist
local function getOrCreateRemoteFunction(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then return existing end
    if existing then existing:Destroy() end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = ReplicatedStorage
    return rf
end

local requestToolCopy = getOrCreateRemoteFunction("RequestToolCopy")

requestToolCopy.OnServerInvoke = function(player, folder, toolName)
    grantTool(player, folder, toolName)
    ensureBackpackFromStarterGear(player)
    return true
end

-- Force-equip handler: client asks server to equip a tool from their Backpack
forceEquipRemote.OnServerEvent:Connect(function(player, folder, toolName)
    local bp = player:FindFirstChildOfClass("Backpack")
    local char = player.Character
    if not bp then return end

    local tool = bp:FindFirstChild(toolName)
    if not tool then
        grantTool(player, folder, toolName)
        ensureBackpackFromStarterGear(player)
        tool = bp:FindFirstChild(toolName)
        if not tool then return end
    end

    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum:EquipTool(tool) end)
        end
    end
end)

local function giveLoadout(player)
    for _, entry in ipairs(DEFAULT_LOADOUT) do
        grantTool(player, entry.folder, entry.toolName)
    end
    -- grant special tool if unlocked and template exists
    if unlockState[player] then
        local sf = toolsRoot:FindFirstChild(SPECIAL_TOOL.folder)
        if sf and sf:FindFirstChild(SPECIAL_TOOL.toolName) then
            grantTool(player, SPECIAL_TOOL.folder, SPECIAL_TOOL.toolName)
        end
    end
end

--- Check Game Pass ownership (yields).
local function checkGamePass(player)
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
    end)
    return ok and owns == true
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player)
    -- check pass on join
    unlockState[player] = checkGamePass(player)

    -- tell the client the initial state
    pcall(function()
        specialUnlockGranted:FireClient(player, unlockState[player] == true)
    end)

    -- give tools every time the character spawns
    player.CharacterAdded:Connect(function()
        -- brief yield so the engine creates the fresh Backpack
        task.wait(0.2)
        giveLoadout(player)
        -- safety net: if the engine's StarterGear → Backpack copy was slow
        task.wait(0.5)
        ensureBackpackFromStarterGear(player)
    end)

    -- handle an already-spawned character (Studio fast-start)
    if player.Character then
        task.defer(function()
            task.wait(0.2)
            giveLoadout(player)
            task.wait(0.5)
            ensureBackpackFromStarterGear(player)
        end)
    end
end

local function onPlayerRemoving(player)
    unlockState[player]   = nil
    promptDebounce[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- catch players already in-game (Studio)
for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, p)
end

--------------------------------------------------------------------------------
-- SPECIAL-SLOT UNLOCK REQUEST
--------------------------------------------------------------------------------
requestSpecialUnlock.OnServerEvent:Connect(function(player)
    -- already unlocked?
    if unlockState[player] then
        specialUnlockGranted:FireClient(player, true)
        return
    end
    -- debounce: one prompt per 5 seconds
    local now = tick()
    if promptDebounce[player] and now - promptDebounce[player] < 5 then return end
    promptDebounce[player] = now

    -- prompt the Game Pass purchase
    pcall(function()
        MarketplaceService:PromptGamePassPurchase(player, GAMEPASS_ID)
    end)
end)

--------------------------------------------------------------------------------
-- PURCHASE FINISHED
--------------------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
    if passId ~= GAMEPASS_ID then return end
    if not purchased then return end

    unlockState[player] = true
    pcall(function()
        specialUnlockGranted:FireClient(player, true)
    end)

    -- grant the special tool immediately if template exists
    local sf = toolsRoot:FindFirstChild(SPECIAL_TOOL.folder)
    if sf and sf:FindFirstChild(SPECIAL_TOOL.toolName) then
        grantTool(player, SPECIAL_TOOL.folder, SPECIAL_TOOL.toolName)
    end
end)
