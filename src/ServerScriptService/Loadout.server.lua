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
local ServerScriptService = game:GetService("ServerScriptService")

local DataStoreOps = require(ServerScriptService:WaitForChild("DataStoreOps"))
local DataSaveCoordinator = require(ServerScriptService:WaitForChild("DataSaveCoordinator"))

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

local WeaponTrailService = nil
pcall(function()
    local mod = ServerScriptService:FindFirstChild("WeaponTrailService")
    if mod and mod:IsA("ModuleScript") then
        WeaponTrailService = require(mod)
    end
end)

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
local loadoutChangedRemote = getOrCreateRemote("LoadoutChanged")
local menuStateRemote = getOrCreateRemote("MenuStateChanged")

--------------------------------------------------------------------------------
-- MENU LOCK: server-side enforcement
-- The client fires MenuStateChanged(true/false) when menus open/close.
-- We also set a player attribute so other server scripts can check it.
--------------------------------------------------------------------------------
menuStateRemote.OnServerEvent:Connect(function(player, isOpen)
    -- Sanitize: only accept boolean
    if type(isOpen) ~= "boolean" then return end
    player:SetAttribute("MenuOpen", isOpen)

    -- If menu just opened, force-unequip any held tool
    if isOpen then
        local char = player.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum:UnequipTools() end)
            end
        end
    end
end)

--- Helper: is this player currently menu-locked?
local function isPlayerMenuLocked(player)
    return player:GetAttribute("MenuOpen") == true
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local unlockState = {}   -- [player] = true/false
local promptDebounce = {} -- [player] = tick
local chosenRanged = {}  -- [player] = toolName override (nil = use default)
local chosenMelee = {}   -- [player] = toolName override for melee
local chosenInstanceId = {} -- [player] = { Melee = id, Ranged = id }
local loadoutSectionRegistered = false
local canClientRequestTool -- defined after playerOwnsWeapon

local function buildLoadoutData(player)
    local ids = chosenInstanceId[player]
    return {
        melee = chosenMelee[player],
        ranged = chosenRanged[player],
        meleeInstanceId = ids and ids.Melee or nil,
        rangedInstanceId = ids and ids.Ranged or nil,
    }
end

local function hasMeaningfulLoadout(data)
    if type(data) ~= "table" then
        return false
    end
    return (type(data.melee) == "string" and data.melee ~= "")
        or (type(data.ranged) == "string" and data.ranged ~= "")
        or (type(data.meleeInstanceId) == "string" and data.meleeInstanceId ~= "")
        or (type(data.rangedInstanceId) == "string" and data.rangedInstanceId ~= "")
end

local function markLoadoutDirty(player, reason, options)
    DataSaveCoordinator:MarkDirty(player, "Loadout", reason or "loadout", options)
end

local function applyLoadoutData(player, data)
    chosenMelee[player] = nil
    chosenRanged[player] = nil
    chosenInstanceId[player] = nil

    if type(data) ~= "table" then
        return
    end

    if type(data.melee) == "string" and #data.melee > 0 then
        chosenMelee[player] = data.melee
    end
    if type(data.ranged) == "string" and #data.ranged > 0 then
        chosenRanged[player] = data.ranged
    end
    if type(data.meleeInstanceId) == "string" or type(data.rangedInstanceId) == "string" then
        chosenInstanceId[player] = {}
        if type(data.meleeInstanceId) == "string" then
            chosenInstanceId[player].Melee = data.meleeInstanceId
        end
        if type(data.rangedInstanceId) == "string" then
            chosenInstanceId[player].Ranged = data.rangedInstanceId
        end
    end
end

--------------------------------------------------------------------------------
-- SALVAGE SYSTEM  – BindableFunction so SalvageService can check equipped state
--------------------------------------------------------------------------------
local isEquippedBF = Instance.new("BindableFunction")
isEquippedBF.Name = "IsInstanceEquipped"
isEquippedBF.Parent = game:GetService("ServerScriptService")

isEquippedBF.OnInvoke = function(player, instanceId)
    if not player or type(instanceId) ~= "string" then return false end
    local ids = chosenInstanceId[player]
    if not ids then return false end
    return ids.Melee == instanceId or ids.Ranged == instanceId
end

--------------------------------------------------------------------------------
-- LOADOUT PERSISTENCE
--------------------------------------------------------------------------------
local function saveLoadout(player)
    local key = "user_" .. player.UserId
    local data = buildLoadoutData(player)
    print("[EquipSave]", player.Name,
        "melee=", data.melee or "(nil)",
        "ranged=", data.ranged or "(nil)",
        "meleeInstId=", data.meleeInstanceId or "(nil)",
        "rangedInstId=", data.rangedInstanceId or "(nil)")
    local ok, _, err = DataStoreOps.Update(loadoutStore, key, "Loadout/" .. key, function(oldData)
        if hasMeaningfulLoadout(oldData) and not hasMeaningfulLoadout(data) then
            warn("[EquipSave] Suspected loadout wipe blocked for", player.Name)
            return oldData
        end
        return data
    end)
    if not ok then
        warn("[EquipSave] Failed to save loadout for", player.Name, err)
        return false, err
    else
        print("[EquipSave] Saved successfully for", player.Name)
        return true
    end
end

local function loadLoadout(player)
    local key = "user_" .. player.UserId
    local ok, data, err = DataStoreOps.Load(loadoutStore, key, "Loadout/" .. key)
    if ok and type(data) == "table" then
        print("[EquipLoad]", player.Name, "raw data:",
            "melee=", data.melee or "(nil)",
            "ranged=", data.ranged or "(nil)",
            "meleeInstId=", data.meleeInstanceId or "(nil)",
            "rangedInstId=", data.rangedInstanceId or "(nil)")
        applyLoadoutData(player, data)
        return data, "existing", nil
    elseif ok then
        print("[EquipLoad]", player.Name, "no saved loadout (new player or empty data)")
        applyLoadoutData(player, nil)
        return buildLoadoutData(player), "new", nil
    else
        warn("[EquipLoad] Failed to load loadout for", player.Name, err)
        applyLoadoutData(player, nil)
        return buildLoadoutData(player), "failed", err
    end
end

local function registerLoadoutSection()
    if loadoutSectionRegistered then
        return
    end
    loadoutSectionRegistered = true

    DataSaveCoordinator:RegisterSection({
        Name = "Loadout",
        Priority = 65,
        Critical = false,
        Load = function(player)
            local data, status, reason = loadLoadout(player)
            return {
                status = status,
                data = data,
                reason = reason,
            }
        end,
        GetSaveData = function(player)
            return buildLoadoutData(player)
        end,
        Save = function(player)
            return saveLoadout(player)
        end,
        Cleanup = function(player)
            unlockState[player] = nil
            promptDebounce[player] = nil
            chosenRanged[player] = nil
            chosenMelee[player] = nil
            chosenInstanceId[player] = nil
        end,
        Validate = function(_, currentData, lastGoodData)
            if hasMeaningfulLoadout(lastGoodData) and not hasMeaningfulLoadout(currentData) then
                return {
                    suspicious = true,
                    severity = "warning",
                    reason = "loadout reset to empty",
                }
            end
            return nil
        end,
    })
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
        -- Legacy name fallback for renamed templates
        local legacyMap = {
            Shortbow = "Bow",
            Longbow = "Bow",
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
    -- Convert WeldConstraints to Welds so we can scale offsets (WeldConstraint has no C0/C1)
    for _, wc in ipairs(tool:GetDescendants()) do
        if wc and wc:IsA("WeldConstraint") then
            local p0 = wc.Part0
            local p1 = wc.Part1
            if p0 and p1 then
                local w = Instance.new("Weld")
                w.Name = wc.Name or "Weld_from_WeldConstraint"
                w.Part0 = p0
                w.Part1 = p1
                -- Compute C0 as Part0.CFrame:ToObjectSpace(Part1.CFrame)
                local ok, c0 = pcall(function() return p0.CFrame:ToObjectSpace(p1.CFrame) end)
                if ok and c0 then
                    w.C0 = c0
                else
                    w.C0 = CFrame.new()
                end
                w.C1 = CFrame.new()
                -- Parent the weld to Part0 to mirror typical Weld placement
                w.Parent = p0
            end
            wc:Destroy()
        end
    end
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

    if WeaponTrailService and tool:IsA("Tool") then
        local trailOk, trailErr = pcall(WeaponTrailService.ApplyToTool, tool)
        if not trailOk then
            warn("[Loadout] WeaponTrailService error:", trailErr)
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

local AssetCodes = nil
pcall(function()
    local mod = ReplicatedStorage:FindFirstChild("AssetCodes")
    if mod and mod:IsA("ModuleScript") then
        AssetCodes = require(mod)
    end
end)

local function applyToolIcon(tool, toolName, enchantName)
    if not tool then return end
    local icon = nil
    if AssetCodes and type(AssetCodes.GetWeaponIcon) == "function" then
        icon = AssetCodes.GetWeaponIcon(toolName, enchantName)
    elseif AssetCodes and type(AssetCodes.Get) == "function" then
        icon = AssetCodes.Get(toolName)
    end
    if type(icon) == "string" and icon ~= "" then
        pcall(function()
            tool.TextureId = icon
            tool:SetAttribute("Icon", icon)
        end)
    end
end

-- ENCHANT SYSTEM — lazy-load WeaponEnchantService for enchant visual application
local WeaponEnchantService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("WeaponEnchantService")
    if mod and mod:IsA("ModuleScript") then
        WeaponEnchantService = require(mod)
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
    if WeaponScaleService then
        pcall(function()
            WeaponScaleService.BindGripAlignment(toolClone)
        end)
    end
    if not WeaponScaleService or not WeaponInstanceService_scale then return end
    local inv = WeaponInstanceService_scale:GetInventory(player)
    if not inv then return end
    local bestInstance = nil
    if type(instanceId) == "string" and instanceId ~= "" then
        local rec = inv[instanceId]
        if type(rec) == "table" and rec.weaponName == toolName then
            bestInstance = rec
        end
    end
    if not bestInstance then
        for _, data in pairs(inv) do
            if type(data) == "table" and data.weaponName == toolName then
                bestInstance = data
                break
            end
        end
    end
    if bestInstance and bestInstance.sizePercent then
        -- Stamp size as an attribute so ToolMeleeSetup / ToolMelee.client can read it
        toolClone:SetAttribute("SizePercent", bestInstance.sizePercent)
        toolClone:SetAttribute("WeaponBaseSizePercent", bestInstance.sizePercent)
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local playerSize = humanoid and tonumber(humanoid:GetAttribute("SizePercent")) or 100
        -- The weapon roll and temporary player-size buffs are visual-only here.
        WeaponScaleService.ApplyScale(toolClone, bestInstance.sizePercent * playerSize / 100)
    end
end

local function syncPlayerWeaponCosmetics(player, character)
    if not WeaponScaleService or not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local function refreshTool(tool)
        if player.Character ~= character or not humanoid.Parent then return end
        if tool.Parent ~= character and tool.Parent ~= player:FindFirstChildOfClass("Backpack")
            and tool.Parent ~= player:FindFirstChild("StarterGear") then return end
        local base = tool:IsA("Tool") and tonumber(tool:GetAttribute("WeaponBaseSizePercent"))
        if not base then return end
        local playerSize = tonumber(humanoid:GetAttribute("SizePercent")) or 100
        pcall(WeaponScaleService.ApplyScale, tool, base * playerSize / 100)
    end
    local function refresh()
        if player.Character ~= character or not humanoid.Parent then return end
        for _, container in ipairs({ character, player:FindFirstChildOfClass("Backpack"), player:FindFirstChild("StarterGear") }) do
            if container then
                for _, tool in ipairs(container:GetChildren()) do
                    refreshTool(tool)
                end
            end
        end
    end
    local connections = {}
    table.insert(connections, humanoid:GetAttributeChangedSignal("SizePercent"):Connect(refresh))
    -- Copies arriving from StarterGear and tools being drawn must be restored
    -- from their saved originals using this character's current size.
    local function onToolAdded(child)
        if child:IsA("Tool") then task.defer(refreshTool, child) end
    end
    table.insert(connections, character.ChildAdded:Connect(onToolAdded))
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        table.insert(connections, backpack.ChildAdded:Connect(onToolAdded))
    end
    table.insert(connections, player.CharacterRemoving:Connect(function(removing)
        if removing ~= character then return end
        for _, connection in ipairs(connections) do connection:Disconnect() end
    end))
    task.defer(refresh)
end

local function bindGripAlignmentForTool(tool)
    if not WeaponScaleService or not tool or not tool:IsA("Tool") then
        return
    end

    pcall(function()
        WeaponScaleService.BindGripAlignment(tool)
    end)
end

local function bindGripAlignmentInContainer(container)
    if not container then
        return
    end

    for _, child in ipairs(container:GetChildren()) do
        bindGripAlignmentForTool(child)
    end
end

--- ENCHANT SYSTEM — Look up the player's weapon instance enchant data and apply visuals.
--- Called after applyWeaponScale so enchant emitters are created on the already-scaled weapon.
local function applyWeaponEnchant(player, toolClone, toolName, instanceId)
    if not WeaponEnchantService or not WeaponInstanceService_scale then
        applyToolIcon(toolClone, toolName, nil)
        return
    end
    local inv = WeaponInstanceService_scale:GetInventory(player)
    if not inv then
        applyToolIcon(toolClone, toolName, nil)
        return
    end
    local bestInstance = nil
    if type(instanceId) == "string" and instanceId ~= "" then
        local rec = inv[instanceId]
        if type(rec) == "table" and rec.weaponName == toolName then
            bestInstance = rec
        end
    end
    if not bestInstance then
        for _, data in pairs(inv) do
            if type(data) == "table" and data.weaponName == toolName then
                bestInstance = data
                break
            end
        end
    end
    local enchantName = bestInstance and bestInstance.enchantName or nil
    if bestInstance then
        local hasEnchant = type(bestInstance.enchantName) == "string" and bestInstance.enchantName ~= ""
        local requiresEnchant = false
        pcall(function()
            local enchantConfig = ReplicatedStorage:FindFirstChild("WeaponEnchantConfig")
            if enchantConfig and enchantConfig:IsA("ModuleScript") then
                local cfg = require(enchantConfig)
                requiresEnchant = type(cfg.RequiresEnchant) == "function" and cfg.RequiresEnchant(toolName)
            end
        end)

        if hasEnchant or requiresEnchant or bestInstance.enchantRollFinal then
            local beforeEnchant = bestInstance.enchantName
            WeaponEnchantService.ApplyEnchantFromInstance(toolClone, bestInstance)
            enchantName = bestInstance.enchantName
            if bestInstance.enchantName ~= beforeEnchant and WeaponInstanceService_scale.SaveForPlayer then
                pcall(function()
                    WeaponInstanceService_scale:SaveForPlayer(player)
                end)
            end
        end
    end

    applyToolIcon(toolClone, toolName, enchantName)
end

local function resolveWeaponInstanceId(player, toolName, instanceId)
    if not WeaponInstanceService_scale then return nil end
    local inv = WeaponInstanceService_scale:GetInventory(player)
    if type(inv) ~= "table" then return nil end
    if type(instanceId) == "string" and instanceId ~= "" then
        local rec = inv[instanceId]
        if type(rec) == "table" and rec.weaponName == toolName then
            return instanceId
        end
    end
    for id, data in pairs(inv) do
        if type(id) == "string" and type(data) == "table" and data.weaponName == toolName then
            return id
        end
    end
    return nil
end

local function stampWeaponAttributes(player, toolClone, folder, toolName, instanceId)
    if not toolClone then return end
    local resolvedInstanceId = resolveWeaponInstanceId(player, toolName, instanceId)
    toolClone:SetAttribute("HotbarCategory", folder)
    toolClone:SetAttribute("WeaponCategory", folder)
    toolClone:SetAttribute("WeaponName", toolName)
    if type(resolvedInstanceId) == "string" and resolvedInstanceId ~= "" then
        toolClone:SetAttribute("WeaponInstanceId", resolvedInstanceId)
    else
        toolClone:SetAttribute("WeaponInstanceId", nil)
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
    local addedToStarterGear = false
    if sg and not sg:FindFirstChild(toolName) then
        local clone = template:Clone()
        stampWeaponAttributes(player, clone, folder, toolName, instanceId)
        sanitizeTool(clone)
        -- Parent first so relative CFrames and pivot math are correct, then scale
        clone.Parent = sg
        local scaleOk, scaleErr = pcall(applyWeaponScale, player, clone, toolName, instanceId)
        if not scaleOk then warn("[Loadout] applyWeaponScale error:", scaleErr) end
        -- ENCHANT SYSTEM: apply enchant visuals after scaling
        local enchantOk, enchantErr = pcall(applyWeaponEnchant, player, clone, toolName, instanceId)
        if not enchantOk then warn("[Loadout] applyWeaponEnchant error:", enchantErr) end
        addedToStarterGear = true
    end

    -- 2) Backpack — skip if already in Backpack or equipped in Character.
    -- If we just added the tool to StarterGear, wait a short moment and let
    -- the engine copy StarterGear → Backpack; only create a Backup clone if
    -- the engine did not produce one (avoids creating duplicates).
    local inBP   = bp and bp:FindFirstChild(toolName)
    local inChar = char and char:FindFirstChild(toolName)
    if not inBP and not inChar and bp then
        if addedToStarterGear then
            task.delay(0.2, function()
                if not (bp and bp.Parent) then return end
                local nowInBP = bp:FindFirstChild(toolName)
                if nowInBP then
                    return
                end
                -- engine didn't copy StarterGear → Backpack; create the clone now
                local clone = template:Clone()
                stampWeaponAttributes(player, clone, folder, toolName, instanceId)
                sanitizeTool(clone)
                clone.Parent = bp
                local scaleOk, scaleErr = pcall(applyWeaponScale, player, clone, toolName, instanceId)
                if not scaleOk then warn("[Loadout] applyWeaponScale error:", scaleErr) end
                local enchantOk, enchantErr = pcall(applyWeaponEnchant, player, clone, toolName, instanceId)
                if not enchantOk then warn("[Loadout] applyWeaponEnchant error:", enchantErr) end
            end)
        else
            local clone = template:Clone()
            stampWeaponAttributes(player, clone, folder, toolName, instanceId)
            sanitizeTool(clone)
            -- Parent into Backpack first so the tool's world/relative CFrames are stable
            clone.Parent = bp
            local scaleOk, scaleErr = pcall(applyWeaponScale, player, clone, toolName, instanceId)
            if not scaleOk then warn("[Loadout] applyWeaponScale error:", scaleErr) end
            -- ENCHANT SYSTEM: apply enchant visuals after scaling
            local enchantOk, enchantErr = pcall(applyWeaponEnchant, player, clone, toolName, instanceId)
            if not enchantOk then warn("[Loadout] applyWeaponEnchant error:", enchantErr) end
        end
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
            if WeaponScaleService then
                pcall(function()
                    WeaponScaleService.BindGripAlignment(clone)
                end)
            end
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
    if not canClientRequestTool(player, folder, toolName) then
        warn("[Loadout] RequestToolCopy rejected for", player and player.Name, folder, toolName)
        return false
    end
    grantTool(player, folder, toolName)
    ensureBackpackFromStarterGear(player)
    return true
end

-- Let the client query the saved loadout so the inventory UI shows correct state
local getLoadoutRF = getOrCreateRemoteFunction("GetLoadout")
getLoadoutRF.OnServerInvoke = function(player)
    local ids = chosenInstanceId[player]
    local result = {
        melee  = chosenMelee[player] or "Starter Sword",
        ranged = chosenRanged[player] or "Starter Slingshot",
        meleeInstanceId  = ids and ids.Melee or nil,
        rangedInstanceId = ids and ids.Ranged or nil,
    }
    print("[EquipLoad] GetLoadout invoked by", player.Name,
        "melee=", result.melee, "ranged=", result.ranged,
        "meleeInstId=", result.meleeInstanceId or "(nil)",
        "rangedInstId=", result.rangedInstanceId or "(nil)")
    return result
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
    ["Punisher"] = 0,
    ["Kingsblade"] = 0,
    Dagger  = 30,
    Sword   = 30,
    Spear   = 30,
    -- Crate ranged weapons are owned via WeaponInstanceService, not this table.
}

-- Lazy-load CurrencyService (same pattern the rest of the codebase uses)
local CurrencyService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("CurrencyService")
    if mod and mod:IsA("ModuleScript") then
        CurrencyService = require(mod)
    end
end)

-- Lazy-load AchievementService for purchase stat tracking
local AchievementService = nil
pcall(function()
    local mod = game:GetService("ServerScriptService"):FindFirstChild("AchievementService")
    if mod and mod:IsA("ModuleScript") then
        AchievementService = require(mod)
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
local STARTER_WEAPONS = {
    ["Starter Sword"] = true,
    ["Starter Slingshot"] = true,
}

local function playerOwnsWeapon(player, toolName)
    -- Legacy check: tool exists in StarterGear
    local sg = player:FindFirstChild("StarterGear")
    if sg and sg:FindFirstChild(toolName) then return true end
    if STARTER_WEAPONS[toolName] then return true end
    -- Crate instance check
    if WeaponInstanceService then
        local count = WeaponInstanceService:CountWeapon(player, toolName)
        if count > 0 then return true end
    end
    return false
end

local CLIENT_GRANT_FOLDERS = {
    Melee = true,
    Ranged = true,
    Special = true,
    Utility = true,
}

canClientRequestTool = function(player, folder, toolName)
    if not player or type(folder) ~= "string" or type(toolName) ~= "string" then
        return false
    end
    if folder == "" or toolName == "" then
        return false
    end
    if folder == "Dev" then
        local ok, DevUserIds = pcall(function()
            return require(ReplicatedStorage:FindFirstChild("DevUserIds"))
        end)
        return ok and type(DevUserIds) == "table" and type(DevUserIds.IsDev) == "function" and DevUserIds.IsDev(player) == true
    end
    if not CLIENT_GRANT_FOLDERS[folder] then
        return false
    end
    for _, entry in ipairs(DEFAULT_LOADOUT) do
        if entry.folder == folder and entry.toolName == toolName then
            return true
        end
    end
    if SPECIAL_TOOL and folder == SPECIAL_TOOL.folder and toolName == SPECIAL_TOOL.toolName then
        return unlockState[player] == true
    end
    return playerOwnsWeapon(player, toolName)
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

    -- Track purchase for achievements (e.g. First Purchase)
    if AchievementService then
        pcall(function() AchievementService:IncrementStat(player, "totalPurchases", 1) end)
    end

    local newBalance = CurrencyService:GetCoins(player)
    return true, newBalance
end

-- Force-equip handler: client asks server to equip a tool from their Backpack
forceEquipRemote.OnServerEvent:Connect(function(player, folder, toolName)
    -- SERVER MENU-LOCK GUARD: reject equip while any menu is open
    if isPlayerMenuLocked(player) then
        return
    end
    if player:GetAttribute("ToolsLocked") == true or player:GetAttribute("DefeatLockActive") == true then
        return
    end
    if type(toolName) ~= "string" or toolName == "" then
        return
    end

    local bp = player:FindFirstChildOfClass("Backpack")
    local char = player.Character
    if not bp then return end

    local tool = bp:FindFirstChild(toolName)
    if not tool then
        if not canClientRequestTool(player, folder, toolName) then
            warn("[Loadout] ForceEquipTool grant rejected for", player and player.Name, folder, toolName)
            return
        end
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
        chosenRanged[player] = toolName
        if not chosenInstanceId[player] then chosenInstanceId[player] = {} end
        chosenInstanceId[player].Ranged = instanceId
        print("[ToolbarSync]", player.Name, "equipped ranged:", toolName, "instanceId:", instanceId or "(nil)")
        grantTool(player, "Ranged", toolName, instanceId)
        ensureBackpackFromStarterGear(player)
        markLoadoutDirty(player, "set_ranged")
        -- Notify client of loadout change
        pcall(function()
            loadoutChangedRemote:FireClient(player, {
                melee  = chosenMelee[player],
                ranged = chosenRanged[player],
                meleeInstanceId  = chosenInstanceId[player] and chosenInstanceId[player].Melee or nil,
                rangedInstanceId = instanceId,
            })
        end)
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
        chosenMelee[player] = toolName
        if not chosenInstanceId[player] then chosenInstanceId[player] = {} end
        chosenInstanceId[player].Melee = instanceId
        print("[ToolbarSync]", player.Name, "equipped melee:", toolName, "instanceId:", instanceId or "(nil)")
        grantTool(player, "Melee", toolName, instanceId)
        ensureBackpackFromStarterGear(player)
        markLoadoutDirty(player, "set_melee")
        -- Notify client of loadout change
        pcall(function()
            loadoutChangedRemote:FireClient(player, {
                melee  = chosenMelee[player],
                ranged = chosenRanged[player],
                meleeInstanceId  = instanceId,
                rangedInstanceId = chosenInstanceId[player] and chosenInstanceId[player].Ranged or nil,
            })
        end)
    end
end)

--- Validate that the saved equipped weapons still exist in the player's inventory.
--- Falls back to starter weapons if the saved weapon is no longer owned.
local function validateLoadout(player)
    -- Validate melee
    local meleeChoice = chosenMelee[player]
    if meleeChoice then
        if not playerOwnsWeapon(player, meleeChoice) then
            warn("[EquipLoad]", player.Name, "saved melee", meleeChoice, "no longer owned, falling back to Starter Sword")
            chosenMelee[player] = "Starter Sword"
            if chosenInstanceId[player] then chosenInstanceId[player].Melee = nil end
        end
    end
    -- Validate ranged
    local rangedChoice = chosenRanged[player]
    if rangedChoice then
        if not playerOwnsWeapon(player, rangedChoice) then
            warn("[EquipLoad]", player.Name, "saved ranged", rangedChoice, "no longer owned, falling back to Starter Slingshot")
            chosenRanged[player] = "Starter Slingshot"
            if chosenInstanceId[player] then chosenInstanceId[player].Ranged = nil end
        end
    end
    print("[EquipLoad]", player.Name, "validated: melee=", chosenMelee[player] or "(default)", "ranged=", chosenRanged[player] or "(default)")
end

local function giveLoadout(player)
    print("[StarterEquip]", player.Name, "granting loadout: melee=", chosenMelee[player] or "(default)", "ranged=", chosenRanged[player] or "(default)")
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
registerLoadoutSection()

local function onPlayerAdded(player)
    print("[EquipLoad]", player.Name, "loading loadout...")
    -- load saved loadout choices before first spawn
    DataSaveCoordinator:LoadSection(player, "Loadout")

    -- Validate saved weapons still exist (falls back to starters if not)
    -- NOTE: validateLoadout calls playerOwnsWeapon which may need
    -- WeaponInstanceService data; CrateServiceInit loads it on PlayerAdded too.
    -- We defer validation slightly to let CrateServiceInit grant starters first.
    task.defer(function()
        task.wait(0.5)
        validateLoadout(player)
    end)

    -- check pass on join
    unlockState[player] = checkGamePass(player)

    local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
    if backpack then
        bindGripAlignmentInContainer(backpack)
        backpack.ChildAdded:Connect(function(child)
            bindGripAlignmentForTool(child)
        end)
    end

    -- tell the client the initial state
    pcall(function()
        specialUnlockGranted:FireClient(player, unlockState[player] == true)
    end)

    -- give tools every time the character spawns
    player.CharacterAdded:Connect(function(character)
        -- brief yield so the engine creates the fresh Backpack
        task.wait(0.2)
        giveLoadout(player)
        -- safety net: if the engine's StarterGear → Backpack copy was slow
        task.wait(0.5)
        ensureBackpackFromStarterGear(player)
        local currentBackpack = player:FindFirstChildOfClass("Backpack")
        bindGripAlignmentInContainer(currentBackpack)
        -- Notify client that loadout is ready (ensures hotbar refreshes after tools arrive)
        print("[ToolbarSync]", player.Name, "loadout granted, notifying client")
        pcall(function()
            local ids = chosenInstanceId[player]
            loadoutChangedRemote:FireClient(player, {
                melee  = chosenMelee[player] or "Starter Sword",
                ranged = chosenRanged[player] or "Starter Slingshot",
                meleeInstanceId  = ids and ids.Melee or nil,
                rangedInstanceId = ids and ids.Ranged or nil,
            })
        end)

        -- MENU-LOCK FAILSAFE: watch for tools parented to Character while menu is open
        local char = player.Character
        if char then
            syncPlayerWeaponCosmetics(player, char)
            bindGripAlignmentInContainer(char)
            char.ChildAdded:Connect(function(child)
                bindGripAlignmentForTool(child)
                if child:IsA("Tool") and isPlayerMenuLocked(player) then
                    print("[MenuLock-Server] Failsafe: unequipping", child.Name, "for", player.Name)
                    task.defer(function()
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then pcall(function() hum:UnequipTools() end) end
                    end)
                end
            end)
        end
    end)

    -- handle an already-spawned character (Studio fast-start)
    if player.Character then
        task.defer(function()
            task.wait(0.2)
            giveLoadout(player)
            task.wait(0.5)
            ensureBackpackFromStarterGear(player)
            local currentBackpack = player:FindFirstChildOfClass("Backpack")
            bindGripAlignmentInContainer(currentBackpack)
            bindGripAlignmentInContainer(player.Character)
            syncPlayerWeaponCosmetics(player, player.Character)
            -- Notify client that loadout is ready
            print("[ToolbarSync]", player.Name, "loadout granted (fast-start), notifying client")
            pcall(function()
                local ids = chosenInstanceId[player]
                loadoutChangedRemote:FireClient(player, {
                    melee  = chosenMelee[player] or "Starter Sword",
                    ranged = chosenRanged[player] or "Starter Slingshot",
                    meleeInstanceId  = ids and ids.Melee or nil,
                    rangedInstanceId = ids and ids.Ranged or nil,
                })
            end)
        end)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)

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
