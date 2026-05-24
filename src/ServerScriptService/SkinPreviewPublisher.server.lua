local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PREVIEW_FOLDER_NAME = "SkinPreviews"
local SOURCE_FOLDER_NAME = "Skins"
local DEBUG = true

local warned = {}

local function dprint(...)
	if DEBUG then
		print("[CosmeticsPreview]", ...)
	end
end

local function warnOnce(key, ...)
	key = tostring(key or "unknown")
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[CosmeticsPreview]", ...)
end

local skinDefinitionsModule = ReplicatedStorage:WaitForChild("SkinDefinitions", 10)
if not (skinDefinitionsModule and skinDefinitionsModule:IsA("ModuleScript")) then
	warnOnce("missing-defs", "SkinDefinitions missing; skin preview templates were not published")
	return
end

local ok, SkinDefinitions = pcall(require, skinDefinitionsModule)
if not ok or type(SkinDefinitions) ~= "table" then
	warnOnce("bad-defs", "SkinDefinitions failed to load; skin preview templates were not published")
	return
end

local function ensurePreviewFolder()
	local folder = ReplicatedStorage:FindFirstChild(PREVIEW_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = PREVIEW_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function sanitizePreviewModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function publishTemplate(previewFolder, sourceFolder, def)
	if type(def) ~= "table" or def.ApplicationType ~= "ReplacementModel" then
		return false
	end

	local skinId = def.Id
	local templateName = def.PreviewTemplateName or def.TemplateName or skinId
	if type(templateName) ~= "string" or templateName == "" then
		warnOnce("missing-template-name-" .. tostring(skinId), "Missing preview source for skinId:", tostring(skinId))
		return false
	end

	local source = sourceFolder:FindFirstChild(templateName)
	if not (source and source:IsA("Model")) then
		warnOnce("missing-source-" .. tostring(skinId), "Missing preview source for skinId:", tostring(skinId))
		return false
	end

	local cloned = nil
	local cloneOk, cloneErr = pcall(function()
		cloned = source:Clone()
	end)
	if not cloneOk or not cloned then
		warnOnce("clone-failed-" .. tostring(skinId), "Failed to clone preview source for skinId:", tostring(skinId), tostring(cloneErr))
		return false
	end

	cloned.Name = templateName
	cloned:SetAttribute("SkinId", skinId)
	cloned:SetAttribute("PreviewSource", "ServerStorage." .. SOURCE_FOLDER_NAME .. "." .. templateName)
	sanitizePreviewModel(cloned)

	local existing = previewFolder:FindFirstChild(templateName)
	if existing then
		existing:Destroy()
	end
	cloned.Parent = previewFolder
	dprint("Published actual skin preview source:", tostring(skinId), "template=" .. templateName)
	return true
end

local function publishAll(sourceFolder)
	local previewFolder = ensurePreviewFolder()
	local count = 0
	local skinList = type(SkinDefinitions.GetAll) == "function" and SkinDefinitions.GetAll() or SkinDefinitions.Skins or {}
	for _, def in ipairs(skinList) do
		if publishTemplate(previewFolder, sourceFolder, def) then
			count += 1
		end
	end
	dprint("Published", count, "replacement skin preview template(s)")
end

local sourceFolder = ServerStorage:FindFirstChild(SOURCE_FOLDER_NAME) or ServerStorage:WaitForChild(SOURCE_FOLDER_NAME, 10)
if not (sourceFolder and sourceFolder:IsA("Folder")) then
	warnOnce("missing-source-folder", "ServerStorage.Skins missing; replacement skin previews will use fallback rendering")
	ensurePreviewFolder()
	return
end

publishAll(sourceFolder)
sourceFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		task.defer(function()
			publishAll(sourceFolder)
		end)
	end
end)