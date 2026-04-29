--------------------------------------------------------------------------------
-- KillCam.client.lua
--   Death spectate camera + right-side kill card.
--
--   Server (KillTracker) fires `Remotes.DeathSpectateEvent` to the victim with
--   a payload describing the killer (Player / NPC / Unknown). This script:
--     • Switches the camera to spectate the killer's character/model.
--     • Shows the KillCardUI on the right side.
--     • Restores Camera.Custom and hides the card on respawn.
--     • Wires the Revenge button to fire `Remotes.RequestRevengeKill` (stub).
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player        = Players.LocalPlayer
local playerGui     = player:WaitForChild("PlayerGui")

local SideUIFolder  = ReplicatedStorage:WaitForChild("SideUI")
local KillCardUI    = require(SideUIFolder:WaitForChild("KillCardUI"))

local remotesFolder       = ReplicatedStorage:WaitForChild("Remotes", 15)
local DeathSpectateEvent  = remotesFolder and remotesFolder:WaitForChild("DeathSpectateEvent", 15)
local RequestRevengeKill  = remotesFolder and remotesFolder:WaitForChild("RequestRevengeKill", 15)

--------------------------------------------------------------------------------
-- Mount the kill card ScreenGui (persists across respawns)
--------------------------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = "KillCardGui"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 50
screen.Parent = playerGui

local card = KillCardUI.Mount(screen)

--------------------------------------------------------------------------------
-- Camera helpers
--------------------------------------------------------------------------------
local function getCamera() return workspace.CurrentCamera end

local function restoreCamera(newChar)
    local cam = getCamera()
    if not cam then return end
    local hum = newChar and newChar:FindFirstChildOfClass("Humanoid")
    cam.CameraType = Enum.CameraType.Custom
    if hum then cam.CameraSubject = hum end
end

local function pickSpectateSubject(model)
    if not model or typeof(model) ~= "Instance" or not model.Parent then return nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then return hum end
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
    return hrp
end

local function spectate(model)
    local cam = getCamera()
    if not cam then return end
    local subject = pickSpectateSubject(model)
    if subject then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = subject
    end
end

local function resolveKillerModel(payload)
    if not payload then return nil end
    if typeof(payload.killerModel) == "Instance" and payload.killerModel.Parent then
        return payload.killerModel
    end
    -- Re-resolve player killer character if instance went stale by the time we read it
    if payload.killerKind == "Player" and payload.killerUserId then
        local p = Players:GetPlayerByUserId(payload.killerUserId)
        if p and p.Character then return p.Character end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Death payload handler
--------------------------------------------------------------------------------
local activeKillerWatch  -- connection that watches killer humanoid Died

local function clearKillerWatch()
    if activeKillerWatch then
        activeKillerWatch:Disconnect()
        activeKillerWatch = nil
    end
end

local function onRevengeClicked(payload)
    if not RequestRevengeKill then return end
    local info = {
        killerKind   = payload.killerKind,
        killerName   = payload.killerName,
        killerUserId = payload.killerUserId,
    }
    -- TODO (future): instead of FireServer here, call
    --   MarketplaceService:PromptProductPurchase(player, REVENGE_PRODUCT_ID)
    -- and let the server's ProcessReceipt path apply the revenge kill.
    pcall(function() RequestRevengeKill:FireServer(info) end)
    print("[KillCam] Revenge requested against", payload.killerName, "(placeholder, no damage yet)")
end

if DeathSpectateEvent then
    DeathSpectateEvent.OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then return end
        clearKillerWatch()

        -- Tiny delay so the death animation reads before camera swap
        task.wait(0.6)

        local killerModel = resolveKillerModel(payload)
        if killerModel then
            spectate(killerModel)

            -- If the killer dies/despawns, gracefully stop spectating but leave the card up.
            local killerHum = killerModel:FindFirstChildOfClass("Humanoid")
            if killerHum then
                activeKillerWatch = killerHum.Died:Connect(function()
                    -- Pause briefly on the body, then drop back to Custom (no subject swap until respawn).
                    task.wait(0.5)
                    local cam = getCamera()
                    if cam then cam.CameraType = Enum.CameraType.Custom end
                end)
            end
        end

        card:Show(payload, onRevengeClicked)
    end)
end

--------------------------------------------------------------------------------
-- Respawn: restore camera + hide card
--------------------------------------------------------------------------------
local function onCharacterAdded(char)
    clearKillerWatch()
    -- Wait for humanoid to exist before restoring subject
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then restoreCamera(char) end
    card:Hide()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    -- Initial join: ensure camera is sane.
    restoreCamera(player.Character)
end
