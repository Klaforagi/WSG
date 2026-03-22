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
local DataStoreService   = game:GetService("DataStoreService")

local loadoutStore = DataStoreService:GetDataStore("Loadout_v1")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local GAMEPASS_ID = 0 -- ← replace with your real Game Pass ID

-- Which tools to give every player on spawn (path inside ServerStorage.Tools)
local DEFAULT_LOADOUT = {
    { folder = "Melee",  toolName = "Starter Sword" },
    { folder = "Ranged", toolName = "Starter Slingshot" },
}

-- Optional: tool to give when the special slot is unlocked
local SPECIAL_TOOL = { folder = "Special", toolName = "Special" }

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
local setRangedRemote = getOrCreateRemote("SetRangedTool")
local setMeleeRemote = getOrCreateRemote("SetMeleeTool")

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local unlockState = {}   -- [player] = true/false
local promptDebounce = {} -- [player] = tick
local chosenRanged = {}  -- [player] = toolName override (nil = use default)
local chosenMelee = {}   -- [player] = toolName override for melee
-- SIZE ROLL SYSTEM — track which instanceId is equipped per category
local chosenInstanceId = {} -- [player] = { Melee = instanceId, Ranged = instanceId }

--------------------------------------------------------------------------------
-- LOADOUT PERSISTENCE
--------------------------------------------------------------------------------
local function saveLoadout(player)
    local key = "user_" .. player.UserId
    local ids = chosenInstanceId[player]
    local data = {
        melee  = chosenMelee[player],
        ranged = chosenRanged[player],
        meleeInstanceId  = ids and ids.Melee or nil,
        rangedInstanceId = ids and ids.Ranged or nil,
    }
    local ok, err = pcall(function()
        loadoutStore:SetAsync(key, data)
    end)
    if not ok then
        warn("[Loadout] Failed to save loadout for", player.Name, err)
    end
end

local function loadLoadout(player)
    local key = "user_" .. player.UserId
    local ok, data = pcall(function()
        return loadoutStore:GetAsync(key)
    end)
    if ok and type(data) == "table" then
        if type(data.melee) == "string" and #data.melee > 0 then
            chosenMelee[player] = data.melee
        end
        if type(data.ranged) == "string" and #data.ranged > 0 then
            chosenRanged[player] = data.ranged
        end
        -- Restore equipped instanceIds
        if type(data.meleeInstanceId) == "string" or type(data.rangedInstanceId) == "string" then
            if not chosenInstanceId[player] then chosenInstanceId[player] = {} end
            if type(data.meleeInstanceId) == "string" then
                chosenInstanceId[player].Melee = data.meleeInstanceId
            end
            if type(data.rangedInstanceId) == "string" then
                chosenInstanceId[player].Ranged = data.rangedInstanceId
            end
        end
    elseif not ok then
        warn("[Loadout] Failed to load loadout for", player.Name, data)
    end
end

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
        -- Legacy name fallback: map renamed tools (e.g. Shortbow -> Bow)
        local legacyMap = {
            Shortbow = "Bow",
        }
        local tryName = legacyMap[toolName]
        if tryName then
            template = categoryFolder:FindFirstChild(tryName)
            if template then
                warn("[Loadout] Using legacy template name for", toolName, "->", tryName)
                return template
            end
        end
        warn("[Loadout] Missing tool ServerStorage.Tools." .. folder .. "." .. toolName)
        return nil
    end
    return template
end

-- Ensure a tool's physical parts won't collide when equipped/backpacked.
local function sanitizeTool(tool)
    if not tool then return end
    for _, d in ipairs(tool:GetDescendants()) do
        if d and d:IsA("BasePart") then
            pcall(function()
                d.CanCollide = false
            end)
            pcall(function() d.CanTouch = false end)
            pcall(function() d.CanQuery = false end)
            pcall(function() d.Massless = true end)
        end
        -- Disable any SwordTrail by default so it only shows during swings
        if d and d:IsA("Trail") and d.Name == "SwordTrail" then
            pcall(function()
                d.Enabled = false
                -- Set the intended white/gray transparent look so every clone matches
                d.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 240, 240)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
                })
                d.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.75),
                    NumberSequenceKeypoint.new(1, 0.95),
                })
                d.Lifetime = 0.14
                d.MinLength = 0
                d.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0.25)})
                d.FaceCamera = false
                d.LightInfluence = 0
            end)
        end
    end
end

-- SIZE ROLL SYSTEM — lazy-load WeaponScaleService for tool scaling
local WeaponScaleService = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("WeaponScaleService")
    if mod and mod:IsA("ModuleScript") then
        WeaponScaleService = require(mod)
    end
end)

-- SIZE ROLL SYSTEM — lazy-load WeaponInstanceService early ref for scaling
-- (The full lazy-load for ownership checks is further down; this forward
--  declaration lets applyWeaponScale resolve at call time, not parse time.)
local WeaponInstanceService_scale = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("WeaponInstanceService")
    if mod and mod:IsA("ModuleScript") then
        WeaponInstanceService_scale = require(mod)
    end
end)

--- Look up the player's weapon instance and apply visual scaling.
--- If instanceId is provided, uses that specific instance; otherwise picks
--- the first matching instance by weapon name.
local function applyWeaponScale(player, toolClone, toolName, instanceId)
    if not WeaponScaleService or not WeaponInstanceService_scale then return end
    local inv = WeaponInstanceService_scale:GetInventory(player)
    if not inv then return end
    local bestInstance = nil
    -- Prefer the specific instanceId if provided
    if instanceId and inv[instanceId] then
        bestInstance = inv[instanceId]
    else
        for _, data in pairs(inv) do
            if type(data) == "table" and data.weaponName == toolName then
                bestInstance = data
                break
            end
        end
    end
    if bestInstance and bestInstance.sizePercent and bestInstance.sizePercent ~= 100 then
        WeaponScaleService.ApplyScale(toolClone, bestInstance.sizePercent)
    end
end

--- Clone a tool into both StarterGear (respawn persistence) and Backpack.
--- Sets HotbarCategory attribute.  Skips duplicates per-container.
--- instanceId is optional; used by SIZE ROLL SYSTEM to scale the correct copy.
local function grantTool(player, folder, toolName, instanceId)
    local template = getTemplate(folder, toolName)
    if not template then return end

    local sg   = player:WaitForChild("StarterGear", 5)
    local bp   = player:FindFirstChildOfClass("Backpack")
    local char = player.Character

    -- 1) StarterGear — persists across respawns; engine auto-clones to Backpack
    if sg and not sg:FindFirstChild(toolName) then
        local clone = template:Clone()
        clone:SetAttribute("HotbarCategory", folder)
        sanitizeTool(clone)
        local scaleOk, scaleErr = pcall(applyWeaponScale, player, clone, toolName, instanceId)
        if not scaleOk then warn("[Loadout] applyWeaponScale error:", scaleErr) end
        clone.Parent = sg
    end

    -- 2) Backpack — skip if already in Backpack or equipped in Character
    local inBP   = bp and bp:FindFirstChild(toolName)
    local inChar = char and char:FindFirstChild(toolName)
    if not inBP and not inChar and bp then
        local clone = template:Clone()
        clone:SetAttribute("HotbarCategory", folder)
        sanitizeTool(clone)
        local scaleOk, scaleErr = pcall(applyWeaponScale, player, clone, toolName, instanceId)
        if not scaleOk then warn("[Loadout] applyWeaponScale error:", scaleErr) end
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

-- Let the client query the saved loadout so the inventory UI shows correct state
local getLoadoutRF = getOrCreateRemoteFunction("GetLoadout")
getLoadoutRF.OnServerInvoke = function(player)
    local ids = chosenInstanceId[player]
    return {
        melee  = chosenMelee[player],
        ranged = chosenRanged[player],
        meleeInstanceId  = ids and ids.Melee or nil,
        rangedInstanceId = ids and ids.Ranged or nil,
    }
end

--------------------------------------------------------------------------------
-- SERVER-AUTHORITATIVE PURCHASE
-- Price table lives here so the client can never cheat.
--------------------------------------------------------------------------------
local PRICES = {
    -- Starters (free, everyone gets one instance)
    ["Starter Sword"]     = 0,
    ["Starter Slingshot"] = 0,
    -- Melee
    ["Wooden Sword"] = 0,
    Dagger  = 30,
    Sword   = 30,
    Spear   = 30,
    -- Ranged
    Slingshot = 0,
    Shortbow  = 20,
    Longbow   = 30,
    Xbow      = 40,
}

-- Lazy-load CurrencyService (same pattern the rest of the codebase uses)
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

local purchaseTool = getOrCreateRemoteFunction("PurchaseTool")

-- Lazy-load WeaponInstanceService for crate-ownership checks
local WeaponInstanceService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("WeaponInstanceService")
    if mod and mod:IsA("ModuleScript") then
        WeaponInstanceService = require(mod)
    end
end)

-- Check whether a player owns a weapon (legacy StarterGear OR crate instance)
local function playerOwnsWeapon(player, toolName)
    -- Legacy check: tool exists in StarterGear
    local sg = player:FindFirstChild("StarterGear")
    if sg and sg:FindFirstChild(toolName) then return true end
    -- Free starters always allowed
    local price = PRICES[toolName]
    if price == 0 then return true end
    -- Crate instance check
    if WeaponInstanceService then
        local count = WeaponInstanceService:CountWeapon(player, toolName)
        if count > 0 then return true end
    end
    return false
end

-- Returns: success (bool), newBalance (number)
purchaseTool.OnServerInvoke = function(player, category, toolName)
    if type(toolName) ~= "string" or type(category) ~= "string" then
        return false, 0
    end

    local price = PRICES[toolName]
    if not price then
        warn("[PurchaseTool] Unknown item:", toolName)
        return false, 0
    end

    if not CurrencyService then
        warn("[PurchaseTool] CurrencyService not available")
        return false, 0
    end

    local balance = CurrencyService:GetCoins(player)
    if balance < price then
        return false, balance
    end

    -- Deduct coins and grant the tool
    CurrencyService:SetCoins(player, balance - price)
    grantTool(player, category, toolName)
    ensureBackpackFromStarterGear(player)

    local newBalance = CurrencyService:GetCoins(player)
    return true, newBalance
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

-- Replace the player's Ranged slot tool (StarterGear + Backpack) without equipping.
setRangedRemote.OnServerEvent:Connect(function(player, toolName, instanceId)
    -- remove existing Ranged tools from StarterGear and Backpack
    local sg = player:FindFirstChild("StarterGear")
    local bp = player:FindFirstChildOfClass("Backpack")
    if sg then
        for i = #sg:GetChildren(), 1, -1 do
            local child = sg:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "ranged" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    if bp then
        for i = #bp:GetChildren(), 1, -1 do
            local child = bp:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "ranged" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    -- remove ranged tools currently equipped on the character as well
    if player.Character then
        for i = #player.Character:GetChildren(), 1, -1 do
            local child = player.Character:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "ranged" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end

    -- grant the requested ranged tool into StarterGear/Backpack (sets HotbarCategory)
    if type(toolName) == "string" and #toolName > 0 then
        if not playerOwnsWeapon(player, toolName) then
            warn("[Loadout] Player", player.Name, "does not own ranged weapon:", toolName)
            return
        end
        -- SIZE ROLL SYSTEM — store which instance is equipped for scaling
        if not chosenInstanceId[player] then chosenInstanceId[player] = {} end
        chosenInstanceId[player].Ranged = instanceId
        chosenRanged[player] = toolName
        grantTool(player, "Ranged", toolName, instanceId)
        ensureBackpackFromStarterGear(player)
        task.spawn(saveLoadout, player)
    end
end)

-- Replace the player's Melee slot tool (StarterGear + Backpack) without equipping.
setMeleeRemote.OnServerEvent:Connect(function(player, toolName, instanceId)
    -- remove existing Melee tools from StarterGear and Backpack
    local sg = player:FindFirstChild("StarterGear")
    local bp = player:FindFirstChildOfClass("Backpack")
    if sg then
        for i = #sg:GetChildren(), 1, -1 do
            local child = sg:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "melee" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    if bp then
        for i = #bp:GetChildren(), 1, -1 do
            local child = bp:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "melee" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    -- remove melee tools currently equipped on the character as well
    if player.Character then
        for i = #player.Character:GetChildren(), 1, -1 do
            local child = player.Character:GetChildren()[i]
            if child and child:IsA("Tool") then
                local attr = child:GetAttribute("HotbarCategory")
                if type(attr) == "string" and string.lower(attr) == "melee" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end

    -- grant the requested melee tool into StarterGear/Backpack (sets HotbarCategory)
    if type(toolName) == "string" and #toolName > 0 then
        if not playerOwnsWeapon(player, toolName) then
            warn("[Loadout] Player", player.Name, "does not own melee weapon:", toolName)
            return
        end
        -- SIZE ROLL SYSTEM — store which instance is equipped for scaling
        if not chosenInstanceId[player] then chosenInstanceId[player] = {} end
        chosenInstanceId[player].Melee = instanceId
        chosenMelee[player] = toolName
        grantTool(player, "Melee", toolName, instanceId)
        ensureBackpackFromStarterGear(player)
        task.spawn(saveLoadout, player)
    end
end)

local function giveLoadout(player)
    local playerInstIds = chosenInstanceId[player] or {}
    for _, entry in ipairs(DEFAULT_LOADOUT) do
        local folder = entry.folder
        local toolName = entry.toolName
        local instId = nil
        -- honour the player's chosen ranged weapon if they swapped it
        if string.lower(folder) == "ranged" and chosenRanged[player] then
            toolName = chosenRanged[player]
            instId = playerInstIds.Ranged
        end
        -- honour player's chosen melee weapon if they swapped it
        if string.lower(folder) == "melee" and chosenMelee[player] then
            toolName = chosenMelee[player]
            instId = playerInstIds.Melee
        end
        grantTool(player, folder, toolName, instId)
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
    -- load saved loadout choices before first spawn
    loadLoadout(player)

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
    saveLoadout(player)
    unlockState[player]    = nil
    promptDebounce[player] = nil
    chosenRanged[player]     = nil
    chosenMelee[player]      = nil
    chosenInstanceId[player] = nil
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

--------------------------------------------------------------------------------
-- SAVE ALL ON SHUTDOWN
--------------------------------------------------------------------------------
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(saveLoadout, player)
    end
    task.wait(2)
end)
