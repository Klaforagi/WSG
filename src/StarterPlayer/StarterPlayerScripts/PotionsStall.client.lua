local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local STALL_NAMES = {
	"PotionsStall",
	"PotionStall",
	"Potion Stall",
	"Potions Stall",
	"PotionShop",
	"PotionsShop",
	"Potion Shop",
	"Potions Shop",
	"PotionStand",
	"PotionsStand",
	"Potion Stand",
	"Potions Stand",
	"PotionVendor",
	"PotionsVendor",
	"PotionBooth",
	"PotionsBooth",
	"Potion Booth",
	"Potions Booth",
	"Potion",
	"Potions",
}

local STALL_NAME_KEYWORDS = {
	"stall",
	"shop",
	"stand",
	"vendor",
	"booth",
}

local function isStallName(name)
	for _, stallName in ipairs(STALL_NAMES) do
		if name == stallName then
			return true
		end
	end

	local lowerName = string.lower(tostring(name or ""))
	if string.find(lowerName, "potion", 1, true) == nil then
		return false
	end

	for _, keyword in ipairs(STALL_NAME_KEYWORDS) do
		if string.find(lowerName, keyword, 1, true) ~= nil then
			return true
		end
	end

	return false
end

local function containsPotionText(instance)
	local name = string.lower(tostring(instance and instance.Name or ""))
	if string.find(name, "potion", 1, true) ~= nil then
		return true
	end

	if instance and instance:IsA("ProximityPrompt") then
		local actionText = string.lower(tostring(instance.ActionText or ""))
		local objectText = string.lower(tostring(instance.ObjectText or ""))
		return string.find(actionText, "potion", 1, true) ~= nil
			or string.find(objectText, "potion", 1, true) ~= nil
	end

	return false
end

local function hasPotionStallAncestor(instance)
	local current = instance
	while current and current ~= Workspace do
		if isStallName(current.Name) then
			return true
		end
		current = current.Parent
	end
	return false
end

local modulesFolder = ReplicatedStorage:WaitForChild("Modules", 15)
if not modulesFolder then
	warn("[PotionsStall] Modules folder not found")
	return
end

local stallModule = modulesFolder:WaitForChild("PotionsStallUI", 15)
if not (stallModule and stallModule:IsA("ModuleScript")) then
	warn("[PotionsStall] PotionsStallUI module not found")
	return
end

local PotionsStallUI = require(stallModule)

local function findStallModel()
	for _, stallName in ipairs(STALL_NAMES) do
		local direct = Workspace:FindFirstChild(stallName)
		if direct and (direct:IsA("Model") or direct:IsA("Folder")) then
			return direct
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if (descendant:IsA("Model") or descendant:IsA("Folder")) and isStallName(descendant.Name) then
			return descendant
		end
	end

	return nil
end

local function findPromptPartUnder(root)
	if not root then
		return nil
	end

	local direct = root:FindFirstChild("PromptPart")
	if direct and direct:IsA("BasePart") then
		return direct
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == "PromptPart" and descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function findPromptPartFromPrompt()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and containsPotionText(descendant) then
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") then
				return parent
			end
		end
	end

	return nil
end

local function findPromptPartInWorkspace()
	local foundStallModel = findStallModel()
	local foundPromptPart = findPromptPartUnder(foundStallModel)
	if foundPromptPart then
		return foundPromptPart, foundStallModel
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant.Name == "PromptPart" and descendant:IsA("BasePart") and hasPotionStallAncestor(descendant) then
			return descendant, descendant:FindFirstAncestorWhichIsA("Model") or descendant.Parent
		end
	end

	foundPromptPart = findPromptPartFromPrompt()
	if foundPromptPart then
		return foundPromptPart, foundPromptPart:FindFirstAncestorWhichIsA("Model") or foundPromptPart.Parent
	end

	return nil, foundStallModel
end

local function disablePromptsUnder(root)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
end

local promptPart = nil
local stallModel = nil
local lastPromptSearchAt = 0
local foundPromptLogged = false
local promptMissingWarned = false
local scriptStartTime = os.clock()

local function resolvePromptPart()
	if promptPart and promptPart.Parent then
		return promptPart
	end

	local now = os.clock()
	if now - lastPromptSearchAt < 0.5 then
		return nil
	end
	lastPromptSearchAt = now

	local foundPromptPart, foundStallModel = findPromptPartInWorkspace()
	if foundPromptPart and foundPromptPart:IsA("BasePart") then
		promptPart = foundPromptPart
		stallModel = foundStallModel
		disablePromptsUnder(stallModel or promptPart)

		if not foundPromptLogged then
			foundPromptLogged = true
			print(string.format(
				"[PotionStall] Found PromptPart for automatic open: %s (CanTouch=%s, CanQuery=%s)",
				promptPart:GetFullName(),
				tostring(promptPart.CanTouch),
				tostring(promptPart.CanQuery)
			))
		end

		return promptPart
	end

	if not promptMissingWarned and now - scriptStartTime >= 10 then
		promptMissingWarned = true
		warn("[PotionStall] PromptPart not found; automatic open disabled")
	end

	return nil
end

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") and (containsPotionText(descendant) or hasPotionStallAncestor(descendant)) then
		descendant.Enabled = false
	end

	if descendant.Name == "PromptPart" and descendant:IsA("BasePart") and hasPotionStallAncestor(descendant) then
		promptPart = nil
		lastPromptSearchAt = 0
	end
end)

local screenGui = playerGui:FindFirstChild("PotionsStallGui")
if screenGui and not screenGui:IsA("ScreenGui") then
	screenGui:Destroy()
	screenGui = nil
end

if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PotionsStallGui"
	screenGui.Parent = playerGui
end

screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 425
screenGui.Enabled = false

local uiRoot = screenGui:FindFirstChild("PotionsStallRoot")
if uiRoot and not uiRoot:IsA("GuiObject") then
	uiRoot = nil
end
if uiRoot then
	uiRoot.Visible = false
end

local built = uiRoot ~= nil
local buildInProgress = false
local isOpen = false
local suppressUntilExit = false
local wasInside = false
local lastOpenAt = 0
local openFunctionWarned = false
local hiddenGuiStates = {}
local legacyGuiNames = { "MainUI", "OptionsHudGui" }

-- Register with authoritative MenuState so MenuLockEnforcer sees this menu.
-- Use the local open flag as the source of truth; this avoids depending on
-- GUI objects before the stall UI has been built.
do
	local ms = nil
	pcall(function()
		local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
		if sideUI then
			local msMod = sideUI:FindFirstChild("MenuState")
			if msMod and msMod:IsA("ModuleScript") then
				local ok, result = pcall(require, msMod)
				if ok then ms = result end
			end
		end
	end)
	if ms and ms.RegisterMenu then
		pcall(function()
			ms.RegisterMenu("PotionsStall", {
				gui = screenGui,
				isOpen = function()
					return isOpen
				end,
			})
		end)
	end
end

local currentCharacter = nil
local currentHumanoid = nil
local currentRootPart = nil
local characterConnections = {}

local function setLegacyHudVisible(visible)
	if visible then
		for _, guiName in ipairs(legacyGuiNames) do
			local gui = playerGui:FindFirstChild(guiName)
			if gui and gui:IsA("ScreenGui") then
				local shouldEnable = hiddenGuiStates[guiName]
				if shouldEnable == nil then
					shouldEnable = true
				end
				gui.Enabled = shouldEnable
			end
		end
		hiddenGuiStates = {}
		return
	end

	for _, guiName in ipairs(legacyGuiNames) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui and gui:IsA("ScreenGui") and hiddenGuiStates[guiName] == nil then
			hiddenGuiStates[guiName] = gui.Enabled
			gui.Enabled = false
		end
	end
end

local function disconnectCharacterConnections()
	for _, conn in ipairs(characterConnections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	characterConnections = {}
end

local function closeStall()
	if uiRoot and uiRoot.Parent and uiRoot:IsA("GuiObject") then
		uiRoot.Visible = false
	end
	if screenGui and screenGui.Parent then
		screenGui.Enabled = false
	end
	if isOpen or next(hiddenGuiStates) ~= nil then
		setLegacyHudVisible(true)
	end
	isOpen = false
end

screenGui.Destroying:Connect(function()
	setLegacyHudVisible(true)
end)

local function bindCloseHandler()
	if uiRoot and type(PotionsStallUI.SetCloseCallback) == "function" then
		PotionsStallUI.SetCloseCallback(uiRoot, function()
			suppressUntilExit = true
			closeStall()
		end)
	end
	if uiRoot and uiRoot:IsA("GuiObject") then
		uiRoot.Visible = false
	end
	if uiRoot then
		built = true
	end
	return uiRoot
end

if uiRoot then
	bindCloseHandler()
end

local function destroyBuiltUi()
	if uiRoot and uiRoot.Parent then
		pcall(function()
			uiRoot:Destroy()
		end)
	end
	uiRoot = nil
	built = false
end

local function ensureUiBuilt(forceRebuild)
	if forceRebuild and not buildInProgress then
		destroyBuiltUi()
	end

	if built or buildInProgress then
		return bindCloseHandler()
	end

	buildInProgress = true
	uiRoot = PotionsStallUI.Create(screenGui, {
		onClose = function()
			suppressUntilExit = true
			closeStall()
		end,
	})
	bindCloseHandler()
	buildInProgress = false
	return uiRoot
end

local function closeSideUiMenus()
	if _G.SideUI and _G.SideUI.MenuController then
		pcall(function()
			_G.SideUI.MenuController.CloseAllMenus()
		end)
	end
end

local function openStall()
	if isOpen or suppressUntilExit then return end
	if buildInProgress then
		return
	end
	local now = os.clock()
	if now - lastOpenAt < 0.5 then return end

	local root = ensureUiBuilt(true)
	if not (root and root.Parent and root:IsA("GuiObject")) then
		if not openFunctionWarned then
			openFunctionWarned = true
			warn("[PotionStall] Could not resolve potion menu open function")
		end
		return
	end
	closeSideUiMenus()
	setLegacyHudVisible(false)
	screenGui.Enabled = true
	root.Visible = true
	isOpen = true
	lastOpenAt = now
	print("[PotionStall] Local player entered zone; opening potion menu")
end

local function resolveRootPart(character)
	if not character then return nil end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
end

local function setCharacter(character)
	disconnectCharacterConnections()
	currentCharacter = character
	currentHumanoid = nil
	currentRootPart = nil
	closeStall()
	wasInside = false
	suppressUntilExit = false

	if not character then
		setLegacyHudVisible(true)
		return
	end

	currentHumanoid = character:FindFirstChildOfClass("Humanoid")
	currentRootPart = resolveRootPart(character)

	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
			currentRootPart = child
		elseif child:IsA("Humanoid") then
			currentHumanoid = child
			table.insert(characterConnections, child.Died:Connect(function()
				closeStall()
				setLegacyHudVisible(true)
				wasInside = false
				suppressUntilExit = false
			end))
		end
	end))

	if currentHumanoid then
		table.insert(characterConnections, currentHumanoid.Died:Connect(function()
			closeStall()
			setLegacyHudVisible(true)
			wasInside = false
			suppressUntilExit = false
		end))
	end

	table.insert(characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			closeStall()
			setLegacyHudVisible(true)
			wasInside = false
			suppressUntilExit = false
		end
	end))

	if not currentRootPart then
		task.spawn(function()
			local rootPart = character:WaitForChild("HumanoidRootPart", 5)
			if rootPart and rootPart:IsA("BasePart") and currentCharacter == character then
				currentRootPart = rootPart
			end
		end)
	end
end

local function isPointInsidePart(part, point, padding)
	padding = padding or 0
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	local horizontalPadding = padding
	local verticalPadding = math.max(padding, 6)
	return math.abs(localPoint.X) <= halfSize.X + horizontalPadding
		and math.abs(localPoint.Y) <= halfSize.Y + verticalPadding
		and math.abs(localPoint.Z) <= halfSize.Z + horizontalPadding
end

player.CharacterAdded:Connect(setCharacter)
if player.Character then
	setCharacter(player.Character)
end

task.defer(function()
	if screenGui.Parent then
		ensureUiBuilt()
	end
end)

RunService.RenderStepped:Connect(function()
	local activePromptPart = resolvePromptPart()
	if not activePromptPart then
		closeStall()
		wasInside = false
		return
	end

	if not currentCharacter or not currentCharacter.Parent then
		closeStall()
		wasInside = false
		return
	end

	if not currentHumanoid or currentHumanoid.Health <= 0 then
		closeStall()
		wasInside = false
		return
	end

	if not currentRootPart or not currentRootPart.Parent then
		currentRootPart = resolveRootPart(currentCharacter)
		if not currentRootPart then
			closeStall()
			wasInside = false
			return
		end
	end

	local padding = (isOpen or wasInside) and 1.5 or 0
	local inside = isPointInsidePart(activePromptPart, currentRootPart.Position, padding)

	if inside then
		if not suppressUntilExit then
			openStall()
		end
	else
		if wasInside then
			suppressUntilExit = false
		end
		closeStall()
	end

	wasInside = inside
end)

_G.OpenPotionsStallMenu = function()
	local root = ensureUiBuilt(true)
	if not (root and root.Parent and root:IsA("GuiObject")) then
		return false
	end
	closeSideUiMenus()
	setLegacyHudVisible(false)
	screenGui.Enabled = true
	screenGui.Enabled = true
	root.Visible = true
	isOpen = true
	return true
end

-- Register with global SideUI MenuController (so MenuLockEnforcer will lock equips)
do
	local MenuController = nil
	pcall(function()
		local sideUI = ReplicatedStorage:FindFirstChild("SideUI")
		if sideUI then
			local mc = sideUI:FindFirstChild("MenuController")
			if mc then MenuController = require(mc) end
		end
	end)
	if MenuController then
		MenuController.RegisterMenu("PotionsStall", {
			open = function()
				ensureUiBuilt(true)
				if screenGui and screenGui.Parent then
					screenGui.Enabled = true
				end
				if uiRoot and uiRoot:IsA("GuiObject") then
					uiRoot.Visible = true
				end
				isOpen = true
			end,
			close = function() suppressUntilExit = true closeStall() end,
			closeInstant = function() closeStall() end,
			isOpen = function() return isOpen end,
		})
	end
end
