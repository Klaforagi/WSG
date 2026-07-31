--------------------------------------------------------------------------------
-- GamepassService.lua
-- Tracks permanent Robux gamepass ownership, exposes additive reward bonuses,
-- and mirrors ownership into player attributes for UI/chat use.
--------------------------------------------------------------------------------

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("ShopCatalog"))

local GamepassService = {}

local initialized = false
local playerState = {}

local function getState(player)
    if not player then
        return nil
    end
    local state = playerState[player]
    if not state then
        state = {
            owned = {},
            coinBonus = 0,
            xpBonus = 0,
            masteryBonus = 0,
            chatPrefix = "",
            lucky = false,
        }
        playerState[player] = state
    end
    return state
end

local function safeSetAttribute(player, name, value)
    if not player then
        return
    end
    pcall(function()
        player:SetAttribute(name, value)
    end)
end

local function applyStateAttributes(player, state)
    safeSetAttribute(player, "ShopCoinBonus", state.coinBonus or 0)
    safeSetAttribute(player, "ShopXPBonus", state.xpBonus or 0)
    safeSetAttribute(player, "ShopMasteryBonus", state.masteryBonus or 0)
    safeSetAttribute(player, "ShopChatPrefix", state.chatPrefix or "")
    safeSetAttribute(player, "ShopLuckyOwned", state.lucky == true)

    for _, item in ipairs(ShopCatalog.GetGamepassItems()) do
        local ownedAttr = item.OwnedAttribute or ("Shop" .. item.Id .. "Owned")
        safeSetAttribute(player, ownedAttr, state.owned[item.Id] == true)
    end
end

local function recomputeState(player)
    if not player or not player:IsA("Player") then
        return nil
    end

    local state = getState(player)
    state.owned = {}
    state.coinBonus = 0
    state.xpBonus = 0
    state.masteryBonus = 0
    state.chatPrefix = ""
    state.lucky = false

    local prefixes = {}
    for _, item in ipairs(ShopCatalog.GetGamepassItems()) do
        local passId = math.floor(tonumber(item.GamePassId) or 0)
        local owns = false
        if passId > 0 then
            local ok, result = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
            end)
            owns = ok and result == true
        end

        if not owns and RunService:IsStudio() then
            local studioAttr = "StudioShopTestOwned_" .. tostring(item.Id)
            owns = player:GetAttribute(studioAttr) == true
        end

        state.owned[item.Id] = owns
        if owns then
            local bonus = item.Bonus or {}
            state.coinBonus = state.coinBonus + math.max(0, tonumber(bonus.Coins) or 0)
            state.xpBonus = state.xpBonus + math.max(0, tonumber(bonus.XP) or 0)
            state.masteryBonus = state.masteryBonus + math.max(0, tonumber(bonus.Mastery) or 0)
            if type(item.ChatPrefix) == "string" and item.ChatPrefix ~= "" then
                table.insert(prefixes, item.ChatPrefix)
            end
            if type(item.LuckyWeights) == "table" then
                state.lucky = true
            end
        end
    end

    state.chatPrefix = table.concat(prefixes, " ")
    applyStateAttributes(player, state)
    return state
end

local function clearState(player)
    local state = playerState[player]
    if not state then
        return
    end
    playerState[player] = nil
    applyStateAttributes(player, {
        owned = {},
        coinBonus = 0,
        xpBonus = 0,
        masteryBonus = 0,
        chatPrefix = "",
        lucky = false,
    })
end

function GamepassService:Init()
    if initialized then
        return
    end
    initialized = true

    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            recomputeState(player)
        end)
    end)

    Players.PlayerRemoving:Connect(function(player)
        clearState(player)
    end)

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
        if not purchased then
            return
        end
        if not player or not player.Parent then
            return
        end
        local targetPassId = math.floor(tonumber(passId) or 0)
        if targetPassId <= 0 then
            return
        end
        task.spawn(function()
            recomputeState(player)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            recomputeState(player)
        end)
    end
end

function GamepassService:RefreshPlayer(player)
    return recomputeState(player)
end

function GamepassService:LoadForPlayer(player)
    return recomputeState(player) ~= nil
end

function GamepassService:ClearPlayer(player)
    clearState(player)
end

function GamepassService:SetStudioTestOwnership(player, itemId, owned)
    if not player or type(itemId) ~= "string" or itemId == "" then
        return false, "invalid itemId"
    end

    pcall(function()
        player:SetAttribute("StudioShopTestOwned_" .. itemId, owned == true and true or nil)
    end)

    return self:RefreshPlayer(player)
end

function GamepassService:ClearStudioTestOwnership(player)
    if not player then
        return false, "missing player"
    end

    for _, item in ipairs(ShopCatalog.GetGamepassItems()) do
        pcall(function()
            player:SetAttribute("StudioShopTestOwned_" .. tostring(item.Id), nil)
        end)
    end

    return self:RefreshPlayer(player)
end

function GamepassService:GetState(player)
    return getState(player)
end

function GamepassService:IsOwned(player, itemId)
    local state = getState(player)
    if not state or type(itemId) ~= "string" then
        return false
    end
    return state.owned[itemId] == true
end

function GamepassService:GetCoinBonus(player)
    local state = getState(player)
    return state and state.coinBonus or 0
end

function GamepassService:GetXPBonus(player)
    local state = getState(player)
    return state and state.xpBonus or 0
end

function GamepassService:GetMasteryBonus(player)
    local state = getState(player)
    return state and state.masteryBonus or 0
end

function GamepassService:GetChatPrefix(player)
    local state = getState(player)
    return state and state.chatPrefix or ""
end

function GamepassService:HasLuckyGamepass(player)
    local state = getState(player)
    return state and state.lucky == true
end

function GamepassService:GetLuckyRarityWeights(player, crateId)
    if not self:HasLuckyGamepass(player) then
        return nil
    end

    local luckyItem = ShopCatalog.GetById("lucky_gamepass")
    if not luckyItem then
        return nil
    end

    if type(crateId) ~= "string" or crateId ~= luckyItem.LuckyCrateId then
        return nil
    end

    local weights = luckyItem.LuckyWeights
    if type(weights) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(weights) do
        copy[key] = value
    end
    return copy
end

return GamepassService