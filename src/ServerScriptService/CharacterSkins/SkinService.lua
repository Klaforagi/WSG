local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local SkinService = {}

local DEBUG = true
local APPLIED_MODEL_NAME = "AppliedCharacterSkin"
local PLAYER_SKIN_ATTRIBUTE = "FullBodySkin"
local MODEL_TAG_ATTRIBUTE = "_FullBodySkinModel"
local PART_TAG_ATTRIBUTE = "_FullBodySkinPart"
local CLOTHING_TAG_ATTRIBUTE = "_FullBodySkinClothing"
local MOTOR_NAME_PREFIX = "SkinMotor_"
local WELD_NAME_PREFIX = "SkinWeld_"
local ORIENTATION_WARN_THRESHOLD_DEGREES = 20
local AUTO_CORRECT_ROTATED_ROOTS = true
local MIN_HUMANOID_SCALE = 0.35
local MAX_HUMANOID_SCALE = 3.5
local HUMANOID_SCALE_DEFAULTS = {
	BodyDepthScale = 1,
	BodyHeightScale = 1,
	BodyWidthScale = 1,
	HeadScale = 1,
}

local function dprint(...)
	if DEBUG then
		print("[CharacterSkinService]", ...)
	end
end

local function dwarn(...)
	warn("[CharacterSkinService]", ...)
end

local function normalizeName(name)
	return string.lower((tostring(name):gsub("[%s%p_]", "")))
end

local function formatVector3(vector)
	return string.format("(%.3f, %.3f, %.3f)", vector.X, vector.Y, vector.Z)
end

local function formatScalePlan(scalePlan)
	if not scalePlan then
		return "(none)"
	end

	return string.format(
		"width=%.3f height=%.3f depth=%.3f head=%.3f",
		scalePlan.BodyWidthScale or 1,
		scalePlan.BodyHeightScale or 1,
		scalePlan.BodyDepthScale or 1,
		scalePlan.HeadScale or 1
	)
end

local function getOrientationDifferenceDegrees(fromCFrame, toCFrame)
	local dot = math.clamp(fromCFrame.LookVector:Dot(toCFrame.LookVector), -1, 1)
	return math.deg(math.acos(dot))
end

local function getMedian(values)
	if #values == 0 then
		return nil
	end

	table.sort(values)
	local middle = math.ceil(#values / 2)
	if #values % 2 == 1 then
		return values[middle]
	end

	return (values[middle] + values[middle + 1]) * 0.5
end

local function clampHumanoidScale(value)
	return math.clamp(value, MIN_HUMANOID_SCALE, MAX_HUMANOID_SCALE)
end

local function getHumanoidScaleValue(humanoid, scaleName, createIfMissing)
	local child = humanoid:FindFirstChild(scaleName)
	if child and child:IsA("NumberValue") then
		return child
	end
	if not createIfMissing then
		return nil
	end

	local created = Instance.new("NumberValue")
	created.Name = scaleName
	created.Value = HUMANOID_SCALE_DEFAULTS[scaleName] or 1
	created.Parent = humanoid
	return created
end

local function captureHumanoidScaleState(humanoid)
	local captured = {}
	for scaleName, defaultValue in pairs(HUMANOID_SCALE_DEFAULTS) do
		local scaleValue = getHumanoidScaleValue(humanoid, scaleName, false)
		captured[scaleName] = scaleValue and scaleValue.Value or defaultValue
	end

	local automaticScalingEnabled = nil
	pcall(function()
		automaticScalingEnabled = humanoid.AutomaticScalingEnabled
	end)
	captured.AutomaticScalingEnabled = automaticScalingEnabled
	return captured
end

local function restoreHumanoidScaleState(humanoid, captured)
	if not humanoid or not captured then
		return
	end

	if captured.AutomaticScalingEnabled ~= nil then
		pcall(function()
			humanoid.AutomaticScalingEnabled = captured.AutomaticScalingEnabled
		end)
	end

	for scaleName, defaultValue in pairs(HUMANOID_SCALE_DEFAULTS) do
		local scaleValue = getHumanoidScaleValue(humanoid, scaleName, true)
		if scaleValue then
			scaleValue.Value = captured[scaleName] or defaultValue
		end
	end
	RunService.Heartbeat:Wait()
	dprint("restored humanoid scale state")
end

local function computeHumanoidScalePlan(rootAttachments)
	local widthRatios = {}
	local heightRatios = {}
	local depthRatios = {}
	local headRatios = {}

	for _, attachment in ipairs(rootAttachments) do
		local sourcePart = attachment.sourcePart
		local targetPart = attachment.targetPart
		local targetSize = targetPart and targetPart.Size
		local sourceSize = sourcePart and sourcePart.Size
		if sourceSize and targetSize and targetSize.X > 0 and targetSize.Y > 0 and targetSize.Z > 0 then
			local widthRatio = sourceSize.X / targetSize.X
			local heightRatio = sourceSize.Y / targetSize.Y
			local depthRatio = sourceSize.Z / targetSize.Z
			if targetPart.Name == "Head" then
				table.insert(headRatios, (widthRatio + heightRatio + depthRatio) / 3)
			elseif targetPart.Name ~= "HumanoidRootPart" then
				table.insert(widthRatios, widthRatio)
				table.insert(heightRatios, heightRatio)
				table.insert(depthRatios, depthRatio)
			end
		end
	end

	local scalePlan = {
		BodyWidthScale = getMedian(widthRatios),
		BodyHeightScale = getMedian(heightRatios),
		BodyDepthScale = getMedian(depthRatios),
		HeadScale = getMedian(headRatios),
	}

	for scaleName, value in pairs(scalePlan) do
		if value ~= nil then
			scalePlan[scaleName] = clampHumanoidScale(value)
		end
	end

	if not next(scalePlan) then
		return nil
	end

	if scalePlan.HeadScale == nil then
		scalePlan.HeadScale = math.max(
			scalePlan.BodyWidthScale or 1,
			scalePlan.BodyHeightScale or 1,
			scalePlan.BodyDepthScale or 1
		)
	end

	return scalePlan
end

local function applyHumanoidScalePlan(humanoid, scalePlan, capturedState)
	if not humanoid or not scalePlan then
		return false
	end

	if capturedState and not capturedState._captured then
		local snapshot = captureHumanoidScaleState(humanoid)
		for key, value in pairs(snapshot) do
			capturedState[key] = value
		end
		capturedState._captured = true
	end

	pcall(function()
		humanoid.AutomaticScalingEnabled = true
	end)

	for scaleName, defaultValue in pairs(HUMANOID_SCALE_DEFAULTS) do
		local scaleValue = getHumanoidScaleValue(humanoid, scaleName, true)
		if scaleValue then
			scaleValue.Value = scalePlan[scaleName] or defaultValue
		end
	end
	RunService.Heartbeat:Wait()
	dprint("applied humanoid scale plan", formatScalePlan(scalePlan))
	return true
end

local function shouldAutoCorrectAttachment(attachment, orientationDifference)
	if not AUTO_CORRECT_ROTATED_ROOTS then
		return false
	end
	if orientationDifference <= ORIENTATION_WARN_THRESHOLD_DEGREES then
		return false
	end

	local label = attachment and attachment.binding and attachment.binding.label or nil
	if label == "HumanoidRootPart" or label == "UpperTorso" or label == "LowerTorso" then
		return false
	end

	return true
end

local HEAD_ATTACHMENT_NAMES = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

local HEAD_ACCESSORY_TYPES = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local function isHeadAccessory(accessory)
	local handle = accessory and accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	local accessoryType = nil
	pcall(function()
		accessoryType = accessory.AccessoryType
	end)
	if accessoryType and HEAD_ACCESSORY_TYPES[accessoryType] then
		return true
	end

	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment") and HEAD_ATTACHMENT_NAMES[child.Name] then
			return true
		end
	end

	local accessoryWeld = handle:FindFirstChild("AccessoryWeld")
	if accessoryWeld and accessoryWeld:IsA("Weld") then
		local part0 = accessoryWeld.Part0
		local part1 = accessoryWeld.Part1
		if (part0 and part0.Name == "Head") or (part1 and part1.Name == "Head") then
			return true
		end
	end

	return false
end

local BODY_PART_NAMES = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	Torso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	HumanoidRootPart = true,
}

local ROOT_BINDINGS = {
	{
		label = "HumanoidRootPart",
		targetNames = { "HumanoidRootPart" },
		sourceAliases = { "humanoidrootpart", "root", "rootpart", "rigroot", "hipsroot" },
	},
	{
		label = "UpperTorso",
		targetNames = { "UpperTorso", "Torso" },
		sourceAliases = { "uppertorso", "torso", "body", "chest", "mainbody" },
	},
	{
		label = "LowerTorso",
		targetNames = { "LowerTorso", "Torso" },
		sourceAliases = { "lowertorso", "waist", "hips", "pelvis" },
	},
	{
		label = "Head",
		targetNames = { "Head" },
		sourceAliases = { "head", "helmetroot", "helmet", "helm" },
	},
	{
		label = "LeftUpperArm",
		targetNames = { "LeftUpperArm", "Left Arm" },
		sourceAliases = { "leftupperarm", "leftarm", "larm", "leftshoulder" },
	},
	{
		label = "LeftLowerArm",
		targetNames = { "LeftLowerArm", "Left Arm" },
		sourceAliases = { "leftlowerarm", "leftforearm", "leftelbow", "leftgauntlet" },
	},
	{
		label = "LeftHand",
		targetNames = { "LeftHand", "Left Arm" },
		sourceAliases = { "lefthand", "leftglove" },
	},
	{
		label = "RightUpperArm",
		targetNames = { "RightUpperArm", "Right Arm" },
		sourceAliases = { "rightupperarm", "rightarm", "rarm", "rightshoulder" },
	},
	{
		label = "RightLowerArm",
		targetNames = { "RightLowerArm", "Right Arm" },
		sourceAliases = { "rightlowerarm", "rightforearm", "rightelbow", "rightgauntlet" },
	},
	{
		label = "RightHand",
		targetNames = { "RightHand", "Right Arm" },
		sourceAliases = { "righthand", "rightglove" },
	},
	{
		label = "LeftUpperLeg",
		targetNames = { "LeftUpperLeg", "Left Leg" },
		sourceAliases = { "leftupperleg", "leftleg", "lleg", "leftthigh" },
	},
	{
		label = "LeftLowerLeg",
		targetNames = { "LeftLowerLeg", "Left Leg" },
		sourceAliases = { "leftlowerleg", "leftshin", "leftcalf", "leftknee" },
	},
	{
		label = "LeftFoot",
		targetNames = { "LeftFoot", "Left Leg" },
		sourceAliases = { "leftfoot", "leftboot" },
	},
	{
		label = "RightUpperLeg",
		targetNames = { "RightUpperLeg", "Right Leg" },
		sourceAliases = { "rightupperleg", "rightleg", "rleg", "rightthigh" },
	},
	{
		label = "RightLowerLeg",
		targetNames = { "RightLowerLeg", "Right Leg" },
		sourceAliases = { "rightlowerleg", "rightshin", "rightcalf", "rightknee" },
	},
	{
		label = "RightFoot",
		targetNames = { "RightFoot", "Right Leg" },
		sourceAliases = { "rightfoot", "rightboot" },
	},
}

local DEFAULT_OPTIONS = {
	HideAccessories = true,
	DestroyAccessories = false,
}

local skinDefinitions = {
	Knight = {
		TemplateName = "Knight",
		HideAccessories = true,
		DestroyAccessories = false,
	},
	Goblin = {
		TemplateName = "Goblin",
		HideAccessories = true,
		DestroyAccessories = false,
	},
}

local activeStates = {}
local desiredSkins = {}
local desiredShowHelmByPlayer = {}
local playerConnections = {}

local function getSkinTemplate(skinName)
	local skinsFolder = ServerStorage:FindFirstChild("Skins")
	if not skinsFolder then
		dwarn("ServerStorage.Skins folder is missing")
		return nil
	end

	local template = skinsFolder:FindFirstChild(skinName)
	if not template or not template:IsA("Model") then
		dwarn("Skin model not found or not a Model:", skinName)
		return nil
	end

	return template
end

local function getCharacterTargetPart(character, binding)
	for _, targetName in ipairs(binding.targetNames) do
		local part = character:FindFirstChild(targetName)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function buildAliasLookup(binding)
	local lookup = {}
	for _, alias in ipairs(binding.sourceAliases) do
		lookup[normalizeName(alias)] = true
	end
	return lookup
end

local function findSourcePart(model, usedParts, binding)
	local aliasLookup = buildAliasLookup(binding)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and not usedParts[desc] then
			if aliasLookup[normalizeName(desc.Name)] then
				usedParts[desc] = true
				return desc
			end
		end
	end
	return nil
end

local function collectBaseParts(model)
	local parts = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	return parts
end

local function isSupportedClothing(instance)
	return instance and (instance:IsA("Shirt") or instance:IsA("Pants") or instance:IsA("ShirtGraphic"))
end

local function collectTemplateClothing(model)
	local clothing = {}
	for _, desc in ipairs(model:GetDescendants()) do
		if isSupportedClothing(desc) then
			table.insert(clothing, desc)
		end
	end
	return clothing
end

local function buildJointAdjacency(model)
	local adjacency = {}

	local function connect(part0, part1)
		if not part0 or not part1 then
			return
		end
		if not part0:IsA("BasePart") or not part1:IsA("BasePart") then
			return
		end
		adjacency[part0] = adjacency[part0] or {}
		adjacency[part1] = adjacency[part1] or {}
		adjacency[part0][part1] = true
		adjacency[part1][part0] = true
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("JointInstance") or desc:IsA("WeldConstraint") then
			connect(desc.Part0, desc.Part1)
		end
	end

	return adjacency
end

local function replaceJointWithWeldConstraint(joint)
	local part0 = joint.Part0
	local part1 = joint.Part1
	if not part0 or not part1 then
		joint:Destroy()
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_NAME_PREFIX .. part1.Name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
	joint:Destroy()
end

local function collectConnectedGroup(startPart, adjacency)
	local connected = {}
	if not startPart then
		return connected
	end

	local stack = { startPart }
	connected[startPart] = true

	while #stack > 0 do
		local current = stack[#stack]
		stack[#stack] = nil
		for neighbor in pairs(adjacency[current] or {}) do
			if not connected[neighbor] then
				connected[neighbor] = true
				stack[#stack + 1] = neighbor
			end
		end
	end

	return connected
end

local function chooseReferenceAttachment(rootAttachments)
	local priorities = {
		"HumanoidRootPart",
		"UpperTorso",
		"Torso",
		"LowerTorso",
		"Head",
	}

	for _, targetName in ipairs(priorities) do
		for _, attachment in ipairs(rootAttachments) do
			if attachment.targetPart.Name == targetName then
				return attachment
			end
		end
	end

	return rootAttachments[1]
end

local function alignCloneToCharacter(cloneModel, rootAttachments)
	local referenceAttachment = chooseReferenceAttachment(rootAttachments)
	if not referenceAttachment then
		return false
	end

	local delta = referenceAttachment.targetPart.CFrame * referenceAttachment.sourcePart.CFrame:Inverse()
	for _, part in ipairs(collectBaseParts(cloneModel)) do
		part.CFrame = delta * part.CFrame
	end

	dprint("aligned skin model using reference part", referenceAttachment.sourcePart.Name, "->", referenceAttachment.targetPart.Name)
	return true
end

local function buildNearestRootAssignments(cloneModel, rootAttachments)
	local adjacency = buildJointAdjacency(cloneModel)
	local attachmentByPart = {}
	local targetByPart = {}
	local groupedParts = {}
	local queue = {}
	local queueIndex = 1

	for _, attachment in ipairs(rootAttachments) do
		groupedParts[attachment] = {}
		if attachment.sourcePart then
			attachmentByPart[attachment.sourcePart] = attachment
			targetByPart[attachment.sourcePart] = attachment.targetPart
			table.insert(groupedParts[attachment], attachment.sourcePart)
			queue[#queue + 1] = attachment.sourcePart
		end
	end

	while queueIndex <= #queue do
		local current = queue[queueIndex]
		queueIndex += 1
		local currentAttachment = attachmentByPart[current]
		if currentAttachment then
			for neighbor in pairs(adjacency[current] or {}) do
				if not attachmentByPart[neighbor] then
					attachmentByPart[neighbor] = currentAttachment
					targetByPart[neighbor] = currentAttachment.targetPart
					table.insert(groupedParts[currentAttachment], neighbor)
					queue[#queue + 1] = neighbor
				end
			end
		end
	end

	for _, part in ipairs(collectBaseParts(cloneModel)) do
		if not attachmentByPart[part] then
			local bestAttachment = nil
			local bestDistance = math.huge
			for _, attachment in ipairs(rootAttachments) do
				local delta = part.Position - attachment.sourcePart.Position
				local distance = delta:Dot(delta)
				if distance < bestDistance then
					bestDistance = distance
					bestAttachment = attachment
				end
			end

			if bestAttachment then
				attachmentByPart[part] = bestAttachment
				targetByPart[part] = bestAttachment.targetPart
				table.insert(groupedParts[bestAttachment], part)
				dprint("fallback-assigned loose cosmetic part", part.Name, "to", bestAttachment.targetPart.Name)
			end
		end
	end

	return attachmentByPart, targetByPart, groupedParts
end

local function normalizeRootGroupOrientations(rootAttachments, groupedParts)
	for _, attachment in ipairs(rootAttachments) do
		local sourcePart = attachment.sourcePart
		local targetPart = attachment.targetPart
		local localOffset = targetPart.CFrame:ToObjectSpace(sourcePart.CFrame)
		local orientationDifference = getOrientationDifferenceDegrees(targetPart.CFrame, sourcePart.CFrame)

		if orientationDifference > ORIENTATION_WARN_THRESHOLD_DEGREES then
			dwarn(
				"root orientation differs from target by",
				string.format("%.1f", orientationDifference),
				"degrees:",
				sourcePart.Name,
				"->",
				targetPart.Name,
				"local offset =",
				formatVector3(localOffset.Position)
			)
		end

		local correctedRootCFrame = targetPart.CFrame * CFrame.new(localOffset.Position)
		if shouldAutoCorrectAttachment(attachment, orientationDifference) then
			local delta = correctedRootCFrame * sourcePart.CFrame:Inverse()
			for _, part in ipairs(groupedParts[attachment] or {}) do
				part.CFrame = delta * part.CFrame
			end
			dprint("auto-corrected rotated root", sourcePart.Name, "->", targetPart.Name)
		end

		attachment.localOffset = targetPart.CFrame:ToObjectSpace(sourcePart.CFrame)
		dprint(
			"final root offset",
			sourcePart.Name,
			"->",
			targetPart.Name,
			"pos =",
			formatVector3(attachment.localOffset.Position),
			"angle =",
			string.format("%.1f", getOrientationDifferenceDegrees(targetPart.CFrame, sourcePart.CFrame))
		)
	end
end

local function prepareClonePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	if part:GetAttribute("_FullBodyOrigTransparency") == nil then
		part:SetAttribute("_FullBodyOrigTransparency", part.Transparency)
	end
	part:SetAttribute(PART_TAG_ATTRIBUTE, true)
end

local function pruneCrossLimbJoints(cloneModel, targetByPart)
	for _, desc in ipairs(cloneModel:GetDescendants()) do
		if desc:IsA("WeldConstraint") then
			local part0 = desc.Part0
			local part1 = desc.Part1
			local target0 = part0 and targetByPart[part0] or nil
			local target1 = part1 and targetByPart[part1] or nil
			if target0 and target1 and target0 ~= target1 then
				dprint("removing cross-limb joint", desc.Name, "between", part0.Name, "and", part1.Name)
				desc:Destroy()
			end
		elseif desc:IsA("JointInstance") then
			local part0 = desc.Part0
			local part1 = desc.Part1
			local target0 = part0 and targetByPart[part0] or nil
			local target1 = part1 and targetByPart[part1] or nil
			if target0 and target1 and target0 ~= target1 then
				dprint("removing cross-limb joint", desc.Name, "between", part0.Name, "and", part1.Name)
				desc:Destroy()
			else
				replaceJointWithWeldConstraint(desc)
			end
		end
	end
	for _, part in ipairs(collectBaseParts(cloneModel)) do
		prepareClonePart(part)
	end
	cloneModel:SetAttribute(MODEL_TAG_ATTRIBUTE, true)
end

local function hideBodyParts(character, state)
	local visibleBodyParts = state.options.VisibleBodyParts
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and BODY_PART_NAMES[child.Name] then
			state.partTransparency[child] = child.Transparency
			local shouldHide = true
			if child.Name ~= "Head" and visibleBodyParts and visibleBodyParts[child.Name] then
				shouldHide = false
			end
			if shouldHide then
				child.Transparency = 1
			end
		end
		if child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				state.accessoryVisibility[handle] = handle.Transparency
				if isHeadAccessory(child) then
					state.headAccessoryHandles[handle] = true
				end
				if state.options.DestroyAccessories then
					child:Destroy()
				elseif state.options.HideAccessories then
					handle.Transparency = 1
				end
			end
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		for _, desc in ipairs(head:GetDescendants()) do
			if desc:IsA("Decal") then
				state.decalTransparency[desc] = desc.Transparency
				desc.Transparency = 1
			end
		end
	end
end

local function setOriginalHeadVisible(state, visible)
	local character = state and state.character
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if head and state.partTransparency[head] ~= nil then
		head.Transparency = visible and state.partTransparency[head] or 1
	end

	for handle in pairs(state.headAccessoryHandles or {}) do
		if handle and handle.Parent then
			handle.Transparency = visible and (state.accessoryVisibility[handle] or 0) or 1
		end
	end

	for decal, transparency in pairs(state.decalTransparency or {}) do
		if decal and decal.Parent then
			decal.Transparency = visible and transparency or 1
		end
	end
end

local function setSkinGroupVisible(partSet, transparencyMap, visible)
	for part in pairs(partSet or {}) do
		if part and part.Parent then
			part.Transparency = visible and (transparencyMap[part] or 0) or 1
		end
	end
end

local function getCloneClothingRigType(rootAttachments)
	for _, attachment in ipairs(rootAttachments or {}) do
		local label = attachment.binding and attachment.binding.label or nil
		if label == "LowerTorso"
			or label == "LeftLowerArm"
			or label == "RightLowerArm"
			or label == "LeftHand"
			or label == "RightHand"
			or label == "LeftLowerLeg"
			or label == "RightLowerLeg"
			or label == "LeftFoot"
			or label == "RightFoot" then
			return Enum.HumanoidRigType.R15
		end
	end

	return Enum.HumanoidRigType.R6
end

local function getStandardClothingPartName(bindingLabel, rigType)
	if rigType == Enum.HumanoidRigType.R15 then
		return bindingLabel
	end

	if bindingLabel == "UpperTorso" or bindingLabel == "LowerTorso" then
		return "Torso"
	end
	if bindingLabel == "LeftUpperArm" or bindingLabel == "LeftLowerArm" or bindingLabel == "LeftHand" then
		return "Left Arm"
	end
	if bindingLabel == "RightUpperArm" or bindingLabel == "RightLowerArm" or bindingLabel == "RightHand" then
		return "Right Arm"
	end
	if bindingLabel == "LeftUpperLeg" or bindingLabel == "LeftLowerLeg" or bindingLabel == "LeftFoot" then
		return "Left Leg"
	end
	if bindingLabel == "RightUpperLeg" or bindingLabel == "RightLowerLeg" or bindingLabel == "RightFoot" then
		return "Right Leg"
	end

	return bindingLabel
end

local function normalizeCloneClothingRig(cloneModel, rootAttachments)
	local rigType = getCloneClothingRigType(rootAttachments)
	local seenNames = {}

	for _, attachment in ipairs(rootAttachments or {}) do
		local sourcePart = attachment.sourcePart
		local binding = attachment.binding
		local desiredName = binding and getStandardClothingPartName(binding.label, rigType) or nil
		if sourcePart and desiredName and not seenNames[desiredName] then
			sourcePart.Name = desiredName
			seenNames[desiredName] = true
		end
	end

	cloneModel:SetAttribute("_FullBodySkinClothingRigType", rigType.Name)
	dprint("normalized clothing rig for", cloneModel.Name, "as", rigType.Name)
	return rigType
end

local function ensureCloneClothingRootPart(cloneModel, rootAttachments)
	local existingRoot = cloneModel:FindFirstChild("HumanoidRootPart")
	if existingRoot and existingRoot:IsA("BasePart") then
		return existingRoot
	end

	local anchorPart = nil
	for _, attachment in ipairs(rootAttachments or {}) do
		local label = attachment.binding and attachment.binding.label or nil
		if label == "HumanoidRootPart" or label == "UpperTorso" or label == "LowerTorso" then
			anchorPart = attachment.sourcePart
			break
		end
	end

	if not anchorPart then
		for _, attachment in ipairs(rootAttachments or {}) do
			if attachment.sourcePart then
				anchorPart = attachment.sourcePart
				break
			end
		end
	end

	if not anchorPart then
		return nil
	end

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.Massless = true
	rootPart.CastShadow = false
	rootPart.CFrame = anchorPart.CFrame
	rootPart.Parent = cloneModel

	local weld = Instance.new("WeldConstraint")
	weld.Name = WELD_NAME_PREFIX .. rootPart.Name
	weld.Part0 = rootPart
	weld.Part1 = anchorPart
	weld.Parent = rootPart

	dprint("added synthetic clothing root part for", cloneModel.Name, "using", anchorPart.Name)
	return rootPart
end

local function configureCloneClothingHumanoid(humanoid, rigType)
	if not humanoid then
		return
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid:SetAttribute("IgnoreCombatTargeting", true)
	humanoid.RigType = rigType

	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)
end

local function setShowHelmForState(state, showHelm)
	if not state then
		return false
	end

	state.showHelm = showHelm ~= false
	setOriginalHeadVisible(state, not state.showHelm)
	setSkinGroupVisible(state.headSkinParts, state.skinPartTransparency, state.showHelm)
	dprint("updated helm visibility for", state.player.Name, "showHelm =", tostring(state.showHelm))
	return true
end

local function restoreCharacterVisibility(state)
	if not state then
		return
	end

	for part, transparency in pairs(state.partTransparency) do
		if part and part.Parent then
			part.Transparency = transparency
		end
	end

	for handle, transparency in pairs(state.accessoryVisibility) do
		if handle and handle.Parent then
			handle.Transparency = transparency
		end
	end

	for decal, transparency in pairs(state.decalTransparency) do
		if decal and decal.Parent then
			decal.Transparency = transparency
		end
	end
end

local function ensureCloneClothingHost(cloneModel, rootAttachments)
	local templateClothing = collectTemplateClothing(cloneModel)
	if #templateClothing == 0 then
		return false
	end

	local rigType = normalizeCloneClothingRig(cloneModel, rootAttachments)
	ensureCloneClothingRootPart(cloneModel, rootAttachments)

	for _, clothing in ipairs(templateClothing) do
		if clothing.Parent ~= cloneModel then
			clothing.Parent = cloneModel
		end
	end

	local humanoid = cloneModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		configureCloneClothingHumanoid(humanoid, rigType)
		dprint("normalized clone clothing under model root for", cloneModel.Name)
		return true
	end

	local createdHumanoid = Instance.new("Humanoid")
	createdHumanoid.Name = "SkinClothingHumanoid"
	configureCloneClothingHumanoid(createdHumanoid, rigType)
	createdHumanoid.Parent = cloneModel
	dprint("added clothing host humanoid for", cloneModel.Name, "with", #templateClothing, "clothing items")
	return true
end

local function destroyAppliedModel(character)
	if not character then
		return
	end

	local existing = character:FindFirstChild(APPLIED_MODEL_NAME)
	if existing then
		existing:Destroy()
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(MODEL_TAG_ATTRIBUTE) then
			child:Destroy()
		elseif isSupportedClothing(child) and child:GetAttribute(CLOTHING_TAG_ATTRIBUTE) then
			child:Destroy()
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Motor6D") and string.sub(desc.Name, 1, #MOTOR_NAME_PREFIX) == MOTOR_NAME_PREFIX then
			desc:Destroy()
		end
	end
end

local function cleanupState(player)
	local state = activeStates[player]
	if not state then
		return
	end

	if state.character and state.character.Parent then
		destroyAppliedModel(state.character)
		local humanoid = state.character:FindFirstChildOfClass("Humanoid")
		restoreHumanoidScaleState(humanoid, state.humanoidScaleState)
		restoreCharacterVisibility(state)
	end

	activeStates[player] = nil
	if player:GetAttribute(PLAYER_SKIN_ATTRIBUTE) == state.skinName then
		player:SetAttribute(PLAYER_SKIN_ATTRIBUTE, nil)
	end
	dprint("removed skin state for", player.Name)
end

local function buildRootAttachments(character, cloneModel)
	local usedParts = {}
	local rootAttachments = {}
	local rootTargetsByPart = {}

	for _, binding in ipairs(ROOT_BINDINGS) do
		local targetPart = getCharacterTargetPart(character, binding)
		if targetPart then
			local sourcePart = findSourcePart(cloneModel, usedParts, binding)
			if sourcePart then
				table.insert(rootAttachments, {
					binding = binding,
					targetPart = targetPart,
					sourcePart = sourcePart,
				})
				rootTargetsByPart[sourcePart] = targetPart
				dprint("matched skin root", sourcePart.Name, "->", targetPart.Name)
			else
				dprint("no source part found for binding", binding.label)
			end
		end
	end

	return rootAttachments, rootTargetsByPart
end

local function attachClone(character, cloneModel, rootAttachments)
	cloneModel.Name = APPLIED_MODEL_NAME
	cloneModel.Parent = character

	for _, attachment in ipairs(rootAttachments) do
		local localOffset = attachment.localOffset or attachment.targetPart.CFrame:ToObjectSpace(attachment.sourcePart.CFrame)
		attachment.sourcePart.CFrame = attachment.targetPart.CFrame * CFrame.new(localOffset.Position)

		local weld = Instance.new("WeldConstraint")
		weld.Name = WELD_NAME_PREFIX .. attachment.sourcePart.Name
		weld.Part0 = attachment.targetPart
		weld.Part1 = attachment.sourcePart
		weld.Parent = attachment.sourcePart
		attachment.sourcePart.CanCollide = false
		attachment.sourcePart.Massless = true
		dprint(
			"attached",
			attachment.sourcePart.Name,
			"to",
			attachment.targetPart.Name,
			"offset =",
			formatVector3(localOffset.Position)
		)
	end
end

local function hideReplacementRootParts(rootAttachments, hiddenRootTargets)
	if not hiddenRootTargets then
		return
	end

	for _, attachment in ipairs(rootAttachments) do
		local targetPart = attachment.targetPart
		local sourcePart = attachment.sourcePart
		if targetPart and sourcePart and hiddenRootTargets[targetPart.Name] then
			sourcePart.Transparency = 1
			dprint("hiding replacement root part", sourcePart.Name, "for target", targetPart.Name)
		end
	end
end

local function applySkinToCharacter(player, character, skinName)
	local definition = skinDefinitions[skinName]
	if not definition then
		dwarn("Unknown skin name passed to ApplySkin:", skinName)
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or humanoid.Health <= 0 then
		dwarn("Cannot apply skin; humanoid missing or dead for", player.Name)
		return false
	end

	local template = getSkinTemplate(definition.TemplateName)
	if not template then
		return false
	end

	cleanupState(player)

	local cloneModel = template:Clone()
	local rootAttachments = nil
	local rootTargetsByPart = nil
	rootAttachments, rootTargetsByPart = buildRootAttachments(character, cloneModel)
	if #rootAttachments == 0 then
		dwarn("No matching skin root parts found for", skinName, "on", player.Name)
		cloneModel:Destroy()
		return false
	end

	local humanoidScaleState = {}
	local humanoidScalePlan = computeHumanoidScalePlan(rootAttachments)
	if humanoidScalePlan then
		applyHumanoidScalePlan(humanoid, humanoidScalePlan, humanoidScaleState)
	end

	alignCloneToCharacter(cloneModel, rootAttachments)
	local _, targetByPart, groupedParts = buildNearestRootAssignments(cloneModel, rootAttachments)
	normalizeRootGroupOrientations(rootAttachments, groupedParts)
	pruneCrossLimbJoints(cloneModel, targetByPart)
	local jointAdjacency = buildJointAdjacency(cloneModel)
	local headRootPart = nil
	for _, attachment in ipairs(rootAttachments) do
		if attachment.targetPart.Name == "Head" then
			headRootPart = attachment.sourcePart
			break
		end
	end

	local state = {
		player = player,
		character = character,
		skinName = skinName,
		partTransparency = {},
		accessoryVisibility = {},
		headAccessoryHandles = {},
		decalTransparency = {},
		headSkinParts = collectConnectedGroup(headRootPart, jointAdjacency),
		skinPartTransparency = {},
		humanoidScaleState = humanoidScaleState._captured and humanoidScaleState or nil,
		options = {
			HideAccessories = definition.HideAccessories ~= false,
			DestroyAccessories = definition.DestroyAccessories == true,
		},
	}

	hideBodyParts(character, state)
	ensureCloneClothingHost(cloneModel, rootAttachments)
	attachClone(character, cloneModel, rootAttachments)
	for part in pairs(state.headSkinParts) do
		state.skinPartTransparency[part] = part:GetAttribute("_FullBodyOrigTransparency")
		if state.skinPartTransparency[part] == nil then
			state.skinPartTransparency[part] = part.Transparency
		end
	end
	activeStates[player] = state
	player:SetAttribute(PLAYER_SKIN_ATTRIBUTE, skinName)
	if desiredShowHelmByPlayer[player] ~= nil then
		setShowHelmForState(state, desiredShowHelmByPlayer[player])
	end
	dprint("skin applied successfully:", skinName, "for", player.Name)
	return true
end

local function ensurePlayerBinding(player)
	if playerConnections[player] then
		return
	end

	playerConnections[player] = {
		ancestryChanged = player.AncestryChanged:Connect(function(_, parent)
			if parent then
				return
			end
			cleanupState(player)
			desiredSkins[player] = nil
			local connections = playerConnections[player]
			if not connections then
				return
			end
			for _, connection in pairs(connections) do
				connection:Disconnect()
			end
			playerConnections[player] = nil
		end),
	}
	end

function SkinService.ApplySkin(player, skinName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		error("SkinService.ApplySkin expected a Player")
	end
	if type(skinName) ~= "string" or skinName == "" then
		error("SkinService.ApplySkin expected a non-empty skinName")
	end
	if not skinDefinitions[skinName] then
		error("SkinService.ApplySkin unknown skinName: " .. tostring(skinName))
	end

	ensurePlayerBinding(player)
	desiredSkins[player] = skinName
	player:SetAttribute(PLAYER_SKIN_ATTRIBUTE, skinName)

	local character = player.Character
	if character then
		return applySkinToCharacter(player, character, skinName)
	end

	dprint("queued skin for next spawn", skinName, "for", player.Name)
	return true
end

function SkinService.RemoveSkin(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		error("SkinService.RemoveSkin expected a Player")
	end

	desiredSkins[player] = nil
	cleanupState(player)
	player:SetAttribute(PLAYER_SKIN_ATTRIBUTE, nil)
	return true
end

function SkinService.GetAppliedSkin(player)
	local state = activeStates[player]
	if state then
		return state.skinName
	end
	return desiredSkins[player]
end

function SkinService.SetShowHelm(player, showHelm)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		error("SkinService.SetShowHelm expected a Player")
	end

	desiredShowHelmByPlayer[player] = showHelm ~= false
	return setShowHelmForState(activeStates[player], showHelm)
end

function SkinService.SetSkinDefinition(skinName, definition)
	if type(skinName) ~= "string" or skinName == "" then
		error("SkinService.SetSkinDefinition expected a non-empty skinName")
	end
	if type(definition) ~= "table" then
		error("SkinService.SetSkinDefinition expected a definition table")
	end

	local merged = {}
	for key, value in pairs(DEFAULT_OPTIONS) do
		merged[key] = value
	end
	for key, value in pairs(definition) do
		merged[key] = value
	end
	if type(merged.TemplateName) ~= "string" or merged.TemplateName == "" then
		error("SkinService.SetSkinDefinition requires TemplateName")
	end
	skinDefinitions[skinName] = merged
	return merged
end

for _, player in ipairs(Players:GetPlayers()) do
	ensurePlayerBinding(player)
end

Players.PlayerAdded:Connect(ensurePlayerBinding)
Players.PlayerRemoving:Connect(function(player)
	cleanupState(player)
	desiredSkins[player] = nil
	desiredShowHelmByPlayer[player] = nil
	local connections = playerConnections[player]
	if not connections then
		return
	end
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	playerConnections[player] = nil
end)

return SkinService