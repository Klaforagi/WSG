local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local modulesFolder = ReplicatedStorage:WaitForChild("Modules", 15)

if not modulesFolder then
	warn("[UpgradeStall] Modules folder not found")
	return
end

local forgeModule = modulesFolder:WaitForChild("ForgeStallUI", 15)
if not (forgeModule and forgeModule:IsA("ModuleScript")) then
	warn("[UpgradeStall] ForgeStallUI module not found")
	return
end

local ForgeStallUI = require(forgeModule)

local stallModel = Workspace:WaitForChild("UpgradeStall", 30)
if not (stallModel and stallModel:IsA("Model")) then
	warn("[UpgradeStall] UpgradeStall model not found")
	return
end

local promptPart = stallModel:WaitForChild("PromptPart", 30)
if not (promptPart and promptPart:IsA("BasePart")) then
	warn("[UpgradeStall] PromptPart missing under UpgradeStall")
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ForgeStallGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 420
screenGui.Enabled = false
screenGui.Parent = playerGui

local built = false
local isOpen = false
local suppressUntilExit = false
local wasInside = false
local hiddenGuiStates = {}
local legacyGuiNames = { "MainUI", "OptionsHudGui" }

-- Register with authoritative MenuState so MenuLockEnforcer sees this menu.
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
			ms.RegisterMenu("ForgeStall", {
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
	if screenGui.Enabled then
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

local function ensureUiBuilt()
	if built then return end
	ForgeStallUI.Create(screenGui, {
		onClose = function()
			suppressUntilExit = true
			closeStall()
		end,
	})
	built = true
end

-- Register with global SideUI MenuController so MenuLockEnforcer will lock equips
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
		MenuController.RegisterMenu("ForgeStall", {
			open = function()
				ensureUiBuilt()
				setLegacyHudVisible(false)
				if screenGui and screenGui.Parent then
					screenGui.Enabled = true
				end
				-- rely on MenuState/MenuLockEnforcer to block equips and force-unequip
				isOpen = true
			end,
			close = function() suppressUntilExit = true closeStall() end,
			closeInstant = function() closeStall() end,
			isOpen = function() return isOpen end,
		})
	end
end

local function openStall()
	if isOpen or suppressUntilExit then return end
	ensureUiBuilt()
	setLegacyHudVisible(false)
	screenGui.Enabled = true
	isOpen = true
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
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = (part.Size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

player.CharacterAdded:Connect(setCharacter)
if player.Character then
	setCharacter(player.Character)
end

RunService.RenderStepped:Connect(function()
	if not promptPart.Parent then
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
	local inside = isPointInsidePart(promptPart, currentRootPart.Position, padding)

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