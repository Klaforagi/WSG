--------------------------------------------------------------------------------
-- WeaponPreviewPublisher.server.lua
--
-- On server startup, clones every weapon template from ServerStorage.Tools
-- into ReplicatedStorage.WeaponPreviews so client scripts can preload the
-- meshes, textures, and other visual assets during the loading screen.
--
-- The clones have all Scripts/LocalScripts removed and parts are anchored +
-- non-collide so they are inert display models only.
--------------------------------------------------------------------------------

local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toolsRoot = ServerStorage:FindFirstChild("Tools")
if not toolsRoot then
    warn("[WeaponPreviewPublisher] ServerStorage.Tools not found — skipping")
    return
end

-- Create or reuse the client-visible folder
local previewFolder = ReplicatedStorage:FindFirstChild("WeaponPreviews")
if not previewFolder then
    previewFolder = Instance.new("Folder")
    previewFolder.Name = "WeaponPreviews"
    previewFolder.Parent = ReplicatedStorage
end

local count = 0

for _, category in ipairs(toolsRoot:GetChildren()) do
    if not category:IsA("Folder") then continue end
    for _, template in ipairs(category:GetChildren()) do
        if not template:IsA("Tool") then continue end

        -- Skip if already published (idempotent on live-edit restarts)
        if previewFolder:FindFirstChild(template.Name) then continue end

        local clone = template:Clone()

        -- Strip all runtime scripts so these are pure visual shells
        for _, desc in ipairs(clone:GetDescendants()) do
            if desc:IsA("Script") or desc:IsA("LocalScript") then
                desc:Destroy()
            end
        end

        -- Make parts inert
        for _, desc in ipairs(clone:GetDescendants()) do
            if desc:IsA("BasePart") then
                pcall(function() desc.Anchored = true end)
                pcall(function() desc.CanCollide = false end)
                pcall(function() desc.CanTouch = false end)
                pcall(function() desc.CanQuery = false end)
            end
        end

        clone.Parent = previewFolder
        count = count + 1
    end
end

print("[WeaponPreviewPublisher] Published", count, "weapon previews to ReplicatedStorage.WeaponPreviews")
