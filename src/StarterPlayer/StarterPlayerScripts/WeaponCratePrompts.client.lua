local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CrateConfig = require(ReplicatedStorage:WaitForChild("CrateConfig"))

local CHEST_DEFS = {
    {
        modelName = "CommonChest",
        promptName = "CommonChestPrompt",
        crateId = "WeaponCrate",
    },
    {
        modelName = "GoldenChest",
        promptName = "GoldenChestPrompt",
        crateId = "PremiumWeaponCrate",
        openSoundName = "Key",
    },
}

CHEST_DEFS[1].openSoundName = "Buy"

local triggerDebounce = false
local promptEntries = {}
local warnedMissingOpenSounds = {}
local openCrateRemote = nil
local currencyCache = {
    Coins = 0,
    Keys = 0,
}
local currencyFetchAt = {
    Coins = 0,
    Keys = 0,
}
local CURRENCY_REFRESH_INTERVAL = 0.35

local function getOpenCrateRemote()
    if openCrateRemote and openCrateRemote.Parent then
        return openCrateRemote
    end

    local remote = ReplicatedStorage:FindFirstChild("OpenCrate")
    if remote and remote:IsA("RemoteFunction") then
        openCrateRemote = remote
        return openCrateRemote
    end

    return nil
end

local function ensureChild(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing
    end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance
end

local function isCrateRewardSequenceActive()
    local activeCheck = _G.IsCrateRewardSequenceActive
    if type(activeCheck) ~= "function" then
        return false
    end

    local ok, result = pcall(activeCheck)
    return ok and result == true
end

local function isSpinWheelRewardSequenceActive()
    local activeCheck = _G.IsSpinWheelRewardSequenceLocked
    if type(activeCheck) ~= "function" then
        return false
    end

    local ok, result = pcall(activeCheck)
    return ok and result == true
end

local function canUseChestPrompts()
    return (type(_G.OpenCrateRequested) == "function" or getOpenCrateRemote() ~= nil)
    and not isCrateRewardSequenceActive()
    and not isSpinWheelRewardSequenceActive()
end

local function getCurrencyAmount(apiGetterName, remoteName, allowRemoteFallback)
    local coinApi = _G.CrateOpeningCoinApi
    if coinApi and type(coinApi[apiGetterName]) == "function" then
        local ok, amount = pcall(function()
            return coinApi[apiGetterName]()
        end)
        if ok and type(amount) == "number" then
            local normalized = math.max(0, math.floor(amount))
            currencyCache[remoteName == "GetKeys" and "Keys" or "Coins"] = normalized
            return normalized
        end
    end

    -- Local fallback from player attributes (set by currency systems in most flows).
    local attrName = (remoteName == "GetKeys") and "Keys" or "Coins"
    local attrAmount = tonumber(player:GetAttribute(attrName))
    if attrAmount then
        local normalized = math.max(0, math.floor(attrAmount))
        currencyCache[attrName] = normalized
        return normalized
    end

    if allowRemoteFallback == false then
        return currencyCache[attrName] or 0
    end

    local now = os.clock()
    if now - (currencyFetchAt[attrName] or 0) < CURRENCY_REFRESH_INTERVAL then
        return currencyCache[attrName] or 0
    end

    local remote = ReplicatedStorage:FindFirstChild(remoteName)
    if remote and remote:IsA("RemoteFunction") then
        currencyFetchAt[attrName] = now
        local ok, amount = pcall(function()
            return remote:InvokeServer()
        end)
        if ok and type(amount) == "number" then
            local normalized = math.max(0, math.floor(amount))
            currencyCache[attrName] = normalized
            return normalized
        end
    end

    return currencyCache[attrName] or 0
end

local function getCoins(allowRemoteFallback)
    return getCurrencyAmount("GetCoins", "GetCoins", allowRemoteFallback)
end

local function getKeys(allowRemoteFallback)
    return getCurrencyAmount("GetKeys", "GetKeys", allowRemoteFallback)
end

local function getPromptCurrencyText(currencyType)
    local coinApi = _G.CrateOpeningCoinApi
    local canReadApiKeys = coinApi and type(coinApi.GetKeys) == "function"
    local canReadApiCoins = coinApi and type(coinApi.GetCoins) == "function"

    if currencyType == "Keys" then
        return string.format("Keys: %d", getKeys(not canReadApiKeys))
    end

    return string.format("Coins: %d", getCoins(not canReadApiCoins))
end

local function openKeysShop()
    local sideUI = _G.SideUI
    if sideUI and type(sideUI.OpenShopSection) == "function" then
        sideUI.OpenShopSection("keys")
    end
end

local function findOpenSoundTemplate(soundName)
    if type(soundName) ~= "string" or soundName == "" then
        return nil
    end

    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then
        return nil
    end

    local direct = soundsFolder:FindFirstChild(soundName)
    if direct and direct:IsA("Sound") then
        return direct
    end

    local uiFolder = soundsFolder:FindFirstChild("UI")
    if uiFolder then
        local nested = uiFolder:FindFirstChild(soundName)
        if nested and nested:IsA("Sound") then
            return nested
        end
    end

    return nil
end

local function playOpenSound(soundName)
    local template = findOpenSoundTemplate(soundName)
    if not template then
        if not warnedMissingOpenSounds[soundName] then
            warnedMissingOpenSounds[soundName] = true
            warn(string.format("[WeaponCratePrompts] Sound '%s' not found in ReplicatedStorage.Sounds", tostring(soundName)))
        end
        return false
    end

    local clone = template:Clone()
    clone.Parent = SoundService
    clone:Play()
    task.delay(math.max(1, (clone.TimeLength or 1) + 0.25), function()
        if clone and clone.Parent then
            pcall(function()
                clone:Destroy()
            end)
        end
    end)
    return true
end

local function requestOpenCrate(crateId)
    if type(_G.OpenCrateRequested) == "function" then
        pcall(function()
            _G.OpenCrateRequested(crateId)
        end)
        return
    end

    local remote = getOpenCrateRemote()
    if not remote then
        warn("[WeaponCratePrompts] OpenCrate remote unavailable")
        return
    end

    task.spawn(function()
        local ok, success, result = pcall(function()
            return remote:InvokeServer(crateId)
        end)

        if not ok then
            warn("[WeaponCratePrompts] OpenCrate invoke failed:", tostring(success))
            return
        end

        if not success then
            warn("[WeaponCratePrompts] OpenCrate rejected:", tostring(result))
            return
        end

        if type(result) ~= "table" then
            return
        end

        -- If SideUI globals are not initialized yet, drive the same roulette
        -- animation directly so chest opens still feel responsive on mobile.
        if type(_G.PlayCrateAnimation) == "function" then
            pcall(function()
                _G.PlayCrateAnimation(result.crateType or crateId, result)
            end)
            return
        end

        local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
        local mod = sideUI and sideUI:FindFirstChild("CrateOpeningUI")
        if mod and mod:IsA("ModuleScript") then
            local requireOk, crateUi = pcall(require, mod)
            if requireOk and type(crateUi) == "table" then
                pcall(function()
                    if type(crateUi.Init) == "function" then
                        crateUi.Init(playerGui)
                    end
                    if type(crateUi.Play) == "function" then
                        crateUi.Play(result.crateType or crateId, result, _G.CrateOpeningCoinApi)
                    end
                end)
            end
        end
    end)
end


for _, chestInfo in ipairs(CHEST_DEFS) do
    local model = Workspace:WaitForChild(chestInfo.modelName, 30)
    if not (model and model:IsA("Model")) then
        warn("[WeaponCratePrompts] Missing chest model", chestInfo.modelName)
        continue
    end

    local promptPart = model:WaitForChild("PromptPart", 30)
    if not (promptPart and promptPart:IsA("BasePart")) then
        warn("[WeaponCratePrompts] Missing PromptPart for", chestInfo.modelName)
        continue
    end

    local crateDef = CrateConfig.Crates[chestInfo.crateId]
    if not crateDef then
        warn("[WeaponCratePrompts] Missing crate definition", chestInfo.crateId)
        continue
    end

    local currencyType = tostring(crateDef.currency or "Coins")
    local price = math.max(0, math.floor(tonumber(crateDef.cost or crateDef.price) or 0))

    local prompt = ensureChild(promptPart, "ProximityPrompt", chestInfo.promptName)
    prompt.ActionText = "Open"
    prompt.ObjectText = getPromptCurrencyText(currencyType)
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.Style = Enum.ProximityPromptStyle.Default
    prompt.Enabled = false

    table.insert(promptEntries, {
        prompt = prompt,
        currencyType = currencyType,
    })

    prompt.Triggered:Connect(function()
        if triggerDebounce or not canUseChestPrompts() then
            return
        end

        triggerDebounce = true

        if currencyType == "Keys" then
            if getKeys(true) < price then
                openKeysShop()
                task.delay(0.2, function()
                    triggerDebounce = false
                end)
                return
            end
        else
            if getCoins(true) < price then
                task.delay(0.2, function()
                    triggerDebounce = false
                end)
                return
            end
        end

        playOpenSound(chestInfo.openSoundName)
        requestOpenCrate(chestInfo.crateId)

        task.delay(1.05, function()
            triggerDebounce = false
        end)
    end)
end

RunService.Heartbeat:Connect(function()
    local enabled = canUseChestPrompts()
    for _, entry in ipairs(promptEntries) do
        local prompt = entry.prompt
        if prompt and prompt.Parent then
            prompt.ActionText = "Open"
            prompt.ObjectText = getPromptCurrencyText(entry.currencyType)
            prompt.Enabled = enabled
        end
    end
end)
