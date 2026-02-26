--------------------------------------------------------------------------------
-- Hotbar.client.lua
-- 3-slot hotbar: Melee / Ranged / Special (locked behind Game Pass)
-- Builds the entire UI at runtime — no Studio ScreenGui required.
-- Equip is INSTANT — always delegates to server ForceEquipTool.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------------------------
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player      = Players.LocalPlayer
local backpack    = player:WaitForChild("Backpack")
local starterGear = player:WaitForChild("StarterGear", 5)
local camera      = workspace.CurrentCamera or workspace:WaitForChild("Camera")

-- Disable default backpack UI
pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
local requestSpecialUnlock = ReplicatedStorage:WaitForChild("RequestSpecialUnlock")
local specialUnlockGranted = ReplicatedStorage:WaitForChild("SpecialUnlockGranted")
local forceEquipRemote     = ReplicatedStorage:WaitForChild("ForceEquipTool")

--------------------------------------------------------------------------------
-- SLOT DEFINITIONS
--------------------------------------------------------------------------------
local SLOT_DEFS = {
    { index = 1, key = Enum.KeyCode.One,   category = "Melee",   toolName = "ToolSword",   label = "1" },
    { index = 2, key = Enum.KeyCode.Two,   category = "Ranged",  toolName = "ToolBow",     label = "2" },
    { index = 3, key = Enum.KeyCode.Three, category = "Special", toolName = "ToolSpecial", label = "3" },
}

local SLOT_COUNT = #SLOT_DEFS

--------------------------------------------------------------------------------
-- STYLE  (all sizing is screen-relative)
--------------------------------------------------------------------------------
-- Slot height as a fraction of viewport height  (~9% of screen)
local SLOT_SCALE     = 0.10
-- Gap between slots as a fraction of viewport width
local GAP_SCALE      = 0.005
-- Bottom margin as a fraction of viewport height
local MARGIN_SCALE   = 0.012

local COLOR_BG       = Color3.fromRGB(18, 18, 22)
local COLOR_BG_SEL   = Color3.fromRGB(40, 40, 65)
local COLOR_BG_LOCK  = Color3.fromRGB(35, 12, 12)
local COLOR_STROKE   = Color3.fromRGB(55, 55, 55)
local COLOR_STROKE_S = Color3.fromRGB(140, 155, 255)
local COLOR_STROKE_L = Color3.fromRGB(100, 30, 30)
local COLOR_TEXT      = Color3.fromRGB(200, 200, 200)
local COLOR_KEY       = Color3.fromRGB(150, 150, 150)
local COLOR_LOCK_TXT  = Color3.fromRGB(190, 50, 50)

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local specialUnlocked = false
local selectedSlot    = 0
local slotUI          = {}
local slotTools       = {}

--------------------------------------------------------------------------------
-- SCREEN GUI
--------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "Hotbar"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.DisplayOrder    = 10
screenGui.Parent          = playerGui

-- Container — scale-based, anchored bottom-center
-- Width: enough for N square slots + gaps  (each slot = SLOT_SCALE of viewportY,
-- expressed as a fraction of viewportX for width).
local container = Instance.new("Frame")
container.Name                    = "HotbarContainer"
container.BackgroundTransparency  = 1
container.AnchorPoint             = Vector2.new(0, 1)
-- anchor to the bottom-left, above the XP bar
container.Position                = UDim2.new(MARGIN_SCALE, 0, 1 - (MARGIN_SCALE + 0.04), 0)
container.Size                    = UDim2.fromScale(1, SLOT_SCALE) -- full width, height = slot height
container.Parent                  = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment   = Enum.VerticalAlignment.Center
layout.SortOrder           = Enum.SortOrder.LayoutOrder
layout.Padding             = UDim.new(GAP_SCALE, 0)
layout.Parent              = container

--------------------------------------------------------------------------------
-- FORWARD DECLARE
--------------------------------------------------------------------------------
local equipSlot

--------------------------------------------------------------------------------
-- BUILD SLOTS
--------------------------------------------------------------------------------
local function buildSlot(def)
    local idx = def.index

    -- Square button — both axes resolve from container HEIGHT (RelativeYY)
    -- so fromScale(1, 1) = a perfect square matching the container's height
    local btn = Instance.new("TextButton")
    btn.Name                    = "Slot" .. idx
    btn.LayoutOrder             = idx
    btn.SizeConstraint          = Enum.SizeConstraint.RelativeYY
    btn.Size                    = UDim2.fromScale(1, 1)
    btn.BackgroundColor3        = COLOR_BG
    btn.BackgroundTransparency  = 0.15
    btn.AutoButtonColor         = false
    btn.Text                    = ""
    btn.Parent                  = container

    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0.12, 0) -- ~12% of slot size

    local stroke = Instance.new("UIStroke", btn)
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness       = 1.5
    stroke.Color           = COLOR_STROKE

    -- Key number (top-left, scale-based)
    local keyLabel = Instance.new("TextLabel")
    keyLabel.Name                  = "KeyLabel"
    keyLabel.Size                  = UDim2.fromScale(0.3, 0.28)
    keyLabel.Position              = UDim2.fromScale(0.06, 0.02)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Text                  = tostring(idx)
    keyLabel.Font                  = Enum.Font.GothamBold
    keyLabel.TextScaled            = true
    keyLabel.TextColor3            = COLOR_KEY
    keyLabel.TextXAlignment        = Enum.TextXAlignment.Left
    keyLabel.Parent                = btn

    -- Tool thumbnail (centered, scale-based)
    local thumb = Instance.new("ImageLabel")
    thumb.Name                  = "Thumb"
    thumb.AnchorPoint           = Vector2.new(0.5, 0.5)
    thumb.Position              = UDim2.fromScale(0.5, 0.45)
    thumb.Size                  = UDim2.fromScale(0.58, 0.58)
    thumb.BackgroundTransparency = 1
    thumb.ScaleType             = Enum.ScaleType.Fit
    thumb.Image                 = ""
    thumb.Visible               = false
    thumb.Parent                = btn

    -- Tool name (bottom, scale-based)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name                  = "NameLabel"
    nameLabel.AnchorPoint           = Vector2.new(0.5, 1)
    nameLabel.Position              = UDim2.fromScale(0.5, 0.96)
    nameLabel.Size                  = UDim2.fromScale(0.9, 0.22)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text                  = ""
    nameLabel.Font                  = Enum.Font.GothamMedium
    nameLabel.TextScaled            = true
    nameLabel.TextColor3            = COLOR_TEXT
    nameLabel.TextTruncate          = Enum.TextTruncate.AtEnd
    nameLabel.Parent                = btn

    slotUI[idx] = {
        btn       = btn,
        stroke    = stroke,
        keyLabel  = keyLabel,
        nameLabel = nameLabel,
        thumb     = thumb,
    }

    btn.MouseButton1Click:Connect(function()
        equipSlot(idx)
    end)
end

for _, def in ipairs(SLOT_DEFS) do
    buildSlot(def)
end

--------------------------------------------------------------------------------
-- TOOL LOOKUP
--------------------------------------------------------------------------------
local function getToolForSlot(idx)
    local def = SLOT_DEFS[idx]
    if not def then return nil end
    local function scan(cont)
        if not cont then return nil end
        for _, child in ipairs(cont:GetChildren()) do
            if not child:IsA("Tool") then continue end
            local attr = child:GetAttribute("HotbarCategory")
            if type(attr) == "string" and string.lower(attr) == string.lower(def.category) then
                return child
            end
            if child.Name == def.toolName then
                return child
            end
        end
        return nil
    end
    return scan(player.Character) or scan(backpack) or scan(starterGear)
end

local function getToolIcon(tool)
    if not tool then return "" end
    local attr = tool:GetAttribute("Icon")
    if type(attr) == "string" and #attr > 0 then return attr end
    local ok, tex = pcall(function() return tool.TextureId end)
    if ok and type(tex) == "string" and #tex > 0 then return tex end
    return ""
end

--------------------------------------------------------------------------------
-- REFRESH UI
--------------------------------------------------------------------------------
local function refreshSlots()
    for idx = 1, SLOT_COUNT do
        local ui  = slotUI[idx]
        local def = SLOT_DEFS[idx]
        if not ui then continue end

        local tool = getToolForSlot(idx)
        slotTools[idx] = tool

        local isLocked   = (idx == 3 and not specialUnlocked)
        local isEquipped = (tool ~= nil and player.Character ~= nil
                            and tool.Parent == player.Character)

        if isEquipped then
            selectedSlot = idx
        elseif selectedSlot == idx and not isEquipped then
            selectedSlot = 0
        end

        -- thumbnail
        local icon = getToolIcon(tool)
        if #icon > 0 then
            ui.thumb.Image   = icon
            ui.thumb.Visible = true
        else
            ui.thumb.Image   = ""
            ui.thumb.Visible = false
        end

        -- colours / text
        if isLocked then
            ui.btn.BackgroundColor3 = COLOR_BG_LOCK
            ui.stroke.Color         = COLOR_STROKE_L
            ui.nameLabel.Text       = "LOCKED"
            ui.nameLabel.TextColor3 = COLOR_LOCK_TXT
        elseif isEquipped then
            ui.btn.BackgroundColor3 = COLOR_BG_SEL
            ui.stroke.Color         = COLOR_STROKE_S
            ui.nameLabel.TextColor3 = COLOR_TEXT
            ui.nameLabel.Text       = tool and tool.Name or def.label
        else
            ui.btn.BackgroundColor3 = COLOR_BG
            ui.stroke.Color         = COLOR_STROKE
            ui.nameLabel.TextColor3 = COLOR_TEXT
            ui.nameLabel.Text       = tool and tool.Name or ""
        end
    end
end

--------------------------------------------------------------------------------
-- EQUIP / UNEQUIP  — always instant, delegates to server
--------------------------------------------------------------------------------
equipSlot = function(idx)
    local def = SLOT_DEFS[idx]
    if not def then return end

    -- Slot 3 locked
    if idx == 3 and not specialUnlocked then
        requestSpecialUnlock:FireServer()
        local ui = slotUI[3]
        if ui then
            ui.nameLabel.Text = "UNLOCKING..."
            task.delay(1.5, function()
                if not specialUnlocked then ui.nameLabel.Text = "LOCKED" end
            end)
        end
        return
    end

    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- block equipping while dead / ragdolled
    if hum.Health <= 0 or char:GetAttribute("_ragdolled") then return end

    local tool = getToolForSlot(idx)
    if not tool then
        refreshSlots()
        return
    end

    if tool.Parent == char then
        -- Already equipped → unequip
        hum:UnequipTools()
        task.defer(refreshSlots)
        return
    end

    -- If tool is in Backpack, try local equip (fastest path)
    if tool.Parent == backpack then
        hum:UnequipTools()
        pcall(function() hum:EquipTool(tool) end)
        task.defer(refreshSlots)
        return
    end

    -- Tool only in StarterGear or elsewhere → ask server to handle it
    hum:UnequipTools()
    forceEquipRemote:FireServer(def.category, def.toolName)

    -- Optimistic UI highlight
    local ui = slotUI[idx]
    if ui then
        ui.btn.BackgroundColor3 = COLOR_BG_SEL
        ui.stroke.Color         = COLOR_STROKE_S
    end
end

--------------------------------------------------------------------------------
-- EVENTS: KEEP UI IN SYNC
--------------------------------------------------------------------------------
local function connectContainerEvents(cont)
    cont.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then task.defer(refreshSlots) end
    end)
    cont.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then task.defer(refreshSlots) end
    end)
end

connectContainerEvents(backpack)
if starterGear then connectContainerEvents(starterGear) end

local function onCharacter(char)
    connectContainerEvents(char)
    task.defer(refreshSlots)
end

if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(function(char)
    task.wait(0.3)
    onCharacter(char)
end)

--------------------------------------------------------------------------------
-- SPECIAL UNLOCK RESPONSE
--------------------------------------------------------------------------------
specialUnlockGranted.OnClientEvent:Connect(function(unlocked)
    specialUnlocked = (unlocked == true)
    refreshSlots()
end)

--------------------------------------------------------------------------------
-- KEYBOARD INPUT
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    for _, def in ipairs(SLOT_DEFS) do
        if input.KeyCode == def.key then
            equipSlot(def.index)
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- INITIAL REFRESH (wait briefly for server to deliver tools)
--------------------------------------------------------------------------------
task.spawn(function()
    for _ = 1, 30 do
        refreshSlots()
        if slotTools[1] and slotTools[2] then break end
        task.wait(0.2)
    end
end)
