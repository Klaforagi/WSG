--------------------------------------------------------------------------------
-- CosmeticPreviewController.lua
-- Shared viewport preview helper for the Cosmetics podium.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local sideUI = script.Parent

local SkinPreview = nil
pcall(function()
	local mod = sideUI:FindFirstChild("SkinPreview")
	if mod and mod:IsA("ModuleScript") then
		SkinPreview = require(mod)
	end
end)

local EffectsPreview = nil
pcall(function()
	local mod = sideUI:FindFirstChild("EffectsPreview")
	if mod and mod:IsA("ModuleScript") then
		EffectsPreview = require(mod)
	end
end)

local EmoteConfig = nil
pcall(function()
	local mod = sideUI:FindFirstChild("EmoteConfig")
	if mod and mod:IsA("ModuleScript") then
		EmoteConfig = require(mod)
	end
end)

local CosmeticPreviewController = {}
CosmeticPreviewController.__index = CosmeticPreviewController

local function clearViewport(viewportFrame)
	if not viewportFrame then
		return
	end
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") then
			child:Destroy()
		end
	end
	viewportFrame.CurrentCamera = nil
end

local function sanitizeRig(rig)
	if not rig then
		return nil
	end
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	return rig
end

local function buildAvatarRig()
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local desc = nil
		pcall(function()
			desc = humanoid:GetAppliedDescription()
		end)
		if desc then
			local ok, rig = pcall(function()
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and rig then
				return sanitizeRig(rig)
			end
		end
	end

	if player then
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromUserId(player.UserId)
		end)
		if ok and rig then
			return sanitizeRig(rig)
		end
	end

	if character then
		local ok, rig = pcall(function()
			return character:Clone()
		end)
		if ok and rig then
			return sanitizeRig(rig)
		end
	end

	return nil
end

local function setupCamera(viewportFrame, worldModel)
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 42
	camera.CFrame = CFrame.lookAt(Vector3.new(3.2, 3.1, 7.2), Vector3.new(0, 2.35, 0))
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	local key = Instance.new("Part")
	key.Name = "PreviewKeyLight"
	key.Anchored = true
	key.CanCollide = false
	key.Transparency = 1
	key.Size = Vector3.new(0.1, 0.1, 0.1)
	key.CFrame = CFrame.new(4, 6, 5)
	key.Parent = worldModel
	local keyLight = Instance.new("PointLight")
	keyLight.Color = Color3.fromRGB(235, 238, 255)
	keyLight.Brightness = 1.7
	keyLight.Range = 24
	keyLight.Parent = key

	local fill = Instance.new("Part")
	fill.Name = "PreviewFillLight"
	fill.Anchored = true
	fill.CanCollide = false
	fill.Transparency = 1
	fill.Size = Vector3.new(0.1, 0.1, 0.1)
	fill.CFrame = CFrame.new(-4, 3.5, 4)
	fill.Parent = worldModel
	local fillLight = Instance.new("PointLight")
	fillLight.Color = Color3.fromRGB(130, 160, 220)
	fillLight.Brightness = 0.65
	fillLight.Range = 18
	fillLight.Parent = fill
end

function CosmeticPreviewController.new(viewportFrame)
	local self = setmetatable({}, CosmeticPreviewController)
	self.ViewportFrame = viewportFrame
	self._connections = {}
	self._track = nil
	self._activeMode = nil
	return self
end

function CosmeticPreviewController:_disconnect()
	for _, conn in ipairs(self._connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._connections = {}
end

function CosmeticPreviewController:Stop()
	self:_disconnect()
	if self._track then
		pcall(function()
			self._track:Stop(0.08)
			self._track:Destroy()
		end)
		self._track = nil
	end
	if EffectsPreview and type(EffectsPreview.Stop) == "function" then
		pcall(function()
			EffectsPreview.Stop()
		end)
	end
	clearViewport(self.ViewportFrame)
	self._activeMode = nil
end

function CosmeticPreviewController:ShowIdle()
	self:Stop()
	local viewportFrame = self.ViewportFrame
	if not viewportFrame then
		return
	end

	local rig = buildAvatarRig()
	if not rig then
		return
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "IdlePreviewWorld"
	worldModel.Parent = viewportFrame
	rig.Parent = worldModel
	rig:PivotTo(CFrame.new(0, 2.45, 0) * CFrame.Angles(0, math.rad(180), 0))
	setupCamera(viewportFrame, worldModel)

	local elapsed = 0
	table.insert(self._connections, RunService.RenderStepped:Connect(function(dt)
		if not rig.Parent then
			return
		end
		elapsed += dt
		rig:PivotTo(CFrame.new(0, 2.45, 0) * CFrame.Angles(0, math.rad(180) + math.sin(elapsed * 0.7) * 0.08, 0))
	end))
	self._activeMode = "Idle"
end

function CosmeticPreviewController:ShowSkin(skinId, showHelm)
	self:Stop()
	if not self.ViewportFrame then
		return
	end
	if SkinPreview and type(SkinPreview.Update) == "function" then
		local ok = pcall(function()
			SkinPreview.Update(self.ViewportFrame, skinId or "Default", showHelm ~= false)
		end)
		if ok then
			self._activeMode = "Skin"
			return
		end
	end
	self:ShowIdle()
end

function CosmeticPreviewController:ShowTrail(effectId)
	self:Stop()
	if not self.ViewportFrame then
		return
	end
	if EffectsPreview and type(EffectsPreview.Update) == "function" then
		local ok = pcall(function()
			EffectsPreview.Update(self.ViewportFrame, effectId or "DefaultTrail")
		end)
		if ok then
			self._activeMode = "Trail"
			return
		end
	end
	self:ShowIdle()
end

function CosmeticPreviewController:ShowEmote(emoteId)
	self:Stop()
	local viewportFrame = self.ViewportFrame
	if not viewportFrame then
		return
	end

	local def = EmoteConfig and EmoteConfig.GetById and EmoteConfig.GetById(emoteId)
	local rig = buildAvatarRig()
	if not rig then
		return
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "EmotePreviewWorld"
	worldModel.Parent = viewportFrame
	rig.Parent = worldModel
	rig:PivotTo(CFrame.new(0, 2.45, 0) * CFrame.Angles(0, math.rad(180), 0))
	setupCamera(viewportFrame, worldModel)

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid and def and type(def.AnimationId) == "string" and def.AnimationId ~= "" then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = def.AnimationId
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			pcall(function()
				track:Play(0.12)
			end)
			self._track = track
		end
	end

	local elapsed = 0
	table.insert(self._connections, RunService.RenderStepped:Connect(function(dt)
		if not rig.Parent then
			return
		end
		elapsed += dt
		rig:PivotTo(CFrame.new(0, 2.45, 0) * CFrame.Angles(0, math.rad(180) + math.sin(elapsed * 0.6) * 0.06, 0))
	end))
	self._activeMode = "Emote"
end

function CosmeticPreviewController:ShowItem(item, showHelm)
	if type(item) ~= "table" then
		self:ShowIdle()
		return
	end
	if item.Category == "Skin" then
		self:ShowSkin(item.Id, showHelm)
	elseif item.Category == "Trail" then
		self:ShowTrail(item.Id)
	elseif item.Category == "Emote" then
		self:ShowEmote(item.Id)
	else
		self:ShowIdle()
	end
end

return CosmeticPreviewController
