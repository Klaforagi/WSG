local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local STALL_NAMES = {
    PotionsStall = true,
    PotionStall = true,
    ["Potion Stall"] = true,
    ["Potions Stall"] = true,
}

local PROMPT_NAME = "PotionsPrompt"
local REMOTE_NAME = "OpenPotionsMenu"

local connectedPromptParts = setmetatable({}, { __mode = "k" })
local setupCount = 0

local function ensureInstance(parent, className, name)
    local existing = parent:FindFirstChild(name)
    if existing and not existing:IsA(className) then
        existing:Destroy()
        existing = nil
    end
    if existing then
        return existing, false
    end

    local instance = Instance.new(className)
    instance.Name = name
    instance.Parent = parent
    return instance, true
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local potionsFolder = ensureInstance(remotesFolder, "Folder", "Potions")
local openMenuRE = ensureInstance(potionsFolder, "RemoteEvent", REMOTE_NAME)

local function isStallName(name)
    if STALL_NAMES[name] == true then
        return true
    end

    local lowerName = string.lower(tostring(name or ""))
    return string.find(lowerName, "potion", 1, true) ~= nil and string.find(lowerName, "stall", 1, true) ~= nil
end

local function isStallModel(instance)
    return instance and instance:IsA("Model") and isStallName(instance.Name)
end

local function findPromptPart(stallModel)
    local direct = stallModel:FindFirstChild("PromptPart")
    if direct and direct:IsA("BasePart") then
        return direct
    end

    for _, descendant in ipairs(stallModel:GetDescendants()) do
        if descendant.Name == "PromptPart" and descendant:IsA("BasePart") then
            return descendant
        end
    end

    return direct
end

local function configurePrompt(stallModel)
    if not isStallModel(stallModel) then
        return false
    end

    print("[PotionsStall] Found stall " .. stallModel:GetFullName())

    local promptPart = findPromptPart(stallModel)
    if not promptPart then
        warn("[PotionsStall] Could not find " .. stallModel:GetFullName() .. ".PromptPart; potions prompt not connected.")
        return false
    end
    if not promptPart:IsA("BasePart") then
        warn("[PotionsStall] Found " .. promptPart:GetFullName() .. " but it is " .. promptPart.ClassName .. ", not BasePart; potions prompt not connected.")
        return false
    end

    print("[PotionsStall] Found PromptPart " .. promptPart:GetFullName())

    local prompt = promptPart:FindFirstChild(PROMPT_NAME)
    local created = false
    if prompt and not prompt:IsA("ProximityPrompt") then
        prompt:Destroy()
        prompt = nil
    end

    if not prompt then
        for _, child in ipairs(promptPart:GetChildren()) do
            if child:IsA("ProximityPrompt") then
                prompt = child
                break
            end
        end
    end

    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Parent = promptPart
        created = true
    end

    prompt.Name = PROMPT_NAME
    prompt.ActionText = "Browse Potions"
    prompt.ObjectText = "Potions"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.Enabled = true
    prompt.Style = Enum.ProximityPromptStyle.Default

    print(string.format("[PotionsStall] %s ProximityPrompt %s", created and "Created" or "Reused", prompt:GetFullName()))

    if connectedPromptParts[promptPart] then
        return true
    end
    connectedPromptParts[promptPart] = true
    setupCount += 1

    prompt.Triggered:Connect(function(player)
        if not player then
            return
        end
        print("[PotionsStall] Prompt triggered by " .. player.Name)
        openMenuRE:FireClient(player)
        print("[PotionsStall] Sent " .. REMOTE_NAME .. " to " .. player.Name)
    end)

    return true
end

local function setupAllStalls()
    local found = 0
    local seen = {}

    for stallName in pairs(STALL_NAMES) do
        local direct = Workspace:FindFirstChild(stallName)
        if isStallModel(direct) and not seen[direct] then
            seen[direct] = true
            found += 1
            configurePrompt(direct)
        end
    end

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if isStallModel(descendant) and not seen[descendant] then
            seen[descendant] = true
            found += 1
            configurePrompt(descendant)
        end
    end

    return found
end

local initialFound = setupAllStalls()
if initialFound == 0 then
    warn("[PotionsStall] Could not find Workspace.PotionsStall or Workspace.PotionStall yet; waiting for stall to appear.")
end

Workspace.DescendantAdded:Connect(function(instance)
    if isStallModel(instance) then
        task.defer(function()
            configurePrompt(instance)
        end)
        return
    end

    if instance.Name == "PromptPart" and instance:IsA("BasePart") then
        task.defer(function()
            local ancestor = instance.Parent
            while ancestor and ancestor ~= Workspace do
                if isStallModel(ancestor) then
                    configurePrompt(ancestor)
                    return
                end
                ancestor = ancestor.Parent
            end
        end)
    end
end)

task.delay(10, function()
    if setupCount == 0 then
        warn("[PotionsStall] Could not find Workspace.PotionsStall.PromptPart; potions prompt not connected.")
    end
end)