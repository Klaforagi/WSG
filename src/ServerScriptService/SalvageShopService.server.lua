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
local _CurrencyService, _SalvageShopConfig, _WeaponInstanceService, _CrateConfig, _AchievementService, _CrateService

local function getCrateService()
    if not _CrateService then
        local mod = ServerScriptService:FindFirstChild("CrateService")
        if mod and mod:IsA("ModuleScript") then _CrateService = require(mod) end
    end
    return _CrateService
end

local function getAchievementService()
    if not _AchievementService then
        local mod = ServerScriptService:FindFirstChild("AchievementService")
        if mod and mod:IsA("ModuleScript") then _AchievementService = require(mod) end
    end
    return _AchievementService
end

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
        -- Route into the CrateService pending-reward pipeline so the player
        -- gets the same Keep/Salvage decision popup as gold crates.
        local cs = getCrateService()
        if not cs then
            warn("[SalvageShopService] CrateService unavailable")
            return false
        end

        print("[SalvageCrate] Routing into pending crate flow:", shopItem.RewardId)
        local ok, result = cs:RollAndPend(player, shopItem.RewardId)
        if not ok then
            warn("[SalvageCrate] RollAndPend failed:", tostring(result))
            return false
        end

        -- Do NOT fire WeaponInventoryUpdated here — weapon is pending until
        -- the player chooses Keep or Salvage in the shared decision popup.

        print("[SalvageCrate] Pending reward created:", result.weaponName, "(" .. result.rarity .. ")")
        return true, {
            weaponName   = result.weaponName,
            rarity       = result.rarity,
            sizePercent  = result.sizePercent,
            sizeTier     = result.sizeTier,
            salvageValue = result.salvageValue,
            isPending    = result.isPending,
            crateType    = result.crateType,
        }
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

    -- Track purchase for achievements
    local achSvc = getAchievementService()
    if achSvc then
        pcall(function() achSvc:IncrementStat(player, "totalPurchases", 1) end)
    end

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
