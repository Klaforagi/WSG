--------------------------------------------------------------------------------
-- SalvageShopService.server.lua
-- Server-side purchase validation and reward granting for the Salvage Shop.
-- All prices and rewards are determined server-side from SalvageShopConfig.
--------------------------------------------------------------------------------

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- DEPENDENCIES (lazy-loaded)
--------------------------------------------------------------------------------
local _CurrencyService, _SalvageShopConfig, _WeaponInstanceService, _CrateConfig

local function getCurrencyService()
    if not _CurrencyService then
        local mod = ServerScriptService:FindFirstChild("CurrencyService")
        if mod and mod:IsA("ModuleScript") then _CurrencyService = require(mod) end
    end
    return _CurrencyService
end

local function getSalvageShopConfig()
    if not _SalvageShopConfig then
        local mod = ReplicatedStorage:FindFirstChild("SalvageShopConfig")
        if mod and mod:IsA("ModuleScript") then _SalvageShopConfig = require(mod) end
    end
    return _SalvageShopConfig
end

local function getWeaponInstanceService()
    if not _WeaponInstanceService then
        local mod = ServerScriptService:FindFirstChild("WeaponInstanceService")
        if mod and mod:IsA("ModuleScript") then _WeaponInstanceService = require(mod) end
    end
    return _WeaponInstanceService
end

local function getCrateConfig()
    if not _CrateConfig then
        local mod = ReplicatedStorage:FindFirstChild("CrateConfig")
        if mod and mod:IsA("ModuleScript") then _CrateConfig = require(mod) end
    end
    return _CrateConfig
end

--------------------------------------------------------------------------------
-- OWNERSHIP TRACKING  (for unique items: skins, effects)
-- Uses DataStores managed by SkinService / EffectsService via their data tables.
-- We query ownership via server-side modules rather than duplicating stores.
--------------------------------------------------------------------------------

-- Check if player already owns a specific salvage-shop reward
local function playerOwnsReward(player, shopItem)
    if not shopItem.Unique then return false end

    if shopItem.RewardType == "Skin" then
        -- Query SkinService data
        local skinSvc = ServerScriptService:FindFirstChild("SkinService.server")
            or ServerScriptService:FindFirstChild("SkinService")
        if skinSvc then
            -- SkinService uses a script, ownership stored in its internal table.
            -- We check via a BindableFunction if it exists.
            local bf = ServerScriptService:FindFirstChild("CheckSkinOwnership")
            if bf and bf:IsA("BindableFunction") then
                local ok, result = pcall(function() return bf:Invoke(player, shopItem.RewardId) end)
                if ok then return result == true end
            end
        end
        return false
    end

    if shopItem.RewardType == "Effect" then
        local bf = ServerScriptService:FindFirstChild("CheckEffectOwnership")
        if bf and bf:IsA("BindableFunction") then
            local ok, result = pcall(function() return bf:Invoke(player, shopItem.RewardId) end)
            if ok then return result == true end
        end
        return false
    end

    return false
end

-- Grant the reward for a salvage shop purchase
local function grantReward(player, shopItem)
    if shopItem.RewardType == "Skin" then
        local bf = ServerScriptService:FindFirstChild("GrantSkin")
        if bf and bf:IsA("BindableFunction") then
            local ok, result = pcall(function() return bf:Invoke(player, shopItem.RewardId) end)
            if ok and result then return true end
        end
        -- Fallback: log and succeed (skin will need manual claim if BindableFunction missing)
        warn("[SalvageShopService] GrantSkin BindableFunction not found for:", shopItem.RewardId)
        return true

    elseif shopItem.RewardType == "Effect" then
        local bf = ServerScriptService:FindFirstChild("GrantEffect")
        if bf and bf:IsA("BindableFunction") then
            local ok, result = pcall(function() return bf:Invoke(player, shopItem.RewardId) end)
            if ok and result then return true end
        end
        warn("[SalvageShopService] GrantEffect BindableFunction not found for:", shopItem.RewardId)
        return true

    elseif shopItem.RewardType == "Crate" then
        -- Grant a crate opening (spawn a random weapon from the crate pool)
        local wis = getWeaponInstanceService()
        local cc = getCrateConfig()
        if not wis or not cc then
            warn("[SalvageShopService] WeaponInstanceService or CrateConfig unavailable")
            return false
        end

        local crateDef = cc.Crates and cc.Crates[shopItem.RewardId]
        if not crateDef then
            warn("[SalvageShopService] Crate not found in CrateConfig:", shopItem.RewardId)
            return false
        end

        -- Roll a random weapon from the crate pool (same logic as CrateService)
        local weaponName, rarity = nil, nil
        if cc.RollCrate then
            weaponName, rarity = cc.RollCrate(shopItem.RewardId)
        else
            -- Manual roll if RollCrate doesn't exist
            local pool = crateDef.pool or {}
            if #pool > 0 then
                local totalWeight = 0
                for _, entry in ipairs(pool) do totalWeight = totalWeight + (entry.weight or 1) end
                local roll = math.random() * totalWeight
                local cumulative = 0
                for _, entry in ipairs(pool) do
                    cumulative = cumulative + (entry.weight or 1)
                    if roll <= cumulative then
                        weaponName = entry.weapon
                        rarity = entry.rarity
                        break
                    end
                end
            end
        end

        if not weaponName then
            warn("[SalvageShopService] Failed to roll weapon from crate:", shopItem.RewardId)
            return false
        end

        -- Add the weapon to the player's inventory
        local category = "Ranged"
        if cc.WeaponsByRarity then
            for r, weapons in pairs(cc.WeaponsByRarity) do
                for _, w in ipairs(weapons) do
                    if w.weapon == weaponName then
                        category = w.category or "Ranged"
                    end
                end
            end
        end

        local instanceId = wis:AddInstance(player, {
            weaponName = weaponName,
            category = category,
            rarity = rarity or "Common",
            source = "SalvageShop",
        })

        if instanceId then
            wis:SaveForPlayer(player)
            -- Notify client of inventory change
            local weaponInvUpdated = ReplicatedStorage:FindFirstChild("WeaponInventoryUpdated")
            if weaponInvUpdated and weaponInvUpdated:IsA("RemoteEvent") then
                pcall(function()
                    weaponInvUpdated:FireClient(player, wis:GetInventory(player))
                end)
            end
            return true, { weaponName = weaponName, rarity = rarity }
        end
        return false
    end

    return false
end

--------------------------------------------------------------------------------
-- REMOTE CREATION
--------------------------------------------------------------------------------
local function getOrCreateRF(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then return existing end
    if existing then existing:Destroy() end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = ReplicatedStorage
    return rf
end

local function getOrCreateRE(name)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then return existing end
    if existing then existing:Destroy() end
    local re = Instance.new("RemoteEvent")
    re.Name = name
    re.Parent = ReplicatedStorage
    return re
end

local purchaseSalvageItemRF = getOrCreateRF("PurchaseSalvageItem")
local getSalvageShopOwnershipRF = getOrCreateRF("GetSalvageShopOwnership")

--------------------------------------------------------------------------------
-- DEBOUNCE  (prevent purchase spam / race conditions)
--------------------------------------------------------------------------------
local purchaseDebounce = {} -- [Player] = tick

--------------------------------------------------------------------------------
-- PURCHASE HANDLER
--------------------------------------------------------------------------------
purchaseSalvageItemRF.OnServerInvoke = function(player, itemId)
    -- Type validation
    if type(itemId) ~= "string" then
        return false, { reason = "Invalid item ID" }
    end

    -- Anti-spam debounce (1 second per player)
    local now = tick()
    if purchaseDebounce[player] and (now - purchaseDebounce[player]) < 1.0 then
        return false, { reason = "Too fast" }
    end
    purchaseDebounce[player] = now

    -- Look up item in config (server-authoritative price)
    local config = getSalvageShopConfig()
    if not config then
        return false, { reason = "Shop config unavailable" }
    end

    local shopItem = config.GetById(itemId)
    if not shopItem then
        print("[SalvageShopService] DENIED:", player.Name, "- item not found:", itemId)
        return false, { reason = "Item not found" }
    end

    if not shopItem.Enabled then
        print("[SalvageShopService] DENIED:", player.Name, "- item disabled:", itemId)
        return false, { reason = "Item not available" }
    end

    -- Check duplicate ownership for unique items
    if shopItem.Unique and playerOwnsReward(player, shopItem) then
        print("[SalvageShopService] DENIED:", player.Name, "- already owns:", itemId)
        return false, { reason = "Already owned" }
    end

    -- Verify sufficient Salvage balance (server-authoritative)
    local cs = getCurrencyService()
    if not cs then
        return false, { reason = "Currency service unavailable" }
    end

    local price = shopItem.SalvagePrice
    if not cs:HasEnoughSalvage(player, price) then
        local bal = cs:GetSalvage(player)
        print("[SalvageShopService] DENIED:", player.Name, "- insufficient salvage. Has:", bal, "Needs:", price)
        return false, { reason = "Not enough Salvage" }
    end

    -- Deduct Salvage FIRST (before granting reward to prevent exploit)
    cs:RemoveSalvage(player, price)

    -- Grant reward
    local granted, rewardData = grantReward(player, shopItem)
    if not granted then
        -- Refund salvage on grant failure
        cs:AddSalvage(player, price)
        print("[SalvageShopService] FAILED:", player.Name, "- reward grant failed for:", itemId, "- refunded")
        return false, { reason = "Failed to grant reward" }
    end

    local newBalance = cs:GetSalvage(player)
    print("[SalvageShopService] SUCCESS:", player.Name, "purchased", shopItem.DisplayName,
        "for", price, "salvage. New balance:", newBalance)

    return true, {
        itemId = itemId,
        displayName = shopItem.DisplayName,
        newBalance = newBalance,
        rewardData = rewardData,
    }
end

--------------------------------------------------------------------------------
-- OWNERSHIP QUERY (client asks which salvage shop items are already owned)
--------------------------------------------------------------------------------
getSalvageShopOwnershipRF.OnServerInvoke = function(player)
    local config = getSalvageShopConfig()
    if not config then return {} end

    local owned = {}
    for _, item in ipairs(config.Items) do
        if item.Unique and item.Enabled then
            if playerOwnsReward(player, item) then
                owned[item.Id] = true
            end
        end
    end
    return owned
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    purchaseDebounce[player] = nil
end)

print("[SalvageShopService] Salvage Shop service ready")
