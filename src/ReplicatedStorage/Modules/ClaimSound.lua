--------------------------------------------------------------------------------
-- ClaimSound.lua  –  Local-only "claim" sound helper.
--
-- Plays the sound named "Claimed" from ReplicatedStorage.Sounds for the
-- LOCAL player only (caller must require this from a LocalScript / client
-- module). Quiet warn-once if the sound is missing; never throws.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local ClaimSound = {}

local warned = false
local cachedTemplate -- cached `Sound` instance from ReplicatedStorage.Sounds.Claimed

local function findTemplate()
    if cachedTemplate and cachedTemplate.Parent then
        return cachedTemplate
    end
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return nil end
    local s = soundsFolder:FindFirstChild("Claimed")
    if s and s:IsA("Sound") then
        cachedTemplate = s
        return s
    end
    return nil
end

--------------------------------------------------------------------------------
-- Plays the local "Claimed" sound. Returns true on success, false otherwise.
--------------------------------------------------------------------------------
function ClaimSound.Play()
    local template = findTemplate()
    if not template then
        if not warned then
            warned = true
            warn("[ClaimSound] ReplicatedStorage.Sounds.Claimed not found — claim sound disabled")
        end
        return false
    end
    local clone = template:Clone()
    clone.Parent = SoundService
    clone:Play()
    -- Self-cleanup so we don't leak Sound instances.
    task.delay(math.max(1, (clone.TimeLength or 1) + 0.25), function()
        if clone and clone.Parent then clone:Destroy() end
    end)
    return true
end

return ClaimSound
