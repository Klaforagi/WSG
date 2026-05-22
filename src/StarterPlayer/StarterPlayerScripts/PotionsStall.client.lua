local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REMOTE_NAME = "OpenPotionsMenu"
local STALL_NAMES = {
	"PotionsStall",
	"PotionStall",
	"Potion Stall",
	"Potions Stall",
}

local function isStallName(name)
	for _, stallName in ipairs(STALL_NAMES) do
		if name == stallName then
			return true
		end
	end

	local lowerName = string.lower(tostring(name or ""))
	return string.find(lowerName, "potion", 1, true) ~= nil and string.find(lowerName, "stall", 1, true) ~= nil
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
screenGui.Enabled = true

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
local hiddenGuiStates = {}
local legacyGuiNames = { "MainUI", "OptionsHudGui" }

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

local function closeStall()
	if uiRoot and uiRoot.Parent and uiRoot:IsA("GuiObject") then
		uiRoot.Visible = false
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

local function ensureUiBuilt()
	if built or buildInProgress then
		return bindCloseHandler()
	end

	buildInProgress = true
	uiRoot = PotionsStallUI.Create(screenGui, {
		onClose = function()
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
	if isOpen then
		return true
	end

	local root = ensureUiBuilt()
	if not (root and root.Parent and root:IsA("GuiObject")) then
		warn("[PotionsStall] Menu controller did not return a GuiObject root")
		return false
	end

	closeSideUiMenus()
	setLegacyHudVisible(false)
	screenGui.Enabled = true
	root.Visible = true
	isOpen = true
	print("[PotionsStall] Menu root found and opened: " .. root.Name)
	return true
end

local function findStallModel()
	for _, stallName in ipairs(STALL_NAMES) do
		local direct = Workspace:FindFirstChild(stallName)
		if direct and direct:IsA("Model") then
			return direct
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and isStallName(descendant.Name) then
			return descendant
		end
	end

	return nil
end

task.defer(function()
	local stallModel = findStallModel()
	if stallModel then
		print("[PotionsStall] Client found stall " .. stallModel:GetFullName())
		local promptPart = stallModel:FindFirstChild("PromptPart", true)
		if promptPart and promptPart:IsA("BasePart") then
			print("[PotionsStall] Client found PromptPart " .. promptPart:GetFullName())
		else
			warn("[PotionsStall] Client could not find a BasePart PromptPart under " .. stallModel:GetFullName())
		end
	else
		warn("[PotionsStall] Client could not find Workspace.PotionsStall/PotionStall; waiting for server prompt event.")
	end
end)

task.spawn(function()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotesFolder then
		warn("[PotionsStall] Remotes folder not found; potions menu open listener unavailable")
		return
	end

	local potionsFolder = remotesFolder:WaitForChild("Potions", 30)
	if not potionsFolder then
		warn("[PotionsStall] Remotes.Potions folder not found; potions menu open listener unavailable")
		return
	end

	local openMenuRE = potionsFolder:WaitForChild(REMOTE_NAME, 30)
	if not (openMenuRE and openMenuRE:IsA("RemoteEvent")) then
		warn("[PotionsStall] Remotes.Potions." .. REMOTE_NAME .. " RemoteEvent not found; potions menu open listener unavailable")
		return
	end

	print("[PotionsStall] Client listening for " .. REMOTE_NAME)
	openMenuRE.OnClientEvent:Connect(function()
		print("[PotionsStall] Open menu request received")
		local opened = openStall()
		if not opened then
			warn("[PotionsStall] Open menu request received, but Potions menu could not be opened")
		end
	end)
end)

_G.OpenPotionsStallMenu = function()
	return openStall()
end