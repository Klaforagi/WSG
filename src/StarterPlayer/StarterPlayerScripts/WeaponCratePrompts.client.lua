local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CrateConfig = require(ReplicatedStorage:WaitForChild("CrateConfig"))
local KeyProducts = require(ReplicatedStorage:WaitForChild("KeyProducts"))
local RobuxPurchaseUI = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RobuxPurchaseUI"))

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

local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "WeaponChestPromptGui"
overlayGui.ResetOnSpawn = false
overlayGui.IgnoreGuiInset = true
overlayGui.DisplayOrder = 450
overlayGui.Parent = playerGui

local modalShade = Instance.new("Frame")
modalShade.Name = "PurchaseShade"
modalShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
modalShade.BackgroundTransparency = 0.3
modalShade.BorderSizePixel = 0
modalShade.Size = UDim2.fromScale(1, 1)
modalShade.Visible = false
modalShade.Parent = overlayGui

local modalCard = Instance.new("Frame")
modalCard.Name = "PurchaseCard"
modalCard.AnchorPoint = Vector2.new(0.5, 0.5)
modalCard.Position = UDim2.fromScale(0.5, 0.5)
modalCard.Size = UDim2.new(0, 430, 0, 390)
modalCard.Parent = modalShade
RobuxPurchaseUI.StyleModalCard(modalCard, RobuxPurchaseUI.Colors.Black)

local modalHeader = Instance.new("TextLabel")
modalHeader.Name = "Header"
modalHeader.BackgroundTransparency = 1
modalHeader.Size = UDim2.new(1, -30, 0, 56)
modalHeader.Position = UDim2.new(0, 15, 0, 18)
modalHeader.Font = Enum.Font.GothamBlack
modalHeader.TextSize = 30
modalHeader.Text = "BUY KEYS"
modalHeader.Parent = modalCard
RobuxPurchaseUI.ApplyOutlinedText(modalHeader, RobuxPurchaseUI.Colors.Gold)

local modalBody = Instance.new("TextLabel")
modalBody.Name = "Body"
modalBody.BackgroundTransparency = 1
modalBody.Size = UDim2.new(1, -30, 0, 64)
modalBody.Position = UDim2.new(0, 15, 0, 68)
modalBody.Font = Enum.Font.GothamMedium
modalBody.TextSize = 20
modalBody.TextWrapped = true
modalBody.Text = "You're out of keys. Pick a pack below to open the Premium Weapon Crate."
modalBody.Parent = modalCard
RobuxPurchaseUI.ApplyOutlinedText(modalBody, RobuxPurchaseUI.Colors.GoldSoft)

local buttonList = Instance.new("Frame")
buttonList.Name = "ButtonList"
buttonList.BackgroundTransparency = 1
buttonList.Size = UDim2.new(1, -30, 0, 188)
buttonList.Position = UDim2.new(0, 15, 0, 138)
buttonList.Parent = modalCard

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Vertical
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Top
buttonLayout.Padding = UDim.new(0, 8)
buttonLayout.Parent = buttonList

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.Size = UDim2.new(1, -30, 0, 44)
cancelButton.Position = UDim2.new(0, 15, 1, -58)
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 18
cancelButton.Text = "Not now"
cancelButton.Parent = modalCard
RobuxPurchaseUI.StyleCancelButton(cancelButton)

local purchaseModalOpen = false
local triggerDebounce = false
local promptEntries = {}
local warnedMissingOpenSounds = {}

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

local function canUseChestPrompts()
    return type(_G.OpenCrateRequested) == "function" and not purchaseModalOpen and not isCrateRewardSequenceActive()
end

local function getCurrencyAmount(apiGetterName, remoteName, allowRemoteFallback)
    local coinApi = _G.CrateOpeningCoinApi
    if coinApi and type(coinApi[apiGetterName]) == "function" then
        local ok, amount = pcall(function()
            return coinApi[apiGetterName]()
        end)
        if ok and type(amount) == "number" then
            return math.max(0, math.floor(amount))
        end
    end

    if allowRemoteFallback == false then
        return 0
    end

    local remote = ReplicatedStorage:FindFirstChild(remoteName)
    if remote and remote:IsA("RemoteFunction") then
        local ok, amount = pcall(function()
            return remote:InvokeServer()
        end)
        if ok and type(amount) == "number" then
            return math.max(0, math.floor(amount))
        end
    end

    return 0
end

local function getCoins(allowRemoteFallback)
    return getCurrencyAmount("GetCoins", "GetCoins", allowRemoteFallback)
end

local function getKeys(allowRemoteFallback)
    return getCurrencyAmount("GetKeys", "GetKeys", allowRemoteFallback)
end

local function getPromptCurrencyText(currencyType)
    if currencyType == "Keys" then
        return string.format("Keys: %d", getKeys(false))
    end

    return string.format("Coins: %d", getCoins(false))
end

local function closePurchaseModal()
    purchaseModalOpen = false
    modalShade.Visible = false
end

local function openPurchaseModal()
    purchaseModalOpen = true
    modalShade.Visible = true
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
    if type(_G.OpenCrateRequested) ~= "function" then
        return
    end
    pcall(function()
        _G.OpenCrateRequested(crateId)
    end)
end

cancelButton.MouseButton1Click:Connect(function()
    closePurchaseModal()
end)

for index, pack in ipairs(KeyProducts.Packs or {}) do
    local packTitle = string.format("%d %s", pack.Keys, (pack.Keys == 1) and "KEY" or "KEYS")
    local button = RobuxPurchaseUI.CreatePackCard(buttonList, {
        name = "PackButton" .. tostring(index),
        title = packTitle,
        subtitle = pack.Name,
        price = pack.Price,
        layoutOrder = index,
    })

    button.MouseButton1Click:Connect(function()
        local productId = pack.ProductId
        if not productId or productId <= 0 then
            warn("[WeaponCratePrompts] Product ID not set for", tostring(pack.Name))
            return
        end

        closePurchaseModal()

        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, productId)
        end)
        if not ok then
            warn("[WeaponCratePrompts] PromptProductPurchase failed:", tostring(err))
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
                openPurchaseModal()
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